#!/usr/bin/env bash
# ABOUTME: TDD test suite for analysis-reflex Stop hook and reflex-runner consumer.
# ABOUTME: Covers: claim+cite enqueues job, no-cite no job, non-synthesis no job, malformed
# ABOUTME: stdin, CONCUR/DIVERGE verdicts, timeout escalation, empty queue, bad JSON skip,
# ABOUTME: missing transcript fail-open, stop_hook_active re-enqueue guard.
# ABOUTME: Run: bash scripts/tests/test-analysis-reflex.sh — all cases must be green.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HOOK="${HOOK:-$SCRIPT_DIR/analysis-reflex.sh}"
RUNNER="${RUNNER:-$SCRIPT_DIR/reflex-runner.sh}"
LIB_EMIT="$SCRIPT_DIR/lib/emit-event.sh"

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

PASS=0; FAIL=0

_pass() { echo "  PASS: $1"; (( PASS++ )) || true; }
_fail() { echo "  FAIL: $1 — ${2:-}"; (( FAIL++ )) || true; }

# ── Isolated STATE so tests never touch real governance ──────────────────────
export STATE="$TMP/governance"
export EVENTS="$STATE/state/events.ndjson"
mkdir -p "$STATE/state" "$STATE/reflex-queue/done"

# ── Helpers ──────────────────────────────────────────────────────────────────

# Build a minimal NDJSON transcript whose last assistant message is $1.
make_transcript() {
  local f="$TMP/transcript-$RANDOM.jsonl"
  jq -cn '{"type":"user","message":{"content":"start"}}' > "$f"
  jq -cn --arg t "$1" \
    '{"type":"assistant","message":{"content":[{"type":"text","text":$t}]}}' >> "$f"
  echo "$f"
}

# Run the Stop hook with a given transcript path and stop_hook_active flag.
run_hook() {
  local transcript="${1:-}"
  local stop_hook_active="${2:-false}"
  jq -cn \
    --arg tp "$transcript" \
    --argjson sha "$stop_hook_active" \
    '{"transcript_path":$tp,"stop_hook_active":$sha,"session_id":"test-sess"}' \
    | bash "$HOOK"
}

# Count jobs currently in the live queue (not done/).
queue_count() {
  find "$STATE/reflex-queue" -maxdepth 1 -name "*.json" 2>/dev/null | wc -l | tr -d ' '
}

# Fresh STATE for each sub-group so jobs don't bleed between cases.
fresh_state() {
  rm -rf "$STATE"
  mkdir -p "$STATE/state" "$STATE/reflex-queue/done"
}

# ── PATH shim: mock `claude` binary ──────────────────────────────────────────
# The shim script is written once; each test case sets MOCK_CLAUDE_OUTPUT to
# control what it echoes. MOCK_CLAUDE_SLEEP controls an artificial delay (seconds).
MOCK_BIN="$TMP/bin"
mkdir -p "$MOCK_BIN"
cat > "$MOCK_BIN/claude" << 'SHIM'
#!/usr/bin/env bash
# Mock claude binary: reads MOCK_CLAUDE_OUTPUT and MOCK_CLAUDE_SLEEP from env.
# Enforces the real CLI contract: when -p/--print is present, the prompt must
# arrive via stdin — NOT as a positional argument alongside -p.  A non-flag
# positional arg present alongside -p triggers the real error and exits 1.
[ -n "${MOCK_CLAUDE_SLEEP:-}" ] && sleep "$MOCK_CLAUDE_SLEEP"

HAS_P=0
POSITIONAL_PROMPT=""
i=1
while [ $i -le $# ]; do
  arg="${!i}"
  case "$arg" in
    -p|--print) HAS_P=1 ;;
    --model|--allowedTools)
      # skip next arg (value)
      i=$(( i + 1 ))
      ;;
    --*)
      # skip other flags that take no value (e.g. bare flags)
      ;;
    -*)
      # skip short flags
      ;;
    *)
      # non-flag positional argument
      POSITIONAL_PROMPT="$arg"
      ;;
  esac
  i=$(( i + 1 ))
done

if [ "$HAS_P" -eq 1 ] && [ -n "$POSITIONAL_PROMPT" ]; then
  echo "Input must be provided either through stdin or as a prompt argument when using --print" >&2
  exit 1
fi

echo "${MOCK_CLAUDE_OUTPUT:-CONCUR: looks good}"
exit 0
SHIM
chmod +x "$MOCK_BIN/claude"
export PATH="$MOCK_BIN:$PATH"

