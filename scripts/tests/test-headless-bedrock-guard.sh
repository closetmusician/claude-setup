#!/usr/bin/env bash
# ABOUTME: TDD suite for scripts/governance/headless-bedrock-guard.sh: a Bash command that starts a
# ABOUTME: headless `claude -p` / `claude --print` must set CLAUDE_CODE_USE_BEDROCK=1 in the command.
# ABOUTME: Born 2026-10-25: 12 side-by-side runs billed the claude.ai plan ($71.20) and hit its limit.
# ABOUTME: Run: bash scripts/tests/test-headless-bedrock-guard.sh  (exit 0 = all green).
# ABOUTME: Cases cover deny, allow, quoting, scripts that only mention claude -p, and the kill switch.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GUARD="${SCRIPT_DIR}/../governance/headless-bedrock-guard.sh"
PASS=0; FAIL=0

# payload: build a PreToolUse Bash payload. Usage: payload '<command>'.
# Gotcha: identity and input come on stdin, never env (lesson_guard_identity_env_vs_stdin).
payload() {
  jq -cn --arg c "$1" '{session_id:"test",hook_event_name:"PreToolUse",tool_name:"Bash",
    tool_input:{command:$c},tool_use_id:"toolu_test"}'
}

# check: run the guard and compare. Usage: check <name> <ALLOW|DENY> '<command>' [env...].
# Gotcha: DENY means exit 2; any other exit code counts as ALLOW.
check() {
  local name="$1" expect="$2" cmd="$3"; shift 3
  local rc got
  payload "$cmd" | env "$@" bash "$GUARD" >/dev/null 2>&1; rc=$?
  got="ALLOW"; [ "$rc" -eq 2 ] && got="DENY"
  if [ "$got" = "$expect" ]; then PASS=$((PASS+1)); printf '  ok   %s\n' "$name"
  else FAIL=$((FAIL+1)); printf '  FAIL %s (expected %s, got %s rc=%d)\n' "$name" "$expect" "$got" "$rc"; fi
}

check "plain claude -p denied"                DENY  'claude -p "hi" --model claude-opus-5-5'
check "claude --print denied"                 DENY  'cd /tmp && claude --print "hi"'
check "piped prompt into claude -p denied"    DENY  'cat x.txt | claude -p --model haiku'
check "bedrock prefix allowed"                ALLOW 'CLAUDE_CODE_USE_BEDROCK=1 claude -p "hi" --model us.anthropic.claude-opus-5-5'
check "exported bedrock allowed"              ALLOW 'export CLAUDE_CODE_USE_BEDROCK=1; claude -p "hi"'
check "env wrapper allowed"                   ALLOW 'env CLAUDE_CODE_USE_BEDROCK=1 AWS_PROFILE=x claude -p hi'
check "bedrock=0 still denied"                DENY  'CLAUDE_CODE_USE_BEDROCK=0 claude -p "hi"'
check "interactive claude not touched"        ALLOW 'claude --version'
check "grep for claude -p not touched"        ALLOW "rtk proxy grep -n 'claude -p' scripts/*.sh"
check "perl search text not touched"          ALLOW "perl -ne 'print if /claude -p/' f.sh"
check "echo mention not touched"              ALLOW 'echo "run claude -p later"'
check "unrelated command allowed"             ALLOW 'git status'
check "kill switch allows"                    ALLOW 'claude -p "hi"' HARNESS_HEADLESS_BEDROCK_GUARD=0
check "claude_bedrock call allowed"           ALLOW 'source scripts/lib/claude-bedrock.sh && claude_bedrock -p --model opus'
check "scripts/lib/claude-bedrock.sh allowed" ALLOW 'bash scripts/lib/claude-bedrock.sh -p --model sonnet'
out=$(jq -cn '{hook_event_name:"PreToolUse",tool_name:"Write",tool_input:{content:"claude -p hi"}}' | bash "$GUARD" >/dev/null 2>&1; echo $?)
if [ "$out" != "2" ]; then PASS=$((PASS+1)); echo "  ok   Write tool with claude -p text ignored"; else FAIL=$((FAIL+1)); echo "  FAIL Write tool denied"; fi

printf '=== %d passed, %d failed ===\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
