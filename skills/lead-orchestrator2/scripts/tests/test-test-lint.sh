#!/usr/bin/env bash
# ABOUTME: Tests for test-lint.py. It checks Python test files added or changed since base_ref for
# ABOUTME: inspect.getsource calls, reading source as text (open/read_text with .py paths), and
# ABOUTME: asserts on single-underscore attributes. Non-Python test files print NOT LINTED. Parse
# ABOUTME: errors are hits (rule p). Git fixtures live under /tmp/<uuid>.
set -euo pipefail

# F12: Unset Git routing variables
unset GIT_DIR GIT_INDEX_FILE GIT_WORK_TREE GIT_PREFIX GIT_COMMON_DIR GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES 2>/dev/null || true

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LINT="python3 $SCRIPT_DIR/../test-lint.py"

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
  git init -q
  git config user.email "test@example.com"
  git config user.name "Test"
  mkdir -p tests src
  echo "# base" > tests/test_base.py
  git add tests/
  git commit -q -m "base"
  echo "$repo"
}

# Test 1: clean file passes
test_clean() {
  local repo=$(setup_repo)
  cd "$repo"
  local base=$(git rev-parse HEAD)
  cat > tests/test_new.py << 'EOF'
def test_foo():
    assert 1 + 1 == 2
EOF
  git add tests/test_new.py

  local output
  output=$(eval "$LINT" "$repo" "$base" 2>&1) && local exit_code=$? || local exit_code=$?

  [[ $exit_code -eq 0 ]] || { echo "exit=$exit_code (expected 0)"; rm -rf "$repo"; return 1; }
  rm -rf "$repo"
  return 0
}
test_case "clean file passes" test_clean

# Test 2: inspect.getsource triggers rule a
test_inspect_getsource() {
  local repo=$(setup_repo)
  cd "$repo"
  local base=$(git rev-parse HEAD)
  cat > tests/test_inspect.py << 'EOF'
import inspect
def test_foo():
    src = inspect.getsource(test_foo)
    assert src
EOF
  git add tests/test_inspect.py

  local output
  output=$(eval "$LINT" "$repo" "$base" 2>&1) || local exit_code=$?

  [[ ${exit_code:-0} -eq 1 ]] || { echo "exit=${exit_code:-0} (expected 1)"; rm -rf "$repo"; return 1; }
  [[ "$output" =~ "tests/test_inspect.py:3 a" ]] || { echo "rule a not reported"; rm -rf "$repo"; return 1; }
  rm -rf "$repo"
  return 0
}
test_case "inspect.getsource triggers rule a" test_inspect_getsource

# Test 3: open with .py path triggers rule b
test_open_py_file() {
  local repo=$(setup_repo)
  cd "$repo"
  local base=$(git rev-parse HEAD)
  cat > tests/test_open.py << 'EOF'
def test_foo():
    with open("src/module.py") as f:
        content = f.read()
EOF
  git add tests/test_open.py

  local output
  output=$(eval "$LINT" "$repo" "$base" 2>&1) || local exit_code=$?

  [[ ${exit_code:-0} -eq 1 ]] || { echo "exit=${exit_code:-0} (expected 1)"; rm -rf "$repo"; return 1; }
  [[ "$output" =~ "tests/test_open.py:2 b" ]] || { echo "rule b not reported"; rm -rf "$repo"; return 1; }
  rm -rf "$repo"
  return 0
}
test_case "open with .py path triggers rule b" test_open_py_file

# Test 4: assert on single underscore attribute triggers rule c
test_assert_private() {
  local repo=$(setup_repo)
  cd "$repo"
  local base=$(git rev-parse HEAD)
  cat > tests/test_assert.py << 'EOF'
def test_foo():
    obj = SomeClass()
    assert obj._private == 42
EOF
  git add tests/test_assert.py

  local output
  output=$(eval "$LINT" "$repo" "$base" 2>&1) || local exit_code=$?

  [[ ${exit_code:-0} -eq 1 ]] || { echo "exit=${exit_code:-0} (expected 1)"; rm -rf "$repo"; return 1; }
  [[ "$output" =~ "tests/test_assert.py:3 c" ]] || { echo "rule c not reported"; rm -rf "$repo"; return 1; }
  rm -rf "$repo"
  return 0
}
test_case "assert on single underscore attribute triggers rule c" test_assert_private

