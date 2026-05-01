#!/usr/bin/env bash
# ABOUTME: PreToolUse hook gating Agent (subagent) spawning with governance context.
# ABOUTME: Ensures orchestrators pass Mandatory Context, Requirement Map, and Constraints.
# ABOUTME: Subagents (agent_id present) and GOVERNANCE_EXEMPT prompts bypass all checks.
# ABOUTME: Persists validated requirement map and spec refs to state/ on success.
# ABOUTME: Outputs JSON {"decision":"block","reason":"..."} to block, or exits 0 to allow.

set -euo pipefail

# Safety net: never block on hook failure.
trap 'exit 0' ERR

# Bail gracefully if jq is missing.
if ! command -v jq &>/dev/null; then
  echo "pre-agent-gate: jq not found, skipping checks" >&2
  exit 0
fi

# Governance only active when sentinel exists (created by lead-orchestrator)
[[ ! -f "$HOME/.claude/scripts/governance/state/.active" ]] && exit 0

# ─── Read input ───
INPUT=$(cat)

# ─── Escape hatch: subagent-to-subagent spawning ───
AGENT_ID=$(echo "$INPUT" | jq -r '.agent_id // empty')
if [[ -n "$AGENT_ID" ]]; then
  exit 0
fi

# ─── Extract prompt ───
PROMPT=$(echo "$INPUT" | jq -r '.tool_input.prompt // empty')
if [[ -z "$PROMPT" ]]; then
  # No prompt to validate — allow (defensive)
  exit 0
fi

# ─── Escape hatch: GOVERNANCE_EXEMPT ───
if echo "$PROMPT" | grep -qi 'GOVERNANCE_EXEMPT'; then
  exit 0
fi

# ─── Helper: emit block JSON and exit ───
block_and_exit() {
  local reason="$1"
  printf '{"decision": "block", "reason": "Pre-Agent Gate: %s"}\n' "$reason"
  exit 0
}

# ─── State directory ───
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STATE_DIR="${SCRIPT_DIR}/state"
mkdir -p "$STATE_DIR"

# ─── CHECK 1: Mandatory Context ───
# Must have a "## Mandatory Context" header followed by at least one spec ref.
if ! echo "$PROMPT" | grep -q '## Mandatory Context'; then
  block_and_exit "Missing '## Mandatory Context' section. Orchestrator must provide spec/doc references for subagent."
fi

# Extract text after ## Mandatory Context until next ## header or end
CONTEXT_SECTION=$(echo "$PROMPT" | sed -n '/^## Mandatory Context/,/^## /{ /^## Mandatory Context/d; /^## /d; p; }')

# Check for at least one spec reference (docs/*.md path or REQ-NNN pattern)
if ! echo "$CONTEXT_SECTION" | grep -qE '(docs/.*\.md|REQ-[0-9]+)'; then
  block_and_exit "## Mandatory Context exists but contains no spec references (expected docs/*.md or REQ-NNN pattern)."
fi

# ─── CHECK 2: Requirement Map ───
# Must contain a fenced JSON code block with task_id + requirements array.
# Extract JSON from fenced code block (```json ... ```)
REQ_MAP_JSON=$(echo "$PROMPT" | sed -n '/^```json/,/^```/{/^```/d; p;}' | head -100)

if [[ -z "$REQ_MAP_JSON" ]]; then
  block_and_exit "Missing requirement map. Orchestrator must include a fenced JSON block with task_id and requirements array."
fi

# Validate structure using jq library
JQ_LIB="${SCRIPT_DIR}/lib/validate-map.jq"
VALIDATE_RESULT=$(echo "$REQ_MAP_JSON" | jq -f "$JQ_LIB" 2>&1) || {
  block_and_exit "Invalid requirement map: ${VALIDATE_RESULT}"
}

# ─── CHECK 3: Governance Constraints ───
# Must have ## Constraints or ## Governance section with non-empty content.
HAS_CONSTRAINTS=false

if echo "$PROMPT" | grep -q '## Constraints'; then
  CONSTRAINTS_BODY=$(echo "$PROMPT" | sed -n '/^## Constraints/,/^## /{ /^## Constraints/d; /^## /d; p; }')
  if echo "$CONSTRAINTS_BODY" | grep -q '[^[:space:]]'; then
    HAS_CONSTRAINTS=true
  fi
fi

if [[ "$HAS_CONSTRAINTS" == "false" ]] && echo "$PROMPT" | grep -q '## Governance'; then
  GOVERNANCE_BODY=$(echo "$PROMPT" | sed -n '/^## Governance/,/^## /{ /^## Governance/d; /^## /d; p; }')
  if echo "$GOVERNANCE_BODY" | grep -q '[^[:space:]]'; then
    HAS_CONSTRAINTS=true
  fi
fi

if [[ "$HAS_CONSTRAINTS" == "false" ]]; then
  block_and_exit "Missing governance constraints. Orchestrator must include '## Constraints' or '## Governance' section with non-empty content."
fi

# ─── ALL CHECKS PASSED — persist state ───
# Extract spec references for passthrough
SPEC_REFS=$(echo "$CONTEXT_SECTION" | grep -oE '(docs/[^ ]*\.md|REQ-[0-9]+)' | jq -R -s 'split("\n") | map(select(length > 0))')

echo "$REQ_MAP_JSON" > "${STATE_DIR}/latest-requirement-map.json"
echo "$SPEC_REFS" > "${STATE_DIR}/latest-passthrough-refs.json"

exit 0
