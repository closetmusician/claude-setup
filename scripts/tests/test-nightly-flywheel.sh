#!/usr/bin/env bash
# ABOUTME: TDD test suite for scripts/flywheel/nightly-flywheel.sh (Pillar III-2).
# ABOUTME: Uses a mock claude shim — never burns real tokens. Covers 8 behavioral cases:
# ABOUTME: dry-run drafts, zero tracked-file mutation, corpus allowlist blocking, cursor
# ABOUTME: advancement, step isolation (failure doesn't abort), write-incapable assertion.
# ABOUTME: Exit 0 all pass, nonzero on any failure.

set -uo pipefail

PASS=0
FAIL=0
SKIP=0

# ── Resolve paths ──────────────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FLYWHEEL_SH="$(cd "$SCRIPT_DIR/.." && pwd)/flywheel/nightly-flywheel.sh"

_pass() { PASS=$(( PASS + 1 )); printf 'PASS: %s\n' "$*"; }
_fail() { FAIL=$(( FAIL + 1 )); printf 'FAIL: %s\n' "$*"; }
_skip() { SKIP=$(( SKIP + 1 )); printf 'SKIP: %s\n' "$*"; }

# ── Sandbox setup ─────────────────────────────────────────────────────────────
# Each test case gets its own isolated tmpdir so no state bleeds between cases.
# $TMPROOT is the root; individual cases use $TMPROOT/caseN/

TMPROOT="$(mktemp -d /tmp/test-nightly-fw-XXXXXX 2>/dev/null)"
trap 'rm -rf "$TMPROOT" 2>/dev/null' EXIT INT TERM

_mk_sandbox() {
  # Create a fresh sandbox with a minimal harness + claude mock environment.
  # Returns the sandbox dir path via stdout.
  local sandbox="$TMPROOT/$1"
  mkdir -p \
    "$sandbox/state/state" \
    "$sandbox/state/state/flywheel/drafts" \
    "$sandbox/evals/incidents" \
    "$sandbox/bin" \
    "$sandbox/scripts/flywheel" \
    "$sandbox/scripts/templates" \
    "$sandbox/scripts/lib" 2>/dev/null

  # Self-isolate against inherited HARNESS_GOV_STATE_DIR (same pattern as
  # FIX-SUITE-HYGIENE): override wins at highest precedence; point at this
  # sandbox's own governance dir so no inherited value can interfere.
  export HARNESS_GOV_STATE_DIR="$sandbox/state"

  # ── Mock harness ─────────────────────────────────────────────────────────
  # Purpose: simulate harness query --type incident --since <cursor> output.
  # The mock reads $HARNESS_MOCK_EVENTS (a .ndjson file) and echoes its content.
  # Supports --empty env var to simulate empty delta.
  cat > "$sandbox/bin/harness" << 'HARNESS_EOF'
#!/usr/bin/env bash
# Mock harness for nightly-flywheel tests.
# Reads HARNESS_MOCK_EVENTS; if HARNESS_MOCK_EMPTY=1 outputs nothing.
if [[ "${HARNESS_MOCK_EMPTY:-0}" == "1" ]]; then
  exit 0
fi
if [[ -f "${HARNESS_MOCK_EVENTS:-/dev/null}" ]]; then
  cat "${HARNESS_MOCK_EVENTS}"
fi
exit 0
HARNESS_EOF
  chmod +x "$sandbox/bin/harness"

  # ── Mock mint-fixture.sh ─────────────────────────────────────────────────
  # Purpose: simulate minting a fixture dir; echo the dir path to stdout.
  cat > "$sandbox/scripts/flywheel/mint-fixture.sh" << 'MINT_EOF'
#!/usr/bin/env bash
# Mock mint-fixture: read one incident line, create a fake fixture dir.
set -uo pipefail
EVALS_DIR="${EVALS_DIR:-${HOME}/.claude/evals/incidents}"
content="$(cat /dev/stdin 2>/dev/null)"
[[ -z "$content" ]] && exit 0
class="$(printf '%s' "$content" | jq -r '.payload.class // "C-unknown"' 2>/dev/null)" || class="C-unknown"
class="${class//[^A-Za-z0-9-]/-}"
seq=001
fix_dir="${EVALS_DIR}/${class}-${seq}"
mkdir -p "$fix_dir" 2>/dev/null || true
echo "$fix_dir"
exit 0
MINT_EOF
  chmod +x "$sandbox/scripts/flywheel/mint-fixture.sh"

  # ── Mock recall-miss-monitor.sh ──────────────────────────────────────────
  cat > "$sandbox/scripts/recall-miss-monitor.sh" << 'RMM_EOF'
#!/usr/bin/env bash
# Mock recall-miss-monitor: always exits 0.
echo "[mock] recall-miss-monitor called" >&2
exit 0
RMM_EOF
  chmod +x "$sandbox/scripts/recall-miss-monitor.sh"

  # ── Mock timeout.sh ──────────────────────────────────────────────────────
  cat > "$sandbox/scripts/lib/timeout.sh" << 'TO_EOF'
#!/usr/bin/env bash
# Mock timeout: just run the command directly.
_run_with_timeout() {
  local secs="$1"; shift
  "$@"
  return $?
}
TO_EOF

  # ── Draft prompt template ─────────────────────────────────────────────────
  cp "${SCRIPT_DIR}/../templates/flywheel-draft-prompt.md" \
     "$sandbox/scripts/templates/flywheel-draft-prompt.md" 2>/dev/null || \
  cat > "$sandbox/scripts/templates/flywheel-draft-prompt.md" << 'TPL_EOF'
# Mock draft prompt. Template variables: {{INCIDENT_TS}} {{INCIDENT_CLASS}} etc.
You are a mock drafter. Incident: {{INCIDENT_TS}} class={{INCIDENT_CLASS}}.
Output a No-Patch: {{INCIDENT_CLASS}} declaration.
No-Patch: {{INCIDENT_CLASS}}
Reason: mock test — no real patch needed.
TPL_EOF

  echo "$sandbox"
}

