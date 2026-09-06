#!/usr/bin/env bash
# ABOUTME: Behavior tests for scripts/governance/parallel-scope-guard.sh (PreToolUse/Agent hook).
# ABOUTME: Covers: first spawn records paths, duplicate path denies, disjoint paths allow,
# ABOUTME: missing Output declaration fails-open, malformed stdin fails-open, prefix-overlap
# ABOUTME: denies, and neuter-and-fail proof that the overlap check is load-bearing.
# ABOUTME: All fixtures feed stdin JSON matching the real Claude Code PreToolUse payload shape.

set -uo pipefail

GUARD="${GUARD:-$HOME/.claude/scripts/governance/parallel-scope-guard.sh}"
TMP=$(mktemp -d)
GOV_STATE="$TMP/gov"
mkdir -p "$GOV_STATE"
trap 'rm -rf "$TMP"' EXIT
PASS=0; FAIL=0

# ── Helpers ──────────────────────────────────────────────────────────────────

# Build a realistic PreToolUse/Agent stdin payload.
# $1 = session_id, $2 = prompt text
make_payload() {
  local sid="$1" prompt="$2"
  jq -cn --arg sid "$sid" --arg prompt "$prompt" \
    '{"session_id":$sid,"tool_name":"Task","tool_input":{"prompt":$prompt},"agent_id":null}'
}

# Run the guard with a specific session state dir (isolated per test group via GOV_STATE).
run_guard() {
  HARNESS_GOV_STATE_DIR="$GOV_STATE" bash "$GUARD"
}

# Helpers for outcome checking.
is_deny() {
  echo "$1" | grep -q '"permissionDecision":"deny"'
}

check_allow() {
  local name="$1" out="$2" exit_code="$3"
  if [[ "$exit_code" -eq 0 ]] && ! is_deny "$out"; then
    echo "PASS: $name"; PASS=$((PASS+1))
  else
    echo "FAIL: $name — expected allow (exit 0, no deny block), got exit=$exit_code out=${out:-<empty>}"
    FAIL=$((FAIL+1))
  fi
}

check_deny() {
  local name="$1" out="$2" exit_code="$3"
  # Guard exits 0 even on deny (outputs hookSpecificOutput JSON); check message content.
  if [[ "$exit_code" -eq 0 ]] && is_deny "$out"; then
    echo "PASS: $name"; PASS=$((PASS+1))
  else
    echo "FAIL: $name — expected deny block, got exit=$exit_code out=${out:-<empty>}"
    FAIL=$((FAIL+1))
  fi
}

SID="testsession-psg-01"

