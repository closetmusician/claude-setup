#!/usr/bin/env bash
# ABOUTME: VI-6 end-to-end synthetic work-economy test — seam-#2 proof.
# ABOUTME: Proves the full queue lifecycle (enqueued→started→staged→approved) is queryable
# ABOUTME: and that ZERO interactive sessions are blocked by any of it.
# ABOUTME: Uses scratch $STATE + mock lane executor; NEVER real spawns, tokens, or pushes.
# ABOUTME: Also runs a real read-only smoke slice on the live queue and cleans up.
# ABOUTME: Run: bash scripts/tests/test-work-economy-e2e.sh

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Canonical .claude paths — absolute to avoid relative-path breakage
CLAUDE_HOME="${HOME}/.claude"
CLAUDE_SCRIPTS="${CLAUDE_HOME}/scripts"
HARNESS="${CLAUDE_HOME}/bin/harness"
NIGHT_RUNNER="${CLAUDE_SCRIPTS}/night-runner.sh"
MORNING_BRIEF="${CLAUDE_SCRIPTS}/morning-brief.sh"
LIB_DIR="${CLAUDE_SCRIPTS}/lib"
PUSH_GUARD="${CLAUDE_SCRIPTS}/autonomous-push-guard.sh"
SECRET_SCAN="${CLAUDE_SCRIPTS}/autonomous-secret-scan.sh"

# ── Test counters ─────────────────────────────────────────────────────────────
PASS=0
FAIL=0
ERRORS=""
TOTAL_ASSERTIONS=0

_pass() {
  local label="$1"
  printf '  [PASS] %s\n' "$label"
  (( PASS++ )) || true
  (( TOTAL_ASSERTIONS++ )) || true
}

_fail() {
  local label="$1" reason="${2:-}"
  local msg
  msg="$(printf '[FAIL] %s — %s' "$label" "$reason")"
  printf '  %s\n' "$msg"
  (( FAIL++ )) || true
  (( TOTAL_ASSERTIONS++ )) || true
  ERRORS+="  ${msg}"$'\n'
}

_assert_true() {
  # _assert_true <label> <command_returning_0_on_pass>
  local label="$1"; shift
  if "$@" 2>/dev/null; then
    _pass "$label"
  else
    _fail "$label" "condition false"
  fi
}

_assert_count() {
  # _assert_count <label> <min> <max> <actual>
  # actual must be a clean integer (no embedded newlines)
  local label="$1" min="$2" max="$3"
  local actual
  actual="$(printf '%s' "${4:-0}" | tr -d '[:space:]')"
  # Validate it's numeric
  if ! [[ "$actual" =~ ^[0-9]+$ ]]; then
    _fail "$label" "non-numeric count: '$actual'"
    return
  fi
  if (( actual >= min && actual <= max )); then
    _pass "$label (count=${actual})"
  else
    _fail "$label" "count=${actual} not in [${min},${max}]"
  fi
}

_count_grep() {
  # Safely count extended-regex grep matches, returning clean integer.
  # Always reads from a file path (no process substitution — macOS /dev/fd unreliable).
  # Wraps grep in a subshell so pipefail doesn't fire on zero-match (grep exits 1).
  local pattern="$1" file="${2:--}"
  (grep -cE "$pattern" "$file" 2>/dev/null || echo 0) | tr -d '[:space:]'
}

_count_grep_in_str() {
  # Count regex matches inside a string variable; writes to a tmp file to avoid proc-sub.
  # Wraps grep in a subshell so pipefail doesn't fire on zero-match (grep exits 1).
  local pattern="$1" str="$2"
  local tf; tf="$(mktemp /tmp/cgrep-XXXXXX)"
  printf '%s' "$str" > "$tf"
  (grep -cE "$pattern" "$tf" 2>/dev/null || echo 0) | tr -d '[:space:]'
  rm -f "$tf" 2>/dev/null || true
}

# ── Scratch isolated environment ──────────────────────────────────────────────
TMPROOT="$(mktemp -d /tmp/test-work-economy-e2e-XXXXXX)"
REPO="${TMPROOT}/fake-repo"

mkdir -p "$REPO"
# Initialise a real git repo so night-runner worktree commands have something to work with
(cd "$REPO" && git init -q && git commit --allow-empty -m "init" -q 2>/dev/null) || true

export STATE="${TMPROOT}/state"
export QUEUE_DIR="${TMPROOT}/queue"
export EVENTS="${STATE}/state/events.ndjson"

