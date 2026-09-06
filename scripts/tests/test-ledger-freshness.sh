#!/usr/bin/env bash
# ABOUTME: Behavior tests for scripts/governance/ledger-freshness-check.sh (Stop hook, PKT-JD-03).
# ABOUTME: Covers: last-test-FAILED blocks, last-test-PASSED allows, no ledger allows,
# ABOUTME: corrupt ledger lines fail-safe, no claim allows, and neuter-and-fail proof.
# ABOUTME: Written per PKT-JD-03 spec §Neuter-and-fail test plan (fixtures A-D + neuter).
# ABOUTME: Uses HARNESS_STATE_OVERRIDE for ledger isolation; never touches the live ledger.

set -uo pipefail

SCRIPT="${SCRIPT:-$HOME/.claude/scripts/governance/ledger-freshness-check.sh}"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
PASS=0; FAIL=0

# ─── Helpers ─────────────────────────────────────────────────────────────────

# Build a minimal transcript whose last assistant message is $1.
make_transcript() {
  local f="$TMP/transcript-$RANDOM.jsonl"
  jq -cn '{"type":"user","message":{"content":"start"}}' > "$f"
  jq -cn --arg t "$1" '{"type":"assistant","message":{"content":[{"type":"text","text":$t}]}}' >> "$f"
  echo "$f"
}

# Build a fake state dir (under $TMP) and populate events.ndjson with the given NDJSON lines.
# Usage: make_ledger_state <state_dir> [line1] [line2] ...
# Returns: the state dir (parent of state/events.ndjson).
make_ledger_state() {
  local sdir="$1"; shift
  mkdir -p "$sdir/state"
  rm -f "$sdir/state/events.ndjson"
  for line in "$@"; do
    printf '%s\n' "$line" >> "$sdir/state/events.ndjson"
  done
  echo "$sdir"
}

# Build a trust_decision test-run event for a given session and outcome.
# $1 = session_id, $2 = outcome (pass|fail)
ledger_testrun_event() {
  local sid="$1" outcome="$2"
  jq -cn --arg sid "$sid" --arg out "$outcome" \
    '{"ts":"2026-07-08T10:00:00.000Z","schema":1,"session_id":$sid,"agent_id":null,
      "event_type":"trust_decision","source":"evidence-ledger.sh","project":"test",
      "payload":{"claim":"test_count","classification":"test-run","passed":"5","failed":"0"},
      "tool":"Bash","skill":null,"outcome":$out,"evidence_ref":"abc123","trace_id":null}'
}

# Run the hook with the given transcript + state dir + session_id.
# $1 = transcript path, $2 = HARNESS_STATE_OVERRIDE dir, $3 = session_id
run_hook() {
  local tp="$1" state_dir="$2" sid="${3:-testsession42}"
  jq -cn --arg tp "$tp" --arg cwd "$TMP" --arg sid "$sid" \
    '{"transcript_path":$tp,"cwd":$cwd,"stop_hook_active":false,"session_id":$sid}' \
  | HARNESS_STATE_OVERRIDE="$state_dir" bash "$SCRIPT"
}

# Check helper: $1 = case name, $2 = expected (block|pass), $3 = actual output.
check() {
  if [[ "$2" == "block" ]]; then
    if printf '%s' "$3" | grep -q '"decision":"block"'; then
      echo "PASS: $1"; PASS=$((PASS+1))
    else
      echo "FAIL: $1 — expected block, got: ${3:-<empty>}"; FAIL=$((FAIL+1))
    fi
  else
    if printf '%s' "$3" | grep -q '"decision":"block"'; then
      echo "FAIL: $1 — expected pass (allow), got block: $3"; FAIL=$((FAIL+1))
    else
      echo "PASS: $1"; PASS=$((PASS+1))
    fi
  fi
}

TEST_SID="testsession42"
# A completion-claim phrase that satisfies the CLAIM regex.
CLAIM_TEXT="All tests pass — implementation is complete."
# A non-claim phrase.
NOCLAIM_TEXT="Here are three options you might consider."

