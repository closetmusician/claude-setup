#!/usr/bin/env bash
# ABOUTME: Test suite for scripts/governance/constraint-wording-lint.sh (PreToolUse/Agent hook).
# ABOUTME: Covers: unqualified constraint → WARN emitted; qualified constraint → silent;
# ABOUTME: non-Agent tool → silent; malformed stdin → silent-allow; never-deny proof.
# ABOUTME: Includes neuter-and-fail check confirming the lint is load-bearing.
# ABOUTME: All cases must pass before wiring; suite exit 0 iff all pass.

set -uo pipefail

HOOK="${HOOK:-$HOME/.claude/scripts/governance/constraint-wording-lint.sh}"
PASS=0; FAIL=0

# ─── Helpers ─────────────────────────────────────────────────────────────────

# Build a realistic Agent PreToolUse payload with a given prompt string.
make_agent_payload() {
  local prompt="$1"
  jq -cn --arg p "$prompt" \
    '{"tool_name":"Agent","tool_input":{"prompt":$p},"session_id":"test-session-lint"}'
}

# Build a non-Agent payload (e.g. Bash) — hook must ignore it.
make_non_agent_payload() {
  local tool="${1:-Bash}"
  jq -cn --arg t "$tool" \
    '{"tool_name":$t,"tool_input":{"command":"echo hi"},"session_id":"test-session-lint"}'
}

# Run hook; returns stdout.
run_hook() {
  printf '%s' "$1" | bash "$HOOK"
}

# Check: case name, expected (warn|silent|allow), actual output.
check() {
  local name="$1" expected="$2" output="$3"
  case "$expected" in
    warn)
      if printf '%s' "$output" | jq -e '.hookSpecificOutput.additionalContext' &>/dev/null \
        && printf '%s' "$output" | jq -r '.hookSpecificOutput.additionalContext' | grep -qi 'constraint-wording-lint'; then
        echo "PASS: $name"; PASS=$((PASS+1))
      else
        echo "FAIL: $name — expected warn with additionalContext, got: ${output:-<empty>}"; FAIL=$((FAIL+1))
      fi
      ;;
    silent)
      if [[ -z "$output" ]]; then
        echo "PASS: $name"; PASS=$((PASS+1))
      else
        echo "FAIL: $name — expected silent (no output), got: ${output}"; FAIL=$((FAIL+1))
      fi
      ;;
    never_deny)
      # Proof: output must NOT contain a deny decision.
      if printf '%s' "$output" | jq -e 'select(.decision == "block")' &>/dev/null; then
        echo "FAIL: $name — NEVER-DENY violated: got block decision in: ${output}"; FAIL=$((FAIL+1))
      else
        echo "PASS: $name (no deny decision)"; PASS=$((PASS+1))
      fi
      ;;
  esac
}

# ─── Test 1: Unqualified absolute constraint → WARN ──────────────────────────
# "MOVES only" without any EXCEPT/authorized qualifier → must emit warning.
PROMPT_1="$(printf '## Mandatory Context\ndocs/spec.md\n\n## Constraints\nMOVES only, do not edit routing\n')"
PAYLOAD_1="$(make_agent_payload "$PROMPT_1")"
OUT_1="$(run_hook "$PAYLOAD_1")"
check "1 unqualified-MOVES-only → warn" warn "$OUT_1"

# ─── Test 2: Qualified constraint (inline EXCEPT) → silent ───────────────────
# "MOVES only" WITH "EXCEPT the routing rows this packet authorizes" → no warning.
PROMPT_2="$(printf '## Mandatory Context\ndocs/spec.md\n\n## Constraints\nMOVES only, EXCEPT the routing rows this packet authorizes\n')"
PAYLOAD_2="$(make_agent_payload "$PROMPT_2")"
OUT_2="$(run_hook "$PAYLOAD_2")"
check "2 qualified-EXCEPT-present → silent" silent "$OUT_2"

# ─── Test 3: No ## Constraints section → silent ──────────────────────────────
PROMPT_3="$(printf '## Mandatory Context\ndocs/spec.md\n\nDo the thing.\n')"
PAYLOAD_3="$(make_agent_payload "$PROMPT_3")"
OUT_3="$(run_hook "$PAYLOAD_3")"
check "3 no-constraints-section → silent" silent "$OUT_3"

# ─── Test 4: Non-Agent tool → silent ─────────────────────────────────────────
# The hook must only fire for Agent tool calls; Bash/Read/etc. must be ignored.
PAYLOAD_4="$(make_non_agent_payload "Bash")"
OUT_4="$(run_hook "$PAYLOAD_4")"
check "4 non-agent-tool-Bash → silent" silent "$OUT_4"

# ─── Test 5: Malformed stdin → silent/allow (fail-open) ──────────────────────
OUT_5="$(printf 'this is not json at all' | bash "$HOOK")"
check "5 malformed-stdin → fail-open silent" silent "$OUT_5"

# ─── Test 6: Empty stdin → fail-open silent ──────────────────────────────────
OUT_6="$(printf '' | bash "$HOOK")"
check "6 empty-stdin → fail-open silent" silent "$OUT_6"

