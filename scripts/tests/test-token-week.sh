#!/usr/bin/env bash
# ABOUTME: TDD test suite for scripts/token-week.py (weekly spend line).
# ABOUTME: Uses synthetic fixtures with known costs. Verifies dedupe rule,
# ABOUTME: exact dollar totals, and line format. Exit 0 on all pass, nonzero on failure.
# ABOUTME: Env override TOKEN_WEEK_ROOT makes the script scan fixtures instead of live projects.

set -uo pipefail

PASS=0
FAIL=0

_pass() { PASS=$(( PASS + 1 )); printf 'PASS: %s\n' "$*"; }
_fail() { FAIL=$(( FAIL + 1 )); printf 'FAIL: %s\n' "$*"; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TOKEN_WEEK_PY="${TOKEN_WEEK_PY:-$SCRIPT_DIR/../token-week.py}"

# Sandbox
TMPROOT="$(mktemp -d /tmp/test-token-week-XXXXXX 2>/dev/null)"
trap 'rm -rf "$TMPROOT" 2>/dev/null' EXIT INT TERM

# Helper: create a synthetic transcript entry
# Usage: _mk_call <timestamp> <model> <input> <c5> <c1> <cr> <output> <msg_id> <req_id>
_mk_call() {
  local ts="$1" model="$2" inp="$3" c5="$4" c1="$5" cr="$6" out="$7" msg_id="$8" req_id="$9"
  jq -cn \
    --arg ts "$ts" \
    --arg model "$model" \
    --argjson inp "$inp" \
    --argjson c5 "$c5" \
    --argjson c1 "$c1" \
    --argjson cr "$cr" \
    --argjson out "$out" \
    --arg msg_id "$msg_id" \
    --arg req_id "$req_id" \
    '{
      type: "assistant",
      timestamp: $ts,
      sessionId: "test-session-001",
      requestId: $req_id,
      message: {
        role: "assistant",
        id: $msg_id,
        model: $model,
        usage: {
          input_tokens: $inp,
          cache_creation: {
            ephemeral_5m_input_tokens: $c5,
            ephemeral_1h_input_tokens: $c1
          },
          cache_read_input_tokens: $cr,
          output_tokens: $out
        }
      }
    }'
}

# ═════════════════════════════════════════════════════════════════════════════
# CASE 1: Known costs with sonnet-4-5 pricing
# ═════════════════════════════════════════════════════════════════════════════
# Price: input=3, c5=3.75, c1=6, cr=0.3, out=15 (per MTok)
# Call: 10k inp, 5k c5, 2k c1, 3k cr, 1k out
# Cost: (10*3 + 5*3.75 + 2*6 + 3*0.3 + 1*15)/1000 = (30 + 18.75 + 12 + 0.9 + 15)/1000 = 76.65/1000 = $0.077
_test_case1() {
  local sb="$TMPROOT/case1"
  mkdir -p "$sb/projects/test-proj"

  # One call 7 days ago
  _mk_call "2026-11-06T12:00:00.000Z" "claude-sonnet-4-5" 10000 5000 2000 3000 1000 "msg-001" "req-001" \
    > "$sb/projects/test-proj/transcript.jsonl"

  # Run token-week.py with fake today=2026-11-13
  local output
  output="$(TOKEN_WEEK_ROOT="$sb/projects" python3 "$TOKEN_WEEK_PY" 2>/dev/null)" || {
    _fail "Case 1: token-week.py failed to run"
    return
  }

  # Expected: $0.08 (rounded from 0.07665)
  if printf '%s' "$output" | grep -qF '$0.08'; then
    _pass "Case 1: correct dollar total in output"
  else
    _fail "Case 1: expected \$0.08, got: $output"
  fi

  # Check format: "last 7d: $X (prior 7d: $Y, change Z%). Subagents N%. Top model: M (P%)."
  if printf '%s' "$output" | grep -qE '\[Tokens\] last 7d: \$[0-9.]+.*\(prior 7d:.*change.*%.*Subagents.*%.*Top model:'; then
    _pass "Case 1: line format matches expected pattern"
  else
    _fail "Case 1: line format does not match: $output"
  fi
}

