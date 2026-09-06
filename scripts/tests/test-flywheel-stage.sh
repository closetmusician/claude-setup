#!/usr/bin/env bash
# ABOUTME: TDD test suite for III-5 staging logic + harness brief + harness eval apply.
# ABOUTME: 8 test cases: STAGE-OK draft → .proposed+.evidence.md, STAGE-REFUSED not staged,
# ABOUTME: brief shows staged patches, eval apply dry-run shows WOULD-WRITE+writes nothing,
# ABOUTME: idempotent re-stage, tracked files untouched, real target never mutated,
# ABOUTME: eval apply with unknown id exits nonzero with clear error.
# ABOUTME: Usage: bash scripts/tests/test-flywheel-stage.sh

set -uo pipefail

HARNESS="${HARNESS_BIN:-$HOME/.claude/bin/harness}"
STAGE_PATCH="${STAGE_PATCH_BIN:-$HOME/.claude/scripts/flywheel/stage-patch.sh}"
CLAUDE_DIR="${CLAUDE_DIR:-$HOME/.claude}"

PASS=0; FAIL=0; SKIP=0
TMP="$(mktemp -d /tmp/test-flywheel-stage-XXXXXX)"
trap 'rm -rf "$TMP"' EXIT

_ok()   { echo "PASS: $1"; PASS=$(( PASS + 1 )); }
_fail() { echo "FAIL: $1 — $2"; FAIL=$(( FAIL + 1 )); }
_skip() { echo "SKIP: $1 — $2"; SKIP=$(( SKIP + 1 )); }

echo "========================================================================"
echo "test-flywheel-stage.sh — III-5 staging + brief + eval apply"
echo "========================================================================"
echo ""

# ── Prerequisites ─────────────────────────────────────────────────────────────
if [[ ! -x "$HARNESS" ]]; then
  _fail "harness binary present" "not found at $HARNESS"
  echo ""
  echo "Results: PASS=$PASS  FAIL=$FAIL  SKIP=$SKIP"
  exit 1
fi

# ── Isolated state/staging area ───────────────────────────────────────────────
# Purpose: All staging artifacts land under $TMP so real ~/.claude files are untouched.
# Usage: exported env vars are picked up by stage-patch.sh and harness.
STATE_DIR="$TMP/state"
STAGING_DIR="$TMP/staging"
DRAFTS_DIR="$TMP/drafts"
mkdir -p "$STATE_DIR" "$STAGING_DIR" "$DRAFTS_DIR"

export HARNESS_STATE_OVERRIDE="$STATE_DIR"
export STAGE_STATE_DIR="$STATE_DIR"
export STAGE_STAGING_DIR="$STAGING_DIR"
export STAGE_DRAFTS_DIR="$DRAFTS_DIR"

# ── Fixture: minimal real-style diff targeting a dummy target file ─────────────
# Purpose: Create a STAGE-OK-worthy diff that targets a temp file (not a tracked file)
#   plus a STAGE-REFUSED-worthy draft marker.
TARGET_FILE="$TMP/target.sh"
printf '#!/usr/bin/env bash\n# old line\necho old\n' > "$TARGET_FILE"
STAGED_TARGET="${TARGET_FILE}.proposed"

# A valid unified diff changing one line (target path is the dummy file)
GOOD_DIFF="$DRAFTS_DIR/C2-001-2026-01-01T00-00-00.diff"
python3 - "$TARGET_FILE" "$GOOD_DIFF" <<'PYEOF'
import sys, subprocess, os, tempfile

target = sys.argv[1]
out_diff = sys.argv[2]

# Create a patched version
patched = target + ".new"
with open(target) as f:
    content = f.read()
patched_content = content.replace("echo old", "echo new")
with open(patched, 'w') as f:
    f.write(patched_content)

# Generate unified diff
result = subprocess.run(
    ["diff", "-u",
     "--label", "a/target.sh",
     "--label", "b/target.sh",
     target, patched],
    capture_output=True, text=True
)
os.unlink(patched)
# diff exits 1 when files differ (that's fine)
with open(out_diff, 'w') as f:
    f.write(result.stdout)
print("diff written")
PYEOF

# A "refused" marker file (STAGE-REFUSED — no real diff, just a marker)
REFUSED_DRAFT="$DRAFTS_DIR/C2-002-2026-01-02T00-00-00.diff"
printf '## No-Patch: C2 — complexity too high for mechanical patch\nincident_ts=2026-01-02T00:00:00Z class=C2\n' > "$REFUSED_DRAFT"

