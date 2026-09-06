#!/usr/bin/env bash
# ABOUTME: Phase 5.1 UserPromptSubmit hook — correction-capture sensor.
# ABOUTME: Detects user-correction patterns (gaslighting, restatements, complaints) and emits
# ABOUTME: a single 'correction' spine event via emit-event.sh. Log-only; never blocks.
# ABOUTME: Fail-open on every error path; budget ≤100ms, no model calls, no network.
# ABOUTME: DEVIATION NOTE (crosswalk Pillar I): spine event replaces the plan's corrections.jsonl
# ABOUTME:   sidecar (apply-master-plan.md §5.1). The event carries session/cwd/prompt/
# ABOUTME:   assistant_tail/rtk_suspect as payload fields, equivalent to the jsonl schema.
# ABOUTME:   Staged wiring note: settings.json UserPromptSubmit hooks array should be
# ABOUTME:   [correction-capture.sh, skill-retrieve.sh] — capture FIRST (plan §5.1 wire note
# ABOUTME:   + B6 ordering constraint from the adversarial review).

set -uo pipefail
# Fail-open: any unhandled error exits 0
trap 'exit 0' ERR

# Guard 1: jq must be present (everything downstream needs it)
command -v jq >/dev/null 2>&1 || exit 0

# ── Read stdin once ───────────────────────────────────────────────────────────
INPUT="$(cat 2>/dev/null || true)"
[ -z "$INPUT" ] && exit 0

# ── Extract prompt (.prompt is the production UserPromptSubmit field; .user_prompt
#    is a legacy fallback retained for backward compat with older fixture payloads).
#    CRITICAL: real UserPromptSubmit payloads carry .prompt NOT .user_prompt — a prior
#    defect shipped green tests on the wrong field (see PART2-verification.md P1-A).
#    jq expression: use .prompt if present and non-null; fall back to .user_prompt;
#    never let a present .prompt be overridden by .user_prompt.
# P1-PERF fix: cap extraction to the first 2000 chars directly in jq with [:2000].
#   Corrections always appear in the opening of the prompt; the detection regex is
#   anchored/early-matching.  A 1MB prompt otherwise creates a 1MB bash string and
#   blows the <100ms budget.  Slicing in jq avoids building the large string at all.
# Purpose: extract the user's prompt text (first 2000 chars) from hook stdin JSON.
# Usage: PROMPT is set to the (up to 2000 char) prompt slice, or empty on failure.
# Gotchas: .prompt takes priority; .user_prompt is legacy fallback only (never override
#   a present .prompt, even with a correction phrase in .user_prompt).
PROMPT="$(printf '%s' "$INPUT" | jq -r '(.prompt // .user_prompt // empty)[:2000]' 2>/dev/null || true)"
[ -z "$PROMPT" ] && exit 0

# Guard 2: skip slash commands
case "$PROMPT" in "/"*) exit 0 ;; esac

# Guard 3: skip very short prompts (<10 chars)
[ "${#PROMPT}" -lt 10 ] && exit 0

# ── Detection regex (case-insensitive ERE, seed set from apply-master-plan.md §5.1)
# Purpose: identify user-correction patterns indicating model error/gaslighting.
# Usage: tested with grep -qiE against the prompt (already capped to 2000 chars above).
# Gotchas: anchors (^) apply to the full string because we use grep -m1 on the single prompt.
#   The regex is verbatim from the plan — do NOT modify without updating the plan.
CORRECTION_REGEX='^no[,.!] |^no[,.!]$|i (already |just )?(said|told you|asked)|you (didn'"'"'?t|did not|never|failed to)|that'"'"'?s (not true|wrong|false|incorrect)|did you (actually|really|even)|show me (the |your )?(proof|evidence|output|diff)|stop (lying|guessing|making)|why did you (ignore|skip|not)|read (the|my) (instructions|prompt|CLAUDE)|not what i (asked|said|wanted)|as i (said|asked|instructed)|^again[:,]|^wrong[.,]'

# Test if prompt matches the correction regex
if ! printf '%s' "$PROMPT" | grep -qiE "$CORRECTION_REGEX" 2>/dev/null; then
  exit 0
fi

# ── Match confirmed — extract remaining fields ────────────────────────────────
SESSION="$(printf '%s' "$INPUT" | jq -r '.session_id // "unknown"' 2>/dev/null || echo "unknown")"
CWD="$(printf '%s' "$INPUT" | jq -r '.cwd // ""' 2>/dev/null || echo "")"
TRANSCRIPT="$(printf '%s' "$INPUT" | jq -r '.transcript_path // ""' 2>/dev/null || echo "")"

# Truncate prompt to 500 chars
PROMPT_TRUNC="${PROMPT:0:500}"

# ── Assistant tail extraction ─────────────────────────────────────────────────
# Purpose: capture the last assistant text from the transcript for correlation.
# Usage: same tail-40 | jq -rs extraction pattern as completion-claim-guard.sh.
# Gotchas: empty string on ANY parse failure (fail-open, never block).
ASSISTANT_TAIL=""
if [ -f "${TRANSCRIPT:-}" ]; then
  ASSISTANT_TAIL="$(tail -40 "$TRANSCRIPT" | jq -rs '
    [ .[] | select(.type=="assistant") | .message.content
      | if type=="array" then (map(select(.type=="text") | .text) | join(" ")) else . end
    ] | last // empty' 2>/dev/null || true)"
  # Truncate to 300 chars
  ASSISTANT_TAIL="${ASSISTANT_TAIL:0:300}"
fi

# ── rtk_suspect detection ─────────────────────────────────────────────────────
# Purpose: flag prompts that may be related to rtk output reformatting defects.
# Usage: true iff PROMPT matches rtk|reformat|mangl (case-insensitive).
RTK_SUSPECT="false"
if printf '%s' "$PROMPT" | grep -qiE 'rtk|reformat|mangl' 2>/dev/null; then
  RTK_SUSPECT="true"
fi

# ── Source event emitter and emit ONE spine event ────────────────────────────
# Purpose: emit a 'correction' spine event carrying all 5 payload fields.
# Usage: source emit-event.sh, then call emit_event once.
# Gotchas: emit-event.sh is fully fail-open; sourcing failure is also fail-open.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="${SCRIPT_DIR}/lib"

# shellcheck source=scripts/lib/emit-event.sh
# shellcheck disable=SC1091
source "${LIB_DIR}/emit-event.sh" 2>/dev/null || true

# Build the payload using jq --arg to safely escape all user-supplied strings.
# Purpose: construct the correction event payload as a valid JSON object.
# Usage: PAYLOAD is passed verbatim to emit_event.
# Gotchas: --arg escapes quotes, backslashes, and control chars; never interpolate raw strings.
PAYLOAD="$(jq -cn \
  --arg session   "$SESSION" \
  --arg cwd       "$CWD" \
  --arg prompt    "$PROMPT_TRUNC" \
  --arg atail     "$ASSISTANT_TAIL" \
  --argjson rtk   "$RTK_SUSPECT" \
  '{session: $session, cwd: $cwd, prompt: $prompt, assistant_tail: $atail, rtk_suspect: $rtk}' \
  2>/dev/null)" || true

[ -z "$PAYLOAD" ] && exit 0

# Emit the correction event; emit_event is fail-open and never writes to stdout.
if declare -f emit_event >/dev/null 2>&1; then
  emit_event "correction" "$PAYLOAD" source="correction-capture.sh" 2>/dev/null || true
fi

# MUST NOT block — always exit 0
exit 0
