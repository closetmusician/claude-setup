#!/usr/bin/env bash
# ABOUTME: Shared budget enforcement library for all autonomous execution planes (VII-2).
# ABOUTME: Single source of truth for per-night task cap and per-task wall-clock cap.
# ABOUTME: Usage: source in night-runner.sh and flywheel-dispatcher.sh before any task dispatch.
# ABOUTME: Gotchas: BSD-safe; fail-closed on ABORT paths; never crashes on missing tools.
# ABOUTME: Kill-switch: sources scripts/lib/kill-switch.sh if present; else writes sentinel directly.

# ── Hard caps — single source of truth (never redefine in callers) ────────────
# These constants are read by both night-runner.sh and flywheel-dispatcher.sh.
# Change them HERE only; callers must source this file.
readonly BUDGET_MAX_TASKS_PER_NIGHT=3
readonly BUDGET_MAX_MINUTES_PER_TASK=45
readonly BUDGET_QUOTA_PATTERNS='quota|rate.?limit|overloaded|529|capacity'

# ── Internal helpers ─────────────────────────────────────────────────────────

# _budget_state_dir: resolves $STATE with fallback to ~/.claude/state
# Purpose: centralise STATE resolution so all budget functions agree on location.
# Usage: local sdir; sdir="$(_budget_state_dir)"
# Gotchas: honours STATE override (used by tests); never errors.
_budget_state_dir() {
  echo "${STATE:-$HOME/.claude/state}"
}

# _budget_emit: optional spine event; fail-open if emit-event.sh absent.
# Purpose: record budget enforcement events to the Pillar I spine.
# Usage: _budget_emit <event_type> <json_payload> [k=v ...]
# Gotchas: silently returns 0 if emit-event.sh is not in the same lib dir.
_budget_emit() {
  local etype="$1"; shift
  local payload="$1"; shift
  local lib_dir
  lib_dir="$(dirname "${BASH_SOURCE[0]}")"
  # shellcheck source=/dev/null
  source "${lib_dir}/emit-event.sh" 2>/dev/null || return 0
  emit_event "$etype" "$payload" "$@" 2>/dev/null || true
}

# _budget_trip_kill_switch: trip the freeze sentinel via kill-switch.sh or direct write.
# Purpose: halt all autonomous execution on quota death; defensive against missing dep.
# Usage: _budget_trip_kill_switch <reason>
# Gotchas: if kill-switch.sh is absent, writes sentinel directly. Never errors.
_budget_trip_kill_switch() {
  local reason="${1:-unspecified quota abort}"
  local lib_dir
  lib_dir="$(dirname "${BASH_SOURCE[0]}")"
  local ks="${lib_dir}/kill-switch.sh"
  if [[ -f "$ks" ]]; then
    # shellcheck source=/dev/null
    source "$ks" 2>/dev/null || true
    kill_switch_trip "quota" "$reason" 2>/dev/null || true
  else
    # Fallback: write sentinel directly (VII-4 not yet built or unavailable)
    local sdir; sdir="$(_budget_state_dir)"
    local ts; ts=$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo "unknown")
    printf '[%s] trigger=quota reason=%s\n' "$ts" "$reason" \
      > "${sdir}/.AUTONOMOUS_FREEZE" 2>/dev/null || true
  fi
}

# ── Public API ───────────────────────────────────────────────────────────────

# budget_check_prerequisites: verify state dir is writable and kill-switch is not tripped.
# Purpose: called once at runner start; returns nonzero if the run should be aborted.
# Usage: budget_check_prerequisites || exit 1
# Gotchas: fail-closed on ABORT (returns 1). Does NOT source kill-switch.sh for the check
#   to avoid circular deps — reads the sentinel file directly.
budget_check_prerequisites() {
  local sdir; sdir="$(_budget_state_dir)"

  # Check kill-switch sentinel first (fail-closed — if tripped, abort)
  local freeze="${sdir}/.AUTONOMOUS_FREEZE"
  if [[ -f "$freeze" ]]; then
    local reason; reason=$(cat "$freeze" 2>/dev/null || echo "manual")
    echo "BUDGET-ABORT: kill-switch is tripped ($reason)" >&2
    return 1
  fi

  # Verify state dir is writable
  if ! mkdir -p "$sdir" 2>/dev/null || ! touch "${sdir}/.budget-prereq-probe" 2>/dev/null; then
    echo "BUDGET-ABORT: state dir $sdir is not writable" >&2
    return 1
  fi
  rm -f "${sdir}/.budget-prereq-probe" 2>/dev/null || true

  return 0
}

