#!/bin/bash
# ABOUTME: PostToolUse hook implementing incident freeze detection (state machine).
# ABOUTME: Monitors Bash output for destructive remote ops (DELETE 2xx) and arms state.
# ABOUTME: If armed and a subsequent mutation fails (4xx/5xx), writes freeze file.
# ABOUTME: State: NORMAL -> ARMED (DELETE 2xx) -> FROZEN (recovery fail) or NORMAL (success/timeout).
# ABOUTME: Requires: jq. See docs/nerf-prevention.md section P1-4.

set -euo pipefail

# Safety net: never break the session on hook failure.
trap 'exit 0' ERR

STATE_FILE="/tmp/.claude-destructive-event"
FREEZE_FILE="/tmp/.claude-incident-freeze"
TIMEOUT_SECONDS=60

# Bail gracefully if jq is missing.
if ! command -v jq &>/dev/null; then
  echo "incident-freeze-detector: jq not found, skipping" >&2
  exit 0
fi

# Read the PostToolUse JSON from stdin.
INPUT=$(cat)

# Extract tool name. Only process Bash tool results.
TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // empty')
if [[ "$TOOL_NAME" != "Bash" ]]; then
  exit 0
fi

# Extract tool_result (PostToolUse provides the command output here).
TOOL_RESULT=$(echo "$INPUT" | jq -r '.tool_result // empty')
if [[ -z "$TOOL_RESULT" ]]; then
  exit 0
fi

# --- Check if currently ARMED (state file exists) ---
if [[ -f "$STATE_FILE" ]]; then
  # Read timestamp from state file and check for timeout.
  ARMED_TS=$(cat "$STATE_FILE" 2>/dev/null || echo "0")
  NOW_TS=$(date +%s)
  ELAPSED=$(( NOW_TS - ARMED_TS ))

  if [[ $ELAPSED -gt $TIMEOUT_SECONDS ]]; then
    # Timed out: disarm and return to NORMAL.
    rm -f "$STATE_FILE"
    exit 0
  fi

  # State is ARMED and within timeout. Check if this output shows a failure.
  # Look for HTTP 4xx or 5xx status codes in the output.
  if echo "$TOOL_RESULT" | grep -qE 'HTTP/[0-9.]+ [45][0-9]{2}'; then
    # Recovery failed. Trigger FREEZE.
    echo "$NOW_TS" > "$FREEZE_FILE"
    rm -f "$STATE_FILE"
    echo "incident-freeze-detector: FREEZE TRIGGERED — destructive op succeeded but recovery failed. All external mutations blocked. Remove ${FREEZE_FILE} to release." >&2
    exit 0
  fi

  # Check if this output shows a success (2xx) — recovery worked, disarm.
  if echo "$TOOL_RESULT" | grep -qE 'HTTP/[0-9.]+ 2[0-9]{2}'; then
    rm -f "$STATE_FILE"
    exit 0
  fi

  # Output has no HTTP status — stay armed (could be a local command).
  exit 0
fi

# --- Not ARMED: check if this output contains a destructive DELETE with 2xx ---
# Match patterns: "DELETE" + "HTTP/... 2xx" both present in output.
HAS_DELETE=false
HAS_SUCCESS=false

if echo "$TOOL_RESULT" | grep -qiE '(curl.*(-X|--request)[[:space:]]+DELETE|DELETE[[:space:]]+/(v[0-9]|api|beta)|method.*DELETE|(-X|--request)[[:space:]]*DELETE)'; then
  HAS_DELETE=true
fi

if echo "$TOOL_RESULT" | grep -qE 'HTTP/[0-9.]+ 2[0-9]{2}'; then
  HAS_SUCCESS=true
fi

if [[ "$HAS_DELETE" == "true" && "$HAS_SUCCESS" == "true" ]]; then
  # ARM the state machine. Record current timestamp.
  date +%s > "$STATE_FILE"
  echo "incident-freeze-detector: ARMED — destructive DELETE with 2xx detected. Monitoring for recovery failure." >&2
fi

exit 0