echo "=== test-analysis-reflex.sh ==="
echo "STATE=$STATE"
echo ""

# ────────────────────────────────────────────────────────────────────────────
# Case 1: synthesis claim + file:line cite → job enqueued, exit 0
# ────────────────────────────────────────────────────────────────────────────
echo "[1] synthesis claim + file:line cite → job enqueued, exit 0"
fresh_state
TRANSCRIPT=$(make_transcript \
  "The root cause is a race condition at src/worker.py:42. Therefore the fix should be applied there.")
rc=0
run_hook "$TRANSCRIPT" false || rc=$?
if [[ $rc -ne 0 ]]; then
  _fail "1 exit code" "expected 0, got $rc"
else
  _pass "1a hook exits 0"
fi
jcount=$(queue_count)
if [[ "$jcount" -ge 1 ]]; then
  _pass "1b job enqueued"
else
  _fail "1b job enqueued" "queue is empty (count=$jcount)"
fi

# ────────────────────────────────────────────────────────────────────────────
# Case 2: analysis claim + artifact path cite → job enqueued, exit 0, no model call on Stop path
# ────────────────────────────────────────────────────────────────────────────
echo "[2] analysis claim + artifact path cite → job enqueued, no model call"
fresh_state
# We verify no model call by checking that our shim was NOT invoked during hook run.
# We do this by pointing MOCK_CLAUDE_OUTPUT to a sentinel file we can check.
SENTINEL="$TMP/claude-called-$RANDOM"
cat > "$MOCK_BIN/claude" << SHIM2
#!/usr/bin/env bash
touch "${SENTINEL}"
echo "\${MOCK_CLAUDE_OUTPUT:-CONCUR: ok}"
exit 0
SHIM2
chmod +x "$MOCK_BIN/claude"

TRANSCRIPT=$(make_transcript \
  "This means the build system is broken. The analysis shows the issue in docs/plans/arch.md.")
rc=0
run_hook "$TRANSCRIPT" false || rc=$?
[[ $rc -eq 0 ]] && _pass "2a hook exits 0" || _fail "2a hook exits 0" "got $rc"
jcount=$(queue_count)
[[ "$jcount" -ge 1 ]] && _pass "2b job enqueued" || _fail "2b job enqueued" "queue empty"
if [[ ! -f "$SENTINEL" ]]; then
  _pass "2c no model call on Stop path"
else
  _fail "2c no model call on Stop path" "claude shim was invoked"
fi
# Restore simple shim
cat > "$MOCK_BIN/claude" << 'SHIM'
#!/usr/bin/env bash
[ -n "${MOCK_CLAUDE_SLEEP:-}" ] && sleep "$MOCK_CLAUDE_SLEEP"
echo "${MOCK_CLAUDE_OUTPUT:-CONCUR: looks good}"
exit 0
SHIM
chmod +x "$MOCK_BIN/claude"

# ────────────────────────────────────────────────────────────────────────────
# Case 3: synthesis claim WITHOUT cites → no job enqueued
# ────────────────────────────────────────────────────────────────────────────
echo "[3] synthesis claim without cites → no job"
fresh_state
TRANSCRIPT=$(make_transcript \
  "The root cause is that the config was missing. Therefore we should add it.")
rc=0; run_hook "$TRANSCRIPT" false || rc=$?
[[ $rc -eq 0 ]] && _pass "3a exit 0" || _fail "3a exit 0" "got $rc"
jcount=$(queue_count)
if [[ "$jcount" -eq 0 ]]; then
  _pass "3b no job when cites absent"
else
  _fail "3b no job when cites absent" "unexpected job count=$jcount"
fi

# ────────────────────────────────────────────────────────────────────────────
# Case 4: non-synthesis final message → no job, no model call
# ────────────────────────────────────────────────────────────────────────────
echo "[4] non-synthesis message → no job"
fresh_state
TRANSCRIPT=$(make_transcript "Here is the file you requested. Let me know if you need changes.")
rc=0; run_hook "$TRANSCRIPT" false || rc=$?
[[ $rc -eq 0 ]] && _pass "4a exit 0" || _fail "4a exit 0" "got $rc"
jcount=$(queue_count)
[[ "$jcount" -eq 0 ]] && _pass "4b no job for non-synthesis" \
  || _fail "4b no job for non-synthesis" "unexpected job count=$jcount"

