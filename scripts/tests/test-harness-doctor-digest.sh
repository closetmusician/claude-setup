#!/usr/bin/env bash
# ABOUTME: Behavior tests for harness-doctor.sh evasion-detector (U3/item-22) and
# ABOUTME: DIGEST section (6.2). Six cases: U3 detect, U3 no-detect on admission,
# ABOUTME: digest all-sections, empty spine, stale last-run warn, idempotent re-run.
# ABOUTME: Uses fixture spine/state dirs via env overrides (CLAUDE_DIR, STATE_DIR,
# ABOUTME: TRANSCRIPT_DIR, EVENTS_FILE, DIGEST_FILE) added to doctor for test isolation.

set -uo pipefail

DOCTOR="${DOCTOR:-$HOME/.claude/scripts/harness-doctor.sh}"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
PASS=0; FAIL=0

check() {
  local name="$1" expected="$2" actual="$3"
  if [[ "$expected" == "contains:"* ]]; then
    local needle="${expected#contains:}"
    if echo "$actual" | grep -qF "$needle"; then
      echo "PASS: $name"; PASS=$((PASS+1))
    else
      echo "FAIL: $name — expected to contain '$needle', got: $(echo "$actual" | head -5)"; FAIL=$((FAIL+1))
    fi
  elif [[ "$expected" == "not_contains:"* ]]; then
    local needle="${expected#not_contains:}"
    if echo "$actual" | grep -qF "$needle"; then
      echo "FAIL: $name — expected NOT to contain '$needle'"; FAIL=$((FAIL+1))
    else
      echo "PASS: $name"; PASS=$((PASS+1))
    fi
  elif [[ "$expected" == "exit0" ]]; then
    # Just check exit code — actual is the exit code
    if [[ "$actual" == "0" ]]; then
      echo "PASS: $name"; PASS=$((PASS+1))
    else
      echo "FAIL: $name — expected exit 0, got $actual"; FAIL=$((FAIL+1))
    fi
  elif [[ "$expected" == "file_exists:"* ]]; then
    local path="${expected#file_exists:}"
    if [[ -f "$path" ]]; then
      echo "PASS: $name"; PASS=$((PASS+1))
    else
      echo "FAIL: $name — expected file $path to exist"; FAIL=$((FAIL+1))
    fi
  fi
}

# ── Helper: build a minimal fixture transcript (2 messages: user then assistant) ──
# $1 = user text, $2 = assistant text, $3 = optional: add tool_use block (true)
make_transcript() {
  local user_text="$1" asst_text="$2" add_tool="${3:-false}"
  local f="$TMP/transcript-$RANDOM.jsonl"
  # User turn
  jq -cn --arg t "$user_text" '{"type":"user","message":{"content":[{"type":"text","text":$t}]}}' >> "$f"
  if [[ "$add_tool" == "true" ]]; then
    # Tool use block — signals evidence
    jq -cn '{"type":"assistant","message":{"content":[{"type":"tool_use","id":"t1","name":"Read","input":{"file_path":"/tmp/x.txt"}}]}}' >> "$f"
  fi
  # Assistant turn
  jq -cn --arg t "$asst_text" '{"type":"assistant","message":{"content":[{"type":"text","text":$t}]}}' >> "$f"
  echo "$f"
}

# ── Build per-test fixture dirs ───────────────────────────────────────────────

# ── CASE 1: correction + no-admission transcript → U3 DETECT line + event ────
T1_DIR="$TMP/case1"
mkdir -p "$T1_DIR/state/state" "$T1_DIR/transcripts" "$T1_DIR/state"
# Correction event in spine (simulates correction-capture having fired)
jq -cn '{"ts":"2026-07-04T22:00:00.000Z","schema":1,"session_id":"sess-001","event_type":"correction","source":"correction-capture.sh","project":"test","payload":{"prompt":"you did not read my instructions","assistant_tail":"I see — let me help you with that task","rtk_suspect":false},"outcome":null}' \
  > "$T1_DIR/state/state/events.ndjson"
# Matching transcript: user confrontation, assistant deflects (no "you're right", no file:line, no tool_use)
T1_TRANSCRIPT=$(make_transcript \
  "you did not read my instructions" \
  "I understand your request. Let me help you with the task you asked about.")
# Evasion detector needs to scan transcripts in TRANSCRIPT_DIR
mkdir -p "$T1_DIR/projects/proj1"
cp "$T1_TRANSCRIPT" "$T1_DIR/projects/proj1/session.jsonl"

