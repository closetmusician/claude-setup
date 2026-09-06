#!/usr/bin/env bash
# ABOUTME: Two-part audit hook for the no-commit constraint (H-29 prevention).
# ABOUTME: Pre-mode (PreToolUse/Agent): detects no-commit token in prompt, records HEAD SHA.
# ABOUTME: Post-mode (PostToolUse/Agent): compares HEAD to recorded SHA; advises on mismatch.
# ABOUTME: Advisory-only (never blocks), fail-open on git unavailability or any error.
# ABOUTME: Keyed by session_id from stdin JSON; record files in ~/.claude/state/.

set -uo pipefail

# Safety net: fail-open on any unhandled error.
trap 'exit 0' ERR

# ── Dependency check ──────────────────────────────────────────────────────────
if ! command -v jq &>/dev/null; then
  echo "no-commit-headsha-audit: jq not found, skipping" >&2
  exit 0
fi

# ── Shared state dir (durable across sessions, per emit-event.sh §amendment) ─
STATE_DIR="${NOCOMMIT_STATE_DIR:-${HOME}/.claude/state}"

# ── Source emit-event for incident reporting ──────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/../lib/emit-event.sh" 2>/dev/null || true

# ── Read stdin — identity MUST come from stdin, never env ────────────────────
INPUT="$(cat)"

# ── Extract fields from hook payload ─────────────────────────────────────────
SESSION_ID="$(printf '%s' "$INPUT" | jq -r '.session_id // empty')"
HOOK_EVENT="$(printf '%s' "$INPUT" | jq -r '.hook_event_name // empty')"

# Determine mode: explicit $1 arg overrides (for tests); otherwise infer from hook_event_name.
# Pre = PreToolUse; Post = PostToolUse.
if [[ "${1:-}" == "pre" ]]; then
  MODE="pre"
elif [[ "${1:-}" == "post" ]]; then
  MODE="post"
elif echo "$HOOK_EVENT" | grep -qi 'pre'; then
  MODE="pre"
elif echo "$HOOK_EVENT" | grep -qi 'post'; then
  MODE="post"
else
  # Can't determine mode — fail-open
  exit 0
fi

# ── Sanitize session_id (no path traversal) ───────────────────────────────────
# Keep only alphanumerics, hyphens, underscores, dots.
SAFE_SID="$(printf '%s' "$SESSION_ID" | tr -cd 'a-zA-Z0-9_.-' | cut -c1-128)"
if [[ -z "$SAFE_SID" ]]; then
  # No session identity — fail-open (can't key a record)
  exit 0
fi

RECORD_FILE="${STATE_DIR}/nocommit-headsha-${SAFE_SID}.txt"

# ── Helper: resolve current HEAD SHA (fail-open if git unavailable) ───────────
get_head_sha() {
  if ! command -v git &>/dev/null; then
    echo ""
    return
  fi
  git rev-parse HEAD 2>/dev/null || echo ""
}

# ═══════════════════════════════════════════════════════════════════════════════
# PRE-MODE: detect no-commit token, record HEAD SHA if present.
# ═══════════════════════════════════════════════════════════════════════════════
if [[ "$MODE" == "pre" ]]; then
  # Extract prompt text from tool_input.prompt (Agent spawn payload).
  PROMPT="$(printf '%s' "$INPUT" | jq -r '.tool_input.prompt // empty')"

  if [[ -z "$PROMPT" ]]; then
    exit 0
  fi

  # Detect no-commit constraint tokens (case-insensitive).
  # Spec tokens: "no-commit", "do not commit", "NO-AUTO-COMMIT".
  if printf '%s' "$PROMPT" | grep -qiE '(no-commit|do not commit|NO-AUTO-COMMIT)'; then
    HEAD_SHA="$(get_head_sha)"
    if [[ -n "$HEAD_SHA" ]]; then
      mkdir -p "$STATE_DIR"
      printf '%s\n' "$HEAD_SHA" > "$RECORD_FILE"
    fi
    # Even if git is unavailable, we exit 0 — never block the spawn.
  fi

  exit 0
fi

# ═══════════════════════════════════════════════════════════════════════════════
# POST-MODE: compare current HEAD to recorded SHA, advise on mismatch.
# ═══════════════════════════════════════════════════════════════════════════════
if [[ "$MODE" == "post" ]]; then
  # No record file → this session was not flagged; nothing to check.
  if [[ ! -f "$RECORD_FILE" ]]; then
    exit 0
  fi

  # Read the recorded SHA; guard empty reads.
  OLD_SHA="$(cat "$RECORD_FILE" 2>/dev/null | tr -d '[:space:]')"

  # Always clean up the record file (one-shot per dispatch).
  rm -f "$RECORD_FILE" 2>/dev/null || true

  if [[ -z "$OLD_SHA" ]]; then
    exit 0
  fi

  # Get current HEAD.
  NEW_SHA="$(get_head_sha)"
  if [[ -z "$NEW_SHA" ]]; then
    # Git unavailable post-spawn — cannot compare; fail-open.
    exit 0
  fi

  # ── Compare ───────────────────────────────────────────────────────────────
  if [[ "$OLD_SHA" == "$NEW_SHA" ]]; then
    # No change — constraint respected.
    exit 0
  fi

  # ── Mismatch: emit advisory to stderr and P1 incident event ───────────────
  SHORT_OLD="${OLD_SHA:0:12}"
  SHORT_NEW="${NEW_SHA:0:12}"

  ADVISORY="[no-commit-headsha-audit] P1 INCIDENT: executor committed under a no-commit constraint (${SHORT_OLD}→${SHORT_NEW}); inspect \`git show --stat ${SHORT_NEW}\` — keep if scope is trio-owned, revert if it swept unrelated files."
  printf '%s\n' "$ADVISORY" >&2

  # Also emit a spine incident event for telemetry.
  emit_event "incident" \
    "{\"rule\":\"no-commit-constraint\",\"old_sha\":\"${OLD_SHA}\",\"new_sha\":\"${NEW_SHA}\",\"action\":\"advise\",\"severity\":\"P1\"}" \
    outcome="denied" source="no-commit-headsha-audit.sh" || true

  exit 0
fi

# Fallback: unknown mode — fail-open.
exit 0
