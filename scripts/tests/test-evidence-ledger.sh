#!/usr/bin/env bash
# ABOUTME: TDD test suite for scripts/evidence-ledger.sh (PostToolUse hook — II.1).
# ABOUTME: Covers: bash test-run extraction, exit-code capture, git SHA capture,
# ABOUTME: Write/Edit file-write token, large output spill, malformed payload fail-open,
# ABOUTME: jq-absent fail-open, non-matching tool no-op, idempotent duplicate suppression.
# ABOUTME: Requires: jq, shasum. Self-contained via mktemp; cleans up on EXIT.

set -uo pipefail

HOOK="${HOOK:-$HOME/.claude/scripts/evidence-ledger.sh}"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
PASS=0; FAIL=0

# ── State dir: isolated per-run via STATE override (emit-event.sh honours STATE env) ──
STATE="$TMP/.agents/claude-governance"
export STATE
export HARNESS_STATE_OVERRIDE="$STATE"
mkdir -p "$STATE/state"

# ── Helpers ───────────────────────────────────────────────────────────────────

# run_hook <json_string>
# Pipe JSON into the hook; capture exit code (always 0 for a fail-open hook).
run_hook() {
  local input="$1"
  printf '%s' "$input" | bash "$HOOK"
}

# events_count <jq_filter>
# Count events.ndjson lines matching the filter.
events_count() {
  local f="$STATE/state/events.ndjson"
  [ -f "$f" ] || { echo 0; return; }
  jq -sr "[ .[] | select($1) ] | length" "$f" 2>/dev/null || echo 0
}

# last_event <jq_expr>
# Extract a field from the most-recently-appended event matching a filter.
last_event() {
  local f="$STATE/state/events.ndjson"
  [ -f "$f" ] || { echo ""; return; }
  jq -rs "[ .[] ] | last | $1" "$f" 2>/dev/null || echo ""
}

# last_matching_event <select_filter> <extract_expr>
last_matching_event() {
  local f="$STATE/state/events.ndjson"
  [ -f "$f" ] || { echo ""; return; }
  jq -rs "[ .[] | select($1) ] | last | $2" "$f" 2>/dev/null || echo ""
}

check() {  # $1 name, $2 condition (true|false), $3 detail
  if [[ "$2" == "true" ]]; then
    echo "PASS: $1"; PASS=$((PASS+1))
  else
    echo "FAIL: $1 — $3"; FAIL=$((FAIL+1))
  fi
}

# ── PostToolUse JSON builders ─────────────────────────────────────────────────

bash_input() {  # $1 command, $2 tool_result (output), $3 exit_code (default 0), $4 tool_use_id
  local cmd="$1" out="$2" ec="${3:-0}" tid="${4:-tid-default}"
  jq -cn \
    --arg cmd "$cmd" \
    --arg out "$out" \
    --argjson ec "$ec" \
    --arg tid "$tid" \
    '{"tool_name":"Bash","tool_use_id":$tid,"tool_input":{"command":$cmd},"tool_result":$out,"tool_result_exit_code":$ec}'
}

write_input() {  # $1 file_path, $2 tool_use_id
  local fp="$1" tid="${2:-tid-write}"
  # Create the file in TMP so stat works
  mkdir -p "$(dirname "$TMP/$fp")" 2>/dev/null || true
  printf 'content' > "$TMP/$fp" 2>/dev/null || true
  jq -cn \
    --arg fp "$TMP/$fp" \
    --arg tid "$tid" \
    '{"tool_name":"Write","tool_use_id":$tid,"tool_input":{"file_path":$fp,"content":"content"},"tool_result":""}'
}

edit_input() {  # $1 file_path, $2 tool_use_id
  local fp="$1" tid="${2:-tid-edit}"
  mkdir -p "$(dirname "$TMP/$fp")" 2>/dev/null || true
  printf 'edited' > "$TMP/$fp" 2>/dev/null || true
  jq -cn \
    --arg fp "$TMP/$fp" \
    --arg tid "$tid" \
    '{"tool_name":"Edit","tool_use_id":$tid,"tool_input":{"file_path":$fp},"tool_result":""}'
}

read_input() {  # $1 file_path, non-matching tool
  jq -cn --arg fp "$1" \
    '{"tool_name":"Read","tool_use_id":"tid-read","tool_input":{"file_path":$fp},"tool_result":"some content"}'
}

# ── Case 1: Bash with test-run output → trust_decision with count token ──────

OUT_1="Test Suite Results
21 passed, 3 failed
Done in 1.4s"
run_hook "$(bash_input "npm test" "$OUT_1" 0 "tc-1")" >/dev/null 2>&1 || true

