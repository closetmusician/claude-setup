#!/usr/bin/env bash
# ABOUTME: VI-4 night-runner — main launchd entry for the autonomous work economy.
# ABOUTME: Dispatches approved queue tasks into isolated git worktrees each night.
# ABOUTME: Kill-switch and budget-kernel checks are performed before any dispatch.
# ABOUTME: Stages completed tasks only; NEVER merges or pushes (push-guard enforces).
# ABOUTME: Ships DISABLED — launchd plist created but not loaded until Pillar VII clears.

set -uo pipefail

export AUTONOMOUS_RUN=1

# ── Path setup ────────────────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="${SCRIPT_DIR}/lib"
LANE_DISPATCH="${SCRIPT_DIR}/lib/lane-dispatch.sh"

# ── Resolve STATE dir (tests may override via env) ────────────────────────────
STATE="${STATE:-$HOME/.claude/state}"
QUEUE_DIR="${QUEUE_DIR:-$HOME/.claude/queue}"
LOG_FILE="${STATE}/night-runner.log"

mkdir -p "$STATE" "$QUEUE_DIR" 2>/dev/null || true

# ── Logging helper ────────────────────────────────────────────────────────────
# Purpose: timestamped log to night-runner.log + stderr
# Usage: _log "message"
# Gotchas: always appends; never truncates mid-run so kills preserve prior entries.
_log() {
  local ts
  ts="$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo "unknown")"
  printf '[%s] %s\n' "$ts" "$1" | tee -a "$LOG_FILE" >&2
}

# ── Source dependencies ────────────────────────────────────────────────────────
# Purpose: load kill-switch and budget-kernel libraries; fail-closed if absent.
# Usage: sourced at startup before any work.
# Gotchas: kill-switch must be sourced BEFORE budget-kernel (budget uses _budget_trip_kill_switch).
if [[ -f "${LIB_DIR}/kill-switch.sh" ]]; then
  # shellcheck source=lib/kill-switch.sh
  source "${LIB_DIR}/kill-switch.sh"
else
  _log "FATAL: kill-switch.sh missing at ${LIB_DIR}/kill-switch.sh — aborting"
  exit 1
fi

if [[ -f "${LIB_DIR}/budget-kernel.sh" ]]; then
  # shellcheck source=lib/budget-kernel.sh
  source "${LIB_DIR}/budget-kernel.sh"
else
  _log "FATAL: budget-kernel.sh missing at ${LIB_DIR}/budget-kernel.sh — aborting"
  exit 1
fi

if [[ -f "${LIB_DIR}/autonomous-registry.sh" ]]; then
  # shellcheck source=lib/autonomous-registry.sh
  source "${LIB_DIR}/autonomous-registry.sh"
else
  _log "FATAL: autonomous-registry.sh missing at ${LIB_DIR}/autonomous-registry.sh — aborting"
  exit 1
fi

if [[ -f "${LIB_DIR}/timeout.sh" ]]; then
  # shellcheck source=lib/timeout.sh
  source "${LIB_DIR}/timeout.sh"
else
  _log "FATAL: timeout.sh missing at ${LIB_DIR}/timeout.sh — aborting"
  exit 1
fi

# ── Emit helper (sourced lazily from emit-event.sh) ────────────────────────────
# Purpose: emit a queue_event to the Pillar I spine; fail-open.
# Usage: _nr_emit_queue <state> <task_id> <source_tag> <intent> <lane_num>
# Gotchas: sources emit-event.sh once per call; fails silently if spine absent.
_nr_emit_queue() {
  local qstate="$1" task_id="$2" qsource="$3" intent="$4" lane="${5:-null}"
  local emit_sh="${LIB_DIR}/emit-event.sh"
  [[ -f "$emit_sh" ]] || return 0
  local payload
  payload="$(jq -cn \
    --arg task_id "$task_id" \
    --arg state "$qstate" \
    --arg source "$qsource" \
    --arg intent "$(printf '%s' "$intent" | cut -c1-100)" \
    --argjson lane "${lane}" \
    '{task_id:$task_id, state:$state, source:$source, intent:$intent, lane:$lane}' \
    2>/dev/null)" || return 0
  # shellcheck source=/dev/null
  (source "$emit_sh" 2>/dev/null && \
   emit_event "queue_event" "$payload" source="night-runner.sh" outcome=ok 2>/dev/null) || true
}

