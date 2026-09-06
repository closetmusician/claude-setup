#!/usr/bin/env bash
# ABOUTME: TDD test suite for scripts/correction-capture.sh (UserPromptSubmit hook, Phase 5.1).
# ABOUTME: Covers: ≥10 correction fixtures (event emitted with all payload fields + rtk_suspect),
# ABOUTME: ≥10 benign prompts not logged, legacy .user_prompt fallback, malformed stdin, timing.
# ABOUTME: Uses $EVENTS override so tests are fully isolated — no writes to real state.
# ABOUTME: Run: bash scripts/tests/test-correction-capture.sh — all cases must be GREEN.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="${SCRIPT_DIR}/../correction-capture.sh"

# ── Isolated temp state dir ───────────────────────────────────────────────────
TMP="$(mktemp -d /tmp/test-correction-capture-XXXXXX)"
trap 'rm -rf "$TMP"' EXIT

EVENTS_FILE="$TMP/state/events.ndjson"
mkdir -p "$TMP/state"
export STATE="$TMP"
export EVENTS="$EVENTS_FILE"

PASS=0
FAIL=0

_pass() { echo "  PASS: $1"; (( PASS++ )) || true; }
_fail() { echo "  FAIL: $1 — $2"; (( FAIL++ )) || true; }

_reset_events() {
  rm -f "$EVENTS_FILE" 2>/dev/null || true
  rm -rf "$TMP/state/.events.lock.d" 2>/dev/null || true
}

_event_count() {
  [ -f "$EVENTS_FILE" ] && grep -c '"event_type":"correction"' "$EVENTS_FILE" 2>/dev/null || echo 0
}

_run() {
  # $1: JSON string to pipe to hook
  printf '%s' "$1" | bash "$HOOK" 2>/dev/null
}

# Make a minimal transcript with a fake assistant tail text
_make_transcript() {
  local tail_text="${1:-}"
  local f="$TMP/transcript-$RANDOM.jsonl"
  printf '{"type":"user","message":{"content":"hello"}}\n' > "$f"
  if [ -n "$tail_text" ]; then
    # Write assistant message in the NDJSON format the hook expects
    printf '{"type":"assistant","message":{"content":[{"type":"text","text":"%s"}]}}\n' \
      "$(printf '%s' "$tail_text" | sed 's/"/\\"/g')" >> "$f"
  fi
  echo "$f"
}

echo "=== test-correction-capture.sh ==="
echo "HOOK=$HOOK"
echo "EVENTS=$EVENTS_FILE"
echo ""

# ─────────────────────────────────────────────────────────────────────────────
# CORRECTION FIXTURES — must emit one event each with all payload fields
# ─────────────────────────────────────────────────────────────────────────────
echo "[GROUP A] Correction fixtures (≥10, must emit correction events)"

# Helper: assert one correction event was emitted for a prompt
_assert_correction() {
  local case_name="$1"
  local json_input="$2"
  _reset_events
  _run "$json_input" >/dev/null
  local cnt
  cnt=$(_event_count)
  if [ "$cnt" -eq 1 ]; then
    # Verify all required payload fields are present in the event
    local ev
    ev=$(cat "$EVENTS_FILE" 2>/dev/null || true)
    local ok=1
    # Fields: session, cwd, prompt, assistant_tail, rtk_suspect
    for field in '"session"' '"cwd"' '"prompt"' '"assistant_tail"' '"rtk_suspect"'; do
      if ! printf '%s' "$ev" | grep -q "$field"; then
        ok=0
        break
      fi
    done
    if [ "$ok" -eq 1 ]; then
      _pass "$case_name"
    else
      _fail "$case_name" "event emitted but missing required payload fields: $ev"
    fi
  else
    _fail "$case_name" "expected 1 correction event, got $cnt"
  fi
}

TR=$(_make_transcript "I ran the tests and everything is fine.")

# C-1: "no, you didn't run the tests"
_assert_correction "C-1 no+comma" \
  "{\"prompt\":\"no, you didn't run the tests at all\",\"session_id\":\"s1\",\"transcript_path\":\"$TR\",\"cwd\":\"/tmp\"}"

# C-2: "No! you forgot the imports"
_assert_correction "C-2 no+excl" \
  "{\"prompt\":\"No! you forgot the imports\",\"session_id\":\"s2\",\"transcript_path\":\"$TR\",\"cwd\":\"/tmp\"}"

# C-3: "I already said to use TypeScript"
_assert_correction "C-3 i already said" \
  "{\"prompt\":\"I already said to use TypeScript not JavaScript\",\"session_id\":\"s3\",\"transcript_path\":\"$TR\",\"cwd\":\"/tmp\"}"

