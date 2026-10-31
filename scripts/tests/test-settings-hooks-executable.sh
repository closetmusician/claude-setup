#!/usr/bin/env bash
# ABOUTME: Checks that every hook command wired in settings.json points at an existing,
# ABOUTME: executable file. A 644 script fails with "permission denied" and silently never runs.
# ABOUTME: Commands of the form `bash <path>` only need the file to exist.
# ABOUTME: Run: bash scripts/tests/test-settings-hooks-executable.sh — exit 0 = all green.
# ABOUTME: Added 2026-10-11 after three new governance hooks were committed as 644.

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "${SCRIPT_DIR}/../.." && pwd)"
SETTINGS="${REPO}/settings.json"
PASS=0; FAIL=0

echo "=== test-settings-hooks-executable.sh ==="
while IFS= read -r cmd; do
  first="${cmd%% *}"
  needs_exec=1
  if [[ "$first" == "bash" || "$first" == "sh" ]]; then
    rest="${cmd#* }"; first="${rest%% *}"; needs_exec=0
  fi
  [[ "$first" == /Users/yklin/.claude/* || "$first" == "~/.claude/"* ]] || continue
  # Resolve against THIS checkout so a worktree tests its own files.
  case "$first" in
    "~/.claude/"*) path="$REPO/${first#"~/.claude/"}" ;;
    *) path="$REPO/${first#/Users/yklin/.claude/}" ;;
  esac
  if [[ ! -f "$path" ]]; then
    FAIL=$((FAIL+1)); printf '  FAIL missing: %s\n' "$first"
  elif [[ "$needs_exec" -eq 1 && ! -x "$path" ]]; then
    FAIL=$((FAIL+1)); printf '  FAIL not executable: %s\n' "$first"
  else
    PASS=$((PASS+1))
  fi
done < <(jq -r '.hooks[][] .hooks[] .command' "$SETTINGS" | sort -u)

echo "=== $PASS passed, $FAIL failed ==="
[ "$FAIL" -eq 0 ]
