#!/usr/bin/env bash
# ABOUTME: Negative-test oracle for the eval corpus runner (Pillar III §Task 3).
# ABOUTME: Covers: baseline STAGE-OK, sabotage-patch STAGE-REFUSED with regressions[],
# ABOUTME: CORPUS_TAMPER exit-3, eval_run event emission, eval ls, no-op patch STAGE-OK.
# ABOUTME: ≥6 cases required per spec; this suite has 8. RED first (subcommand absent),
# ABOUTME: then GREEN after harness eval run is implemented.
# ABOUTME: Usage: bash scripts/tests/test-flywheel-corpus.sh
# ABOUTME: BSD/macOS compatible. Uses HARNESS_STATE_OVERRIDE for test isolation.

set -uo pipefail

HARNESS="${HARNESS_BIN:-$HOME/.claude/bin/harness}"
CLAUDE_DIR="${CLAUDE_DIR:-$HOME/.claude}"
CORPUS_DIR="$CLAUDE_DIR/evals/incidents"
SCRIPTS_DIR="$CLAUDE_DIR/scripts"

PASS=0; FAIL=0; SKIP=0
TMP=$(mktemp -d /tmp/test-flywheel-corpus-XXXXXX)
trap 'rm -rf "$TMP"' EXIT

_ok()   { echo "PASS: $1"; PASS=$(( PASS + 1 )); }
_fail() { echo "FAIL: $1 — $2"; FAIL=$(( FAIL + 1 )); }
_skip() { echo "SKIP: $1 — $2"; SKIP=$(( SKIP + 1 )); }

echo "========================================================================"
echo "test-flywheel-corpus.sh — eval corpus runner negative-test oracle"
echo "========================================================================"
echo ""

# ── Prerequisites ─────────────────────────────────────────────────────────────
if [[ ! -x "$HARNESS" ]]; then
  _fail "harness binary present and executable" "not found at $HARNESS"
  echo ""
  echo "Results: PASS=$PASS  FAIL=$FAIL  SKIP=$SKIP"
  exit 1
fi

# ── Helper: run harness eval run with isolated state and corpus ───────────────
# Purpose: Wraps harness eval run with HARNESS_STATE_OVERRIDE and HARNESS_EVAL_CORPUS_DIR
#   so tests are fully isolated from the real spine and each other.
# Usage: _eval_run [--with-patch <diff>]  (returns exit code; output to stdout)
# Gotchas: Uses $TMP for state isolation; corpus is always the real incidents dir.
_eval_run() {
  (
    unset HARNESS_GOV_STATE_DIR
    HARNESS_STATE_OVERRIDE="$TMP/state-$$" \
    HARNESS_EVAL_CORPUS_DIR="$CORPUS_DIR" \
    "$HARNESS" eval run "$@"
  )
}

# ── Create sabotage diff (neuters CLAIM regex in completion-claim-guard) ──────
# Purpose: Produce a unified diff that makes the guard fail to detect completion
#   claims, causing C2-002 (expect=block) to produce "allow" -> regression.
# Gotchas: Uses python3 to modify a temp copy; diff uses a/b/ prefix format for patch -p1.
ORIG_GUARD="$CLAUDE_DIR/scripts/completion-claim-guard.sh"
if [[ ! -f "$ORIG_GUARD" ]]; then
  _skip "sabotage diff setup" "completion-claim-guard.sh not found"
  SABOTAGE_DIFF=""
else
  PATCHED_GUARD="$TMP/guard-patched.sh"
  cp "$ORIG_GUARD" "$PATCHED_GUARD"
  python3 -c "
import re
content = open('$PATCHED_GUARD').read()
content = re.sub(
    r\"^CLAIM='.*'\$\",
    \"CLAIM='XXXXXXX_NEVER_MATCHES_test_corpus_zzz'\",
    content,
    count=1,
    flags=re.MULTILINE
)
open('$PATCHED_GUARD', 'w').write(content)
"
  SABOTAGE_DIFF="$TMP/sabotage.diff"
  diff -u "$ORIG_GUARD" "$PATCHED_GUARD" \
    | sed "s|$ORIG_GUARD|a/scripts/completion-claim-guard.sh|g" \
    | sed "s|$PATCHED_GUARD|b/scripts/completion-claim-guard.sh|g" \
    > "$SABOTAGE_DIFF" 2>/dev/null || true
fi