cnt=$(events_count '.event_type == "trust_decision" and (.payload.claim // "") == "test_count"')
check "1 bash test-run emits trust_decision" "$( [[ "$cnt" -ge 1 ]] && echo true || echo false )" "trust_decision count=$cnt"

ev_ref=$(last_matching_event '.event_type == "trust_decision" and (.payload.claim // "") == "test_count"' '.evidence_ref // ""')
check "1b test-run evidence_ref contains passed count" "$( echo "$ev_ref" | grep -q '21' && echo true || echo false )" "evidence_ref='$ev_ref'"

# ── Case 2: Bash with non-zero exit code captured ─────────────────────────────

run_hook "$(bash_input "make test" "FAIL: assertion error" 1 "tc-2")" >/dev/null 2>&1 || true

cnt=$(events_count '.event_type == "metric" and (.payload.name // "") == "cmd_exit" and (.outcome // "") == "error"')
check "2 bash nonzero exit captured as metric outcome=error" "$( [[ "$cnt" -ge 1 ]] && echo true || echo false )" "metric cmd_exit error count=$cnt"

# ── Case 3: Bash git commit → SHA captured ───────────────────────────────────

GIT_OUT="[main abc1234def56] Add feature foo
 1 file changed, 10 insertions(+)"
run_hook "$(bash_input "git commit -m 'Add feature'" "$GIT_OUT" 0 "tc-3")" >/dev/null 2>&1 || true

ev_ref=$(last_matching_event '.event_type == "metric" and (.payload.classification // "") == "git-commit"' '.evidence_ref // ""')
check "3 git commit SHA captured in evidence_ref" "$( echo "$ev_ref" | grep -qE '[0-9a-f]{7,}' && echo true || echo false )" "evidence_ref='$ev_ref'"

# ── Case 4: Write tool → metric file_write with path+sha16 ──────────────────

run_hook "$(write_input "src/foo.py" "tc-4")" >/dev/null 2>&1 || true

cnt=$(events_count '.event_type == "metric" and (.payload.name // "") == "file_write"')
check "4 Write emits metric file_write" "$( [[ "$cnt" -ge 1 ]] && echo true || echo false )" "file_write metric count=$cnt"

ev_ref=$(last_matching_event '.event_type == "metric" and (.payload.name // "") == "file_write"' '.evidence_ref // ""')
check "4b Write evidence_ref contains file path" "$( echo "$ev_ref" | grep -q 'foo.py' && echo true || echo false )" "evidence_ref='$ev_ref'"

# ── Case 5: Edit tool → metric file_write ────────────────────────────────────

run_hook "$(edit_input "src/bar.ts" "tc-5")" >/dev/null 2>&1 || true

cnt=$(events_count '.event_type == "metric" and (.payload.name // "") == "file_write" and (.payload.tool // "") == "Edit"')
check "5 Edit emits metric file_write with tool=Edit" "$( [[ "$cnt" -ge 1 ]] && echo true || echo false )" "file_write Edit metric count=$cnt"

# ── Case 6: Large bash output spilled to ledger file with pointer ─────────────

LARGE_OUT=$(python3 -c "print('x' * 3000)")
run_hook "$(bash_input "cat bigfile" "$LARGE_OUT" 1 "tc-6")" >/dev/null 2>&1 || true

# Find a .out file in the ledger dir
ledger_dir="$STATE/state/ledger"
spill_count=$(find "$ledger_dir" -name "*.out" 2>/dev/null | wc -l | tr -d ' ')
check "6 large output spilled to ledger/*.out file" "$( [[ "$spill_count" -ge 1 ]] && echo true || echo false )" "spill_count=$spill_count in $ledger_dir"

# The event should carry a ledger_spill key pointing to the file
spill_ref=$(last_matching_event '.event_type == "metric" and (.payload.ledger_spill // "") != ""' '.payload.ledger_spill // ""')
check "6b large output event carries ledger_spill pointer" "$( [[ -n "$spill_ref" ]] && echo true || echo false )" "ledger_spill='$spill_ref'"

# ── Case 7: Malformed payload (non-JSON stdin) → exit 0, no write ─────────────

events_before=$(wc -l < "$STATE/state/events.ndjson" 2>/dev/null || echo 0)
printf 'this is not json at all!!!' | bash "$HOOK" >/dev/null 2>&1
rc=$?
events_after=$(wc -l < "$STATE/state/events.ndjson" 2>/dev/null || echo 0)
check "7 malformed payload exits 0" "$( [[ "$rc" -eq 0 ]] && echo true || echo false )" "rc=$rc"
check "7b malformed payload writes no event" "$( [[ "$events_after" -le "$((events_before))" ]] && echo true || echo false )" "before=$events_before after=$events_after"