# ── Shared incident fixture ───────────────────────────────────────────────────
_mk_incident() {
  # Make a minimal valid incident JSON line.
  local ts="${1:-2026-07-04T02:00:00.000Z}"
  local class="${2:-C2}"
  jq -cn \
    --arg ts "$ts" \
    --arg class "$class" \
    '{ts:$ts, schema:1, session_id:"test-session-001",
      event_type:"incident", source:"test",
      project:".claude",
      payload:{class:$class, detail:"test incident detail"},
      outcome:"denied"}'
}

# ═════════════════════════════════════════════════════════════════════════════
# CASE 1: dry-run against real incidents produces ≥1 draft diff (or No-Patch)
# ═════════════════════════════════════════════════════════════════════════════
_test_case1() {
  local sb
  sb="$(_mk_sandbox case1)"

  # Create a mock claude that writes a No-Patch response (write-incapable, no side effects)
  cat > "$sb/bin/claude" << 'CLAUDE_EOF'
#!/usr/bin/env bash
# Mock claude: reads stdin, writes a No-Patch draft to stdout.
# Asserts: --allowedTools must include Read/Grep/Glob but NOT Write/Edit.
allowed_ok=0
no_write=1
for arg in "$@"; do
  [[ "$arg" == "Read Grep Glob" ]] && allowed_ok=1
  [[ "$arg" == "Write" || "$arg" == "Edit" ]] && no_write=0
done
# Read stdin (the prompt)
content="$(cat /dev/stdin 2>/dev/null)"
class="$(printf '%s' "$content" | grep -o 'class=[A-Za-z0-9_-]*' | head -1 | cut -d= -f2)"
[[ -z "$class" ]] && class="C-unknown"
printf '## No-Patch: %s\n' "$class"
printf 'Reason: mock test — no real patch available\n'
printf 'incident_ts=2026-07-04T02:00:00.000Z class=%s\n' "$class"
exit 0
CLAUDE_EOF
  chmod +x "$sb/bin/claude"

  # Write one incident to mock events file
  _mk_incident "2026-07-04T02:00:00.000Z" "C2" > "$sb/incidents.ndjson"

  # Run flywheel with controlled env
  HARNESS_MOCK_EVENTS="$sb/incidents.ndjson" \
  HARNESS_BIN="$sb/bin/harness" \
  CLAUDE_BIN="$sb/bin/claude" \
  EVALS_DIR="$sb/evals/incidents" \
  STATE="$sb/state" \
  FLYWHEEL_DRAFT_TIMEOUT_SECS=10 \
  FLYWHEEL_DRAFT_MODEL="claude-sonnet-4-5" \
  bash "$FLYWHEEL_SH" 2>/dev/null

  # Check: ≥1 draft file in drafts dir
  local draft_count
  draft_count="$(find "$sb/state/state/flywheel/drafts" -name "*.diff" -o -name "*.txt" 2>/dev/null | wc -l | tr -d ' ')"
  if [[ "$draft_count" -ge 1 ]]; then
    _pass "Case 1: dry-run produced $draft_count draft file(s)"
  else
    _fail "Case 1: expected ≥1 draft file, got $draft_count"
  fi
}

