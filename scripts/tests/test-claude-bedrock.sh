#!/usr/bin/env bash
# ABOUTME: Test suite for scripts/lib/claude-bedrock.sh — Bedrock env setup and model aliasing.
# ABOUTME: Covers: env vars exported, model alias mapping, SSO token expiry fail-closed, no fallback.
# ABOUTME: Usage: bash scripts/tests/test-claude-bedrock.sh
# ABOUTME: Exit 0 if all tests pass, 1 if any fail.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
LIB_DIR="$(cd "$SCRIPT_DIR/../lib" && pwd)"
CLAUDE_BEDROCK_SH="$LIB_DIR/claude-bedrock.sh"

_pass=0
_fail=0
_test_name=""

test_start() {
  _test_name="$1"
  printf '  %-60s ' "$_test_name"
}

test_pass() {
  printf '\033[32m✓\033[0m\n'
  _pass=$(( _pass + 1 ))
}

test_fail() {
  printf '\033[31m✗\033[0m %s\n' "$1"
  _fail=$(( _fail + 1 ))
}

# ══════════════════════════════════════════════════════════════════════════════
# TEST 1: Sourcing the script exports required env vars
# ══════════════════════════════════════════════════════════════════════════════
test_start "Exports CLAUDE_CODE_USE_BEDROCK=1"
(
  unset CLAUDE_CODE_USE_BEDROCK AWS_PROFILE AWS_REGION || true
  # shellcheck source=/dev/null
  source "$CLAUDE_BEDROCK_SH"
  [[ "${CLAUDE_CODE_USE_BEDROCK:-}" == "1" ]]
) && test_pass || test_fail "CLAUDE_CODE_USE_BEDROCK not set to 1"

test_start "Exports AWS_PROFILE=dil-team-boards"
(
  unset CLAUDE_CODE_USE_BEDROCK AWS_PROFILE AWS_REGION || true
  # shellcheck source=/dev/null
  source "$CLAUDE_BEDROCK_SH"
  [[ "${AWS_PROFILE:-}" == "dil-team-boards" ]]
) && test_pass || test_fail "AWS_PROFILE not set"

test_start "Exports AWS_REGION=us-west-2"
(
  unset CLAUDE_CODE_USE_BEDROCK AWS_PROFILE AWS_REGION || true
  # shellcheck source=/dev/null
  source "$CLAUDE_BEDROCK_SH"
  [[ "${AWS_REGION:-}" == "us-west-2" ]]
) && test_pass || test_fail "AWS_REGION not set"

# ══════════════════════════════════════════════════════════════════════════════
# TEST 2: Model alias mapping
# ══════════════════════════════════════════════════════════════════════════════
test_start "Alias opus → us.anthropic.claude-opus-5-5"
(
  # shellcheck source=/dev/null
  source "$CLAUDE_BEDROCK_SH"
  claude_bedrock opus | grep -q 'us.anthropic.claude-opus-5-5'
) && test_pass || test_fail "opus alias not mapped"

test_start "Alias sonnet → us.anthropic.claude-sonnet-5"
(
  # shellcheck source=/dev/null
  source "$CLAUDE_BEDROCK_SH"
  claude_bedrock sonnet | grep -q 'us.anthropic.claude-sonnet-5'
) && test_pass || test_fail "sonnet alias not mapped"

test_start "Alias haiku → us.anthropic.claude-haiku-4-5-20251001-v1:0"
(
  # shellcheck source=/dev/null
  source "$CLAUDE_BEDROCK_SH"
  claude_bedrock haiku | grep -q 'us.anthropic.claude-haiku-4-5-20251001-v1:0'
) && test_pass || test_fail "haiku alias not mapped"

test_start "claude.ai name claude-haiku-4-5 maps to the Bedrock ID (invalid on Bedrock as-is)"
(
  # shellcheck source=/dev/null
  source "$CLAUDE_BEDROCK_SH"
  [ "$(map_model_alias claude-haiku-4-5)" = "us.anthropic.claude-haiku-4-5-20251001-v1:0" ]
) && test_pass || test_fail "claude-haiku-4-5 not mapped"

test_start "Non-alias model passes through unchanged"
(
  # shellcheck source=/dev/null
  source "$CLAUDE_BEDROCK_SH"
  result="$(claude_bedrock us.anthropic.claude-custom-1-0)"
  [[ "$result" == "us.anthropic.claude-custom-1-0" ]]
) && test_pass || test_fail "custom model not passed through"

