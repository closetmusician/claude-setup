#!/usr/bin/env bash
# ABOUTME: PreToolUse hook (Write/Edit): an orchestrator writes specs, plans and orchestration
# ABOUTME: docs; workers (agent_id present) write everything else. Armed by $STATE/.active.
# ABOUTME: Allow lists live in roles.json and depend on workspace kind (code vs docs).
# ABOUTME: Paths match by whole directory segment, never by substring.
# ABOUTME: Outputs {"decision":"block","reason":"..."} to block; exit 0 alone allows.

set -euo pipefail

# Safety net: never crash-block the user on hook failure.
trap 'exit 0' ERR

if ! command -v jq &>/dev/null; then
  echo "role-enforcement: jq not found, skipping checks" >&2
  exit 0
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/project-root.sh"
source "${SCRIPT_DIR}/lib/workspace-kind.sh"

# Governance only active when sentinel exists (created by lead-orchestrator)
[[ ! -f "$(get_governance_state_dir)/.active" ]] && exit 0

INPUT=$(cat)

# ─── Subagent (worker) → always allow ───
[[ -n "$(echo "$INPUT" | jq -r '.agent_id // empty')" ]] && exit 0

ROLES_FILE="${SCRIPT_DIR}/roles.json"
[[ -f "$ROLES_FILE" ]] || { echo "role-enforcement: roles.json missing, allowing" >&2; exit 0; }

TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // empty')
jq -e --arg t "$TOOL_NAME" '.orchestrator.denied_tools | index($t)' "$ROLES_FILE" >/dev/null || exit 0

FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')
[[ -z "$FILE_PATH" ]] && exit 0

# ─── Resolve the file relative to the session's project root ───
ROOT="$(workspace_root "$PWD")"
FILE="$(physical_path "$FILE_PATH" "$PWD")"
REL="$(rel_to_root "$FILE" "$ROOT")" || exit 0   # outside the project: not our concern
BASE="$(basename "$REL")"

# roles_list <key>
# Purpose: print one entry per line from .orchestrator.<key> in roles.json.
# Usage: while IFS= read -r x; do ...; done < <(roles_list allow_prefixes)
# Gotchas: a missing key prints nothing.
roles_list() { jq -r --arg k "$1" '.orchestrator[$k] // [] | .[]' "$ROLES_FILE"; }

# matches_prefix <key>
# Purpose: exit 0 when REL starts with any repo-relative prefix listed under <key>.
# Usage: matches_prefix allow_prefixes && exit 0
# Gotchas: prefixes end with "/" so "docs/" never matches "docsx/".
matches_prefix() {
  local p
  while IFS= read -r p; do
    [[ -n "$p" && "$REL" == "$p"* ]] && return 0
  done < <(roles_list "$1")
  return 1
}

# ─── Always allowed, any workspace kind ───
SEGMENTS=()
while IFS= read -r s; do [[ -n "$s" ]] && SEGMENTS+=("$s"); done < <(roles_list allow_segments)
[[ ${#SEGMENTS[@]} -gt 0 ]] && has_segment "$REL" "${SEGMENTS[@]}" && exit 0
matches_prefix allow_prefixes && exit 0
while IFS= read -r g; do
  # shellcheck disable=SC2053
  [[ -n "$g" && "$BASE" == $g ]] && exit 0
done < <(roles_list allow_basenames)

# ─── Kind-specific allow lists ───
KIND="$(get_workspace_kind "$ROOT" 2>/dev/null)"
if [[ "$KIND" == "code" ]]; then
  matches_prefix code_allow_prefixes && exit 0
  ALLOWED="docs/, docs/plans/, qa/, specs/, and *spec*/*plan*/*review*.md files"
else
  EXT="$(printf '%s' "${BASE##*.}" | tr '[:upper:]' '[:lower:]')"
  [[ "$BASE" == *.* ]] && jq -e --arg e "$EXT" '.orchestrator.docs_allow_ext | index($e)' "$ROLES_FILE" >/dev/null && exit 0
  ALLOWED="md, txt, yaml, yml and json files"
fi

printf '{"decision": "block", "reason": "Role Enforcement: orchestrator cannot %s %s in this %s workspace. The orchestrator may write %s. Delegate this file to a worker (Agent with model sonnet)."}\n' \
  "$TOOL_NAME" "$REL" "$KIND" "$ALLOWED"
exit 0
