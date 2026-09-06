#!/usr/bin/env bash
# ABOUTME: Behavior tests for scripts/heartbeat-stop-warn.sh (Stop hook, warn-only).
# ABOUTME: Covers: promise-no-artifact emits event; promise WITH artifact path in message
# ABOUTME: stays silent; no-promise message stays silent; malformed transcript fail-open.
# ABOUTME: Verifies: hook NEVER produces a {"decision":"block",...} output (warn-only contract).
# ABOUTME: Mirrors the suite-count requirement from upgrade-proposal.md item 23c (>=4 cases).

set -uo pipefail

GUARD="${GUARD:-$HOME/.claude/scripts/heartbeat-stop-warn.sh}"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
PASS=0; FAIL=0

# Override STATE so emit-event.sh writes to our tmp dir.
export STATE="$TMP/emit-state"
mkdir -p "$STATE/state" 2>/dev/null || true

# Build an NDJSON transcript whose last assistant message is $1.
# $2 (optional): extra raw JSON line to prepend (simulates tool_use or tool_result).
make_transcript() {
  local f="$TMP/transcript-$RANDOM.jsonl"
  jq -cn '{"type":"user","message":{"content":"start"}}' > "$f"
  [[ -n "${2:-}" ]] && printf '%s\n' "$2" >> "$f"
  jq -cn --arg t "$1" '{"type":"assistant","message":{"content":[{"type":"text","text":$t}]}}' >> "$f"
  echo "$f"
}

run_guard() {
  local tp="$1"
  jq -cn --arg tp "$tp" \
    '{"transcript_path":$tp,"session_id":"test-session-hb"}' \
  | bash "$GUARD" 2>/dev/null
}

check_no_block() {
  local name="$1" actual="$2"
  # Warn-only: must NEVER produce a block decision.
  if echo "$actual" | grep -q '"decision":"block"'; then
    echo "FAIL: $name — heartbeat MUST NOT block but got: $actual"; FAIL=$((FAIL+1))
  else
    echo "PASS: $name (no block)"; PASS=$((PASS+1))
  fi
}

check_event() {
  local name="$1"
  # Check events.ndjson for would_block from heartbeat-stop-warn.
  EVENTS="$STATE/state/events.ndjson"
  if [[ -f "$EVENTS" ]] && grep -q '"would_block"' "$EVENTS" 2>/dev/null && grep -q '"heartbeat-stop-warn"' "$EVENTS" 2>/dev/null; then
    echo "PASS: $name (would_block event emitted)"; PASS=$((PASS+1))
  else
    echo "FAIL: $name — expected would_block event in events.ndjson"; FAIL=$((FAIL+1))
  fi
}

# ── Case 1: promise + no artifact-producing tool calls → event emitted ───────
# Clear events first.
rm -f "$STATE/state/events.ndjson"
T=$(make_transcript "I'll implement the next part in the following turn once you confirm.")
OUT1="$(run_guard "$T")"
check_no_block "1a promise-no-artifact: no block" "$OUT1"
check_event "1b promise-no-artifact: would_block event"

# ── Case 2: promise WITH Write tool use in window → no event, no block ───────
rm -f "$STATE/state/events.ndjson"
# Simulate an assistant turn with a Write tool_use in the window.
WRITE_USE=$(jq -cn '{"type":"assistant","message":{"content":[{"type":"tool_use","id":"t1","name":"Write","input":{"file_path":"/tmp/out.md","content":"done"}}]}}')
T=$(make_transcript "I'll wrap up now — wrote the summary." "$WRITE_USE")
OUT2="$(run_guard "$T")"
check_no_block "2a promise-with-artifact: no block" "$OUT2"
# Should NOT emit a would_block event in this case.
EVENTS="$STATE/state/events.ndjson"
if [[ -f "$EVENTS" ]] && grep -q '"would_block"' "$EVENTS" 2>/dev/null && grep -q '"heartbeat-stop-warn"' "$EVENTS" 2>/dev/null; then
  echo "FAIL: 2b promise-with-artifact should NOT emit would_block event"; FAIL=$((FAIL+1))
else
  echo "PASS: 2b promise-with-artifact: no event"; PASS=$((PASS+1))
fi