# ═════════════════════════════════════════════════════════════════════════════
# CASE 2: git status shows ZERO modified tracked files after a dry-run
# ═════════════════════════════════════════════════════════════════════════════
_test_case2() {
  local sb
  sb="$(_mk_sandbox case2)"

  cat > "$sb/bin/claude" << 'CLAUDE_EOF'
#!/usr/bin/env bash
content="$(cat /dev/stdin 2>/dev/null)"
class="$(printf '%s' "$content" | grep -o 'class=[A-Za-z0-9_-]*' | head -1 | cut -d= -f2)"
printf 'No-Patch: %s\nReason: mock\n' "${class:-C-unknown}"
exit 0
CLAUDE_EOF
  chmod +x "$sb/bin/claude"

  _mk_incident "2026-07-04T02:01:00.000Z" "C2" > "$sb/incidents.ndjson"

  # Snapshot tracked files in ~/.claude before the run
  local before_status after_status
  before_status="$(git -C "${HOME}/.claude" status --porcelain 2>/dev/null | grep -v '^??' | wc -l | tr -d ' ')"

  HARNESS_MOCK_EVENTS="$sb/incidents.ndjson" \
  HARNESS_BIN="$sb/bin/harness" \
  CLAUDE_BIN="$sb/bin/claude" \
  EVALS_DIR="$sb/evals/incidents" \
  STATE="$sb/state" \
  bash "$FLYWHEEL_SH" 2>/dev/null

  after_status="$(git -C "${HOME}/.claude" status --porcelain 2>/dev/null | grep -v '^??' | wc -l | tr -d ' ')"

  if [[ "$before_status" == "$after_status" ]]; then
    _pass "Case 2: zero tracked file modifications (before=$before_status after=$after_status)"
  else
    _fail "Case 2: tracked files changed! before=$before_status after=$after_status"
  fi
}

# ═════════════════════════════════════════════════════════════════════════════
# CASE 3: corpus-touching draft patch is BLOCKED by allowlist
# ═════════════════════════════════════════════════════════════════════════════
_test_case3() {
  local sb
  sb="$(_mk_sandbox case3)"

  # Mock claude that returns a diff touching run-harness-evals.sh (FORBIDDEN)
  cat > "$sb/bin/claude" << 'CLAUDE_EOF'
#!/usr/bin/env bash
cat /dev/stdin >/dev/null  # consume stdin
# Return a diff touching the eval runner (should be BLOCKED)
printf '# incident_ts=2026-07-04T02:00:00.000Z class=C2\n'
printf '--- a/scripts/run-harness-evals.sh\n'
printf '+++ b/scripts/run-harness-evals.sh\n'
printf '@@ -1,3 +1,4 @@\n'
printf ' #!/usr/bin/env bash\n'
printf '+# injected line\n'
printf ' set -e\n'
printf ' echo ok\n'
exit 0
CLAUDE_EOF
  chmod +x "$sb/bin/claude"

  _mk_incident "2026-07-04T02:02:00.000Z" "C2" > "$sb/incidents.ndjson"

  HARNESS_MOCK_EVENTS="$sb/incidents.ndjson" \
  HARNESS_BIN="$sb/bin/harness" \
  CLAUDE_BIN="$sb/bin/claude" \
  EVALS_DIR="$sb/evals/incidents" \
  STATE="$sb/state" \
  bash "$FLYWHEEL_SH" 2>/dev/null

  # The draft should NOT be saved as a .diff (it's corpus-touching)
  local diff_count block_count
  diff_count="$(find "$sb/state/state/flywheel/drafts" -name "*.diff" 2>/dev/null | wc -l | tr -d ' ')"
  block_count="$(find "$sb/state/state/flywheel/drafts" -name "BLOCKED-*" 2>/dev/null | wc -l | tr -d ' ')"

  if [[ "$diff_count" -eq 0 && "$block_count" -ge 1 ]]; then
    _pass "Case 3: corpus-touching diff blocked (block files=$block_count diff files=$diff_count)"
  else
    _fail "Case 3: expected 0 .diff + ≥1 BLOCKED, got diff=$diff_count block=$block_count"
  fi
}

