#!/usr/bin/env bash
# ABOUTME: TDD test suite for harness replay subcommand (§III-3.5 golden trace-replay).
# ABOUTME: 8 oracle cases: all 5 golden traces match, synthetic decision mutation DIVERGE,
# ABOUTME: live-guard mutation DIVERGE, MANIFEST tamper fails, missing trace dir error,
# ABOUTME: --all-golden aggregation, run-harness-evals.sh green path, and dirty-fail path.
# ABOUTME: All tests are deterministic, <60s total, no model calls.

set -uo pipefail

HARNESS="${HARNESS_BIN:-$HOME/.claude/bin/harness}"
EVALS_SCRIPT="${EVALS_SCRIPT:-$HOME/.claude/scripts/run-harness-evals.sh}"
GOLDEN_BUILDER="${GOLDEN_BUILDER:-$HOME/.claude/scripts/flywheel/build-golden-traces.sh}"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

export HARNESS_GOV_STATE_DIR="${HARNESS_GOV_STATE_DIR:-$TMP/gov-state}"
export HARNESS_GOLDEN_DIR="${HARNESS_GOLDEN_DIR:-$HARNESS_GOV_STATE_DIR/eval-corpus/golden-traces}"
mkdir -p "$HARNESS_GOV_STATE_DIR"
touch "$HARNESS_GOV_STATE_DIR/.active"

PASS=0; FAIL=0

_ok()   { echo "PASS: $1"; PASS=$(( PASS + 1 )); }
_fail() { echo "FAIL: $1${2:+ — $2}"; FAIL=$(( FAIL + 1 )); }

# Resolve the golden traces dir from the real $STATE (get_governance_state_dir returns
# ~/.claude/.agents/claude-governance when run from ~/.claude).
# Tests override via HARNESS_GOLDEN_DIR env when working with mutated copies.
REAL_GOLDEN_DIR="$HARNESS_GOLDEN_DIR"

if [[ ! -x "$GOLDEN_BUILDER" ]]; then
  _fail "golden trace builder executable" "$GOLDEN_BUILDER"
else
  BUILD_OUT=$("$GOLDEN_BUILDER" 2>&1) && BUILD_EC=0 || BUILD_EC=$?
  if [[ "$BUILD_EC" -eq 0 && -d "$REAL_GOLDEN_DIR" ]]; then
    _ok "setup: golden traces built in isolated state"
  else
    _fail "setup: golden traces built" "exit=$BUILD_EC output=${BUILD_OUT:0:300}"
  fi
fi

# ── Case 1: all 5 golden traces match → exit 0, runtime <60s ─────────────────
echo ""
echo "── Case 1: all-golden exits 0 (timing test) ────────────────────────────"
START=$(date +%s)
ALL_OUT=$("$HARNESS" replay --all-golden 2>&1) && ALL_EC=0 || ALL_EC=$?
END=$(date +%s)
ELAPSED=$(( END - START ))

if [[ "$ALL_EC" -eq 0 ]]; then
  _ok "case 1a: --all-golden exits 0"
else
  _fail "case 1a: --all-golden exits 0" "got exit $ALL_EC; output: ${ALL_OUT:0:500}"
fi

if [[ "$ELAPSED" -lt 60 ]]; then
  _ok "case 1b: --all-golden completes in <60s (took ${ELAPSED}s)"
else
  _fail "case 1b: --all-golden completes in <60s" "took ${ELAPSED}s"
fi

if echo "$ALL_OUT" | grep -q "golden-healthy-orchestration"; then
  _ok "case 1c: --all-golden output mentions traces"
else
  _fail "case 1c: --all-golden output mentions traces" "output: ${ALL_OUT:0:200}"
fi

# ── Case 2: synthetic decision mutation → DIVERGE, nonzero, names trace+seq ──
echo ""
echo "── Case 2: synthetic decision mutation → DIVERGE ───────────────────────"

# Copy golden-completion-block and flip its expected "block" decision to "allow"
MUTATED_DIR="$TMP/mutated-traces"
cp -R "$REAL_GOLDEN_DIR" "$MUTATED_DIR"
python3 -c "
import json, sys
lines = []
with open('$MUTATED_DIR/golden-completion-block/golden-decisions.jsonl') as f:
    for line in f:
        d = json.loads(line.strip())
        if d.get('decision') == 'block':
            d['decision'] = 'allow'  # flip the expected decision
        lines.append(json.dumps(d))
with open('$MUTATED_DIR/golden-completion-block/golden-decisions.jsonl', 'w') as f:
    f.write('\n'.join(lines) + '\n')
print('Mutated golden-decisions.jsonl — flipped block->allow')
"

# Regenerate MANIFEST for the mutated dir so MANIFEST check passes, then replay
cd "$MUTATED_DIR" && find . -type f ! -name 'MANIFEST.sha256' | sort | xargs shasum -a 256 > MANIFEST.sha256 2>/dev/null || true
cd /

