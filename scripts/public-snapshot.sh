#!/usr/bin/env bash
# ABOUTME: Copies the shareable folders of private ~/.claude main into a checkout of the PUBLIC
# ABOUTME: closetmusician/claude-setup repo, then commits there. It never pushes; you push after review.
# ABOUTME: Private paths (docs/, handoffs/, memory/, rules/personal.md) never go out. Company names may.
# ABOUTME: Fails closed (exit 1, no commit) if any copied file holds a token or key pattern.
# ABOUTME: Usage: public-snapshot.sh <src-repo> <src-ref> <public-repo>. Tests: scripts/tests/test-public-snapshot.sh

set -uo pipefail

SRC="$1"; REF="$2"; PUB="$3"
SECRET_SCAN="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/secret-scan.sh"

# What goes public. Folders are mirrored from $REF, so a file deleted in main is deleted here too.
INCLUDE=(.githooks bin evals hooks plugins policy references rules scripts skills tests
         CLAUDE.md RTK.md settings.json litellm_config.yaml skills-lock.json .gitignore)
# Private files inside an included folder.
EXCLUDE=(rules/personal.md)
# Public-only files: the newcomer README, the installer and the personal-rules template.
KEEP=(README.md install.sh rules/personal.md.example)
# Bearer and AWS secret keys are not in secret-scan.sh's provider list, so check them here.
EXTRA_PATTERNS='Bearer [A-Za-z0-9._~+/=-]{24,}|aws_secret_access_key *= *[A-Za-z0-9/+]{30,}'

cd "$PUB" || { echo "public-snapshot: no repo at $PUB" >&2; exit 2; }
[ -z "$(git status --porcelain)" ] || { echo "public-snapshot: $PUB has uncommitted changes" >&2; exit 2; }

# Mirror: remove the included paths, extract them fresh from $REF, drop excludes, restore keeps.
for p in "${INCLUDE[@]}"; do git rm -r -q --ignore-unmatch -- "$p" >/dev/null; rm -rf -- "$p"; done
present=(); for p in "${INCLUDE[@]}"; do git -C "$SRC" cat-file -e "$REF:$p" 2>/dev/null && present+=("$p"); done
git -C "$SRC" archive "$REF" -- "${present[@]}" | tar -x -C "$PUB"
for p in "${EXCLUDE[@]}"; do rm -rf -- "$p"; done
for p in "${KEEP[@]}"; do git cat-file -e "HEAD:$p" 2>/dev/null && git checkout -q HEAD -- "$p"; done

# Gate: scan every copied file. On a hit, roll the checkout back and stop.
hits="$(find "${present[@]}" -type f -print0 2>/dev/null | xargs -0 bash "$SECRET_SCAN" 2>&1 | grep 'SECRET?')"
extra="$(find "${present[@]}" -type f -print0 2>/dev/null | xargs -0 grep -lE "$EXTRA_PATTERNS" 2>/dev/null)"
if [ -n "$hits$extra" ]; then
  echo "public-snapshot: BLOCKED, secret patterns found:" >&2
  [ -n "$hits" ] && echo "$hits" >&2
  [ -n "$extra" ] && echo "$extra" | sed 's/^/  BEARER-or-AWS? /' >&2
  git reset -q --hard HEAD; git clean -q -fd
  exit 1
fi

# Stage only paths that exist: one missing pathspec makes `git add` stage nothing.
# -f is safe: every file here came from a tracked file in $REF, some force-added past .gitignore.
for p in "${INCLUDE[@]}" "${KEEP[@]}"; do [ -e "$p" ] && git add -f -- "$p"; done
git add -u
if git diff --cached --quiet; then echo "public-snapshot: no changes"; exit 0; fi
git commit -q -m "Sync from private main $(git -C "$SRC" rev-parse --short "$REF")"
echo "public-snapshot: committed $(git rev-parse --short HEAD). Review, then: git -C $PUB push origin main"
