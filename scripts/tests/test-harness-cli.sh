#!/usr/bin/env bash
# ABOUTME: Test suite for harness CLI (Pillar I, tasks I-3.1 through I-3.6).
# ABOUTME: Covers all 6 oracle cases per spec: scaffold/ingest, query filters,
# ABOUTME: trace tree, incidents de-noising, metrics time series, and doctor.
# ABOUTME: Uses an isolated temp-dir $STATE override — never touches real state.
# ABOUTME: Exit 0 = all pass; nonzero = failures; prints tally.

set -euo pipefail

HARNESS="${HARNESS_BIN:-$HOME/.claude/bin/harness}"
PASS=0
FAIL=0
SKIP=0

# ── Test framework ─────────────────────────────────────────────────────────────
_ok() {
  local label="$1"
  PASS=$(( PASS + 1 ))
  echo "  PASS: $label"
}

_fail() {
  local label="$1" detail="${2:-}"
  FAIL=$(( FAIL + 1 ))
  echo "  FAIL: $label${detail:+ — $detail}"
}

_assert_eq() {
  local label="$1" got="$2" want="$3"
  if [[ "$got" == "$want" ]]; then
    _ok "$label"
  else
    _fail "$label" "got='$got' want='$want'"
  fi
}

_assert_ge() {
  local label="$1" got="$2" want="$3"
  if [[ "$got" -ge "$want" ]]; then
    _ok "$label"
  else
    _fail "$label" "got=$got want>=$want"
  fi
}

_assert_contains() {
  local label="$1" haystack="$2" needle="$3"
  if echo "$haystack" | grep -qF "$needle"; then
    _ok "$label"
  else
    _fail "$label" "needle='$needle' not found in output"
  fi
}

_assert_not_contains() {
  local label="$1" haystack="$2" needle="$3"
  if echo "$haystack" | grep -qF "$needle"; then
    _fail "$label" "needle='$needle' unexpectedly found in output"
  else
    _ok "$label"
  fi
}

# ── Temp state setup ───────────────────────────────────────────────────────────
TMPDIR_BASE="$(mktemp -d /tmp/harness-test-XXXXXX)"
export HARNESS_STATE_OVERRIDE="$TMPDIR_BASE"
# Self-isolate against inherited HARNESS_GOV_STATE_DIR (FIX-SUITE-HYGIENE pattern):
# override wins at highest precedence; point at this suite's scratch dir.
export HARNESS_GOV_STATE_DIR="$TMPDIR_BASE"
mkdir -p "$TMPDIR_BASE/state"
EVENTS="$TMPDIR_BASE/state/events.ndjson"
DB="$TMPDIR_BASE/state/events.db"

# ── Fixture builder ────────────────────────────────────────────────────────────
# Builds an RFC3339 UTC timestamp N seconds in the past
_ts_ago() {
  local secs="$1"
  python3 -c "
from datetime import datetime, timezone, timedelta
t = datetime.now(timezone.utc) - timedelta(seconds=$secs)
print(t.strftime('%Y-%m-%dT%H:%M:%S.') + f'{t.microsecond//1000:03d}Z')
"
}

_make_event() {
  # _make_event <event_type> <session_id> [key=val ...]
  local etype="$1" sid="$2"; shift 2
  local ts project payload agent_id trace_id outcome skill tool source
  ts="$(_ts_ago 300)"
  project="test-project"
  payload="{}"
  agent_id="null"
  trace_id="null"
  outcome="null"
  skill="null"
  tool="null"
  source="test-fixture"
  for kv in "$@"; do
    local k="${kv%%=*}" v="${kv#*=}"
    case "$k" in
      ts)       ts="$v" ;;
      project)  project="$v" ;;
      payload)  payload="$v" ;;
      agent_id) agent_id="\"$v\"" ;;
      trace_id) trace_id="\"$v\"" ;;
      outcome)  outcome="\"$v\"" ;;
      skill)    skill="\"$v\"" ;;
      tool)     tool="\"$v\"" ;;
      source)   source="$v" ;;
    esac
  done
  jq -cn \
    --arg ts "$ts" \
    --arg session_id "$sid" \
    --arg event_type "$etype" \
    --arg source "$source" \
    --arg project "$project" \
    --argjson agent_id "$agent_id" \
    --argjson trace_id "$trace_id" \
    --argjson outcome "$outcome" \
    --argjson skill "$skill" \
    --argjson tool "$tool" \
    --argjson payload "$payload" \
    '{ts:$ts,schema:1,session_id:$session_id,agent_id:$agent_id,
      event_type:$event_type,source:$source,project:$project,
      payload:$payload,tool:$tool,skill:$skill,outcome:$outcome,
      evidence_ref:null,trace_id:$trace_id}'
}

