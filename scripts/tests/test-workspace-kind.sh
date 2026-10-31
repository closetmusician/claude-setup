#!/usr/bin/env bash
# ABOUTME: TDD suite for scripts/governance/lib/workspace-kind.sh (spec C1).
# ABOUTME: Checks the marker file, phase.json, manifests and the git ls-files ratio
# ABOUTME: against REAL temp git repos. No mocks.
# ABOUTME: Run: bash scripts/tests/test-workspace-kind.sh — exit 0 = all green.
# ABOUTME: Spec: docs/plans/harness/governance-scope-spec.md §3 C1, §4.

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB="${SCRIPT_DIR}/../governance/lib/workspace-kind.sh"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
PASS=0; FAIL=0
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib/gov-hook-fixtures.sh"
# shellcheck disable=SC1090
source "$LIB" 2>/dev/null || { echo "FAIL cannot source $LIB"; echo "=== 0 passed, 1 failed ==="; exit 1; }

echo "=== test-workspace-kind.sh ==="

new_repo "$TMP/mdocs" a.py b.py c.py
mkdir -p "$TMP/mdocs/.claude"; echo '{"kind":"docs"}' > "$TMP/mdocs/.claude/workspace.json"
assert_eq "marker docs wins over code files" docs "$(get_workspace_kind "$TMP/mdocs")"

new_repo "$TMP/mcode" a.md b.md c.md
mkdir -p "$TMP/mcode/.claude"; echo '{"kind":"code"}' > "$TMP/mcode/.claude/workspace.json"
assert_eq "marker code wins over doc files" code "$(get_workspace_kind "$TMP/mcode")"

new_repo "$TMP/mbad" a.md b.md
mkdir -p "$TMP/mbad/.claude"; echo '{"kind":"banana"}' > "$TMP/mbad/.claude/workspace.json"
assert_eq "invalid marker falls through" docs "$(get_workspace_kind "$TMP/mbad" 2>/dev/null)"

new_repo "$TMP/vibe" a.md b.md .claude/phase.json
assert_eq "phase.json means code" code "$(get_workspace_kind "$TMP/vibe")"
is_vibe_repo "$TMP/vibe" && r=yes || r=no
assert_eq "is_vibe_repo true with phase.json" yes "$r"
is_vibe_repo "$TMP/mcode" && r=yes || r=no
assert_eq "is_vibe_repo false without phase.json" no "$r"

new_repo "$TMP/node" package.json a.md b.md c.md
assert_eq "package.json means code" code "$(get_workspace_kind "$TMP/node")"

new_repo "$TMP/dotnet" Api.csproj a.md b.md
assert_eq "*.csproj means code" code "$(get_workspace_kind "$TMP/dotnet")"

new_repo "$TMP/mdheavy" a.md b.md c.pptx d.xlsx tool.py
assert_eq "doc-heavy git repo is docs" docs "$(get_workspace_kind "$TMP/mdheavy")"

new_repo "$TMP/codeheavy" a.go b.go c.sh README.md
assert_eq "code-heavy git repo is code" code "$(get_workspace_kind "$TMP/codeheavy")"

new_repo "$TMP/bigdocs" src/a.cs src/b.ts src/c.ts docs/1.md docs/2.md docs/3.md docs/4.md docs/5.md README.md
assert_eq "code repo with big docs/ folder is code" code "$(get_workspace_kind "$TMP/bigdocs")"

mkdir -p "$TMP/codeheavy/pkg/deep"
assert_eq "subdirectory resolves to repo root" code "$(get_workspace_kind "$TMP/codeheavy/pkg/deep")"

mkdir -p "$TMP/plain"; : > "$TMP/plain/notes.md"
assert_eq "non-git folder with no manifest is docs" docs "$(get_workspace_kind "$TMP/plain")"

new_repo "$TMP/mpaths" a.go
mkdir -p "$TMP/mpaths/.claude"
echo '{"kind":"code","allow_doc_paths":["notes/","design/"]}' > "$TMP/mpaths/.claude/workspace.json"
assert_eq "allow_doc_paths listed" "notes/ design/" "$(get_workspace_doc_paths "$TMP/mpaths" | tr '\n' ' ' | sed 's/ $//')"

echo
echo "=== $PASS passed, $FAIL failed ==="
[ "$FAIL" -eq 0 ]
