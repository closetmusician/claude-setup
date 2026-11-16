#!/usr/bin/env bash
# ABOUTME: Step 3 gate for arm D. Undoes any spec-fix edit to the requirements (restore from base_ref, go on);
# ABOUTME: verdict and ambiguities hold no P0/P1 line (P2 is the coder's choice; owner 2026-11-15). Always writes design.diff.
# ABOUTME: design edits are kept. Fails only if base_ref lacks the requirements. Exit 0 only
# ABOUTME: when all checks pass; exit 1 on any failure with the failed checks named; exit 2 on usage error.
set -euo pipefail

# Purpose: show usage text and exit with code 2 (usage error).
# Usage:   usage
# Gotchas: called on --help or wrong argument count.
usage() {
  cat <<'EOF'
Usage: spec-gate.sh <repo> <requirements> <design> <verdict> <ambiguities> <base_ref> <out_dir>

Checks:
  1. requirements must match base_ref. A spec-fix edit is undone from base_ref and the gate goes on.
     It fails only when base_ref does not hold the requirements file.
  2. verdict holds no P0: or P1: line (untagged text counts as P1).
  3. ambiguities hold no P0: or P1: line. P2: lines and NONE pass. Untagged lines count as P1.
  4. Always writes git diff <base_ref> -- <design> to <out_dir>/design.diff.

Exit codes:
  0 = all checks pass
  1 = one or more checks failed
  2 = usage error

All paths are relative to <repo>.
EOF
  exit 2
}

[[ $# -eq 7 ]] || usage
[[ "${1:-}" == "--help" ]] && usage

REPO="$1"
REQUIREMENTS="$2"
DESIGN="$3"
VERDICT="$4"
AMBIGUITIES="$5"
BASE_REF="$6"
OUT_DIR="$7"

cd "$REPO"
mkdir -p "$OUT_DIR"

failures=()

# Check 1: requirements unchanged from base_ref
# Purpose: detect if requirements file has any staged or unstaged changes from base_ref.
# Usage:   git diff --quiet exits 0 when no diff, 1 when there is a diff.
# Gotchas: compares working tree to base_ref, which catches both staged and unstaged changes.
# Owner (2026-11-15, c7e1271): move forward. Commit changed requirements and design, then go on.
# armd-spec.sh commits the inputs before Codex runs, so base_ref always holds this file here.
if ! git diff --quiet "$BASE_REF" -- "$REQUIREMENTS" 2>/dev/null; then
  if git cat-file -e "${BASE_REF}:${REQUIREMENTS}" 2>/dev/null; then
    git add -- "$REQUIREMENTS" "$DESIGN"
    if ! git diff --cached --quiet -- "$REQUIREMENTS" "$DESIGN"; then
      # F11: Commit only the two staged paths
      git commit -q -m "spec inputs changed" -- "$REQUIREMENTS" "$DESIGN"
    fi
    echo "REQUIREMENTS CHANGED: committed and moved on"
  else
    failures+=("requirements file is not in $BASE_REF; nothing was restored")
  fi
fi

# Checks 2-3: verdict and ambiguities
# Owner rule (2026-11-15): only P0 and P1 lines block. P2 is the coder's choice.
# Purpose: count blocking lines. A line blocks when it starts with P0: or P1: (after an optional
#          bullet or number), or when it is untagged text that is not NONE / NO CONFLICTS / P2:.
# Gotchas: untagged lines count as P1 to fail safe; blank lines never count.
count_blocking() {
  perl -ne 'BEGIN{$n=0} s/\s+$//; next if $_ eq ""; s/^\s*(?:[-*]|\d+[.)])?\s*\**//; next if /^(NONE|NO CONFLICTS)\b/; next if /^P2\b/; $n++ if /^P[01]\b/ || !/^P[0-2]\b/; END{print $n}' "$1" 2>/dev/null || echo 1
}
[[ -f "$VERDICT" ]] || failures+=("verdict file missing")
[[ -f "$AMBIGUITIES" ]] || failures+=("ambiguities file missing")
# An empty verdict means the Codex check did not run, so the spec is unchecked: count it as P1.
if [[ -f "$VERDICT" ]] && ! perl -ne '$f = 1 if /\S/; END { exit($f ? 0 : 1) }' "$VERDICT"; then
  failures+=("verdict is empty: the Codex check did not run")
fi
verdict_block=$(count_blocking "$VERDICT")
ambig_block=$(count_blocking "$AMBIGUITIES")
if [[ "$verdict_block" != "0" ]]; then
  failures+=("verdict has $verdict_block P0/P1 conflict line(s)")
fi
if [[ "$ambig_block" != "0" ]]; then
  failures+=("ambiguities has $ambig_block P0/P1 line(s)")
fi

# Check 4: always write design.diff
# Purpose: write the diff even if the gate fails, so the caller can see what changed.
# Usage:   git diff <base_ref> -- <design> > <out_dir>/design.diff
# Gotchas: runs after the requirements check, which may have restored design.
git diff "$BASE_REF" -- "$DESIGN" > "$OUT_DIR/design.diff" 2>&1 || true

# Report and exit
if [[ ${#failures[@]} -eq 0 ]]; then
  echo "PASS"
  exit 0
else
  echo "FAILED:"
  for f in "${failures[@]}"; do
    echo "  - $f"
  done
  exit 1
fi
