#!/usr/bin/env bash
# ABOUTME: Complete spec infrastructure setup for a single repo/worktree.
# ABOUTME: Adds frontmatter to all .md files, rebuilds spec registry,
# ABOUTME: stages everything, and commits. Idempotent and safe to re-run.
# ABOUTME: Usage: process-repo-specs.sh [path-to-repo]
# ABOUTME: If no path given, uses current directory.

set -euo pipefail

REPO_PATH="${1:-.}"
cd "$REPO_PATH"

# Verify we're in a git repo
if ! git rev-parse --is-inside-work-tree &>/dev/null; then
  echo "SKIP: $REPO_PATH is not a git repo" >&2
  exit 0
fi

REPO_NAME=$(basename "$(git rev-parse --show-toplevel 2>/dev/null || echo "$REPO_PATH")")
BRANCH=$(git branch --show-current 2>/dev/null || echo "detached")
echo "=== Processing: $REPO_PATH (branch: $BRANCH) ==="

# Step 1: Add frontmatter to all .md files without it
"$HOME/.claude/scripts/add-spec-frontmatter.sh"

# Step 2: Rebuild the spec registry
"$HOME/.claude/scripts/rebuild-spec-registry.sh"

# Step 3: Stage all modified .md files and the registry
# Only stage .md files that were modified (frontmatter added)
git diff --name-only -z -- '*.md' | xargs -0 -r git add
# Also stage any untracked .md files that might have been missed
git ls-files --others --exclude-standard -z -- '*.md' | head -z -n 20 | xargs -0 -r git add
# Registry is already staged by rebuild script
git add docs/spec-registry.yaml 2>/dev/null || true

# Step 4: Commit if there are staged changes
if ! git diff --cached --quiet; then
  git commit -m "$(cat <<'EOF'
chore: add spec frontmatter and rebuild spec registry

- Added YAML frontmatter (domain, skills, schemas) to all .md spec files
- Generated docs/spec-registry.yaml indexing all specs in the repo
- Infrastructure for orchestrator spec context injection

Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>
EOF
)"
  echo "DONE: Committed spec infrastructure for $REPO_PATH"
else
  echo "DONE: No changes needed for $REPO_PATH"
fi
