#!/usr/bin/env bash
# ABOUTME: PreToolUse hook (Agent/Task) — while a Codex request is active this turn, BLOCK a
# ABOUTME: Claude/general subagent spawned to PERFORM an adversarial / second-opinion review
# ABOUTME: (imitation). Real codex:* agents and pure-synthesis subagents are always allowed.
# ABOUTME: Sentinel is armed by codex-cli-nudge.sh and self-expires after 30 min.
# ABOUTME: Fail-open: any error or no sentinel → exit 0 (allow). bash+grep+jq only.
set -uo pipefail
trap 'exit 0' ERR

FLAG="$HOME/.claude/state/codex-turn.flag"
[ -f "$FLAG" ] || exit 0

# Self-expire: a sentinel older than 30 min is stale (turn ended without a clean disarm).
NOW=$(date +%s); TS=$(cat "$FLAG" 2>/dev/null || echo 0)
case "$TS" in ''|*[!0-9]*) TS=0;; esac
[ $(( NOW - TS )) -gt 1800 ] && { rm -f "$FLAG" 2>/dev/null || true; exit 0; }

INPUT=$(cat 2>/dev/null || true)

# Real Codex agent (codex:codex-rescue etc.) → always allow; the nudge steers it to the CLI.
ST=$(printf '%s' "$INPUT" | jq -r '.tool_input.subagent_type // empty' 2>/dev/null || true)
case "$ST" in *codex*) exit 0;; esac

BODY=$(printf '%s' "$INPUT" | jq -r '(.tool_input.prompt // "") + " " + (.tool_input.description // "")' 2>/dev/null | tr '[:upper:]' '[:lower:]')

# Allow: the subagent CONSUMES existing review output rather than producing a review.
if printf '%s' "$BODY" | grep -qE 'synthesi|consolidat|reconcile|debate .*(finding|review)|read (the )?review-|merge (the )?(finding|review)'; then
  exit 0
fi

# Block: the subagent is clearly being asked to PERFORM an adversarial / second-opinion review.
if printf '%s' "$BODY" | grep -qE 'adversarial|second opinion|red.?team|try to (refute|break)|you are (an?|the) (adversarial|skeptical) (auditor|reviewer|critic)|independently (verify|review|audit)|audit (this|the) (doc|diagnosis|claim|file)'; then
  reason='Codex was requested this turn. Run the real Codex CLI verbatim (node <codex-companion.mjs> adversarial-review --wait) — do NOT spawn a Claude/general subagent to imitate a Codex / adversarial / second-opinion review. If this subagent only SYNTHESIZES existing Codex output, include "synthesize"/"reconcile"/"read review-" in its prompt; if it is unrelated to the review, remove the adversarial/audit wording.'
  jq -cn --arg r "$reason" '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":$r}}' 2>/dev/null || { printf '%s\n' "$reason" >&2; exit 2; }
  exit 0
fi
exit 0
