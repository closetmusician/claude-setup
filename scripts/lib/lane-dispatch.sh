#!/usr/bin/env bash
# ABOUTME: VI-4 lane-dispatch — spawns one autonomous lane in an isolated git worktree.
# ABOUTME: Called by night-runner.sh per task; handles worktree setup, gtimeout claude invocation,
# ABOUTME: manifest parsing, and runner validation. Returns 0 on successful staging, 1 on failure.
# ABOUTME: Gotchas: never merges or pushes; AUTONOMOUS_RUN=1 must be set by caller.
# ABOUTME: BSD-safe; set -uo pipefail; uses gtimeout for hard wall-clock enforcement.

set -uo pipefail

# ── Argument parsing ────────────────────────────────────────────────────────────
# Purpose: parse --lane, --task-id, --task-file, --state from argv.
# Usage: lane-dispatch.sh --lane N --task-id <id> --task-file <path> --state <dir>
# Gotchas: all args required; exits 1 with usage on missing.
LANE_NUM=""
TASK_ID=""
TASK_FILE=""
STATE_DIR=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --lane)       LANE_NUM="${2:-}"; shift 2 ;;
    --task-id)    TASK_ID="${2:-}"; shift 2 ;;
    --task-file)  TASK_FILE="${2:-}"; shift 2 ;;
    --state)      STATE_DIR="${2:-}"; shift 2 ;;
    *)            echo "lane-dispatch: unknown arg: $1" >&2; exit 1 ;;
  esac
done

if [[ -z "$LANE_NUM" || -z "$TASK_ID" || -z "$TASK_FILE" || -z "$STATE_DIR" ]]; then
  echo "lane-dispatch: usage: lane-dispatch.sh --lane N --task-id <id> --task-file <path> --state <dir>" >&2
  exit 1
fi

if [[ ! -f "$TASK_FILE" ]]; then
  echo "lane-dispatch: task file not found: $TASK_FILE" >&2
  exit 1
fi

# ── Path setup ────────────────────────────────────────────────────────────────
LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source budget-kernel to get BUDGET_MAX_MINUTES_PER_TASK (DRY cap — MASTER-40 fix).
# Fail-open: if missing, fall back to the matching constant value.
# shellcheck source=scripts/lib/budget-kernel.sh
# shellcheck disable=SC1091
source "${LIB_DIR}/budget-kernel.sh" 2>/dev/null || readonly BUDGET_MAX_MINUTES_PER_TASK=45

# Validate TASK_ID: must be non-empty, alphanumeric/hyphen/underscore/dot only.
# Prevents path injection via task-controlled TASK_ID (e.g. "../../../evil"). MASTER-40.
if [[ -z "$TASK_ID" ]] || ! [[ "$TASK_ID" =~ ^[a-zA-Z0-9._-]+$ ]]; then
  echo "lane-dispatch: TASK_ID '${TASK_ID}' contains unsafe characters or is empty — rejecting" >&2
  exit 1
fi

MANIFEST_DIR="${STATE_DIR}/runs"
mkdir -p "$MANIFEST_DIR" 2>/dev/null || true
MANIFEST_FILE="${MANIFEST_DIR}/${TASK_ID}.json"

# ── Logging ───────────────────────────────────────────────────────────────────
_log() {
  local ts
  ts="$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo "unknown")"
  printf '[%s] [lane-%s] %s\n' "$ts" "$LANE_NUM" "$1" >&2
}

# ── Read frontmatter field from task file ───────────────────────────────────────
# Purpose: extract a scalar YAML frontmatter value from the task file.
# Usage: _field <key>
# Gotchas: strips surrounding quotes; reads first match only.
_field() {
  local key="$1"
  grep -E "^${key}:[[:space:]]" "$TASK_FILE" 2>/dev/null \
    | head -1 \
    | sed "s/^${key}:[[:space:]]*//" \
    | sed 's/[[:space:]]*$//' \
    | sed "s/^['\"]//;s/['\"]$//"
}

# ── Extract acceptance commands from frontmatter ────────────────────────────────
# Purpose: collect all acceptance list items for injection into the task prompt.
# Usage: _read_acceptance
# Gotchas: reads only within the frontmatter block (up to second ---).
_read_acceptance() {
  local fm_end
  fm_end="$(grep -n '^---$' "$TASK_FILE" 2>/dev/null | awk -F: 'NR==2{print $1}')"
  [[ -z "$fm_end" ]] && fm_end=60
  head -n "$fm_end" "$TASK_FILE" \
    | grep -E '^[[:space:]]+-[[:space:]]' \
    | sed 's/^[[:space:]]*-[[:space:]]*//' \
    | sed 's/^"//;s/"$//'
}

# ── Read task fields ─────────────────────────────────────────────────────────────
REPO="$(_field "repo")"
INTENT="$(_field "intent")"
MAX_MINUTES="$(_field "max_minutes")"
MODEL="$(_field "model")"
SOURCE_TAG="$(_field "source")"

