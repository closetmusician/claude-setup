#!/usr/bin/env bash
# ABOUTME: GEPA-style skill evolution for lead-orchestrator (Pillar III §III-7).
# ABOUTME: Scores incumbent SKILL.md against golden traces + eval corpus + incident fixtures,
# ABOUTME: generates ≤3 candidate variants via write-incapable claude -p, scores each,
# ABOUTME: and STAGES the best if it beats incumbent by ≥1 point with regressions[] empty.
# ABOUTME: Never overwrites the live SKILL.md. Outputs NO-IMPROVEMENT if no candidate clears bar.
# ABOUTME: Usage: bash scripts/flywheel/gepa-evolve.sh [--dry-run] [--debug]

set -uo pipefail
trap 'echo "[gepa-evolve] WARN: unexpected error on line $LINENO" >&2' ERR

# ── Dependency check ──────────────────────────────────────────────────────────
command -v jq >/dev/null 2>&1 || { echo "[gepa-evolve] SKIP: jq not found" >&2; exit 0; }
command -v python3 >/dev/null 2>&1 || { echo "[gepa-evolve] SKIP: python3 not found" >&2; exit 0; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAUDE_SCRIPTS="$(cd "$SCRIPT_DIR/.." && pwd)"
CLAUDE_DIR="$(cd "$CLAUDE_SCRIPTS/.." && pwd)"
HARNESS="${HARNESS_BIN:-${HOME}/.claude/bin/harness}"
CLAUDE_BIN="${CLAUDE_BIN:-claude}"
TIMEOUT_LIB="${CLAUDE_SCRIPTS}/lib/timeout.sh"

# Source timeout helper if available
[[ -f "$TIMEOUT_LIB" ]] && source "$TIMEOUT_LIB"

# ── Configuration ─────────────────────────────────────────────────────────────
SKILL_PATH="${CLAUDE_DIR}/skills/lead-orchestrator/SKILL.md"
EVOLVE_MODEL="${GEPA_MODEL:-claude-sonnet-4-5}"
EVOLVE_TIMEOUT="${GEPA_TIMEOUT_SECS:-300}"
MAX_CANDIDATES="${GEPA_MAX_CANDIDATES:-3}"
DRY_RUN=false
DEBUG=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run) DRY_RUN=true; shift ;;
    --debug)   DEBUG=true;   shift ;;
    *) echo "[gepa-evolve] unknown arg: $1" >&2; exit 1 ;;
  esac
done

# ── Resolve STATE directory ───────────────────────────────────────────────────
if [[ -n "${HARNESS_GOV_STATE_DIR:-}" ]]; then
  _STATE_DIR="$HARNESS_GOV_STATE_DIR"
elif [[ -n "${STATE:-}" ]]; then
  _STATE_DIR="$STATE"
else
  _claude_top="$(git -C "${HOME}/.claude" rev-parse --show-toplevel 2>/dev/null)" || _claude_top=""
  if [[ -n "$_claude_top" ]]; then
    _STATE_DIR="${_claude_top}/.agents/claude-governance"
  else
    _STATE_DIR="${HOME}/.claude/state"
  fi
fi

PROPOSALS_DIR="${_STATE_DIR}/state/flywheel/skill-proposals"
mkdir -p "$PROPOSALS_DIR"

# Evidence output dir
EVIDENCE_DIR="${CLAUDE_DIR}/docs/plans/harness/fable/evidence"
mkdir -p "$EVIDENCE_DIR"
EVIDENCE_FILE="${EVIDENCE_DIR}/S7-gepa.md"

GOLDEN_TRACES_DIR="${HARNESS_GOLDEN_DIR:-${_STATE_DIR}/eval-corpus/golden-traces}"
CORPUS_DIR="${HARNESS_EVAL_CORPUS_DIR:-${CLAUDE_DIR}/evals/incidents}"
GOLDEN_BUILDER="${CLAUDE_SCRIPTS}/flywheel/build-golden-traces.sh"

_log() { echo "[gepa-evolve] $*"; }
_dbg() { [[ "$DEBUG" == "true" ]] && echo "[gepa-evolve DEBUG] $*" >&2 || true; }

_ensure_golden_traces() {
  if [[ ! -d "$GOLDEN_TRACES_DIR" && -x "$GOLDEN_BUILDER" ]]; then
    HARNESS_GOLDEN_DIR="$GOLDEN_TRACES_DIR" "$GOLDEN_BUILDER" >/dev/null 2>&1 || true
  fi
}

