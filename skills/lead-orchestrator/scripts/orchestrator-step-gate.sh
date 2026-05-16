#!/usr/bin/env bash
# ABOUTME: PreToolUse hook enforcing orchestration step ordering via sentinels.
# ABOUTME: Prevents orchestrator from spawning subagents out of sequence.
# ABOUTME: Checks sentinel files in governance/state/ to enforce phase transitions.
# ABOUTME: Scoped to lead-orchestrator sessions (requires .active sentinel).
# ABOUTME: Exit 0 = allow, JSON block output = reject with reason.

set -euo pipefail

# Safety net: never block on hook failure
trap 'exit 0' ERR

# Bail if jq missing
if ! command -v jq &>/dev/null; then
  exit 0
fi

# Only active when governance is active
[[ ! -f "$HOME/.claude/scripts/governance/state/.active" ]] && exit 0

STATE_DIR="$HOME/.claude/scripts/governance/state"

# ─── Read input ───
INPUT=$(cat)

# Subagent-to-subagent: skip
AGENT_ID=$(echo "$INPUT" | jq -r '.agent_id // empty')
if [[ -n "$AGENT_ID" ]]; then
  exit 0
fi

# ─── Extract prompt ───
PROMPT=$(echo "$INPUT" | jq -r '.tool_input.prompt // empty')
if [[ -z "$PROMPT" ]]; then
  exit 0
fi

# GOVERNANCE_EXEMPT bypasses step gates too
if echo "$PROMPT" | grep -qi 'GOVERNANCE_EXEMPT'; then
  exit 0
fi

# ─── Helper: emit block JSON and exit ───
block_and_exit() {
  local reason="$1"
  printf '{"decision": "block", "reason": "Orchestrator Step Gate: %s"}\n' "$reason"
  exit 0
}

# ─── Detect what the orchestrator is trying to spawn ───
# We identify the subagent role by prompt content patterns

IS_CODER_SPAWN=false
IS_QA_SPAWN=false
IS_GARRY_SPAWN=false

# Coder detection: references coder subagent role or TDD protocol patterns
if echo "$PROMPT" | grep -qiE '(CODER subagent|TDD Protocol|ready-for-review|acceptance.*tests.*RED)'; then
  IS_CODER_SPAWN=true
fi

# QA Tester detection: references cycle-1/cycle-2, QA testing patterns
if echo "$PROMPT" | grep -qiE '(qa.*tester|cycle-1|cycle-2|qa.*cycle|test.*break)'; then
  IS_QA_SPAWN=true
fi

# Garry-Review detection: architecture/code quality review patterns
if echo "$PROMPT" | grep -qiE '(garry.*review|code.*review.*architecture|review.*findings)' && \
   echo "$PROMPT" | grep -qi 'GOVERNANCE_EXEMPT'; then
  # Garry review is GOVERNANCE_EXEMPT, so it won't reach here
  # But if someone forgets the exempt marker:
  IS_GARRY_SPAWN=true
fi

# ─── GATE: .gate-pre-coder ───
# When .gate-pre-coder exists, QA test-writer just finished but Pre-Coder checks
# haven't been verified yet. Block Coder spawns until gate is cleared.
if [[ -f "${STATE_DIR}/.gate-pre-coder" ]]; then
  if [[ "$IS_CODER_SPAWN" == "true" ]]; then
    block_and_exit "Pre-Coder gate active. You MUST verify acceptance tests are committed and RED (failing) BEFORE spawning Coder. Clear gate with: rm ${STATE_DIR}/.gate-pre-coder"
  fi
fi

# ─── GATE: .gate-pre-qa ───
# When .gate-pre-qa exists, it means coder just finished but pre-QA checks
# haven't been verified yet. Block QA/Review spawns until gate is cleared.
if [[ -f "${STATE_DIR}/.gate-pre-qa" ]]; then
  if [[ "$IS_QA_SPAWN" == "true" ]] || [[ "$IS_GARRY_SPAWN" == "true" ]]; then
    block_and_exit "Pre-QA gate active. You MUST verify TDD Evidence table and run test suite BEFORE spawning QA or review subagents. Clear gate with: rm ${STATE_DIR}/.gate-pre-qa"
  fi
fi

# ─── GATE: .gate-qa-c1 ───
# When .gate-qa-c1 exists, QA C1 is in progress or expected next.
# Block C2 spawns (detect by cycle-2 reference).
if [[ -f "${STATE_DIR}/.gate-qa-c1" ]]; then
  if echo "$PROMPT" | grep -qiE '(cycle-2|c2.*regression|qa.*mode.*cycle-2)'; then
    block_and_exit "QA C1 gate active. Cycle 1 must complete and produce cycle-1.md BEFORE spawning Cycle 2. Clear gate with: rm ${STATE_DIR}/.gate-qa-c1"
  fi
fi

# ─── GATE: .gate-spec-diff ───
# When .gate-spec-diff exists, spec-diff verification is required before
# marking the task complete. Block any "task complete" signals.
# This gate is checked by the orchestrator itself, not by agent spawning.
# It's enforced via the Write hook on orchestration log updates.
# (Included here for completeness — primary enforcement is in validate-artifact.sh)

exit 0
