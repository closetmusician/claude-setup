#!/usr/bin/env bash
# ABOUTME: Behavior tests for scripts/completion-claim-guard.sh (Stop hook).
# ABOUTME: Covers: unevidenced/rephrased claims, fabricated artifact & file:line cites,
# ABOUTME: test-count cross-check against transcript tool output, C1 existence-denial
# ABOUTME: misreports, stop_hook_active retry logging, and fail-open on garbage transcripts.
# ABOUTME: Written after adversarial review docs/temp/adv-review-0703 (findings F1/F2/F9/B5/C1).

set -uo pipefail

GUARD="${GUARD:-$HOME/.claude/scripts/completion-claim-guard.sh}"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
PASS=0; FAIL=0

# Build an NDJSON transcript whose last assistant message is $1; $2 (optional) is an
# extra raw JSON line inserted before it (e.g. a tool_result line).
make_transcript() {
  local f="$TMP/transcript-$RANDOM.jsonl"
  jq -cn '{"type":"user","message":{"content":"start"}}' > "$f"
  [[ -n "${2:-}" ]] && printf '%s\n' "$2" >> "$f"
  jq -cn --arg t "$1" '{"type":"assistant","message":{"content":[{"type":"text","text":$t}]}}' >> "$f"
  echo "$f"
}

run_guard() { # $1 transcript path, $2 stop_hook_active (true|false)
  jq -cn --arg tp "$1" --arg cwd "$TMP" --argjson sha "${2:-false}" \
    '{"transcript_path":$tp,"cwd":$cwd,"stop_hook_active":$sha}' | bash "$GUARD"
}

check() { # $1 case name, $2 expected (block|pass), $3 actual output
  if [[ "$2" == "block" ]]; then
    if echo "$3" | grep -q '"decision":"block"'; then
      echo "PASS: $1"; PASS=$((PASS+1))
    else
      echo "FAIL: $1 — expected block, got: ${3:-<empty>}"; FAIL=$((FAIL+1))
    fi
  else
    if echo "$3" | grep -q '"decision":"block"'; then
      echo "FAIL: $1 — expected pass, got block: $3"; FAIL=$((FAIL+1))
    else
      echo "PASS: $1"; PASS=$((PASS+1))
    fi
  fi
}

# 1. Naked completion claim, no evidence -> block
T=$(make_transcript "Implementation complete. Everything is wired up.")
check "1 unevidenced claim blocks" block "$(run_guard "$T")"

# 2. Rephrased claim outside the old 8-phrase set (bypass B3) -> block
T=$(make_transcript "All done! The feature is in and the task is finished.")
check "2 rephrased claim blocks" block "$(run_guard "$T")"

# 3. Claim + cited artifact that exists -> pass
touch "$TMP/proof.png"
T=$(make_transcript "All tests pass — screenshot saved at $TMP/proof.png")
check "3 existing artifact cite passes" pass "$(run_guard "$T")"

# 4. Claim + cited artifact that does NOT exist (fabricated evidence, F1) -> block
T=$(make_transcript "All tests pass — screenshot saved at /tmp/nonexistent-zz9-proof.png")
check "4 fabricated artifact cite blocks" block "$(run_guard "$T")"

# 5. Claimed test count present in tool output -> pass
TOOLLINE=$(jq -cn '{"type":"user","message":{"content":[{"type":"tool_result","content":"===== 84 passed in 2.13s ====="}]}}')
T=$(make_transcript "Implementation complete — 84 passed." "$TOOLLINE")
check "5 tool-backed test count passes" pass "$(run_guard "$T")"

# 6. Claimed test count absent from any tool output (F1) -> block
T=$(make_transcript "Implementation complete — 312 passed.")
check "6 unbacked test count blocks" block "$(run_guard "$T")"

# 7. No completion claim at all -> pass
T=$(make_transcript "Here is my analysis of the two options and their tradeoffs.")
check "7 non-claim message passes" pass "$(run_guard "$T")"

