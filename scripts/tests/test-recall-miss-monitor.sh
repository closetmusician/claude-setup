#!/usr/bin/env bash
# ABOUTME: TDD test suite for scripts/recall-miss-monitor.sh (Pillar V, task V4).
# ABOUTME: 5 oracle cases covering: qualifying miss emits incident, dedupe on re-run,
# ABOUTME: empty_for_known_topic:false events ignored, no recall_query events exits 0,
# ABOUTME: and malformed ndjson lines skipped without error.
# ABOUTME: All tests use mktemp sandboxes with $EVENTS env override; never touches real state.

set -uo pipefail

SCRIPT="${SCRIPT_OVERRIDE:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/recall-miss-monitor.sh}"

PASS=0
FAIL=0

_ok() {
  PASS=$(( PASS + 1 ))
  echo "  PASS: $1"
}

_fail() {
  FAIL=$(( FAIL + 1 ))
  echo "  FAIL: $1${2:+ — $2}"
}

_assert_eq() {
  local label="$1" got="$2" want="$3"
  if [[ "$got" == "$want" ]]; then
    _ok "$label"
  else
    _fail "$label" "got='$got' want='$want'"
  fi
}

# ── Timestamp helpers ────────────────────────────────────────────────────────
_ts_ago() {
  # Return RFC3339 UTC timestamp N seconds in the past
  python3 -c "
from datetime import datetime, timezone, timedelta
t = datetime.now(timezone.utc) - timedelta(seconds=$1)
print(t.strftime('%Y-%m-%dT%H:%M:%S.') + f'{t.microsecond//1000:03d}Z')
"
}

_ts_days_ago() {
  python3 -c "
from datetime import datetime, timezone, timedelta
t = datetime.now(timezone.utc) - timedelta(days=$1)
print(t.strftime('%Y-%m-%dT%H:%M:%S.') + f'{t.microsecond//1000:03d}Z')
"
}

echo ""
echo "========================================================================"
echo "recall-miss-monitor test suite (Pillar V, task V4)"
echo "========================================================================"

# ════════════════════════════════════════════════════════════════════════════
# ORACLE 1 — One qualifying miss → exactly one incident emitted
# A recall_query event with empty_for_known_topic:true, no prior incident
# with class:recall-miss for the same query → exactly 1 incident emitted.
echo ""
echo "── Oracle 1: one qualifying miss → exactly 1 incident emitted ──────────"

T1="$(mktemp -d /tmp/rmm-t1-XXXXXX)"
RECENT_TS="$(_ts_ago 3600)"

cat > "$T1/events.ndjson" <<EOF
{"ts":"${RECENT_TS}","schema":1,"session_id":"sess-abc","event_type":"recall_query","source":"harness","project":".claude","payload":{"query":"frobnicator deployment","hits":0,"empty_for_known_topic":true},"outcome":null}
EOF

out1="$(EVENTS="$T1/events.ndjson" STATE="$T1" bash "$SCRIPT" 2>&1)" || true
exit1=$?
_assert_eq "exit 0 on qualifying miss" "$exit1" "0"

incident_count="$(grep -c '"recall-miss"' "$T1/events.ndjson" 2>/dev/null || echo 0)"
_assert_eq "exactly 1 incident emitted" "$incident_count" "1"

rm -rf "$T1"

# ════════════════════════════════════════════════════════════════════════════
# ORACLE 2 — Re-run → 0 new incidents (dedupe)
# Same file from Oracle 1 but now includes the incident event already.
# Running the monitor again must NOT emit a second incident for the same query.
echo ""
echo "── Oracle 2: re-run → 0 new incidents (idempotent dedupe) ──────────────"

T2="$(mktemp -d /tmp/rmm-t2-XXXXXX)"
RECENT_TS2="$(_ts_ago 3600)"
EXISTING_INC_TS="$(_ts_ago 1800)"

cat > "$T2/events.ndjson" <<EOF
{"ts":"${RECENT_TS2}","schema":1,"session_id":"sess-abc","event_type":"recall_query","source":"harness","project":".claude","payload":{"query":"frobnicator deployment","hits":0,"empty_for_known_topic":true},"outcome":null}
{"ts":"${EXISTING_INC_TS}","schema":1,"session_id":"unknown","event_type":"incident","source":"recall-miss-monitor.sh","project":".claude","payload":{"severity":"P2","class":"recall-miss","query":"frobnicator deployment","detail":"recall returned 0 hits for 'frobnicator deployment' though journal FTS knows the topic"},"outcome":null}
EOF

lines_before="$(wc -l < "$T2/events.ndjson")"
EVENTS="$T2/events.ndjson" STATE="$T2" bash "$SCRIPT" 2>&1 || true
lines_after="$(wc -l < "$T2/events.ndjson")"