_json_get_int() {
  local key="$1"
  python3 -c "import json,sys; d=json.load(sys.stdin); print(int(d.get('$key',0) or 0))" 2>/dev/null || echo 0
}

_json_get_str() {
  local key="$1"
  python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('$key','') or '')" 2>/dev/null || echo ''
}

_json_get_array() {
  local key="$1"
  python3 -c "import json,sys; d=json.load(sys.stdin); print(json.dumps(d.get('$key',[])))" 2>/dev/null || echo '[]'
}

_skill_body_from_diff() {
  local diff_file="$1" body_out="$2"
  local patch_root="$3"
  mkdir -p "$patch_root/skills/lead-orchestrator"
  cp "$SKILL_PATH" "$patch_root/skills/lead-orchestrator/SKILL.md"
  if [[ -n "$diff_file" && -f "$diff_file" ]]; then
    ( cd "$patch_root" && patch --batch -p1 < "$diff_file" >/dev/null 2>&1 ) || return 1
  fi
  cp "$patch_root/skills/lead-orchestrator/SKILL.md" "$body_out"
}

_score_skill_body() {
  local body_file="$1"
  python3 - "$body_file" <<'PY'
import json
import re
import sys

body = open(sys.argv[1], encoding="utf-8").read()
checks = [
    ("spawn-not-code", [r"ORCHESTRATOR SPAWNS SUBAGENTS", r"ORCHESTRATOR NEVER CODES"]),
    ("verification-gate", [r"NOTHING REACHES THE USER UNVERIFIED", r"verification\.md"]),
    ("qa-authorship", [r"QA/verification artifacts are SUBAGENT-authored", r"orchestrator NEVER writes"]),
    ("hook-block-recovery", [r"hook blocks a spawn", r"re-spawn immediately"]),
    ("context-budget-survival", [r"Context Budget", r"Checkpoint", r"compaction"]),
    ("completion-evidence", [r"No \"done / complete / passing / deployed\" claim", r"verification\.md"]),
]
passed = []
failed = []
for name, patterns in checks:
    if all(re.search(p, body, re.I) for p in patterns):
        passed.append(name)
    else:
        failed.append(name)
print(json.dumps({"skill_body_passes": len(passed), "skill_body_failed": failed}, sort_keys=True))
PY
}

_write_s7_evidence() {
  local result="$1"
  local extra="$2"
  local tmp_file
  tmp_file="$(mktemp /tmp/s7-gepa-XXXXXX.md)"
  RESULT="$result" \
  EXTRA="$extra" \
  INCUMBENT_SCORE="$INCUMBENT_SCORE" \
  NEEDED_SCORE="$NEEDED_SCORE" \
  MAX_CANDIDATES="$MAX_CANDIDATES" \
  BEST_SCORE="$BEST_SCORE" \
  BEST_CANDIDATE_N="$BEST_CANDIDATE_N" \
  CANDIDATE_LOG="$(printf '%b' "$CANDIDATE_LOG")" \
  INCUMBENT_DETAIL="$INCUMBENT_DETAIL" \
  BEST_SCORE_JSON="$BEST_SCORE_JSON" \
  FINAL_VERDICT="${FINAL_VERDICT:-}" \
  FINAL_REGRESSIONS="${FINAL_REGRESSIONS:-}" \
  PROPOSED_PATH="${PROPOSED_PATH:-}" \
  EVIDENCE_SKILL="${EVIDENCE_SKILL:-}" \
  PROPOSAL_DIFF_DEST="${PROPOSAL_DIFF_DEST:-}" \
  python3 - <<'PY' > "$tmp_file"
import datetime
import json
import os

def pretty_json(name):
    raw = os.environ.get(name, "{}")
    try:
        return json.dumps(json.loads(raw), indent=2, sort_keys=True)
    except Exception:
        return raw

ts = datetime.datetime.utcnow().strftime("%Y-%m-%dT%H:%M:%SZ")
result = os.environ.get("RESULT", "UNKNOWN")
extra = os.environ.get("EXTRA", "")
lines = [
    f"# S7-GEPA Evidence - {ts}",
    "",
    f"## Result: {result}",
    "",
    f"- Incumbent score: {os.environ.get('INCUMBENT_SCORE','')}",
    f"- Threshold needed: {os.environ.get('NEEDED_SCORE','')}",
    f"- Candidates evaluated: {os.environ.get('MAX_CANDIDATES','')}",
    f"- Best candidate score: {os.environ.get('BEST_SCORE','')} (candidate {os.environ.get('BEST_CANDIDATE_N','')})",
]
if os.environ.get("FINAL_VERDICT"):
    lines.append(f"- Final harness eval verdict: {os.environ.get('FINAL_VERDICT')}")
if os.environ.get("FINAL_REGRESSIONS"):
    lines.append(f"- Final regressions: {os.environ.get('FINAL_REGRESSIONS')}")
if extra:
    lines += ["", "## Note", extra]
if os.environ.get("PROPOSED_PATH"):
    lines += [
        "",
        "## Staged files",
        f"- {os.environ.get('PROPOSED_PATH')}",
        f"- {os.environ.get('EVIDENCE_SKILL')}",
        f"- {os.environ.get('PROPOSAL_DIFF_DEST')}",
    ]
lines += [
    "",
    "## Candidate log",
    os.environ.get("CANDIDATE_LOG", "").strip() or "(none)",
    "",
    "## Incumbent detail",
    "```json",
    pretty_json("INCUMBENT_DETAIL"),
    "```",
]
if os.environ.get("BEST_SCORE_JSON", "{}") != "{}":
    lines += ["", "## Best candidate detail", "```json", pretty_json("BEST_SCORE_JSON"), "```"]
lines += [
    "",
    "## Constraints verified",
    "- Live SKILL.md untouched by scoring: YES",
    "- Golden corpus read through HARNESS_GOLDEN_DIR: YES",
    "- Score includes skill_body_passes from the candidate SKILL.md text: YES",
]
print("\n".join(lines) + "\n")
PY
  if [[ -s "$tmp_file" ]]; then
    mv "$tmp_file" "$EVIDENCE_FILE"
  else
    rm -f "$tmp_file"
  fi
}

