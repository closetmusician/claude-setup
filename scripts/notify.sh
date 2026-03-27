#!/usr/bin/env bash
# ABOUTME: Cross-platform notification wrapper for Claude Code hooks.
# ABOUTME: Tries terminal-notifier (macOS), then notify-send (Linux),
# ABOUTME: then falls back to a no-op so hooks never fail on missing
# ABOUTME: notification tools.

MESSAGE="${1:-Claude Code}"
SOUND="${2:-default}"

if command -v terminal-notifier &>/dev/null; then
    terminal-notifier -title 'Claude Code' -message "$MESSAGE" -sound "$SOUND"
elif command -v notify-send &>/dev/null; then
    notify-send 'Claude Code' "$MESSAGE"
fi
# Silent no-op if neither is available
