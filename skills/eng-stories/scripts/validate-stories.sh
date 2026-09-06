#!/usr/bin/env bash
# ABOUTME: Validates FEAT-*-stories.md files for structural compliance and specificity retention.
# ABOUTME: Modes: --size team|large selects the required per-story field set (team = compact
# ABOUTME: sprint-board stories; large = full mini-spec). --inventory <dir> adds the specificity
# ABOUTME: diff: number+unit tokens from behaviors-*.md must survive into the stories doc.
# ABOUTME: Exit 0 = PASS, 1 = structural FAIL, 2 = specificity values need disposition.
# ABOUTME: Usage: validate-stories.sh <stories.md> [--size team|large] [--inventory <dir>]

set -euo pipefail

FILE=""
SIZE="large"
INVENTORY=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --size) SIZE="${2:-large}"; shift 2 ;;
    --inventory) INVENTORY="${2:-}"; shift 2 ;;
    -*) echo "Unknown flag: $1"; echo "Usage: validate-stories.sh <stories.md> [--size team|large] [--inventory <dir>]"; exit 1 ;;
    *) FILE="$1"; shift ;;
  esac
done

if [[ -z "$FILE" ]]; then
  echo "Usage: validate-stories.sh <stories.md> [--size team|large] [--inventory <dir>]"
  exit 1
fi
if [[ ! -f "$FILE" ]]; then
  echo "FAIL: File not found: $FILE"
  exit 1
fi
if [[ "$SIZE" != "team" && "$SIZE" != "large" ]]; then
  echo "FAIL: --size must be 'team' or 'large' (got: $SIZE)"
  exit 1
fi

# Purpose: count regex matches without the double-zero bug.
# Gotcha: `grep -c` prints "0" AND exits 1 on no match, so `|| echo 0` appends a second
# zero ("0\n0") and breaks arithmetic comparisons. `|| true` keeps grep's own "0".
count_matches() {
  grep -cE "$1" "$2" || true
}

ERRORS=()

# --- Required Section Headers ---
REQUIRED_SECTIONS=(
  "^## Objective|Objective"
  "^## Story Index|Story Index"
  "^## Requirements|Requirements"
  "^### P0|P0 (Must Have)"
  "^### Non-Goals|Non-Goals"
  "^## Jira Stories|Jira Stories"
  "^## Execution DAG|Execution DAG"
  "^### Dependency Order|Dependency Order"
  "^### File Conflict Matrix|File Conflict Matrix"
  "^## Behavioral Coverage Summary|Behavioral Coverage Summary"
  "^## Definition of Done|Definition of Done"
)
# Team-size docs hoist shared sections to feature level — require them once per doc.
if [[ "$SIZE" == "team" ]]; then
  REQUIRED_SECTIONS+=("^## Roles & Permissions|Roles & Permissions (feature-level)")
fi

for entry in "${REQUIRED_SECTIONS[@]}"; do
  pattern="${entry%%|*}"
  name="${entry##*|}"
  if ! grep -qE "$pattern" "$FILE"; then
    ERRORS+=("Missing required section: $name")
  fi
done

# --- Story Naming Convention ---
if grep -qE "^### T-[A-Z0-9]" "$FILE"; then
  ERRORS+=("Story naming violation: found T-XXX at top level (should be S-XXX)")
fi
if ! grep -qE "^### S-" "$FILE"; then
  ERRORS+=("No stories found: expected at least one ### S-XXX section")
fi

# --- Story Title Jargon Heuristic (ban extends to titles + ID mnemonics) ---
JARGON_TERMS='(CRUD|API|endpoint|SignalR|controller|middleware|schema|DTO|enum|backend|frontend|microservice|refactor|DB migration)'
if grep -E "^### S-" "$FILE" | grep -qiE "$JARGON_TERMS"; then
  ERRORS+=("Story title jargon (titles/IDs are PM-facing too — rename from the user's domain):")
  while IFS= read -r line; do
    ERRORS+=("  $line")
  done < <(grep -nE "^### S-" "$FILE" | grep -iE "$JARGON_TERMS" || true)