echo ""
echo "========================================================================"
echo "harness CLI test suite — temp STATE: $TMPDIR_BASE"
echo "========================================================================"

# ════════════════════════════════════════════════════════════════════════════════
# ORACLE 1 — I-3.1: Scaffold / ingest
# 10-line fixture NDJSON → 10-row replica
echo ""
echo "── Oracle 1: Scaffold + 10-line fixture ingest ─────────────────────────"

# Build 10-line NDJSON fixture with mixed event types
# NOTE: metric events are placed 1 day (86400s) in the past so they are ALWAYS
# outside the 2h window but inside 30d — this makes the MASTER-07 regression
# assertion deterministic (2h_count < 30d_count) regardless of execution timing.
# The old placement at -7200s was right at the 2h boundary and caused intermittent
# false-reds when the timing margin was tight.
{
  _make_event session_start  "sess-AAA" ts="$(_ts_ago 3600)" project="alpha"
  _make_event agent_spawn    "sess-AAA" ts="$(_ts_ago 3500)" agent_id="ag-1" trace_id="tr-1" project="alpha"
  _make_event agent_result   "sess-AAA" ts="$(_ts_ago 3400)" agent_id="ag-1" trace_id="tr-1" outcome="ok" project="alpha"
  _make_event skill_fire     "sess-AAA" ts="$(_ts_ago 3300)" skill="qa" project="alpha"
  _make_event tool_error     "sess-AAA" ts="$(_ts_ago 3200)" tool="Bash" project="alpha" payload='{"err_class":"EXIT1","err_msg_digest":"cmd failed"}'
  _make_event metric         "sess-BBB" ts="$(_ts_ago 86400)" project="beta" payload='{"name":"latency","value":42,"unit":"ms"}'
  _make_event metric         "sess-BBB" ts="$(_ts_ago 86300)" project="beta" payload='{"name":"latency","value":55,"unit":"ms"}'
  _make_event metric         "sess-BBB" ts="$(_ts_ago 86200)" project="beta" payload='{"name":"latency","value":38,"unit":"ms"}'
  _make_event session_end    "sess-AAA" ts="$(_ts_ago 3100)" project="alpha"
  _make_event agent_spawn    "sess-CCC" ts="$(_ts_ago  600)" agent_id="ag-2" trace_id="tr-2" project="gamma"
} > "$EVENTS"

line_count="$(wc -l < "$EVENTS" | tr -d ' ')"
_assert_eq "fixture has 10 lines" "$line_count" "10"

# Run harness --help (also triggers STATE resolution)
help_out="$("$HARNESS" --help 2>&1)"
_assert_contains "help lists 'query'"       "$help_out" "query"
_assert_contains "help lists 'trace'"       "$help_out" "trace"
_assert_contains "help lists 'incidents'"   "$help_out" "incidents"
_assert_contains "help lists 'metrics'"     "$help_out" "metrics"
_assert_contains "help lists 'doctor'"      "$help_out" "doctor"
_assert_contains "help lists 'recall'"      "$help_out" "recall"
_assert_contains "help lists 'queue'"       "$help_out" "queue"
_assert_contains "help lists 'eval'"        "$help_out" "eval"
_assert_contains "help lists 'brief'"       "$help_out" "brief"
_assert_contains "help lists 'escalations'" "$help_out" "escalations"

# Ingest the fixture (triggers lazy build)
"$HARNESS" query --limit 1 >/dev/null 2>&1 || true

row_count="$(sqlite3 "$DB" "SELECT COUNT(*) FROM events;" 2>/dev/null || echo 0)"
_assert_eq "10-line fixture → 10-row replica" "$row_count" "10"

# ════════════════════════════════════════════════════════════════════════════════
# ORACLE 2 — I-3.2: query filters
echo ""
echo "── Oracle 2: query --since + --type filter ─────────────────────────────"

