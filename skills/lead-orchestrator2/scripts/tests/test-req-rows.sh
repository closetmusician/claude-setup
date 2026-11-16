#!/usr/bin/env bash
# ABOUTME: Tests for req-rows.sh. It checks that each REQ id has a table row with that id in the
# ABOUTME: first cell and met/not met in the second cell. REQ-05 must not match REQ-05b. Exit 0 when
# ABOUTME: all rows present, exit 1 lists missing or bad status. No git fixtures needed.
set -euo pipefail

# F12: Unset Git routing variables
unset GIT_DIR GIT_INDEX_FILE GIT_WORK_TREE GIT_PREFIX GIT_COMMON_DIR GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES 2>/dev/null || true

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GATE="$SCRIPT_DIR/../req-rows.sh"

pass=0
fail=0

# Purpose: run one test case and record pass or fail.
# Usage:   test_case "name" <test function>
# Gotchas: the test function must return 0 on success, nonzero on failure.
test_case() {
  local name="$1"
  shift
  if "$@"; then
    echo "ok - $name"
    ((pass++)) || true
  else
    echo "not ok - $name"
    ((fail++)) || true
  fi
}

# Test 1: happy path (all rows present with met status)
test_happy() {
  local review="/tmp/req-rows-test-$$-happy.md"
  cat > "$review" << 'EOF'
# Review

| REQ ID | Status | Evidence | Test |
|---|---|---|---|
| REQ-01 | met | src/x.py:12 | tests/test_x.py::test_a passed |
| REQ-02 | met | src/y.py:34 | tests/test_y.py::test_b passed |
EOF

  local output
  output=$("$GATE" "$review" "REQ-01,REQ-02" 2>&1) && local exit_code=$? || local exit_code=$?

  [[ $exit_code -eq 0 ]] || { echo "exit=$exit_code (expected 0)"; rm -f "$review"; return 1; }
  [[ "$output" =~ "ALL ROWS PRESENT" ]] || { echo "no success message"; rm -f "$review"; return 1; }
  [[ "$output" =~ \(2\) ]] || { echo "count not shown"; rm -f "$review"; return 1; }
  rm -f "$review"
  return 0
}
test_case "happy path (all rows present)" test_happy

# Test 2: missing row
test_missing_row() {
  local review="/tmp/req-rows-test-$$-missing.md"
  cat > "$review" << 'EOF'
| REQ ID | Status | Evidence |
|---|---|---|
| REQ-01 | met | src/x.py:12 |
EOF

  local output
  output=$("$GATE" "$review" "REQ-01,REQ-02" 2>&1) || local exit_code=$?

  [[ ${exit_code:-0} -eq 1 ]] || { echo "exit=${exit_code:-0} (expected 1)"; rm -f "$review"; return 1; }
  [[ "$output" =~ REQ-02 ]] || { echo "missing id not listed"; rm -f "$review"; return 1; }
  rm -f "$review"
  return 0
}
test_case "missing row" test_missing_row

# Test 3: bad status (not met or not met)
test_bad_status() {
  local review="/tmp/req-rows-test-$$-bad-status.md"
  cat > "$review" << 'EOF'
| REQ ID | Status | Evidence |
|---|---|---|
| REQ-01 | met | src/x.py:12 |
| REQ-02 | partial | src/y.py:34 |
EOF

  local output
  output=$("$GATE" "$review" "REQ-01,REQ-02" 2>&1) || local exit_code=$?

  [[ ${exit_code:-0} -eq 1 ]] || { echo "exit=${exit_code:-0} (expected 1)"; rm -f "$review"; return 1; }
  [[ "$output" =~ REQ-02 ]] || { echo "bad status not reported"; rm -f "$review"; return 1; }
  rm -f "$review"
  return 0
}
test_case "bad status (not met or not met)" test_bad_status

# Test 4: REQ-05 must not match REQ-05b
test_no_partial_match() {
  local review="/tmp/req-rows-test-$$-partial.md"
  cat > "$review" << 'EOF'
| REQ ID | Status | Evidence |
|---|---|---|
| REQ-05b | met | src/x.py:12 |
EOF

  local output
  output=$("$GATE" "$review" "REQ-05" 2>&1) || local exit_code=$?

  [[ ${exit_code:-0} -eq 1 ]] || { echo "exit=${exit_code:-0} (expected 1)"; rm -f "$review"; return 1; }
  [[ "$output" =~ REQ-05 ]] && [[ ! "$output" =~ REQ-05b ]] || { echo "partial match accepted"; rm -f "$review"; return 1; }
  rm -f "$review"
  return 0
}
test_case "REQ-05 must not match REQ-05b" test_no_partial_match

# Test 5: not met status is valid
test_not_met_valid() {
  local review="/tmp/req-rows-test-$$-not-met.md"
  cat > "$review" << 'EOF'
| REQ ID | Status | Evidence |
|---|---|---|
| REQ-01 | not met | missing feature |
EOF

  local output
  output=$("$GATE" "$review" "REQ-01" 2>&1) && local exit_code=$? || local exit_code=$?

  [[ $exit_code -eq 0 ]] || { echo "exit=$exit_code (expected 0)"; rm -f "$review"; return 1; }
  rm -f "$review"
  return 0
}
test_case "not met status is valid" test_not_met_valid

# Test 6: multiple missing rows
test_multiple_missing() {
  local review="/tmp/req-rows-test-$$-multi.md"
  cat > "$review" << 'EOF'
| REQ ID | Status | Evidence |
|---|---|---|
| REQ-01 | met | src/x.py:12 |
EOF

  local output
  output=$("$GATE" "$review" "REQ-01,REQ-02,REQ-03" 2>&1) || local exit_code=$?

  [[ ${exit_code:-0} -eq 1 ]] || { echo "exit=${exit_code:-0} (expected 1)"; rm -f "$review"; return 1; }
  [[ "$output" =~ REQ-02 ]] && [[ "$output" =~ REQ-03 ]] || { echo "not all missing ids listed"; rm -f "$review"; return 1; }
  rm -f "$review"
  return 0
}
test_case "multiple missing rows" test_multiple_missing

# Test 7: --help flag
test_help() {
  local output=$("$GATE" --help 2>&1)
  [[ "$output" =~ usage|Usage ]] || { echo "no usage text"; return 1; }
  return 0
}
test_case "--help flag shows usage" test_help

# Test 8: missing arguments
test_missing_args() {
  local output
  output=$("$GATE" 2>&1) && local exit_code=$? || local exit_code=$?
  [[ "$output" =~ [Uu]sage ]] || { echo "no usage text in output"; return 1; }
  [[ $exit_code -eq 2 ]] || { echo "exit=$exit_code (expected 2)"; return 1; }
  return 0
}
test_case "missing arguments exits 2 with usage" test_missing_args

# Test 9: exact cell match (pipes as delimiters, leading pipe on line)
test_exact_cell_match() {
  local review="/tmp/req-rows-test-$$-exact.md"
  cat > "$review" << 'EOF'
Some text REQ-01 in prose
| REQ-01 | met | src/x.py:12 |
EOF

  local output
  output=$("$GATE" "$review" "REQ-01" 2>&1) && local exit_code=$? || local exit_code=$?

  [[ $exit_code -eq 0 ]] || { echo "exit=$exit_code (expected 0)"; rm -f "$review"; return 1; }
  rm -f "$review"
  return 0
}
test_case "exact cell match (prose mention ignored)" test_exact_cell_match

# Summary
echo "# req-rows: $pass passed, $fail failed"
[[ $fail -eq 0 ]] && exit 0 || exit 1
