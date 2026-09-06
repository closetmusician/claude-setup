#!/usr/bin/env bash
# ABOUTME: TDD test suite for VI-1 queue storage schema + VI-2 harness queue CLI.
# ABOUTME: ≥10 cases: add validates + emits queue_event{enqueued}; backlog-auto rejected;
# ABOUTME: ls lists; approve emits approved; reject emits rejected; rm removes; show displays;
# ABOUTME: --from-inbox tags source:loop-inbox; explicit tags source:explicit; clear-freeze works.
# ABOUTME: Run: bash scripts/tests/test-harness-queue.sh — RED before impl, GREEN after.
# ABOUTME: Isolation: HARNESS_STATE_OVERRIDE + temp queue dir; never touches real ~/.claude/queue.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HARNESS="${SCRIPT_DIR}/../../bin/harness"
VALIDATE_LIB="${SCRIPT_DIR}/../lib/queue-validate.sh"
EMIT_LIB="${SCRIPT_DIR}/../lib/emit-event.sh"
KS_LIB="${SCRIPT_DIR}/../lib/kill-switch.sh"

# ── Isolated temp dirs (never the real ones) ─────────────────────────────────
TMPROOT="$(mktemp -d /tmp/test-harness-queue-XXXXXX)"
export HARNESS_STATE_OVERRIDE="$TMPROOT/state"
export STATE="$TMPROOT/state"
export QUEUE_DIR="$TMPROOT/queue"
export EVENTS="$STATE/state/events.ndjson"
mkdir -p "$STATE/state" "$QUEUE_DIR"

PASS=0
FAIL=0

_pass() { printf '  PASS: %s\n' "$1"; (( PASS++ )) || true; }
_fail() { printf '  FAIL: %s — %s\n' "$1" "$2"; (( FAIL++ )) || true; }

_fresh() {
  # Reset queue dir and events between cases
  rm -rf "${QUEUE_DIR:?}/"* 2>/dev/null || true
  rm -f "$EVENTS" 2>/dev/null || true
  rm -rf "$STATE/state/.events.lock.d" 2>/dev/null || true
  rm -f "$STATE/.AUTONOMOUS_FREEZE" 2>/dev/null || true
  mkdir -p "$STATE/state" "$QUEUE_DIR"
}

_event_has() {
  # Check that events.ndjson contains a queue_event with a given field value.
  # Usage: _event_has state enqueued
  local field="$1" value="$2"
  [ -f "$EVENTS" ] && grep -q "\"${field}\":\"${value}\"" "$EVENTS" 2>/dev/null
}

_queue_count() {
  find "$QUEUE_DIR" -name 'q-*.md' 2>/dev/null | wc -l | tr -d ' '
}

_queue_first_id() {
  # Return the id (filename sans .md) of the first queue file found.
  local f
  f="$(find "$QUEUE_DIR" -name 'q-*.md' 2>/dev/null | sort | head -1)"
  [ -n "$f" ] && basename "$f" .md || echo ""
}

printf '=== test-harness-queue.sh (VI-1 + VI-2) ===\n'
printf 'HARNESS=%s\n' "$HARNESS"
printf 'VALIDATE_LIB=%s\n' "$VALIDATE_LIB"
printf 'QUEUE_DIR=%s\n' "$QUEUE_DIR"
printf 'STATE=%s\n' "$STATE"
printf '\n'

# ─────────────────────────────────────────────────────────────────────────────
# Case 1: queue-validate.sh validates a well-formed task and returns 0
# ─────────────────────────────────────────────────────────────────────────────
printf '[1] queue-validate: valid frontmatter returns 0\n'
_fresh
VALID_TASK="$TMPROOT/valid-task.md"
cat > "$VALID_TASK" <<'TASK'
---
id: q-20260704-120000-test-task
repo: $HOME/.claude
intent: Fix the test harness latency regression
priority: normal
acceptance:
  - "bash scripts/tests/test-emit-event.sh exits 0"
max_minutes: 30
model: sonnet
status: enqueued
created: 2026-07-04T12:00:00Z
source: explicit
lane: null
---
Free-form context for this task.
TASK
if bash "$VALIDATE_LIB" "$VALID_TASK" 2>/dev/null; then
  _pass "valid task returns 0"
else
  _fail "valid task" "queue-validate.sh returned nonzero for a valid task"
fi

# ─────────────────────────────────────────────────────────────────────────────
# Case 2: HARD-REJECT — source:backlog-auto is FORBIDDEN
# ─────────────────────────────────────────────────────────────────────────────
printf '[2] queue-validate: source:backlog-auto is rejected\n'
_fresh
BACKLOG_TASK="$TMPROOT/backlog-task.md"
cat > "$BACKLOG_TASK" <<'TASK'
---
id: q-20260704-120001-backlog-task
repo: $HOME/.claude
intent: Auto-ingested backlog task that must be rejected
priority: normal
acceptance:
  - "bash some-test.sh exits 0"
