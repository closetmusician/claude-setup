#!/usr/bin/env bash
# ABOUTME: Stop hook (Phase 6.3): enqueues a selfcheck job when harness dirs were modified.
# ABOUTME: Fires on session Stop; reads .harness-dirty, builds a job spec to $STATE/queue/.
# ABOUTME: Never blocks interactively — enqueue-not-run. Total ceiling: 5s. Fail-open.
# ABOUTME: stop_hook_active: log only (mirrors completion-claim-guard retry pattern), exit 0.
# ABOUTME: PLANE GUARD: no-ops entirely when AUTONOMOUS_RUN=1 so .harness-dirty survives for
# ABOUTME: harness-selfcheck-autonomous.sh (which runs AFTER this in Stop hook order). On
# ABOUTME: interactive success also writes $STATE/.harness-selfcheck-ok stamp for night-runner.

set -uo pipefail
trap 'exit 0' ERR

command -v jq >/dev/null 2>&1 || exit 0

# ── PLANE SEPARATOR: autonomous plane must be handled by harness-selfcheck-autonomous.sh ─────
# The two Stop hooks share the .harness-dirty file. This script runs FIRST in the array.
# If we delete the flag here on an autonomous run, the autonomous hook reads nothing and
# the eval gate never fires (BUG-SEAMS-01). Yield the entire path to the autonomous hook.
[[ "${AUTONOMOUS_RUN:-}" == "1" ]] && exit 0

CLAUDE_DIR="${CLAUDE_DIR:-$HOME/.claude}"
DIRTY_FILE="$CLAUDE_DIR/state/.harness-dirty"
SELFCHECK_LOG="$CLAUDE_DIR/state/harness-selfcheck.log"

INPUT=$(cat 2>/dev/null) || exit 0
[[ -z "$INPUT" ]] && exit 0

# ── Loop protection: stop_hook_active ────────────────────────────────────────
SHA=$(printf '%s' "$INPUT" | jq -r '.stop_hook_active // false' 2>/dev/null) || SHA=false
if [[ "$SHA" == "true" ]]; then
  mkdir -p "$(dirname "$SELFCHECK_LOG")" 2>/dev/null || true
  printf '%s harness-selfcheck stop_hook_active retry — skipping enqueue\n' \
    "$(date -u +%Y-%m-%dT%H:%M:%SZ)" >> "$SELFCHECK_LOG" 2>/dev/null || true
  exit 0
fi

# ── Fast path: no dirty flag ──────────────────────────────────────────────────
[[ -f "$DIRTY_FILE" ]] || exit 0

# ── Read dirty paths ──────────────────────────────────────────────────────────
DIRTY_PATHS_ARR=()
while IFS= read -r line; do
  [[ -n "$line" ]] && DIRTY_PATHS_ARR+=("$line")
done < "$DIRTY_FILE"

[[ "${#DIRTY_PATHS_ARR[@]}" -eq 0 ]] && { rm -f "$DIRTY_FILE"; exit 0; }

# ── Resolve STATE dir via project-root.sh ────────────────────────────────────
_LIB="$CLAUDE_DIR/scripts/lib/project-root.sh"
if [[ -f "$_LIB" ]]; then
  # shellcheck source=/dev/null
  source "$_LIB" 2>/dev/null || true
fi
if declare -f get_governance_state_dir >/dev/null 2>&1; then
  STATE_DIR=$(get_governance_state_dir 2>/dev/null || echo "$HOME/.claude/state")
else
  TOPLEVEL=$(git rev-parse --show-toplevel 2>/dev/null || true)
  STATE_DIR="${TOPLEVEL:+$TOPLEVEL/.agents/claude-governance}"
  STATE_DIR="${STATE_DIR:-$HOME/.claude/state}"
fi

QUEUE_DIR="$STATE_DIR/queue"
mkdir -p "$QUEUE_DIR" 2>/dev/null || exit 0

# ── Build timestamp ───────────────────────────────────────────────────────────
if command -v python3 >/dev/null 2>&1; then
  TS=$(python3 -c "
from datetime import datetime, timezone
now = datetime.now(timezone.utc)
print(now.strftime('%Y-%m-%dT%H:%M:%S.') + str(now.microsecond // 1000).zfill(3) + 'Z')
" 2>/dev/null || date -u +%Y-%m-%dT%H:%M:%SZ)
else
  TS=$(date -u +%Y-%m-%dT%H:%M:%SZ)
fi

# ── Build JSON array of dirty paths ──────────────────────────────────────────
DIRTY_JSON=$(printf '%s\n' "${DIRTY_PATHS_ARR[@]}" | \
  jq -Rsc '[split("\n")[] | select(length>0)]' 2>/dev/null || echo '[]')

# ── Write job spec to queue ───────────────────────────────────────────────────
# Same enqueue shape as analysis-reflex.sh (II.4 reflex-queue pattern).
SAFE_TS="${TS//:/-}"
SAFE_TS="${SAFE_TS//./-}"
JOB_FILE="$QUEUE_DIR/selfcheck-${SAFE_TS}.json"

jq -cn \
  --arg ts "$TS" \
  --argjson dirty_paths "$DIRTY_JSON" \
  --arg suggested_cmd "scripts/run-harness-evals.sh --check-dirty" \
  '{
    ts: $ts,
    type: "selfcheck",
    dirty_paths: $dirty_paths,
    suggested_cmd: $suggested_cmd
  }' > "$JOB_FILE" 2>/dev/null || true

# ── Clear the dirty flag ──────────────────────────────────────────────────────
rm -f "$DIRTY_FILE" 2>/dev/null || true

# ── Write .harness-selfcheck-ok stamp (BUG-SEAMS-02 fix) ─────────────────────
# night-runner.sh checks this stamp (≤24h) as a precondition. The stamp must live
# under ~/.claude/state (durable) NOT under .agents/claude-governance (wiped by
# governance-cleanup.sh at SessionEnd). Interactive success = harness was reviewed.
DURABLE_STATE="${CLAUDE_DIR}/state"
mkdir -p "$DURABLE_STATE" 2>/dev/null || true
touch "$DURABLE_STATE/.harness-selfcheck-ok" 2>/dev/null || true

exit 0
