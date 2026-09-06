#!/usr/bin/env bash
# ABOUTME: PreToolUse(Agent) hook: denies a 2nd+ parallel spawn whose declared ## Output:
# ABOUTME: path overlaps an in-flight sibling's claimed output. Implements H-34 / lane6 PROP-2.
# ABOUTME: FAIL-OPEN by design — any parse/jq failure, missing declarations, or absent state
# ABOUTME: allows the spawn; only genuine path overlaps between concurrent spawns are denied.
# ABOUTME: Depends on DA-02 (dispatch-templates ## Output: marker) for real enforcement value.

set -uo pipefail
# FAIL-OPEN: any error exits 0 — never block real work on hook failure.
trap 'exit 0' ERR

command -v jq >/dev/null 2>&1 || exit 0

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/project-root.sh"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/../lib/emit-event.sh" 2>/dev/null || true

# Read the full hook payload from stdin — NEVER from env (identity lesson).
INPUT=$(cat)

SESSION_ID=$(printf '%s' "$INPUT" | jq -r '.session_id // empty' 2>/dev/null)
# Without a session_id we cannot key state — fail-open.
[[ -z "$SESSION_ID" || "$SESSION_ID" == "null" ]] && exit 0

# Sanitize session_id to prevent path traversal.
SESSION_ID=$(printf '%s' "$SESSION_ID" | tr -dc 'A-Za-z0-9_-')
[[ -z "$SESSION_ID" ]] && exit 0

# State file tracks claimed output paths for this session (one per line, JSON array).
STATE_DIR="${HARNESS_GOV_STATE_DIR:-$(get_governance_state_dir)}"
mkdir -p "$STATE_DIR" 2>/dev/null || true
CLAIMS_FILE="$STATE_DIR/claimed-output-paths-${SESSION_ID}.json"

# ── Extract prompt ───────────────────────────────────────────────────────────
PROMPT=$(printf '%s' "$INPUT" | jq -r '.tool_input.prompt // empty' 2>/dev/null)
if [[ -z "$PROMPT" ]]; then
  exit 0
fi

# ── Extract declared output paths from the prompt ────────────────────────────
# Matches both:
#   ## Output: <path>
#   Output file: <path>
# Captures the path value (trimmed); emits one path per line.
extract_output_paths() {
  local prompt="$1"
  # Extract ## Output: <path> and Output file: <path> markers.
  # Use perl for portability (BSD/GNU grep -P not universal).
  printf '%s' "$prompt" | \
    perl -ne 'if (/^(?:##\s*Output|Output file)\s*:\s*(.+)/i) { my $p=$1; $p=~s/^\s+|\s+$//g; print "$p\n" if length($p) > 0 }'
}

DECLARED_PATHS=$(extract_output_paths "$PROMPT")

# ── Fail-open: no declared output paths ─────────────────────────────────────
if [[ -z "$DECLARED_PATHS" ]]; then
  # Log a warning to state (non-blocking).
  printf '%s parallel-scope-guard: no ## Output: declaration in prompt — fail-open allow\n' \
    "$(date -u +%Y-%m-%dT%H:%M:%SZ)" >> "$STATE_DIR/parallel-scope-guard-warns.log" 2>/dev/null || true
  exit 0
fi

# ── Load existing claimed paths for this session ─────────────────────────────
EXISTING_PATHS=()
if [[ -f "$CLAIMS_FILE" ]]; then
  # Read paths from JSON array — one element per entry.
  while IFS= read -r p; do
    [[ -n "$p" ]] && EXISTING_PATHS+=("$p")
  done < <(jq -r '.[]' "$CLAIMS_FILE" 2>/dev/null || true)
fi

# ── Check for overlaps ───────────────────────────────────────────────────────
# Overlap: exact match OR one path is a prefix of the other (directory containment).
# Normalise paths: strip trailing slash for prefix comparison.
paths_overlap() {
  local a="$1" b="$2"
  # Strip trailing slashes for comparison.
  a="${a%/}"; b="${b%/}"
  # Exact match.
  [[ "$a" == "$b" ]] && return 0
  # a is a prefix of b (directory containment: a/ is a parent of b).
  [[ "$b" == "${a}/"* ]] && return 0
  # b is a prefix of a.
  [[ "$a" == "${b}/"* ]] && return 0
  return 1
}

OVERLAP_FOUND=""
OVERLAP_NEW=""
OVERLAP_EXISTING=""
while IFS= read -r new_path; do
  [[ -z "$new_path" ]] && continue
  for existing in "${EXISTING_PATHS[@]:-}"; do
    [[ -z "$existing" ]] && continue
    if paths_overlap "$new_path" "$existing"; then
      OVERLAP_FOUND="1"
      OVERLAP_NEW="$new_path"
      OVERLAP_EXISTING="$existing"
      break 2
    fi
  done
done <<< "$DECLARED_PATHS"

if [[ -n "$OVERLAP_FOUND" ]]; then
  # Emit telemetry before denying.
  emit_event "trust_decision" \
    "{\"guard\":\"parallel-scope-guard\",\"new_path\":\"${OVERLAP_NEW}\",\"existing_path\":\"${OVERLAP_EXISTING}\"}" \
    outcome="denied" source="parallel-scope-guard.sh" || true

  jq -cn \
    --arg new_path "$OVERLAP_NEW" \
    --arg existing_path "$OVERLAP_EXISTING" \
    '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":
      ("parallel agent output paths overlap with an in-flight spawn — make scopes disjoint or serialize. Conflicting path: "+$new_path+" already claimed by sibling targeting: "+$existing_path)}}'
  exit 0
fi

# ── Allow: record the new paths in the claims file ───────────────────────────
NEW_PATHS_JSON=$(printf '%s' "$DECLARED_PATHS" | jq -Rs 'split("\n") | map(select(length > 0))' 2>/dev/null || echo '[]')

if [[ -f "$CLAIMS_FILE" ]]; then
  # Merge: existing array + new paths.
  MERGED=$(jq -cn \
    --argjson existing "$(jq '.' "$CLAIMS_FILE" 2>/dev/null || echo '[]')" \
    --argjson new_paths "$NEW_PATHS_JSON" \
    '$existing + $new_paths | unique' 2>/dev/null || echo '[]')
else
  MERGED="$NEW_PATHS_JSON"
fi

printf '%s\n' "$MERGED" > "$CLAIMS_FILE" 2>/dev/null || true

emit_event "trust_decision" \
  "{\"guard\":\"parallel-scope-guard\",\"paths_recorded\":$NEW_PATHS_JSON}" \
  outcome="allowed" source="parallel-scope-guard.sh" || true

exit 0
