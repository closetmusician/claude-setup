# ABOUTME: SQL reviewer for the sql-lint-guard.sh hook. Decides if a Bash command runs a database client or program.
# ABOUTME: If so, one Sonnet call (Bifrost, mTLS, standard library only) says allow or rewrite. Slow SQL goes back to the writer.
# ABOUTME: Reads the hook JSON on stdin. Prints a deny reason and exits 3 for "rewrite". Exits 0 for everything else (fail open).
# ABOUTME: Never reads ANTHROPIC_API_KEY. Part A (the watchdog) is the real time cap. Spec: sql-lint-guard/spec.md Part B.
# ABOUTME: One 12 s alarm starts before stdin is read and bounds every step. Override: "# SQL-LINT-OK: <why>" in the command.
import hashlib
import json
import os
import re
import shlex
import signal
import ssl
import subprocess
import sys
import time
import urllib.request
import uuid
from datetime import datetime, timezone
from pathlib import Path

DEADLINE_SECONDS = 12
CUT = 12000
RUBRIC_VERSION = "1"
MODEL = os.environ.get("SQL_LINT_MODEL", "global.anthropic.claude-sonnet-5-5")
BASE_URL = "https://mtls.dev-llm-proxy.diligenttech.com/anthropic"
CERT_DIR = Path.home() / "Library/Application Support/diligent/bifrost/prod/current"
DILIGENT = Path(os.environ.get("SQL_LINT_DILIGENT", Path.home() / ".local/bin/diligent"))
HEADERS = {"x-tenant-id": "global", "x-product": "product-ai-tools", "x-feature": "progress-tracking"}
STATE = Path.home() / ".claude" / "state" / "sql-lint"
SIZES = STATE / "table-sizes.json"
SIZES_FAIL = STATE / "table-sizes.fail"
VERDICTS = STATE / "verdicts.json"
CLIENTS = {"psql", "pg_dump", "pg_restore"}
SHELLS = {"bash", "sh", "zsh"}
WRAPPERS = {"env", "nohup", "time", "nice", "timeout", "gtimeout", "sudo", "command", "exec", "setsid"}
UV_VALUE_OPTS = {"--with", "-p", "--python", "--project", "--directory", "--with-requirements", "--env-file", "--with-editable"}
MARKER = re.compile(
    r"psycopg|PgStore|postgresql://|\.sql\b|\bSELECT\b[^\n]*\bFROM\b|\bINSERT\s+INTO\b|\bUPDATE\b[^\n]*\bSET\b|"
    r"\bDELETE\s+FROM\b|\bALTER\b|\bDROP\b|\bTRUNCATE\b|statement_timeout", re.I)
OVERRIDE = re.compile(r"#\s*SQL-LINT-OK:\s*(\S.{9,})")
SIZE_QUERY = """SELECT coalesce(json_agg(t), '[]') FROM (
  SELECT c.relname AS table, c.reltuples::bigint AS row_estimate,
         pg_size_pretty(pg_total_relation_size(c.oid)) AS size,
         (SELECT coalesce(json_agg(pg_get_indexdef(i.indexrelid)), '[]') FROM pg_index i WHERE i.indrelid = c.oid) AS indexes
  FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
  WHERE n.nspname = 'portfolio' AND c.relkind = 'r'
  ORDER BY pg_total_relation_size(c.oid) DESC LIMIT 15) t"""
RUBRIC = """You review shell commands that run SQL on a local PostgreSQL server. The SQL is NOT run; you only judge it.
Goal: no query may run for minutes. Use the table sizes given (database pt_live, schema portfolio) to judge.
Answer "rewrite" when a query can run for minutes on those sizes. Examples: NOT IN (SELECT ...); UPDATE or DELETE with no WHERE;
a cross join; a function on an indexed column in WHERE; a repeated full count(*) on a table of millions of rows;
a join on big tables with no index; SET statement_timeout = 0 (or a huge value) around heavy work.
Also answer "rewrite" when the command writes to pt_live outside the daily run. The daily run is launched with PGAPPNAME=pt_daily or by the
pilot kit run.sh, and those are approved. Any other write to pt_live is not approved.
Answer "allow" for ordinary reads that use an index or a LIMIT, writes to other databases, and anything you cannot see a risk in.
Text marked [TRUNCATED: N more chars not shown] was NOT shown to you. Do not judge unseen text. Judge only what you see.
Reply with ONLY this JSON, no other text: {"verdict": "allow" or "rewrite", "reason": "<one plain sentence>", "fix": "<one plain sentence, empty if allow>"}"""


