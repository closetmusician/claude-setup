#!/usr/bin/env bash
# ABOUTME: Stop hook — runs harness eval corpus in autonomous context ONLY (inverse of harness-selfcheck.sh).
# ABOUTME: Fires when AUTONOMOUS_RUN=1 AND .harness-dirty flag exists; blocks the stop on regression.
# ABOUTME: Does NOT skip on stop_hook_active — autonomous runs have no human safety net.
# ABOUTME: Fail-open on infra errors (missing jq/run-harness-evals.sh). Real regressions block.
# ABOUTME: BSD/macOS compatible. Plane separator reads stdin session_id and AUTONOMOUS_RUN.

set -uo pipefail
trap 'exit 0' ERR

command -v jq >/dev/null 2>&1 || exit 0

# ── PLANE SEPARATOR ──────────────────────────────────────────────────────────
INPUT=$(cat 2>/dev/null || true)
STATE="${STATE:-$HOME/.claude/state}"
_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -f "${_SCRIPT_DIR}/lib/autonomous-registry.sh" ]]; then
  # shellcheck disable=SC1091
  source "${_SCRIPT_DIR}/lib/autonomous-registry.sh"
  autonomous_registry_should_enforce "$INPUT" 2>/dev/null || exit 0
else
  if [[ "${AUTONOMOUS_RUN:-}" != "1" ]]; then
    _sid="$(printf '%s' "$INPUT" | jq -r '.session_id // ""' 2>/dev/null || true)"
    [[ -n "$_sid" ]] || _sid="${SESSION_ID:-}"
    jq -e --arg sid "$_sid" \
       'any(.[]; (.session_id == $sid or .lane_id == $sid) and .status == "active")' \
       "${STATE}/autonomous-registry.json" >/dev/null 2>&1 || exit 0
  fi
fi

# NOTE: No stop_hook_active bailout here — autonomous runs must run evals even if another
# Stop hook is active. Unlike harness-selfcheck.sh (interactive), unattended execution has
# no human safety net; the eval gate must fire unconditionally on the autonomous plane.

CLAUDE_DIR="${CLAUDE_DIR:-$HOME/.claude}"
DIRTY_FILE="${CLAUDE_DIR}/state/.harness-dirty"
EVALS_SCRIPT="${CLAUDE_DIR}/scripts/run-harness-evals.sh"

# Fast path: no dirty flag → nothing to check
[[ -f "$DIRTY_FILE" ]] || exit 0

# Fail-open: eval script missing (infrastructure not yet installed on fresh clone)
if [[ ! -x "$EVALS_SCRIPT" ]]; then
  exit 0
fi

# Source emit-event for audit trail (best-effort — fail-open if unavailable)
# shellcheck source=/dev/null
source "${CLAUDE_DIR}/scripts/lib/emit-event.sh" 2>/dev/null || true

echo "harness-selfcheck-autonomous: .harness-dirty present in autonomous run — running eval corpus" >&2

# Run corpus; capture combined output for the block message on failure.
# Disable ERR trap around the eval run — a nonzero exit is expected on regression and
# must be checked explicitly rather than caught by the top-level fail-open trap.
trap - ERR
RESULT=""
EVAL_EC=0
RESULT=$(bash "$EVALS_SCRIPT" 2>&1) || EVAL_EC=$?
trap 'exit 0' ERR

if [[ "$EVAL_EC" -ne 0 ]]; then
  # Real regression — BLOCK the stop. Emit an audit event first (best-effort).
  FIRST_FAIL=$(printf '%s' "$RESULT" | grep -i 'FAIL\|REFUSED\|ERROR' | head -1 | sed 's/"/\\"/g' || true)
  emit_event "eval_run" \
    "{\"corpus\":\"incidents\",\"passed\":0,\"failed\":1,\"regressions\":[\"corpus-run-failed\"],\"first_fail\":\"$FIRST_FAIL\"}" \
    outcome=error 2>/dev/null || true
  printf '{"decision":"block","reason":"AUTONOMOUS PLANE: harness eval corpus FAILED after self-modification — patch is staged, not applied. Examine .proposed files. First failure: %s"}\n' \
    "$FIRST_FAIL"
  exit 0
fi

# Corpus passed — emit success event and clear the dirty flag
emit_event "eval_run" \
  '{"corpus":"incidents","passed":1,"failed":0,"regressions":[]}' \
  outcome=ok 2>/dev/null || true

rm -f "$DIRTY_FILE" 2>/dev/null || true
exit 0
