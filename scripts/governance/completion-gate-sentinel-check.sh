#!/usr/bin/env bash
# ABOUTME: Stop hook: blocks a completion claim while VIBE gate sentinels are live or the
# ABOUTME: evidence ledger has RED items. Extends completion-claim-guard.sh (runs after it).
# ABOUTME: Only active in governed pipelines (requires $STATE/.active). Fail-open on all
# ABOUTME: errors — a crashed guard must never block real work. H-16 / lane6 PROP-4.
# ABOUTME: PKT-JD-01. Reads identity from STDIN JSON only — never env ($SESSION_ID unset).

set -uo pipefail

# Safety net: any unexpected error → fail-open so we never block real work.
trap 'exit 0' ERR

# Bail gracefully if jq is missing.
if ! command -v jq &>/dev/null; then
  printf '%s completion-gate-sentinel-check: jq not found, skipping\n' \
    "$(date -u +%Y-%m-%dT%H:%M:%SZ)" >&2
  exit 0
fi

# ─── Resolve governance script dir and shared helpers ────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib/project-root.sh"
# Pillar I emit — additive only; fail-open by design.
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/../lib/emit-event.sh" 2>/dev/null || true

# ─── Read stdin JSON (identity must come from here — never env, per L-27) ───
INPUT=$(cat)

# ─── Resolve the governance state directory ───────────────────────────────────
# HARNESS_GOV_STATE_DIR override (non-empty) is handled by get_governance_state_dir().
STATE="$(get_governance_state_dir)"

# ─── Guard: only active in governed pipelines ─────────────────────────────────
if [[ ! -f "$STATE/.active" ]]; then
  exit 0
fi

# ─── Extract the last assistant message text from the transcript ──────────────
TRANSCRIPT=$(printf '%s' "$INPUT" | jq -r '.transcript_path // empty')
if [[ ! -f "$TRANSCRIPT" ]]; then
  exit 0
fi

LAST=$(tail -80 "$TRANSCRIPT" | jq -rs '
  [ .[] | select(.type=="assistant") | .message.content
    | if type=="array" then (map(select(.type=="text") | .text) | join(" ")) else . end
  ] | last // empty' 2>/dev/null) || LAST=""
[[ -z "$LAST" ]] && exit 0

# ─── Completion-claim detection (CLAIM regex sourced from completion-claim-guard) ───
# Per spec: "reuse completion-claim-guard's CLAIM regex; source it, do not re-implement."
# We extract the CLAIM= line from the guard and eval it here — single source of truth.
# If extraction fails (file missing/format changed), fall back to a minimal regex so the
# guard degrades gracefully (fail-open for the claim-detection step only).
CCG="${SCRIPT_DIR}/../completion-claim-guard.sh"
CLAIM=""
if [[ -f "$CCG" ]]; then
  # grep the exact CLAIM='...' assignment; eval it to set CLAIM in this scope.
  _claim_line="$(grep -m1 "^CLAIM='" "$CCG" 2>/dev/null)" || _claim_line=""
  if [[ -n "$_claim_line" ]]; then
    eval "$_claim_line" 2>/dev/null || CLAIM=""
  fi
fi
# Minimal fallback if extraction failed.
if [[ -z "$CLAIM" ]]; then
  CLAIM='(all tests? pass(ed)?|implementation (is )?complete|task is (done|complete|finished)|completed successfully|everything works|\ball done\b|\bLGTM\b|ready (for review|to merge))'
fi

# If the last message contains no completion claim, nothing to check.
if ! printf '%s' "$LAST" | grep -qiE "$CLAIM"; then
  exit 0
fi

# ─── Helper: emit block JSON and exit ────────────────────────────────────────
block() {
  emit_event "trust_decision" \
    '{"guard":"completion-gate-sentinel-check","claim_type":"completion"}' \
    outcome="denied" source="completion-gate-sentinel-check.sh" || true
  jq -cn --arg r "$1" '{"decision":"block","reason":$r}'
  exit 0
}

# ─── Step 1: Scan for live gate sentinels (.gate-* files) ────────────────────
# Any .gate-* present while a completion is claimed means the pipeline isn't done.
# Use find with -maxdepth 1 to avoid traversing subdirs.
gate_file=""
while IFS= read -r gf; do
  [[ -n "$gf" ]] && gate_file="$gf" && break
done < <(find "$STATE" -maxdepth 1 -name '.gate-*' -type f 2>/dev/null)

if [[ -n "$gate_file" ]]; then
  gate_name="$(basename "$gate_file")"
  block "Governance gate sentinel '${gate_name}' still active — pipeline not complete. Clear all .gate-* sentinels in $STATE before claiming completion. (Manual recovery: rm $gate_file)"
fi

# ─── Step 2: Check evidence ledger for RED items ─────────────────────────────
# If latest-evidence-ledger.json exists and has any item with status=RED (or
# "status":"RED"), block the completion claim naming the first RED item found.
#
# Fail-open: if the ledger is missing, malformed, or jq fails — allow.
LEDGER="${STATE}/latest-evidence-ledger.json"
if [[ -f "$LEDGER" ]]; then
  # Extract the first RED item's id or description for a useful error message.
  red_item=""
  red_item=$(jq -r '
    # Support array of items or an object with an "items" array.
    (if type == "array" then . else (.items // []) end)
    | map(select(
        (.status // .result // .state // "" | ascii_upcase) == "RED"
      ))
    | if length == 0 then empty
      else first | (.id // .name // .description // "unknown item")
      end
  ' "$LEDGER" 2>/dev/null) || red_item=""

  if [[ -n "$red_item" && "$red_item" != "null" ]]; then
    block "Evidence ledger has RED items (first: '${red_item}') — resolve all RED items in $LEDGER before claiming completion."
  fi
fi

exit 0
