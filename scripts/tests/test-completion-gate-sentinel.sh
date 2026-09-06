#!/usr/bin/env bash
# ABOUTME: Test suite for scripts/governance/completion-gate-sentinel-check.sh (Stop hook).
# ABOUTME: Covers the 6 fixtures from PKT-JD-01: gate-block, allow-no-gate, allow-no-active,
# ABOUTME: ledger-RED-block, neuter-and-fail proof, and stdin identity probe (L-27 contract).
# ABOUTME: Mirrors style of test-completion-claim-guard.sh. All fixtures feed stdin JSON;
# ABOUTME: identity (session_id) comes from stdin only — no env injection (guard identity contract).

set -uo pipefail

GUARD="${GUARD:-$HOME/.claude/scripts/governance/completion-gate-sentinel-check.sh}"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
PASS=0; FAIL=0

# ─── Helpers ─────────────────────────────────────────────────────────────────

# Build a minimal NDJSON transcript whose last assistant message is $1.
make_transcript() {
  local f="$TMP/transcript-$RANDOM.jsonl"
  jq -cn '{"type":"user","message":{"content":"start"}}' > "$f"
  jq -cn --arg t "$1" \
    '{"type":"assistant","message":{"content":[{"type":"text","text":$t}]}}' >> "$f"
  echo "$f"
}

# Run the guard: $1=transcript_path, $2=HARNESS_GOV_STATE_DIR override.
# session_id is embedded in stdin JSON (identity contract — never env).
run_guard() {
  local tp="$1" state_dir="$2"
  jq -cn --arg tp "$tp" --arg sid "testsid-$(basename "$state_dir")" \
    '{"transcript_path":$tp,"stop_hook_active":false,"session_id":$sid}' \
  | HARNESS_GOV_STATE_DIR="$state_dir" bash "$GUARD"
}

# Check result: $1=case name, $2=expected (block|pass), $3=actual output.
check() {
  local name="$1" expected="$2" actual="$3"
  if [[ "$expected" == "block" ]]; then
    if printf '%s' "$actual" | grep -q '"decision":"block"'; then
      echo "PASS: $name"; PASS=$((PASS+1))
    else
      echo "FAIL: $name — expected block, got: ${actual:-<empty>}"; FAIL=$((FAIL+1))
    fi
  else
    if printf '%s' "$actual" | grep -q '"decision":"block"'; then
      echo "FAIL: $name — expected pass, got block: $actual"; FAIL=$((FAIL+1))
    else
      echo "PASS: $name"; PASS=$((PASS+1))
    fi
  fi
}

# Create a governance state dir with .active sentinel.
make_active_state() {
  local d="$TMP/state-$RANDOM"
  mkdir -p "$d"
  touch "$d/.active"
  echo "$d"
}

# Completion claim text that reliably matches the CLAIM regex.
CLAIM_TEXT="All tests passing, task complete."

# ─── Fixture A: gate-block ────────────────────────────────────────────────────
# $STATE/.active + $STATE/.gate-pre-coder present + completion claim → BLOCK.
echo "--- Fixture A: gate sentinel active → block ---"
STATE_A="$(make_active_state)"
touch "$STATE_A/.gate-pre-coder"
T_A="$(make_transcript "$CLAIM_TEXT")"
out_A="$(run_guard "$T_A" "$STATE_A")"
check "A block: .gate-pre-coder present → blocks" block "$out_A"
# Also verify the block message names the sentinel file.
if printf '%s' "$out_A" | grep -q '.gate-pre-coder'; then
  echo "PASS: A detail: block reason names .gate-pre-coder"; PASS=$((PASS+1))
else
  echo "FAIL: A detail: block reason did not name .gate-pre-coder; got: $out_A"; FAIL=$((FAIL+1))
fi

# ─── Fixture B: allow — no gate file ─────────────────────────────────────────
# $STATE/.active present, NO .gate-* files, same completion claim → ALLOW.
echo "--- Fixture B: .active but no .gate-* → allow ---"
STATE_B="$(make_active_state)"
T_B="$(make_transcript "$CLAIM_TEXT")"
check "B allow: no .gate-* → passes" pass "$(run_guard "$T_B" "$STATE_B")"

