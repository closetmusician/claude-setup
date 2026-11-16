#!/usr/bin/env bash
# ABOUTME: Tests for test-run.sh. Runs pytest with passed-through args, parses FAILED and ERROR lines,
# ABOUTME: reports new failures (not in baseline) and now passing (in baseline but passing). --make-baseline
# ABOUTME: writes baseline. Exit 0 when no new failures, exit 1 otherwise. Git fixtures under /tmp/<uuid>.
set -euo pipefail

# F12: Unset Git routing variables
unset GIT_DIR GIT_INDEX_FILE GIT_WORK_TREE GIT_PREFIX GIT_COMMON_DIR GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES 2>/dev/null || true

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RUN="$SCRIPT_DIR/../test-run.sh"

pass=0
fail=0

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

setup_repo() {
  # F12: use mktemp -d
  local repo="$(mktemp -d)"
  cd "$repo"
  # Create a fake pytest that mimics real -rfE output
  cat > fake-pytest.sh << 'EOF'
#!/usr/bin/env bash
# Fake pytest for testing (-rfE format)
case "${TEST_SCENARIO:-pass}" in
  pass)
    echo "collected 2 items"
    echo "2 passed in 0.1s"
    exit 0
    ;;
  fail)
    cat << 'INNER'
collected 2 items
=========================== short test summary info ============================
FAILED tests/test_b.py::test_2 - AssertionError
1 passed, 1 failed in 0.1s
INNER
    exit 1
    ;;
  error)
    cat << 'INNER'
=========================== short test summary info ============================
ERROR tests/test_c.py - SyntaxError
1 error in 0.1s
INNER
    exit 2
    ;;
esac
EOF
  chmod +x fake-pytest.sh
  echo "$repo"
}

# Test 1: --make-baseline creates baseline file
test_make_baseline() {
  local repo=$(setup_repo)
  cd "$repo"
  local out="$repo/out.txt"
  local baseline="$repo/baseline.txt"

  export TEST_SCENARIO=fail
  export TEST_PYTEST_CMD="$repo/fake-pytest.sh"
  local exit_code
  "$RUN" "$repo" "$out" "$baseline" --make-baseline && exit_code=$? || exit_code=$?

  [[ $exit_code -eq 0 ]] || { echo "exit=$exit_code (expected 0)"; rm -rf "$repo"; return 1; }
  [[ -f "$baseline" ]] || { echo "baseline not created"; rm -rf "$repo"; return 1; }
  grep -q "tests/test_b.py::test_2" "$baseline" || { echo "failure not in baseline"; rm -rf "$repo"; return 1; }
  rm -rf "$repo"
  return 0
}
test_case "--make-baseline creates baseline file" test_make_baseline

# Test 2: no new failures exits 0
test_no_new_failures() {
  local repo=$(setup_repo)
  cd "$repo"
  local out="$repo/out.txt"
  local baseline="$repo/baseline.txt"
  echo "tests/test_b.py::test_2" > "$baseline"

  export TEST_SCENARIO=fail
  export TEST_PYTEST_CMD="$repo/fake-pytest.sh"
  local exit_code
  "$RUN" "$repo" "$out" "$baseline" && exit_code=$? || exit_code=$?

  [[ $exit_code -eq 0 ]] || { echo "exit=$exit_code (expected 0)"; rm -rf "$repo"; return 1; }
  rm -rf "$repo"
  return 0
}
test_case "no new failures exits 0" test_no_new_failures

# Test 3: new failure exits 1
test_new_failure() {
  local repo=$(setup_repo)
  cd "$repo"
  local out="$repo/out.txt"
  local baseline="$repo/baseline.txt"
  touch "$baseline"  # empty baseline

  export TEST_SCENARIO=fail
  export TEST_PYTEST_CMD="$repo/fake-pytest.sh"
  local exit_code
  "$RUN" "$repo" "$out" "$baseline" || exit_code=$?

  [[ ${exit_code:-0} -eq 1 ]] || { echo "exit=${exit_code:-0} (expected 1)"; rm -rf "$repo"; return 1; }
  grep -q "NEW FAILURES" "$out" || { echo "NEW FAILURES not in output"; rm -rf "$repo"; return 1; }
  grep -q "tests/test_b.py::test_2" "$out" || { echo "failure not listed"; rm -rf "$repo"; return 1; }
  rm -rf "$repo"
  return 0
}
test_case "new failure exits 1" test_new_failure