# 8. stop_hook_active retry -> passes (loop protection) but is logged (F9)
LOG="$HOME/.claude/state/completion-claim-guard.log"
BEFORE=$(grep -c "" "$LOG" 2>/dev/null || echo 0)
T=$(make_transcript "Implementation complete. Trust me this time.")
check "8a stop_hook_active passes" pass "$(run_guard "$T" true)"
AFTER=$(grep -c "" "$LOG" 2>/dev/null || echo 0)
if [[ "$AFTER" -gt "$BEFORE" ]]; then
  echo "PASS: 8b retry was logged"; PASS=$((PASS+1))
else
  echo "FAIL: 8b retry not logged ($BEFORE -> $AFTER)"; FAIL=$((FAIL+1))
fi

# 9. Existence-denial misreport (C1): denied path actually exists -> block
touch "$TMP/exists.txt"
T=$(make_transcript "The file $TMP/exists.txt does not exist, so I skipped that step.")
check "9 false existence-denial blocks" block "$(run_guard "$T")"

# 10. Existence-denial of a genuinely missing path -> pass
T=$(make_transcript "The file /tmp/definitely-missing-zz9.txt does not exist, so I skipped it.")
check "10 true existence-denial passes" pass "$(run_guard "$T")"

# 11. Old vacuous-evidence bypass (B5): '$ command' prose is no longer evidence -> block
T=$(make_transcript "All tests pass. Run \$ npm test to verify for yourself.")
check "11 command-prose non-evidence blocks" block "$(run_guard "$T")"

# 12. Garbage transcript -> fail-open pass
echo "this is not json" > "$TMP/garbage.jsonl"
check "12 garbage transcript fails open" pass "$(run_guard "$TMP/garbage.jsonl")"

# 13. Claim + real file:line citation -> pass
echo "x = 1" > "$TMP/code.py"
T=$(make_transcript "Fix applied — see $TMP/code.py:1 for the change.")
check "13 real file:line cite passes" pass "$(run_guard "$T")"

# 14. Claim + fabricated file:line citation -> block
T=$(make_transcript "Fix applied — see $TMP/ghost.py:42 for the change.")
check "14 fabricated file:line cite blocks" block "$(run_guard "$T")"

# ---- Exit-code evidence branch (REV-C finding: branch untested) ----

# 15. Claim + "exit code 0" backed by a tool_result line -> pass (true positive)
TOOLLINE=$(jq -cn '{"type":"user","message":{"content":[{"type":"tool_result","content":"Process exited with exit code 0"}]}}')
T=$(make_transcript "Fix applied and verified — command finished with exit code 0." "$TOOLLINE")
check "15 exit-code backed by tool output passes" pass "$(run_guard "$T")"

# 16. Claim + "exit code 0" with no tool output backing it -> block (true negative)
T=$(make_transcript "Fix applied and verified — command finished with exit code 0.")
check "16 exit-code not backed by tool output blocks" block "$(run_guard "$T")"

# ---- Commit SHA evidence branch (REV-C finding: branch untested) ----

# 17. Claim + commit SHA backed by a tool_result line -> pass (true positive)
TOOLLINE=$(jq -cn '{"type":"user","message":{"content":[{"type":"tool_result","content":"commit abc1234 (HEAD -> main)\nAuthor: dev"}]}}')
T=$(make_transcript "Implementation complete — see commit abc1234 for the changes." "$TOOLLINE")
check "17 commit SHA backed by tool output passes" pass "$(run_guard "$T")"

# 18. Claim + commit SHA NOT backed by tool output -> block (true negative)
T=$(make_transcript "Implementation complete — see commit abc1234def5678 for the changes.")
check "18 commit SHA not backed by tool output blocks" block "$(run_guard "$T")"

# ---- Numeric-count "all N tests pass" bypass gap (smoke step 2-5b) ----

# 19. "Done. All 47 tests pass." with no tool output -> must block (coverage gap)
T=$(make_transcript "Done. All 47 tests pass.")
check "19 numeric-count claim without tool output blocks" block "$(run_guard "$T")"

