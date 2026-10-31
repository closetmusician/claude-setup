#!/usr/bin/env bash
# ABOUTME: Tests that governance activation (activate-on-orchestrator.sh) creates .active
# ABOUTME: only in VIBE repos, and that gates respect this sentinel. Covers the fix for
# ABOUTME: REPORT.md §4g/D2 where gates blocked spawns in non-VIBE contexts.
# ABOUTME: Run: bash scripts/tests/test-vibe-activation.sh — exit 0 = all green.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ACTIVATOR="$SCRIPT_DIR/../governance/activate-on-orchestrator.sh"
PARALLEL_GUARD="$SCRIPT_DIR/../governance/parallel-scope-guard.sh"
CONSTRAINT_LINT="$SCRIPT_DIR/../governance/constraint-wording-lint.sh"
NOCOMMIT_AUDIT="$SCRIPT_DIR/../governance/no-commit-headsha-audit.sh"
PRE_AGENT="$SCRIPT_DIR/../governance/pre-agent-gate.sh"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
PASS=0; FAIL=0

# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib/gov-hook-fixtures.sh"

# ── Helpers ──────────────────────────────────────────────────────────────────

# Create a git repo with given files
new_repo() {
  local d="$1"; shift
  mkdir -p "$d"
  (cd "$d" && git init -q && git config user.name "Test" && git config user.email "test@test")
  local files=()
  for f in "$@"; do
    mkdir -p "$d/$(dirname "$f")"
    echo "content" > "$d/$f"
    files+=("$f")
  done
  (cd "$d" && git add "${files[@]}" && git commit -q -m "init")
}

# Make Skill tool payload for lead-orchestrator
skill_payload() {
  jq -cn '{tool_name:"Skill",tool_input:{skill:"lead-orchestrator",prompt:"Run the pipeline."}}'
}

# Make Agent payload with ## Output: for parallel-scope-guard
agent_payload_with_output() {
  local sid="$1" path="$2"
  jq -cn --arg sid "$sid" --arg path "$path" \
    '{session_id:$sid,tool_name:"Agent",tool_input:{prompt:("Do work.\n## Output: "+$path)},agent_id:null}'
}

# Make Agent payload with ## Constraints for constraint-wording-lint
agent_payload_with_constraints() {
  jq -cn '{tool_name:"Agent",tool_input:{prompt:"Task.\n## Constraints\n- MOVES only"}}'
}

# Make Agent payload with NO-COMMIT for no-commit-headsha-audit
agent_payload_nocommit() {
  jq -cn '{session_id:"test-nc",tool_name:"Agent",tool_input:{prompt:"Fix bug. NO-COMMIT."},hook_event_name:"PreToolUse"}'
}

# ── Test 1: Activation in non-VIBE repo does not create .active ─────────────

echo "=== Test 1: non-VIBE repo activation ==="
NON_VIBE="$TMP/non-vibe"
new_repo "$NON_VIBE" package.json src/a.ts
STATE_NON="$TMP/state-non"
mkdir -p "$STATE_NON"

cd "$NON_VIBE"
RESULT=$(echo '{"tool_name":"Skill","tool_input":{"skill":"lead-orchestrator","prompt":"Test"}}' | \
  HARNESS_GOV_STATE_DIR="$STATE_NON" bash "$ACTIVATOR" 2>&1); RC=$?

if [[ ! -f "$STATE_NON/.active" ]]; then
  echo "PASS: 1a .active not created in non-VIBE repo"; PASS=$((PASS+1))
else
  echo "FAIL: 1a .active created in non-VIBE repo"; FAIL=$((FAIL+1))
fi

if [[ "$RC" -eq 0 ]]; then
  echo "PASS: 1b activation script exit 0"; PASS=$((PASS+1))
else
  echo "FAIL: 1b activation script exit $RC"; FAIL=$((FAIL+1))
fi

# ── Test 2: Activation in VIBE repo creates .active ─────────────────────────

echo "=== Test 2: VIBE repo activation ==="
VIBE_REPO="$TMP/vibe"
new_repo "$VIBE_REPO" .claude/phase.json src/a.ts
STATE_VIBE="$TMP/state-vibe"
mkdir -p "$STATE_VIBE"

cd "$VIBE_REPO"
RESULT=$(echo '{"tool_name":"Skill","tool_input":{"skill":"lead-orchestrator","prompt":"Test"}}' | \
  HARNESS_GOV_STATE_DIR="$STATE_VIBE" bash "$ACTIVATOR" 2>&1); RC=$?

