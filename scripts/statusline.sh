#!/bin/bash
# Claude Code custom status line
# Reads JSON session data from stdin, outputs 2-line colored status bar
# Requires: jq, Nerd Font in terminal, AWS CLI with SSO

set -euo pipefail
# Fallback: if anything fails, output a safe plain-text line
trap 'echo "[statusline error]"; exit 0' ERR

# Read all JSON from stdin
INPUT=$(cat)

# --- Extract fresh fields from Claude Code JSON (never cached) ---
MODEL=$(echo "$INPUT" | jq -r '.model.display_name // "unknown"')
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // "--------"' | cut -c1-8)
DIR=$(echo "$INPUT" | jq -r '.workspace.current_dir // "."')
DIR_NAME="${DIR##*/}"
PCT=$(echo "$INPUT" | jq -r '.context_window.used_percentage // 0' | cut -d. -f1)
# Guard against empty string from jq
[ -z "$PCT" ] && PCT=0
COST=$(echo "$INPUT" | jq -r '.cost.total_cost_usd // 0')
TRANSCRIPT_PATH=$(echo "$INPUT" | jq -r '.transcript_path // ""')
PROJECT_DIR=""
[ -n "$TRANSCRIPT_PATH" ] && PROJECT_DIR=$(dirname "$TRANSCRIPT_PATH")

# --- Caching for slow external commands ---
CACHE_FILE="/tmp/claude-statusline-cache"
CACHE_MAX_AGE=5  # seconds

cache_is_stale() {
    [ ! -f "$CACHE_FILE" ] || \
    [ $(($(date +%s) - $(stat -f %m "$CACHE_FILE" 2>/dev/null || echo 0))) -gt $CACHE_MAX_AGE ]
}