# ─── Test 7: "never write files" unqualified → warn ──────────────────────────
PROMPT_7="$(printf '## Constraints\nnever write files to disk\n')"
PAYLOAD_7="$(make_agent_payload "$PROMPT_7")"
OUT_7="$(run_hook "$PAYLOAD_7")"
check "7 never-write-files unqualified → warn" warn "$OUT_7"

# ─── Test 8: "never write files" with "authorized" qualifier → silent ─────────
PROMPT_8="$(printf '## Constraints\nnever write files unless packet authorizes it\n')"
PAYLOAD_8="$(make_agent_payload "$PROMPT_8")"
OUT_8="$(run_hook "$PAYLOAD_8")"
check "8 never-write-files with authorized-qualifier → silent" silent "$OUT_8"

# ─── Test 9: "do not edit" unqualified → warn ────────────────────────────────
PROMPT_9="$(printf '## Constraints\ndo not edit any existing files\n')"
PAYLOAD_9="$(make_agent_payload "$PROMPT_9")"
OUT_9="$(run_hook "$PAYLOAD_9")"
check "9 do-not-edit unqualified → warn" warn "$OUT_9"

# ─── Test 10: NEVER-DENY proof (even worst-case unqualified prompt) ───────────
# Verify output is either empty or an allow decision — never a block/deny.
PROMPT_10="$(printf '## Constraints\nMOVES only, do not edit, never write files, no Bash, never use any tool\n')"
PAYLOAD_10="$(make_agent_payload "$PROMPT_10")"
OUT_10="$(run_hook "$PAYLOAD_10")"
check "10a never-deny proof — has warn" warn "$OUT_10"
check "10b never-deny proof — no block decision" never_deny "$OUT_10"
# Extra: permissionDecision must be "allow"
if printf '%s' "$OUT_10" | jq -e 'select(.hookSpecificOutput.permissionDecision == "allow")' &>/dev/null; then
  echo "PASS: 10c permissionDecision=allow confirmed"; PASS=$((PASS+1))
else
  echo "FAIL: 10c permissionDecision not 'allow': ${OUT_10}"; FAIL=$((FAIL+1))
fi

# ─── Test 11: "except the" qualifier suppresses warn ─────────────────────────
PROMPT_11="$(printf '## Constraints\nMOVES only, except the files this packet creates\n')"
PAYLOAD_11="$(make_agent_payload "$PROMPT_11")"
OUT_11="$(run_hook "$PAYLOAD_11")"
check "11 except-the qualifier → silent" silent "$OUT_11"

# ─── Test 12: "no Bash" unqualified → warn ───────────────────────────────────
PROMPT_12="$(printf '## Constraints\nno Bash commands allowed\n')"
PAYLOAD_12="$(make_agent_payload "$PROMPT_12")"
OUT_12="$(run_hook "$PAYLOAD_12")"
check "12 no-Bash unqualified → warn" warn "$OUT_12"

# ─── Test 13: Agent payload with no prompt field → fail-open silent ───────────
PAYLOAD_13="$(jq -cn '{"tool_name":"Agent","tool_input":{},"session_id":"test"}')"
OUT_13="$(run_hook "$PAYLOAD_13")"
check "13 agent-no-prompt-field → fail-open silent" silent "$OUT_13"

# ─── NEUTER-AND-FAIL CHECK ────────────────────────────────────────────────────
# Temporarily comment out the ABSOLUTE_PATTERNS array in the hook, re-run Test 1,
# confirm it NO LONGER warns (suite must fail). Then restore.
echo ""
echo "── Neuter-and-fail check ─────────────────────────────────────────────────"

TMP_HOOK="$(mktemp /tmp/constraint-wording-lint-neutered.XXXXXX.sh)"
trap 'rm -f "$TMP_HOOK"' EXIT

# Neuter: replace the ABSOLUTE_PATTERNS array with an empty one.
sed 's/^ABSOLUTE_PATTERNS=(.*/ABSOLUTE_PATTERNS=()/' "$HOOK" > "$TMP_HOOK"
chmod +x "$TMP_HOOK"

OUT_NEUTER="$(HOOK="$TMP_HOOK" printf '%s' "$PAYLOAD_1" | bash "$TMP_HOOK")"

NEUTER_PASS=false
if [[ -z "$OUT_NEUTER" ]]; then
  NEUTER_PASS=true
fi

if $NEUTER_PASS; then
  echo "PASS: neuter-and-fail — neutered hook produced no warn (Test 1 correctly fails when patterns removed)"
  PASS=$((PASS+1))
else
  echo "FAIL: neuter-and-fail — neutered hook still emitted a warning; the lint may not be load-bearing"
  echo "      Output was: ${OUT_NEUTER:0:200}"
  FAIL=$((FAIL+1))
fi

# ─── Final result ─────────────────────────────────────────────────────────────
echo ""
echo "constraint-wording-lint: $PASS passed, $FAIL failed"
[[ "$FAIL" -eq 0 ]]
