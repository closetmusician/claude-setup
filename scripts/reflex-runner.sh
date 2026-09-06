#!/usr/bin/env bash
# ABOUTME: Night-plane consumer for the analysis-reflex queue (Pillar II / S5).
# ABOUTME: For each job in $STATE/reflex-queue/, calls the haiku skeptic claude -p with
# ABOUTME: the analysis-reflex-prompt.md template, parses CONCUR/DIVERGE, emits trust_decision
# ABOUTME: event, and archives the job. Will later be registered as a nightly-flywheel step.
# ABOUTME: Always exits 0 — fail-open. Runnable standalone now for testing.

set -uo pipefail
trap 'exit 0' ERR

command -v jq >/dev/null 2>&1 || exit 0

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ── Source emit-event.sh ──────────────────────────────────────────────────────
# shellcheck source=/dev/null
source "$SCRIPT_DIR/lib/emit-event.sh" 2>/dev/null || true

# ── Source timeout helper ─────────────────────────────────────────────────────
# shellcheck source=/dev/null
source "$SCRIPT_DIR/lib/timeout.sh" 2>/dev/null || true

# ── Resolve STATE dir ─────────────────────────────────────────────────────────
if [[ -n "${STATE:-}" ]]; then
  STATE_DIR="$STATE"
else
  TOPLEVEL=$(git rev-parse --show-toplevel 2>/dev/null || true)
  if [[ -n "$TOPLEVEL" ]]; then
    STATE_DIR="$TOPLEVEL/.agents/claude-governance"
  else
    STATE_DIR="$HOME/.claude/state"
  fi
fi

QUEUE_DIR="$STATE_DIR/reflex-queue"
DONE_DIR="$QUEUE_DIR/done"
BAD_DIR="$DONE_DIR/bad"
mkdir -p "$DONE_DIR" "$BAD_DIR" 2>/dev/null || true

PROMPT_TEMPLATE="$SCRIPT_DIR/templates/analysis-reflex-prompt.md"
TIMEOUT_SECS="${REFLEX_TIMEOUT_SECS:-60}"

# ── Process each job ──────────────────────────────────────────────────────────
for JOB_FILE in "$QUEUE_DIR"/*.json; do
  # Glob with no match → skip gracefully
  [[ -f "$JOB_FILE" ]] || continue

  JOB_NAME="$(basename "$JOB_FILE")"

  # ── Parse job JSON ──────────────────────────────────────────────────────────
  if ! JOB_JSON=$(jq -e '.' "$JOB_FILE" 2>/dev/null); then
    # Malformed JSON: archive to done/bad and continue
    mv "$JOB_FILE" "$BAD_DIR/$JOB_NAME" 2>/dev/null || true
    continue
  fi

  CLAIM_EXCERPT=$(printf '%s' "$JOB_JSON" | jq -r '.claim_excerpt // empty' 2>/dev/null)
  TRANSCRIPT_PATH=$(printf '%s' "$JOB_JSON" | jq -r '.transcript_path // empty' 2>/dev/null)
  CITED_SOURCES=$(printf '%s' "$JOB_JSON" | jq -r '.cited_sources | if type=="array" then join(", ") else . end' 2>/dev/null || echo "")

  # ── Build prompt by substituting template placeholders ─────────────────────
  if [[ -f "$PROMPT_TEMPLATE" ]]; then
    PROMPT=$(sed \
      -e "s|{{CLAIM_EXCERPT}}|${CLAIM_EXCERPT}|g" \
      -e "s|{{CITED_SOURCES}}|${CITED_SOURCES}|g" \
      "$PROMPT_TEMPLATE" 2>/dev/null || cat "$PROMPT_TEMPLATE")
  else
    PROMPT="You are a skeptic. Re-check this claim: ${CLAIM_EXCERPT}. Sources: ${CITED_SOURCES}. Output CONCUR: or DIVERGE: with a one-line reason."
  fi

  # ── Run haiku skeptic with timeout ─────────────────────────────────────────
  VERDICT=""
  REASON=""
  OUTCOME="unreviewed_verification"
  TIMED_OUT=0

  if command -v _run_with_timeout >/dev/null 2>&1 || declare -f _run_with_timeout >/dev/null 2>&1; then
    RAW=$(printf '%s' "$PROMPT" | _run_with_timeout "$TIMEOUT_SECS" \
      claude -p --model claude-haiku-4-5 --allowedTools "Read Grep Glob" \
      2>/dev/null) || TIMED_OUT=$?
  else
    RAW=$(printf '%s' "$PROMPT" | claude -p --model claude-haiku-4-5 --allowedTools "Read Grep Glob" \
      2>/dev/null) || TIMED_OUT=$?
  fi

  # Timeout exit codes: gtimeout=124, perl watchdog=124, general non-zero
  if [[ $TIMED_OUT -eq 124 ]] || [[ -z "$RAW" && $TIMED_OUT -ne 0 ]]; then
    OUTCOME="escalated"
    VERDICT=""
    REASON="runner timed out after ${TIMEOUT_SECS}s"
  else
    # Parse CONCUR or DIVERGE from first line
    FIRST_LINE=$(printf '%s' "$RAW" | head -1)
    if printf '%s' "$FIRST_LINE" | grep -qE '^CONCUR:'; then
      VERDICT="CONCUR"
      REASON=$(printf '%s' "$FIRST_LINE" | sed 's/^CONCUR:[[:space:]]*//')
    elif printf '%s' "$FIRST_LINE" | grep -qE '^DIVERGE:'; then
      VERDICT="DIVERGE"
      REASON=$(printf '%s' "$FIRST_LINE" | sed 's/^DIVERGE:[[:space:]]*//')
    else
      # Unrecognized output → treat as escalated
      OUTCOME="escalated"
      VERDICT=""
      REASON="unrecognized verifier output: $(printf '%s' "$FIRST_LINE" | cut -c1-100)"
    fi
  fi

  # ── Emit trust_decision event ───────────────────────────────────────────────
  # NEVER auto-promote to correction/incident — human confirmation required.
  # promoted:false is a TODO marker for the escalation pipeline.
  PAYLOAD=$(jq -cn \
    --arg verifier "analysis-reflex" \
    --arg outcome "$OUTCOME" \
    --arg verdict "${VERDICT:-}" \
    --arg claim_excerpt "$CLAIM_EXCERPT" \
    --arg reason "${REASON:-}" \
    --argjson promoted false \
    '{
      verifier: $verifier,
      outcome: $outcome,
      verdict: (if $verdict == "" then null else $verdict end),
      claim_excerpt: $claim_excerpt,
      reason: $reason,
      promoted: $promoted
    }' 2>/dev/null) || PAYLOAD="{}"

  emit_event "trust_decision" "$PAYLOAD" \
    outcome="$OUTCOME" \
    source="reflex-runner.sh" 2>/dev/null || true

  # ── Archive job to done/ ────────────────────────────────────────────────────
  mv "$JOB_FILE" "$DONE_DIR/$JOB_NAME" 2>/dev/null || true

done

exit 0