# Morning-brief env overrides
export MORNING_BRIEF_STATE_ROOT="$STATE"
export MORNING_BRIEF_QUEUE_DIR="$QUEUE_DIR"
export MORNING_BRIEF_RUNS_DIR="${STATE}/runs"
export MORNING_BRIEF_OUTPUT_DIR="${TMPROOT}/briefings"
export MORNING_BRIEF_HARNESS="$HARNESS"
export MORNING_BRIEF_NOTIFY_SKIP=1

# harness env overrides
export HARNESS_STATE_OVERRIDE="$STATE"

mkdir -p "${STATE}/state" "${STATE}/runs" "${QUEUE_DIR}" "${TMPROOT}/briefings"

ORIG_PATH="$PATH"

# ── Shared helpers ────────────────────────────────────────────────────────────

_fresh() {
  rm -rf "${QUEUE_DIR:?}/"* 2>/dev/null || true
  rm -rf "${STATE:?}/state/"* 2>/dev/null || true
  rm -rf "${STATE:?}/runs/"* 2>/dev/null || true
  rm -rf "${TMPROOT:?}/briefings/"* 2>/dev/null || true
  rm -f "${STATE}/.AUTONOMOUS_FREEZE" 2>/dev/null || true
  rm -f "${STATE}/night-runner.done" 2>/dev/null || true
  rm -f "${STATE}/night-runner.heartbeat" 2>/dev/null || true
  rm -f "${STATE}/night-runner.log" 2>/dev/null || true
  rm -f "${STATE}/.harness-selfcheck-ok" 2>/dev/null || true
  rm -f "${STATE}/completion-claim-guard.log" 2>/dev/null || true
  rm -f "${STATE}/.night-task-count" 2>/dev/null || true
  mkdir -p "${STATE}/state" "${STATE}/runs" "${QUEUE_DIR}" "${TMPROOT}/briefings"
  export PATH="$ORIG_PATH"
}

# Write a well-formed approved queue task
_make_task() {
  local id="$1"
  local status="${2:-approved}"
  local acceptance_cmd="${3:-true}"
  local fpath="${QUEUE_DIR}/${id}.md"
  cat > "$fpath" <<TASK
---
id: ${id}
repo: ${REPO}
intent: E2E synthetic test task ${id}
priority: normal
acceptance:
  - "${acceptance_cmd}"
max_minutes: 1
model: sonnet
status: ${status}
created: 2026-07-05T00:00:00Z
source: explicit
lane: null
---
Synthetic E2E test task body. This is a mock task, not a real work item.
TASK
  echo "$fpath"
}

# Emit a queue_event directly to the events ndjson (for seeding lifecycle states)
_emit_queue_event() {
  local task_id="$1" state="$2" source_tag="${3:-explicit}" intent="${4:-test task}"
  local ts; ts="$(date -u +%Y-%m-%dT%H:%M:%S.000Z 2>/dev/null || echo "2026-07-05T00:00:00.000Z")"
  local payload
  payload="$(jq -cn \
    --arg task_id "$task_id" \
    --arg state "$state" \
    --arg source "$source_tag" \
    --arg intent "$intent" \
    '{task_id:$task_id, state:$state, source:$source, intent:$intent, lane:null, reason:null}' \
    2>/dev/null)" || payload="{\"task_id\":\"$task_id\",\"state\":\"$state\"}"
  local line
  line="$(jq -cn \
    --arg ts "$ts" \
    --arg event_type "queue_event" \
    --arg source "test-harness" \
    --arg project "test" \
    --arg outcome "ok" \
    --argjson payload "$payload" \
    '{schema:1, ts:$ts, session_id:"test-session", agent_id:null,
      event_type:$event_type, source:$source, project:$project,
      tool:null, skill:null, outcome:$outcome, evidence_ref:null,
      trace_id:null, payload:$payload}' 2>/dev/null)" || line=""
  [[ -n "$line" ]] && printf '%s\n' "$line" >> "$EVENTS"
}

# ── MOCK PATH SETUP ────────────────────────────────────────────────────────────
MOCK_BIN="${TMPROOT}/mock-bin"
mkdir -p "$MOCK_BIN"

# Mock gtimeout: strip the timeout arg and exec the rest
cat > "${MOCK_BIN}/gtimeout" <<'MOCK'
#!/usr/bin/env bash
shift
exec "$@"
MOCK
chmod +x "${MOCK_BIN}/gtimeout"

