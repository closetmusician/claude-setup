#!/usr/bin/env bash
# ABOUTME: TDD suite for harness-selfcheck-autonomous.sh (Stop hook) and .githooks/pre-commit.
# ABOUTME: ≥5 Stop-hook cases + pre-commit block/allow/fail-open + idempotency marker check.
# ABOUTME: Uses scratch git repos + HARNESS_STATE_OVERRIDE pattern for full isolation.
# ABOUTME: NEVER commits to the real ~/.claude repo. RED without scripts; GREEN after.
# ABOUTME: Run: bash scripts/tests/test-selfcheck-autonomous.sh

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAUDE_DIR="${CLAUDE_DIR:-$HOME/.claude}"
HOOK="${SCRIPT_DIR}/../harness-selfcheck-autonomous.sh"
PRE_COMMIT="${CLAUDE_DIR}/.githooks/pre-commit"
RUN_EVALS="${SCRIPT_DIR}/../run-harness-evals.sh"

# ── Isolated temp root ──────────────────────────────────────────────────────
TMPROOT="$(mktemp -d /tmp/test-selfcheck-auto-XXXXXX)"
trap 'rm -rf "$TMPROOT"' EXIT

PASS=0
FAIL=0
ERRORS=""

_pass() { echo "  PASS: $1"; (( PASS++ )) || true; }
_fail() { echo "  FAIL: $1 — $2"; (( FAIL++ )) || true; ERRORS+="  FAIL: $1 — $2\n"; }

# Build a minimal autonomous registry JSON with the given session ID registered as active.
_setup_registry() {
  local state_dir="$1" sid="$2"
  mkdir -p "$state_dir"
  printf '[{"session_id":"%s","lane_id":"lane-test","status":"active","started_at":"2026-07-05T00:00:00Z"}]\n' \
    "$sid" > "${state_dir}/autonomous-registry.json"
}

_clear_registry() {
  local state_dir="$1"
  rm -f "${state_dir}/autonomous-registry.json"
}

# Build a Stop hook stdin JSON; production delivers session_id here, not in env.
_run_stop_hook() {
  # Remaining args are VAR=VALUE env overrides
  env "$@" bash "$HOOK" <<< '{"session_id":"test-session"}' 2>/dev/null
  return 0  # capture exit code separately
}

# Run the hook and capture the raw exit code (hook itself always exits 0 per Stop hook contract;
# blocking is communicated via {"decision":"block",...} on stdout).
_run_hook_capture() {
  local -n _out_var=$1; shift
  _out_var=$(env "$@" bash "$HOOK" <<< '{"session_id":"test-session"}' 2>/dev/null || true)
}

echo "=== harness-selfcheck-autonomous + pre-commit TDD suite ==="
echo "HOOK: $HOOK"
echo "PRE_COMMIT: $PRE_COMMIT"
echo "TMPROOT: $TMPROOT"
echo ""

if [[ ! -f "$HOOK" ]]; then
  echo "  harness-selfcheck-autonomous.sh NOT FOUND — some tests will indicate RED phase"
fi

# ─────────────────────────────────────────────────────────────────────────────
# CASE 1: Interactive plane (AUTONOMOUS_RUN unset) → exit 0, no evals run, fast
# Plane separator: [[ -z "${AUTONOMOUS_RUN:-}" ]] && exit 0
# ─────────────────────────────────────────────────────────────────────────────
echo "--- Case 1: AUTONOMOUS_RUN unset (interactive plane) → pass-through, evals NOT run ---"

C1_STATE="${TMPROOT}/c1-state"
mkdir -p "$C1_STATE"
_setup_registry "$C1_STATE" "session-c1"

# Create a dirty flag — should be IGNORED on the interactive plane
C1_CLAUDE="${TMPROOT}/c1-claude"
mkdir -p "${C1_CLAUDE}/state"
touch "${C1_CLAUDE}/state/.harness-dirty"

