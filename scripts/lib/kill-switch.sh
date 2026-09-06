#!/usr/bin/env bash
# ABOUTME: VII-4 kill-switch library — single mechanical stop for autonomous execution.
# ABOUTME: Sentinel: $STATE/.AUTONOMOUS_FREEZE. Functions: kill_switch_check,
# ABOUTME: kill_switch_trip, kill_switch_clear (interactive-only), kill_switch_autotrip_scan.
# ABOUTME: Scope: autonomous-plane enforcement only; interactive sessions never call these.
# ABOUTME: Usage: source in night-runner.sh / flywheel-dispatcher.sh; check at start + boundary.
#
# Design notes:
#   - set -uo pipefail (no -e) + trap 'exit 0' ERR when sourced-as-hook so errors never kill caller.
#   - BSD-safe: no GNU-only flags, no flock (absent on macOS — see substrate-decision §Q1).
#   - emit_event() sourced lazily at call time so the library is safe to source without a live spine.
#   - kill_switch_clear is INTERACTIVE-ONLY: refuses (returns 1 + logs) when AUTONOMOUS_RUN=1.
#     A runaway autonomous run cannot un-freeze itself.
#   - SCOPE INVARIANT: auto-trip + enforcement only matters under AUTONOMOUS_RUN. The functions
#     themselves are callable anywhere, but callers in the interactive plane have no business
#     calling kill_switch_check or kill_switch_autotrip_scan — they would be no-ops or false trips.
#   - harness queue clear-freeze should call kill_switch_clear; do NOT edit bin/harness queue
#     directly from this file to avoid collision with the VI builder.

set -uo pipefail
trap 'exit 0' ERR

# ── State resolution ──────────────────────────────────────────────────────────
# Honour $STATE override (used by tests); fall back to global durable home.
# See substrate-decision §Q3: global durable home is ~/.claude/state (I-5 amendment).
_KS_STATE="${STATE:-$HOME/.claude/state}"
_KS_SENTINEL="${_KS_STATE}/.AUTONOMOUS_FREEZE"
_KS_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
_KS_EMIT="${_KS_LIB_DIR}/emit-event.sh"

# ── Internal helpers ──────────────────────────────────────────────────────────

# _ks_emit <event_type> <json_payload> [k=v ...]
# Purpose: Source emit-event.sh lazily and call emit_event; fully fail-open.
# Usage: internal only; never call directly from outside this lib.
# Gotchas: If emit-event.sh is unavailable, falls back to stderr log only.
_ks_emit() {
  local event_type="$1"; shift
  local payload="$1"; shift
  # Source emit lib if not already loaded (idempotent — emit_event function check)
  if ! declare -f emit_event >/dev/null 2>&1; then
    # shellcheck source=/dev/null
    source "$_KS_EMIT" 2>/dev/null || true
  fi
  if declare -f emit_event >/dev/null 2>&1; then
    emit_event "$event_type" "$payload" "$@" source="kill-switch.sh" 2>/dev/null || true
  fi
}

# _ks_ts: second-precision UTC timestamp (BSD-safe; gdate not required here).
# Purpose: Produce an RFC3339 timestamp for sentinel content.
# Usage: ts=$(_ks_ts)
# Gotchas: Only second precision needed for sentinel (not spine); avoids gdate dependency.
_ks_ts() {
  date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo "1970-01-01T00:00:00Z"
}

# ── Public API ────────────────────────────────────────────────────────────────