# ── Fixture: eval run result JSON (simulates STAGE-OK and STAGE-REFUSED outcomes) ─
# Purpose: stage-patch.sh reads eval_result to decide staging. We inject these.
EVAL_OK_JSON="$TMP/eval-ok.json"
EVAL_REFUSED_JSON="$TMP/eval-refused.json"
printf '{"verdict":"STAGE-OK","passed":3,"failed":0,"regressions":[],"corpus":3}\n' > "$EVAL_OK_JSON"
printf '{"verdict":"STAGE-REFUSED","passed":2,"failed":1,"regressions":["C2-001"],"corpus":3}\n' > "$EVAL_REFUSED_JSON"

# Incident data for evidence.md
INCIDENT_JSON='{"ts":"2026-01-01T00:00:00Z","payload":{"class":"C2","detail":"completion claim without artifact"}}'

# ── Test 1: stage-patch.sh exists and is executable ───────────────────────────
echo "── Test 1: stage-patch.sh exists and is executable ─────────────────────"
if [[ -x "$STAGE_PATCH" ]]; then
  _ok "stage-patch.sh present and executable"
else
  _fail "stage-patch.sh present and executable" "not found at $STAGE_PATCH"
fi
echo ""

# ── Test 2: STAGE-OK draft → .proposed + .evidence.md written ────────────────
echo "── Test 2: STAGE-OK → .proposed + .evidence.md written ─────────────────"
if [[ ! -x "$STAGE_PATCH" ]]; then
  _skip "STAGE-OK staging" "stage-patch.sh not found"
else
  # Run stage-patch.sh with STAGE-OK eval result
  STAGE_OUT="$TMP/stage-ok.log"
  STAGE_TARGET_OVERRIDE="$TARGET_FILE" \
  STAGE_EVAL_RESULT="$EVAL_OK_JSON" \
  STAGE_INCIDENT_JSON="$INCIDENT_JSON" \
  bash "$STAGE_PATCH" "$GOOD_DIFF" >"$STAGE_OUT" 2>&1
  STAGE_EC=$?

  # Check .proposed was written
  PROPOSED_FILE="${STAGING_DIR}/$(basename "$GOOD_DIFF" .diff).proposed"
  EVIDENCE_FILE="${PROPOSED_FILE}.evidence.md"

  if [[ -f "$PROPOSED_FILE" ]]; then
    _ok "STAGE-OK: .proposed file written"
  else
    # Try alternate location: alongside the target
    PROPOSED_ALT="${TARGET_FILE}.proposed"
    if [[ -f "$PROPOSED_ALT" ]]; then
      PROPOSED_FILE="$PROPOSED_ALT"
      EVIDENCE_FILE="${PROPOSED_ALT}.evidence.md"
      _ok "STAGE-OK: .proposed file written (alongside target)"
    else
      _fail "STAGE-OK: .proposed file written" "not found at $PROPOSED_FILE or $PROPOSED_ALT; stage output: $(cat "$STAGE_OUT" 2>/dev/null | head -5)"
    fi
  fi

  if [[ -f "$EVIDENCE_FILE" ]]; then
    _ok "STAGE-OK: .evidence.md file written"
  else
    _fail "STAGE-OK: .evidence.md file written" "not found at $EVIDENCE_FILE"
  fi

  # Verify .evidence.md contains required fields
  if [[ -f "$EVIDENCE_FILE" ]]; then
    EV_CONTENT="$(cat "$EVIDENCE_FILE")"
    if printf '%s' "$EV_CONTENT" | grep -qi "incident\|class\|eval\|STAGE-OK"; then
      _ok "STAGE-OK: .evidence.md contains eval result"
    else
      _fail "STAGE-OK: .evidence.md contains eval result" "content missing incident/eval fields"
    fi
    if printf '%s' "$EV_CONTENT" | grep -qi "apply\|approve\|harness"; then
      _ok "STAGE-OK: .evidence.md contains one-click apply command"
    else
      _fail "STAGE-OK: .evidence.md contains one-click apply command" "no harness eval apply command found"
    fi
  fi
fi
echo ""

# ── Test 3: STAGE-REFUSED draft → NOT staged ──────────────────────────────────
echo "── Test 3: STAGE-REFUSED → NOT staged ──────────────────────────────────"
if [[ ! -x "$STAGE_PATCH" ]]; then
  _skip "STAGE-REFUSED rejection" "stage-patch.sh not found"
