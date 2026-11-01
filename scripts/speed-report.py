#!/usr/bin/env python3
# ABOUTME: Wall-clock speed report over Claude Code session transcripts (~/.claude/projects/*/*.jsonl).
# ABOUTME: Splits each request (prompt to last reply) into model time, per-tool time and background waits,
# ABOUTME: then ranks the buckets by total minutes so the biggest 80/20 target is the top row.
# ABOUTME: --hooks times each PreToolUse hook that fires on Bash. --save writes state/speed/ for trends.
# ABOUTME: Plan and loop: docs/learnings/speed/PLAN.md. Tests: scripts/tests/test-speed-report.py

import argparse
import glob
import json
import os
import statistics
import subprocess
import sys
import time
from datetime import datetime, timedelta, timezone

HOME = os.path.expanduser("~/.claude")
IDLE_CAP_S = 1800  # a background wait longer than 30 min counts as idle, not as waiting


def parse_ts(s):
    """Purpose: turn a transcript timestamp into an aware datetime.
    Usage: parse_ts("2026-11-01T12:00:00.000Z").
    Gotcha: transcripts use a trailing Z, which fromisoformat on 3.10 rejects."""
    return datetime.fromisoformat(s.replace("Z", "+00:00"))


def is_prompt(e):
    """Purpose: True when a transcript entry is a prompt the user typed.
    Usage: is_prompt(entry).
    Gotcha: task notices, hook text (isMeta) and local-command output are user-typed entries too.
    Only entrypoint "cli" counts: "sdk-cli" is a headless claude -p job, and no entrypoint is a
    subagent warm-up or a compaction summary. Nobody sits and waits on those."""
    if e.get("type") != "user" or e.get("isMeta") or e.get("entrypoint") != "cli":
        return False
    c = (e.get("message") or {}).get("content")
    if isinstance(c, str):
        return not c.lstrip().startswith(("<task-notification", "<local-command"))
    if isinstance(c, list):
        kinds = {b.get("type") for b in c if isinstance(b, dict)}
        return "text" in kinds and "tool_result" not in kinds
    return False


def union_seconds(intervals):
    """Purpose: total seconds covered by possibly overlapping (start, end) intervals.
    Usage: union_seconds([(a, b), (c, d)]).
    Gotcha: parallel tool calls overlap, so a plain sum would count time twice."""
    total, cur_s, cur_e = 0.0, None, None
    for s, e in sorted(intervals):
        if cur_e is None or s > cur_e:
            if cur_e is not None:
                total += (cur_e - cur_s).total_seconds()
            cur_s, cur_e = s, e
        else:
            cur_e = max(cur_e, e)
    if cur_e is not None:
        total += (cur_e - cur_s).total_seconds()
    return total


def command_key(cmd):
    """Purpose: group a Bash command line by what it runs, so repeats add up.
    Usage: command_key("cd ~/.claude; ls; bash scripts/run.sh -v") -> "run.sh"; "git commit -m x" -> "git commit".
    Gotcha: it names the first segment that is not a helper (cd, ls, echo, export). A command that
    is only helpers is named by its first word."""
    import re
    cmd = re.sub(r"<<-?\s*['\"]?(\w+)['\"]?.*?\n.*?^\1$", "", cmd or "", flags=re.S | re.M)
    segs = [x.strip() for x in re.split(r"&&|\|\||[;|\n]", cmd) if x.strip() and not x.strip().startswith("#")]
    segs = [re.sub(r"^(\w+=\S*\s+)+", "", x) for x in segs]
    helpers = ("cd", "ls", "echo", "export", "set", "printf", "true", "wc", "head", "tail", "sort", "cat")
    real = [x for x in segs if x.split()[0] not in helpers]
    toks = (real or segs or ["?"])[0].split()
    if toks[0] in ("bash", "sh", "python3", "python", "node", "uv", "rtk") and len(toks) > 1:
        rest = [t for t in toks[1:] if not t.startswith("-") and t not in ("run", "proxy")]
        return os.path.basename(rest[0]) if rest else toks[0]
    if toks[0] in ("git", "gh", "npm", "claude") and len(toks) > 1:
        return f"{toks[0]} {toks[1]}"
    return os.path.basename(toks[0])