if cache_is_stale; then
    # Git branch
    BRANCH=""
    if git rev-parse --git-dir > /dev/null 2>&1; then
        BRANCH=$(git branch --show-current 2>/dev/null || echo "")
    fi

    # AWS profile name
    AWS_PROF="${AWS_PROFILE:-${AWS_DEFAULT_PROFILE:-}}"
    if [ -z "$AWS_PROF" ]; then
        AWS_PROF=$(aws configure list 2>/dev/null | awk '/profile/ {print $2}' || echo "")
    fi
    [ "$AWS_PROF" = "<not" ] && AWS_PROF=""

    # AWS credential expiry — read from CLI role credential cache (most accurate)
    AWS_EXPIRY=""
    if [ -d "$HOME/.aws/cli/cache" ]; then
        CLI_FILE=$(ls -t "$HOME/.aws/cli/cache"/*.json 2>/dev/null | while read -r f; do
            if jq -e '.Credentials.Expiration' "$f" > /dev/null 2>&1; then
                echo "$f"
                break
            fi
        done)
        if [ -n "$CLI_FILE" ]; then
            AWS_EXPIRY=$(jq -r '.Credentials.Expiration // ""' "$CLI_FILE" 2>/dev/null)
        fi
    fi

    # Active sub-agent context windows
    # Sub-agents live at: ${TRANSCRIPT_PATH%.jsonl}/subagents/agent-*.jsonl
    AGENTS=""
    SUBAGENTS_DIR="${TRANSCRIPT_PATH%.jsonl}/subagents"
    if [ -n "$TRANSCRIPT_PATH" ] && [ -d "$SUBAGENTS_DIR" ]; then
        AGENT_COUNT=0
        MAX_PCT=0
        NOW=$(date +%s)
        for f in "$SUBAGENTS_DIR"/agent-*.jsonl; do
            [ -f "$f" ] || continue
            MTIME=$(stat -f %m "$f" 2>/dev/null || echo 0)
            [ $(( NOW - MTIME )) -gt 120 ] && continue  # only recently active files
            # Usage is top-level on JSONL entries; sum all input token types
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

    # Write cache: pipe-delimited single line
    echo "${BRANCH}|${AWS_PROF}|${AWS_EXPIRY}|${AGENTS}" > "$CACHE_FILE"
fi

# Read cached values
IFS='|' read -r BRANCH AWS_PROF AWS_EXPIRY AGENTS < "$CACHE_FILE"

# Validate cache wasn't corrupted (should have exactly 3 pipe chars)
if [ "$(tr -cd '|' < "$CACHE_FILE" | wc -c | tr -d ' ')" -ne 3 ]; then
    rm -f "$CACHE_FILE"
    BRANCH=""
    AWS_PROF=""
    AWS_EXPIRY=""
    AGENTS=""
fi

# --- Nerd Font Icons (defined via hex escapes to avoid encoding issues) ---
IC_MODEL=$(printf '\xEF\x8B\x9B')   # U+F2DB nf-fa-microchip
IC_SESSION=$(printf '\xEF\x8A\x92') # U+F292 nf-fa-hashtag
IC_DIR=$(printf '\xEF\x81\xBB')     # U+F07B nf-fa-folder
IC_BRANCH=$(printf '\xEE\x82\xA0')  # U+E0A0 nf-dev-git_branch
IC_AWS=$(printf '\xEF\x83\x82')     # U+F0C2 nf-fa-cloud
IC_CLOCK=$(printf '\xEF\x80\x97')   # U+F017 nf-fa-clock_o
IC_AGENTS=$(printf '\xEF\x82\xAE') # U+F0AE nf-fa-tasks

# --- Output Line 1 ---
LINE1="${IC_MODEL} $MODEL  ${IC_SESSION} $SESSION_ID │ ${IC_DIR} $DIR_NAME"

# Append git branch if available
if [ -n "$BRANCH" ]; then
    LINE1="${LINE1} │ ${IC_BRANCH} $BRANCH"
fi

# Append AWS profile if available
if [ -n "$AWS_PROF" ]; then
    LINE1="${LINE1} │ ${IC_AWS} $AWS_PROF"
fi

# Append active sub-agent count and highest context % if any are running
if [ -n "$AGENTS" ]; then
    AGENT_COUNT="${AGENTS%%:*}"
    AGENT_MAX_PCT="${AGENTS##*:}"
    LINE1="${LINE1} │ ${IC_AGENTS} ${AGENT_COUNT} ↓${AGENT_MAX_PCT}%"
fi

echo "$LINE1"

# --- Context Zone Colors ---
GREEN='\033[32m'
YELLOW='\033[33m'
RED='\033[31m'
RESET='\033[0m'

if [ "$PCT" -ge 60 ]; then
    ZONE_COLOR="$RED"
    ZONE_EMOJI="💀"
elif [ "$PCT" -ge 50 ]; then
    ZONE_COLOR="$YELLOW"
    ZONE_EMOJI="🦥"
else
    ZONE_COLOR="$GREEN"
    ZONE_EMOJI="🧠"
fi

# --- Progress Bar (10 chars) ---
BAR_WIDTH=10
FILLED=$((PCT * BAR_WIDTH / 100))
EMPTY=$((BAR_WIDTH - FILLED))
BAR=""
[ "$FILLED" -gt 0 ] && BAR=$(printf "%${FILLED}s" | tr ' ' '█')
[ "$EMPTY" -gt 0 ] && BAR="${BAR}$(printf "%${EMPTY}s" | tr ' ' '░')"

# --- Cost ---
COST_FMT=$(printf '$%.2f' "$COST")

# --- AWS SSO Timer ---
AWS_TIMER=""
AWS_TIMER_COLOR=""
if [ -n "$AWS_EXPIRY" ]; then
    # Parse ISO 8601 to epoch (macOS date -j -u for UTC)
    EXPIRY_EPOCH=$(date -j -u -f "%Y-%m-%dT%H:%M:%SZ" "$AWS_EXPIRY" "+%s" 2>/dev/null || echo 0)
    NOW_EPOCH=$(date +%s)
    REMAINING_SEC=$((EXPIRY_EPOCH - NOW_EPOCH))

    if [ "$REMAINING_SEC" -le 0 ]; then
        AWS_TIMER_COLOR="$RED"
        AWS_TIMER="⚠ AWS EXPIRED"
    elif [ "$REMAINING_SEC" -le 1800 ]; then
        # <= 30 minutes
        REMAINING_MIN=$((REMAINING_SEC / 60))
        AWS_TIMER_COLOR="$RED"
        AWS_TIMER="⚠  ${REMAINING_MIN}m left — REFRESH AWS"
    elif [ "$REMAINING_SEC" -le 7200 ]; then
        # <= 2 hours
        REMAINING_H=$((REMAINING_SEC / 3600))
        REMAINING_M=$(((REMAINING_SEC % 3600) / 60))
        AWS_TIMER_COLOR="$YELLOW"
        AWS_TIMER="${IC_CLOCK} ${REMAINING_H}h ${REMAINING_M}m left"
    else
        # > 2 hours
        REMAINING_H=$((REMAINING_SEC / 3600))
        REMAINING_M=$(((REMAINING_SEC % 3600) / 60))
        AWS_TIMER_COLOR=""
        AWS_TIMER="${IC_CLOCK} ${REMAINING_H}h ${REMAINING_M}m left"
    fi
else
    AWS_TIMER="${IC_CLOCK} no session"
fi

# --- Output Line 2 ---
# Zone color wraps the bar + percentage + emoji + cost
# AWS timer has its own independent color
AWS_TIMER_OUT=""
if [ -n "$AWS_TIMER_COLOR" ]; then
    AWS_TIMER_OUT="${AWS_TIMER_COLOR}${AWS_TIMER}${RESET}"
else
    AWS_TIMER_OUT="${AWS_TIMER}"
fi

printf '%b' "${ZONE_COLOR}${BAR} ${PCT}% ${ZONE_EMOJI} │ ${COST_FMT}${RESET} │ ${AWS_TIMER_OUT}\n"
