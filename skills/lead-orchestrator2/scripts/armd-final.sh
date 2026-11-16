#!/usr/bin/env bash
# ABOUTME: Stage 5 script for arm D (final re-review of fix diff). Runs Codex on fix range, extracts open P0/P1.
# ABOUTME: Counts src/ files changed in the fix diff.
# ABOUTME: Last stdout line: JSON with open_p0p1, final_ok, src_files_changed, open_items.
# ABOUTME: Written 2026-11-15. Updated 2026-11-16 for REQ-02 (final_ok) and REQ-06 (golden_ref).
# ABOUTME: Usage: armd-final.sh <repo> <run_dir> <task_label> <req_ids comma> <requirements> <design> <pre_fix_sha> <base_ref> <codex> <golden_ref>

set -euo pipefail

# Transition (owner yes, 2026-11-16): workflow copies made before d39f636 pass no golden_ref.
# Accept the old count, with golden_ref "none". Remove this fallback after 2026-11-23.
if [[ $# -ne 10 && $# -ne 9 ]]; then
  echo "Usage: armd-final.sh <repo> <run_dir> <task_label> <req_ids comma> <requirements> <design> <pre_fix_sha> <base_ref> <codex> <golden_ref>" >&2
  exit 2
fi

REPO="$1"
RUN_DIR="$2"
TASK_LABEL="$3"
REQ_IDS="$4"
REQUIREMENTS="$5"
DESIGN="$6"
PRE_FIX_SHA="$7"
BASE_REF="$8"
CODEX="$9"
GOLDEN_REF="${10:-none}"

SCRIPTS="$(cd "$(dirname "$0")" && pwd)"
PROMPTS="$SCRIPTS/prompts"
source "$SCRIPTS/armd-lib.sh"

cd "$REPO"
mkdir -p "$RUN_DIR"
date -u +"final-start %FT%TZ" >> "$RUN_DIR/times.txt"

# Codex re-review (read-only) - REQ-06: pass golden_ref
final_prompt="$RUN_DIR/review-final-prompt.md"
final_out="$RUN_DIR/review-final.md"
final_log="$RUN_DIR/review-final.log"

fill_template "$PROMPTS/final-review.md" "$final_prompt" \
  "PRE_FIX_SHA" "$PRE_FIX_SHA" \
  "REQUIREMENTS" "$REQUIREMENTS" \
  "DESIGN" "$DESIGN" \
  "REQ_IDS" "$REQ_IDS" \
  "RUN_DIR" "$RUN_DIR" \
  "GOLDEN_REF" "$GOLDEN_REF"

node "$CODEX" task --wait --prompt-file "$final_prompt" > "$final_out" 2> "$final_log" || true

# Extract the open P0/P1 list; a parse failure is an open item - REQ-02: make final_ok explicit
open_items=()
final_ok=true
open_p0p1_json=$(extract_json "$final_out" open_p0p1)
if [[ "$open_p0p1_json" = "PARSE_FAIL" ]]; then
  final_ok=false
  open_p0p1_json="[]"
  open_items+=("final review JSON block missing or bad; see $final_out")
fi

# Count src/ files changed in fix diff
src_files_changed=$(git diff --name-only "$PRE_FIX_SHA..HEAD" -- src | wc -l | tr -d ' ')

date -u +"final-end %FT%TZ" >> "$RUN_DIR/times.txt"

# Last line: JSON - REQ-02: include final_ok
final_ok_bool="false"
[[ "$final_ok" = true ]] && final_ok_bool="true"

python3 - "$open_p0p1_json" "$final_ok_bool" "$src_files_changed" "${open_items[@]}" <<'BUILD_JSON'
import sys, json
open_p0p1_json = sys.argv[1]
final_ok_bool = sys.argv[2] == "true"
src_files_changed = int(sys.argv[3])

open_p0p1 = json.loads(open_p0p1_json)

print(json.dumps({
    'open_p0p1': open_p0p1,
    'final_ok': final_ok_bool,
    'src_files_changed': src_files_changed,
    'open_items': [x for x in sys.argv[4:] if x.strip()]
}))
BUILD_JSON
