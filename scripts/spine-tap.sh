#!/usr/bin/env bash
# ABOUTME: Unconditional telemetry observer — NOT sentinel-gated, fail-open.
# ABOUTME: Emits agent_spawn/agent_result for Task|Agent tools; tool_error on nonzero
# ABOUTME: Bash exit; tool_call sampled at HARNESS_TOOL_SAMPLE rate (default 0.05).
# ABOUTME: Synthesizes session_start once per session_id via spine-seen/ dedup dir.
# ABOUTME: Writes to SPINE_HOME (default ~/.claude/state/state); never stdout/stderr.

# Guard rules: no -e (fail-open via trap); no stdout/stderr ever.
# Do NOT use set -e — we want the trap to catch all errors gracefully.
set -uo pipefail
trap 'exit 0' ERR

# ── Configuration ─────────────────────────────────────────────────────────────
# SPINE_HOME: directory containing events.ndjson (overridable for tests)
# SPINE_SEEN: directory for per-session dedup markers (overridable for tests)
_SPINE_HOME="${SPINE_HOME:-${HOME}/.claude/state/state}"
_SPINE_SEEN="${SPINE_SEEN:-${HOME}/.claude/state/spine-seen}"
_EVENTS="${_SPINE_HOME}/events.ndjson"
_LOCK="${_SPINE_HOME}/.events.lock.d"
_SAMPLE_RATE="${HARNESS_TOOL_SAMPLE:-0.05}"

# ── Fail-open guard: jq required ─────────────────────────────────────────────
command -v jq >/dev/null 2>&1 || exit 0

# ── Parse hook context from HOOK_STDIN_JSON ───────────────────────────────────
# Purpose: extract session_id, tool_name, hook phase, and exit code from stdin JSON.
# Hook phase detection: presence of tool_result → PostToolUse; tool_input → PreToolUse.
# HOOK_EVENT_NAME env override accepted (used by tests and for explicit wiring).
# Gotchas: HOOK_STDIN_JSON may be empty or invalid; jq errors → exit 0 via trap.
_HOOK_JSON="${HOOK_STDIN_JSON:-}"
[[ -z "$_HOOK_JSON" ]] && exit 0

_SESSION_ID="$(printf '%s' "$_HOOK_JSON" | jq -r '.session_id // "unknown"' 2>/dev/null || echo "unknown")"
_AGENT_ID="$(printf '%s' "$_HOOK_JSON" | jq -r '.agent_id // empty' 2>/dev/null || echo "")"
_TOOL_NAME="$(printf '%s' "$_HOOK_JSON" | jq -r '.tool_name // ""' 2>/dev/null || echo "")"
_EXIT_CODE="$(printf '%s' "$_HOOK_JSON" | jq -r '.tool_result.exit_code // 0' 2>/dev/null || echo "0")"

# Normalize: empty strings to safe defaults
[[ -z "$_SESSION_ID" ]] && _SESSION_ID="unknown"
[[ -z "$_TOOL_NAME" ]] && _TOOL_NAME=""
[[ -z "$_EXIT_CODE" ]] && _EXIT_CODE="0"

# Auto-detect hook phase from JSON structure; HOOK_EVENT_NAME env overrides
if [[ -n "${HOOK_EVENT_NAME:-}" ]]; then
  _HOOK_EVENT="$HOOK_EVENT_NAME"
elif printf '%s' "$_HOOK_JSON" | jq -e '.tool_result != null' >/dev/null 2>&1; then
  _HOOK_EVENT="PostToolUse"
elif printf '%s' "$_HOOK_JSON" | jq -e '.tool_input != null' >/dev/null 2>&1; then
  _HOOK_EVENT="PreToolUse"
else
  _HOOK_EVENT=""
fi

# ── mkdir-lock append helper ──────────────────────────────────────────────────
# Purpose: append one JSON line to events.ndjson under a mkdir-lock (Q1 protocol).
# Usage: _tap_append "$line"
# Gotchas: BSD stat -f %m only; never spin; append attempted regardless of lock.
_tap_append() {
  local line="$1"
  mkdir -p "$_SPINE_HOME" 2>/dev/null || true

  local _lock=0
  if mkdir "$_LOCK" 2>/dev/null; then
    _lock=1
  else
    local lock_mtime now age
    lock_mtime=$(stat -f %m "$_LOCK" 2>/dev/null || echo 0)
    now=$(date +%s)
    age=$(( now - lock_mtime ))
    if [[ "$age" -gt 5 ]]; then
      rm -rf "$_LOCK" 2>/dev/null && mkdir "$_LOCK" 2>/dev/null && _lock=1 || true
    fi
  fi

  printf '%s\n' "$line" >> "$_EVENTS" || true
  [[ "$_lock" -eq 1 ]] && rm -rf "$_LOCK" 2>/dev/null || true
}

# ── Timestamp helper (Q2 chain) ───────────────────────────────────────────────
_tap_ts() {
  if command -v gdate >/dev/null 2>&1; then
    gdate -u +%Y-%m-%dT%H:%M:%S.%3NZ 2>/dev/null && return
  fi
  if command -v python3 >/dev/null 2>&1; then
    python3 -c \
      "from datetime import datetime,timezone; print(datetime.now(timezone.utc).strftime('%Y-%m-%dT%H:%M:%S.')+str(datetime.now(timezone.utc).microsecond//1000).zfill(3)+'Z')" \
      2>/dev/null && return
  fi
  date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo "1970-01-01T00:00:00Z"
}

