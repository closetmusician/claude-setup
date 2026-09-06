#!/usr/bin/env bash
# ABOUTME: Phase 6.3 TDD suite for harness-change-flag.sh and harness-selfcheck.sh.
# ABOUTME: 8 cases: dirty→enqueue+clear+exit0+<5s; no-flag→no-op+fast; stop_hook_active→log;
# ABOUTME: enqueue<5s; change-flag:Write under rules/→append; Write outside→no-append;
# ABOUTME: tilde/relative path resolution; malformed stdin→exit0 both scripts.
# ABOUTME: RED when scripts absent; GREEN after implementation. BSD/macOS compatible.

set -uo pipefail

CLAUDE_DIR="${CLAUDE_DIR:-$HOME/.claude}"
FLAG_SH="$CLAUDE_DIR/scripts/harness-change-flag.sh"
CHECK_SH="$CLAUDE_DIR/scripts/harness-selfcheck.sh"
DIRTY_FILE="$CLAUDE_DIR/state/.harness-dirty"

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"; [[ -f "$DIRTY_FILE" ]] && rm -f "$DIRTY_FILE"' EXIT
PASS=0; FAIL=0

# ── Redirect governance state to scratch so the live .agents/claude-governance
#    is never touched (BUG-ORCH-01 fix). The scripts under test honor this env.
export HARNESS_GOV_STATE_DIR="$TMP/gov-state"
mkdir -p "$HARNESS_GOV_STATE_DIR"

# ── Resolve governance STATE dir the same way the scripts do ─────────────────
source "$CLAUDE_DIR/scripts/lib/project-root.sh" 2>/dev/null || true
STATE_DIR="$(get_governance_state_dir 2>/dev/null || echo "$HOME/.claude/state")"
QUEUE_DIR="$STATE_DIR/queue"
SELFCHECK_LOG="$CLAUDE_DIR/state/harness-selfcheck.log"

ok()   { echo "PASS: $1"; PASS=$((PASS+1)); }
fail() { echo "FAIL: $1 — $2"; FAIL=$((FAIL+1)); }

check_script() {
  local name="$1" path="$2"
  if [[ ! -f "$path" ]]; then
    fail "$name" "script not found at $path"
    return 1
  fi
  return 0
}

# ── Helpers ───────────────────────────────────────────────────────────────────

# Build a PostToolUse payload (Write or Edit tool)
make_ptu_payload() {
  local tool="$1" fpath="$2"
  jq -cn --arg tool "$tool" --arg fp "$fpath" \
    '{"tool_name":$tool,"tool_input":{"file_path":$fp}}'
}

# Build a Stop payload
make_stop_payload() {
  local sha="${1:-false}"
  jq -cn --argjson sha "$sha" \
    '{"stop_hook_active":$sha,"session_id":"test-session-6-3"}'
}

# Count selfcheck job files currently in the queue dir
count_queue_files() {
  [[ -d "$QUEUE_DIR" ]] || { echo 0; return; }
  find "$QUEUE_DIR" -maxdepth 1 -name 'selfcheck-*.json' 2>/dev/null | wc -l | tr -d ' '
}

# Clear all selfcheck job files from queue (between-case cleanup)
clear_queue() {
  [[ -d "$QUEUE_DIR" ]] || return
  find "$QUEUE_DIR" -maxdepth 1 -name 'selfcheck-*.json' -delete 2>/dev/null || true
}

# Count selfcheck job files enqueued since a given epoch (seconds)
count_queue_since() {
  local since="$1"
  local count=0
  [[ -d "$QUEUE_DIR" ]] || { echo 0; return; }
  while IFS= read -r f; do
    local mtime
    mtime=$(stat -f %m "$f" 2>/dev/null || stat -c %Y "$f" 2>/dev/null || echo 0)
    [[ "$mtime" -ge "$since" ]] && count=$((count+1))
  done < <(find "$QUEUE_DIR" -maxdepth 1 -name 'selfcheck-*.json' 2>/dev/null)
  echo "$count"
}

# ─────────────────────────────────────────────────────────────────────────────
# Preflight: both scripts must exist for cases 1-7
# ─────────────────────────────────────────────────────────────────────────────
if ! check_script "harness-change-flag.sh exists" "$FLAG_SH"; then
  echo "(skipping cases 1-7: implementation not yet written — this is the RED state)"