# 20. Same claim WITH matching tool output -> must pass (evidence present)
TOOLLINE=$(jq -cn '{"type":"user","message":{"content":[{"type":"tool_result","content":"===== 47 passed in 1.23s ====="}]}}')
T=$(make_transcript "Done. All 47 tests pass." "$TOOLLINE")
check "20 numeric-count claim with backed tool output passes" pass "$(run_guard "$T")"

# ---- Stage 3: Ledger reconciliation (II.2) ----
# Helper: build a fake events.ndjson in a temp STATE dir and run the guard with it.
# HARNESS_STATE_OVERRIDE points completion-claim-guard's ledger reader at $1 (the fake
# state dir); session_id is injected into the transcript hook input via a wrapper that
# sets SESSION_ID in the environment so the guard can read it from INPUT.

make_ledger_state() {
  # $1 = state dir to create/populate; subsequent args = NDJSON lines to write.
  local sdir="$1"; shift
  mkdir -p "$sdir/state"
  # Clear any prior ledger
  rm -f "$sdir/state/events.ndjson"
  for line in "$@"; do
    printf '%s\n' "$line" >> "$sdir/state/events.ndjson"
  done
  echo "$sdir"
}

# Build a ledger trust_decision event for a test-run with a given passed count + session.
ledger_testrun_event() {
  # $1 = session_id, $2 = passed count
  local sid="$1" n="$2"
  jq -cn --arg sid "$sid" --arg n "$n" \
    '{"ts":"2026-07-04T00:00:00.000Z","schema":1,"session_id":$sid,"agent_id":null,
      "event_type":"trust_decision","source":"evidence-ledger.sh","project":"test",
      "payload":{"claim":"test_count","classification":"test-run","passed":$n,"failed":""},
      "tool":"Bash","skill":null,"outcome":"ok",
      "evidence_ref":($n+"passed@abc1234567890ab"),"trace_id":null}'
}

# Build a ledger metric event for a git commit with a given SHA + session.
ledger_gitcommit_event() {
  # $1 = session_id, $2 = git SHA
  local sid="$1" sha="$2"
  jq -cn --arg sid "$sid" --arg sha "$sha" \
    '{"ts":"2026-07-04T00:00:00.000Z","schema":1,"session_id":$sid,"agent_id":null,
      "event_type":"metric","source":"evidence-ledger.sh","project":"test",
      "payload":{"name":"cmd_exit","classification":"git-commit","git_sha":$sha},
      "tool":"Bash","skill":null,"outcome":"ok",
      "evidence_ref":($sha+"@abc1234567890ab"),"trace_id":null}'
}

# run_guard_ledger: run the guard with a fake ledger state override and a session ID.
# $1 = transcript path, $2 = HARNESS_STATE_OVERRIDE dir, $3 = session_id to inject
run_guard_ledger() {
  local tp="$1" state_override="$2" sid="${3:-testsession42}"
  # Build hook input with session_id set (so guard can read it from INPUT.session_id)
  jq -cn --arg tp "$tp" --arg cwd "$TMP" --arg sid "$sid" \
    '{"transcript_path":$tp,"cwd":$cwd,"stop_hook_active":false,"session_id":$sid}' \
  | HARNESS_STATE_OVERRIDE="$state_override" bash "$GUARD"
}

TEST_SID="testsession42"

# 21. Claim '21 passed' + session ledger event with count 21 -> ALLOW
# Stage 3 finds the test-run token; all stages pass.
EV=$(ledger_testrun_event "$TEST_SID" "21")
SDIR=$(make_ledger_state "$TMP/state21" "$EV")
TOOLLINE=$(jq -cn '{"type":"user","message":{"content":[{"type":"tool_result","content":"21 passed in 1.5s"}]}}')
T=$(make_transcript "All tests pass — 21 passed." "$TOOLLINE")
check "21 ledger-backed count 21 → ALLOW" pass "$(run_guard_ledger "$T" "$SDIR" "$TEST_SID")"