max_minutes: 30
model: sonnet
status: enqueued
created: 2026-07-04T12:00:01Z
source: backlog-auto
lane: null
---
This should be rejected.
TASK
if bash "$VALIDATE_LIB" "$BACKLOG_TASK" 2>/dev/null; then
  _fail "backlog-auto" "queue-validate.sh should have REJECTED source:backlog-auto but returned 0"
else
  _pass "source:backlog-auto correctly rejected (exit nonzero)"
fi

# ─────────────────────────────────────────────────────────────────────────────
# Case 3: harness queue add validates + enqueues + emits queue_event{enqueued}
# ─────────────────────────────────────────────────────────────────────────────
printf '[3] harness queue add: validates, creates file, emits queue_event{enqueued}\n'
_fresh
ADD_OUT="$(QUEUE_DIR="$QUEUE_DIR" "$HARNESS" queue add "Test seed task for VI-1 oracle" 2>&1)" || true
COUNT="$(_queue_count)"
if [[ "$COUNT" -ge 1 ]]; then
  _pass "queue file created (found $COUNT file)"
else
  _fail "add creates queue file" "expected ≥1 file in $QUEUE_DIR, got $COUNT. Output: $ADD_OUT"
fi
if _event_has "state" "enqueued"; then
  _pass "queue_event{state:enqueued} emitted to spine"
else
  _fail "queue_event emitted" "no queue_event with state:enqueued in $EVENTS. Output: $ADD_OUT"
fi

# ─────────────────────────────────────────────────────────────────────────────
# Case 4: explicit add tags source:explicit in the queue file
# ─────────────────────────────────────────────────────────────────────────────
printf '[4] harness queue add: explicit source tagging (source:explicit)\n'
_fresh
QUEUE_DIR="$QUEUE_DIR" "$HARNESS" queue add "Explicit source tag test task" 2>/dev/null || true
QF="$(find "$QUEUE_DIR" -name 'q-*.md' 2>/dev/null | sort | head -1)"
if [[ -n "$QF" ]] && grep -q 'source: explicit' "$QF" 2>/dev/null; then
  _pass "queue file has source: explicit"
else
  _fail "source:explicit tagged" "queue file missing 'source: explicit'. File: $QF"
fi

# ─────────────────────────────────────────────────────────────────────────────
# Case 5: backlog-auto add via harness queue add --source backlog-auto is rejected
# ─────────────────────────────────────────────────────────────────────────────
printf '[5] harness queue add --source backlog-auto: must be rejected\n'
_fresh
REJECT_OUT="$(QUEUE_DIR="$QUEUE_DIR" "$HARNESS" queue add --source backlog-auto "Should be rejected" 2>&1)" || true
COUNT="$(_queue_count)"
if [[ "$COUNT" -eq 0 ]]; then
  _pass "backlog-auto add rejected — no file created"
else
  _fail "backlog-auto rejected by CLI" "expected 0 files, got $COUNT. Output: $REJECT_OUT"
fi

# ─────────────────────────────────────────────────────────────────────────────
# Case 6: harness queue ls lists enqueued tasks
# ─────────────────────────────────────────────────────────────────────────────
printf '[6] harness queue ls: lists tasks\n'
_fresh
QUEUE_DIR="$QUEUE_DIR" "$HARNESS" queue add "Task alpha for ls test" 2>/dev/null || true
QUEUE_DIR="$QUEUE_DIR" "$HARNESS" queue add "Task beta for ls test" 2>/dev/null || true
LS_OUT="$(QUEUE_DIR="$QUEUE_DIR" "$HARNESS" queue ls 2>&1)" || true
if echo "$LS_OUT" | grep -q 'alpha\|beta\|enqueued\|q-'; then
  _pass "ls output contains queue entries"
else
  _fail "ls lists tasks" "ls output did not show expected tasks. Output: $LS_OUT"
fi

# ─────────────────────────────────────────────────────────────────────────────
# Case 7: harness queue approve <id> emits queue_event{approved}
# ─────────────────────────────────────────────────────────────────────────────
printf '[7] harness queue approve: emits queue_event{approved}\n'
_fresh
QUEUE_DIR="$QUEUE_DIR" "$HARNESS" queue add "Task to approve" 2>/dev/null || true
TASK_ID="$(_queue_first_id)"
if [[ -z "$TASK_ID" ]]; then
  _fail "approve — setup" "no task id found after add"
else
  QUEUE_DIR="$QUEUE_DIR" "$HARNESS" queue approve "$TASK_ID" 2>/dev/null || true
  if _event_has "state" "approved"; then
    _pass "queue_event{state:approved} emitted"
  else
    _fail "approve emits approved event" "no queue_event with state:approved in $EVENTS"
  fi
fi

# ─────────────────────────────────────────────────────────────────────────────
# Case 8: harness queue reject <id> emits queue_event{rejected}
# ─────────────────────────────────────────────────────────────────────────────
printf '[8] harness queue reject: emits queue_event{rejected}\n'
_fresh
QUEUE_DIR="$QUEUE_DIR" "$HARNESS" queue add "Task to reject" 2>/dev/null || true
TASK_ID="$(_queue_first_id)"
if [[ -z "$TASK_ID" ]]; then
  _fail "reject — setup" "no task id found after add"
