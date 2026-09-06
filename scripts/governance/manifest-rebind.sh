#!/usr/bin/env bash
# ABOUTME: Clears the agent_id claim for a (task, role) entry in run-manifest.json so a
# ABOUTME: re-spawned agent can claim it via first-write-wins without a DENY. Invoked by
# ABOUTME: the orchestrator between legitimate re-spawns (e.g., QA strengthening RED tests).
# ABOUTME: NOT a sentinel deletion — operates only on one manifest field, atomic write.
# ABOUTME: Usage: manifest-rebind.sh <task_id> <role>   (e.g., T-001 qa-test-writer)

set -uo pipefail
trap 'exit 0' ERR

command -v jq >/dev/null 2>&1 || exit 0

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/project-root.sh"

STATE=$(get_governance_state_dir)
MANIFEST="$STATE/run-manifest.json"

TASK="${1:-}"
ROLE="${2:-}"

[[ -z "$TASK" || -z "$ROLE" ]] && { echo "Usage: manifest-rebind.sh <task_id> <role>" >&2; exit 1; }
[[ -f "$MANIFEST" ]] || { echo "No run-manifest.json in $STATE — nothing to rebind." >&2; exit 0; }

TMP_MANIFEST="$STATE/run-manifest.json.tmp.$$"

# Null out the agent_id and bound_ts for the matching entry — atomic via tmp+mv (D9).
jq --arg t "$TASK" --arg r "$ROLE" \
  '(.tasks[] | select(.task_id == $t and .role == $r)) |= (.agent_id = null | .bound_ts = null)' \
  "$MANIFEST" > "$TMP_MANIFEST" && mv -f "$TMP_MANIFEST" "$MANIFEST" || exit 0

echo "Rebound $TASK/$ROLE — agent_id cleared. Next writer will claim via first-write-wins."
exit 0
