#!/bin/bash
# ABOUTME: PreToolUse hook for Write tool — validates PRD structure when writing final artifact.
# Purpose: When prd-writer is active and writing a PRD, validate structural compliance.
# Usage: Configured as PreToolUse hook on "Write" in settings.json. Receives tool input JSON on stdin.
# Gotchas: Allows scaffold copies (which have TODO markers). Blocks non-compliant final PRDs.

# Fast bail-out: no gate directory means prd-writer is not active
GATE_DIR="docs/.prd-writer"
if [ ! -d "$GATE_DIR" ]; then
  exit 0
fi

# Only enforce when the draft sentinel is active (Step 4)
if [ ! -f "$GATE_DIR/.gate-prd-draft" ]; then
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

# Only validate PRD writes (docs/ directory, PRD-like names)
if ! echo "$FILE_PATH" | grep -qE '(prd|PRD).*\.md$|docs/.*\.md$'; then
  exit 0
fi

# Skip checkpoint files (interview, context, research)
if echo "$FILE_PATH" | grep -qE '(-context|-interview|-research)\.md$'; then
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
# If the content has many TODO markers, this is the initial scaffold copy — allow it
TODO_COUNT=$(echo "$CONTENT" | grep -c 'TODO: Fill' 2>/dev/null || true)
if [ "$TODO_COUNT" -gt 5 ]; then
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

# Core required sections (all modes)
check_section "^# 1\. Problem Definition|^## Objective" "Problem Definition / Objective"
check_section "^# 2\. Jobs to Be Done|^## JTBD-" "Jobs to Be Done & Requirements"
check_section "TL;DR:" "TL;DR line"

# Check for REQ-IDs
REQ_COUNT=$(echo "$CONTENT" | grep -cE '\*\*REQ-[0-9]+:' 2>/dev/null || true)
if [ "$REQ_COUNT" -eq 0 ]; then
  ERRORS+=("REQ-IDS: No requirements with **REQ-XXX:** format found")
fi

# Check for JTBD Evidence
if echo "$CONTENT" | grep -qE '^## JTBD-'; then
  EVIDENCE_COUNT=$(echo "$CONTENT" | grep -c '\*\*Evidence:\*\*' 2>/dev/null || true)
  JTBD_COUNT=$(echo "$CONTENT" | grep -c '^## JTBD-' 2>/dev/null || true)
  if [ "$EVIDENCE_COUNT" -lt "$JTBD_COUNT" ]; then
    ERRORS+=("JTBD: $JTBD_COUNT JTBDs but only $EVIDENCE_COUNT have **Evidence:** sections")
  fi
fi

# Check for banned "Open Questions" section
if echo "$CONTENT" | grep -qi "^## Open Questions\|^### Open Questions"; then
  ERRORS+=("BANNED: 'Open Questions' section — use inline [Data gap: ...] markers")
fi

# P0 acceptance criteria check
P0_REQS=$(echo "$CONTENT" | grep -n '\*\*REQ-[0-9]*:.*\*\* *(P0)' 2>/dev/null || true)
if [ -n "$P0_REQS" ]; then
  P0_COUNT=$(echo "$P0_REQS" | wc -l | tr -d ' ')
  # Rough check: should have at least 2x numbered items per P0 req
  NUMBERED_ITEMS=$(echo "$CONTENT" | grep -c '^[0-9]\+\.' 2>/dev/null || true)
  EXPECTED=$((P0_COUNT * 2))
  if [ "$NUMBERED_ITEMS" -lt "$EXPECTED" ]; then
    ERRORS+=("ACCEPTANCE CRITERIA: $P0_COUNT P0 requirements but only $NUMBERED_ITEMS numbered acceptance criteria (need ≥$EXPECTED)")
  fi
fi

if [ ${#ERRORS[@]} -eq 0 ]; then
  exit 0
else
  echo "PRD-WRITER WRITE GATE: PRD structural validation FAILED."
  echo ""
  echo "The PRD being written to $FILE_PATH is missing required structure:"
  echo ""
  for err in "${ERRORS[@]}"; do
    echo "  ✗ $err"
  done
  echo ""
  echo "Fix these issues before writing the PRD."
  echo "Template: ~/.claude/skills/prd-writer/templates/acme-prd-template.md"
  echo "Scaffold: ~/.claude/skills/prd-writer/templates/prd-scaffold.md"
  exit 2
fi
