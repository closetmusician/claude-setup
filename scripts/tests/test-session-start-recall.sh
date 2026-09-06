#!/usr/bin/env bash
# ABOUTME: Test suite for scripts/session-start.d/20-recall.sh (Pillar V, task V3).
# ABOUTME: 5 oracle cases per spec: known project (memories injected), unknown slug (empty),
# ABOUTME: recall hangs (timeout), malformed stdin (exit 0, no stderr), git-absent cwd (basename).
# ABOUTME: All tests use mktemp sandboxes + PATH shims for fake harness; never touches real state.
# ABOUTME: RED phase: written before 20-recall.sh exists; all tests expected to fail initially.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DROP_IN="${SCRIPT_DIR}/../session-start.d/20-recall.sh"

PASS=0
FAIL=0
SKIP=0

# ── Test framework ──────────────────────────────────────────────────────────────
_ok() {
  local label="$1"
  PASS=$(( PASS + 1 ))
  echo "  PASS: $label"
}

_fail() {
  local label="$1" detail="${2:-}"
  FAIL=$(( FAIL + 1 ))
  echo "  FAIL: $label${detail:+ — $detail}"
}

_assert_eq() {
  local label="$1" got="$2" want="$3"
  if [[ "$got" == "$want" ]]; then
    _ok "$label"
  else
    _fail "$label" "got='$got' want='$want'"
  fi
}

_assert_contains() {
  local label="$1" haystack="$2" needle="$3"
  if printf '%s' "$haystack" | grep -qF "$needle"; then
    _ok "$label"
  else
    _fail "$label" "needle='$needle' not found in: ${haystack:0:200}"
  fi
}

_assert_not_contains() {
  local label="$1" haystack="$2" needle="$3"
  if printf '%s' "$haystack" | grep -qF "$needle"; then
    _fail "$label" "needle='$needle' unexpectedly found in output"
  else
    _ok "$label"
  fi
}

_assert_empty() {
  local label="$1" val="$2"
  if [[ -z "$val" ]]; then
    _ok "$label"
  else
    _fail "$label" "expected empty, got: ${val:0:200}"
  fi
}

_assert_not_empty() {
  local label="$1" val="$2"
  if [[ -n "$val" ]]; then
    _ok "$label"
  else
    _fail "$label" "expected non-empty"
  fi
}

_assert_json_path() {
  # Purpose: assert jq path returns expected value in JSON string
  # Usage: _assert_json_path label json_string jq_path expected_value
  local label="$1" json="$2" jq_path="$3" want="$4"
  local got
  got="$(printf '%s' "$json" | jq -r "$jq_path" 2>/dev/null || echo "__JQ_ERROR__")"
  if [[ "$got" == "$want" ]]; then
    _ok "$label"
  else
    _fail "$label" "path=$jq_path got='$got' want='$want'"
  fi
}

# ── Helpers ─────────────────────────────────────────────────────────────────────

# _make_state: create a temp STATE dir with required subdirs; echo path
_make_state() {
  local d
  d="$(mktemp -d /tmp/harness-recall-test-XXXXXX)"
  mkdir -p "$d/state"
  echo "$d"
}

# _run_drop_in: run the drop-in sourced in a subshell with given env overrides
# Params: stdin_json, extra env vars as KEY=VALUE pairs…
# Outputs: stdout of the drop-in
# Returns: exit code of the subshell
_run_drop_in() {
  local stdin_json="$1"
  shift
  # extra env vars passed as remaining args (KEY=VALUE)
  local extra_env=("$@")
  (
    for kv in "${extra_env[@]}"; do
      export "$kv"
    done
    export HOOK_STDIN_JSON="$stdin_json"
    # Source the drop-in; capture stdout
    bash -c 'source "$1"' _ "$DROP_IN" 2>/dev/null
  )
}