# ────────────────────────────────────────────────────────────────────────────
# Case 5: malformed stdin → exit 0
# ────────────────────────────────────────────────────────────────────────────
echo "[5] malformed stdin → exit 0"
fresh_state
rc=0
echo "this is not json at all {{{{" | bash "$HOOK" || rc=$?
[[ $rc -eq 0 ]] && _pass "5 malformed stdin exit 0" \
  || _fail "5 malformed stdin exit 0" "got $rc"

# ────────────────────────────────────────────────────────────────────────────
# Case 6: runner + shim CONCUR → trust_decision emitted, outcome unreviewed_verification, archived
# ────────────────────────────────────────────────────────────────────────────
echo "[6] runner CONCUR → trust_decision + archive"
fresh_state
export MOCK_CLAUDE_OUTPUT="CONCUR: sources support the claim"
# Plant a job file manually
TPATH=$(make_transcript "dummy")
JOBFILE="$STATE/reflex-queue/job-test6.json"
jq -cn \
  --arg ts "2026-07-04T00:00:00Z" \
  --arg tp "$TPATH" \
  --arg ce "the root cause is X (src/foo.py:10)" \
  '{"ts":$ts,"transcript_path":$tp,"claim_excerpt":$ce,"cited_sources":["src/foo.py:10"]}' \
  > "$JOBFILE"

bash "$RUNNER"
rc=$?
[[ $rc -eq 0 ]] && _pass "6a runner exits 0" || _fail "6a runner exits 0" "got $rc"

# Job must be in done/ now
if [[ -f "$STATE/reflex-queue/done/job-test6.json" ]]; then
  _pass "6b job archived to done/"
else
  _fail "6b job archived" "file not in done/"
fi

# Event must have been emitted
if [[ -f "$EVENTS" ]] && grep -q "trust_decision" "$EVENTS" && \
   grep -q "unreviewed_verification" "$EVENTS" && grep -q "CONCUR" "$EVENTS"; then
  _pass "6c trust_decision event with CONCUR and unreviewed_verification"
else
  _fail "6c trust_decision event" "events: $(cat "$EVENTS" 2>/dev/null | head -3)"
fi

# promoted field must be false (not auto-promoted)
if [[ -f "$EVENTS" ]] && grep -q '"promoted":false' "$EVENTS"; then
  _pass "6d promoted:false (no auto-promotion)"
else
  _fail "6d promoted:false" "$(grep "promoted" "$EVENTS" 2>/dev/null || echo 'no promoted field')"
fi

# ────────────────────────────────────────────────────────────────────────────
# Case 7: runner + shim DIVERGE → trust_decision DIVERGE, no correction/incident event
# ────────────────────────────────────────────────────────────────────────────
echo "[7] runner DIVERGE → trust_decision DIVERGE, no correction/incident"
fresh_state
export MOCK_CLAUDE_OUTPUT="DIVERGE: sources do not support the claim"
TPATH=$(make_transcript "dummy")
JOBFILE="$STATE/reflex-queue/job-test7.json"
jq -cn \
  --arg ts "2026-07-04T00:00:01Z" \
  --arg tp "$TPATH" \
  --arg ce "the analysis shows X (report.md)" \
  '{"ts":$ts,"transcript_path":$tp,"claim_excerpt":$ce,"cited_sources":["report.md"]}' \
  > "$JOBFILE"

bash "$RUNNER"

if [[ -f "$EVENTS" ]] && grep -q '"verdict":"DIVERGE"' "$EVENTS"; then
  _pass "7a DIVERGE verdict in event"
else
  _fail "7a DIVERGE verdict" "$(cat "$EVENTS" 2>/dev/null | head -3)"
fi

# Must NOT emit correction or incident event
if [[ -f "$EVENTS" ]] && (grep -q '"event_type":"correction"' "$EVENTS" || \
   grep -q '"event_type":"incident"' "$EVENTS"); then
  _fail "7b no correction/incident on DIVERGE" "found correction or incident event"
else
  _pass "7b no correction/incident emitted on DIVERGE"
fi

# Reason captured (anything after "DIVERGE: ")
if [[ -f "$EVENTS" ]] && grep -q "do not support" "$EVENTS"; then
  _pass "7c reason captured"
else
  _fail "7c reason captured" "$(cat "$EVENTS" 2>/dev/null | head -3)"
fi