def parse_requests(path):
    """Purpose: split one session transcript into requests with timed buckets.
    Usage: parse_requests("/path/session.jsonl") -> [{start, wall, buckets, bash_calls, tool_calls, session}].
    Gotchas: AskUserQuestion time is the user's, so it leaves the wall. A gap after my turn ends
    is a background wait (agents, workflows), capped at IDLE_CAP_S. Parallel tool time is scaled to its union."""
    reqs, cur, pending = [], None, {}
    prev_ts, prev_ended = None, False

    def close():
        if not cur or cur["last"] is None:
            return
        wall = (cur["last"] - cur["start"]).total_seconds() - cur["ask"] - cur["idle"]
        raw = {k: v for k, v in cur["tools"].items()}
        raw_sum = sum(raw.values())
        tool_union = union_seconds(cur["intervals"])
        scale = tool_union / raw_sum if raw_sum else 0
        buckets = {f"tool:{k}": v * scale for k, v in raw.items()}
        if cur["bg"]:
            buckets["wait:background"] = cur["bg"]
        buckets["model"] = max(0.0, wall - tool_union - cur["bg"])
        reqs.append({"start": cur["start"], "wall": max(wall, 0.0), "buckets": buckets,
                     "bash_calls": cur["bash"], "bash_cmds": cur["cmds"], "tool_calls": cur["calls"], "session": os.path.basename(path)[:8]})

    with open(path, errors="replace") as f:
        for line in f:
            try:
                e = json.loads(line)
            except ValueError:
                continue
            if e.get("type") not in ("user", "assistant") or not e.get("timestamp"):
                continue
            t = parse_ts(e["timestamp"])
            if is_prompt(e):
                close()
                cur = {"start": t, "last": None, "ask": 0.0, "idle": 0.0, "bg": 0.0, "tools": {},
                       "intervals": [], "bash": [], "cmds": [], "calls": 0}
                pending, prev_ts, prev_ended = {}, t, False
                continue
            if cur is None:
                continue
            content = (e.get("message") or {}).get("content")
            blocks = content if isinstance(content, list) else []
            if e["type"] == "user" and prev_ended and prev_ts is not None:
                gap = (t - prev_ts).total_seconds()
                cur["bg"] += min(gap, IDLE_CAP_S)
                cur["idle"] += max(0.0, gap - IDLE_CAP_S)
            if e["type"] == "assistant":
                cur["last"] = t
                uses = [b for b in blocks if b.get("type") == "tool_use"]
                for b in uses:
                    pending[b.get("id")] = (t, b.get("name", "?"), (b.get("input") or {}).get("command", ""))
                    cur["calls"] += 1
                prev_ended = not uses and not pending
            else:
                for b in blocks:
                    if b.get("type") == "tool_result" and b.get("tool_use_id") in pending:
                        s, name, cmd = pending.pop(b["tool_use_id"])
                        d = (t - s).total_seconds()
                        if name == "AskUserQuestion":
                            cur["ask"] += d
                        else:
                            cur["tools"][name] = cur["tools"].get(name, 0.0) + d
                            cur["intervals"].append((s, t))
                            if name == "Bash":
                                cur["bash"].append(d)
                                cur["cmds"].append((command_key(cmd), d, " ".join((cmd or "").split())[:70]))
                prev_ended = False
            prev_ts = t
    close()
    return reqs


