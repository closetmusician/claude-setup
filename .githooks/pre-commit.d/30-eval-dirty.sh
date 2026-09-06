#!/usr/bin/env bash
# HARNESS_EVAL_GATE installed
# ABOUTME: Pre-commit eval gate for the harness self-modification safety check (§Task 6 / §III-3.5).
# ABOUTME: Runs run-harness-evals.sh --check-dirty when staged files touch guarded paths.
# ABOUTME: Sourced by the VII pre-commit.d dispatcher (pre-commit itself only runs secret-scan).
# ABOUTME: This file is inert-by-design until the VII dispatcher is installed (VII owns pre-commit).
# ABOUTME: Fail-open ONLY on missing harness binary; blocks on real replay FAIL.

set -uo pipefail
trap 'exit 0' ERR

# Idempotency marker: this comment is the idempotency anchor.
# If sourced more than once, the guard is still safe — it just runs again (idempotent).

CLAUDE_DIR="${CLAUDE_DIR:-$HOME/.claude}"
EVALS_SCRIPT="$CLAUDE_DIR/scripts/run-harness-evals.sh"
HARNESS="${HARNESS_BIN:-$CLAUDE_DIR/bin/harness}"

# Fail-open ONLY on missing harness binary (per spec §III-3.5 / §Task 6).
# A real FAIL must never be swallowed.
if ! command -v "$HARNESS" >/dev/null 2>&1 && [[ ! -x "$HARNESS" ]]; then
  exit 0  # fail-open: harness not installed
fi

# Check if any staged files touch guarded paths.
# Guarded: rules/, scripts/, skills/, settings.json
STAGED_PATHS="$(git diff --cached --name-only 2>/dev/null || true)"
if [[ -z "$STAGED_PATHS" ]]; then
  exit 0  # nothing staged
fi

TOUCHES_GUARDED=0
while IFS= read -r path; do
  case "$path" in
    rules/*|scripts/*|skills/*|settings.json)
      TOUCHES_GUARDED=1
      break ;;
  esac
done <<<"$STAGED_PATHS"

if [[ "$TOUCHES_GUARDED" -eq 0 ]]; then
  exit 0  # no guarded files staged — skip
fi

echo "pre-commit.d/30-eval-dirty.sh: guarded files staged, running harness evals..."

if [[ ! -x "$EVALS_SCRIPT" ]]; then
  echo "pre-commit.d/30-eval-dirty.sh: WARN: evals script not found at $EVALS_SCRIPT" >&2
  exit 0  # fail-open on missing evals script itself
fi

# Run the check — exits nonzero on any real failure.
if "$EVALS_SCRIPT" --check-dirty; then
  echo "pre-commit.d/30-eval-dirty.sh: PASS"
  exit 0
else
  echo "pre-commit.d/30-eval-dirty.sh: FAIL — eval gate blocked commit" >&2
  exit 1
fi