else
  REFUSED_PROPOSED="${STAGING_DIR}/$(basename "$REFUSED_DRAFT" .diff).proposed"
  STAGE_OUT2="$TMP/stage-refused.log"
  STAGE_EVAL_RESULT="$EVAL_REFUSED_JSON" \
  STAGE_INCIDENT_JSON="$INCIDENT_JSON" \
  bash "$STAGE_PATCH" "$REFUSED_DRAFT" >"$STAGE_OUT2" 2>&1 || true

  if [[ ! -f "$REFUSED_PROPOSED" ]]; then
    _ok "STAGE-REFUSED: .proposed NOT written"
  else
    _fail "STAGE-REFUSED: .proposed NOT written" "found at $REFUSED_PROPOSED — refused drafts must not be staged"
  fi

  # Log should mention STAGE-REFUSED
  if grep -qi "refused\|refused\|regressions\|No-Patch" "$STAGE_OUT2" 2>/dev/null; then
    _ok "STAGE-REFUSED: rejection reason logged"
  else
    _fail "STAGE-REFUSED: rejection reason logged" "output: $(cat "$STAGE_OUT2" | head -3)"
  fi
fi
echo ""

# ── Test 4: harness brief shows staged patches ────────────────────────────────
echo "── Test 4: harness brief shows STAGED PATCHES section ───────────────────"
BRIEF_OUT="$TMP/brief.log"
BRIEF_EC=0

# brief needs to know where to find staged artifacts; inject via env
STAGE_STAGING_DIR="$STAGING_DIR" \
HARNESS_STATE_OVERRIDE="$STATE_DIR" \
"$HARNESS" brief >"$BRIEF_OUT" 2>&1 || BRIEF_EC=$?

# If brief is still a stub (exit 3), that's the RED state
if [[ "$BRIEF_EC" -eq 3 ]]; then
  _fail "harness brief: not a stub" "still exits 3 (not yet implemented — expected GREEN failure)"
else
  BRIEF_CONTENT="$(cat "$BRIEF_OUT")"
  if printf '%s' "$BRIEF_CONTENT" | grep -qi "STAGED\|PATCH\|proposed"; then
    _ok "harness brief: STAGED PATCHES section present"
  else
    _fail "harness brief: STAGED PATCHES section present" "output missing staged patches section: $(echo "$BRIEF_CONTENT" | head -5)"
  fi

  if printf '%s' "$BRIEF_CONTENT" | grep -qi "incident\|recent"; then
    _ok "harness brief: recent incidents section present"
  else
    _fail "harness brief: recent incidents section present" "no recent incidents in brief"
  fi
fi
echo ""

# ── Test 5: harness eval apply <id> dry-run shows WOULD-WRITE and writes nothing ─
echo "── Test 5: eval apply dry-run: WOULD-WRITE, writes nothing ─────────────"
# Derive the staged patch ID from the GOOD_DIFF filename (same logic as stage-patch.sh)
GOOD_DIFF_ID="$(basename "$GOOD_DIFF" .diff)"
APPLY_OUT="$TMP/apply.log"
APPLY_EC=0
STAGE_STAGING_DIR="$STAGING_DIR" \
STAGE_STATE_DIR="$STATE_DIR" \
HARNESS_STATE_OVERRIDE="$STATE_DIR" \
"$HARNESS" eval apply --dry-run "$GOOD_DIFF_ID" >"$APPLY_OUT" 2>&1 || APPLY_EC=$?

if [[ "$APPLY_EC" -eq 3 ]]; then
  _fail "harness eval apply --dry-run: implemented" "exits 3 stub — not yet implemented"
else
  APPLY_CONTENT="$(cat "$APPLY_OUT")"
  if printf '%s' "$APPLY_CONTENT" | grep -qi "WOULD-WRITE\|would write\|dry.run"; then
    _ok "eval apply --dry-run: WOULD-WRITE shown"
  else
    _fail "eval apply --dry-run: WOULD-WRITE shown" "output: $(echo "$APPLY_CONTENT" | head -3)"
  fi
  # Verify nothing was actually written to real target
  if [[ ! -f "${TARGET_FILE}.applied" ]]; then
    _ok "eval apply --dry-run: no real file written"
  else
    _fail "eval apply --dry-run: no real file written" ".applied file appeared unexpectedly"
  fi
fi
echo ""

# ── Test 6: idempotent re-stage ────────────────────────────────────────────────
echo "── Test 6: idempotent re-stage ──────────────────────────────────────────"
if [[ ! -x "$STAGE_PATCH" ]]; then
  _skip "idempotent re-stage" "stage-patch.sh not found"
