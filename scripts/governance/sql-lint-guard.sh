#!/usr/bin/env bash
# ABOUTME: PreToolUse hook (Bash): sends database commands to a Sonnet SQL reviewer. Slow SQL goes back to the writer.
# ABOUTME: Thin wrapper. Fast path skips anything that cannot start a database client or program. Logic: sql_lint_guard.py.
# ABOUTME: Same deny contract as psql-guard.sh: exit 2 plus permissionDecision deny JSON. Fail-open. Kill switch HARNESS_SQL_LINT=0.
# ABOUTME: Unwired until the owner approves the settings.json diff in sql-lint-guard/proposal.md. Spec: spec.md Part B.

set -uo pipefail
trap 'exit 0' ERR

[[ "${HARNESS_SQL_LINT:-1}" == "0" ]] && exit 0
command -v jq >/dev/null 2>&1 || { echo "sql-lint-guard: jq not found, skipping" >&2; exit 0; }

INPUT="$(cat)"
[[ "$(printf '%s' "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null)" == "Bash" ]] || exit 0
CMD="$(printf '%s' "$INPUT" | jq -r '.tool_input.command // empty')"
# Fast path: no database client or program word anywhere in the text, so nothing to review.
RE='(^|[^[:alnum:]_])(psql|pg_dump|pg_restore|python[0-9.]*|uv|bash|sh|zsh)([^[:alnum:]_]|$)'
[[ "$CMD" =~ $RE ]] || exit 0

RC=0
REASON="$(printf '%s' "$INPUT" | python3 "$(dirname "$0")/sql_lint_guard.py")" || RC=$?
[[ "$RC" -eq 3 ]] || exit 0   # 0 = allow; any other code = reviewer broke, fail open

jq -cn --arg r "$REASON" '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:$r}}'
exit 2
