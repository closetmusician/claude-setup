#!/bin/bash
# ABOUTME: Test suite for remote-destructive-hook.sh PreToolUse hook.
# ABOUTME: Pipes mock JSON through the hook and validates exit codes.
# ABOUTME: Exit code 2 = blocked (destructive), exit code 0 = allowed.
# ABOUTME: Covers all block patterns from docs/nerf-prevention.md section 4.1.1.
# ABOUTME: Run: bash test-remote-destructive-hook.sh

set -euo pipefail

# --- Configuration ---
HOOK="$(cd "$(dirname "$0")/.." && pwd)/remote-destructive-hook.sh"
PASS=0
FAIL=0
ERRORS=""

# --- Helpers ---

# make_input <command>
# Builds the JSON that Claude Code pipes to PreToolUse hooks.
# Uses jq to handle proper JSON escaping of the command string.
make_input() {
  local cmd="$1"
  jq -n --arg cmd "$cmd" '{"tool_name":"Bash","tool_input":{"command":$cmd}}'
}

# make_input_tool <tool_name> <command_or_path>
# Builds JSON for a non-Bash tool. Used to test passthrough.
make_input_tool() {
  local tool="$1"
  local val="$2"
  jq -n --arg t "$tool" --arg v "$val" '{"tool_name":$t,"tool_input":{"file_path":$v}}'
}

# assert_blocked <test_name> <command>
# Expects the hook to exit 2 (deny).
assert_blocked() {
  local name="$1"
  local cmd="$2"
  local exit_code=0
  make_input "$cmd" | bash "$HOOK" >/dev/null 2>&1 || exit_code=$?
  if [[ $exit_code -eq 2 ]]; then
    PASS=$((PASS + 1))
  else
    FAIL=$((FAIL + 1))
    ERRORS="${ERRORS}\n  FAIL: ${name} — expected exit 2, got ${exit_code}"
  fi
}

# assert_blocked_raw <test_name> <raw_json>
# Like assert_blocked but takes raw JSON input.
assert_blocked_raw() {
  local name="$1"
  local json="$2"
  local exit_code=0
  echo "$json" | bash "$HOOK" >/dev/null 2>&1 || exit_code=$?
  if [[ $exit_code -eq 2 ]]; then
    PASS=$((PASS + 1))
  else
    FAIL=$((FAIL + 1))
    ERRORS="${ERRORS}\n  FAIL: ${name} — expected exit 2, got ${exit_code}"
  fi
}

# assert_allowed <test_name> <command>
# Expects the hook to exit 0 (allow).
assert_allowed() {
  local name="$1"
  local cmd="$2"
  local exit_code=0
  make_input "$cmd" | bash "$HOOK" >/dev/null 2>&1 || exit_code=$?
  if [[ $exit_code -eq 0 ]]; then
    PASS=$((PASS + 1))
  else
    FAIL=$((FAIL + 1))
    ERRORS="${ERRORS}\n  FAIL: ${name} — expected exit 0, got ${exit_code}"
  fi
}

# assert_allowed_raw <test_name> <raw_json>
# Like assert_allowed but takes raw JSON input.
assert_allowed_raw() {
  local name="$1"
  local json="$2"
  local exit_code=0
  echo "$json" | bash "$HOOK" >/dev/null 2>&1 || exit_code=$?
  if [[ $exit_code -eq 0 ]]; then
    PASS=$((PASS + 1))
  else
    FAIL=$((FAIL + 1))
    ERRORS="${ERRORS}\n  FAIL: ${name} — expected exit 0, got ${exit_code}"
  fi
}

# =====================================================================
# REQ-001: Block curl DELETE to graph.microsoft.com
# =====================================================================

assert_blocked "REQ-001a: curl -X DELETE graph.microsoft.com" \
  "curl -X DELETE https://graph.microsoft.com/v1.0/me/drive/items/abc123"

assert_blocked "REQ-001b: curl -X DELETE graph.microsoft.com (with headers)" \
  "curl -H 'Authorization: Bearer tok' -X DELETE https://graph.microsoft.com/v1.0/sites/foo"

# =====================================================================
# REQ-002: Block curl DELETE to sharepoint.com
# =====================================================================

assert_blocked "REQ-002a: curl -X DELETE sharepoint.com" \
  "curl -X DELETE https://mycompany.sharepoint.com/_api/web/lists/items(5)"

assert_blocked "REQ-002b: curl -X DELETE to sharepoint.com (subsite)" \
  "curl -X DELETE https://mycompany.sharepoint.com/sites/team/_api/recycle"

# =====================================================================
# REQ-003: Block bypass-shared-lock header
# =====================================================================

assert_blocked "REQ-003a: bypass-shared-lock in Prefer header" \
  "curl -H 'Prefer: bypass-shared-lock' -X DELETE https://graph.microsoft.com/v1.0/me/drive/items/abc"

assert_blocked "REQ-003b: bypass-shared-lock in any context" \
  "curl -H 'Prefer: bypass-shared-lock' -X GET https://graph.microsoft.com/v1.0/me/drive/items/abc"

