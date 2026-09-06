#!/usr/bin/env bash
# ABOUTME: 48-hour post-campaign burn-in scorer for the fable-qa-0706 harness upgrade.
# ABOUTME: On each run, appends a timestamped block to ~/.claude/state/burnin/report.md
# ABOUTME: scoring: (1) trust-incident rate delta, (2) retype rate delta, (3) 44-suite
# ABOUTME: health, (4) spine health delta, (5) kill-switch / QUOTA-ABORT / needs-user trips.
# ABOUTME: Stores byte-offset cursors so each run reports only the DELTA since last run.

set -uo pipefail
trap 'exit 0' EXIT   # fail-open: never let the scorer crash a cron job

# ── Paths ─────────────────────────────────────────────────────────────────────
CLAUDE_DIR="${CLAUDE_DIR:-$HOME/.claude}"
STATE_DIR="${CLAUDE_DIR}/state"
BURNIN_DIR="${STATE_DIR}/burnin"
REPORT_FILE="${BURNIN_DIR}/report.md"
CURSOR_FILE="${BURNIN_DIR}/cursor.json"
HARNESS="${HARNESS_BIN:-${CLAUDE_DIR}/bin/harness}"
SUITE_DIR="${CLAUDE_DIR}/scripts/tests"
EVENTS_NDJSON="${STATE_DIR}/state/events.ndjson"
CORRECTIONS_JSONL="${STATE_DIR}/corrections.jsonl"

# ── IMPORTANT: isolated governance state so suite runs never touch live state ─
# Reuses the F0 fix pattern: each suite run gets a fresh tmpdir for gov state.
# The outer HARNESS_GOV_STATE_DIR remains unset so the harness reads live events.
export BURNIN_SUITE_TMPDIR
BURNIN_SUITE_TMPDIR="$(mktemp -d)"
trap 'rm -rf "$BURNIN_SUITE_TMPDIR"; exit 0' EXIT

mkdir -p "$BURNIN_DIR"

NOW_TS="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
NOW_EPOCH="$(date -u +%s)"

# ── Load cursors (byte offsets from previous run) ─────────────────────────────
# Cursor JSON schema: {"events_bytes": N, "corrections_lines": N, "run_ts": "..."}
prev_events_bytes=0
prev_corrections_lines=0
prev_run_ts="never"
if [[ -f "$CURSOR_FILE" ]] && command -v jq >/dev/null 2>&1; then
  prev_events_bytes="$(jq -r '.events_bytes // 0' "$CURSOR_FILE" 2>/dev/null || echo 0)"
  prev_corrections_lines="$(jq -r '.corrections_lines // 0' "$CURSOR_FILE" 2>/dev/null || echo 0)"
  prev_run_ts="$(jq -r '.run_ts // "never"' "$CURSOR_FILE" 2>/dev/null || echo "never")"
fi
[[ "$prev_events_bytes" =~ ^[0-9]+$ ]] || prev_events_bytes=0
[[ "$prev_corrections_lines" =~ ^[0-9]+$ ]] || prev_corrections_lines=0

# ── Capture current cursor values BEFORE scoring ──────────────────────────────
cur_events_bytes=0
if [[ -f "$EVENTS_NDJSON" ]]; then
  cur_events_bytes="$(wc -c < "$EVENTS_NDJSON" | tr -d '[:space:]' || echo 0)"
fi
[[ "$cur_events_bytes" =~ ^[0-9]+$ ]] || cur_events_bytes=0

cur_corrections_lines=0
if [[ -f "$CORRECTIONS_JSONL" ]]; then
  cur_corrections_lines="$(wc -l < "$CORRECTIONS_JSONL" | tr -d '[:space:]' || echo 0)"
fi
[[ "$cur_corrections_lines" =~ ^[0-9]+$ ]] || cur_corrections_lines=0

# ── Compute since-window for harness CLI (fall back to 6h if no prior run) ────
since_arg="6h"
if [[ "$prev_run_ts" != "never" ]]; then
  since_arg="$prev_run_ts"
fi

# ── §1  Trust-incident rate (delta since last run) ────────────────────────────
score_trust() {
  local out=""
  if [[ ! -x "$HARNESS" ]]; then
    echo "  status: SKIP (harness binary not found at $HARNESS)"
    return
  fi
  # Get real incident count in the window
  local raw
  raw="$("$HARNESS" incidents --since "$since_arg" 2>&1 || true)"
  local real_count
  real_count="$(printf '%s\n' "$raw" | perl -ne '/Real incidents:\s*(\d+)/ and print $1' || echo "")"
  real_count="${real_count:-unknown}"
  # Extract first-line incident types for a compact sample
  local sample
  sample="$(printf '%s\n' "$raw" | perl -ne '/^\s{2}\S/ and print' | head -5 || true)"
  echo "  since: $since_arg"
  echo "  real_incidents_delta: $real_count"
  if [[ -n "$sample" ]]; then
    echo "  sample_incidents:"
    while IFS= read -r line; do
      echo "    $line"
    done <<< "$sample"
  else
    echo "  sample_incidents: none in window"
  fi
}

