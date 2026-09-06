#!/bin/bash
# ABOUTME: Test suite for incident-freeze-detector.sh and incident-freeze-enforcer.sh.
# ABOUTME: Tests the state machine: NORMAL -> ARMED -> FROZEN, freeze enforcement, and release.
# ABOUTME: Pipes mock JSON through hooks, validates exit codes and state/freeze files.
# ABOUTME: Covers trigger, enforcement, local passthrough, disarm, timeout, and release.
# ABOUTME: Run: bash test-incident-freeze.sh

set -euo pipefail

# --- Configuration ---
SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
DETECTOR="${SCRIPT_DIR}/incident-freeze-detector.sh"
ENFORCER="${SCRIPT_DIR}/incident-freeze-enforcer.sh"

STATE_FILE="/tmp/.claude-destructive-event"
FREEZE_FILE="/tmp/.claude-incident-freeze"

PASS=0
FAIL=0
ERRORS=""

# --- Cleanup before/after ---
cleanup() {
  rm -f "$STATE_FILE" "$FREEZE_FILE"
}
trap cleanup EXIT
cleanup

# --- Helpers ---

# make_post_input <tool_output>
# Builds mock PostToolUse JSON. The detector reads tool_result from stdin.
make_post_input() {
  local output="$1"
  jq -n --arg result "$output" '{"tool_name":"Bash","tool_result":$result}'
}

# make_pre_input <command>
# Builds mock PreToolUse JSON for the enforcer.
make_pre_input() {
  local cmd="$1"
  jq -n --arg cmd "$cmd" '{"tool_name":"Bash","tool_input":{"command":$cmd}}'
}

# assert_file_exists <test_name> <file_path>
assert_file_exists() {
  local name="$1"
  local fpath="$2"
  if [[ -f "$fpath" ]]; then
    PASS=$((PASS + 1))
  else
    FAIL=$((FAIL + 1))
    ERRORS="${ERRORS}\n  FAIL: ${name} — expected ${fpath} to exist"
  fi
}

# assert_file_not_exists <test_name> <file_path>
assert_file_not_exists() {
  local name="$1"
  local fpath="$2"
  if [[ ! -f "$fpath" ]]; then
    PASS=$((PASS + 1))
  else
    FAIL=$((FAIL + 1))
    ERRORS="${ERRORS}\n  FAIL: ${name} — expected ${fpath} to NOT exist"
  fi
}

# assert_exit <test_name> <expected_exit> <actual_exit>
assert_exit() {
  local name="$1"
  local expected="$2"
  local actual="$3"
  if [[ "$actual" -eq "$expected" ]]; then
    PASS=$((PASS + 1))
  else
    FAIL=$((FAIL + 1))
    ERRORS="${ERRORS}\n  FAIL: ${name} — expected exit ${expected}, got ${actual}"
  fi
}

# run_detector <tool_output>
# Runs the detector hook with mock PostToolUse output. Returns exit code.
run_detector() {
  local output="$1"
  local exit_code=0
  make_post_input "$output" | bash "$DETECTOR" >/dev/null 2>&1 || exit_code=$?
  echo "$exit_code"
}

# run_enforcer <command>
# Runs the enforcer hook with mock PreToolUse input. Returns exit code.
run_enforcer() {
  local cmd="$1"
  local exit_code=0
  make_pre_input "$cmd" | bash "$ENFORCER" >/dev/null 2>&1 || exit_code=$?
  echo "$exit_code"
}

# =====================================================================
# SECTION 1: DETECTOR — State Machine Tests
# =====================================================================

echo "--- Detector: State Machine ---"