# C-4: "you didn't follow the instructions"
_assert_correction "C-4 you didnt" \
  "{\"prompt\":\"you didn't follow the instructions I gave\",\"session_id\":\"s4\",\"transcript_path\":\"$TR\",\"cwd\":\"/tmp\"}"

# C-5: "that's not true"
_assert_correction "C-5 thats not true" \
  "{\"prompt\":\"that's not true, the file does exist\",\"session_id\":\"s5\",\"transcript_path\":\"$TR\",\"cwd\":\"/tmp\"}"

# C-6: "show me the proof"
_assert_correction "C-6 show me the proof" \
  "{\"prompt\":\"show me the proof that it actually ran\",\"session_id\":\"s6\",\"transcript_path\":\"$TR\",\"cwd\":\"/tmp\"}"

# C-7: "why did you ignore my request"
_assert_correction "C-7 why did you ignore" \
  "{\"prompt\":\"why did you ignore my request to add tests?\",\"session_id\":\"s7\",\"transcript_path\":\"$TR\",\"cwd\":\"/tmp\"}"

# C-8: "read the instructions"
_assert_correction "C-8 read the instructions" \
  "{\"prompt\":\"read the instructions more carefully next time\",\"session_id\":\"s8\",\"transcript_path\":\"$TR\",\"cwd\":\"/tmp\"}"

# C-9: "not what i asked"
_assert_correction "C-9 not what i asked" \
  "{\"prompt\":\"not what i asked — I wanted the tests to pass first\",\"session_id\":\"s9\",\"transcript_path\":\"$TR\",\"cwd\":\"/tmp\"}"

# C-10: "wrong." at start
_assert_correction "C-10 wrong dot" \
  "{\"prompt\":\"wrong. please revert that change\",\"session_id\":\"s10\",\"transcript_path\":\"$TR\",\"cwd\":\"/tmp\"}"

# C-11: "again," at start
_assert_correction "C-11 again comma" \
  "{\"prompt\":\"again, you skipped the linting step\",\"session_id\":\"s11\",\"transcript_path\":\"$TR\",\"cwd\":\"/tmp\"}"

# C-12: "you never mentioned that"
_assert_correction "C-12 you never" \
  "{\"prompt\":\"you never said that the hook was already wired\",\"session_id\":\"s12\",\"transcript_path\":\"$TR\",\"cwd\":\"/tmp\"}"

echo ""

# ─────────────────────────────────────────────────────────────────────────────
# RTK SUSPECT — prompt matching rtk|reformat|mangl → rtk_suspect:true
# ─────────────────────────────────────────────────────────────────────────────
echo "[GROUP B] rtk_suspect field correctness"

# B-1: rtk_suspect:true when prompt mentions rtk
_reset_events
_run "{\"prompt\":\"no, the rtk command mangled the output\",\"session_id\":\"srtk1\",\"transcript_path\":\"$TR\",\"cwd\":\"/tmp\"}" >/dev/null
if [ -f "$EVENTS_FILE" ] && grep -q '"rtk_suspect":true' "$EVENTS_FILE" 2>/dev/null; then
  _pass "B-1 rtk_suspect true when rtk mentioned"
else
  _fail "B-1 rtk_suspect true when rtk mentioned" "got: $(cat "$EVENTS_FILE" 2>/dev/null || echo '<nothing>')"
fi

# B-2: rtk_suspect:false when prompt does not mention rtk/reformat/mangl
_reset_events
_run "{\"prompt\":\"wrong. you missed the semicolon\",\"session_id\":\"srtk2\",\"transcript_path\":\"$TR\",\"cwd\":\"/tmp\"}" >/dev/null
if [ -f "$EVENTS_FILE" ] && grep -q '"rtk_suspect":false' "$EVENTS_FILE" 2>/dev/null; then
  _pass "B-2 rtk_suspect false when no rtk reference"
else
  _fail "B-2 rtk_suspect false when no rtk reference" "got: $(cat "$EVENTS_FILE" 2>/dev/null || echo '<nothing>')"
fi

# B-3: rtk_suspect:true when prompt mentions reformat
_reset_events
_run "{\"prompt\":\"no, the reformat step broke the output\",\"session_id\":\"srtk3\",\"transcript_path\":\"$TR\",\"cwd\":\"/tmp\"}" >/dev/null
if [ -f "$EVENTS_FILE" ] && grep -q '"rtk_suspect":true' "$EVENTS_FILE" 2>/dev/null; then
  _pass "B-3 rtk_suspect true for reformat"