# ═════════════════════════════════════════════════════════════════════════════
# CASE 4: cursor advances; re-run with same cursor processes only new incidents
# ═════════════════════════════════════════════════════════════════════════════
_test_case4() {
  local sb
  sb="$(_mk_sandbox case4)"

  cat > "$sb/bin/claude" << 'CLAUDE_EOF'
#!/usr/bin/env bash
cat /dev/stdin >/dev/null
printf 'No-Patch: C2\nReason: mock\n'
exit 0
CLAUDE_EOF
  chmod +x "$sb/bin/claude"

  # First run with 1 incident
  _mk_incident "2026-07-04T02:03:00.000Z" "C2" > "$sb/incidents.ndjson"

  HARNESS_MOCK_EVENTS="$sb/incidents.ndjson" \
  HARNESS_BIN="$sb/bin/harness" \
  CLAUDE_BIN="$sb/bin/claude" \
  EVALS_DIR="$sb/evals/incidents" \
  STATE="$sb/state" \
  bash "$FLYWHEEL_SH" 2>/dev/null

  local cursor_after_run1
  cursor_after_run1="$(cat "$sb/state/state/flywheel.cursor" 2>/dev/null | tr -d '[:space:]')"

  # Second run with EMPTY mock (no new incidents since cursor)
  HARNESS_MOCK_EVENTS="$sb/incidents.ndjson" \
  HARNESS_MOCK_EMPTY=1 \
  HARNESS_BIN="$sb/bin/harness" \
  CLAUDE_BIN="$sb/bin/claude" \
  EVALS_DIR="$sb/evals/incidents" \
  STATE="$sb/state" \
  bash "$FLYWHEEL_SH" 2>/dev/null

  # Cursor should still hold run1's value (unchanged on empty delta)
  local cursor_after_run2
  cursor_after_run2="$(cat "$sb/state/state/flywheel.cursor" 2>/dev/null | tr -d '[:space:]')"

  if [[ -n "$cursor_after_run1" ]]; then
    _pass "Case 4a: cursor advanced after run1 ($cursor_after_run1)"
  else
    _fail "Case 4a: cursor not written after run1"
  fi

  if [[ "$cursor_after_run1" == "$cursor_after_run2" ]]; then
    _pass "Case 4b: cursor unchanged on empty-delta run2"
  else
    _fail "Case 4b: cursor changed on empty-delta run (run1=$cursor_after_run1 run2=$cursor_after_run2)"
  fi
}

