#!/usr/bin/env bash
# ABOUTME: PreToolUse hook (Read, Bash): stops an orchestrating session from pulling large
# ABOUTME: files into its own context. Caps: 32 KB per read, 8 KB for code files.
# ABOUTME: Armed by $STATE/.active, .orchestration-active or any .gate-* sentinel.
# ABOUTME: Subagents always pass. Kill switch HARNESS_READ_BUDGET=0. Fail-open on errors.
# ABOUTME: Spec: docs/plans/harness/governance-scope-spec.md §3 C6. Replaces orchestrator-context-guard.sh.

set -uo pipefail
trap 'exit 0' ERR

[[ "${HARNESS_READ_BUDGET:-1}" == "0" ]] && exit 0
command -v jq >/dev/null 2>&1 || { echo "read-budget-guard: jq not found, skipping" >&2; exit 0; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/project-root.sh"
source "${SCRIPT_DIR}/lib/workspace-kind.sh"

# ─── Sentinel gate: only orchestrating sessions are budgeted ───
STATE="$(get_governance_state_dir)"
ARMED=0
[[ -e "$STATE/.active" || -e "$STATE/.orchestration-active" ]] && ARMED=1
for f in "$STATE"/.gate-*; do [[ -e "$f" ]] && ARMED=1 && break; done
[[ "$ARMED" -eq 1 ]] || exit 0

INPUT="$(cat)"
printf '%s' "$INPUT" | jq -e . >/dev/null 2>&1 || exit 0
[[ -n "$(printf '%s' "$INPUT" | jq -r '.agent_id // empty')" ]] && exit 0

TOOL="$(printf '%s' "$INPUT" | jq -r '.tool_name // empty')"
CWD="$(printf '%s' "$INPUT" | jq -r '.cwd // empty')"; [[ -d "$CWD" ]] || CWD="$PWD"
CAP="${READ_CAP_BYTES:-32768}"
CODE_CAP="${CODE_READ_CAP_BYTES:-8192}"

# always_allow <path>
# Purpose: templates, rules and small planning indexes the orchestrator needs to run.
# Usage: always_allow "$FILE" && exit 0
# Gotchas: kept from orchestrator-context-guard.sh; .claude/skills SKILL.md files load via Skill anyway.
always_allow() {
  case "$1" in
    */.claude/phase.json|*/.claude/rules/*|*/.claude/templates/*|*/.claude/skills/*) return 0 ;;
    */templates/*|*/docs/spec-registry.yaml|*/docs/backlog.md|*/docs/.eng-planning/progress.json) return 0 ;;
  esac
  return 1
}

# deny <bytes> <cap> <what>
# Purpose: emit the PreToolUse deny decision with delegation guidance.
# Usage: deny 66150 32768 "temp/src.md"
# Gotchas: exit 2 plus JSON, matching the other read guards.
deny() {
  local r="READ BUDGET: this read would put about $(( $1 / 1024 )) KB of ${3} into the orchestrator's context (cap $(( $2 / 1024 )) KB). Delegate it: Agent(model: \"sonnet\", subagent_type: \"Explore\") with a specific question and a 15-line digest. Or read a smaller range (Read offset/limit, head -n, sed -n 'A,Bp')."
  jq -cn --arg r "$r" '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:$r}}'
  exit 2
}

if [[ "$TOOL" == "Read" ]]; then
  FILE="$(printf '%s' "$INPUT" | jq -r '.tool_input.file_path // empty')"
  [[ "$FILE" == /* ]] || FILE="$CWD/$FILE"
  [[ -f "$FILE" ]] || exit 0
  printf '%s' "$FILE" | grep -qiE '\.(png|jpe?g|gif|webp)$' && exit 0
  # A PDF read with a page range is bounded by the Read tool itself.
  printf '%s' "$FILE" | grep -qiE '\.pdf$' && [[ -n "$(printf '%s' "$INPUT" | jq -r '.tool_input.pages // empty')" ]] && exit 0
  always_allow "$FILE" && exit 0
  OFFSET="$(printf '%s' "$INPUT" | jq -r '.tool_input.offset // 1')"
  LIMIT="$(printf '%s' "$INPUT" | jq -r '.tool_input.limit // 2000')"
  [[ "$OFFSET" =~ ^[0-9]+$ && "$OFFSET" -ge 1 ]] || OFFSET=1
  [[ "$LIMIT" =~ ^[0-9]+$ ]] || LIMIT=2000
  # The Read tool cuts each line at 2000 characters, so cost each line the same way.
  BYTES="$(sed -n "${OFFSET},$(( OFFSET + LIMIT - 1 ))p" "$FILE" | cut -c1-2000 | wc -c | tr -d ' ')"
  LIMIT_CAP="$CAP"; is_code_ext "$FILE" && LIMIT_CAP="$CODE_CAP"
  [[ "${BYTES:-0}" -gt "$LIMIT_CAP" ]] && deny "$BYTES" "$LIMIT_CAP" "$(basename "$FILE")"
  exit 0
fi

if [[ "$TOOL" == "Bash" ]]; then
  CMD="$(printf '%s' "$INPUT" | jq -r '.tool_input.command // empty')"
  [[ -z "$CMD" ]] && exit 0
  read -r BYTES CODE_BYTES FIRST <<<"$(perl "${SCRIPT_DIR}/lib/bash-read-estimate.pl" "$CWD" "$CMD" 2>/dev/null)"
  [[ -z "${BYTES:-}" ]] && exit 0
  always_allow "${FIRST:-}" && exit 0
  [[ "${CODE_BYTES:-0}" -gt "$CODE_CAP" ]] && deny "$CODE_BYTES" "$CODE_CAP" "code ($(basename "${FIRST:-file}"))"
  [[ "$BYTES" -gt "$CAP" ]] && deny "$BYTES" "$CAP" "$(basename "${FIRST:-file}")"
  exit 0
fi

exit 0
