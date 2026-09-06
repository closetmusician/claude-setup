#!/usr/bin/env bash
# ABOUTME: Pre-commit secret-scan gate. Blocks any commit that stages a high-confidence secret
# ABOUTME: token (GitHub PAT, Atlassian, OpenAI, AWS, Slack, GCP, GitLab, PEM private keys).
# ABOUTME: Runs FIRST in the pre-commit.d/ dispatcher (sorted order, prefix 10-).
# ABOUTME: Re-wired from the 2026-07-03 leak-fix (d4fa4b1) after commit 488190f silently dropped it.
# ABOUTME: Fail-closed: missing scanner BLOCKS commit (a lost scanner must be loud, not silent).

set -uo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || echo "$HOME/.claude")"
SCANNER="${REPO_ROOT}/scripts/secret-scan.sh"

if [[ ! -x "$SCANNER" ]]; then
  echo "pre-commit.d/10-secret-scan.sh: FATAL — secret-scan.sh not found at $SCANNER" >&2
  echo "  This scanner is a security backstop. Its absence blocks commits (fail-closed)." >&2
  echo "  Restore scripts/secret-scan.sh and chmod +x, then re-commit." >&2
  exit 1
fi

# Run scanner in pre-commit mode (no args = staged-content scan).
# exit 0 = clean; exit 1 = secret detected; any other nonzero = scanner error (block, fail-closed).
if ! "$SCANNER"; then
  exit 1
fi

exit 0
