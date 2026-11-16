#!/usr/bin/env bash
# ABOUTME: Step 6 gate for arm D. Checks that each REQ id has a markdown table row with that exact
# ABOUTME: id in the first cell and met or not met in the second cell. REQ-05 must not match REQ-05b.
# ABOUTME: Exit 0 when all rows present, exit 1 lists every missing id or bad status, exit 2 on usage error.
set -euo pipefail

# Purpose: show usage text and exit with code 2 (usage error).
# Usage:   usage
# Gotchas: called on --help or wrong argument count.
usage() {
  cat <<'EOF'
Usage: req-rows.sh <review_file> <REQ ids, comma list>

Checks:
  Each id needs a markdown table row where:
  - First cell is exactly that id (e.g. | REQ-01 | ...)
  - Second cell is "met" or "not met"

  REQ-05 must not match REQ-05b (exact cell match required).

Exit codes:
  0 = all rows present with valid status
  1 = missing id or bad status (lists each)
  2 = usage error

Output:
  Success: "ALL ROWS PRESENT (N)"
  Failure: lists each missing id or bad status
EOF
  exit 2
}

[[ $# -eq 2 ]] || usage
[[ "${1:-}" == "--help" ]] && usage

REVIEW_FILE="$1"
REQ_IDS="$2"

# Purpose: split comma-separated list into array.
# Usage:   IFS=',' read -ra ids <<< "$REQ_IDS"
# Gotchas: bash array, spaces around commas are preserved.
IFS=',' read -ra ids <<< "$REQ_IDS"

missing=()

# Purpose: check if a REQ id has a valid table row in the review file.
# Usage:   for each id, look for a line starting with | <id> | and check the status cell.
# Gotchas: exact match in first cell, status must be "met" or "not met" in second cell.
for id in "${ids[@]}"; do
  # Strip any leading/trailing whitespace from id
  id=$(echo "$id" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')

  # Look for a table row where first cell is exactly this id
  # Pattern: line starts with |, optional whitespace, the id, optional whitespace, |
  # Then capture the second cell (status)
  # Use perl for more reliable regex matching
  status=$(perl -ne "print \$1 if /^\\|\\s*\Q$id\E\\s*\\|\\s*([^|]+)\\s*\\|/" "$REVIEW_FILE" | head -1 | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')

  if [[ -z "$status" ]]; then
    missing+=("$id: row not found")
  elif [[ "$status" != "met" && "$status" != "not met" ]]; then
    missing+=("$id: status is '$status' (expected met or not met)")
  fi
done

# Report and exit
if [[ ${#missing[@]} -eq 0 ]]; then
  echo "ALL ROWS PRESENT (${#ids[@]})"
  exit 0
else
  echo "FAILED:"
  for m in "${missing[@]}"; do
    echo "  - $m"
  done
  exit 1
fi