# Test 4: now passing listed
test_now_passing() {
  local repo=$(setup_repo)
  cd "$repo"
  local out="$repo/out.txt"
  local baseline="$repo/baseline.txt"
  echo "tests/test_b.py::test_2" > "$baseline"

  export TEST_SCENARIO=pass
  export TEST_PYTEST_CMD="$repo/fake-pytest.sh"
  local exit_code
  "$RUN" "$repo" "$out" "$baseline" && exit_code=$? || exit_code=$?

  [[ $exit_code -eq 0 ]] || { echo "exit=$exit_code (expected 0)"; rm -rf "$repo"; return 1; }
  grep -q "NOW PASSING" "$out" || { echo "NOW PASSING not in output"; rm -rf "$repo"; return 1; }
  grep -q "tests/test_b.py::test_2" "$out" || { echo "passing test not listed"; rm -rf "$repo"; return 1; }
  rm -rf "$repo"
  return 0
}
test_case "now passing listed" test_now_passing

# Test 5: ERROR lines parsed
test_error_lines() {
  local repo=$(setup_repo)
  cd "$repo"
  local out="$repo/out.txt"
  local baseline="$repo/baseline.txt"
  touch "$baseline"

  export TEST_SCENARIO=error
  export TEST_PYTEST_CMD="$repo/fake-pytest.sh"
  local exit_code
  "$RUN" "$repo" "$out" "$baseline" || exit_code=$?

  [[ ${exit_code:-0} -eq 1 ]] || { echo "exit=${exit_code:-0} (expected 1)"; rm -rf "$repo"; return 1; }
  grep -q "tests/test_c.py" "$out" || { echo "ERROR line not parsed"; rm -rf "$repo"; return 1; }
  rm -rf "$repo"
  return 0
}
test_case "ERROR lines parsed" test_error_lines

# Test 6: --help flag
test_help() {
  local output=$("$RUN" --help 2>&1)
  [[ "$output" =~ usage|Usage ]] || { echo "no usage text"; return 1; }
  return 0
}
test_case "--help flag shows usage" test_help

# Test 7: strip message suffix from nodeid
test_strip_message() {
  local repo=$(setup_repo)
  cd "$repo"
  cat > fake-pytest2.sh << 'EOF'
#!/usr/bin/env bash
cat << 'INNER'
=========================== short test summary info ============================
FAILED tests/test_a.py::test_1 - AssertionError: expected 1
1 failed in 0.01s
INNER
exit 1
EOF
  chmod +x fake-pytest2.sh
  local out="$repo/out.txt"
  local baseline="$repo/baseline.txt"
  touch "$baseline"

  export TEST_PYTEST_CMD="$repo/fake-pytest2.sh"
  "$RUN" "$repo" "$out" "$baseline" || true

  # Check that the NEW FAILURES section has the stripped nodeid
  local new_failures_section=$(sed -n '/^NEW FAILURES/,/^NOW PASSING/p' "$out")
  [[ "$new_failures_section" =~ tests/test_a.py::test_1 ]] || { echo "failure not in NEW FAILURES"; rm -rf "$repo"; return 1; }
  # Check that the nodeid line itself doesn't have the message (line should be just the nodeid)
  echo "$new_failures_section" | grep -q "^tests/test_a.py::test_1$" || { echo "message suffix not stripped from nodeid"; rm -rf "$repo"; return 1; }

  rm -rf "$repo"
  return 0
}
test_case "strip message suffix from nodeid" test_strip_message