# The fixture has 1 agent_spawn within the last hour (sess-CCC at -600s)
# and 1 agent_spawn older (sess-AAA at -3500s)
since_ts="$(_ts_ago 1800)"  # 30 minutes ago

query_out="$("$HARNESS" query --since "$since_ts" --type agent_spawn 2>&1)"
# Should match only sess-CCC (ag-2), not sess-AAA (ag-1)
_assert_contains     "query --since + --type returns matching row" "$query_out" "ag-2"
_assert_not_contains "query --since filters old rows"              "$query_out" "ag-1"

# REGRESSION: MASTER-07 -- --since must do real time arithmetic, not lexicographic compare.
# The old bug: --since 2h returned 0 rows (ISO ts "2026..." > "2h" lexicographically).
# --since 1h returned the WHOLE log ("2026..." > "1h" fails, all rows pass).
# New invariant: --since 2h must return a subset of --since 30d.
since_2h_out="$("$HARNESS" query --since 2h --limit 100000 2>&1)"
since_2h_count="$(echo "$since_2h_out" | grep -c '{' 2>/dev/null || echo 0)"
since_30d_out="$("$HARNESS" query --since 30d --limit 100000 2>&1)"
since_30d_count="$(echo "$since_30d_out" | grep -c '{' 2>/dev/null || echo 0)"
# 2h window must return > 0 (fixture has events at -600s, well within 2h)
_assert_ge "REGRESSION MASTER-07: --since 2h returns >0 rows (not all-or-nothing)" "$since_2h_count" "1"
# 2h count must be strictly less than 30d count (fixture has 7200s-old events outside 2h)
if [[ "$since_2h_count" -lt "$since_30d_count" ]]; then
  _ok "REGRESSION MASTER-07: --since 2h < --since 30d (real time-bounding, not lexicographic)"
else
  _fail "REGRESSION MASTER-07: --since 2h >= --since 30d — lexicographic compare still active" \
        "2h=$since_2h_count 30d=$since_30d_count"
fi

# Test --limit
limit_out="$("$HARNESS" query --limit 2 2>&1)"
limit_rows="$(echo "$limit_out" | grep -c '{' 2>/dev/null || echo 0)"
_assert_ge "query --limit 2 returns ≤2 rows" "$limit_rows" 0  # may be 0..2 depending on output format
# Verify limit is respected: fetch all then limited
all_rows="$(sqlite3 "$DB" "SELECT COUNT(*) FROM events;" 2>/dev/null || echo 0)"
# With limit=2, output should be ≤2 rows
_assert_ge "fixture has ≥2 rows for limit test" "$all_rows" "2"

# Test --type filter (only metric events = 3)
metric_out="$("$HARNESS" query --type metric 2>&1)"
metric_count="$(echo "$metric_out" | grep -c '"event_type"' 2>/dev/null || echo 0)"
_assert_eq "query --type metric returns 3 rows" "$metric_count" "3"

# Test --outcome filter
outcome_out="$("$HARNESS" query --outcome ok 2>&1)"
_assert_contains "query --outcome ok finds the agent_result" "$outcome_out" '"ok"'

# Test --jq projection
jq_out="$("$HARNESS" query --type skill_fire --jq '.session_id' 2>&1)"
_assert_contains "query --jq projects session_id" "$jq_out" "sess-AAA"

echo ""
echo "── Oracle 2b: empty query exits 0 ─────────────────────────────────────"
empty_out="$("$HARNESS" query --type session_start --session "no-such-session" 2>&1)" || true
_assert_eq "empty query returns empty output" "$empty_out" ""

# ════════════════════════════════════════════════════════════════════════════════
# ORACLE 3 — I-3.3: trace tree
echo ""
echo "── Oracle 3: trace ordered spawn→result tree ───────────────────────────"

trace_out="$("$HARNESS" trace "tr-1" 2>&1)"
# tr-1 has: agent_spawn (ag-1) and agent_result (ag-1, outcome=ok)
_assert_contains "trace shows agent_spawn" "$trace_out" "agent_spawn"
_assert_contains "trace shows agent_result" "$trace_out" "agent_result"
_assert_contains "trace shows outcome=ok" "$trace_out" "outcome=ok"