new_lines=$(( lines_after - lines_before ))
_assert_eq "re-run emits 0 new incidents (dedupe)" "$new_lines" "0"

rm -rf "$T2"

# ════════════════════════════════════════════════════════════════════════════
# ORACLE 3 — empty_for_known_topic:false events → ignored (no incident)
# A recall_query event with empty_for_known_topic:false must NOT produce an incident.
echo ""
echo "── Oracle 3: empty_for_known_topic:false → ignored, no incident ─────────"

T3="$(mktemp -d /tmp/rmm-t3-XXXXXX)"
TS3="$(_ts_ago 7200)"

cat > "$T3/events.ndjson" <<EOF
{"ts":"${TS3}","schema":1,"session_id":"sess-def","event_type":"recall_query","source":"harness","project":".claude","payload":{"query":"completely unknown zz99xyz","hits":0,"empty_for_known_topic":false},"outcome":null}
EOF

EVENTS="$T3/events.ndjson" STATE="$T3" bash "$SCRIPT" 2>&1 || true
# grep -c exits 1 on 0 matches; use grep -c ... || true to avoid false || echo 0 duplication
incident_count3="$({ grep -c '"'"'"recall-miss"'"'"' "$T3/events.ndjson" 2>/dev/null; } || true)"
incident_count3="${incident_count3:-0}"
_assert_eq "empty_for_known_topic:false → no incident emitted" "$incident_count3" "0"

rm -rf "$T3"

# ════════════════════════════════════════════════════════════════════════════
# ORACLE 4 — No recall_query events → exit 0 silently
# An events file with no recall_query events → monitor exits 0 with no incidents.
echo ""
echo "── Oracle 4: no recall_query events → exit 0 silent ────────────────────"

T4="$(mktemp -d /tmp/rmm-t4-XXXXXX)"

cat > "$T4/events.ndjson" <<EOF
{"ts":"2026-07-04T10:00:00.000Z","schema":1,"session_id":"s1","event_type":"trust_decision","source":"test","project":".claude","payload":{"class":"test"},"outcome":"ok"}
{"ts":"2026-07-04T10:01:00.000Z","schema":1,"session_id":"s1","event_type":"incident","source":"test","project":".claude","payload":{"class":"some-other-class"},"outcome":null}
EOF

lines_before4="$(wc -l < "$T4/events.ndjson")"
out4="$(EVENTS="$T4/events.ndjson" STATE="$T4" bash "$SCRIPT" 2>&1)" || true
exit4=$?
lines_after4="$(wc -l < "$T4/events.ndjson")"

_assert_eq "no recall_query → exit 0" "$exit4" "0"

new_lines4=$(( lines_after4 - lines_before4 ))
_assert_eq "no recall_query → no incidents emitted" "$new_lines4" "0"

rm -rf "$T4"

# ════════════════════════════════════════════════════════════════════════════
# ORACLE 5 — Malformed event line in ndjson → skipped, exit 0
# Garbage line in the middle of the file must be skipped gracefully.
# The one qualifying miss around it must still fire.
echo ""
echo "── Oracle 5: malformed ndjson line → skipped, exit 0 ───────────────────"

T5="$(mktemp -d /tmp/rmm-t5-XXXXXX)"
TS5="$(_ts_ago 1000)"

cat > "$T5/events.ndjson" <<EOF
{"ts":"${TS5}","schema":1,"session_id":"s2","event_type":"recall_query","source":"harness","project":".claude","payload":{"query":"valid topic missing fts","hits":0,"empty_for_known_topic":true},"outcome":null}
THIS IS NOT VALID JSON AT ALL {{{{{
{"ts":"${TS5}","schema":1,"session_id":"s3","event_type":"recall_query","source":"harness","project":".claude","payload":{"query":"another valid topic","hits":0,"empty_for_known_topic":false},"outcome":null}
EOF

out5="$(EVENTS="$T5/events.ndjson" STATE="$T5" bash "$SCRIPT" 2>&1)" || true
exit5=$?
_assert_eq "malformed line in ndjson → exit 0" "$exit5" "0"

# The one qualifying miss must have fired; the false one must not have.
incident_count5="$(grep -c '"recall-miss"' "$T5/events.ndjson" 2>/dev/null || echo 0)"
_assert_eq "malformed line skipped, valid miss still fires incident" "$incident_count5" "1"

rm -rf "$T5"

# ════════════════════════════════════════════════════════════════════════════
echo ""
echo "========================================================================"
echo "Results: PASS=$PASS  FAIL=$FAIL  (total=$(( PASS + FAIL )))"
echo "========================================================================"
echo ""

if [[ "$FAIL" -gt 0 ]]; then
  exit 1
fi
exit 0