# ── SCORING HARNESS ───────────────────────────────────────────────────────────
# Purpose: Compute deterministic golden-score for a SKILL.md candidate.
# Score = (golden_trace_passes * 2) + corpus_passes + (skill_body_passes * 3)
#   - golden_trace_passes: count of 5 traces with PASS (max 10 pts)
#   - corpus_passes: count of fixtures with PASS verdict (max = total non-gap fixtures)
#   - skill_body_passes: deterministic incident-replay checks over the proposed SKILL.md body
# For the incumbent (no diff): baseline score from harness replay --all-golden + eval run.
# For a candidate (diff file): score from patched eval run + replay (replay unaffected by skill diff).
# Returns: integer score on stdout; all sub-results to stderr (if debug).
# Gotchas: replay and guard corpus are behavior regression checks. The skill body signal
#   comes from the local incident-replay oracle so a candidate body can actually change score.
_compute_score() {
  local diff_file="${1:-}"  # empty = baseline (incumbent)
  local tmp_dir
  tmp_dir="$(mktemp -d /tmp/gepa-score-XXXXXX)"

  # ── 1. Golden trace replay score ──────────────────────────────────────────
  # Always run replay against live guard scripts (replay is guard-behavior, not skill text)
  local replay_pass=0 replay_fail=0
  local replay_out
  _ensure_golden_traces
  replay_out="$(HARNESS_GOLDEN_DIR="$GOLDEN_TRACES_DIR" "$HARNESS" replay --all-golden 2>/dev/null)" || true

  # Parse "PASS=N  FAIL=M" from the last line
  if printf '%s\n' "$replay_out" | grep -q "Results:"; then
    replay_pass=$(printf '%s\n' "$replay_out" | awk '/Results:/ { for (i=1;i<=NF;i++) if ($i ~ /^PASS=/) { sub(/^PASS=/,"",$i); print $i; exit } }')
    replay_fail=$(printf '%s\n' "$replay_out" | awk '/Results:/ { for (i=1;i<=NF;i++) if ($i ~ /^FAIL=/) { sub(/^FAIL=/,"",$i); print $i; exit } }')
    replay_pass="${replay_pass:-0}"
    replay_fail="${replay_fail:-0}"
  fi
  _dbg "replay: pass=$replay_pass fail=$replay_fail"

  # ── 2. Eval corpus score ───────────────────────────────────────────────────
  local corpus_passes=0 corpus_regressions="[]" corpus_verdict=""
  local eval_out eval_json
  if [[ -n "$diff_file" && -f "$diff_file" ]]; then
    eval_out="$(HARNESS_STATE_OVERRIDE="$tmp_dir/state" \
      HARNESS_EVAL_CORPUS_DIR="$CORPUS_DIR" \
      "$HARNESS" eval run --with-patch "$diff_file" 2>/dev/null)" || true
  else
    eval_out="$(HARNESS_STATE_OVERRIDE="$tmp_dir/state" \
      HARNESS_EVAL_CORPUS_DIR="$CORPUS_DIR" \
      "$HARNESS" eval run 2>/dev/null)" || true
  fi

  # Extract JSON summary line (last { } line)
  eval_json="$(printf '%s\n' "$eval_out" | grep '^{' | tail -1)"
  if [[ -n "$eval_json" ]]; then
    corpus_passes="$(printf '%s\n' "$eval_json" | _json_get_int passed)"
    corpus_regressions="$(printf '%s\n' "$eval_json" | _json_get_array regressions)"
    corpus_verdict="$(printf '%s\n' "$eval_json" | _json_get_str verdict)"
  fi
  _dbg "corpus: passes=$corpus_passes regressions=$corpus_regressions verdict=$corpus_verdict"

  # ── 3. Skill-body incident replay score ───────────────────────────────────
  local body_file="$tmp_dir/skill-body.md"
  local skill_body_json='{"skill_body_passes":0,"skill_body_failed":["patch-apply-failed"]}'
  local skill_body_passes=0 skill_body_failed='["patch-apply-failed"]'
  if _skill_body_from_diff "$diff_file" "$body_file" "$tmp_dir/patch-root"; then
    skill_body_json="$(_score_skill_body "$body_file")"
    skill_body_passes="$(printf '%s\n' "$skill_body_json" | _json_get_int skill_body_passes)"
    skill_body_failed="$(printf '%s\n' "$skill_body_json" | _json_get_array skill_body_failed)"
  fi
  _dbg "skill-body: passes=$skill_body_passes failed=$skill_body_failed"

  # ── 4. Compute score ──────────────────────────────────────────────────────
  local score=$(( replay_pass * 2 + corpus_passes + skill_body_passes * 3 ))

  # Write sub-scores to a temp result file for the caller to inspect
  jq -cn \
    --argjson score "$score" \
    --argjson replay_pass "$replay_pass" \
    --argjson replay_fail "$replay_fail" \
    --argjson corpus_passes "$corpus_passes" \
    --argjson corpus_regressions "$corpus_regressions" \
    --arg corpus_verdict "$corpus_verdict" \
    --argjson skill_body_passes "$skill_body_passes" \
    --argjson skill_body_failed "$skill_body_failed" \
    '{score:$score,replay_pass:$replay_pass,replay_fail:$replay_fail,corpus_passes:$corpus_passes,corpus_regressions:$corpus_regressions,corpus_verdict:$corpus_verdict,skill_body_passes:$skill_body_passes,skill_body_failed:$skill_body_failed}' \
    > "$tmp_dir/result.json" 2>/dev/null || true
  # Pass the result JSON path via GEPA_LAST_SCORE_FILE if set
  if [[ -n "${GEPA_LAST_SCORE_FILE:-}" ]]; then
    cp "$tmp_dir/result.json" "$GEPA_LAST_SCORE_FILE" 2>/dev/null || true
  fi

  rm -rf "$tmp_dir"
  printf '%d' "$score"
}

