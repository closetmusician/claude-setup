#!/bin/bash
# ABOUTME: PreToolUse hook that blocks unauthorized external messaging via Graph API.
# ABOUTME: Reads JSON from stdin, checks Bash commands against messaging endpoint patterns.
# ABOUTME: Sanctioned tools (run-send.js, teams-send-chat.js, outlook-send-mail.js) bypass.
# ABOUTME: Exits 2 (blocking) with deny JSON on stdout when pattern matches.
# ABOUTME: Exits 0 (allow) for clean commands, non-Bash tools, or sanctioned tools.

set -euo pipefail
# Fail-open: any unhandled error (e.g. jq parse failure on malformed stdin) exits 0.
trap 'exit 0' ERR

# Bail gracefully if jq is missing -- do not block legitimate work.
if ! command -v jq &>/dev/null; then
  echo "external-comms-hook: jq not found, skipping checks" >&2
  exit 0
fi

# Read the tool-call JSON from stdin.
INPUT=$(cat)

# Extract tool name. PreToolUse provides it as "tool_name".
TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // empty')

# Only inspect Bash calls -- everything else passes through.
if [[ "$TOOL_NAME" != "Bash" ]]; then
  exit 0
fi

# Extract the command string from tool_input.
CMD=$(echo "$INPUT" | jq -r '.tool_input.command // empty')

# Nothing to check if the command is empty.
if [[ -z "$CMD" ]]; then
  exit 0
fi

# --- Sanctioned tool exceptions ---
# These tools have their own approval gates. If the command invokes one,
# skip all block checks. This lets `node ~/Code/pm_os/bin/run-send.js`
# through while blocking raw `curl -X POST graph.microsoft.com/.../chats`.
SANCTIONED_TOOLS=(
  "run-send.js"
  "teams-send-chat.js"
  "outlook-send-mail.js"
)
# Collapse newlines and carriage returns so `^` in grep -qE matches only
# the true start of the full command, not start-of-any-embedded-line.
# Without this, an attacker can put a sanctioned tool name on a separate
# line to bypass all block pattern checks.  (P0-002 fix)
CMD_FLAT=$(printf '%s' "$CMD" | tr '\n\r' '  ')

# Match only when the tool is the primary executable — the argument to
# `node` at a command boundary, or invoked directly as a script. The tool
# must appear right after: start-of-string, &&, ||, ;, or | (with optional
# whitespace and an optional `node <path>/` prefix). This prevents bypass
# via chain operators, comments, variable assignments, curl bodies, and
# newline injection.
for tool in "${SANCTIONED_TOOLS[@]}"; do
  escaped=$(printf '%s' "$tool" | sed 's/\./\\./g')
  if echo "$CMD_FLAT" | grep -qE "(^|&&|\|\||;|\|)\s*(node\s+\S*/)?${escaped}(\s|$)"; then
    exit 0
  fi
done

# Strip heredoc bodies and quoted strings to reduce false positives on
# text like 'graph.microsoft.com/chats' inside commit messages or echo output.
# Replace heredoc blocks with any word delimiter (<<EOF, <<'HERE', <<DOC, etc.)
# using a backreference, then strip double-quoted and single-quoted strings.
STRIPPED=$(echo "$CMD" | perl -0777 -pe "s/<<'?(\w+)'?.*?^\1\$/__HEREDOC__/gms" | sed "s/\"[^\"]*\"/__STR__/g; s/'[^']*'/__STR__/g")

# deny_and_exit <reason>
# Outputs a hookSpecificOutput JSON blob that tells Claude Code to deny the
# tool call, then exits with code 2 so the call is blocked.
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

# --- Block pattern checks ---

# 1. graph.microsoft.com.*/chats
if echo "$STRIPPED" | grep -qiE 'graph\.microsoft\.com.*/chats'; then
  deny_and_exit "Blocked: unauthorized access to Graph API /chats endpoint. Use a sanctioned messaging tool (run-send.js, teams-send-chat.js) instead."
fi

# 2. graph.microsoft.com.*/messages
if echo "$STRIPPED" | grep -qiE 'graph\.microsoft\.com.*/messages'; then
  deny_and_exit "Blocked: unauthorized access to Graph API /messages endpoint. Use a sanctioned messaging tool (run-send.js, outlook-send-mail.js) instead."
fi

# 3. graph.microsoft.com.*/sendMail
if echo "$STRIPPED" | grep -qiE 'graph\.microsoft\.com.*/sendMail'; then
  deny_and_exit "Blocked: unauthorized access to Graph API /sendMail endpoint. Use outlook-send-mail.js via run-send.js instead."
fi

# 4. teams.*send.*message
if echo "$STRIPPED" | grep -qiE 'teams.*send.*message'; then
  deny_and_exit "Blocked: detected Teams send-message pattern. Use teams-send-chat.js via run-send.js instead."
fi

# 5. chat.*create.*member
if echo "$STRIPPED" | grep -qiE 'chat.*create.*member'; then
  deny_and_exit "Blocked: detected chat create-member pattern. This operation requires explicit user approval."
fi

# All checks passed -- allow the command.
exit 0
