#!/usr/bin/env bash
# ABOUTME: VI-3 cap-consistency guard — asserts BUDGET_MAX_TASKS_PER_NIGHT is the single
# ABOUTME: source of truth for the per-night task cap across all enforcement points.
# ABOUTME: Exits 0 only if ALL sources agree; fails with a diff-style summary on mismatch.
# ABOUTME: Guards against cap drift: if any script hardcodes a literal that differs from
# ABOUTME: the kernel value, or if any source that MUST reference the kernel doesn't, the
# ABOUTME: test reports exactly what drifted and where to fix it.
# ABOUTME: Run: bash scripts/tests/test-cap-consistency.sh — must pass on a clean tree.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAUDE_HOME="${CLAUDE_HOME:-$HOME/.claude}"
BUDGET_KERNEL="${CLAUDE_HOME}/scripts/lib/budget-kernel.sh"
NIGHT_RUNNER="${CLAUDE_HOME}/scripts/night-runner.sh"
MORNING_BRIEF="${CLAUDE_HOME}/scripts/morning-brief.sh"
VI_DOC="${CLAUDE_HOME}/docs/plans/harness/audit-2026-07-03/evidence/pillar-6-work-economy.md"

PASS=0
FAIL=0

_pass() { printf '  PASS: %s\n' "$1"; (( PASS++ )) || true; }
_fail() { printf '  FAIL: %s\n    reason: %s\n' "$1" "$2"; (( FAIL++ )) || true; }

printf '=== test-cap-consistency.sh (VI-3) ===\n'
printf 'Canonical source: %s\n' "$BUDGET_KERNEL"

# ── Step 1: Extract kernel cap value ─────────────────────────────────────────
# Purpose: read BUDGET_MAX_TASKS_PER_NIGHT from budget-kernel.sh.
# The value is always a bare integer on a readonly line; parse with grep+sed.
if [[ ! -f "$BUDGET_KERNEL" ]]; then
  printf '  FAIL: budget-kernel.sh not found at %s\n' "$BUDGET_KERNEL"
  printf '\n=== RESULTS: %d passed, 1 failed ===\n' "$PASS"
  exit 1
fi

KERNEL_CAP="$(grep -E '^readonly BUDGET_MAX_TASKS_PER_NIGHT=' "$BUDGET_KERNEL" \
              | head -1 \
              | sed 's/.*BUDGET_MAX_TASKS_PER_NIGHT=//' \
              | tr -d '[:space:]')"

if [[ -z "$KERNEL_CAP" ]] || ! [[ "$KERNEL_CAP" =~ ^[0-9]+$ ]]; then
  _fail "kernel cap is readable and numeric" "got: '$KERNEL_CAP' from $BUDGET_KERNEL"
  printf '\n=== RESULTS: %d passed, %d failed ===\n' "$PASS" "$FAIL"
  exit 1
fi

_pass "budget-kernel.sh defines BUDGET_MAX_TASKS_PER_NIGHT=$KERNEL_CAP (numeric)"

# ── Step 2: night-runner.sh must reference BUDGET_MAX_TASKS_PER_NIGHT (not hardcode) ──
# Purpose: ensure the runner reads from the kernel, never a literal cap.
if [[ ! -f "$NIGHT_RUNNER" ]]; then
  _fail "night-runner.sh exists" "not found at $NIGHT_RUNNER"
else
  # Must reference the kernel variable name
  if grep -q 'BUDGET_MAX_TASKS_PER_NIGHT' "$NIGHT_RUNNER" 2>/dev/null; then
    _pass "night-runner.sh references BUDGET_MAX_TASKS_PER_NIGHT (reads from kernel)"
  else
    _fail "night-runner.sh references BUDGET_MAX_TASKS_PER_NIGHT" \
      "no reference found — night-runner.sh may be using a hardcoded literal"
  fi

  # Must NOT hardcode the cap as a literal integer NOT adjacent to the variable name
  # Check for bare integer assignments like CAP=3 or TASKS=3 in the runner
  bad_lines="$(grep -En '^\s*(readonly\s+)?(CAP|MAX_TASKS|NIGHT_CAP|TASK_CAP)\s*=\s*[0-9]+' \
                "$NIGHT_RUNNER" 2>/dev/null || true)"
  if [[ -n "$bad_lines" ]]; then
    _fail "night-runner.sh has no hardcoded cap assignments (must use kernel)" \
      "offending lines: $bad_lines"
  else
    _pass "night-runner.sh has no hardcoded cap variable assignments"
  fi

  # Must source budget-kernel.sh (not just reference the constant name)
  if grep -q 'budget-kernel\.sh' "$NIGHT_RUNNER" 2>/dev/null; then
    _pass "night-runner.sh sources budget-kernel.sh"
  else
    _fail "night-runner.sh sources budget-kernel.sh" \
      "no 'budget-kernel.sh' reference in $NIGHT_RUNNER"
  fi