# 22. Claim '21 passed' + ledger shows only a 15-passed run -> BLOCK naming mismatch.
# Stage 2 (transcript grep) still passes (21 is in the tool output).
# Stage 3 finds only a 15-passed token → BLOCK.
EV=$(ledger_testrun_event "$TEST_SID" "15")
SDIR=$(make_ledger_state "$TMP/state22" "$EV")
TOOLLINE=$(jq -cn '{"type":"user","message":{"content":[{"type":"tool_result","content":"21 passed in 1.5s"}]}}')
T=$(make_transcript "All tests pass — 21 passed." "$TOOLLINE")
check "22 ledger count mismatch (15 vs 21) → BLOCK" block "$(run_guard_ledger "$T" "$SDIR" "$TEST_SID")"

# 23. Claim with commit SHA + no git-commit ledger event but SHA verifiable in transcript
# (existing Stage-2 path) → stays ALLOW. Stage 3 must not add a new block here.
# Evidence: the SHA appears in tool output (transcript), which Stage 2 already verified.
# Ledger has events but no git-commit event (only a test-run token); Stage 3 for SHAs
# must treat absent git-commit ledger as "not verifiable via ledger → pass-through to
# Stage 2's already-passed result."
EV=$(ledger_testrun_event "$TEST_SID" "5")
SDIR=$(make_ledger_state "$TMP/state23" "$EV")
TOOLLINE=$(jq -cn '{"type":"user","message":{"content":[{"type":"tool_result","content":"commit deadbeef1234 (HEAD)\nAuthor: dev"}]}}')
T=$(make_transcript "Implementation complete — see commit deadbeef1234 for the changes." "$TOOLLINE")
check "23 commit SHA Stage-2 verified → no weakening from Stage 3" pass "$(run_guard_ledger "$T" "$SDIR" "$TEST_SID")"

# 24. Session with zero ledger events (ledger unwired) -> Stage 3 silent pass-through,
# existing Stage-1/Stage-2 behavior unchanged. Count claim is backed by transcript tool
# output, so Stage 2 passes; Stage 3 must be silent because there are no ledger events
# for this session.
SDIR=$(make_ledger_state "$TMP/state24")  # empty ledger
TOOLLINE=$(jq -cn '{"type":"user","message":{"content":[{"type":"tool_result","content":"21 passed in 1.5s"}]}}')
T=$(make_transcript "All tests pass — 21 passed." "$TOOLLINE")
check "24 zero ledger events → Stage 3 pass-through (unwired)" pass "$(run_guard_ledger "$T" "$SDIR" "$TEST_SID")"

# 25. Malformed ledger line -> fail-open ALLOW. Ledger has one garbled JSON line + one
# valid-but-different-session line; Stage 3 must not crash or block on parse error.
EV_BAD='this is not json at all { broken'
EV_OTHER=$(ledger_testrun_event "differentsession" "21")
SDIR=$(make_ledger_state "$TMP/state25" "$EV_BAD" "$EV_OTHER")
TOOLLINE=$(jq -cn '{"type":"user","message":{"content":[{"type":"tool_result","content":"21 passed in 1.5s"}]}}')
T=$(make_transcript "All tests pass — 21 passed." "$TOOLLINE")
check "25 malformed ledger line → fail-open ALLOW" pass "$(run_guard_ledger "$T" "$SDIR" "$TEST_SID")"

# ---- C3 Citation gate for numeric claims (Phase 4.2, item 20) ----
# Tests 26-33: DETECT-only shadow mode (uncited) and conditional BLOCK mode (cited).
# SENTINEL: ~/.claude/state/.citation-gate-live enables the BLOCK path.
# DETECT always on; BLOCK only when sentinel exists.
#
# Helper: run the guard with a custom STATE dir so emitted trust_decision events can be
# read back. EVENTS env var overrides the STATE path for emit-event.sh (via STATE env).
run_guard_state() {
  # $1 = transcript path, $2 = STATE dir for event capture (DETECT assertions)
  local tp="$1" state_dir="$2"
  jq -cn --arg tp "$tp" --arg cwd "$TMP" \
    '{"transcript_path":$tp,"cwd":$cwd,"stop_hook_active":false}' \
  | STATE="$state_dir" bash "$GUARD"
}

