#!/usr/bin/env bash
# ABOUTME: Adds YAML frontmatter to all .md files in a repo that lack it.
# ABOUTME: Derives domain from filename (strips date prefix, suffixes).
# ABOUTME: Sets skills: [] and schemas: [] (domain-only mode).
# ABOUTME: Skips README, CHANGELOG, CLAUDE.md, and files in .git/.claude.
# ABOUTME: Run from the project root. Idempotent — skips files with frontmatter.

set -euo pipefail

count=0
skipped=0

# Find all .md files, excluding known non-spec patterns
while IFS= read -r -d '' filepath; do
  filepath="${filepath#./}"
  basename_lower=$(basename "$filepath" | tr '[:upper:]' '[:lower:]')

  # Skip known non-spec files
  case "$basename_lower" in
    readme.md|changelog.md|contributing.md|license.md|code_of_conduct.md) continue ;;
    claude.md|memory.md|spec-registry.yaml) continue ;;
  esac

  # Skip files that already have frontmatter
  first_line=$(head -1 "$filepath" 2>/dev/null || echo "")
  if [ "$first_line" = "---" ]; then
    skipped=$((skipped + 1))
    continue
  fi

  # Derive domain from filename
  basename_no_ext=$(basename "$filepath" .md)
  domain=$(echo "$basename_no_ext" | sed -E 's/^[0-9]{4}-[0-9]{2}-[0-9]{2}-//')
  domain=$(echo "$domain" | sed -E 's/-(design|implementation)$//')
  domain=$(echo "$domain" | tr '[:upper:]' '[:lower:]' | tr '_' '-')

  # Prepend frontmatter using temp file
  tmpfile=$(mktemp)
  cat > "$tmpfile" << EOF
---
domain: ${domain}
skills: []
schemas: []
---

EOF
  cat "$filepath" >> "$tmpfile"
  mv "$tmpfile" "$filepath"
  count=$((count + 1))

done < <(find . -name "*.md" -type f \
  -not -path "./.git/*" \
  -not -path "./.claude/*" \
  -not -path "./node_modules/*" \
  -not -path "./.venv*/*" \
  -not -path "./venv/*" \
  -not -path "./__pycache__/*" \
  -not -path "./.worktrees/*" \
  -not -path "*/.claude/worktrees/*" \
  -not -path "*/node_modules/*" \
  -print0 | sort -z)

echo "Frontmatter added to $count files ($skipped already had frontmatter)."
