#!/usr/bin/env bash
# ABOUTME: Shared helper — worktree-safe project root + governance state dir resolution.
# ABOUTME: Sourced by scripts/lib/ scripts (e.g. skill-retrieve.sh) to get per-project paths.
# ABOUTME: Delegates to scripts/governance/lib/project-root.sh when reachable; standalone fallback.
# ABOUTME: Exposes: get_project_root(), get_governance_state_dir()
# ABOUTME: Never errors — always returns a path. Honors HARNESS_GOV_STATE_DIR for isolation.

_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)"

# Prefer the canonical governance version if it exists (single source of truth)
_GOV_LIB="${_LIB_DIR}/../governance/lib/project-root.sh"
if [ -f "$_GOV_LIB" ]; then
  # shellcheck source=/dev/null
  source "$_GOV_LIB" 2>/dev/null || true
fi

# Define fallbacks if the governance source didn't define them
if ! declare -f get_project_root >/dev/null 2>&1; then
  get_project_root() {
    git rev-parse --show-toplevel 2>/dev/null || echo "$PWD"
  }
fi

if ! declare -f get_governance_state_dir >/dev/null 2>&1; then
  # Honors HARNESS_GOV_STATE_DIR override when set (non-empty) — test isolation.
  get_governance_state_dir() {
    if [[ -n "${HARNESS_GOV_STATE_DIR:-}" ]]; then
      echo "$HARNESS_GOV_STATE_DIR"
      return
    fi
    echo "$(get_project_root)/.agents/claude-governance"
  }
fi