# Check that a C3 DETECT event was emitted to STATE dir.
check_detect_event() {
  # $1 = case name, $2 = STATE dir
  local case_name="$1" state_dir="$2"
  local spine="$state_dir/state/events.ndjson"
  if [[ -f "$spine" ]] && grep -q '"citation-gate"' "$spine" 2>/dev/null; then
    echo "PASS: $case_name (detect-event present)"; PASS=$((PASS+1))
  else
    echo "FAIL: $case_name — expected C3 detect event in $spine"; FAIL=$((FAIL+1))
  fi
}

# Check that NO C3 DETECT event was emitted to STATE dir.
check_no_detect_event() {
  local case_name="$1" state_dir="$2"
  local spine="$state_dir/state/events.ndjson"
  if [[ -f "$spine" ]] && grep -q '"citation-gate"' "$spine" 2>/dev/null; then
    echo "FAIL: $case_name — unexpected C3 detect event in $spine"; FAIL=$((FAIL+1))
  else
    echo "PASS: $case_name (no detect event, correct)"; PASS=$((PASS+1))
  fi
}

# Ensure sentinel is absent for all tests that depend on sentinel-absence.
SENTINEL="$HOME/.claude/state/.citation-gate-live"
# Save original sentinel state; remove it to guarantee a known baseline.
_SENTINEL_EXISTED=false
[[ -f "$SENTINEL" ]] && _SENTINEL_EXISTED=true && rm -f "$SENTINEL"

# 26. Cited numeric claim — "46%" appears in tool output (non-assistant line) -> PASS, no event.
# The number "46" is present in transcript tool output → verified → no block, no detect event.
SDIR26="$TMP/state26"
TOOLLINE=$(jq -cn '{"type":"user","message":{"content":[{"type":"tool_result","content":"token savings: 46% (measured)"}]}}')
T=$(make_transcript "Implementation complete — exit code 0 — reduced tokens by 46%." "$TOOLLINE")
TOOLLINE2=$(jq -cn '{"type":"user","message":{"content":[{"type":"tool_result","content":"Process exited with exit code 0"}]}}')
T=$(make_transcript "Implementation complete — exit code 0 — reduced tokens by 46%." "$TOOLLINE2")
# Stage 2 exit-code check needs the toolline; build a transcript with both
{
  jq -cn '{"type":"user","message":{"content":"start"}}'
  printf '%s\n' "$TOOLLINE"
  printf '%s\n' "$TOOLLINE2"
  jq -cn '{"type":"text","type":"assistant","message":{"content":[{"type":"text","text":"Implementation complete — exit code 0 — reduced tokens by 46%."}]}}'
} > "$TMP/t26.jsonl"
# Simpler: use an artifact cite so stage-2 passes cleanly, plus tool-output with "46"
touch "$TMP/proof26.json"
T=$(make_transcript "Implementation complete — results at $TMP/proof26.json — reduced tokens by 46%." "$TOOLLINE")
check "26 cited numeric (46 in tool output) → pass no block" pass "$(run_guard_state "$T" "$SDIR26")"
check_no_detect_event "26b cited numeric no detect event" "$SDIR26"

# 27. Cited numeric claim — number ABSENT from tool output + sentinel EXISTS -> BLOCK.
# "500" does not appear in any non-assistant line → cited-but-unverifiable → BLOCK when sentinel live.
touch "$SENTINEL"
SDIR27="$TMP/state27"
touch "$TMP/proof27.md"
T=$(make_transcript "All done — see $TMP/proof27.md — handles 500 requests/sec." "")
check "27 cited numeric absent from tool output (sentinel live) → block" block "$(run_guard_state "$T" "$SDIR27")"
rm -f "$SENTINEL"