# ── Case 3: no promise in final message → no event, no block ────────────────
rm -f "$STATE/state/events.ndjson"
T=$(make_transcript "Here is the analysis of the three options and their tradeoffs.")
OUT3="$(run_guard "$T")"
check_no_block "3a no-promise: no block" "$OUT3"
if [[ -f "$EVENTS" ]] && grep -q '"would_block"' "$EVENTS" 2>/dev/null && grep -q '"heartbeat-stop-warn"' "$EVENTS" 2>/dev/null; then
  echo "FAIL: 3b no-promise should NOT emit would_block event"; FAIL=$((FAIL+1))
else
  echo "PASS: 3b no-promise: no event"; PASS=$((PASS+1))
fi

# ── Case 4: malformed transcript → fail-open (no block, no crash) ───────────
echo "this is not json at all" > "$TMP/garbage.jsonl"
OUT4="$(run_guard "$TMP/garbage.jsonl")"
check_no_block "4 malformed transcript fail-open" "$OUT4"

# ── Case 5: promise + artifact path in assistant text → no event, no warn ────
# P2 fix: "I'll refactor next. Done for now — see foo.py:42" must NOT warn.
rm -f "$STATE/state/events.ndjson"
T=$(make_transcript "I'll refactor this next. Done for now — see /tmp/foo.py:42 for the result.")
OUT5="$(run_guard "$T")"
check_no_block "5a promise-with-artifact-path-in-text: no block" "$OUT5"
# Must NOT emit warn event.
EVENTS="$STATE/state/events.ndjson"
if [[ -f "$EVENTS" ]] && grep -q '"would_block"' "$EVENTS" 2>/dev/null && grep -q '"heartbeat-stop-warn"' "$EVENTS" 2>/dev/null; then
  echo "FAIL: 5b promise-with-artifact-path-in-text: must NOT emit would_block event"; FAIL=$((FAIL+1))
else
  echo "PASS: 5b promise-with-artifact-path-in-text: no event"; PASS=$((PASS+1))
fi
# Must produce empty stdout (no warning).
if [[ -z "$OUT5" ]]; then
  echo "PASS: 5c promise-with-artifact-path-in-text: stdout empty"; PASS=$((PASS+1))
else
  echo "FAIL: 5c promise-with-artifact-path-in-text: got stdout: ${OUT5}"; FAIL=$((FAIL+1))
fi

# ── Case 6: promise + code block in assistant text → no event, no warn ───────
# P2 fix: a message ending with a fenced code block must NOT warn.
rm -f "$STATE/state/events.ndjson"
CODE_MSG="I'll incorporate this fix. Here's the summary:
\`\`\`bash
echo hello
\`\`\`"
T=$(make_transcript "$CODE_MSG")
OUT6="$(run_guard "$T")"
check_no_block "6a promise-with-code-block: no block" "$OUT6"
EVENTS="$STATE/state/events.ndjson"
if [[ -f "$EVENTS" ]] && grep -q '"would_block"' "$EVENTS" 2>/dev/null && grep -q '"heartbeat-stop-warn"' "$EVENTS" 2>/dev/null; then
  echo "FAIL: 6b promise-with-code-block: must NOT emit would_block event"; FAIL=$((FAIL+1))
else
  echo "PASS: 6b promise-with-code-block: no event"; PASS=$((PASS+1))
fi
if [[ -z "$OUT6" ]]; then
  echo "PASS: 6c promise-with-code-block: stdout empty"; PASS=$((PASS+1))
else
  echo "FAIL: 6c promise-with-code-block: got stdout: ${OUT6}"; FAIL=$((FAIL+1))
fi

# ── Case 7: bare idle promise (no artifact anywhere) → warn event fires ───────
# Regression check: the classic idle-promise must still warn after the above fixes.
rm -f "$STATE/state/events.ndjson"
T=$(make_transcript "I'll get to it, let me know when you're ready.")
OUT7="$(run_guard "$T")"
check_no_block "7a bare-idle-promise: no block" "$OUT7"
check_event "7b bare-idle-promise: would_block event"
# Must produce a warning in stdout.
if echo "$OUT7" | grep -q '"type":"system"'; then
  echo "PASS: 7c bare-idle-promise: warning in stdout"; PASS=$((PASS+1))
else
  echo "FAIL: 7c bare-idle-promise: expected warning stdout, got: ${OUT7:-<empty>}"; FAIL=$((FAIL+1))
fi

echo
echo "heartbeat-stop-warn: $PASS passed, $FAIL failed"
[[ "$FAIL" -eq 0 ]]
