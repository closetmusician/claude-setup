#!/bin/bash
# ABOUTME: Structural validation script for prd-writer PRD artifacts.
# Purpose: Verify a PRD has all required sections, REQ-ID format, acceptance criteria minimums,
#          End-User POV compliance, and density rule compliance.
# Usage: validate-prd.sh <path-to-prd> [--mode full|lite]
# Gotchas: Exits 1 on structural failures. Mode defaults to "full" (12 sections).

set -euo pipefail

DOC="${1:?Usage: validate-prd.sh <path-to-prd> [--mode full|lite]}"
MODE="${2:---mode}"
MODE_VAL="${3:-full}"

# Handle --mode flag
if [ "$MODE" = "--mode" ]; then
  MODE_VAL="${MODE_VAL}"
else
  MODE_VAL="full"
fi

if [ ! -f "$DOC" ]; then
  echo "FAIL: File not found: $DOC"
  exit 1
fi

ERRORS=()
WARNINGS=()

# --- Required section headers (Mode A: Full PRD) ---
REQUIRED_FULL=(
  "^# 1\. Problem Definition|# 1. Problem Definition"
  "^## Objective|## Objective"
  "^## Context|## Context & Strategic Drivers"
  "^## Opportunity Size|## Opportunity Size"
  "^## Success Measures|## Success Measures"
  "^# 2\. Jobs to Be Done|# 2. Jobs to Be Done & Requirements"
  "^## JTBD-|## JTBD (at least one)"
  "^# 3\. UX Flows|# 3. UX Flows"
  "^# 4\. Risks|# 4. Risks & Out of Scope"
  "^# 7\. Engineering|# 7. Engineering"
)

# Sections required only in full mode
FULL_ONLY=(
  "^# 5\. Legacy|# 5. Legacy Reference"
  "^# 6\. RACI|# 6. RACI"
  "^# 8\. Other Dependencies|# 8. Other Dependencies"
  "^# 9\. Release Plan|# 9. Release Plan"
)

for entry in "${REQUIRED_FULL[@]}"; do
  pattern="${entry%%|*}"
  name="${entry##*|}"
  if ! grep -qE "$pattern" "$DOC"; then
    ERRORS+=("MISSING SECTION: $name")
  fi
done

if [ "$MODE_VAL" = "full" ]; then
  for entry in "${FULL_ONLY[@]}"; do
    pattern="${entry%%|*}"
    name="${entry##*|}"
    # These may legitimately have "(if applicable)" — check they exist even as stubs
    if ! grep -qE "$pattern" "$DOC"; then
      WARNINGS+=("OPTIONAL SECTION NOT PRESENT: $name (expected in full mode)")
    fi
  done
fi

# --- REQ-ID format validation ---
# Requirements must use 2-3 letter prefix + number format
REQ_COUNT=$(grep -cE '\*\*REQ-[0-9]+:' "$DOC" 2>/dev/null || true)
if [ "$REQ_COUNT" -eq 0 ]; then
  ERRORS+=("REQ-IDS: No requirements found with **REQ-XXX:** format. PRD must have at least one requirement.")
fi

# --- Acceptance criteria minimum (P0 requirements need ≥2) ---
# Find P0 requirements and check they have numbered acceptance criteria
P0_REQS=$(grep -n '\*\*REQ-[0-9]*:.*\*\* *(P0)' "$DOC" 2>/dev/null || true)
if [ -n "$P0_REQS" ]; then
  while IFS= read -r line; do
    LINE_NUM="${line%%:*}"
    REQ_NAME=$(echo "$line" | grep -oE 'REQ-[0-9]+' | head -1)
    # Count numbered items (acceptance criteria) in the 10 lines after the REQ header
    AC_COUNT=$(sed -n "$((LINE_NUM+1)),$((LINE_NUM+12))p" "$DOC" | grep -cE '^[0-9]+\.' 2>/dev/null || true)
    if [ "$AC_COUNT" -lt 2 ]; then
      ERRORS+=("ACCEPTANCE CRITERIA: $REQ_NAME (P0) has $AC_COUNT acceptance criteria — minimum is 2")
    fi
  done <<< "$P0_REQS"
fi

