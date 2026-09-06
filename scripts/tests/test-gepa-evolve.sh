#!/usr/bin/env bash
# ABOUTME: TDD test suite for gepa-evolve.sh (Pillar III §III-7 GEPA skill evolution).
# ABOUTME: Uses a MOCK claude shim (no real tokens burned). Covers ≥5 cases:
# ABOUTME:   T1. Scorer deterministic (same input → same score)
# ABOUTME:   T2. Pipeline completes without error (basic smoke)
# ABOUTME:   T3. Worse candidate (empty output) → NO-IMPROVEMENT, .proposed not created
# ABOUTME:   T4. Regressions in eval → gate blocks staging (STAGE-REFUSED check)
# ABOUTME:   T5. Live SKILL.md byte-identical after all tests (never modified)
# ABOUTME:   T6. Identical candidate → pipeline detects no diff → NO-IMPROVEMENT
# ABOUTME:   T7. _regressions_empty function correct for empty + non-empty arrays
# ABOUTME: Usage: bash scripts/tests/test-gepa-evolve.sh
# ABOUTME: BSD/macOS compatible. All state isolated to $TMP.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAUDE_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
EVOLVE_SH="${CLAUDE_DIR}/scripts/flywheel/gepa-evolve.sh"
GOLDEN_BUILDER="${CLAUDE_DIR}/scripts/flywheel/build-golden-traces.sh"
HARNESS="${HARNESS_BIN:-${HOME}/.claude/bin/harness}"
SKILL_PATH="${CLAUDE_DIR}/skills/lead-orchestrator/SKILL.md"
CORPUS_DIR="${HARNESS_EVAL_CORPUS_DIR:-${CLAUDE_DIR}/evals/incidents}"

PASS=0; FAIL=0; SKIP=0
TMP="$(mktemp -d /tmp/test-gepa-evolve-XXXXXX)"
trap 'rm -rf "$TMP"' EXIT
export HARNESS_GOV_STATE_DIR="${HARNESS_GOV_STATE_DIR:-$TMP/gov-state}"
export HARNESS_GOLDEN_DIR="${HARNESS_GOLDEN_DIR:-$HARNESS_GOV_STATE_DIR/eval-corpus/golden-traces}"
mkdir -p "$HARNESS_GOV_STATE_DIR"
touch "$HARNESS_GOV_STATE_DIR/.active"

_ok()   { echo "PASS: $1"; PASS=$(( PASS + 1 )); }
_fail() { echo "FAIL: $1 — $2"; FAIL=$(( FAIL + 1 )); }
_skip() { echo "SKIP: $1 — $2"; SKIP=$(( SKIP + 1 )); }

echo "========================================================================"
echo "test-gepa-evolve.sh — GEPA skill evolution test suite"
echo "========================================================================"
echo ""

# ── Prerequisites ─────────────────────────────────────────────────────────────
if [[ ! -f "$EVOLVE_SH" ]]; then
  _fail "gepa-evolve.sh exists" "not found at $EVOLVE_SH"; echo "Results: PASS=$PASS  FAIL=$FAIL  SKIP=$SKIP"; exit 1
fi
if [[ ! -x "$HARNESS" ]]; then
  _fail "harness binary present" "not found at $HARNESS"; echo "Results: PASS=$PASS  FAIL=$FAIL  SKIP=$SKIP"; exit 1
fi
if [[ ! -f "$SKILL_PATH" ]]; then
  _fail "SKILL.md present" "not found at $SKILL_PATH"; echo "Results: PASS=$PASS  FAIL=$FAIL  SKIP=$SKIP"; exit 1
fi
if [[ ! -x "$GOLDEN_BUILDER" ]]; then
  _fail "golden trace builder executable" "not found/executable at $GOLDEN_BUILDER"; echo "Results: PASS=$PASS  FAIL=$FAIL  SKIP=$SKIP"; exit 1
fi

BUILD_OUT="$(HARNESS_GOLDEN_DIR="$HARNESS_GOLDEN_DIR" "$GOLDEN_BUILDER" 2>&1)" || true
if [[ -d "$HARNESS_GOLDEN_DIR" ]]; then
  _ok "setup: golden traces built in isolated state"
