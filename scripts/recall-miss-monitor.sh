#!/usr/bin/env bash
# ABOUTME: Pillar V recall-miss monitor — detects recall_query events where the
# ABOUTME: journal FTS knew the topic but the federation returned 0 hits (data-quality gap).
# ABOUTME: Emits P2 incident events for each new miss not already covered by a prior
# ABOUTME: incident of class recall-miss for the same query within 2 days (idempotent).
# ABOUTME: Intended as step 5 of scripts/flywheel/nightly-flywheel.sh (not yet built).

set -uo pipefail
# Fail-open: any unexpected error exits 0 silently — never breaks the nightly pipeline.
trap 'exit 0' ERR

# ── Dependency check: require jq ─────────────────────────────────────────────
command -v jq >/dev/null 2>&1 || exit 0

# ── Resolve paths ─────────────────────────────────────────────────────────────
# $EVENTS: path to events.ndjson. Test harness overrides via env.
# $STATE:  governance state dir (for emit-event.sh sourcing). Defaults to resolved dir.
_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)"

if [[ -z "${STATE:-}" ]]; then
  _toplevel="$(git rev-parse --show-toplevel 2>/dev/null)" || true
  if [[ -n "${_toplevel:-}" ]]; then
    STATE="${_toplevel}/.agents/claude-governance"
  else
    STATE="${HOME}/.claude/.agents/claude-governance"
  fi
fi

# Default events file: use $EVENTS env override (tests) or canonical spine path
if [[ -z "${EVENTS:-}" ]]; then
  # Production mode: Try harness query first (functional); fall back to ndjson scan
  _RMM_TEST_MODE=0
  _HARNESS="${HOME}/.claude/bin/harness"
  if command -v "$_HARNESS" >/dev/null 2>&1; then
    # harness query returns ndjson lines — capture into temp file for processing
    _EVENTS_TMP="$(mktemp /tmp/rmm-events-XXXXXX.ndjson)"
    "$_HARNESS" query --type recall_query --since 1d 2>/dev/null > "$_EVENTS_TMP" || true
    _RMM_EVENTS_SOURCE="harness"
  else
    _EVENTS_TMP=""
    _RMM_EVENTS_SOURCE="ndjson"
  fi
  # Also need full events for dedupe check (harness query can't filter incidents by payload)
  _FULL_EVENTS="${STATE}/state/events.ndjson"
  _WRITE_EVENTS="${_FULL_EVENTS}"
else
  # Test mode: $EVENTS is the full ndjson file; filter recall_query in-process.
  # IMPORTANT: use direct-append path — emit_event's _EMIT_STATE_DIR is cached at
  # source time to the real repo's governance dir, not the test sandbox.
  _RMM_TEST_MODE=1
  _EVENTS_TMP=""
  _RMM_EVENTS_SOURCE="ndjson"
  _FULL_EVENTS="${EVENTS}"
  _WRITE_EVENTS="${EVENTS}"
fi

# Source emit-event.sh for incident emission
_EMIT_SH="${_SCRIPT_DIR}/lib/emit-event.sh"
if [[ -f "${_EMIT_SH}" ]]; then
  # shellcheck source=/dev/null
  source "${_EMIT_SH}" 2>/dev/null || true
fi

# ── Cutoff: 1 day ago (ISO8601 UTC) ──────────────────────────────────────────
_CUTOFF="$(python3 -c "
from datetime import datetime, timezone, timedelta
t = datetime.now(timezone.utc) - timedelta(days=1)
print(t.strftime('%Y-%m-%dT%H:%M:%S.000Z'))
" 2>/dev/null)" || _CUTOFF=""

# ── Dedupe window: 2 days ago ─────────────────────────────────────────────────
_DEDUP_CUTOFF="$(python3 -c "
from datetime import datetime, timezone, timedelta
t = datetime.now(timezone.utc) - timedelta(days=2)
print(t.strftime('%Y-%m-%dT%H:%M:%S.000Z'))
" 2>/dev/null)" || _DEDUP_CUTOFF=""

