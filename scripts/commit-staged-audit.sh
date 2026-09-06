#!/usr/bin/env bash
# ABOUTME: PreToolUse/Bash hook: scans staged files for secrets on every `git commit` call.
# ABOUTME: Closes the interactive-session gap where autonomous-secret-scan.sh does not fire.
# ABOUTME: Delegates detection to ~/.claude/scripts/secret-scan.sh (reuse only, never forked).
# ABOUTME: Fail-open when scanner is absent or errors; fail-CLOSED on any secret hit (exit 2).
# ABOUTME: Reads tool payload from STDIN JSON — never from env variables.

set -uo pipefail

SCANNER="${SCANNER:-$HOME/.claude/scripts/secret-scan.sh}"

# Bail gracefully if jq is missing — do not block legitimate work.
if ! command -v jq &>/dev/null; then
  echo "commit-staged-audit: jq not found, skipping scan" >&2
  exit 0
fi

# Read hook payload from stdin (never env).
INPUT="$(cat)"

# Only inspect Bash tool calls.
TOOL_NAME="$(printf '%s' "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null || true)"
if [[ "$TOOL_NAME" != "Bash" ]]; then
  exit 0
fi

# Extract the command string from tool_input.
CMD="$(printf '%s' "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null || true)"
if [[ -z "$CMD" ]]; then
  exit 0
fi

# Strip heredoc bodies so a commit message containing 'git commit' does not
# self-match. Mirror git-safety-hook.sh's approach (BSD-safe perl).
STRIPPED="$(printf '%s' "$CMD" | perl -0777 -pe "s/<<'?EOF'?.*?^EOF\$/__HEREDOC__/gms" \
  | sed "s/\"[^\"]*\"/__STR__/g; s/'[^']*'/__STR__/g")"

# Fast-path: not a git commit → allow immediately.
if ! printf '%s' "$STRIPPED" | grep -qE '\bgit\s+commit\b'; then
  exit 0
fi

# Fail-open guard: scanner must be present and executable.
if [[ ! -x "$SCANNER" ]]; then
  echo "commit-staged-audit: scanner not found at $SCANNER — skipping (fail-open)" >&2
  exit 0
fi

# Resolve CWD from the hook payload (Claude Code sends it as cwd).
REPO_CWD="$(printf '%s' "$INPUT" | jq -r '.cwd // empty' 2>/dev/null || true)"
if [[ -n "$REPO_CWD" && -d "$REPO_CWD" ]]; then
  cd "$REPO_CWD"
fi

# Verify we are inside a git repository before running git commands.
if ! git rev-parse --is-inside-work-tree &>/dev/null; then
  exit 0
fi

# Collect staged files (NUL-delimited → newline for safety-hook compatibility).
STAGED_FILES=()
while IFS= read -r -d '' f; do
  [[ -n "$f" ]] && STAGED_FILES+=("$f")
done < <(git diff --cached --name-only -z 2>/dev/null)

# Nothing staged → nothing to scan → allow.
if [[ ${#STAGED_FILES[@]} -eq 0 ]]; then
  exit 0
fi

# Run the scanner with set -e temporarily disabled so we can capture its exit code.
# Scanner exit 0 = clean; exit 1 = secret(s) found; exit ≥ 2 = scanner error → fail-open.
SCAN_OUT_FILE="$(mktemp)"
trap 'rm -f "$SCAN_OUT_FILE"' EXIT
SCAN_EXIT=0
"$SCANNER" "${STAGED_FILES[@]}" > "$SCAN_OUT_FILE" 2>&1 || SCAN_EXIT=$?
SCAN_OUT="$(cat "$SCAN_OUT_FILE")"
rm -f "$SCAN_OUT_FILE"

# Fail-open: scanner itself crashed (exit ≥ 2 or other anomaly from the runner).
if [[ "$SCAN_EXIT" -ge 2 ]]; then
  echo "commit-staged-audit: scanner returned exit $SCAN_EXIT — skipping (fail-open)" >&2
  exit 0
fi

if [[ "$SCAN_EXIT" -eq 0 ]]; then
  # Clean — allow the commit.
  exit 0
fi

# Secret detected (exit 1): build a denial message from scanner output.
DETAIL="${SCAN_OUT:-<no detail>}"
# Emit a P0 incident line for the journal.
echo "P0-INCIDENT commit-staged-audit: secret pattern detected in staged file(s) — commit BLOCKED. Details: $DETAIL" >&2

jq -n \
  --arg reason "commit-staged-audit BLOCKED: secret pattern detected in staged file(s). Unstage and clean before committing. Details: ${DETAIL}" \
  '{
    "hookSpecificOutput": {
      "hookEventName": "PreToolUse",
      "permissionDecision": "deny",
      "permissionDecisionReason": $reason
    }
  }'
exit 2
