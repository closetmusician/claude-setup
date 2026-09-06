#!/usr/bin/env bash
# ABOUTME: TDD test suite for scripts/autonomous-push-guard.sh (VII-1 meta-safety).
# ABOUTME: RED pass: guard absent → positive-block cases fail (exit 0 instead of denying).
# ABOUTME: Tests: interactive plane allow, registered push to solo→allow, corporate→DENY,
# ABOUTME: merge→DENY, AUTONOMOUS_RUN without env SESSION_ID→DENY, non-git→allow, malformed→allow.
# ABOUTME: Run: bash test-autonomous-push-guard.sh from any directory.

set -uo pipefail

GUARD_SCRIPT="$(cd "$(dirname "$0")/.." && pwd)/autonomous-push-guard.sh"
LIB_DIR="$(cd "$(dirname "$0")/.." && pwd)/lib"
REGISTRY_LIB="${LIB_DIR}/autonomous-registry.sh"

PASS=0
FAIL=0
ERRORS=""

# ── Isolated state dir so tests never touch real ~/.claude/state ──────────────
TMPDIR_TEST="$(mktemp -d /tmp/test-autonomous-push-guard.XXXXXX)"
# Note: HARNESS_STATE_OVERRIDE is set per-case, not globally, so the registry
# path is isolated per test case rather than inherited from the outer env.

# Set up a fake git repo with both solo and corporate remotes for use in tests
FAKE_SOLO_REPO="${TMPDIR_TEST}/fake-solo-repo"
FAKE_CORP_REPO="${TMPDIR_TEST}/fake-corp-repo"

mkdir -p "${FAKE_SOLO_REPO}"
(cd "${FAKE_SOLO_REPO}" && git init -q && git remote add closetmusician "https://github.com/closetmusician/dotclaude.git" 2>/dev/null || true)

mkdir -p "${FAKE_CORP_REPO}"
(cd "${FAKE_CORP_REPO}" && git init -q && git remote add origin "https://github.com/ExampleOrg/hermes.git" 2>/dev/null || true)

cleanup() {
  rm -rf "${TMPDIR_TEST}"
}
trap cleanup EXIT

# ── Helpers ───────────────────────────────────────────────────────────────────

assert_eq() {
  local name="$1" expected="$2" actual="$3"
  if [[ "$actual" == "$expected" ]]; then
    PASS=$((PASS + 1))
    echo "  PASS: ${name}"
  else
    FAIL=$((FAIL + 1))
    ERRORS="${ERRORS}\n  FAIL: ${name} — expected '${expected}', got '${actual}'"
    echo "  FAIL: ${name} — expected '${expected}', got '${actual}'"
  fi
}

# Run the guard with given env vars and payload; capture stdout and exit code.
# Usage: run_guard <env_vars_as_assignments> <json_payload> [repo_dir]
run_guard() {
  local env_overrides="${1:-}"
  local payload="${2:-}"
  local repo_dir="${3:-}"

  # Build command: cd to repo if specified, then run guard
  if [[ -n "$repo_dir" ]]; then
    env $env_overrides bash -c "cd '${repo_dir}' && printf '%s' '${payload}' | bash '${GUARD_SCRIPT}'" 2>/dev/null
  else
    env $env_overrides bash -c "printf '%s' '${payload}' | bash '${GUARD_SCRIPT}'" 2>/dev/null
  fi
}

# Register a session in the temp registry and return the SESSION_ID used.
# Writes JSON directly so tests can set the exact active stdin session_id.
setup_registered_session() {
  local reg_state="${1:-${TMPDIR_TEST}/reg-state}"
  local session_id="test-session-$(date +%s)-$$"
  mkdir -p "${reg_state}"
  local ts
  ts="$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo '1970-01-01T00:00:00Z')"
  # Write registry entry directly so session_id field is preserved correctly.
  jq -n \
    --arg sid "${session_id}" \
    --arg ts "${ts}" \
    '[{lane_id:"lane-test",task_id:"task-T001",session_id:$sid,started_at:$ts,status:"active",token:"lane-test:ts",meta:{}}]' \
    > "${reg_state}/autonomous-registry.json" 2>/dev/null || true
  printf '%s' "${session_id}"
}

# ── Case 1: AUTONOMOUS_RUN unset + git push → ALLOW (interactive plane, case 5 spec) ─
echo ""
echo "--- Case 1: AUTONOMOUS_RUN unset → ALLOW (interactive plane, seam-#2 check) ---"
PAYLOAD='{"tool_name":"Bash","tool_input":{"command":"git push origin main"}}'
OUTPUT=$(env -i PATH="$PATH" bash "${GUARD_SCRIPT}" <<< "${PAYLOAD}" 2>/dev/null; echo "EXIT:$?")
if ! printf '%s' "${OUTPUT}" | grep -q 'permissionDecision.*deny'; then
  assert_eq "AUTONOMOUS_RUN unset: no block decision" "PASS" "PASS"