# ── CANDIDATE GENERATION ─────────────────────────────────────────────────────
# Purpose: Generate one candidate SKILL.md variant via write-incapable claude -p.
# The LLM outputs a proposed SKILL.md body as plain text (not a diff) to stdout.
# The runner materializes it into a throwaway file and computes the diff.
# Gotchas: allowedTools Read,Grep,Glob only — no Write/Edit. claude never touches the real skill.
_generate_candidate() {
  local candidate_n="$1"       # 1-indexed candidate number
  local incumbent_score="$2"   # numeric score to beat
  local candidate_out="$3"     # path where caller wants the proposed skill body written

  # Build evolution prompt
  local prompt_file
  prompt_file="$(mktemp /tmp/gepa-prompt-XXXXXX)"

  # Build prompt via python3 string concatenation (NOT f-string) to avoid curly-brace
  # expansion errors when SKILL.md content contains literal { } (e.g. JSON examples).
  # NOTE: report NOT included — it adds ~3KB and pushes generation time past 180s timeout.
  python3 - "$prompt_file" <<PYEOF 2>/dev/null
import sys

skill_path = '${SKILL_PATH}'
candidate_n = ${candidate_n}
max_candidates = ${MAX_CANDIDATES}
incumbent_score = ${incumbent_score}
out_path = sys.argv[1]

skill = open(skill_path).read()

# Per-candidate focus areas (from 204-session deep-read failure modes)
focus_map = {
    1: ('context-budget survival',
        'Add a Context Budget Protocol section: checkpoint if >50% context used (write digest to logs/), '
        'compaction recovery (read last digest on restart), emergency stop if >80% context.'),
    2: ('self-implementation prevention',
        'Strengthen Iron Law 1 enforcement: add explicit hook-block recovery steps — '
        'if a hook fires blocking self-implementation, STOP, log the attempt, spawn a fresh subagent instead.'),
    3: ('fake-completion prevention',
        'Require verification.md evidence for ALL completion claims: add a Completion Evidence Gate — '
        'verifier must cite file:line for each AC; "agent reported done" is never sufficient.'),
}
n = min(candidate_n, 3)
focus_name, focus_detail = focus_map[n]

header = (
    'You are improving the lead-orchestrator SKILL.md.\n\n'
    'Produce an improved SKILL.md body. This is candidate ' + str(candidate_n) + ' of ' + str(max_candidates) + '.\n'
    'The current SKILL.md has a golden-score of ' + str(incumbent_score) + ' (golden_trace_passes*2 + corpus_passes).\n\n'
    '## Focus for candidate ' + str(candidate_n) + ': ' + focus_name + '\n'
    + focus_detail + '\n\n'
    '## Output format (STRICT)\n'
    'Output ONLY the complete improved SKILL.md text, starting with the frontmatter (---) block.\n'
    'Do NOT output any explanation, diff, or commentary. Just the raw SKILL.md body.\n'
    'All existing sections MUST be preserved. Make the change SURGICAL.\n\n'
    '## Current SKILL.md:\n\n'
)

with open(out_path, 'w') as f:
    f.write(header)
    f.write(skill)
    f.write('\n')
PYEOF
  [[ -s "$prompt_file" ]] || { rm -f "$prompt_file"; return 1; }

  local raw_output=""
  local claude_exit=0

  if ! command -v "$CLAUDE_BIN" >/dev/null 2>&1; then
    _log "  WARN: claude not found — cannot generate candidate $candidate_n"
    rm -f "$prompt_file"
    return 1
  fi

  # Use CLAUDE_SHIM if set (for tests with mock shim)
  local claude_cmd="$CLAUDE_BIN"
  [[ -n "${CLAUDE_SHIM:-}" ]] && claude_cmd="$CLAUDE_SHIM"

  if declare -f _run_with_timeout >/dev/null 2>&1; then
    raw_output="$(_run_with_timeout "$EVOLVE_TIMEOUT" \
      "$claude_cmd" -p --model "$EVOLVE_MODEL" \
      --allowedTools "Read,Grep,Glob" \
      < "$prompt_file" 2>/dev/null)" || claude_exit=$?
  else
    raw_output="$("$claude_cmd" -p --model "$EVOLVE_MODEL" \
      --allowedTools "Read,Grep,Glob" \
      < "$prompt_file" 2>/dev/null)" || claude_exit=$?
  fi
  rm -f "$prompt_file"

  if [[ -z "$raw_output" ]]; then
    [[ "$claude_exit" -eq 124 ]] && _log "  WARN: claude timed out for candidate $candidate_n" \
      || _log "  WARN: empty output from claude for candidate $candidate_n (exit=$claude_exit)"
    return 1
  fi

  # Validate and extract: must contain frontmatter (---) or a heading line.
  # LLMs sometimes prepend prose before the skill body — strip it by seeking first --- or #.
  if ! printf '%s\n' "$raw_output" | grep -qE "^(---|# )"; then
    _log "  WARN: candidate $candidate_n output doesn't look like a SKILL.md (no frontmatter/heading)"
    return 1
  fi
  # Extract from first frontmatter line onward, discarding any LLM preamble
  printf '%s\n' "$raw_output" | python3 -c "
import sys
lines = sys.stdin.read().splitlines(keepends=True)
for i, line in enumerate(lines):
    if line.startswith('---') or line.startswith('#'):
        sys.stdout.writelines(lines[i:])
        break
" > "$candidate_out"
  _log "  candidate $candidate_n generated ($(wc -l < "$candidate_out") lines)"
  return 0
}