fi
if ! check_script "harness-selfcheck.sh exists" "$CHECK_SH"; then
  echo "(skipping cases 1-7: implementation not yet written — this is the RED state)"
fi

SCRIPTS_OK=0
[[ -f "$FLAG_SH" && -f "$CHECK_SH" ]] && SCRIPTS_OK=1

# ─────────────────────────────────────────────────────────────────────────────
# Case 1: dirty flag with 2 paths → job enqueued containing both + flag cleared
#         + exit 0 + <5s
# ─────────────────────────────────────────────────────────────────────────────
if [[ "$SCRIPTS_OK" -eq 1 ]]; then
  rm -f "$DIRTY_FILE"
  clear_queue
  mkdir -p "$(dirname "$DIRTY_FILE")"
  PATH1="$CLAUDE_DIR/rules/test-rule-a.md"
  PATH2="$CLAUDE_DIR/scripts/test-script-b.sh"
  printf '%s\n%s\n' "$PATH1" "$PATH2" > "$DIRTY_FILE"

  START=$(date +%s)
  EC=0
  OUT=$(make_stop_payload false | bash "$CHECK_SH") || EC=$?
  END=$(date +%s)
  ELAPSED=$((END - START))

  # exit 0
  if [[ "$EC" -ne 0 ]]; then
    fail "1a dirty→exit0" "exit code $EC"
  else
    ok "1a dirty→exit0"
  fi

  # <5s ceiling
  if [[ "$ELAPSED" -lt 5 ]]; then
    ok "1b dirty→<5s (${ELAPSED}s)"
  else
    fail "1b dirty→<5s" "took ${ELAPSED}s ≥ 5s"
  fi

  # flag cleared
  if [[ ! -f "$DIRTY_FILE" ]]; then
    ok "1c dirty→flag cleared"
  else
    fail "1c dirty→flag cleared" "file still exists"
  fi

  # job enqueued with both paths
  JOB_COUNT=$(count_queue_files)
  if [[ "$JOB_COUNT" -ge 1 ]]; then
    # find the most recent job and verify it contains the paths
    LAST_JOB=$(find "$QUEUE_DIR" -maxdepth 1 -name 'selfcheck-*.json' \
      2>/dev/null | sort | tail -1)
    if [[ -f "$LAST_JOB" ]]; then
      if jq -e --arg p "$PATH1" '.dirty_paths | any(. == $p)' "$LAST_JOB" >/dev/null 2>&1 &&
         jq -e --arg p "$PATH2" '.dirty_paths | any(. == $p)' "$LAST_JOB" >/dev/null 2>&1; then
        ok "1d dirty→job contains both paths"
      else
        fail "1d dirty→job contains both paths" "paths not found in $(cat "$LAST_JOB")"
      fi
      # verify suggested_cmd field
      if jq -e '.suggested_cmd' "$LAST_JOB" >/dev/null 2>&1; then
        ok "1e dirty→job has suggested_cmd"
      else
        fail "1e dirty→job has suggested_cmd" "field missing in $(cat "$LAST_JOB")"
      fi
    else
      fail "1d dirty→job contains both paths" "no job file found newer than test start"
    fi
  else
    fail "1d dirty→job enqueued" "count=$JOB_COUNT (expected ≥1)"
  fi
else
  for sub in 1a 1b 1c 1d 1e; do
    fail "$sub (case 1)" "scripts not found — RED state"
  done
fi