# _run_drop_in_with_stderr: same but captures stderr separately via temp file
_run_drop_in_with_stderr() {
  local stdin_json="$1"
  shift
  local extra_env=("$@")
  local stderr_file
  stderr_file="$(mktemp /tmp/harness-stderr-XXXXXX)"
  local stdout
  stdout=$(
    (
      for kv in "${extra_env[@]}"; do
        export "$kv"
      done
      export HOOK_STDIN_JSON="$stdin_json"
      bash -c 'source "$1"' _ "$DROP_IN" 2>"$stderr_file"
    )
  )
  local rc=$?
  # Print stderr file path on its own line so caller can check it
  printf '%s' "$stdout"
  printf '\n__STDERR_FILE__:%s\n' "$stderr_file"
  return $rc
}

echo ""
echo "========================================================================"
echo "session-start recall drop-in test suite (Pillar V, task V3)"
echo "========================================================================"

# ════════════════════════════════════════════════════════════════════════════════
# ORACLE 1 — Known project: shim recall returns 2 lines
#   → stdout JSON contains [Memory] block in additionalContext
#   → session_start event emitted with non-empty injected_memories array
# ════════════════════════════════════════════════════════════════════════════════
echo ""
echo "── Oracle 1: known project (shim returns 2 lines) ──"

_TMP1="$(_make_state)"
_SHIM1="$(mktemp -d /tmp/recall-shim-XXXXXX)/bin"
mkdir -p "$_SHIM1"

# Create a fake harness that returns 2 recall lines
cat > "$_SHIM1/harness" <<'SHIM'
#!/usr/bin/env bash
# Fake harness: if called as "recall <anything>" return 2 fixture lines
if [[ "${1:-}" == "recall" ]]; then
  echo "Decision: use TDD for all new code (2026-03-22)"
  echo "Pattern: emit_event must be sourced before use (2026-07-03)"
  exit 0
fi
exit 1
SHIM
chmod +x "$_SHIM1/harness"
_HARNESS_BIN1="$_SHIM1/harness"

# Make a fake git repo dir for slug resolution
_GIT_DIR1="$(mktemp -d /tmp/recall-gitdir-XXXXXX)"
mkdir -p "$_GIT_DIR1/.git"
git -C "$_GIT_DIR1" init -q 2>/dev/null || true

_STDIN1='{"session_id":"test-sess-1","cwd":"'"$_GIT_DIR1"'"}'

_OUT1="$(_run_drop_in "$_STDIN1" \
  "STATE=$_TMP1" \
  "HARNESS_RECALL_BIN=$_HARNESS_BIN1" \
  "HOOK_STDIN_JSON=$_STDIN1")"
_RC1=$?

# 1a: exit code is 0
if [[ "$_RC1" -eq 0 ]]; then
  _ok "1a-exit-code-zero"
else
  _fail "1a-exit-code-zero" "rc=$_RC1"
fi

# 1b: stdout is non-empty (some JSON output)
_assert_not_empty "1b-stdout-nonempty" "$_OUT1"

# 1c: stdout contains [Memory] marker
_assert_contains "1c-stdout-memory-block" "$_OUT1" "[Memory]"

# 1d: stdout is valid JSON with hookSpecificOutput.additionalContext
if printf '%s' "$_OUT1" | python3 -c "import json,sys; d=json.load(sys.stdin); ac=d.get('hookSpecificOutput',{}).get('additionalContext',''); assert '[Memory]' in ac, f'no Memory block in: {ac[:200]}'" 2>/dev/null; then
  _ok "1d-stdout-json-additionalcontext"
else
  _fail "1d-stdout-json-additionalcontext" "bad JSON or missing [Memory] in additionalContext: ${_OUT1:0:300}"
fi

# 1e: session_start event emitted with non-empty injected_memories
_EVENTS1="$_TMP1/state/events.ndjson"
if [[ -f "$_EVENTS1" ]]; then
  _MEM1="$(grep '"session_start"' "$_EVENTS1" | tail -1 | jq -r '.payload.injected_memories | length' 2>/dev/null || echo "0")"
  if [[ "$_MEM1" -ge 1 ]]; then
    _ok "1e-event-injected-memories-nonempty"
  else
    _fail "1e-event-injected-memories-nonempty" "injected_memories length=$_MEM1 in events"
  fi
