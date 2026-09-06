#!/bin/bash
# ABOUTME: PreToolUse hook blocking destructive remote API patterns (Graph, SharePoint).
# ABOUTME: Reads JSON from stdin, checks Bash commands against banned-pattern regexes.
# ABOUTME: Exits 2 (deny) with hookSpecificOutput JSON when a destructive pattern matches.
# ABOUTME: Exits 0 (allow) for clean commands or non-Bash tools.
# ABOUTME: Requires: jq, perl. See docs/nerf-prevention.md section 4.1.1.

set -euo pipefail
# Fail-open: any unhandled error (e.g. jq parse failure on malformed stdin) exits 0.
trap 'exit 0' ERR

# Bail gracefully if jq is missing -- do not block legitimate work.
if ! command -v jq &>/dev/null; then
  echo "remote-destructive-hook: jq not found, skipping checks" >&2
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

# Strip heredoc bodies and quoted strings to avoid false positives on
# text like 'curl -X DELETE ...' inside echo output or heredocs.
# Replace <<[-]?'?DELIM'?...DELIM blocks with a placeholder (any word
# delimiter, not just EOF). Then strip double-quoted and single-quoted strings.
STRIPPED=$(echo "$CMD" \
  | perl -0777 -pe "s/<<-?'?(\w+)'?.*?^\t*\1\$/__HEREDOC__/gms" \
  | sed "s/\"[^\"]*\"/__STR__/g; s/'[^']*'/__STR__/g")

# deny_and_exit <reason>
# Outputs hookSpecificOutput JSON that tells Claude Code to deny the
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
# Patterns that represent actual code/commands (bypass-shared-lock, requests.delete,
# urllib, graph-file-ops) are checked against the RAW command. These are dangerous
# even inside -c '...' or -H '...' arguments.
#
# Curl DELETE patterns (REQ-001, 002, 006) are checked against the STRIPPED command
# to avoid false positives on echo/heredoc text that merely mentions DELETE.

# REQ-003: bypass-shared-lock (check RAW — this header is ALWAYS dangerous)
if echo "$CMD" | grep -qi 'bypass-shared-lock'; then
  deny_and_exit "BLOCKED: Command contains 'bypass-shared-lock'. This header force-deletes locked files. See docs/nerf-prevention.md."
fi

if echo "$CMD" | grep -qiE '(BypassSharedLock|CreateCopyJobs|Prefer:[[:space:]]*bypass-shared-lock)'; then
  deny_and_exit "BLOCKED: SharePoint/Graph bypass-lock or copy-job behavior is prohibited."
fi

if echo "$CMD" | grep -qiE '(_api/[^[:space:]]*/Recycle|/restore\b|restore\(|moveTo\(|copy-over-original|rename-overwrite|copy-over)'; then
  if echo "$CMD" | grep -qiE '(graph\.microsoft\.com|sharepoint\.com|\.sharepoint\.)'; then
    deny_and_exit "BLOCKED: SharePoint/Graph recycle, restore, move, rename-overwrite, or copy-over behavior is prohibited."
  fi
fi

# REQ-004: Python requests.delete( (check RAW — code inside -c '...' gets stripped)
if echo "$CMD" | grep -qE 'requests\.delete\('; then
  deny_and_exit "BLOCKED: requests.delete() detected. Remote deletion via Python requests is prohibited. See docs/nerf-prevention.md."
fi

# REQ-004: Python urllib DELETE to sharepoint (check RAW)
# URL and method= can appear in either order in Request(), so check all three tokens.
if echo "$CMD" | grep -qE 'urllib\.request\.Request' && \
   echo "$CMD" | grep -q 'DELETE' && \
   echo "$CMD" | grep -qi 'sharepoint'; then
  deny_and_exit "BLOCKED: urllib DELETE to SharePoint detected. Remote deletion is prohibited. See docs/nerf-prevention.md."
fi

# REQ-004: Python urllib DELETE to graph.microsoft (check RAW)
if echo "$CMD" | grep -qE 'urllib\.request\.Request' && \
   echo "$CMD" | grep -q 'DELETE' && \
   echo "$CMD" | grep -qi 'graph\.microsoft'; then
  deny_and_exit "BLOCKED: urllib DELETE to Graph API detected. Remote deletion is prohibited. See docs/nerf-prevention.md."
fi

# REQ-005: graph-file-ops delete/remove (check RAW — NOT graph-list-crud, that's legitimate)
if echo "$CMD" | grep -qE 'graph-file-ops.*delete'; then
  deny_and_exit "BLOCKED: graph-file-ops delete command. Remote file deletion is prohibited. See docs/nerf-prevention.md."
fi

if echo "$CMD" | grep -qE 'graph-file-ops.*remove'; then
  deny_and_exit "BLOCKED: graph-file-ops remove command. Remote file removal is prohibited. See docs/nerf-prevention.md."
fi

# is_curl_delete <string>
# Detects curl with any DELETE method variant, order-independent and
# case-insensitive. Covers: -X DELETE, -XDELETE, --request DELETE,
# --request=DELETE, and any spacing/case combination.
is_curl_delete() {
  echo "$1" | grep -qiE '\bcurl\b' && \
  echo "$1" | grep -qiE '(-X[[:space:]]*DELETE\b|--request[[:space:]]+DELETE\b|--request=DELETE\b)'
}

# REQ-001, REQ-002, REQ-006: curl DELETE to protected domains.
# Two-step: (1) detect curl + DELETE method, (2) check target domain.
# Order-independent — works regardless of whether URL or flag comes first.
# Checked against STRIPPED to avoid false positives on echo/heredoc text.
if is_curl_delete "$STRIPPED"; then
  if echo "$STRIPPED" | grep -qiE 'graph\.microsoft\.com'; then
    deny_and_exit "BLOCKED: curl DELETE to graph.microsoft.com. Remote file deletion is prohibited. See docs/nerf-prevention.md."
  fi
  if echo "$STRIPPED" | grep -qiE 'sharepoint\.com'; then
    deny_and_exit "BLOCKED: curl DELETE to sharepoint.com. Remote file deletion is prohibited. See docs/nerf-prevention.md."
  fi
  if echo "$STRIPPED" | grep -qiE '\.sharepoint\.'; then
    deny_and_exit "BLOCKED: DELETE request to .sharepoint. domain. Remote deletion is prohibited. See docs/nerf-prevention.md."
  fi
  if echo "$STRIPPED" | grep -qiE '\.microsoft\.'; then
    deny_and_exit "BLOCKED: DELETE request to .microsoft. domain. Remote deletion is prohibited. See docs/nerf-prevention.md."
  fi
  if echo "$STRIPPED" | grep -qiE '\.graph\.'; then
    deny_and_exit "BLOCKED: DELETE request to .graph. domain. Remote deletion is prohibited. See docs/nerf-prevention.md."
  fi
fi

# All checks passed -- allow the command.
exit 0