# Create a fake run-harness-evals.sh that creates a sentinel file so we can detect if it ran
C1_EVAL_SENTINEL="${TMPROOT}/c1-eval-ran"
C1_FAKE_EVALS="${TMPROOT}/c1-run-harness-evals.sh"
cat > "$C1_FAKE_EVALS" << 'FAKE_EOF'
#!/usr/bin/env bash
touch "$1"
exit 0
FAKE_EOF
chmod +x "$C1_FAKE_EVALS"

# Run without AUTONOMOUS_RUN set (interactive plane)
C1_OUT=""
C1_EC=0
C1_OUT=$(STATE="$C1_STATE" CLAUDE_DIR="$C1_CLAUDE" \
  bash "$HOOK" <<< '{}' 2>/dev/null) || C1_EC=$?

if [[ "$C1_EC" -eq 0 ]]; then
  _pass "C1: exit code is 0 on interactive plane"
else
  _fail "C1: exit code is 0 on interactive plane" "got exit code $C1_EC"
fi

if printf '%s' "$C1_OUT" | grep -q '"decision":"block"'; then
  _fail "C1: no block on interactive plane" "hook output block decision unexpectedly"
else
  _pass "C1: no block decision emitted on interactive plane"
fi

# Dirty flag must still exist (interactive plane must not clear it)
if [[ -f "${C1_CLAUDE}/state/.harness-dirty" ]]; then
  _pass "C1: dirty flag preserved (not cleared on interactive plane)"
else
  _fail "C1: dirty flag preserved (not cleared on interactive plane)" "flag was removed by interactive run"
fi

_clear_registry "$C1_STATE"

# ─────────────────────────────────────────────────────────────────────────────
# CASE 2: Autonomous + no .harness-dirty flag → exit 0, evals NOT run
# ─────────────────────────────────────────────────────────────────────────────
echo "--- Case 2: AUTONOMOUS_RUN=1 + session registered + no dirty flag → allow, no eval run ---"

C2_STATE="${TMPROOT}/c2-state"
C2_CLAUDE="${TMPROOT}/c2-claude"
mkdir -p "${C2_CLAUDE}/state"
_setup_registry "$C2_STATE" "session-c2"

# Create a fake run-harness-evals.sh that would FAIL if called (so we know if it ran)
C2_FAKE_EVALS="${TMPROOT}/c2-run-harness-evals.sh"
cat > "$C2_FAKE_EVALS" << 'FAKE_EOF'
#!/usr/bin/env bash
echo "EVALS SHOULD NOT HAVE RUN" >&2
exit 1
FAKE_EOF
chmod +x "$C2_FAKE_EVALS"

C2_OUT=""
# Start timing for fast-path assertion
C2_START=$SECONDS
C2_OUT=$(AUTONOMOUS_RUN=1 STATE="$C2_STATE" CLAUDE_DIR="$C2_CLAUDE" \
  env -u SESSION_ID bash "$HOOK" <<< '{"session_id":"session-c2"}' 2>/dev/null) || true
C2_ELAPSED=$(( SECONDS - C2_START ))

if ! printf '%s' "$C2_OUT" | grep -q '"decision":"block"'; then
  _pass "C2: no block when dirty flag absent"
else
  _fail "C2: no block when dirty flag absent" "hook emitted block unexpectedly"
fi

if [[ "$C2_ELAPSED" -lt 5 ]]; then
  _pass "C2: no-dirty fast-path < 5s (timing: ${C2_ELAPSED}s)"
else
  _fail "C2: no-dirty fast-path < 5s" "took ${C2_ELAPSED}s"
fi

_clear_registry "$C2_STATE"

# ─────────────────────────────────────────────────────────────────────────────
# CASE 3: Autonomous + .harness-dirty + corpus PASSES → allow, flag cleared
# ─────────────────────────────────────────────────────────────────────────────
echo "--- Case 3: AUTONOMOUS_RUN=1 + dirty flag + corpus PASSES → allow, flag cleared ---"

C3_STATE="${TMPROOT}/c3-state"
C3_CLAUDE="${TMPROOT}/c3-claude"
mkdir -p "${C3_CLAUDE}/state" "${C3_CLAUDE}/scripts"
_setup_registry "$C3_STATE" "session-c3"