# ── §2  Retype rate (corrections.jsonl delta) ─────────────────────────────────
score_retype() {
  local delta=$(( cur_corrections_lines - prev_corrections_lines ))
  [[ "$delta" -lt 0 ]] && delta=0
  if [[ ! -f "$CORRECTIONS_JSONL" ]]; then
    echo "  status: no_data (corrections.jsonl absent — no corrections captured yet)"
    return
  fi
  echo "  corrections_total: $cur_corrections_lines"
  echo "  corrections_delta: $delta"
  if [[ "$delta" -gt 0 ]] && command -v jq >/dev/null 2>&1; then
    # Show a brief sample of new corrections (last $delta lines, up to 3)
    local sample_count=$(( delta < 3 ? delta : 3 ))
    echo "  recent_corrections (up to 3):"
    tail -"${sample_count}" "$CORRECTIONS_JSONL" 2>/dev/null | while IFS= read -r line; do
      local topic
      topic="$(printf '%s' "$line" | jq -r '.topic // .text // "?"' 2>/dev/null || echo "?")"
      echo "    - $topic"
    done || true
  else
    echo "  recent_corrections: none"
  fi
}

# ── §3  Suite health (44-suite loop under isolated HARNESS_GOV_STATE_DIR) ──────
score_suite_health() {
  local green=0 red=0 red_names="" suite_tmpdir
  suite_tmpdir="$(mktemp -d "${BURNIN_SUITE_TMPDIR}/suite-XXXX")"

  for suite in "$SUITE_DIR"/test-*.sh; do
    [[ -f "$suite" ]] || continue
    local name
    name="$(basename "$suite")"
    local ec=0
    # Each suite runs with its own isolated gov state dir
    local gov_tmp
    gov_tmp="$(mktemp -d "${suite_tmpdir}/gov-XXXX")"
    out="$(HARNESS_GOV_STATE_DIR="$gov_tmp" bash "$suite" 2>&1)" || ec=$?
    local fail_count
    fail_count="$(printf '%s\n' "$out" | perl -ne '/^FAIL:/ and $n++; END{print $n//0}' || echo 0)"
    [[ "$fail_count" =~ ^[0-9]+$ ]] || fail_count=0
    if [[ "$ec" -ne 0 ]] || [[ "$fail_count" -gt 0 ]]; then
      red=$(( red + 1 ))
      red_names="${red_names}${red_names:+, }${name}"
    else
      green=$(( green + 1 ))
    fi
    rm -rf "$gov_tmp"
  done

  local total=$(( green + red ))
  echo "  total_suites: $total"
  echo "  green: $green"
  echo "  red: $red"
  if [[ "$red" -gt 0 ]]; then
    echo "  red_suites: $red_names"
    echo "  verdict: DEGRADED"
  else
    echo "  verdict: ALL_GREEN"
  fi
}

# ── §4  Spine health (new event count + malformed lines in delta) ─────────────
score_spine() {
  local bytes_delta=$(( cur_events_bytes - prev_events_bytes ))
  [[ "$bytes_delta" -lt 0 ]] && bytes_delta=0
  echo "  spine_file: $EVENTS_NDJSON"
  echo "  bytes_total: $cur_events_bytes"
  echo "  bytes_delta: $bytes_delta"

  if [[ ! -f "$EVENTS_NDJSON" ]]; then
    echo "  status: MISSING — spine file absent"
    return
  fi

  # Count new lines by reading from prev byte offset; count malformed JSON
  # Use python3 for reliable byte-offset seek (no RTK/grep parsing)
  local spine_stats
  spine_stats="$(python3 - "$EVENTS_NDJSON" "$prev_events_bytes" <<'PYEOF' 2>/dev/null || echo "new_lines=0 malformed=0"
import sys, json
path = sys.argv[1]
offset = int(sys.argv[2]) if len(sys.argv) > 2 else 0
new_lines = 0; malformed = 0
try:
    with open(path, 'rb') as f:
        f.seek(offset)
        for raw in f:
            line = raw.strip()
            if not line:
                continue
            new_lines += 1
            try:
                json.loads(line)
            except Exception:
                malformed += 1
except Exception as e:
    print(f"new_lines=0 malformed=0 error={e}")
    sys.exit(0)
print(f"new_lines={new_lines} malformed={malformed}")
PYEOF
)"
  local new_lines malformed
  new_lines="$(printf '%s' "$spine_stats" | perl -ne '/new_lines=(\d+)/ and print $1' || echo 0)"
  malformed="$(printf '%s' "$spine_stats" | perl -ne '/malformed=(\d+)/ and print $1' || echo 0)"
  echo "  new_events_delta: ${new_lines:-0}"
  echo "  malformed_lines_delta: ${malformed:-0}"
  if [[ "${malformed:-0}" -gt 0 ]]; then
    echo "  verdict: WARN_MALFORMED"
  else
    echo "  verdict: HEALTHY"
  fi
}