else
  _fail "setup: golden traces built" "${BUILD_OUT:0:300}"
fi

# Record live SKILL.md hash for untouched proof
SKILL_HASH_BEFORE="$(shasum -a 256 "$SKILL_PATH" | cut -d' ' -f1)"

# ── Build mock claude shim ────────────────────────────────────────────────────
# Purpose: Produces different SKILL.md bodies depending on MOCK_CLAUDE_MODE env.
# Modes: better=adds a new section; worse=empty output (fails generation); identical=verbatim copy
SHIM_PATH="$TMP/mock-claude"
cat > "$SHIM_PATH" <<'SHIM_EOF'
#!/usr/bin/env bash
# Mock claude shim — reads stdin (prompt), responds by mode without calling any API.
mode="${MOCK_CLAUDE_MODE:-identical}"
skill_path="${MOCK_SKILL_PATH:-}"
case "$mode" in
  better)
    # Valid SKILL.md with one extra section appended
    cat "$skill_path"
    printf '\n## Context Budget Emergency Protocol\nIf context limit is near, checkpoint immediately.\n'
    ;;
  worse)
    # Empty output — simulates generation failure or timeout
    exit 0
    ;;
  identical)
    # Verbatim copy of incumbent — produces zero diff → NO-IMPROVEMENT
    cat "$skill_path"
    ;;
  *)
    cat "$skill_path"
    ;;
esac
SHIM_EOF
chmod +x "$SHIM_PATH"

# ── Inline scorer helper (no script sourcing — avoids main execution) ──────────
# Purpose: Deterministic golden-score computation that mirrors _compute_score()
#   logic in gepa-evolve.sh without sourcing the full script.
# Usage: _score [diff_file]
# Output: integer score on stdout
_score() {
  local diff_file="${1:-}"
  local replay_pass corpus_passes skill_body_passes eval_out eval_json score body_file patch_root

  # Golden trace replay (always baseline — skill text doesn't affect guard scripts)
  replay_pass="$(HARNESS_GOLDEN_DIR="$HARNESS_GOLDEN_DIR" "$HARNESS" replay --all-golden 2>/dev/null | awk '/Results:/ { for (i=1;i<=NF;i++) if ($i ~ /^PASS=/) { sub(/^PASS=/,"",$i); print $i; exit } }')"
  replay_pass="${replay_pass:-0}"

  # Eval corpus (with or without patch)
  if [[ -n "$diff_file" && -f "$diff_file" ]]; then
    eval_out="$(HARNESS_EVAL_CORPUS_DIR="$CORPUS_DIR" "$HARNESS" eval run --with-patch "$diff_file" 2>/dev/null)" || true
  else
    eval_out="$(HARNESS_EVAL_CORPUS_DIR="$CORPUS_DIR" "$HARNESS" eval run 2>/dev/null)" || true
  fi
  eval_json="$(printf '%s\n' "$eval_out" | grep '^{' | tail -1)"
  corpus_passes="$(printf '%s\n' "$eval_json" | python3 -c \
    "import sys,json; d=json.load(sys.stdin); print(d.get('passed',0))" 2>/dev/null || echo 0)"

  patch_root="$TMP/score-patch-root-$$"
  rm -rf "$patch_root"
  mkdir -p "$patch_root/skills/lead-orchestrator"
  cp "$SKILL_PATH" "$patch_root/skills/lead-orchestrator/SKILL.md"
  if [[ -n "$diff_file" && -f "$diff_file" ]]; then
    ( cd "$patch_root" && patch --batch -p1 < "$diff_file" >/dev/null 2>&1 ) || true
  fi
  body_file="$patch_root/skills/lead-orchestrator/SKILL.md"
  skill_body_passes="$(python3 - "$body_file" <<'PY'
import re
import sys
body = open(sys.argv[1], encoding="utf-8").read()
checks = [
    [r"ORCHESTRATOR SPAWNS SUBAGENTS", r"ORCHESTRATOR NEVER CODES"],
    [r"NOTHING REACHES THE USER UNVERIFIED", r"verification\.md"],
    [r"QA/verification artifacts are SUBAGENT-authored", r"orchestrator NEVER writes"],
    [r"hook blocks a spawn", r"re-spawn immediately"],
    [r"Context Budget", r"Checkpoint", r"compaction"],
    [r"No \"done / complete / passing / deployed\" claim", r"verification\.md"],
]
print(sum(1 for patterns in checks if all(re.search(p, body, re.I) for p in patterns)))
PY
)"
  skill_body_passes="${skill_body_passes:-0}"
  rm -rf "$patch_root"

  score=$(( replay_pass * 2 + corpus_passes + skill_body_passes * 3 ))
  printf '%d' "$score"
}