# 28. Same claim as 27 but sentinel ABSENT -> DETECT event + pass (no block).
SDIR28="$TMP/state28"
touch "$TMP/proof28.md"
T=$(make_transcript "All done — see $TMP/proof28.md — handles 500 requests/sec." "")
check "28 cited numeric absent (no sentinel) → detect+pass" pass "$(run_guard_state "$T" "$SDIR28")"
check_detect_event "28b sentinel-absent emits C3 detect event" "$SDIR28"

# 29. Uncited prose numeric ("improved performance by 30%") -> DETECT event + pass, never block.
# Even with sentinel live, uncited prose is DETECT-only (no citation shape nearby).
# The message must include a $CLAIM trigger so Stage 4 is reached; exit code 0 is backed by tool output.
touch "$SENTINEL"
SDIR29="$TMP/state29"
TOOLLINE=$(jq -cn '{"type":"user","message":{"content":[{"type":"tool_result","content":"Process exited with exit code 0"}]}}')
T=$(make_transcript "Implementation complete — we improved performance by 30% — exit code 0." "$TOOLLINE")
check "29 uncited prose numeric → detect+pass never block" pass "$(run_guard_state "$T" "$SDIR29")"
check_detect_event "29b uncited prose emits C3 detect event" "$SDIR29"
rm -f "$SENTINEL"

# 30. Innocent numbers (version v2.1.0, date 2026-07-05, PR #42, file.py:123) -> NO detect event.
# The regex must exclude: versions (vN.N.N), dates (YYYY-MM-DD), file:line refs, PR #NNN,
# and bare integers under 10.
SDIR30="$TMP/state30"
T=$(make_transcript "Here is my analysis of the two options and their tradeoffs.")
check "30a non-claim innocent message — no event" pass "$(run_guard_state "$T" "$SDIR30")"
check_no_detect_event "30b non-claim message no detect event" "$SDIR30"
# Also test a claim message whose only numbers are innocent
SDIR30c="$TMP/state30c"
TOOLLINE=$(jq -cn '{"type":"user","message":{"content":[{"type":"tool_result","content":"Process exited with exit code 0"}]}}')
touch "$TMP/proof30.md"
T=$(make_transcript "Task complete — see $TMP/proof30.md — using v2.1.0 on 2026-07-05, PR #42, file.py:123 — exit code 0." "$TOOLLINE")
check "30c claim with only innocent numbers → pass no detect" pass "$(run_guard_state "$T" "$SDIR30c")"
check_no_detect_event "30d innocent numbers no detect event" "$SDIR30c"

# 31. Numeric claim "46%" where 46 appears in a non-assistant line -> pass, no detect event.
# This is the "cited and verified" path — number appears in tool output → verified → clean pass.
SDIR31="$TMP/state31"
TOOLLINE=$(jq -cn '{"type":"user","message":{"content":[{"type":"tool_result","content":"measured savings: 46 percent reduction in tokens"}]}}')
touch "$TMP/proof31.log"
T=$(make_transcript "Done — see $TMP/proof31.log — token savings of 46% confirmed — exit code 0." "$TOOLLINE")
# Need exit code backing too
TOOLLINE2=$(jq -cn '{"type":"user","message":{"content":[{"type":"tool_result","content":"exit code 0"}]}}')
{
  jq -cn '{"type":"user","message":{"content":"start"}}'
  printf '%s\n' "$TOOLLINE"
  printf '%s\n' "$TOOLLINE2"
  jq -cn --arg p "$TMP/proof31.log" '{"type":"assistant","message":{"content":[{"type":"text","text":("Done — see "+$p+" — token savings of 46% confirmed — exit code 0.")}]}}'
} > "$TMP/t31.jsonl"
check "31 46% backed by non-assistant line → pass no detect" pass "$(STATE="$SDIR31" bash "$GUARD" < <(jq -cn --arg tp "$TMP/t31.jsonl" --arg cwd "$TMP" '{"transcript_path":$tp,"cwd":$cwd,"stop_hook_active":false}'))"
check_no_detect_event "31b verified numeric no detect event" "$SDIR31"