# Validate repo path
if [[ -z "$REPO" || ! -d "$REPO" ]]; then
  _log "INVALID: repo not found: ${REPO:-<empty>}"
  exit 1
fi

# Default model to sonnet if unset
[[ -z "$MODEL" ]] && MODEL="sonnet"

# Default max_minutes to BUDGET_MAX_MINUTES_PER_TASK (from budget-kernel) if unset or invalid.
# MASTER-40: reads the single source of truth instead of hardcoding 45.
if ! [[ "$MAX_MINUTES" =~ ^[0-9]+$ ]] || (( MAX_MINUTES > BUDGET_MAX_MINUTES_PER_TASK )); then
  MAX_MINUTES="$BUDGET_MAX_MINUTES_PER_TASK"
fi
WALL_CLOCK_SECS=$(( MAX_MINUTES * 60 ))

# ── Worktree setup ───────────────────────────────────────────────────────────────
# Purpose: create an isolated git worktree for this task so parallel lanes don't collide.
# Usage: called once per lane at dispatch time.
# Gotchas: ~/.claude tasks use branch directly (no worktree — chain load safety per spec §2.4).
_setup_worktree() {
  local is_claude_dir=0
  [[ "$REPO" == "$HOME/.claude" || "$REPO" == "${HOME}/.claude" ]] && is_claude_dir=1

  if [[ "$is_claude_dir" -eq 1 ]]; then
    # For ~/.claude: create branch directly, no worktree
    WORKTREE="$REPO"
    BRANCH="night/${TASK_ID}"
    (cd "$REPO" && git checkout -b "$BRANCH" 2>/dev/null || git checkout "$BRANCH" 2>/dev/null || true)
    _log "Using direct branch: ${BRANCH} in ${REPO}"
  else
    # For repo tasks: create worktree in ../wt-night/<id>
    local parent
    parent="$(dirname "$REPO")"
    WORKTREE="${parent}/wt-night/${TASK_ID}"
    BRANCH="wt-night/${TASK_ID}"
    mkdir -p "${parent}/wt-night" 2>/dev/null || true
    (cd "$REPO" && \
      git worktree add "$WORKTREE" -b "$BRANCH" 2>/dev/null || \
      git worktree add "$WORKTREE" "$BRANCH" 2>/dev/null || true)
    _log "Worktree: ${WORKTREE} branch: ${BRANCH}"
  fi
}

# ── Build task prompt for the claude invocation ────────────────────────────────────
# Purpose: inject the task intent, acceptance list, and manifest-writing contract into the prompt.
# Usage: called in main; writes to a temp file consumed by claude -p.
# Gotchas: prompt must contain explicit anti-merge/anti-push instruction per spec §2.3.
_build_prompt() {
  local acceptance_block
  acceptance_block="$(_read_acceptance | sed 's/^/  - /')"

  cat <<PROMPT
You are an autonomous agent executing a single queued task in an isolated git worktree.
Your work is STAGED ONLY — you MUST NOT git push, git merge, or git push to any remote.

TASK ID: ${TASK_ID}
REPO: ${REPO}
WORKTREE: ${WORKTREE:-${REPO}}
BRANCH: ${BRANCH:-night/${TASK_ID}}
INTENT: ${INTENT}

ACCEPTANCE CRITERIA (you must satisfy ALL of these by running them):
${acceptance_block}

MANDATORY STEPS:
1. Work ONLY toward the acceptance criteria above. Do nothing outside their scope.
2. For each criterion: run it, verify it passes. Log result to progress block.
3. After each criterion attempt (pass or fail): update the manifest at ${MANIFEST_FILE}
   with the progress block (jq merge-patch so a kill preserves the last checkpoint).
4. When all criteria pass: commit your changes to branch ${BRANCH:-night/${TASK_ID}}.
   DO NOT merge, DO NOT push. Staged branch only.
5. Write final manifest to ${MANIFEST_FILE} with:
   - status: "done" (or "failed" / "needs-user" as appropriate)
   - acceptance array with exit_code (0=pass, 1=fail) for each criterion
   - progress block with completed_criteria, blockers, next_step
6. If blocked by an irreversible decision or P0: set status=needs-user and STOP.
   NEVER try to push or merge to resolve a block.

MANIFEST SCHEMA (write as JSON to ${MANIFEST_FILE}):
{
  "task_id": "${TASK_ID}",
  "status": "done|failed|needs-user",
  "worktree": "${WORKTREE:-${REPO}}",
  "branch": "${BRANCH:-night/${TASK_ID}}",
  "acceptance": [
    {"criterion": "<text>", "exit_code": 0}
  ],
  "progress": {
    "completed_criteria": [],
    "attempted": [],
    "blockers": [],
    "next_step": "",
    "scratch_ref": "",
    "wall_clock_elapsed_s": 0,
    "resume_count": 0
  }
}

HARD CONSTRAINTS (enforced by the runner; violations mark task failed):
- NEVER run: git push, git push --force, git merge, git push origin, hub push
- NEVER run: git push <remote>, gh pr create, gh pr merge
- Work only in the worktree path above
- If in doubt about scope: set status=needs-user and stop
PROMPT
}