# ── Case 8: jq absent → exit 0, no write ─────────────────────────────────────
# Strategy: install a fake jq shim that exits 127 (command not found).
# The hook's "command -v jq" check passes (shim is found) but the shim returns
# nonzero. We need the shim to make `command -v jq` succeed but runtime calls fail.
# Simpler: make a shim that returns 1 on -r/-c flags (actual calls), pass on --version.
# Even simpler: the hook guards with `command -v jq >/dev/null 2>&1 || exit 0`.
# So we need jq to be ABSENT from PATH, not present-but-broken.
# Use a sub-env that has only /bin (has bash, shasum, stat, cat, etc.) but not jq.

events_before=$(wc -l < "$STATE/state/events.ndjson" 2>/dev/null || echo 0)
FAKE_BIN="$TMP/fake_bin"
mkdir -p "$FAKE_BIN"
# Create a jq shim that fails (simulating jq absent for the hook's guard)
# The trick: override PATH so our fake_bin comes first, but put no jq there.
# Use env -i to strip PATH to only system dirs without jq.
# On macOS, jq lives in /usr/bin/jq. Strip that dir from PATH.
_NOJQ_PATH=$(printf '%s' "$PATH" | tr ':' '\n' | while IFS= read -r d; do
  # Keep dirs that don't contain jq
  [[ -x "$d/jq" ]] || printf '%s:' "$d"
done)
_NOJQ_PATH="${_NOJQ_PATH%:}"  # trim trailing colon
# Fall back if stripping fails (e.g. all dirs have jq)
[[ -z "$_NOJQ_PATH" ]] && _NOJQ_PATH="/bin:/usr/local/bin"

printf '%s' '{"tool_name":"Bash","tool_use_id":"tc-8","tool_input":{"command":"ls"},"tool_result":"ok","tool_result_exit_code":0}' \
  | PATH="$_NOJQ_PATH" bash "$HOOK" >/dev/null 2>&1
rc=$?
events_after=$(wc -l < "$STATE/state/events.ndjson" 2>/dev/null || echo 0)
check "8 jq absent exits 0" "$( [[ "$rc" -eq 0 ]] && echo true || echo false )" "rc=$rc"
check "8b jq absent writes no event" "$( [[ "$events_after" -le "$((events_before))" ]] && echo true || echo false )" "before=$events_before after=$events_after"

# ── Case 9: Non-matching tool (Read) → exit 0, no new event ──────────────────

events_before=$(wc -l < "$STATE/state/events.ndjson" 2>/dev/null || echo 0)
run_hook "$(read_input "src/foo.py")" >/dev/null 2>&1
events_after=$(wc -l < "$STATE/state/events.ndjson" 2>/dev/null || echo 0)
check "9 Read tool writes no event" "$( [[ "$events_after" -eq "$events_before" ]] && echo true || echo false )" "before=$events_before after=$events_after"

# ── Case 10: Idempotent — same tool_use_id not duplicated ────────────────────

events_before=$(wc -l < "$STATE/state/events.ndjson" 2>/dev/null || echo 0)
INPUT_IDEM="$(bash_input "echo hi" "hi" 0 "tc-10-idem")"
run_hook "$INPUT_IDEM" >/dev/null 2>&1 || true
run_hook "$INPUT_IDEM" >/dev/null 2>&1 || true
events_after=$(wc -l < "$STATE/state/events.ndjson" 2>/dev/null || echo 0)
delta=$(( events_after - events_before ))
check "10 idempotent: same tool_use_id not duplicated" "$( [[ "$delta" -le 1 ]] && echo true || echo false )" "delta=$delta (want ≤1)"

# ── Case 11: Bash passing test run with variant regex (passing/passing) ────────

OUT_11="  41 passing
  2 pending"
run_hook "$(bash_input "mocha test/" "$OUT_11" 0 "tc-11")" >/dev/null 2>&1 || true

cnt=$(events_count '.event_type == "trust_decision" and (.payload.claim // "") == "test_count" and ((.evidence_ref // "") | test("41"))')
check "11 passing variant (mocha) captured" "$( [[ "$cnt" -ge 1 ]] && echo true || echo false )" "trust_decision with 41 count=$cnt"

# ── Summary ───────────────────────────────────────────────────────────────────

echo ""
echo "evidence-ledger: $PASS passed, $FAIL failed"
[[ "$FAIL" -eq 0 ]]