fi

# --- Required Story Fields (per size mode) ---
if [[ "$SIZE" == "team" ]]; then
  STORY_FIELDS=(
    "User Story:"
    "Acceptance Criteria:"
    "Slice Done Gate:"
  )
else
  STORY_FIELDS=(
    "Depends On:"
    "Spec Reference:"
    "User Story:"
    "Business Value:"
    "Objective:"
    "Context:"
    "Roles & Permissions:"
    "Preconditions:"
    "Workflow:"
    "Acceptance Criteria:"
    "Slice Done Gate:"
  )
fi

for field in "${STORY_FIELDS[@]}"; do
  if ! grep -q "$field" "$FILE"; then
    ERRORS+=("Missing story field across all stories: $field")
  fi
done

# --- Story Index Table ---
if grep -qE "^## Story Index" "$FILE"; then
  if ! grep -q "Story ID" "$FILE"; then
    ERRORS+=("Story Index table missing 'Story ID' column")
  fi
  if ! grep -qiE "\| *Estimate" "$FILE"; then
    ERRORS+=("Story Index table missing 'Estimate' column (XS-XL; >M must be split)")
  fi
fi

# --- Oversized Stories (>M must split) ---
if grep -qE '^\|[^|]*S-[A-Z0-9-]+[^|]*\|[^|]*\|[^|]*\|[[:space:]]*(L|XL)[[:space:]]*\|' "$FILE"; then
  ERRORS+=("Oversized story in Story Index (estimate L/XL — must be split before traceability):")
  while IFS= read -r line; do
    ERRORS+=("  $line")
  done < <(grep -nE '^\|[^|]*S-[A-Z0-9-]+[^|]*\|[^|]*\|[^|]*\|[[:space:]]*(L|XL)[[:space:]]*\|' "$FILE" || true)
fi

# --- Required Table Columns ---
if grep -qE "^### P0" "$FILE"; then
  if ! grep -q "Jira Story" "$FILE"; then
    ERRORS+=("Requirements table missing 'Jira Story' column")
  fi
  if ! grep -qE "\| Tasks" "$FILE"; then
    ERRORS+=("Requirements table missing 'Tasks' column")
  fi
fi
if grep -qE "^### File Conflict Matrix" "$FILE"; then
  if ! grep -q "Conflicts With" "$FILE"; then
    ERRORS+=("File Conflict Matrix missing 'Conflicts With' column")
  fi
fi

# --- Edge Case Structure ---
if grep -qE "^\*\*EC-[0-9]" "$FILE"; then
  for ec_field in "Scenario:" "Expected Behavior:" "Rationale:"; do
    if ! grep -q "$ec_field" "$FILE"; then
      ERRORS+=("Edge cases present but missing structured '$ec_field' format")
    fi
  done
fi

# --- TODO Marker Check ---
TODO_COUNT=$(count_matches "TODO" "$FILE")
if [[ "$TODO_COUNT" -gt 0 ]]; then
  ERRORS+=("Found $TODO_COUNT unfilled TODO markers:")
  while IFS= read -r line; do
    ERRORS+=("  $line")
  done < <(grep -n "TODO" "$FILE" || true)
fi

# --- TBD Check (Requirements table backfill) ---
# Word-boundary pattern: "TBD" must not be preceded/followed by a letter, so "JTBD"
# (Jobs To Be Done) and "JTBD-3" never match. Verified: "(PRD JTBD-3)" → 0 matches.
TBD_PATTERN='(^|[^A-Za-z])TBD([^A-Za-z]|$)'
TBD_COUNT=$(count_matches "$TBD_PATTERN" "$FILE")
if [[ "$TBD_COUNT" -gt 0 ]]; then
  ERRORS+=("Found $TBD_COUNT TBD markers (requirements table backfill incomplete):")
  while IFS= read -r line; do
    ERRORS+=("  $line")
  done < <(grep -nE "$TBD_PATTERN" "$FILE" || true)