# budget_night_reset: reset per-night task counter at the start of each night run.
# Purpose: call once at the top of night-runner.sh before any task dispatch.
# Usage: budget_night_reset
# Gotchas: stamps state/budget-night.json with ISO timestamp; overwrites any prior count.
budget_night_reset() {
  local sdir; sdir="$(_budget_state_dir)"
  mkdir -p "$sdir" 2>/dev/null || true
  local counter_file="${sdir}/.night-task-count"
  local night_json="${sdir}/budget-night.json"
  echo "0" > "$counter_file"
  local ts; ts=$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo "unknown")
  printf '{"reset_at":"%s","max_tasks":%d,"max_minutes":%d}\n' \
    "$ts" "$BUDGET_MAX_TASKS_PER_NIGHT" "$BUDGET_MAX_MINUTES_PER_TASK" \
    > "$night_json" 2>/dev/null || true
  _budget_emit "metric" \
    '{"name":"budget.night_reset","value":0,"unit":"tasks"}' \
    outcome=ok 2>/dev/null || true
  return 0
}

# budget_task_start: increment the per-night task counter; BUDGET-ABORT if cap would be exceeded.
# Purpose: gate each task dispatch; the 4th task in a night is hard-refused.
# Usage: budget_task_start <task_id> || { log "BUDGET-ABORT"; exit 1; }
# Gotchas: fail-closed on ABORT (returns 1). Counter file missing → treated as 0 (safe start).
budget_task_start() {
  local task_id="${1:-unknown}"
  local sdir; sdir="$(_budget_state_dir)"
  mkdir -p "$sdir" 2>/dev/null || true
  local counter_file="${sdir}/.night-task-count"
  local count
  count=$(cat "$counter_file" 2>/dev/null || echo "0")
  # Strip non-numeric (safety net for corrupt file)
  count=$(printf '%s' "$count" | tr -d '[:space:]' | grep -E '^[0-9]+$' || echo "0")
  count="${count:-0}"

  if (( count >= BUDGET_MAX_TASKS_PER_NIGHT )); then
    _budget_emit "metric" \
      "{\"name\":\"budget.cap_hit\",\"value\":$count,\"unit\":\"tasks\",\"task_id\":\"$task_id\"}" \
      outcome=denied 2>/dev/null || true
    echo "BUDGET-ABORT: nightly task cap ($BUDGET_MAX_TASKS_PER_NIGHT) reached; task $task_id refused" >&2
    return 1
  fi

  local new_count=$(( count + 1 ))
  echo "$new_count" > "$counter_file"
  local ts; ts=$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo "unknown")
  _budget_emit "metric" \
    "{\"name\":\"budget.task_started\",\"value\":$new_count,\"unit\":\"tasks\",\"task_id\":\"$task_id\",\"started_at\":\"$ts\"}" \
    outcome=ok 2>/dev/null || true
  return 0
}

# budget_check_quota_abort: scan task output for quota/rate-limit signals; trip kill-switch on match.
# Purpose: called after each task completes; quota death aborts the whole night, not just one task.
# Usage: budget_check_quota_abort <output_file> [task_id]
# Gotchas: fail-closed on ABORT (returns 1). Returns 0 on clean output or missing file.
budget_check_quota_abort() {
  local output_file="${1:-/dev/null}"
  local task_id="${2:-unknown}"

  if [[ ! -f "$output_file" ]]; then
    return 0
  fi

  if grep -qE "$BUDGET_QUOTA_PATTERNS" "$output_file" 2>/dev/null; then
    _budget_emit "incident" \
      "{\"severity\":\"P1\",\"class\":\"quota-abort\",\"detail\":\"Quota/overload detected in task $task_id output\"}" \
      outcome=error 2>/dev/null || true
    # Trip kill-switch: quota death aborts the NIGHT, not just this task
    _budget_trip_kill_switch "Quota/rate-limit detected in task $task_id output"
    echo "QUOTA-ABORT: quota pattern detected in task $task_id — kill-switch tripped" >&2
    return 1
  fi

  return 0
}