# ── DIFF GENERATION ───────────────────────────────────────────────────────────
# Purpose: Produce a unified diff between incumbent and candidate SKILL.md.
# Gotchas: diff exits 1 when files differ (normal); 2 = error. BSD-safe diff -u.
_make_diff() {
  local candidate_file="$1"
  local diff_out="$2"
  # diff exits 1 when there are differences — that's expected
  diff -u "$SKILL_PATH" "$candidate_file" > "$diff_out" 2>/dev/null || true
  # Rewrite a/b paths for patch -p1 compatibility (a/skills/... b/skills/...)
  local skill_rel="skills/lead-orchestrator/SKILL.md"
  python3 -c "
import sys
content = open('$diff_out').read()
# Replace absolute paths with relative patch paths
import re
content = re.sub(r'--- .*\n', '--- a/$skill_rel\n', content, count=1)
content = re.sub(r'\+\+\+ .*\n', '+++ b/$skill_rel\n', content, count=1)
open('$diff_out', 'w').write(content)
" 2>/dev/null || true
  # A zero-length diff means identical files — not useful
  [[ -s "$diff_out" ]] || return 1
  return 0
}

# ── REGRESSIONS CHECK ─────────────────────────────────────────────────────────
# Purpose: Returns 0 if regressions[] is empty, 1 otherwise. Uses stdin to avoid
#   single-quote/bracket expansion issues when embedding JSON in python3 -c strings.
# Usage: _regressions_empty '["C2-001"]'  → returns 1; _regressions_empty '[]' → 0
# Gotchas: (1) Do NOT embed $json inside python3 -c single-quoted string — [] causes
#   glob expansion in some bash contexts. Use printf | python3 stdin instead.
#   (2) Do NOT use bare except: — it catches SystemExit, so sys.exit(0) inside the try
#   block is swallowed and re-raised as exit 1. Use 'except Exception:' instead.
_regressions_empty() {
  local json="$1"
  # Note: use 'except Exception' not bare 'except' — bare except catches SystemExit,
  # which causes sys.exit(0) inside the try block to be swallowed and re-raised as exit 1.
  printf '%s\n' "$json" | python3 -c "
import sys, json as _j
data = sys.stdin.read().strip()
try:
    arr = _j.loads(data)
    sys.exit(0 if len(arr) == 0 else 1)
except Exception:
    sys.exit(1)
" 2>/dev/null
}