# Install mock claude per case — writes a success manifest
_install_mock_claude_success() {
  local task_id="$1"
  local repo_path="$2"
  local acceptance_exit="${3:-0}"
  cat > "${MOCK_BIN}/claude" <<MOCK
#!/usr/bin/env bash
# Mock claude for ${task_id} — writes a manifest and exits without any real work
MFILE="\${STATE}/runs/${task_id}.json"
mkdir -p "\$(dirname "\$MFILE")" 2>/dev/null || true
cat > "\$MFILE" <<MANIFEST
{
  "task_id": "${task_id}",
  "status": "done",
  "worktree": "${repo_path}",
  "branch": "wt-night/${task_id}",
  "acceptance": [{"criterion": "true", "exit_code": ${acceptance_exit}}],
  "progress": {
    "completed_criteria": ["true"], "attempted": [], "blockers": [],
    "next_step": "", "scratch_ref": "", "wall_clock_elapsed_s": 2, "resume_count": 0
  }
}
MANIFEST
echo "Mock lane: task done."
exit 0
MOCK
  chmod +x "${MOCK_BIN}/claude"
}

printf '=== test-work-economy-e2e.sh (VI-6) ===\n'
printf 'TMPROOT=%s\n' "$TMPROOT"
printf 'REPO=%s\n' "$REPO"
printf 'STATE=%s\n' "$STATE"
printf 'HARNESS=%s\n' "$HARNESS"
printf '\n'

# =============================================================================
# PART 1: FULL QUEUE LIFECYCLE (enqueued→started→staged→approved)
# =============================================================================
printf '── PART 1: Full lifecycle chain (mocked night-runner) ──────────────────\n'

_fresh
TASK_ID="q-20260705-000001-e2e-smoke"

# ── Step 1: Seed an approved queue task ──────────────────────────────────────
printf '[1] Seeding approved queue task\n'
_make_task "$TASK_ID" "approved" "true" >/dev/null

# Emit enqueued event (normally done by harness queue add)
_emit_queue_event "$TASK_ID" "enqueued" "explicit" "E2E synthetic test task $TASK_ID"

task_file="${QUEUE_DIR}/${TASK_ID}.md"
_assert_true "ASSERT-1: task file written with status=approved" \
  grep -q "^status: approved" "$task_file"

# ── Step 2: Mocked night-runner pass ──────────────────────────────────────────
printf '[2] Running mocked night-runner (mock lane, NEVER real claude)\n'

touch "${STATE}/.harness-selfcheck-ok"
printf 'trust kernel live\n' > "${STATE}/completion-claim-guard.log"

_install_mock_claude_success "$TASK_ID" "$REPO" 0

export PATH="${MOCK_BIN}:${ORIG_PATH}"

NIGHT_OUT="${TMPROOT}/night-runner-e2e.log"
AUTONOMOUS_RUN=1 STATE="$STATE" QUEUE_DIR="$QUEUE_DIR" \
  bash "$NIGHT_RUNNER" >"$NIGHT_OUT" 2>&1
NR_EXIT=$?

export PATH="$ORIG_PATH"
printf '  night-runner exit=%d\n' "$NR_EXIT"

# ── Step 3: Assert transitions in events.ndjson ──────────────────────────────
printf '[3] Asserting queue_event transitions\n'

ENQUEUED_COUNT="$(_count_grep '"state":"enqueued"' "$EVENTS")"
STARTED_COUNT="$(_count_grep '"state":"started"' "$EVENTS")"
STAGED_COUNT="$(_count_grep '"state":"staged"' "$EVENTS")"

_assert_count "ASSERT-2: queue_event{enqueued} present" 1 99 "$ENQUEUED_COUNT"
_assert_count "ASSERT-3: queue_event{started} emitted by night-runner" 1 99 "$STARTED_COUNT"
_assert_count "ASSERT-4: queue_event{staged} emitted after acceptance pass" 1 99 "$STAGED_COUNT"

# ── Step 4: Morning-brief lists staged task ──────────────────────────────────
printf '[4] Running morning-brief (should list staged task)\n'

# Seed a run manifest for morning-brief display
mkdir -p "${STATE}/runs"
cat > "${STATE}/runs/${TASK_ID}.json" <<MANIFEST
{
  "task_id": "${TASK_ID}",
  "intent": "E2E synthetic test task ${TASK_ID}",
  "status": "staged",
  "ts": "2026-07-05T00:00:01Z",
  "acceptance": [{"criterion": "true", "exit_code": 0}]
}
MANIFEST