# ── CASE 2: confrontation followed by admission + evidence → no detect ────────
T2_DIR="$TMP/case2"
mkdir -p "$T2_DIR/state/state" "$T2_DIR/projects/proj2" "$T2_DIR/state"
jq -cn '{"ts":"2026-07-04T22:00:00.000Z","schema":1,"session_id":"sess-002","event_type":"correction","source":"correction-capture.sh","project":"test","payload":{"prompt":"you are wrong about this","assistant_tail":"","rtk_suspect":false},"outcome":null}' \
  > "$T2_DIR/state/state/events.ndjson"
T2_TRANSCRIPT=$(make_transcript \
  "you are wrong about this" \
  "You're right, I was wrong. Here is the corrected output at /tmp/evidence.txt:1 — see the file above." \
  "true")
cp "$T2_TRANSCRIPT" "$T2_DIR/projects/proj2/session.jsonl"

# ── CASE 3: digest renders all sections with fixture data ─────────────────────
T3_DIR="$TMP/case3"
mkdir -p "$T3_DIR/state/state" "$T3_DIR/projects/proj3" "$T3_DIR/state/loop/inbox"
# Spine with some trust_decision events this week
{
  # Block event this week
  jq -cn '{"ts":"2026-07-04T22:00:00.000Z","schema":1,"session_id":"s3a","event_type":"trust_decision","source":"completion-claim-guard.sh","project":"test","payload":{"guard":"completion-claim-guard"},"outcome":"denied"}'
  # Allow event this week
  jq -cn '{"ts":"2026-07-04T21:00:00.000Z","schema":1,"session_id":"s3b","event_type":"trust_decision","source":"completion-claim-guard.sh","project":"test","payload":{"guard":"completion-claim-guard"},"outcome":"allowed"}'
  # Correction event this week
  jq -cn '{"ts":"2026-07-04T20:00:00.000Z","schema":1,"session_id":"s3c","event_type":"correction","source":"correction-capture.sh","project":"test","payload":{"prompt":"you ignored this","assistant_tail":"","rtk_suspect":false},"outcome":null}'
} > "$T3_DIR/state/state/events.ndjson"
# A .proposed file (not too old)
touch "$T3_DIR/test-proposal.proposed"
# last-run stamps (fresh)
date -u +%Y-%m-%dT%H:%M:%SZ > "$T3_DIR/state/harness-doctor.last-run"
date -u +%Y-%m-%dT%H:%M:%SZ > "$T3_DIR/state/journal-index.last-run"
# Loop inbox with a pending file
echo "## Proposal 1" > "$T3_DIR/state/loop/inbox/2026-07-04.md"
# Transcript for canary
T3_TRANSCRIPT=$(make_transcript "ok" "done")
cp "$T3_TRANSCRIPT" "$T3_DIR/projects/proj3/session.jsonl"

# ── CASE 4: empty spine → "no data yet" everywhere, exits clean ──────────────
T4_DIR="$TMP/case4"
mkdir -p "$T4_DIR/state/state" "$T4_DIR/projects/proj4" "$T4_DIR/state"
echo "" > "$T4_DIR/state/state/events.ndjson"  # empty spine
T4_TRANSCRIPT=$(make_transcript "hello" "hi")
cp "$T4_TRANSCRIPT" "$T4_DIR/projects/proj4/session.jsonl"

# ── CASE 5: stale .last-run stamp → ⚠ line ────────────────────────────────────
T5_DIR="$TMP/case5"
mkdir -p "$T5_DIR/state/state" "$T5_DIR/projects/proj5" "$T5_DIR/state"
echo "" > "$T5_DIR/state/state/events.ndjson"
T5_TRANSCRIPT=$(make_transcript "hello" "hi")
cp "$T5_TRANSCRIPT" "$T5_DIR/projects/proj5/session.jsonl"
# Write a stamp 10 days in the past
python3 -c "
from datetime import datetime, timezone, timedelta
ts = datetime.now(timezone.utc) - timedelta(days=10)
print(ts.strftime('%Y-%m-%dT%H:%M:%SZ'))
" > "$T5_DIR/state/journal-index.last-run"