class Deadline(Exception):
    """Raised by the alarm when the 12 second budget is spent."""


def note(text):
    """
    Print one stderr note.

    Purpose: Tell the owner why the hook allowed a command without a verdict.
    Usage: note("model error, allowing").
    Gotchas: Never prints a token or the command.
    """
    print(f"sql-lint-guard: {text}", file=sys.stderr)


def append_log(name, record):
    """
    Append one JSON line to a file in the state folder.

    Purpose: Audit trail for reviews and overrides (L-09, L-11).
    Usage: append_log("reviews.jsonl", {...}).
    Gotchas: Never raises. A write failure is dropped.
    """
    try:
        STATE.mkdir(parents=True, exist_ok=True)
        record = {"time": datetime.now(timezone.utc).isoformat(timespec="seconds"), **record}
        with (STATE / name).open("a") as f:
            f.write(json.dumps(record) + "\n")
    except OSError:
        pass


def split_segments(cmd):
    """
    Split a command into token lists, one per simple command, and also return text inside bash -c strings.

    Purpose: Find the program at the command position, so "rg psql" is not a database command.
    Usage: segs = split_segments(cmd).
    Gotchas: Heredoc bodies are removed first (they stay in the full command text for the marker check).
    On a quoting error it falls back to a plain split.
    """
    text = re.sub(r"(<<-?\s*['\"]?(\w+)['\"]?[^\n]*)\n.*?\n[ \t]*\2[ \t]*(?=\n|$)", r"\1", cmd, flags=re.S)
    try:
        lex = shlex.shlex(text, posix=True, punctuation_chars=True)
        lex.whitespace_split = True
        lex.commenters = ""
        toks = list(lex)
    except ValueError:
        toks = text.split()
    segs, cur = [], []
    for t in toks:
        if t and set(t) <= set(";&|()\n"):
            segs.append(cur)
            cur = []
        else:
            cur.append(t)
    segs.append(cur)
    return [s for s in segs if s]


def program_of(toks):
    """
    Return (program, args) at the command position of one segment, after env assignments and wrappers.

    Purpose: Classify the segment (psql, python, bash, uv run ...).
    Usage: prog, args = program_of(toks).
    Gotchas: Skips env/nohup/time/nice/timeout/sudo wrappers with their options. For "uv run" it returns the program after the uv options.
    """
    i = 0
    while i < len(toks):
        name = os.path.basename(toks[i])
        if re.match(r"[A-Za-z_]\w*=", toks[i]):
            i += 1
        elif name in WRAPPERS:
            i += 1
            while i < len(toks) and (toks[i].startswith("-") or re.match(r"[A-Za-z_]\w*=", toks[i]) or
                                     (name in ("timeout", "gtimeout") and re.match(r"^\d", toks[i]))):
                i += 2 if toks[i] in ("-u", "-n", "-s", "-k") else 1
        elif name == "uv" and i + 1 < len(toks) and toks[i + 1] == "run":
            i += 2
            while i < len(toks) and toks[i].startswith("-"):
                i += 2 if toks[i] in UV_VALUE_OPTS else 1
        else:
            break
    if i >= len(toks):
        return "", []
    return os.path.basename(toks[i]), toks[i + 1:]


def named_files(cmd, cwd):
    """
    Return the existing .sql, .py and .sh files named anywhere in the command.

    Purpose: Their text is context for the reviewer (L-02).
    Usage: files = named_files(cmd, cwd).
    Gotchas: Relative paths resolve against the hook's cwd. A file that does not exist is ignored.
    """
    found = []
    for tok in re.findall(r"[^\s'\"=;&|()<>]+\.(?:sql|py|sh)\b", cmd):
        p = Path(os.path.expanduser(tok))
        p = p if p.is_absolute() else Path(cwd) / p
        if p.is_file() and p not in found:
            found.append(p)
    return found


def runs_database_program(cmd):
    """
    Tell whether the command runs a database client or a program that could hold SQL (L-01).

    Purpose: Gate for the review. Reads, searches, git and pytest never pass.
    Usage: if not runs_database_program(cmd): return.
    Gotchas: Looks only at the command position of each segment, and into bash -c strings. python counts with -c, "-", or a .py file.
    """
    for toks in split_segments(cmd):
        prog, args = program_of(toks)
        if prog in CLIENTS:
            return True
        if re.fullmatch(r"python[0-9.]*", prog) and ("-c" in args or "-" in args or any(a.endswith(".py") for a in args)):
            return True
        if prog in SHELLS:
            if any(a.endswith(".sh") for a in args):
                return True
            if "-c" in args and args.index("-c") + 1 < len(args) and runs_database_program(args[args.index("-c") + 1]):
                return True
    return False