# ─── Fixture C: allow — no .active ────────────────────────────────────────────
# No $STATE/.active at all, completion claim present → ALLOW (not a governed run).
echo "--- Fixture C: no .active → allow ---"
STATE_C="$TMP/state-no-active-$RANDOM"
mkdir -p "$STATE_C"
# No .active here; also add a .gate-* to make sure it's the .active check that matters.
touch "$STATE_C/.gate-pre-coder"
T_C="$(make_transcript "$CLAIM_TEXT")"
check "C allow: no .active (ungoverned) → passes" pass "$(run_guard "$T_C" "$STATE_C")"

# ─── Fixture D: ledger RED ────────────────────────────────────────────────────
# $STATE/.active + latest-evidence-ledger.json with one RED item + completion claim → BLOCK.
echo "--- Fixture D: ledger RED item → block ---"
STATE_D="$(make_active_state)"
cat > "$STATE_D/latest-evidence-ledger.json" <<'EOF'
[
  {"id":"REQ-01","description":"Tests must all pass","status":"RED"},
  {"id":"REQ-02","description":"Artifact exists","status":"GREEN"}
]
EOF
T_D="$(make_transcript "$CLAIM_TEXT")"
out_D="$(run_guard "$T_D" "$STATE_D")"
check "D block: RED ledger item → blocks" block "$out_D"
# Block message must cite the RED item.
if printf '%s' "$out_D" | grep -q 'REQ-01'; then
  echo "PASS: D detail: block reason cites RED item REQ-01"; PASS=$((PASS+1))
else
  echo "FAIL: D detail: block reason did not cite REQ-01; got: $out_D"; FAIL=$((FAIL+1))
fi

# ─── Fixture E: neuter-and-fail proof ─────────────────────────────────────────
# Create a neutered copy of the guard with the sentinel-scan "find" command replaced
# by an empty generator. Re-run Fixture A — the suite MUST now allow (not block).
# This proves the sentinel-scan block is load-bearing, not incidental.
#
# Neutering strategy: replace the find command output that populates gate_file with
# an empty echo. The guard sources lib/project-root.sh by absolute path (derived from
# BASH_SOURCE[0]), so the neutered copy in $TMP needs the lib directory alongside it.
echo "--- Fixture E: neuter-and-fail --- (disabling sentinel scan)"
NEUTERED_DIR="$TMP/neutered"
mkdir -p "$NEUTERED_DIR/lib"
cp "$GUARD" "$NEUTERED_DIR/guard.sh"
chmod +x "$NEUTERED_DIR/guard.sh"
# Copy the lib directory the guard sources (lib/project-root.sh, lib/emit-event.sh).
GUARD_DIR="$(dirname "$GUARD")"
[[ -f "$GUARD_DIR/lib/project-root.sh" ]] && cp "$GUARD_DIR/lib/project-root.sh" "$NEUTERED_DIR/lib/"
[[ -f "$GUARD_DIR/../lib/emit-event.sh" ]] && cp "$GUARD_DIR/../lib/emit-event.sh" "$NEUTERED_DIR/lib/" 2>/dev/null || true

# Neuter: replace the find … .gate-* command with `echo ""` so no gate_file is ever set.
perl -0777 -pi \
  -e 's|done < <\(find "\$STATE" -maxdepth 1 -name '"'"'\.gate-\*'"'"' -type f 2>/dev/null\)|done < <(echo "")  # NEUTERED|g' \
  "$NEUTERED_DIR/guard.sh" 2>/dev/null

out_E="$(
  jq -cn --arg tp "$T_A" --arg sid "neutersid" \
    '{"transcript_path":$tp,"stop_hook_active":false,"session_id":$sid}' \
  | HARNESS_GOV_STATE_DIR="$STATE_A" bash "$NEUTERED_DIR/guard.sh" 2>/dev/null
)" || out_E=""