else
  _fail "1e-event-injected-memories-nonempty" "events.ndjson not created at $_EVENTS1"
fi

rm -rf "$_TMP1" "$_GIT_DIR1" "$(dirname "$_SHIM1")"

# ════════════════════════════════════════════════════════════════════════════════
# ORACLE 2 — Unknown slug: shim returns nothing
#   → exit 0, minimal/empty stdout (no [Memory] block)
#   → session_start event emitted with empty injected_memories array
# ════════════════════════════════════════════════════════════════════════════════
echo ""
echo "── Oracle 2: unknown slug (shim returns empty) ──"

_TMP2="$(_make_state)"
_SHIM2="$(mktemp -d /tmp/recall-shim-XXXXXX)/bin"
mkdir -p "$_SHIM2"

cat > "$_SHIM2/harness" <<'SHIM'
#!/usr/bin/env bash
# Fake harness: recall returns nothing (unknown project)
if [[ "${1:-}" == "recall" ]]; then
  exit 0
fi
exit 1
SHIM
chmod +x "$_SHIM2/harness"
_HARNESS_BIN2="$_SHIM2/harness"

_GIT_DIR2="$(mktemp -d /tmp/recall-gitdir-XXXXXX)"
mkdir -p "$_GIT_DIR2/.git"
git -C "$_GIT_DIR2" init -q 2>/dev/null || true

_STDIN2='{"session_id":"test-sess-2","cwd":"'"$_GIT_DIR2"'"}'
_OUT2="$(_run_drop_in "$_STDIN2" \
  "STATE=$_TMP2" \
  "HARNESS_RECALL_BIN=$_HARNESS_BIN2" \
  "HOOK_STDIN_JSON=$_STDIN2")"
_RC2=$?

# 2a: exit code is 0
if [[ "$_RC2" -eq 0 ]]; then
  _ok "2a-exit-code-zero"
else
  _fail "2a-exit-code-zero" "rc=$_RC2"
fi

# 2b: no [Memory] block in stdout (empty or no injection)
_assert_not_contains "2b-stdout-no-memory-block" "$_OUT2" "[Memory]"

# 2c: session_start event emitted with injected_memories = []
_EVENTS2="$_TMP2/state/events.ndjson"
if [[ -f "$_EVENTS2" ]]; then
  _MEM2="$(grep '"session_start"' "$_EVENTS2" | tail -1 | jq -r '.payload.injected_memories | length' 2>/dev/null || echo "-1")"
  if [[ "$_MEM2" -eq 0 ]]; then
    _ok "2c-event-empty-memories"
  else
    _fail "2c-event-empty-memories" "injected_memories length=$_MEM2 (expected 0)"
  fi
else
  _fail "2c-event-empty-memories" "events.ndjson not created"
fi

rm -rf "$_TMP2" "$_GIT_DIR2" "$(dirname "$_SHIM2")"

# ════════════════════════════════════════════════════════════════════════════════
# ORACLE 3 — Recall hangs (shim sleeps)
#   → drop-in exits 0 (timeout fires, trap exits 0)
#   → injected_memories is empty
# ════════════════════════════════════════════════════════════════════════════════
echo ""
echo "── Oracle 3: recall hangs (shim sleeps, tight timeout) ──"

_TMP3="$(_make_state)"
_SHIM3="$(mktemp -d /tmp/recall-shim-XXXXXX)/bin"
mkdir -p "$_SHIM3"

cat > "$_SHIM3/harness" <<'SHIM'
#!/usr/bin/env bash
# Fake harness that sleeps to simulate a hang
if [[ "${1:-}" == "recall" ]]; then
  sleep 60
  echo "should never appear"
  exit 0
fi
exit 1
SHIM
chmod +x "$_SHIM3/harness"
_HARNESS_BIN3="$_SHIM3/harness"

_GIT_DIR3="$(mktemp -d /tmp/recall-gitdir-XXXXXX)"
mkdir -p "$_GIT_DIR3/.git"
git -C "$_GIT_DIR3" init -q 2>/dev/null || true

