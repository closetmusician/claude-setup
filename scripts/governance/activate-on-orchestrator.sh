#!/usr/bin/env bash
# ABOUTME: PostToolUse hook that auto-activates governance when lead-orchestrator skill loads.
# ABOUTME: Fires mechanically on Skill tool use — zero LLM dependency for sentinel creation.
# ABOUTME: Reads tool_input.skill from stdin JSON; touches .active if it matches lead-orchestrator.
# ABOUTME: Designed to prevent the failure mode where LLM skips governance activation instructions.
# ABOUTME: Paired with SessionEnd hook that cleans up the sentinel file.

set -euo pipefail
trap 'exit 0' ERR

if ! command -v jq &>/dev/null; then
  exit 0
fi

INPUT=$(cat)

SKILL_NAME=$(echo "$INPUT" | jq -r '.tool_input.skill // empty' 2>/dev/null)

if [[ "$SKILL_NAME" == *"lead-orchestrator"* ]]; then
  mkdir -p "$HOME/.claude/scripts/governance/state"
  touch "$HOME/.claude/scripts/governance/state/.active"
  echo "governance: sentinel activated by lead-orchestrator skill load" >&2
fi

exit 0