else
  _fail "B-3 rtk_suspect true for reformat" "got: $(cat "$EVENTS_FILE" 2>/dev/null || echo '<nothing>')"
fi

echo ""

# ─────────────────────────────────────────────────────────────────────────────
# BENIGN PROMPTS — must NOT emit any event
# ─────────────────────────────────────────────────────────────────────────────
echo "[GROUP C] Benign prompts (≥10, must NOT emit events)"

_assert_no_event() {
  local case_name="$1"
  local json_input="$2"
  _reset_events
  _run "$json_input" >/dev/null
  local cnt
  cnt=$(_event_count)
  if [ "$cnt" -eq 0 ]; then
    _pass "$case_name"
  else
    _fail "$case_name" "expected 0 events, got $cnt — $(cat "$EVENTS_FILE" 2>/dev/null | head -1 || true)"
  fi
}

# N-1: slash command — skip
_assert_no_event "N-1 slash command /review" \
  "{\"prompt\":\"/review this PR\",\"session_id\":\"n1\",\"transcript_path\":\"$TR\",\"cwd\":\"/tmp\"}"

# N-2: another slash command
_assert_no_event "N-2 slash command /help" \
  "{\"prompt\":\"/help\",\"session_id\":\"n2\",\"transcript_path\":\"$TR\",\"cwd\":\"/tmp\"}"

# N-3: positive feedback "you did great"
_assert_no_event "N-3 positive feedback" \
  "{\"prompt\":\"you did great work on this feature\",\"session_id\":\"n3\",\"transcript_path\":\"$TR\",\"cwd\":\"/tmp\"}"

# N-4: "no worries" — starts with no but is NOT a correction
_assert_no_event "N-4 no worries benign" \
  "{\"prompt\":\"no worries, take your time\",\"session_id\":\"n4\",\"transcript_path\":\"$TR\",\"cwd\":\"/tmp\"}"

# N-5: short prompt <10 chars
_assert_no_event "N-5 short prompt 9 chars" \
  "{\"prompt\":\"hi there!\",\"session_id\":\"n5\",\"transcript_path\":\"$TR\",\"cwd\":\"/tmp\"}"

# N-6: very short prompt "ok"
_assert_no_event "N-6 very short ok" \
  "{\"prompt\":\"ok\",\"session_id\":\"n6\",\"transcript_path\":\"$TR\",\"cwd\":\"/tmp\"}"

# N-7: normal question that doesn't match regex
_assert_no_event "N-7 normal question" \
  "{\"prompt\":\"can you help me refactor this function?\",\"session_id\":\"n7\",\"transcript_path\":\"$TR\",\"cwd\":\"/tmp\"}"

# N-8: thanks message
_assert_no_event "N-8 thanks message" \
  "{\"prompt\":\"thanks, that looks great to me!\",\"session_id\":\"n8\",\"transcript_path\":\"$TR\",\"cwd\":\"/tmp\"}"

# N-9: "no" embedded mid-sentence (not at start, not matching regex)
_assert_no_event "N-9 no mid-sentence" \
  "{\"prompt\":\"there is no need to add more tests here\",\"session_id\":\"n9\",\"transcript_path\":\"$TR\",\"cwd\":\"/tmp\"}"

# N-10: starts with "nobody" — not a correction trigger
_assert_no_event "N-10 nobody not trigger" \
  "{\"prompt\":\"nobody expected that edge case\",\"session_id\":\"n10\",\"transcript_path\":\"$TR\",\"cwd\":\"/tmp\"}"

# N-11: starts with "nope " — does NOT match ^no[,.! ]
_assert_no_event "N-11 nope not trigger" \
  "{\"prompt\":\"nope that is wrong let me clarify\",\"session_id\":\"n11\",\"transcript_path\":\"$TR\",\"cwd\":\"/tmp\"}"

# N-12: "did you enjoy that film?" — 'did you' but not 'did you actually|really|even'
_assert_no_event "N-12 did you enjoy benign" \
  "{\"prompt\":\"did you enjoy that film recommendation?\",\"session_id\":\"n12\",\"transcript_path\":\"$TR\",\"cwd\":\"/tmp\"}"

echo ""

# ─────────────────────────────────────────────────────────────────────────────
# LEGACY FALLBACK — .user_prompt field (backward compat)
# ─────────────────────────────────────────────────────────────────────────────
echo "[GROUP D] Legacy .user_prompt fallback"

_reset_events
_run "{\"user_prompt\":\"wrong. you used the wrong branch\",\"session_id\":\"leg1\",\"transcript_path\":\"$TR\",\"cwd\":\"/tmp\"}" >/dev/null
cnt=$(_event_count)
if [ "$cnt" -eq 1 ]; then
  _pass "D-1 .user_prompt legacy fallback triggers correction"