# kill_switch_check
# Purpose: Return nonzero if the freeze sentinel is present; emit a P0 incident.
# Usage: kill_switch_check || exit 1  (call at runner start and task boundary)
# Gotchas: Halt is the priority — returns nonzero even if emit_event is unavailable.
#   Never called by interactive code paths (callers enforce AUTONOMOUS_RUN separation).
kill_switch_check() {
  # Re-read STATE override each call (tests may change it between calls)
  local sentinel="${STATE:+${STATE}/.AUTONOMOUS_FREEZE}"
  [ -z "$sentinel" ] && sentinel="$_KS_SENTINEL"
  if [[ -f "$sentinel" ]]; then
    local reason
    reason=$(cat "$sentinel" 2>/dev/null || echo "manual")
    # Build payload via jq --arg so $reason is properly escaped regardless of content
    # (reason may be JSON text from a structured sentinel — raw interpolation produces invalid JSON)
    local _ks_payload
    _ks_payload=$(jq -cn --arg r "$reason" \
      '{"severity":"P0","class":"kill-switch-active","detail":("Autonomous execution halted: " + $r)}' \
      2>/dev/null) || _ks_payload='{"severity":"P0","class":"kill-switch-active","detail":"Autonomous execution halted"}'
    _ks_emit "incident" "$_ks_payload" \
      outcome=denied 2>/dev/null || true
    printf 'KILL-SWITCH ACTIVE: %s — all autonomous execution halted. Remove %s to resume.\n' \
      "$reason" "$sentinel" >&2
    return 1
  fi
  return 0
}

# kill_switch_trip <trigger> <reason>
# Purpose: Create the freeze sentinel with trigger+reason+ts JSON; emit P0 incident.
# Usage: kill_switch_trip "auto" "quota death"  — idempotent: if sentinel already exists, no-op.
# Gotchas: trigger should be "manual" | "auto"; reason is free text (avoid embedded quotes).
kill_switch_trip() {
  local trigger="${1:-auto}"
  local reason="${2:-unspecified anomaly}"
  local sentinel="${STATE:+${STATE}/.AUTONOMOUS_FREEZE}"
  [ -z "$sentinel" ] && sentinel="$_KS_SENTINEL"
  local ts
  ts=$(_ks_ts)

  # Idempotent: do not overwrite an existing sentinel (first trip wins).
  if [[ -f "$sentinel" ]]; then
    # Still emit a P0 so every invocation is traceable, but keep the original sentinel.
    _ks_emit "incident" \
      "{\"severity\":\"P0\",\"class\":\"kill-switch-tripped\",\"detail\":\"$reason (idempotent — sentinel already exists)\",\"trigger\":\"$trigger\"}" \
      outcome=denied 2>/dev/null || true
    printf 'KILL-SWITCH already TRIPPED (idempotent): %s\n' "$reason" >&2
    return 0
  fi

  # Write sentinel as JSON-like text with trigger, reason, ts for human readability.
  printf '{"trigger":"%s","reason":"%s","ts":"%s"}\n' "$trigger" "$reason" "$ts" > "$sentinel"

  _ks_emit "incident" \
    "{\"severity\":\"P0\",\"class\":\"kill-switch-tripped\",\"detail\":\"$reason\",\"trigger\":\"$trigger\"}" \
    outcome=denied 2>/dev/null || true
  printf 'KILL-SWITCH TRIPPED: %s\n' "$reason" >&2
}

# kill_switch_clear
# Purpose: Remove the freeze sentinel; INTERACTIVE-ONLY.
# Usage: kill_switch_clear  — called by the user or `harness queue clear-freeze`.
# Gotchas: REFUSES when AUTONOMOUS_RUN=1. A runaway autonomous run cannot un-freeze itself.
#   harness queue clear-freeze should call this function (do NOT edit bin/harness queue here).
kill_switch_clear() {
  local sentinel="${STATE:+${STATE}/.AUTONOMOUS_FREEZE}"
  [ -z "$sentinel" ] && sentinel="$_KS_SENTINEL"

  # Guard: refuse if called from an autonomous context.
  if [[ "${AUTONOMOUS_RUN:-}" == "1" ]]; then
    printf 'KILL-SWITCH CLEAR REFUSED: autonomous runs cannot un-freeze themselves (AUTONOMOUS_RUN=1).\n' >&2
    return 1
  fi

  rm -f "$sentinel" 2>/dev/null || true
  _ks_emit "incident" \
    '{"severity":"P2","class":"kill-switch-cleared","detail":"Autonomous freeze lifted"}' \
    outcome=ok 2>/dev/null || true
  printf 'Kill-switch cleared.\n' >&2
}

