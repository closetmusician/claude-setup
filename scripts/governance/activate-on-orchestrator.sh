#!/usr/bin/env bash
# ABOUTME: PostToolUse hook that auto-activates governance when lead-orchestrator skill loads.
# ABOUTME: Fires mechanically on Skill tool use — zero LLM dependency for sentinel creation.
# ABOUTME: Reads tool_input.skill from stdin JSON; touches .active if it matches lead-orchestrator.
# ABOUTME: Designed to prevent the failure mode where LLM skips governance activation instructions.
# ABOUTME: Paired with SessionEnd hook that cleans up the sentinel file.

set -euo pipefail
trap 'exit 0' ERR

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/project-root.sh"
source "${SCRIPT_DIR}/lib/workspace-kind.sh"
# Pillar I emit — purely additive; fail-open via emit_event design + || true guard.
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/../lib/emit-event.sh" 2>/dev/null || true

if ! command -v jq &>/dev/null; then
  exit 0
fi

INPUT=$(cat)

SKILL_NAME=$(echo "$INPUT" | jq -r '.tool_input.skill // empty' 2>/dev/null)

if [[ "$SKILL_NAME" == *"lead-orchestrator"* ]]; then
  # Only activate governance in VIBE repos (.claude/phase.json).
  # Non-VIBE repos (docs workspaces, plain code repos) spawn freely (REPORT.md §4g, D2).
  if ! is_vibe_repo "$PWD"; then
    echo "governance: lead-orchestrator called in non-VIBE repo, sentinel not activated" >&2
    exit 0
  fi

  GOV_DIR="$(get_governance_state_dir)"
  mkdir -p "$GOV_DIR"
  touch "$GOV_DIR/.active"
  echo "$GOV_DIR" > "$HOME/.claude/.last-governance-state-path"
  echo "governance: sentinel activated at $GOV_DIR/.active" >&2
  # Emit skill_fire for lead-orchestrator activation.
  emit_event "skill_fire" '{"skill":"lead-orchestrator","action":"sentinel_activated"}' \
    skill="lead-orchestrator" outcome="ok" source="activate-on-orchestrator.sh" || true
fi

exit 0