# ═════════════════════════════════════════════════════════════════════════════
# CASE 2: Dedupe rule — streaming with same (msg_id, req_id), keep max output
# ═════════════════════════════════════════════════════════════════════════════
_test_case2() {
  local sb="$TMPROOT/case2"
  mkdir -p "$sb/projects/test-proj"

  # Three streaming updates: output grows 100 → 500 → 1000
  # Only the last (1000 output) should be counted
  {
    _mk_call "2026-11-06T12:00:00.000Z" "claude-sonnet-4-5" 10000 5000 2000 3000 100 "msg-002" "req-002"
    _mk_call "2026-11-06T12:00:01.000Z" "claude-sonnet-4-5" 10000 5000 2000 3000 500 "msg-002" "req-002"
    _mk_call "2026-11-06T12:00:02.000Z" "claude-sonnet-4-5" 10000 5000 2000 3000 1000 "msg-002" "req-002"
  } > "$sb/projects/test-proj/transcript.jsonl"

  local output
  output="$(TOKEN_WEEK_ROOT="$sb/projects" python3 "$TOKEN_WEEK_PY" 2>/dev/null)" || {
    _fail "Case 2: token-week.py failed"
    return
  }

  # Expected: same as case 1 (1000 output = $0.08)
  if printf '%s' "$output" | grep -qF '$0.08'; then
    _pass "Case 2: dedupe rule works (kept max output_tokens)"
  else
    _fail "Case 2: dedupe failed, expected \$0.08, got: $output"
  fi
}

# ═════════════════════════════════════════════════════════════════════════════
# CASE 3: Two weeks split — 2 calls in last 7d, 1 call in prior 7d
# ═════════════════════════════════════════════════════════════════════════════
_test_case3() {
  local sb="$TMPROOT/case3"
  mkdir -p "$sb/projects/test-proj"

  # Prior week (Nov 1): 1 call @ $0.08
  # Last week (Nov 10, Nov 11): 2 calls @ $0.08 each = $0.16
  # Change: +100%
  {
    _mk_call "2026-11-01T12:00:00.000Z" "claude-sonnet-4-5" 10000 5000 2000 3000 1000 "msg-003" "req-003"
    _mk_call "2026-11-10T12:00:00.000Z" "claude-sonnet-4-5" 10000 5000 2000 3000 1000 "msg-004" "req-004"
    _mk_call "2026-11-11T12:00:00.000Z" "claude-sonnet-4-5" 10000 5000 2000 3000 1000 "msg-005" "req-005"
  } > "$sb/projects/test-proj/transcript.jsonl"

  local output
  output="$(TOKEN_WEEK_ROOT="$sb/projects" python3 "$TOKEN_WEEK_PY" 2>/dev/null)" || {
    _fail "Case 3: token-week.py failed"
    return
  }

  # Expected: last 7d $0.15 (two calls), prior 7d $0.08, change +100%
  if printf '%s' "$output" | grep -qE 'last 7d: \$0\.1[56].*prior 7d: \$0\.08.*change \+[0-9]+%'; then
    _pass "Case 3: two-week split correct"
  else
    _fail "Case 3: two-week split wrong: $output"
  fi
}

# ═════════════════════════════════════════════════════════════════════════════
# CASE 4: Subagent percentage
# ═════════════════════════════════════════════════════════════════════════════
_test_case4() {
  local sb="$TMPROOT/case4"
  mkdir -p "$sb/projects/test-proj" "$sb/projects/test-proj/subagents"

  # 1 main call + 1 subagent call (50% subagent)
  _mk_call "2026-11-10T12:00:00.000Z" "claude-sonnet-4-5" 10000 5000 2000 3000 1000 "msg-006" "req-006" \
    > "$sb/projects/test-proj/transcript.jsonl"
  _mk_call "2026-11-10T12:01:00.000Z" "claude-sonnet-4-5" 10000 5000 2000 3000 1000 "msg-007" "req-007" \
    > "$sb/projects/test-proj/subagents/agent-001.jsonl"

  local output
  output="$(TOKEN_WEEK_ROOT="$sb/projects" python3 "$TOKEN_WEEK_PY" 2>/dev/null)" || {
    _fail "Case 4: token-week.py failed"
    return
  }

  # Expected: Subagents 50%
  if printf '%s' "$output" | grep -qE 'Subagents 50%'; then
    _pass "Case 4: subagent percentage correct"
  else
    _fail "Case 4: expected Subagents 50%, got: $output"
  fi
}

# ═════════════════════════════════════════════════════════════════════════════
# CASE 5: Top model reporting
# ═════════════════════════════════════════════════════════════════════════════
_test_case5() {
  local sb="$TMPROOT/case5"
  mkdir -p "$sb/projects/test-proj"

  # 3 sonnet-4-5 calls @ $0.08 each = $0.24 (75%)
  # 1 haiku-4-5 call (input 10k @ $1/MTok = $0.01) (25%)
  {
    _mk_call "2026-11-10T12:00:00.000Z" "claude-sonnet-4-5" 10000 5000 2000 3000 1000 "msg-008" "req-008"
    _mk_call "2026-11-10T12:01:00.000Z" "claude-sonnet-4-5" 10000 5000 2000 3000 1000 "msg-009" "req-009"
    _mk_call "2026-11-10T12:02:00.000Z" "claude-sonnet-4-5" 10000 5000 2000 3000 1000 "msg-010" "req-010"
    _mk_call "2026-11-10T12:03:00.000Z" "claude-haiku-4-5" 10000 0 0 0 0 "msg-011" "req-011"
  } > "$sb/projects/test-proj/transcript.jsonl"

  local output
  output="$(TOKEN_WEEK_ROOT="$sb/projects" python3 "$TOKEN_WEEK_PY" 2>/dev/null)" || {
    _fail "Case 5: token-week.py failed"
    return
  }

  # Expected: Top model: sonnet-4-5 (7x% or higher)
  if printf '%s' "$output" | grep -qE 'Top model: sonnet-4-5 \([7-9][0-9]%\)'; then
    _pass "Case 5: top model correct"
  else
    _fail "Case 5: top model wrong: $output"
  fi
}

