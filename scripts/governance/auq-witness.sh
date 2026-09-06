#!/usr/bin/env bash
# ABOUTME: PostToolUse(AskUserQuestion) witness: writes the per-session AUQ marker so the
# ABOUTME: multi-agent-auq-gate knows an AskUserQuestion fired in this session. Purely
# ABOUTME: additive — fail-open on every error. Companion to multi-agent-auq-gate.sh (R16).
# ABOUTME: Marker path: $STATE/.auq-<session_id> (governed run state dir keyed by session).
# ABOUTME: Outside governed runs: exits silently without writing anything.

set -uo pipefail
trap 'exit 0' ERR

command -v jq >/dev/null 2>&1 || exit 0

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/project-root.sh"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/../lib/emit-event.sh" 2>/dev/null || true

# Only active during governed runs.
STATE="$(get_governance_state_dir)"
( [[ -f "$STATE/.active" ]] || [[ -f "$STATE/.orchestration-active" ]] ) || exit 0

INPUT=$(cat)

SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // empty' 2>/dev/null)
[[ -z "$SESSION_ID" || "$SESSION_ID" == "null" ]] && exit 0

# Sanitize session_id: allow only [A-Za-z0-9_-] — must match multi-agent-auq-gate.sh
# so the marker name the witness writes equals the marker name the gate checks.
SESSION_ID=$(printf '%s' "$SESSION_ID" | tr -dc 'A-Za-z0-9_-')
[[ -z "$SESSION_ID" ]] && exit 0

# Write the AUQ approval marker for this session.
mkdir -p "$STATE" 2>/dev/null || true
AUQ_MARKER="$STATE/.auq-${SESSION_ID}"
touch "$AUQ_MARKER" 2>/dev/null || true

emit_event "trust_decision" \
  '{"guard":"auq-witness","claim_type":"auq_marker_written"}' \
  outcome="ok" source="auq-witness.sh" || true

exit 0