fi

# --- Jargon Spot Check (state-machine notation) ---
if grep -qE '(idle|voting|stopped|finalized)\s*->' "$FILE"; then
  ERRORS+=("Possible state-machine jargon in story artifact (check for 'X -> Y' notation — all content must be PM-facing)")
fi

# --- Specificity Retention Diff (--inventory) ---
# Purpose: catch numbers/durations/mechanisms that vaporized during the jargon-to-plain-
# English rewrite (June 2026: 5 P1 values lost; the prose rule alone failed).
# Method: extract "number + unit" tokens from behavioral inventory files; each token's
# number must appear somewhere in the stories doc (word-form allowances for 1 and 2).
# Flags are exit-2 REVIEW items, not hard failures — the agent dispositions each one.
SPEC_MISSING=()
if [[ -n "$INVENTORY" ]]; then
  UNITS='(ms|milliseconds?|seconds?|secs?|minutes?|mins?|hours?|days?|weeks?|months?|retries|retry|attempts?|times|items?|characters?|chars?|entries|records?|files?|users?|members?|levels?|stages?|steps?|versions?|percent|%|px|pixels?|KB|MB|GB)'
  INV_FILES=$(ls "$INVENTORY"/behaviors-*.md "$INVENTORY"/behavioral-inventory.md 2>/dev/null || true)
  if [[ -z "$INV_FILES" ]]; then
    echo "WARN: --inventory given but no behaviors-*.md / behavioral-inventory.md under $INVENTORY (skipping specificity diff)"
  else
    TOKENS=$(cat $INV_FILES 2>/dev/null \
      | grep -ioE "[0-9]+(\.[0-9]+)?[ -]?${UNITS}([^A-Za-z]|$)" \
      | sed -E 's/[^A-Za-z0-9.% ]+$//' | tr '[:upper:]' '[:lower:]' | sed -E 's/[ -]+/ /g' \
      | sort -u || true)
    while IFS= read -r tok; do
      [[ -z "$tok" ]] && continue
      num=$(printf '%s' "$tok" | grep -oE '^[0-9]+(\.[0-9]+)?' || true)
      [[ -z "$num" ]] && continue
      # Number present anywhere in the stories doc (digit form) → retained.
      if grep -qE "(^|[^0-9.])${num}([^0-9]|$)" "$FILE"; then continue; fi
      # Word-form allowances: "1 second" often becomes "once per second"; 2 → "twice/both".
      case "$num" in
        1) grep -qiE '(once|one |single|each |every )' "$FILE" && continue ;;
        2) grep -qiE '(twice|two |both |double|doubling)' "$FILE" && continue ;;
      esac
      SPEC_MISSING+=("$tok")
    done <<< "$TOKENS"
  fi
fi

# --- Report ---
STORY_COUNT=$(count_matches "^### S-" "$FILE")

if [[ ${#ERRORS[@]} -gt 0 ]]; then
  echo "FAIL: ${#ERRORS[@]} structural issues found in $FILE (size mode: $SIZE, $STORY_COUNT stories)"
  echo ""
  for err in "${ERRORS[@]}"; do
    echo "  - $err"
  done
  echo ""
  echo "Reference: ~/.claude/skills/eng-stories/templates/stories-template.md"
  exit 1
fi

if [[ ${#SPEC_MISSING[@]} -gt 0 ]]; then
  echo "SPECIFICITY: ${#SPEC_MISSING[@]} inventory values not found in $FILE — disposition each (restore in plain English, or record why excluded):"
  for tok in "${SPEC_MISSING[@]}"; do
    echo "  - POSSIBLY LOST: $tok"
  done
  exit 2
fi

echo "PASS: structure OK ($STORY_COUNT stories, size mode: $SIZE)${INVENTORY:+, specificity diff clean}: $FILE"
exit 0