else
  _fail "D-1 .user_prompt legacy fallback triggers correction" "expected 1 event, got $cnt"
fi

echo ""

# ─────────────────────────────────────────────────────────────────────────────
# MALFORMED STDIN — exit 0, nothing logged
# ─────────────────────────────────────────────────────────────────────────────
echo "[GROUP E] Malformed/edge-case stdin"

# E-1: empty stdin
_reset_events
printf '' | bash "$HOOK" 2>/dev/null
cnt=$(_event_count)
if [ "$cnt" -eq 0 ]; then
  _pass "E-1 empty stdin → exit 0 nothing logged"
else
  _fail "E-1 empty stdin → exit 0 nothing logged" "got $cnt events"
fi

# E-2: garbage non-JSON
_reset_events
printf 'not json at all' | bash "$HOOK" 2>/dev/null
cnt=$(_event_count)
if [ "$cnt" -eq 0 ]; then
  _pass "E-2 garbage stdin → exit 0 nothing logged"
else
  _fail "E-2 garbage stdin → exit 0 nothing logged" "got $cnt events"
fi

# E-3: JSON but no prompt field
_reset_events
printf '{"session_id":"x","cwd":"/tmp"}' | bash "$HOOK" 2>/dev/null
cnt=$(_event_count)
if [ "$cnt" -eq 0 ]; then
  _pass "E-3 JSON no prompt field → exit 0 nothing logged"
else
  _fail "E-3 JSON no prompt field → exit 0 nothing logged" "got $cnt events"
fi

# E-4: exit code must be 0 even on malformed stdin
_reset_events
EXIT_CODE=0
printf 'garbage{{}' | bash "$HOOK" 2>/dev/null || EXIT_CODE=$?
if [ "$EXIT_CODE" -eq 0 ]; then
  _pass "E-4 exit code 0 on malformed stdin"
else
  _fail "E-4 exit code 0 on malformed stdin" "got exit $EXIT_CODE"
fi

echo ""

# ─────────────────────────────────────────────────────────────────────────────
# STDOUT SILENCE — hook must emit NOTHING to stdout (decisions live in events)
# ─────────────────────────────────────────────────────────────────────────────
echo "[GROUP F] Stdout silence"

_reset_events
STDOUT_OUT=$(_run "{\"prompt\":\"no, you didn't follow my instructions at all\",\"session_id\":\"st1\",\"transcript_path\":\"$TR\",\"cwd\":\"/tmp\"}")
if [ -z "$STDOUT_OUT" ]; then
  _pass "F-1 no stdout on correction match"
else
  _fail "F-1 no stdout on correction match" "got stdout: $STDOUT_OUT"
fi

_reset_events
STDOUT_OUT=$(_run "{\"prompt\":\"this is a normal benign question about coding\",\"session_id\":\"st2\",\"transcript_path\":\"$TR\",\"cwd\":\"/tmp\"}")
if [ -z "$STDOUT_OUT" ]; then
  _pass "F-2 no stdout on benign prompt"
else
  _fail "F-2 no stdout on benign prompt" "got stdout: $STDOUT_OUT"
fi

echo ""

# ─────────────────────────────────────────────────────────────────────────────
# TIMING — 20 invocations must complete in <2s
# ─────────────────────────────────────────────────────────────────────────────
echo "[GROUP G] Timing (20 invocations <2s)"

_reset_events
TIMING_TR=$(_make_transcript "all tests pass")
TIMING_INPUT="{\"prompt\":\"wrong. you skipped the linting\",\"session_id\":\"t1\",\"transcript_path\":\"$TIMING_TR\",\"cwd\":\"/tmp\"}"

# Use ms-precision timing via gdate (GNU coreutils, present on this host per emit-event.sh Q2 chain).
# Fall back to python3 for ms, and then to date +%s for second-level.
# Purpose: measure 20 invocations and assert <2000ms total.
_ms_now() {
  if command -v gdate >/dev/null 2>&1; then
    gdate +%s%3N 2>/dev/null && return
  fi
  if command -v python3 >/dev/null 2>&1; then
    python3 -c "import time; print(int(time.time()*1000))" 2>/dev/null && return
  fi
  # Second fallback — multiply by 1000 so comparisons still work (just 1s precision)
  echo "$(( $(date +%s) * 1000 ))"
}

START_MS=$(_ms_now)
for i in $(seq 1 20); do
  _run "$TIMING_INPUT" >/dev/null
done
END_MS=$(_ms_now)
ELAPSED_MS=$(( END_MS - START_MS ))