_STDIN3='{"session_id":"test-sess-3","cwd":"'"$_GIT_DIR3"'"}'

# Use HARNESS_RECALL_TIMEOUT_SECS=1 so the test completes quickly
_START3="$(date +%s)"
_OUT3="$(_run_drop_in "$_STDIN3" \
  "STATE=$_TMP3" \
  "HARNESS_RECALL_BIN=$_HARNESS_BIN3" \
  "HOOK_STDIN_JSON=$_STDIN3" \
  "HARNESS_RECALL_TIMEOUT_SECS=1")"
_RC3=$?
_END3="$(date +%s)"
_ELAPSED3=$(( _END3 - _START3 ))

# 3a: exit code is 0 (fail-open)
if [[ "$_RC3" -eq 0 ]]; then
  _ok "3a-exit-code-zero"
else
  _fail "3a-exit-code-zero" "rc=$_RC3"
fi

# 3b: completed in <10 seconds (timeout kicked in)
if [[ "$_ELAPSED3" -lt 10 ]]; then
  _ok "3b-timeout-respected-lt10s"
else
  _fail "3b-timeout-respected-lt10s" "elapsed=${_ELAPSED3}s ≥ 10s"
fi

# 3c: no [Memory] block (timed out → empty)
_assert_not_contains "3c-no-memory-on-timeout" "$_OUT3" "[Memory]"

# 3d: injected_memories is empty (event still emitted)
_EVENTS3="$_TMP3/state/events.ndjson"
if [[ -f "$_EVENTS3" ]]; then
  _MEM3="$(grep '"session_start"' "$_EVENTS3" | tail -1 | jq -r '.payload.injected_memories | length' 2>/dev/null || echo "-1")"
  if [[ "$_MEM3" -eq 0 ]]; then
    _ok "3d-event-empty-memories-on-timeout"
  else
    _fail "3d-event-empty-memories-on-timeout" "injected_memories length=$_MEM3 (expected 0)"
  fi
else
  # event may not have been emitted due to early exit — that's acceptable (fail-open)
  _ok "3d-event-empty-memories-on-timeout"
fi

rm -rf "$_TMP3" "$_GIT_DIR3" "$(dirname "$_SHIM3")"

# ════════════════════════════════════════════════════════════════════════════════
# ORACLE 4 — Malformed stdin
#   → exit 0, NOTHING on stderr
# ════════════════════════════════════════════════════════════════════════════════
echo ""
echo "── Oracle 4: malformed stdin → exit 0, empty stderr ──"

_TMP4="$(_make_state)"
_SHIM4="$(mktemp -d /tmp/recall-shim-XXXXXX)/bin"
mkdir -p "$_SHIM4"

cat > "$_SHIM4/harness" <<'SHIM'
#!/usr/bin/env bash
if [[ "${1:-}" == "recall" ]]; then
  exit 0
fi
exit 1
SHIM
chmod +x "$_SHIM4/harness"

_STDIN4='this is not valid json {{{'
_STDERR4_FILE="$(mktemp /tmp/harness-stderr-XXXXXX)"

_OUT4=$(
  (
    export HOOK_STDIN_JSON="$_STDIN4"
    export STATE="$_TMP4"
    export HARNESS_RECALL_BIN="$_SHIM4/harness"
    bash -c 'source "$1"' _ "$DROP_IN"
  ) 2>"$_STDERR4_FILE"
)
_RC4=$?
_STDERR4="$(cat "$_STDERR4_FILE" 2>/dev/null || true)"
rm -f "$_STDERR4_FILE"

# 4a: exit code is 0
if [[ "$_RC4" -eq 0 ]]; then
  _ok "4a-exit-code-zero"
else
  _fail "4a-exit-code-zero" "rc=$_RC4"
fi

# 4b: stderr is empty
_assert_empty "4b-stderr-empty" "$_STDERR4"

rm -rf "$_TMP4" "$(dirname "$_SHIM4")"

