#!/bin/bash
# ABOUTME: Weekly cleanup script that removes stale debug logs, telemetry, and artifacts.
# ABOUTME: Enforces 14-day retention on debug/, telemetry/, shell-snapshots/, file-history/.
# ABOUTME: Removes empty files from projects/*/qa/ directories.
# ABOUTME: Never deletes protected files listed in ~/.claude/rules/protected-files.md.
# ABOUTME: Logs deletion counts and freed space to ~/.claude/logs/cleanup.log.

set -euo pipefail

# Cleanup failure should never block anything.
trap 'exit 0' ERR

CLAUDE_DIR="$HOME/.claude"
LOG_FILE="$CLAUDE_DIR/logs/cleanup.log"
RETENTION_DAYS=14
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

# Protected files that must never be deleted (absolute paths).
PROTECTED_FILES=(
  "$CLAUDE_DIR/docs/vibe-manual.md"
  "$CLAUDE_DIR/rules/vibe-protocol.md"
  "$CLAUDE_DIR/rules/code-style.md"
  "$CLAUDE_DIR/rules/protected-files.md"
  "$CLAUDE_DIR/CLAUDE.md"
)

# Ensure log directory exists.
mkdir -p "$(dirname "$LOG_FILE")"

# is_protected <filepath>
# Returns 0 (true) if the file is in the protected list, 1 otherwise.
is_protected() {
  local target
  target=$(realpath "$1" 2>/dev/null || echo "$1")
  for pf in "${PROTECTED_FILES[@]}"; do
    local resolved
    resolved=$(realpath "$pf" 2>/dev/null || echo "$pf")
    if [ "$target" = "$resolved" ]; then
      return 0
    fi
  done
  return 1
}

# cleanup_old_files <directory> <label>
# Finds and deletes files older than RETENTION_DAYS in the given directory.
# Skips protected files. Logs count and freed bytes.
cleanup_old_files() {
  local dir="$1"
  local label="$2"
  local count=0
  local freed=0

  if [ ! -d "$dir" ]; then
    return
  fi

  while IFS= read -r -d '' file; do
    if is_protected "$file"; then
      continue
    fi
    local size
    size=$(stat -f%z "$file" 2>/dev/null || echo 0)
    rm -f "$file" 2>/dev/null && {
      count=$((count + 1))
      freed=$((freed + size))
    }
  done < <(find "$dir" -type f -mtime +"$RETENTION_DAYS" -print0 2>/dev/null)

  if [ "$count" -gt 0 ]; then
    echo "[$TIMESTAMP] $label: deleted $count files, freed $((freed / 1024))KB" >> "$LOG_FILE"
  fi
}

# cleanup_empty_files <glob_pattern> <label>
# Removes empty (0-byte) files matching the pattern. Skips protected files.
cleanup_empty_files() {
  local dir="$1"
  local label="$2"
  local count=0

  if [ ! -d "$dir" ]; then
    return
  fi

  while IFS= read -r -d '' file; do
    if is_protected "$file"; then
      continue
    fi
    rm -f "$file" 2>/dev/null && count=$((count + 1))
  done < <(find "$dir" -type f -empty -print0 2>/dev/null)

  if [ "$count" -gt 0 ]; then
    echo "[$TIMESTAMP] $label: removed $count empty files" >> "$LOG_FILE"
  fi
}

echo "[$TIMESTAMP] === Weekly cleanup started ===" >> "$LOG_FILE"

# 1. Debug logs older than 14 days.
cleanup_old_files "$CLAUDE_DIR/debug" "debug-logs"

# 2. Empty files in projects/*/qa/ directories.
for qa_dir in "$CLAUDE_DIR"/projects/*/qa/ ; do
  [ -d "$qa_dir" ] && cleanup_empty_files "$qa_dir" "empty-qa-artifacts"
done

# 3. Stale telemetry (if directory exists).
cleanup_old_files "$CLAUDE_DIR/telemetry" "telemetry"

# 4. Old session snapshots.
cleanup_old_files "$CLAUDE_DIR/shell-snapshots" "shell-snapshots"

# 5. Old file-history entries.
cleanup_old_files "$CLAUDE_DIR/file-history" "file-history"

echo "[$TIMESTAMP] === Weekly cleanup finished ===" >> "$LOG_FILE"

exit 0
