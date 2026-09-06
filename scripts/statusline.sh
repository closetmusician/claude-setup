#!/bin/bash
# ABOUTME: Claude Code custom status line script (single-line for reliable rendering).
# ABOUTME: Reads JSON session data from stdin, outputs 1 dense line: context% │ model │ repo/branch │ agents.
# ABOUTME: Caches slow operations (git) with 5s TTL. No ANSI colors — plain text for max compatibility.
# ABOUTME: Requires: jq, Nerd Font in terminal.
# ABOUTME: Configured via settings.json statusLine.command.

set -euo pipefail
trap 'echo "[statusline error]"; exit 0' ERR

# Read all JSON from stdin
INPUT=$(cat)

# --- Extract fresh fields from Claude Code JSON (never cached) ---
MODEL=$(echo "$INPUT" | jq -r '.model.display_name // "unknown"')
DIR=$(echo "$INPUT" | jq -r '.workspace.current_dir // "."')
DIR_NAME="${DIR##*/}"
PCT=$(echo "$INPUT" | jq -r '.context_window.used_percentage // 0' | cut -d. -f1)
[ -z "$PCT" ] && PCT=0
TRANSCRIPT_PATH=$(echo "$INPUT" | jq -r '.transcript_path // ""')

# --- Caching for slow external commands ---
CACHE_FILE="/tmp/claude-statusline-cache"
CACHE_MAX_AGE=5

cache_is_stale() {
    [ ! -f "$CACHE_FILE" ] || \
    [ $(($(date +%s) - $(stat -f %m "$CACHE_FILE" 2>/dev/null || echo 0))) -gt $CACHE_MAX_AGE ]
}

if cache_is_stale; then
    BRANCH=""
    GIT_DIRTY=""
    if git rev-parse --git-dir > /dev/null 2>&1; then
        BRANCH=$(git branch --show-current 2>/dev/null || echo "")
        if [ -n "$(git status --porcelain 2>/dev/null | head -1)" ]; then
            GIT_DIRTY="*"
        fi
    fi

    # Active sub-agent context windows
    AGENTS=""
    SUBAGENTS_DIR="${TRANSCRIPT_PATH%.jsonl}/subagents"
    if [ -n "$TRANSCRIPT_PATH" ] && [ -d "$SUBAGENTS_DIR" ]; then
        AGENT_COUNT=0
        MAX_PCT=0
        NOW=$(date +%s)
        for f in "$SUBAGENTS_DIR"/agent-*.jsonl; do
            [ -f "$f" ] || continue
            MTIME=$(stat -f %m "$f" 2>/dev/null || echo 0)
            [ $(( NOW - MTIME )) -gt 120 ] && continue
            TOKENS=$(tail -100 "$f" 2>/dev/null \
                | jq -rs 'map(select(.type=="assistant")) | last | (.message.usage.input_tokens // 0) + (.message.usage.cache_read_input_tokens // 0) + (.message.usage.cache_creation_input_tokens // 0)' 2>/dev/null)
            if [ -z "$TOKENS" ] || [ "$TOKENS" = "null" ] || [ "$TOKENS" = "0" ]; then
                continue
            fi
            PCT_AGENT=$(( TOKENS * 100 / 200000 ))
            AGENT_COUNT=$(( AGENT_COUNT + 1 ))
            if [ "$PCT_AGENT" -gt "$MAX_PCT" ]; then MAX_PCT=$PCT_AGENT; fi
        done
        [ "$AGENT_COUNT" -gt 0 ] && AGENTS="${AGENT_COUNT}:${MAX_PCT}"
    fi

    echo "${BRANCH}|${GIT_DIRTY}|${AGENTS}" > "$CACHE_FILE"
fi

# Read cached values
IFS='|' read -r BRANCH GIT_DIRTY AGENTS < "$CACHE_FILE"

# Validate cache (should have exactly 2 pipes)
if [ "$(tr -cd '|' < "$CACHE_FILE" | wc -c | tr -d ' ')" -ne 2 ]; then
    rm -f "$CACHE_FILE"
    BRANCH=""
    GIT_DIRTY=""
    AGENTS=""
fi

# --- Progress Bar (10 chars, plain text) ---
BAR_WIDTH=10
FILLED=$((PCT * BAR_WIDTH / 100))
EMPTY=$((BAR_WIDTH - FILLED))
BAR=""
[ "$FILLED" -gt 0 ] && BAR=$(printf "%${FILLED}s" | tr ' ' '█')
[ "$EMPTY" -gt 0 ] && BAR="${BAR}$(printf "%${EMPTY}s" | tr ' ' '░')"

# --- Zone emoji based on context usage ---
if [ "$PCT" -ge 60 ]; then
    ZONE_EMOJI="💀"
elif [ "$PCT" -ge 50 ]; then
    ZONE_EMOJI="🦥"
else
    ZONE_EMOJI="🧠"
fi

# --- Build single output line ---
# Priority order: context% (critical) │ model │ repo/branch │ agents
LINE="${BAR} ${PCT}% ${ZONE_EMOJI} │ ${MODEL} │ ${DIR_NAME}"

if [ -n "$BRANCH" ]; then
    LINE="${LINE}/${BRANCH}${GIT_DIRTY}"
fi

if [ -n "$AGENTS" ]; then
    AGENT_COUNT="${AGENTS%%:*}"
    AGENT_MAX_PCT="${AGENTS##*:}"
    LINE="${LINE} │ ${AGENT_COUNT}agents ↓${AGENT_MAX_PCT}%"
fi

echo "$LINE"