assert_blocked "REQ-003c: bypass-shared-lock standalone mention" \
  "echo bypass-shared-lock"

# =====================================================================
# REQ-004: Block Python requests.delete and urllib DELETE to sharepoint/graph
# =====================================================================

assert_blocked "REQ-004a: requests.delete(" \
  "python3 -c 'import requests; requests.delete(url)'"

assert_blocked "REQ-004b: urllib DELETE to sharepoint" \
  'python3 -c "import urllib.request; req = urllib.request.Request(sharepoint_url, method=DELETE)"; python3 script.py'

assert_blocked "REQ-004c: urllib DELETE to graph.microsoft" \
  'python3 -c "req = urllib.request.Request(graph.microsoft_url, method=DELETE)"'

# =====================================================================
# REQ-005: Block graph-file-ops delete/remove commands
# =====================================================================

assert_blocked "REQ-005a: graph-file-ops delete" \
  "node ~/Code/pm_os/bin/graph-file-ops.js delete --url https://example.com/file"

assert_blocked "REQ-005b: graph-file-ops remove" \
  "node ~/Code/pm_os/bin/graph-file-ops.js remove --url https://example.com/file"

assert_blocked "REQ-005c: graph-file-ops.js delete (different path)" \
  "node graph-file-ops.js delete --item-id abc123"

# =====================================================================
# REQ-006: Extended patterns — generic DELETE with Microsoft domains
# =====================================================================

assert_blocked "REQ-006a: -X DELETE *.sharepoint.*" \
  "curl -X DELETE https://company.sharepoint.com/sites/docs/file"

assert_blocked "REQ-006b: -X DELETE *.microsoft.*" \
  "curl -X DELETE https://portal.microsoft.com/api/items/123"

assert_blocked "REQ-006c: -X DELETE *.graph.* domain" \
  "curl -X DELETE https://api.graph.microsoft.com/beta/me/events/123"

# =====================================================================
# REQ-007: Allowed commands pass through cleanly
# =====================================================================

assert_allowed "REQ-007a: curl GET to graph.microsoft.com" \
  "curl -X GET https://graph.microsoft.com/v1.0/me/drive/items/abc123"

assert_allowed "REQ-007b: curl POST upload to graph.microsoft.com" \
  "curl -X POST https://graph.microsoft.com/v1.0/me/drive/items/abc/content -d @file.docx"

assert_allowed "REQ-007c: graph-file-ops download" \
  "node ~/Code/pm_os/bin/graph-file-ops.js download --url https://example.com/file"

assert_allowed "REQ-007d: graph-file-ops upload" \
  "node ~/Code/pm_os/bin/graph-file-ops.js upload --url https://example.com/file"

assert_allowed "REQ-007e: graph-list-crud delete (legitimate)" \
  "node ~/Code/pm_os/bin/graph-list-crud.js delete --list-id abc --item-id 5"

assert_allowed "REQ-007f: normal curl to unrelated domain" \
  "curl -X DELETE https://api.example.com/items/123"

assert_allowed "REQ-007g: git command (no interference)" \
  "git status"

assert_allowed "REQ-007h: python without destructive patterns" \
  "python3 -c 'print(hello)'"

assert_allowed "REQ-007i: non-Bash tool passes through" \
  ""  # Empty command — should pass

# Use make_input_tool for non-Bash tool
NONBASH_JSON=$(make_input_tool "Read" "/tmp/test")
assert_allowed_raw "REQ-007j: non-Bash tool_name" "$NONBASH_JSON"

# =====================================================================
# REQ-008: Edge cases — heredoc, quoted strings
# =====================================================================

# DELETE pattern inside a heredoc should NOT trigger block
HEREDOC_CMD=$(printf 'cat <<EOF\ncurl -X DELETE https://graph.microsoft.com/v1.0/me/drive/items/abc\nEOF')
HEREDOC_JSON=$(make_input "$HEREDOC_CMD")
assert_allowed_raw "REQ-008a: DELETE in heredoc body (should not block)" "$HEREDOC_JSON"

# DELETE pattern inside single-quoted echo should NOT trigger block
assert_allowed "REQ-008b: DELETE in single-quoted string (should not block)" \
  "echo 'curl -X DELETE https://graph.microsoft.com/v1.0/me/drive/items/abc'"

# DELETE pattern inside double-quoted echo should NOT trigger block
DQUOTE_CMD='echo "curl -X DELETE https://graph.microsoft.com/v1.0/me/drive/items/abc"'
DQUOTE_JSON=$(make_input "$DQUOTE_CMD")
assert_allowed_raw "REQ-008c: DELETE in double-quoted string (should not block)" "$DQUOTE_JSON"

# Ensure curl PUT to sharepoint is allowed (not DELETE/bypass/recycle/etc.)
assert_allowed "REQ-008d: curl PUT to sharepoint (allowed)" \
  "curl -X PUT https://mycompany.sharepoint.com/_api/web/upload -d @file.docx"

# Multiple commands where only first is safe — second is destructive
assert_blocked "REQ-008e: piped command with DELETE at end" \
  "echo hello && curl -X DELETE https://graph.microsoft.com/v1.0/me/drive/items/abc"