def summarize(reqs):
    """Purpose: roll requests up into ranked buckets plus headline numbers.
    Usage: summarize(parse_requests(p)) -> dict with buckets sorted by total seconds.
    Gotcha: bash_overhead_s uses the 10th-percentile Bash round trip as the fixed cost of one call."""
    wall = sum(r["wall"] for r in reqs)
    totals = {}
    for r in reqs:
        for k, v in r["buckets"].items():
            totals[k] = totals.get(k, 0.0) + v
    buckets = [{"name": k, "seconds": v, "pct": 100 * v / wall if wall else 0}
               for k, v in sorted(totals.items(), key=lambda x: -x[1])]
    bash = sorted(d for r in reqs for d in r["bash_calls"])
    p10 = bash[int(len(bash) * 0.1)] if bash else 0.0
    walls = sorted(r["wall"] for r in reqs)
    by_cmd = {}
    for r in reqs:
        for k, d, *_ in r.get("bash_cmds", []):
            n, tot = by_cmd.get(k, (0, 0.0))
            by_cmd[k] = (n + 1, tot + d)
    top_bash = sorted(((k, n, tot) for k, (n, tot) in by_cmd.items()), key=lambda x: -x[2])[:8]
    long_bash = sorted(((d, c[2]) for r in reqs for c in r.get("bash_cmds", []) for d in [c[1]] if d > 60),
                       reverse=True)[:8]
    return {"top_bash": top_bash, "long_bash": long_bash, "requests": len(reqs), "wall_s": wall, "buckets": buckets,
            "median_req_s": statistics.median(walls) if walls else 0,
            "p90_req_s": walls[int(len(walls) * 0.9)] if walls else 0,
            "median_tool_calls": statistics.median([r.get("tool_calls", 0) for r in reqs]) if reqs else 0,
            "bash_calls": len(bash), "bash_p10_s": p10, "bash_overhead_s": p10 * len(bash),
            "slowest": sorted(reqs, key=lambda r: -r["wall"])[:5]}


def render(s, days, now, prev=None):
    """Purpose: format a summary as a short markdown report with narrow tables.
    Usage: print(render(summary, 7, now, previous_history_line)).
    Gotcha: keep tables at 4 columns or fewer so they wrap in a terminal."""
    m = lambda sec: f"{sec / 60:.1f}"
    out = [f"# Speed report: last {days} days to {now:%Y-%m-%d}", "",
           f"Requests: {s['requests']} · wall total: {s['wall_s'] / 3600:.1f} h · "
           f"median request: {m(s['median_req_s'])} min · p90: {m(s['p90_req_s'])} min · "
           f"median tool calls per request: {s['median_tool_calls']:.0f}", "",
           "| Bucket | Minutes | % of wall |", "|---|---|---|"]
    out += [f"| {b['name']} | {m(b['seconds'])} | {b['pct']:.0f}% |" for b in s["buckets"][:8]]
    pct = 100 * s["bash_overhead_s"] / s["wall_s"] if s["wall_s"] else 0
    out += ["", f"Bash fixed cost: p10 round trip {s['bash_p10_s']:.1f} s × {s['bash_calls']} calls = "
                f"{m(s['bash_overhead_s'])} min ({pct:.0f}% of wall).", "",
            "Top Bash commands by total time:", "", "| Command | Calls | Minutes |", "|---|---|---|"]
    out += [f"| {k} | {n} | {m(tot)} |" for k, n, tot in s.get("top_bash", [])]
    out += ["", "Bash calls over 60 s (a trivial command here usually waited on a permission prompt):", "",
            "| Seconds | Command |", "|---|---|"]
    out += [f"| {d:.0f} | `{c.replace('|', '/')}` |" for d, c in s.get("long_bash", [])]
    out += ["",
            "Slowest requests:", "", "| Session | Start (UTC) | Minutes | Top bucket |", "|---|---|---|---|"]
    for r in s["slowest"]:
        top = max(r["buckets"].items(), key=lambda x: x[1])[0] if r["buckets"] else "-"
        out.append(f"| {r['session']} | {r['start']:%m-%d %H:%M} | {m(r['wall'])} | {top} |")
    if prev:
        out += ["", f"Trend vs {prev['date']}: median request {prev['median_req_min']:.1f} → "
                    f"{s['median_req_s'] / 60:.1f} min; Bash p10 {prev['bash_p10_s']:.1f} → {s['bash_p10_s']:.1f} s."]
    return "\n".join(out)