# ─── Fixture A: last test-run FAIL + completion claim → BLOCK ────────────────
SDIR_A="$TMP/stateA"
EV_FAIL=$(ledger_testrun_event "$TEST_SID" "fail")
make_ledger_state "$SDIR_A" "$EV_FAIL" > /dev/null
T_A=$(make_transcript "$CLAIM_TEXT")
OUT_A=$(run_hook "$T_A" "$SDIR_A" "$TEST_SID")
check "A: last-test-FAILED + claim → BLOCK" block "$OUT_A"

# Also verify the block reason mentions the session id (useful diagnostic).
if printf '%s' "$OUT_A" | grep -q "$TEST_SID"; then
  echo "PASS: A(detail) block reason contains session_id"; PASS=$((PASS+1))
else
  echo "FAIL: A(detail) block reason missing session_id (got: $OUT_A)"; FAIL=$((FAIL+1))
fi

# ─── Fixture B: last test-run PASS + completion claim → ALLOW ────────────────
SDIR_B="$TMP/stateB"
EV_PASS=$(ledger_testrun_event "$TEST_SID" "pass")
make_ledger_state "$SDIR_B" "$EV_PASS" > /dev/null
T_B=$(make_transcript "$CLAIM_TEXT")
check "B: last-test-PASSED + claim → ALLOW" pass "$(run_hook "$T_B" "$SDIR_B" "$TEST_SID")"

# ─── Fixture C: no test-run events for session → ALLOW (fail-open) ───────────
SDIR_C="$TMP/stateC"
# Ledger has an event for a DIFFERENT session only — this session has none.
EV_OTHER=$(ledger_testrun_event "differentsession" "fail")
make_ledger_state "$SDIR_C" "$EV_OTHER" > /dev/null
T_C=$(make_transcript "$CLAIM_TEXT")
check "C: no test-run events for session → ALLOW (fail-open)" pass "$(run_hook "$T_C" "$SDIR_C" "$TEST_SID")"

# ─── Fixture D: fail event present but last message has NO claim → ALLOW ─────
SDIR_D="$TMP/stateD"
make_ledger_state "$SDIR_D" "$EV_FAIL" > /dev/null
T_D=$(make_transcript "$NOCLAIM_TEXT")
check "D: fail event but no completion claim → ALLOW" pass "$(run_hook "$T_D" "$SDIR_D" "$TEST_SID")"

# ─── Extra: missing ledger → ALLOW (fail-open) ───────────────────────────────
SDIR_E="$TMP/stateE"
mkdir -p "$SDIR_E/state"
# No events.ndjson created.
T_E=$(make_transcript "$CLAIM_TEXT")
check "E: missing ledger → ALLOW (fail-open)" pass "$(run_hook "$T_E" "$SDIR_E" "$TEST_SID")"

# ─── Extra: corrupt ledger lines → ALLOW (fail-safe) ─────────────────────────
SDIR_F="$TMP/stateF"
EV_CORRUPT='this is not json { broken }'
EV_OTHER2=$(ledger_testrun_event "othersession" "pass")
make_ledger_state "$SDIR_F" "$EV_CORRUPT" "$EV_OTHER2" > /dev/null
T_F=$(make_transcript "$CLAIM_TEXT")
check "F: corrupt ledger lines → ALLOW (fail-safe)" pass "$(run_hook "$T_F" "$SDIR_F" "$TEST_SID")"

# ─── Extra: most recent is PASS even if earlier event was FAIL ────────────────
# Ensures we look at MOST RECENT, not worst-case.
SDIR_G="$TMP/stateG"
EV_FAIL_EARLY=$(ledger_testrun_event "$TEST_SID" "fail")
EV_PASS_LATER=$(ledger_testrun_event "$TEST_SID" "pass")
make_ledger_state "$SDIR_G" "$EV_FAIL_EARLY" "$EV_PASS_LATER" > /dev/null
T_G=$(make_transcript "$CLAIM_TEXT")
check "G: earlier FAIL then later PASS → ALLOW (most recent wins)" pass "$(run_hook "$T_G" "$SDIR_G" "$TEST_SID")"

