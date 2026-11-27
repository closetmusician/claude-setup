#!/usr/bin/env python3
# ABOUTME: Live-trial report. One row per compaction event in the transcripts, built-in or fast-compact (/fc).
# ABOUTME: For each event it measures the next 40 tool calls: repeat work, saved-file reads, corrections, turns, context size.
# ABOUTME: fc is counted only when a ledger line in ~/.claude/fast-compact/ledger-*.jsonl proves it. Read only; standard library only.
# ABOUTME: Run: python3 report.py [--since YYYY-MM-DD] [--root DIR] [--ledger-dir DIR] [--judge]. Writes out/report-events.jsonl and out/report-table.md.
# ABOUTME: Spec: ~/.claude/docs/plans/harness/compaction-eval/spec.md (the "Spec fixes from the Codex check" section wins).
import argparse
import glob
import json
import os
import statistics
import subprocess
import sys
from datetime import datetime, timezone

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "out")
WINDOW_CALLS = 40
LEDGER_SLACK_SECONDS = 120
JUDGE_CAP = 50
FC_MARKER = "[fast-compact]"
FC_DIR_PART = "/.claude/fast-compact/"
# Short phrases that suggest the person had to repeat or correct something. One place to edit.
CORRECTION_PHRASES = ["i already told you", "as i said", "you forgot", "we already", "again,", "no, ", "that's wrong"]
HOST_PREFIXES = ["<command-name>", "<command-message>", "<local-command-", "<task-notification>", "<system-reminder>", "Caveat: The messages below were generated"]


def parse_time(text):
    """Purpose: turn an ISO timestamp (with Z) into a datetime, or None.
    Usage: parse_time(rec.get("timestamp")).
    Gotchas: bad or missing input gives None, never an error."""
    if not text:
        return None
    try:
        return datetime.fromisoformat(text.replace("Z", "+00:00"))
    except ValueError:
        return None


def read_records(path):
    """Purpose: read every JSON line of one transcript.
    Usage: read_records(path) returns the records in file order.
    Gotchas: a torn last line (session still writing) is skipped."""
    out = []
    with open(path, encoding="utf-8") as fh:
        for line in fh:
            line = line.strip()
            if not line:
                continue
            try:
                out.append(json.loads(line))
            except json.JSONDecodeError:
                pass
    return out


def blocks_of(rec):
    """Purpose: the content blocks of a message record as a list.
    Usage: blocks_of(rec). A plain string becomes one text block.
    Gotchas: records without a message give an empty list."""
    content = (rec.get("message") or {}).get("content")
    if isinstance(content, str):
        return [{"type": "text", "text": content}]
    return content if isinstance(content, list) else []


def flat_strings(value):
    """Purpose: join every string inside a tool input into one text.
    Usage: flat_strings(input_dict).
    Gotchas: numbers are ignored; only strings matter for path and command checks."""
    if isinstance(value, str):
        return value
    if isinstance(value, list):
        return "\n".join(flat_strings(v) for v in value)
    if isinstance(value, dict):
        return "\n".join(flat_strings(v) for v in value.values())
    return ""


def call_key(block):
    """Purpose: the identity of a Read or Bash call, used to spot repeat work.
    Usage: call_key(tool_use_block) returns "R:<path>", "B:<command>" or None.
    Gotchas: other tools are never counted as repeats."""
    inp = block.get("input") or {}
    if block.get("name") == "Read" and isinstance(inp.get("file_path"), str):
        return "R:" + inp["file_path"]
    if block.get("name") == "Bash" and isinstance(inp.get("command"), str):
        return "B:" + inp["command"]
    return None


def real_user_text(rec):
    """Purpose: the words a person typed in a user record, or '' for tool results, host notices and summaries.
    Usage: real_user_text(rec).
    Gotchas: command echoes and system reminders count as host text and are dropped."""
    if rec.get("type") != "user" or rec.get("isSidechain") or rec.get("isMeta") or rec.get("isCompactSummary"):
        return ""
    texts = [b.get("text", "") for b in blocks_of(rec) if b.get("type") == "text"]
    text = "\n".join(t for t in texts if t)
    if any(text.lstrip().startswith(p) for p in HOST_PREFIXES):
        return ""
    return text


def load_ledger(ledger_dir):
    """Purpose: read every fast-compact ledger line (one JSON object per line, one file per month).
    Usage: load_ledger(dir) returns a list of dicts with a parsed "_at" time.
    Gotchas: a missing folder (fc not installed) gives an empty list."""
    lines = []
    for path in sorted(glob.glob(os.path.join(ledger_dir, "ledger-*.jsonl"))):
        with open(path, encoding="utf-8") as fh:
            for raw in fh:
                try:
                    row = json.loads(raw)
                except json.JSONDecodeError:
                    continue
                row["_at"] = parse_time(row.get("at"))
                if row["_at"] and row.get("session"):
                    lines.append(row)
    return lines


