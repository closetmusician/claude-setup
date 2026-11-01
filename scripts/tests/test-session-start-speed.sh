#!/usr/bin/env bash
# ABOUTME: TDD suite for scripts/session-start.d/30-speed.sh, the one-line speed note at session start.
# ABOUTME: The note shows only in ~/.claude sessions, reads state/speed/history.jsonl, and asks for
# ABOUTME: /speed-tune when the last experiment is 7 or more days old (or there is none).
# ABOUTME: Uses a temp SPEED_STATE_DIR; never touches the live state folder.
# ABOUTME: Run: bash scripts/tests/test-session-start-speed.sh  (exit 0 = all green).

set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
DROPIN="$ROOT/scripts/session-start.d/30-speed.sh"
PASS=0; FAIL=0
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT

# run_dropin: source the drop-in like session-start.sh does. Usage: run_dropin <cwd> -> stdout.
run_dropin() {
  HOOK_STDIN_JSON="{\"cwd\":\"$1\"}" SPEED_STATE_DIR="$TMP/state" SPEED_TODAY="2026-11-10" \
    bash -c "source '$DROPIN'" 2>/dev/null
}
check() { if eval "$2"; then PASS=$((PASS+1)); echo "  ok   $1"; else FAIL=$((FAIL+1)); echo "  FAIL $1"; fi; }

mkdir -p "$TMP/state"
echo '{"date":"2026-11-09","median_req_min":1.3,"top":"wait:background","top_pct":49}' > "$TMP/state/history.jsonl"

out="$(run_dropin "$HOME/.claude")"
check "shows top bucket"               '[[ "$out" == *"wait:background 49%"* ]]'
check "asks for tune with no history"  '[[ "$out" == *"/speed-tune"* ]]'

echo '{"date":"2026-11-08","bucket":"model"}' > "$TMP/state/experiments.jsonl"
out="$(run_dropin "$HOME/.claude")"
check "no tune ask when tuned 2d ago"  '[[ "$out" != *"/speed-tune"* && -n "$out" ]]'

echo '{"date":"2026-11-01","bucket":"model"}' > "$TMP/state/experiments.jsonl"
out="$(run_dropin "$HOME/.claude")"
check "tune ask when tuned 9d ago"     '[[ "$out" == *"/speed-tune"* ]]'

out="$(run_dropin "/Users/someone/Code/app")"
check "silent outside ~/.claude"       '[ -z "$out" ]'

rm "$TMP/state/history.jsonl"
out="$(run_dropin "$HOME/.claude")"
check "silent with no report yet"      '[ -z "$out" ]'

printf '=== %d passed, %d failed ===\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