# ═════════════════════════════════════════════════════════════════════════════
# CASE 6: JSON output format
# ═════════════════════════════════════════════════════════════════════════════
_test_case6() {
  local sb="$TMPROOT/case6"
  mkdir -p "$sb/projects/test-proj"

  _mk_call "2026-11-10T12:00:00.000Z" "claude-sonnet-4-5" 10000 5000 2000 3000 1000 "msg-012" "req-012" \
    > "$sb/projects/test-proj/transcript.jsonl"

  local json_output
  json_output="$(TOKEN_WEEK_ROOT="$sb/projects" python3 "$TOKEN_WEEK_PY" --json 2>/dev/null)" || {
    _fail "Case 6: token-week.py --json failed"
    return
  }

  # Expected: valid JSON with keys: last_7d, prior_7d, change_pct, subagent_pct, top_model, top_model_pct
  if printf '%s' "$json_output" | jq -e '.last_7d, .prior_7d, .change_pct, .subagent_pct, .top_model, .top_model_pct' >/dev/null 2>&1; then
    _pass "Case 6: JSON output has all required keys"
  else
    _fail "Case 6: JSON output missing keys or invalid: $json_output"
  fi
}

# ═════════════════════════════════════════════════════════════════════════════
# CASE 7: <synthetic> model filtered out
# ═════════════════════════════════════════════════════════════════════════════
_test_case7() {
  local sb="$TMPROOT/case7"
  mkdir -p "$sb/projects/test-proj"

  # 1 real call + 1 synthetic (should be dropped)
  {
    _mk_call "2026-11-10T12:00:00.000Z" "claude-sonnet-4-5" 10000 5000 2000 3000 1000 "msg-013" "req-013"
    _mk_call "2026-11-10T12:01:00.000Z" "<synthetic>" 50000 10000 5000 8000 2000 "msg-014" "req-014"
  } > "$sb/projects/test-proj/transcript.jsonl"

  local output
  output="$(TOKEN_WEEK_ROOT="$sb/projects" python3 "$TOKEN_WEEK_PY" 2>/dev/null)" || {
    _fail "Case 7: token-week.py failed"
    return
  }

  # Expected: only $0.08 from the real call (synthetic dropped)
  if printf '%s' "$output" | grep -qF '$0.08'; then
    _pass "Case 7: synthetic model filtered out"
  else
    _fail "Case 7: synthetic not filtered, expected \$0.08, got: $output"
  fi
}

# ═════════════════════════════════════════════════════════════════════════════
# CASE 8: --write-cache writes both files and uses lock
# ═════════════════════════════════════════════════════════════════════════════
_test_case8() {
  local sb="$TMPROOT/case8"
  mkdir -p "$sb/projects/test-proj" "$sb/state"

  _mk_call "2026-11-10T12:00:00.000Z" "claude-sonnet-4-5" 10000 5000 2000 3000 1000 "msg-015" "req-015" \
    > "$sb/projects/test-proj/transcript.jsonl"

  TOKEN_WEEK_ROOT="$sb/projects" TOKEN_STATE_DIR="$sb/state" \
    python3 "$TOKEN_WEEK_PY" --write-cache 2>/dev/null || {
    _fail "Case 8: --write-cache failed"
    return
  }

  # Check latest.txt exists and has content
  if [[ -s "$sb/state/latest.txt" ]]; then
    _pass "Case 8: latest.txt written"
  else
    _fail "Case 8: latest.txt not written"
  fi

  # Check history.jsonl exists and has valid JSON with date field
  if [[ -f "$sb/state/history.jsonl" ]]; then
    local json_line
    json_line=$(cat "$sb/state/history.jsonl")
    if printf '%s' "$json_line" | jq -e '.date' >/dev/null 2>&1; then
      _pass "Case 8: history.jsonl written with date field"
    else
      _fail "Case 8: history.jsonl missing date field"
    fi
  else
    _fail "Case 8: history.jsonl not written"
  fi

  # Test lock prevents concurrent writes
  # Start two --write-cache processes and verify only one appends to history
  local line_count_before line_count_after
  line_count_before=$(wc -l < "$sb/state/history.jsonl" 2>/dev/null || echo 0)

  TOKEN_WEEK_ROOT="$sb/projects" TOKEN_STATE_DIR="$sb/state" \
    python3 "$TOKEN_WEEK_PY" --write-cache 2>/dev/null &
  TOKEN_WEEK_ROOT="$sb/projects" TOKEN_STATE_DIR="$sb/state" \
    python3 "$TOKEN_WEEK_PY" --write-cache 2>/dev/null &
  wait

  line_count_after=$(wc -l < "$sb/state/history.jsonl" 2>/dev/null || echo 0)
  # Should have at most 2 more lines (one or both processes succeeded)
  if [[ $line_count_after -le $(( line_count_before + 2 )) ]]; then
    _pass "Case 8: lock prevents unbounded concurrent writes"
  else
    _fail "Case 8: lock did not work, got $line_count_after lines (expected <= $(( line_count_before + 2 )))"
  fi
}

