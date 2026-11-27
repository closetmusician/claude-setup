#!/bin/bash
# ABOUTME: Refreshes the AWS SSO token for the dil-team-boards profile.
# ABOUTME: Skips the login when the token is valid. Else: hidden browser + Keychain password
# ABOUTME: (lib/okta-hidden-login.py), then Chrome + a Return press on its filled Okta page.
# ABOUTME: launchd (com.yklin.aws-sso-boards, every 3000s) runs it plain: one try per 8h.
# ABOUTME: Agents run it with --now: no 8h limit. Exit 0 = token valid. Log: ~/Library/Logs/aws-sso-boards.log

set -uo pipefail

AWS_BIN="${AWS_BIN:-/opt/homebrew/bin/aws}"
UV_BIN="${UV_BIN:-$HOME/.local/bin/uv}"
PROFILE="dil-team-boards"
LOG="$HOME/Library/Logs/aws-sso-boards.log"
STAMP="$HOME/.aws/sso-boards-last-login-attempt"
LOCK="$HOME/.aws/sso-boards-login.lock"
OKTA_SUBMIT="$(dirname "$0")/lib/okta-submit.applescript"
HIDDEN_LOGIN="$(dirname "$0")/lib/okta-hidden-login.py"
AGE_STAMP="$HOME/.aws/sso-boards-password-reminder-day"
KEYCHAIN_CMD="security add-generic-password -U -s aws-sso-okta -a yklin@diligent.com -w"
THROTTLE_SECS=$((8 * 60 * 60))
LOGIN_TIMEOUT_SECS=300
MAX_PRESSES=3   # cap so a wrong saved password cannot lock the Okta account

# Purpose: write one timed line to the log and to stderr.
# Usage: log "message"
# Gotchas: stderr lets an agent calling --now see progress live. Under launchd, stderr
#   already goes to $LOG, so the stderr copy is skipped there to avoid double lines.
log() {
  local line
  line="$(date '+%Y-%m-%d %H:%M:%S') $1"
  printf '%s\n' "$line" >> "$LOG"
  [ "${XPC_SERVICE_NAME:-}" = com.yklin.aws-sso-boards ] || printf '%s\n' "$line" >&2
}

# Purpose: true when the profile's token works right now, the same way Python callers see it.
# Usage: token_valid && echo ok
# Gotchas: uses boto3, not the aws CLI. The CLI can pass on cached role keys after the SSO
#   token has died, while boto3 (llm.py) then fails. boto3 also renews the 1-hour access
#   token itself. Needs the network.
token_valid() {
  "$UV_BIN" run --quiet --with boto3 python -I -c \
    "import boto3; boto3.Session(profile_name='$PROFILE').client('sts').get_caller_identity()" >/dev/null 2>&1
}

# Purpose: tell Yu-Kuan the saved Okta password needs an update.
# Usage: remind "message"
# Gotchas: a macOS notification shows even when launchd runs this; a locked Mac shows it
#   on unlock. The "REMINDER:" log line also reaches any Claude session that ran --now.
remind() {
  log "REMINDER: $1"
  osascript -e "display notification \"$1\" with title \"AWS SSO login\" sound name \"Glass\"" >/dev/null 2>&1
}

# Purpose: remind once a day when the saved Okta password is over 80 days old.
# Usage: check_password_age
# Gotchas: Okta passwords expire about every 90 days. The age is the Keychain item's
#   change date, so updating the item resets it.
check_password_age() {
  local mdat saved age
  mdat=$(security find-generic-password -s aws-sso-okta -a yklin@diligent.com 2>/dev/null \
    | sed -n 's/.*"mdat".*"\([0-9]\{14\}\)Z.*/\1/p')
  [ -n "$mdat" ] || return 0
  saved=$(date -j -u -f '%Y%m%d%H%M%S' "$mdat" +%s 2>/dev/null) || return 0
  age=$(( ($(date +%s) - saved) / 86400 ))
  [ "$age" -ge 80 ] || return 0
  [ "$(cat "$AGE_STAMP" 2>/dev/null)" = "$(date +%F)" ] && return 0
  date +%F > "$AGE_STAMP"
  remind "Your saved Okta password is $age days old and expires around day 90. After you change it, run: $KEYCHAIN_CMD"
}

FORCE=0
[ "${1:-}" = "--now" ] && FORCE=1
check_password_age

if token_valid; then
  log "token valid"
  exit 0
fi

# One login at a time. Other callers (up to 8 workers) wait for it, then re-check the token.
if [ -d "$LOCK" ] && [ $(( $(date +%s) - $(stat -f %m "$LOCK") )) -gt $((LOGIN_TIMEOUT_SECS + 60)) ]; then
  rmdir "$LOCK" 2>/dev/null