# ── §5  Safety signals (kill-switch / QUOTA-ABORT / needs-user) ───────────────
score_safety() {
  # Kill-switch / autonomous freeze files
  local freeze_active="false"
  [[ -f "${STATE_DIR}/.AUTONOMOUS_FREEZE" ]] && freeze_active="true"
  [[ -f "${STATE_DIR}/.kill-switch" ]] && freeze_active="true"
  echo "  autonomous_freeze_active: $freeze_active"

  # QUOTA-ABORT / needs-user events in the spine
  if [[ ! -x "$HARNESS" ]]; then
    echo "  quota_abort_events: unknown (harness missing)"
    echo "  needs_user_events: unknown (harness missing)"
    return
  fi

  local qa_count nu_count
  # Use harness query with jq to filter; count lines
  qa_count="$("$HARNESS" query --since "$since_arg" --type quota_abort --limit 1000 2>&1 | perl -ne '/^\{/ and $n++; END{print $n//0}' || echo 0)"
  nu_count="$("$HARNESS" query --since "$since_arg" --type needs-user --limit 1000 2>&1 | perl -ne '/^\{/ and $n++; END{print $n//0}' || echo 0)"

  # Also scan spine delta directly for any kill-switch or QUOTA-ABORT text
  local raw_hits=""
  if [[ -f "$EVENTS_NDJSON" ]] && command -v python3 >/dev/null 2>&1; then
    raw_hits="$(python3 - "$EVENTS_NDJSON" "$prev_events_bytes" <<'PYEOF' 2>/dev/null || echo ""
import sys, json
path = sys.argv[1]
offset = int(sys.argv[2]) if len(sys.argv) > 2 else 0
hits = []
try:
    with open(path, 'rb') as f:
        f.seek(offset)
        for raw in f:
            raw = raw.strip()
            if not raw:
                continue
            try:
                obj = json.loads(raw)
                et = obj.get('event_type', '')
                p = str(obj.get('payload', {}))
                if any(k in et.lower() or k in p.lower()
                       for k in ('quota', 'kill_switch', 'freeze', 'needs_user', 'budget_abort')):
                    ts = obj.get('ts', '')
                    hits.append(f"{ts} {et}")
            except Exception:
                pass
except Exception:
    pass
for h in hits[:5]:
    print(h)
PYEOF
)"
  fi

  echo "  quota_abort_events_delta: ${qa_count:-0}"
  echo "  needs_user_events_delta: ${nu_count:-0}"
  if [[ -n "$raw_hits" ]]; then
    echo "  safety_signal_hits:"
    while IFS= read -r line; do
      echo "    - $line"
    done <<< "$raw_hits"
  else
    echo "  safety_signal_hits: none"
  fi
  if [[ "$freeze_active" == "true" ]]; then
    echo "  verdict: FROZEN"
  else
    echo "  verdict: NOMINAL"
  fi
}

# ── Build the report block ─────────────────────────────────────────────────────
{
  echo ""
  echo "## Burn-in check — $NOW_TS"
  echo "<!-- 48h burn-in for fable-qa-0706. Unload after 2026-07-08T00:00:00Z: launchctl unload ~/Library/LaunchAgents/com.yklin.burnin.plist -->"
  echo "previous_run: $prev_run_ts"
  echo ""
  echo "### §1 Trust-incident rate"
  score_trust
  echo ""
  echo "### §2 Retype rate (corrections.jsonl)"
  score_retype
  echo ""
  echo "### §3 Suite health (44 suites)"
  score_suite_health
  echo ""
  echo "### §4 Spine health"
  score_spine
  echo ""
  echo "### §5 Safety signals"
  score_safety
  echo ""
  echo "---"
} >> "$REPORT_FILE"

# ── Write updated cursors ──────────────────────────────────────────────────────
if command -v jq >/dev/null 2>&1; then
  jq -cn \
    --arg ts "$NOW_TS" \
    --argjson eb "$cur_events_bytes" \
    --argjson cl "$cur_corrections_lines" \
    '{"run_ts":$ts,"events_bytes":$eb,"corrections_lines":$cl}' \
    > "$CURSOR_FILE"
else
  printf '{"run_ts":"%s","events_bytes":%d,"corrections_lines":%d}\n' \
    "$NOW_TS" "$cur_events_bytes" "$cur_corrections_lines" > "$CURSOR_FILE"
fi

# Stamp last-run file (matching other com.yklin.* patterns)
date -u +%Y-%m-%dT%H:%M:%SZ > "${STATE_DIR}/com.yklin.burnin.last-run"

echo "burnin-score: block appended to $REPORT_FILE"
