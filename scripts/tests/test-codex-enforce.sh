#!/usr/bin/env bash
# ABOUTME: Tests for the Codex-enforcement hooks (codex-cli-nudge.sh + codex-cli-guard.sh).
# ABOUTME: Proves the nudge arms/disarms the turn sentinel and the guard denies a Claude
# ABOUTME: imitation while allowing real codex:* agents AND pure-synthesis subagents.
# ABOUTME: Uses an isolated HOME so it never touches the live ~/.claude/state sentinel.
# ABOUTME: Run: bash ~/.claude/scripts/tests/test-codex-enforce.sh
set -uo pipefail

SRC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
NUDGE="$SRC_DIR/codex-cli-nudge.sh"
GUARD="$SRC_DIR/codex-cli-guard.sh"

# Isolated fake HOME so the real sentinel + real plugin path are not used/needed.
FAKE_HOME="$(mktemp -d)"
trap 'rm -rf "$FAKE_HOME"' EXIT
mkdir -p "$FAKE_HOME/.claude/state"
# Provide a fake companion script so the nudge's path-resolution has something to find.
mkdir -p "$FAKE_HOME/.claude/plugins/cache/openai-codex/codex/1.0.6/scripts"
: > "$FAKE_HOME/.claude/plugins/cache/openai-codex/codex/1.0.6/scripts/codex-companion.mjs"
FLAG="$FAKE_HOME/.claude/state/codex-turn.flag"

PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); printf '  ok   %s\n' "$1"; }
bad() { FAIL=$((FAIL+1)); printf '  FAIL %s\n' "$1"; }

run_nudge() { printf '%s' "$1" | HOME="$FAKE_HOME" bash "$NUDGE" 2>/dev/null; }
run_guard() { printf '%s' "$1" | HOME="$FAKE_HOME" bash "$GUARD" 2>/dev/null; }

echo "== nudge =="

# 1. Codex trigger arms the sentinel and emits the directive.
rm -f "$FLAG"
out=$(run_nudge '{"prompt":"please run a codex adversarial review on my diff"}')
[ -f "$FLAG" ] && printf '%s' "$out" | grep -q 'CODEX (hook)' && ok "codex prompt arms sentinel + emits directive" || bad "codex prompt should arm + emit"

# 2. Non-codex prompt disarms the sentinel and stays silent.
date +%s > "$FLAG"
out=$(run_nudge '{"prompt":"refactor the pricing module for clarity"}')
[ ! -f "$FLAG" ] && [ -z "$out" ] && ok "non-codex prompt disarms + silent" || bad "non-codex prompt should disarm + be silent"

# 3. "second opinion" arms it too.
rm -f "$FLAG"
run_nudge '{"prompt":"can you get a second opinion on this design"}' >/dev/null
[ -f "$FLAG" ] && ok "second-opinion arms sentinel" || bad "second-opinion should arm"

echo "== guard (sentinel armed) =="
date +%s > "$FLAG"

# 4. Claude/general agent doing the adversarial review → DENY.
out=$(run_guard '{"tool_name":"Agent","tool_input":{"subagent_type":"general-purpose","prompt":"You are an adversarial auditor. Independently verify each claim and try to refute it."}}')
printf '%s' "$out" | grep -q '"permissionDecision":"deny"' && ok "blocks Claude subagent imitating the review" || bad "should DENY Claude imitation"

# 5. Real codex agent → ALLOW.
out=$(run_guard '{"tool_name":"Agent","tool_input":{"subagent_type":"codex:codex-rescue","prompt":"adversarial review of the diff"}}')
[ -z "$out" ] && ok "allows real codex:* agent" || bad "should ALLOW codex:* agent"

# 6. Synthesis agent → ALLOW (must not block the debate/synthesis step).
out=$(run_guard '{"tool_name":"Agent","tool_input":{"subagent_type":"general-purpose","prompt":"Read review-1.md and review-2.md, debate the findings and synthesize a verdict into the doc."}}')
[ -z "$out" ] && ok "allows a pure-synthesis subagent" || bad "should ALLOW synthesis subagent"

# 7. Unrelated subagent (no review wording) → ALLOW.
out=$(run_guard '{"tool_name":"Agent","tool_input":{"subagent_type":"Explore","prompt":"find every call site of resolveToken"}}')
[ -z "$out" ] && ok "allows unrelated subagent" || bad "should ALLOW unrelated subagent"

echo "== guard (sentinel absent / stale) =="

# 8. No sentinel → ALLOW even an adversarial-review Claude agent.
rm -f "$FLAG"
out=$(run_guard '{"tool_name":"Agent","tool_input":{"subagent_type":"general-purpose","prompt":"adversarial review, try to refute"}}')
[ -z "$out" ] && ok "no sentinel → allow (guard is scoped, not always-on)" || bad "no sentinel should ALLOW"

# 9. Stale sentinel (>30min) → ALLOW + cleanup (proves the guard is load-bearing on freshness).
echo 1 > "$FLAG"   # epoch 1 = 1970, far stale
out=$(run_guard '{"tool_name":"Agent","tool_input":{"subagent_type":"general-purpose","prompt":"adversarial review, try to refute"}}')
[ -z "$out" ] && [ ! -f "$FLAG" ] && ok "stale sentinel → allow + cleanup" || bad "stale sentinel should ALLOW + remove flag"

echo
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
