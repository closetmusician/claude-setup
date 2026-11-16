#!/usr/bin/env python3
# ABOUTME: Step 8 gate for arm D. Lints Python test files added or changed since base_ref using
# ABOUTME: the ast module. Fails on inspect.getsource calls, reading source as text (open/read_text
# ABOUTME: with .py paths or src/ in the path), and asserts on single-underscore attributes. Non-Python
# ABOUTME: test files print NOT LINTED. Parse errors are hits (rule p). Exit 0 = clean, exit 1 = hits, exit 2 = usage.

import ast
import os
import subprocess
import sys


def usage():
    """
    Purpose: show usage text and exit with code 2 (usage error).
    Usage:   called on --help or wrong argument count.
    Gotchas: prints to stderr then exits.
    """
    print("""Usage: test-lint.py <repo> <base_ref>

Lints Python test files added or changed since base_ref.

Rules:
  a - inspect.getsource, inspect.getsourcelines, inspect.getfile calls
  b - reading source as text: open(...), .read_text(), .read_bytes() when
      the path expression contains a string literal with 'src/' or ending in '.py'
  c - assert that reads a single-underscore attribute (not dunder)
  p - parse error

Output: file:line rule-letter what (one per hit)
Exit codes:
  0 = no hits
  1 = one or more hits
  2 = usage error

Non-Python test files print "NOT LINTED: <file>" and do not fail.
""", file=sys.stderr)
    sys.exit(2)


def get_test_files(repo, base_ref):
    """
    Purpose: get list of test files added or modified since base_ref.
    Usage:   files = get_test_files("/repo", "abc123")
    Gotchas: returns absolute paths; a test file is test_*.py, *_test.py, or any .py under tests/.
    """
    try:
        result = subprocess.run(
            ["git", "diff", "--name-only", "--diff-filter=AM", base_ref],
            cwd=repo,
            capture_output=True,
            text=True,
            check=True
        )
        all_files = result.stdout.strip().split('\n') if result.stdout.strip() else []

        test_files = []
        for f in all_files:
            if not f:
                continue
            # Test file patterns
            basename = os.path.basename(f)
            dirname = os.path.dirname(f)
            is_test = (
                basename.startswith('test_') and basename.endswith('.py') or
                basename.endswith('_test.py') or
                '/tests/' in f or dirname == 'tests'
            )
            if is_test:
                test_files.append(os.path.join(repo, f))
        return test_files
    except subprocess.CalledProcessError:
        return []


def check_file(filepath):
    """
    Purpose: lint one Python test file and return a list of violations.
    Usage:   hits = check_file("/repo/tests/test_foo.py")
    Gotchas: returns list of (line, rule, what) tuples; parse errors return rule 'p'.
    """
    hits = []

    # Non-Python files
    if not filepath.endswith('.py'):
        return [('NOT_LINTED', '', filepath)]

    try:
        with open(filepath, 'r') as f:
            source = f.read()
        tree = ast.parse(source, filename=filepath)
    except SyntaxError as e:
        return [(e.lineno or 1, 'p', f'parse error: {e.msg}')]
    except Exception as e:
        return [(1, 'p', f'parse error: {str(e)}')]

    # Walk the AST
    for node in ast.walk(tree):
        # Rule a: inspect.getsource, inspect.getsourcelines, inspect.getfile
        if isinstance(node, ast.Call):
            if isinstance(node.func, ast.Attribute):
                if (isinstance(node.func.value, ast.Name) and
                    node.func.value.id == 'inspect' and
                    node.func.attr in ('getsource', 'getsourcelines', 'getfile')):
                    hits.append((node.lineno, 'a', f'inspect.{node.func.attr}'))

            # Rule b: open(...), .read_text(), .read_bytes() with .py or src/ in path
            if isinstance(node.func, ast.Name) and node.func.id == 'open':
                if node.args and isinstance(node.args[0], ast.Constant):
                    path_str = str(node.args[0].value)
                    if path_str.endswith('.py') or 'src/' in path_str:
                        hits.append((node.lineno, 'b', f'open("{path_str}")'))

            if isinstance(node.func, ast.Attribute):
                if node.func.attr in ('read_text', 'read_bytes'):
                    # Check if the object is a Path with a .py string
                    if isinstance(node.func.value, ast.Call):
                        if isinstance(node.func.value.func, ast.Name) and node.func.value.func.id == 'Path':
                            if node.func.value.args and isinstance(node.func.value.args[0], ast.Constant):
                                path_str = str(node.func.value.args[0].value)
                                if path_str.endswith('.py') or 'src/' in path_str:
                                    hits.append((node.lineno, 'b', f'Path("{path_str}").{node.func.attr}()'))

        # Rule c: assert on single-underscore attribute (not dunder)
        if isinstance(node, ast.Assert):
            # Walk the test expression to find attribute accesses
            for child in ast.walk(node.test):
                if isinstance(child, ast.Attribute):
                    attr_name = child.attr
                    if attr_name.startswith('_') and not attr_name.startswith('__'):
                        hits.append((node.lineno, 'c', f'assert on .{attr_name}'))

    return hits


def main():
    """
    Purpose: main entry point for test-lint.py.
    Usage:   called from command line with repo and base_ref arguments.
    Gotchas: exits 0 (clean), 1 (hits), or 2 (usage error).
    """
    if len(sys.argv) == 2 and sys.argv[1] in ('--help', '-h'):
        usage()

    if len(sys.argv) != 3:
        usage()

    repo = sys.argv[1]
    base_ref = sys.argv[2]

    test_files = get_test_files(repo, base_ref)

    all_hits = []
    for filepath in test_files:
        relpath = os.path.relpath(filepath, repo)
        hits = check_file(filepath)
        for hit in hits:
            if hit[0] == 'NOT_LINTED':
                print(f"NOT LINTED: {relpath}")
            else:
                line, rule, what = hit
                all_hits.append(f"{relpath}:{line} {rule} {what}")

    if all_hits:
        for hit in all_hits:
            print(hit)
        sys.exit(1)
    else:
        sys.exit(0)


if __name__ == '__main__':
    main()