# ────────────────────────────────────────────────────────────────────────────
# Case 8: runner + shim hangs → outcome escalated, exit 0
# ────────────────────────────────────────────────────────────────────────────
echo "[8] runner timeout → outcome escalated, exit 0"
fresh_state
export MOCK_CLAUDE_SLEEP="90"
# Override timeout for test: set a 2-second limit via env
export REFLEX_TIMEOUT_SECS="2"
TPATH=$(make_transcript "dummy")
JOBFILE="$STATE/reflex-queue/job-test8.json"
jq -cn \
  --arg ts "2026-07-04T00:00:02Z" \
  --arg tp "$TPATH" \
  --arg ce "the root cause is Y (lib.py:5)" \
  '{"ts":$ts,"transcript_path":$tp,"claim_excerpt":$ce,"cited_sources":["lib.py:5"]}' \
  > "$JOBFILE"

rc=0; bash "$RUNNER" || rc=$?
[[ $rc -eq 0 ]] && _pass "8a runner exits 0 on timeout" \
  || _fail "8a runner exits 0 on timeout" "got $rc"

if [[ -f "$EVENTS" ]] && grep -q '"outcome":"escalated"' "$EVENTS"; then
  _pass "8b escalated outcome emitted"
else
  _fail "8b escalated outcome" "$(cat "$EVENTS" 2>/dev/null | head -5)"
fi

unset MOCK_CLAUDE_SLEEP
unset REFLEX_TIMEOUT_SECS

# ────────────────────────────────────────────────────────────────────────────
# Case 9: empty queue → runner exits 0 silently
# ────────────────────────────────────────────────────────────────────────────
echo "[9] empty queue → runner exits 0 silently"
fresh_state
rc=0; bash "$RUNNER" || rc=$?
[[ $rc -eq 0 ]] && _pass "9 empty queue runner exit 0" \
  || _fail "9 empty queue runner exit 0" "got $rc"

# ────────────────────────────────────────────────────────────────────────────
# Case 10: queue job with malformed JSON → skipped, archived to done/bad, exit 0
# ────────────────────────────────────────────────────────────────────────────
echo "[10] malformed queue job → skipped + archived to done/bad"
fresh_state
export MOCK_CLAUDE_OUTPUT="CONCUR: ok"
BADFILE="$STATE/reflex-queue/bad-job.json"
echo "this is not valid json {{{" > "$BADFILE"

rc=0; bash "$RUNNER" || rc=$?
[[ $rc -eq 0 ]] && _pass "10a runner exits 0 on bad job" \
  || _fail "10a runner exits 0 on bad job" "got $rc"

if [[ -f "$STATE/reflex-queue/done/bad/bad-job.json" ]]; then
  _pass "10b bad job archived to done/bad"
else
  _fail "10b bad job archived to done/bad" \
    "not found; done/ contents: $(ls "$STATE/reflex-queue/done/" 2>/dev/null)"
fi

# ────────────────────────────────────────────────────────────────────────────
# Case 11: transcript_path in job is missing → exit 0, job still archived
# ────────────────────────────────────────────────────────────────────────────
echo "[11] missing transcript in job → exit 0"
fresh_state
export MOCK_CLAUDE_OUTPUT="CONCUR: ok"
JOBFILE="$STATE/reflex-queue/job-test11.json"
jq -cn \
  --arg ts "2026-07-04T00:00:03Z" \
  --arg tp "/tmp/this-transcript-does-not-exist-zzz.jsonl" \
  --arg ce "the root cause is Z (missing.py:1)" \
  '{"ts":$ts,"transcript_path":$tp,"claim_excerpt":$ce,"cited_sources":["missing.py:1"]}' \
  > "$JOBFILE"

rc=0; bash "$RUNNER" || rc=$?
[[ $rc -eq 0 ]] && _pass "11a exit 0 on missing transcript" \
  || _fail "11a exit 0 on missing transcript" "got $rc"
# Job should still be archived (no crash)
if [[ -f "$STATE/reflex-queue/done/job-test11.json" ]]; then
  _pass "11b job archived even with missing transcript"
else
  _fail "11b job archived despite missing transcript" \
    "done/ contents: $(ls "$STATE/reflex-queue/done/" 2>/dev/null)"
fi

# ────────────────────────────────────────────────────────────────────────────
# Case 12: stop_hook_active true in hook input → exit 0, no re-enqueue
# ────────────────────────────────────────────────────────────────────────────
echo "[12] stop_hook_active=true → exit 0, no re-enqueue"
fresh_state
TRANSCRIPT=$(make_transcript \
  "The root cause is a null pointer at src/core.c:99. Therefore we must fix it.")