# ── Read recall_query events from the last 1 day ──────────────────────────────
# Purpose: extract qualifying misses (empty_for_known_topic == true).
# Uses either the temp file from harness query or direct ndjson scan.
# Gotchas: Each line is a separate JSON event; malformed lines are skipped silently.
_process_events() {
  local events_source="$1"   # file path to read from (ndjson, one event per line)
  local full_events="$2"     # full events.ndjson for dedupe reads and new incident writes
  local cutoff="$3"          # ISO8601 cutoff (skip events older than this)
  local dedup_cutoff="$4"    # ISO8601 cutoff for dedupe window

  # Read events line-by-line; use python3 for JSON parsing + dedupe check
  python3 - "$events_source" "$full_events" "$cutoff" "$dedup_cutoff" <<'PYEOF'
import sys, json, os
from datetime import datetime, timezone

events_source = sys.argv[1]   # ndjson file with recall_query events to scan
full_events   = sys.argv[2]   # full events.ndjson for dedupe + append
cutoff        = sys.argv[3]   # 1-day ago cutoff
dedup_cutoff  = sys.argv[4]   # 2-day ago cutoff for incident dedupe window

# ── Load existing recall-miss incidents within the 2-day dedup window ─────────
# Purpose: build a set of (query) keys already covered so we don't re-emit.
covered_queries = set()
if os.path.isfile(full_events):
    try:
        with open(full_events, 'r', encoding='utf-8', errors='replace') as f:
            for raw_line in f:
                line = raw_line.strip()
                if not line:
                    continue
                try:
                    ev = json.loads(line)
                except json.JSONDecodeError:
                    continue
                if ev.get('event_type') != 'incident':
                    continue
                p = ev.get('payload', {})
                if p.get('class') != 'recall-miss':
                    continue
                # Only count incidents within the 2-day dedup window
                ts = ev.get('ts', '')
                if dedup_cutoff and ts < dedup_cutoff:
                    continue
                q = p.get('query', '')
                if q:
                    covered_queries.add(q)
    except Exception:
        pass

# ── Scan recall_query events for qualifying misses ─────────────────────────────
new_incidents = []

if not os.path.isfile(events_source):
    sys.exit(0)

try:
    with open(events_source, 'r', encoding='utf-8', errors='replace') as f:
        for raw_line in f:
            line = raw_line.strip()
            if not line:
                continue
            try:
                ev = json.loads(line)
            except json.JSONDecodeError:
                # Malformed line — skip silently (fail-open)
                continue
            if ev.get('event_type') != 'recall_query':
                continue
            # Apply 1-day cutoff (skip older events; harness query already filters
            # but direct ndjson reads may include older events)
            ts = ev.get('ts', '')
            if cutoff and ts < cutoff:
                continue
            p = ev.get('payload', {})
            # Only qualifying: empty_for_known_topic must be exactly True
            if p.get('empty_for_known_topic') is not True:
                continue
            query = p.get('query', '')
            if not query:
                continue
            # Dedupe: skip if already covered by a prior incident
            if query in covered_queries:
                continue
            new_incidents.append(query)
            # Mark as covered so duplicate recall_query events in the same run don't
            # each produce an incident
            covered_queries.add(query)

except Exception:
    sys.exit(0)

# ── Emit incident events for each new miss ─────────────────────────────────────
if not new_incidents:
    sys.exit(0)

# Write to full_events file (append)
if not full_events or not os.path.isfile(os.path.dirname(full_events) + '/.') and False:
    sys.exit(0)

# Emit via stdout — caller will append via emit_event or direct append
for q in new_incidents:
    print(q)
PYEOF
}

# ── Main: gather misses, emit incidents ───────────────────────────────────────
# Purpose: orchestrate the scan/dedupe/emit pipeline.
# Gotchas: Uses two different paths depending on whether harness CLI is available.
#   In both cases, _process_events outputs one query-string per new miss to stdout.

# Determine the events file to scan for recall_query events
if [[ -n "${_EVENTS_TMP:-}" && -f "${_EVENTS_TMP:-}" ]]; then
  _scan_file="${_EVENTS_TMP}"
else
  # Direct ndjson scan (test mode or harness unavailable)
  _scan_file="${_FULL_EVENTS}"
fi

# Guard: if the events file doesn't exist, exit cleanly
if [[ ! -f "${_scan_file}" ]]; then
  [[ -n "${_EVENTS_TMP:-}" ]] && rm -f "${_EVENTS_TMP}" || true
  exit 0
fi

# Run the python processor — outputs one query per new miss, one per line
_new_misses="$(python3 - \
    "${_scan_file}" \
    "${_FULL_EVENTS}" \
    "${_CUTOFF:-}" \
    "${_DEDUP_CUTOFF:-}" <<'PYEOF' 2>/dev/null || true
import sys, json, os

events_source = sys.argv[1]
full_events   = sys.argv[2]
cutoff        = sys.argv[3]
dedup_cutoff  = sys.argv[4]