if [ "$ELAPSED_MS" -lt 2000 ]; then
  _pass "G-1 20 invocations in ${ELAPSED_MS}ms (<2000ms)"
else
  _fail "G-1 20 invocations in ${ELAPSED_MS}ms (<2000ms)" "too slow: ${ELAPSED_MS}ms"
fi

echo ""

# ─────────────────────────────────────────────────────────────────────────────
# P1-PERF: 1MB prompt completes <150ms AND detects correction in first 2000 chars
# ─────────────────────────────────────────────────────────────────────────────
echo "[GROUP H] P1-PERF: 1MB prompt truncation + performance"

# H-1: a 1MB prompt with correction phrase in the first 2000 chars must complete <150ms
#       AND emit a correction event (phrase detected despite the oversized payload).
_reset_events
# Build a 1MB JSON payload: correction phrase near start, then padding
HUGE_PROMPT="$(python3 -c "
import json, sys
prefix = 'you did not read the instructions '
# fill remainder so total prompt is ~1MB
filler = 'A' * (1024*1024 - len(prefix))
print(json.dumps({'session_id':'sHuge','prompt': prefix + filler}))
")"

START_MS=$(_ms_now)
printf '%s' "$HUGE_PROMPT" | bash "$HOOK" 2>/dev/null
END_MS=$(_ms_now)
ELAPSED_MS=$(( END_MS - START_MS ))

# Assert timing <150ms
if [ "$ELAPSED_MS" -lt 150 ]; then
  _pass "H-1a 1MB prompt completes in ${ELAPSED_MS}ms (<150ms)"
else
  _fail "H-1a 1MB prompt completes <150ms" "took ${ELAPSED_MS}ms"
fi

# Assert correction was still detected (phrase was in first 2000 chars)
cnt=$(_event_count)
if [ "$cnt" -ge 1 ]; then
  _pass "H-1b 1MB prompt: correction phrase (in first 2000 chars) still detected"
else
  _fail "H-1b 1MB prompt: correction phrase (in first 2000 chars) still detected" "no event emitted; event count=$cnt"
fi

echo ""

# ─────────────────────────────────────────────────────────────────────────────
# P2-FIELD-PRIORITY: .prompt takes priority over .user_prompt; fallback works correctly
# ─────────────────────────────────────────────────────────────────────────────
echo "[GROUP I] P2-FIELD-PRIORITY: .prompt vs .user_prompt disambiguation"

# I-1: payload with BOTH .prompt (correction) and .user_prompt (benign) → uses .prompt
#      → should emit a correction event (correction is in .prompt)
_reset_events
_run '{"prompt":"you did not read the instructions","user_prompt":"hello there no correction","session_id":"pi1","cwd":"/tmp"}' >/dev/null
cnt=$(_event_count)
if [ "$cnt" -eq 1 ]; then
  _pass "I-1 both keys present → uses .prompt (correction detected)"
else
  _fail "I-1 both keys present → uses .prompt (correction detected)" "expected 1 event, got $cnt"
fi

# I-2: payload with BOTH .prompt (benign) and .user_prompt (correction) → uses .prompt
#      → should NOT emit a correction event (.user_prompt must be ignored when .prompt exists)
_reset_events
_run '{"prompt":"this looks great, nice work","user_prompt":"you did not read the instructions","session_id":"pi2","cwd":"/tmp"}' >/dev/null
cnt=$(_event_count)
if [ "$cnt" -eq 0 ]; then
  _pass "I-2 both keys present: benign .prompt + correction .user_prompt → .user_prompt ignored, no event"
else
  _fail "I-2 both keys present: benign .prompt + correction .user_prompt → .user_prompt ignored" "expected 0 events, got $cnt"
fi

# I-3: payload with ONLY .user_prompt (correction, no .prompt key) → fallback uses .user_prompt
#      → should emit a correction event (legacy fallback still works)
_reset_events
_run '{"user_prompt":"you did not read the instructions","session_id":"pi3","cwd":"/tmp"}' >/dev/null
cnt=$(_event_count)
if [ "$cnt" -eq 1 ]; then
  _pass "I-3 only .user_prompt present → fallback uses it, correction detected"
else
  _fail "I-3 only .user_prompt present → fallback uses it, correction detected" "expected 1 event, got $cnt"
fi

echo ""

# ─────────────────────────────────────────────────────────────────────────────
# SUMMARY
# ─────────────────────────────────────────────────────────────────────────────
echo "=== SUMMARY ==="
echo "${PASS} passed, ${FAIL} failed"
if [ "$FAIL" -gt 0 ]; then
  exit 1
fi
exit 0
