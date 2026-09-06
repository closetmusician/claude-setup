#!/usr/bin/env bash
# ABOUTME: TDD test suite for scripts/lib/autonomous-registry.sh (VII-7 meta-safety).
# ABOUTME: RED pass: source fails or functions absent → all cases fail intentionally.
# ABOUTME: Tests: register→is_registered, unregistered, deregister, reset, corrupt fail-safe.
# ABOUTME: Also documents the negative-integration stub for VII-1 push-guard (see bottom).
# ABOUTME: Run: bash test-autonomous-registry.sh

set -uo pipefail

LIB_DIR="$(cd "$(dirname "$0")/.." && pwd)/lib"
REGISTRY_LIB="${LIB_DIR}/autonomous-registry.sh"

PASS=0
FAIL=0
ERRORS=""

# ── Isolated state dir so tests never touch real ~/.claude/state ──────────────
TMPDIR_TEST="$(mktemp -d /tmp/test-autonomous-registry.XXXXXX)"
export STATE="${TMPDIR_TEST}"

cleanup() {
  rm -rf "${TMPDIR_TEST}"
}
trap cleanup EXIT

# ── Helpers ───────────────────────────────────────────────────────────────────

assert_eq() {
  local name="$1" expected="$2" actual="$3"
  if [[ "$actual" == "$expected" ]]; then
    PASS=$((PASS + 1))
  else
    FAIL=$((FAIL + 1))
    ERRORS="${ERRORS}\n  FAIL: ${name} — expected '${expected}', got '${actual}'"
  fi
}

assert_exit_0() {
  local name="$1"
  shift
  if "$@" >/dev/null 2>&1; then
    PASS=$((PASS + 1))
  else
    FAIL=$((FAIL + 1))
    ERRORS="${ERRORS}\n  FAIL: ${name} — expected exit 0, got nonzero"
  fi
}

assert_exit_nonzero() {
  local name="$1"
  shift
  if "$@" >/dev/null 2>&1; then
    FAIL=$((FAIL + 1))
    ERRORS="${ERRORS}\n  FAIL: ${name} — expected nonzero exit, got 0"
  else
    PASS=$((PASS + 1))
  fi
}

# Source the library (will fail if file absent — RED phase)
# shellcheck source=/dev/null
source "${REGISTRY_LIB}" 2>/dev/null || true

# ── Case 1: register then is_registered returns 0 ─────────────────────────────
echo "--- Case 1: register → is_registered exits 0 ---"
(
  export STATE="${TMPDIR_TEST}/case1"
  mkdir -p "${STATE}"
  source "${REGISTRY_LIB}"
  autonomous_registry_register "lane-001" "task-T101" '{"run":"nightly"}'
  autonomous_registry_is_registered "lane-001"
)
RC=$?
assert_eq "register→is_registered exit code" "0" "$RC"

# ── Case 2: unregistered id returns nonzero ────────────────────────────────────
echo "--- Case 2: unregistered id → nonzero ---"
(
  export STATE="${TMPDIR_TEST}/case2"
  mkdir -p "${STATE}"
  source "${REGISTRY_LIB}"
  autonomous_registry_is_registered "lane-BOGUS"
)
RC=$?
if [[ "$RC" -ne 0 ]]; then
  PASS=$((PASS + 1))
else
  FAIL=$((FAIL + 1))
  ERRORS="${ERRORS}\n  FAIL: unregistered id — expected nonzero, got 0"
fi

# ── Case 3: deregister makes it unregistered ──────────────────────────────────
echo "--- Case 3: register → deregister → is_registered exits nonzero ---"
(
  export STATE="${TMPDIR_TEST}/case3"
  mkdir -p "${STATE}"
  source "${REGISTRY_LIB}"
  autonomous_registry_register "lane-002" "task-T102"
  autonomous_registry_deregister "lane-002"
  autonomous_registry_is_registered "lane-002"
)
RC=$?
if [[ "$RC" -ne 0 ]]; then
  PASS=$((PASS + 1))
else
  FAIL=$((FAIL + 1))
  ERRORS="${ERRORS}\n  FAIL: deregister — expected nonzero after deregister, got 0"
fi

# ── Case 4: reset clears all entries ──────────────────────────────────────────
echo "--- Case 4: register two lanes → reset → both unregistered ---"
(
  export STATE="${TMPDIR_TEST}/case4"
  mkdir -p "${STATE}"
  source "${REGISTRY_LIB}"
  autonomous_registry_register "lane-A" "task-TA"
  autonomous_registry_register "lane-B" "task-TB"
  autonomous_registry_reset
  # Both must be unregistered
  autonomous_registry_is_registered "lane-A" && exit 0  # means FAIL — still registered
  autonomous_registry_is_registered "lane-B" && exit 0  # means FAIL — still registered
  exit 1  # means PASS — neither registered
)
RC=$?
if [[ "$RC" -ne 0 ]]; then
  PASS=$((PASS + 1))