# --- T-001: DELETE 204 detection arms the state ---
cleanup
EXIT_CODE=$(run_detector "curl -X DELETE https://graph.microsoft.com/v1.0/me/drive/items/abc
HTTP/1.1 204 No Content
Date: Sat, 26 Apr 2026 12:00:00 GMT")
assert_exit "T-001a: detector exits 0 after DELETE 204" 0 "$EXIT_CODE"
assert_file_exists "T-001b: state file created after DELETE 204" "$STATE_FILE"

# --- T-002: Recovery failure triggers freeze ---
# State file exists from T-001. Now simulate a failed upload.
EXIT_CODE=$(run_detector "curl -X PUT https://graph.microsoft.com/v1.0/me/drive/items/abc/content
HTTP/1.1 403 Forbidden
{\"error\":{\"code\":\"accessDenied\"}}")
assert_exit "T-002a: detector exits 0 after recovery failure" 0 "$EXIT_CODE"
assert_file_exists "T-002b: freeze file created after recovery failure" "$FREEZE_FILE"
assert_file_not_exists "T-002c: state file removed after freeze trigger" "$STATE_FILE"

# --- T-003: Recovery success disarms ---
cleanup
# First arm it
run_detector "curl -X DELETE https://graph.microsoft.com/v1.0/me/drive/items/abc
HTTP/1.1 204 No Content" >/dev/null
assert_file_exists "T-003a: state file exists (armed)" "$STATE_FILE"

# Then successful recovery
EXIT_CODE=$(run_detector "curl -X PUT https://graph.microsoft.com/v1.0/me/drive/items/abc/content
HTTP/1.1 200 OK
{\"id\":\"abc123\"}")
assert_exit "T-003b: detector exits 0 after recovery success" 0 "$EXIT_CODE"
assert_file_not_exists "T-003c: state file removed (disarmed)" "$STATE_FILE"
assert_file_not_exists "T-003d: no freeze file created" "$FREEZE_FILE"

# --- T-004: Normal operation (no DELETE) does nothing ---
cleanup
EXIT_CODE=$(run_detector "curl -X GET https://graph.microsoft.com/v1.0/me/drive/items/abc
HTTP/1.1 200 OK
{\"name\":\"file.docx\"}")
assert_exit "T-004a: detector exits 0 for normal GET" 0 "$EXIT_CODE"
assert_file_not_exists "T-004b: no state file for normal GET" "$STATE_FILE"
assert_file_not_exists "T-004c: no freeze file for normal GET" "$FREEZE_FILE"

# --- T-005: Timeout disarms state ---
cleanup
# Create state file with old timestamp (> 60 seconds ago)
OLD_TS=$(($(date +%s) - 120))
echo "$OLD_TS" > "$STATE_FILE"

EXIT_CODE=$(run_detector "curl -X PUT https://graph.microsoft.com/v1.0/me/drive/items/abc/content
HTTP/1.1 403 Forbidden
{\"error\":\"denied\"}")
assert_exit "T-005a: detector exits 0 after timed-out state" 0 "$EXIT_CODE"
assert_file_not_exists "T-005b: stale state file removed" "$STATE_FILE"
assert_file_not_exists "T-005c: no freeze file on timed-out state" "$FREEZE_FILE"

# --- T-006: Non-Bash tool passes through ---
cleanup
EXIT_CODE=0
echo '{"tool_name":"Read","tool_result":"some file content"}' | bash "$DETECTOR" >/dev/null 2>&1 || EXIT_CODE=$?
assert_exit "T-006: non-Bash tool passes through detector" 0 "$EXIT_CODE"

# --- T-007: DELETE with 404 does not arm ---
cleanup
EXIT_CODE=$(run_detector "curl -X DELETE https://graph.microsoft.com/v1.0/me/drive/items/abc
HTTP/1.1 404 Not Found")
assert_exit "T-007a: detector exits 0 for DELETE 404" 0 "$EXIT_CODE"
assert_file_not_exists "T-007b: no state file for failed DELETE" "$STATE_FILE"

# --- T-008: Multiple DELETE 2xx patterns ---
cleanup
EXIT_CODE=$(run_detector "DELETE /v1.0/me/drive/items/abc HTTP/1.1
HTTP/1.1 200 OK")
assert_exit "T-008a: detector exits 0 for DELETE 200" 0 "$EXIT_CODE"
assert_file_exists "T-008b: state file created for DELETE 200" "$STATE_FILE"

# --- T-009: POST failure after armed state triggers freeze ---
cleanup
run_detector "curl -X DELETE https://api.example.com/resource/123
HTTP/1.1 204 No Content" >/dev/null
assert_file_exists "T-009a: armed after external DELETE 204" "$STATE_FILE"

EXIT_CODE=$(run_detector "curl -X POST https://api.example.com/resource/
HTTP/1.1 500 Internal Server Error")
assert_file_exists "T-009b: freeze triggered by POST 500 after armed" "$FREEZE_FILE"

# =====================================================================
# SECTION 2: ENFORCER — Freeze Enforcement Tests
# =====================================================================

echo "--- Enforcer: Freeze Enforcement ---"

# --- T-010: No freeze file = all commands pass ---
cleanup
EXIT_CODE=$(run_enforcer "curl -X POST https://api.example.com/upload -d @file.txt")
assert_exit "T-010: no freeze = external mutation allowed" 0 "$EXIT_CODE"

# --- T-011: Freeze blocks external curl POST ---
cleanup
touch "$FREEZE_FILE"
EXIT_CODE=$(run_enforcer "curl -X POST https://api.example.com/upload -d @file.txt")
assert_exit "T-011: freeze blocks curl POST to external" 2 "$EXIT_CODE"

# --- T-012: Freeze blocks external curl PUT ---
cleanup
touch "$FREEZE_FILE"
EXIT_CODE=$(run_enforcer "curl -X PUT https://graph.microsoft.com/v1.0/me/drive/items/abc/content -d @file.docx")
assert_exit "T-012: freeze blocks curl PUT to external" 2 "$EXIT_CODE"

# --- T-013: Freeze blocks external curl PATCH ---
cleanup
touch "$FREEZE_FILE"
EXIT_CODE=$(run_enforcer "curl -X PATCH https://api.example.io/permissions/123 -d '{}'")
assert_exit "T-013: freeze blocks curl PATCH to external" 2 "$EXIT_CODE"

# --- T-014: Freeze blocks external curl DELETE ---
cleanup
touch "$FREEZE_FILE"
EXIT_CODE=$(run_enforcer "curl -X DELETE https://graph.microsoft.com/v1.0/me/drive/items/abc")
assert_exit "T-014: freeze blocks curl DELETE to external" 2 "$EXIT_CODE"

# --- T-015: Freeze blocks node upload scripts ---
cleanup
touch "$FREEZE_FILE"
EXIT_CODE=$(run_enforcer "node ~/Code/pm_os/bin/graph-file-ops.js upload --url https://example.com/file")
assert_exit "T-015: freeze blocks node upload script" 2 "$EXIT_CODE"

# --- T-016: Freeze allows local-only commands ---
cleanup
touch "$FREEZE_FILE"

EXIT_CODE=$(run_enforcer "ls -la /tmp")
assert_exit "T-016a: freeze allows ls" 0 "$EXIT_CODE"

EXIT_CODE=$(run_enforcer "cat /tmp/some-file.txt")
assert_exit "T-016b: freeze allows cat" 0 "$EXIT_CODE"

EXIT_CODE=$(run_enforcer "git status")
assert_exit "T-016c: freeze allows git" 0 "$EXIT_CODE"

EXIT_CODE=$(run_enforcer "echo hello world")
assert_exit "T-016d: freeze allows echo" 0 "$EXIT_CODE"

EXIT_CODE=$(run_enforcer "grep -r pattern /some/path")
assert_exit "T-016e: freeze allows grep" 0 "$EXIT_CODE"

EXIT_CODE=$(run_enforcer "find /tmp -name '*.txt'")
assert_exit "T-016f: freeze allows find" 0 "$EXIT_CODE"

EXIT_CODE=$(run_enforcer "python3 -c 'print(42)'")
assert_exit "T-016g: freeze allows local python" 0 "$EXIT_CODE"

EXIT_CODE=$(run_enforcer "node -e 'console.log(42)'")
assert_exit "T-016h: freeze allows local node" 0 "$EXIT_CODE"

EXIT_CODE=$(run_enforcer "jq '.name' /tmp/data.json")
assert_exit "T-016i: freeze allows jq" 0 "$EXIT_CODE"

EXIT_CODE=$(run_enforcer "wc -l /tmp/file.txt")
assert_exit "T-016j: freeze allows wc" 0 "$EXIT_CODE"

# --- T-017: Freeze allows rm of freeze file (user release) ---
cleanup
touch "$FREEZE_FILE"
EXIT_CODE=$(run_enforcer "rm /tmp/.claude-incident-freeze")
assert_exit "T-017a: freeze allows rm of freeze file" 0 "$EXIT_CODE"

EXIT_CODE=$(run_enforcer "rm /tmp/.claude-incident-freeze*")
assert_exit "T-017b: freeze allows rm freeze glob" 0 "$EXIT_CODE"

EXIT_CODE=$(run_enforcer "rm -f /tmp/.claude-incident-freeze")
assert_exit "T-017c: freeze allows rm -f freeze file" 0 "$EXIT_CODE"

# --- T-018: Non-Bash tool passes through enforcer ---
cleanup
touch "$FREEZE_FILE"
EXIT_CODE=0
echo '{"tool_name":"Read","tool_input":{"file_path":"/tmp/test"}}' | bash "$ENFORCER" >/dev/null 2>&1 || EXIT_CODE=$?
assert_exit "T-018: non-Bash tool passes through enforcer during freeze" 0 "$EXIT_CODE"

# --- T-019: Freeze blocks node scripts with external URLs ---
cleanup
touch "$FREEZE_FILE"
EXIT_CODE=$(run_enforcer "node ~/Code/pm_os/bin/graph-edit-pptx.js --url https://sharepoint.com/slides.pptx --action add-slide")
assert_exit "T-019: freeze blocks node graph-edit-pptx to external URL" 2 "$EXIT_CODE"

# --- T-020: Freeze blocks run-send.js (messaging during freeze) ---
cleanup
touch "$FREEZE_FILE"
EXIT_CODE=$(run_enforcer "node ~/Code/pm_os/bin/run-send.js --to someone@example.com --body 'help'")
assert_exit "T-020: freeze blocks run-send.js during freeze" 2 "$EXIT_CODE"

# --- T-021: Empty command passes through ---
cleanup
touch "$FREEZE_FILE"
EXIT_CODE=0
echo '{"tool_name":"Bash","tool_input":{"command":""}}' | bash "$ENFORCER" >/dev/null 2>&1 || EXIT_CODE=$?
assert_exit "T-021: empty command passes through during freeze" 0 "$EXIT_CODE"

# =====================================================================
# SECTION 3: INTEGRATION — Full Cycle
# =====================================================================

echo "--- Integration: Full Cycle ---"

# --- T-022: Full cycle: DELETE 204 -> upload 403 -> freeze -> block -> release ---
cleanup

# Step 1: DELETE 204 arms state
run_detector "curl -X DELETE https://graph.microsoft.com/v1.0/me/drive/items/abc
HTTP/1.1 204 No Content" >/dev/null
assert_file_exists "T-022a: armed after DELETE 204" "$STATE_FILE"

# Step 2: Upload 403 triggers freeze
run_detector "curl -X PUT https://graph.microsoft.com/v1.0/me/drive/items/abc/content
HTTP/1.1 403 Forbidden" >/dev/null
assert_file_exists "T-022b: frozen after upload 403" "$FREEZE_FILE"

# Step 3: External mutation blocked
EXIT_CODE=$(run_enforcer "curl -X POST https://api.example.com/resource")
assert_exit "T-022c: external mutation blocked during freeze" 2 "$EXIT_CODE"

# Step 4: Local command allowed
EXIT_CODE=$(run_enforcer "ls /tmp")
assert_exit "T-022d: local command allowed during freeze" 0 "$EXIT_CODE"

# Step 5: rm freeze file allowed (release)
EXIT_CODE=$(run_enforcer "rm /tmp/.claude-incident-freeze")
assert_exit "T-022e: rm freeze file allowed" 0 "$EXIT_CODE"

# Step 6: After release, external mutation passes (freeze file gone)
rm -f "$FREEZE_FILE"
EXIT_CODE=$(run_enforcer "curl -X POST https://api.example.com/resource")
assert_exit "T-022f: external mutation allowed after release" 0 "$EXIT_CODE"

# =====================================================================
# SECTION 4: P1 FIX TESTS — Adversarial bypass patterns
# =====================================================================

echo "--- P1 Fix: Adversarial Bypass Patterns ---"

# --- P1-001: curl implicit POST via data flags (no explicit -X) ---
cleanup
touch "$FREEZE_FILE"

EXIT_CODE=$(run_enforcer "curl --data '{\"key\":\"val\"}' https://graph.microsoft.com/v1.0/me/messages")
assert_exit "P1-001a: freeze blocks curl --data to external URL" 2 "$EXIT_CODE"

EXIT_CODE=$(run_enforcer "curl -d @/tmp/payload.json https://graph.microsoft.com/v1.0/me/messages")
assert_exit "P1-001b: freeze blocks curl -d to external URL" 2 "$EXIT_CODE"

EXIT_CODE=$(run_enforcer "curl --data-binary @/tmp/file.docx https://graph.microsoft.com/v1.0/me/drive/items/abc/content")
assert_exit "P1-001c: freeze blocks curl --data-binary to external URL" 2 "$EXIT_CODE"

EXIT_CODE=$(run_enforcer "curl --data-raw '{\"body\":\"test\"}' https://graph.microsoft.com/v1.0/me/messages")
assert_exit "P1-001d: freeze blocks curl --data-raw to external URL" 2 "$EXIT_CODE"

EXIT_CODE=$(run_enforcer "curl --data-urlencode 'name=value' https://api.example.com/endpoint")
assert_exit "P1-001e: freeze blocks curl --data-urlencode to external URL" 2 "$EXIT_CODE"

EXIT_CODE=$(run_enforcer "curl -F 'file=@doc.docx' https://graph.microsoft.com/v1.0/me/drive/items/abc/content")
assert_exit "P1-001f: freeze blocks curl -F to external URL" 2 "$EXIT_CODE"

EXIT_CODE=$(run_enforcer "curl --form 'file=@doc.docx' https://graph.microsoft.com/v1.0/me/drive/items/abc/content")
assert_exit "P1-001g: freeze blocks curl --form to external URL" 2 "$EXIT_CODE"

EXIT_CODE=$(run_enforcer "curl --upload-file /tmp/file.docx https://graph.microsoft.com/v1.0/me/drive/items/abc/content")
assert_exit "P1-001h: freeze blocks curl --upload-file to external URL" 2 "$EXIT_CODE"

EXIT_CODE=$(run_enforcer "curl -T /tmp/file.docx https://graph.microsoft.com/v1.0/me/drive/items/abc/content")
assert_exit "P1-001i: freeze blocks curl -T to external URL" 2 "$EXIT_CODE"

# Must NOT block curl -d to localhost (false positive check)
EXIT_CODE=$(run_enforcer "curl -d '{\"q\":1}' http://localhost:8080/api")
assert_exit "P1-001j: freeze allows curl -d to localhost" 0 "$EXIT_CODE"

# Must NOT block curl --data to 127.0.0.1 (false positive check)
EXIT_CODE=$(run_enforcer "curl --data 'x=1' http://127.0.0.1:3000/endpoint")
assert_exit "P1-001k: freeze allows curl --data to 127.0.0.1" 0 "$EXIT_CODE"

# --- P1-002: curl --request long form (equivalent to -X) ---
cleanup
touch "$FREEZE_FILE"

EXIT_CODE=$(run_enforcer "curl --request DELETE https://graph.microsoft.com/v1.0/me/drive/items/abc")
assert_exit "P1-002a: freeze blocks curl --request DELETE" 2 "$EXIT_CODE"

EXIT_CODE=$(run_enforcer "curl --request POST https://api.example.com/resource -d '{}'")
assert_exit "P1-002b: freeze blocks curl --request POST" 2 "$EXIT_CODE"

EXIT_CODE=$(run_enforcer "curl --request PUT https://graph.microsoft.com/v1.0/me/drive/items/abc/content -d @file")
assert_exit "P1-002c: freeze blocks curl --request PUT" 2 "$EXIT_CODE"

EXIT_CODE=$(run_enforcer "curl --request PATCH https://api.example.io/resource/123 -d '{}'")
assert_exit "P1-002d: freeze blocks curl --request PATCH" 2 "$EXIT_CODE"

# Detector must also recognize --request DELETE for arming
cleanup
EXIT_CODE=$(run_detector "curl --request DELETE https://graph.microsoft.com/v1.0/me/drive/items/abc
HTTP/1.1 204 No Content
Date: Sat, 26 Apr 2026 12:00:00 GMT")
assert_exit "P1-002e: detector exits 0 for --request DELETE 204" 0 "$EXIT_CODE"
assert_file_exists "P1-002f: state file created for --request DELETE 204" "$STATE_FILE"

# --- P1-003: wget --post-data and --post-file bypass ---
cleanup
touch "$FREEZE_FILE"

EXIT_CODE=$(run_enforcer "wget --post-data='key=val' https://api.example.com/endpoint")
assert_exit "P1-003a: freeze blocks wget --post-data to external URL" 2 "$EXIT_CODE"

EXIT_CODE=$(run_enforcer "wget --post-file=/tmp/data.json https://api.example.com/endpoint")
assert_exit "P1-003b: freeze blocks wget --post-file to external URL" 2 "$EXIT_CODE"

# Must NOT block wget for reads (false positive check)
EXIT_CODE=$(run_enforcer "wget https://example.com/readme.txt")
assert_exit "P1-003c: freeze allows wget GET (no mutation flag)" 0 "$EXIT_CODE"

# --- P1-004: Enforcer missing ERR trap (malformed JSON) ---
cleanup
touch "$FREEZE_FILE"

EXIT_CODE=0
echo "NOT_JSON_AT_ALL" | bash "$ENFORCER" >/dev/null 2>&1 || EXIT_CODE=$?
assert_exit "P1-004a: enforcer exits 0 on malformed input (not JSON)" 0 "$EXIT_CODE"

EXIT_CODE=0
echo '{"partial":' | bash "$ENFORCER" >/dev/null 2>&1 || EXIT_CODE=$?
assert_exit "P1-004b: enforcer exits 0 on truncated JSON" 0 "$EXIT_CODE"

EXIT_CODE=0
echo "" | bash "$ENFORCER" >/dev/null 2>&1 || EXIT_CODE=$?
assert_exit "P1-004c: enforcer exits 0 on empty input" 0 "$EXIT_CODE"

# --- P1-005: gh api -X DELETE bypasses safe-list ---
cleanup
touch "$FREEZE_FILE"

EXIT_CODE=$(run_enforcer "gh api -X DELETE repos/owner/repo/issues/1")
assert_exit "P1-005a: freeze blocks gh api -X DELETE" 2 "$EXIT_CODE"

EXIT_CODE=$(run_enforcer "gh api --method DELETE repos/owner/repo/issues/1")
assert_exit "P1-005b: freeze blocks gh api --method DELETE" 2 "$EXIT_CODE"

EXIT_CODE=$(run_enforcer "gh api -X POST repos/owner/repo/issues -f title='test'")
assert_exit "P1-005c: freeze blocks gh api -X POST" 2 "$EXIT_CODE"

EXIT_CODE=$(run_enforcer "gh api -X PUT repos/owner/repo/issues/1/lock")
assert_exit "P1-005d: freeze blocks gh api -X PUT" 2 "$EXIT_CODE"

EXIT_CODE=$(run_enforcer "gh api -X PATCH repos/owner/repo/issues/1 -f state='closed'")
assert_exit "P1-005e: freeze blocks gh api -X PATCH" 2 "$EXIT_CODE"

# Must NOT block safe gh commands (false positive check)
EXIT_CODE=$(run_enforcer "gh pr list")
assert_exit "P1-005f: freeze allows gh pr list" 0 "$EXIT_CODE"

EXIT_CODE=$(run_enforcer "gh api repos/owner/repo/issues")
assert_exit "P1-005g: freeze allows gh api GET (no method flag)" 0 "$EXIT_CODE"

EXIT_CODE=$(run_enforcer "gh issue view 123")
assert_exit "P1-005h: freeze allows gh issue view" 0 "$EXIT_CODE"

# =====================================================================
# Summary
# =====================================================================

TOTAL=$((PASS + FAIL))
echo ""
echo "=== Incident Freeze Tests ==="
echo "Total: ${TOTAL}  Pass: ${PASS}  Fail: ${FAIL}"

if [[ $FAIL -gt 0 ]]; then
  echo -e "\nFailures:${ERRORS}"
  echo ""
  exit 1
fi

echo "All tests passed."
exit 0
