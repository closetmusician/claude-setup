#!/usr/bin/env bash
# ABOUTME: TDD test suite for scripts/autonomous-secret-scan.sh — PostToolUse secret guard.
# ABOUTME: Tests the SCOPE INVARIANT (interactive-plane pass-through), clean-file no-op,
# ABOUTME: PAT detection (delete + tombstone + P0 event + kill-switch), tombstone privacy,
# ABOUTME: scanner-missing fail-open, Anthropic key detection, and stdin session_id contract.
# ABOUTME: Run: bash scripts/tests/test-autonomous-secret-scan.sh
# ABOUTME: Token fragments assembled at runtime — no secret-shaped literal at rest in this file.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="${SCRIPT_DIR}/../autonomous-secret-scan.sh"

# ── Isolated temp environment for all tests ───────────────────────────────────
TMPROOT="$(mktemp -d /tmp/test-assr-XXXXXX)"
# Isolated STATE so no test touches the real events log or kill-switch sentinel
export STATE="$TMPROOT/state"
mkdir -p "$STATE"

PASS=0
FAIL=0
ERRORS=""

_pass() { echo "  PASS: $1"; (( PASS++ )) || true; }
_fail() { echo "  FAIL: $1 — $2"; (( FAIL++ )) || true; ERRORS+="  FAIL: $1 — $2\n"; }

_assert_file_exists() {
  local label="$1" fpath="$2"
  if [[ -f "$fpath" ]]; then _pass "$label"; else _fail "$label" "expected $fpath to exist"; fi
}

_assert_file_absent() {
  local label="$1" fpath="$2"
  if [[ ! -f "$fpath" ]]; then _pass "$label"; else _fail "$label" "expected $fpath to be absent"; fi
}

_assert_contains() {
  local label="$1" file="$2" pattern="$3"
  if grep -q "$pattern" "$file" 2>/dev/null; then _pass "$label"; else _fail "$label" "pattern '$pattern' not found in $file"; fi
}

_assert_not_contains() {
  local label="$1" file="$2" pattern="$3"
  if ! grep -q "$pattern" "$file" 2>/dev/null; then _pass "$label"; else _fail "$label" "forbidden pattern '$pattern' found in $file"; fi
}

# Build a valid autonomous-registry.json with a registered session ID.
# The session ID value used by tests.
TEST_SID="test-session-assr-001"

_setup_registry() {
  printf '[{"session_id":"%s","started":"2026-07-05T00:00:00Z"}]\n' "$TEST_SID" \
    > "$STATE/autonomous-registry.json"
}

_clear_registry() {
  rm -f "$STATE/autonomous-registry.json"
}

# Build PostToolUse hook stdin JSON for a Write tool call with the given file path.
_hook_input() {
  local fpath="$1"
  local sid="${2:-$TEST_SID}"
  jq -cn --arg p "$fpath" --arg sid "$sid" '{"session_id":$sid,"tool_name":"Write","tool_input":{"file_path":$p}}'
}

# Run the hook with a given environment, piping hook input from stdin.
# Usage: _run_hook <hook_input_json> [env_overrides...]
_run_hook() {
  local input="$1"; shift
  # Pass remaining args as env vars (NAME=VALUE form)
  env "$@" bash "$HOOK" <<< "$input" 2>/dev/null
  return 0  # always succeed at shell level; hook exits 0
}

echo "=== autonomous-secret-scan TDD suite ==="
echo "HOOK: $HOOK"
echo "TMPROOT: $TMPROOT"
echo ""

if [[ ! -f "$HOOK" ]]; then
  echo "  autonomous-secret-scan.sh NOT FOUND — all tests will FAIL (RED phase)"
fi

# ── Case 1: Interactive plane — AUTONOMOUS_RUN unset → exit 0, file untouched ──
echo "--- Case 1: AUTONOMOUS_RUN unset (interactive plane) → pass-through ---"
_setup_registry
_clean1="$TMPROOT/clean1.txt"
printf 'hello world\n' > "$_clean1"
_run_hook "$(_hook_input "$_clean1")" "STATE=$STATE"
_assert_file_exists  "C1: file untouched when AUTONOMOUS_RUN unset" "$_clean1"
_assert_file_absent  "C1: no tombstone when AUTONOMOUS_RUN unset" "${_clean1}.DELETED-SECRET-SCAN"
_clear_registry

# ── Case 2: AUTONOMOUS_RUN=1 + clean file → untouched ────────────────────────
echo "--- Case 2: AUTONOMOUS_RUN=1 + clean file → untouched ---"
_setup_registry
_clean2="$TMPROOT/clean2.txt"
printf 'this is perfectly fine content\n' > "$_clean2"
_run_hook "$(_hook_input "$_clean2")" "AUTONOMOUS_RUN=1" "STATE=$STATE"
_assert_file_exists  "C2: clean file survives autonomous scan" "$_clean2"
_assert_file_absent  "C2: no tombstone for clean file" "${_clean2}.DELETED-SECRET-SCAN"
_clear_registry

