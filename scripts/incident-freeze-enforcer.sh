#!/bin/bash
# ABOUTME: PreToolUse hook enforcing incident freeze on all external mutations.
# ABOUTME: When /tmp/.claude-incident-freeze exists, blocks curl POST/PUT/PATCH/DELETE to external URLs.
# ABOUTME: Also blocks node scripts targeting external services (upload, send, edit).
# ABOUTME: Allows local-only commands (ls, cat, git, etc.) and rm of the freeze file itself.
# ABOUTME: Requires: jq. See docs/nerf-prevention.md section P1-4.

set -euo pipefail

# Safety net: never break the session on hook failure (matches detector).
trap 'exit 0' ERR

FREEZE_FILE="/tmp/.claude-incident-freeze"

# Bail gracefully if jq is missing.
if ! command -v jq &>/dev/null; then
  echo "incident-freeze-enforcer: jq not found, skipping" >&2
  exit 0
fi

# Read the tool-call JSON from stdin.
INPUT=$(cat)

# Extract tool name. Only inspect Bash calls.
TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // empty')
if [[ "$TOOL_NAME" != "Bash" ]]; then
  exit 0
fi

# Extract the command string from tool_input.
CMD=$(echo "$INPUT" | jq -r '.tool_input.command // empty')

# Nothing to check if the command is empty.
if [[ -z "$CMD" ]]; then
  exit 0
fi

# If no freeze file exists, allow everything.
if [[ ! -f "$FREEZE_FILE" ]]; then
  exit 0
fi

# --- FROZEN: Decide allow vs. block ---

# deny_and_exit <reason>
# Outputs hookSpecificOutput JSON to deny the tool call, exits 2.
deny_and_exit() {
  local reason="$1"
  jq -n \
    --arg reason "$reason" \
    '{
      "hookSpecificOutput": {
        "hookEventName": "PreToolUse",
        "permissionDecision": "deny",
        "permissionDecisionReason": $reason
      }
    }'
  exit 2
}

# ALWAYS allow: rm of the freeze file (user release mechanism).
if echo "$CMD" | grep -qE 'rm\s+(-[a-zA-Z]+\s+)*/?/tmp/\.claude-incident-freeze'; then
  exit 0
fi

# BLOCK: gh api with mutation methods (before safe-list so gh api -X DELETE is caught).
if echo "$CMD" | grep -qE 'gh[[:space:]]+api[[:space:]].*(-X|--request|--method)[[:space:]]*(POST|PUT|PATCH|DELETE)'; then
  deny_and_exit "INCIDENT FREEZE: gh api mutation blocked. A destructive operation succeeded but recovery failed. All external mutations are halted until freeze is released. Run: rm ${FREEZE_FILE}"
fi

# ALLOW: Local-only commands that cannot affect external state.
# Extract the base command (first word, ignoring env vars and leading whitespace).
BASE_CMD=$(echo "$CMD" | sed 's/^[[:space:]]*//' | sed 's/^[A-Z_]*=[^ ]* //' | awk '{print $1}')

# Known safe local commands.
LOCAL_SAFE_CMDS="ls|cat|head|tail|less|more|grep|rg|find|echo|printf|wc|sort|uniq|diff|file|stat|readlink|realpath|pwd|whoami|id|date|which|type|true|false|test|read|mkdir|touch|cp|mv|sed|awk|perl|tee|xargs|tr|cut|paste|basename|dirname|env|set|export|cd|pushd|popd|history|alias|source|jq|yq"
GIT_CMDS="git|gh"
SAFE_PATTERN="^(${LOCAL_SAFE_CMDS}|${GIT_CMDS})$"

if echo "$BASE_CMD" | grep -qE "$SAFE_PATTERN"; then
  exit 0
fi

# Python/Node with only local args (no URLs).
if echo "$BASE_CMD" | grep -qE '^(python3?|node)$'; then
  # If the command does NOT contain any external URL pattern, allow it.
  if ! echo "$CMD" | grep -qE '(https?://|\.com|\.io|\.net|\.org|\.microsoft\.|\.sharepoint\.|graph\.)'; then
    exit 0
  fi
fi

# Anything with curl using mutation methods to external URLs -> block.
if echo "$CMD" | grep -qE 'curl.*(-X|--request)[[:space:]]*(POST|PUT|PATCH|DELETE)'; then
  deny_and_exit "INCIDENT FREEZE: External mutation blocked. A destructive operation succeeded but recovery failed. All external mutations are halted until freeze is released. Run: rm ${FREEZE_FILE}"
fi

# curl with implicit POST data flags (no explicit -X) to external URLs -> block.
# These flags cause curl to use POST/PUT implicitly: -d, --data*, -F, --form, --upload-file, -T.
if echo "$CMD" | grep -qE 'curl.*(--data-binary|--data-raw|--data-urlencode|--data|--upload-file|--form|-d[[:space:]]|-F[[:space:]]|-T[[:space:]])'; then
  # Only block if targeting an external URL (not localhost/127.0.0.1).
  if echo "$CMD" | grep -qE 'https?://' && ! echo "$CMD" | grep -qE 'https?://(localhost|127\.0\.0\.1)'; then
    deny_and_exit "INCIDENT FREEZE: External mutation blocked (implicit POST). A destructive operation succeeded but recovery failed. All external mutations are halted until freeze is released. Run: rm ${FREEZE_FILE}"
  fi
fi

# wget with POST data flags to external URLs -> block.
if echo "$CMD" | grep -qE 'wget.*(--post-data|--post-file).*https?://'; then
  deny_and_exit "INCIDENT FREEZE: External mutation blocked (wget POST). A destructive operation succeeded but recovery failed. All external mutations are halted until freeze is released. Run: rm ${FREEZE_FILE}"
fi

# Node scripts that target external services (upload, send, edit with URLs).
if echo "$CMD" | grep -qE 'node.*\.(js|mjs)'; then
  if echo "$CMD" | grep -qiE '(upload|send|delete|remove|create|edit|add|update|patch|post|put)'; then
    deny_and_exit "INCIDENT FREEZE: External node script blocked. A destructive operation succeeded but recovery failed. All external mutations are halted until freeze is released. Run: rm ${FREEZE_FILE}"
  fi
  if echo "$CMD" | grep -qE '(https?://|\.com|\.io|\.net|\.org|\.microsoft\.|\.sharepoint\.)'; then
    deny_and_exit "INCIDENT FREEZE: Node script with external URL blocked. All external mutations are halted until freeze is released. Run: rm ${FREEZE_FILE}"
  fi
fi

# uv/pip/pipx running scripts that might hit external services.
if echo "$CMD" | grep -qE '(uv run|pipx run)'; then
  if echo "$CMD" | grep -qE '(https?://|\.com|\.io|\.net|\.org|\.microsoft\.|\.sharepoint\.)'; then
    deny_and_exit "INCIDENT FREEZE: Python tool with external URL blocked. All external mutations are halted until freeze is released. Run: rm ${FREEZE_FILE}"
  fi
fi

# Default: allow commands not matching any block pattern.
# This ensures local-only work continues during freeze.
exit 0
