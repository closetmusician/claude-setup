#!/usr/bin/env bash
# ABOUTME: PreToolUse hook that gates Task tool calls requiring a spec reference.
# ABOUTME: Blocks build-related tasks missing docs/*.md references.
# ABOUTME: Pass-through for exploratory tasks (debug, review, qa, etc.).
# ABOUTME: Escape hatch: include NO_SPEC_REQUIRED in the task prompt to bypass.
# ABOUTME: Outputs JSON {"decision":"block","reason":"..."} to block, or exits 0 silently to allow.

set -euo pipefail

# Read JSON from stdin
input="$(cat)"

# Extract tool name — exit 0 for anything other than Task
tool_name="$(echo "$input" | jq -r '.tool_name // empty')"
if [[ "$tool_name" != "Task" ]]; then
  exit 0
fi

# Extract prompt from tool_input.prompt or tool_input.description
prompt="$(echo "$input" | jq -r '.tool_input.prompt // .tool_input.description // empty')"
if [[ -z "$prompt" ]]; then
  exit 0
fi

# Escape hatch — explicit bypass
if echo "$prompt" | grep -qi 'NO_SPEC_REQUIRED'; then
  exit 0
fi

# Pass-through for exploratory/non-build tasks
if echo "$prompt" | grep -qiE '(debug|explore|review|qa|investigate|analyze|research|read|search|check)'; then
  exit 0
fi

has_spec_ref() {
  echo "$prompt" | grep -qE 'docs/.*\.md'
}

# Hard-block tier — build tasks that absolutely need a spec
if echo "$prompt" | grep -qiE '(generate.*test|create.*schema|implement.*feature|write.*spec)'; then
  if ! has_spec_ref; then
    echo '{"decision": "block", "reason": "Build task requires spec reference (docs/*.md). Add spec path to prompt or NO_SPEC_REQUIRED to bypass."}'
    exit 0
  fi
fi

# Soft-warn tier — general creation tasks without a spec
if echo "$prompt" | grep -qiE '(create|write|implement|build|generate)'; then
  if ! has_spec_ref; then
    echo "⚠ Task has no spec reference (docs/*.md). Consider adding one." >&2
  fi
fi

exit 0
