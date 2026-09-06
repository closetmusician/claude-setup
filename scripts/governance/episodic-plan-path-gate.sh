#!/usr/bin/env bash
# ABOUTME: PreToolUse(mcp__plugin_episodic-memory_episodic-memory__search) hook: denies
# ABOUTME: episodic memory search when the session context indicates a plan/doc-pointed task.
# ABOUTME: Detection: .orchestration-active/.active sentinel present (governed run) is the
# ABOUTME: PRIMARY and SOLE authoritative trigger. Query-string matching was removed (it was
# ABOUTME: too broad and caused false-denies for legit queries that mention "docs/plans").
# ABOUTME: Encodes: "do NOT search episodic memory if the prompt points at a plan/doc" (CLAUDE.md).

set -uo pipefail
trap 'exit 0' ERR

command -v jq >/dev/null 2>&1 || exit 0

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/project-root.sh"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/../lib/emit-event.sh" 2>/dev/null || true

INPUT=$(cat)

STATE="$(get_governance_state_dir)"

deny() {
  local reason="$1"
  emit_event "trust_decision" \
    '{"guard":"episodic-plan-path-gate","claim_type":"episodic_search"}' \
    outcome="would_block" source="episodic-plan-path-gate.sh" || true
  jq -cn --arg r "$reason" \
    '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":$r}}'
  exit 0
}

# Primary (authoritative) trigger: governed run sentinel present → deny.
# The sentinel means the session's sole context IS a plan/doc; episodic search
# would contaminate that context window. Query-string matching was intentionally
# removed — it produced false-denies for legit queries that merely mention
# "docs/plans" as words. The sentinel is the only reliable signal.
if [[ -f "$STATE/.orchestration-active" ]] || [[ -f "$STATE/.active" ]]; then
  deny "Prompt points at a plan/doc — that doc is sole context (CLAUDE.md); episodic search denied. Override: remove sentinel or rephrase."
fi

# No sentinel — plain session query. Allow.
emit_event "trust_decision" \
  '{"guard":"episodic-plan-path-gate","claim_type":"episodic_search"}' \
  outcome="allowed" source="episodic-plan-path-gate.sh" || true
exit 0