# Load existing recall-miss incidents for dedupe
covered_queries = set()
if os.path.isfile(full_events):
    try:
        with open(full_events, 'r', encoding='utf-8', errors='replace') as f:
            for raw_line in f:
                line = raw_line.strip()
                if not line:
                    continue
                try:
                    ev = json.loads(line)
                except json.JSONDecodeError:
                    continue
                if ev.get('event_type') != 'incident':
                    continue
                p = ev.get('payload', {})
                if p.get('class') != 'recall-miss':
                    continue
                ts = ev.get('ts', '')
                if dedup_cutoff and ts < dedup_cutoff:
                    continue
                q = p.get('query', '')
                if q:
                    covered_queries.add(q)
    except Exception:
        pass

# Scan recall_query events for qualifying misses
if not os.path.isfile(events_source):
    sys.exit(0)

try:
    with open(events_source, 'r', encoding='utf-8', errors='replace') as f:
        for raw_line in f:
            line = raw_line.strip()
            if not line:
                continue
            try:
                ev = json.loads(line)
            except json.JSONDecodeError:
                continue
            if ev.get('event_type') != 'recall_query':
                continue
            ts = ev.get('ts', '')
            if cutoff and ts < cutoff:
                continue
            p = ev.get('payload', {})
            if p.get('empty_for_known_topic') is not True:
                continue
            query = p.get('query', '')
            if not query:
                continue
            if query in covered_queries:
                continue
            covered_queries.add(query)
            print(query)
except Exception:
    pass
PYEOF
)"

# Clean up temp file from harness query
[[ -n "${_EVENTS_TMP:-}" ]] && rm -f "${_EVENTS_TMP}" || true

# Guard: nothing to do
if [[ -z "${_new_misses:-}" ]]; then
  exit 0
fi

# ── Emit one incident per new miss ────────────────────────────────────────────
# Purpose: append incident events to the spine via emit_event (if sourced) or
#   direct append fallback. jq --arg used exclusively — never interpolate into
#   jq filter body.
# Gotchas: emit_event is fail-open by design; direct append is the fallback path
#   for test mode where the full lib may not be sourced.

_emit_ts_now() {
  if command -v gdate >/dev/null 2>&1; then
    gdate -u +%Y-%m-%dT%H:%M:%S.%3NZ 2>/dev/null && return
  fi
  if command -v python3 >/dev/null 2>&1; then
    python3 -c "
from datetime import datetime, timezone
t = datetime.now(timezone.utc)
print(t.strftime('%Y-%m-%dT%H:%M:%S.') + f'{t.microsecond//1000:03d}Z')
" 2>/dev/null && return
  fi
  date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo "1970-01-01T00:00:00Z"
}

while IFS= read -r _query; do
  [[ -z "${_query:-}" ]] && continue

  # Build the incident payload using jq --arg (never interpolate into filter text)
  _detail="recall returned 0 hits for '${_query}' though journal FTS knows the topic"
  _payload="$(jq -cn \
    --arg severity "P2" \
    --arg cls "recall-miss" \
    --arg query "${_query}" \
    --arg detail "${_detail}" \
    '{severity:$severity, class:$cls, query:$query, detail:$detail}' \
    2>/dev/null)" || continue

  # In test mode use direct append (emit_event writes to real spine, not the sandbox).
  # In production use emit_event (fail-open, proper lock/schema).
  if [[ "${_RMM_TEST_MODE:-0}" -eq 1 ]]; then
    # Direct append to test sandbox events file
    _ts="$(_emit_ts_now)"
    _line="$(jq -cn \
      --arg ts "${_ts}" \
      --arg session_id "unknown" \
      --arg source "recall-miss-monitor.sh" \
      --arg project ".claude" \
      --argjson payload "${_payload}" \
      '{ts:$ts,schema:1,session_id:$session_id,event_type:"incident",source:$source,project:$project,payload:$payload,outcome:null}' \
      2>/dev/null)" || continue
    printf '%s\n' "${_line}" >> "${_WRITE_EVENTS}" 2>/dev/null || true
  elif declare -f emit_event >/dev/null 2>&1; then
    emit_event "incident" "${_payload}" \
      source="recall-miss-monitor.sh" outcome="open" || true
  else
    # Fallback: direct append to production spine (emit-event.sh not sourced)
    _ts="$(_emit_ts_now)"
    _line="$(jq -cn \
      --arg ts "${_ts}" \
      --arg session_id "unknown" \
      --arg source "recall-miss-monitor.sh" \
      --arg project ".claude" \
      --argjson payload "${_payload}" \
      '{ts:$ts,schema:1,session_id:$session_id,event_type:"incident",source:$source,project:$project,payload:$payload,outcome:null}' \
      2>/dev/null)" || continue
    printf '%s\n' "${_line}" >> "${_WRITE_EVENTS}" 2>/dev/null || true
  fi

done <<< "${_new_misses}"

exit 0