# ─── Extra: most recent is FAIL even if earlier event was PASS ────────────────
SDIR_H="$TMP/stateH"
EV_PASS_EARLY=$(ledger_testrun_event "$TEST_SID" "pass")
EV_FAIL_LATER=$(ledger_testrun_event "$TEST_SID" "fail")
make_ledger_state "$SDIR_H" "$EV_PASS_EARLY" "$EV_FAIL_LATER" > /dev/null
T_H=$(make_transcript "$CLAIM_TEXT")
check "H: earlier PASS then later FAIL → BLOCK (most recent wins)" block "$(run_hook "$T_H" "$SDIR_H" "$TEST_SID")"

# ─── Extra: missing/unknown session_id → ALLOW (fail-open, no filtering) ─────
SDIR_I="$TMP/stateI"
make_ledger_state "$SDIR_I" "$EV_FAIL" > /dev/null
T_I=$(make_transcript "$CLAIM_TEXT")
# Run without session_id in payload (omit the field → empty/unknown).
OUT_I=$(jq -cn --arg tp "$T_I" --arg cwd "$TMP" \
  '{"transcript_path":$tp,"cwd":$cwd,"stop_hook_active":false}' \
  | HARNESS_STATE_OVERRIDE="$SDIR_I" bash "$SCRIPT")
check "I: missing session_id → ALLOW (fail-open)" pass "$OUT_I"

echo ""
echo "── pre-neuter summary: $PASS passed, $FAIL failed ──"
echo ""

# ─── Neuter-and-fail check ────────────────────────────────────────────────────
# Comment out the ledger-read logic; re-run Fixture A. Suite MUST fail (A no longer blocks).
# Strategy: copy the script, remove the grep|jq pipeline that reads events.ndjson, then
# run against Fixture A. If the neutered script still blocks, the neuter didn't work —
# the ledger-read is NOT load-bearing (false positive in our test).
NEUTERED="$TMP/ledger-freshness-neutered.sh"
cp "$SCRIPT" "$NEUTERED"
# Comment out the line that actually reads the ledger (the grep+jq pipe into MOST_RECENT_OUTCOME).
# We replace the assignment block with a no-op that always sets MOST_RECENT_OUTCOME="".
perl -0777 -i -pe '
  s{MOST_RECENT_OUTCOME=\$\([\s\S]*?\) \|\| MOST_RECENT_OUTCOME=""}{MOST_RECENT_OUTCOME="" # NEUTERED}m
' "$NEUTERED"
chmod +x "$NEUTERED"

NEUTER_SDIR="$TMP/stateNeuter"
make_ledger_state "$NEUTER_SDIR" "$EV_FAIL" > /dev/null
T_NEUTER=$(make_transcript "$CLAIM_TEXT")
NEUTER_OUT=$(jq -cn --arg tp "$T_NEUTER" --arg cwd "$TMP" --arg sid "$TEST_SID" \
  '{"transcript_path":$tp,"cwd":$cwd,"stop_hook_active":false,"session_id":$sid}' \
  | HARNESS_STATE_OVERRIDE="$NEUTER_SDIR" bash "$NEUTERED")

if printf '%s' "$NEUTER_OUT" | grep -q '"decision":"block"'; then
  echo "FAIL: neuter-check — neutered script still blocks (ledger-read not load-bearing or neuter ineffective)"
  FAIL=$((FAIL+1))
else
  echo "PASS: neuter-and-fail — neutered script allows Fixture A (ledger-read IS load-bearing)"
  PASS=$((PASS+1))
fi

echo ""
echo "ledger-freshness-check: $PASS passed, $FAIL failed"
[[ "$FAIL" -eq 0 ]]
