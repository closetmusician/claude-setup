#!/usr/bin/env bash
# ABOUTME: UserPromptSubmit hook — when the user invokes Codex (or asks for an adversarial /
# ABOUTME: second-opinion review), inject a mandatory directive to run the real Codex CLI
# ABOUTME: verbatim, and ARM a turn sentinel that codex-cli-guard.sh reads to block a Claude
# ABOUTME: subagent from imitating the review. Any prompt with no Codex intent DISARMS it.
# ABOUTME: Fail-open: any error → exit 0 silent. No network. bash+grep+jq only.
set -uo pipefail
trap 'exit 0' ERR

STATE_DIR="$HOME/.claude/state"
FLAG="$STATE_DIR/codex-turn.flag"

# disarm: clear a stale sentinel and stay silent. Called for every non-Codex prompt so the
# block is scoped to the turn that actually asked for Codex.
disarm() { rm -f "$FLAG" 2>/dev/null || true; exit 0; }

INPUT=$(cat 2>/dev/null || true)
PROMPT=$(printf '%s' "$INPUT" | jq -r '.prompt // empty' 2>/dev/null || true)
[ -z "$PROMPT" ] && disarm
P=$(printf '%s' "$PROMPT" | tr '[:upper:]' '[:lower:]' | head -c 2000)

# Codex intent = the literal tool name (+ speech-to-text aliases "code x"/"code ex"), or a
# bare "adversarial review/audit" / "second opinion" ask that the codex skill owns.
if printf '%s' "$P" | grep -qE '\bcodex\b|\bcode ?ex\b|adversarial(ly)? (review|audit)|second opinion|another opinion'; then
  mkdir -p "$STATE_DIR" 2>/dev/null || true
  date +%s > "$FLAG" 2>/dev/null || true
  # Resolve the newest installed companion script so this never rots when the plugin updates.
  CX=$(ls -d "$HOME"/.claude/plugins/cache/openai-codex/codex/*/scripts/codex-companion.mjs 2>/dev/null | sort -V | tail -1)
  CX=${CX:-"<codex-companion.mjs not found — run its setup subcommand>"}
  printf 'CODEX (hook): the user invoked Codex / an adversarial second opinion. Run the REAL Codex CLI and WAIT for its verbatim output — do NOT imitate a reviewer with a Claude subagent, and do NOT accept codex:codex-rescue'\''s async "it is running" message as the result. Run via Bash:\n  node "%s" adversarial-review --wait   (subcommand: review for a plain diff review; task for a free-form question)\nRelay/verify Codex'\''s own findings. Spawning a Claude/general subagent to PERFORM the review this turn will be BLOCKED; a subagent that only SYNTHESIZES Codex output is allowed.\n' "$CX"
  exit 0
fi

disarm
