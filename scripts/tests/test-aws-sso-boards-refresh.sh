#!/usr/bin/env bash
# ABOUTME: Tests for aws-sso-boards-refresh.sh (SSO token check + throttled login).
# ABOUTME: Proves a valid token skips the browser, an invalid token opens it once,
# ABOUTME: and a fresh stamp file suppresses a repeat open within 8 hours.
# ABOUTME: Uses a fake `aws` binary (via AWS_BIN) and an isolated HOME/log/stamp.
# ABOUTME: Run: bash ~/.claude/scripts/tests/test-aws-sso-boards-refresh.sh
set -uo pipefail

SRC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$SRC_DIR/aws-sso-boards-refresh.sh"

FAKE_HOME="$(mktemp -d)"
trap 'rm -rf "$FAKE_HOME"' EXIT
mkdir -p "$FAKE_HOME/Library/Logs" "$FAKE_HOME/.aws"
STAMP="$FAKE_HOME/.aws/sso-boards-last-login-attempt"
LOG="$FAKE_HOME/Library/Logs/aws-sso-boards.log"

FAKE_AWS="$FAKE_HOME/fake-aws.sh"
cat > "$FAKE_AWS" <<'EOF'
#!/bin/bash
echo "$@" >> "$CALL_LOG"
if [ "$1" = "sts" ]; then
  exit "${FAKE_AWS_STS_EXIT:-0}"
fi
exit 0
EOF
chmod +x "$FAKE_AWS"

PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); printf '  ok   %s\n' "$1"; }
bad() { FAIL=$((FAIL+1)); printf '  FAIL %s\n' "$1"; }

sso_login_calls() { grep -c '^sso login' "$CALL_LOG" 2>/dev/null || true; }

run_script() {
  CALL_LOG="$FAKE_HOME/calls.log"
  : > "$CALL_LOG"
  export CALL_LOG FAKE_AWS_STS_EXIT
  HOME="$FAKE_HOME" AWS_BIN="$FAKE_AWS" bash "$SCRIPT" >/dev/null 2>&1
}

echo "== valid token =="
rm -f "$STAMP"
FAKE_AWS_STS_EXIT=0
run_script
[ "$(sso_login_calls)" = "0" ] && ok "valid token: no sso login call" || bad "valid token should not call sso login"

echo "== invalid token, no stamp =="
rm -f "$STAMP"
FAKE_AWS_STS_EXIT=1
run_script
[ "$(sso_login_calls)" = "1" ] && ok "invalid token + no stamp: exactly one sso login call" || bad "invalid token + no stamp should call sso login once"
[ -f "$STAMP" ] && ok "invalid token + no stamp: stamp file written" || bad "stamp file should be written"

echo "== invalid token, fresh stamp =="
date +%s > "$STAMP"
FAKE_AWS_STS_EXIT=1
run_script
[ "$(sso_login_calls)" = "0" ] && ok "invalid token + fresh stamp: no sso login call" || bad "fresh stamp should skip sso login"

echo "== invalid token, stale (9h) stamp =="
echo $(( $(date +%s) - 9*3600 )) > "$STAMP"
FAKE_AWS_STS_EXIT=1
run_script
[ "$(sso_login_calls)" = "1" ] && ok "invalid token + 9h stamp: one sso login call" || bad "9h stale stamp should call sso login once"

echo
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