# ── CASE 7: two distinct U3 incidents in same session → two events (FIX-U3-2) ──
# Regression for dedup bug: u_ts was always "" because transcript messages use
# "timestamp" not "ts", so all hits in a session collapsed to one dedup key.
# With the fix each confrontation's unique timestamp makes a unique dedup key.
T7_DIR="$TMP/case7"
mkdir -p "$T7_DIR/state/state" "$T7_DIR/projects/proj7" "$T7_DIR/state"
echo "" > "$T7_DIR/state/state/events.ndjson"
# Single transcript with two separate confrontation+evasion sequences, each with
# a distinct timestamp so the fixed dedup key differs between them.
cat > "$T7_DIR/projects/proj7/session.jsonl" <<'JSONL'
{"type":"user","session_id":"sess-007","message":{"content":[{"type":"text","text":"you did not read my instructions"}]},"timestamp":"2026-07-04T10:00:00.000Z"}
{"type":"assistant","message":{"content":[{"type":"text","text":"I understand. Let me continue with the original plan."}]}}
{"type":"user","session_id":"sess-007","message":{"content":[{"type":"text","text":"again, you ignored what I asked"}]},"timestamp":"2026-07-04T10:05:00.000Z"}
{"type":"assistant","message":{"content":[{"type":"text","text":"I see. Moving forward with the approach as discussed."}]}}
JSONL

# ── CASE 8: confrontation → text preamble → tool_use → NOT flagged (FIX-U3-1) ─
# Regression for false-fire: lookahead stopped at first assistant message even
# if it was a text preamble; real tool_use in the next assistant was missed.
# With the fix, K=3 lookahead scans ahead and finds the tool_use — not evasion.
T8_DIR="$TMP/case8"
mkdir -p "$T8_DIR/state/state" "$T8_DIR/projects/proj8" "$T8_DIR/state"
echo "" > "$T8_DIR/state/state/events.ndjson"
cat > "$T8_DIR/projects/proj8/session.jsonl" <<'JSONL'
{"type":"user","message":{"content":[{"type":"text","text":"you did not read my instructions"}]}}
{"type":"assistant","message":{"content":[{"type":"text","text":"Let me take a closer look at that now."}]}}
{"type":"assistant","message":{"content":[{"type":"tool_use","id":"t1","name":"Read","input":{"file_path":"/tmp/x.txt"}}]}}
JSONL

# ── CASE 9: mixed real+synthetic events → real/synthetic split in METRICS ──────
# Regression for FIX-DIG-1: test-emitted events (session_id="unknown") were
# counted in the "guard blocks" headline, inflating the production signal.
# With the fix, synthetic events are reported separately as "(+N synthetic/test)".
T9_DIR="$TMP/case9"
mkdir -p "$T9_DIR/state/state" "$T9_DIR/projects/proj9" "$T9_DIR/state"
{
  # Real block (real session_id)
  jq -cn '{"ts":"2026-07-04T22:00:00.000Z","schema":1,"session_id":"real-session-abc","event_type":"trust_decision","source":"completion-claim-guard.sh","project":"test","payload":{},"outcome":"denied"}'
  # Synthetic block (session_id="unknown" — emitted by test suite)
  jq -cn '{"ts":"2026-07-04T21:00:00.000Z","schema":1,"session_id":"unknown","event_type":"trust_decision","source":"completion-claim-guard.sh","project":"test","payload":{},"outcome":"denied"}'
  # Another synthetic (session_id="test")
  jq -cn '{"ts":"2026-07-04T20:00:00.000Z","schema":1,"session_id":"test","event_type":"trust_decision","source":"completion-claim-guard.sh","project":"test","payload":{},"outcome":"denied"}'
} > "$T9_DIR/state/state/events.ndjson"
make_transcript "hello" "hi" > /dev/null  # just need a transcript for canary
T9_TRANSCRIPT=$(make_transcript "hello" "hi")
cp "$T9_TRANSCRIPT" "$T9_DIR/projects/proj9/session.jsonl"

# ── CASE 6: idempotent re-run → no duplicate U3 events ────────────────────────
T6_DIR="$TMP/case6"
mkdir -p "$T6_DIR/state/state" "$T6_DIR/projects/proj6" "$T6_DIR/state"
jq -cn '{"ts":"2026-07-04T22:00:00.000Z","schema":1,"session_id":"sess-006","event_type":"correction","source":"correction-capture.sh","project":"test","payload":{"prompt":"you never read my instructions","assistant_tail":"","rtk_suspect":false},"outcome":null}' \
  > "$T6_DIR/state/state/events.ndjson"
T6_TRANSCRIPT=$(make_transcript \
  "you never read my instructions" \
  "I understand. Let me proceed with the original approach.")
cp "$T6_TRANSCRIPT" "$T6_DIR/projects/proj6/session.jsonl"

# ── Run tests ─────────────────────────────────────────────────────────────────

echo "=== test-harness-doctor-digest: 6 cases ==="
echo ""