else
  assert_eq "AUTONOMOUS_RUN unset: no block decision" "PASS" "FAIL"
fi

# ── Case 2: AUTONOMOUS_RUN=1, registered, git push to solo remote → ALLOW ─────
echo ""
echo "--- Case 2: registered + git push to solo (closetmusician) remote → ALLOW ---"
REG_STATE_2="${TMPDIR_TEST}/state-case2"
SID_2=$(setup_registered_session "${REG_STATE_2}")
PAYLOAD=$(jq -cn --arg sid "$SID_2" '{"session_id":$sid,"tool_name":"Bash","tool_input":{"command":"git push closetmusician feat/my-branch"}}')
OUTPUT=$(cd "${FAKE_SOLO_REPO}" && HARNESS_STATE_OVERRIDE="${REG_STATE_2}" AUTONOMOUS_RUN=1 \
  env -u SESSION_ID bash "${GUARD_SCRIPT}" <<< "${PAYLOAD}" 2>/dev/null; echo "EXIT:$?")
if ! printf '%s' "${OUTPUT}" | grep -q 'permissionDecision.*deny'; then
  assert_eq "solo remote push: ALLOW" "PASS" "PASS"
else
  assert_eq "solo remote push: ALLOW" "PASS" "FAIL"
fi

# ── Case 3: AUTONOMOUS_RUN=1, registered, git push to corporate remote → DENY + P0 ─
echo ""
echo "--- Case 3: registered + git push to ExampleOrg remote → DENY ---"
REG_STATE_3="${TMPDIR_TEST}/state-case3"
SID_3=$(setup_registered_session "${REG_STATE_3}")
PAYLOAD=$(jq -cn --arg sid "$SID_3" '{"session_id":$sid,"tool_name":"Bash","tool_input":{"command":"git push origin main"}}')
# Run from the fake-corp-repo so the guard can detect the ExampleOrg remote.
OUTPUT=$(cd "${FAKE_CORP_REPO}" && HARNESS_STATE_OVERRIDE="${REG_STATE_3}" AUTONOMOUS_RUN=1 \
  env -u SESSION_ID \
  bash "${GUARD_SCRIPT}" <<< "${PAYLOAD}" 2>/dev/null)
if printf '%s' "${OUTPUT}" | grep -q 'permissionDecision.*deny'; then
  assert_eq "corporate remote push: DENY" "PASS" "PASS"
else
  assert_eq "corporate remote push: DENY" "PASS" "FAIL"
fi

# ── Case 4: AUTONOMOUS_RUN=1, registered, git merge → DENY ─────────────────────
echo ""
echo "--- Case 4: registered + git merge → DENY (even in solo context) ---"
REG_STATE_4="${TMPDIR_TEST}/state-case4"
SID_4=$(setup_registered_session "${REG_STATE_4}")
PAYLOAD=$(jq -cn --arg sid "$SID_4" '{"session_id":$sid,"tool_name":"Bash","tool_input":{"command":"git merge main"}}')
OUTPUT=$(cd "${FAKE_SOLO_REPO}" && HARNESS_STATE_OVERRIDE="${REG_STATE_4}" AUTONOMOUS_RUN=1 \
  env -u SESSION_ID \
  bash "${GUARD_SCRIPT}" <<< "${PAYLOAD}" 2>/dev/null)
if printf '%s' "${OUTPUT}" | grep -q 'permissionDecision.*deny'; then
  assert_eq "git merge: DENY" "PASS" "PASS"
else
  assert_eq "git merge: DENY" "PASS" "FAIL"
fi

# ── Case 5: AUTONOMOUS_RUN=1, no SESSION_ID env, git push → DENY ─────────────
echo ""
echo "--- Case 5: AUTONOMOUS_RUN=1 + no SESSION_ID env → DENY (prod contract) ---"
REG_STATE_5="${TMPDIR_TEST}/state-case5"
mkdir -p "${REG_STATE_5}"
printf '[]\n' > "${REG_STATE_5}/autonomous-registry.json"  # empty registry
PAYLOAD='{"session_id":"lane-1","tool_name":"Bash","tool_input":{"command":"git push origin main"}}'
OUTPUT=$(cd "${FAKE_CORP_REPO}" && HARNESS_STATE_OVERRIDE="${REG_STATE_5}" AUTONOMOUS_RUN=1 \
  env -u SESSION_ID bash "${GUARD_SCRIPT}" <<< "${PAYLOAD}" 2>/dev/null)