# ── Update queue task status in its file ────────────────────────────────────────
# Purpose: patch the status: field in the task's frontmatter; BSD-sed compatible.
# Usage: _q_set_status <task_file> <new_status>
# Gotchas: tries BSD sed -i '' first, falls back to GNU sed -i.
_q_set_status() {
  local fpath="$1" new_status="$2"
  sed -i '' "s/^status: .*/status: ${new_status}/" "$fpath" 2>/dev/null || \
  sed -i "s/^status: .*/status: ${new_status}/" "$fpath" 2>/dev/null || true
}

# ── Read a frontmatter field from a queue task file ─────────────────────────────
# Purpose: extract scalar YAML frontmatter values without a YAML parser.
# Usage: _q_field <task_file> <key>
# Gotchas: reads first match only; strips surrounding whitespace and quotes.
_q_field() {
  local fpath="$1" key="$2"
  grep -E "^${key}:[[:space:]]" "$fpath" 2>/dev/null \
    | head -1 \
    | sed "s/^${key}:[[:space:]]*//" \
    | sed 's/[[:space:]]*$//' \
    | sed "s/^['\"]//;s/['\"]$//"
}

# ── Load approved queue tasks sorted by priority then created ───────────────────
# Purpose: return list of task file paths for status=approved tasks.
# Usage: mapfile -t approved_tasks < <(_load_approved_tasks)
# Gotchas: high priority first, oldest created first within same priority.
_load_approved_tasks() {
  local f
  local -a high_pri=() normal_pri=() low_pri=()
  for f in "${QUEUE_DIR}"/q-*.md; do
    [[ -f "$f" ]] || continue
    local status
    status="$(_q_field "$f" "status")"
    [[ "$status" == "approved" ]] || continue
    local pri
    pri="$(_q_field "$f" "priority")"
    case "$pri" in
      high)   high_pri+=("$f")  ;;
      low)    low_pri+=("$f")   ;;
      *)      normal_pri+=("$f") ;;
    esac
  done
  # Sort each group by created date (filename is time-ordered: q-YYYYMMDD-HHMMSS-slug)
  printf '%s\n' "${high_pri[@]+"${high_pri[@]}"}"   | sort
  printf '%s\n' "${normal_pri[@]+"${normal_pri[@]}"}" | sort
  printf '%s\n' "${low_pri[@]+"${low_pri[@]}"}"     | sort
}

# ── Precondition checks ─────────────────────────────────────────────────────────
# Purpose: abort the entire run if any system guard is not met.
# Usage: called once at start; exits 1 on failure.
# Gotchas: check order matters — kill-switch FIRST (spec §2.1).
_check_preconditions() {
  # 1. Kill-switch FIRST (spec mandate)
  kill_switch_check || { _log "Precondition failed: kill-switch is tripped — exiting before dispatch"; exit 1; }

  # 2. Budget-kernel prerequisites (also checks .AUTONOMOUS_FREEZE via budget path)
  budget_check_prerequisites || { _log "Precondition failed: budget prerequisites not met — exiting"; exit 1; }

  # 3. gtimeout availability
  if ! command -v gtimeout >/dev/null 2>&1; then
    _log "Precondition failed: gtimeout not found (install coreutils: brew install coreutils)"
    exit 1
  fi

  # 4. harness-selfcheck stamp ≤24h (Phase 6.3 gate)
  local stamp_file="${STATE}/.harness-selfcheck-ok"
  if [[ ! -f "$stamp_file" ]]; then
    _log "Precondition failed: ${stamp_file} missing — harness-selfcheck (6.3) has not run"
    exit 1
  fi
  local stamp_age
  stamp_age="$(( $(date +%s) - $(date -r "$stamp_file" +%s 2>/dev/null || echo 0) ))"
  if (( stamp_age > 86400 )); then
    _log "Precondition failed: harness-selfcheck stamp is ${stamp_age}s old (>24h)"
    exit 1
  fi

  # 5. Pillar II trust kernel live (completion-claim-guard.log exists and non-empty)
  local trust_log="${STATE}/completion-claim-guard.log"
  if [[ ! -s "$trust_log" ]]; then
    _log "Precondition failed: Pillar II trust kernel not live (${trust_log} missing or empty)"
    exit 1
  fi
}

