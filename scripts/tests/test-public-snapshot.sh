#!/usr/bin/env bash
# ABOUTME: TDD suite for scripts/public-snapshot.sh, which copies the shareable folders of private
# ABOUTME: main into the public closetmusician/claude-setup checkout and commits them there.
# ABOUTME: It must drop private paths, keep the public-only files, and fail closed on any secret.
# ABOUTME: Fake tokens are built at run time so this file never trips the secret-scan commit hook.
# ABOUTME: Run: bash scripts/tests/test-public-snapshot.sh  (exit 0 = all green).

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SNAP="${SCRIPT_DIR}/../public-snapshot.sh"
PASS=0; FAIL=0
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT

ok()   { PASS=$((PASS+1)); printf '  ok   %s\n' "$1"; }
bad()  { FAIL=$((FAIL+1)); printf '  FAIL %s\n' "$1"; }
want() { if eval "$2"; then ok "$1"; else bad "$1"; fi; }

# make_repos: build a fresh private source repo and a public repo. Usage: make_repos <extra-line>.
# The extra line goes into skills/a/SKILL.md, so a case can plant a fake secret there.
# Gotcha: both repos need a commit identity, or `git commit` fails inside the script.
make_repos() {
  rm -rf "$TMP/src" "$TMP/pub"
  mkdir -p "$TMP/src/skills/a" "$TMP/src/rules" "$TMP/src/docs" "$TMP/src/scripts"
  printf 'skill a\n%s\n' "$1" > "$TMP/src/skills/a/SKILL.md"
  echo "my name" > "$TMP/src/rules/personal.md"
  echo "code style" > "$TMP/src/rules/code-style.md"
  echo "private plan" > "$TMP/src/docs/plan.md"
  echo "echo hi" > "$TMP/src/scripts/x.sh"
  mkdir -p "$TMP/src/bin"; echo tool > "$TMP/src/bin/tool"; echo "bin/" > "$TMP/src/.gitignore"
  echo "private readme" > "$TMP/src/README.md"
  git -C "$TMP/src" init -q -b main
  git -C "$TMP/src" add . && git -C "$TMP/src" add -f bin/tool && git -C "$TMP/src" -c user.name=t -c user.email=t@t commit -qm src

  mkdir -p "$TMP/pub/rules" "$TMP/pub/scripts"
  echo "public readme" > "$TMP/pub/README.md"
  echo "example" > "$TMP/pub/rules/personal.md.example"
  echo "gone" > "$TMP/pub/scripts/old.sh"
  git -C "$TMP/pub" init -q -b main
  git -C "$TMP/pub" add . && git -C "$TMP/pub" -c user.name=t -c user.email=t@t commit -qm pub
  git -C "$TMP/pub" config user.name t; git -C "$TMP/pub" config user.email t@t
}

echo "case: clean sync"
make_repos "nothing secret"
bash "$SNAP" "$TMP/src" main "$TMP/pub" >/dev/null 2>&1; rc=$?
want "exit 0"                       '[ "$rc" -eq 0 ]'
want "skill copied"                 '[ -f "$TMP/pub/skills/a/SKILL.md" ]'
want "ignored-but-tracked bin kept" 'git -C "$TMP/pub" cat-file -e HEAD:bin/tool 2>/dev/null'
want "rules copied"                 '[ -f "$TMP/pub/rules/code-style.md" ]'
want "docs not copied"              '[ ! -e "$TMP/pub/docs" ]'
want "personal.md not copied"       '[ ! -e "$TMP/pub/rules/personal.md" ]'
want "public README kept"           'grep -q "public readme" "$TMP/pub/README.md"'
want "personal.md.example kept"     '[ -f "$TMP/pub/rules/personal.md.example" ]'
want "file deleted in main removed" '[ ! -e "$TMP/pub/scripts/old.sh" ]'
want "one new commit"               '[ "$(git -C "$TMP/pub" rev-list --count HEAD)" -eq 2 ]'
want "tree clean after commit"      '[ -z "$(git -C "$TMP/pub" status --porcelain)" ]'

echo "case: provider token blocks"
make_repos "token ghp_$(printf 'a%.0s' {1..36})"
bash "$SNAP" "$TMP/src" main "$TMP/pub" >/dev/null 2>&1; rc=$?
want "exit 1"                       '[ "$rc" -eq 1 ]'
want "no commit made"               '[ "$(git -C "$TMP/pub" rev-list --count HEAD)" -eq 1 ]'

echo "case: bearer token blocks"
make_repos "Authorization=Bearer $(printf 'Zq9%.0s' {1..12})"
bash "$SNAP" "$TMP/src" main "$TMP/pub" >/dev/null 2>&1; rc=$?
want "exit 1"                       '[ "$rc" -eq 1 ]'
want "no commit made"               '[ "$(git -C "$TMP/pub" rev-list --count HEAD)" -eq 1 ]'

echo "case: nothing changed"
make_repos "nothing secret"
bash "$SNAP" "$TMP/src" main "$TMP/pub" >/dev/null 2>&1
bash "$SNAP" "$TMP/src" main "$TMP/pub" >/dev/null 2>&1; rc=$?
want "second run exit 0"            '[ "$rc" -eq 0 ]'
want "no empty commit"              '[ "$(git -C "$TMP/pub" rev-list --count HEAD)" -eq 2 ]'

printf '=== %d passed, %d failed ===\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
