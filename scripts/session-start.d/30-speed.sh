#!/usr/bin/env bash
# ABOUTME: SessionStart drop-in: prints one line from the nightly speed report (state/speed/history.jsonl).
# ABOUTME: Shows only in ~/.claude sessions, so product work is not distracted.
# ABOUTME: Adds "run /speed-tune" when the last speed experiment is 7 or more days old, or there is none.
# ABOUTME: Sourced by session-start.sh; fail-open and silent when no report exists yet.
# ABOUTME: Plan: docs/learnings/speed/PLAN.md. Tests: scripts/tests/test-session-start-speed.sh

_speed_state="${SPEED_STATE_DIR:-$HOME/.claude/state/speed}"
_speed_cwd="$(printf '%s' "${HOOK_STDIN_JSON:-}" | jq -r '.cwd // empty' 2>/dev/null)"
if [[ "$_speed_cwd" == "$HOME/.claude"* && -s "$_speed_state/history.jsonl" ]]; then
  python3 - "$_speed_state" "${SPEED_TODAY:-$(date +%F)}" <<'PY' 2>/dev/null || true
import json, os, sys
from datetime import date
state, today = sys.argv[1], date.fromisoformat(sys.argv[2])
h = json.loads(open(os.path.join(state, "history.jsonl")).read().strip().splitlines()[-1])
line = f"[Speed] {h['date']}: median request {h['median_req_min']} min; top bucket {h['top']} {h['top_pct']}%."
exp = os.path.join(state, "experiments.jsonl")
last = None
if os.path.exists(exp):
    rows = [l for l in open(exp) if l.strip()]
    last = date.fromisoformat(json.loads(rows[-1])["date"]) if rows else None
if last is None or (today - last).days >= 7:
    line += " Last tune: " + (f"{last} ({(today - last).days} days ago)" if last else "never") + ". Run /speed-tune when there is a 10-minute gap."
print(line)
PY
fi
unset _speed_state _speed_cwd
