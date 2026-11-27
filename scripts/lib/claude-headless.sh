#!/usr/bin/env bash
# ABOUTME: Runs headless `claude -p` on Yu-Kuan's Claude.ai plan (owner, 2026-11-22).
# ABOUTME: Clears every Bedrock variable, so a launch never routes to AWS Bedrock.
# ABOUTME: Why: the company AWS policy denies all Claude models on Bedrock (seen 2026-11-22).
# ABOUTME: Usage: source scripts/lib/claude-headless.sh && claude_headless -p --model haiku ...,
# ABOUTME:    or: scripts/lib/claude-headless.sh -p --model opus <<< "prompt"

set -euo pipefail

# Purpose: drop the variables that would send a launch to Bedrock.
# Usage: runs automatically when sourced or executed.
# Gotchas: ~/.zshrc already unsets CLAUDE_CODE_USE_BEDROCK; this also covers cron and launchd shells.
unset CLAUDE_CODE_USE_BEDROCK AWS_PROFILE AWS_REGION ANTHROPIC_DEFAULT_SONNET_MODEL || true

# Purpose: run claude with the given arguments on the Claude.ai plan.
# Usage: claude_headless -p --model sonnet <<< "prompt"
# Gotchas: model aliases (opus, sonnet, haiku) pass through unchanged; Claude Code resolves them.
claude_headless() {
  claude "$@"
}

# Purpose: when executed (not sourced), run claude_headless with all arguments.
# Usage: scripts/lib/claude-headless.sh -p --model opus <<< "prompt"
# Gotchas: detects execution by comparing BASH_SOURCE with $0.
if [[ "${BASH_SOURCE[0]:-}" == "${0}" ]]; then
  claude_headless "$@"
fi