MUT_OUT=$(HARNESS_GOLDEN_DIR="$MUTATED_DIR" "$HARNESS" replay golden-completion-block --assert-decisions 2>&1) && MUT_EC=0 || MUT_EC=$?

if [[ "$MUT_EC" -ne 0 ]]; then
  _ok "case 2a: mutated trace exits nonzero (DIVERGE)"
else
  _fail "case 2a: mutated trace should exit nonzero" "got exit 0"
fi

if echo "$MUT_OUT" | grep -qiE "DIVERGE|diverge|golden-completion-block"; then
  _ok "case 2b: DIVERGE output names the trace"
else
  _fail "case 2b: DIVERGE output names trace" "output: ${MUT_OUT:0:300}"
fi

if echo "$MUT_OUT" | grep -qE "seq.*1|step.*1|seq=1|seq:1"; then
  _ok "case 2c: DIVERGE output names the seq"
else
  _fail "case 2c: DIVERGE output names seq" "output: ${MUT_OUT:0:300}"
fi

if echo "$MUT_OUT" | grep -qiE "expect|got|block|allow"; then
  _ok "case 2d: DIVERGE shows expected vs got"
else
  _fail "case 2d: DIVERGE shows expected vs got" "output: ${MUT_OUT:0:300}"
fi

# ── Case 3: live-guard mutation → DIVERGE nonzero ─────────────────────────────
echo ""
echo "── Case 3: live-guard mutation → DIVERGE ───────────────────────────────"

# Create a patched guard that inverts the completion-claim decision:
# The real guard blocks on bare "Done."; the patched guard always exits 0 (silent).
PATCHED_GUARD="$TMP/patched-completion-claim-guard.sh"
cat > "$PATCHED_GUARD" <<'GUARDEOF'
#!/usr/bin/env bash
# Patched guard: always silent (inverts block decision for testing)
exit 0
GUARDEOF
chmod +x "$PATCHED_GUARD"

# Run replay on golden-completion-block with the guard path overridden
# The env override HARNESS_HOOK_ROOT lets the replay runner find the patched guard.
LIVE_OUT=$(HARNESS_HOOK_ROOT="$TMP" HARNESS_HOOK_OVERRIDE_completion_claim_guard="$PATCHED_GUARD" \
  "$HARNESS" replay golden-completion-block --assert-decisions 2>&1) && LIVE_EC=0 || LIVE_EC=$?

if [[ "$LIVE_EC" -ne 0 ]]; then
  _ok "case 3a: live-guard mutation exits nonzero (DIVERGE)"
else
  _fail "case 3a: live-guard mutation should exit nonzero" "got exit 0"
fi

if echo "$LIVE_OUT" | grep -qiE "DIVERGE|diverge"; then
  _ok "case 3b: DIVERGE reported for live-guard mutation"
else
  _fail "case 3b: DIVERGE reported" "output: ${LIVE_OUT:0:300}"
fi

# ── Case 4: MANIFEST tamper → loud fail nonzero ───────────────────────────────
echo ""
echo "── Case 4: MANIFEST tamper → loud fail ─────────────────────────────────"

TAMPERED_DIR="$TMP/tampered-traces"
cp -R "$REAL_GOLDEN_DIR" "$TAMPERED_DIR"
# Generate a valid manifest, then modify a file to break the manifest
cd "$TAMPERED_DIR" && find . -type f ! -name 'MANIFEST.sha256' | sort | xargs shasum -a 256 > MANIFEST.sha256 2>/dev/null || true
# Tamper: add an extra byte to one of the golden-decisions files
echo "TAMPERED" >> "$TAMPERED_DIR/golden-completion-block/golden-decisions.jsonl"
cd /

TAMP_OUT=$(HARNESS_GOLDEN_DIR="$TAMPERED_DIR" "$HARNESS" replay golden-completion-block --assert-decisions 2>&1) && TAMP_EC=0 || TAMP_EC=$?

if [[ "$TAMP_EC" -ne 0 ]]; then
  _ok "case 4a: MANIFEST tamper exits nonzero"
else
  _fail "case 4a: MANIFEST tamper should exit nonzero" "got exit 0"
fi

if echo "$TAMP_OUT" | grep -qiE "MANIFEST|manifest|tamper|mismatch|corrupt"; then
  _ok "case 4b: MANIFEST tamper reports clear error"
else
  _fail "case 4b: MANIFEST tamper clear error" "output: ${TAMP_OUT:0:300}"
fi

# ── Case 5: missing trace dir → clear error nonzero ───────────────────────────
echo ""
echo "── Case 5: missing trace dir → clear error ─────────────────────────────"