# Update queue file to staged so morning-brief queue counts include it
sed -i '' "s/^status: .*/status: staged/" "$task_file" 2>/dev/null || \
  sed -i "s/^status: .*/status: staged/" "$task_file" 2>/dev/null || true

MORNING_BRIEF_OUTPUT_DIR="${TMPROOT}/briefings" \
  bash "$MORNING_BRIEF" 2>/dev/null || true

BRIEF_CONTENT="${TMPROOT}/briefings/$(date +%Y-%m-%d).md"
# The task id contains "e2e-smoke" — check for that slug
if [[ -f "$BRIEF_CONTENT" ]]; then
  BRIEF_HAS_TASK="$(_count_grep "e2e-smoke" "$BRIEF_CONTENT")"
else
  BRIEF_HAS_TASK="0"
fi
_assert_count "ASSERT-5: morning-brief lists the staged task" 1 99 "$BRIEF_HAS_TASK"

# ── Step 5: harness queue approve → approved ─────────────────────────────────
printf '[5] harness queue approve → emits queue_event{approved}\n'

HARNESS_STATE_OVERRIDE="$STATE" STATE="$STATE" QUEUE_DIR="$QUEUE_DIR" \
  "$HARNESS" queue approve "$TASK_ID" 2>/dev/null

APPROVED_COUNT="$(_count_grep '"state":"approved"' "$EVENTS")"
_assert_count "ASSERT-6: queue_event{approved} emitted" 1 99 "$APPROVED_COUNT"

# ── Step 6: Full chain queryable ─────────────────────────────────────────────
printf '[6] Full chain queryable via harness query --type queue_event\n'

QUERY_OUT="${TMPROOT}/query-e2e.json"
HARNESS_STATE_OVERRIDE="$STATE" STATE="$STATE" \
  "$HARNESS" query --type queue_event --limit 50 >"$QUERY_OUT" 2>&1 || true

STATES_FOUND=0
for state in enqueued started staged approved; do
  if grep -q "\"${state}\"" "$QUERY_OUT" 2>/dev/null; then
    (( STATES_FOUND++ )) || true
  fi
done

_assert_count "ASSERT-7: all 4 lifecycle states queryable (enqueued/started/staged/approved)" \
  4 4 "$STATES_FOUND"

printf '\n'

# =============================================================================
# PART 2: SAFETY INVARIANTS
# =============================================================================
printf '── PART 2: Safety invariants ───────────────────────────────────────────\n'

# ── Invariant 1: ZERO git merges/pushes in night-runner output ───────────────
printf '[I1] No git merge or push in night-runner log\n'
MERGE_COUNT="$(_count_grep '\bgit merge\b\|\bgit push\b' "$NIGHT_OUT")"
_assert_count "ASSERT-8: 0 git merge/push in night-runner log" 0 0 "$MERGE_COUNT"

# ── Invariant 2: Lane was dispatched (registered then deregistered) ──────────
printf '[I2] Lane dispatch was logged (autonomous-registry registration path ran)\n'
DISPATCH_COUNT="$(_count_grep 'Dispatching lane' "$NIGHT_OUT")"
_assert_count "ASSERT-9: lane-1 dispatched" 1 99 "$DISPATCH_COUNT"

# ── Invariant 3: Budget never exceeded 3 ─────────────────────────────────────
printf '[I3] Budget counter ≤ 3 (cap not exceeded)\n'
TASK_COUNT_FINAL="$(cat "${STATE}/.night-task-count" 2>/dev/null | tr -d '[:space:]' || echo "0")"
_assert_count "ASSERT-10: budget counter ≤ 3" 1 3 "$TASK_COUNT_FINAL"

# ── Invariant 4: Push-guard denies git merge in AUTONOMOUS_RUN context ────────
# git merge is hard-denied regardless of remote — cleanest positive-control test.
printf '[I4] Push-guard: denies git merge when AUTONOMOUS_RUN=1 and session is registered\n'

REG_STATE="${TMPROOT}/pushguard-state"
mkdir -p "${REG_STATE}"
PUSHGUARD_SESSION="test-autonomous-lane-99"
jq -cn --arg lid "$PUSHGUARD_SESSION" \
  '[{lane_id: $lid, task_id: "test-task", session_id: $lid,
     started_at: "2026-07-05T00:00:00Z", status: "active",
     token: "test-token", meta: {}}]' \
  > "${REG_STATE}/autonomous-registry.json" 2>/dev/null

