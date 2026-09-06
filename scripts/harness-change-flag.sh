#!/usr/bin/env bash
# ABOUTME: PostToolUse hook (Phase 6.3): marks harness dirs dirty when Claude writes/edits them.
# ABOUTME: Matches Write and Edit tool calls; resolves ~/$HOME/relative paths canonically.
# ABOUTME: Appends resolved path to ~/.claude/state/.harness-dirty (deduped). Log-only, fail-open.
# ABOUTME: Target dirs: ~/.claude/rules/, ~/.claude/scripts/, ~/.claude/skills/. <50ms by design.
# ABOUTME: BSD/macOS compatible. Never blocks. exit 0 always.

set -uo pipefail
trap 'exit 0' ERR

command -v jq >/dev/null 2>&1 || exit 0

CLAUDE_DIR="${CLAUDE_DIR:-$HOME/.claude}"
DIRTY_FILE="$CLAUDE_DIR/state/.harness-dirty"

INPUT=$(cat 2>/dev/null) || exit 0
[[ -z "$INPUT" ]] && exit 0

# ── Extract file_path from tool input ────────────────────────────────────────
RAW_PATH=$(printf '%s' "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null) || exit 0
[[ -z "$RAW_PATH" ]] && exit 0

# ── Resolve path: tilde, $HOME prefix, absolute, or relative to CLAUDE_DIR ──
resolve_path() {
  # Purpose: canonicalize a path that may use ~, $HOME, or be relative.
  # Gotchas: MASTER-36 / BUG-SEAMS-05 — use $CLAUDE_DIR as the effective home base for
  #   tilde/HOME expansion so test isolation (CLAUDE_DIR=/tmp/...) produces paths inside
  #   the test tree rather than leaking into $HOME/.claude.
  local p="$1"
  local effective_home
  effective_home="${CLAUDE_DIR:-$HOME}"
  # Strip trailing /.claude from CLAUDE_DIR to get the parent dir for tilde expansion
  # e.g. CLAUDE_DIR=/home/foo/.claude → effective_home_parent=/home/foo
  # If CLAUDE_DIR is the harness dir (ends in /.claude), strip that suffix.
  local effective_home_parent="${effective_home%/.claude}"
  case "$p" in
    "~/.claude/"*) echo "${effective_home}/${p:10}" ;;
    "~/"*)         echo "${effective_home_parent}/${p:2}" ;;
    "~")           echo "$effective_home_parent" ;;
    "\$HOME/.claude/"*) echo "${effective_home}/${p:14}" ;;
    "\$HOME/"*)    echo "${effective_home_parent}/${p:6}" ;;
    /*)            echo "$p" ;;
    *)
      # Relative — try relative to CLAUDE_DIR first, then PWD
      if [[ -n "${CLAUDE_DIR:-}" ]]; then
        echo "$CLAUDE_DIR/$p"
      else
        echo "$PWD/$p"
      fi
      ;;
  esac
}

ABS_PATH=$(resolve_path "$RAW_PATH")

# ── Check if path is under one of the three harness dirs ─────────────────────
RULES_DIR="${CLAUDE_DIR}/rules"
SCRIPTS_DIR="${CLAUDE_DIR}/scripts"
SKILLS_DIR="${CLAUDE_DIR}/skills"

is_under_harness() {
  local p="$1"
  case "$p" in
    "${RULES_DIR}/"*|"${SCRIPTS_DIR}/"*|"${SKILLS_DIR}/"*) return 0 ;;
    "${RULES_DIR}"|"${SCRIPTS_DIR}"|"${SKILLS_DIR}")        return 0 ;;
    *) return 1 ;;
  esac
}

is_under_harness "$ABS_PATH" || exit 0

# ── Append to dirty file (dedupe) ────────────────────────────────────────────
mkdir -p "$(dirname "$DIRTY_FILE")" 2>/dev/null || exit 0

# Check for existing entry before appending (dedupe)
if [[ -f "$DIRTY_FILE" ]] && grep -qxF "$ABS_PATH" "$DIRTY_FILE" 2>/dev/null; then
  exit 0
fi

printf '%s\n' "$ABS_PATH" >> "$DIRTY_FILE" 2>/dev/null || true

exit 0