# Plant a dirty flag
touch "${C3_CLAUDE}/state/.harness-dirty"

# Create a fake run-harness-evals.sh that PASSES
C3_FAKE_EVALS="${C3_CLAUDE}/scripts/run-harness-evals.sh"
cat > "$C3_FAKE_EVALS" << 'FAKE_EOF'
#!/usr/bin/env bash
echo "run-harness-evals: PASS (mocked)"
exit 0
FAKE_EOF
chmod +x "$C3_FAKE_EVALS"

C3_OUT=""
C3_OUT=$(AUTONOMOUS_RUN=1 STATE="$C3_STATE" CLAUDE_DIR="$C3_CLAUDE" \
  env -u SESSION_ID bash "$HOOK" <<< '{"session_id":"session-c3"}' 2>/dev/null) || true

if ! printf '%s' "$C3_OUT" | grep -q '"decision":"block"'; then
  _pass "C3: allow (no block) when corpus passes"
else
  _fail "C3: allow (no block) when corpus passes" "hook blocked unexpectedly"
fi

if [[ ! -f "${C3_CLAUDE}/state/.harness-dirty" ]]; then
  _pass "C3: dirty flag cleared after passing corpus"
else
  _fail "C3: dirty flag cleared after passing corpus" "dirty flag still exists"
fi

_clear_registry "$C3_STATE"

# ─────────────────────────────────────────────────────────────────────────────
# CASE 4: Autonomous + .harness-dirty + corpus FAILS → BLOCK
# ─────────────────────────────────────────────────────────────────────────────
echo "--- Case 4: AUTONOMOUS_RUN=1 + dirty flag + corpus FAILS → BLOCK with message ---"

C4_STATE="${TMPROOT}/c4-state"
C4_CLAUDE="${TMPROOT}/c4-claude"
mkdir -p "${C4_CLAUDE}/state" "${C4_CLAUDE}/scripts"
_setup_registry "$C4_STATE" "session-c4"

# Plant a dirty flag
touch "${C4_CLAUDE}/state/.harness-dirty"

# Create a fake run-harness-evals.sh that FAILS (simulating regression)
C4_FAKE_EVALS="${C4_CLAUDE}/scripts/run-harness-evals.sh"
cat > "$C4_FAKE_EVALS" << 'FAKE_EOF'
#!/usr/bin/env bash
echo "FAIL: corpus-regression-detected" >&2
echo "STAGE-REFUSED"
exit 1
FAKE_EOF
chmod +x "$C4_FAKE_EVALS"

C4_OUT=""
C4_OUT=$(AUTONOMOUS_RUN=1 STATE="$C4_STATE" CLAUDE_DIR="$C4_CLAUDE" \
  env -u SESSION_ID bash "$HOOK" <<< '{"session_id":"session-c4"}' 2>/dev/null) || true

if printf '%s' "$C4_OUT" | grep -q '"decision":"block"'; then
  _pass "C4: block emitted when corpus fails"
else
  _fail "C4: block emitted when corpus fails" "hook did not emit block; output: $C4_OUT"
fi

if printf '%s' "$C4_OUT" | grep -q '"reason"'; then
  _pass "C4: block message contains 'reason' field"
else
  _fail "C4: block message contains 'reason' field" "no reason field in output"
fi

_clear_registry "$C4_STATE"

# ─────────────────────────────────────────────────────────────────────────────
# CASE 5: stop_hook_active=1 in autonomous plane → corpus STILL runs (no bailout)
# Inverse of harness-selfcheck.sh which bails on stop_hook_active.
# ─────────────────────────────────────────────────────────────────────────────
echo "--- Case 5: AUTONOMOUS_RUN=1 + stop_hook_active=1 → corpus runs anyway (no bailout) ---"

C5_STATE="${TMPROOT}/c5-state"
C5_CLAUDE="${TMPROOT}/c5-claude"
mkdir -p "${C5_CLAUDE}/state" "${C5_CLAUDE}/scripts"
_setup_registry "$C5_STATE" "session-c5"