# The neutered guard must NOT block — Fixture A now passes the (neutered) sentinel scan.
# Proof: the real guard blocks the same input (Fixture A above), so the scan is load-bearing.
if printf '%s' "$out_E" | grep -q '"decision":"block"'; then
  echo "FAIL: E neuter-and-fail: neutered guard still blocks — sentinel scan may not be load-bearing (check perl sub)"; FAIL=$((FAIL+1))
else
  echo "PASS: E neuter-and-fail: neutered guard allows (confirms sentinel scan is load-bearing)"; PASS=$((PASS+1))
fi

# ─── Fixture F: stdin identity probe ──────────────────────────────────────────
# Run Fixture A (block case) with session_id supplied ONLY on stdin (no SESSION_ID env).
# Guard must still block — proves it reads stdin, not env (guards against env-vs-stdin bug).
echo "--- Fixture F: stdin-identity-only probe ---"
STATE_F="$(make_active_state)"
touch "$STATE_F/.gate-pre-coder"
T_F="$(make_transcript "$CLAIM_TEXT")"
# Explicitly unset SESSION_ID in the child environment to prove stdin-only identity.
out_F="$(
  unset SESSION_ID 2>/dev/null || true
  jq -cn --arg tp "$T_F" --arg sid "stdin-only-sid" \
    '{"transcript_path":$tp,"stop_hook_active":false,"session_id":$sid}' \
  | HARNESS_GOV_STATE_DIR="$STATE_F" env -u SESSION_ID bash "$GUARD" 2>/dev/null
)"
check "F stdin-identity: no env SESSION_ID → still blocks (reads stdin)" block "$out_F"

# ─── Edge cases ───────────────────────────────────────────────────────────────

# G: Malformed stdin JSON → fail-open (exit 0, no block).
echo "--- Edge G: malformed stdin → fail-open ---"
STATE_G="$(make_active_state)"
out_G="$(printf 'this is not json at all\n' | HARNESS_GOV_STATE_DIR="$STATE_G" bash "$GUARD")"
check "G malformed stdin → fail-open" pass "$out_G"

# H: Non-claim message with .gate-* present → allow (only blocks on completion claims).
echo "--- Edge H: .gate-* present but no completion claim → allow ---"
STATE_H="$(make_active_state)"
touch "$STATE_H/.gate-pre-coder"
T_H="$(make_transcript "Here is my analysis of the two options and their tradeoffs.")"
check "H no-claim message → passes even with gate active" pass "$(run_guard "$T_H" "$STATE_H")"

# I: GREEN-only ledger → allow.
echo "--- Edge I: GREEN-only ledger → allow ---"
STATE_I="$(make_active_state)"
cat > "$STATE_I/latest-evidence-ledger.json" <<'EOF'
[
  {"id":"REQ-01","description":"Tests pass","status":"GREEN"},
  {"id":"REQ-02","description":"Artifact exists","status":"GREEN"}
]
EOF
T_I="$(make_transcript "$CLAIM_TEXT")"
check "I GREEN-only ledger → allows" pass "$(run_guard "$T_I" "$STATE_I")"

# J: Malformed ledger JSON → fail-open (ledger check skipped, allow).
echo "--- Edge J: malformed ledger JSON → fail-open ---"
STATE_J="$(make_active_state)"
printf 'this is not valid json at all' > "$STATE_J/latest-evidence-ledger.json"
T_J="$(make_transcript "$CLAIM_TEXT")"
check "J malformed ledger → fail-open allow" pass "$(run_guard "$T_J" "$STATE_J")"

# K: .gate-* is a directory (not a regular file) → should NOT block (find -type f).
echo "--- Edge K: .gate-* is a directory → allow ---"
STATE_K="$(make_active_state)"
mkdir -p "$STATE_K/.gate-pre-coder"  # directory, not file
T_K="$(make_transcript "$CLAIM_TEXT")"
check "K .gate-dir not a file → allows" pass "$(run_guard "$T_K" "$STATE_K")"

# ─── Summary ─────────────────────────────────────────────────────────────────
echo
echo "completion-gate-sentinel-check: $PASS passed, $FAIL failed"
[[ "$FAIL" -eq 0 ]]
