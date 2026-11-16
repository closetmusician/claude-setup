#!/usr/bin/env bash
# ABOUTME: Pre-commit hook drop-in for LO2 suites. Runs all LO2 tests when a commit touches skills/lead-orchestrator2/.
# ABOUTME: Written 2026-11-16 for REQ-09. Exit 0 = pass, exit 1 = fail (blocks commit).
# ABOUTME: Usage: called automatically by git commit when core.hooksPath points at .githooks.
# ABOUTME: Clears the GIT_* variables git exports to hooks before any test runs. Without that, the tests'
# ABOUTME: throwaway `git init`/`git config` calls hit the real repo (lessons-learned 2026-11-16).

set -euo pipefail

# Check if any staged files are under skills/lead-orchestrator2/
if ! git diff --cached --name-only | grep -q '^skills/lead-orchestrator2/'; then
  # No LO2 files staged, skip
  exit 0
fi

echo "Running LO2 test suites (staged LO2 files detected)..."

# The staged-files check above needs the hook's git variables. The tests must not see them.
unset GIT_DIR GIT_INDEX_FILE GIT_WORK_TREE GIT_PREFIX GIT_COMMON_DIR GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES

LO2_DIR="skills/lead-orchestrator2"
failed=0

# Run all .mjs test suites
for test_file in "$LO2_DIR/tests/"*.mjs; do
  [[ -f "$test_file" ]] || continue
  echo "Running $(basename "$test_file")..."
  if ! node "$test_file"; then
    failed=1
  fi
done

# Run all .sh test suites
for test_file in "$LO2_DIR/scripts/tests/"*.sh; do
  [[ -f "$test_file" ]] || continue
  echo "Running $(basename "$test_file")..."
  if ! bash "$test_file"; then
    failed=1
  fi
done

if [[ $failed -eq 1 ]]; then
  echo "LO2 suites failed. Commit blocked."
  exit 1
fi

echo "All LO2 suites passed."
exit 0