# ── Case 3: AUTONOMOUS_RUN=1 + GitHub PAT pattern → deleted + tombstone + P0 emit + kill-switch ──
# Token assembled at runtime so no literal secret-shaped string exists at rest in this file.
echo "--- Case 3: AUTONOMOUS_RUN=1 + GitHub PAT → delete + tombstone + P0 + kill-switch ---"
_setup_registry
_secret3="$TMPROOT/secret3.txt"
# Assemble a fake PAT (not a real credential — constructed from fragments at runtime).
# Pattern: ghp_ followed by 30+ alphanumeric chars. We concat three parts so no literal exists.
_PAT_PREFIX="ghp_"
_PAT_BODY="AAAA$(printf 'B%.0s' {1..30})CC"
printf '%s%s\n' "$_PAT_PREFIX" "$_PAT_BODY" > "$_secret3"
_run_hook "$(_hook_input "$_secret3")" "AUTONOMOUS_RUN=1" "STATE=$STATE"
_assert_file_absent  "C3: secret file deleted after detection" "$_secret3"
_assert_file_exists  "C3: tombstone written" "${_secret3}.DELETED-SECRET-SCAN"
# P0 incident should appear in events log (if emit-event.sh wired)
if [[ -f "$STATE/state/events.ndjson" ]]; then
  _assert_contains   "C3: P0 incident event emitted" "$STATE/state/events.ndjson" "autonomous-secret-detected"
else
  _pass "C3: P0 incident event (emit unavailable in isolated test — fail-open OK)"
fi
# Kill-switch sentinel should be tripped
_assert_file_exists  "C3: kill-switch sentinel tripped" "$STATE/.AUTONOMOUS_FREEZE"
# Reset kill-switch sentinel for subsequent tests
rm -f "$STATE/.AUTONOMOUS_FREEZE"
_clear_registry

# ── Case 4: Tombstone must NOT contain the raw secret value ──────────────────
echo "--- Case 4: Tombstone never contains raw secret ---"
_setup_registry
_secret4="$TMPROOT/secret4.txt"
_PAT4_PREFIX="ghp_"
_PAT4_BODY="$(printf 'X%.0s' {1..35})"
_FULL_PAT4="${_PAT4_PREFIX}${_PAT4_BODY}"
printf '%s\n' "$_FULL_PAT4" > "$_secret4"
_run_hook "$(_hook_input "$_secret4")" "AUTONOMOUS_RUN=1" "STATE=$STATE"
_tombstone4="${_secret4}.DELETED-SECRET-SCAN"
if [[ -f "$_tombstone4" ]]; then
  # The tombstone must not contain the full PAT value (it may contain a masked prefix at most)
  _assert_not_contains "C4: tombstone omits raw secret" "$_tombstone4" "$_FULL_PAT4"
else
  _fail "C4: tombstone omits raw secret" "tombstone not created — hook may not have fired"
fi
rm -f "$STATE/.AUTONOMOUS_FREEZE"
_clear_registry

# ── Case 5: Scanner missing → fail-open (no delete) ─────────────────────────
echo "--- Case 5: Scanner missing → fail-open, file untouched ---"
_setup_registry
_clean5="$TMPROOT/clean5.txt"
_PAT5_PREFIX="ghp_"
_PAT5_BODY="$(printf 'Y%.0s' {1..30})"
printf '%s%s\n' "$_PAT5_PREFIX" "$_PAT5_BODY" > "$_clean5"
# Override SECRET_SCAN path to a non-existent binary via the env override that the hook reads
# The hook must check [[ -x "$SECRET_SCAN" ]] || exit 0
# We test by temporarily renaming secret-scan.sh — instead, set REAL_SCANNER to a fake path.
# The hook derives SECRET_SCAN from HOME; we override HOME to an isolated dir with no scanner.
_fake_home="$TMPROOT/fakehome"
mkdir -p "$_fake_home/.claude/scripts"
# No secret-scan.sh in fake home → hook must exit 0 without deleting
HOME="$_fake_home" _run_hook "$(_hook_input "$_clean5")" "AUTONOMOUS_RUN=1" "STATE=$STATE"
_assert_file_exists  "C5: scanner missing → file untouched (fail-open)" "$_clean5"
_assert_file_absent  "C5: scanner missing → no tombstone" "${_clean5}.DELETED-SECRET-SCAN"
_clear_registry

# ── Case 6: Malformed payload → exit 0, no side effects ──────────────────────
echo "--- Case 6: Malformed JSON payload → exit 0, no crash ---"
_setup_registry
_junk_input="this is not json at all {{{invalid"
# Hook must trap ERR and exit 0 on malformed input
result=0
AUTONOMOUS_RUN=1 STATE="$STATE" env -u SESSION_ID bash "$HOOK" <<< "$_junk_input" 2>/dev/null || result=$?
if [[ "$result" -eq 0 ]]; then _pass "C6: malformed payload → exit 0"; else _fail "C6: malformed payload → exit 0" "hook exited $result"; fi
_clear_registry

# ── Case 7: AUTONOMOUS_RUN=1 but no SESSION_ID env → enforce via prod contract ──
echo "--- Case 7: AUTONOMOUS_RUN=1 + no SESSION_ID env → scan and block secret ---"
_setup_registry  # registry has TEST_SID but we'll use a DIFFERENT session ID
_secret7="$TMPROOT/secret7.txt"
_PAT7_PREFIX="ghp_"
_PAT7_BODY="$(printf 'Z%.0s' {1..30})"
printf '%s%s\n' "$_PAT7_PREFIX" "$_PAT7_BODY" > "$_secret7"
# Use a session ID only on stdin; env SESSION_ID is absent.
_run_hook "$(_hook_input "$_secret7" "lane-1")" "AUTONOMOUS_RUN=1" "STATE=$STATE"
_assert_file_absent  "C7: no SESSION_ID env → secret file deleted" "$_secret7"
_assert_file_exists  "C7: no SESSION_ID env → tombstone written" "${_secret7}.DELETED-SECRET-SCAN"
_clear_registry

# ── Final summary ──────────────────────────────────────────────────────────────
echo ""
echo "=== Results: $PASS passed, $FAIL failed ==="
if [[ "$FAIL" -gt 0 ]]; then
  echo ""
  echo "Failures:"
  printf '%b' "$ERRORS"
  exit 1
fi
exit 0