else
  QUEUE_DIR="$QUEUE_DIR" "$HARNESS" queue reject "$TASK_ID" 2>/dev/null || true
  if _event_has "state" "rejected"; then
    _pass "queue_event{state:rejected} emitted"
  else
    _fail "reject emits rejected event" "no queue_event with state:rejected in $EVENTS"
  fi
fi

# ─────────────────────────────────────────────────────────────────────────────
# Case 9: harness queue rm <id> removes the task file
# ─────────────────────────────────────────────────────────────────────────────
printf '[9] harness queue rm: removes task file\n'
_fresh
QUEUE_DIR="$QUEUE_DIR" "$HARNESS" queue add "Task to remove" 2>/dev/null || true
TASK_ID="$(_queue_first_id)"
if [[ -z "$TASK_ID" ]]; then
  _fail "rm — setup" "no task id found after add"
else
  QUEUE_DIR="$QUEUE_DIR" "$HARNESS" queue rm "$TASK_ID" 2>/dev/null || true
  COUNT="$(_queue_count)"
  if [[ "$COUNT" -eq 0 ]]; then
    _pass "task file removed (queue now empty)"
  else
    _fail "rm removes file" "expected 0 files after rm, got $COUNT"
  fi
fi

# ─────────────────────────────────────────────────────────────────────────────
# Case 10: harness queue show <id> displays the task
# ─────────────────────────────────────────────────────────────────────────────
printf '[10] harness queue show: displays task content\n'
_fresh
QUEUE_DIR="$QUEUE_DIR" "$HARNESS" queue add "Task for show command" 2>/dev/null || true
TASK_ID="$(_queue_first_id)"
if [[ -z "$TASK_ID" ]]; then
  _fail "show — setup" "no task id found after add"
else
  SHOW_OUT="$(QUEUE_DIR="$QUEUE_DIR" "$HARNESS" queue show "$TASK_ID" 2>&1)" || true
  if echo "$SHOW_OUT" | grep -q 'show command\|intent\|status\|source'; then
    _pass "show displays task content"
  else
    _fail "show displays content" "show output missing task content. Output: $SHOW_OUT"
  fi
fi

# ─────────────────────────────────────────────────────────────────────────────
# Case 11: harness queue add --from-inbox N tags source:loop-inbox
# ─────────────────────────────────────────────────────────────────────────────
printf '[11] harness queue add --from-inbox: tags source:loop-inbox\n'
_fresh
# Create a minimal inbox entry
INBOX_DIR="$STATE/loop/inbox"
mkdir -p "$INBOX_DIR"
cat > "$INBOX_DIR/proposal-001.md" <<'INBOX'
Intent: Fix loop inbox proposal for VI-2 testing
Acceptance: bash scripts/tests/test-emit-event.sh exits 0
INBOX
INBOX_OUT="$(QUEUE_DIR="$QUEUE_DIR" INBOX_DIR="$INBOX_DIR" "$HARNESS" queue add --from-inbox 1 2>&1)" || true
QF="$(find "$QUEUE_DIR" -name 'q-*.md' 2>/dev/null | sort | head -1)"
if [[ -n "$QF" ]] && grep -q 'source: loop-inbox' "$QF" 2>/dev/null; then
  _pass "queue file has source: loop-inbox"
else
  _fail "--from-inbox tags source:loop-inbox" "queue file missing 'source: loop-inbox'. File: ${QF:-none}. Output: $INBOX_OUT"
fi

# ─────────────────────────────────────────────────────────────────────────────
# Case 12: clear-freeze removes .AUTONOMOUS_FREEZE sentinel (interactive-only)
# ─────────────────────────────────────────────────────────────────────────────
printf '[12] harness queue clear-freeze: removes .AUTONOMOUS_FREEZE sentinel\n'
_fresh
# Create the sentinel
printf '{"trigger":"manual","reason":"test freeze","ts":"2026-07-04T00:00:00Z"}\n' \
  > "$STATE/.AUTONOMOUS_FREEZE"
CLEAR_OUT="$(QUEUE_DIR="$QUEUE_DIR" "$HARNESS" queue clear-freeze 2>&1)" || true
if [[ ! -f "$STATE/.AUTONOMOUS_FREEZE" ]]; then
  _pass "sentinel removed by clear-freeze"
else
  _fail "clear-freeze removes sentinel" "sentinel still present after clear-freeze. Output: $CLEAR_OUT"
fi

# ─────────────────────────────────────────────────────────────────────────────
# Summary
# ─────────────────────────────────────────────────────────────────────────────
printf '\n'
printf '=== Results: %d PASS, %d FAIL ===\n' "$PASS" "$FAIL"
rm -rf "$TMPROOT" 2>/dev/null || true
[[ "$FAIL" -eq 0 ]]