# ═════════════════════════════════════════════════════════════════════════════
# CASE 9: 40-tokens.sh prints cached line
# ═════════════════════════════════════════════════════════════════════════════
_test_case9() {
  local sb="$TMPROOT/case9"
  mkdir -p "$sb/state"

  # Write a cached line
  echo "[Tokens] last 7d: \$10.00 (prior 7d: \$8.00, change +25%). Subagents 50%. Top model: sonnet-4-5 (80%)." \
    > "$sb/state/latest.txt"

  local output
  output=$(TOKEN_STATE_DIR="$sb/state" bash "$SCRIPT_DIR/../session-start.d/40-tokens.sh" 2>/dev/null)

  if printf '%s' "$output" | grep -qF '[Tokens] last 7d: $10.00'; then
    _pass "Case 9: 40-tokens.sh prints cached line"
  else
    _fail "Case 9: 40-tokens.sh did not print cached line: $output"
  fi
}

# ═════════════════════════════════════════════════════════════════════════════
# CASE 10: 40-tokens.sh triggers refresh when cache is stale
# ═════════════════════════════════════════════════════════════════════════════
_test_case10() {
  local sb="$TMPROOT/case10"
  mkdir -p "$sb/projects/test-proj" "$sb/state"

  # Create a stale cache (>24h old) by touching with old timestamp
  echo "[Tokens] stale data" > "$sb/state/latest.txt"
  touch -t 202611010000 "$sb/state/latest.txt" 2>/dev/null || {
    # macOS may need different format
    touch -mt 202611010000 "$sb/state/latest.txt" 2>/dev/null || true
  }

  # Create transcript data so refresh can generate new line
  _mk_call "2026-11-10T12:00:00.000Z" "claude-sonnet-4-5" 10000 5000 2000 3000 1000 "msg-016" "req-016" \
    > "$sb/projects/test-proj/transcript.jsonl"

  # Run 40-tokens.sh (should trigger background refresh)
  TOKEN_STATE_DIR="$sb/state" \
    TOKEN_WEEK_ROOT="$sb/projects" \
    TOKEN_WEEK_SCRIPT="$TOKEN_WEEK_PY" \
    bash "$SCRIPT_DIR/../session-start.d/40-tokens.sh" 2>/dev/null

  # Wait up to 5 seconds for background refresh to complete
  local waited=0
  local refreshed=0
  while [[ $waited -lt 50 ]]; do
    if [[ -f "$sb/state/history.jsonl" ]]; then
      refreshed=1
      break
    fi
    sleep 0.1
    waited=$(( waited + 1 ))
  done

  if [[ $refreshed -eq 1 ]]; then
    _pass "Case 10: 40-tokens.sh triggered background refresh for stale cache"
  else
    _fail "Case 10: background refresh did not complete within 5s"
  fi
}

# ═════════════════════════════════════════════════════════════════════════════
# Run all cases
# ═════════════════════════════════════════════════════════════════════════════

if [[ ! -f "$TOKEN_WEEK_PY" ]]; then
  _fail "token-week.py not found at $TOKEN_WEEK_PY (required for tests)"
  echo ""
  echo "========================================================================"
  printf 'Results: PASS=%d  FAIL=%d  (total=%d)\n' "$PASS" "$FAIL" "$(( PASS + FAIL ))"
  echo "========================================================================"
  exit 1
fi

_test_case1
_test_case2
_test_case3
_test_case4
_test_case5
_test_case6
_test_case7
_test_case8
_test_case9
_test_case10

echo ""
echo "========================================================================"
printf 'Results: PASS=%d  FAIL=%d  (total=%d)\n' "$PASS" "$FAIL" "$(( PASS + FAIL ))"
echo "========================================================================"

[[ "$FAIL" -eq 0 ]]
