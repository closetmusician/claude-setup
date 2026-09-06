#!/usr/bin/env bash
# ABOUTME: PreToolUse hook enforcing orchestration step ordering via sentinels AND disk checks.
# ABOUTME: Two enforcement layers: (1) sentinel gates block out-of-order spawns,
# ABOUTME: (2) acceptance-test-on-disk check blocks coder spawns when no tests exist.
# ABOUTME: Layer 2 is LLM-proof — even if the orchestrator never sets sentinels,
# ABOUTME: coder/fix agents are blocked until acceptance test artifacts exist on disk.
# ABOUTME: Exit 0 = allow, JSON block output = reject with reason.

set -euo pipefail

# Safety net: never block on hook failure
trap 'exit 0' ERR

source "$HOME/.claude/scripts/governance/lib/project-root.sh"

# Bail if jq missing
if ! command -v jq &>/dev/null; then
  exit 0
fi

GOV_DIR="$(get_governance_state_dir)"

# Only active when governance is active
[[ ! -f "$GOV_DIR/.active" ]] && exit 0

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

# ─── Also extract description (for Agent tool calls) ───
DESCRIPTION=$(echo "$INPUT" | jq -r '.tool_input.description // empty')
COMBINED="${DESCRIPTION} ${PROMPT}"

# ─── Detect what the orchestrator is trying to spawn ───
# We identify the subagent role by prompt content patterns

IS_CODER_SPAWN=false
IS_QA_SPAWN=false
IS_GARRY_SPAWN=false

# QA/non-coder detection FIRST (takes priority — QA agents are always allowed through)
if echo "$COMBINED" | grep -qiE '(qa.*(test|tester|writer)|test.*writer|acceptance.*test|e2e.*test|run.*test|verify|explore|extract|read.*spec|architect)'; then
  IS_QA_SPAWN=true
fi

# Coder detection: formal template patterns + informal fix/implement patterns
# Layer 1: formal coder templates
if echo "$PROMPT" | grep -qiE '(CODER subagent|TDD Protocol|ready-for-review|acceptance.*tests.*RED)'; then
  IS_CODER_SPAWN=true
fi
# Layer 2: informal fix/implement patterns (catches hand-crafted prompts)
if echo "$COMBINED" | grep -qiE '(fix bug|fix issue|fix the|fixing|implement|write code|write the code|write implementation|feature-dev|make.*pass|add.*to.*select|add.*field|plumb.*param|smallest.*fix)'; then
  IS_CODER_SPAWN=true
fi

# QA takes priority over coder (a "QA: test and fix" agent is QA, not coder)
if [[ "$IS_QA_SPAWN" == "true" ]]; then
  IS_CODER_SPAWN=false
fi

# Garry-Review detection: architecture/code quality review patterns
if echo "$PROMPT" | grep -qiE '(garry.*review|code.*review.*architecture|review.*findings)'; then
  IS_GARRY_SPAWN=true
fi

# ─── GATE: .gate-pre-coder ───
# When .gate-pre-coder exists, QA test-writer just finished but Pre-Coder checks
# haven't been verified yet. Block Coder spawns until gate is cleared.
if [[ -f "${GOV_DIR}/.gate-pre-coder" ]]; then
  if [[ "$IS_CODER_SPAWN" == "true" ]]; then
    block_and_exit "Pre-Coder gate active. You MUST verify acceptance tests are committed and RED (failing) BEFORE spawning Coder. Clear gate with: rm ${GOV_DIR}/.gate-pre-coder"
  fi
fi

# ─── GATE: .gate-pre-qa ───
# When .gate-pre-qa exists, it means coder just finished but pre-QA checks
# haven't been verified yet. Block QA/Review spawns until gate is cleared.
if [[ -f "${GOV_DIR}/.gate-pre-qa" ]]; then
  if [[ "$IS_QA_SPAWN" == "true" ]] || [[ "$IS_GARRY_SPAWN" == "true" ]]; then
    block_and_exit "Pre-QA gate active. You MUST verify TDD Evidence table and run test suite BEFORE spawning QA or review subagents. Clear gate with: rm ${GOV_DIR}/.gate-pre-qa"
  fi
fi

# ─── GATE: .gate-qa-c1 ───
# When .gate-qa-c1 exists, QA C1 is in progress or expected next.
# Block C2 spawns (detect by cycle-2 reference).
if [[ -f "${GOV_DIR}/.gate-qa-c1" ]]; then
  if echo "$PROMPT" | grep -qiE '(cycle-2|c2.*regression|qa.*mode.*cycle-2)'; then
    block_and_exit "QA C1 gate active. Cycle 1 must complete and produce cycle-1.md BEFORE spawning Cycle 2. Clear gate with: rm ${GOV_DIR}/.gate-qa-c1"
  fi
fi

# ─── GATE: .gate-spec-diff ───
# When .gate-spec-diff exists, spec-diff verification is required before
# marking the task complete. Block any "task complete" signals.
# This gate is checked by the orchestrator itself, not by agent spawning.
# It's enforced via the Write hook on orchestration log updates.
# (Included here for completeness — primary enforcement is in validate-artifact.sh)

# ═══════════════════════════════════════════════════════════════════════
# LAYER 2: ACCEPTANCE-TEST-ON-DISK CHECK (LLM-proof)
# Even if the orchestrator never set sentinels (e.g., "skip all permissions"),
# this check physically blocks coder/fix agents when no acceptance tests exist.
# This cannot be bypassed by reformatting prompts or rationalizing instructions.
# ═══════════════════════════════════════════════════════════════════════

if [[ "$IS_CODER_SPAWN" == "true" ]]; then
  # Extract task ID patterns from the prompt (T-XXX, T-RC-1, T-ST-1, etc.)
  TASK_IDS=$(echo "$COMBINED" | grep -oE 'T-[A-Za-z]*-?[0-9]+' | sort -u)

  FOUND_ACCEPTANCE_TESTS=false

  if [[ -n "$TASK_IDS" ]]; then
    # Check for task-specific acceptance test artifacts
    while IFS= read -r tid; do
      [[ -z "$tid" ]] && continue
      if find . -path "*/qa/*" -name "*${tid}*acceptance-tests*" -type f 2>/dev/null | grep -q .; then
        FOUND_ACCEPTANCE_TESTS=true
        break
      fi
    done <<< "$TASK_IDS"
  fi

  # Fallback: check for ANY acceptance test artifacts in qa/
  if [[ "$FOUND_ACCEPTANCE_TESTS" == "false" ]]; then
    if find . -path "*/qa/*" -name "*acceptance-tests*" -type f 2>/dev/null | grep -q .; then
      FOUND_ACCEPTANCE_TESTS=true
    fi
  fi

  if [[ "$FOUND_ACCEPTANCE_TESTS" == "false" ]]; then
    TASK_HINT=""
    if [[ -n "$TASK_IDS" ]]; then
      FIRST_TID=$(echo "$TASK_IDS" | head -1)
      TASK_HINT=" Expected: qa/FEAT-XXX/${FIRST_TID}-acceptance-tests.md."
    fi
    block_and_exit "No acceptance tests found on disk.${TASK_HINT} R2 TDD requires QA Test Writer to write and commit acceptance tests (RED) BEFORE any coder/fix agent is spawned. 'Skip permissions' does NOT mean skip this gate. Spawn a QA Test Writer agent first using templates/qa-prompt.md (PHASE=acceptance-red)."
  fi
fi

exit 0