def marker_near(recs, idx):
    """Purpose: whether a '[fast-compact]' command echo sits within 40 records of a boundary.
    Usage: marker_near(recs, boundary_index).
    Gotchas: this alone is NOT proof of fc; without a ledger line the event is called unknown."""
    for rec in recs[max(0, idx - 40): idx + 40]:
        if rec.get("type") == "user" and ("<command-args>" + FC_MARKER) in json.dumps(rec.get("message", {})):
            return True
    return False


def bucket_of(tokens):
    """Purpose: the starting-context size group of an event.
    Usage: bucket_of(preTokens). Under 200k, 200k-500k, over 500k tokens.
    Gotchas: None gives 'unknown'."""
    if tokens is None:
        return "unknown"
    return "<200k" if tokens < 200_000 else "200k-500k" if tokens <= 500_000 else ">500k"


def window_stats(recs, start, end, before_keys, skip_uuids=frozenset()):
    """Purpose: measure the window after one compaction: up to 40 tool calls, or until the next compaction.
    Usage: window_stats(recs, start_index, end_index, set_of_before_call_keys, preserved_uuids). Stops at exactly 40 calls, even inside one record.
    Gotchas: replies are counted once per message.id; the last line of an id carries its final usage."""
    calls = repeats = saved = corrections = 0
    replies = {}
    for rec in recs[start + 1: end]:
        if rec.get("isSidechain") or rec.get("isCompactSummary") or rec.get("uuid") in skip_uuids:
            continue
        if rec.get("type") == "assistant":
            msg_id = (rec.get("message") or {}).get("id") or rec.get("uuid")
            usage = (rec.get("message") or {}).get("usage") or {}
            ctx = (usage.get("input_tokens") or 0) + (usage.get("cache_read_input_tokens") or 0) + (usage.get("cache_creation_input_tokens") or 0)
            if usage:
                replies[msg_id] = ctx
            for b in blocks_of(rec):
                if b.get("type") != "tool_use":
                    continue
                if calls >= WINDOW_CALLS:
                    break
                calls += 1
                key = call_key(b)
                if key and key in before_keys:
                    repeats += 1
                if FC_DIR_PART in flat_strings(b.get("input")):
                    saved += 1
            if calls >= WINDOW_CALLS:
                break
        else:
            lowered = real_user_text(rec).lower()
            if lowered and any(p in lowered for p in CORRECTION_PHRASES):
                corrections += 1
    ctxs = list(replies.values())
    return {
        "window_calls": calls,
        "repeat_calls": repeats,
        "repeat_share": (repeats / calls) if calls else None,
        "saved_file_reads": saved,
        "corrections": corrections,
        "window_replies": len(ctxs),
        "avg_context_tokens": (sum(ctxs) / len(ctxs)) if ctxs else None,
        "first_reply_context_tokens": ctxs[0] if ctxs else None,
    }


