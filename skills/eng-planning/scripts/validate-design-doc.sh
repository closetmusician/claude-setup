#!/bin/bash
# ABOUTME: Structural validation script for eng-planning design doc artifacts.
# Purpose: Verify a FEAT-*-design.md has all required sections from design-doc-template.md.
# Usage: validate-design-doc.sh <path-to-design-doc>
# Gotchas: Exits 1 on any missing section. Checks headers, naming, tables, TODO markers.

set -euo pipefail

DOC="${1:?Usage: validate-design-doc.sh <path-to-design-doc>}"

if [ ! -f "$DOC" ]; then
  echo "FAIL: File not found: $DOC"
  exit 1
fi

ERRORS=()

# --- Required section headers ---
# Each entry: "grep pattern|human-readable name"
REQUIRED_SECTIONS=(
  "^## Objective|## Objective"
  "^## Requirements|## Requirements"
  "^### P0|### P0 (Must Have)"
  "^### P1|### P1 (Should Have)"
  "^### P2|### P2 (Nice to Have)"
  "^### Non-Goals|### Non-Goals"
  "^## Architecture|## Architecture"
  "^### System Overview|### System Overview"
  "^### Data Flow|### Data Flow"
  "^### Error Handling|### Error Handling Strategy"
  "^## Interfaces|## Interfaces"
  "^### New Dependencies|### New Dependencies (R17)"
  "^## Jira Stories|## Jira Stories"
  "^## Execution DAG|## Execution DAG"
  "^### Concurrency Batches|### Concurrency Batches"
  "^### File Conflict Matrix|### File Conflict Matrix"
  "^## Codepath Coverage|## Codepath Coverage Diagram"
  "^## Failure Modes|## Failure Modes"
  "^## Definition of Done|## Definition of Done"
)

for entry in "${REQUIRED_SECTIONS[@]}"; do
  pattern="${entry%%|*}"
  name="${entry##*|}"
  if ! grep -qE "$pattern" "$DOC"; then
    ERRORS+=("MISSING SECTION: $name")
  fi
done

# --- Story naming convention ---
# Top-level stories MUST use S-XXX, not T-XXX
# Look for "### T-" which indicates T-XXX used at story level (wrong)
if grep -qE '^### T-[0-9]' "$DOC"; then
  ERRORS+=("NAMING: Top-level stories use T-XXX instead of S-XXX. Stories must be ### S-XXX")
fi

# Must have at least one S-XXX story
if ! grep -qE '^### S-' "$DOC"; then
  ERRORS+=("NAMING: No S-XXX stories found. Design doc must have at least one ### S-XXX story")
fi

# --- Required table columns ---
# Requirements tables must have Jira Story and Tasks columns
if ! grep -q "Jira Story" "$DOC"; then
  ERRORS+=("TABLE: Requirements tables missing 'Jira Story' column")
fi
if ! grep -qE "\| Tasks" "$DOC"; then
  ERRORS+=("TABLE: Requirements tables missing 'Tasks' column")
fi

# Concurrency Batches table must have "Can Run In Parallel" column
if grep -q "Concurrency Batches" "$DOC" && ! grep -q "Can Run In Parallel" "$DOC"; then
  ERRORS+=("TABLE: Concurrency Batches missing 'Can Run In Parallel' column")
fi

# File Conflict Matrix must have "Conflicts With" column
if grep -q "File Conflict Matrix" "$DOC" && ! grep -q "Conflicts With" "$DOC"; then
  ERRORS+=("TABLE: File Conflict Matrix missing 'Conflicts With' column")
fi

# Failure Modes table must have correct columns
if grep -q "Failure Modes" "$DOC"; then
  if ! grep -q "Tests Cover It" "$DOC"; then
    ERRORS+=("TABLE: Failure Modes missing 'Tests Cover It?' column")
  fi
  if ! grep -q "Silent?" "$DOC"; then
    ERRORS+=("TABLE: Failure Modes missing 'Silent?' column")
  fi
fi

# --- Required story fields ---
# Check that at least one story has the required fields
if grep -qE '^### S-' "$DOC"; then
  for field in "Layers:" "Depends On:" "Spec Reference:" "Objective:" "Context:" "Build Guidance:" "Acceptance Criteria:" "Slice Done Gate:"; do
    if ! grep -q "$field" "$DOC"; then
      ERRORS+=("STORY FIELD: Missing '$field' in story mini-specs")
    fi
  done
fi

# --- TODO markers (should be zero in final output) ---
TODO_COUNT=$(grep -c 'TODO: Fill' "$DOC" 2>/dev/null || true)
if [ "$TODO_COUNT" -gt 0 ]; then
  ERRORS+=("UNFILLED: $TODO_COUNT TODO markers remain — sections not filled by subagent")
  # List which sections still have TODOs
  grep -n 'TODO: Fill' "$DOC" | while IFS= read -r line; do
    ERRORS+=("  $line")
  done
fi

# --- Report ---
if [ ${#ERRORS[@]} -eq 0 ]; then
  echo "PASS: All required sections, naming conventions, and table structures verified."
  exit 0
else
  echo "FAIL: ${#ERRORS[@]} structural issues found in $DOC"
  echo ""
  for err in "${ERRORS[@]}"; do
    echo "  $err"
  done
  echo ""
  echo "Template reference: ~/.claude/skills/eng-planning/templates/design-doc-template.md"
  echo "Scaffold reference: ~/.claude/skills/eng-planning/templates/design-doc-scaffold.md"
  exit 1
fi