# Test 8: real pytest -rfE output format (item 13)
test_real_pytest_format() {
  local repo=$(setup_repo)
  cd "$repo"
  mkdir -p tests
  cat > tests/test_fixture.py << 'EOF'
def test_will_fail():
    assert 1 == 2
EOF

  local out="$repo/out.txt"
  local baseline="$repo/baseline.txt"
  touch "$baseline"

  # Use real pytest -rfE format output
  cat > fake-real.sh << 'INNER'
#!/usr/bin/env bash
cat << 'PYTEST_OUT'
F                                                                        [100%]
=========================== short test summary info ============================
FAILED tests/test_fixture.py::test_will_fail - AssertionError: assert 1 == 2
1 failed in 0.01s
PYTEST_OUT
exit 1
INNER
  chmod +x fake-real.sh

  export TEST_PYTEST_CMD="$repo/fake-real.sh"
  "$RUN" "$repo" "$out" "$baseline" || true

  # Check that the nodeid was parsed correctly from "FAILED nodeid - message" format
  grep -q "tests/test_fixture.py::test_will_fail" "$out" || { echo "real -rfE format not parsed"; rm -rf "$repo"; return 1; }

  # Check baseline format: bare nodeid, no FAILED word
  "$RUN" "$repo" "$out" "$baseline" --make-baseline || true
  local baseline_content=$(cat "$baseline")
  [[ "$baseline_content" == "tests/test_fixture.py::test_will_fail" ]] || { echo "baseline format wrong"; rm -rf "$repo"; return 1; }

  rm -rf "$repo"
  return 0
}
test_case "real pytest -rfE output format" test_real_pytest_format

# Test 9: --related option (item 8)
test_related_option() {
  local repo=$(setup_repo)
  cd "$repo"
  git init -q
  git config user.email "test@test.com"
  git config user.name "Test"

  mkdir -p src/mymod tests
  cat > src/mymod/core.py << 'EOF'
def foo():
    return 1
EOF
  cat > tests/test_core.py << 'EOF'
from mymod.core import foo
def test_foo():
    assert foo() == 1
EOF
  cat > tests/test_other.py << 'EOF'
def test_other():
    assert True
EOF
  git add src tests
  git commit -q -m "base"
  local base=$(git rev-parse HEAD)

  # Modify src/mymod/core.py
  echo "# changed" >> src/mymod/core.py

  local out="$repo/out.txt"
  local baseline="$repo/baseline.txt"
  touch "$baseline"

  # Fake pytest that accepts file args
  cat > fake-related.sh << 'INNER'
#!/usr/bin/env bash
# Check that only test_core.py is selected (imports mymod.core)
[[ "$*" =~ test_core.py ]] || { echo "test_core.py not selected" >&2; exit 2; }
[[ "$*" =~ test_other.py ]] && { echo "test_other.py wrongly selected" >&2; exit 2; }
echo "1 passed"
exit 0
INNER
  chmod +x fake-related.sh

  export TEST_PYTEST_CMD="$repo/fake-related.sh"
  "$RUN" "$repo" "$out" "$baseline" --related "$base" && exit_code=$? || exit_code=$?

  [[ $exit_code -eq 0 ]] || { echo "exit=$exit_code (expected 0)"; rm -rf "$repo"; return 1; }
  grep -q "SELECTED.*test" "$out" || { echo "no selection message"; rm -rf "$repo"; return 1; }

  rm -rf "$repo"
  return 0
}
test_case "--related option selects importing tests" test_related_option

# Test 10: .py only filter (item 14)
test_py_only_filter() {
  local repo=$(setup_repo)
  cd "$repo"
  git init -q
  git config user.email "test@test.com"
  git config user.name "Test"

  mkdir -p tests/__pycache__
  cat > tests/test_one.py << 'EOF'
def test_one():
    assert True
EOF
  echo "fake pyc content" > "tests/__pycache__/test_one.cpython-39.pyc"
  git add tests
  git commit -q -m "base"
  local base=$(git rev-parse HEAD)

  # Modify test file
  echo "# changed" >> tests/test_one.py

  local out="$repo/out.txt"
  local baseline="$repo/baseline.txt"
  touch "$baseline"

  # Fake pytest that would fail if .pyc is passed
  cat > fake-py-only.sh << 'INNER'
#!/usr/bin/env bash
[[ "$*" =~ \.pyc ]] && { echo "ERROR: .pyc file passed to pytest" >&2; exit 2; }
echo "1 passed"
exit 0
INNER
  chmod +x fake-py-only.sh

  export TEST_PYTEST_CMD="$repo/fake-py-only.sh"
  "$RUN" "$repo" "$out" "$baseline" --related "$base" && exit_code=$? || exit_code=$?

  [[ $exit_code -eq 0 ]] || { echo "exit=$exit_code (expected 0), .pyc passed"; rm -rf "$repo"; return 1; }

  rm -rf "$repo"
  return 0
}
test_case ".py only filter excludes .pyc" test_py_only_filter

echo "# test-run: $pass passed, $fail failed"
[[ $fail -eq 0 ]] && exit 0 || exit 1