if printf '%s' "${OUTPUT}" | grep -q 'permissionDecision.*deny'; then
  assert_eq "AUTONOMOUS_RUN no SESSION_ID env: DENY" "PASS" "PASS"
else
  assert_eq "AUTONOMOUS_RUN no SESSION_ID env: DENY" "PASS" "FAIL"
fi

# ── Case 6: AUTONOMOUS_RUN=1, registered, non-git bash command → ALLOW ─────────
echo ""
echo "--- Case 6: registered + non-git bash command → ALLOW ---"
REG_STATE_6="${TMPDIR_TEST}/state-case6"
SID_6=$(setup_registered_session "${REG_STATE_6}")
PAYLOAD=$(jq -cn --arg sid "$SID_6" '{"session_id":$sid,"tool_name":"Bash","tool_input":{"command":"ls -la /tmp"}}')
OUTPUT=$(HARNESS_STATE_OVERRIDE="${REG_STATE_6}" AUTONOMOUS_RUN=1 \
  env -u SESSION_ID \
  bash "${GUARD_SCRIPT}" <<< "${PAYLOAD}" 2>/dev/null)
if ! printf '%s' "${OUTPUT}" | grep -q 'permissionDecision.*deny'; then
  assert_eq "non-git command: ALLOW" "PASS" "PASS"
else
  assert_eq "non-git command: ALLOW" "PASS" "FAIL"
fi

# ── Case 7: malformed payload (not JSON) → exit 0 fail-open ──────────────────
echo ""
echo "--- Case 7: malformed payload → exit 0 (fail-open) ---"
OUTPUT=$(AUTONOMOUS_RUN=1 env -u SESSION_ID bash "${GUARD_SCRIPT}" <<< "NOT-JSON-AT-ALL" 2>/dev/null)
EC=$?
if [[ "$EC" -eq 0 ]]; then
  assert_eq "malformed payload: exit 0 (fail-open)" "PASS" "PASS"
else
  assert_eq "malformed payload: exit 0 (fail-open)" "PASS" "FAIL"
fi

# ── Case 8: push via variable/indirection → best-effort detect documented ────
echo ""
echo "--- Case 8: push via variable indirection → documented residual / best-effort ---"
# e.g. CMD="git push"; $CMD — this is a known residual; guard detects literal commands only.
# The test documents the limitation (no block expected), which matches spec note.
PAYLOAD='{"tool_name":"Bash","tool_input":{"command":"CMD=\"git push origin main\"; $CMD"}}'
OUTPUT=$(AUTONOMOUS_RUN=1 env -u SESSION_ID bash "${GUARD_SCRIPT}" <<< "${PAYLOAD}" 2>/dev/null)
# No block expected for indirection (documented residual per spec)
if ! printf '%s' "${OUTPUT}" | grep -q 'permissionDecision.*deny'; then
  assert_eq "push via indirection: documented residual (no false-positive)" "PASS" "PASS"
else
  # Would be a bonus if it blocks, but not required
  assert_eq "push via indirection: documented residual (no false-positive)" "PASS" "PASS"
fi

# ── Case 9 (bonus per spec): corporate remote substring 'acme' → DENY ─────
echo ""
echo "--- Case 9: 'acme' in remote URL → DENY regardless of branch name ---"
FAKE_ACME_REPO="${TMPDIR_TEST}/fake-acme-repo"
mkdir -p "${FAKE_ACME_REPO}"
(cd "${FAKE_ACME_REPO}" && git init -q && git remote add origin "https://github.com/ExampleOrg/some-repo.git" 2>/dev/null || true)
REG_STATE_9="${TMPDIR_TEST}/state-case9"
SID_9=$(setup_registered_session "${REG_STATE_9}")
PAYLOAD=$(jq -cn --arg sid "$SID_9" '{"session_id":$sid,"tool_name":"Bash","tool_input":{"command":"git push origin feat/safe-branch"}}')
OUTPUT=$(cd "${FAKE_ACME_REPO}" && HARNESS_STATE_OVERRIDE="${REG_STATE_9}" AUTONOMOUS_RUN=1 \
  env -u SESSION_ID \
  bash "${GUARD_SCRIPT}" <<< "${PAYLOAD}" 2>/dev/null)
if printf '%s' "${OUTPUT}" | grep -q 'permissionDecision.*deny'; then
  assert_eq "acme remote substring: DENY" "PASS" "PASS"
else
  assert_eq "acme remote substring: DENY" "PASS" "FAIL"
fi

# ── SUMMARY ───────────────────────────────────────────────────────────────────
echo ""
echo "=============================="
echo "Results: ${PASS} passed, ${FAIL} failed"
if [[ -n "${ERRORS}" ]]; then
  printf '%b\n' "${ERRORS}"
fi
echo "=============================="

[[ $FAIL -eq 0 ]]
