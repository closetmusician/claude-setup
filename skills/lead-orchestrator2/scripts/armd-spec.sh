#!/usr/bin/env bash
# ABOUTME: Stage 1 script for arm D (spec fix). Runs Codex spec fix and re-check once (owner, 2026-11-15).
# ABOUTME: Commits inputs missing at or changed from base_ref first, then calls spec-gate.sh. Commits design edits.
# ABOUTME: Last stdout line: JSON with passed, rounds, open_items, kind. kind = pass/design/infra. Writes <run_dir>/spec-gate.pass only on a pass.
# ABOUTME: Written 2026-11-15. Updated 2026-11-16 for REQ-04 (kind) and REQ-06 (golden_ref).
# ABOUTME: Usage: armd-spec.sh <repo> <run_dir> <task_label> <req_ids comma> <requirements> <design> <base_ref> <codex> <golden_ref>

set -euo pipefail

# Transition (owner yes, 2026-11-16): workflow copies made before d39f636 pass no golden_ref.
# Accept the old count, with golden_ref "none". Remove this fallback after 2026-11-23.
if [[ $# -ne 9 && $# -ne 8 ]]; then
  echo "Usage: armd-spec.sh <repo> <run_dir> <task_label> <req_ids comma> <requirements> <design> <base_ref> <codex> <golden_ref>" >&2
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
GOLDEN_REF="${9:-none}"

SCRIPTS="$(cd "$(dirname "$0")" && pwd)"
PROMPTS="$SCRIPTS/prompts"
source "$SCRIPTS/armd-lib.sh"

cd "$REPO"
mkdir -p "$RUN_DIR"
date -u +"spec-start %FT%TZ" >> "$RUN_DIR/times.txt"
# The pass file is the coder's second lock. Remove a stale one from an earlier run first.
rm -f "$RUN_DIR/spec-gate.pass"

# Inputs at base_ref (owner, 2026-11-15: move forward, do not stop). If base_ref lacks an input, or an input
# differs from it, commit the inputs and use HEAD as this stage's base. Without this, spec-gate.sh would
# "restore" a file that base_ref does not hold, which deletes it (run R14a, 2026-11-15).
# REQ-04: A missing or unreadable input is kind="infra".
for input in "$REQUIREMENTS" "$DESIGN"; do
  if [[ ! -f "$input" ]]; then
    python3 -c 'import json,sys; print(json.dumps({"passed": False, "kind": "infra", "rounds": 0, "open_items": ["input file missing on disk: " + sys.argv[1]]}))' "$input"
    exit 0
  fi
  if [[ ! -r "$input" ]]; then
    python3 -c 'import json,sys; print(json.dumps({"passed": False, "kind": "infra", "rounds": 0, "open_items": ["input file not readable: " + sys.argv[1]]}))' "$input"
    exit 0
  fi
done
if ! git cat-file -e "${BASE_REF}:${REQUIREMENTS}" 2>/dev/null || ! git cat-file -e "${BASE_REF}:${DESIGN}" 2>/dev/null \
   || ! git diff --quiet "$BASE_REF" -- "$REQUIREMENTS" "$DESIGN"; then
  git add -- "$REQUIREMENTS" "$DESIGN"
  if ! git diff --cached --quiet -- "$REQUIREMENTS" "$DESIGN"; then
    git commit -q -m "inputs for $TASK_LABEL" -- "$REQUIREMENTS" "$DESIGN"
  fi
  BASE_REF="$(git rev-parse HEAD)"
  echo "inputs committed; spec base $BASE_REF" >> "$RUN_DIR/times.txt"
fi

# REQ-05: Write spec-base.txt for spec-resolve-check.sh
echo "$BASE_REF" > "$RUN_DIR/spec-base.txt"

round=0
passed=false
kind="pass"
open_items=()

# Owner rule (2026-11-15): Codex runs one round. P0/P1 left over go to an Opus resolver in the workflow.
while [[ $round -lt 1 ]] && [[ "$passed" = false ]]; do
  round=$((round + 1))

  # Codex spec fix (--write) - REQ-06: pass golden_ref
  fix_prompt="$RUN_DIR/spec-fix-$round-prompt.md"
  fix_out="$RUN_DIR/spec-fix-$round.out"
  fix_log="$RUN_DIR/spec-fix-$round.log"

  # REQ-07: Dead round-2 branch removed (loop bound is 1)
  fill_template "$PROMPTS/spec-fix.md" "$fix_prompt" \
    "TASK_LABEL" "$TASK_LABEL" \
    "REQ_IDS" "$REQ_IDS" \
    "REQUIREMENTS" "$REQUIREMENTS" \
    "DESIGN" "$DESIGN" \
    "RUN_DIR" "$RUN_DIR" \
    "GOLDEN_REF" "$GOLDEN_REF"

  node "$CODEX" task --wait --write --prompt-file "$fix_prompt" > "$fix_out" 2> "$fix_log" || true

  # Codex re-check (read-only) - REQ-06: pass golden_ref
  # REQ-04: Empty verdict or ambiguities gets ONE retry
  recheck_prompt="$RUN_DIR/spec-recheck-$round-prompt.md"
  verdict_out="$RUN_DIR/spec-verdict.md"
  recheck_log="$RUN_DIR/spec-recheck-$round.log"

  fill_template "$PROMPTS/spec-recheck.md" "$recheck_prompt" \
    "TASK_LABEL" "$TASK_LABEL" \
    "REQUIREMENTS" "$REQUIREMENTS" \
    "DESIGN" "$DESIGN" \
    "GOLDEN_REF" "$GOLDEN_REF"

  node "$CODEX" task --wait --prompt-file "$recheck_prompt" > "$verdict_out" 2> "$recheck_log" || true

  # REQ-04: Retry Codex once if verdict or ambiguities is empty or missing
  verdict_empty=false
  ambig_empty=false
  # N01: Check text content directly, not pipe size
  if [[ ! -s "$verdict_out" ]] || ! grep -q '[^[:space:]]' "$verdict_out" 2>/dev/null; then
    verdict_empty=true
  fi
  [[ ! -s "$RUN_DIR/ambiguities.md" ]] && ambig_empty=true

  if [[ "$verdict_empty" = true ]] || [[ "$ambig_empty" = true ]]; then
    echo "codex retry: empty verdict=$verdict_empty empty ambiguities=$ambig_empty" >> "$RUN_DIR/times.txt"
    node "$CODEX" task --wait --write --prompt-file "$fix_prompt" > "$fix_out.retry" 2> "$fix_log.retry" || true
    node "$CODEX" task --wait --prompt-file "$recheck_prompt" > "$verdict_out.retry" 2> "$recheck_log.retry" || true
    [[ -s "$verdict_out.retry" ]] && mv "$verdict_out.retry" "$verdict_out"
    # F06: Reset ambig_empty after successful retry
    ambig_empty=false
    [[ -s "$RUN_DIR/ambiguities.md" ]] || ambig_empty=true

    # N01: Still empty after retry = infra
    verdict_still_empty=false
    if [[ ! -s "$verdict_out" ]] || ! grep -q '[^[:space:]]' "$verdict_out" 2>/dev/null; then
      verdict_still_empty=true
    fi
    if [[ "$verdict_still_empty" = true ]] || [[ "$ambig_empty" = true ]]; then
      kind="infra"
      open_items+=("codex returned empty verdict or ambiguities twice")
      passed=false
      break
    fi
  fi

  # F08: Check that inputs still exist and are readable after Codex runs
  if [[ ! -f "$REQUIREMENTS" ]] || [[ ! -r "$REQUIREMENTS" ]]; then
    kind="infra"
    open_items+=("requirements file deleted or unreadable: $REQUIREMENTS")
    passed=false
    break
  fi
  if [[ ! -f "$DESIGN" ]] || [[ ! -r "$DESIGN" ]]; then
    kind="infra"
    open_items+=("design file deleted or unreadable: $DESIGN")
    passed=false
    break
  fi

  # Run spec-gate.sh - REQ-04: gate fail = design (not infra)
  gate_out="$RUN_DIR/gate-spec-$round.txt"
  if bash "$SCRIPTS/spec-gate.sh" "$REPO" "$REQUIREMENTS" "$DESIGN" "$verdict_out" "$RUN_DIR/ambiguities.md" "$BASE_REF" "$RUN_DIR" > "$gate_out" 2>&1; then
    passed=true
  else
    # N02: Gate failed means design conflict (Codex verdict never has kind:)
    # kind is already set by script facts above; a gate fail with non-empty verdict is design
    if [[ "$kind" != "infra" ]]; then
      kind="design"
    fi
    passed=false
  fi
done

# Commit design if it has uncommitted changes (whether or not gate passed). Compare with HEAD, not
# base_ref: on a relaunch the earlier spec fix is already committed, and an empty commit would exit 1.
if ! git diff --quiet HEAD -- "$DESIGN"; then
  git add "$DESIGN"
  git commit -m "spec fix $TASK_LABEL" -- "$DESIGN"
fi

# Write the pass file only when the gate passed. The coder refuses to start without it.
[[ "$passed" = true ]] && date -u +"%FT%TZ" > "$RUN_DIR/spec-gate.pass"

# Gather open items if the gate failed
if [[ "$passed" = false ]]; then
  if [[ -f "$RUN_DIR/spec-verdict.md" ]]; then
    mapfile -t verdict_lines < <(head -10 "$RUN_DIR/spec-verdict.md")
    open_items+=("${verdict_lines[@]}")
  fi
  if [[ -f "$RUN_DIR/ambiguities.md" ]]; then
    mapfile -t amb_lines < <(head -10 "$RUN_DIR/ambiguities.md")
    open_items+=("${amb_lines[@]}")
  fi
fi

date -u +"spec-end %FT%TZ" >> "$RUN_DIR/times.txt"

# Last line: JSON - REQ-04: include kind
passed_bool="false"
[[ "$passed" = true ]] && passed_bool="true"

python3 - "$passed_bool" "$kind" "$round" "${open_items[@]}" <<'JSON_END'
import sys, json
print(json.dumps({'passed': sys.argv[1] == 'true', 'kind': sys.argv[2], 'rounds': int(sys.argv[3]),
                  'open_items': [x.rstrip() for x in sys.argv[4:] if x.strip()]}))
JSON_END