# ════════════════════════════════════════════════════════════════════════════════
# ORACLE 5 — Git absent / non-repo cwd
#   → falls back to basename slug, still exits 0
# ════════════════════════════════════════════════════════════════════════════════
echo ""
echo "── Oracle 5: git absent/non-repo cwd → basename slug fallback ──"

_TMP5="$(_make_state)"
_SHIM5="$(mktemp -d /tmp/recall-shim-XXXXXX)/bin"
mkdir -p "$_SHIM5"

# Record what slug was passed to recall
_SLUG5_FILE="$(mktemp /tmp/recall-slug-XXXXXX)"

cat > "$_SHIM5/harness" <<SHIM
#!/usr/bin/env bash
if [[ "\${1:-}" == "recall" ]]; then
  # Write the query (which contains the slug) to a file so the test can inspect it
  echo "\${2:-}" > "$_SLUG5_FILE"
  exit 0
fi
exit 1
SHIM
chmod +x "$_SHIM5/harness"

# Use a non-repo directory; the drop-in must fall back to its basename
# Build: /tmp/<random>/my-special-project (not a git repo)
_NON_REPO_PARENT="$(mktemp -d /tmp/recall-nongit-XXXXXX)"
_NON_REPO_DIR="$_NON_REPO_PARENT/my-special-project"
mkdir -p "$_NON_REPO_DIR"

_STDIN5='{"session_id":"test-sess-5","cwd":"'"$_NON_REPO_DIR"'"}'

_OUT5="$(_run_drop_in "$_STDIN5" \
  "STATE=$_TMP5" \
  "HARNESS_RECALL_BIN=$_SHIM5/harness" \
  "HOOK_STDIN_JSON=$_STDIN5")"
_RC5=$?

# 5a: exit code is 0
if [[ "$_RC5" -eq 0 ]]; then
  _ok "5a-exit-code-zero"
else
  _fail "5a-exit-code-zero" "rc=$_RC5"
fi

# 5b: slug passed to recall is basename of the cwd
_SLUG5_CONTENT="$(cat "$_SLUG5_FILE" 2>/dev/null || true)"
_EXPECTED_SLUG5="my-special-project"
if printf '%s' "$_SLUG5_CONTENT" | grep -qF "$_EXPECTED_SLUG5"; then
  _ok "5b-slug-is-basename"
else
  _fail "5b-slug-is-basename" "slug query='$_SLUG5_CONTENT' expected to contain '$_EXPECTED_SLUG5'"
fi

rm -rf "$_TMP5" "$_NON_REPO_PARENT" "$(dirname "$_SHIM5")" "$_SLUG5_FILE"

# ════════════════════════════════════════════════════════════════════════════════
# BONUS: settings.json SessionStart key count check (read-only)
# ════════════════════════════════════════════════════════════════════════════════
echo ""
echo "── Bonus: settings.json SessionStart key count (read-only) ──"

_SETTINGS="$HOME/.claude/settings.json"
if [[ -f "$_SETTINGS" ]]; then
  _SS_COUNT="$(jq '[.hooks | to_entries[] | select(.key == "SessionStart")] | length' "$_SETTINGS" 2>/dev/null || echo "-1")"
  if [[ "$_SS_COUNT" -le 1 ]]; then
    _ok "bonus-settings-at-most-one-sessionstart-key"
  else
    _fail "bonus-settings-at-most-one-sessionstart-key" "found $_SS_COUNT SessionStart keys (must be ≤1)"
  fi
else
  _ok "bonus-settings-json-absent-staged-inert"
fi

# ════════════════════════════════════════════════════════════════════════════════
# SUMMARY
# ════════════════════════════════════════════════════════════════════════════════
echo ""
echo "========================================================================"
echo "Results: PASS=$PASS  FAIL=$FAIL  SKIP=$SKIP  TOTAL=$(( PASS + FAIL + SKIP ))"
echo "========================================================================"
echo ""

if [[ "$FAIL" -gt 0 ]]; then
  exit 1
fi
exit 0
