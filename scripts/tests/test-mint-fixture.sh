#!/usr/bin/env bash
# ABOUTME: TDD test suite for scripts/flywheel/mint-fixture.sh (Pillar III Task III-1).
# ABOUTME: Tests fixture minting: well-formed tree, expected_gap, synthesized, idempotency,
# ABOUTME: malformed-input skip, and monotonic naming. Run: bash test-mint-fixture.sh
# ABOUTME: Must be RED before mint-fixture.sh exists; GREEN after implementation.
# ABOUTME: BSD/macOS compatible. No model calls. All tests use synthetic incidents.

set -uo pipefail

CLAUDE_DIR="${CLAUDE_DIR:-$HOME/.claude}"
MINT="${CLAUDE_DIR}/scripts/flywheel/mint-fixture.sh"
EVALS_DIR="${CLAUDE_DIR}/evals/incidents"

# ── test harness ─────────────────────────────────────────────────────────────
PASS=0
FAIL=0
ERRORS=()

_ok() {
  local label="$1"
  PASS=$(( PASS + 1 ))
  echo "  [PASS] $label"
}

_fail() {
  local label="$1"
  local detail="${2:-}"
  FAIL=$(( FAIL + 1 ))
  ERRORS+=("FAIL: $label${detail:+ — $detail}")
  echo "  [FAIL] $label${detail:+ — $detail}"
}

# Scratch isolated eval dir so tests don't pollute the real corpus
SCRATCH_DIR="$(mktemp -d)"
trap 'rm -rf "$SCRATCH_DIR"' EXIT

# ── synthetic incident builder ────────────────────────────────────────────────
# Purpose: produce a minimal valid incident JSON matching the schema §2.3.
# Usage: make_incident <class> [purged=1] [extra_json_kv...]
# Gotchas: session_id must be unique per test to avoid idempotency false-hits.

make_incident() {
  local class="$1"; shift
  local purged="${purged:-0}"
  local session_id="${session_id:-sess-test-$(date +%s%N 2>/dev/null || date +%s)-$$-${RANDOM}}"
  local ts
  ts="$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo "2026-07-04T00:00:00Z")"
  jq -cn \
    --arg ts "$ts" \
    --arg class "$class" \
    --arg session_id "$session_id" \
    --argjson purged "$purged" \
    '{
      ts: $ts,
      schema: 1,
      session_id: $session_id,
      agent_id: null,
      event_type: "incident",
      source: "test-mint-fixture.sh",
      project: "test",
      payload: {
        class: $class,
        detail: "Synthetic test incident for class \($class)",
        purged_transcript: $purged
      }
    }'
}

echo ""
echo "══════════════════════════════════════════════════════"
echo "  test-mint-fixture.sh — Pillar III-1 eval fixture minter"
echo "══════════════════════════════════════════════════════"
echo ""

# ── Case 1: synthetic incident → well-formed fixture tree (all 3 files) ───────
echo "Case 1: synthetic incident → well-formed fixture tree"
EVALS_DIR_1="$SCRATCH_DIR/evals-1"
mkdir -p "$EVALS_DIR_1"
INCIDENT_1="$(session_id="sess-c1-$$" make_incident "C2")"
OUT_DIR="$(EVALS_DIR="$EVALS_DIR_1" bash "$MINT" <(echo "$INCIDENT_1") 2>&1)"
EC=$?

# Find the minted dir
MINTED_DIR="$(find "$EVALS_DIR_1" -maxdepth 1 -type d -name 'C2-*' | head -1)"
if [[ -z "$MINTED_DIR" ]]; then
  _fail "Case 1" "no fixture dir created under $EVALS_DIR_1 (exit $EC)"
else
  # Check all 3 files exist
  if [[ -f "$MINTED_DIR/fixture.jsonl" && -f "$MINTED_DIR/input.json" && -f "$MINTED_DIR/expect.json" ]]; then
    # Validate JSON syntax
    JSONL_OK=1
    while IFS= read -r line; do
      [[ -z "$line" ]] && continue
      if ! echo "$line" | jq . >/dev/null 2>&1; then
        JSONL_OK=0
        break
      fi
    done < "$MINTED_DIR/fixture.jsonl"
    INPUT_OK=0; jq . "$MINTED_DIR/input.json" >/dev/null 2>&1 && INPUT_OK=1
    EXPECT_OK=0; jq . "$MINTED_DIR/expect.json" >/dev/null 2>&1 && EXPECT_OK=1
    if [[ $JSONL_OK -eq 1 && $INPUT_OK -eq 1 && $EXPECT_OK -eq 1 ]]; then
      _ok "Case 1: well-formed fixture tree with all 3 files, valid JSON"
    else
      _fail "Case 1" "JSON invalid — fixture.jsonl=${JSONL_OK} input.json=${INPUT_OK} expect.json=${EXPECT_OK}"
    fi
  else
    _fail "Case 1" "missing files in $MINTED_DIR"
  fi
