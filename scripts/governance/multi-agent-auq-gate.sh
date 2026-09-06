#!/usr/bin/env bash
# ABOUTME: PreToolUse(Agent|Task) hook: enforces R16 — parallel agent spawning requires
# ABOUTME: one AskUserQuestion approval per session within governed runs. Tracks per-session
# ABOUTME: spawn counts in $STATE/auq-spawn-count-<session_id>; denies the 2nd+ spawn when
# ABOUTME: no AUQ marker exists ($STATE/.auq-<session_id>). Outside governed runs: fail-open.
# ABOUTME: Companion: auq-witness.sh (PostToolUse AskUserQuestion) writes the AUQ marker.

set -uo pipefail
trap 'exit 0' ERR

command -v jq >/dev/null 2>&1 || exit 0

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/project-root.sh"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/../lib/emit-event.sh" 2>/dev/null || true

# Only active during governed orchestration runs.
STATE="$(get_governance_state_dir)"
( [[ -f "$STATE/.active" ]] || [[ -f "$STATE/.orchestration-active" ]] ) || exit 0

INPUT=$(cat)

SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // empty' 2>/dev/null)
# Without a session_id we cannot key state — fail-open.
[[ -z "$SESSION_ID" || "$SESSION_ID" == "null" ]] && exit 0

# Sanitize session_id: allow only [A-Za-z0-9_-] to prevent path traversal.
# Characters outside this set are stripped so the resulting key is always safe
# to interpolate into a file path under $STATE. An empty result after stripping
# is treated as "no usable session_id" and we fail-open.
SESSION_ID=$(printf '%s' "$SESSION_ID" | tr -dc 'A-Za-z0-9_-')
[[ -z "$SESSION_ID" ]] && exit 0

mkdir -p "$STATE" 2>/dev/null || true

# ── spawn counter (atomic-enough: single-writer per session) ────────────────
COUNT_FILE="$STATE/auq-spawn-count-${SESSION_ID}"
CURRENT=0
# Redirect expected-failure stderr on file reads to suppress benign "no file" errors.
[[ -f "$COUNT_FILE" ]] && CURRENT=$(cat "$COUNT_FILE" 2>/dev/null | grep -oE '^[0-9]+' 2>/dev/null || echo 0)
NEW=$(( CURRENT + 1 ))
printf '%s\n' "$NEW" > "$COUNT_FILE" 2>/dev/null || true

# First spawn always allowed regardless of AUQ state.
if [[ "$NEW" -lt 2 ]]; then
  exit 0
fi

# ── 2nd+ spawn: require AUQ marker ──────────────────────────────────────────
AUQ_MARKER="$STATE/.auq-${SESSION_ID}"
if [[ -f "$AUQ_MARKER" ]]; then
  # AUQ approval recorded for this session — allow.
  emit_event "trust_decision" \
    '{"guard":"multi-agent-auq-gate","claim_type":"parallel_spawn"}' \
    outcome="allowed" source="multi-agent-auq-gate.sh" || true
  exit 0
fi

# Deny: 2+ spawns without prior AskUserQuestion in governed run (R16).
emit_event "trust_decision" \
  "{\"guard\":\"multi-agent-auq-gate\",\"claim_type\":\"parallel_spawn\",\"spawn_count\":$NEW}" \
  outcome="denied" source="multi-agent-auq-gate.sh" || true

TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // "Agent"' 2>/dev/null)
jq -cn --arg r "2+ parallel agents require one AskUserQuestion approval — R16. This session has spawned $NEW ${TOOL_NAME} tools without a prior AskUserQuestion. Ask the user for approval before spawning parallel agents, or use AskUserQuestion first (it writes the approval marker). Governed run: $STATE" \
  '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":$r}}'
exit 0
