#!/bin/bash
# ABOUTME: Refreshes the AWS SSO token for the dil-team-boards profile.
# ABOUTME: Checks the cached token first and skips the browser when it is valid.
# ABOUTME: Opens the browser login at most once per 8 hours via a stamp file.
# ABOUTME: Called by com.yklin.aws-sso-boards launchd job every 3000s.
# ABOUTME: Log: ~/Library/Logs/aws-sso-boards.log

set -uo pipefail

AWS_BIN="${AWS_BIN:-/opt/homebrew/bin/aws}"
PROFILE="dil-team-boards"
LOG="$HOME/Library/Logs/aws-sso-boards.log"
STAMP="$HOME/.aws/sso-boards-last-login-attempt"
THROTTLE_SECS=$((8 * 60 * 60))

log() {
  printf '%s %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$1" >> "$LOG"
}

if "$AWS_BIN" sts get-caller-identity --profile "$PROFILE" >/dev/null 2>&1; then
  log "token valid"
  exit 0
fi

if [ -f "$STAMP" ]; then
  last=$(cat "$STAMP" 2>/dev/null || echo 0)
  age=$(( $(date +%s) - last ))
  if [ "$age" -lt "$THROTTLE_SECS" ]; then
    log "login needed, last attempt $(date -r "$last" '+%Y-%m-%d %H:%M:%S'), skipping"
    exit 0
  fi
fi

date +%s > "$STAMP"
log "login needed, opening browser"
"$AWS_BIN" sso login --profile "$PROFILE"
exit 0
