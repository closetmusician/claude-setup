#!/usr/bin/env bash
# ABOUTME: TDD test suite for scripts/spine-tap.sh — the unconditional telemetry observer.
# ABOUTME: Tests agent_spawn, agent_result, tool_error, sampling, session_start dedup,
# ABOUTME: malformed payload exit 0, jq absent exit 0, and never-writes-stdout invariants.
# ABOUTME: All 8 required cases must pass GREEN after spine-tap.sh is created.
# ABOUTME: Run: bash scripts/tests/test-spine-tap.sh

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TAP="${SCRIPT_DIR}/../spine-tap.sh"

# ── Isolated temp STATE for all tests ────────────────────────────────────────
TMPROOT="$(mktemp -d /tmp/test-spine-tap-XXXXXX)"
export SPINE_HOME="$TMPROOT/spine"
export SPINE_SEEN="$TMPROOT/spine-seen"
mkdir -p "$SPINE_HOME" "$SPINE_SEEN"

EVENTS="$SPINE_HOME/events.ndjson"

PASS=0
FAIL=0

_pass() { echo "  PASS: $1"; (( PASS++ )) || true; }
_fail() { echo "  FAIL: $1 — $2"; (( FAIL++ )) || true; }

_assert_contains() {
  local label="$1" file="$2" pattern="$3"
  if grep -q "$pattern" "$file" 2>/dev/null; then
    _pass "$label"
  else
    _fail "$label" "pattern '$pattern' not found in $file"
  fi
}

_assert_count() {
  local label="$1" file="$2" expected="$3"
  local actual
  actual=$(wc -l < "$file" 2>/dev/null || echo 0)
  actual="${actual// /}"
  if [[ "$actual" -eq "$expected" ]]; then
    _pass "$label"
  else
    _fail "$label" "expected $expected lines, got $actual"
  fi
}

_fresh() {
  rm -f "$EVENTS"
  rm -rf "$SPINE_SEEN"
  mkdir -p "$SPINE_SEEN"
}

echo "=== spine-tap TDD suite ==="
echo "TAP: $TAP"
echo "SPINE_HOME: $SPINE_HOME"
echo ""

# Guard: script must exist (after GREEN phase)
if [[ ! -f "$TAP" ]]; then
  echo "spine-tap.sh NOT FOUND — all 8 tests will FAIL (RED phase confirmed)"
fi

# ── Case 1: agent_spawn emitted on PreToolUse Task/Agent ─────────────────────
echo "--- Case 1: agent_spawn on PreToolUse Task/Agent ---"
_fresh
HOOK_STDIN_JSON='{"session_id":"sess-spawn-1","agent_id":null,"tool_name":"Task","tool_input":{"description":"test task"}}' \
HOOK_EVENT_NAME="PreToolUse" \
SPINE_HOME="$SPINE_HOME" SPINE_SEEN="$SPINE_SEEN" \
  bash "$TAP" 2>/dev/null; true
if [[ -f "$EVENTS" ]]; then
  _assert_contains "agent_spawn event written" "$EVENTS" '"agent_spawn"'
  _assert_contains "session_id present" "$EVENTS" '"sess-spawn-1"'
else
  _fail "agent_spawn event written" "events.ndjson not created"
  _fail "session_id present" "events.ndjson not created"
fi

# ── Case 2: agent_result emitted on PostToolUse Task/Agent ───────────────────
echo "--- Case 2: agent_result on PostToolUse Task/Agent ---"
_fresh
HOOK_STDIN_JSON='{"session_id":"sess-result-2","agent_id":null,"tool_name":"Agent","tool_result":{"output":"done"}}' \
HOOK_EVENT_NAME="PostToolUse" \
SPINE_HOME="$SPINE_HOME" SPINE_SEEN="$SPINE_SEEN" \
  bash "$TAP" 2>/dev/null; true
if [[ -f "$EVENTS" ]]; then
  _assert_contains "agent_result event written" "$EVENTS" '"agent_result"'
