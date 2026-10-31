#!/usr/bin/env bash
# ABOUTME: TDD suite for scripts/governance/doc-placement-guard.sh (spec C5).
# ABOUTME: In a code repo, a NEW document outside docs/ is denied for every agent.
# ABOUTME: Docs workspaces, existing files and allowed locations pass.
# ABOUTME: Run: bash scripts/tests/test-doc-placement-guard.sh — exit 0 = all green.
# ABOUTME: Spec: docs/plans/harness/governance-scope-spec.md §3 C5, §4.

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="${SCRIPT_DIR}/../governance/doc-placement-guard.sh"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
PASS=0; FAIL=0
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib/gov-hook-fixtures.sh"

CODE="$TMP/app"; new_repo "$CODE" package.json src/a.ts existing.md reports/2026-10-05-weekly.md
mkdir -p "$CODE/.claude"; echo '{"kind":"code","allow_doc_paths":["design/"]}' > "$CODE/.claude/workspace.json"
DOCS="$TMP/pm"; new_repo "$DOCS" fy27/a.md
mkdir -p "$DOCS/.claude"; echo '{"kind":"docs"}' > "$DOCS/.claude/workspace.json"

w() { pl PreToolUse "$1" Write "$(jq -cn --arg f "$2" '{file_path:$f,content:"x"}')" "${3:-}"; }

echo "=== test-doc-placement-guard.sh ==="
check "code: new root notes.md denied (orchestrator)" DENY "$HOOK" "$CODE" "$(w "$CODE" "$CODE/notes.md")"
check "code: new root notes.md denied (subagent)"     DENY "$HOOK" "$CODE" "$(w "$CODE" "$CODE/notes.md" agent1)"
check "code: new src/PLAN.md denied"                  DENY "$HOOK" "$CODE" "$(w "$CODE" "$CODE/src/PLAN.md")"
check "code: new report.docx denied"                  DENY "$HOOK" "$CODE" "$(w "$CODE" "$CODE/report.docx")"
check "code: docs/notes.md allowed"                   ALLOW "$HOOK" "$CODE" "$(w "$CODE" "$CODE/docs/notes.md")"
check "code: packages/a/docs/x.md allowed"            ALLOW "$HOOK" "$CODE" "$(w "$CODE" "$CODE/packages/a/docs/x.md")"
check "code: README.md allowed"                       ALLOW "$HOOK" "$CODE" "$(w "$CODE" "$CODE/README.md")"
check "code: src/lib/README.md allowed"               ALLOW "$HOOK" "$CODE" "$(w "$CODE" "$CODE/src/lib/README.md")"
check "code: CLAUDE.md allowed"                       ALLOW "$HOOK" "$CODE" "$(w "$CODE" "$CODE/CLAUDE.md")"
check "code: .github/PULL_REQUEST_TEMPLATE.md allowed" ALLOW "$HOOK" "$CODE" "$(w "$CODE" "$CODE/.github/PULL_REQUEST_TEMPLATE.md")"
check "code: qa/FEAT-1/T-1.md allowed"                ALLOW "$HOOK" "$CODE" "$(w "$CODE" "$CODE/qa/FEAT-1/T-1.md")"
check "code: tests/fixtures/in.md allowed"            ALLOW "$HOOK" "$CODE" "$(w "$CODE" "$CODE/tests/fixtures/in.md")"
check "code: allow_doc_paths design/x.md allowed"     ALLOW "$HOOK" "$CODE" "$(w "$CODE" "$CODE/design/x.md")"
check "code: overwrite existing.md allowed"           ALLOW "$HOOK" "$CODE" "$(w "$CODE" "$CODE/existing.md")"
check "code: new src/x.ts allowed (not a doc)"        ALLOW "$HOOK" "$CODE" "$(w "$CODE" "$CODE/src/x.ts")"
check "code: outside repo allowed"                    ALLOW "$HOOK" "$CODE" "$(w "$CODE" "$TMP/scratch/n.md")"
check "code: new doc beside tracked docs allowed"  ALLOW "$HOOK" "$CODE" "$(w "$CODE" "$CODE/reports/2026-10-12-weekly.md")"
check "code: new doc in reports/sub/ denied"       DENY  "$HOOK" "$CODE" "$(w "$CODE" "$CODE/reports/sub/x.md")"
check "docs: new fy27/notes.md allowed"               ALLOW "$HOOK" "$DOCS" "$(w "$DOCS" "$DOCS/fy27/notes.md")"
check "kill switch allows"                            ALLOW "$HOOK" "$CODE" "$(w "$CODE" "$CODE/notes.md")" HARNESS_DOC_PLACEMENT_GUARD=0

echo
echo "=== $PASS passed, $FAIL failed ==="
[ "$FAIL" -eq 0 ]