# Write payload to temp file (stdin consumed by registration check then by INPUT=$(cat))
PAYLOAD_FILE="${TMPROOT}/push-payload.json"
jq -cn \
  --arg sid "$PUSHGUARD_SESSION" \
  --arg cmd "git merge feature-branch" \
  '{session_id: $sid, tool_input: {command: $cmd}}' \
  > "$PAYLOAD_FILE" 2>/dev/null

PUSH_GUARD_OUT="$(AUTONOMOUS_RUN=1 \
  SESSION_ID="$PUSHGUARD_SESSION" \
  STATE="$REG_STATE" \
  HARNESS_STATE_OVERRIDE="$REG_STATE" \
  bash "$PUSH_GUARD" < "$PAYLOAD_FILE" 2>/dev/null)"

PUSH_DENIED="$(_count_grep_in_str '"permissionDecision"[[:space:]]*:[[:space:]]*"deny"' "$PUSH_GUARD_OUT")"
_assert_count "ASSERT-11: push-guard denies git merge in AUTONOMOUS_RUN context" \
  1 99 "$PUSH_DENIED"

# ── Invariant 5: Kill-switch halts dispatch before any lanes start ────────────
printf '[I5] Kill-switch: AUTONOMOUS_FREEZE sentinel halts runner before dispatch\n'

_fresh
TASK_KS="q-20260705-000010-ks-test"
_make_task "$TASK_KS" "approved" "true" >/dev/null
touch "${STATE}/.harness-selfcheck-ok"
printf 'trust kernel live\n' > "${STATE}/completion-claim-guard.log"
# Trip kill-switch BEFORE runner starts
touch "${STATE}/.AUTONOMOUS_FREEZE"

export PATH="${MOCK_BIN}:${ORIG_PATH}"
KS_OUT="${TMPROOT}/ks-test.log"
AUTONOMOUS_RUN=1 STATE="$STATE" QUEUE_DIR="$QUEUE_DIR" \
  bash "$NIGHT_RUNNER" >"$KS_OUT" 2>&1 || true
export PATH="$ORIG_PATH"

KS_DISPATCHED="$(_count_grep 'Dispatching lane' "$KS_OUT")"
KS_LOGGED="$(_count_grep 'kill.switch|AUTONOMOUS_FREEZE|KILL.SWITCH|kill_switch' "$KS_OUT")"
_assert_count "ASSERT-12: kill-switch prevents dispatch (0 lanes started)" 0 0 "$KS_DISPATCHED"
_assert_count "ASSERT-13: kill-switch activation logged" 1 99 "$KS_LOGGED"

printf '\n'

# =============================================================================
# PART 3: INTERACTIVE NON-BLOCKING
# =============================================================================
printf '── PART 3: Interactive non-blocking (no AUTONOMOUS_RUN) ────────────────\n'

unset AUTONOMOUS_RUN 2>/dev/null || true

# ── Check 1: push-guard exits 0 for interactive session ──────────────────────
printf '[NB1] push-guard exits 0 for interactive (no AUTONOMOUS_RUN)\n'

INTER_PAYLOAD_FILE="${TMPROOT}/inter-payload.json"
jq -cn \
  --arg sid "interactive-session-abc" \
  --arg cmd "git push origin main" \
  '{session_id: $sid, tool_input: {command: $cmd}}' \
  > "$INTER_PAYLOAD_FILE" 2>/dev/null

INTER_OUT_FILE="${TMPROOT}/inter-out.json"
bash "$PUSH_GUARD" < "$INTER_PAYLOAD_FILE" > "$INTER_OUT_FILE" 2>/dev/null
INTER_RC=$?

INTER_DENIED="$(_count_grep '"permissionDecision"[[:space:]]*:[[:space:]]*"deny"' "$INTER_OUT_FILE")"
_assert_count "ASSERT-14: push-guard does NOT deny interactive push (no AUTONOMOUS_RUN)" \
  0 0 "$INTER_DENIED"
_assert_count "ASSERT-15: push-guard exits 0 for interactive" 0 0 "$INTER_RC"

# ── Check 2: secret-scan exits 0 for interactive ─────────────────────────────
printf '[NB2] secret-scan exits 0 for interactive (no AUTONOMOUS_RUN)\n'