# --- JTBD format validation ---
# Each JTBD should have Evidence and Hypothesis
JTBD_HEADERS=$(grep -c '^## JTBD-' "$DOC" 2>/dev/null || true)
EVIDENCE_COUNT=$(grep -c '\*\*Evidence:\*\*' "$DOC" 2>/dev/null || true)
HYPOTHESIS_COUNT=$(grep -ci '\*Hypothesis:\*\|hypothesis:' "$DOC" 2>/dev/null || true)

if [ "$JTBD_HEADERS" -gt 0 ]; then
  if [ "$EVIDENCE_COUNT" -lt "$JTBD_HEADERS" ]; then
    ERRORS+=("JTBD: Found $JTBD_HEADERS JTBDs but only $EVIDENCE_COUNT have **Evidence:** sections")
  fi
  if [ "$HYPOTHESIS_COUNT" -lt "$JTBD_HEADERS" ]; then
    WARNINGS+=("JTBD: Found $JTBD_HEADERS JTBDs but only $HYPOTHESIS_COUNT have Hypothesis sections")
  fi
fi

# --- End-User POV enforcement (§1-6 must be user-facing) ---
# Check for implementation detail leaks in sections 1-6
# Get content of sections 1-6 (before # 7. Engineering)
SECTIONS_1_6=$(sed -n '1,/^# 7\. Engineering/p' "$DOC" 2>/dev/null || cat "$DOC")

# Technical terms that should NOT appear in §1-6
TECH_VIOLATIONS=()
for term in "BFF" "middleware" "microservice" "REST API" "GraphQL" "WebSocket" "SSE" "gRPC" "database schema" "SQL" "ORM" "Redis" "Kafka" "regex" "JSON schema" "protobuf"; do
  if echo "$SECTIONS_1_6" | grep -qi "$term"; then
    # Skip if it's in a code block or the Engineering section leaked into our sed
    TECH_VIOLATIONS+=("$term")
  fi
done

