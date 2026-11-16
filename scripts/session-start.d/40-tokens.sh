#!/usr/bin/env bash
# ABOUTME: SessionStart drop-in: prints weekly token spend line and refreshes cache if stale.
# ABOUTME: Shows cached line from state/tokens/latest.txt. If missing or >24h old, starts
# ABOUTME: background refresh via token-week.py --write-cache (detached, no wait).
# ABOUTME: Sourced by session-start.sh; fail-open and silent when no report exists yet.
# ABOUTME: Plan: docs/temp/token-study-2026-11/. Tests: scripts/tests/test-token-week.sh

_tokens_state="${TOKEN_STATE_DIR:-$HOME/.claude/state/tokens}"
_tokens_latest="$_tokens_state/latest.txt"
_token_week_script="${TOKEN_WEEK_SCRIPT:-$HOME/.claude/scripts/token-week.py}"

# Print cached line if exists
if [[ -s "$_tokens_latest" ]]; then
  cat "$_tokens_latest" 2>/dev/null || true
fi

# Check if cache needs refresh (missing or >24h old)
_needs_refresh=0
if [[ ! -f "$_tokens_latest" ]]; then
  _needs_refresh=1
elif [[ "$(uname)" == "Darwin" ]]; then
  # macOS: stat -f %m gives mtime in seconds since epoch
  _mtime=$(stat -f %m "$_tokens_latest" 2>/dev/null || echo 0)
  _now=$(date +%s)
  _age=$(( _now - _mtime ))
  [[ $_age -gt 86400 ]] && _needs_refresh=1
else
  # Linux: stat -c %Y
  _mtime=$(stat -c %Y "$_tokens_latest" 2>/dev/null || echo 0)
  _now=$(date +%s)
  _age=$(( _now - _mtime ))
  [[ $_age -gt 86400 ]] && _needs_refresh=1
fi

# Start background refresh if needed
if [[ $_needs_refresh -eq 1 && -f "$_token_week_script" ]]; then
  nohup python3 "$_token_week_script" --write-cache >/dev/null 2>&1 </dev/null &
fi

unset _tokens_state _tokens_latest _token_week_script _needs_refresh _mtime _now _age
