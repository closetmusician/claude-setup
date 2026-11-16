#!/usr/bin/env bash
# ABOUTME: Tests for spec-gate.sh. It checks that the gate passes only when requirements are
# ABOUTME: unchanged from base_ref, verdict line 1 is NO CONFLICTS, ambiguities line 1 is NONE,
# ABOUTME: and that it always writes the design diff even on a fail. The requirements-changed case
# ABOUTME: restores both requirements and design from base_ref. Git fixtures live under /tmp/<uuid>.
set -euo pipefail

# F12: Unset Git routing variables
unset GIT_DIR GIT_INDEX_FILE GIT_WORK_TREE GIT_PREFIX GIT_COMMON_DIR GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES 2>/dev/null || true

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GATE="$SCRIPT_DIR/../spec-gate.sh"

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

# Purpose: set up a scratch git repo with a base commit and working tree files.
# Usage:   REPO=$(setup_repo); cd "$REPO"
# Gotchas: returns the absolute path to the repo root. F12: use mktemp -d.
setup_repo() {
  local repo="$(mktemp -d)"
  cd "$repo"
  git init -q
  git config user.email "test@example.com"
  git config user.name "Test"
  mkdir -p docs
  echo "REQ-01: must do X" > docs/requirements.md
  echo "REQ-02: must do Y" >> docs/requirements.md
  echo "Design: we do X and Y" > docs/design.md
  git add docs/
  git commit -q -m "base"
  echo "$repo"
}

# Test 1: happy path (all checks pass)
test_happy() {
  local repo=$(setup_repo)
  cd "$repo"
  local base_sha=$(git rev-parse HEAD)
  echo "NO CONFLICTS" > verdict.md
  echo "NONE" > ambiguities.md
  echo "Design: we do X and Y with a change" > docs/design.md
  git add docs/design.md
  git commit -q -m "design update"
  local out_dir="$repo/output"
  mkdir -p "$out_dir"

  "$GATE" "$repo" docs/requirements.md docs/design.md verdict.md ambiguities.md "$base_sha" "$out_dir" > /dev/null
  local exit_code=$?

  [[ $exit_code -eq 0 ]] || { echo "exit=$exit_code (expected 0)"; return 1; }
  [[ -f "$out_dir/design.diff" ]] || { echo "design.diff not written"; return 1; }
  return 0
}
test_case "happy path (all checks pass)" test_happy

# Test 2: verdict line 1 is not NO CONFLICTS
test_verdict_bad() {
  local repo=$(setup_repo)
  cd "$repo"
  local base_sha=$(git rev-parse HEAD)
  echo "CONFLICTS FOUND" > verdict.md
  echo "NONE" > ambiguities.md
  local out_dir="$repo/output"
  mkdir -p "$out_dir"

  "$GATE" "$repo" docs/requirements.md docs/design.md verdict.md ambiguities.md "$base_sha" "$out_dir" > /dev/null 2>&1
  local exit_code=$?

  [[ $exit_code -eq 1 ]] || { echo "exit=$exit_code (expected 1)"; return 1; }
  [[ -f "$out_dir/design.diff" ]] || { echo "design.diff not written on fail"; return 1; }
  return 0
}
test_case "verdict line 1 is not NO CONFLICTS" test_verdict_bad

# Test 3: ambiguities line 1 is not NONE
test_ambiguities_bad() {
  local repo=$(setup_repo)
  cd "$repo"
  local base_sha=$(git rev-parse HEAD)
  echo "NO CONFLICTS" > verdict.md
  echo "REQ-01 is ambiguous" > ambiguities.md
  local out_dir="$repo/output"
  mkdir -p "$out_dir"

  "$GATE" "$repo" docs/requirements.md docs/design.md verdict.md ambiguities.md "$base_sha" "$out_dir" > /dev/null 2>&1
  local exit_code=$?

  [[ $exit_code -eq 1 ]] || { echo "exit=$exit_code (expected 1)"; return 1; }
  return 0
}
test_case "ambiguities line 1 is not NONE" test_ambiguities_bad

# Test 3b: ambiguities all tagged P2: pass (owner, 2026-11-15: only P0/P1 block)
# Test 3c: one P1: line among P2: lines fails
# Purpose: run the gate on a given ambiguities text and check the exit code.
# Usage:   ambig_case "<text>" <expected exit>
# Gotchas: the verdict is NO CONFLICTS, so only check 3 decides the result.
ambig_case() {
  local repo=$(setup_repo)
  cd "$repo"
  local base_sha=$(git rev-parse HEAD)
  echo "NO CONFLICTS" > verdict.md
  printf '%s\n' "$1" > ambiguities.md
  mkdir -p "$repo/output"
  "$GATE" "$repo" docs/requirements.md docs/design.md verdict.md ambiguities.md "$base_sha" "$repo/output" > /dev/null 2>&1
  local exit_code=$?
  [[ $exit_code -eq $2 ]] || { echo "exit=$exit_code (expected $2)"; return 1; }
}
test_ambiguities_coder_only() { ambig_case $'P2: field names\nP2: batch size' 0; }
test_ambiguities_one_blocking() { ambig_case $'P2: field names\nP1: which source feeds membership' 1; }
test_case "ambiguities all tagged P2: pass" test_ambiguities_coder_only
test_case "one P1: ambiguity fails" test_ambiguities_one_blocking