def events_of(path, project, ledger, used_ledger):
    """Purpose: build one row per compaction boundary in a transcript file.
    Usage: events_of(path, project, ledger_lines, set_of_used_ledger_ids). Marks fc only on a ledger match.
    Gotchas: each ledger line matches at most one boundary (the closest in time, within 120 s)."""
    session = os.path.basename(path)[: -len(".jsonl")]
    recs = read_records(path)
    bounds = [i for i, r in enumerate(recs) if r.get("type") == "system" and r.get("subtype") == "compact_boundary"]
    rows = []
    mine = [(n, row) for n, row in enumerate(ledger) if row["session"] == session]
    for k, bi in enumerate(bounds):
        b = recs[bi]
        cm = b.get("compactMetadata") or {}
        t = parse_time(b.get("timestamp"))
        match = None
        if t:
            best = None
            for n, row in mine:
                if (session, n) in used_ledger:
                    continue
                delta = abs((row["_at"] - t).total_seconds())
                if delta <= LEDGER_SLACK_SECONDS and (best is None or delta < best[0]):
                    best = (delta, n, row)
            if best:
                match = best[2]
                used_ledger.add((session, best[1]))
        has_summary = any(recs[j].get("isCompactSummary") for j in range(bi + 1, min(len(recs), bi + 25)))
        if match:
            kind = "fc"
        elif marker_near(recs, bi) or not has_summary:
            kind = "unknown"
        else:
            kind = "built-in"
        prev = bounds[k - 1] if k > 0 else -1
        nxt = bounds[k + 1] if k + 1 < len(bounds) else len(recs)
        # Simple version: every Read/Bash call earlier in the same session file (before the boundary), plus calls in preserved messages.
        # It is wider than the exact context chain, so repeat counts can be a little high.
        preserved = set((cm.get("preservedMessages") or {}).get("uuids") or [])
        before_keys = set()
        for j, rec in enumerate(recs):
            if rec.get("type") == "assistant" and not rec.get("isSidechain") and (j < bi or rec.get("uuid") in preserved):
                for blk in blocks_of(rec):
                    if blk.get("type") == "tool_use" and call_key(blk):
                        before_keys.add(call_key(blk))
        # The window starts after the summary and after every preserved message.
        start = bi
        for j, rec in enumerate(recs):
            if rec.get("uuid") in preserved or (rec.get("isCompactSummary") and bi < j < bi + 25):
                start = max(start, j)
        stats = window_stats(recs, start, nxt, before_keys, preserved)
        replies_until_next = None
        ended = k + 1 >= len(bounds)
        if not ended:
            ids = set()
            for rec in recs[bi + 1: nxt]:
                if rec.get("type") == "assistant" and not rec.get("isSidechain"):
                    ids.add((rec.get("message") or {}).get("id") or rec.get("uuid"))
            replies_until_next = len(ids)
        pre = cm.get("preTokens")
        rows.append({
            "kind": kind,
            "session": session,
            "project": project,
            "index": k,
            "time": b.get("timestamp"),
            "trigger": (match.get("trigger") if match else cm.get("trigger")),
            "bucket": bucket_of(pre),
            "duration_ms": None if match else cm.get("durationMs"),
            "before_tokens": pre,
            "after_tokens": cm.get("postTokens"),
            "before_chars": match.get("before") if match else None,
            "after_chars": match.get("after") if match else None,
            "ledger_outputs_cut": match.get("outputs") if match else None,
            "turns_until_next": replies_until_next,
            "ended": ended,
            **stats,
            "_window": (start, nxt),
            "_preserved": preserved,
        })
    return rows, recs


def judge_prompt(recs, window, skip_uuids=frozenset()):
    """Purpose: the question sent to Haiku for one event: the window's assistant words and tool-call list.
    Usage: judge_prompt(recs, (start, end)).
    Gotchas: cut to 30000 characters; the question asks for one word, yes or no."""
    start, end = window
    texts, calls = [], []
    for rec in recs[start + 1: end]:
        if len(calls) >= WINDOW_CALLS:
            break
        if rec.get("type") != "assistant" or rec.get("isSidechain") or rec.get("uuid") in skip_uuids:
            continue
        for b in blocks_of(rec):
            if len(calls) >= WINDOW_CALLS:
                break
            if b.get("type") == "text" and b.get("text"):
                texts.append(b["text"])
            elif b.get("type") == "tool_use":
                calls.append(f"{b.get('name')}: {flat_strings(b.get('input'))[:200]}")
    body = "ASSISTANT TEXT:\n" + "\n---\n".join(texts) + "\n\nTOOL CALLS:\n" + "\n".join(calls)
    question = "Does the assistant claim work that no tool call in this list did? Answer with one word: yes or no."
    return body[:30_000] + "\n\n" + question


def run_judge(prompt):
    """Purpose: ask Haiku the yes/no question through the claude CLI.
    Usage: run_judge(prompt) returns 'yes', 'no' or 'error'. This costs money; only --judge calls it.
    Gotchas: capped at 50 events by the caller; a timeout or odd answer gives 'error'."""
    try:
        out = subprocess.run(["claude", "-p", "--model", "haiku"], input=prompt, capture_output=True, text=True, timeout=180)
    except (OSError, subprocess.TimeoutExpired):
        return "error"
    word = out.stdout.strip().lower()
    return "yes" if word.startswith("yes") else "no" if word.startswith("no") else "error"


def med(values):
    """Purpose: median of the numbers in a list, or None when there are none.
    Usage: med([..]). None values are skipped.
    Gotchas: a median only describes the middle; it does not prove one method is better."""
    xs = [v for v in values if isinstance(v, (int, float))]
    return statistics.median(xs) if xs else None


def fmt(v, digits=0, scale=1.0):
    """Purpose: format a number for the table, 'n/a' when missing.
    Usage: fmt(value, digits, scale) divides by scale first.
    Gotchas: thousands separators are added; None is never an error."""
    return "n/a" if v is None else f"{v / scale:,.{digits}f}"


