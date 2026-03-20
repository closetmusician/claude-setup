#!/bin/bash
# ABOUTME: Auto-journaling Stop hook for Claude Code.
# ABOUTME: Reads Stop event JSON from stdin, parses the session transcript,
# ABOUTME: and appends a timestamped summary entry to the journal file.
# ABOUTME: Designed to be fast (<1s) and fail silently on malformed input.
# ABOUTME: Journal location: ~/.claude/memory/journal.md

set -euo pipefail

JOURNAL_FILE="$HOME/.claude/memory/journal.md"
TAIL_LINES=500

# Fail silently on any error — this hook must never block Claude.
trap 'exit 0' ERR

# Read Stop event JSON from stdin.
# Claude Code pipes JSON and closes stdin, so cat returns immediately.
INPUT=$(cat 2>/dev/null || echo '{}')

# Validate we got parseable JSON.
if ! echo "$INPUT" | jq -e '.' > /dev/null 2>&1; then
  exit 0
fi

# Skip journaling if this is a stop-hook continuation (prevent noise).
STOP_HOOK_ACTIVE=$(echo "$INPUT" | jq -r '.stop_hook_active // false')
if [ "$STOP_HOOK_ACTIVE" = "true" ]; then
  exit 0
fi

# Extract fields from the Stop event.
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // "unknown"' | cut -c1-8)
TRANSCRIPT_PATH=$(echo "$INPUT" | jq -r '.transcript_path // ""')
CWD=$(echo "$INPUT" | jq -r '.cwd // "unknown"')

# Derive project name from cwd.
PROJECT="${CWD##*/}"

# Parse transcript for tool/file info (only tail for speed).
TOOLS=""
FILES=""
ERROR_COUNT=0

if [ -n "$TRANSCRIPT_PATH" ] && [ -f "$TRANSCRIPT_PATH" ]; then
  # Extract unique tool names from recent assistant messages.
  # Note: macOS paste -d cycles delimiters, so use awk for reliable joining.
  TOOLS=$(tail -n "$TAIL_LINES" "$TRANSCRIPT_PATH" 2>/dev/null \
    | jq -r 'select(.type == "assistant") | .message.content[]? | select(.type == "tool_use") | .name' 2>/dev/null \
    | sort -u \
    | awk 'NR>1{printf ", "}{printf "%s", $0}END{print ""}' 2>/dev/null || echo "")

  # Extract unique file paths from Edit/Write tool calls.
  FILES=$(tail -n "$TAIL_LINES" "$TRANSCRIPT_PATH" 2>/dev/null \
    | jq -r 'select(.type == "assistant") | .message.content[]? | select(.type == "tool_use") | select(.name == "Edit" or .name == "Write") | .input.file_path' 2>/dev/null \
    | sort -u \
    | sed "s|$HOME|~|g" \
    | awk 'NR>1{printf ", "}{printf "%s", $0}END{print ""}' 2>/dev/null || echo "")

  # Count tool results with is_error=true.
  ERROR_COUNT=$(tail -n "$TAIL_LINES" "$TRANSCRIPT_PATH" 2>/dev/null \
    | jq -r 'select(.type == "user") | .message.content[]? | select(.type == "tool_result" and .is_error == true)' 2>/dev/null \
    | jq -s 'length' 2>/dev/null || echo "0")
fi

# Apply defaults for empty values.
[ -z "$TOOLS" ] && TOOLS="none detected"
[ -z "$FILES" ] && FILES="none"
[ -z "$ERROR_COUNT" ] && ERROR_COUNT=0

# Format error line.
if [ "$ERROR_COUNT" -eq 0 ]; then
  ERROR_LINE="none"
else
  ERROR_LINE="$ERROR_COUNT error(s)"
fi

# Ensure journal file and directory exist.
mkdir -p "$(dirname "$JOURNAL_FILE")"
if [ ! -f "$JOURNAL_FILE" ]; then
  printf '# Claude Code Session Journal\n\nAppend-only log of session activity. Searchable by date, file, tool, or error.\n\n---\n' > "$JOURNAL_FILE"
fi

# Build and append journal entry.
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

cat >> "$JOURNAL_FILE" <<EOF
## $TIMESTAMP — $PROJECT ($SESSION_ID)
- **Files:** $FILES
- **Tools:** $TOOLS
- **Errors:** $ERROR_LINE
---
EOF

exit 0