else
  _fail "agent_result event written" "events.ndjson not created"
fi

# ── Case 3: tool_error on nonzero Bash exit ───────────────────────────────────
echo "--- Case 3: tool_error on PostToolUse Bash nonzero exit ---"
_fresh
HOOK_STDIN_JSON='{"session_id":"sess-err-3","agent_id":null,"tool_name":"Bash","tool_result":{"exit_code":1,"stderr":"command not found"}}' \
HOOK_EVENT_NAME="PostToolUse" \
SPINE_HOME="$SPINE_HOME" SPINE_SEEN="$SPINE_SEEN" \
  bash "$TAP" 2>/dev/null; true
if [[ -f "$EVENTS" ]]; then
  _assert_contains "tool_error event written" "$EVENTS" '"tool_error"'
else
  _fail "tool_error event written" "events.ndjson not created"
fi

# ── Case 4a: sampling=0 suppresses tool_call for Bash success ────────────────
echo "--- Case 4a: sampling=0 → no tool_call for Bash exit 0 ---"
_fresh
HARNESS_TOOL_SAMPLE=0 \
HOOK_STDIN_JSON='{"session_id":"sess-samp-4a","agent_id":null,"tool_name":"Bash","tool_result":{"exit_code":0}}' \
HOOK_EVENT_NAME="PostToolUse" \
SPINE_HOME="$SPINE_HOME" SPINE_SEEN="$SPINE_SEEN" \
  bash "$TAP" 2>/dev/null; true
# No events (or only session_start, never tool_call)
if [[ -f "$EVENTS" ]]; then
  if grep -q '"tool_call"' "$EVENTS" 2>/dev/null; then
    _fail "sampling=0 suppresses tool_call" "tool_call event found (should be suppressed)"
  else
    _pass "sampling=0 suppresses tool_call"
  fi
else
  _pass "sampling=0 suppresses tool_call"
fi

# ── Case 4b: sampling=1 always emits tool_call for Bash success ──────────────
echo "--- Case 4b: sampling=1 → tool_call always for Bash exit 0 ---"
_fresh
HARNESS_TOOL_SAMPLE=1 \
HOOK_STDIN_JSON='{"session_id":"sess-samp-4b","agent_id":null,"tool_name":"Bash","tool_result":{"exit_code":0}}' \
HOOK_EVENT_NAME="PostToolUse" \
SPINE_HOME="$SPINE_HOME" SPINE_SEEN="$SPINE_SEEN" \
  bash "$TAP" 2>/dev/null; true
if [[ -f "$EVENTS" ]]; then
  _assert_contains "sampling=1 emits tool_call" "$EVENTS" '"tool_call"'
else
  _fail "sampling=1 emits tool_call" "events.ndjson not created"
fi

# ── Case 5: session_start emitted once-then-never ────────────────────────────
echo "--- Case 5: session_start once per session_id ---"
_fresh
# First call — should emit session_start
HOOK_STDIN_JSON='{"session_id":"sess-dedup-5","agent_id":null,"tool_name":"Task","tool_input":{}}' \
HOOK_EVENT_NAME="PreToolUse" \
SPINE_HOME="$SPINE_HOME" SPINE_SEEN="$SPINE_SEEN" \
  bash "$TAP" 2>/dev/null; true

first_count=0
[[ -f "$EVENTS" ]] && first_count=$(grep -c '"session_start"' "$EVENTS" 2>/dev/null || echo 0)

# Second call with same session_id — should NOT emit another session_start
HOOK_STDIN_JSON='{"session_id":"sess-dedup-5","agent_id":null,"tool_name":"Task","tool_input":{}}' \
HOOK_EVENT_NAME="PreToolUse" \
SPINE_HOME="$SPINE_HOME" SPINE_SEEN="$SPINE_SEEN" \
  bash "$TAP" 2>/dev/null; true

second_count=0
[[ -f "$EVENTS" ]] && second_count=$(grep -c '"session_start"' "$EVENTS" 2>/dev/null || echo 0)