# kill_switch_autotrip_scan
# Purpose: Read the spine for breach conditions and trip the kill-switch if any threshold met.
# Usage: kill_switch_autotrip_scan  — called by a monitor or harness doctor to enforce auto-trip.
# Gotchas: Pure query function — reads $STATE/state/events.ndjson (or EVENTS env override).
#   Thresholds: >=5 tool_errors in last 60s window; >=3 trust_decision{denied} per trace;
#   any autonomous-push-shared incident; any autonomous-secret-detected incident.
#   Scope invariant: only meaningful under AUTONOMOUS_RUN — document but do NOT gate here
#   (the scan itself is safe from any context; enforcement is the runner's responsibility).
kill_switch_autotrip_scan() {
  local state_dir="${STATE:-$_KS_STATE}"
  local events_file="${EVENTS:-${state_dir}/state/events.ndjson}"

  [[ -f "$events_file" ]] || return 0

  # ── Threshold 1: ≥5 tool_errors in a 60-second window ───────────────────
  # Compute the cutoff timestamp 60s ago (second precision; BSD-safe).
  local cutoff
  cutoff=$(date -u -v-60S +%Y-%m-%dT%H:%M:%SZ 2>/dev/null) || \
  cutoff=$(python3 -c "from datetime import datetime,timezone,timedelta; \
    print((datetime.now(timezone.utc)-timedelta(seconds=60)).strftime('%Y-%m-%dT%H:%M:%SZ'))" \
    2>/dev/null) || cutoff=""

  if [[ -n "$cutoff" ]]; then
    # Count tool_error events whose ts >= cutoff.
    # BSD-safe: no 3-arg match(); extract ts via grep+sed, then compare in awk.
    local tool_error_count
    tool_error_count=$(grep '"event_type":"tool_error"' "$events_file" 2>/dev/null | \
      grep -o '"ts":"[^"]*"' | \
      sed 's/"ts":"//;s/"//' | \
      awk -v cutoff="$cutoff" '$1 >= cutoff { count++ } END { print (count+0) }' \
      2>/dev/null || echo 0)
    if (( tool_error_count >= 5 )); then
      kill_switch_trip "auto" "tool_error spike: $tool_error_count errors in 60s window (threshold >=5)"
      return 0
    fi
  fi

  # ── Threshold 2: ≥3 trust_decision{denied} in any single trace ──────────
  # Group by trace_id, count denied trust_decisions per trace.
  local trust_breach
  trust_breach=$(grep '"event_type":"trust_decision"' "$events_file" 2>/dev/null | \
    grep '"outcome":"denied"' | \
    grep -o '"trace_id":"[^"]*"' | \
    sort | uniq -c | \
    awk '$1 >= 3 { print $0 }' | head -1 2>/dev/null || echo "")
  if [[ -n "$trust_breach" ]]; then
    kill_switch_trip "auto" "trust_decision denied spike: >=3 denials in single task trace"
    return 0
  fi

  # ── Threshold 3: any autonomous-push-shared incident ─────────────────────
  if grep -q '"class":"autonomous-push-shared"' "$events_file" 2>/dev/null; then
    kill_switch_trip "auto" "autonomous-push-shared incident detected — push guard tripped"
    return 0
  fi

  # ── Threshold 4: any autonomous-secret-detected incident ─────────────────
  if grep -q '"class":"autonomous-secret-detected"' "$events_file" 2>/dev/null; then
    kill_switch_trip "auto" "autonomous-secret-detected — secret written by autonomous run"
    return 0
  fi

  return 0
}