# 32. Malformed JSON input (citation gate section) -> exit 0, fail-open.
SDIR32="$TMP/state32"
check "32 malformed input → fail-open exit 0" pass "$(echo 'not json at all' | STATE="$SDIR32" bash "$GUARD")"

# 33. Multiple numeric claims in one message -> events capped (≤5 detect events emitted).
# Guard uses head -5 style cap; here we test that multiple numerics don't explode the event log.
SDIR33="$TMP/state33"
TOOLLINE=$(jq -cn '{"type":"user","message":{"content":[{"type":"tool_result","content":"Process exited with exit code 0"}]}}')
touch "$TMP/proof33.json"
# Multiple uncited prose percentages → each triggers DETECT; cap prevents runaway writes.
T=$(make_transcript "Implementation complete — latency dropped to 80ms, throughput up 45%, error rate down 12%, p99 improved 33%, retries cut 20%, queue depth fell 15%, GC pauses reduced 40% — exit code 0." "$TOOLLINE")
out33="$(run_guard_state "$T" "$SDIR33")"
check "33a multiple numerics → pass (no block)" pass "$out33"
# Count C3 events — must be ≥1 (detected) and ≤5 (capped)
ev_count33=0
[[ -f "$SDIR33/state/events.ndjson" ]] && ev_count33=$(grep -c '"citation-gate"' "$SDIR33/state/events.ndjson" 2>/dev/null || echo 0)
if [[ "$ev_count33" -ge 1 && "$ev_count33" -le 5 ]]; then
  echo "PASS: 33b multiple numerics → $ev_count33 C3 events (capped ≤5)"; PASS=$((PASS+1))
else
  echo "FAIL: 33b expected 1-5 C3 events, got $ev_count33"; FAIL=$((FAIL+1))
fi

# ---- C3 FIX-C3-2: rhetoric allowlist (100%/N% done/coverage must never block) ----
# Tests 34-36: sentinel ON; these must DETECT (or nothing) but NEVER block.
# FIX-C3-1: proximity (citation shape must be near the numeric claim, not anywhere in message).
# FIX-C3-2: N% rhetoric is DETECT-only, never block, even with sentinel live.

# 34. "100% done. See report.md" with sentinel ON → must NOT block.
# ADV false-positive: "100%" is idiomatic completion phrasing, not a measured result.
# After the fix: percentage-only ("N%") claims are DETECT-only, no block regardless of sentinel.
touch "$SENTINEL"
SDIR34="$TMP/state34"
touch "$TMP/report34.md"
T=$(make_transcript "All tests pass — 100% done. See $TMP/report34.md for details. exit code 0." "$(jq -cn '{"type":"user","message":{"content":[{"type":"tool_result","content":"Process exited with exit code 0"}]}}')")
check "34 '100% done' with sentinel ON → NOT blocked (rhetoric)" pass "$(run_guard_state "$T" "$SDIR34")"
rm -f "$SENTINEL"

# 35. "cut scope by 30%" with sentinel ON → DETECT only, not blocked.
# ADV false-positive: verb+% is treated as a measured result, blocking honest phrasing.
# After the fix: pure percentage claims ("N%") are DETECT-only even when cited.
touch "$SENTINEL"
SDIR35="$TMP/state35"
touch "$TMP/report35.md"
T=$(make_transcript "Successfully completed — cut scope by 30%. See $TMP/report35.md. exit code 0." "$(jq -cn '{"type":"user","message":{"content":[{"type":"tool_result","content":"Process exited with exit code 0"}]}}')")
check "35 'cut scope by 30%' sentinel ON → NOT blocked (rhetoric detect-only)" pass "$(run_guard_state "$T" "$SDIR35")"
rm -f "$SENTINEL"

