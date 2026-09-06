#!/usr/bin/env bash
# ABOUTME: TDD test suite for VI-5 morning-brief.sh.
# ABOUTME: ≥5 cases: overnight run listed; FROZEN banner when sentinel present;
# ABOUTME: queue depth reported; approve flow emits queue_event{approved}; graceful empty night.
# ABOUTME: Run: bash scripts/tests/test-morning-brief.sh — RED before impl, GREEN after.
# ABOUTME: Isolation: HARNESS_STATE_OVERRIDE + QUEUE_DIR + temp dirs; never touches real state.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BRIEF="${SCRIPT_DIR}/../morning-brief.sh"
HARNESS="${SCRIPT_DIR}/../../bin/harness"

# ── Isolated temp environment ─────────────────────────────────────────────────
TMPROOT="$(mktemp -d /tmp/test-morning-brief-XXXXXX)"
export HARNESS_STATE_OVERRIDE="$TMPROOT/state"
export STATE="$TMPROOT/state"
export QUEUE_DIR="$TMPROOT/queue"
export EVENTS="$STATE/state/events.ndjson"
# Morning-brief respects these overrides when calling harness
export MORNING_BRIEF_STATE_ROOT="$TMPROOT/state"
export MORNING_BRIEF_QUEUE_DIR="$TMPROOT/queue"
export MORNING_BRIEF_RUNS_DIR="$TMPROOT/state/runs"
export MORNING_BRIEF_OUTPUT_DIR="$TMPROOT/briefings"
export MORNING_BRIEF_NOTIFY_SKIP=1   # suppress terminal-notifier in tests

mkdir -p "$STATE/state" "$QUEUE_DIR" "$TMPROOT/state/runs" "$TMPROOT/briefings"

PASS=0
FAIL=0

_pass() { printf '  PASS: %s\n' "$1"; (( PASS++ )) || true; }
_fail() { printf '  FAIL: %s — %s\n' "$1" "$2"; (( FAIL++ )) || true; }

_fresh() {
  rm -rf "${QUEUE_DIR:?}/"* 2>/dev/null || true
  rm -rf "${TMPROOT:?}/state/runs/"* 2>/dev/null || true
  rm -rf "${TMPROOT:?}/briefings/"* 2>/dev/null || true
  rm -f "$EVENTS" 2>/dev/null || true
  rm -f "$STATE/.AUTONOMOUS_FREEZE" 2>/dev/null || true
  rm -f "$STATE/night-runner.done" 2>/dev/null || true
  rm -f "$STATE/night-runner.heartbeat" 2>/dev/null || true
  mkdir -p "$STATE/state" "$QUEUE_DIR" "$TMPROOT/state/runs" "$TMPROOT/briefings"
}

# Seed a queue_event JSON line (minimal run manifest as a queue_event)
_seed_run_manifest() {
  local id="$1" status="${2:-staged}" intent="${3:-Fix emit latency}"
  local ts; ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  mkdir -p "$TMPROOT/state/runs"
  cat > "$TMPROOT/state/runs/${id}.json" <<EOF
{
  "task_id": "${id}",
  "intent": "${intent}",
  "status": "${status}",
  "ts": "${ts}",
  "acceptance": [
    {"criterion": "bash scripts/tests/test-emit-event.sh exits 0", "exit_code": 0}
  ]
}
EOF
}

# Seed a queue task file
_seed_queue_task() {
  local id="$1" qstatus="${2:-enqueued}" intent="${3:-Test task}"
  local ts; ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  cat > "${QUEUE_DIR}/${id}.md" <<EOF
---
id: ${id}
repo: ${HOME}/.claude
intent: ${intent}
priority: normal
acceptance:
  - "bash scripts/tests/test-x.sh exits 0"
max_minutes: 45
model: sonnet
status: ${qstatus}
created: ${ts}
source: explicit
lane: null
---
Test task body.
EOF
}

printf '=== test-morning-brief.sh (VI-5) ===\n'
printf 'BRIEF=%s\n' "$BRIEF"

# ──────────────────────────────────────────────────────────────────────────────
# Case 1: Briefing lists last night's run (seed a queue_event history / manifest)
# Oracle: brief output contains the task id
# ──────────────────────────────────────────────────────────────────────────────
_fresh
_seed_run_manifest "q-20260704-220000-fix-emit-latency" "staged" "Fix emit latency regression"