# Test 5: dunder attributes are allowed
test_dunder_allowed() {
  local repo=$(setup_repo)
  cd "$repo"
  local base=$(git rev-parse HEAD)
  cat > tests/test_dunder.py << 'EOF'
def test_foo():
    obj = SomeClass()
    assert obj.__name__ == "test"
EOF
  git add tests/test_dunder.py

  local output
  output=$(eval "$LINT" "$repo" "$base" 2>&1) && local exit_code=$? || local exit_code=$?

  [[ $exit_code -eq 0 ]] || { echo "exit=$exit_code (expected 0)"; rm -rf "$repo"; return 1; }
  rm -rf "$repo"
  return 0
}
test_case "dunder attributes are allowed" test_dunder_allowed

# Test 6: parse error triggers rule p
test_parse_error() {
  local repo=$(setup_repo)
  cd "$repo"
  local base=$(git rev-parse HEAD)
  cat > tests/test_syntax.py << 'EOF'
def test_foo()
    assert True
EOF
  git add tests/test_syntax.py

  local output
  output=$(eval "$LINT" "$repo" "$base" 2>&1) || local exit_code=$?

  [[ ${exit_code:-0} -eq 1 ]] || { echo "exit=${exit_code:-0} (expected 1)"; rm -rf "$repo"; return 1; }
  [[ "$output" =~ "tests/test_syntax.py:1 p" ]] || { echo "rule p not reported"; rm -rf "$repo"; return 1; }
  rm -rf "$repo"
  return 0
}
test_case "parse error triggers rule p" test_parse_error

# Test 7: only checks added/modified test files
test_only_new_files() {
  local repo=$(setup_repo)
  cd "$repo"
  local base=$(git rev-parse HEAD)
  # Existing file with violation (not checked)
  cat > tests/test_base.py << 'EOF'
import inspect
def test_old():
    src = inspect.getsource(test_old)
EOF
  git add tests/test_base.py
  git commit -q -m "modify base"
  local base2=$(git rev-parse HEAD)
  # New file without violation
  cat > tests/test_new.py << 'EOF'
def test_new():
    assert True
EOF
  git add tests/test_new.py

  local output
  output=$(eval "$LINT" "$repo" "$base2" 2>&1) && local exit_code=$? || local exit_code=$?

  [[ $exit_code -eq 0 ]] || { echo "exit=$exit_code (expected 0), checked old file"; rm -rf "$repo"; return 1; }
  rm -rf "$repo"
  return 0
}
test_case "only checks added/modified test files since base_ref" test_only_new_files

# Test 8: non-Python test files print NOT LINTED
test_non_python() {
  local repo=$(setup_repo)
  cd "$repo"
  local base=$(git rev-parse HEAD)
  cat > tests/test_new.js << 'EOF'
test('foo', () => { expect(1).toBe(1); });
EOF
  git add tests/test_new.js

  local output
  output=$(eval "$LINT" "$repo" "$base" 2>&1) && local exit_code=$? || local exit_code=$?

  [[ $exit_code -eq 0 ]] || { echo "exit=$exit_code (expected 0)"; rm -rf "$repo"; return 1; }
  [[ "$output" =~ "NOT LINTED: tests/test_new.js" ]] || { echo "NOT LINTED message missing"; rm -rf "$repo"; return 1; }
  rm -rf "$repo"
  return 0
}
test_case "non-Python test files print NOT LINTED" test_non_python

# Test 9: --help flag
test_help() {
  local output=$(eval "$LINT" --help 2>&1)
  [[ "$output" =~ usage|Usage ]] || { echo "no usage text"; return 1; }
  return 0
}
test_case "--help flag shows usage" test_help

# Test 10: Path.read_text with .py triggers rule b
test_path_read_text() {
  local repo=$(setup_repo)
  cd "$repo"
  local base=$(git rev-parse HEAD)
  cat > tests/test_path.py << 'EOF'
from pathlib import Path
def test_foo():
    content = Path("src/module.py").read_text()
EOF
  git add tests/test_path.py

  local output
  output=$(eval "$LINT" "$repo" "$base" 2>&1) || local exit_code=$?

  [[ ${exit_code:-0} -eq 1 ]] || { echo "exit=${exit_code:-0} (expected 1)"; rm -rf "$repo"; return 1; }
  [[ "$output" =~ "tests/test_path.py:3 b" ]] || { echo "rule b not reported"; rm -rf "$repo"; return 1; }
  rm -rf "$repo"
  return 0
}
test_case "Path.read_text with .py triggers rule b" test_path_read_text

echo "# test-lint: $pass passed, $fail failed"
[[ $fail -eq 0 ]] && exit 0 || exit 1
