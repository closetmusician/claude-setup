#!/usr/bin/env bash
# ABOUTME: Verifies TDD Evidence claims in ready-for-review artifacts against git history.
# ABOUTME: Parses the TDD Evidence table, extracts RED/GREEN commit SHAs, validates existence.
# ABOUTME: RED commits must only touch test files; RED must be ancestor of GREEN.
# ABOUTME: Called by orchestrator during Pre-QA Gates after validate-artifact.sh passes.
# ABOUTME: Exit 0 = PASS (or SKIP if TDD-EXEMPT), Exit 1 = FAIL with details.

set -euo pipefail

if [[ $# -lt 1 ]]; then
  echo "Usage: verify-tdd-evidence.sh <path-to-ready-for-review-artifact>"
  exit 1
fi

ARTIFACT="$1"
if [[ ! -f "$ARTIFACT" ]]; then
  echo "FAIL: verify-tdd-evidence — artifact not found: $ARTIFACT"
  exit 1
fi

# Extract TDD Evidence section (between ## TDD Evidence and next ##)
TDD_SECTION=$(sed -n '/^## TDD Evidence/,/^## /p' "$ARTIFACT" | sed '$d')
if [[ -z "$TDD_SECTION" ]]; then
  echo "FAIL: verify-tdd-evidence — no '## TDD Evidence' section found"
  exit 1
fi

# Parse table rows: skip header and separator lines, extract SHAs
# Expected format: | Behavior | <red_sha> | <green_sha> | test_file |
ISSUES=()
VERIFIED=0
CLAIMED=0

while IFS='|' read -r _ _behavior red_sha green_sha _rest; do
  # Trim whitespace
  red_sha=$(echo "$red_sha" | xargs)
  green_sha=$(echo "$green_sha" | xargs)

  # Skip empty, N/A, or header/separator rows
  [[ "$red_sha" =~ ^(-+|RED|red_sha|SHA|Commit)?$ ]] && continue
  [[ "$red_sha" == "N/A" || "$red_sha" == "n/a" || -z "$red_sha" ]] && continue

  CLAIMED=$((CLAIMED + 1))

  # Verify RED commit exists
  if ! git cat-file -e "${red_sha}^{commit}" 2>/dev/null; then
    ISSUES+=("RED commit $red_sha does not exist")
    continue
  fi

  # Verify RED commit only touches test files
  NON_TEST_FILES=$(git diff-tree --no-commit-id --name-only -r "$red_sha" | \
    grep -vE '(^test|_test\.|_spec\.|/tests/|/spec/|/__tests__/|conftest\.py|jest\.config|vitest\.config|pytest\.ini|\.pytest\.ini)' || true)
  if [[ -n "$NON_TEST_FILES" ]]; then
    while IFS= read -r f; do
      ISSUES+=("RED commit $red_sha touches non-test file: $f")
    done <<< "$NON_TEST_FILES"
    continue
  fi

  # Verify GREEN commit exists (skip if N/A)
  if [[ "$green_sha" == "N/A" || "$green_sha" == "n/a" || -z "$green_sha" ]]; then
    VERIFIED=$((VERIFIED + 1))
    continue
  fi
  if ! git cat-file -e "${green_sha}^{commit}" 2>/dev/null; then
    ISSUES+=("GREEN commit $green_sha does not exist")
    continue
  fi

  # Verify ordering: RED is ancestor of GREEN
  if ! git merge-base --is-ancestor "$red_sha" "$green_sha" 2>/dev/null; then
    ISSUES+=("RED commit $red_sha is not ancestor of GREEN commit $green_sha")
    continue
  fi

  VERIFIED=$((VERIFIED + 1))
done <<< "$(echo "$TDD_SECTION" | grep '^|' | tail -n +3)"

# Handle TDD-EXEMPT case
if [[ $CLAIMED -eq 0 ]]; then
  echo "SKIP: all behaviors TDD-EXEMPT"
  exit 0
fi

if [[ ${#ISSUES[@]} -eq 0 ]]; then
  echo "PASS: verify-tdd-evidence — $VERIFIED/$CLAIMED behaviors verified (all RED commits test-only, ordering correct)"
  exit 0
else
  echo "FAIL: verify-tdd-evidence — ${#ISSUES[@]} issue(s):"
  for issue in "${ISSUES[@]}"; do
    echo "  - $issue"
  done
  exit 1
fi
