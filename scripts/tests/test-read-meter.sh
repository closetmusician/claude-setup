#!/usr/bin/env bash
# ABOUTME: TDD suite for scripts/governance/read-meter.sh (spec C7).
# ABOUTME: The meter adds up raw tool output an orchestrator takes in and warns once at
# ABOUTME: 100 KB, 200 KB and 400 KB. It never blocks.
# ABOUTME: Run: bash scripts/tests/test-read-meter.sh — exit 0 = all green.
# ABOUTME: Spec: docs/plans/harness/governance-scope-spec.md §3 C7, §4.

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="${SCRIPT_DIR}/../governance/read-meter.sh"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
PASS=0; FAIL=0
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib/gov-hook-fixtures.sh"

ARMED="$TMP/state"; mkdir -p "$ARMED"; touch "$ARMED/.active"
IDLE="$TMP/state-idle"; mkdir -p "$IDLE"
R="$TMP/r"; new_repo "$R" a.md

# post <bytes> [agent_id] → PostToolUse Bash payload with a response of about <bytes>
post() {
  local body; body="$(perl -e 'print "x" x $ARGV[0]' "$1")"
  pl PostToolUse "$R" Bash '{"command":"cat x"}' "${2:-}" "$(jq -cn --arg s "$body" '{stdout:$s,stderr:""}')"
}
warned() { printf '%s' "$OUT" | jq -e '.hookSpecificOutput.additionalContext | test("raw tool output")' >/dev/null 2>&1 && echo yes || echo no; }

echo "=== test-read-meter.sh ==="
run_hook "$HOOK" "$R" "$(post 60000)" HARNESS_GOV_STATE_DIR="$ARMED"
assert_eq "60 KB: no warning"            no  "$(warned)"
assert_eq "60 KB: never blocks"          ALLOW "$(decision_of)"
run_hook "$HOOK" "$R" "$(post 50000)" HARNESS_GOV_STATE_DIR="$ARMED"
assert_eq "110 KB: warns"                yes "$(warned)"
run_hook "$HOOK" "$R" "$(post 20000)" HARNESS_GOV_STATE_DIR="$ARMED"
assert_eq "130 KB: no repeat warning"    no  "$(warned)"
run_hook "$HOOK" "$R" "$(post 80000)" HARNESS_GOV_STATE_DIR="$ARMED"
assert_eq "210 KB: warns again"          yes "$(warned)"
TOTAL="$(cat "$ARMED"/read-meter-test-sess 2>/dev/null)"
[ "${TOTAL:-0}" -ge 210000 ] && r=yes || r=no
assert_eq "meter file holds the running total" yes "$r"

run_hook "$HOOK" "$R" "$(post 500000 agent1)" HARNESS_GOV_STATE_DIR="$IDLE"
assert_eq "subagent output not metered"  no "$(warned)"
run_hook "$HOOK" "$R" "$(post 500000)" HARNESS_GOV_STATE_DIR="$IDLE"
assert_eq "no sentinel: not metered"     no "$(warned)"
[ -e "$IDLE/read-meter-test-sess" ] && r=yes || r=no
assert_eq "no sentinel: no meter file"   no "$r"

echo
echo "=== $PASS passed, $FAIL failed ==="
[ "$FAIL" -eq 0 ]
