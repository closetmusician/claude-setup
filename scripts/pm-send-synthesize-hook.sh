#!/bin/bash
# ABOUTME: SessionEnd hook that triggers pm-send feedback synthesis in background.
# ABOUTME: Checks if feedback.jsonl is newer than patterns.md (mtime guard),
# ABOUTME: then spawns synthesize-feedback.js via nohup so it runs after session exits.
# ABOUTME: Returns in <100ms — synthesis happens asynchronously.
# ABOUTME: Log output: /tmp/pm-send-synthesize.log

set -euo pipefail

# Fail silently on any error — this hook must never block Claude.
trap 'exit 0' ERR

# Read stdin (hooks protocol requires consuming it).
cat > /dev/null 2>&1 || true

FEEDBACK_FILE="$HOME/Code/pm_os/state/pm-send-feedback.jsonl"
PATTERNS_FILE="$HOME/Code/pm_os/state/pm-send-patterns.md"
SCRIPT="$HOME/Code/pm_os/bin/synthesize-feedback.js"

# Exit if no feedback file exists.
if [ ! -f "$FEEDBACK_FILE" ]; then
  exit 0
fi

# Exit if patterns file is newer than feedback (already up to date).
if [ -f "$PATTERNS_FILE" ]; then
  FEEDBACK_MTIME=$(stat -f %m "$FEEDBACK_FILE" 2>/dev/null || echo "0")
  PATTERNS_MTIME=$(stat -f %m "$PATTERNS_FILE" 2>/dev/null || echo "0")
  if [ "$PATTERNS_MTIME" -ge "$FEEDBACK_MTIME" ]; then
    exit 0
  fi
fi

# Spawn synthesis in background — runs after session exits.
nohup node "$SCRIPT" >> /tmp/pm-send-synthesize.log 2>&1 &

exit 0
