#!/usr/bin/env bash
# ABOUTME: PostToolUse hook (Pillar II.1): captures ground-truth evidence tokens per tool call.
# ABOUTME: Bash: records cmd_exit metric + test-run trust_decision (pass counts) + git SHA.
# ABOUTME: Write/Edit: records file_write metric (path + sha16). Large outputs spill to ledger/.
# ABOUTME: Fail-open always: set -uo pipefail, trap ERR→exit 0, jq/shasum guard. BSD-safe.
# ABOUTME: PostToolUse observer only — never writes stdout/stderr, never blocks a tool call.

set -uo pipefail
trap 'exit 0' ERR

# ── Dependency guard ─────────────────────────────────────────────────────────
command -v jq     >/dev/null 2>&1 || exit 0
command -v shasum >/dev/null 2>&1 || exit 0

# ── Source emit-event.sh ─────────────────────────────────────────────────────
_EL_EMIT_SH="${HOME}/.claude/scripts/lib/emit-event.sh"
# shellcheck disable=SC1090
[[ -f "$_EL_EMIT_SH" ]] && source "$_EL_EMIT_SH" 2>/dev/null || true
unset _EL_EMIT_SH

# ── Read PostToolUse stdin ───────────────────────────────────────────────────
INPUT=$(cat)