fi

# ── Step 3: morning-brief.sh must NOT hardcode a cap number ──────────────────
# Purpose: morning-brief is read-only/reporting; it must not embed a stale literal cap.
# If it sources budget-kernel.sh, the variable reference is fine.
# If it has no cap reference at all, that is also fine (it reports queue state, not cap).
if [[ ! -f "$MORNING_BRIEF" ]]; then
  _fail "morning-brief.sh exists" "not found at $MORNING_BRIEF"
else
  # Check for bare numeric cap literals that look like a hardcoded policy number.
  # Pattern: variable assignment like MAX_TASKS=3 or a comment-free literal cap usage.
  # We only fail if a bare integer is assigned to a cap-sounding variable without using
  # the kernel constant name.
  hardcoded_cap_lines="$(grep -En \
    '^\s*(readonly\s+)?(MAX_TASKS|BUDGET_MAX|NIGHT_CAP|TASK_CAP|CAP_TASKS)\s*=\s*[0-9]+' \
    "$MORNING_BRIEF" 2>/dev/null || true)"

  if [[ -n "$hardcoded_cap_lines" ]]; then
    _fail "morning-brief.sh has no hardcoded cap assignments" \
      "offending lines: $hardcoded_cap_lines — must use budget-kernel.sh or no cap at all"
  else
    _pass "morning-brief.sh has no hardcoded cap variable assignments"
  fi

  # If morning-brief references a cap, it must use the kernel constant
  if grep -q 'BUDGET_MAX_TASKS_PER_NIGHT' "$MORNING_BRIEF" 2>/dev/null; then
    _pass "morning-brief.sh references BUDGET_MAX_TASKS_PER_NIGHT kernel constant (not a literal)"
  else
    # Not referencing the kernel is OK — reporting scripts don't need to know the cap
    _pass "morning-brief.sh does not reference cap (no enforcement role — acceptable)"
  fi
fi

# ── Step 4: VI spec doc must cite the kernel as canonical source ──────────────
# Purpose: the doc is the source of English spec; it must acknowledge budget-kernel.sh
# as canonical rather than stating a bare number as ground truth.
if [[ ! -f "$VI_DOC" ]]; then
  _fail "pillar-6 spec doc exists" "not found at $VI_DOC"
else
  if grep -q 'budget-kernel\.sh' "$VI_DOC" 2>/dev/null; then
    _pass "pillar-6 spec doc references budget-kernel.sh as canonical cap source"
  else
    _fail "pillar-6 spec doc references budget-kernel.sh" \
      "doc may state a bare cap number without citing the kernel as source of truth"
  fi

  # Doc must not contradict the kernel — if it states a number, it must equal kernel cap
  # Extract any explicit "3 tasks" or "cap = N" statements and verify they match
  stated_caps="$(grep -oE 'total ≤ [0-9]+ tasks|cap \(.*\).*[0-9]+|BUDGET_MAX_TASKS_PER_NIGHT=[0-9]+|[0-9]+ tasks/night' \
    "$VI_DOC" 2>/dev/null | grep -oE '[0-9]+' | sort -u || true)"

  mismatched=0
  while IFS= read -r n; do
    [[ -z "$n" ]] && continue
    if [[ "$n" != "$KERNEL_CAP" ]]; then
      _fail "cap number in spec doc matches kernel ($KERNEL_CAP)" \
        "doc contains different number: $n — check context in $VI_DOC"
      mismatched=1
    fi
  done <<< "$stated_caps"

  if [[ "$mismatched" -eq 0 ]]; then
    _pass "all numeric cap references in spec doc ($stated_caps) match kernel cap ($KERNEL_CAP)"
  fi
fi

# ── Summary ───────────────────────────────────────────────────────────────────
printf '\nCanonical cap: BUDGET_MAX_TASKS_PER_NIGHT=%s (from budget-kernel.sh)\n' "$KERNEL_CAP"
printf '\n=== RESULTS: %d passed, %d failed ===\n' "$PASS" "$FAIL"

if [[ "$FAIL" -gt 0 ]]; then
  printf '\nTo fix cap drift:\n'
  printf '  1. Edit ONLY scripts/lib/budget-kernel.sh to change the cap value.\n'
  printf '  2. Ensure night-runner.sh sources budget-kernel.sh (never hardcodes).\n'
  printf '  3. Ensure morning-brief.sh does not hardcode a cap assignment.\n'
  printf '  4. Update the spec doc to cite the kernel as canonical source.\n'
  exit 1
fi

exit 0