if [[ -f "$STATE_VIBE/.active" ]]; then
  echo "PASS: 2a .active created in VIBE repo"; PASS=$((PASS+1))
else
  echo "FAIL: 2a .active not created in VIBE repo (state in: $STATE_VIBE)"; FAIL=$((FAIL+1))
fi

if [[ "$RC" -eq 0 ]]; then
  echo "PASS: 2b activation script exit 0"; PASS=$((PASS+1))
else
  echo "FAIL: 2b activation script exit $RC"; FAIL=$((FAIL+1))
fi

# ── Test 3: parallel-scope-guard is inert without .active ───────────────────

echo "=== Test 3: parallel-scope-guard without .active ==="
STATE_NO_ACTIVE="$TMP/state-no-active"
mkdir -p "$STATE_NO_ACTIVE"
# Deliberately do NOT create .active

PAYLOAD=$(agent_payload_with_output "test-session" "docs/out.md")
cd "$NON_VIBE"
OUT=$(HARNESS_GOV_STATE_DIR="$STATE_NO_ACTIVE" echo "$PAYLOAD" | bash "$PARALLEL_GUARD" 2>&1); RC=$?

if [[ "$RC" -eq 0 ]] && [[ ! "$OUT" =~ "permissionDecision" ]]; then
  echo "PASS: 3 parallel-scope-guard allows without .active"; PASS=$((PASS+1))
else
  echo "FAIL: 3 parallel-scope-guard blocked without .active: RC=$RC OUT=$OUT"; FAIL=$((FAIL+1))
fi

# ── Test 4: constraint-wording-lint is inert without .active ────────────────

echo "=== Test 4: constraint-wording-lint without .active ==="
PAYLOAD=$(agent_payload_with_constraints)
cd "$NON_VIBE"
OUT=$(HARNESS_GOV_STATE_DIR="$STATE_NO_ACTIVE" echo "$PAYLOAD" | bash "$CONSTRAINT_LINT" 2>&1); RC=$?

if [[ "$RC" -eq 0 ]]; then
  echo "PASS: 4 constraint-wording-lint exit 0 without .active"; PASS=$((PASS+1))
else
  echo "FAIL: 4 constraint-wording-lint exit $RC without .active"; FAIL=$((FAIL+1))
fi

# ── Test 5: no-commit-headsha-audit is inert without .active ────────────────

echo "=== Test 5: no-commit-headsha-audit without .active ==="
PAYLOAD=$(agent_payload_nocommit)
cd "$NON_VIBE"
OUT=$(HARNESS_GOV_STATE_DIR="$STATE_NO_ACTIVE" NOCOMMIT_STATE_DIR="$STATE_NO_ACTIVE" echo "$PAYLOAD" | bash "$NOCOMMIT_AUDIT" 2>&1); RC=$?

if [[ "$RC" -eq 0 ]]; then
  echo "PASS: 5 no-commit-headsha-audit exit 0 without .active"; PASS=$((PASS+1))
else
  echo "FAIL: 5 no-commit-headsha-audit exit $RC without .active"; FAIL=$((FAIL+1))
fi

# ── Test 6: Coder spawn in non-VIBE repo with .active allows coder spawn ──────

echo "=== Test 6: non-VIBE repo with .active allows coder spawn ==="
STATE_NON_WITH_ACTIVE="$TMP/state-non-with-active"
mkdir -p "$STATE_NON_WITH_ACTIVE"
touch "$STATE_NON_WITH_ACTIVE/.active"

CODER_PAYLOAD=$(jq -cn '{tool_name:"Agent",tool_input:{prompt:"Implement T-1. Write code."},agent_id:null}')
cd "$NON_VIBE"
OUT=$(HARNESS_GOV_STATE_DIR="$STATE_NON_WITH_ACTIVE" echo "$CODER_PAYLOAD" | bash "$PRE_AGENT" 2>&1); RC=$?

if [[ "$RC" -eq 0 ]] && [[ ! "$OUT" =~ '"decision".*"block"' ]]; then
  echo "PASS: 6 coder spawn in non-VIBE with .active allowed"; PASS=$((PASS+1))
else
  echo "FAIL: 6 coder spawn in non-VIBE blocked: RC=$RC OUT=$OUT"; FAIL=$((FAIL+1))
fi

# ─────────────────────────────────────────────────────────────────────────────

echo
echo "=== $PASS passed, $FAIL failed ==="
[ "$FAIL" -eq 0 ]
