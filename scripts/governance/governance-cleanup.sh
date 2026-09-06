#!/usr/bin/env bash
# ABOUTME: SessionEnd hook that cleans up per-project governance state.
# ABOUTME: Reads the stashed state path from ~/.claude/.last-governance-state-path.
# ABOUTME: Removes the .agents/claude-governance/ directory and the stash file itself.
# ABOUTME: Falls back to project-root detection if stash file is missing.
# ABOUTME: Replaces the old inline `rm -f ~/.agents/claude-governance/.active` approach.

set -euo pipefail
trap 'exit 0' ERR

STASH_FILE="$HOME/.claude/.last-governance-state-path"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Pillar I emit — purely additive; sourced before any logic so emit_event is available.
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/../lib/emit-event.sh" 2>/dev/null || true

cleanup_dir() {
  local dir="$1"
  if [[ -d "$dir" ]]; then
    rm -rf "$dir"
    echo "governance: cleaned up state at $dir" >&2
  fi
}

# Primary: read stashed path from activation
if [[ -f "$STASH_FILE" ]]; then
  GOV_DIR="$(cat "$STASH_FILE")"
  emit_event "session_end" '{"trigger":"SessionEnd","path":"stash"}' source="governance-cleanup.sh" || true
  cleanup_dir "$GOV_DIR"
  rm -f "$STASH_FILE"
  exit 0
fi

# Fallback: try project root detection
source "${SCRIPT_DIR}/lib/project-root.sh"
GOV_DIR="$(get_governance_state_dir)"
emit_event "session_end" '{"trigger":"SessionEnd","path":"fallback"}' source="governance-cleanup.sh" || true
cleanup_dir "$GOV_DIR"

exit 0