# ── ANTI-SELF-REPORT: re-run acceptance commands from task manifest ─────────────
# Purpose: night-runner independently verifies acceptance criteria — never trusts lane self-report.
# Usage: _verify_acceptance <task_id> <task_file> <worktree_path>
# Returns: 0 if ALL acceptance commands pass, 1 if any fail.
# Gotchas: acceptance lines are read from the original task file, not the manifest.
_verify_acceptance() {
  local task_id="$1" task_file="$2" worktree="$3"
  local all_pass=0

  # Extract acceptance list items (lines "  - \"...\"" or "  - ...") from frontmatter.
  local fm_end
  fm_end="$(grep -n '^---$' "$task_file" 2>/dev/null | awk -F: 'NR==2{print $1}')"
  [[ -z "$fm_end" ]] && fm_end=50

  local acceptance_cmds
  acceptance_cmds="$(head -n "$fm_end" "$task_file" \
    | grep -E '^[[:space:]]+-[[:space:]]' \
    | sed 's/^[[:space:]]*-[[:space:]]*//' \
    | sed 's/^"//;s/"$//')"

  if [[ -z "$acceptance_cmds" ]]; then
    _log "  [acceptance] WARNING: no acceptance commands found in ${task_id} — marking failed"
    return 1
  fi

  local real_worktree
  real_worktree="$(cd "$worktree" 2>/dev/null && pwd -P || true)"
  if [[ -z "$real_worktree" || ! -d "$real_worktree" ]]; then
    _log "  [acceptance] FAIL: invalid worktree for ${task_id}: ${worktree:-<empty>}"
    return 1
  fi

  local cmd
  while IFS= read -r cmd; do
    [[ -z "$cmd" ]] && continue

    local reject_reason=""
    case "$cmd" in
      *$'\n'*|*$'\r'*) reject_reason="multiline acceptance commands are not allowed" ;;
    esac
    if [[ -z "$reject_reason" ]] && printf '%s' "$cmd" | grep -qE '[;&|<>`$(){}*?\[\]~"'"'"']'; then
      reject_reason="shell metacharacters are not allowed"
    fi
    if [[ -z "$reject_reason" ]] && printf '%s' "$cmd" | grep -qiE '(^|[[:space:]])(git[[:space:]]+push|git[[:space:]]+merge|gh[[:space:]]+pr[[:space:]]+(create|merge))([[:space:]]|$)'; then
      reject_reason="publishing and merge commands are not allowed in acceptance"
    fi
    if [[ -z "$reject_reason" ]] && printf '%s' "$cmd" | grep -qiE '(^|[[:space:]])((ba|z|c|k)?sh[[:space:]]+-c|python3?[[:space:]]+-c|perl[[:space:]]+-e|ruby[[:space:]]+-e|node[[:space:]]+-e)([[:space:]]|$)'; then
      reject_reason="inline interpreter execution is not allowed"
    fi
    if [[ -z "$reject_reason" ]] && printf '%s' "$cmd" | grep -qE '(^|[[:space:]])(/|\\.\\./|\\.\\.$|cd[[:space:]])'; then
      reject_reason="absolute paths, parent paths, and cd are not allowed"
    fi
    if [[ -n "$reject_reason" ]]; then
      _log "  [acceptance] FAIL: ${cmd} (${reject_reason})"
      all_pass=1
      continue
    fi

    local -a argv=()
    # shellcheck disable=SC2206
    set -f
    argv=($cmd)
    set +f
    if [[ "${#argv[@]}" -eq 0 ]]; then
      continue
    fi

    local sandbox_profile=""
    local -a runner=()
    if command -v sandbox-exec >/dev/null 2>&1 && \
       sandbox-exec -p '(version 1) (allow default)' true >/dev/null 2>&1; then
      sandbox_profile="$(mktemp /tmp/night-acceptance-sandbox-XXXXXX.sb)"
      cat > "$sandbox_profile" <<SANDBOX