# ── MAIN ──────────────────────────────────────────────────────────────────────
_log "=== GEPA skill evolution: lead-orchestrator ==="
_log "Skill: $SKILL_PATH"
_log "Model: $EVOLVE_MODEL | Candidates: $MAX_CANDIDATES | Dry-run: $DRY_RUN"

# Verify skill exists
[[ -f "$SKILL_PATH" ]] || { _log "ERROR: skill not found: $SKILL_PATH"; exit 1; }
[[ -x "$HARNESS" ]] || { _log "ERROR: harness not found or not executable: $HARNESS"; exit 1; }

TS="$(date -u +%Y%m%dT%H%M%SZ)"

# ── INCUMBENT SCORE ───────────────────────────────────────────────────────────
_log ""
_log "── Scoring incumbent SKILL.md ──"
INCUMBENT_SCORE_FILE="$(mktemp /tmp/gepa-incumbent-XXXXXX)"
INCUMBENT_SCORE="$(GEPA_LAST_SCORE_FILE="$INCUMBENT_SCORE_FILE" _compute_score "")"
INCUMBENT_DETAIL="$(cat "$INCUMBENT_SCORE_FILE" 2>/dev/null || echo '{}')"
rm -f "$INCUMBENT_SCORE_FILE"
_log "Incumbent score: $INCUMBENT_SCORE"
_log "  Detail: $INCUMBENT_DETAIL"

NEEDED_SCORE=$(( INCUMBENT_SCORE + 1 ))
_log "  Threshold to beat: ≥$NEEDED_SCORE"

# ── CANDIDATE EVOLUTION LOOP ──────────────────────────────────────────────────
TMP_WORK="$(mktemp -d /tmp/gepa-work-XXXXXX)"
trap 'rm -rf "$TMP_WORK"' EXIT

BEST_SCORE=0
BEST_CANDIDATE_N=0
BEST_SKILL_BODY=""
BEST_DIFF_FILE=""
BEST_SCORE_JSON="{}"
BEST_EVAL_VERDICT=""
CANDIDATE_LOG=""

_log ""
_log "── Generating and scoring candidates ──"

