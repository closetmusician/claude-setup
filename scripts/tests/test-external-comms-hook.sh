#!/bin/bash
# ABOUTME: Test suite for the external communications PreToolUse hook.
# ABOUTME: Pipes mock JSON through the hook and verifies exit codes.
# ABOUTME: Covers all block patterns, sanctioned exceptions, and edge cases.
# ABOUTME: Exit 0 = all tests pass; exit 1 = at least one failure.
# ABOUTME: Requires: jq, the hook script at ../external-comms-hook.sh

set -uo pipefail

HOOK="$(cd "$(dirname "$0")/.." && pwd)/external-comms-hook.sh"
PASS=0
FAIL=0
TOTAL=0

# make_json <tool_name> <command>
# Builds the JSON blob that Claude Code pipes to PreToolUse hooks.
make_json() {
  local tool="$1"
  local cmd="$2"
  jq -n --arg tool "$tool" --arg cmd "$cmd" \
    '{"tool_name": $tool, "tool_input": {"command": $cmd}}'
}

# assert_exit <test_name> <expected_exit> <tool_name> <command>
# Pipes JSON through the hook, checks exit code matches expected.
assert_exit() {
  local name="$1"
  local expected="$2"
  local tool="$3"
  local cmd="$4"
  TOTAL=$((TOTAL + 1))

  local json
  json=$(make_json "$tool" "$cmd")

  local actual
  echo "$json" | "$HOOK" > /dev/null 2>&1
  actual=$?

  if [[ "$actual" -eq "$expected" ]]; then
    PASS=$((PASS + 1))
  else
    FAIL=$((FAIL + 1))
    echo "FAIL: $name (expected exit $expected, got $actual)"
    echo "  command: $cmd"
  fi
}

# assert_blocked <test_name> <command>
# Shorthand: expect hook to block (exit 2) a Bash command.
assert_blocked() {
  assert_exit "$1" 2 "Bash" "$2"
}

# assert_allowed <test_name> <command>
# Shorthand: expect hook to allow (exit 0) a Bash command.
assert_allowed() {
  assert_exit "$1" 0 "Bash" "$2"
}

echo "=== External Communications Hook Tests ==="
echo ""

# --- Block pattern: graph.microsoft.com.*/chats ---
echo "--- REQ-001: graph.microsoft.com/chats ---"

assert_blocked "POST to chats endpoint" \
  "curl -X POST https://graph.microsoft.com/v1.0/chats -H 'Authorization: Bearer token'"

assert_blocked "GET to chats endpoint (also blocked per spec)" \
  "curl https://graph.microsoft.com/v1.0/chats/abc123"

assert_blocked "chats endpoint with beta API" \
  "curl https://graph.microsoft.com/beta/chats"

# --- Block pattern: graph.microsoft.com.*/messages ---
echo "--- REQ-002: graph.microsoft.com/messages ---"

assert_blocked "POST to messages endpoint" \
  "curl -X POST https://graph.microsoft.com/v1.0/me/messages -d '{\"subject\":\"test\"}'"

assert_blocked "GET to channel messages" \
  "curl https://graph.microsoft.com/v1.0/teams/abc/channels/def/messages"

assert_blocked "messages endpoint with beta API" \
  "curl https://graph.microsoft.com/beta/me/messages"

# --- Block pattern: graph.microsoft.com.*/sendMail ---
echo "--- REQ-003: graph.microsoft.com/sendMail ---"

assert_blocked "sendMail endpoint" \
  "curl -X POST https://graph.microsoft.com/v1.0/me/sendMail -d '{\"message\":{}}'"

assert_blocked "sendMail with beta API" \
  "curl -X POST https://graph.microsoft.com/beta/me/sendMail"

# --- Block pattern: teams.*send.*message / chat.*create.*member ---
echo "--- REQ-004: teams send message / chat create member ---"

assert_blocked "teams send message pattern" \
  "node ~/Code/pm_os/bin/some-tool.js teams send message --to someone"

assert_blocked "teams send a message variation" \
  "curl -X POST https://example.com/teams/abc/send/def/message"

assert_blocked "chat create member pattern" \
  "curl -X POST https://graph.microsoft.com/v1.0/chat/abc/create/def/member"

# --- Sanctioned tool exceptions ---
echo "--- REQ-005: Sanctioned tool exceptions ---"

assert_allowed "run-send.js calling chats endpoint" \
  "node ~/Code/pm_os/bin/run-send.js --channel general --message 'hello'"

assert_allowed "teams-send-chat.js with graph chats URL" \
  "node ~/Code/pm_os/bin/teams-send-chat.js --chat-id abc --body 'test'"

assert_allowed "outlook-send-mail.js with sendMail" \
  "node ~/Code/pm_os/bin/outlook-send-mail.js --to user@example.com --subject 'test'"

# Sanctioned tool that also matches a block pattern in its arguments
assert_allowed "run-send.js with graph URL in args" \
  "node ~/Code/pm_os/bin/run-send.js --url https://graph.microsoft.com/v1.0/chats"

# --- Edge cases ---
echo "--- REQ-006: Edge cases ---"

assert_allowed "non-Bash tool skipped" \
  "anything here"
# Override: non-Bash tool should exit 0
assert_exit "Read tool passes through" 0 "Read" "graph.microsoft.com/v1.0/chats"

assert_allowed "echo with 'message' in string (not messaging)" \
  "echo 'error message: operation failed'"

assert_allowed "grep for messages in log file" \
  "grep 'messages' /var/log/app.log"

assert_allowed "empty command" \
  ""

assert_allowed "unrelated curl to graph API (no messaging endpoint)" \
  "curl https://graph.microsoft.com/v1.0/me/drive/items"

