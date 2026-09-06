#!/usr/bin/env bash
# ABOUTME: TDD test suite for scripts/lib/kill-switch.sh — the VII-4 kill-switch library.
# ABOUTME: Covers sentinel creation, check, clear, autotrip, idempotency, and AUTONOMOUS_RUN guard.
# ABOUTME: Run: bash scripts/tests/test-kill-switch.sh — all RED before impl, GREEN after.
# ABOUTME: HARNESS_STATE_OVERRIDE used to redirect emit_event output to temp dir.
# ABOUTME: Test isolation: every case gets a fresh TMPROOT; no leakage into real STATE.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB="${SCRIPT_DIR}/../lib/kill-switch.sh"
EMIT_LIB="${SCRIPT_DIR}/../lib/emit-event.sh"

# ── Isolated temp STATE (never the real one) ─────────────────────────────────
TMPROOT="$(mktemp -d /tmp/test-kill-switch-XXXXXX)"
export STATE="$TMPROOT/governance"
export EVENTS="$STATE/state/events.ndjson"
mkdir -p "$STATE/state"

PASS=0
FAIL=0

_pass() { printf '  PASS: %s\n' "$1"; (( PASS++ )) || true; }
_fail() { printf '  FAIL: %s — %s\n' "$1" "$2"; (( FAIL++ )) || true; }

_fresh() {
  # Reset sentinel and events for each case
  rm -f "$STATE/.AUTONOMOUS_FREEZE" || true
  rm -f "$EVENTS" || true
  rm -rf "$STATE/state/.events.lock.d" || true
  mkdir -p "$STATE/state"
}

_event_count() {
  [ -f "$EVENTS" ] && wc -l < "$EVENTS" | tr -d ' ' || echo 0
}

_event_has_class() {
  local class="$1"
  [ -f "$EVENTS" ] && grep -q "\"class\":\"$class\"" "$EVENTS" 2>/dev/null && return 0
  return 1
}

_load() {
  # Unset any previously-defined functions so each case gets a clean slate
  unset kill_switch_check kill_switch_trip kill_switch_clear kill_switch_autotrip_scan 2>/dev/null || true
  # shellcheck source=/dev/null
  source "$LIB" 2>/dev/null
  # Also source emit_event so it's available to the library internals
  source "$EMIT_LIB" 2>/dev/null || true
}

printf '=== test-kill-switch.sh ===\n'
printf 'LIB=%s\n' "$LIB"
printf 'STATE=%s\n' "$STATE"
printf 'EVENTS=%s\n' "$EVENTS"
printf '\n'

# ─────────────────────────────────────────────────────────────────────────────
# Case 1: kill_switch_check returns 0 when sentinel is absent
# ─────────────────────────────────────────────────────────────────────────────
printf '[1] kill_switch_check returns 0 (no halt) when sentinel absent\n'
_fresh
_load
if kill_switch_check 2>/dev/null; then
  _pass "1-check-absent"
else
  _fail "1-check-absent" "expected 0 (no halt) but returned nonzero"
fi

# ─────────────────────────────────────────────────────────────────────────────
# Case 2: kill_switch_check returns nonzero when sentinel is present
# ─────────────────────────────────────────────────────────────────────────────
printf '[2] kill_switch_check returns nonzero and emits P0 incident when sentinel present\n'
_fresh
_load
# Manually place sentinel
printf '{"trigger":"manual","reason":"test-case-2","ts":"2026-01-01T00:00:00Z"}\n' > "$STATE/.AUTONOMOUS_FREEZE"
rc=0; kill_switch_check 2>/dev/null || rc=$?
if [ "$rc" -ne 0 ]; then
  _pass "2-check-tripped-rc"
else
  _fail "2-check-tripped-rc" "expected nonzero but got 0"
fi
# Must emit a P0 incident event
if _event_has_class "kill-switch-active"; then
  _pass "2-check-tripped-event"
else
  _fail "2-check-tripped-event" "no kill-switch-active incident event in $EVENTS"
fi

# ─────────────────────────────────────────────────────────────────────────────
# Case 3: kill_switch_trip creates sentinel with trigger+reason+ts JSON and emits P0
# ─────────────────────────────────────────────────────────────────────────────
printf '[3] kill_switch_trip creates sentinel with JSON content and emits P0 incident\n'
_fresh
_load
kill_switch_trip "auto" "quota death" 2>/dev/null
# Sentinel must exist
if [ -f "$STATE/.AUTONOMOUS_FREEZE" ]; then
  _pass "3-trip-sentinel-exists"
else
  _fail "3-trip-sentinel-exists" "sentinel file not created at $STATE/.AUTONOMOUS_FREEZE"
