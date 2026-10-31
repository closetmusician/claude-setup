#!/usr/bin/env bash
# ABOUTME: PreToolUse hook (Write): in a CODE repo, a new document (md, rst, docx, pptx,
# ABOUTME: xlsx, pdf) must go under docs/. Applies to every agent, orchestrator or worker.
# ABOUTME: Docs workspaces (workspace-kind.sh), existing files, READMEs and test/qa paths pass.
# ABOUTME: Kill switch HARNESS_DOC_PLACEMENT_GUARD=0. Fail-open on every error.
# ABOUTME: Spec: docs/plans/harness/governance-scope-spec.md §3 C5.

set -uo pipefail
trap 'exit 0' ERR

[[ "${HARNESS_DOC_PLACEMENT_GUARD:-1}" == "0" ]] && exit 0
command -v jq >/dev/null 2>&1 || exit 0

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/workspace-kind.sh"

INPUT="$(cat)"
FILE_PATH="$(printf '%s' "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null)"
[[ -z "$FILE_PATH" ]] && exit 0

# Only new documents are checked; editing or overwriting an existing file is fine.
printf '%s' "$FILE_PATH" | grep -qiE '\.(md|markdown|rst|docx|pptx|xlsx|pdf)$' || exit 0
ROOT="$(workspace_root "$PWD")"
FILE="$(physical_path "$FILE_PATH" "$PWD")"
[[ -e "$FILE" ]] && exit 0
REL="$(rel_to_root "$FILE" "$ROOT")" || exit 0

[[ "$(get_workspace_kind "$ROOT" 2>/dev/null)" == "code" ]] || exit 0

has_segment "$REL" docs doc .github .claude .agents skills qa test tests __tests__ fixtures testdata templates && exit 0
case "$(basename "$REL")" in
  README*|CHANGELOG*|CONTRIBUTING*|LICENSE*|SECURITY*|CODE_OF_CONDUCT*|CLAUDE.md|AGENTS.md) exit 0 ;;
esac
while IFS= read -r p; do
  [[ -n "$p" && "$REL" == "$p"* ]] && exit 0
done < <(get_workspace_doc_paths "$ROOT")
# A folder that already tracks documents (reports/, prompts/, .changeset/) is a doc home.
DIR="$(dirname "$REL")"
if [[ "$DIR" != "." ]] && git -C "$ROOT" ls-files -- "$DIR" 2>/dev/null \
     | awk -v d="$DIR/" 'index($0, d) == 1 && index(substr($0, length(d) + 1), "/") == 0' \
     | grep -qiE '\.(md|markdown|rst|docx|pptx|xlsx|pdf)$'; then
  exit 0
fi

REASON="Code repo: documents go under docs/. Write ${REL} as docs/$(basename "$REL") (or a docs/ subfolder) instead, or add its folder to allow_doc_paths in .claude/workspace.json."
jq -cn --arg r "$REASON" '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:$r}}'
exit 0