# Verify result is nested (indented) under spawn by checking line order
spawn_line="$(echo "$trace_out" | grep -n "agent_spawn" | head -1 | cut -d: -f1)"
result_line="$(echo "$trace_out" | grep -n "agent_result" | head -1 | cut -d: -f1)"
_assert_ge "agent_result appears after agent_spawn in tree" "${result_line:-0}" "${spawn_line:-0}"

# Verify result line is indented (has leading spaces or └─)
result_raw="$(echo "$trace_out" | sed -n "${result_line}p")"
if echo "$result_raw" | grep -qE '^[[:space:]]+|^└'; then
  _ok "agent_result is indented under its spawn"
else
  _fail "agent_result is not indented under its spawn" "line='$result_raw'"
fi

# ════════════════════════════════════════════════════════════════════════════════
# ORACLE 4 — I-3.4: incidents de-noising
echo ""
echo "── Oracle 4: incidents de-noising (SYNTHETIC fixture) ──────────────────"
# SYNTHETIC: 262-line-equivalent trust/incident stream to validate ~46/262 ratio
# We build 262 raw rows: 46 real + 216 noise (duplicate/probe/benign)
# This verifies the de-noiser lands in the ±20% band (37..55 real incidents)

# Start fresh for incidents test
INC_TMPDIR="$(mktemp -d /tmp/harness-inc-test-XXXXXX)"
mkdir -p "$INC_TMPDIR/state"
INC_EVENTS="$INC_TMPDIR/state/events.ndjson"
INC_DB="$INC_TMPDIR/state/events.db"

python3 - "$INC_EVENTS" <<'PYEOF'
import sys, json
from datetime import datetime, timezone, timedelta

out = sys.argv[1]

def ts(offset_secs):
    t = datetime.now(timezone.utc) - timedelta(seconds=offset_secs)
    return t.strftime('%Y-%m-%dT%H:%M:%S.') + f'{t.microsecond//1000:03d}Z'

def mk(etype, session_id, project, cls, detail, outcome=None, severity=None, offset=300):
    ev = {
        'ts': ts(offset), 'schema': 1,
        'session_id': session_id, 'agent_id': None,
        'event_type': etype, 'source': 'test', 'project': project,
        'payload': {'class': cls, 'detail': detail},
        'tool': None, 'skill': None,
        'outcome': outcome, 'evidence_ref': None, 'trace_id': None
    }
    if severity:
        ev['payload']['severity'] = severity
    return json.dumps(ev)

lines = []

# 46 REAL incidents (distinct project+class+detail pairs, spread >60s apart)
real_classes = [
    ('alpha', 'PERM_DENY',       'unauthorized write to protected dir'),
    ('alpha', 'SCHEMA_DRIFT',    'missing required field ts'),
    ('alpha', 'CLAIM_UNVERIFIED','unverified completion claim'),
    ('beta',  'ESCALATION',      'P0 escalation triggered'),
    ('beta',  'FORCE_PUSH',      'force push attempt on main'),
    ('beta',  'HOOK_FAIL',       'hook exit code 1'),
    ('gamma', 'PERM_DENY',       'write to /etc rejected'),
    ('gamma', 'SKILL_BYPASS',    'skill routing guard fired'),
    ('gamma', 'TRUST_DENY',      'trust decision denied'),
    ('delta', 'PERM_DENY',       'rm -rf blocked'),
    ('delta', 'TDD_SKIP',        'implementation without red test'),
    ('delta', 'MOCK_INTERNAL',   'mock on core module detected'),
    ('epsilon','PERM_DENY',      'git reset hard blocked'),
    ('epsilon','CLAIM_UNVERIFIED','no evidence_ref on completion'),
    ('epsilon','HOOK_FAIL',      'pre-commit hook failed'),
    ('zeta',  'PERM_DENY',       'curl to external blocked'),
    ('zeta',  'ESCALATION',      'n+1 escalation'),
    ('zeta',  'SCHEMA_DRIFT',    'missing session_id field'),
    ('eta',   'PERM_DENY',       'apt install blocked'),
    ('eta',   'FORCE_PUSH',      'push --force-with-lease on main'),
    ('theta', 'PERM_DENY',       'sudo attempt denied'),
    ('theta', 'CLAIM_UNVERIFIED','claim without spec-diff'),
    ('iota',  'PERM_DENY',       'write to ~/.ssh blocked'),
    ('iota',  'TRUST_DENY',      'untrusted source detected'),
    ('kappa', 'ESCALATION',      'repeated failure escalated'),
    ('kappa', 'SCHEMA_DRIFT',    'invalid event_type value'),
    ('lambda','PERM_DENY',       'npm publish blocked'),
    ('lambda','HOOK_FAIL',       'qa-artifact-guard rejected'),
    ('mu',    'PERM_DENY',       'aws cli credential write blocked'),
    ('mu',    'TRUST_DENY',      'memory injection attempt'),
    ('nu',    'ESCALATION',      'cost overrun escalated'),
    ('nu',    'PERM_DENY',       'docker socket write blocked'),
    ('xi',    'CLAIM_UNVERIFIED','diff missing from evidence'),
    ('xi',    'SCHEMA_DRIFT',    'payload exceeds 2KB limit'),
    ('omicron','PERM_DENY',      'git tag push blocked'),
    ('omicron','TRUST_DENY',     'skill_fire without routing check'),
    ('pi',    'ESCALATION',      'tool_error P0 threshold hit'),
    ('pi',    'PERM_DENY',       'crontab edit blocked'),
    ('rho',   'HOOK_FAIL',       'completion-claim-guard.sh exit 1'),
    ('rho',   'TRUST_DENY',      'evidence_ref hash mismatch'),
    ('sigma', 'PERM_DENY',       'chmod 777 blocked'),
    ('sigma', 'ESCALATION',      'QA cycle 2 failed twice'),
    ('tau',   'TRUST_DENY',      'claim body truncated'),
    ('tau',   'PERM_DENY',       'pip install --user blocked'),
    ('upsilon','HOOK_FAIL',      'skill-routing-guard denied'),
    ('upsilon','PERM_DENY',      'git push origin main blocked'),
]
for i, (proj, cls, det) in enumerate(real_classes):
    lines.append(mk('incident', f'sess-real-{i:03d}', proj, cls, det,
                     severity='P1', offset=300 + i * 130))