rc=0; run_hook "$TRANSCRIPT" true || rc=$?
[[ $rc -eq 0 ]] && _pass "12a exit 0 with stop_hook_active" \
  || _fail "12a exit 0 with stop_hook_active" "got $rc"
jcount=$(queue_count)
if [[ "$jcount" -eq 0 ]]; then
  _pass "12b no re-enqueue when stop_hook_active"
else
  _fail "12b no re-enqueue when stop_hook_active" "queue count=$jcount"
fi

# ────────────────────────────────────────────────────────────────────────────
# Case 13: multi-line claim_excerpt — runner must pipe prompt via stdin, not
# pass it as a positional arg.  The shim rejects positional args alongside -p
# the same way the real claude CLI does.  The event must be emitted (not
# escalated) and the job must be archived.
# ────────────────────────────────────────────────────────────────────────────
echo "[13] multi-line claim_excerpt → runner pipes prompt via stdin (not positional arg)"
fresh_state
export MOCK_CLAUDE_OUTPUT="CONCUR: multi-line claim verified"
TPATH=$(make_transcript "dummy multiline")
JOBFILE="$STATE/reflex-queue/job-test13.json"
# Build a claim_excerpt that spans two lines (the real failure trigger)
MULTILINE_CLAIM="The analysis shows a race condition at src/core.py:42.
Therefore the fix must be atomic."
jq -cn \
  --arg ts "2026-07-04T00:00:04Z" \
  --arg tp "$TPATH" \
  --arg ce "$MULTILINE_CLAIM" \
  '{"ts":$ts,"transcript_path":$tp,"claim_excerpt":$ce,"cited_sources":["src/core.py:42"]}' \
  > "$JOBFILE"

# Install the stdin-enforcement shim: rejects a positional prompt alongside -p,
# mirroring the real claude CLI error.  Case 2 restored the simple shim, so we
# must re-install the enforcement version here.
cat > "$MOCK_BIN/claude" << 'SHIM13'
#!/usr/bin/env bash
HAS_P=0
POSITIONAL_PROMPT=""
i=1
while [ $i -le $# ]; do
  arg="${!i}"
  case "$arg" in
    -p|--print) HAS_P=1 ;;
    --model|--allowedTools) i=$(( i + 1 )) ;;
    --*) ;;
    -*) ;;
    *) POSITIONAL_PROMPT="$arg" ;;
  esac
  i=$(( i + 1 ))
done
if [ "$HAS_P" -eq 1 ] && [ -n "$POSITIONAL_PROMPT" ]; then
  echo "Input must be provided either through stdin or as a prompt argument when using --print" >&2
  exit 1
fi
echo "${MOCK_CLAUDE_OUTPUT:-CONCUR: looks good}"
exit 0
SHIM13
chmod +x "$MOCK_BIN/claude"

bash "$RUNNER"
rc=$?
[[ $rc -eq 0 ]] && _pass "13a runner exits 0 with multi-line claim" \
  || _fail "13a runner exits 0 with multi-line claim" "got $rc"

# Job must be archived (runner did not crash)
if [[ -f "$STATE/reflex-queue/done/job-test13.json" ]]; then
  _pass "13b job archived after multi-line claim"
else
  _fail "13b job archived after multi-line claim" \
    "not found; done/ contents: $(ls "$STATE/reflex-queue/done/" 2>/dev/null)"
fi

# Event must NOT be escalated — the claude call must have succeeded
if [[ -f "$EVENTS" ]] && grep -q '"outcome":"escalated"' "$EVENTS"; then
  _fail "13c outcome not escalated" "got escalated — runner passed prompt as positional arg"
else
  _pass "13c outcome is not escalated (stdin pipe working)"
fi

# CONCUR verdict must be present in the event
if [[ -f "$EVENTS" ]] && grep -q '"verdict":"CONCUR"' "$EVENTS"; then
  _pass "13d CONCUR verdict recorded"
else
  _fail "13d CONCUR verdict recorded" \
    "events: $(cat "$EVENTS" 2>/dev/null | tail -3)"
fi

# Restore simple shim so any future cases start clean
cat > "$MOCK_BIN/claude" << 'SHIM'
#!/usr/bin/env bash
[ -n "${MOCK_CLAUDE_SLEEP:-}" ] && sleep "$MOCK_CLAUDE_SLEEP"
echo "${MOCK_CLAUDE_OUTPUT:-CONCUR: looks good}"
exit 0
SHIM
chmod +x "$MOCK_BIN/claude"

# ────────────────────────────────────────────────────────────────────────────
echo ""
echo "analysis-reflex: $PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]]
