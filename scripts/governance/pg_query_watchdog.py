# ABOUTME: One-pass watchdog for the local PostgreSQL server. Cancels agent queries that run over 300 seconds.
# ABOUTME: Log-only by default. Enforce mode needs the file ~/.claude/state/pg-watchdog/ENFORCE. Kill switch: file OFF.
# ABOUTME: Run it from launchd every 30 s: uv run --with "psycopg[binary]" python pg_query_watchdog.py
# ABOUTME: Never fails the caller: any error is one "error" event and exit 0. Spec: sql-lint-guard/spec.md Part A.
# ABOUTME: Each cancel re-checks pid, start time, state, type, name and age in the same statement, so it never hits a changed session.
import argparse
import json
import os
import sys
import time
from datetime import datetime, timezone
from pathlib import Path

LIMIT_SECONDS = 300
SECOND_STRIKE_AFTER = 60
STATE = Path.home() / ".claude" / "state" / "pg-watchdog"
ALLOW_FILE = Path(__file__).resolve().with_name("pg-query-watchdog.allow")
EVENTS = STATE / "events.jsonl"
STRIKES = STATE / "strikes.json"

TARGETS = """
SELECT pid, query_start::text, datname, usename, application_name, client_addr::text,
       extract(epoch FROM now() - query_start)::int, left(query, 300)
FROM pg_stat_activity
WHERE backend_type = 'client backend' AND state = 'active'
  AND now() - query_start > make_interval(secs => %s) AND pid <> pg_backend_pid()
"""

# Cancel or terminate only if the backend is still the same query, still active, still over the cap and still the same name.
SIGNAL = """
SELECT {fn}(pid) FROM pg_stat_activity
WHERE pid = %s AND query_start::text = %s AND state = 'active' AND backend_type = 'client backend'
  AND application_name = %s AND now() - query_start > make_interval(secs => %s) AND pid <> pg_backend_pid()
"""


def log_event(mode, action, row=None, error=None):
    """
    Append one event line to events.jsonl.

    Purpose: The single record of what the watchdog saw or did.
    Usage: log_event("enforce", "cancel", row) or log_event(mode, "error", error="...").
    Gotchas: Never raises. A write failure is dropped, because the run must exit 0.
    """
    event = {"time": datetime.now(timezone.utc).isoformat(timespec="seconds"), "mode": mode, "action": action}
    if row:
        keys = ("pid", "query_start", "datname", "usename", "application_name", "client_addr", "seconds", "query")
        event.update(zip(keys, row))
        event.pop("query_start")
    if error:
        event["error"] = error
    try:
        with EVENTS.open("a") as f:
            f.write(json.dumps(event) + "\n")
    except OSError:
        pass


def read_allow():
    """
    Return the set of approved application names.

    Purpose: Names in this set are never cancelled (W-03).
    Usage: if row_app in read_allow(): skip.
    Gotchas: Exact match only. Text after "#" is a comment. An unreadable file returns None,
    and run_pass() then refuses to enforce, so approved work is never cancelled by mistake.
    """
    try:
        lines = ALLOW_FILE.read_text().splitlines()
    except OSError:
        return None
    return {l.split("#", 1)[0].strip() for l in lines} - {""}


def read_strikes():
    """
    Return the strikes dict {"pid|query_start": {"mode": str, "t": float}}.

    Purpose: Remember the first strike between passes (W-04).
    Usage: strikes = read_strikes().
    Gotchas: A missing or bad file, a non-dict, or a bad record reads as no strike, so a cancel is never skipped.
    """
    try:
        data = json.loads(STRIKES.read_text())
    except (OSError, ValueError):
        return {}
    if not isinstance(data, dict):
        return {}
    return {k: v for k, v in data.items() if isinstance(v, dict) and isinstance(v.get("mode"), str)
            and isinstance(v.get("t"), (int, float))}


def run_pass(only_app):
    """
    Read pg_stat_activity once and act on every query running over 300 s.

    Purpose: The whole watchdog. First strike cancels, a second strike 60 s later terminates.
    Usage: run_pass(None) or run_pass("watchdog_proof").
    Gotchas: In log-only mode nothing is touched and strikes are kept apart from enforce strikes.
    A strike is keyed by pid plus query_start, so a new query on the same pid starts again at strike one.
    """
    import psycopg

    mode = "enforce" if (STATE / "ENFORCE").exists() else "log-only"
    allow = read_allow()
    if allow is None:
        if mode == "enforce":
            raise RuntimeError(f"allow file unreadable ({ALLOW_FILE}); enforce pass skipped")
        allow = set()
    strikes = read_strikes()
    now = time.time()
    kept = {}
    with psycopg.connect(dbname="postgres", application_name="pg_query_watchdog", connect_timeout=5,
                         options="-c statement_timeout=5000", autocommit=True) as conn:
        rows = conn.execute(TARGETS, (LIMIT_SECONDS,)).fetchall()
        for row in rows:
            pid, started, app = row[0], row[1], row[4]
            if app in allow or (only_app is not None and app != only_app):
                continue
            key = f"{pid}|{started}"
            prev = strikes.get(key)
            if prev and prev["mode"] != mode:
                prev = None
            if prev is None:
                kept[key] = {"mode": mode, "t": now}
                action = "cancel"
            elif now - prev["t"] >= SECOND_STRIKE_AFTER:
                kept[key] = prev
                action = "terminate"
            else:
                kept[key] = prev
                continue
            try:  # one bad target must not stop the others
                if mode == "enforce":
                    hit = conn.execute(SIGNAL.format(fn=f"pg_{action}_backend"), (pid, started, app, LIMIT_SECONDS)).fetchall()
                    if not hit:
                        action = "skip_changed"  # the query ended or changed between the read and the signal
                log_event(mode, action if mode == "enforce" else "would_" + action, row)
            except Exception as exc:
                log_event(mode, "error", row, error=f"{type(exc).__name__}: {exc}"[:300])
    STRIKES.write_text(json.dumps(kept))


def main():
    """
    Parse flags, honour the kill switch, run one pass, and always exit 0.

    Purpose: Entry point for launchd and for the proof runs.
    Usage: pg_query_watchdog.py [--only-app NAME]
    Gotchas: --only-app is required for every enforce-mode proof run (W-07b). OFF file means exit at once, no log.
    """
    parser = argparse.ArgumentParser()
    parser.add_argument("--only-app", default=None)
    args = parser.parse_args()
    if (STATE / "OFF").exists():
        return
    STATE.mkdir(parents=True, exist_ok=True)
    try:
        run_pass(args.only_app)
    except Exception as exc:  # any failure: one error event, exit 0 (W-08)
        log_event("enforce" if (STATE / "ENFORCE").exists() else "log-only", "error", error=f"{type(exc).__name__}: {exc}"[:300])


if __name__ == "__main__":
    main()
    sys.exit(0)