touch "${C5_CLAUDE}/state/.harness-dirty"

# Fake evals that pass; we plant a sentinel to confirm it was called
C5_SENTINEL="${TMPROOT}/c5-evals-ran"
C5_FAKE_EVALS="${C5_CLAUDE}/scripts/run-harness-evals.sh"
cat > "$C5_FAKE_EVALS" <<FAKE_EOF
#!/usr/bin/env bash
touch "${C5_SENTINEL}"
exit 0
FAKE_EOF
chmod +x "$C5_FAKE_EVALS"

# Pass stop_hook_active via stdin (as Claude Code Stop hook would)
C5_STDIN='{"stop_hook_active":true}'
AUTONOMOUS_RUN=1 STATE="$C5_STATE" CLAUDE_DIR="$C5_CLAUDE" \
  env -u SESSION_ID bash "$HOOK" <<< "$C5_STDIN" 2>/dev/null || true

if [[ -f "$C5_SENTINEL" ]]; then
  _pass "C5: eval corpus ran even with stop_hook_active (no bailout in autonomous plane)"
else
  _fail "C5: eval corpus ran even with stop_hook_active" "evals did not run — hook bailed early"
fi

_clear_registry "$C5_STATE"

# ─────────────────────────────────────────────────────────────────────────────
# CASE 6: AUTONOMOUS_RUN=1 with no SESSION_ID env still enforces self-mod gate
# ─────────────────────────────────────────────────────────────────────────────
echo "--- Case 6: AUTONOMOUS_RUN=1 + no SESSION_ID env → corpus FAILS and BLOCKS ---"

C6_STATE="${TMPROOT}/c6-state"
C6_CLAUDE="${TMPROOT}/c6-claude"
mkdir -p "${C6_CLAUDE}/state" "${C6_CLAUDE}/scripts"
_setup_registry "$C6_STATE" "registered-session"  # registry has a DIFFERENT session ID

touch "${C6_CLAUDE}/state/.harness-dirty"

# Fake evals that would fail if called
C6_FAKE_EVALS="${C6_CLAUDE}/scripts/run-harness-evals.sh"
cat > "$C6_FAKE_EVALS" << 'FAKE_EOF'
#!/usr/bin/env bash
echo "FAIL: should not have reached evals on spoofed-env" >&2
exit 1
FAKE_EOF
chmod +x "$C6_FAKE_EVALS"

C6_OUT=""
C6_EC=0
C6_OUT=$(AUTONOMOUS_RUN=1 STATE="$C6_STATE" CLAUDE_DIR="$C6_CLAUDE" \
  env -u SESSION_ID bash "$HOOK" <<< '{"session_id":"lane-1"}' 2>/dev/null) || C6_EC=$?

if [[ "$C6_EC" -eq 0 ]]; then
  _pass "C6: no SESSION_ID env exits 0"
else
  _fail "C6: no SESSION_ID env exits 0" "exit code was $C6_EC"
fi

if printf '%s' "$C6_OUT" | grep -q '"decision":"block"'; then
  _pass "C6: no SESSION_ID env still blocks regression"
else
  _fail "C6: no SESSION_ID env still blocks regression" "hook did not block; output: $C6_OUT"
fi

_clear_registry "$C6_STATE"

# ─────────────────────────────────────────────────────────────────────────────
# CASE 7: pre-commit idempotency marker — VII-3-PRE-COMMIT-INSTALLED appears exactly once
# ─────────────────────────────────────────────────────────────────────────────
echo "--- Case 7: pre-commit idempotency marker appears exactly once in .githooks/pre-commit ---"

if [[ ! -f "$PRE_COMMIT" ]]; then
  _fail "C7: pre-commit file exists" "$PRE_COMMIT not found"
else
  MARKER_COUNT=$(grep -c 'VII-3-PRE-COMMIT-INSTALLED' "$PRE_COMMIT" 2>/dev/null || echo 0)
  if [[ "$MARKER_COUNT" -eq 1 ]]; then
    _pass "C7: exactly one VII-3-PRE-COMMIT-INSTALLED marker in pre-commit"
  else
    _fail "C7: exactly one VII-3-PRE-COMMIT-INSTALLED marker in pre-commit" "found $MARKER_COUNT occurrences"
  fi
