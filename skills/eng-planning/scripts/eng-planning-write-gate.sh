#!/bin/bash
# ABOUTME: PreToolUse hook for Write tool — validates design doc structure on write.
# Purpose: When eng-planning is active and writing a FEAT design doc, validate structural compliance.
# Usage: Configured as PreToolUse hook on "Write" in settings.json. Receives tool input JSON on stdin.
# Gotchas: Allows scaffold copies (which have TODO markers). Blocks non-compliant rewrites.

# Fast bail-out: no progress.json means eng-planning is not active
PROGRESS="docs/.eng-planning/progress.json"
if [ ! -f "$PROGRESS" ]; then
  exit 0
fi

# Read the Write tool input from stdin
INPUT=$(cat)

# Extract file_path from the tool input
FILE_PATH=$(echo "$INPUT" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    if 'file_path' in data:
        print(data['file_path'])
    elif 'tool_input' in data and 'file_path' in data['tool_input']:
        print(data['tool_input']['file_path'])
    else:
        print('')
except:
    print('')
" 2>/dev/null)

# If we couldn't parse or path is empty, allow
if [ -z "$FILE_PATH" ]; then
  exit 0
fi

# Only validate FEAT design doc writes
if ! echo "$FILE_PATH" | grep -qE 'docs/plans/FEAT-.*-design\.md$'; then
  exit 0
fi

# Extract content from the tool input
CONTENT=$(echo "$INPUT" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    if 'content' in data:
        print(data['content'])
    elif 'tool_input' in data and 'content' in data['tool_input']:
        print(data['tool_input']['content'])
    else:
        print('')
except:
    print('')
" 2>/dev/null)

if [ -z "$CONTENT" ]; then
  exit 0
fi

# --- Scaffold detection ---
# If the content has TODO markers AND all required headers, this is the initial
# scaffold copy — allow it through. The subagent will fill it via Edit calls.
TODO_COUNT=$(echo "$CONTENT" | grep -c 'TODO: Fill' 2>/dev/null || true)
if [ "$TODO_COUNT" -gt 5 ]; then
  # This looks like the scaffold template being copied — allow it
  exit 0
fi

# --- Structural validation on filled content ---
ERRORS=()

check_section() {
  local pattern="$1"
  local name="$2"
  if ! echo "$CONTENT" | grep -qE "$pattern"; then
    ERRORS+=("MISSING: $name")
  fi
}

check_section "^## Objective" "## Objective"
check_section "^## Requirements" "## Requirements"
check_section "^### P0" "### P0 (Must Have)"
check_section "^## Architecture" "## Architecture"
check_section "^### System Overview" "### System Overview"
check_section "^### Error Handling" "### Error Handling Strategy"
check_section "^## Interfaces" "## Interfaces"
check_section "^## Jira Stories" "## Jira Stories"
check_section "^## Execution DAG" "## Execution DAG"
check_section "^### Concurrency Batches" "### Concurrency Batches"
check_section "^### File Conflict Matrix" "### File Conflict Matrix"
check_section "^## Codepath Coverage" "## Codepath Coverage Diagram"
check_section "^## Failure Modes" "## Failure Modes"
check_section "^## Definition of Done" "## Definition of Done"

# Story naming: must have S-XXX stories, not T-XXX at top level
if echo "$CONTENT" | grep -qE '^### T-[0-9]'; then
  ERRORS+=("NAMING: Stories use T-XXX instead of S-XXX at top level")
fi
if ! echo "$CONTENT" | grep -qE '^### S-'; then
  ERRORS+=("NAMING: No S-XXX stories found")
fi

# Required table columns
if ! echo "$CONTENT" | grep -q "Jira Story"; then
  ERRORS+=("TABLE: Missing 'Jira Story' column in requirements")
fi
if ! echo "$CONTENT" | grep -q "Can Run In Parallel"; then
  ERRORS+=("TABLE: Missing 'Can Run In Parallel' in Concurrency Batches")
fi
if ! echo "$CONTENT" | grep -q "Conflicts With"; then
  ERRORS+=("TABLE: Missing 'Conflicts With' in File Conflict Matrix")
fi

# Failure modes columns
if echo "$CONTENT" | grep -q "Failure Modes"; then
  if ! echo "$CONTENT" | grep -q "Silent?"; then
    ERRORS+=("TABLE: Failure Modes missing 'Silent?' column")
  fi
fi

if [ ${#ERRORS[@]} -eq 0 ]; then
  exit 0
else
  echo "ENG-PLANNING WRITE GATE: Design doc structural validation FAILED."
  echo ""
  echo "The content being written to $FILE_PATH is missing required structure:"
  echo ""
  for err in "${ERRORS[@]}"; do
    echo "  $err"
  done
  echo ""
  echo "Reference: ~/.claude/skills/eng-planning/templates/design-doc-scaffold.md"
  echo "You should copy the scaffold first, then fill sections. Or ensure your"
  echo "subagent prompt includes the design-doc-template.md structure."
  exit 2
fi
