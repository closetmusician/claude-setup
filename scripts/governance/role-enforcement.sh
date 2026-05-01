#!/usr/bin/env bash
# ABOUTME: PreToolUse hook enforcing role-based write restrictions on orchestrators.
# ABOUTME: Blocks Write/Edit/Bash for top-level agents (no agent_id) while allowing subagents.
# ABOUTME: Exception paths (logs/, qa/, governance/) and safe Bash prefixes bypass the block.
# ABOUTME: Configuration lives in roles.json alongside this script.
# ABOUTME: Outputs JSON {"decision":"block","reason":"..."} to block, or exits 0 to allow.

set -euo pipefail

# Safety net: never crash-block the user on hook failure.
trap 'exit 0' ERR

# Bail gracefully if jq is missing.
if ! command -v jq &>/dev/null; then
  echo "role-enforcement: jq not found, skipping checks" >&2
  exit 0
fi

# Governance only active when sentinel exists (created by lead-orchestrator)
[[ ! -f "$HOME/.claude/scripts/governance/state/.active" ]] && exit 0

# ─── Read input ───
INPUT=$(cat)

# ─── Primary signal: agent_id present = subagent (worker) → always allow ───
AGENT_ID=$(echo "$INPUT" | jq -r '.agent_id // empty')
if [[ -n "$AGENT_ID" ]]; then
  exit 0
fi

# ─── At this point we are the orchestrator. Load roles config. ───
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROLES_FILE="${SCRIPT_DIR}/roles.json"

if [[ ! -f "$ROLES_FILE" ]]; then
  echo "role-enforcement: roles.json not found at ${ROLES_FILE}, allowing" >&2
  exit 0
fi

# ─── Extract tool info ───
TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // empty')

# Only enforce on denied tools for orchestrator role.
DENIED_TOOLS=$(jq -r '.orchestrator.denied_tools[]' "$ROLES_FILE" 2>/dev/null)
if [[ -z "$DENIED_TOOLS" ]]; then
  exit 0
fi

# Check if current tool is in the denied list.
IS_DENIED=false
while IFS= read -r denied; do
  if [[ "$TOOL_NAME" == "$denied" ]]; then
    IS_DENIED=true
    break
  fi
done <<< "$DENIED_TOOLS"

if [[ "$IS_DENIED" == "false" ]]; then
  exit 0
fi

# ─── Tool is denied for orchestrator. Check exceptions. ───

# Helper: emit block JSON and exit.
block_and_exit() {
  local reason="$1"
  printf '{"decision": "block", "reason": "Role Enforcement: %s"}\n' "$reason"
  exit 0
}

# For Write/Edit: check if file_path matches any exception pattern.
if [[ "$TOOL_NAME" == "Write" || "$TOOL_NAME" == "Edit" ]]; then
  FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')

  if [[ -n "$FILE_PATH" ]]; then
    # Check exception paths from roles.json.
    EXCEPTIONS=$(jq -r '.orchestrator.exceptions[]' "$ROLES_FILE" 2>/dev/null)
    while IFS= read -r exc; do
      if [[ -n "$exc" ]] && echo "$FILE_PATH" | grep -q "$exc"; then
        exit 0
      fi
    done <<< "$EXCEPTIONS"
  fi

  block_and_exit "orchestrator cannot use ${TOOL_NAME} on implementation files. Spawn a coder subagent instead."
fi

# For Bash: check if command starts with a safe prefix.
if [[ "$TOOL_NAME" == "Bash" ]]; then
  COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty')

  if [[ -z "$COMMAND" ]]; then
    # No command to evaluate — block defensively.
    block_and_exit "orchestrator cannot use Bash without a command."
  fi

  # Check safe prefixes from roles.json.
  SAFE_PREFIXES=$(jq -r '.orchestrator.safe_bash_prefixes[]' "$ROLES_FILE" 2>/dev/null)
  while IFS= read -r prefix; do
    if [[ -n "$prefix" ]] && [[ "$COMMAND" == "${prefix}"* ]]; then
      exit 0
    fi
  done <<< "$SAFE_PREFIXES"

  block_and_exit "orchestrator cannot use Bash for '${COMMAND%%\ *}...'. Only safe commands (git, ls, cat, docker, curl, echo, mkdir, gh, rtk) allowed. Spawn a coder subagent instead."
fi

# Catch-all for any other denied tool (shouldn't reach here, but defensive).
block_and_exit "orchestrator cannot use ${TOOL_NAME}. Spawn a coder subagent instead."
