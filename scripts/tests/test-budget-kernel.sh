#!/usr/bin/env bash
# ABOUTME: TDD test suite for scripts/lib/budget-kernel.sh — the VII-2 budget enforcement library.
# ABOUTME: ≥7 cases covering prerequisites, night reset, task counter caps, quota detection,
# ABOUTME: kill-switch integration, and cap-constant drift guard.
# ABOUTME: Run: bash scripts/tests/test-budget-kernel.sh — cases must be RED before implementation.
# ABOUTME: Defensive: sources kill-switch from lib if present; falls back to sentinel write.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB="${SCRIPT_DIR}/../lib/budget-kernel.sh"

# ── Isolated temp STATE (never the real one) ─────────────────────────────────
TMPROOT="$(mktemp -d /tmp/test-budget-XXXXXX)"
export STATE="$TMPROOT/governance"
mkdir -p "$STATE"

PASS=0
FAIL=0

_pass() { echo "  PASS: $*"; (( PASS++ )) || true; }
_fail() { echo "  FAIL: $*"; (( FAIL++ )) || true; }

_load() {
  # shellcheck source=/dev/null
  source "$LIB" 2>/dev/null || true
}

_fresh_state() {
  # Reset night counter and freeze sentinel between tests
  rm -f "$STATE/.night-task-count" || true
  rm -f "$STATE/.AUTONOMOUS_FREEZE" || true
  # Write a minimal budget-night.json dir if needed
  rm -f "$STATE/budget-night.json" || true
}

_freeze_sentinel() {
  echo "$STATE/.AUTONOMOUS_FREEZE"
}

echo "=== test-budget-kernel.sh (VII-2) ==="
echo "LIB=$LIB"
echo "STATE=$STATE"
echo ""

# ─────────────────────────────────────────────────────────────────────────────
# Case 1: prerequisites ok when state dir is writable and kill-switch not tripped
# ─────────────────────────────────────────────────────────────────────────────
echo "[1] prerequisites ok: writable state dir, no freeze sentinel"
_fresh_state
_load
if budget_check_prerequisites 2>/dev/null; then
  _pass "prerequisites returns 0 when conditions ok"
else
  _fail "prerequisites should return 0 when state dir writable and no freeze — got nonzero"
fi

# ─────────────────────────────────────────────────────────────────────────────
# Case 2: prerequisites fail when kill-switch is tripped (freeze sentinel present)
# ─────────────────────────────────────────────────────────────────────────────
echo "[2] prerequisites fail when kill-switch is tripped"
_fresh_state
# Plant the freeze sentinel (as kill-switch.sh would do)
echo "manual: test-tripped" > "$STATE/.AUTONOMOUS_FREEZE"
_load
if budget_check_prerequisites 2>/dev/null; then
  _fail "prerequisites should return nonzero when freeze sentinel present — got 0"
else
  _pass "prerequisites returns nonzero when kill-switch tripped"
fi

# ─────────────────────────────────────────────────────────────────────────────
# Case 3: night_reset zeroes the counter
# ─────────────────────────────────────────────────────────────────────────────
echo "[3] night_reset zeroes the counter"
_fresh_state
_load
# Seed a stale count
echo "2" > "$STATE/.night-task-count"
budget_night_reset 2>/dev/null || true
COUNT=$(cat "$STATE/.night-task-count" 2>/dev/null || echo "missing")
if [ "$COUNT" = "0" ]; then
  _pass "night_reset wrote 0 to counter file"
else
  _fail "night_reset should set counter to 0, got: $COUNT"
fi

# ─────────────────────────────────────────────────────────────────────────────
# Case 4a: task_start 1 succeeds (counter goes from 0 to 1)
# ─────────────────────────────────────────────────────────────────────────────
echo "[4a] task_start 1 succeeds"
_fresh_state
_load
if budget_task_start "task-1" 2>/dev/null; then
  COUNT=$(cat "$STATE/.night-task-count" 2>/dev/null || echo "missing")
  if [ "$COUNT" = "1" ]; then
    _pass "task_start 1 succeeded; counter=1"
  else
    _fail "task_start 1 succeeded but counter=$COUNT (expected 1)"
  fi
else
  _fail "task_start for task 1 should succeed (return 0), got nonzero"
fi

# ─────────────────────────────────────────────────────────────────────────────
# Case 4b: task_start 2 succeeds (counter goes from 1 to 2)
# ─────────────────────────────────────────────────────────────────────────────
echo "[4b] task_start 2 succeeds"
# Counter already at 1 from case 4a — re-source and continue
_load
if budget_task_start "task-2" 2>/dev/null; then
  COUNT=$(cat "$STATE/.night-task-count" 2>/dev/null || echo "missing")
  if [ "$COUNT" = "2" ]; then
    _pass "task_start 2 succeeded; counter=2"
  else
    _fail "task_start 2 succeeded but counter=$COUNT (expected 2)"
  fi
