#!/usr/bin/env bash
# ABOUTME: PreToolUse hook that blocks code file commits without prior test-only commit.
# ABOUTME: Enforces TDD commit ordering: test files must be committed before implementation.
# ABOUTME: Only active when per-project .agents/claude-governance/.active exists.
# ABOUTME: Intercepts 'git commit' commands via Bash tool matcher.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/project-root.sh"

# Only active when governance sentinel exists
ACTIVE_FILE="$(get_governance_state_dir)/.active"
if [[ ! -f "$ACTIVE_FILE" ]]; then
  exit 0
fi

# Read the tool input from stdin (JSON with "command" field for Bash tool)
INPUT="$(cat)"

# Extract the command being run
COMMAND="$(echo "$INPUT" | perl -ne 'print $1 if /"command"\s*:\s*"((?:[^"\\]|\\.)*)"/s')"

# Only intercept git commit commands
if [[ ! "$COMMAND" =~ git[[:space:]]+commit ]]; then
  exit 0
fi

# Extract files being committed: check staged files
# Get the list of staged files
STAGED_FILES="$(git diff --cached --name-only 2>/dev/null || true)"

# If no staged files, nothing to check
if [[ -z "$STAGED_FILES" ]]; then
  exit 0
fi

# File classification patterns
TEST_PATTERN='(^tests/|/tests/|test_|_test\.|\.spec\.|\.test\.|conftest\.py|fixtures/)'
IGNORED_PATTERN='\.(md|sh|bash|yml|yaml|json|toml|cfg|ini|txt|css|html|svg|sql|lock)$'
IGNORED_FILES_PATTERN='(Makefile|Dockerfile|\.gitignore|LICENSE|\.env)'
CODE_PATTERN='\.(py|ts|js|tsx|jsx|go|rs|java|kt|swift|rb|c|cpp|h)$'

# Classify staged files
has_code_files=false
has_only_tests_or_ignored=true

while IFS= read -r file; do
  [[ -z "$file" ]] && continue

  # Skip ignored files
  if echo "$file" | grep -qE "$IGNORED_PATTERN"; then
    continue
  fi
  if echo "$file" | grep -qE "$IGNORED_FILES_PATTERN"; then
    continue
  fi

  # Check if it's a test file
  if echo "$file" | grep -qE "$TEST_PATTERN"; then
    continue
  fi

  # Check if it's a code file
  if echo "$file" | grep -qE "$CODE_PATTERN"; then
    has_code_files=true
    has_only_tests_or_ignored=false
  fi
done <<< "$STAGED_FILES"

# If no code files staged, allow the commit (test-only or config-only)
if [[ "$has_code_files" == "false" ]]; then
  exit 0
fi

# Code files are staged — check if a test-only commit already exists in recent history
# Look at the last 10 commits for a test-only commit (no code files)
RECENT_COMMITS="$(git log --oneline -10 --name-only --pretty=format:'---COMMIT---' 2>/dev/null || true)"

found_test_commit=false
in_commit=false
commit_has_code=false
commit_has_tests=false

while IFS= read -r line; do
  if [[ "$line" == "---COMMIT---" ]]; then
    # Check previous commit
    if [[ "$in_commit" == "true" && "$commit_has_tests" == "true" && "$commit_has_code" == "false" ]]; then
      found_test_commit=true
      break
    fi
    in_commit=true
    commit_has_code=false
    commit_has_tests=false
    continue
  fi

  [[ -z "$line" ]] && continue
  [[ "$in_commit" != "true" ]] && continue

  # Classify this file in the commit
  if echo "$line" | grep -qE "$TEST_PATTERN"; then
    commit_has_tests=true
  elif echo "$line" | grep -qE "$CODE_PATTERN"; then
    if ! echo "$line" | grep -qE "$IGNORED_PATTERN"; then
      commit_has_code=true
    fi
  fi
done <<< "$RECENT_COMMITS"

# Check the last commit too (loop might not process it)
if [[ "$in_commit" == "true" && "$commit_has_tests" == "true" && "$commit_has_code" == "false" ]]; then
  found_test_commit=true
fi

if [[ "$found_test_commit" == "true" ]]; then
  # Test-only commit found in recent history — allow the code commit
  exit 0
fi

# BLOCK: No test-only commit found before this code commit
echo "BLOCKED"
echo ""
echo "commit-order-guard: Code files staged without prior test-only commit."
echo ""
echo "TDD requires tests to be committed BEFORE implementation code."
echo "Staged code files:"
while IFS= read -r file; do
  if echo "$file" | grep -qE "$CODE_PATTERN"; then
    if ! echo "$file" | grep -qE "$TEST_PATTERN" && ! echo "$file" | grep -qE "$IGNORED_PATTERN"; then
      echo "  - $file"
    fi
  fi
done <<< "$STAGED_FILES"
echo ""
echo "Fix: Commit your test files first:"
echo "  git add tests/  (or your test directory)"
echo "  git commit -m 'T-XXX: RED — test for <behavior>'"
echo "  Then commit your implementation files."
echo ""
echo "If this is a legitimate non-TDD commit (config, docs, scripts), ensure no"
echo ".py/.ts/.js/.go/.rs/.java/.kt/.swift/.rb/.c/.cpp/.h files are staged."
exit 2