_skill_diff() {
  local candidate_file="$1" diff_out="$2"
  diff -u "$SKILL_PATH" "$candidate_file" > "$diff_out" 2>/dev/null || true
  python3 - "$diff_out" <<'PY'
import re
import sys
path = sys.argv[1]
content = open(path).read()
content = re.sub(r"^--- .*\n", "--- a/skills/lead-orchestrator/SKILL.md\n", content, count=1, flags=re.M)
content = re.sub(r"^\+\+\+ .*\n", "+++ b/skills/lead-orchestrator/SKILL.md\n", content, count=1, flags=re.M)
open(path, "w").write(content)
PY
}

# ── _regressions_empty helper (mirrors logic in gepa-evolve.sh) ───────────────
# Purpose: Returns 0 if regressions[] JSON array is empty, 1 otherwise.
# Usage: _regressions_empty '[]'  → 0; _regressions_empty '["C2-001"]' → 1
# Gotchas: Use stdin not embedded $json to avoid bracket-glob expansion in pipefail mode.
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
except Exception: sys.exit(1)
" 2>/dev/null
}

# ═══════════════════════════════════════════════════════════════════════════════
# T1: Scorer deterministic — same input → same score (two independent runs)
# ═══════════════════════════════════════════════════════════════════════════════
echo "── T1: Scorer determinism ──"
SCORE_A="$(_score "")"
SCORE_B="$(_score "")"
if [[ -n "$SCORE_A" && "$SCORE_A" == "$SCORE_B" && "$SCORE_A" =~ ^[0-9]+$ ]]; then
  _ok "T1: scorer deterministic (score=$SCORE_A both runs)"
else
  _fail "T1: scorer deterministic" "run-A='$SCORE_A' run-B='$SCORE_B'"
fi

# ═══════════════════════════════════════════════════════════════════════════════
# T2: Pipeline completes without error (smoke test with dry-run + better mode)
# ═══════════════════════════════════════════════════════════════════════════════
echo ""
echo "── T2: Pipeline smoke test ──"
{
  RUN2="$TMP/state-t2"
  OUT2="$(
    MOCK_CLAUDE_MODE=better \
    MOCK_SKILL_PATH="$SKILL_PATH" \
    CLAUDE_SHIM="$SHIM_PATH" \
    STATE="$RUN2" \
    HARNESS_BIN="$HARNESS" \
    HARNESS_EVAL_CORPUS_DIR="$CORPUS_DIR" \
    GEPA_MODEL="mock" \
    GEPA_MAX_CANDIDATES=1 \
    GEPA_TIMEOUT_SECS=10 \
    bash "$EVOLVE_SH" --dry-run 2>&1
  )" || true

  if printf '%s\n' "$OUT2" | grep -qE "(gepa-evolve.*complete|NO-IMPROVEMENT)"; then
    _ok "T2: pipeline ran to completion (dry-run mode)"
  else
    _fail "T2: pipeline ran to completion" "last 3 lines: $(printf '%s\n' "$OUT2" | tail -3 | tr '\n' '|')"
  fi
}

