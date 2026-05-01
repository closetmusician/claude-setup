#!/usr/bin/env bash
# ABOUTME: PostToolUse hook auditing subagent completion against the requirement map.
# ABOUTME: Compares Agent tool_result text against persisted requirement map from pre-gate.
# ABOUTME: Builds RED/GREEN evidence ledger; emits decision=block JSON if any RED.
# ABOUTME: Escape hatches: agent_id present, missing state file, AUDIT_EXEMPT in output.
# ABOUTME: Writes latest-evidence-ledger.json to state/ on full GREEN pass.

set -euo pipefail

# Safety net: never break the session on hook failure.
trap 'exit 0' ERR

# ─── Dependency check ───
if ! command -v jq &>/dev/null; then
  echo "post-agent-audit: jq not found, skipping audit" >&2
  exit 0
fi

# Governance only active when sentinel exists (created by lead-orchestrator)
[[ ! -f "$HOME/.claude/scripts/governance/state/.active" ]] && exit 0

# ─── Read input ───
INPUT=$(cat)

# ─── Escape hatch: subagent-to-subagent (agent_id present) ───
AGENT_ID=$(echo "$INPUT" | jq -r '.agent_id // empty')
if [[ -n "$AGENT_ID" ]]; then
  exit 0
fi

# ─── Extract tool_result ───
TOOL_RESULT=$(echo "$INPUT" | jq -r '.tool_result // empty')
if [[ -z "$TOOL_RESULT" ]]; then
  echo "post-agent-audit: no tool_result in input, skipping" >&2
  exit 0
fi

# ─── Escape hatch: AUDIT_EXEMPT ───
if echo "$TOOL_RESULT" | grep -q 'AUDIT_EXEMPT'; then
  exit 0
fi

# ─── State directory ───
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STATE_DIR="${SCRIPT_DIR}/state"
REQ_MAP_FILE="${STATE_DIR}/latest-requirement-map.json"

# ─── Escape hatch: no state file (pre-gate may not have run) ───
if [[ ! -f "$REQ_MAP_FILE" ]] || [[ ! -s "$REQ_MAP_FILE" ]]; then
  echo "post-agent-audit: no requirement map found (pre-gate may not have run), skipping" >&2
  exit 0
fi

# ─── Read requirement map ───
REQ_MAP=$(cat "$REQ_MAP_FILE")
TASK_ID=$(echo "$REQ_MAP" | jq -r '.task_id // "unknown"')

# ─── Build evidence object from tool_result ───
# For each req_id in the map, search tool_result for evidence patterns:
#   - req_id + completion indicator word
#   - Structured "REQ-XX: description" line
EVIDENCE_JSON=$(echo "$REQ_MAP" | jq -r '.requirements[].req_id' | while read -r REQ_ID; do
  # Pattern 1: structured evidence line "REQ-XX: <text>" (req_id followed by colon)
  EVIDENCE_LINE=$(echo "$TOOL_RESULT" | grep -oiE "${REQ_ID}\s*:\s*.+" | head -1 || true)

  if [[ -n "$EVIDENCE_LINE" ]]; then
    # Found structured evidence
    printf '%s\t%s\n' "$REQ_ID" "$EVIDENCE_LINE"
    continue
  fi

  # Pattern 2: req_id followed by completion indicator (within same sentence context)
  COMPLETION_LINE=$(echo "$TOOL_RESULT" | grep -oiE "${REQ_ID}[^.;]*\b(done|complete|verified|evidence|implemented|created|passed|added|populated|updated|fixed|resolved|confirmed|exists|present)\b[^.;]*" | head -1 || true)

  if [[ -n "$COMPLETION_LINE" ]]; then
    printf '%s\t%s\n' "$REQ_ID" "$COMPLETION_LINE"
    continue
  fi

  # No evidence found
  printf '%s\t\n' "$REQ_ID"
done)

# ─── Convert evidence to JSON object ───
EVIDENCE_OBJ=$(echo "$EVIDENCE_JSON" | jq -R -s '
  split("\n") | map(select(length > 0)) |
  map(split("\t")) |
  map({key: .[0], value: (if .[1] == "" then null else .[1] end)}) |
  from_entries
')

# ─── Check for unlinked references (req_ids in output not in map) ───
MAP_REQ_IDS=$(echo "$REQ_MAP" | jq -r '.requirements[].req_id')
FOUND_REQ_REFS=$(echo "$TOOL_RESULT" | grep -oE 'REQ-[0-9]+' | sort -u || true)

if [[ -n "$FOUND_REQ_REFS" ]]; then
  while read -r REF; do
    if ! echo "$MAP_REQ_IDS" | grep -qx "$REF"; then
      echo "post-agent-audit: UNLINKED reference '${REF}' in output (not in requirement map)" >&2
    fi
  done <<< "$FOUND_REQ_REFS"
fi

# ─── Validate using jq library ───
JQ_LIB="${SCRIPT_DIR}/lib/validate-ledger.jq"
VALIDATION_INPUT=$(jq -n --argjson reqs "$REQ_MAP" --argjson ev "$EVIDENCE_OBJ" '{
  requirements: $reqs.requirements,
  evidence: $ev
}')

ASSESSMENT=$(echo "$VALIDATION_INPUT" | jq -f "$JQ_LIB")

# ─── Count RED items ───
RED_COUNT=$(echo "$ASSESSMENT" | jq '[.[] | select(.status == "RED")] | length')
GREEN_COUNT=$(echo "$ASSESSMENT" | jq '[.[] | select(.status == "GREEN")] | length')

# ─── All GREEN: persist ledger and allow ───
if [[ "$RED_COUNT" -eq 0 ]]; then
  # Write evidence ledger to state
  jq -n --arg task "$TASK_ID" --argjson assessment "$ASSESSMENT" --argjson evidence "$EVIDENCE_OBJ" '{
    task_id: $task,
    timestamp: (now | todate),
    assessment: $assessment,
    evidence: $evidence,
    result: "PASS"
  }' > "${STATE_DIR}/latest-evidence-ledger.json"
  exit 0
fi

# ─── RED items exist: build block message ───
SUMMARY=$(echo "$ASSESSMENT" | jq -r '.[] |
  if .status == "GREEN" then
    "GREEN ✓ \(.req_id): \(.what) (\(.detail))"
  else
    "RED   ✗ \(.req_id): \(.what) (\(.detail))"
  end
')

BLOCK_REASON=$(cat <<EOF
EVIDENCE AUDIT — INCOMPLETE COVERAGE (${TASK_ID})

${SUMMARY}

Blocked: ${RED_COUNT} requirement(s) have no evidence of completion.
The subagent must provide explicit evidence for each requirement.
EOF
)

# Emit block decision JSON
printf '{"decision": "block", "reason": %s}\n' "$(echo "$BLOCK_REASON" | jq -Rs .)"
exit 0
