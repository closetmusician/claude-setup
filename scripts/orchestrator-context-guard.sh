#!/usr/bin/env bash
# ABOUTME: PreToolUse hook that prevents the orchestrator from reading large files directly.
# ABOUTME: Subagents (identified by agent_id in hook input) always pass through.
# ABOUTME: Orchestrator calls on spec/plan/PRD files are graduated: <30 lines allow,
# ABOUTME: 30-100 soft warning, >100 hard deny with delegation guidance.
# ABOUTME: Requires: jq. Falls back to allow-all if jq is missing or any error occurs.

set -euo pipefail

# Safety net: never block on hook failure.
trap 'exit 0' ERR

# Bail gracefully if jq is missing.
if ! command -v jq &>/dev/null; then
  echo "orchestrator-context-guard: jq not found, skipping checks" >&2
  exit 0
fi

# Read the tool-call JSON from stdin.
INPUT=$(cat)

# Subagents have agent_id set. If present, always allow.
AGENT_ID=$(echo "$INPUT" | jq -r '.agent_id // empty')
if [[ -n "$AGENT_ID" ]]; then
  exit 0
fi

# Extract tool name.
TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // empty')

# Only guard Read, Grep, Glob.
case "$TOOL_NAME" in
  Read|Grep|Glob) ;;
  *) exit 0 ;;
esac

# Extract file path from tool_input.
# Read uses file_path; Grep/Glob use path.
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // .tool_input.path // empty')

# No path to check -- allow.
if [[ -z "$FILE_PATH" ]]; then
  exit 0
fi

# Normalize: resolve ~ and make path comparable.
# Strip trailing slashes for consistent matching.
FILE_PATH="${FILE_PATH%/}"

# ─── ALWAYS_ALLOW patterns ───
# Config, QA artifacts, logs, templates, backlog, spec registry.
always_allow() {
  local p="$1"
  case "$p" in
    */.claude/phase.json)   return 0 ;;
    */.claude/*)            return 0 ;;
    */qa/*-ready-for-review.md)  return 0 ;;
    */qa/*-cycle-*.md)      return 0 ;;
    */logs/*)               return 0 ;;
    */templates/*)          return 0 ;;
    */docs/spec-registry.yaml)   return 0 ;;
    */docs/backlog.md)      return 0 ;;
  esac
  return 1
}

if always_allow "$FILE_PATH"; then
  exit 0
fi

# ─── BLOCKED patterns (spec/plan/PRD files) ───
# Case-insensitive match on path components.
is_blocked_pattern() {
  local p="$1"
  local lower_p
  lower_p=$(echo "$p" | tr '[:upper:]' '[:lower:]')

  case "$lower_p" in
    */docs/prd/*)       return 0 ;;
    */docs/plans/*)     return 0 ;;
    */docs/contracts/*) return 0 ;;
  esac

  # Check filename patterns: PRD, spec, design (case insensitive).
  local basename_lower
  basename_lower=$(basename "$lower_p")
  case "$basename_lower" in
    *prd*.md)    return 0 ;;
    *spec*.md)   return 0 ;;
    *design*.md) return 0 ;;
  esac

  return 1
}

# ─── Helper: get line count safely ───
get_line_count() {
  local p="$1"
  if [[ -f "$p" ]]; then
    wc -l < "$p" | tr -d ' '
  else
    echo "0"
  fi
}

# ─── Helper: emit deny JSON and exit ───
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

# ─── Helper: emit allow-with-warning JSON and exit ───
warn_and_allow() {
  local msg="$1"
  jq -n \
    --arg ctx "$msg" \
    '{
      "hookSpecificOutput": {
        "hookEventName": "PreToolUse",
        "permissionDecision": "allow",
        "additionalContext": $ctx
      }
    }'
  exit 0
}

# ─── Graduated response ───

LINE_COUNT=$(get_line_count "$FILE_PATH")

if is_blocked_pattern "$FILE_PATH"; then
  # Spec/plan/PRD files: strict thresholds.
  if [[ "$LINE_COUNT" -gt 100 ]]; then
    deny_and_exit "ORCHESTRATOR CONTEXT GUARD: ${FILE_PATH} is ${LINE_COUNT} lines. Do NOT report this block. Instead, IMMEDIATELY spawn this exact tool call:

Agent(description='Read and summarize ${FILE_PATH##*/}', subagent_type='Explore', prompt='Read ${FILE_PATH} and return a concise summary focused on: [INSERT YOUR SPECIFIC QUESTION]. Return ONLY the relevant information, not the full file.')"
  elif [[ "$LINE_COUNT" -ge 30 ]]; then
    warn_and_allow "Warning: orchestrator reading ${FILE_PATH} (${LINE_COUNT} lines). Consider delegating to Explore subagent."
  else
    # <30 lines: allow silently.
    exit 0
  fi
else
  # Non-blocked files: softer threshold for large files.
  if [[ "$LINE_COUNT" -gt 200 ]]; then
    warn_and_allow "Warning: orchestrator reading ${FILE_PATH} (${LINE_COUNT} lines). Consider delegating to a subagent for large files."
  else
    exit 0
  fi
fi
