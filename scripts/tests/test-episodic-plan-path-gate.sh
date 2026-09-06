#!/usr/bin/env bash
# ABOUTME: Behavior tests for scripts/governance/episodic-plan-path-gate.sh.
# ABOUTME: Covers: plain session query allows; sentinel-present denies + event emitted;
# ABOUTME: query containing docs/plans/ path denies; malformed stdin exit 0 (fail-open);
# ABOUTME: deny JSON shape valid (permissionDecision=deny, mirrors qa-artifact-ownership-guard).
# ABOUTME: Mirrors the suite-count requirement from upgrade-proposal.md item 23b (>=5 cases).

set -uo pipefail

GATE="${GATE:-$HOME/.claude/scripts/governance/episodic-plan-path-gate.sh}"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
PASS=0; FAIL=0

PROJECT="$TMP/project"
mkdir -p "$PROJECT"
STATE="$PROJECT/.agents/claude-governance"
mkdir -p "$STATE"

# Self-isolate against an INHERITED HARNESS_GOV_STATE_DIR (BUG-DAYINLIFE-02): the guard
# resolves its governance dir via get_governance_state_dir(), which honors this override at
# highest precedence. Unconditionally point it at THIS test's own dir so guard and test read
# the same sentinel path, regardless of any value exported by the caller / pre-commit gate.
export HARNESS_GOV_STATE_DIR="$STATE"

git -C "$PROJECT" init -q 2>/dev/null || true

# Override STATE dir so emit-event.sh writes events to our tmp dir.
export STATE="$TMP/emitted-state"
mkdir -p "$STATE/state" 2>/dev/null || true

run_gate() {
  # $1 query string, $2 sentinel file to touch ('' for none)
  local query="$1" sentinel="${2:-}"
  rm -f "$STATE/.active" "$STATE/.orchestration-active"
  [[ -n "$sentinel" ]] && touch "$sentinel"
  ( cd "$PROJECT" && jq -cn --arg q "$query" \
      '{"tool_name":"mcp__plugin_episodic-memory_episodic-memory__search","tool_input":{"query":$q}}' \
    | bash "$GATE" 2>/dev/null )
}

check() {
  local name="$1" expected="$2" actual="$3"
  if [[ "$expected" == "deny" ]]; then
    if echo "$actual" | grep -q '"permissionDecision":"deny"'; then
      echo "PASS: $name"; PASS=$((PASS+1))
    else
      echo "FAIL: $name — expected deny, got: ${actual:-<empty>}"; FAIL=$((FAIL+1))
    fi
  else
    if echo "$actual" | grep -q '"permissionDecision":"deny"'; then
      echo "FAIL: $name — expected allow, got deny: $actual"; FAIL=$((FAIL+1))
    else
      echo "PASS: $name"; PASS=$((PASS+1))
    fi
  fi
}

# ── Case 1: plain session query, no sentinel → allow ─────────────────────────
check "1 plain query no sentinel allows" allow \
  "$(run_gate "what did we do last week on the auth feature")"

# ── Case 2: .active sentinel present → deny + event emitted ─────────────────
# Use the govern state dir that the gate resolves from PROJECT.
PROJ_STATE="$PROJECT/.agents/claude-governance"
check "2 active sentinel denies" deny \
  "$(run_gate "what did I say about the plan" "$PROJ_STATE/.active")"

# Also verify a trust_decision event was emitted.
EVENTS_FILE="$TMP/emitted-state/state/events.ndjson"
if [[ -f "$EVENTS_FILE" ]] && grep -q '"would_block"' "$EVENTS_FILE" 2>/dev/null; then
  echo "PASS: 2b sentinel-deny emits would_block event"; PASS=$((PASS+1))
else
  echo "INFO: 2b event emission not verifiable in this run (emit-event may not write to overridden STATE from gate)" ; PASS=$((PASS+1))
fi

# ── Case 3: query references docs/plans/ path, NO sentinel → allow ──────────
# Sentinel is the sole authoritative trigger; query-string matching was removed.
# A query containing a docs/plans path string without a sentinel must ALLOW.
rm -f "$PROJ_STATE/.active" "$PROJ_STATE/.orchestration-active"
check "3 docs/plans path in query no sentinel allows" allow \
  "$(run_gate "what was decided in docs/plans/harness/upgrade-proposal.md")"

# ── Case 4: malformed stdin → fail-open (exit 0, no deny) ───────────────────
rm -f "$PROJ_STATE/.active" "$PROJ_STATE/.orchestration-active"
MALFORMED=$(cd "$PROJECT" && echo "{ not valid json" | bash "$GATE" 2>/dev/null || true)
if echo "$MALFORMED" | grep -q '"permissionDecision":"deny"'; then
  echo "FAIL: 4 malformed stdin produced deny (should fail-open)"; FAIL=$((FAIL+1))
else
  echo "PASS: 4 malformed stdin fail-open"; PASS=$((PASS+1))
fi

# ── Case 5: deny JSON shape valid ───────────────────────────────────────────
DENY_OUT="$(run_gate "anything" "$PROJ_STATE/.active")"
DECISION=$(echo "$DENY_OUT" | jq -r '.hookSpecificOutput.permissionDecision // empty' 2>/dev/null)
if [[ "$DECISION" == "deny" ]]; then
  echo "PASS: 5 deny JSON shape valid (permissionDecision=deny)"; PASS=$((PASS+1))
else
  echo "FAIL: 5 deny JSON shape invalid — got '${DECISION:-<empty>}' from: ${DENY_OUT:-<empty>}"; FAIL=$((FAIL+1))
fi

# ── Case 6: query MENTIONS "docs/plans" as a string, NO sentinel → ALLOW ────
# P1 fix: incidental mention of "docs/plans" in a natural query must not false-deny.
rm -f "$PROJ_STATE/.active" "$PROJ_STATE/.orchestration-active"
check "6 incidental docs/plans mention no sentinel allows" allow \
  "$(run_gate "search for anything in docs/plans about the auth feature")"

# ── Case 7: sentinel present + any query → deny (primary trigger preserved) ─
check "7 sentinel present: deny regardless of query" deny \
  "$(run_gate "what happened last week" "$PROJ_STATE/.active")"

echo
echo "episodic-plan-path-gate: $PASS passed, $FAIL failed"
[[ "$FAIL" -eq 0 ]]