# ── Test 1: First spawn with ## Output: declaration → ALLOW and path recorded ────
echo "--- Test 1: first spawn records path and allows ---"
PAYLOAD=$(make_payload "$SID" "Do some work.
## Output: docs/temp/foo.md
Build thing.")
OUT=$(echo "$PAYLOAD" | run_guard); RC=$?
check_allow "1 first spawn with Output: → allow" "$OUT" "$RC"

# Verify path was recorded in the claims file.
CLAIMS_FILE="$GOV_STATE/claimed-output-paths-${SID}.json"
if [[ -f "$CLAIMS_FILE" ]] && jq -e '.[] | select(. == "docs/temp/foo.md")' "$CLAIMS_FILE" >/dev/null 2>&1; then
  echo "PASS: 1b path recorded in claims file"; PASS=$((PASS+1))
else
  echo "FAIL: 1b docs/temp/foo.md not found in $CLAIMS_FILE"; FAIL=$((FAIL+1))
fi

# ── Test 2: Second spawn, SAME output path → DENY ────────────────────────────
echo "--- Test 2: duplicate output path → deny ---"
PAYLOAD=$(make_payload "$SID" "Another agent.
## Output: docs/temp/foo.md
Merge results.")
OUT=$(echo "$PAYLOAD" | run_guard); RC=$?
check_deny "2 duplicate Output: path → deny" "$OUT" "$RC"

# ── Test 3: Second spawn, DISJOINT output path → ALLOW ───────────────────────
echo "--- Test 3: disjoint output path → allow ---"
PAYLOAD=$(make_payload "$SID" "Different agent.
## Output: docs/temp/bar.md
Different work.")
OUT=$(echo "$PAYLOAD" | run_guard); RC=$?
check_allow "3 disjoint Output: path → allow" "$OUT" "$RC"

# ── Test 4: Spawn with NO ## Output: marker → FAIL-OPEN (allow) ──────────────
echo "--- Test 4: no Output declaration → fail-open allow ---"
PAYLOAD=$(make_payload "$SID" "Do work, but no output declaration here.")
OUT=$(echo "$PAYLOAD" | run_guard); RC=$?
check_allow "4 no Output: declaration → fail-open allow" "$OUT" "$RC"

# ── Test 5: Malformed stdin (not JSON) → FAIL-OPEN ───────────────────────────
echo "--- Test 5: malformed stdin → fail-open allow ---"
OUT=$(echo "this is not json at all" | run_guard); RC=$?
check_allow "5 malformed stdin → fail-open exit 0" "$OUT" "$RC"

# ── Test 6: PREFIX overlap — A declares docs/temp/x/, B declares docs/temp/x/y.md → DENY ──
echo "--- Test 6: prefix overlap → deny ---"
SID2="testsession-psg-02"
GOV_STATE2="$TMP/gov2"
mkdir -p "$GOV_STATE2"

# First spawn: declare directory prefix.
PAYLOAD=$(make_payload "$SID2" "First agent.
## Output: docs/temp/x
Main output dir.")
OUT=$(echo "$PAYLOAD" | HARNESS_GOV_STATE_DIR="$GOV_STATE2" bash "$GUARD"); RC=$?
check_allow "6a directory-prefix first spawn → allow" "$OUT" "$RC"

# Second spawn: declares a file inside that directory.
PAYLOAD=$(make_payload "$SID2" "Second agent.
## Output: docs/temp/x/y.md
Sub-file output.")
OUT=$(echo "$PAYLOAD" | HARNESS_GOV_STATE_DIR="$GOV_STATE2" bash "$GUARD"); RC=$?
check_deny "6b file inside declared directory → deny (prefix overlap)" "$OUT" "$RC"

# ── Test 7: NEUTER-AND-FAIL — comment out overlap check, Fixture B must fail ────
echo "--- Test 7: neuter-and-fail proof ---"
# Create a neutered version with the overlap comparison short-circuited.
NEUTERED="$TMP/neutered-guard.sh"
# Copy the original and neutralise the paths_overlap function so it never returns 0.
perl -pe 's|paths_overlap "\$new_path" "\$existing"|false|g' "$GUARD" > "$NEUTERED"
chmod +x "$NEUTERED"

SID3="testsession-psg-03"
GOV_STATE3="$TMP/gov3"
mkdir -p "$GOV_STATE3"

# First spawn to register the path.
PAYLOAD=$(make_payload "$SID3" "First spawn.
## Output: docs/temp/neuter-test.md
First output.")
OUT=$(echo "$PAYLOAD" | HARNESS_GOV_STATE_DIR="$GOV_STATE3" bash "$NEUTERED"); RC=$?
check_allow "7a neutered: first spawn → allow" "$OUT" "$RC"

# Duplicate path with NEUTERED guard — this must NOT deny (neuter worked).
PAYLOAD=$(make_payload "$SID3" "Second spawn, same path.
## Output: docs/temp/neuter-test.md
Overlapping output.")
OUT=$(echo "$PAYLOAD" | HARNESS_GOV_STATE_DIR="$GOV_STATE3" bash "$NEUTERED"); RC=$?
if [[ "$RC" -eq 0 ]] && ! is_deny "$OUT"; then
  echo "PASS: 7b neutered guard ALLOWS duplicate — overlap check is load-bearing (neuter confirmed)"; PASS=$((PASS+1))
else
  echo "FAIL: 7b neutered guard still blocked — neuter did not work: exit=$RC out=${OUT:-<empty>}"; FAIL=$((FAIL+1))
fi

# Now confirm the REAL guard blocks the same case (proves the check matters).
PAYLOAD=$(make_payload "$SID3" "Second spawn, same path.
## Output: docs/temp/neuter-test.md
Should be denied by real guard.")
# Reset state to only have the first claim (re-register first).
rm -rf "$GOV_STATE3" && mkdir -p "$GOV_STATE3"
PAYLOAD1=$(make_payload "$SID3" "First spawn again.
## Output: docs/temp/neuter-test.md
Register path.")
echo "$PAYLOAD1" | HARNESS_GOV_STATE_DIR="$GOV_STATE3" bash "$GUARD" >/dev/null 2>&1 || true
OUT=$(echo "$PAYLOAD" | HARNESS_GOV_STATE_DIR="$GOV_STATE3" bash "$GUARD"); RC=$?
check_deny "7c real guard DENIES same duplicate — confirms neuter exposed a real difference" "$OUT" "$RC"

# ── Test 8: Output file: back-compat marker → recorded and overlap-detected ──
echo "--- Test 8: 'Output file:' back-compat marker ---"
SID4="testsession-psg-04"
GOV_STATE4="$TMP/gov4"
mkdir -p "$GOV_STATE4"

PAYLOAD=$(make_payload "$SID4" "Agent using legacy marker.
Output file: docs/temp/legacy.md
Some work.")
OUT=$(echo "$PAYLOAD" | HARNESS_GOV_STATE_DIR="$GOV_STATE4" bash "$GUARD"); RC=$?
check_allow "8a Output file: first spawn → allow" "$OUT" "$RC"

PAYLOAD=$(make_payload "$SID4" "Second agent, same legacy path.
Output file: docs/temp/legacy.md
Overlap via legacy marker.")
OUT=$(echo "$PAYLOAD" | HARNESS_GOV_STATE_DIR="$GOV_STATE4" bash "$GUARD"); RC=$?
check_deny "8b Output file: duplicate → deny (back-compat overlap detected)" "$OUT" "$RC"

# ── Test 9: Empty prompt → fail-open ─────────────────────────────────────────
echo "--- Test 9: empty prompt → fail-open allow ---"
PAYLOAD=$(jq -cn --arg sid "$SID" \
  '{"session_id":$sid,"tool_name":"Task","tool_input":{"prompt":""},"agent_id":null}')
OUT=$(echo "$PAYLOAD" | run_guard); RC=$?
check_allow "9 empty prompt → fail-open allow" "$OUT" "$RC"

# ── Test 10: Missing session_id → fail-open ───────────────────────────────────
echo "--- Test 10: missing session_id → fail-open allow ---"
PAYLOAD=$(jq -cn '{"tool_name":"Task","tool_input":{"prompt":"## Output: docs/temp/nosid.md"}}')
OUT=$(echo "$PAYLOAD" | run_guard); RC=$?
check_allow "10 missing session_id → fail-open allow" "$OUT" "$RC"

# ── Summary ──────────────────────────────────────────────────────────────────
echo
echo "parallel-scope-guard: $PASS passed, $FAIL failed"
[[ "$FAIL" -eq 0 ]]