# ═══════════════════════════════════════════════════════════════════════════════
# T3: Worse candidate (empty output) → NO-IMPROVEMENT + no .proposed file
# ═══════════════════════════════════════════════════════════════════════════════
echo ""
echo "── T3: Worse candidate → NO-IMPROVEMENT ──"
{
  RUN3="$TMP/state-t3"
  OUT3="$(
    MOCK_CLAUDE_MODE=worse \
    MOCK_SKILL_PATH="$SKILL_PATH" \
    CLAUDE_SHIM="$SHIM_PATH" \
    STATE="$RUN3" \
    HARNESS_BIN="$HARNESS" \
    HARNESS_EVAL_CORPUS_DIR="$CORPUS_DIR" \
    GEPA_MODEL="mock" \
    GEPA_MAX_CANDIDATES=1 \
    GEPA_TIMEOUT_SECS=10 \
    bash "$EVOLVE_SH" 2>&1
  )" || true

  if printf '%s\n' "$OUT3" | grep -q "NO-IMPROVEMENT"; then
    _ok "T3a: worse candidate → NO-IMPROVEMENT in output"
  else
    _fail "T3a: worse candidate → NO-IMPROVEMENT" "output: $(printf '%s\n' "$OUT3" | tail -3 | tr '\n' '|')"
  fi

  PROPOSED="${SKILL_PATH}.proposed"
  if [[ ! -f "$PROPOSED" ]]; then
    _ok "T3b: .proposed not created on NO-IMPROVEMENT"
  else
    _fail "T3b: .proposed not created" "file exists: $PROPOSED"
    rm -f "$PROPOSED"
  fi
}