else
  FAIL=$((FAIL + 1))
  ERRORS="${ERRORS}\n  FAIL: reset — lanes still registered after reset"
fi

# ── Case 5: corrupt registry file → is_registered returns nonzero (fail-safe) ─
echo "--- Case 5: corrupt registry → is_registered nonzero (fail-safe) ---"
(
  export STATE="${TMPDIR_TEST}/case5"
  mkdir -p "${STATE}"
  # Write deliberately corrupt JSON
  printf 'NOT_JSON{{{corrupt' > "${STATE}/autonomous-registry.json"
  source "${REGISTRY_LIB}"
  autonomous_registry_is_registered "lane-any"
)
RC=$?
if [[ "$RC" -ne 0 ]]; then
  PASS=$((PASS + 1))
else
  FAIL=$((FAIL + 1))
  ERRORS="${ERRORS}\n  FAIL: corrupt registry — expected nonzero (fail-safe), got 0"
fi

# ── Case 6: register returns a non-empty token ────────────────────────────────
echo "--- Case 6: register returns non-empty token ---"
(
  export STATE="${TMPDIR_TEST}/case6"
  mkdir -p "${STATE}"
  source "${REGISTRY_LIB}"
  TOKEN=$(autonomous_registry_register "lane-tok" "task-tok" '{"meta":"x"}')
  [[ -n "$TOKEN" ]]
)
RC=$?
assert_eq "register returns non-empty token" "0" "$RC"

# ── Case 7: is_registered accepts session_id field as alternative lookup ───────
echo "--- Case 7: session_id lookup after register with session metadata ---"
(
  export STATE="${TMPDIR_TEST}/case7"
  mkdir -p "${STATE}"
  source "${REGISTRY_LIB}"
  autonomous_registry_register "lane-s1" "task-s1" '{"session_id":"sess-abc-999"}'
  # Lookup by lane_id must still work
  autonomous_registry_is_registered "lane-s1"
)
RC=$?
assert_eq "session_id-bearing entry: lane lookup" "0" "$RC"

# ── Case 8: session_id must survive metadata round-trip (regression: ${3:-{}} brace bug) ──
echo "--- Case 8: lookup BY session_id after register with metadata ---"
(
  export STATE="${TMPDIR_TEST}/case8"
  mkdir -p "${STATE}"
  source "${REGISTRY_LIB}"
  autonomous_registry_register "lane-s2" "task-s2" '{"session_id":"sess-xyz-777"}'
  # Registry JSON must hold the exact session_id (stray-brace bug corrupted it to empty)
  autonomous_registry_is_registered "sess-xyz-777"
)
RC=$?
assert_eq "session_id lookup round-trip" "0" "$RC"

# ── SUMMARY ───────────────────────────────────────────────────────────────────
echo ""
echo "=============================="
echo "Results: ${PASS} passed, ${FAIL} failed"
if [[ -n "${ERRORS}" ]]; then
  printf '%b\n' "${ERRORS}"
fi
echo "=============================="

# ── NEGATIVE INTEGRATION STUB (for VII-1 push-guard builder) ─────────────────
#
# VII-1 (autonomous-push-guard.sh) must perform this exact check:
#
#   PLANE SEPARATOR — registry-primary (CON-13):
#
#     # Step 1: env-var fast-path hint
#     [[ -z "${AUTONOMOUS_RUN:-}" ]] && exit 0
#
#     # Step 2: registry membership is authoritative
#     STATE="${STATE:-$HOME/.claude/state}"
#     source "$(dirname "$0")/lib/autonomous-registry.sh"
#     autonomous_registry_is_registered "${SESSION_ID:-}" || exit 0
#
#   Semantics:
#   - AUTONOMOUS_RUN unset   → exit 0 immediately (interactive path; zero overhead)
#   - AUTONOMOUS_RUN set + SESSION_ID not in registry → spoofed env; exit 0 (deny privilege)
#   - AUTONOMOUS_RUN set + SESSION_ID in registry → legitimate autonomous plane; proceed
#
#   Negative test the VII-1 builder MUST add to test-autonomous-push-guard.sh:
#     export AUTONOMOUS_RUN=1
#     export SESSION_ID="unregistered-session-xyz"
#     # Do NOT call autonomous_registry_register
#     result=$(echo '{"tool_input":{"command":"git push origin main"}}' \
#              | AUTONOMOUS_RUN=1 SESSION_ID=unregistered-session-xyz \
#                STATE=<empty-registry-dir> \
#                bash scripts/autonomous-push-guard.sh)
#     # Guard must exit 0 (treat as interactive / no block decision emitted)
#     # — i.e. AUTONOMOUS_RUN=1 alone is NOT sufficient to trigger the guard.
#
# ─────────────────────────────────────────────────────────────────────────────

[[ $FAIL -eq 0 ]]