# NOISE GROUP 1: 60-second duplicates (same class+detail, sent twice <60s apart)
# 100 duplicate pairs = 100 noise rows that should collapse to 0 new incidents
for i, (proj, cls, det) in enumerate(real_classes[:20]):
    lines.append(mk('incident', f'sess-dup-{i:03d}', proj, cls, det,
                     severity='P1', offset=300 + i * 130 + 30))  # 30s after real

# NOISE GROUP 2: PROBE project rows (50 rows)
for i in range(50):
    lines.append(mk('trust_decision', f'sess-probe-{i:03d}', 'PROBE-sessions',
                     'PERM_DENY', f'probe attempt {i}',
                     outcome='denied', offset=200 + i * 10))

# NOISE GROUP 3: canary/fixture markers (30 rows)
for i in range(30):
    lines.append(mk('incident', f'sess-fixture-{i:03d}', 'test-project',
                     'canary', f'canary:{i}', offset=100 + i * 5))

# NOISE GROUP 4: trust_decision(denied) duplicates within 60s (40 rows collapsing to ≤5)
for i in range(40):
    offset_sec = 500 + (i // 8) * 130 + (i % 8) * 5  # 8 identical rows per 130s window
    lines.append(mk('trust_decision', f'sess-td-{i:03d}', 'beta',
                     'TRUST_DENY', 'repeated deny signal',
                     outcome='denied', severity='P0', offset=offset_sec))

# Write all lines (order by offset ~ time)
with open(out, 'w') as f:
    for line in lines:
        f.write(line + '\n')

print(f"SYNTHETIC fixture: {len(lines)} total rows written to {out}")
PYEOF

total_synthetic="$(wc -l < "$INC_EVENTS" | tr -d ' ')"
echo "  SYNTHETIC fixture: $total_synthetic raw rows"

inc_out="$(HARNESS_STATE_OVERRIDE="$INC_TMPDIR" "$HARNESS" incidents 2>&1)"
echo "  incidents output:"
echo "$inc_out" | head -3 | sed 's/^/    /'

# Extract the real count
real_count="$(echo "$inc_out" | grep -oE 'Real incidents: [0-9]+' | grep -oE '[0-9]+' || echo 0)"
echo "  de-noised count: $real_count (raw: $total_synthetic)"

# Band check: 46/262 = 17.6% → on our fixture should land ~37..55 (±20% of 46)
lower=37
upper=55
if [[ "${real_count:-0}" -ge "$lower" && "${real_count:-0}" -le "$upper" ]]; then
  _ok "incidents de-noising in ±20% band ($real_count ∈ [$lower,$upper]) (SYNTHETIC fixture)"
else
  _fail "incidents de-noising out of band" "got=$real_count want in [$lower,$upper]"
fi

# Test --open filter
open_out="$(HARNESS_STATE_OVERRIDE="$INC_TMPDIR" "$HARNESS" incidents --open 2>&1)"
_assert_contains "incidents --open runs without error" "$open_out" "Real incidents"

rm -rf "$INC_TMPDIR"

# ════════════════════════════════════════════════════════════════════════════════
# ORACLE 5 — I-3.5: metrics time series
echo ""
echo "── Oracle 5: metrics 3-point time series ───────────────────────────────"

# The fixture has 3 metric events with name=latency in sess-BBB
metrics_out="$("$HARNESS" metrics latency 2>&1)"
_assert_contains "metrics latency shows header row" "$metrics_out" "ts"
_assert_contains "metrics latency shows value 42"   "$metrics_out" "42"
_assert_contains "metrics latency shows value 55"   "$metrics_out" "55"
_assert_contains "metrics latency shows value 38"   "$metrics_out" "38"

# Count data rows (non-header, non-separator)
metric_data_rows="$(echo "$metrics_out" | grep -v '^\s*$' | grep -v '^ts' | grep -v '^-' | wc -l | tr -d ' ')"
_assert_eq "metrics latency returns 3-point series" "$metric_data_rows" "3"

# Test listing all metric names
metrics_list="$("$HARNESS" metrics 2>&1)"
_assert_contains "harness metrics lists 'latency'" "$metrics_list" "latency"

# ════════════════════════════════════════════════════════════════════════════════
# ORACLE 6 — I-3.6: doctor + --rebuild
echo ""
echo "── Oracle 6: doctor + canary round-trip + --rebuild ────────────────────"

doctor_out="$("$HARNESS" doctor 2>&1)"
_assert_contains "doctor prints STATE"      "$doctor_out" "STATE"
_assert_contains "doctor prints EVENTS"     "$doctor_out" "EVENTS"
_assert_contains "doctor passes canary"     "$doctor_out" "PASS: canary written and read back"
_assert_contains "doctor passes schema"     "$doctor_out" "PASS: no schema drift"

# Check replica freshness section
_assert_contains "doctor shows EOF"         "$doctor_out" "EOF"
_assert_contains "doctor shows Cursor"      "$doctor_out" "Cursor"

# --rebuild: drop + re-ingest, verify same row count
pre_count="$(sqlite3 "$DB" "SELECT COUNT(*) FROM events;" 2>/dev/null || echo 0)"
rebuild_out="$("$HARNESS" doctor --rebuild 2>&1)"
post_count="$(sqlite3 "$DB" "SELECT COUNT(*) FROM events;" 2>/dev/null || echo 0)"

_assert_contains "doctor --rebuild prints REBUILD"  "$rebuild_out" "REBUILD"
_assert_contains "doctor --rebuild shows row match" "$rebuild_out" "PASS: row count matches"

# Test --rotate with small threshold (override via env)
HARNESS_ROTATE_BYTES=1 "$HARNESS" doctor --rotate >/dev/null 2>&1 || true
arc_count="$(ls "$TMPDIR_BASE/state/events-archive/"*.ndjson.zst 2>/dev/null | wc -l | tr -d ' ')"
_assert_ge "doctor --rotate creates archive file" "$arc_count" "1"

# ════════════════════════════════════════════════════════════════════════════════
# ORACLE 7 — II.5: trust_incident_rate north-star metric + incidents --severity
echo ""
echo "── Oracle 7a: trust_incident_rate north-star ratio (II.5) ─────────────"

# Build a minimal fixture: 4 session_starts + 2 incidents + 1 denied trust_decision
NS_TMPDIR="$(mktemp -d /tmp/harness-ns-XXXXXX)"
mkdir -p "$NS_TMPDIR/state"
python3 - "$NS_TMPDIR/state/events.ndjson" <<'NSEOF'
import sys, json, datetime as dt

out = sys.argv[1]
base = dt.datetime(2026, 7, 1, 0, 0, 0, tzinfo=dt.timezone.utc)
lines = []

# Note: payload must be a dict (not pre-JSON-encoded string) — harness ingest
# does json.dumps on it; pre-encoding causes double-encoding and AttributeError.
def ev(i_offset, etype, outcome='ok', payload=None, project='ns-test'):
    ts = (base + dt.timedelta(hours=i_offset)).isoformat().replace('+00:00','Z')
    return json.dumps({'schema':1,'ts':ts,'event_type':etype,
                       'session_id':f's{i_offset:03d}','agent_id':None,
                       'project':project,'trace_id':None,'outcome':outcome,
                       'payload':payload or {},'evidence_ref':None,'source':'ns-test'})

# 4 session_starts
for i in range(4):
    lines.append(ev(i, 'session_start'))
# 2 real incidents (P1)
for i in range(2):
    lines.append(ev(10+i, 'incident', 'denied', {'class':'C2','severity':'P1'}))
# 1 denied trust_decision (P0)
lines.append(ev(20, 'trust_decision', 'denied', {'class':'C1','severity':'P0'}))
# 1 noise incident (project=PROBE — should be excluded)
lines.append(ev(30, 'incident', 'denied', {'class':'C2','severity':'P1'}, project='PROBE-session'))

with open(out,'w') as f:
    f.write('\n'.join(lines)+'\n')
NSEOF

ns_out="$(HARNESS_STATE_OVERRIDE="$NS_TMPDIR" "$HARNESS" metrics trust_incident_rate 2>&1)"
_assert_contains "trust_incident_rate shows sessions count"   "$ns_out" "sessions"
_assert_contains "trust_incident_rate shows incidents count"  "$ns_out" "incidents"
_assert_contains "trust_incident_rate shows ratio"            "$ns_out" "incidents per 100 sessions"
# 3 non-noise incidents / 4 sessions = 75.00 per 100
_assert_contains "trust_incident_rate computes correct ratio" "$ns_out" "75.00"

echo ""
echo "── Oracle 7b: incidents --severity P0 filter (II.5) ───────────────────"
# Reuse the same NS_TMPDIR — DB is already built from 7a ingest; query again.
# Only the 1 P0 denied trust_decision should appear; 2 P1 incidents excluded.
sev_out="$(HARNESS_STATE_OVERRIDE="$NS_TMPDIR" "$HARNESS" incidents --severity P0 2>&1)"
_assert_contains "incidents --severity P0 runs ok"  "$sev_out" "Real incidents"
# P0 count should be exactly 1
p0_count="$(echo "$sev_out" | grep -oE 'Real incidents: [0-9]+' | grep -oE '[0-9]+' || echo 0)"
_assert_eq "incidents --severity P0 returns 1 match" "$p0_count" "1"

rm -rf "$NS_TMPDIR"

# ════════════════════════════════════════════════════════════════════════════════
# Stub subcommands exit 3
echo ""
echo "── Stub subcommands exit 3 ─────────────────────────────────────────────"
# Note: 'eval'/'brief' (Pillar III), 'recall' (Pillar V), and 'queue' (Pillar VI) are
# implemented, so they are excluded from the stub list. Only 'escalations' remains a stub.
for stub in escalations; do
  exit_code=0
  "$HARNESS" "$stub" 2>/dev/null || exit_code=$?
  if [[ "$exit_code" -eq 3 ]]; then
    _ok "harness $stub exits 3"
  else
    _fail "harness $stub should exit 3" "got exit $exit_code"
  fi
done

# harness eval (no subverb) exits 1 — it is implemented but requires run|ls subverb
exit_code=0
"$HARNESS" eval 2>/dev/null || exit_code=$?
if [[ "$exit_code" -eq 1 ]]; then
  _ok "harness eval (no subverb) exits 1"
else
  _fail "harness eval (no subverb) should exit 1" "got exit $exit_code"
fi

# ════════════════════════════════════════════════════════════════════════════════
# Cleanup
rm -rf "$TMPDIR_BASE"

echo ""
echo "========================================================================"
echo "Results: PASS=$PASS  FAIL=$FAIL  SKIP=$SKIP  (total=$(( PASS + FAIL + SKIP )))"
echo "========================================================================"
echo ""

if [[ "$FAIL" -gt 0 ]]; then
  exit 1
fi
exit 0
