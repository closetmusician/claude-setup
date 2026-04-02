#!/usr/bin/env bash
# ABOUTME: PreToolUse hook that prevents the orchestrator from reading large files directly.
# ABOUTME: Subagents (identified by agent_id in hook input) always pass through.
# ABOUTME: Spec/plan/PRD files: <30 allow, 30-100 warn, >100 hard deny.
# ABOUTME: Code files (.py/.ts/.tsx/.js/.go etc): always blocked with delegation guidance.
# ABOUTME: All other files: hard deny at >200 lines. No warn-only — delegate or don't read.
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
# Explicit allow-list for .claude/ — no wildcards. Plus small config files.
always_allow() {
  local p="$1"
  case "$p" in
    # .claude/ explicit allow-list (was */.claude/* — too broad)
    */.claude/phase.json)        return 0 ;;
    */.claude/rules/*.md)        return 0 ;;
    */.claude/rules/*)           return 0 ;;
    */.claude/templates/*)       return 0 ;;
    */.claude/skills/*)          return 0 ;;
    # QA artifacts, logs, config
    */templates/*)               return 0 ;;
    */docs/spec-registry.yaml)   return 0 ;;
    */docs/backlog.md)           return 0 ;;
    # Intermediary planning files (read by subagents and orchestrator)
    */docs/.eng-planning/progress.json)  return 0 ;;
  esac
  return 1
}

if always_allow "$FILE_PATH"; then
  exit 0
fi

# ─── BLOCKED patterns ───
# Two categories: (A) spec/plan/PRD files, (B) implementation code files.
# Both get hard-denied with delegation guidance. Orchestrators never read these.

# (A) Spec/plan/PRD files — graduated response (small ones OK).
is_spec_pattern() {
  local p="$1"
  local lower_p
  lower_p=$(echo "$p" | tr '[:upper:]' '[:lower:]')

  case "$lower_p" in
    */docs/prd/*)       return 0 ;;
    */docs/plans/*)     return 0 ;;
    */docs/contracts/*) return 0 ;;
  esac

  local basename_lower
  basename_lower=$(basename "$lower_p")
  case "$basename_lower" in
    *prd*.md)    return 0 ;;
    *spec*.md)   return 0 ;;
    *design*.md) return 0 ;;
  esac

  return 1
}

# (B) Implementation code files — always blocked regardless of size.
is_code_file() {
  local p="$1"
  local ext="${p##*.}"
  local lower_ext
  lower_ext=$(echo "$ext" | tr '[:upper:]' '[:lower:]')

  case "$lower_ext" in
    py|ts|tsx|js|jsx|go|rs|rb|java|kt|cs|swift|c|cpp|h|hpp) return 0 ;;
    vue|svelte|dart|scala|clj|ex|exs|erl|hs|ml|php)         return 0 ;;
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

DENY_MSG_SUFFIX="Do NOT report this block. Instead, IMMEDIATELY spawn:
Agent(description='Read and summarize ${FILE_PATH##*/}', subagent_type='Explore', prompt='Read ${FILE_PATH} and return a concise summary focused on: [YOUR SPECIFIC QUESTION]. Return ONLY the relevant information, not the full file.')"

LINE_COUNT=$(get_line_count "$FILE_PATH")

# (B) Code files: always deny. Orchestrators never read implementation code.
if is_code_file "$FILE_PATH"; then
  deny_and_exit "ORCHESTRATOR CONTEXT GUARD: ${FILE_PATH} is a code file (${LINE_COUNT} lines). Orchestrators NEVER read implementation code. ${DENY_MSG_SUFFIX}"
fi

# (A) Spec/plan/PRD files: graduated — small ones OK, large ones denied.
if is_spec_pattern "$FILE_PATH"; then
  if [[ "$LINE_COUNT" -gt 100 ]]; then
    deny_and_exit "ORCHESTRATOR CONTEXT GUARD: ${FILE_PATH} is ${LINE_COUNT} lines. ${DENY_MSG_SUFFIX}"
  elif [[ "$LINE_COUNT" -ge 30 ]]; then
    warn_and_allow "Warning: orchestrator reading ${FILE_PATH} (${LINE_COUNT} lines). Consider delegating to Explore subagent."
  else
    exit 0
  fi
fi

# Everything else: hard deny at >200 lines. No warn-only — delegate or don't read.
if [[ "$LINE_COUNT" -gt 200 ]]; then
  deny_and_exit "ORCHESTRATOR CONTEXT GUARD: ${FILE_PATH} is ${LINE_COUNT} lines. ${DENY_MSG_SUFFIX}"
fi

# ≤200 lines, not code, not spec: allow.
exit 0