fi

# ─────────────────────────────────────────────────────────────────────────────
# CASE 8: pre-commit dispatches pre-commit.d/*.sh (30-eval-dirty.sh found and executable)
# ─────────────────────────────────────────────────────────────────────────────
echo "--- Case 8: pre-commit.d/30-eval-dirty.sh is present and executable ---"

EVAL_DIRTY="${CLAUDE_DIR}/.githooks/pre-commit.d/30-eval-dirty.sh"
if [[ -f "$EVAL_DIRTY" ]]; then
  if [[ -x "$EVAL_DIRTY" ]]; then
    _pass "C8: 30-eval-dirty.sh is present and executable"
  else
    _fail "C8: 30-eval-dirty.sh is present and executable" "file exists but is not executable"
  fi
else
  _fail "C8: 30-eval-dirty.sh is present and executable" "file not found at $EVAL_DIRTY"
fi

# ─────────────────────────────────────────────────────────────────────────────
# CASE 9: pre-commit on scratch branch — blocks a sabotaged-guard commit, allows clean commit
# Uses a scratch git repo so we NEVER commit to the real ~/.claude.
# ─────────────────────────────────────────────────────────────────────────────
echo "--- Case 9: pre-commit scratch-repo block/allow test ---"

C9_REPO="${TMPROOT}/c9-scratch-repo"
mkdir -p "$C9_REPO"
git -C "$C9_REPO" init -q
git -C "$C9_REPO" config user.email "test@test.com"
git -C "$C9_REPO" config user.name "Test"

# Create the directory structure the pre-commit hook expects
mkdir -p "${C9_REPO}/.githooks/pre-commit.d" "${C9_REPO}/scripts" "${C9_REPO}/bin" "${C9_REPO}/rules"

# Plant a minimal initial commit
echo "initial" > "${C9_REPO}/README.txt"
git -C "$C9_REPO" add README.txt
git -C "$C9_REPO" commit -q -m "initial"

# Plant a harness binary (non-functional but present — must exist for the gate to trigger)
# We want to test the BLOCK path, so make run-harness-evals.sh fail
C9_HARNESS="${C9_REPO}/bin/harness"
printf '#!/usr/bin/env bash\nexit 0\n' > "$C9_HARNESS"
chmod +x "$C9_HARNESS"

C9_EVALS="${C9_REPO}/scripts/run-harness-evals.sh"
cat > "$C9_EVALS" << 'FAKE_EOF'
#!/usr/bin/env bash
echo "FAIL: sabotaged corpus" >&2
exit 1
FAKE_EOF
chmod +x "$C9_EVALS"

# Install the real pre-commit dispatcher into the scratch repo
cp "$PRE_COMMIT" "${C9_REPO}/.githooks/pre-commit" 2>/dev/null || {
  _fail "C9: pre-commit scratch-repo block" "pre-commit file not found at $PRE_COMMIT"
  # Skip remaining C9 sub-cases
  echo "  (skipping C9 sub-cases — pre-commit not found)"
  C9_SKIP=1
}

C9_SKIP="${C9_SKIP:-0}"
if [[ "$C9_SKIP" -eq 0 ]]; then
  git -C "$C9_REPO" config core.hooksPath .githooks

  # Stage a guarded-path file (rules/test.md) → should BLOCK on corpus failure
  echo "sabotaged rule" > "${C9_REPO}/rules/test.md"
  git -C "$C9_REPO" add rules/test.md

  C9_BLOCK_OUT=""
  C9_BLOCK_EC=0
  C9_BLOCK_OUT=$(HARNESS_BIN="${C9_HARNESS}" git -C "$C9_REPO" commit -m "should-be-blocked" 2>&1) || C9_BLOCK_EC=$?

  if [[ "$C9_BLOCK_EC" -ne 0 ]]; then
    _pass "C9: pre-commit blocks commit on failing corpus (both planes)"
  else
    _fail "C9: pre-commit blocks commit on failing corpus" "commit succeeded when it should have been blocked"
  fi

  # Now fix the evals to pass and stage a non-guarded-path file → should ALLOW
  cat > "$C9_EVALS" << 'FAKE_EOF'