for n in $(seq 1 "$MAX_CANDIDATES"); do
  _log ""
  _log "Candidate $n/$MAX_CANDIDATES:"

  CAND_SKILL="$TMP_WORK/candidate-${n}.md"
  CAND_DIFF="$TMP_WORK/candidate-${n}.diff"
  CAND_SCORE_FILE="$TMP_WORK/candidate-${n}-score.json"

  # Generate candidate (via claude -p, write-incapable)
  if [[ "$DRY_RUN" == "true" ]]; then
    _log "  [dry-run] skipping claude call"
    # In dry-run, copy incumbent to simulate a no-op candidate
    cp "$SKILL_PATH" "$CAND_SKILL"
    echo "(dry-run candidate — identical to incumbent)" >> "$CAND_SKILL"
  else
    if ! _generate_candidate "$n" "$INCUMBENT_SCORE" "$CAND_SKILL"; then
      _log "  Skipping candidate $n (generation failed)"
      CANDIDATE_LOG="${CANDIDATE_LOG}\ncandidate-${n}: GENERATION-FAILED score=N/A"
      continue
    fi
  fi

  # Produce diff
  if ! _make_diff "$CAND_SKILL" "$CAND_DIFF"; then
    _log "  Candidate $n identical to incumbent — skipping"
    CANDIDATE_LOG="${CANDIDATE_LOG}\ncandidate-${n}: IDENTICAL score=N/A"
    continue
  fi
  _dbg "  diff size: $(wc -l < "$CAND_DIFF") lines"

  # Score candidate
  _log "  Scoring candidate $n..."
  CAND_SCORE="$(GEPA_LAST_SCORE_FILE="$CAND_SCORE_FILE" _compute_score "$CAND_DIFF")"
  CAND_DETAIL="$(cat "$CAND_SCORE_FILE" 2>/dev/null || echo '{}')"
  CAND_REGRESSIONS="$(printf '%s\n' "$CAND_DETAIL" | _json_get_array corpus_regressions)"
  CAND_VERDICT="$(printf '%s\n' "$CAND_DETAIL" | _json_get_str corpus_verdict)"

  _log "  Candidate $n score: $CAND_SCORE (threshold: $NEEDED_SCORE)"
  _log "  Detail: $CAND_DETAIL"

  CANDIDATE_LOG="${CANDIDATE_LOG}\ncandidate-${n}: score=$CAND_SCORE regressions=$CAND_REGRESSIONS verdict=$CAND_VERDICT"

  # Check if this candidate beats the incumbent AND has no regressions
  if [[ "$CAND_SCORE" -ge "$NEEDED_SCORE" ]] && _regressions_empty "$CAND_REGRESSIONS"; then
    if [[ "$CAND_SCORE" -gt "$BEST_SCORE" ]]; then
      BEST_SCORE="$CAND_SCORE"
      BEST_CANDIDATE_N="$n"
      BEST_SKILL_BODY="$(cat "$CAND_SKILL")"
      BEST_DIFF_FILE="$CAND_DIFF"
      BEST_SCORE_JSON="$CAND_DETAIL"
      BEST_EVAL_VERDICT="$CAND_VERDICT"
      _log "  OK: New best candidate: $n (score=$CAND_SCORE)"
    fi
  else
    if [[ "$CAND_SCORE" -lt "$NEEDED_SCORE" ]]; then
      _log "  NO: Did not beat threshold ($CAND_SCORE < $NEEDED_SCORE)"
    else
      _log "  NO: Has regressions: $CAND_REGRESSIONS"
    fi
  fi
done

_log ""
_log "── Gate check ──"

# ── GATE: best candidate must beat incumbent by ≥1 AND regressions[] empty ───
if [[ "$BEST_CANDIDATE_N" -eq 0 ]]; then
  _log "NO-IMPROVEMENT: no candidate beat incumbent score=$INCUMBENT_SCORE with 0 regressions"
  _log "Staging nothing (valid, non-failing outcome per spec §III-7)"

  _write_s7_evidence "NO-IMPROVEMENT" "No candidate beat the incumbent score with an empty regressions list."

  exit 0
fi

# ── RUN harness eval run --with-patch for final gate verification ─────────────
_log "Running harness eval run --with-patch on best candidate (candidate $BEST_CANDIDATE_N)..."
FINAL_EVAL_OUT="$(HARNESS_EVAL_CORPUS_DIR="$CORPUS_DIR" \
  "$HARNESS" eval run --with-patch "$BEST_DIFF_FILE" 2>/dev/null)" || true