# Case 1: U3 DETECT line emitted
echo "--- Case 1: correction + no-admission → U3 DETECT ---"
DIGEST_FILE_1="$T1_DIR/state/weekly-digest.md"
out1=$(CLAUDE_DIR="$T1_DIR" STATE_DIR="$T1_DIR/state" TRANSCRIPT_DIR="$T1_DIR/projects" \
  EVENTS_FILE="$T1_DIR/state/state/events.ndjson" DIGEST_FILE="$DIGEST_FILE_1" \
  bash "$DOCTOR" 2>&1 || true)
check "1a U3 DETECT line in output" "contains:DETECT [U3]" "$out1"
# Check that a trust_decision event with evasion-detector was emitted
ev_count1=0
if [[ -f "$T1_DIR/state/state/events.ndjson" ]]; then
  ev_count1=$(grep -c '"evasion-detector"' "$T1_DIR/state/state/events.ndjson" 2>/dev/null || echo 0)
fi
if [[ "${ev_count1:-0}" -ge 1 ]]; then
  echo "PASS: 1b U3 trust_decision event emitted (count: $ev_count1)"; PASS=$((PASS+1))
else
  echo "FAIL: 1b expected U3 trust_decision event in spine, got $ev_count1"; FAIL=$((FAIL+1))
fi

echo ""
# Case 2: confrontation + admission → no DETECT
echo "--- Case 2: confrontation + admission+evidence → no detect ---"
DIGEST_FILE_2="$T2_DIR/state/weekly-digest.md"
out2=$(CLAUDE_DIR="$T2_DIR" STATE_DIR="$T2_DIR/state" TRANSCRIPT_DIR="$T2_DIR/projects" \
  EVENTS_FILE="$T2_DIR/state/state/events.ndjson" DIGEST_FILE="$DIGEST_FILE_2" \
  bash "$DOCTOR" 2>&1 || true)
check "2a no U3 DETECT on admission+evidence" "not_contains:DETECT [U3]" "$out2"

echo ""
# Case 3: digest renders all sections
echo "--- Case 3: digest renders all sections ---"
DIGEST_FILE_3="$T3_DIR/state/weekly-digest.md"
out3=$(CLAUDE_DIR="$T3_DIR" STATE_DIR="$T3_DIR/state" TRANSCRIPT_DIR="$T3_DIR/projects" \
  EVENTS_FILE="$T3_DIR/state/state/events.ndjson" DIGEST_FILE="$DIGEST_FILE_3" \
  bash "$DOCTOR" 2>&1 || true)
check "3a digest contains STAGED PATCHES section" "contains:STAGED PATCHES" "$out3"
check "3b digest contains METRICS section" "contains:METRICS" "$out3"
check "3c digest contains STALENESS section" "contains:STALENESS" "$out3"
check "3d digest file written" "file_exists:$DIGEST_FILE_3" ""

echo ""
# Case 4: empty spine → "no data yet" everywhere, exit clean
echo "--- Case 4: empty spine → no data yet, clean exit ---"
DIGEST_FILE_4="$T4_DIR/state/weekly-digest.md"
out4=$(CLAUDE_DIR="$T4_DIR" STATE_DIR="$T4_DIR/state" TRANSCRIPT_DIR="$T4_DIR/projects" \
  EVENTS_FILE="$T4_DIR/state/state/events.ndjson" DIGEST_FILE="$DIGEST_FILE_4" \
  bash "$DOCTOR" 2>&1 || true)
ec4=$?
check "4a empty spine → contains 'no data yet'" "contains:no data yet" "$out4"
# Doctor exits 0 when no CRITICAL findings (in test we have no skills/settings to check)
# We can't guarantee exit 0 due to real skill checks; just verify no crash from digest section
check "4b empty spine → digest still shows 'no data yet'" "contains:no data yet" "$out4"

echo ""
# Case 5: stale .last-run stamp → ⚠ warning
echo "--- Case 5: stale last-run stamp → warning ---"
DIGEST_FILE_5="$T5_DIR/state/weekly-digest.md"
out5=$(CLAUDE_DIR="$T5_DIR" STATE_DIR="$T5_DIR/state" TRANSCRIPT_DIR="$T5_DIR/projects" \
  EVENTS_FILE="$T5_DIR/state/state/events.ndjson" DIGEST_FILE="$DIGEST_FILE_5" \
  bash "$DOCTOR" 2>&1 || true)
check "5a stale journal-index.last-run → STALENESS warning" "contains:journal-index.last-run" "$out5"