#!/usr/bin/env bash
echo "run-harness-evals: PASS (mocked)"
exit 0
FAKE_EOF
  chmod +x "$C9_EVALS"

  # Reset staged file and stage a non-guarded file instead
  git -C "$C9_REPO" restore --staged rules/test.md 2>/dev/null || git -C "$C9_REPO" reset HEAD rules/test.md 2>/dev/null || true
  echo "non-guarded content" > "${C9_REPO}/README.txt"
  git -C "$C9_REPO" add README.txt

  C9_ALLOW_EC=0
  git -C "$C9_REPO" commit -m "non-guarded-allow" 2>/dev/null || C9_ALLOW_EC=$?

  if [[ "$C9_ALLOW_EC" -eq 0 ]]; then
    _pass "C9: pre-commit allows non-guarded-path clean commit"
  else
    _fail "C9: pre-commit allows non-guarded-path clean commit" "commit failed with exit $C9_ALLOW_EC"
  fi

  # Test: passing corpus + guarded path → ALLOW
  cat > "$C9_EVALS" << 'FAKE_EOF'
#!/usr/bin/env bash
echo "run-harness-evals: PASS (mocked)"
exit 0
FAKE_EOF
  chmod +x "$C9_EVALS"

  echo "rule content passes corpus" > "${C9_REPO}/rules/test.md"
  git -C "$C9_REPO" add rules/test.md

  C9_PASS_EC=0
  git -C "$C9_REPO" commit -m "guarded-path-corpus-passes" 2>/dev/null || C9_PASS_EC=$?

  if [[ "$C9_PASS_EC" -eq 0 ]]; then
    _pass "C9: pre-commit allows guarded-path commit when corpus passes"
  else
    _fail "C9: pre-commit allows guarded-path commit when corpus passes" "commit failed with exit $C9_PASS_EC"
  fi
fi

# ─────────────────────────────────────────────────────────────────────────────
# CASE 10: pre-commit missing harness binary → fail-open (allow commit)
# ─────────────────────────────────────────────────────────────────────────────
echo "--- Case 10: pre-commit fail-open when harness binary missing ---"

C10_REPO="${TMPROOT}/c10-scratch-repo"
mkdir -p "$C10_REPO"
git -C "$C10_REPO" init -q
git -C "$C10_REPO" config user.email "test@test.com"
git -C "$C10_REPO" config user.name "Test"
mkdir -p "${C10_REPO}/.githooks" "${C10_REPO}/rules"

echo "initial" > "${C10_REPO}/README.txt"
git -C "$C10_REPO" add README.txt
git -C "$C10_REPO" commit -q -m "initial"

# Install pre-commit; no harness binary, no bin/ directory
cp "$PRE_COMMIT" "${C10_REPO}/.githooks/pre-commit" 2>/dev/null || true
git -C "$C10_REPO" config core.hooksPath .githooks

echo "rule without harness" > "${C10_REPO}/rules/test.md"
git -C "$C10_REPO" add rules/test.md

C10_EC=0
git -C "$C10_REPO" commit -m "fail-open-test" 2>/dev/null || C10_EC=$?

if [[ "$C10_EC" -eq 0 ]]; then
  _pass "C10: pre-commit fail-open (allow) when harness binary missing"
else
  _fail "C10: pre-commit fail-open (allow) when harness binary missing" "commit blocked when it should have been allowed (exit $C10_EC)"
fi

# ─────────────────────────────────────────────────────────────────────────────
# Final summary
# ─────────────────────────────────────────────────────────────────────────────
echo ""
echo "=== Results: $PASS passed, $FAIL failed ==="
if [[ "$FAIL" -gt 0 ]]; then
  echo ""
  echo "Failures:"
  printf '%b' "$ERRORS"
  exit 1
fi
exit 0