if [[ "$first_count" -eq 1 && "$second_count" -eq 1 ]]; then
  _pass "session_start emitted exactly once (not again on 2nd call)"
elif [[ "$first_count" -eq 0 ]]; then
  _fail "session_start emitted exactly once" "no session_start emitted on first call"
else
  _fail "session_start emitted exactly once" "session_start count after 2nd call: $second_count (expected 1)"
fi

# ── Case 6: malformed/empty payload exits 0 ──────────────────────────────────
echo "--- Case 6: malformed payload exits 0 ---"
_fresh
result=0
HOOK_STDIN_JSON='not valid json at all {{{' \
HOOK_EVENT_NAME="PreToolUse" \
SPINE_HOME="$SPINE_HOME" SPINE_SEEN="$SPINE_SEEN" \
  bash "$TAP" 2>/dev/null || result=$?
if [[ "$result" -eq 0 ]]; then
  _pass "malformed payload exits 0"
else
  _fail "malformed payload exits 0" "exit code was $result"
fi

# Empty payload
result=0
HOOK_STDIN_JSON='' \
HOOK_EVENT_NAME="PreToolUse" \
SPINE_HOME="$SPINE_HOME" SPINE_SEEN="$SPINE_SEEN" \
  bash "$TAP" 2>/dev/null || result=$?
if [[ "$result" -eq 0 ]]; then
  _pass "empty payload exits 0"
else
  _fail "empty payload exits 0" "exit code was $result"
fi

# ── Case 7: jq absent → exits 0, no crash ────────────────────────────────────
echo "--- Case 7: jq absent exits 0 ---"
_fresh
# Create a fake bin dir with everything EXCEPT jq (keep bash, stat, date, etc.)
TMPBIN="$(mktemp -d /tmp/test-spine-tap-bin-XXXXXX)"
# Build a PATH that has bash et al but not jq: put a fake jq that doesn't exist by
# creating a TMPBIN ahead of the real jq in PATH, containing no jq binary.
# We need bash itself to stay available — so we use the full system PATH but inject
# a dir ahead that has a broken jq stub.
cat > "$TMPBIN/jq" << 'STUB'
#!/usr/bin/env bash
exit 127
STUB
chmod +x "$TMPBIN/jq"
result=0
PATH="$TMPBIN:$PATH" \
HOOK_STDIN_JSON='{"session_id":"sess-nojq-7","agent_id":null,"tool_name":"Task","tool_input":{}}' \
HOOK_EVENT_NAME="PreToolUse" \
SPINE_HOME="$SPINE_HOME" SPINE_SEEN="$SPINE_SEEN" \
  bash "$TAP" 2>/dev/null || result=$?
rm -rf "$TMPBIN"
if [[ "$result" -eq 0 ]]; then
  _pass "jq absent exits 0"
else
  _fail "jq absent exits 0" "exit code was $result"
fi

# ── Case 8: never writes to stdout ──────────────────────────────────────────
echo "--- Case 8: never writes to stdout ---"
_fresh
stdout_output=$(
  HOOK_STDIN_JSON='{"session_id":"sess-stdout-8","agent_id":null,"tool_name":"Task","tool_input":{}}' \
  HOOK_EVENT_NAME="PreToolUse" \
  SPINE_HOME="$SPINE_HOME" SPINE_SEEN="$SPINE_SEEN" \
    bash "$TAP" 2>/dev/null
)
if [[ -z "$stdout_output" ]]; then
  _pass "never writes to stdout"
else
  _fail "never writes to stdout" "stdout was: ${stdout_output:0:100}"
fi

# ── Summary ──────────────────────────────────────────────────────────────────
echo ""
echo "─────────────────────────────────────"
echo "Results: $PASS passed, $FAIL failed"
echo "─────────────────────────────────────"

# Cleanup
rm -rf "$TMPROOT"

[[ "$FAIL" -eq 0 ]] && exit 0 || exit 1
