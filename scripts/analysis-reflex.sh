#!/usr/bin/env bash
# ABOUTME: Stop hook (Pillar II / S5): analysis-reflex — after-the-fact skeptic for analysis claims.
# ABOUTME: Fires when the final assistant message both (a) contains a synthesis/analysis-conclusion
# ABOUTME: claim AND (b) cites explicit primary sources (file:line patterns or artifact paths).
# ABOUTME: Writes a job spec JSON to $STATE/reflex-queue/ and exits 0 immediately — no model call.
# ABOUTME: Enqueue-not-block: DIVERGE may never block a turn. This hook always exits 0.

set -uo pipefail
trap 'exit 0' ERR

command -v jq >/dev/null 2>&1 || exit 0

INPUT=$(cat)

# ── Loop-protection: stop_hook_active retries are never re-enqueued ──────────
# (mirrors completion-claim-guard.sh stop_hook_active check)
if [[ "$(printf '%s' "$INPUT" | jq -r '.stop_hook_active // false' 2>/dev/null)" == "true" ]]; then
  exit 0
fi

TRANSCRIPT=$(printf '%s' "$INPUT" | jq -r '.transcript_path // empty' 2>/dev/null)
[[ -f "$TRANSCRIPT" ]] || exit 0

SESSION_ID=$(printf '%s' "$INPUT" | jq -r '.session_id // "unknown"' 2>/dev/null)

# ── Extract last assistant message text ──────────────────────────────────────
LAST=$(tail -80 "$TRANSCRIPT" | jq -rs '
  [ .[] | select(.type=="assistant") | .message.content
    | if type=="array" then (map(select(.type=="text") | .text) | join(" ")) else . end
  ] | last // empty' 2>/dev/null)
[[ -z "$LAST" ]] && exit 0

# ── (a) CLAIM regex: synthesis/analysis-conclusion shapes ────────────────────
# Designed to catch epistemic conclusions — sentences that assert the meaning or
# root cause of something rather than merely describing it.
#
# Regex set (case-insensitive OR):
#   "the root cause is"           — direct causal assertion
#   "this means"                  — semantic interpretation
#   "therefore"                   — logical conclusion marker
#   "the analysis shows"          — analysis-conclusion phrase
#   "thus "                       — formal conclusion marker
#   "it follows that"             — deductive conclusion
#   "the evidence (suggests|shows|indicates|points to)"  — evidence interpretation
#   "as a result,"                — causal conclusion
#   "in conclusion,"              — explicit conclusion marker
#   "the investigation (reveals|shows|found|confirms)"   — investigation conclusion
#   "this (confirms|demonstrates|indicates|proves)"      — assertion of demonstrated fact
CLAIM_REGEX='(the root cause is|this means[[:space:]]|therefore[[:space:]]|the analysis shows|[[:space:]]thus[[:space:]]|it follows that|the evidence (suggests|shows|indicates|points to)|as a result,|in conclusion,|the investigation (reveals|shows|found|confirms)|this (confirms|demonstrates|indicates|proves))'

if ! printf '%s' "$LAST" | grep -qiE "$CLAIM_REGEX"; then
  exit 0
fi

# ── (b) CITE regex: explicit primary sources must also be present ─────────────
# file:line pattern (e.g. src/foo.py:42) OR artifact paths (.md, .json, .log etc.)
CITE_FILE_LINE='[A-Za-z0-9_./-]+\.[A-Za-z]{1,5}:[0-9]+'
CITE_ARTIFACT='(~|/|[A-Za-z0-9_-]+/)[A-Za-z0-9._/-]*\.(md|json|log|txt|html|jsonl|py|ts|js|sh|go|rs|c|h|cpp)'

if ! printf '%s' "$LAST" | grep -qE "$CITE_FILE_LINE" && \
   ! printf '%s' "$LAST" | grep -qiE "$CITE_ARTIFACT"; then
  exit 0
fi

# ── Both conditions met: extract claim excerpt and cited sources ──────────────
# Claim excerpt: the matching sentence (first 300 chars)
CLAIM_EXCERPT=$(printf '%s' "$LAST" | grep -iEo '.{0,50}(the root cause is|this means |therefore |the analysis shows| thus |it follows that|the evidence (suggests|shows|indicates|points to)|as a result,|in conclusion,|the investigation (reveals|shows|found|confirms)|this (confirms|demonstrates|indicates|proves)).{0,200}' | head -1 | cut -c1-300)
[[ -z "$CLAIM_EXCERPT" ]] && CLAIM_EXCERPT=$(printf '%s' "$LAST" | cut -c1-300)

# Cited sources: collect file:line tokens + artifact path tokens
CITED_SOURCES_ARR=()
while IFS= read -r tok; do
  [[ -n "$tok" ]] && CITED_SOURCES_ARR+=("$tok")
done < <(printf '%s' "$LAST" | grep -oE "$CITE_FILE_LINE" | head -10)
while IFS= read -r tok; do
  [[ -n "$tok" ]] && CITED_SOURCES_ARR+=("$tok")
done < <(printf '%s' "$LAST" | grep -oiE "$CITE_ARTIFACT" | head -10)

# Build JSON array of cited sources
CITED_JSON=$(printf '%s\n' "${CITED_SOURCES_ARR[@]:-}" | \
  jq -Rsc '[split("\n")[] | select(length>0)]' 2>/dev/null || echo '[]')

# ── Resolve STATE dir ─────────────────────────────────────────────────────────
if [[ -n "${STATE:-}" ]]; then
  STATE_DIR="$STATE"
else
  TOPLEVEL=$(git rev-parse --show-toplevel 2>/dev/null || true)
  if [[ -n "$TOPLEVEL" ]]; then
    STATE_DIR="$TOPLEVEL/.agents/claude-governance"
  else
    STATE_DIR="$HOME/.claude/state"
  fi
fi

QUEUE_DIR="$STATE_DIR/reflex-queue"
mkdir -p "$QUEUE_DIR" 2>/dev/null || exit 0

# ── Build timestamp ───────────────────────────────────────────────────────────
if command -v gdate >/dev/null 2>&1; then
  TS=$(gdate -u +%Y-%m-%dT%H:%M:%S.%3NZ 2>/dev/null)
elif command -v python3 >/dev/null 2>&1; then
  TS=$(python3 -c "from datetime import datetime,timezone; print(datetime.now(timezone.utc).strftime('%Y-%m-%dT%H:%M:%S.')+str(datetime.now(timezone.utc).microsecond//1000).zfill(3)+'Z')" 2>/dev/null)
else
  TS=$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo "1970-01-01T00:00:00Z")
fi

# ── Write job file ────────────────────────────────────────────────────────────
SAFE_TS="${TS//:/-}"
SAFE_TS="${SAFE_TS//./-}"
JOB_FILE="$QUEUE_DIR/reflex-${SAFE_TS}-${SESSION_ID:0:8}.json"

jq -cn \
  --arg ts "$TS" \
  --arg transcript_path "$TRANSCRIPT" \
  --arg claim_excerpt "$CLAIM_EXCERPT" \
  --argjson cited_sources "$CITED_JSON" \
  '{
    ts: $ts,
    transcript_path: $transcript_path,
    claim_excerpt: $claim_excerpt,
    cited_sources: $cited_sources
  }' > "$JOB_FILE" 2>/dev/null || true

exit 0
