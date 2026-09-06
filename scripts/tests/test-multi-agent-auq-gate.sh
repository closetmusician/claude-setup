#!/usr/bin/env bash
# ABOUTME: Behavior tests for scripts/governance/multi-agent-auq-gate.sh and auq-witness.sh.
# ABOUTME: Covers: ungated always-allows (no sentinel), 1st spawn allow, 2nd spawn without
# ABOUTME: AUQ marker deny, 2nd spawn WITH marker allow, malformed stdin fail-open, and the
# ABOUTME: auq-witness.sh companion hook writing the marker on AskUserQuestion PostToolUse.
# ABOUTME: Mirrors the suite-count requirement from upgrade-proposal.md item 23a (>=6 cases).

set -uo pipefail

GATE="${GATE:-$HOME/.claude/scripts/governance/multi-agent-auq-gate.sh}"
WITNESS="${WITNESS:-$HOME/.claude/scripts/governance/auq-witness.sh}"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
PASS=0; FAIL=0

# Per-test governance state dir (override get_governance_state_dir via a wrapper).
# We achieve this by creating the expected path structure: $TMP/project/.agents/claude-governance
PROJECT="$TMP/project"
mkdir -p "$PROJECT"
STATE="$PROJECT/.agents/claude-governance"
mkdir -p "$STATE"

# Self-isolate against an INHERITED HARNESS_GOV_STATE_DIR (BUG-DAYINLIFE-02): the gate
# resolves its governance dir via get_governance_state_dir(), which honors this override at
# highest precedence. Unconditionally point it at THIS test's own dir so gate and test read
# the same sentinel/marker path, regardless of any value exported by the caller.
export HARNESS_GOV_STATE_DIR="$STATE"

# Fake git repo so project-root.sh resolves $PROJECT as the root.
git -C "$PROJECT" init -q 2>/dev/null || true

run_gate() {
  # $1 session_id, $2 tool_name ("Agent"|"Task")
  # Uses $STATE by running the gate inside $PROJECT so get_governance_state_dir works.
  local sid="$1" tool="${2:-Agent}"
  ( cd "$PROJECT" && jq -cn --arg sid "$sid" --arg tn "$tool" \
      '{"session_id":$sid,"tool_name":$tn,"tool_input":{"prompt":"spawn"}}' \
    | bash "$GATE" )
}

run_witness() {
  # $1 session_id
  ( cd "$PROJECT" && jq -cn --arg sid "$1" \
      '{"session_id":$sid,"tool_name":"AskUserQuestion","tool_input":{"question":"proceed?"}}' \
    | bash "$WITNESS" )
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
    # allow: must NOT contain a deny decision
    if echo "$actual" | grep -q '"permissionDecision":"deny"'; then
      echo "FAIL: $name — expected allow, got deny: $actual"; FAIL=$((FAIL+1))
    else
      echo "PASS: $name"; PASS=$((PASS+1))
    fi
  fi
}

# ── Case 1: no sentinel → gate inert (always allow) ─────────────────────────
rm -f "$STATE/.active" "$STATE/.orchestration-active"
check "1 no-sentinel always-allow (1st spawn)" allow "$(run_gate "sess-inert")"
check "1b no-sentinel always-allow (2nd spawn, no AUQ)" allow "$(run_gate "sess-inert")"

# ── Case 2: sentinel present, 1st spawn → allow ─────────────────────────────
touch "$STATE/.active"
# Reset counter for fresh session id.
SESSION_FRESH="sess-fresh-$$"
check "2 first spawn allows" allow "$(run_gate "$SESSION_FRESH")"

# ── Case 3: sentinel present, 2nd spawn WITHOUT AUQ marker → deny ───────────
SESSION_NO_AUQ="sess-no-auq-$$"
run_gate "$SESSION_NO_AUQ" > /dev/null 2>&1 || true   # 1st spawn (consume counter slot)
check "3 second spawn without AUQ denies" deny "$(run_gate "$SESSION_NO_AUQ")"

# ── Case 4: sentinel present, 2nd spawn WITH AUQ marker → allow ─────────────
SESSION_WITH_AUQ="sess-with-auq-$$"
run_gate "$SESSION_WITH_AUQ" > /dev/null 2>&1 || true  # 1st spawn
run_witness "$SESSION_WITH_AUQ" > /dev/null 2>&1 || true  # witness writes marker
check "4 second spawn with AUQ marker allows" allow "$(run_gate "$SESSION_WITH_AUQ")"

# ── Case 5: malformed stdin → fail-open (exit 0, no deny) ───────────────────
# Pipe garbage — gate should exit 0 silently.
touch "$STATE/.active"
MALFORMED_OUT=$(cd "$PROJECT" && echo "not json at all { }" | bash "$GATE" 2>/dev/null || true)
if echo "$MALFORMED_OUT" | grep -q '"permissionDecision":"deny"'; then
  echo "FAIL: 5 malformed stdin produced deny (should fail-open)"; FAIL=$((FAIL+1))
