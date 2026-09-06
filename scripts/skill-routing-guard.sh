#!/usr/bin/env bash
# ABOUTME: PreToolUse hook that catches git commit / PR / push commands that should
# ABOUTME: route through the /ship skill instead of being run directly.
# ABOUTME: Reads JSON from stdin, checks Bash commands against ship-workflow patterns.
# ABOUTME: Exits 2 (blocking) with deny JSON on stdout if pattern matched.
# ABOUTME: Add '# SKILL-BYPASS' to the command to intentionally bypass this guard.

set -euo pipefail
# Fail-open: any unhandled error (e.g. jq parse failure on malformed stdin) exits 0.
trap 'exit 0' ERR

# Bail gracefully if jq is missing -- do not block legitimate work.
if ! command -v jq &>/dev/null; then
  echo "skill-routing-guard: jq not found, skipping checks" >&2
  exit 0
fi

# Pillar I emit — purely additive; fail-open via emit_event design + || true guard.
_SKILL_EMIT_SH="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/emit-event.sh"
# shellcheck disable=SC1090
[[ -f "$_SKILL_EMIT_SH" ]] && source "$_SKILL_EMIT_SH" 2>/dev/null || true
unset _SKILL_EMIT_SH

# Read the tool-call JSON from stdin.
INPUT=$(cat)
# Expose stdin JSON to emit-event.sh so it can resolve session_id from the real payload
# rather than defaulting to "unknown". MASTER-38 / BUG-SPINE-09 fix.
export HOOK_STDIN_JSON="$INPUT"

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

# Allow bypass: if the command contains '# SKILL-BYPASS', let it through.
if echo "$CMD" | grep -qF '# SKILL-BYPASS'; then
  exit 0
fi

# Strip heredoc bodies and quoted strings to avoid false positives on
# text like 'git commit' inside commit messages or echo output.
STRIPPED=$(echo "$CMD" | perl -0777 -pe "s/<<'?EOF'?.*?^EOF\$/__HEREDOC__/gms" | sed "s/\"[^\"]*\"/__STR__/g; s/'[^']*'/__STR__/g")

# deny_and_exit <reason>
# Outputs a hookSpecificOutput JSON blob that tells Claude Code to deny the
# tool call, then exits with code 2 so the call is blocked.
deny_and_exit() {
  local reason="$1"
  # Emit incident on deny — purely additive; before deny JSON output.
  emit_event "incident" '{"class":"skill_routing_deny","guard":"skill-routing-guard"}' \
    outcome="denied" source="skill-routing-guard.sh" || true
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

# 1. gh pr create → use /pr-briefing
if echo "$STRIPPED" | grep -qE '\bgh\s+pr\s+create\b'; then
  deny_and_exit "SKILL ROUTING GUARD: 'gh pr create' matches 'Generate PR briefing after PR creation' workflow. Use /pr-briefing skill first (see skill-routing.md). Add # SKILL-BYPASS to the command if intentionally bypassing."
fi

# All checks passed -- allow the command.
exit 0
