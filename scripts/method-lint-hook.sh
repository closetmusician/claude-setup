#!/usr/bin/env bash
# ABOUTME: PostToolUse hook (Write|Edit|MultiEdit): runs method-lint.pl on a just-written
# ABOUTME: .md/.html deliverable and feeds any findings back to Claude as additionalContext.
# ABOUTME: Warn-only and fail-OPEN: it never blocks, and any error exits 0 silently.
# ABOUTME: Skips working files: ~/.claude/**, evidence/, work/, qa/, plans/, handoffs/,
# ABOUTME: memory/, temp/, research/, and files named verification*/README*. Owner OK 2026-11-19.

set -uo pipefail
trap 'exit 0' ERR

[ "${HARNESS_METHOD_LINT:-1}" = "0" ] && exit 0
command -v jq >/dev/null 2>&1 || exit 0

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LINT="${METHOD_LINT_BIN:-$SCRIPT_DIR/method-lint.pl}"
[ -x "$LINT" ] || exit 0

INPUT="$(cat 2>/dev/null)" || exit 0
[ -z "$INPUT" ] && exit 0

# Field name copied from harness-change-flag.sh, a working PostToolUse Write/Edit consumer.
FILE="$(printf '%s' "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null)" || exit 0
[ -z "$FILE" ] && exit 0
[ -f "$FILE" ] || exit 0

# Only finished-doc formats.
case "$FILE" in
  *.md|*.MD|*.html|*.htm) ;;
  *) exit 0 ;;
esac

# Working files may talk about method; deliverables may not.
case "$FILE" in
  "$HOME"/.claude/*|*/evidence/*|*/work/*|*/qa/*|*/plans/*|*/handoffs/*|*/memory/*|*/temp/*|*/research/*) exit 0 ;;
esac
case "$(basename "$FILE")" in
  verification*|README*|CLAUDE.md|MEMORY.md) exit 0 ;;
esac

# The lint exits 1 on findings; capture that without tripping the ERR trap.
RC=0; OUT="$("$LINT" "$FILE" 2>/dev/null)" || RC=$?
[ "$RC" -eq 1 ] || exit 0
[ -z "$OUT" ] && exit 0

N="$(printf '%s\n' "$OUT" | grep -c '^/' || true)"
MSG="[method-lint] ${N} finding(s) in ${FILE}. Finished docs show results only: cut method, process and tooling detail (owner rule). Put it in your reply or a working file instead. Fix, then re-run: ~/.claude/scripts/method-lint.pl \"${FILE}\"
$(printf '%s\n' "$OUT" | head -24)"

jq -n --arg ctx "$MSG" '{hookSpecificOutput: {hookEventName: "PostToolUse", additionalContext: $ctx}}'
exit 0