# ═══════════════════════════════════════════════════════════════════════════════
# T4: Regressions in eval → harness returns STAGE-REFUSED for sabotage diff
#     The gepa-evolve gate checks for STAGE-OK + empty regressions[].
#     We verify the harness mechanism works correctly.
# ═══════════════════════════════════════════════════════════════════════════════
echo ""
echo "── T4: Regressions gate ──"
{
  ORIG_GUARD="${CLAUDE_DIR}/scripts/completion-claim-guard.sh"
  if [[ ! -f "$ORIG_GUARD" ]]; then
    _skip "T4: regression gate" "completion-claim-guard.sh not found"
  else
    PATCHED_GUARD="$TMP/guard-patched.sh"
    cp "$ORIG_GUARD" "$PATCHED_GUARD"
    # Neuter the detection regex — replaces CLAIM= with CLAIM_DISABLED= (the completion claim pattern)
    python3 -c "
c = open('$PATCHED_GUARD').read()
# Replace the CLAIM regex assignment to prevent any completion-claim matching
c = c.replace(\"CLAIM='\", \"CLAIM_DISABLED='\", 1)
open('$PATCHED_GUARD', 'w').write(c)
" 2>/dev/null || true

    SABOTAGE_DIFF="$TMP/sabotage.diff"
    diff -u "$ORIG_GUARD" "$PATCHED_GUARD" > "$SABOTAGE_DIFF" 2>/dev/null || true
    # Fix patch paths for patch -p1
    python3 -c "
import re
c = open('$SABOTAGE_DIFF').read()
c = re.sub(r'^--- .*\n', '--- a/scripts/completion-claim-guard.sh\n', c, count=1, flags=re.M)
c = re.sub(r'^\+\+\+ .*\n', '+++ b/scripts/completion-claim-guard.sh\n', c, count=1, flags=re.M)
open('$SABOTAGE_DIFF', 'w').write(c)
" 2>/dev/null || true

    if [[ -s "$SABOTAGE_DIFF" ]]; then
      EVAL_OUT4="$(HARNESS_EVAL_CORPUS_DIR="$CORPUS_DIR" \
        "$HARNESS" eval run --with-patch "$SABOTAGE_DIFF" 2>/dev/null)" || true
      EVAL_JSON4="$(printf '%s\n' "$EVAL_OUT4" | grep '^{' | tail -1)"
      VERDICT4="$(printf '%s\n' "$EVAL_JSON4" | python3 -c \
        "import sys,json; d=json.load(sys.stdin); print(d.get('verdict',''))" 2>/dev/null || echo '')"
      REGS4="$(printf '%s\n' "$EVAL_JSON4" | python3 -c \
        "import sys,json; d=json.load(sys.stdin); print(json.dumps(d.get('regressions',[])))" 2>/dev/null || echo '[]')"

      if [[ "$VERDICT4" == "STAGE-REFUSED" ]]; then
        _ok "T4a: sabotage diff → STAGE-REFUSED (gate would block)"
      elif ! _regressions_empty "$REGS4"; then
        _ok "T4a: sabotage diff → non-empty regressions[] (gate would block; verdict=$VERDICT4)"
      else
        # Verify regressions_empty logic itself is correct
        if ! python3 -c "import sys,json; arr=json.loads('[\"C2-002\"]'); sys.exit(0 if arr else 1)" 2>/dev/null; then
          _ok "T4a: _regressions_empty logic correct for non-empty array"
        else
          _fail "T4a: regression gate" "sabotage produced verdict=$VERDICT4 regs=$REGS4 — guard may not detect DONE_PAT variable name"
        fi
      fi

      # Also verify regressions_empty correctly handles both cases
      if _regressions_empty "[]"; then
        _ok "T4b: _regressions_empty([]) → 0 (empty is clean)"
      else
        _fail "T4b: _regressions_empty([]) should return 0" "returned 1"
      fi
      if ! _regressions_empty '["C2-002"]'; then
        _ok "T4c: _regressions_empty([\"C2-002\"]) → 1 (not empty → gate blocks)"
      else
        _fail "T4c: _regressions_empty([\"C2-002\"]) should return 1" "returned 0"
      fi
    else
      _skip "T4: regression gate" "could not create sabotage diff (files may be identical)"
    fi
  fi
}

# ═══════════════════════════════════════════════════════════════════════════════
# T5: Live SKILL.md byte-identical after all tests — never modified
# ═══════════════════════════════════════════════════════════════════════════════
echo ""
echo "── T5: Live SKILL.md untouched ──"
{
  SKILL_HASH_AFTER="$(shasum -a 256 "$SKILL_PATH" | cut -d' ' -f1)"
  if [[ "$SKILL_HASH_BEFORE" == "$SKILL_HASH_AFTER" ]]; then
    _ok "T5a: SKILL.md byte-identical (hash=$SKILL_HASH_BEFORE)"
  else
    _fail "T5a: SKILL.md untouched" "hash changed before=$SKILL_HASH_BEFORE after=$SKILL_HASH_AFTER"
  fi

  # Check no stray .proposed file
  PROPOSED="${SKILL_PATH}.proposed"
  if [[ ! -f "$PROPOSED" ]]; then
    _ok "T5b: no stray .proposed file after tests"
  else
    _fail "T5b: no stray .proposed" ".proposed exists: $PROPOSED"
    rm -f "$PROPOSED"
  fi

  # Git status check
  GIT_DIFF="$(git -C "${CLAUDE_DIR}" diff --name-only HEAD -- "skills/lead-orchestrator/SKILL.md" 2>/dev/null || true)"
  if [[ -z "$GIT_DIFF" ]]; then
    _ok "T5c: git diff shows SKILL.md clean vs HEAD"
  else
    _fail "T5c: git status clean" "diff: $GIT_DIFF"
  fi
}

# ═══════════════════════════════════════════════════════════════════════════════
# T6: Identical candidate → pipeline reports NO-IMPROVEMENT (no diff → skip)
# ═══════════════════════════════════════════════════════════════════════════════
echo ""
echo "── T6: Identical candidate → NO-IMPROVEMENT ──"
{
  RUN6="$TMP/state-t6"
  OUT6="$(
    MOCK_CLAUDE_MODE=identical \
    MOCK_SKILL_PATH="$SKILL_PATH" \
    CLAUDE_SHIM="$SHIM_PATH" \
    STATE="$RUN6" \
    HARNESS_BIN="$HARNESS" \
    HARNESS_EVAL_CORPUS_DIR="$CORPUS_DIR" \
    GEPA_MODEL="mock" \
    GEPA_MAX_CANDIDATES=1 \
    GEPA_TIMEOUT_SECS=10 \
    bash "$EVOLVE_SH" 2>&1
  )" || true

  if printf '%s\n' "$OUT6" | grep -q "NO-IMPROVEMENT"; then
    _ok "T6: identical candidate → NO-IMPROVEMENT"
  else
    _fail "T6: identical candidate → NO-IMPROVEMENT" "$(printf '%s\n' "$OUT6" | tail -3 | tr '\n' '|')"
  fi
}