(version 1)
(deny default)
(allow process*)
(allow sysctl*)
(allow signal)
(allow file-read*)
(allow file-write* (subpath "$real_worktree"))
(deny network*)
SANDBOX
      runner=(sandbox-exec -f "$sandbox_profile")
    else
      runner=(env)
    fi

    if (
      cd "$real_worktree" 2>/dev/null || exit 1
      _run_with_timeout 30 "${runner[@]}" "${argv[@]}" >/dev/null 2>&1
    ); then
      _log "  [acceptance] PASS: ${cmd}"
    else
      _log "  [acceptance] FAIL: ${cmd}"
      all_pass=1
    fi
    [[ -n "$sandbox_profile" ]] && rm -f "$sandbox_profile" 2>/dev/null || true
  done <<< "$acceptance_cmds"

  return $all_pass
}

# ── .AUTONOMOUS_FREEZE mid-run guard ────────────────────────────────────────────
# Purpose: check if freeze was tripped since run started (e.g. by a lane).
# Usage: _freeze_check || break
# Gotchas: separate from kill_switch_check at start; called at lane boundaries.
_freeze_check() {
  local sentinel="${STATE}/.AUTONOMOUS_FREEZE"
  if [[ -f "$sentinel" ]]; then
    _log "MID-RUN FREEZE: .AUTONOMOUS_FREEZE appeared — halting remaining lanes"
    return 1
  fi
  return 0
}

