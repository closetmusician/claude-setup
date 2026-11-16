#!/usr/bin/env bash
# ABOUTME: Step 5 for arm D. Runs pytest and reports only new failures against a baseline. Parses
# ABOUTME: FAILED and ERROR lines from -rfE output format. --related selects test subset. Exit 0 when
# ABOUTME: no new failures, exit 1 otherwise. Baseline format: one bare nodeid per line (no FAILED/ERROR word).
# ABOUTME: PT_TEST_PG_DSN is passed through. Pytest only (known gap for JS).
set -euo pipefail

# Purpose: show usage text and exit with code 2 (usage error).
# Usage:   usage
# Gotchas: called on --help or wrong argument count.
usage() {
  cat <<'EOF'
Usage: test-run.sh <repo> <out_file> <baseline_file> [--make-baseline] [--related <base_ref>] [-- <pytest args>]

Runs pytest with passed-through args and compares failures to baseline.

--make-baseline: writes sorted unique failing ids to baseline_file, then exits 0
--related <base_ref>: runs only changed test files plus test files importing changed src modules
Otherwise: writes out_file with summary, new failures, now passing, and last 60 lines

Exit codes:
  0 = no new failures
  1 = one or more new failures
  2 = usage error

Environment: PT_TEST_PG_DSN is passed through to pytest
Pytest only (known gap for JS repos)
Baseline format: one bare nodeid per line
EOF
  exit 2
}