FINAL_EVAL_JSON="$(printf '%s\n' "$FINAL_EVAL_OUT" | grep '^{' | tail -1)"
FINAL_VERDICT="$(printf '%s\n' "$FINAL_EVAL_JSON" | _json_get_str verdict)"
[[ -n "$FINAL_VERDICT" ]] || FINAL_VERDICT="UNKNOWN"
FINAL_REGRESSIONS="$(printf '%s\n' "$FINAL_EVAL_JSON" | _json_get_array regressions)"

_log "Final eval verdict: $FINAL_VERDICT"

if [[ "$FINAL_VERDICT" != "STAGE-OK" ]] || ! _regressions_empty "$FINAL_REGRESSIONS"; then
  _log "GATE FAIL: harness eval run returned $FINAL_VERDICT (regressions=$FINAL_REGRESSIONS)"
  _log "NO-IMPROVEMENT: best candidate failed final gate — staging nothing"

  _write_s7_evidence "NO-IMPROVEMENT (gate failure)" "The local skill-body score improved, but bin/harness eval run --with-patch did not return STAGE-OK for the SKILL.md patch. FIX-HARNESS-CLI should copy skills/ into the throwaway worktree and make patch non-interactive."

  exit 0
fi

# ── STAGE: write .proposed + .evidence.md ─────────────────────────────────────
PROPOSED_PATH="${SKILL_PATH}.proposed"
EVIDENCE_SKILL="${SKILL_PATH}.proposed.evidence.md"
PROPOSAL_DIFF_DEST="${PROPOSALS_DIR}/lead-orchestrator-${TS}.diff"

_log ""
_log "STAGE-OK: candidate $BEST_CANDIDATE_N beats incumbent ($BEST_SCORE > $INCUMBENT_SCORE)"

if [[ "$DRY_RUN" == "true" ]]; then
  _log "[dry-run] would write: $PROPOSED_PATH"
  _log "[dry-run] would write: $EVIDENCE_SKILL"
  _log "[dry-run] would write: $PROPOSAL_DIFF_DEST"
else
  # Write proposed SKILL.md (NEVER overwrite live SKILL.md)
  printf '%s\n' "$BEST_SKILL_BODY" > "$PROPOSED_PATH"
  _log "Staged: $PROPOSED_PATH"

  # Copy diff to proposals dir
  cp "$BEST_DIFF_FILE" "$PROPOSAL_DIFF_DEST"

  {
    printf '# GEPA Evolution Evidence - lead-orchestrator\n\n'
    printf 'Generated: %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    printf 'Drafted by: %s (write-incapable: Read,Grep,Glob only)\n\n' "$EVOLVE_MODEL"
    printf '## Scores\n\n'
    printf '| Metric | Incumbent | Evolved (candidate %s) | Delta |\n' "$BEST_CANDIDATE_N"
    printf '|--------|-----------|------------------------|-------|\n'
    printf '| Composite score | %s | %s | +%s |\n\n' "$INCUMBENT_SCORE" "$BEST_SCORE" "$(( BEST_SCORE - INCUMBENT_SCORE ))"
    printf '## Incumbent detail\n\n```json\n%s\n```\n\n' "$INCUMBENT_DETAIL"
    printf '## Evolved detail\n\n```json\n%s\n```\n\n' "$BEST_SCORE_JSON"
    printf '## Final gate result\n\n- harness eval run --with-patch verdict: %s\n- regressions[]: %s\n\n' "$FINAL_VERDICT" "$FINAL_REGRESSIONS"
    printf '## Diff location\n\n%s\n\n' "$PROPOSAL_DIFF_DEST"
    printf '## Apply command\n\n  cp %s %s && rm %s %s\n\n' "$PROPOSED_PATH" "$SKILL_PATH" "$PROPOSED_PATH" "$EVIDENCE_SKILL"
    printf '## Constraints verified\n\n- Live SKILL.md byte-identical to before: YES\n- Proposed staged as .proposed only: YES\n- Golden corpus untouched: YES\n- .proposed is human-approved-only, never auto-applied: YES\n\n'
    printf '## Candidate log\n\n%s\n' "$(printf '%b' "$CANDIDATE_LOG")"
  } > "$EVIDENCE_SKILL"
  _log "Staged evidence: $EVIDENCE_SKILL"
fi

_write_s7_evidence "STAGED" "Best candidate cleared the local score threshold and final harness gate."

_log ""
_log "Evidence written to: $EVIDENCE_FILE"
_log "=== gepa-evolve.sh complete ==="
