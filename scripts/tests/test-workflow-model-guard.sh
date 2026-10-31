#!/usr/bin/env bash
# ABOUTME: TDD suite for scripts/governance/workflow-model-guard.sh — enforces that every
# ABOUTME: agent() call in a workflow script has an explicit model option.
# ABOUTME: Run: bash scripts/tests/test-workflow-model-guard.sh — exit 0 = all green.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GUARD="${SCRIPT_DIR}/../governance/workflow-model-guard.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

PASS=0; FAIL=0

# payload <tool_name> <script_inline> [scriptPath]
payload() {
  local tn="$1" script="$2" spath="${3:-}"
  if [ -n "$spath" ]; then
    jq -cn --arg tn "$tn" --arg s "$script" --arg sp "$spath" \
      '{session_id:"test",transcript_path:"/tmp/t.jsonl",cwd:"/test",
        permission_mode:"auto",hook_event_name:"PreToolUse",tool_name:$tn,
        tool_input:{script:$s,scriptPath:$sp},tool_use_id:"toolu_test"}'
  else
    jq -cn --arg tn "$tn" --arg s "$script" \
      '{session_id:"test",transcript_path:"/tmp/t.jsonl",cwd:"/test",
        permission_mode:"auto",hook_event_name:"PreToolUse",tool_name:$tn,
        tool_input:{script:$s},tool_use_id:"toolu_test"}'
  fi
}

# check <name> <expected: ALLOW|DENY> <payload-json> [env assignments...]
check() {
  local name="$1" expect="$2" pl="$3"; shift 3
  local out rc
  out="$(printf '%s' "$pl" | env "$@" bash "$GUARD" 2>/dev/null)"; rc=$?
  local got="ALLOW"; [ "$rc" -eq 2 ] && got="DENY"
  if [ "$got" = "$expect" ]; then
    PASS=$((PASS+1)); printf '  ok   %s\n' "$name"
  else
    FAIL=$((FAIL+1)); printf '  FAIL %s (expected %s, got %s rc=%d)\n' "$name" "$expect" "$got" "$rc"
  fi
}

echo "=== test-workflow-model-guard.sh ==="

echo "-- Scripts with missing model --"
check "single agent no model" DENY "$(payload Workflow 'const r = await agent("do it")')"
check "multiple agents one missing" DENY "$(payload Workflow 'await agent("a", {model:"sonnet"}); await agent("b")')"
check "agent with schema but no model" DENY "$(payload Workflow 'await agent("x", {schema:{type:"object"}})')"

echo "-- Scripts with explicit model --"
check "single agent with model" ALLOW "$(payload Workflow 'const r = await agent("do it", {model:"sonnet"})')"
check "multiple agents all with model" ALLOW "$(payload Workflow 'await agent("a", {model:"sonnet"}); await agent("b", {model:"haiku"})')"
check "model with other options" ALLOW "$(payload Workflow 'await agent("x", {model:"opus", schema:{type:"object"}, effort:"high"})')"

echo "-- Multi-line agent calls --"
check "multi-line with model" ALLOW "$(payload Workflow 'await agent(
  "analyze this",
  {
    model: "sonnet",
    schema: SCHEMA
  }
)')"
check "multi-line no model" DENY "$(payload Workflow 'await agent(
  "analyze this",
  {
    schema: SCHEMA,
    effort: "high"
  }
)')"

echo "-- Script via scriptPath --"
SCRIPT_FILE="$TMP/test-workflow.js"
cat > "$SCRIPT_FILE" <<'EOF'
export const meta = {name: "test", description: "test"}
const result = await agent("work", {model: "sonnet"})
EOF
check "scriptPath with model" ALLOW "$(payload Workflow "" "$SCRIPT_FILE")"

cat > "$SCRIPT_FILE" <<'EOF'
export const meta = {name: "test", description: "test"}
const result = await agent("work")
EOF
check "scriptPath no model" DENY "$(payload Workflow "" "$SCRIPT_FILE")"

echo "-- Escape hatches --"
check "MODEL-ROLE-EXEMPT in script" ALLOW "$(payload Workflow 'await agent("x") // MODEL-ROLE-EXEMPT')"
check "env kill switch" ALLOW "$(payload Workflow 'await agent("x")')" HARNESS_WORKFLOW_MODEL_GUARD=0

echo "-- Non-Workflow tool passes through --"
check "Agent tool not checked" ALLOW "$(payload Agent 'const r = await agent("do it")')"
check "Bash tool not checked" ALLOW "$(payload Bash 'echo test')"

echo ""
echo "=== $((PASS + FAIL)) passed, $FAIL failed ==="
[ "$FAIL" -eq 0 ]