assert_allowed "git commit with message word" \
  "git commit -m 'fix message formatting in chat display'"

assert_allowed "heredoc with graph URL inside (should not block)" \
  "cat <<'EOF'
curl https://graph.microsoft.com/v1.0/chats
EOF"

# --- Adversarial: sanctioned tool bypass vectors (P0-001) ---
echo "--- P0-001: Sanctioned tool substring injection ---"

assert_blocked "ATTACK: sanctioned tool appended after chain operator" \
  "curl -X POST https://graph.microsoft.com/v1.0/chats -d hello && echo run-send.js"

assert_blocked "ATTACK: sanctioned tool in trailing comment" \
  "curl -X POST https://graph.microsoft.com/v1.0/chats # run-send.js"

assert_blocked "ATTACK: sanctioned tool in variable assignment before malicious cmd" \
  "TOOL=run-send.js && curl -X POST https://graph.microsoft.com/v1.0/chats"

assert_blocked "ATTACK: sanctioned tool in curl -d body" \
  "curl -X POST https://graph.microsoft.com/v1.0/me/sendMail -d \"run-send.js\""

assert_blocked "ATTACK: sanctioned tool in pipe after malicious cmd" \
  "curl -X POST https://graph.microsoft.com/v1.0/chats | grep run-send.js"

assert_blocked "ATTACK: sanctioned tool in subshell after malicious cmd" \
  "curl -X POST https://graph.microsoft.com/v1.0/messages; (echo run-send.js)"

# Ensure legitimate sanctioned tool invocations still pass after the fix
assert_allowed "LEGIT: node run-send.js at start of command" \
  "node ~/Code/pm_os/bin/run-send.js --channel general"

assert_allowed "LEGIT: node teams-send-chat.js at start of command" \
  "node ~/Code/pm_os/bin/teams-send-chat.js --chat-id abc"

assert_allowed "LEGIT: node outlook-send-mail.js at start of command" \
  "node ~/Code/pm_os/bin/outlook-send-mail.js --to foo@bar.com"

# --- P1-001: Heredoc stripping with non-EOF delimiters ---
echo "--- P1-001: Heredoc with various delimiters ---"

assert_allowed "heredoc with HERE delimiter (should not block)" \
  "cat <<'HERE'
curl https://graph.microsoft.com/v1.0/chats
HERE"

assert_allowed "heredoc with DOC delimiter (should not block)" \
  "cat <<DOC
curl https://graph.microsoft.com/v1.0/messages
DOC"

assert_allowed "heredoc with MARKER delimiter (should not block)" \
  "cat <<'MARKER'
curl https://graph.microsoft.com/v1.0/me/sendMail
MARKER"

# --- P0-002: Newline injection bypasses sanctioned tool check ---
echo "--- P0-002: Newline injection bypass vectors ---"

# QA Attack 7: Malicious command on line 1, sanctioned tool on line 2
assert_blocked "ATTACK: newline injection — malicious cmd + sanctioned tool on line 2" \
  "$(printf 'curl -X POST https://graph.microsoft.com/v1.0/chats -d "payload"\nnode ~/Code/pm_os/bin/run-send.js')"

# QA Attack 8: Bare tool name on new line
assert_blocked "ATTACK: newline injection — bare tool name on separate line" \
  "$(printf 'curl -X POST https://graph.microsoft.com/v1.0/chats\nrun-send.js')"

# QA Attack 9: sendMail bypass with different sanctioned tool
assert_blocked "ATTACK: newline injection — sendMail + teams tool on line 2" \
  "$(printf 'curl -X POST https://graph.microsoft.com/v1.0/me/sendMail -d "payload"\nteams-send-chat.js')"

# QA Attack 10: messages bypass
assert_blocked "ATTACK: newline injection — messages + outlook tool on line 2" \
  "$(printf 'curl https://graph.microsoft.com/v1.0/teams/abc/channels/def/messages\noutlook-send-mail.js')"

# New Attack 11: Multiple newlines with tool buried deep
assert_blocked "ATTACK: newline injection — tool buried after multiple newlines" \
  "$(printf 'curl -X POST https://graph.microsoft.com/v1.0/chats\necho hello\nrun-send.js')"

# New Attack 12: Tab+newline combo — tool after tab and newline
assert_blocked "ATTACK: newline injection — tab+newline before sanctioned tool" \
  "$(printf 'curl -X POST https://graph.microsoft.com/v1.0/me/sendMail\t\nrun-send.js')"

# New Attack 13: Carriage return injection — tool after \r\n (Windows-style)
assert_blocked "ATTACK: newline injection — CRLF before sanctioned tool" \
  "$(printf 'curl -X POST https://graph.microsoft.com/v1.0/chats\r\nrun-send.js')"

# Verify deny output is valid JSON with correct structure
echo "--- Deny output format ---"
TOTAL=$((TOTAL + 1))
DENY_JSON=$(make_json "Bash" "curl https://graph.microsoft.com/v1.0/me/sendMail" | "$HOOK" 2>/dev/null) || true
DECISION=$(echo "$DENY_JSON" | jq -r '.hookSpecificOutput.permissionDecision // empty')
if [[ "$DECISION" == "deny" ]]; then
  PASS=$((PASS + 1))
else
  FAIL=$((FAIL + 1))
  echo "FAIL: deny output should contain permissionDecision=deny (got: $DECISION)"
fi

# --- Summary ---
echo ""
echo "=== Results: $PASS passed, $FAIL failed, $TOTAL total ==="

if [[ "$FAIL" -gt 0 ]]; then
  exit 1
fi
exit 0