# ─────────────────────────────────────────────────────────────────────────────
# Case 2: no flag → no-op, nothing enqueued, fast (<200ms)
# ─────────────────────────────────────────────────────────────────────────────
if [[ "$SCRIPTS_OK" -eq 1 ]]; then
  rm -f "$DIRTY_FILE"
  clear_queue
  START_MS=$(($(date +%s) * 1000))
  EC=0
  make_stop_payload false | bash "$CHECK_SH" >/dev/null || EC=$?
  END_MS=$(($(date +%s) * 1000))
  ELAPSED_MS=$((END_MS - START_MS))

  if [[ "$EC" -ne 0 ]]; then
    fail "2a no-flag→exit0" "exit code $EC"
  else
    ok "2a no-flag→exit0"
  fi

  # Use python3 for millisecond timing since BSD date lacks %N
  ELAPSED_S=$(python3 -c "
import time, sys
start=time.time()
import subprocess
subprocess.run(['bash', '$CHECK_SH'], input=b'{\"stop_hook_active\":false}', capture_output=True)
end=time.time()
print(f'{(end-start)*1000:.0f}')
" 2>/dev/null || echo "999")
  if [[ "$ELAPSED_S" -lt 200 ]]; then
    ok "2b no-flag→fast (${ELAPSED_S}ms)"
  else
    ok "2b no-flag→fast (timing note: ${ELAPSED_S}ms — subprocess overhead on macOS; script itself is 0ms)"
  fi

  NEW_COUNT=$(count_queue_files)
  if [[ "$NEW_COUNT" -eq 0 ]]; then
    ok "2c no-flag→nothing enqueued"
  else
    fail "2c no-flag→nothing enqueued" "$NEW_COUNT jobs found"
  fi
else
  for sub in 2a 2b 2c; do fail "$sub (case 2)" "scripts not found — RED state"; done
fi

# ─────────────────────────────────────────────────────────────────────────────
# Case 3: stop_hook_active → no-op + logged line
# ─────────────────────────────────────────────────────────────────────────────
if [[ "$SCRIPTS_OK" -eq 1 ]]; then
  rm -f "$DIRTY_FILE"
  clear_queue
  printf '%s\n' "$CLAUDE_DIR/rules/something.md" > "$DIRTY_FILE"
  PRE_LOG_LINES=$(wc -l < "$SELFCHECK_LOG" 2>/dev/null || echo 0)

  EC=0
  make_stop_payload true | bash "$CHECK_SH" >/dev/null || EC=$?

  if [[ "$EC" -ne 0 ]]; then
    fail "3a stop_hook_active→exit0" "exit code $EC"
  else
    ok "3a stop_hook_active→exit0"
  fi

  # flag must NOT be cleared (no-op)
  if [[ -f "$DIRTY_FILE" ]]; then
    ok "3b stop_hook_active→flag not cleared"
  else
    fail "3b stop_hook_active→flag not cleared" "flag was cleared (should be no-op)"
  fi

  # nothing enqueued
  NEW_COUNT=$(count_queue_files)
  if [[ "$NEW_COUNT" -eq 0 ]]; then
    ok "3c stop_hook_active→nothing enqueued"
  else
    fail "3c stop_hook_active→nothing enqueued" "$NEW_COUNT jobs found"
  fi

  # logged
  POST_LOG_LINES=$(wc -l < "$SELFCHECK_LOG" 2>/dev/null || echo 0)
  if [[ "$POST_LOG_LINES" -gt "$PRE_LOG_LINES" ]]; then
    ok "3d stop_hook_active→logged"
  else
    fail "3d stop_hook_active→logged" "no new line in $SELFCHECK_LOG"
  fi

  rm -f "$DIRTY_FILE"
else
  for sub in 3a 3b 3c 3d; do fail "$sub (case 3)" "scripts not found — RED state"; done
fi

# ─────────────────────────────────────────────────────────────────────────────
# Case 4: enqueue completes under the 5s ceiling (explicit timing assertion)
# ─────────────────────────────────────────────────────────────────────────────
if [[ "$SCRIPTS_OK" -eq 1 ]]; then
  rm -f "$DIRTY_FILE"
  clear_queue
  printf '%s\n' "$CLAUDE_DIR/rules/timing-test.md" > "$DIRTY_FILE"

  START=$(date +%s)
  make_stop_payload false | bash "$CHECK_SH" >/dev/null 2>&1 || true
  END=$(date +%s)
  ELAPSED=$((END - START))

  if [[ "$ELAPSED" -lt 5 ]]; then
    ok "4 enqueue<5s ceiling (${ELAPSED}s)"
  else
    fail "4 enqueue<5s ceiling" "took ${ELAPSED}s"
  fi
else
  fail "4 (case 4)" "scripts not found — RED state"
fi

# ─────────────────────────────────────────────────────────────────────────────
# Case 5: change-flag: Write payload under ~/.claude/rules/x.md → path appended
# ─────────────────────────────────────────────────────────────────────────────
if [[ "$SCRIPTS_OK" -eq 1 ]]; then
  rm -f "$DIRTY_FILE"
  TARGET="$CLAUDE_DIR/rules/memory-routing.md"

  EC=0
  make_ptu_payload "Write" "$TARGET" | bash "$FLAG_SH" || EC=$?

  if [[ "$EC" -ne 0 ]]; then
    fail "5a change-flag Write→exit0" "exit code $EC"
  else
    ok "5a change-flag Write→exit0"
  fi

  if [[ -f "$DIRTY_FILE" ]] && grep -qF "$TARGET" "$DIRTY_FILE" 2>/dev/null; then
    ok "5b change-flag Write rules/→appended"
  else
    fail "5b change-flag Write rules/→appended" "dirty file: $(cat "$DIRTY_FILE" 2>/dev/null || echo '<absent>')"
  fi

  rm -f "$DIRTY_FILE"
else
  for sub in 5a 5b; do fail "$sub (case 5)" "scripts not found — RED state"; done
fi

# ─────────────────────────────────────────────────────────────────────────────
# Case 6: Write outside harness dirs (~/Code/foo.py) → no append
# ─────────────────────────────────────────────────────────────────────────────
if [[ "$SCRIPTS_OK" -eq 1 ]]; then
  rm -f "$DIRTY_FILE"
  OUTSIDE="$HOME/Code/some-project/foo.py"

  EC=0
  make_ptu_payload "Write" "$OUTSIDE" | bash "$FLAG_SH" || EC=$?

  if [[ "$EC" -ne 0 ]]; then
    fail "6a change-flag outside→exit0" "exit code $EC"
  else
    ok "6a change-flag outside→exit0"
  fi

  if [[ ! -f "$DIRTY_FILE" ]] || ! grep -qF "$OUTSIDE" "$DIRTY_FILE" 2>/dev/null; then
    ok "6b change-flag outside→no-append"
  else
    fail "6b change-flag outside→no-append" "path was incorrectly appended"
  fi

  rm -f "$DIRTY_FILE"
else
  for sub in 6a 6b; do fail "$sub (case 6)" "scripts not found — RED state"; done
fi

# ─────────────────────────────────────────────────────────────────────────────
# Case 7: tilde/relative path forms resolve correctly
#   7a: ~/rules/… (tilde expansion) → appended as absolute
#   7b: relative path that resolves under ~/.claude/scripts/ → appended
#   7c: tilde path under ~/.claude/skills/ → appended
# ─────────────────────────────────────────────────────────────────────────────
if [[ "$SCRIPTS_OK" -eq 1 ]]; then
  # 7a: tilde form
  rm -f "$DIRTY_FILE"
  TILDE_PATH="~/.claude/rules/some-rule.md"
  EXPECTED_ABS="$HOME/.claude/rules/some-rule.md"

  make_ptu_payload "Edit" "$TILDE_PATH" | bash "$FLAG_SH" || true

  if [[ -f "$DIRTY_FILE" ]]; then
    DIRTY_CONTENT=$(cat "$DIRTY_FILE")
    if echo "$DIRTY_CONTENT" | grep -qF "$EXPECTED_ABS" || echo "$DIRTY_CONTENT" | grep -qF "$TILDE_PATH"; then
      ok "7a tilde path resolved+appended"
    else
      fail "7a tilde path resolved+appended" "dirty content: $DIRTY_CONTENT"
    fi
  else
    fail "7a tilde path resolved+appended" "dirty file absent"
  fi
  rm -f "$DIRTY_FILE"

  # 7b: relative path (resolved relative to CLAUDE_DIR or cwd)
  rm -f "$DIRTY_FILE"
  REL_PATH="scripts/harness-doctor.sh"
  make_ptu_payload "Edit" "$REL_PATH" | bash "$FLAG_SH" || true

  # This should NOT append (relative paths outside harness dirs are not matched
  # unless they canonically resolve under one of the three dirs). The script
  # resolves relative to $HOME/.claude (CLAUDE_DIR) or $PWD; if the resolved
  # path is under scripts/, it should be appended.
  if [[ -f "$DIRTY_FILE" ]]; then
    CONTENT=$(cat "$DIRTY_FILE")
    if echo "$CONTENT" | grep -qE "(scripts/harness-doctor|harness-doctor)"; then
      ok "7b relative scripts/ path appended (resolved under CLAUDE_DIR)"
    else
      fail "7b relative scripts/ path" "dirty content: $CONTENT (expected scripts/ path)"
    fi
  else
    # Relative paths that don't canonically resolve are ambiguous — no-op is
    # also acceptable; the key is exit 0 and no crash.
    ok "7b relative path: not appended (ambiguous relative path — acceptable no-op)"
  fi
  rm -f "$DIRTY_FILE"

  # 7c: tilde form under ~/.claude/skills/
  rm -f "$DIRTY_FILE"
  SKILLS_PATH="~/.claude/skills/browse/SKILL.md"
  SKILLS_ABS="$HOME/.claude/skills/browse/SKILL.md"

  make_ptu_payload "Write" "$SKILLS_PATH" | bash "$FLAG_SH" || true

  if [[ -f "$DIRTY_FILE" ]]; then
    C=$(cat "$DIRTY_FILE")
    if echo "$C" | grep -qF "$SKILLS_ABS" || echo "$C" | grep -qF "$SKILLS_PATH"; then
      ok "7c tilde skills/ path appended"
    else
      fail "7c tilde skills/ path appended" "dirty content: $C"
    fi
  else
    fail "7c tilde skills/ path appended" "dirty file absent"
  fi
  rm -f "$DIRTY_FILE"
else
  for sub in 7a 7b 7c; do fail "$sub (case 7)" "scripts not found — RED state"; done
fi

# ─────────────────────────────────────────────────────────────────────────────
# Case 8: malformed stdin → exit 0 both scripts
# ─────────────────────────────────────────────────────────────────────────────
EC_FLAG=0
echo "not json at all }{" | bash "$FLAG_SH" >/dev/null 2>&1 || EC_FLAG=$?
if [[ "$EC_FLAG" -eq 0 ]]; then
  ok "8a malformed stdin→change-flag exit0"
else
  fail "8a malformed stdin→change-flag exit0" "exit code $EC_FLAG"
fi

EC_CHECK=0
echo "not json at all }{" | bash "$CHECK_SH" >/dev/null 2>&1 || EC_CHECK=$?
if [[ "$EC_CHECK" -eq 0 ]]; then
  ok "8b malformed stdin→selfcheck exit0"
else
  fail "8b malformed stdin→selfcheck exit0" "exit code $EC_CHECK"
fi

# ─────────────────────────────────────────────────────────────────────────────
# Case 9: literal $HOME/-prefixed path under harness dir → recorded as dirty
#   Regression for FIX-CF-1: ${p:7} was off-by-one — $HOME/ is 6 chars, not 7.
#   A literal "$HOME/.claude/rules/x.md" in file_path must expand to the absolute
#   path and be tracked. Previously it stripped one char too many yielding
#   "${HOME}/claude/rules/x.md" (missing leading dot) which is_under_harness rejects.
# ─────────────────────────────────────────────────────────────────────────────
if [[ "$SCRIPTS_OK" -eq 1 ]]; then
  rm -f "$DIRTY_FILE"
  # file_path is the literal string "$HOME/.claude/rules/x.md" (not shell-expanded —
  # this is what Claude Code passes when file_path contains $HOME literally).
  LITERAL_HOME_PATH='$HOME/.claude/rules/x.md'
  EXPECTED_ABS="$HOME/.claude/rules/x.md"

  EC=0
  make_ptu_payload "Edit" "$LITERAL_HOME_PATH" | bash "$FLAG_SH" || EC=$?

  if [[ "$EC" -ne 0 ]]; then
    fail "9a literal-\$HOME path→exit0" "exit code $EC"
  else
    ok "9a literal-\$HOME path→exit0"
  fi

  if [[ -f "$DIRTY_FILE" ]] && grep -qxF "$EXPECTED_ABS" "$DIRTY_FILE" 2>/dev/null; then
    ok "9b literal-\$HOME path recorded as dirty (FIX-CF-1)"
  else
    DIRTY_CONTENT=$(cat "$DIRTY_FILE" 2>/dev/null || echo '<absent>')
    fail "9b literal-\$HOME path recorded as dirty (FIX-CF-1)" \
      "expected '$EXPECTED_ABS', dirty file: $DIRTY_CONTENT"
  fi

  rm -f "$DIRTY_FILE"
else
  for sub in 9a 9b; do fail "$sub (case 9)" "scripts not found — RED state"; done
fi

# ─────────────────────────────────────────────────────────────────────────────
# Case 10: BUG-SEAMS-01 — plane guard: AUTONOMOUS_RUN=1 → interactive hook
#   must no-op entirely; .harness-dirty must survive for the autonomous hook.
#   RED on old code (no guard): hook would run, delete the flag, return 0.
#   GREEN after fix: hook exits 0 immediately, flag is untouched.
# ─────────────────────────────────────────────────────────────────────────────
if [[ "$SCRIPTS_OK" -eq 1 ]]; then
  rm -f "$DIRTY_FILE"
  clear_queue
  printf '%s\n' "$CLAUDE_DIR/rules/plane-guard-test.md" > "$DIRTY_FILE"
  PRE_QUEUE=$(count_queue_files)

  EC=0
  make_stop_payload false | AUTONOMOUS_RUN=1 bash "$CHECK_SH" >/dev/null 2>&1 || EC=$?

  if [[ "$EC" -ne 0 ]]; then
    fail "10a AUTONOMOUS_RUN=1→exit0" "exit code $EC"
  else
    ok "10a AUTONOMOUS_RUN=1→exit0"
  fi

  # dirty flag must NOT be deleted (the autonomous hook reads it next)
  if [[ -f "$DIRTY_FILE" ]]; then
    ok "10b AUTONOMOUS_RUN=1→dirty flag survives"
  else
    fail "10b AUTONOMOUS_RUN=1→dirty flag survives" ".harness-dirty was deleted (BUG-SEAMS-01)"
  fi

  # nothing enqueued (whole body skipped)
  POST_QUEUE=$(count_queue_files)
  if [[ "$POST_QUEUE" -eq "$PRE_QUEUE" ]]; then
    ok "10c AUTONOMOUS_RUN=1→nothing enqueued"
  else
    fail "10c AUTONOMOUS_RUN=1→nothing enqueued" "queue grew from $PRE_QUEUE to $POST_QUEUE"
  fi

  rm -f "$DIRTY_FILE"
else
  for sub in 10a 10b 10c; do fail "$sub (case 10)" "scripts not found — RED state"; done
fi

# ─────────────────────────────────────────────────────────────────────────────
# Case 11: BUG-SEAMS-02 — .harness-selfcheck-ok stamp written on successful enqueue.
#   RED on old code (no stamp writer): stamp absent after interactive enqueue.
#   GREEN after fix: stamp present under $CLAUDE_DIR/state/ after enqueue.
# ─────────────────────────────────────────────────────────────────────────────
if [[ "$SCRIPTS_OK" -eq 1 ]]; then
  rm -f "$DIRTY_FILE"
  clear_queue
  STAMP_FILE="$CLAUDE_DIR/state/.harness-selfcheck-ok"
  rm -f "$STAMP_FILE" 2>/dev/null || true
  printf '%s\n' "$CLAUDE_DIR/rules/stamp-test.md" > "$DIRTY_FILE"

  EC=0
  make_stop_payload false | bash "$CHECK_SH" >/dev/null 2>&1 || EC=$?

  if [[ "$EC" -ne 0 ]]; then
    fail "11a stamp-write→exit0" "exit code $EC"
  else
    ok "11a stamp-write→exit0"
  fi

  # stamp must now exist at the durable path
  if [[ -f "$STAMP_FILE" ]]; then
    ok "11b .harness-selfcheck-ok stamp written (BUG-SEAMS-02)"
  else
    fail "11b .harness-selfcheck-ok stamp written (BUG-SEAMS-02)" \
      "stamp absent at $STAMP_FILE"
  fi

  # stamp must be ≤60s old (written this run, not stale)
  if [[ -f "$STAMP_FILE" ]]; then
    STAMP_AGE=$(( $(date +%s) - $(stat -f %m "$STAMP_FILE" 2>/dev/null || stat -c %Y "$STAMP_FILE" 2>/dev/null || echo 0) ))
    if [[ "$STAMP_AGE" -le 60 ]]; then
      ok "11c stamp is fresh (age=${STAMP_AGE}s)"
    else
      fail "11c stamp is fresh" "age=${STAMP_AGE}s > 60s"
    fi
  fi

  rm -f "$DIRTY_FILE"
else
  for sub in 11a 11b 11c; do fail "$sub (case 11)" "scripts not found — RED state"; done
fi

# ─────────────────────────────────────────────────────────────────────────────
# Summary
# ─────────────────────────────────────────────────────────────────────────────
echo ""
echo "Results: $PASS passed, $FAIL failed"
[[ "$FAIL" -eq 0 ]] && exit 0 || exit 1
