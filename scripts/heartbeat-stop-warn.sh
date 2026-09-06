#!/usr/bin/env bash
# ABOUTME: Stop hook (warn-only, NEVER blocks): detects idle-promise pattern — the session's
# ABOUTME: final message promises future work ("I'll", "I will", "next I", etc.) while no
# ABOUTME: artifact-bearing tool calls occurred in the final N turns. Emits a trust_decision
# ABOUTME: {class:"idle-promise"} event and prints a systemMessage-style warning if possible.
# ABOUTME: Fail-open on ALL errors (set -uo pipefail + trap exit 0). Never outputs a block.

set -uo pipefail
trap 'exit 0' ERR

command -v jq >/dev/null 2>&1 || exit 0

_HB_EMIT_SH="${HOME}/.claude/scripts/lib/emit-event.sh"
# shellcheck disable=SC1090
[[ -f "$_HB_EMIT_SH" ]] && source "$_HB_EMIT_SH" 2>/dev/null || true
unset _HB_EMIT_SH

INPUT=$(cat)

TRANSCRIPT=$(echo "$INPUT" | jq -r '.transcript_path // empty' 2>/dev/null)
[[ -f "$TRANSCRIPT" ]] || exit 0

# ── Final N turns window ─────────────────────────────────────────────────────
# Examine only the last 10 message objects from the transcript for recency.
WINDOW_SIZE=10

# Last assistant message text.
LAST_ASSISTANT=$(tail -"$WINDOW_SIZE" "$TRANSCRIPT" 2>/dev/null | jq -rs '
  [ .[] | select(.type=="assistant") | .message.content
    | if type=="array" then (map(select(.type=="text") | .text) | join(" ")) else . end
  ] | last // empty' 2>/dev/null)
[[ -z "$LAST_ASSISTANT" ]] && exit 0

# ── Promise detection ────────────────────────────────────────────────────────
PROMISE_REGEX="(I'?ll |I will |let me know when|next I|once you)"
if ! echo "$LAST_ASSISTANT" | grep -qiE "$PROMISE_REGEX"; then
  # No future-work promise — nothing to warn about.
  exit 0
fi

# ── Artifact detection in final window ──────────────────────────────────────
# An "artifact" is a Write or tool_use result for any file-producing tool appearing
# in the recent window. Detect via tool_use entries with type=tool_use.
# Also accept any mention of an artifact path in the window's tool_result content,
# an artifact path/file:line reference in the final assistant text itself,
# or a fenced code block in the final assistant text (all count as evidence).
ARTIFACT_REGEX='(~|/)[A-Za-z0-9._/-]{4,}(\.(md|log|txt|json|jsonl|html|png|sh)|:[0-9]+)'

HAS_ARTIFACT=0
# Check tool_use calls in the final window for Write/Edit tools (artifact producers).
TOOL_USES=$(tail -"$WINDOW_SIZE" "$TRANSCRIPT" 2>/dev/null | jq -r '
  select(.type=="assistant") | .message.content // []
  | map(select(.type=="tool_use") | .name) | .[]' 2>/dev/null | tr '\n' ' ')
if echo "$TOOL_USES" | grep -qiE '(Write|Edit|Bash)'; then
  HAS_ARTIFACT=1
fi

# Check for artifact paths in tool_result content in the final window.
if [[ "$HAS_ARTIFACT" -eq 0 ]]; then
  TOOL_RESULTS=$(tail -"$WINDOW_SIZE" "$TRANSCRIPT" 2>/dev/null | jq -r '
    select(.type=="user") | .message.content // []
    | map(select(.type=="tool_result") | .content) | .[]' 2>/dev/null)
  if echo "$TOOL_RESULTS" | grep -qiE "$ARTIFACT_REGEX"; then
    HAS_ARTIFACT=1
  fi
fi

# Check for artifact path/file:line reference or fenced code block in the final
# assistant message text itself. A message that contains evidence alongside a
# promise is NOT an idle-promise — it has accompanying work output.
if [[ "$HAS_ARTIFACT" -eq 0 ]]; then
  if echo "$LAST_ASSISTANT" | grep -qiE "$ARTIFACT_REGEX"; then
    HAS_ARTIFACT=1
  fi
fi
if [[ "$HAS_ARTIFACT" -eq 0 ]]; then
  # A fenced code block (``` ... ```) in the final text is treated as evidence.
  if echo "$LAST_ASSISTANT" | grep -qF '```'; then
    HAS_ARTIFACT=1
  fi
fi

if [[ "$HAS_ARTIFACT" -eq 1 ]]; then
  # Promise but artifact found — not idle; no warning.
  exit 0
fi

# ── Emit and warn ────────────────────────────────────────────────────────────
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // "unknown"' 2>/dev/null)

emit_event "trust_decision" \
  "{\"guard\":\"heartbeat-stop-warn\",\"class\":\"idle-promise\",\"session_id\":\"${SESSION_ID}\"}" \
  outcome="would_block" source="heartbeat-stop-warn.sh" || true

# Print a systemMessage-style warning (non-blocking — completion-claim-guard already owns
# the block contract; this hook ONLY warns). Output to stdout for the Stop-hook event
# channel (Claude Code surfaces hook stdout as system messages when output is JSON-shaped).
# If only block/allow JSON is parsed by the harness, this is ignored but does no harm.
jq -cn '{"type":"system","message":"heartbeat-stop-warn: final message promises future work but no artifact-producing tool calls were found in the recent window. Consider completing the work before stopping, or explicitly noting what is deferred and why."}'

exit 0