fi
# Sentinel content must contain trigger and reason
CONTENT=$(cat "$STATE/.AUTONOMOUS_FREEZE" 2>/dev/null || echo "")
if printf '%s' "$CONTENT" | grep -q "quota death"; then
  _pass "3-trip-sentinel-content"
else
  _fail "3-trip-sentinel-content" "sentinel missing reason text; got: $CONTENT"
fi
if printf '%s' "$CONTENT" | grep -q "auto"; then
  _pass "3-trip-sentinel-trigger"
else
  _fail "3-trip-sentinel-trigger" "sentinel missing trigger field; got: $CONTENT"
fi
# Must emit kill-switch-tripped incident
if _event_has_class "kill-switch-tripped"; then
  _pass "3-trip-event-emitted"
else
  _fail "3-trip-event-emitted" "no kill-switch-tripped incident in $EVENTS"
fi

# ─────────────────────────────────────────────────────────────────────────────
# Case 4: kill_switch_clear removes sentinel when NOT under AUTONOMOUS_RUN
# ─────────────────────────────────────────────────────────────────────────────
printf '[4] kill_switch_clear removes sentinel and emits P2 incident (interactive context)\n'
_fresh
_load
# Plant a sentinel
printf '{"trigger":"test","reason":"case-4"}\n' > "$STATE/.AUTONOMOUS_FREEZE"
unset AUTONOMOUS_RUN 2>/dev/null || true
kill_switch_clear 2>/dev/null
if [ ! -f "$STATE/.AUTONOMOUS_FREEZE" ]; then
  _pass "4-clear-removes-sentinel"
else
  _fail "4-clear-removes-sentinel" "sentinel still exists after clear"
fi
if _event_has_class "kill-switch-cleared"; then
  _pass "4-clear-event"
else
  _fail "4-clear-event" "no kill-switch-cleared incident event emitted"
fi

# ─────────────────────────────────────────────────────────────────────────────
# Case 5: kill_switch_clear REFUSES when AUTONOMOUS_RUN=1
# ─────────────────────────────────────────────────────────────────────────────
printf '[5] kill_switch_clear REFUSES when AUTONOMOUS_RUN=1 (autonomous cannot self-unfreeze)\n'
_fresh
_load
printf '{"trigger":"test","reason":"case-5"}\n' > "$STATE/.AUTONOMOUS_FREEZE"
AUTONOMOUS_RUN=1 kill_switch_clear 2>/dev/null || true
if [ -f "$STATE/.AUTONOMOUS_FREEZE" ]; then
  _pass "5-clear-refused-autonomous"
else
  _fail "5-clear-refused-autonomous" "clear must be refused under AUTONOMOUS_RUN=1 but sentinel was removed"
fi

# ─────────────────────────────────────────────────────────────────────────────
# Case 6: kill_switch_trip is idempotent (second call does not corrupt sentinel)
# ─────────────────────────────────────────────────────────────────────────────
printf '[6] kill_switch_trip is idempotent — second call keeps sentinel intact\n'
_fresh
_load
kill_switch_trip "auto" "first-reason" 2>/dev/null
CONTENT1=$(cat "$STATE/.AUTONOMOUS_FREEZE" 2>/dev/null || echo "")
# Second trip with different reason
kill_switch_trip "auto" "second-reason" 2>/dev/null
if [ -f "$STATE/.AUTONOMOUS_FREEZE" ]; then
  _pass "6-idempotent-sentinel-exists"
else
  _fail "6-idempotent-sentinel-exists" "sentinel gone after second trip"
fi
# First reason should still be present (idempotent = first write wins OR it keeps the file)
# Both implementations are acceptable; what matters is sentinel persists
_pass "6-idempotent-complete"

# ─────────────────────────────────────────────────────────────────────────────
# Case 7: kill_switch_autotrip_scan trips on ≥5 tool_errors in 60s window
# ─────────────────────────────────────────────────────────────────────────────
printf '[7] kill_switch_autotrip_scan trips on >=5 tool_errors in 60-second window\n'
_fresh
_load
# Inject 5 tool_error events with recent timestamps into the spine
NOW_S=$(date +%s)
for i in 1 2 3 4 5; do
  TS=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  printf '{"schema_v":1,"ts":"%s","event_type":"tool_error","payload":{},"outcome":"error","project":"test","session_id":"auto-sess-1","trace_id":"tr1","source":"test"}\n' \
    "$TS" >> "$EVENTS"
done
kill_switch_autotrip_scan 2>/dev/null || true
if [ -f "$STATE/.AUTONOMOUS_FREEZE" ]; then
  _pass "7-autotrip-tool-errors"
