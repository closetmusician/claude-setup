#!/usr/bin/env bash
# ABOUTME: SessionStart drop-in: injects recent memory context from harness recall.
# ABOUTME: Derives project slug from git toplevel of .cwd; falls back to basename of cwd.
# ABOUTME: Emits a session_start event with injected_memories[] (top-3 snippets, ≤200 chars each).
# ABOUTME: Outputs hookSpecificOutput JSON to stdout when memories are found; silent otherwise.
# ABOUTME: Fail-open: timeout, recall error, missing tools, or empty output → exit 0 silently.

set -uo pipefail
trap 'exit 0' ERR

# Guard: jq required (used for JSON output and event payload construction)
command -v jq >/dev/null 2>&1 || exit 0

# ── Constants ─────────────────────────────────────────────────────────────────
_RECALL_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
_RECALL_HARNESS="${HARNESS_RECALL_BIN:-${HOME}/.claude/bin/harness}"
_RECALL_TIMEOUT_SECS="${HARNESS_RECALL_TIMEOUT_SECS:-2}"
_RECALL_TOP_N=3

# ── Source timeout helper (fail-open if absent) ───────────────────────────────
# Purpose: provides _run_with_timeout for capping harness recall wall time.
# Gotcha: must be sourced before emit-event.sh to avoid double-source issues.
_RECALL_TIMEOUT_SH="${_RECALL_SCRIPT_DIR}/lib/timeout.sh"
if [[ -f "$_RECALL_TIMEOUT_SH" ]]; then
  # shellcheck disable=SC1090
  source "$_RECALL_TIMEOUT_SH" 2>/dev/null || true
fi

# ── Source event emitter ──────────────────────────────────────────────────────
# Purpose: emit session_start events with injected_memories payload.
# Gotcha: STATE env must be set BEFORE sourcing so _EMIT_STATE_DIR is resolved correctly.
_RECALL_EMIT_SH="${_RECALL_SCRIPT_DIR}/lib/emit-event.sh"
if [[ -f "$_RECALL_EMIT_SH" ]]; then
  # shellcheck disable=SC1090
  source "$_RECALL_EMIT_SH" 2>/dev/null || true
fi

# ── Slug resolution ───────────────────────────────────────────────────────────
# Purpose: derive project slug for the recall query from the hook's cwd field.
# Usage: reads HOOK_STDIN_JSON .cwd; if absent falls back to $PWD.
# Gotcha: git rev-parse may be absent or fail (no repo) — basename fallback required.

_recall_cwd=""
if [[ -n "${HOOK_STDIN_JSON:-}" ]]; then
  _recall_cwd="$(printf '%s' "$HOOK_STDIN_JSON" | jq -r '.cwd // empty' 2>/dev/null || true)"
fi
[[ -z "$_recall_cwd" ]] && _recall_cwd="${PWD:-/tmp}"

# Try git toplevel first; basename of cwd as fallback
_recall_slug=""
_recall_git_top="$(git -C "$_recall_cwd" rev-parse --show-toplevel 2>/dev/null || true)"
if [[ -n "$_recall_git_top" ]]; then
  _recall_slug="$(basename "$_recall_git_top")"
else
  _recall_slug="$(basename "$_recall_cwd")"
fi
[[ -z "$_recall_slug" ]] && _recall_slug="unknown"

# ── Run harness recall with timeout ──────────────────────────────────────────
# Purpose: retrieve top-N recent context/decision snippets for this project.
# Gotcha: harness may not be installed; always fail-open.
_recall_raw=""
if [[ -x "$_RECALL_HARNESS" ]]; then
  _recall_query="${_recall_slug} recent context decisions"
  if declare -f _run_with_timeout >/dev/null 2>&1; then
    _recall_raw="$(_run_with_timeout "$_RECALL_TIMEOUT_SECS" \
      "$_RECALL_HARNESS" recall "$_recall_query" "$_RECALL_TOP_N" 2>/dev/null || true)"
  else
    _recall_raw="$("$_RECALL_HARNESS" recall "$_recall_query" "$_RECALL_TOP_N" 2>/dev/null || true)"
  fi
fi

# ── Build injected_memories JSON array ───────────────────────────────────────
# Purpose: truncate each line to ≤200 chars, build a JSON array for the event payload.
# Gotcha: jq --arg handles all JSON escaping; we never interpolate raw strings.

_recall_memories_json="[]"
if [[ -n "$_recall_raw" ]]; then
  # Read up to top_n non-empty lines, each truncated to 200 chars
  _recall_memories_json="$(printf '%s' "$_recall_raw" | \
    grep -v '^[[:space:]]*$' | \
    head -n "$_RECALL_TOP_N" | \
    python3 -c "
import sys, json
lines = [l.rstrip('\n')[:200] for l in sys.stdin]
print(json.dumps(lines))
" 2>/dev/null || echo "[]")"
fi

# Validate it's actually a JSON array (fail-open if python3 absent/failed)
if ! printf '%s' "$_recall_memories_json" | jq -e 'type == "array"' >/dev/null 2>&1; then
  _recall_memories_json="[]"
fi

# ── Emit session_start event with injected_memories ──────────────────────────
# Purpose: record recall outcome in the Pillar I telemetry spine regardless of hit/miss.
# Gotcha: emit_event is only available if emit-event.sh was sourced above.
if declare -f emit_event >/dev/null 2>&1; then
  _recall_payload="$(jq -cn \
    --arg slug "$_recall_slug" \
    --argjson mems "$_recall_memories_json" \
    '{"trigger":"SessionStart","source":"20-recall.sh","slug":$slug,"injected_memories":$mems}' \
    2>/dev/null || echo '{"trigger":"SessionStart","source":"20-recall.sh","injected_memories":[]}')"
  emit_event "session_start" "$_recall_payload" source="20-recall.sh" || true
fi

# ── Output hook context JSON ──────────────────────────────────────────────────
# Purpose: inject memories as additionalContext into the SessionStart hook output
#   so Claude Code surfaces them to the model at session start.
# Gotcha: only emit stdout when we have actual memories — empty output is preferred
#   over an empty [Memory] block which adds noise.
_recall_mem_count="$(printf '%s' "$_recall_memories_json" | jq 'length' 2>/dev/null || echo 0)"
if [[ "$_recall_mem_count" -gt 0 ]]; then
  _recall_context_text="$(printf '%s' "$_recall_memories_json" | \
    jq -r --arg slug "$_recall_slug" \
    '"[Memory] Top context for \($slug):\n" + (to_entries[] | "  \(.key+1). \(.value)") ' \
    2>/dev/null || true)"

  if [[ -n "$_recall_context_text" ]]; then
    jq -cn \
      --arg ctx "$_recall_context_text" \
      --arg event "SessionStart" \
      '{"hookSpecificOutput":{"hookEventName":$event,"additionalContext":$ctx}}' \
      2>/dev/null || true
  fi
fi

exit 0