# ══════════════════════════════════════════════════════════════════════════════
# TEST 3: Expired SSO token fails closed (exit 3)
# ══════════════════════════════════════════════════════════════════════════════
test_start "Expired token → exit 3 with stderr message"
(
  # Create fake expired cache
  FAKE_CACHE_DIR="$(mktemp -d)"
  FAKE_CACHE_FILE="$FAKE_CACHE_DIR/fake-sso-cache.json"

  # Expired timestamp (2020-01-01)
  cat > "$FAKE_CACHE_FILE" <<'CACHE'
{
  "startUrl": "https://d-123.awsapps.com/start",
  "region": "us-west-2",
  "expiresAt": "2020-01-01T00:00:00Z",
  "accessToken": "fake-token"
}
CACHE

  # MUST export before sourcing so the script sees it
  export _TEST_SSO_CACHE_DIR="$FAKE_CACHE_DIR"

  # shellcheck source=/dev/null
  ( source "$CLAUDE_BEDROCK_SH" 2>/dev/null )
  exit_code=$?
  rm -rf "$FAKE_CACHE_DIR"
  [[ $exit_code -eq 3 ]]
) && test_pass || test_fail "did not exit 3 on expired token"

# ══════════════════════════════════════════════════════════════════════════════
# TEST 4: Valid token allows pass-through
# ══════════════════════════════════════════════════════════════════════════════
test_start "Valid token → exports vars and continues"
(
  # Create fake valid cache
  FAKE_CACHE_DIR="$(mktemp -d)"
  FAKE_CACHE_FILE="$FAKE_CACHE_DIR/fake-sso-cache.json"

  # Future timestamp
  FUTURE_DATE="$(date -u -v+1d +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -d '+1 day' +%Y-%m-%dT%H:%M:%SZ)"
  cat > "$FAKE_CACHE_FILE" <<CACHE
{
  "startUrl": "https://d-123.awsapps.com/start",
  "region": "us-west-2",
  "expiresAt": "$FUTURE_DATE",
  "accessToken": "fake-valid-token"
}
CACHE

  export _TEST_SSO_CACHE_DIR="$FAKE_CACHE_DIR"

  # shellcheck source=/dev/null
  source "$CLAUDE_BEDROCK_SH"
  result=$?
  rm -rf "$FAKE_CACHE_DIR"
  [[ $result -eq 0 && "${CLAUDE_CODE_USE_BEDROCK:-}" == "1" ]]
) && test_pass || test_fail "valid token did not pass through"

# ══════════════════════════════════════════════════════════════════════════════
# TEST 5: Script can be executed as a command
# ══════════════════════════════════════════════════════════════════════════════
test_start "Direct execution: claude-bedrock.sh -p ..."
(
  # Create a fake claude binary that prints its env
  FAKE_BIN_DIR="$(mktemp -d)"
  FAKE_CLAUDE="$FAKE_BIN_DIR/claude"
  cat > "$FAKE_CLAUDE" <<'FAKECLAUDE'
#!/bin/bash
echo "CLAUDE_CODE_USE_BEDROCK=${CLAUDE_CODE_USE_BEDROCK:-unset}"
echo "AWS_PROFILE=${AWS_PROFILE:-unset}"
echo "AWS_REGION=${AWS_REGION:-unset}"
echo "MODEL=$3"
FAKECLAUDE
  chmod +x "$FAKE_CLAUDE"

  # Put fake claude first in PATH
  export PATH="$FAKE_BIN_DIR:$PATH"

  # Run claude-bedrock.sh as a command
  output="$("$CLAUDE_BEDROCK_SH" -p --model opus <<< "test" 2>/dev/null)"
  rm -rf "$FAKE_BIN_DIR"

  echo "$output" | grep -q 'CLAUDE_CODE_USE_BEDROCK=1' && \
  echo "$output" | grep -q 'AWS_PROFILE=dil-team-boards' && \
  echo "$output" | grep -q 'MODEL=us.anthropic.claude-opus-5-5'
) && test_pass || test_fail "direct execution failed"

# ══════════════════════════════════════════════════════════════════════════════
# TEST 6: No fallback to claude.ai
# ══════════════════════════════════════════════════════════════════════════════
test_start "No fallback path to claude.ai login"
(
  # shellcheck source=/dev/null
  source "$CLAUDE_BEDROCK_SH"
  # Check that ANTHROPIC_API_KEY is NOT set (would be a fallback)
  [[ -z "${ANTHROPIC_API_KEY:-}" ]]
) && test_pass || test_fail "ANTHROPIC_API_KEY was set (fallback path)"

# ══════════════════════════════════════════════════════════════════════════════
# SUMMARY
# ══════════════════════════════════════════════════════════════════════════════
printf '\n'
if [[ $_fail -eq 0 ]]; then
  printf '\033[32m✓ All %d tests passed\033[0m\n' $_pass
  exit 0
else
  printf '\033[31m✗ %d/%d tests failed\033[0m\n' $_fail $(( _pass + _fail ))
  exit 1
fi
