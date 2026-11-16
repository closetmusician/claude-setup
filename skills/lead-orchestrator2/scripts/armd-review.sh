#!/usr/bin/env bash
# ABOUTME: Stage 3 script for arm D (Codex review). Runs review, req-rows check, extracts JSON.
# ABOUTME: Records pre_fix_sha before review. Retries req-rows once if needed. Retries JSON parse once.
# ABOUTME: Last stdout line: JSON with req_rows_ok, review_ok, defects, pre_fix_sha, open_items.
# ABOUTME: Written 2026-11-15. Updated 2026-11-16 for REQ-02 (review_ok), REQ-06 (golden_ref), REQ-07 (repro trim).
# ABOUTME: Usage: armd-review.sh <repo> <run_dir> <task_label> <req_ids comma> <requirements> <design> <base_ref> <codex> <round_tag> <golden_ref>

set -euo pipefail

# Transition (owner yes, 2026-11-16): workflow copies made before d39f636 pass no golden_ref.
# Accept the old count, with golden_ref "none". Remove this fallback after 2026-11-23.
if [[ $# -ne 10 && $# -ne 9 ]]; then
  echo "Usage: armd-review.sh <repo> <run_dir> <task_label> <req_ids comma> <requirements> <design> <base_ref> <codex> <round_tag> <golden_ref>" >&2
  exit 2
fi

REPO="$1"
RUN_DIR="$2"
TASK_LABEL="$3"
REQ_IDS="$4"
REQUIREMENTS="$5"
DESIGN="$6"
BASE_REF="$7"
CODEX="$8"
ROUND_TAG="$9"
GOLDEN_REF="${10:-none}"

SCRIPTS="$(cd "$(dirname "$0")" && pwd)"
PROMPTS="$SCRIPTS/prompts"
source "$SCRIPTS/armd-lib.sh"

cd "$REPO"
mkdir -p "$RUN_DIR"
date -u +"review-start %FT%TZ" >> "$RUN_DIR/times.txt"

# Record pre_fix_sha
PRE_FIX_SHA=$(git rev-parse HEAD)

# Codex review (read-only) - REQ-06: pass golden_ref
review_prompt="$RUN_DIR/review-$ROUND_TAG-prompt.md"
review_out="$RUN_DIR/review-$ROUND_TAG.md"
review_log="$RUN_DIR/review-$ROUND_TAG.log"

fill_template "$PROMPTS/review.md" "$review_prompt" \
  "BASE_REF" "$BASE_REF" \
  "DESIGN" "$DESIGN" \
  "REQUIREMENTS" "$REQUIREMENTS" \
  "REQ_IDS" "$REQ_IDS" \
  "GOLDEN_REF" "$GOLDEN_REF"

node "$CODEX" task --wait --prompt-file "$review_prompt" > "$review_out" 2> "$review_log" || true

# req-rows check
req_rows_ok=true
req_rows_out="$RUN_DIR/req-rows-$ROUND_TAG.txt"
open_items=()

if ! bash "$SCRIPTS/req-rows.sh" "$review_out" "$REQ_IDS" > "$req_rows_out" 2>&1; then
  # Retry once with full context
  missing=$(cat "$req_rows_out")
  retry_prompt="$RUN_DIR/review-$ROUND_TAG-retry-prompt.md"
  retry_out="$RUN_DIR/review-$ROUND_TAG-retry.md"
  retry_log="$RUN_DIR/review-$ROUND_TAG-retry.log"

  # Repeat the filled review prompt, then add the missing ids
  {
    cat "$review_prompt"
    echo ""
    echo "RETRY. The req-rows gate says: $missing"
    echo "Add the missing rows. Print the full review again with part (a) containing all REQ rows: $REQ_IDS."
  } > "$retry_prompt"

  node "$CODEX" task --wait --prompt-file "$retry_prompt" > "$retry_out" 2> "$retry_log" || true

  if ! bash "$SCRIPTS/req-rows.sh" "$retry_out" "$REQ_IDS" > "$req_rows_out" 2>&1; then
    req_rows_ok=false
    open_items+=("req-rows gate failed twice: $missing")
  else
    # Use retry output
    cp "$retry_out" "$review_out"
  fi
fi

# Extract the defects list from the last ```json block; one Codex retry on a parse failure
# REQ-02: Make parse failure explicit via review_ok field
review_ok=true
defects_json=$(extract_json "$review_out" defects)
if [[ "$defects_json" = "PARSE_FAIL" ]]; then
  json_retry_prompt="$RUN_DIR/review-$ROUND_TAG-json-retry-prompt.md"
  json_retry_out="$RUN_DIR/review-$ROUND_TAG-json-retry.md"
  {
    cat "$review_prompt"
    echo ""
    echo "Your earlier review is in $review_out. Print only its fenced json defects block, in the format above."
  } > "$json_retry_prompt"
  node "$CODEX" task --wait --prompt-file "$json_retry_prompt" > "$json_retry_out" 2> "$json_retry_out.log" || true
  defects_json=$(extract_json "$json_retry_out" defects)
fi
if [[ "$defects_json" = "PARSE_FAIL" ]]; then
  review_ok=false
  defects_json="[]"
  open_items+=("defects JSON block missing or bad twice; see $review_out")
fi

# REQ-07: Request repros only for P0/P1 defects without repros AND without file:line
python3 - "$defects_json" <<'P0P1_WITHOUT_REPRO' > "$RUN_DIR/p0p1-no-repro.txt"
import sys, json, re
defects = json.loads(sys.argv[1])
ids = [d['id'] for d in defects
       if d.get('sev') in ['P0', 'P1']
       and not d.get('has_repro', False)
       and not re.search(r':\d+', d.get('file', ''))]
if ids:
    print(' '.join(ids))
P0P1_WITHOUT_REPRO

p0p1_no_repro=$(cat "$RUN_DIR/p0p1-no-repro.txt")
if [[ -n "$p0p1_no_repro" ]]; then
  repro_prompt="$RUN_DIR/review-$ROUND_TAG-repro-prompt.md"
  repro_out="$RUN_DIR/review-$ROUND_TAG-repro.md"

  {
    echo "Read $review_out. For each of these P0/P1 defect ids: $p0p1_no_repro"
    echo "Read $REQUIREMENTS and $DESIGN."
    echo "Golden reference: $GOLDEN_REF"
    echo "When files clash, the owner's product docs named in the golden reference win, then the requirements, then the design. Note the clash; never stop on it."
    echo "Provide one shell repro command, or the literal NO REPRO if none exists."
    echo "End with a fenced json block:"
    echo '```json'
    echo '{"repros": {"<id>": "<cmd or NO REPRO>"}}'
    echo '```'
  } > "$repro_prompt"

  node "$CODEX" task --wait --prompt-file "$repro_prompt" > "$repro_out" 2> "$repro_out.log" || true

  repros_json=$(extract_json "$repro_out" repros)
  if [[ "$repros_json" != "PARSE_FAIL" ]]; then
    # Merge repros back into defects_json
    defects_json=$(python3 - "$defects_json" "$repros_json" <<'MERGE_REPROS'
import sys, json
defects = json.loads(sys.argv[1])
repros = json.loads(sys.argv[2])
for d in defects:
    if d['id'] in repros and repros[d['id']] != 'NO REPRO':
        d['has_repro'] = True
        d['repro'] = repros[d['id']]
    elif d['id'] in repros and repros[d['id']] == 'NO REPRO':
        pass  # Still no repro
print(json.dumps(defects))
MERGE_REPROS
)
  fi
  # Add ids still without repro to open_items (also when the repro answer did not parse)
    while read -r line; do
      [[ -n "$line" ]] && open_items+=("$line")
    done < <(python3 - "$defects_json" <<'STILL_NO_REPRO'
import sys, json
defects = json.loads(sys.argv[1])
for d in defects:
    if d.get('sev') in ['P0', 'P1'] and not d.get('has_repro', False):
        print(f"{d['id']} {d['sev']}: no repro")
STILL_NO_REPRO
)
fi

date -u +"review-end %FT%TZ" >> "$RUN_DIR/times.txt"

# Last line: JSON - REQ-02: include review_ok
req_rows_bool="false"
[[ "$req_rows_ok" = true ]] && req_rows_bool="true"
review_ok_bool="false"
[[ "$review_ok" = true ]] && review_ok_bool="true"

python3 - "$defects_json" "$PRE_FIX_SHA" "$req_rows_bool" "$review_ok_bool" "${open_items[@]}" <<'BUILD_JSON'
import sys, json
defects_json = sys.argv[1]
pre_fix_sha = sys.argv[2]
req_rows_bool = sys.argv[3] == "true"
review_ok_bool = sys.argv[4] == "true"

items = [x.rstrip() for x in sys.argv[5:] if x.strip()]
defects = json.loads(defects_json)

print(json.dumps({
    'req_rows_ok': req_rows_bool,
    'review_ok': review_ok_bool,
    'defects': defects,
    'pre_fix_sha': pre_fix_sha,
    'open_items': items
}))
BUILD_JSON