def table_sizes(deadline):
    """
    Return the cached top-15 table sizes of pt_live.portfolio, refreshing the cache when older than 24 h.

    Purpose: Facts the reviewer needs to judge "runs for minutes" (L-02, L-03).
    Usage: date, sizes = table_sizes(deadline).
    Gotchas: One read-only psql query, connect_timeout=3, statement_timeout=3000. On failure returns no sizes, and a fail
    marker stops new tries for one hour, so a down server costs 3 s only once.
    """
    def fresh(path, seconds):
        return path.exists() and time.time() - path.stat().st_mtime < seconds
    if not fresh(SIZES, 86400) and not fresh(SIZES_FAIL, 3600) and deadline - time.time() > 4:
        env = {**os.environ, "PGCONNECT_TIMEOUT": "3", "PGOPTIONS": "-c statement_timeout=3000", "PGAPPNAME": "sql_lint_guard"}
        try:
            out = subprocess.run(["psql", "-h", "/tmp", "-d", "pt_live", "-At", "-c", SIZE_QUERY], env=env,
                                 capture_output=True, text=True, timeout=min(4, deadline - time.time()), check=True).stdout
            STATE.mkdir(parents=True, exist_ok=True)
            SIZES.write_text(json.dumps({"date": datetime.now().strftime("%Y-%m-%d"), "tables": json.loads(out)}))
        except (OSError, subprocess.SubprocessError, ValueError):
            STATE.mkdir(parents=True, exist_ok=True)
            SIZES_FAIL.write_text("")
            note("table sizes unavailable, reviewing without them")
    try:
        data = json.loads(SIZES.read_text())
        return data["date"], data["tables"]
    except (OSError, ValueError, KeyError):
        return "none", []


def read_head(path):
    """
    Read at most CUT characters of a file, plus the TRUNCATED marker when there is more.

    Purpose: Keep every file read bounded, so the 12 s deadline holds even for a huge file (L-02, L-07).
    Usage: text = read_head(path).
    Gotchas: The "more" count is estimated from the file size in bytes. A FIFO or slow disk is bounded by the alarm in main().
    """
    with open(path, errors="replace") as f:
        text = f.read(CUT)
    more = max(0, path.stat().st_size - len(text.encode()))
    return text + (f"\n[TRUNCATED: {more} more chars not shown]" if more else "")


def cut(text):
    """Cut text to 12000 characters. Purpose: bound the prompt. Usage: cut(s). Gotchas: adds the TRUNCATED marker the reviewer is told about."""
    return text if len(text) <= CUT else text[:CUT] + f"\n[TRUNCATED: {len(text) - CUT} more chars not shown]"


def get_token(deadline):
    """
    Get a Bifrost token from the diligent CLI.

    Purpose: The only credential source (never ANTHROPIC_API_KEY).
    Usage: token = get_token(deadline).
    Gotchas: Raises on failure. Never prints the token.
    """
    out = subprocess.run([str(DILIGENT), "auth", "token", "--env", "prod"], capture_output=True, text=True,
                         timeout=max(1, deadline - time.time()), check=True).stdout.strip()
    if not out:
        raise RuntimeError("empty token")
    return out


def ask_model(prompt, deadline):
    """
    Send the prompt to the reviewer model through Bifrost and return (verdict dict, model id).

    Purpose: The one model call (L-04).
    Usage: verdict, model = ask_model(prompt, deadline).
    Gotchas: Standard library only. mTLS cert and key are loaded into the ssl context. The reply model must be an Anthropic model.
    Raises on any failure, and the caller allows the command.
    """
    ctx = ssl.create_default_context()
    ctx.load_cert_chain(str(CERT_DIR / "cert.pem"), str(CERT_DIR / "key.pem"))
    body = json.dumps({"model": MODEL, "max_tokens": 1500, "temperature": 0, "system": RUBRIC,
                       "messages": [{"role": "user", "content": prompt}]}).encode()
    req = urllib.request.Request(BASE_URL + "/v1/messages", data=body, method="POST", headers={
        **HEADERS, "x-api-key": get_token(deadline), "anthropic-version": "2023-06-01",
        "content-type": "application/json", "x-correlation-id": str(uuid.uuid4())})
    with urllib.request.urlopen(req, context=ctx, timeout=max(1, deadline - time.time())) as resp:
        reply = json.load(resp)
    model = str(reply.get("model", ""))
    if "claude" not in model.lower():
        raise RuntimeError(f"reply came from a non-Anthropic model {model!r}")
    text = "".join(b.get("text", "") for b in reply.get("content", []) if b.get("type") == "text")
    match = re.search(r"\{.*\}", text, re.S)
    if not match:
        raise RuntimeError("reply held no JSON")
    verdict = json.loads(match.group(0))
    if verdict.get("verdict") not in ("allow", "rewrite"):
        raise RuntimeError("bad verdict")
    return verdict, model