# ── Kill in-flight lane PIDs (BUG-VII-04 fix) ─────────────────────────────────
# Purpose: on a freeze event, SIGTERM all background lane processes that are still
#   alive, then SIGKILL after 5s. Errs toward halting — this is a safety guard.
# Usage: _kill_inflight_lanes lane_pids_array_name [start_idx]
# Gotchas: PIDs that already exited are silently skipped (kill returns nonzero, ignored).
#   RESIDUAL: if a lane spawned sub-processes (e.g. claude CLI children), those are in
#   a separate process group and require process-group kill (kill -- -PGID). The current
#   implementation kills only the direct bash subshell PID. For the claude CLI invoked
#   via gtimeout inside lane-dispatch.sh, gtimeout's own SIGTERM propagates to claude
#   because gtimeout sends the signal to the whole process group — so coverage is good
#   in practice, but a lane that ignores SIGTERM in its own code could survive until the
#   gtimeout wall-clock cap fires. This residual is documented; a supervisor process
#   with PGID tracking would close it.
_kill_inflight_lanes() {
  local -n _pids_ref=$1
  local start_idx="${2:-0}"
  local i
  local killed=0
  for (( i=start_idx; i < ${#_pids_ref[@]}; i++ )); do
    local pid="${_pids_ref[$i]}"
    if kill -0 "$pid" 2>/dev/null; then
      _log "FREEZE-KILL: sending SIGTERM to in-flight lane PID $pid"
      kill -TERM "$pid" 2>/dev/null || true
      (( killed++ )) || true
    fi
  done
  if (( killed > 0 )); then
    # Brief grace period, then SIGKILL survivors
    sleep 5
    for (( i=start_idx; i < ${#_pids_ref[@]}; i++ )); do
      local pid="${_pids_ref[$i]}"
      if kill -0 "$pid" 2>/dev/null; then
        _log "FREEZE-KILL: grace expired, SIGKILL PID $pid"
        kill -KILL "$pid" 2>/dev/null || true
      fi
    done
  fi
  _log "FREEZE-KILL: terminated ${killed} in-flight lane(s)"
}

# ── Main entry point ────────────────────────────────────────────────────────────
main() {
  _log "=== night-runner start ==="

  # Stamp heartbeat at START (AUTO-5 positive-heartbeat contract)
  printf '%s\n' "$(date +%s)" > "${STATE}/night-runner.heartbeat"

  # Precondition checks — exits on failure
  _check_preconditions

  # Reset per-night budget counter and autonomous registry
  budget_night_reset
  autonomous_registry_reset 2>/dev/null || true

  # Remove done sentinel from any prior run (AUTO-5)
  rm -f "${STATE}/night-runner.done" 2>/dev/null || true

  # Load approved tasks
  local -a task_files=()
  while IFS= read -r line; do
    [[ -n "$line" ]] && task_files+=("$line")
  done < <(_load_approved_tasks)

  local total_approved="${#task_files[@]}"
  _log "Approved tasks found: ${total_approved}"

  if [[ "$total_approved" -eq 0 ]]; then
    _log "Queue empty — nothing to dispatch. Exiting cleanly."
    printf '%s\n' "$(date +%s)" > "${STATE}/night-runner.done"
    exit 0
  fi

  # ── Dispatch loop ─────────────────────────────────────────────────────────────
  # Dispatches up to BUDGET_MAX_TASKS_PER_NIGHT lanes; stops early on freeze or quota-abort.
  # Lane PIDs are tracked for parallel execution monitoring.
  local lane_num=0
  local -a lane_pids=()
  local -a lane_task_ids=()
  local -a lane_task_files=()
  local tasks_started=0
  local quota_abort=0

  for task_file in "${task_files[@]}"; do
    # Mid-run freeze check at each lane boundary (BUG-VII-04: also kill already-spawned lanes)
    _freeze_check || {
      _log "Halting dispatch due to mid-run freeze — killing ${#lane_pids[@]} already-spawned lane(s)"
      _kill_inflight_lanes lane_pids 0
      break
    }

    local task_id
    task_id="$(_q_field "$task_file" "id")"
    [[ -z "$task_id" ]] && task_id="$(basename "$task_file" .md)"

    local intent
    intent="$(_q_field "$task_file" "intent")"

    local source_tag
    source_tag="$(_q_field "$task_file" "source")"
    [[ -z "$source_tag" ]] && source_tag="explicit"

    # Budget gate — 4th task triggers BUDGET-ABORT and trips kill-switch
    if ! budget_task_start "$task_id"; then
      _log "BUDGET-ABORT: task cap reached — tripping kill-switch and halting"
      kill_switch_trip "auto" "night-runner: BUDGET_MAX_TASKS_PER_NIGHT exceeded"
      quota_abort=1
      break
    fi

    (( lane_num++ )) || true
    (( tasks_started++ )) || true

    _log "Dispatching lane-${lane_num}: task_id=${task_id}"

    # Register lane in autonomous-registry BEFORE spawning
    if ! autonomous_registry_register "lane-${lane_num}" "$task_id" \
      "{\"session_id\":\"lane-${lane_num}\",\"pid\":\"$$\"}" >/dev/null 2>&1; then
      _log "FATAL: failed to register lane-${lane_num}; marking task failed and skipping spawn"
      _q_set_status "$task_file" "failed"
      continue
    fi

    # Emit queue_event{started}
    _nr_emit_queue "started" "$task_id" "$source_tag" "$intent" "$lane_num"

    # Mark task as started in queue file
    _q_set_status "$task_file" "started"

    # Stamp heartbeat at each lane boundary (AUTO-5)
    printf '%s\n' "$(date +%s)" > "${STATE}/night-runner.heartbeat"

    # Spawn lane in background for parallel execution
    local lane_log="${STATE}/lane-${lane_num}-${task_id}.log"
    (
      export AUTONOMOUS_RUN=1
      export SESSION_ID="lane-${lane_num}"
      export STATE="$STATE"
      bash "$LANE_DISPATCH" \
        --lane "$lane_num" \
        --task-id "$task_id" \
        --task-file "$task_file" \
        --state "$STATE" \
        2>&1
    ) > "$lane_log" 2>&1 &

    lane_pids+=("$!")
    lane_task_ids+=("$task_id")
    lane_task_files+=("$task_file")
  done

  # ── Wait for all dispatched lanes ─────────────────────────────────────────────
  _log "Waiting for ${#lane_pids[@]} lane(s) to complete..."
  local i
  for (( i=0; i < ${#lane_pids[@]}; i++ )); do
    local pid="${lane_pids[$i]}"
    local tid="${lane_task_ids[$i]}"
    local tfile="${lane_task_files[$i]}"
    local cur_lane=$(( i + 1 ))

    # Check for mid-run freeze before processing each lane result.
    # BUG-VII-04 fix: on freeze, kill ALL remaining in-flight PIDs (including those
    # already dispatched but not yet waited on), not just break out of result collection.
    _freeze_check || {
      _log "Freeze detected while waiting for lanes — killing in-flight PIDs and aborting"
      _kill_inflight_lanes lane_pids "$i"
      break
    }

    # Wait for this lane's background process
    wait "$pid" 2>/dev/null || true

    local lane_log="${STATE}/lane-${cur_lane}-${tid}.log"

    # ── ANTI-SELF-REPORT: check quota signals in lane output ──────────────────
    if [[ -f "$lane_log" ]]; then
      if grep -qE "$BUDGET_QUOTA_PATTERNS" "$lane_log" 2>/dev/null; then
        _log "QUOTA-ABORT: quota pattern in lane-${cur_lane} output — tripping kill-switch"
        budget_check_quota_abort "$lane_log" "$tid" || true
        _q_set_status "$tfile" "enqueued"
        quota_abort=1
        break
      fi
    fi

    # ── ANTI-SELF-REPORT: re-run acceptance commands (§2.3 Addition A) ─────────
    # Determine worktree path from manifest if written by the lane
    local manifest_file="${STATE}/runs/${tid}.json"
    local worktree=""
    if [[ -f "$manifest_file" ]]; then
      worktree="$(jq -r '.worktree // ""' "$manifest_file" 2>/dev/null || true)"
    fi
    # Fallback: derive worktree from convention
    if [[ -z "$worktree" ]]; then
      local repo
      repo="$(_q_field "$tfile" "repo")"
      if [[ -n "$repo" && -d "$repo" ]]; then
        worktree="${repo}/../wt-night/${tid}"
      fi
    fi

    if _verify_acceptance "$tid" "$tfile" "${worktree:-/tmp}"; then
      _log "Lane-${cur_lane} [${tid}]: acceptance PASSED — marking staged"
      _q_set_status "$tfile" "staged"
      local source_tag intent
      source_tag="$(_q_field "$tfile" "source")"
      intent="$(_q_field "$tfile" "intent")"
      _nr_emit_queue "staged" "$tid" "${source_tag:-explicit}" "${intent:-}" "$cur_lane"
    else
      _log "Lane-${cur_lane} [${tid}]: acceptance FAILED (anti-self-report) — marking failed"
      _q_set_status "$tfile" "failed"
    fi

    # Deregister lane from autonomous-registry
    autonomous_registry_deregister "lane-${cur_lane}" 2>/dev/null || true
  done

  # ── Final state ────────────────────────────────────────────────────────────────
  if [[ "$quota_abort" -eq 1 ]]; then
    _log "Night run ended with QUOTA-ABORT — kill-switch may be tripped"
    printf 'QUOTA-ABORT\n' > "${STATE}/night-runner.done"
  else
    _log "Night run complete. Tasks started: ${tasks_started}"
    printf '%s\n' "$(date +%s)" > "${STATE}/night-runner.done"
  fi

  # Stamp last-run for harness doctor
  printf '%s\n' "$(date +%s)" > "${STATE}/com.yklin.night-runner.last-run"

  # Final heartbeat stamp
  printf '%s\n' "$(date +%s)" > "${STATE}/night-runner.heartbeat"

  _log "=== night-runner done ==="
}

main "$@"