fi

# ── Case 2: C7/U3 incident → expected_gap:true ───────────────────────────────
echo "Case 2: C7 incident → expected_gap:true in expect.json"
EVALS_DIR_2="$SCRATCH_DIR/evals-2"
mkdir -p "$EVALS_DIR_2"
INCIDENT_2="$(session_id="sess-c2-$$" make_incident "C7")"
EVALS_DIR="$EVALS_DIR_2" bash "$MINT" <(echo "$INCIDENT_2") >/dev/null 2>&1
MINTED_DIR_2="$(find "$EVALS_DIR_2" -maxdepth 1 -type d -name 'C7-*' | head -1)"
if [[ -z "$MINTED_DIR_2" ]]; then
  _fail "Case 2" "no C7 fixture dir created"
else
  GAP="$(jq -r '.expected_gap // false' "$MINTED_DIR_2/expect.json" 2>/dev/null)"
  if [[ "$GAP" == "true" ]]; then
    _ok "Case 2: C7 incident → expected_gap:true"
  else
    _fail "Case 2" "expected_gap is '$GAP', expected 'true'"
  fi
fi

# ── Case 3: U3 incident → expected_gap:true ──────────────────────────────────
echo "Case 3: U3 incident → expected_gap:true"
EVALS_DIR_3="$SCRATCH_DIR/evals-3"
mkdir -p "$EVALS_DIR_3"
INCIDENT_3="$(session_id="sess-c3-$$" make_incident "U3")"
EVALS_DIR="$EVALS_DIR_3" bash "$MINT" <(echo "$INCIDENT_3") >/dev/null 2>&1
MINTED_DIR_3="$(find "$EVALS_DIR_3" -maxdepth 1 -type d -name 'U3-*' | head -1)"
if [[ -z "$MINTED_DIR_3" ]]; then
  _fail "Case 3" "no U3 fixture dir created"
else
  GAP="$(jq -r '.expected_gap // false' "$MINTED_DIR_3/expect.json" 2>/dev/null)"
  if [[ "$GAP" == "true" ]]; then
    _ok "Case 3: U3 incident → expected_gap:true"
  else
    _fail "Case 3" "expected_gap is '$GAP', expected 'true'"
  fi
fi

# ── Case 4: purged transcript incident → synthesized:true ─────────────────────
echo "Case 4: purged transcript → synthesized:true in fixture.jsonl"
EVALS_DIR_4="$SCRATCH_DIR/evals-4"
mkdir -p "$EVALS_DIR_4"
INCIDENT_4="$(purged=1 session_id="sess-c4-$$" make_incident "C2")"
EVALS_DIR="$EVALS_DIR_4" bash "$MINT" <(echo "$INCIDENT_4") >/dev/null 2>&1
MINTED_DIR_4="$(find "$EVALS_DIR_4" -maxdepth 1 -type d -name 'C2-*' | head -1)"
if [[ -z "$MINTED_DIR_4" ]]; then
  _fail "Case 4" "no fixture dir created for purged-transcript incident"
else
  # synthesized:true must appear in at least one line of fixture.jsonl
  SYNTH="$(jq -r '.synthesized // false' "$MINTED_DIR_4/fixture.jsonl" 2>/dev/null | grep -m1 "true" || true)"
  if [[ "$SYNTH" == "true" ]]; then
    _ok "Case 4: purged transcript → synthesized:true"
  else
    _fail "Case 4" "synthesized marker not found in fixture.jsonl"
  fi
fi

# ── Case 5: re-mint same incident adds 0 (idempotency) ───────────────────────
echo "Case 5: re-minting the same incident is idempotent (adds 0 fixtures)"
EVALS_DIR_5="$SCRATCH_DIR/evals-5"
mkdir -p "$EVALS_DIR_5"
SESS_ID_5="sess-idem-$$"
INCIDENT_5="$(session_id="$SESS_ID_5" make_incident "C2")"
EVALS_DIR="$EVALS_DIR_5" bash "$MINT" <(echo "$INCIDENT_5") >/dev/null 2>&1
COUNT_BEFORE="$(find "$EVALS_DIR_5" -maxdepth 1 -type d -name 'C2-*' | wc -l | tr -d ' ')"
EVALS_DIR="$EVALS_DIR_5" bash "$MINT" <(echo "$INCIDENT_5") >/dev/null 2>&1
COUNT_AFTER="$(find "$EVALS_DIR_5" -maxdepth 1 -type d -name 'C2-*' | wc -l | tr -d ' ')"
if [[ "$COUNT_BEFORE" == "$COUNT_AFTER" && "$COUNT_BEFORE" -eq 1 ]]; then
  _ok "Case 5: re-mint idempotent (count stayed at $COUNT_BEFORE)"