fi
if ! mkdir "$LOCK" 2>/dev/null; then
  log "another login is running, waiting for it"
  waited=0
  while [ -d "$LOCK" ] && [ "$waited" -lt $((LOGIN_TIMEOUT_SECS + 30)) ]; do
    /bin/sleep 5; waited=$((waited + 5))
  done
  token_valid && { log "token valid after waiting"; exit 0; }
  log "login by the other caller did not work"
  exit 1
fi
trap 'rmdir "$LOCK" 2>/dev/null' EXIT

if [ "$FORCE" -eq 0 ] && [ -f "$STAMP" ]; then
  last=$(cat "$STAMP" 2>/dev/null || echo 0)
  if [ $(( $(date +%s) - last )) -lt "$THROTTLE_SECS" ]; then
    log "login needed, last attempt $(date -r "$last" '+%Y-%m-%d %H:%M:%S'), skipping"
    exit 2
  fi
fi

date +%s > "$STAMP"
log "login needed, starting aws sso login"
login_out=$(mktemp)
trap 'rmdir "$LOCK" 2>/dev/null; cat "$login_out" >> "$LOG" 2>/dev/null; rm -f "$login_out"' EXIT
"$AWS_BIN" sso login --profile "$PROFILE" --no-browser > "$login_out" 2>&1 &
aws_pid=$!

# Step 1: the hidden browser. It works while the screen is locked and steals no focus.
url=""
for _ in $(seq 15); do
  url=$(sed -n '/^https:\/\//{p;q;}' "$login_out")
  [ -n "$url" ] && break
  /bin/sleep 1
done
if [ -n "$url" ]; then
  log "trying the hidden browser login"
  # perl alarm = a hard 180 s limit on the helper (macOS has no timeout command by default).
  perl -e 'alarm shift; exec @ARGV' 180 \
    "$UV_BIN" run --quiet --with playwright python -I "$HIDDEN_LOGIN" "$url" >> "$LOG" 2>&1
  hidden=$?
  for _ in $(seq 10); do kill -0 "$aws_pid" 2>/dev/null || break; /bin/sleep 1; done
  # Step 2: if the hidden login did not finish, use Chrome and its filled password.
  # Exit 4 = Okta already got a password and refused it. Chrome likely holds the same
  # password, and more tries could lock the account, so stop instead.
  # Exit 5 = Okta says the password expired. Chrome cannot fix that either.
  if [ "$hidden" -eq 4 ] || [ "$hidden" -eq 5 ]; then
    [ "$hidden" -eq 4 ] && why="Okta refused the saved password" || why="Okta says your password expired"
    remind "$why. Change it at diligent.okta.com if needed, then run: $KEYCHAIN_CMD"
    kill "$aws_pid" 2>/dev/null
  elif kill -0 "$aws_pid" 2>/dev/null; then
    log "hidden login did not finish (exit $hidden), opening Chrome"
    open -a "Google Chrome" "$url"
  fi
fi

# Watch for the Okta sign-in page in Chrome while the login waits.
presses=0
last_press=0
start=$(date +%s)
while kill -0 "$aws_pid" 2>/dev/null; do
  now=$(date +%s)
  if [ $((now - start)) -ge "$LOGIN_TIMEOUT_SECS" ]; then
    log "login timed out after ${LOGIN_TIMEOUT_SECS}s"
    kill "$aws_pid" 2>/dev/null
    break
  fi
  # A locked screen swallows key presses, so do not spend a press while locked.
  locked=$(ioreg -n Root -d1 -a | plutil -extract IOConsoleUsers.0.CGSSessionScreenIsLocked raw - 2>/dev/null)
  if [ "$locked" = "true" ]; then
    [ "${locked_logged:-0}" -eq 0 ] && log "screen is locked, cannot press Return on Okta"
    locked_logged=1
  elif [ "$presses" -lt "$MAX_PRESSES" ] && [ $((now - last_press)) -ge 15 ]; then
    result=$(osascript "$OKTA_SUBMIT" 2>&1)
    if [ "$result" = "pressed" ]; then
      presses=$((presses + 1)); last_press=$now
      log "pressed Return on the Okta sign-in page ($presses/$MAX_PRESSES)"
    elif [ "$result" != "none" ]; then
      log "okta-submit: $result"
    fi
  fi
  /bin/sleep 3
done
wait "$aws_pid" 2>/dev/null

if token_valid; then
  log "login worked, token valid"
  exit 0
fi
log "login failed, token still invalid"
exit 1