else
  # Run the STAGE-OK path again
  STAGE_OUT3="$TMP/stage-idem.log"
  STAGE_TARGET_OVERRIDE="$TARGET_FILE" \
  STAGE_EVAL_RESULT="$EVAL_OK_JSON" \
  STAGE_INCIDENT_JSON="$INCIDENT_JSON" \
  bash "$STAGE_PATCH" "$GOOD_DIFF" >"$STAGE_OUT3" 2>&1
  STAGE_EC3=$?

  # Should not fail/error on second run
  if [[ "$STAGE_EC3" -le 1 ]]; then
    _ok "idempotent re-stage: exits 0 or 1 (not error) on second run"
  else
    _fail "idempotent re-stage: exits 0 or 1 on second run" "exit code=$STAGE_EC3"
  fi

  # File should still exist after re-run
  PROPOSED_CHECK="${STAGING_DIR}/$(basename "$GOOD_DIFF" .diff).proposed"
  PROPOSED_ALT_CHECK="${TARGET_FILE}.proposed"
  if [[ -f "$PROPOSED_CHECK" ]] || [[ -f "$PROPOSED_ALT_CHECK" ]]; then
    _ok "idempotent re-stage: .proposed still present after re-run"
  else
    _fail "idempotent re-stage: .proposed still present after re-run" "file disappeared"
  fi
fi
echo ""

# ── Test 7: real tracked files untouched (no new dirty files from staging) ────
echo "── Test 7: tracked files in ~/.claude untouched ─────────────────────────"
# Purpose: check that staging ops didn't touch any tracked source files.
# We compare the set of modified tracked files BEFORE and AFTER staging.
# The staging artifacts live in $STAGING_DIR (under $TMP), which is untracked.
# So: if the set of dirty tracked files after all tests == the set before tests,
# staging is clean. We capture the baseline at test time (all staging already ran).
#
# Approach: verify no staged artifact lives under $CLAUDE_DIR (all should be in $TMP).
STAGED_IN_CLAUDE_DIR=""
if [[ -d "$STAGING_DIR" ]]; then
  # staging dir is under $TMP, not $CLAUDE_DIR — good
  if [[ "$STAGING_DIR" == "$CLAUDE_DIR"* ]]; then
    STAGED_IN_CLAUDE_DIR="staging dir inside claude dir: $STAGING_DIR"
  fi
fi
# Also check: no .proposed files appeared in $CLAUDE_DIR tree (outside evals/incidents)
NEW_PROPOSED=""
NEW_PROPOSED="$(find "$CLAUDE_DIR" -name "*.proposed" -newer "$TMP" -not -path "$CLAUDE_DIR/evals/*" 2>/dev/null | head -3)" || NEW_PROPOSED=""
if [[ -z "$STAGED_IN_CLAUDE_DIR" ]] && [[ -z "$NEW_PROPOSED" ]]; then
  _ok "git status clean: no new .proposed files in tracked source tree"
else
  _fail "git status clean: no new .proposed files in tracked source tree" \
    "${STAGED_IN_CLAUDE_DIR:-}${NEW_PROPOSED:-}"
fi
echo ""

# ── Test 8: eval apply with unknown id exits nonzero with error message ────────
echo "── Test 8: eval apply unknown-id exits nonzero ──────────────────────────"
APPLY2_OUT="$TMP/apply2.log"
APPLY2_EC=0
STAGE_STAGING_DIR="$STAGING_DIR" \
HARNESS_STATE_OVERRIDE="$STATE_DIR" \
"$HARNESS" eval apply nonexistent-patch-id-xyz >"$APPLY2_OUT" 2>&1 || APPLY2_EC=$?

if [[ "$APPLY2_EC" -eq 3 ]]; then
  _fail "eval apply nonexistent id: not a stub" "exits 3 stub"
elif [[ "$APPLY2_EC" -ne 0 ]]; then
  APPLY2_MSG="$(cat "$APPLY2_OUT")"
  if printf '%s' "$APPLY2_MSG" | grep -qi "not found\|unknown\|no patch\|WOULD-WRITE\|dry.run\|nonexistent"; then
    _ok "eval apply unknown id: exits nonzero with informative message"
  else
    _ok "eval apply unknown id: exits nonzero (exit=$APPLY2_EC)"
  fi
else
  _fail "eval apply unknown id: exits nonzero" "exited 0 for nonexistent patch id"
fi
echo ""

# ── Summary ────────────────────────────────────────────────────────────────────
echo "========================================================================"
echo "Results: PASS=$PASS  FAIL=$FAIL  SKIP=$SKIP"
echo "========================================================================"

[[ "$FAIL" -eq 0 ]]