# ── Write initial manifest ─────────────────────────────────────────────────────────
# Purpose: write a stub manifest before the claude call so a hard kill still leaves a record.
# Usage: called after worktree setup, before claude invocation.
# Gotchas: uses jq for safe JSON construction; fails silently to a minimal JSON stub.
_write_initial_manifest() {
  local ts
  ts="$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo "unknown")"
  local manifest
  manifest="$(jq -n \
    --arg task_id "$TASK_ID" \
    --arg worktree "${WORKTREE:-${REPO}}" \
    --arg branch "${BRANCH:-night/${TASK_ID}}" \
    --arg started_at "$ts" \
    '{task_id:$task_id, status:"in-progress", worktree:$worktree,
      branch:$branch, started_at:$started_at,
      acceptance:[], progress:{completed_criteria:[],attempted:[],
        blockers:[],next_step:"",scratch_ref:"",
        wall_clock_elapsed_s:0, resume_count:0}}' 2>/dev/null)" || \
    manifest="{\"task_id\":\"${TASK_ID}\",\"status\":\"in-progress\"}"
  printf '%s\n' "$manifest" > "$MANIFEST_FILE"
}

# ── Freeze-sentinel poll helper (BUG-VII-04 fix) ───────────────────────────────
# Purpose: check .AUTONOMOUS_FREEZE before each major phase; abort if present.
# Usage: _lane_freeze_check || exit 1
# Gotchas: $STATE_DIR is this lane's state dir (passed via --state). errs toward halting.
_lane_freeze_check() {
  local sentinel="${STATE_DIR}/.AUTONOMOUS_FREEZE"
  if [[ -f "$sentinel" ]]; then
    _log "LANE-FREEZE: .AUTONOMOUS_FREEZE detected — aborting lane for task ${TASK_ID}"
    # Update manifest so the runner knows why the lane stopped
    jq '.status = "failed" | .progress.blockers += ["kill-switch: AUTONOMOUS_FREEZE set mid-run"]' \
      "$MANIFEST_FILE" 2>/dev/null > "${MANIFEST_FILE}.tmp" && \
      mv "${MANIFEST_FILE}.tmp" "$MANIFEST_FILE" 2>/dev/null || true
    return 1
  fi
  return 0
}

# ── Main lane execution ────────────────────────────────────────────────────────────
WORKTREE=""
BRANCH=""

_setup_worktree

_write_initial_manifest

# Poll freeze sentinel before starting the (long-running) claude invocation.
# This is the between-task boundary — if a freeze arrived after this lane was
# registered but before work started, abort cleanly instead of invoking claude.
_lane_freeze_check || exit 1

# Build prompt file for the claude invocation
PROMPT_FILE="$(mktemp /tmp/night-lane-prompt-XXXXXX.md)"
trap 'rm -f "$PROMPT_FILE"' EXIT
_build_prompt > "$PROMPT_FILE"

_log "Invoking claude (model=${MODEL}, max=${MAX_MINUTES}min, task=${TASK_ID})"

# ── Invoke claude under gtimeout ─────────────────────────────────────────────────
# Purpose: execute the task agent with a hard wall-clock cap.
# Usage: gtimeout <secs> claude --model <model> -p <prompt>
# Gotchas: exit code 124 = timeout; output captured for quota-abort scan.
CLAUDE_OUTPUT_FILE="$(mktemp /tmp/night-lane-output-XXXXXX.txt)"
trap 'rm -f "$PROMPT_FILE" "$CLAUDE_OUTPUT_FILE"' EXIT

CLAUDE_EXIT=0
if command -v claude >/dev/null 2>&1; then
  gtimeout "${WALL_CLOCK_SECS}" \
    claude --model "$MODEL" -p "$(cat "$PROMPT_FILE")" \
    > "$CLAUDE_OUTPUT_FILE" 2>&1 || CLAUDE_EXIT=$?
else
  # claude not available — write a failed manifest for testing
  _log "WARNING: claude CLI not available — writing failed manifest"
  printf 'claude not available\n' > "$CLAUDE_OUTPUT_FILE"
  CLAUDE_EXIT=127
fi

if [[ "$CLAUDE_EXIT" -eq 124 ]]; then
  _log "TIMEOUT: task ${TASK_ID} hit ${MAX_MINUTES}min wall-clock limit"
  # Update manifest status to failed (timeout)
  jq '.status = "failed" | .progress.blockers += ["gtimeout: wall-clock limit exceeded"]' \
    "$MANIFEST_FILE" 2>/dev/null > "${MANIFEST_FILE}.tmp" && \
    mv "${MANIFEST_FILE}.tmp" "$MANIFEST_FILE" 2>/dev/null || true
fi

# Echo the claude output so the caller (night-runner) can scan it for quota strings
cat "$CLAUDE_OUTPUT_FILE" 2>/dev/null || true

_log "Lane ${LANE_NUM} complete: claude exit=${CLAUDE_EXIT}"
exit 0