MISS_OUT=$(HARNESS_GOLDEN_DIR="$REAL_GOLDEN_DIR" \
  "$HARNESS" replay nonexistent-trace-xyzzy --assert-decisions 2>&1) && MISS_EC=0 || MISS_EC=$?

if [[ "$MISS_EC" -ne 0 ]]; then
  _ok "case 5a: missing trace exits nonzero"
else
  _fail "case 5a: missing trace should exit nonzero" "got exit 0"
fi

if echo "$MISS_OUT" | grep -qiE "not found|no such|missing|nonexistent"; then
  _ok "case 5b: missing trace gives clear error message"
else
  _fail "case 5b: missing trace clear error" "output: ${MISS_OUT:0:300}"
fi

# ── Case 6: --all-golden aggregates per-trace status ─────────────────────────
echo ""
echo "── Case 6: --all-golden aggregates per-trace status ────────────────────"

AGG_OUT=$("$HARNESS" replay --all-golden 2>&1) && AGG_EC=0 || AGG_EC=$?

TRACES=(golden-healthy-orchestration golden-qa-ownership golden-completion-block golden-skill-routing golden-clean-interactive)
ALL_MENTIONED=1
for t in "${TRACES[@]}"; do
  if ! echo "$AGG_OUT" | grep -q "$t"; then
    ALL_MENTIONED=0
    echo "  (missing trace name in output: $t)"
  fi
done

if [[ "$ALL_MENTIONED" -eq 1 ]]; then
  _ok "case 6a: --all-golden mentions all 5 trace names"
else
  _fail "case 6a: --all-golden mentions all 5 trace names"
fi

PASS_COUNT=$(echo "$AGG_OUT" | grep -ciE "PASS|pass|ok|match" || true)
if [[ "$PASS_COUNT" -ge 1 ]]; then
  _ok "case 6b: --all-golden shows pass indicators"
else
  _fail "case 6b: --all-golden shows pass indicators" "output: ${AGG_OUT:0:200}"
fi

# ── Case 7: run-harness-evals.sh --check-dirty green path exits 0 ─────────────
echo ""
echo "── Case 7: run-harness-evals.sh --check-dirty green path ───────────────"

if [[ ! -x "$EVALS_SCRIPT" ]]; then
  _fail "case 7: run-harness-evals.sh not executable" "$EVALS_SCRIPT"
else
  EVALS_OUT="$(unset HARNESS_GOV_STATE_DIR; HARNESS_GOLDEN_DIR="$REAL_GOLDEN_DIR" "$EVALS_SCRIPT" --check-dirty 2>&1)" && EVALS_EC=0 || EVALS_EC=$?
  if [[ "$EVALS_EC" -eq 0 ]]; then
    _ok "case 7: run-harness-evals.sh --check-dirty exits 0 (green path)"
  else
    _fail "case 7: run-harness-evals.sh --check-dirty should exit 0" "got $EVALS_EC; output: ${EVALS_OUT:0:300}"
  fi
fi

# ── Case 8: run-harness-evals.sh --check-dirty with failing replay → nonzero ──
echo ""
echo "── Case 8: run-harness-evals.sh --check-dirty with failing replay ───────"

# Create a mutated golden dir where one trace will DIVERGE
DIRTY_GOLDEN="$TMP/dirty-golden"
cp -R "$REAL_GOLDEN_DIR" "$DIRTY_GOLDEN"
python3 -c "
import json
lines = []
with open('$DIRTY_GOLDEN/golden-clean-interactive/golden-decisions.jsonl') as f:
    for line in f:
        d = json.loads(line.strip())
        d['decision'] = 'block'  # Force DIVERGE on clean interactive
        lines.append(json.dumps(d))
with open('$DIRTY_GOLDEN/golden-clean-interactive/golden-decisions.jsonl', 'w') as f:
    f.write('\n'.join(lines) + '\n')
print('Dirtied golden-clean-interactive decisions')
"
cd "$DIRTY_GOLDEN" && find . -type f ! -name 'MANIFEST.sha256' | sort | xargs shasum -a 256 > MANIFEST.sha256 2>/dev/null || true
cd /

DIRTY_OUT="$(unset HARNESS_GOV_STATE_DIR; HARNESS_GOLDEN_DIR="$DIRTY_GOLDEN" "$EVALS_SCRIPT" --check-dirty 2>&1)" && DIRTY_EC=0 || DIRTY_EC=$?

if [[ "$DIRTY_EC" -ne 0 ]]; then
  _ok "case 8a: dirty replay causes run-harness-evals.sh to exit nonzero"
else
  _fail "case 8a: dirty replay should cause nonzero exit" "got exit 0"
fi

# ── Summary ───────────────────────────────────────────────────────────────────
echo ""
echo "========================================================================"
echo "test-harness-replay: PASS=$PASS  FAIL=$FAIL  (total=$(( PASS + FAIL )))"
echo "========================================================================"

[[ "$FAIL" -eq 0 ]]