SECRET_OUT="$(bash "$SECRET_SCAN" < "$INTER_PAYLOAD_FILE" 2>/dev/null)"
SECRET_RC=$?
_assert_count "ASSERT-16: secret-scan exits 0 for interactive (no AUTONOMOUS_RUN)" 0 0 "$SECRET_RC"

printf '\n'

# =============================================================================
# PART 4: REAL READ-ONLY SMOKE SLICE on the actual live queue
# =============================================================================
printf '── PART 4: Real read-only smoke slice (live queue) ─────────────────────\n'
printf '  Using REAL ~/.claude/queue — seed, query, remove\n'

# Run with NO env overrides so it touches the real queue and state
unset STATE HARNESS_STATE_OVERRIDE QUEUE_DIR EVENTS 2>/dev/null || true

REAL_ADD_OUT="$(bash "$HARNESS" queue add "e2e smoke seed" 2>&1)"
REAL_ADD_RC=$?
printf '  Add output: %s (rc=%d)\n' "$REAL_ADD_OUT" "$REAL_ADD_RC"

REAL_TASK_ID="$(printf '%s' "$REAL_ADD_OUT" | grep -oE 'q-[0-9]+-[0-9]+-[a-z0-9-]+' | head -1)"
printf '  Task id: %s\n' "${REAL_TASK_ID:-<not-found>}"

# ls shows it enqueued
if [[ -n "${REAL_TASK_ID:-}" ]]; then
  REAL_LS_OUT="$(bash "$HARNESS" queue ls 2>&1)"
  if printf '%s' "$REAL_LS_OUT" | grep -q "$REAL_TASK_ID" 2>/dev/null; then
    _pass "ASSERT-17: real queue ls shows the seeded task as enqueued"
  else
    _fail "ASSERT-17: real queue ls" "task $REAL_TASK_ID not in ls output"
  fi

  # query shows the enqueued event in the real spine
  REAL_QUERY_OUT="$(bash "$HARNESS" query --type queue_event --limit 20 2>&1)"
  if printf '%s' "$REAL_QUERY_OUT" | grep -q "$REAL_TASK_ID" 2>/dev/null; then
    _pass "ASSERT-18: harness query --type queue_event shows real enqueued event"
  else
    _fail "ASSERT-18: harness query" "task $REAL_TASK_ID not in query output"
  fi

  # Clean up: remove the seed task
  REAL_RM_OUT="$(bash "$HARNESS" queue rm "$REAL_TASK_ID" 2>&1)"
  REAL_RM_RC=$?
  printf '  Cleanup: %s (rc=%d)\n' "$REAL_RM_OUT" "$REAL_RM_RC"
  _assert_count "ASSERT-19: harness queue rm cleaned up the seed task" 0 0 "$REAL_RM_RC"

  # Verify queue is clean
  REAL_LS_AFTER="$(bash "$HARNESS" queue ls 2>&1)"
  if ! printf '%s' "$REAL_LS_AFTER" | grep -q "$REAL_TASK_ID" 2>/dev/null; then
    _pass "ASSERT-20: real queue clean after rm"
  else
    _fail "ASSERT-20: queue clean" "task still visible after rm"
  fi
else
  _fail "ASSERT-17: real queue ls" "no task id captured"
  _fail "ASSERT-18: harness query" "skipped (no task id)"
  _fail "ASSERT-19: harness queue rm" "skipped (no task id)"
  _fail "ASSERT-20: queue clean" "skipped (no task id)"
fi

printf '\n'

# =============================================================================
# SUMMARY
# =============================================================================
printf '══════════════════════════════════════════════════════════════════\n'
printf '  RESULTS: %d PASS / %d FAIL / %d total assertions\n' "$PASS" "$FAIL" "$TOTAL_ASSERTIONS"
if [[ "$FAIL" -eq 0 ]]; then
  printf '  STATUS: GREEN — all VI-6 invariants satisfied\n'
else
  printf '  STATUS: RED — %d assertion(s) failed:\n' "$FAIL"
  printf '%s' "$ERRORS"
fi
printf '══════════════════════════════════════════════════════════════════\n'

# Cleanup scratch dirs (real queue already cleaned above)
rm -rf "${TMPROOT}" 2>/dev/null || true

if [[ "$FAIL" -eq 0 ]]; then
  exit 0
else
  exit 1
fi
