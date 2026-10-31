#!/usr/bin/env bash
# ABOUTME: TDD suite for spec C3: the VIBE spawn gates (pre-agent-gate, orchestrator
# ABOUTME: step gate, task-spec-gate) arm only in VIBE repos (.claude/phase.json), and
# ABOUTME: pre-agent-gate accepts any existing .md spec path, which ends the deadlock.
# ABOUTME: Run: bash scripts/tests/test-spawn-gate-scope.sh — exit 0 = all green.
# ABOUTME: Spec: docs/plans/harness/governance-scope-spec.md §3 C3, §4.

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PRE="${SCRIPT_DIR}/../governance/pre-agent-gate.sh"
STEP="${SCRIPT_DIR}/../../skills/lead-orchestrator/scripts/orchestrator-step-gate.sh"
TSG="${SCRIPT_DIR}/../task-spec-gate.sh"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
PASS=0; FAIL=0
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib/gov-hook-fixtures.sh"

ARMED="$TMP/state"; mkdir -p "$ARMED"; touch "$ARMED/.active"

DOCS="$TMP/pm"; new_repo "$DOCS" fy27/a.md
mkdir -p "$DOCS/.claude"; echo '{"kind":"docs"}' > "$DOCS/.claude/workspace.json"
CODE="$TMP/app"; new_repo "$CODE" package.json src/a.ts
VIBE="$TMP/vibe"; new_repo "$VIBE" package.json .claude/phase.json notes/spec.md
VDOCS="$TMP/vdocs"; new_repo "$VDOCS" .claude/phase.json a.md
echo '{"kind":"docs"}' > "$VDOCS/.claude/workspace.json"

# spawn <cwd> <tool> <prompt> → Agent/Task payload
spawn() { pl PreToolUse "$1" "$2" "$(jq -cn --arg p "$3" '{description:"work",prompt:$p,model:"sonnet"}')"; }

governed_prompt() {
  printf '## Mandatory Context\n- Spec: %s\n\n## Requirement Map\n```json\n%s\n```\n\n## Constraints\n- Stay in scope.\n' \
    "$1" '{"task_id":"T-1","requirements":[{"req_id":"REQ-01","what":"w","done_when":"d","escalate_if":"e","source":"s"}]}'
}

echo "=== test-spawn-gate-scope.sh ==="
echo "-- pre-agent-gate --"
check "docs workspace: plain prompt allowed"   ALLOW "$PRE" "$DOCS" "$(spawn "$DOCS" Agent "Extract the slide text.")" HARNESS_GOV_STATE_DIR="$ARMED"
check "code repo without phase.json: allowed"  ALLOW "$PRE" "$CODE" "$(spawn "$CODE" Agent "Write the parser.")" HARNESS_GOV_STATE_DIR="$ARMED"
check "VIBE repo: plain prompt denied"         DENY  "$PRE" "$VIBE" "$(spawn "$VIBE" Agent "Write the parser.")" HARNESS_GOV_STATE_DIR="$ARMED"
check "VIBE repo: existing notes/spec.md allowed" ALLOW "$PRE" "$VIBE" "$(spawn "$VIBE" Agent "$(governed_prompt notes/spec.md)")" HARNESS_GOV_STATE_DIR="$ARMED"
check "VIBE repo: absolute existing spec allowed" ALLOW "$PRE" "$VIBE" "$(spawn "$VIBE" Agent "$(governed_prompt "$VIBE/notes/spec.md")")" HARNESS_GOV_STATE_DIR="$ARMED"
check "VIBE repo: missing notes/nope.md denied"  DENY "$PRE" "$VIBE" "$(spawn "$VIBE" Agent "$(governed_prompt notes/nope.md)")" HARNESS_GOV_STATE_DIR="$ARMED"
check "VIBE repo: docs/x.md pattern allowed"   ALLOW "$PRE" "$VIBE" "$(spawn "$VIBE" Agent "$(governed_prompt docs/x.md)")" HARNESS_GOV_STATE_DIR="$ARMED"
check "phase.json + docs marker: plain prompt allowed" ALLOW "$PRE" "$VDOCS" "$(spawn "$VDOCS" Agent "Summarise the notes.")" HARNESS_GOV_STATE_DIR="$ARMED"
echo "-- orchestrator-step-gate --"
CODER="Implement the fix for T-1. Write code until the test passes."
check "docs workspace: coder spawn allowed"    ALLOW "$STEP" "$DOCS" "$(spawn "$DOCS" Agent "$CODER")" HARNESS_GOV_STATE_DIR="$ARMED"
check "VIBE repo: coder spawn without tests denied" DENY "$STEP" "$VIBE" "$(spawn "$VIBE" Agent "$CODER")" HARNESS_GOV_STATE_DIR="$ARMED"

echo "-- task-spec-gate --"
BUILD="implement feature login with a new schema"
check "docs workspace: build task allowed"     ALLOW "$TSG" "$DOCS" "$(spawn "$DOCS" Task "$BUILD")" HARNESS_GOV_STATE_DIR="$ARMED"
check "VIBE repo: build task without spec denied" DENY "$TSG" "$VIBE" "$(spawn "$VIBE" Task "$BUILD")" HARNESS_GOV_STATE_DIR="$ARMED"

echo
echo "=== $PASS passed, $FAIL failed ==="
[ "$FAIL" -eq 0 ]
