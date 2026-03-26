#!/bin/bash
# ABOUTME: PreToolUse hook that catches dangerous git patterns before execution.
# ABOUTME: Reads JSON from stdin, checks Bash commands against a banned-pattern list.
# ABOUTME: Exits 2 (blocking) with reason on stdout if banned pattern found.
# ABOUTME: Exits 0 (allow) for clean commands or non-Bash tools.
# ABOUTME: Requires: jq

set -euo pipefail

# Bail gracefully if jq is missing -- do not block legitimate work.
if ! command -v jq &>/dev/null; then
  echo "git-safety-hook: jq not found, skipping checks" >&2
  exit 0
fi

# Read the tool-call JSON from stdin.
INPUT=$(cat)

# Extract tool name. PreToolUse provides it as "tool_name".
TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // empty')

# Only inspect Bash calls -- everything else passes through.
if [[ "$TOOL_NAME" != "Bash" ]]; then
  exit 0
fi

# Extract the command string from tool_input.
CMD=$(echo "$INPUT" | jq -r '.tool_input.command // empty')

# Nothing to check if the command is empty.
if [[ -z "$CMD" ]]; then
  exit 0
fi

# Strip heredoc bodies and quoted strings to avoid false positives on
# text like 'git add -A' inside commit messages or echo output.
# Replace <<'EOF'...EOF (and <<EOF...EOF) blocks with a placeholder,
# then strip double-quoted and single-quoted strings.
# macOS BSD sed requires newline after c\ -- use perl for portability.
STRIPPED=$(echo "$CMD" | perl -0777 -pe "s/<<'?EOF'?.*?^EOF\$/__HEREDOC__/gms" | sed "s/\"[^\"]*\"/__STR__/g; s/'[^']*'/__STR__/g")

# --- Banned pattern checks ---
# Each check outputs a deny decision via JSON on stdout and exits 2.

# deny_and_exit <reason>
# Outputs a hookSpecificOutput JSON blob that tells Claude Code to deny the
# tool call, then exits with code 2 so the call is blocked.
deny_and_exit() {
  local reason="$1"
  jq -n \
    --arg reason "$reason" \
    '{
      "hookSpecificOutput": {
        "hookEventName": "PreToolUse",
        "permissionDecision": "deny",
        "permissionDecisionReason": $reason
      }
    }'
  exit 2
}

# 1. git add -A / git add --all / git add . (should use specific file names)
#    Match "git add -A", "git add --all", "git add .", and common variants like "git add -a".
if echo "$STRIPPED" | grep -qE '\bgit\s+add\s+(-A\b|--all\b|\.\s*(;|$|&&|\|))'; then
  deny_and_exit "Banned: 'git add -A' / 'git add --all' / 'git add .' -- use specific file names instead. Run 'git status' first to review what will be staged."
fi

# 2. --no-verify on any git command
if echo "$STRIPPED" | grep -qE '\bgit\b.*--no-verify\b'; then
  deny_and_exit "Banned: '--no-verify' skips git hooks. Remove the flag and let hooks run."
fi

# 3. git push --force / git push -f (dangerous force push)
#    Allow --force-with-lease (the safe alternative).
if echo "$STRIPPED" | grep -qE '\bgit\s+push\s+.*(-f\b|--force\b)'; then
  if ! echo "$CMD" | grep -qE '\bgit\s+push\s+.*--force-with-lease\b'; then
    deny_and_exit "Banned: 'git push --force' is destructive. Use '--force-with-lease' or rethink the push."
  fi
fi

# 4. git reset --hard (destructive)
if echo "$STRIPPED" | grep -qE '\bgit\s+reset\s+.*--hard\b'; then
  deny_and_exit "Banned: 'git reset --hard' discards changes permanently. Consider 'git stash' or a safer alternative."
fi

# 5. git checkout -- . / git restore . (discard all changes)
if echo "$STRIPPED" | grep -qE '\bgit\s+checkout\s+--\s+\.\s*(;|$|&&|\|)'; then
  deny_and_exit "Banned: 'git checkout -- .' discards all unstaged changes. Be specific about which files to restore."
fi
if echo "$STRIPPED" | grep -qE '\bgit\s+restore\s+\.\s*(;|$|&&|\|)'; then
  deny_and_exit "Banned: 'git restore .' discards all unstaged changes. Be specific about which files to restore."
fi

# 6. Protected files -- block rm/git rm of critical ~/.claude/ files
PROTECTED_FILES=(
  "vibe-manual.md"
  "vibe-protocol.md"
  "code-style.md"
  "protected-files.md"
  "CLAUDE.md"
)
for pf in "${PROTECTED_FILES[@]}"; do
  if echo "$STRIPPED" | grep -qE "(rm|git\s+rm)\s.*$pf"; then
    deny_and_exit "Banned: '$pf' is a protected file (see ~/.claude/rules/protected-files.md). Cannot delete."
  fi
done

# 7. gh pr create (requires explicit user approval -- never auto-create PRs)
if echo "$STRIPPED" | grep -qE '\bgh\s+pr\s+create\b'; then
  deny_and_exit "Blocked: 'gh pr create' requires Yu-Kuan's explicit approval. Present the PR title/summary and ask before creating."
fi

# All checks passed -- allow the command.
exit 0