# =====================================================================
# P0-001: --request DELETE (long-form -X) must be blocked
# =====================================================================

assert_blocked "P0-001a: --request DELETE to graph.microsoft.com" \
  "curl --request DELETE https://graph.microsoft.com/v1.0/me/drive/items/abc123"

assert_blocked "P0-001b: --request DELETE to sharepoint.com" \
  "curl --request DELETE https://mycompany.sharepoint.com/sites/team/_api/items/5"

assert_blocked "P0-001c: --request DELETE to .microsoft. domain" \
  "curl --request DELETE https://portal.microsoft.com/api/items/123"

assert_blocked "P0-001d: --request=DELETE (equals form) to graph.microsoft.com" \
  "curl --request=DELETE https://graph.microsoft.com/v1.0/me/drive/items/abc123"

# =====================================================================
# P0-002: URL-before-flag ordering must be blocked
# =====================================================================

assert_blocked "P0-002a: URL before -X DELETE (graph.microsoft.com)" \
  "curl https://graph.microsoft.com/v1.0/me/drive/items/abc123 -X DELETE"

assert_blocked "P0-002b: URL before -X DELETE (sharepoint.com)" \
  "curl https://mycompany.sharepoint.com/_api/web/lists/items(5) -X DELETE"

assert_blocked "P0-002c: URL before --request DELETE (graph.microsoft.com)" \
  "curl https://graph.microsoft.com/v1.0/me/drive/items/abc123 --request DELETE"

# =====================================================================
# P0-003: -XDELETE (no space) must be blocked
# =====================================================================

assert_blocked "P0-003a: -XDELETE (no space) to graph.microsoft.com" \
  "curl -XDELETE https://graph.microsoft.com/v1.0/me/drive/items/abc123"

assert_blocked "P0-003b: -XDELETE (no space) to sharepoint.com" \
  "curl -XDELETE https://mycompany.sharepoint.com/sites/team/_api/items/5"

assert_blocked "P0-003c: -XDELETE (no space) to .microsoft. domain" \
  "curl -XDELETE https://portal.microsoft.com/api/items/123"

# =====================================================================
# P1-001: Mixed-case DELETE must be blocked
# =====================================================================

assert_blocked "P1-001a: -X Delete to graph.microsoft.com" \
  "curl -X Delete https://graph.microsoft.com/v1.0/me/drive/items/abc123"

assert_blocked "P1-001b: -X delete to sharepoint.com" \
  "curl -X delete https://mycompany.sharepoint.com/sites/team/_api/items/5"

assert_blocked "P1-001c: --request delete to graph.microsoft.com" \
  "curl --request delete https://graph.microsoft.com/v1.0/me/drive/items/abc123"

# =====================================================================
# P1-002: Non-EOF heredoc delimiters must be stripped (not false positive)
# =====================================================================

HEREDOC_ENDMARKER_CMD=$(printf 'cat <<ENDMARKER\ncurl -X DELETE https://graph.microsoft.com/v1.0/me/drive/items/abc\nENDMARKER')
HEREDOC_ENDMARKER_JSON=$(make_input "$HEREDOC_ENDMARKER_CMD")
assert_allowed_raw "P1-002a: DELETE in heredoc with ENDMARKER delimiter (should not block)" "$HEREDOC_ENDMARKER_JSON"

HEREDOC_DOC_CMD=$(printf 'cat <<DOC\ncurl -X DELETE https://graph.microsoft.com/v1.0/me/drive/items/abc\nDOC')
HEREDOC_DOC_JSON=$(make_input "$HEREDOC_DOC_CMD")
assert_allowed_raw "P1-002b: DELETE in heredoc with DOC delimiter (should not block)" "$HEREDOC_DOC_JSON"

HEREDOC_QUOTED_CMD=$(printf "cat <<'HERE'\ncurl -X DELETE https://graph.microsoft.com/v1.0/me/drive/items/abc\nHERE")
HEREDOC_QUOTED_JSON=$(make_input "$HEREDOC_QUOTED_CMD")
assert_allowed_raw "P1-002c: DELETE in heredoc with quoted 'HERE' delimiter (should not block)" "$HEREDOC_QUOTED_JSON"

# Indented heredoc (<<-) with tab-stripped closing delimiter
HEREDOC_INDENT_CMD=$(printf 'cat <<-MARKER\n\tcurl -X DELETE https://graph.microsoft.com/v1.0/me/drive/items/abc\n\tMARKER')
HEREDOC_INDENT_JSON=$(make_input "$HEREDOC_INDENT_CMD")
assert_allowed_raw "P1-002d: DELETE in indented heredoc (<<-MARKER) (should not block)" "$HEREDOC_INDENT_JSON"

# =====================================================================
# Summary
# =====================================================================

TOTAL=$((PASS + FAIL))
echo ""
echo "=== Remote Destructive Hook Tests ==="
echo "Total: ${TOTAL}  Pass: ${PASS}  Fail: ${FAIL}"

if [[ $FAIL -gt 0 ]]; then
  echo -e "\nFailures:${ERRORS}"
  echo ""
  exit 1
fi

echo "All tests passed."
exit 0
