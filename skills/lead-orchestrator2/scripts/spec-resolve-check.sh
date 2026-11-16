#!/usr/bin/env bash
# ABOUTME: Check after the Opus resolver (arm D). Verifies requirements unchanged and design has resolutions heading.
# ABOUTME: Writes <run_dir>/spec-gate.pass on success. Prints JSON with ok and reason.
# ABOUTME: Written 2026-11-16 for REQ-05. exit 0 = pass, exit 1 = fail, exit 2 = usage error.
# ABOUTME: Usage: spec-resolve-check.sh <repo> <requirements> <design> <run_dir>

set -euo pipefail

if [[ $# -ne 4 ]]; then
  echo "Usage: spec-resolve-check.sh <repo> <requirements> <design> <run_dir>" >&2
  exit 2
fi

REPO="$1"
REQUIREMENTS="$2"
DESIGN="$3"
RUN_DIR="$4"

cd "$REPO"

# F09: Delete any old pass file before checking
rm -f "$RUN_DIR/spec-gate.pass"

# REQ-05: Read the base from spec-base.txt (written by armd-spec.sh)
if [[ ! -f "$RUN_DIR/spec-base.txt" ]]; then
  python3 -c 'import json; print(json.dumps({"ok": False, "reason": "spec-base.txt missing"}))'
  exit 1
fi
SPEC_BASE=$(cat "$RUN_DIR/spec-base.txt")

# Check 1: requirements unchanged against the spec base
if ! git diff --quiet "$SPEC_BASE" -- "$REQUIREMENTS"; then
  python3 -c 'import json; print(json.dumps({"ok": False, "reason": "requirements changed after spec stage"}))'
  exit 1
fi

# Check 2: design contains "## Opus resolutions (spec gate)"
if ! grep -qF "## Opus resolutions (spec gate)" "$DESIGN"; then
  python3 -c 'import json; print(json.dumps({"ok": False, "reason": "design missing Opus resolutions heading"}))'
  exit 1
fi

# Pass: write the pass file and return ok
date -u +"%FT%TZ" > "$RUN_DIR/spec-gate.pass"
python3 -c 'import json; print(json.dumps({"ok": True}))'
exit 0