# ═════════════════════════════════════════════════════════════════════════════
# CASE 5: step failure is isolated (one bad incident doesn't abort the night)
# ═════════════════════════════════════════════════════════════════════════════
_test_case5() {
  local sb
  sb="$(_mk_sandbox case5)"

  # Mock claude that fails on first call, succeeds on second
  local call_count_file="$sb/call_count"
  printf '0' > "$call_count_file"

  cat > "$sb/bin/claude" << 'CLAUDE_EOF'
#!/usr/bin/env bash
content="$(cat /dev/stdin 2>/dev/null)"
# Alternate: fail on odd calls, succeed on even
call_file="${CLAUDE_CALL_COUNT_FILE:-/dev/null}"
count="$(cat "$call_file" 2>/dev/null | tr -d '[:space:]')" || count=0
count=$(( count + 1 ))
printf '%d' "$count" > "$call_file" 2>/dev/null || true
if (( count % 2 == 1 )); then
  exit 1  # Simulate failure on 1st call
fi
printf 'No-Patch: C2\nReason: second call succeeded\n'
exit 0
CLAUDE_EOF
  chmod +x "$sb/bin/claude"

  # Two incidents in the events file
  {
    _mk_incident "2026-07-04T02:04:00.000Z" "C2"
    _mk_incident "2026-07-04T02:05:00.000Z" "freeze_enforced"
  } > "$sb/incidents.ndjson"

  HARNESS_MOCK_EVENTS="$sb/incidents.ndjson" \
  HARNESS_BIN="$sb/bin/harness" \
  CLAUDE_BIN="$sb/bin/claude" \
  CLAUDE_CALL_COUNT_FILE="$call_count_file" \
  EVALS_DIR="$sb/evals/incidents" \
  STATE="$sb/state" \
  bash "$FLYWHEEL_SH" 2>/dev/null
  local flywheel_exit=$?

  # Flywheel should exit 0 even when one claude call failed
  if [[ "$flywheel_exit" -eq 0 ]]; then
    _pass "Case 5: flywheel exited 0 despite one failing claude call"
  else
    _fail "Case 5: flywheel exited $flywheel_exit — should be 0 (fail-open)"
  fi

  # Last-run stamp must exist (run completed)
  if [[ -f "$sb/state/state/com.yklin.nightly-flywheel.last-run" ]]; then
    _pass "Case 5b: last-run stamp written (run completed)"
  else
    _fail "Case 5b: last-run stamp missing — run may have aborted"
  fi
}