def bench_hooks(settings_path, runs):
    """Purpose: time every PreToolUse hook whose matcher covers Bash, on a no-op `pwd` call.
    Usage: bench_hooks("~/.claude/settings.json", 3) -> [(command, median_ms)] slowest first.
    Gotcha: the hooks really run, so any logging they do happens. The payload uses session_id speed-bench."""
    import re
    with open(os.path.expanduser(settings_path)) as f:
        cfg = json.load(f)
    payload = json.dumps({"session_id": "speed-bench", "hook_event_name": "PreToolUse", "cwd": os.getcwd(),
                          "tool_name": "Bash", "tool_input": {"command": "pwd"}})
    rows = []
    for group in cfg.get("hooks", {}).get("PreToolUse", []):
        matcher = group.get("matcher") or "*"
        if matcher != "*" and not re.fullmatch(matcher, "Bash"):
            continue
        for h in group.get("hooks", []):
            cmd = h.get("command")
            if not cmd:
                continue
            times = []
            for _ in range(runs):
                t0 = time.perf_counter()
                try:
                    subprocess.run(cmd, shell=True, input=payload, capture_output=True, text=True, timeout=15)
                except subprocess.TimeoutExpired:
                    pass
                times.append((time.perf_counter() - t0) * 1000)
            rows.append((cmd, statistics.median(times)))
    return sorted(rows, key=lambda r: -r[1])


def main():
    ap = argparse.ArgumentParser(description="Wall-clock speed report over Claude Code transcripts.")
    ap.add_argument("--days", type=int, default=7)
    ap.add_argument("--projects", default=os.path.join(HOME, "projects"))
    ap.add_argument("--state", default=os.path.join(HOME, "state", "speed"))
    ap.add_argument("--save", action="store_true", help="write latest.md and append history.jsonl")
    ap.add_argument("--hooks", action="store_true", help="benchmark PreToolUse hooks on a Bash call")
    ap.add_argument("--settings", default=os.path.join(HOME, "settings.json"))
    ap.add_argument("--runs", type=int, default=3)
    ap.add_argument("--now", help="ISO time to treat as now (tests)")
    a = ap.parse_args()

    if a.hooks:
        rows = bench_hooks(a.settings, a.runs)
        print("| Hook | ms |\n|---|---|")
        for cmd, ms in rows:
            print(f"| {os.path.basename(cmd.split()[0]) if cmd.split() else cmd} | {ms:.0f} |")
        if rows:
            print(f"\n{len(rows)} hooks. Sum {sum(r[1] for r in rows):.0f} ms; slowest {rows[0][1]:.0f} ms.")
        return 0

    now = datetime.fromisoformat(a.now) if a.now else datetime.now(timezone.utc)
    since = now - timedelta(days=a.days)
    reqs = []
    for p in glob.glob(os.path.join(a.projects, "*", "*.jsonl")):
        if not a.now and datetime.fromtimestamp(os.path.getmtime(p), timezone.utc) < since:
            continue
        reqs += [r for r in parse_requests(p) if since <= r["start"] <= now]
    s = summarize(reqs)

    prev = None
    hist = os.path.join(a.state, "history.jsonl")
    if os.path.exists(hist):
        with open(hist) as f:
            lines = [l for l in f if l.strip()]
        prev = json.loads(lines[-1]) if lines else None
    report = render(s, a.days, now, prev)
    print(report)

    if a.save:
        os.makedirs(a.state, exist_ok=True)
        with open(os.path.join(a.state, "latest.md"), "w") as f:
            f.write(report + "\n")
        per_req = {b["name"]: round(b["seconds"] / s["requests"], 1) for b in s["buckets"][:8]} if s["requests"] else {}
        line = {"date": f"{now:%Y-%m-%d}", "days": a.days, "requests": s["requests"],
                "wall_h": round(s["wall_s"] / 3600, 2), "median_req_min": round(s["median_req_s"] / 60, 2),
                "bash_p10_s": round(s["bash_p10_s"], 2), "top": s["buckets"][0]["name"] if s["buckets"] else None,
                "top_pct": round(s["buckets"][0]["pct"]) if s["buckets"] else 0, "sec_per_request": per_req}
        with open(hist, "a") as f:
            f.write(json.dumps(line) + "\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