out="$(bash "$BRIEF" 2>&1)"
if echo "$out" | grep -q "q-20260704-220000-fix-emit-latency"; then
  _pass "Case 1: overnight run task id appears in brief"
else
  _fail "Case 1: overnight run task id appears in brief" "got: $(echo "$out" | head -5)"
fi

# ──────────────────────────────────────────────────────────────────────────────
# Case 2: FROZEN banner appears when sentinel present
# Oracle: brief output contains "FROZEN" and how-to-clear instructions
# ──────────────────────────────────────────────────────────────────────────────
_fresh
echo "[2026-07-04T23:37:00Z] trigger=quota reason=rate-limit" > "$STATE/.AUTONOMOUS_FREEZE"

out="$(bash "$BRIEF" 2>&1)"
if echo "$out" | grep -qi "FROZEN\|AUTONOMOUS_FREEZE"; then
  _pass "Case 2: FROZEN banner visible when sentinel present"
else
  _fail "Case 2: FROZEN banner visible when sentinel present" "got: $(echo "$out" | head -5)"
fi

if echo "$out" | grep -qi "clear-freeze\|harness queue clear"; then
  _pass "Case 2b: FROZEN banner includes how-to-clear instructions"
else
  _fail "Case 2b: FROZEN banner includes how-to-clear instructions" "got: $(echo "$out" | grep -i "freeze\|clear" | head -3)"
fi

# ──────────────────────────────────────────────────────────────────────────────
# Case 3: Queue depth is reported (enqueued/staged counts)
# Oracle: brief output contains at least one queue status count
# ──────────────────────────────────────────────────────────────────────────────
_fresh
_seed_queue_task "q-20260705-010000-task-a" "enqueued" "Task A"
_seed_queue_task "q-20260705-010001-task-b" "staged"   "Task B"

out="$(bash "$BRIEF" 2>&1)"
if echo "$out" | grep -qiE "queue|enqueued|staged|depth|task"; then
  _pass "Case 3: queue depth/status section present in brief"
else
  _fail "Case 3: queue depth/status section present in brief" "got: $(echo "$out" | head -10)"
fi

# ──────────────────────────────────────────────────────────────────────────────
# Case 4: Approve flow — harness queue approve <id> emits queue_event{approved}
# Oracle: after approve, queue file status is "approved" and event present
# ──────────────────────────────────────────────────────────────────────────────
_fresh
_seed_queue_task "q-20260705-020000-staged-task" "staged" "Staged task"
mkdir -p "$STATE/state"
touch "$STATE/state/events.ndjson"

"$HARNESS" queue approve "q-20260705-020000-staged-task" 2>/dev/null || true

status="$(grep '^status:' "${QUEUE_DIR}/q-20260705-020000-staged-task.md" 2>/dev/null | head -1 | sed 's/status:[[:space:]]*//' | tr -d '[:space:]')"
if [[ "$status" == "approved" ]]; then
  _pass "Case 4: harness queue approve sets status=approved"
else
  _fail "Case 4: harness queue approve sets status=approved" "status=$status"
fi

if [ -f "$STATE/state/events.ndjson" ] && grep -q '"approved"' "$STATE/state/events.ndjson" 2>/dev/null; then
  _pass "Case 4b: approve emits queue_event with state=approved"
else
  _fail "Case 4b: approve emits queue_event with state=approved" "events: $(cat "$STATE/state/events.ndjson" 2>/dev/null | tail -2)"
fi

# ──────────────────────────────────────────────────────────────────────────────
# Case 5: Graceful when no runs (empty-night message, no crash)
# Oracle: brief exits 0 and contains an empty-night signal
# ──────────────────────────────────────────────────────────────────────────────
_fresh

out="$(bash "$BRIEF" 2>&1)"
rc=$?
if [[ "$rc" -eq 0 ]]; then
  _pass "Case 5: brief exits 0 with empty queue/no runs"
else
  _fail "Case 5: brief exits 0 with empty queue/no runs" "exit_code=$rc"
fi

if echo "$out" | grep -qiE "empty|quiet|no runs|no tasks|nothing"; then
  _pass "Case 5b: empty-night message present in brief"