else
  _fail "Case 5" "before=$COUNT_BEFORE after=$COUNT_AFTER (expected same, 1)"
fi

# ── Case 6: malformed incident → skip + exit 0 ───────────────────────────────
echo "Case 6: malformed incident JSON → skip + exit 0"
EVALS_DIR_6="$SCRATCH_DIR/evals-6"
mkdir -p "$EVALS_DIR_6"
BAD_INPUT="$(mktemp)"
echo "this is not valid JSON at all {{{" > "$BAD_INPUT"
EVALS_DIR="$EVALS_DIR_6" bash "$MINT" "$BAD_INPUT" >/dev/null 2>&1
EC6=$?
COUNT_6="$(find "$EVALS_DIR_6" -maxdepth 1 -type d | grep -v "^$EVALS_DIR_6$" | wc -l | tr -d ' ')"
rm -f "$BAD_INPUT"
if [[ $EC6 -eq 0 && "$COUNT_6" -eq 0 ]]; then
  _ok "Case 6: malformed input → skip, exit 0, no fixtures created"
else
  _fail "Case 6" "exit=$EC6 fixtures_created=$COUNT_6 (expected exit=0, fixtures=0)"
fi

# ── Case 7: naming monotonically increments per class ────────────────────────
echo "Case 7: monotonic naming — sequential incidents get C2-001, C2-002, ..."
EVALS_DIR_7="$SCRATCH_DIR/evals-7"
mkdir -p "$EVALS_DIR_7"
for i in 1 2 3; do
  INC="$(session_id="sess-mono-$i-$$" make_incident "C2")"
  EVALS_DIR="$EVALS_DIR_7" bash "$MINT" <(echo "$INC") >/dev/null 2>&1
done
DIRS_7=( $(find "$EVALS_DIR_7" -maxdepth 1 -type d -name 'C2-*' | sort) )
if [[ ${#DIRS_7[@]} -eq 3 ]]; then
  N1="$(basename "${DIRS_7[0]}" | sed 's/C2-//')"
  N2="$(basename "${DIRS_7[1]}" | sed 's/C2-//')"
  N3="$(basename "${DIRS_7[2]}" | sed 's/C2-//')"
  # Each should be zero-padded 3-digit integers incrementing by 1
  V1=$(( 10#$N1 ))
  V2=$(( 10#$N2 ))
  V3=$(( 10#$N3 ))
  if [[ $V2 -eq $(( V1 + 1 )) && $V3 -eq $(( V2 + 1 )) ]]; then
    _ok "Case 7: monotonic naming — C2-$(printf '%03d' $V1), C2-$(printf '%03d' $V2), C2-$(printf '%03d' $V3)"
  else
    _fail "Case 7" "expected consecutive: got $N1 $N2 $N3"
  fi
else
  _fail "Case 7" "expected 3 dirs, got ${#DIRS_7[@]}: ${DIRS_7[*]:-none}"
fi

# ── Case 8: SCHEMA.md exists and documents the fixture format ────────────────
echo "Case 8: evals/SCHEMA.md exists and documents fixture format"
SCHEMA_MD="${CLAUDE_DIR}/evals/SCHEMA.md"
if [[ -f "$SCHEMA_MD" ]]; then
  # Must mention fixture.jsonl, input.json, expect.json, expected_gap, synthesized
  SCHEMA_OK=1
  for kw in "fixture.jsonl" "input.json" "expect.json" "expected_gap" "synthesized"; do
    if ! grep -q "$kw" "$SCHEMA_MD"; then
      _fail "Case 8" "SCHEMA.md missing keyword: $kw"
      SCHEMA_OK=0
      break
    fi
  done
  [[ $SCHEMA_OK -eq 1 ]] && _ok "Case 8: SCHEMA.md exists and documents all required fields"
else
  _fail "Case 8" "SCHEMA.md not found at $SCHEMA_MD"
fi

# ── Summary ───────────────────────────────────────────────────────────────────
echo ""
echo "══════════════════════════════════════════════════════"
TOTAL=$(( PASS + FAIL ))
echo "  Results: $PASS/$TOTAL passed, $FAIL failed"
if [[ ${#ERRORS[@]} -gt 0 ]]; then
  echo ""
  echo "  Failures:"
  for e in "${ERRORS[@]}"; do
    echo "    $e"
  done
fi
echo "══════════════════════════════════════════════════════"
echo ""

[[ $FAIL -eq 0 ]]
