#!/usr/bin/env bash
# ABOUTME: TDD suite for scripts/governance/role-enforcement.sh (spec C2).
# ABOUTME: The orchestrator may write specs, plans and orchestration docs; workers do
# ABOUTME: the rest. Allow lists depend on workspace kind. Path matching is by segment.
# ABOUTME: Run: bash scripts/tests/test-role-enforcement.sh — exit 0 = all green.
# ABOUTME: Spec: docs/plans/harness/governance-scope-spec.md §3 C2, §4.

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="${SCRIPT_DIR}/../governance/role-enforcement.sh"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
PASS=0; FAIL=0
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib/gov-hook-fixtures.sh"

ARMED="$TMP/state-armed"; mkdir -p "$ARMED"; touch "$ARMED/.active"
IDLE="$TMP/state-idle"; mkdir -p "$IDLE"

CODE="$TMP/app"; new_repo "$CODE" package.json src/a.ts
DOCS="$TMP/pm"; new_repo "$DOCS" fy27/a.md
mkdir -p "$DOCS/.claude"; echo '{"kind":"docs"}' > "$DOCS/.claude/workspace.json"

# w <cwd> <file> [agent_id] → Write payload
w() { pl PreToolUse "$1" Write "$(jq -cn --arg f "$2" '{file_path:$f,content:"x"}')" "${3:-}"; }

echo "=== test-role-enforcement.sh ==="
echo "-- code repo --"
check "code: docs/spec.md allowed"          ALLOW "$HOOK" "$CODE" "$(w "$CODE" "$CODE/docs/spec.md")" HARNESS_GOV_STATE_DIR="$ARMED"
check "code: docs/temp/run/notes.md allowed" ALLOW "$HOOK" "$CODE" "$(w "$CODE" "$CODE/docs/temp/run/notes.md")" HARNESS_GOV_STATE_DIR="$ARMED"
check "code: qa/FEAT-1/T-1.md allowed"      ALLOW "$HOOK" "$CODE" "$(w "$CODE" "$CODE/qa/FEAT-1/T-1.md")" HARNESS_GOV_STATE_DIR="$ARMED"
check "code: root api-spec.md allowed"      ALLOW "$HOOK" "$CODE" "$(w "$CODE" "$CODE/api-spec.md")" HARNESS_GOV_STATE_DIR="$ARMED"
check "code: src/x.py denied"               DENY  "$HOOK" "$CODE" "$(w "$CODE" "$CODE/src/x.py")" HARNESS_GOV_STATE_DIR="$ARMED"
check "code: notqa/x.py denied (no substring bypass)" DENY "$HOOK" "$CODE" "$(w "$CODE" "$CODE/notqa/x.py")" HARNESS_GOV_STATE_DIR="$ARMED"
check "code: src/qa_helpers/x.ts denied"    DENY  "$HOOK" "$CODE" "$(w "$CODE" "$CODE/src/qa_helpers/x.ts")" HARNESS_GOV_STATE_DIR="$ARMED"
check "code: root notes.md denied"          DENY  "$HOOK" "$CODE" "$(w "$CODE" "$CODE/notes.md")" HARNESS_GOV_STATE_DIR="$ARMED"
check "code: src/settings.json denied"      DENY  "$HOOK" "$CODE" "$(w "$CODE" "$CODE/src/settings.json")" HARNESS_GOV_STATE_DIR="$ARMED"
check "code: .claude/settings.local.json allowed" ALLOW "$HOOK" "$CODE" "$(w "$CODE" "$CODE/.claude/settings.local.json")" HARNESS_GOV_STATE_DIR="$ARMED"
echo "-- docs workspace --"
check "docs: fy27/claude/spec.md allowed"   ALLOW "$HOOK" "$DOCS" "$(w "$DOCS" "$DOCS/fy27/claude/spec.md")" HARNESS_GOV_STATE_DIR="$ARMED"
check "docs: fy27/notes.md allowed"         ALLOW "$HOOK" "$DOCS" "$(w "$DOCS" "$DOCS/fy27/notes.md")" HARNESS_GOV_STATE_DIR="$ARMED"
check "docs: fy27/plan.yaml allowed"        ALLOW "$HOOK" "$DOCS" "$(w "$DOCS" "$DOCS/fy27/plan.yaml")" HARNESS_GOV_STATE_DIR="$ARMED"
check "docs: build.py denied"               DENY  "$HOOK" "$DOCS" "$(w "$DOCS" "$DOCS/fy27/build.py")" HARNESS_GOV_STATE_DIR="$ARMED"
check "docs: deck.pptx denied"              DENY  "$HOOK" "$DOCS" "$(w "$DOCS" "$DOCS/fy27/deck.pptx")" HARNESS_GOV_STATE_DIR="$ARMED"
check "docs: data.csv denied"               DENY  "$HOOK" "$DOCS" "$(w "$DOCS" "$DOCS/fy27/data.csv")" HARNESS_GOV_STATE_DIR="$ARMED"

echo "-- scope --"
check "subagent: src/x.py allowed"          ALLOW "$HOOK" "$CODE" "$(w "$CODE" "$CODE/src/x.py" agent123)" HARNESS_GOV_STATE_DIR="$ARMED"
check "no .active: src/x.py allowed"        ALLOW "$HOOK" "$CODE" "$(w "$CODE" "$CODE/src/x.py")" HARNESS_GOV_STATE_DIR="$IDLE"
check "outside project root allowed"        ALLOW "$HOOK" "$CODE" "$(w "$CODE" "$TMP/scratch/build.py")" HARNESS_GOV_STATE_DIR="$ARMED"
check "Edit on src/x.py denied"             DENY  "$HOOK" "$CODE" "$(pl PreToolUse "$CODE" Edit "$(jq -cn --arg f "$CODE/src/x.py" '{file_path:$f,old_string:"a",new_string:"b"}')")" HARNESS_GOV_STATE_DIR="$ARMED"

echo
echo "=== $PASS passed, $FAIL failed ==="
[ "$FAIL" -eq 0 ]