# ── Create no-op diff (whitespace-only comment change, safe) ─────────────────
NOOP_ORIG="$CLAUDE_DIR/scripts/analysis-reflex.sh"
NOOP_DIFF=""
if [[ -f "$NOOP_ORIG" ]]; then
  PATCHED_NOOP="$TMP/noop-patched.sh"
  cp "$NOOP_ORIG" "$PATCHED_NOOP"
  # Add a comment line to a non-guard file (analysis-reflex.sh is NOT a guard)
  printf '\n# test-no-op-comment\n' >> "$PATCHED_NOOP"
  NOOP_DIFF="$TMP/noop.diff"
  diff -u "$NOOP_ORIG" "$PATCHED_NOOP" \
    | sed "s|$NOOP_ORIG|a/scripts/analysis-reflex.sh|g" \
    | sed "s|$PATCHED_NOOP|b/scripts/analysis-reflex.sh|g" \
    > "$NOOP_DIFF" 2>/dev/null || true
fi

# ── Create CORPUS_TAMPER diff (touches run-harness-evals.sh) ─────────────────
TAMPER_DIFF="$TMP/tamper.diff"
cat > "$TAMPER_DIFF" << 'ENDDIFF'
--- a/scripts/run-harness-evals.sh
+++ b/scripts/run-harness-evals.sh
@@ -1,3 +1,3 @@
 #!/usr/bin/env bash
-# ABOUTME: Thin wrapper
+# ABOUTME: TAMPERED
ENDDIFF

# ────────────────────────────────────────────────────────────────────────────
echo "── Case 1: harness eval run (baseline) → STAGE-OK ──────────────────────"
ec=0
out="$(_eval_run 2>&1)" || ec=$?
if [[ "$ec" -eq 0 ]]; then
  if printf '%s\n' "$out" | grep -q 'STAGE-OK'; then
    _ok "baseline run exits 0 with STAGE-OK"
  else
    _fail "baseline run STAGE-OK in output" "output: ${out:0:200}"
  fi
else
  _fail "baseline run exits 0" "got exit $ec; output: ${out:0:200}"
fi

# ────────────────────────────────────────────────────────────────────────────
echo ""
echo "── Case 2: regressions[] empty on baseline → STAGE-OK ──────────────────"
if printf '%s\n' "$out" | python3 -c "
import sys, json
for line in sys.stdin:
    line = line.strip()
    if 'regressions' in line and line.startswith('{'):
        try:
            d = json.loads(line)
            arr = d.get('regressions', [None])
            if isinstance(arr, list) and len(arr) == 0:
                sys.exit(0)
        except Exception:
            pass
sys.exit(1)
" 2>/dev/null; then
  _ok "baseline regressions[] is empty"
else
  _fail "baseline regressions[] is empty" "summary line missing or regressions non-empty"
fi

# ────────────────────────────────────────────────────────────────────────────
echo ""
echo "── Case 3: sabotage patch → STAGE-REFUSED + regressions[] non-empty ────"
if [[ -z "$SABOTAGE_DIFF" ]]; then
  _skip "sabotage patch test" "sabotage diff not created (guard missing)"
else
  ec=0
  out="$(_eval_run --with-patch "$SABOTAGE_DIFF" 2>&1)" || ec=$?
  if [[ "$ec" -ne 0 ]] && printf '%s\n' "$out" | grep -q 'STAGE-REFUSED'; then
    _ok "sabotage patch exits nonzero with STAGE-REFUSED"
  else
    _fail "sabotage patch exits nonzero with STAGE-REFUSED" "exit=$ec; output: ${out:0:300}"
  fi

  # Verify regressions[] is non-empty
  if printf '%s\n' "$out" | python3 -c "
import sys, json
for line in sys.stdin:
    line = line.strip()
    if 'regressions' in line and line.startswith('{'):
        try:
            d = json.loads(line)
            arr = d.get('regressions', [])
            if isinstance(arr, list) and len(arr) > 0:
                sys.exit(0)
        except Exception:
            pass
sys.exit(1)
" 2>/dev/null; then
    _ok "sabotage patch produces non-empty regressions[]"
  else
    _fail "sabotage patch regressions[] non-empty" "output: ${out:0:300}"
  fi
fi