# Validate: must be non-empty JSON with a tool_name field
TOOL_NAME=$(printf '%s' "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null) || exit 0
[[ -z "$TOOL_NAME" ]] && exit 0

# ── Resolve STATE for ledger spill dir ───────────────────────────────────────
# Uses $STATE env (set by tests) else resolves from git toplevel per substrate §2.1
if [[ -n "${STATE:-}" ]]; then
  _EL_STATE="$STATE"
else
  _EL_TOPLEVEL="$(git rev-parse --show-toplevel 2>/dev/null)" || true
  if [[ -n "${_EL_TOPLEVEL:-}" ]]; then
    _EL_STATE="${_EL_TOPLEVEL}/.agents/claude-governance"
  else
    _EL_STATE="${HOME}/.claude/state"
  fi
  unset _EL_TOPLEVEL
fi
LEDGER_DIR="${_EL_STATE}/state/ledger"

# ── Idempotency: suppress duplicate events for the same tool_use_id ──────────
# Purpose: if the hook fires twice for the same call, only the first write lands.
# Gotchas: uses a lightweight file-presence check under the ledger dir; mktemp-safe.
TOOL_USE_ID=$(printf '%s' "$INPUT" | jq -r '.tool_use_id // empty' 2>/dev/null) || true
if [[ -n "${TOOL_USE_ID:-}" ]]; then
  SEEN_DIR="${_EL_STATE}/state/ledger-seen"
  mkdir -p "$SEEN_DIR" 2>/dev/null || true
  SEEN_FILE="${SEEN_DIR}/${TOOL_USE_ID}"
  if [[ -f "$SEEN_FILE" ]]; then
    exit 0   # duplicate — already emitted for this tool call
  fi
  # Mark seen before emitting (atomic enough for single-writer hook context)
  touch "$SEEN_FILE" 2>/dev/null || true
fi

# ── sha16 helper ─────────────────────────────────────────────────────────────
# Purpose: produce a 16-char hex digest of a string for use as evidence_ref.
# Usage: sha16 "$string" → result in _SHA16_OUT
sha16() {
  _SHA16_OUT=$(printf '%s' "$1" | shasum -a 256 2>/dev/null | cut -c1-16)
}

# ── LARGE OUTPUT THRESHOLD: 2000 bytes ───────────────────────────────────────
# Spill outputs larger than this to ledger/<sha16>.out; event carries pointer.
_EL_SPILL_THRESHOLD=2000

# ─────────────────────────────────────────────────────────────────────────────
# BASH TOOL
# ─────────────────────────────────────────────────────────────────────────────
if [[ "$TOOL_NAME" == "Bash" ]]; then
  COMMAND=$(printf '%s' "$INPUT" | jq -r '.tool_input.command // ""' 2>/dev/null) || COMMAND=""
  OUTPUT=$(printf '%s' "$INPUT" | jq -r '.tool_result // ""' 2>/dev/null) || OUTPUT=""
  EXIT_CODE=$(printf '%s' "$INPUT" | jq -r '.tool_result_exit_code // 0' 2>/dev/null) || EXIT_CODE=0

  # Compute sha16 of the output for evidence_ref base
  sha16 "$OUTPUT"
  OUTPUT_SHA16="$_SHA16_OUT"

  # ── Large output spill ───────────────────────────────────────────────────
  LEDGER_SPILL_KEY=""
  OUTPUT_LEN=${#OUTPUT}
  if [[ "$OUTPUT_LEN" -gt "$_EL_SPILL_THRESHOLD" ]]; then
    mkdir -p "$LEDGER_DIR" 2>/dev/null || true
    SPILL_FILE="${LEDGER_DIR}/${OUTPUT_SHA16}.out"
    printf '%s' "$OUTPUT" > "$SPILL_FILE" 2>/dev/null || true
    LEDGER_SPILL_KEY="$SPILL_FILE"
  fi

  # ── Classify the tool call ────────────────────────────────────────────────
  # test-run: output contains a pass/fail count line
  # git-commit: command starts with git commit or output contains commit SHA
  # other: generic cmd_exit

  CLASSIFICATION="other"
  PASSED_COUNT=""
  FAILED_COUNT=""
  GIT_SHA=""

  # Test-run detection: look for N passed / N failed / N passing in output
  # Supports: "21 passed", "21 passing", "21 failed", "PASS (21 tests)", "Tests: 21 passed"
  if printf '%s' "$OUTPUT" | grep -qiE '[0-9]+ (passed|passing|failed|tests?)'; then
    CLASSIFICATION="test-run"
    # Extract first "N passed" or "N passing"
    PASSED_COUNT=$(printf '%s' "$OUTPUT" | \
      grep -oiE '[0-9]+ (passed|passing)' | head -1 | grep -oE '[0-9]+' | head -1) || true
    # Extract first "N failed"
    FAILED_COUNT=$(printf '%s' "$OUTPUT" | \
      grep -oiE '[0-9]+ failed' | head -1 | grep -oE '[0-9]+' | head -1) || true
  fi

  # Git commit detection: command or output contains a commit SHA pattern
  # git commit output: "[branch abc1234] message"
  if printf '%s' "$COMMAND" | grep -qE '^git (commit|merge|cherry-pick)' || \
     printf '%s' "$OUTPUT" | grep -qE '^\[.* [0-9a-f]{7,}\]'; then
    CLASSIFICATION="git-commit"
    GIT_SHA=$(printf '%s' "$OUTPUT" | \
      grep -oE '[0-9a-f]{7,40}' | head -1) || GIT_SHA=""
  fi

  # ── Build and emit ────────────────────────────────────────────────────────
  OUTCOME="ok"
  [[ "$EXIT_CODE" != "0" ]] && OUTCOME="error"

  if [[ "$CLASSIFICATION" == "test-run" ]]; then
    # Emit trust_decision for test-run: evidence_ref = "<N>passed@<sha16>"
    PASSED_LABEL="${PASSED_COUNT:-0}"
    EVREF="${PASSED_LABEL}passed@${OUTPUT_SHA16}"

    # Build payload JSON safely with jq
    PAYLOAD=$(jq -cn \
      --arg cls "$CLASSIFICATION" \
      --arg passed "${PASSED_COUNT:-}" \
      --arg failed "${FAILED_COUNT:-}" \
      --arg spill "${LEDGER_SPILL_KEY}" \
      '{"claim":"test_count","classification":$cls,"passed":$passed,"failed":$failed}
       + (if $spill != "" then {"ledger_spill":$spill} else {} end)') || PAYLOAD='{"claim":"test_count"}'

    emit_event "trust_decision" "$PAYLOAD" \
      tool="Bash" \
      outcome="$OUTCOME" \
      evidence_ref="$EVREF" \
      source="evidence-ledger.sh" || true

  elif [[ "$CLASSIFICATION" == "git-commit" ]]; then
    # Emit metric for git commit: evidence_ref = "<sha>@<output_sha16>"
    EVREF="${GIT_SHA:-unknown}@${OUTPUT_SHA16}"

    PAYLOAD=$(jq -cn \
      --arg cls "$CLASSIFICATION" \
      --arg sha "${GIT_SHA:-}" \
      --arg spill "${LEDGER_SPILL_KEY}" \
      '{"name":"cmd_exit","classification":$cls,"git_sha":$sha}
       + (if $spill != "" then {"ledger_spill":$spill} else {} end)') || PAYLOAD='{"name":"cmd_exit","classification":"git-commit"}'

    emit_event "metric" "$PAYLOAD" \
      tool="Bash" \
      outcome="$OUTCOME" \
      evidence_ref="$EVREF" \
      source="evidence-ledger.sh" || true

  else
    # Generic: cmd_exit metric
    EVREF="${OUTPUT_SHA16}"

    PAYLOAD=$(jq -cn \
      --arg cls "$CLASSIFICATION" \
      --arg spill "${LEDGER_SPILL_KEY}" \
      '{"name":"cmd_exit","classification":$cls}
       + (if $spill != "" then {"ledger_spill":$spill} else {} end)') || PAYLOAD='{"name":"cmd_exit","classification":"other"}'

    emit_event "metric" "$PAYLOAD" \
      tool="Bash" \
      outcome="$OUTCOME" \
      evidence_ref="$EVREF" \
      source="evidence-ledger.sh" || true
  fi

  exit 0
fi

# ─────────────────────────────────────────────────────────────────────────────
# WRITE / EDIT TOOLS
# ─────────────────────────────────────────────────────────────────────────────
if [[ "$TOOL_NAME" == "Write" || "$TOOL_NAME" == "Edit" ]]; then
  FILE_PATH=$(printf '%s' "$INPUT" | jq -r '.tool_input.file_path // ""' 2>/dev/null) || FILE_PATH=""
  [[ -z "$FILE_PATH" ]] && exit 0

  # Post-write stat: mtime + size (BSD stat -f %m and %z)
  FILE_MTIME=$(stat -f %m "$FILE_PATH" 2>/dev/null) || FILE_MTIME="0"
  FILE_SIZE=$(stat -f %z "$FILE_PATH" 2>/dev/null) || FILE_SIZE="0"

  # sha16 of the file path for evidence_ref uniqueness
  sha16 "$FILE_PATH"
  PATH_SHA16="$_SHA16_OUT"

  # evidence_ref = "<abspath>#<size>@<mtime>"
  EVREF="${FILE_PATH}#${FILE_SIZE}@${FILE_MTIME}"

  PAYLOAD=$(jq -cn \
    --arg fp "$FILE_PATH" \
    --arg sz "$FILE_SIZE" \
    --arg mt "$FILE_MTIME" \
    --arg sha "$PATH_SHA16" \
    --arg tool "$TOOL_NAME" \
    '{"name":"file_write","file_path":$fp,"size":$sz,"mtime":$mt,"sha16":$sha,"tool":$tool}') \
    || PAYLOAD="{\"name\":\"file_write\",\"file_path\":\"$FILE_PATH\"}"

  emit_event "metric" "$PAYLOAD" \
    tool="$TOOL_NAME" \
    outcome="ok" \
    evidence_ref="$EVREF" \
    source="evidence-ledger.sh" || true

  exit 0
fi

# Non-matching tool — exit 0, no emit
exit 0
