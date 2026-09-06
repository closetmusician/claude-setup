#!/usr/bin/env bash
# ABOUTME: Shared helper for worktree-safe project root detection.
# ABOUTME: Sourced by all governance scripts to resolve per-project state paths.
# ABOUTME: Uses git rev-parse --show-toplevel (correct for worktrees) with $PWD fallback.
# ABOUTME: Returns the project root directory — never the main repo when inside a worktree.
# ABOUTME: Single source of truth; honors HARNESS_GOV_STATE_DIR override for test isolation.

get_project_root() {
  git rev-parse --show-toplevel 2>/dev/null || echo "$PWD"
}

# Convenience: resolve the per-project governance state directory.
# Usage: STATE_DIR="$(get_governance_state_dir)"
# Honors HARNESS_GOV_STATE_DIR override when set (non-empty) — allows test suites
# to point at a mktemp scratch dir instead of the live governance state.
get_governance_state_dir() {
  if [[ -n "${HARNESS_GOV_STATE_DIR:-}" ]]; then
    echo "$HARNESS_GOV_STATE_DIR"
    return
  fi
  echo "$(get_project_root)/.agents/claude-governance"
}