def load_verdicts():
    """Return the verdict cache dict. Purpose: L-08 cache. Usage: v = load_verdicts(). Gotchas: a bad file reads as empty."""
    try:
        return json.loads(VERDICTS.read_text())
    except (OSError, ValueError):
        return {}


def review(cmd, cwd, deadline):
    """
    Review one database command and return a deny reason, or None to allow.

    Purpose: L-02 to L-08 and L-11 in one place.
    Usage: reason = review(cmd, cwd, deadline).
    Gotchas: A cached verdict skips the model call. Every review writes one reviews.jsonl line. Errors raise to main(), which allows.
    """
    started = time.time()
    pieces = [("COMMAND", cut(cmd))]
    for path in named_files(cmd, cwd):
        pieces.append((f"FILE {path}", read_head(path)))
    if not MARKER.search("\n".join(p[1] for p in pieces)):
        return None
    date, tables = table_sizes(deadline)
    key = hashlib.sha256(json.dumps([[p[0], p[1]] for p in pieces] + [MODEL, RUBRIC_VERSION, date]).encode()).hexdigest()
    cache = load_verdicts()
    hit = cache.get(key)
    if hit and time.time() - hit["ts"] < 7 * 86400:
        verdict, model, cached = hit["verdict"], hit["model"], True
    else:
        sizes = json.dumps(tables) if tables else "not available"
        prompt = "TABLE SIZES (pt_live.portfolio, top 15):\n" + sizes + "\n\n" + "\n\n".join(f"--- {n} ---\n{t}" for n, t in pieces)
        verdict, model = ask_model(prompt, deadline)
        cached = False
        now = time.time()
        cache = {k: v for k, v in cache.items() if now - v["ts"] < 7 * 86400}
        cache[key] = {"ts": now, "verdict": verdict, "model": model}
        STATE.mkdir(parents=True, exist_ok=True)
        VERDICTS.write_text(json.dumps(cache))
    append_log("reviews.jsonl", {"key": key[:16], "verdict": verdict["verdict"], "reason": str(verdict.get("reason", ""))[:300],
                                 "model": model, "cached": cached, "seconds": round(time.time() - started, 2)})
    if verdict["verdict"] == "allow":
        return None
    return (f"SQL review ({model}): {str(verdict.get("reason", "")).rstrip(". ")}. Try: {str(verdict.get("fix", "")).rstrip(". ")}. "
            'Rewrite the command and run it again. If the review is wrong, add "# SQL-LINT-OK: <why>" to the command.')


def main():
    """
    Read the hook JSON, decide, and exit 0 (allow) or print a reason and exit 3 (deny).

    Purpose: Entry point called by sql-lint-guard.sh.
    Usage: python3 sql_lint_guard.py < hook-input.json
    Gotchas: One 12 s alarm covers everything. Any error or the alarm allows the command with one stderr note (L-07).
    """
    # The one deadline starts first, so stdin, file reads, the token, the cache refresh and the model call all sit inside it.
    deadline = time.time() + DEADLINE_SECONDS
    signal.signal(signal.SIGALRM, lambda *_: (_ for _ in ()).throw(Deadline()))
    signal.alarm(DEADLINE_SECONDS)
    try:
        data = json.load(sys.stdin)
        cmd = data.get("tool_input", {}).get("command", "")
        cwd = data.get("cwd") or os.getcwd()
        if not runs_database_program(cmd):
            return 0
        text = cmd + "\n" + "\n".join(read_head(p) for p in named_files(cmd, cwd))
        if not MARKER.search(text):
            return 0
        override = OVERRIDE.search(cmd)
        if override:
            append_log("overrides.jsonl", {"reason": override.group(1)[:200], "command": cmd[:300]})
            return 0
        reason = review(cmd, cwd, deadline)
        signal.alarm(0)
        if reason:
            print(reason)
            return 3
    except Exception as exc:  # fail open (L-07): Part A caps time anyway
        note(f"{type(exc).__name__}: {str(exc)[:150]}. Allowing the command without review.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