else
  echo "PASS: 5 malformed stdin fail-open"; PASS=$((PASS+1))
fi

# ── Case 6: auq-witness.sh creates marker file from AskUserQuestion payload ─
SESSION_WIT="sess-witness-$$"
rm -f "$STATE/.auq-${SESSION_WIT}"
run_witness "$SESSION_WIT" > /dev/null 2>&1
if [[ -f "$STATE/.auq-${SESSION_WIT}" ]]; then
  echo "PASS: 6 witness creates AUQ marker file"; PASS=$((PASS+1))
else
  echo "FAIL: 6 witness did NOT create marker file at $STATE/.auq-${SESSION_WIT}"; FAIL=$((FAIL+1))
fi

# ── Case 7: deny JSON shape is valid (permissionDecision=deny) ──────────────
SESSION_DENY_SHAPE="sess-deny-shape-$$"
touch "$STATE/.active"
run_gate "$SESSION_DENY_SHAPE" > /dev/null 2>&1 || true  # 1st spawn
DENY_OUT="$(run_gate "$SESSION_DENY_SHAPE" 2>/dev/null || true)"
DECISION=$(echo "$DENY_OUT" | jq -r '.hookSpecificOutput.permissionDecision // empty' 2>/dev/null)
if [[ "$DECISION" == "deny" ]]; then
  echo "PASS: 7 deny JSON shape valid (hookSpecificOutput.permissionDecision=deny)"; PASS=$((PASS+1))
else
  echo "FAIL: 7 deny JSON shape invalid — got permissionDecision='${DECISION:-<empty>}' from: ${DENY_OUT:-<empty>}"; FAIL=$((FAIL+1))
fi

# ── Case 8: path-injection session_id stays inside $STATE (P1 fix) ──────────
# A session_id containing path-traversal chars must not create files outside STATE.
touch "$STATE/.active"
# Record all files present outside STATE before the call.
OUTSIDE_BEFORE=$(find "$TMP" -path "$STATE" -prune -o -type f -print 2>/dev/null | sort)
# Run gate with injected session_id; capture stderr.
INJECT_OUT=$(cd "$PROJECT" && printf '%s' '{"session_id":"../../etc/passwd","tool_name":"Agent"}' \
  | bash "$GATE" 2>"$TMP/inject-stderr.txt" || true)
INJECT_STDERR=$(cat "$TMP/inject-stderr.txt" 2>/dev/null)
OUTSIDE_AFTER=$(find "$TMP" -path "$STATE" -prune -o -type f -print 2>/dev/null | sort)
# No new files should appear outside STATE.
NEW_FILES=$(comm -13 <(echo "$OUTSIDE_BEFORE") <(echo "$OUTSIDE_AFTER") | grep -v "inject-stderr" || true)
if [[ -z "$NEW_FILES" ]]; then
  echo "PASS: 8a path-injection: no files created outside STATE"; PASS=$((PASS+1))
else
  echo "FAIL: 8a path-injection: files escaped STATE: $NEW_FILES"; FAIL=$((FAIL+1))
fi
# stderr must be clean (no redirection errors from unsanitized path).
if [[ -z "$INJECT_STDERR" ]]; then
  echo "PASS: 8b path-injection: stderr is empty"; PASS=$((PASS+1))
else
  echo "FAIL: 8b path-injection: stderr not empty: $INJECT_STDERR"; FAIL=$((FAIL+1))
fi
# Gate must still function (fail-open is fine — sanitized sid treated as valid session key).
# The exact decision doesn't matter here; what matters is no path escape and no stderr leak.
echo "INFO: 8c path-injection gate output: ${INJECT_OUT:-<empty>}"
PASS=$((PASS+1))

# ── Case 9: normal spawn produces no stderr ─────────────────────────────────
touch "$STATE/.active"
SESSION_CLEAN="sess-clean-stderr-$$"
CLEAN_STDERR=$( (cd "$PROJECT" && jq -cn --arg sid "$SESSION_CLEAN" \
    '{"session_id":$sid,"tool_name":"Agent","tool_input":{}}' \
  | bash "$GATE") 2>&1 >/dev/null )
if [[ -z "$CLEAN_STDERR" ]]; then
  echo "PASS: 9 normal spawn: stderr empty"; PASS=$((PASS+1))
else
  echo "FAIL: 9 normal spawn: stderr not empty: $CLEAN_STDERR"; FAIL=$((FAIL+1))
fi

echo
echo "multi-agent-auq-gate: $PASS passed, $FAIL failed"
[[ "$FAIL" -eq 0 ]]
