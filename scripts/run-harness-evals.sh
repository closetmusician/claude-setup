#!/usr/bin/env bash
# ABOUTME: Thin wrapper: invokes `harness eval run` (Pillar III §Task 3/6 — eval corpus runner).
# ABOUTME: --check-dirty mode: runs corpus + both guard suites + harness replay --all-golden.
# ABOUTME: Named deliverable (Pillar VII calls it as pre-commit.d/30-eval-dirty.sh).
# ABOUTME: Exits 0 on STAGE-OK, 1 on STAGE-REFUSED. Fail-open on missing harness binary or absent golden-traces dir.
# ABOUTME: With --with-patch <diff>: passes the patch to harness eval run for a throwaway run.
# ABOUTME: BSD/macOS compatible. No model calls. Idempotent.

set -uo pipefail
# Do NOT trap ERR to exit 0 — we are the gate; a real FAIL must propagate.

CLAUDE_DIR="${CLAUDE_DIR:-$HOME/.claude}"
HARNESS="${HARNESS_BIN:-$CLAUDE_DIR/bin/harness}"

# Guard suite scripts
COMPLETION_SUITE="$CLAUDE_DIR/scripts/tests/test-completion-claim-guard.sh"
QA_OWNERSHIP_SUITE="$CLAUDE_DIR/scripts/tests/test-qa-artifact-ownership-guard.sh"

# ── parse args ────────────────────────────────────────────────────────────────
MODE="run"
PATCH_ARG=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --check-dirty) MODE="check-dirty"; shift ;;
    --with-patch)
      [[ $# -lt 2 ]] && { echo "run-harness-evals.sh: --with-patch requires a file" >&2; exit 1; }
      PATCH_ARG=(--with-patch "$2"); shift 2 ;;
    --help|-h)
      echo "Usage: run-harness-evals.sh [--check-dirty] [--with-patch <diff>]"
      echo ""
      echo "  --check-dirty   Pre-commit gate: run corpus + suites + replay; exit nonzero on failure."
      echo "  --with-patch    Apply patch to throwaway copy before running corpus."
      exit 0 ;;
    *) echo "run-harness-evals.sh: unknown option: $1" >&2; exit 1 ;;
  esac
done

# ── fail-open guard: missing harness binary ───────────────────────────────────
# Per spec (§III-3.5 / §Task 6): fail-open ONLY on missing harness binary.
# A real FAIL (guard regression, STAGE-REFUSED) must never be swallowed.
if [[ ! -x "$HARNESS" ]]; then
  echo "run-harness-evals.sh: harness binary not found at $HARNESS — skipping (fail-open)"
  exit 0
fi

# ── Standard eval run (default mode) ─────────────────────────────────────────
if [[ "$MODE" == "run" ]]; then
  exec "$HARNESS" eval run "${PATCH_ARG[@]}"
fi

# ── check-dirty mode (pre-commit gate) ───────────────────────────────────────
echo "run-harness-evals.sh: check-dirty mode"
OVERALL_EC=0

# ── 1. harness eval run (corpus + integrated guard suites) ───────────────────
echo ""
echo "── harness eval run (corpus + suites) ───────────────────────────────────"
if "$HARNESS" eval run "${PATCH_ARG[@]}"; then
  echo "harness eval run: STAGE-OK"
else
  eval_ec=$?
  if [[ "$eval_ec" -eq 3 ]]; then
    echo "harness eval run: CORPUS_TAMPER — refusing" >&2
  else
    echo "harness eval run: STAGE-REFUSED" >&2
  fi
  OVERALL_EC=1
fi

# ── 2. harness replay --all-golden ───────────────────────────────────────────
echo ""
echo "── harness replay --all-golden ──────────────────────────────────────────"
# Fail-open when golden-traces dir is absent (infrastructure not yet bootstrapped).
# A missing directory means no regressions can exist — this is NOT a guard failure.
_REPLAY_GOLDEN_DIR="${HARNESS_GOLDEN_DIR:-$CLAUDE_DIR/.agents/claude-governance/eval-corpus/golden-traces}"
if [[ ! -d "$_REPLAY_GOLDEN_DIR" ]]; then
  echo "harness replay --all-golden: golden-traces dir absent ($CLAUDE_DIR/.agents/claude-governance/eval-corpus/golden-traces) — skipping (fail-open, infrastructure not bootstrapped)"
elif HARNESS_GOLDEN_DIR="$_REPLAY_GOLDEN_DIR" "$HARNESS" replay --all-golden 2>&1; then
  echo "harness replay --all-golden: PASS"
else
  echo "harness replay --all-golden: FAIL" >&2
  OVERALL_EC=1
fi

# ── summary ───────────────────────────────────────────────────────────────────
echo ""
if [[ "$OVERALL_EC" -eq 0 ]]; then
  echo "run-harness-evals.sh: all checks PASS"
else
  echo "run-harness-evals.sh: FAIL (exit $OVERALL_EC)" >&2
fi

exit "$OVERALL_EC"