# ── JSON-safe string escaping (no jq fork needed for simple strings) ──────────
# Purpose: escape a string for use as a JSON string value.
# Usage: _je_out=$(_je "raw string")
_je() {
  local s="$1"
  s="${s//\\/\\\\}"
  s="${s//\"/\\\"}"
  s="${s//$'\n'/\\n}"
  s="${s//$'\r'/\\r}"
  s="${s//$'\t'/\\t}"
  printf '%s' "$s"
}

# ── session_start synthesis (once per session_id via spine-seen/ dedup) ──────
# Purpose: emit one session_start per session to give headless -p sessions an anchor.
# Gotchas: uses a sentinel file under SPINE_SEEN; harmless if dir is missing.
_maybe_emit_session_start() {
  [[ -z "$_SESSION_ID" || "$_SESSION_ID" == "unknown" ]] && return 0
  mkdir -p "$_SPINE_SEEN" 2>/dev/null || return 0
  local seen_file="${_SPINE_SEEN}/${_SESSION_ID}.seen"
  [[ -f "$seen_file" ]] && return 0

  # Mark as seen first to prevent races
  touch "$seen_file" 2>/dev/null || return 0

  local ts agent_null project line
  ts="$(_tap_ts)"
  [[ -n "$_AGENT_ID" ]] && agent_null="\"$(_je "$_AGENT_ID")\"" || agent_null="null"
  project="$(basename "$(git rev-parse --show-toplevel 2>/dev/null)" 2>/dev/null || echo "~global")"
  [[ -z "$project" ]] && project="~global"

  line=$(printf \
    '{"ts":"%s","schema":1,"session_id":"%s","agent_id":%s,"event_type":"session_start","source":"spine-tap.sh","project":"%s","payload":{"synthesized":true},"tool":null,"skill":null,"outcome":null,"evidence_ref":null,"trace_id":null}' \
    "$(_je "$ts")" "$(_je "$_SESSION_ID")" "$agent_null" "$(_je "$project")" 2>/dev/null)
  [[ -n "$line" ]] && _tap_append "$line" || true
}

# ── Emit helper ───────────────────────────────────────────────────────────────
# Purpose: build and append one schema-v1 event line.
# Usage: _emit_tap <event_type> <tool_val_or_empty> <payload_json>
_emit_tap() {
  local event_type="$1" tool_val="$2" payload="$3"
  local ts agent_null project tool_field line

  ts="$(_tap_ts)"
  [[ -n "$_AGENT_ID" ]] && agent_null="\"$(_je "$_AGENT_ID")\"" || agent_null="null"
  project="$(basename "$(git rev-parse --show-toplevel 2>/dev/null)" 2>/dev/null || echo "~global")"
  [[ -z "$project" ]] && project="~global"
  [[ -n "$tool_val" ]] && tool_field="\"$(_je "$tool_val")\"" || tool_field="null"

  line=$(printf \
    '{"ts":"%s","schema":1,"session_id":"%s","agent_id":%s,"event_type":"%s","source":"spine-tap.sh","project":"%s","payload":%s,"tool":%s,"skill":null,"outcome":null,"evidence_ref":null,"trace_id":null}' \
    "$(_je "$ts")" "$(_je "$_SESSION_ID")" "$agent_null" \
    "$(_je "$event_type")" "$(_je "$project")" \
    "${payload:-{\}}" "$tool_field" 2>/dev/null)
  [[ -n "$line" ]] && _tap_append "$line" || true
}

# ── Main dispatch ─────────────────────────────────────────────────────────────

# Always try to emit session_start for this session_id first
_maybe_emit_session_start

# Route by hook event and tool name
case "$_HOOK_EVENT" in
  PreToolUse)
    case "$_TOOL_NAME" in
      Task|Agent)
        _emit_tap "agent_spawn" "$_TOOL_NAME" '{"trigger":"PreToolUse"}'
        ;;
      # Other tools: no tap on PreToolUse
    esac
    ;;
  PostToolUse)
    case "$_TOOL_NAME" in
      Task|Agent)
        _emit_tap "agent_result" "$_TOOL_NAME" '{"trigger":"PostToolUse"}'
        ;;
      Bash)
        # tool_error: always on nonzero exit (never sampled — errors are the signal)
        if [[ "$_EXIT_CODE" != "0" ]]; then
          _emit_tap "tool_error" "Bash" "{\"exit_code\":${_EXIT_CODE}}"
        else
          # tool_call: sampled at HARNESS_TOOL_SAMPLE rate
          # Note: cannot use 'local' here (not inside a function); use plain vars.
          _sample_int=$(awk "BEGIN{printf \"%d\", ${_SAMPLE_RATE} * 100}" 2>/dev/null || echo "5")
          _threshold=$(( _sample_int * 328 ))  # RANDOM range 0-32767; 32768/100 ≈ 328
          if [[ "$RANDOM" -lt "$_threshold" ]]; then
            _emit_tap "tool_call" "Bash" '{"trigger":"PostToolUse"}'
          fi
        fi
        ;;
      # Other tools: no tap on PostToolUse
    esac
    ;;
  # Other hook events: no tap
esac

exit 0
