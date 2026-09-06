#!/usr/bin/env bash
# ABOUTME: Pillar III-2 nightly flywheel orchestrator. Queries new incidents since last
# ABOUTME: cursor, mints eval fixtures (mint-fixture.sh), drafts candidate patches via a
# ABOUTME: write-incapable claude -p call (Read/Grep/Glob only), writes diffs to state/
# ABOUTME: flywheel/drafts/, then runs recall-miss-monitor and advances the cursor.
# ABOUTME: Fail-open per step: one bad step logs + continues; never aborts the night.

set -uo pipefail
# Per-step fail-open: errors in individual steps are trapped and logged, not fatal.
# The global trap handles unexpected top-level failures only.
trap 'echo "[nightly-flywheel] WARN: unexpected error on line $LINENO — continuing" >&2' ERR

# ── Dependency check ──────────────────────────────────────────────────────────
command -v jq >/dev/null 2>&1 || { echo "[nightly-flywheel] SKIP: jq not found" >&2; exit 0; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAUDE_SCRIPTS="$(cd "$SCRIPT_DIR/.." && pwd)"
HARNESS="${HARNESS_BIN:-${HOME}/.claude/bin/harness}"
MINT_SH="${SCRIPT_DIR}/mint-fixture.sh"
RECALL_MISS="${CLAUDE_SCRIPTS}/recall-miss-monitor.sh"
TIMEOUT_LIB="${CLAUDE_SCRIPTS}/lib/timeout.sh"
DRAFT_PROMPT="${CLAUDE_SCRIPTS}/templates/flywheel-draft-prompt.md"

# ── Resolve STATE directory ───────────────────────────────────────────────────
# Purpose: find the governance state dir for cursor + drafts.
# Production: ~/.claude is a git repo → STATE = .agents/claude-governance
# Tests: override via $STATE env var.
# Gotchas: never hardcode; use env override for test isolation.
if [[ -n "${STATE:-}" ]]; then
  _STATE_DIR="$STATE"
else
  _claude_top="$(git -C "${HOME}/.claude" rev-parse --show-toplevel 2>/dev/null)" || _claude_top=""
  if [[ -n "$_claude_top" ]]; then
    _STATE_DIR="${_claude_top}/.agents/claude-governance"
  else
    _STATE_DIR="${HOME}/.claude/state"
  fi
fi

CURSOR_FILE="${_STATE_DIR}/state/flywheel.cursor"
DRAFTS_DIR="${_STATE_DIR}/state/flywheel/drafts"
LAST_RUN_STAMP="${_STATE_DIR}/state/com.yklin.nightly-flywheel.last-run"

# ── Claude model + timeout ────────────────────────────────────────────────────
# Draft model: sonnet (per spec §Task 2 — sonnet drafts patches)
DRAFT_MODEL="${FLYWHEEL_DRAFT_MODEL:-claude-sonnet-4-5}"
DRAFT_TIMEOUT="${FLYWHEEL_DRAFT_TIMEOUT_SECS:-90}"
CLAUDE_BIN="${CLAUDE_BIN:-claude}"

# ── Diff allowlist: BLOCK patches touching the eval runner or corpus ──────────
# Purpose: prevent a rogue LLM draft from rewriting its own judge (CON-9, spec §2).
# Any draft touching these paths is discarded with an explicit log entry.
# Gotchas: match on path strings inside the diff (--- a/<path> / +++ b/<path> lines).
_BLOCKED_PATHS=(
  "evals/"
  "run-harness-evals.sh"
  "bin/harness"
  ".claude/evals"
  "eval-corpus"
)

# Purpose: check if a draft diff touches any blocked path.
# Usage: _diff_touches_blocked <diff_content>  → 0 if blocked, 1 if allowed
# Gotchas: checks unified diff +++ / --- header lines only (not content lines).
_diff_touches_blocked() {
  local diff_content="$1"
  local blocked
  for blocked in "${_BLOCKED_PATHS[@]}"; do
    if printf '%s' "$diff_content" | grep -E "^(\+\+\+|---) " | grep -qF "$blocked"; then
      return 0  # blocked
    fi
  done
  return 1  # allowed
}

# ── Logging helper ────────────────────────────────────────────────────────────
_log() { printf '[nightly-flywheel] %s\n' "$*" >&2; }

# ── Setup directories ─────────────────────────────────────────────────────────
mkdir -p "${DRAFTS_DIR}" "${_STATE_DIR}/state" 2>/dev/null || true

# ── Load timeout lib ──────────────────────────────────────────────────────────
# shellcheck source=/dev/null
[[ -f "$TIMEOUT_LIB" ]] && source "$TIMEOUT_LIB" 2>/dev/null || true

# ── Timestamp helper ──────────────────────────────────────────────────────────
_now_iso() {
  if command -v gdate >/dev/null 2>&1; then
    gdate -u +%Y-%m-%dT%H:%M:%S.%3NZ 2>/dev/null && return
  fi
  python3 -c "
from datetime import datetime, timezone
t = datetime.now(timezone.utc)
print(t.strftime('%Y-%m-%dT%H:%M:%S.')+str(t.microsecond//1000).zfill(3)+'Z')
" 2>/dev/null || date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo "1970-01-01T00:00:00Z"
}

# =============================================================================
# STEP 1: Query new incidents since last cursor
# =============================================================================
# Purpose: read the cursor timestamp (or default to 7d ago on first run), query
#   harness for new incident events, collect as ndjson lines.
# Gotchas: harness query accepts ISO8601 timestamps for --since. Cursor stores
#   the ts of the last-processed incident. Empty result → stamp + exit 0 (no cost).

_log "[1/6] Querying incidents since cursor"

# Read cursor (ISO8601 timestamp or duration string)
_cursor=""
if [[ -f "$CURSOR_FILE" ]]; then
  _cursor="$(cat "$CURSOR_FILE" 2>/dev/null | tr -d '[:space:]')" || _cursor=""
fi
if [[ -z "$_cursor" ]]; then
  # First run: look back 7 days
  _cursor="7d"
  _log "  No cursor found — defaulting to --since 7d"
else
  _log "  Cursor: $_cursor"
fi

# Query incidents
_incidents_tmp="$(mktemp /tmp/nightly-fw-incidents-XXXXXX.ndjson 2>/dev/null)" || {
  _log "  ERROR: mktemp failed — aborting"; exit 0
}
_step1_ok=1
if [[ -x "$HARNESS" ]]; then
  "$HARNESS" query --type incident --since "$_cursor" 2>/dev/null > "$_incidents_tmp" || _step1_ok=0
else
  _log "  WARN: harness not found at $HARNESS"
  _step1_ok=0
fi

_incident_count=0
if [[ -s "$_incidents_tmp" ]]; then
  _incident_count="$(wc -l < "$_incidents_tmp" | tr -d ' ')" || _incident_count=0
fi

_log "  Found $_incident_count incident(s)"

# Early exit when nothing new (zero cost)
if [[ "$_incident_count" -eq 0 ]]; then
  _log "  No new incidents — stamping and exiting (empty-delta path)"
  _now_iso > "$LAST_RUN_STAMP" 2>/dev/null || true
  rm -f "$_incidents_tmp" 2>/dev/null || true
  exit 0
fi

# Track the latest ts seen for cursor advancement
_latest_ts=""

# =============================================================================
# STEP 2: Mint fixtures for new incidents
# =============================================================================
# Purpose: call mint-fixture.sh for each new incident to create eval fixtures.
# Gotchas: mint-fixture.sh is idempotent (skips already-minted session_id+class).
#   Failure of one mint doesn't stop others (per-incident fail-open).

_log "[2/6] Minting eval fixtures"

_minted_count=0
_minted_dirs=()

if [[ -f "$MINT_SH" ]]; then
  while IFS= read -r _incident_line; do
    [[ -z "$_incident_line" ]] && continue
    # Validate JSON
    if ! printf '%s' "$_incident_line" | jq -e . >/dev/null 2>&1; then
      _log "  SKIP: non-JSON line"
      continue
    fi
    # Track latest ts for cursor
    _ts_this="$(printf '%s' "$_incident_line" | jq -r '.ts // empty' 2>/dev/null)" || true
    if [[ -n "$_ts_this" ]] && [[ "$_ts_this" > "$_latest_ts" ]]; then
      _latest_ts="$_ts_this"
    fi
    # Mint fixture — fail-open: error in one mint doesn't abort the loop
    _minted_dir="$( { printf '%s\n' "$_incident_line" | bash "$MINT_SH" /dev/stdin 2>/dev/null; } )" || _minted_dir=""
    if [[ -n "$_minted_dir" ]] && [[ -d "$_minted_dir" ]]; then
      _minted_dirs+=("$_minted_dir")
      _minted_count=$(( _minted_count + 1 ))
    fi
  done < "$_incidents_tmp"
  _log "  Minted $_minted_count fixture(s)"
else
  _log "  WARN: mint-fixture.sh not found at $MINT_SH — skipping mint step"
  # Still need to collect latest_ts and incident lines for drafting
  while IFS= read -r _incident_line; do
    [[ -z "$_incident_line" ]] && continue
    _ts_this="$(printf '%s' "$_incident_line" | jq -r '.ts // empty' 2>/dev/null)" || true
    if [[ -n "$_ts_this" ]] && [[ "$_ts_this" > "$_latest_ts" ]]; then
      _latest_ts="$_ts_this"
    fi
  done < "$_incidents_tmp"
fi

# =============================================================================
# STEP 3: Draft candidate patches via write-incapable claude call
# =============================================================================
# Purpose: for each incident, call claude -p with Read/Grep/Glob only (no Write/Edit)
#   using the flywheel-draft-prompt.md template. Capture stdout as the draft diff.
# Gotchas: LLM CANNOT write files. The nightly-flywheel OWNS all writes (step 4).
#   Uses scripts/lib/timeout.sh for the claude call. One failure → log + continue.

_log "[3/6] Drafting patches (write-incapable claude calls)"

_draft_count=0
_draft_files=()

if [[ ! -f "$DRAFT_PROMPT" ]]; then
  _log "  WARN: draft prompt template not found at $DRAFT_PROMPT — skipping draft step"
else

while IFS= read -r _incident_line; do
  [[ -z "$_incident_line" ]] && continue
  if ! printf '%s' "$_incident_line" | jq -e . >/dev/null 2>&1; then
    continue
  fi

  # Extract incident fields for template substitution
  _inc_ts="$(printf '%s' "$_incident_line" | jq -r '.ts // "unknown"' 2>/dev/null)" || _inc_ts="unknown"
  _inc_class="$(printf '%s' "$_incident_line" | jq -r '.payload.class // "unknown"' 2>/dev/null)" || _inc_class="unknown"
  _inc_source="$(printf '%s' "$_incident_line" | jq -r '.source // "unknown"' 2>/dev/null)" || _inc_source="unknown"
  _inc_detail="$(printf '%s' "$_incident_line" | jq -r '.payload.detail // (.payload | tostring)' 2>/dev/null)" || _inc_detail="no detail"
  _inc_session="$(printf '%s' "$_incident_line" | jq -r '.session_id // "unknown"' 2>/dev/null)" || _inc_session="unknown"

  # Build prompt from template (BSD-safe: no sed -i; use python3 for substitution)
  _prompt_tmp="$(mktemp /tmp/nightly-fw-prompt-XXXXXX.md 2>/dev/null)" || {
    _log "  WARN: mktemp failed for prompt — skipping incident $_inc_class/$_inc_ts"
    continue
  }
  python3 - "$DRAFT_PROMPT" "$_prompt_tmp" \
    "$_inc_ts" "$_inc_class" "$_inc_source" "$_inc_detail" "$_inc_session" <<'PYEOF' 2>/dev/null || {
import sys
template_path, out_path = sys.argv[1], sys.argv[2]
inc_ts, inc_class, inc_source, inc_detail, inc_session = sys.argv[3:8]
with open(template_path, 'r', errors='replace') as f:
    content = f.read()
content = content.replace('{{INCIDENT_TS}}', inc_ts)
content = content.replace('{{INCIDENT_CLASS}}', inc_class)
content = content.replace('{{INCIDENT_SOURCE}}', inc_source)
content = content.replace('{{INCIDENT_DETAIL}}', inc_detail)
content = content.replace('{{INCIDENT_SESSION_ID}}', inc_session)
with open(out_path, 'w') as f:
    f.write(content)
PYEOF
    rm -f "$_prompt_tmp" 2>/dev/null || true
    continue
  }

  # Run write-incapable claude with timeout
  _raw_output=""
  _claude_exit=0
  if command -v "$CLAUDE_BIN" >/dev/null 2>&1; then
    if declare -f _run_with_timeout >/dev/null 2>&1; then
      _raw_output="$(_run_with_timeout "$DRAFT_TIMEOUT" \
        "$CLAUDE_BIN" -p --model "$DRAFT_MODEL" \
        --allowedTools "Read Grep Glob" \
        < "$_prompt_tmp" 2>/dev/null)" || _claude_exit=$?
    else
      _raw_output="$("$CLAUDE_BIN" -p --model "$DRAFT_MODEL" \
        --allowedTools "Read Grep Glob" \
        < "$_prompt_tmp" 2>/dev/null)" || _claude_exit=$?
    fi
  else
    _log "  WARN: claude not found — skipping draft for $_inc_class"
    rm -f "$_prompt_tmp" 2>/dev/null || true
    continue
  fi
  rm -f "$_prompt_tmp" 2>/dev/null || true

  if [[ -z "$_raw_output" ]]; then
    if [[ $_claude_exit -eq 124 ]]; then
      _log "  WARN: claude timed out for incident class=$_inc_class — skipping"
    else
      _log "  WARN: empty output from claude for class=$_inc_class (exit=$_claude_exit) — skipping"
    fi
    continue
  fi

  # ── DIFF ALLOWLIST CHECK ──────────────────────────────────────────────────
  # Purpose: BLOCK any draft that touches eval runner or corpus paths.
  # This is the self-modification-forbidden gate (CON-9, spec §Task2).
  if _diff_touches_blocked "$_raw_output"; then
    _blocked_path=""
    for _bp in "${_BLOCKED_PATHS[@]}"; do
      if printf '%s' "$_raw_output" | grep -E "^(\+\+\+|---) " | grep -qF "$_bp"; then
        _blocked_path="$_bp"
        break
      fi
    done
    _log "  BLOCKED: draft for class=$_inc_class touches protected path '$_blocked_path' — discarded"
    # Write a block record (not a diff) so the run is auditable
    _block_slug="${_inc_class//[^A-Za-z0-9-]/-}"
    _block_ts_slug="${_inc_ts//[^0-9T]/-}"
    _block_file="${DRAFTS_DIR}/BLOCKED-${_block_slug}-${_block_ts_slug}.txt"
    {
      printf '# BLOCKED: draft touched protected path\n'
      printf '# incident_ts=%s class=%s\n' "$_inc_ts" "$_inc_class"
      printf '# blocked_path=%s\n' "${_blocked_path:-unknown}"
      printf '# Draft content was discarded for safety.\n'
    } > "$_block_file" 2>/dev/null || true
    continue
  fi

  # Step 4 (inline): write draft diff to drafts dir — NEVER applied to tracked files
  _slug="${_inc_class//[^A-Za-z0-9-]/-}"
  _ts_slug="${_inc_ts//[^0-9T]/-}"
  _draft_file="${DRAFTS_DIR}/${_slug}-${_ts_slug}.diff"

  if printf '%s\n' "$_raw_output" > "$_draft_file" 2>/dev/null; then
    _draft_files+=("$_draft_file")
    _draft_count=$(( _draft_count + 1 ))
    _log "  Wrote draft: $(basename "$_draft_file")"
  else
    _log "  WARN: failed to write draft file for class=$_inc_class"
  fi

done < "$_incidents_tmp"

fi  # end if DRAFT_PROMPT exists

_log "[4/6] Wrote $_draft_count draft diff(s) to $DRAFTS_DIR"
_log "  (Diffs are STAGED ONLY — never applied to tracked files)"

# =============================================================================
# STEP 5: Recall-miss monitor
# =============================================================================
# Purpose: call the standalone recall-miss-monitor.sh (Pillar V, V4).
# Gotchas: fail-open — if it exits non-zero or doesn't exist, log + continue.

_log "[5/6] Running recall-miss-monitor"
if [[ -f "$RECALL_MISS" ]]; then
  bash "$RECALL_MISS" 2>&1 | sed 's/^/  [recall-miss] /' >&2 || {
    _log "  WARN: recall-miss-monitor exited non-zero — continuing"
  }
else
  _log "  WARN: recall-miss-monitor.sh not found at $RECALL_MISS — skipping"
fi

# =============================================================================
# STEP 6: Advance cursor + stamp last-run
# =============================================================================
# Purpose: update the cursor to the latest incident ts seen, so next run only
#   processes new incidents. Stamp last-run for harness doctor stale detection.
# Gotchas: cursor is an ISO8601 ts — harness query --since accepts this format.

_log "[6/6] Advancing cursor"

if [[ -n "$_latest_ts" ]]; then
  _log "  New cursor: $_latest_ts"
  printf '%s\n' "$_latest_ts" > "$CURSOR_FILE" 2>/dev/null || {
    _log "  WARN: failed to write cursor file"
  }
else
  _log "  No incidents processed — cursor unchanged"
fi

# Stamp last-run
_now_iso > "$LAST_RUN_STAMP" 2>/dev/null || true

# Cleanup
rm -f "$_incidents_tmp" 2>/dev/null || true

_log "Done. minted=$_minted_count drafts=$_draft_count"
exit 0