# Test 4: requirements changed (staged change)
test_requirements_changed_staged() {
  local repo=$(setup_repo)
  cd "$repo"
  local base_sha=$(git rev-parse HEAD)
  echo "NO CONFLICTS" > verdict.md
  echo "NONE" > ambiguities.md
  echo "REQ-01: must do X differently" > docs/requirements.md
  git add docs/requirements.md
  echo "Design: updated" > docs/design.md
  git add docs/design.md
  local out_dir="$repo/output"
  mkdir -p "$out_dir"

  local output
  output=$("$GATE" "$repo" docs/requirements.md docs/design.md verdict.md ambiguities.md "$base_sha" "$out_dir" 2>&1) || local exit_code=$?

  # c7e1271: requirements changed now proceeds (exit 0), doesn't restore
  [[ ${exit_code:-0} -eq 0 ]] || { echo "exit=${exit_code:-0} (expected 0)"; return 1; }
  # Files are committed, not restored
  local req_content=$(cat docs/requirements.md)
  [[ "$req_content" == "REQ-01: must do X differently" ]] || { echo "requirements should be committed as changed"; return 1; }
  local design_content=$(cat docs/design.md)
  [[ "$design_content" == "Design: updated" ]] || { echo "design should be committed as changed"; return 1; }
  return 0
}
test_case "requirements changed (staged) restores both files" test_requirements_changed_staged

# Test 5: requirements changed (unstaged change)
test_requirements_changed_unstaged() {
  local repo=$(setup_repo)
  cd "$repo"
  local base_sha=$(git rev-parse HEAD)
  echo "NO CONFLICTS" > verdict.md
  echo "NONE" > ambiguities.md
  echo "REQ-01: must do X differently" > docs/requirements.md
  local out_dir="$repo/output"
  mkdir -p "$out_dir"

  local output
  output=$("$GATE" "$repo" docs/requirements.md docs/design.md verdict.md ambiguities.md "$base_sha" "$out_dir" 2>&1) || local exit_code=$?

  # c7e1271: requirements changed now proceeds (exit 0)
  [[ ${exit_code:-0} -eq 0 ]] || { echo "exit=${exit_code:-0} (expected 0)"; return 1; }
  # File is committed
  local req_content=$(cat docs/requirements.md)
  [[ "$req_content" == "REQ-01: must do X differently" ]] || { echo "requirements should be committed as changed"; return 1; }
  return 0
}
test_case "requirements changed (unstaged) proceeds" test_requirements_changed_unstaged

# Test 6: trailing whitespace in verdict allowed
test_verdict_trailing_whitespace() {
  local repo=$(setup_repo)
  cd "$repo"
  local base_sha=$(git rev-parse HEAD)
  echo "NO CONFLICTS   " > verdict.md
  echo "NONE" > ambiguities.md
  local out_dir="$repo/output"
  mkdir -p "$out_dir"

  "$GATE" "$repo" docs/requirements.md docs/design.md verdict.md ambiguities.md "$base_sha" "$out_dir" > /dev/null
  local exit_code=$?

  [[ $exit_code -eq 0 ]] || { echo "exit=$exit_code (expected 0)"; return 1; }
  return 0
}
test_case "verdict line 1 with trailing whitespace passes" test_verdict_trailing_whitespace

# Test 7: design.diff always written
test_diff_always_written() {
  local repo=$(setup_repo)
  cd "$repo"
  local base_sha=$(git rev-parse HEAD)
  echo "CONFLICTS FOUND" > verdict.md
  echo "REQ-01 ambiguous" > ambiguities.md
  echo "Design: changed" > docs/design.md
  local out_dir="$repo/output"
  mkdir -p "$out_dir"

  "$GATE" "$repo" docs/requirements.md docs/design.md verdict.md ambiguities.md "$base_sha" "$out_dir" > /dev/null 2>&1

  [[ -f "$out_dir/design.diff" ]] || { echo "design.diff not written"; return 1; }
  local diff_content=$(cat "$out_dir/design.diff")
  [[ -n "$diff_content" ]] || { echo "design.diff is empty"; return 1; }
  return 0
}
test_case "design.diff always written even on fail" test_diff_always_written

# Test 8: --help flag
test_help() {
  local output=$("$GATE" --help 2>&1)
  [[ "$output" =~ usage|Usage ]] || { echo "no usage text"; return 1; }
  return 0
}
test_case "--help flag shows usage" test_help

# Test 9: missing arguments
test_missing_args() {
  local output
  output=$("$GATE" 2>&1) && local exit_code=$? || local exit_code=$?
  [[ "$output" =~ [Uu]sage ]] || { echo "no usage text in output"; return 1; }
  [[ $exit_code -eq 2 ]] || { echo "exit=$exit_code (expected 2)"; return 1; }
  return 0
}
test_case "missing arguments exits 2 with usage" test_missing_args

# Summary
echo "# spec-gate: $pass passed, $fail failed"
[[ $fail -eq 0 ]] && exit 0 || exit 1