# ────────────────────────────────────────────────────────────────────────────
echo ""
echo "── Case 4: CORPUS_TAMPER patch → exit 3 ────────────────────────────────"
ec=0
out="$(_eval_run --with-patch "$TAMPER_DIFF" 2>&1)" || ec=$?
if [[ "$ec" -eq 3 ]]; then
  _ok "CORPUS_TAMPER diff exits 3"
else
  _fail "CORPUS_TAMPER diff exits 3" "got exit $ec; output: ${out:0:200}"
fi
if printf '%s\n' "$out" | grep -qi "CORPUS_TAMPER"; then
  _ok "CORPUS_TAMPER output contains CORPUS_TAMPER message"
else
  _fail "CORPUS_TAMPER message in output" "output: ${out:0:200}"
fi

# ────────────────────────────────────────────────────────────────────────────
echo ""
echo "── Case 5: every run emits eval_run event to spine ─────────────────────"
EVENTS_FILE="$TMP/state-$$-events/state/events.ndjson"
# Run a baseline to generate an event in our isolated state dir
state_override="$TMP/state-evtest"
mkdir -p "$state_override/state"
(
  unset HARNESS_GOV_STATE_DIR
  HARNESS_STATE_OVERRIDE="$state_override" \
  HARNESS_EVAL_CORPUS_DIR="$CORPUS_DIR" \
  "$HARNESS" eval run >/dev/null 2>&1
) || true

eval_events="$(grep '"event_type":"eval_run"' "$state_override/state/events.ndjson" 2>/dev/null | wc -l | tr -d '[:space:]')"
if [[ "${eval_events:-0}" -ge 1 ]]; then
  _ok "eval run emits eval_run event to spine (count=$eval_events)"
else
  _fail "eval run emits eval_run event" "found 0 eval_run events in $state_override/state/events.ndjson"
fi

# ────────────────────────────────────────────────────────────────────────────
echo ""
echo "── Case 6: no-op patch → STAGE-OK ──────────────────────────────────────"
if [[ -z "$NOOP_DIFF" ]]; then
  _skip "no-op patch test" "noop diff not created (analysis-reflex.sh missing)"
else
  ec=0
  out="$(_eval_run --with-patch "$NOOP_DIFF" 2>&1)" || ec=$?
  if [[ "$ec" -eq 0 ]] && printf '%s\n' "$out" | grep -q 'STAGE-OK'; then
    _ok "no-op patch exits 0 with STAGE-OK"
  else
    _fail "no-op patch STAGE-OK" "exit=$ec; output: ${out:0:300}"
  fi
fi

# ────────────────────────────────────────────────────────────────────────────
echo ""
echo "── Case 7: harness eval ls lists fixtures ───────────────────────────────"
ec=0
out="$(HARNESS_EVAL_CORPUS_DIR="$CORPUS_DIR" "$HARNESS" eval ls 2>&1)" || ec=$?
if [[ "$ec" -eq 0 ]] && printf '%s\n' "$out" | grep -q 'Total:'; then
  _ok "harness eval ls exits 0 and shows Total: line"
else
  _fail "harness eval ls" "exit=$ec; output: ${out:0:200}"
fi
fixture_count="$(printf '%s\n' "$out" | grep -o 'Total: [0-9]*' | grep -o '[0-9]*' || echo 0)"
if [[ "${fixture_count:-0}" -ge 2 ]]; then
  _ok "harness eval ls shows ≥2 fixtures (count=$fixture_count)"
else
  _fail "harness eval ls shows ≥2 fixtures" "count=$fixture_count"
fi

# ────────────────────────────────────────────────────────────────────────────
echo ""
echo "── Case 8: sabotage patch names regressed fixture in summary ────────────"
if [[ -z "$SABOTAGE_DIFF" ]]; then
  _skip "sabotage regression name" "sabotage diff not created"
else
  ec=0
  out="$(_eval_run --with-patch "$SABOTAGE_DIFF" 2>&1)" || ec=$?
  if printf '%s\n' "$out" | grep -q 'C2-002'; then
    _ok "sabotage summary names C2-002 as regressed fixture"
  else
    _fail "sabotage summary names C2-002" "output: ${out:0:300}"
  fi
fi

# ────────────────────────────────────────────────────────────────────────────
echo ""
echo "========================================================================"
echo "Results: PASS=$PASS  FAIL=$FAIL  SKIP=$SKIP  (total=$(( PASS + FAIL + SKIP )))"
echo "========================================================================"
echo ""

if [[ "$FAIL" -gt 0 ]]; then
  exit 1
fi
exit 0
