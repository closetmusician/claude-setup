#!/usr/bin/env bash
# ABOUTME: PostToolUse hook (Read|Bash|Grep|Glob|Agent|WebFetch): adds up the raw tool output
# ABOUTME: an orchestrating session takes into its context, per session.
# ABOUTME: Warns once each time the total first crosses 100 KB, 200 KB and 400 KB. Never blocks.
# ABOUTME: Armed by the same sentinels as read-budget-guard.sh; subagents are not metered.
# ABOUTME: Spec: docs/plans/harness/governance-scope-spec.md §3 C7.

set -uo pipefail
trap 'exit 0' ERR

command -v jq >/dev/null 2>&1 || exit 0
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/project-root.sh"

STATE="$(get_governance_state_dir)"
ARMED=0
[[ -e "$STATE/.active" || -e "$STATE/.orchestration-active" ]] && ARMED=1
for f in "$STATE"/.gate-*; do [[ -e "$f" ]] && ARMED=1 && break; done
[[ "$ARMED" -eq 1 ]] || exit 0

INPUT="$(cat)"
[[ -n "$(printf '%s' "$INPUT" | jq -r '.agent_id // empty' 2>/dev/null)" ]] && exit 0
SID="$(printf '%s' "$INPUT" | jq -r '.session_id // empty' 2>/dev/null | tr -dc 'A-Za-z0-9_-')"
[[ -z "$SID" ]] && exit 0

ADD="$(printf '%s' "$INPUT" | jq -c '.tool_response // empty' 2>/dev/null | wc -c | tr -d ' ')"
METER="$STATE/read-meter-${SID}"
PREV="$(cat "$METER" 2>/dev/null | grep -oE '^[0-9]+' || echo 0)"
TOTAL=$(( ${PREV:-0} + ${ADD:-0} ))
printf '%s\n' "$TOTAL" > "$METER" 2>/dev/null || true

# Warn only on the call that crosses a threshold, so each warning appears once.
for T in 102400 204800 409600; do
  if [[ "${PREV:-0}" -lt "$T" && "$TOTAL" -ge "$T" ]]; then
    jq -cn --arg c "Orchestrator raw tool output this session: $(( TOTAL / 1024 )) KB. Delegate reads; ask agents for 15-line digests." \
      '{hookSpecificOutput:{hookEventName:"PostToolUse",additionalContext:$c}}'
    break
  fi
done
exit 0
