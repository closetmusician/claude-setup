#!/bin/bash
# ABOUTME: Thin wrapper Stop hook that delegates to session-journal.py.
# ABOUTME: Reads Stop event JSON from stdin and pipes it to the Python script.
# ABOUTME: Kept as a bash wrapper because settings.json hooks point here.
# ABOUTME: Always exits 0 to never block Claude Code.
# ABOUTME: Journal location: ~/.claude/memory/journal.md

# Fail silently on any error — this hook must never block Claude.
exec python3 "$(dirname "$0")/session-journal.py" 2>/dev/null
exit 0