[[ "${1:-}" == "--help" ]] && usage
[[ $# -ge 3 ]] || usage

REPO="$1"
OUT_FILE="$2"
BASELINE_FILE="$3"
shift 3

MAKE_BASELINE=false
RELATED_REF=""
PYTEST_ARGS=()

# Parse optional flags
while [[ $# -gt 0 ]]; do
  case "$1" in
    --make-baseline)
      MAKE_BASELINE=true
      shift
      ;;
    --related)
      RELATED_REF="$2"
      shift 2
      ;;
    --)
      shift
      PYTEST_ARGS=("$@")
      break
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage
      ;;
  esac
done

cd "$REPO"

# Purpose: select test files when --related is given.
# Usage:   called once if RELATED_REF is set.
# Gotchas: finds changed test *.py files plus tests that import changed src modules.
select_related_tests() {
  local base="$1"
  local test_files=()

  # Find *.py test files added or changed
  while IFS= read -r f; do
    [[ "$f" =~ \.py$ ]] || continue
    [[ "$f" =~ (^|/)tests?/ || "$f" =~ (^|/)test_ || "$f" =~ _test\.py$ ]] && test_files+=("$f")
  done < <(git diff --name-only --diff-filter=AM "$base" 2>/dev/null || true)

  # Find changed src *.py modules
  local changed_src=()
  while IFS= read -r f; do
    [[ "$f" =~ ^src/.*\.py$ ]] && changed_src+=("$f")
  done < <(git diff --name-only --diff-filter=AM "$base" 2>/dev/null || true)

  # For each changed src module, find tests that import it
  for src_file in "${changed_src[@]}"; do
    # Convert src/progress_tracking/collectors/github.py -> progress_tracking.collectors.github
    local module_path="${src_file#src/}"
    module_path="${module_path%.py}"
    local module_name="${module_path//\//.}"
    local parent_package=$(dirname "$module_path" | tr / .)
    local bare_name=$(basename "$module_path")

    # Search all test *.py files under tests/
    while IFS= read -r test_file; do
      if grep -qE "(import ${module_name}|from ${module_name} import|from ${parent_package} import.*${bare_name})" "$test_file" 2>/dev/null; then
        # Check if already in list
        local already_there=false
        for existing in "${test_files[@]}"; do
          [[ "$existing" == "$test_file" ]] && already_there=true && break
        done
        $already_there || test_files+=("$test_file")
      fi
    done < <(find tests -name '*.py' -type f 2>/dev/null || true)
  done

  printf '%s\n' "${test_files[@]}" | sort -u
}

# Select test files if --related given
TEST_FILES_ARGS=()
if [[ -n "$RELATED_REF" ]]; then
  mapfile -t selected < <(select_related_tests "$RELATED_REF")
  if [[ ${#selected[@]} -eq 0 ]]; then
    {
      echo "NO RELATED TESTS"
      echo ""
      echo "NEW FAILURES (0)"
      echo ""
      echo "NOW PASSING (0)"
    } > "$OUT_FILE"
    exit 0
  fi
  TEST_FILES_ARGS=("${selected[@]}")
  {
    echo "SELECTED ${#selected[@]} test files:"
    printf '  %s\n' "${selected[@]}"
    echo ""
  } > "$OUT_FILE"
fi

# Purpose: run pytest and capture output.
# Usage:   called once per invocation.
# Gotchas: runs uv run pytest with -q -p no:cacheprovider -rfE --continue-on-collection-errors.
RAW_OUTPUT=$(mktemp)
if [[ -n "${TEST_PYTEST_CMD:-}" ]]; then
  pytest_cmd=($TEST_PYTEST_CMD "${PYTEST_ARGS[@]}" "${TEST_FILES_ARGS[@]}")
else
  pytest_cmd=(uv run pytest -q -p no:cacheprovider -rfE --continue-on-collection-errors "${PYTEST_ARGS[@]}" "${TEST_FILES_ARGS[@]}")
fi

# Pass through PT_TEST_PG_DSN if set
if [[ -n "${PT_TEST_PG_DSN:-}" ]]; then
  export PT_TEST_PG_DSN
fi

# Run pytest and capture output and exit code
set +e
"${pytest_cmd[@]}" > "$RAW_OUTPUT" 2>&1
PYTEST_EXIT=$?
set -e

# Purpose: parse FAILED and ERROR lines from pytest -rfE output, strip message suffix.
# Usage:   ids=$(parse_failures < "$RAW_OUTPUT")
# Gotchas: -rfE format is "FAILED nodeid - message" and "ERROR nodeid - message".
parse_failures() {
  perl -ne '
    # Match "FAILED nodeid - message" or "ERROR nodeid - message"
    if (/^(FAILED|ERROR)\s+(\S+)/) {
      my $nodeid = $2;
      $nodeid =~ s/\s+-.*$//;  # strip " - message" suffix if present
      print "$nodeid\n";
    }
  '
}

# Parse failures
FAILING_IDS=$(parse_failures < "$RAW_OUTPUT" | sort -u)

# --make-baseline mode: write bare nodeids
if $MAKE_BASELINE; then
  echo "$FAILING_IDS" > "$BASELINE_FILE"
  rm -f "$RAW_OUTPUT"
  exit 0
fi

# Normal mode: compare to baseline
BASELINE_IDS=$(sort -u "$BASELINE_FILE" 2>/dev/null || true)

# Purpose: compute set difference: items in A but not in B.
# Usage:   new=$(comm -23 <(echo "$A") <(echo "$B"))
# Gotchas: requires sorted input.
NEW_FAILURES=$(comm -23 <(echo "$FAILING_IDS") <(echo "$BASELINE_IDS"))
NOW_PASSING=$(comm -23 <(echo "$BASELINE_IDS") <(echo "$FAILING_IDS"))

# Count new failures
NEW_COUNT=$(echo "$NEW_FAILURES" | grep -c . || true)

# Write output file (append if --related already wrote header)
{
  [[ -z "$RELATED_REF" ]] && head -1 "$RAW_OUTPUT"

  echo ""
  if [[ $NEW_COUNT -gt 0 ]]; then
    echo "NEW FAILURES ($NEW_COUNT):"
    echo "$NEW_FAILURES"
  else
    echo "NEW FAILURES (0)"
  fi

  echo ""
  if [[ -n "$NOW_PASSING" ]]; then
    PASSING_COUNT=$(echo "$NOW_PASSING" | grep -c .)
    echo "NOW PASSING ($PASSING_COUNT):"
    echo "$NOW_PASSING"
  else
    echo "NOW PASSING (0)"
  fi

  echo ""
  echo "=== Last 60 lines of raw output ==="
  tail -60 "$RAW_OUTPUT"
} >> "$OUT_FILE"

rm -f "$RAW_OUTPUT"

# Exit based on new failures
if [[ $NEW_COUNT -eq 0 ]]; then
  exit 0
else
  exit 1
fi