if [ ${#TECH_VIOLATIONS[@]} -gt 0 ]; then
  WARNINGS+=("END-USER POV: Sections 1-6 contain implementation terms: ${TECH_VIOLATIONS[*]}. These should only appear in §7 Engineering or TAR.")
fi

# --- Requirement formatting rules ---
# Check for >5 numbered items under any requirement area header
# Find all REQ headers and count numbered items between them
REQ_HEADERS=$(grep -n '^\*\*[A-Z]\{2,3\}-[0-9a-z]*:' "$DOC" 2>/dev/null || true)
if [ -n "$REQ_HEADERS" ]; then
  PREV_LINE=0
  PREV_NAME=""
  while IFS= read -r line; do
    LINE_NUM="${line%%:*}"
    REQ_NAME=$(echo "$line" | grep -oE '[A-Z]{2,3}-[0-9a-z]+' | head -1)
    if [ "$PREV_LINE" -gt 0 ]; then
      # Count numbered items between previous REQ header and this one
      ITEM_COUNT=$(sed -n "$((PREV_LINE+1)),$((LINE_NUM-1))p" "$DOC" | grep -cE '^[0-9]+\.' 2>/dev/null || true)
      if [ "$ITEM_COUNT" -gt 5 ]; then
        ERRORS+=("REQ FORMAT: $PREV_NAME has $ITEM_COUNT numbered items — max 5. Decompose into sub-areas (e.g., ${PREV_NAME}a, ${PREV_NAME}b).")
      fi
    fi
    PREV_LINE="$LINE_NUM"
    PREV_NAME="$REQ_NAME"
  done <<< "$REQ_HEADERS"
  # Check last REQ header to end of next section or EOF
  if [ "$PREV_LINE" -gt 0 ]; then
    NEXT_SECTION=$(tail -n +"$((PREV_LINE+1))" "$DOC" | grep -n '^\*\*[A-Z]\{2,3\}-[0-9a-z]*:\|^## \|^# ' | head -1 | cut -d: -f1)
    if [ -n "$NEXT_SECTION" ]; then
      END_LINE=$((PREV_LINE + NEXT_SECTION - 1))
    else
      END_LINE=$(wc -l < "$DOC")
    fi
    ITEM_COUNT=$(sed -n "$((PREV_LINE+1)),${END_LINE}p" "$DOC" | grep -cE '^[0-9]+\.' 2>/dev/null || true)
    if [ "$ITEM_COUNT" -gt 5 ]; then
      ERRORS+=("REQ FORMAT: $PREV_NAME has $ITEM_COUNT numbered items — max 5. Decompose into sub-areas (e.g., ${PREV_NAME}a, ${PREV_NAME}b).")
    fi
  fi
fi

# Check for per-item priority tags [P0]/[P1]/[P2]
NUMBERED_ITEMS=$(grep -cE '^[0-9]+\.' "$DOC" 2>/dev/null || true)
TAGGED_ITEMS=$(grep -cE '^[0-9]+\. \[P[012]\]' "$DOC" 2>/dev/null || true)
if [ "$NUMBERED_ITEMS" -gt 0 ] && [ "$TAGGED_ITEMS" -eq 0 ]; then
  WARNINGS+=("REQ FORMAT: No numbered items have [P0]/[P1]/[P2] priority tags. Every acceptance criterion should start with a priority tag.")
elif [ "$NUMBERED_ITEMS" -gt 0 ] && [ "$TAGGED_ITEMS" -lt "$NUMBERED_ITEMS" ]; then
  MISSING=$((NUMBERED_ITEMS - TAGGED_ITEMS))
  WARNINGS+=("REQ FORMAT: $MISSING of $NUMBERED_ITEMS numbered items missing [P0]/[P1]/[P2] priority tags.")
fi

# --- Density rules ---
# Check for "Open Questions" section (banned)
if grep -qi "^## Open Questions\|^### Open Questions" "$DOC"; then
  ERRORS+=("DENSITY: 'Open Questions' section found — this is banned. Use inline [Data gap: recommend X research] markers instead.")
fi

# --- TL;DR presence ---
if ! grep -q "TL;DR:" "$DOC"; then
  ERRORS+=("MISSING: TL;DR line at document top")
fi

# --- Success Measures table ---
if grep -q "Success Measures" "$DOC"; then
  if ! grep -q "Target\|Guardrail" "$DOC"; then
    WARNINGS+=("TABLE: Success Measures section exists but may be missing Target/Guardrail rows")
  fi
fi

# --- TODO markers (should be zero in final output) ---
TODO_COUNT=$(grep -c 'TODO: Fill' "$DOC" 2>/dev/null || true)
if [ "$TODO_COUNT" -gt 0 ]; then
  ERRORS+=("UNFILLED: $TODO_COUNT TODO markers remain — sections not completed")
  grep -n 'TODO: Fill' "$DOC" | head -10 | while IFS= read -r line; do
    ERRORS+=("  $line")
  done
fi

# --- UX Flows: wireframes check (full mode) ---
if [ "$MODE_VAL" = "full" ]; then
  WIREFRAME_COUNT=$(grep -c 'ASCII Wireframe\|┌\|┐\|└\|┘' "$DOC" 2>/dev/null || true)
  if [ "$WIREFRAME_COUNT" -lt 3 ]; then
    WARNINGS+=("UX FLOWS: Expected 3-5 ASCII wireframes for a feature PRD, found ~$WIREFRAME_COUNT references")
  fi
fi

# --- Report ---
echo "=== PRD Validation Report: $DOC (mode: $MODE_VAL) ==="
echo ""

if [ ${#ERRORS[@]} -eq 0 ] && [ ${#WARNINGS[@]} -eq 0 ]; then
  echo "PASS: All required sections, formats, and rules verified."
  exit 0
fi

if [ ${#ERRORS[@]} -gt 0 ]; then
  echo "ERRORS (${#ERRORS[@]} — must fix):"
  for err in "${ERRORS[@]}"; do
    echo "  ✗ $err"
  done
  echo ""
fi

if [ ${#WARNINGS[@]} -gt 0 ]; then
  echo "WARNINGS (${#WARNINGS[@]} — review recommended):"
  for warn in "${WARNINGS[@]}"; do
    echo "  ⚠ $warn"
  done
  echo ""
fi

echo "Template reference: ~/.claude/skills/prd-writer/templates/acme-prd-template.md"
echo "Scaffold reference: ~/.claude/skills/prd-writer/templates/prd-scaffold.md"

if [ ${#ERRORS[@]} -gt 0 ]; then
  exit 1
else
  exit 0
fi
