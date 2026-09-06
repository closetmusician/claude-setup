#!/bin/bash
# ABOUTME: Post-commit hook that auto-pushes feature branches to origin.
# ABOUTME: Pushes work/*, feature/*, feat/* branches in the background.
# ABOUTME: Never pushes main/master. Never blocks commits (exit 0 always).
# ABOUTME: Logs failures to .git/push-failures.log relative to repo root.
# ABOUTME: Safe to symlink from any repo's .git/hooks/post-commit.

set -euo pipefail

# Never block a commit — catch all errors and exit clean.
trap 'exit 0' ERR

# Resolve the repo root for logging. Skip if not in a git repo.
REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || exit 0
LOG_FILE="$REPO_ROOT/.git/push-failures.log"

# log_failure <message>
# Appends a timestamped failure line to the push log.
log_failure() {
  local msg="$1"
  local ts
  ts=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
  echo "[$ts] $msg" >> "$LOG_FILE" 2>/dev/null || true
}

# Detect detached HEAD — nothing to push.
BRANCH=$(git symbolic-ref --short HEAD 2>/dev/null) || exit 0

# Only push allowed branch prefixes. Everything else (main, master, etc.) skips.
case "$BRANCH" in
  work/*|feature/*|feat/*) ;;
  *) exit 0 ;;
esac

# Verify "origin" remote exists. Skip if no remote configured.
if ! git remote get-url origin &>/dev/null; then
  log_failure "branch=$BRANCH: no 'origin' remote configured, skipping push"
  exit 0
fi

# Push in the background so the commit returns instantly.
# Uses -u on first push (no upstream) to set tracking. Subsequent pushes are plain.
(
  if git rev-parse --abbrev-ref --symbolic-full-name '@{u}' &>/dev/null; then
    # Upstream exists — plain push.
    if ! git push origin "$BRANCH" 2>/dev/null; then
      log_failure "branch=$BRANCH: push to origin failed"
    fi
  else
    # No upstream yet — set tracking.
    if ! git push -u origin "$BRANCH" 2>/dev/null; then
      log_failure "branch=$BRANCH: initial push -u to origin failed"
    fi
  fi
) &

# Disown the background process so the shell doesn't wait for it.
disown 2>/dev/null || true

exit 0
