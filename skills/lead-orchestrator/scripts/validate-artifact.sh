#!/usr/bin/env bash
# ABOUTME: Structural validator for lead-orchestrator QA artifacts.
# ABOUTME: Checks ready-for-review, review-findings, cycle-1, and cycle-2 files.
# ABOUTME: Called explicitly by orchestrator after subagent returns AND as Write hook.
# ABOUTME: Exit 0 = PASS, Exit 1 = FAIL (lists deviations).
# ABOUTME: When run as hook: receives JSON on stdin, validates file_path in qa/ dirs.

set -euo pipefail

# ─── Mode detection ───
# If stdin has data (hook mode), extract file path from JSON input.
# If argument provided (explicit mode), validate that file directly.

FILE_PATH=""

if [[ $# -ge 1 ]]; then
  # Explicit invocation: validate-artifact.sh <path>
  FILE_PATH="$1"
elif [[ ! -t 0 ]]; then
  # Hook mode: read JSON from stdin
  INPUT=$(cat)

  # Only activate when governance is active
  [[ ! -f "$HOME/.claude/scripts/governance/state/.active" ]] && exit 0

  # Extract file path from Write tool input
  FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null || true)

  # Only validate files in qa/ directories
  if [[ -z "$FILE_PATH" ]] || ! echo "$FILE_PATH" | grep -qE '/qa/[A-Z]+-[0-9]+/T-'; then
    exit 0
  fi

  # Extract content from Write tool input for pre-write validation
  CONTENT=$(echo "$INPUT" | jq -r '.tool_input.content // empty' 2>/dev/null || true)
else
  echo "Usage: validate-artifact.sh <path-to-artifact>"
  echo "   or: pipe JSON hook input via stdin"
  exit 1
fi

# ─── Determine artifact type from filename ───
BASENAME=$(basename "$FILE_PATH")
ERRORS=()

validate_content() {
  local content="$1"

  case "$BASENAME" in
    *ready-for-review*)
      # Must have TDD Evidence section with table rows OR TDD-EXEMPT declarations
      if ! echo "$content" | grep -q '## TDD Evidence'; then
        ERRORS+=("Missing '## TDD Evidence' section")
      else
        # Check for table data rows (| col | col |) or TDD-EXEMPT
        TDD_SECTION=$(echo "$content" | sed -n '/^## TDD Evidence/,/^## /{ /^## TDD Evidence/d; /^## /d; p; }')
        HAS_TABLE_ROW=$(echo "$TDD_SECTION" | grep -cE '^\|[^-]' || true)
        HAS_EXEMPT=$(echo "$TDD_SECTION" | grep -c 'TDD-EXEMPT' || true)
        if [[ "$HAS_TABLE_ROW" -lt 2 ]] && [[ "$HAS_EXEMPT" -eq 0 ]]; then
          ERRORS+=("TDD Evidence section has no data rows and no TDD-EXEMPT declarations")
        fi
      fi

      # Must have ReviewCommit SHA
      if ! echo "$content" | grep -qE 'ReviewCommit:[[:space:]]*[0-9a-f]{7,40}'; then
        ERRORS+=("Missing 'ReviewCommit:<SHA>' (7-40 hex chars required)")
      fi
      ;;

    *review-findings*)
      # Must have at least one severity classification
      HAS_P0=$(echo "$content" | grep -c 'P0' || true)
      HAS_P1=$(echo "$content" | grep -c 'P1' || true)
      HAS_P2=$(echo "$content" | grep -c 'P2' || true)
      HAS_NO_FINDINGS=$(echo "$content" | grep -ci 'no findings\|no issues\|clean' || true)

      if [[ "$HAS_P0" -eq 0 ]] && [[ "$HAS_P1" -eq 0 ]] && [[ "$HAS_P2" -eq 0 ]] && [[ "$HAS_NO_FINDINGS" -eq 0 ]]; then
        ERRORS+=("Missing severity classifications (expected P0/P1/P2 findings or explicit 'no findings' statement)")
      fi

      # Must have a verdict or summary section
      if ! echo "$content" | grep -qiE '(## Summary|## Verdict|## Findings|## Review)'; then
        ERRORS+=("Missing summary/findings section header")
      fi
      ;;

    *cycle-1*|*cycle-2*)
      # Must have a verdict
      if ! echo "$content" | grep -qiE '(PASS|FAIL|PASS_WITH_CONCERNS)'; then
        ERRORS+=("Missing verdict (expected PASS, FAIL, or PASS_WITH_CONCERNS)")
      fi

      # Must have test output or test results section
      if ! echo "$content" | grep -qiE '(## Test|## Results|## Output|test run|tests? (passed|failed|ran))'; then
        ERRORS+=("Missing test output/results section")
      fi

      # Cycle files should reference the task
      if ! echo "$content" | grep -qE 'T-[0-9]+'; then
        ERRORS+=("Missing task reference (T-XXX)")
      fi
      ;;

    *)
      # Unknown artifact type in qa/ — skip validation
      exit 0
      ;;
  esac
}

# ─── Run validation ───
if [[ -n "${CONTENT:-}" ]]; then
  # Hook mode: validate content before write
  validate_content "$CONTENT"
elif [[ -f "$FILE_PATH" ]]; then
  # Explicit mode: validate existing file
  CONTENT=$(cat "$FILE_PATH")
  validate_content "$CONTENT"
else
  echo "FAIL: File does not exist: $FILE_PATH"
  exit 1
fi

# ─── Report results ───
if [[ ${#ERRORS[@]} -gt 0 ]]; then
  if [[ -n "${INPUT:-}" ]]; then
    # Hook mode: emit block JSON
    REASON=$(printf '%s; ' "${ERRORS[@]}")
    printf '{"decision": "block", "reason": "Artifact Validation FAIL (%s): %s"}\n' "$BASENAME" "$REASON"
    exit 0
  else
    # Explicit mode: print errors and exit 1
    echo "FAIL: $BASENAME — ${#ERRORS[@]} issue(s):"
    for err in "${ERRORS[@]}"; do
      echo "  - $err"
    done
    exit 1
  fi
fi

# All checks passed
if [[ -z "${INPUT:-}" ]]; then
  echo "PASS: $BASENAME"
fi
exit 0