# ═══════════════════════════════════════════════════════════════════════════════
# T7: Scoring harness returns numeric output (sanity / regression guard)
# ═══════════════════════════════════════════════════════════════════════════════
echo ""
echo "── T7: Scoring harness numeric output ──"
{
  SCORE7="$(_score "")"
  if [[ "$SCORE7" =~ ^[0-9]+$ && "$SCORE7" -ge 0 ]]; then
    _ok "T7: scoring harness returns numeric score: $SCORE7"
  else
    _fail "T7: scoring harness numeric" "got: '$SCORE7'"
  fi

  # Score must be >= 10 given 5 golden traces all PASS (5*2=10) and ≥0 corpus
  if [[ "$SCORE7" -ge 10 ]]; then
    _ok "T7b: score $SCORE7 ≥ 10 (consistent with 5 golden PASS)"
  else
    _fail "T7b: score reflects 5 golden PASS" "score=$SCORE7 < 10 — unexpected"
  fi
}

# ═══════════════════════════════════════════════════════════════════════════════
# T8: Skill-body scoring is not a no-op — improved body beats degraded body
# ═══════════════════════════════════════════════════════════════════════════════
echo ""
echo "── T8: Skill-body score depends on SKILL.md text ──"
{
  IMPROVED_SKILL="$TMP/improved-skill.md"
  DEGRADED_SKILL="$TMP/degraded-skill.md"
  IMPROVED_DIFF="$TMP/improved-skill.diff"
  DEGRADED_DIFF="$TMP/degraded-skill.diff"

  cat "$SKILL_PATH" > "$IMPROVED_SKILL"
  printf '\n## GEPA Incident-Replay Reinforcement\n' >> "$IMPROVED_SKILL"
  printf 'If context limit is near, use the Context Budget Emergency Protocol: Checkpoint immediately before compaction and re-spawn immediately after any hook blocks a spawn.\n' >> "$IMPROVED_SKILL"

  python3 - "$SKILL_PATH" "$DEGRADED_SKILL" <<'PY'
import sys
body = open(sys.argv[1], encoding="utf-8").read()
for token in [
    "ORCHESTRATOR SPAWNS SUBAGENTS",
    "ORCHESTRATOR NEVER CODES",
    "NOTHING REACHES THE USER UNVERIFIED",
    "QA/verification artifacts are SUBAGENT-authored",
    "Context Budget",
    "verification.md",
]:
    body = body.replace(token, "REMOVED")
open(sys.argv[2], "w", encoding="utf-8").write(body)
PY

  _skill_diff "$IMPROVED_SKILL" "$IMPROVED_DIFF"
  _skill_diff "$DEGRADED_SKILL" "$DEGRADED_DIFF"

  IMPROVED_SCORE="$(_score "$IMPROVED_DIFF")"
  DEGRADED_SCORE="$(_score "$DEGRADED_DIFF")"

  if [[ "$IMPROVED_SCORE" =~ ^[0-9]+$ && "$DEGRADED_SCORE" =~ ^[0-9]+$ && "$IMPROVED_SCORE" -gt "$DEGRADED_SCORE" ]]; then
    _ok "T8: improved body score $IMPROVED_SCORE > degraded body score $DEGRADED_SCORE"
  else
    _fail "T8: skill-body score should distinguish candidates" "improved=$IMPROVED_SCORE degraded=$DEGRADED_SCORE"
  fi
}

echo ""
echo "========================================================================"
echo "Results: PASS=$PASS  FAIL=$FAIL  SKIP=$SKIP"
echo "========================================================================"
[[ "$FAIL" -eq 0 ]]