else
  _fail "Case 5b: empty-night message present in brief" "got: $(echo "$out" | head -5)"
fi

# ──────────────────────────────────────────────────────────────────────────────
# Case 6: Brief renders staged patches section from harness brief
# Oracle: brief output contains "STAGED" or approval action instructions
# ──────────────────────────────────────────────────────────────────────────────
_fresh
_seed_run_manifest "q-20260704-230000-patch-task" "staged" "Apply flywheel patch"

out="$(bash "$BRIEF" 2>&1)"
if echo "$out" | grep -qiE "staged|approve|reject|harness queue"; then
  _pass "Case 6: staged-items approval actions visible in brief"
else
  _fail "Case 6: staged-items approval actions visible in brief" "got: $(echo "$out" | grep -iE 'staged|approve|queue' | head -3)"
fi

# ──────────────────────────────────────────────────────────────────────────────
# Case 7: Honest manifest (status=done, all acceptance exit_code=0) → "done"
# Oracle: brief prints "done", NOT "SUSPECT" / "FAILED" / "MISMATCH"
# RED against code that trusts self-reported status; GREEN after re-derivation fix
# ──────────────────────────────────────────────────────────────────────────────
_fresh
cat > "$TMPROOT/state/runs/honest-task.json" <<'EOF'
{
  "task_id": "honest-task",
  "intent": "A real honest run",
  "status": "done",
  "ts": "2026-07-06T03:00:00Z",
  "acceptance": [
    {"criterion": "npm test", "exit_code": 0},
    {"criterion": "lint passes", "exit_code": 0}
  ]
}
EOF

out="$(bash "$BRIEF" 2>&1)"
if echo "$out" | grep -qiE "^Status.*done" && ! echo "$out" | grep -qiE "SUSPECT|MISMATCH|FAILED"; then
  _pass "Case 7: honest manifest (all exit_code=0) shows 'done', no false alarm"
else
  _fail "Case 7: honest manifest shows 'done', no false alarm" "got: $(echo "$out" | grep -i 'status\|SUSPECT\|MISMATCH' | head -5)"
fi

# ──────────────────────────────────────────────────────────────────────────────
# Case 8: Lying manifest (status=done, acceptance exit_code=1) → SUSPECT/FAILED
# Oracle: brief prints SUSPECT/MISMATCH, NOT "done" as-is — this is the BUG-VI-03 regression test
# RED against old code (which trusts manifest.status), GREEN after re-derivation fix
# ──────────────────────────────────────────────────────────────────────────────
_fresh
cat > "$TMPROOT/state/runs/lying-task.json" <<'EOF'
{
  "task_id": "lying-task",
  "intent": "Claims done but tests failed",
  "status": "done",
  "ts": "2026-07-06T04:00:00Z",
  "acceptance": [
    {"criterion": "npm test", "exit_code": 1}
  ]
}
EOF

out="$(bash "$BRIEF" 2>&1)"
if echo "$out" | grep -qiE "SUSPECT|MISMATCH|FAILED"; then
  _pass "Case 8: lying manifest (exit_code=1) flagged as SUSPECT/MISMATCH — NOT laundered as 'done'"
else
  _fail "Case 8: lying manifest (exit_code=1) flagged as SUSPECT/MISMATCH" "got: $(echo "$out" | grep -i 'status\|suspect\|mismatch\|done' | head -5)"
fi

# Confirm the lying manifest does NOT print a bare "Status : done" (the launder)
if ! echo "$out" | grep -Eq '^Status[[:space:]]*:[[:space:]]*done[[:space:]]*$'; then
  _pass "Case 8b: lying manifest does not show bare 'Status : done'"
else
  _fail "Case 8b: lying manifest does not show bare 'Status : done'" "got: $(echo "$out" | grep -i 'status' | head -3)"
fi

# ──────────────────────────────────────────────────────────────────────────────
# Cleanup
# ──────────────────────────────────────────────────────────────────────────────
rm -rf "${TMPROOT:?}" 2>/dev/null || true

printf '\n=== RESULTS: %d passed, %d failed ===\n' "$PASS" "$FAIL"
[[ "$FAIL" -eq 0 ]]