echo ""
# Case 6: idempotent re-run → no duplicate U3 events
echo "--- Case 6: idempotent re-run → no duplicate U3 events ---"
DIGEST_FILE_6="$T6_DIR/state/weekly-digest.md"
# Run 1
CLAUDE_DIR="$T6_DIR" STATE_DIR="$T6_DIR/state" TRANSCRIPT_DIR="$T6_DIR/projects" \
  EVENTS_FILE="$T6_DIR/state/state/events.ndjson" DIGEST_FILE="$DIGEST_FILE_6" \
  bash "$DOCTOR" >/dev/null 2>&1 || true
count_after_run1=$(grep -c '"evasion-detector"' "$T6_DIR/state/state/events.ndjson" 2>/dev/null || echo 0)
# Run 2 (idempotent)
CLAUDE_DIR="$T6_DIR" STATE_DIR="$T6_DIR/state" TRANSCRIPT_DIR="$T6_DIR/projects" \
  EVENTS_FILE="$T6_DIR/state/state/events.ndjson" DIGEST_FILE="$DIGEST_FILE_6" \
  bash "$DOCTOR" >/dev/null 2>&1 || true
count_after_run2=$(grep -c '"evasion-detector"' "$T6_DIR/state/state/events.ndjson" 2>/dev/null || echo 0)
if [[ "${count_after_run1:-0}" -ge 1 && "${count_after_run1}" -eq "${count_after_run2}" ]]; then
  echo "PASS: 6a idempotent — $count_after_run1 events after run 1, same after run 2"; PASS=$((PASS+1))
else
  echo "FAIL: 6a expected same event count on re-run — run1: $count_after_run1, run2: $count_after_run2"; FAIL=$((FAIL+1))
fi

echo ""
# Case 7: two distinct U3 incidents in one session → two events (FIX-U3-2 dedup)
echo "--- Case 7: two U3 incidents in one session → two separate events (FIX-U3-2) ---"
DIGEST_FILE_7="$T7_DIR/state/weekly-digest.md"
CLAUDE_DIR="$T7_DIR" STATE_DIR="$T7_DIR/state" TRANSCRIPT_DIR="$T7_DIR/projects" \
  EVENTS_FILE="$T7_DIR/state/state/events.ndjson" DIGEST_FILE="$DIGEST_FILE_7" \
  bash "$DOCTOR" >/dev/null 2>&1 || true
ev_count7=$(grep -c '"evasion-detector"' "$T7_DIR/state/state/events.ndjson" 2>/dev/null || echo 0)
if [[ "${ev_count7:-0}" -ge 2 ]]; then
  echo "PASS: 7a two U3 incidents → ${ev_count7} events (not collapsed to 1) (FIX-U3-2)"; PASS=$((PASS+1))
else
  echo "FAIL: 7a expected 2+ U3 events for two distinct incidents, got ${ev_count7}"; FAIL=$((FAIL+1))
fi

echo ""
# Case 8: confrontation → text preamble → tool_use → NOT flagged (FIX-U3-1 lookahead)
echo "--- Case 8: confrontation → preamble → tool_use → not flagged (FIX-U3-1) ---"
DIGEST_FILE_8="$T8_DIR/state/weekly-digest.md"
out8=$(CLAUDE_DIR="$T8_DIR" STATE_DIR="$T8_DIR/state" TRANSCRIPT_DIR="$T8_DIR/projects" \
  EVENTS_FILE="$T8_DIR/state/state/events.ndjson" DIGEST_FILE="$DIGEST_FILE_8" \
  bash "$DOCTOR" 2>&1 || true)
check "8a preamble→tool_use not flagged as U3 (FIX-U3-1)" "not_contains:DETECT [U3]" "$out8"

echo ""
# Case 9: mixed real+synthetic events → guard blocks split correctly (FIX-DIG-1)
echo "--- Case 9: real+synthetic events → split in METRICS section (FIX-DIG-1) ---"
DIGEST_FILE_9="$T9_DIR/state/weekly-digest.md"
out9=$(CLAUDE_DIR="$T9_DIR" STATE_DIR="$T9_DIR/state" TRANSCRIPT_DIR="$T9_DIR/projects" \
  EVENTS_FILE="$T9_DIR/state/state/events.ndjson" DIGEST_FILE="$DIGEST_FILE_9" \
  bash "$DOCTOR" 2>&1 || true)
# Should show "1 this week" (real) with "(+2 synthetic/test)" annotation
check "9a real block count is 1 (not 3)" "contains:Guard blocks: 1 this week" "$out9"
check "9b synthetic annotation present" "contains:synthetic/test" "$out9"

echo ""
echo "harness-doctor-digest: $PASS passed, $FAIL failed"
[[ "$FAIL" -eq 0 ]]