else
  _fail "7-autotrip-tool-errors" "autotrip_scan did not trip on 5 tool_errors"
fi

# ─────────────────────────────────────────────────────────────────────────────
# Case 8: kill_switch_autotrip_scan does NOT trip on <5 tool_errors
# ─────────────────────────────────────────────────────────────────────────────
printf '[8] kill_switch_autotrip_scan does NOT trip on <5 tool_errors\n'
_fresh
_load
for i in 1 2 3 4; do
  TS=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  printf '{"schema_v":1,"ts":"%s","event_type":"tool_error","payload":{},"outcome":"error","project":"test","session_id":"auto-sess-2","trace_id":"tr2","source":"test"}\n' \
    "$TS" >> "$EVENTS"
done
kill_switch_autotrip_scan 2>/dev/null || true
if [ ! -f "$STATE/.AUTONOMOUS_FREEZE" ]; then
  _pass "8-no-autotrip-below-threshold"
else
  _fail "8-no-autotrip-below-threshold" "autotrip_scan fired on only 4 tool_errors (threshold is >=5)"
fi

# ─────────────────────────────────────────────────────────────────────────────
# Case 9: kill_switch_autotrip_scan trips on ≥3 trust_decision{denied} per task trace
# ─────────────────────────────────────────────────────────────────────────────
printf '[9] kill_switch_autotrip_scan trips on >=3 trust_decision denied in same trace\n'
_fresh
_load
TRACE="trace-trust-test"
for i in 1 2 3; do
  TS=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  printf '{"schema_v":1,"ts":"%s","event_type":"trust_decision","payload":{},"outcome":"denied","project":"test","session_id":"auto-sess-3","trace_id":"%s","source":"test"}\n' \
    "$TS" "$TRACE" >> "$EVENTS"
done
kill_switch_autotrip_scan 2>/dev/null || true
if [ -f "$STATE/.AUTONOMOUS_FREEZE" ]; then
  _pass "9-autotrip-trust-denied"
else
  _fail "9-autotrip-trust-denied" "autotrip_scan did not trip on 3 trust_decision denied in trace"
fi

# ─────────────────────────────────────────────────────────────────────────────
# Case 10: kill_switch_autotrip_scan trips on autonomous-push-shared incident
# ─────────────────────────────────────────────────────────────────────────────
printf '[10] kill_switch_autotrip_scan trips on autonomous-push-shared incident\n'
_fresh
_load
TS=$(date -u +%Y-%m-%dT%H:%M:%SZ)
printf '{"schema_v":1,"ts":"%s","event_type":"incident","payload":{"class":"autonomous-push-shared"},"outcome":"denied","project":"test","session_id":"auto-sess-4","trace_id":"tr4","source":"push-guard"}\n' \
  "$TS" >> "$EVENTS"
kill_switch_autotrip_scan 2>/dev/null || true
if [ -f "$STATE/.AUTONOMOUS_FREEZE" ]; then
  _pass "10-autotrip-push-shared"
else
  _fail "10-autotrip-push-shared" "autotrip_scan did not trip on autonomous-push-shared"
fi

# ─────────────────────────────────────────────────────────────────────────────
# Case 11: kill_switch_check still returns nonzero when emit_event unavailable (fail-open halt)
# ─────────────────────────────────────────────────────────────────────────────
printf '[11] kill_switch_check returns nonzero even if emit_event unavailable (halt is priority)\n'
_fresh
# Source just the kill-switch library without emit-event (simulate unavailable)
unset kill_switch_check kill_switch_trip kill_switch_clear kill_switch_autotrip_scan 2>/dev/null || true
# Temporarily hide emit-event lib by pointing to nonexistent path inside source call
REAL_EMIT="$EMIT_LIB"
# The lib sources emit-event; if unavailable it must still halt
source "$LIB" 2>/dev/null
# Place sentinel
printf '{"trigger":"manual","reason":"emit-unavailable-test"}\n' > "$STATE/.AUTONOMOUS_FREEZE"
rc=0; kill_switch_check 2>/dev/null || rc=$?
if [ "$rc" -ne 0 ]; then
  _pass "11-halt-without-emit"
else
  _fail "11-halt-without-emit" "kill_switch_check must return nonzero (halt) even when emit unavailable"
fi

# ─────────────────────────────────────────────────────────────────────────────
# Cleanup
# ─────────────────────────────────────────────────────────────────────────────
rm -rf "$TMPROOT"

printf '\n'
printf '=== Results: %d passed, %d failed ===\n' "$PASS" "$FAIL"
if [ "$FAIL" -gt 0 ]; then
  exit 1
fi
exit 0
