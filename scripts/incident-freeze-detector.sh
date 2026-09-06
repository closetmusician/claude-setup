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

# Pillar I emit — purely additive; fail-open via emit_event design + || true guard.
_DETECT_EMIT_SH="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/emit-event.sh"
# shellcheck disable=SC1090
[[ -f "$_DETECT_EMIT_SH" ]] && source "$_DETECT_EMIT_SH" 2>/dev/null || true
unset _DETECT_EMIT_SH

# Read the PostToolUse JSON from stdin.
INPUT=$(cat)

# Extract tool name. Only process Bash tool results.
TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // empty')
if [[ "$TOOL_NAME" != "Bash" ]]; then
  exit 0
fi

# ── Pillar I: tool_error (always) and tool_call (sampled) emits ──────────────
# tool_error is NEVER sampled — errors are the signal (§2.4).
# tool_call is sampled via HARNESS_TOOL_SAMPLE (default 5%).
# These emits are purely additive: fail-open, no exit-code changes.
_TOOL_CMD=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null || echo "")
_TOOL_EXIT=$(echo "$INPUT" | jq -r '.tool_result_exit_code // empty' 2>/dev/null || echo "")
if [[ -n "$_TOOL_EXIT" && "$_TOOL_EXIT" != "0" ]]; then
  emit_event "tool_error" \
    "{\"tool\":\"Bash\",\"exit_code\":${_TOOL_EXIT}}" \
    tool="Bash" outcome="error" source="incident-freeze-detector.sh" || true
else
  # tool_call: emit only if HARNESS_TOOL_SAMPLE threshold passes.
  _SAMPLE_PCT="${HARNESS_TOOL_SAMPLE:-0.05}"
  _SAMPLE_INT=$(awk "BEGIN{printf \"%d\", $_SAMPLE_PCT * 100}" 2>/dev/null || echo "5")
  _THRESHOLD=$(( _SAMPLE_INT * 328 ))
  if [[ $(( RANDOM )) -lt $_THRESHOLD ]]; then
    emit_event "tool_call" \
      '{"tool":"Bash"}' \
      tool="Bash" outcome="ok" source="incident-freeze-detector.sh" || true
  fi
fi
unset _TOOL_CMD _TOOL_EXIT _SAMPLE_PCT _SAMPLE_INT _THRESHOLD

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
    # Emit incident event — purely additive, after freeze file is written.
    emit_event "incident" '{"class":"freeze_triggered","cause":"destructive_delete_recovery_fail"}' \
      outcome="denied" source="incident-freeze-detector.sh" || true
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
  # Emit incident (armed state) — purely additive.
  emit_event "incident" '{"class":"freeze_armed","cause":"destructive_delete_2xx"}' \
    source="incident-freeze-detector.sh" || true
fi

exit 0