def table(rows):
    """Purpose: markdown table of medians grouped by kind, then trigger, then starting context size.
    Usage: table(rows).
    Gotchas: 'ended' counts events with no later compaction in the file; they are not given a number."""
    order = {"built-in": 0, "fc": 1, "unknown": 2}
    groups = {}
    for r in rows:
        groups.setdefault((r["kind"], r["trigger"] or "n/a", r["bucket"]), []).append(r)
    head = ["Kind", "Trigger", "Start size", "Events", "Duration s (med)", "Before tok (med)", "After tok (med)",
            "Repeat share (med)", "Saved-file reads (total)", "Corrections (total)", "Replies to next compaction (med)", "Ended", "Avg context tok (med)"]
    out = ["| " + " | ".join(head) + " |", "|" + "---|" * len(head)]
    for key in sorted(groups, key=lambda k: (order.get(k[0], 9), k[1], k[2])):
        g = groups[key]
        share = med([r["repeat_share"] for r in g])
        out.append("| " + " | ".join([
            key[0], key[1], key[2], str(len(g)),
            fmt(med([r["duration_ms"] for r in g]), 1, 1000.0),
            fmt(med([r["before_tokens"] for r in g])), fmt(med([r["after_tokens"] for r in g])),
            "n/a" if share is None else f"{100 * share:.1f}%",
            str(sum(r["saved_file_reads"] for r in g)), str(sum(r["corrections"] for r in g)),
            fmt(med([r["turns_until_next"] for r in g])), f"{sum(1 for r in g if r['ended'])} of {len(g)}",
            fmt(med([r["avg_context_tokens"] for r in g])),
        ]) + " |")
    return "\n".join(out)


def main():
    """Purpose: scan the transcripts, build the rows, write out/report-events.jsonl and out/report-table.md.
    Usage: python3 report.py [--since DATE] [--root DIR] [--ledger-dir DIR] [--judge].
    Gotchas: --judge costs money (50 events max); without it nothing leaves this machine."""
    ap = argparse.ArgumentParser()
    ap.add_argument("--root", default=os.path.expanduser("~/.claude/projects"))
    ap.add_argument("--ledger-dir", default=os.path.expanduser("~/.claude/fast-compact"))
    ap.add_argument("--since", default=None, help="YYYY-MM-DD; only events on or after this day")
    ap.add_argument("--judge", action="store_true", help="ask Haiku one yes/no question per event (max 50). Costs money.")
    args = ap.parse_args()
    since = datetime.fromisoformat(args.since).replace(tzinfo=timezone.utc) if args.since else None
    ledger = load_ledger(args.ledger_dir)
    used = set()
    rows, judged = [], 0
    for path in sorted(glob.glob(os.path.join(args.root, "*", "*.jsonl"))):
        if os.path.basename(path).startswith("agent-"):
            continue
        with open(path, encoding="utf-8") as fh:
            if '"compact_boundary"' not in fh.read():
                continue
        found, recs = events_of(path, os.path.basename(os.path.dirname(path)), ledger, used)
        for r in found:
            t = parse_time(r["time"])
            if since and (not t or t < since):
                continue
            if args.judge and judged < JUDGE_CAP:
                r["judge"] = run_judge(judge_prompt(recs, r["_window"], r["_preserved"]))
                judged += 1
            rows.append(r)
    os.makedirs(OUT, exist_ok=True)
    with open(os.path.join(OUT, "report-events.jsonl"), "w", encoding="utf-8") as fh:
        for r in rows:
            fh.write(json.dumps({k: v for k, v in r.items() if not k.startswith("_")}) + "\n")
    kinds = {}
    for r in rows:
        kinds[r["kind"]] = kinds.get(r["kind"], 0) + 1
    unmatched = len(ledger) - len(used)
    text = [
        "# Live compaction report",
        "",
        f"Events: {len(rows)} ({', '.join(f'{k} {v}' for k, v in sorted(kinds.items())) or 'none'}). Ledger lines read: {len(ledger)}; matched to an event: {len(used)}; unmatched: {unmatched}.",
        "fc rows are counted only when a ledger line matches the boundary (same session, within 120 s). A '[fast-compact]' marker alone is called unknown.",
        "Medians describe the middle; they do not prove which method is better. The sample is small and the work differs between events.",
        "",
        table(rows),
        "",
    ]
    with open(os.path.join(OUT, "report-table.md"), "w", encoding="utf-8") as fh:
        fh.write("\n".join(text))
    print("\n".join(text))
    print(f"wrote {os.path.join(OUT, 'report-events.jsonl')} and {os.path.join(OUT, 'report-table.md')}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
