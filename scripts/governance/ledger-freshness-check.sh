#!/usr/bin/env bash
# ABOUTME: Stop hook (PKT-JD-03): blocks a completion claim when the most recent
# ABOUTME: test-run event in the session's events.ndjson ledger recorded a FAILURE.
# ABOUTME: Closes the "passed once, then broke, then claimed done without re-running" gap.
# ABOUTME: Fail-open: missing/empty/corrupt ledger, no test-run events, or any parse
# ABOUTME: error all result in exit 0 (allow). Read-only consumer of events.ndjson.

set -uo pipefail

# Safety net: any unexpected error → fail-open so we never block real work.
trap 'exit 0' ERR

# Bail gracefully if jq is missing.
if ! command -v jq &>/dev/null; then
  exit 0
fi

# ─── Read stdin JSON (identity must come from here — never env, per hook-authoring doctrine) ──
INPUT=$(cat)

# ─── Extract session_id from stdin payload ────────────────────────────────────
SESSION_ID=$(printf '%s' "$INPUT" | jq -r '.session_id // empty' 2>/dev/null) || SESSION_ID=""

# If session_id is missing or "unknown", we cannot filter the ledger meaningfully → allow.
if [[ -z "$SESSION_ID" || "$SESSION_ID" == "unknown" ]]; then
  exit 0
fi

# ─── Extract the last assistant message text from the transcript ──────────────
TRANSCRIPT=$(printf '%s' "$INPUT" | jq -r '.transcript_path // empty' 2>/dev/null) || TRANSCRIPT=""
if [[ ! -f "$TRANSCRIPT" ]]; then
  exit 0
fi

LAST=$(tail -80 "$TRANSCRIPT" | jq -rs '
  [ .[] | select(.type=="assistant") | .message.content
    | if type=="array" then (map(select(.type=="text") | .text) | join(" ")) else . end
  ] | last // empty' 2>/dev/null) || LAST=""
[[ -z "$LAST" ]] && exit 0

# ─── Completion-claim detection: source CLAIM regex from completion-claim-guard ──
# Per spec: reuse the CLAIM regex; extract it from the guard — single source of truth.
# Fall back to a minimal regex if extraction fails (fail-open for claim detection only).
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CCG="${SCRIPT_DIR}/../completion-claim-guard.sh"
CLAIM=""
if [[ -f "$CCG" ]]; then
  _claim_line="$(grep -m1 "^CLAIM='" "$CCG" 2>/dev/null)" || _claim_line=""
  if [[ -n "$_claim_line" ]]; then
    eval "$_claim_line" 2>/dev/null || CLAIM=""
  fi
fi
# Minimal fallback.
if [[ -z "$CLAIM" ]]; then
  CLAIM='(all tests? pass(ed)?|implementation (is )?complete|task is (done|complete|finished)|completed successfully|everything works|\ball done\b|\bLGTM\b|ready (for review|to merge))'
fi

# If the last message contains no completion claim, nothing to check — fast exit.
if ! printf '%s' "$LAST" | grep -qiE "$CLAIM"; then
  exit 0
fi

# ─── Resolve ledger path (HARNESS_STATE_OVERRIDE for test isolation) ─────────
# Primary: global durable ledger at ~/.claude/state/state/events.ndjson (where
# emit-event.sh writes — see emit-event.sh: _EMIT_STATE_DIR=~/.claude/state, then
# the ledger is appended at $_EMIT_STATE_DIR/state/events.ndjson).
# HARNESS_STATE_OVERRIDE replaces the parent dir (mirrors completion-claim-guard pattern).
if [[ -n "${HARNESS_STATE_OVERRIDE:-}" ]]; then
  LEDGER_PATH="${HARNESS_STATE_OVERRIDE}/state/events.ndjson"
else
  LEDGER_PATH="${HOME}/.claude/state/state/events.ndjson"
fi

# ─── Fail-open: if ledger is absent or empty, allow ──────────────────────────
if [[ ! -f "$LEDGER_PATH" || ! -s "$LEDGER_PATH" ]]; then
  exit 0
fi

# ─── Find the most recent test-run trust_decision event for this session ──────
# We grep for lines containing the session_id AND "trust_decision" AND "test-run"
# classification, then pick the last one (most recent). Gracefully skip malformed lines.
#
# Event shape (from emit-event.sh schema v1):
#   {"ts":"...","schema":1,"session_id":"<sid>","event_type":"trust_decision",
#    "payload":{"classification":"test-run",...},"outcome":"<pass|fail>", ...}
#
# Use jq to parse each candidate line; grep pre-filters to avoid parsing the entire ledger.

MOST_RECENT_OUTCOME=""

# Pre-filter: only lines mentioning session_id + test-run (fast grep pass over large file).
# Then parse with jq, picking the last valid event.
MOST_RECENT_OUTCOME=$(
  grep -F "\"$SESSION_ID\"" "$LEDGER_PATH" 2>/dev/null \
  | grep '"test-run"' \
  | while IFS= read -r line; do
      # Parse and check event_type=trust_decision + payload.classification=test-run.
      printf '%s' "$line" | jq -r '
        select(
          .session_id != null and
          .event_type == "trust_decision" and
          (.payload.classification // "") == "test-run"
        ) | .outcome // empty
      ' 2>/dev/null || true
    done \
  | tail -1
) || MOST_RECENT_OUTCOME=""

# ─── Decision ─────────────────────────────────────────────────────────────────
# Fail-open: no test-run events found → allow (ledger may not have test-run events yet).
if [[ -z "$MOST_RECENT_OUTCOME" ]]; then
  exit 0
fi

# If the most recent test-run outcome is "fail" → block the completion claim.
if [[ "$MOST_RECENT_OUTCOME" == "fail" ]]; then
  jq -cn --arg sid "$SESSION_ID" \
    '{"decision":"block","reason":("ledger-freshness-check (PKT-JD-03): the most recent test-run event in this session recorded a FAILURE. Re-run the tests and confirm they pass before claiming completion. (session: "+$sid+")")}'
  exit 0
fi

# Any other outcome (pass, ok, or unrecognised) → allow.
exit 0