else
  _fail "task_start for task 2 should succeed (return 0), got nonzero"
fi

# ─────────────────────────────────────────────────────────────────────────────
# Case 4c: task_start 3 succeeds (counter goes from 2 to 3)
# ─────────────────────────────────────────────────────────────────────────────
echo "[4c] task_start 3 succeeds"
_load
if budget_task_start "task-3" 2>/dev/null; then
  COUNT=$(cat "$STATE/.night-task-count" 2>/dev/null || echo "missing")
  if [ "$COUNT" = "3" ]; then
    _pass "task_start 3 succeeded; counter=3"
  else
    _fail "task_start 3 succeeded but counter=$COUNT (expected 3)"
  fi
else
  _fail "task_start for task 3 should succeed (return 0), got nonzero"
fi

# ─────────────────────────────────────────────────────────────────────────────
# Case 5: task_start 4 → BUDGET-ABORT (nonzero return)
# ─────────────────────────────────────────────────────────────────────────────
echo "[5] task_start 4 returns nonzero BUDGET-ABORT"
# Counter is at 3 (from cases 4a-4c)
_load
if budget_task_start "task-4" 2>/dev/null; then
  _fail "task_start for task 4 should BUDGET-ABORT (nonzero), but returned 0"
else
  COUNT=$(cat "$STATE/.night-task-count" 2>/dev/null || echo "missing")
  _pass "task_start 4 returned nonzero BUDGET-ABORT; counter stayed at $COUNT"
fi

# ─────────────────────────────────────────────────────────────────────────────
# Case 6: quota condition trips kill-switch (assert AUTONOMOUS_FREEZE sentinel appears)
# ─────────────────────────────────────────────────────────────────────────────
echo "[6] quota condition trips kill-switch sentinel"
_fresh_state
_load
# Create a fake output file containing a quota-exceeded pattern
QUOTA_OUTPUT="$(mktemp /tmp/test-quota-XXXXXX)"
echo "Error: quota exceeded for this billing period" > "$QUOTA_OUTPUT"
budget_check_quota_abort "$QUOTA_OUTPUT" "task-quota-test" 2>/dev/null || true
FREEZE="$(_freeze_sentinel)"
if [ -f "$FREEZE" ]; then
  _pass "quota condition created $STATE/.AUTONOMOUS_FREEZE sentinel"
else
  _fail "quota condition should create AUTONOMOUS_FREEZE sentinel — not found at $FREEZE"
fi
rm -f "$QUOTA_OUTPUT" || true

# ─────────────────────────────────────────────────────────────────────────────
# Case 7: cap constant is exactly 3 (guards against drift)
# ─────────────────────────────────────────────────────────────────────────────
echo "[7] BUDGET_MAX_TASKS_PER_NIGHT constant is exactly 3"
_fresh_state
_load
# The constant must be defined and equal to 3
if [ "${BUDGET_MAX_TASKS_PER_NIGHT:-MISSING}" = "3" ]; then
  _pass "BUDGET_MAX_TASKS_PER_NIGHT == 3"
else
  _fail "BUDGET_MAX_TASKS_PER_NIGHT should be 3, got: ${BUDGET_MAX_TASKS_PER_NIGHT:-MISSING}"
fi

# ─────────────────────────────────────────────────────────────────────────────
# Case 8: quota check on clean output returns 0 (no false positive)
# ─────────────────────────────────────────────────────────────────────────────
echo "[8] quota check on clean output returns 0"
_fresh_state
_load
CLEAN_OUTPUT="$(mktemp /tmp/test-clean-XXXXXX)"
echo "Task completed successfully. All outputs written." > "$CLEAN_OUTPUT"
if budget_check_quota_abort "$CLEAN_OUTPUT" "task-clean" 2>/dev/null; then
  FREEZE="$(_freeze_sentinel)"
  if [ ! -f "$FREEZE" ]; then
    _pass "clean output: returns 0, no freeze sentinel"
  else
    _fail "clean output: returns 0 but sentinel was wrongly created"
  fi
else
  _fail "clean output: should return 0 (no quota pattern), got nonzero"
fi
rm -f "$CLEAN_OUTPUT" || true

# ─────────────────────────────────────────────────────────────────────────────
# Cleanup
# ─────────────────────────────────────────────────────────────────────────────
rm -rf "$TMPROOT" || true

echo ""
echo "=== Results: PASS=$PASS FAIL=$FAIL ==="
if [ "$FAIL" -eq 0 ]; then
  echo "ALL PASSED"
  exit 0
else
  echo "FAILURES DETECTED"
  exit 1
fi