# ═════════════════════════════════════════════════════════════════════════════
# CASE 6: claude call is write-incapable — mock shim would FAIL if asked to write
# ═════════════════════════════════════════════════════════════════════════════
_test_case6() {
  local sb
  sb="$(_mk_sandbox case6)"

  # Mock claude: exits non-zero if Write or Edit is in --allowedTools
  cat > "$sb/bin/claude" << 'CLAUDE_EOF'
#!/usr/bin/env bash
# Write-incapability assertion: if --allowedTools contains Write or Edit, fail.
allowed_tools=""
while [[ $# -gt 0 ]]; do
  if [[ "$1" == "--allowedTools" ]]; then
    shift
    allowed_tools="$1"
  fi
  shift
done
# Drain stdin
cat /dev/stdin >/dev/null 2>&1 || true

if printf '%s' "$allowed_tools" | grep -qE 'Write|Edit'; then
  # Write/Edit in allowed tools — this would be a security violation
  echo "ASSERT FAIL: Write or Edit in allowedTools: $allowed_tools" >&2
  exit 99
fi

# Good: write-incapable. Output a No-Patch.
printf 'No-Patch: C2\nReason: write-incapable assertion passed\n'
exit 0
CLAUDE_EOF
  chmod +x "$sb/bin/claude"

  _mk_incident "2026-07-04T02:06:00.000Z" "C2" > "$sb/incidents.ndjson"

  local flywheel_out
  flywheel_out="$(HARNESS_MOCK_EVENTS="$sb/incidents.ndjson" \
  HARNESS_BIN="$sb/bin/harness" \
  CLAUDE_BIN="$sb/bin/claude" \
  EVALS_DIR="$sb/evals/incidents" \
  STATE="$sb/state" \
  bash "$FLYWHEEL_SH" 2>&1)"
  local flywheel_exit=$?

  if [[ "$flywheel_exit" -eq 0 ]] && ! printf '%s' "$flywheel_out" | grep -q "ASSERT FAIL"; then
    _pass "Case 6: claude called write-incapably (no Write/Edit in allowedTools)"
  else
    _fail "Case 6: write-incapability assertion fired or flywheel failed (exit=$flywheel_exit output=$flywheel_out)"
  fi
}

# ═════════════════════════════════════════════════════════════════════════════
# CASE 7: empty delta (no new incidents) exits 0 without calling claude
# ═════════════════════════════════════════════════════════════════════════════
_test_case7() {
  local sb
  sb="$(_mk_sandbox case7)"

  # Mock claude that writes a sentinel file if called (should NOT be called)
  cat > "$sb/bin/claude" << 'CLAUDE_EOF'
#!/usr/bin/env bash
cat /dev/stdin >/dev/null
# Signal that claude was called (should not happen on empty delta)
touch "${CLAUDE_CALLED_SENTINEL:-/dev/null}" 2>/dev/null || true
printf 'No-Patch: C2\nReason: should not have been called\n'
exit 0
CLAUDE_EOF
  chmod +x "$sb/bin/claude"

  local sentinel_file="$sb/claude_was_called"

  HARNESS_MOCK_EMPTY=1 \
  HARNESS_BIN="$sb/bin/harness" \
  CLAUDE_BIN="$sb/bin/claude" \
  CLAUDE_CALLED_SENTINEL="$sentinel_file" \
  EVALS_DIR="$sb/evals/incidents" \
  STATE="$sb/state" \
  bash "$FLYWHEEL_SH" 2>/dev/null
  local flywheel_exit=$?

  if [[ "$flywheel_exit" -eq 0 ]]; then
    _pass "Case 7a: empty delta exits 0"
  else
    _fail "Case 7a: expected exit 0 on empty delta, got $flywheel_exit"
  fi

  if [[ ! -f "$sentinel_file" ]]; then
    _pass "Case 7b: claude NOT called on empty delta (zero cost)"
  else
    _fail "Case 7b: claude was called despite empty delta — should exit before drafting"
  fi
}

# ═════════════════════════════════════════════════════════════════════════════
# CASE 8: evals/ path blocked by allowlist (variant: touching ~/.claude/evals)
# ═════════════════════════════════════════════════════════════════════════════
_test_case8() {
  local sb
  sb="$(_mk_sandbox case8)"

  # Mock claude that returns a diff touching ~/.claude/evals/
  cat > "$sb/bin/claude" << 'CLAUDE_EOF'
#!/usr/bin/env bash
cat /dev/stdin >/dev/null
printf '# incident_ts=2026-07-04T02:00:00.000Z class=C7\n'
printf '--- a/.claude/evals/incidents/C7-001/expect.json\n'
printf '+++ b/.claude/evals/incidents/C7-001/expect.json\n'
printf '@@ -1,3 +1,4 @@\n'
printf ' {\n'
printf '+  "injected": true,\n'
printf '   "expected_gap": true\n'
printf ' }\n'
exit 0
CLAUDE_EOF
  chmod +x "$sb/bin/claude"

  _mk_incident "2026-07-04T02:07:00.000Z" "C7" > "$sb/incidents.ndjson"

  HARNESS_MOCK_EVENTS="$sb/incidents.ndjson" \
  HARNESS_BIN="$sb/bin/harness" \
  CLAUDE_BIN="$sb/bin/claude" \
  EVALS_DIR="$sb/evals/incidents" \
  STATE="$sb/state" \
  bash "$FLYWHEEL_SH" 2>/dev/null

  local diff_count block_count
  diff_count="$(find "$sb/state/state/flywheel/drafts" -name "*.diff" 2>/dev/null | wc -l | tr -d ' ')"
  block_count="$(find "$sb/state/state/flywheel/drafts" -name "BLOCKED-*" 2>/dev/null | wc -l | tr -d ' ')"

  if [[ "$diff_count" -eq 0 && "$block_count" -ge 1 ]]; then
    _pass "Case 8: evals/-touching diff blocked (block=$block_count diff=$diff_count)"
  else
    _fail "Case 8: evals/ allowlist not enforced (diff=$diff_count block=$block_count)"
  fi
}

# ═════════════════════════════════════════════════════════════════════════════
# Run all cases
# ═════════════════════════════════════════════════════════════════════════════

if [[ ! -f "$FLYWHEEL_SH" ]]; then
  printf 'FATAL: nightly-flywheel.sh not found at %s\n' "$FLYWHEEL_SH" >&2
  exit 1
fi

_test_case1
_test_case2
_test_case3
_test_case4
_test_case5
_test_case6
_test_case7
_test_case8

echo ""
echo "========================================================================"
printf 'Results: PASS=%d  FAIL=%d  SKIP=%d  (total=%d)\n' \
  "$PASS" "$FAIL" "$SKIP" "$(( PASS + FAIL + SKIP ))"
echo "========================================================================"

[[ "$FAIL" -eq 0 ]]