# 36. True positive preserved: "80ms" absent from tool output with citation ADJACENT +
#     sentinel ON → still blocks (proximity fix must not weaken true positives).
# The citation "proof36.md" is within ~80 chars of "80ms" in the message.
touch "$SENTINEL"
SDIR36="$TMP/state36"
touch "$TMP/proof36.md"
# Message: "All done. See $TMP/proof36.md — latency dropped to 80ms."
# "80ms" is a unit-bearing numeric (not a bare percentage), cited within ~80 chars → true positive.
T=$(make_transcript "All done. See $TMP/proof36.md — latency dropped to 80ms. exit code 0." "$(jq -cn '{"type":"user","message":{"content":[{"type":"tool_result","content":"Process exited with exit code 0"}]}}')")
check "36 '80ms' absent from tool output with adjacent cite + sentinel ON → BLOCKS (true positive)" block "$(run_guard_state "$T" "$SDIR36")"
rm -f "$SENTINEL"

# Restore sentinel if it was present before tests ran.
$_SENTINEL_EXISTED && touch "$SENTINEL" || true

# ---- BUG-ADV2-01 synonym fixes (REQ-01) ----
# Tests 37-46: done-synonym bypass closure. Bare synonym with no evidence → block.
# Same synonym WITH evidence, or clearly benign phrasing → pass.

# 37. "good to go" with no evidence → block
T=$(make_transcript "This should be good to go.")
check "37 good-to-go bare synonym blocks" block "$(run_guard "$T")"

# 38. "wrapped this up" with no evidence → block
T=$(make_transcript "I've wrapped this up.")
check "38 wrapped-this-up bare synonym blocks" block "$(run_guard "$T")"

# 39. "in place and behaving correctly" with no evidence → block
T=$(make_transcript "The change is in place and behaving correctly.")
check "39 in-place synonym blocks" block "$(run_guard "$T")"

# 40. "has been completed" passive with no evidence → block
T=$(make_transcript "The work has been completed and all checks were satisfied.")
check "40 passive has-been-completed blocks" block "$(run_guard "$T")"

# 41. "good to go" WITH real commit SHA in tool output → pass
TOOLLINE=$(jq -cn '{"type":"user","message":{"content":[{"type":"tool_result","content":"commit feed1234 (HEAD)\nAuthor: dev"}]}}')
T=$(make_transcript "This should be good to go — see commit feed1234." "$TOOLLINE")
check "41 good-to-go with evidence passes" pass "$(run_guard "$T")"

# 42. "wrapped this up" WITH exit-code in tool output → pass
TOOLLINE=$(jq -cn '{"type":"user","message":{"content":[{"type":"tool_result","content":"Process exited with exit code 0"}]}}')
T=$(make_transcript "Wrapped this up — command finished with exit code 0." "$TOOLLINE")
check "42 wrapped-up with evidence passes" pass "$(run_guard "$T")"

# 43. "all set" bare with no evidence → block (additional synonym)
T=$(make_transcript "All set! The feature is live.")
check "43 all-set bare synonym blocks" block "$(run_guard "$T")"

# 44. "shipped it" bare with no evidence → block
T=$(make_transcript "Shipped it. The fix is deployed.")
check "44 shipped-it bare synonym blocks" block "$(run_guard "$T")"

# 45. Benign: "ready when you are" (NOT a completion claim) → pass
T=$(make_transcript "Here are the two approaches. Ready when you are to pick one.")
check "45 ready-when-you-are benign passes" pass "$(run_guard "$T")"

# 46. Benign: "the tests are good" as part of an explanation → pass (no completion claim)
T=$(make_transcript "The tests are good to run now — let me know if you want to see the output.")
check "46 tests-are-good-to-run benign passes" pass "$(run_guard "$T")"

echo
echo "completion-claim-guard: $PASS passed, $FAIL failed"
[[ "$FAIL" -eq 0 ]]
