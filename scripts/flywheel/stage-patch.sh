#!/usr/bin/env bash
# ABOUTME: Pillar III-5 staging script. Takes a draft diff from the flywheel drafts dir,
# ABOUTME: reads the eval_run verdict (STAGE-OK/STAGE-REFUSED), and materializes the
# ABOUTME: patch as a STAGED artifact pair: <id>.proposed + <id>.proposed.evidence.md.
# ABOUTME: NEVER auto-applies to the real file. STAGE-REFUSED drafts are logged only.
# ABOUTME: Usage: STAGE_EVAL_RESULT=<json_file> STAGE_INCIDENT_JSON=<json> bash stage-patch.sh <draft.diff>
# ABOUTME: Env overrides: STAGE_STAGING_DIR, STAGE_STATE_DIR, STAGE_TARGET_OVERRIDE.

set -uo pipefail
trap 'echo "[stage-patch] WARN: error on line $LINENO" >&2' ERR

# ── Dependency check ──────────────────────────────────────────────────────────
command -v jq >/dev/null 2>&1 || { echo "[stage-patch] SKIP: jq not found" >&2; exit 0; }
command -v python3 >/dev/null 2>&1 || { echo "[stage-patch] SKIP: python3 not found" >&2; exit 0; }

# ── Arguments ─────────────────────────────────────────────────────────────────
DRAFT_DIFF="${1:-}"
if [[ -z "$DRAFT_DIFF" ]]; then
  echo "[stage-patch] ERROR: draft diff path required as first argument" >&2
  echo "Usage: bash stage-patch.sh <draft.diff>" >&2
  exit 1
fi

if [[ ! -f "$DRAFT_DIFF" ]]; then
  echo "[stage-patch] ERROR: draft diff not found: $DRAFT_DIFF" >&2
  exit 1
fi

# ── Resolve STATE and STAGING directories ─────────────────────────────────────
# Purpose: State dir for logging; staging dir for .proposed artifacts (NEVER under tracked source).
# Production: $HOME/.claude/state/flywheel/staging/
# Tests: override via STAGE_STAGING_DIR / STAGE_STATE_DIR env vars.
# Gotchas: staging dir must NOT be under ~/.claude tracked tree.
if [[ -n "${STAGE_STATE_DIR:-}" ]]; then
  _STATE_DIR="$STAGE_STATE_DIR"
elif [[ -n "${HARNESS_STATE_OVERRIDE:-}" ]]; then
  _STATE_DIR="$HARNESS_STATE_OVERRIDE"
else
  _claude_top="$(git -C "${HOME}/.claude" rev-parse --show-toplevel 2>/dev/null)" || _claude_top=""
  if [[ -n "$_claude_top" ]]; then
    _STATE_DIR="${_claude_top}/.agents/claude-governance"
  else
    _STATE_DIR="${HOME}/.claude/state"
  fi
fi

if [[ -n "${STAGE_STAGING_DIR:-}" ]]; then
  STAGING_DIR="$STAGE_STAGING_DIR"
else
  STAGING_DIR="${_STATE_DIR}/state/flywheel/staging"
fi

mkdir -p "$STAGING_DIR" 2>/dev/null || true

# ── Logging helper ────────────────────────────────────────────────────────────
_log() { printf '[stage-patch] %s\n' "$*" >&2; }

# ── Derive patch ID from diff filename ────────────────────────────────────────
# Purpose: stable ID for referencing the staged artifact (used by harness eval apply).
# Format: <class>-<ts-slug> derived from the draft filename.
DRAFT_BASENAME="$(basename "$DRAFT_DIFF" .diff)"
PATCH_ID="$DRAFT_BASENAME"

_log "Processing draft: $DRAFT_BASENAME"

# ── Read eval result ──────────────────────────────────────────────────────────
# Purpose: determine if this draft passed corpus eval (STAGE-OK) or failed (STAGE-REFUSED).
# env STAGE_EVAL_RESULT: path to a JSON file with {"verdict":"STAGE-OK|STAGE-REFUSED",...}
# If not set: we run harness eval run --with-patch in-process. For tests, the env var is injected.
EVAL_VERDICT=""
EVAL_PASSED=0
EVAL_FAILED=0
EVAL_REGRESSIONS="[]"
EVAL_CORPUS=0

if [[ -n "${STAGE_EVAL_RESULT:-}" ]] && [[ -f "${STAGE_EVAL_RESULT}" ]]; then
  # Read pre-computed result (test injection or cached result from nightly-flywheel)
  EVAL_JSON="$(cat "${STAGE_EVAL_RESULT}")"
  EVAL_VERDICT="$(printf '%s' "$EVAL_JSON" | jq -r '.verdict // "STAGE-REFUSED"' 2>/dev/null)" || EVAL_VERDICT="STAGE-REFUSED"
  EVAL_PASSED="$(printf '%s' "$EVAL_JSON" | jq -r '.passed // 0' 2>/dev/null)" || EVAL_PASSED=0
  EVAL_FAILED="$(printf '%s' "$EVAL_JSON" | jq -r '.failed // 0' 2>/dev/null)" || EVAL_FAILED=0
  EVAL_REGRESSIONS="$(printf '%s' "$EVAL_JSON" | jq -r '.regressions // []' 2>/dev/null)" || EVAL_REGRESSIONS="[]"
  EVAL_CORPUS="$(printf '%s' "$EVAL_JSON" | jq -r '.corpus // 0' 2>/dev/null)" || EVAL_CORPUS=0
else
  # Run harness eval run --with-patch live (production path)
  HARNESS="${HARNESS_BIN:-${HOME}/.claude/bin/harness}"
  if [[ ! -x "$HARNESS" ]]; then
    _log "WARN: harness not found at $HARNESS — defaulting to STAGE-REFUSED"
    EVAL_VERDICT="STAGE-REFUSED"
  else
    EVAL_OUTPUT="$(HARNESS_STATE_OVERRIDE="${_STATE_DIR}" "$HARNESS" eval run --with-patch "$DRAFT_DIFF" 2>/dev/null)" || true
    EVAL_VERDICT="$(printf '%s' "$EVAL_OUTPUT" | grep '^VERDICT:' | awk '{print $2}')" || EVAL_VERDICT=""
    if [[ -z "$EVAL_VERDICT" ]]; then
      EVAL_VERDICT="$(printf '%s' "$EVAL_OUTPUT" | grep '"verdict"' | python3 -c \
        "import sys,json; lines=sys.stdin.read(); d=json.loads('{'+lines.split('{',1)[1].split('}')[0]+'}'); print(d.get('verdict','STAGE-REFUSED'))" 2>/dev/null)" || EVAL_VERDICT="STAGE-REFUSED"
    fi
    # Try to extract summary JSON from the eval output
    EVAL_JSON_LINE="$(printf '%s' "$EVAL_OUTPUT" | grep '"verdict"' | head -1)" || EVAL_JSON_LINE=""
    if [[ -n "$EVAL_JSON_LINE" ]]; then
      EVAL_PASSED="$(printf '%s' "$EVAL_JSON_LINE" | jq -r '.passed // 0' 2>/dev/null)" || EVAL_PASSED=0
      EVAL_FAILED="$(printf '%s' "$EVAL_JSON_LINE" | jq -r '.failed // 0' 2>/dev/null)" || EVAL_FAILED=0
      EVAL_REGRESSIONS="$(printf '%s' "$EVAL_JSON_LINE" | jq -r '.regressions // []' 2>/dev/null)" || EVAL_REGRESSIONS="[]"
      EVAL_CORPUS="$(printf '%s' "$EVAL_JSON_LINE" | jq -r '.corpus // 0' 2>/dev/null)" || EVAL_CORPUS=0
    fi
    [[ -z "$EVAL_VERDICT" ]] && EVAL_VERDICT="STAGE-REFUSED"
  fi
fi

_log "Eval verdict: $EVAL_VERDICT (passed=$EVAL_PASSED failed=$EVAL_FAILED)"

# ── STAGE-REFUSED: log and exit (do not stage) ────────────────────────────────
if [[ "$EVAL_VERDICT" != "STAGE-OK" ]]; then
  _log "STAGE-REFUSED: draft $PATCH_ID not staged (regressions: $EVAL_REGRESSIONS)"
  # Write a refused log entry for auditability
  REFUSED_LOG="${STAGING_DIR}/${PATCH_ID}.refused.log"
  {
    printf '# STAGE-REFUSED\n'
    printf 'patch_id: %s\n' "$PATCH_ID"
    printf 'verdict: %s\n' "$EVAL_VERDICT"
    printf 'regressions: %s\n' "$EVAL_REGRESSIONS"
    printf 'draft: %s\n' "$DRAFT_DIFF"
    printf 'ts: %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo 'unknown')"
  } > "$REFUSED_LOG" 2>/dev/null || true
  exit 0
fi

# ── STAGE-OK: materialize .proposed + .evidence.md ────────────────────────────
# Purpose: Create the staged artifact pair. The .proposed file contains the patched
#   file content (or the diff itself if we can't determine the target). The
#   .evidence.md links back to the incident, eval result, and one-click apply command.
# Gotchas: NEVER write to the real target file. Artifacts go under STAGING_DIR.
#   STAGE_TARGET_OVERRIDE env: for tests, specify the dummy target path.

# Determine the target file from the diff (--- a/<path> line)
TARGET_FILE_FROM_DIFF=""
TARGET_FILE_FROM_DIFF="$(grep -m1 '^--- ' "$DRAFT_DIFF" | sed 's|^--- a/||; s|^--- ||' | tr -d '[:space:]')" || TARGET_FILE_FROM_DIFF=""
# Strip leading a/ prefix if present
TARGET_FILE_FROM_DIFF="${TARGET_FILE_FROM_DIFF#a/}"

# Resolve the actual target path (real file in ~/.claude)
if [[ -n "${STAGE_TARGET_OVERRIDE:-}" ]]; then
  ACTUAL_TARGET="$STAGE_TARGET_OVERRIDE"
elif [[ -n "$TARGET_FILE_FROM_DIFF" ]]; then
  ACTUAL_TARGET="${HOME}/.claude/${TARGET_FILE_FROM_DIFF}"
else
  ACTUAL_TARGET=""
fi

_log "Target: ${ACTUAL_TARGET:-<unknown>}"

# Write .proposed (patched file content OR raw diff as fallback)
PROPOSED_FILE="${STAGING_DIR}/${PATCH_ID}.proposed"

if [[ -n "$ACTUAL_TARGET" ]] && [[ -f "$ACTUAL_TARGET" ]]; then
  # Apply diff to a tempdir copy to get the patched content
  _APPLY_TMP="$(mktemp -d /tmp/stage-patch-apply-XXXXXX)"
  _APPLY_COPY="$_APPLY_TMP/$(basename "$ACTUAL_TARGET")"
  cp "$ACTUAL_TARGET" "$_APPLY_COPY" 2>/dev/null || true
  _PATCH_EC=0
  ( cd "$_APPLY_TMP" && patch -p1 < "$DRAFT_DIFF" 2>/dev/null ) || _PATCH_EC=$?
  if [[ "$_PATCH_EC" -eq 0 ]] && [[ -f "$_APPLY_COPY" ]]; then
    cp "$_APPLY_COPY" "$PROPOSED_FILE" 2>/dev/null || true
    _log "Wrote .proposed (patched content): $PROPOSED_FILE"
  else
    # Fallback: store the raw diff
    cp "$DRAFT_DIFF" "$PROPOSED_FILE" 2>/dev/null || true
    _log "WARN: patch failed (exit=$_PATCH_EC) — stored raw diff as .proposed"
  fi
  rm -rf "$_APPLY_TMP" 2>/dev/null || true
else
  # No target found — store raw diff as .proposed
  cp "$DRAFT_DIFF" "$PROPOSED_FILE" 2>/dev/null || true
  _log "Wrote .proposed (raw diff, target not found): $PROPOSED_FILE"
fi

# ── Read incident metadata for evidence.md ────────────────────────────────────
# env STAGE_INCIDENT_JSON: JSON string or file path with incident data
INC_TS="unknown"
INC_CLASS="unknown"
INC_DETAIL="unknown"

if [[ -n "${STAGE_INCIDENT_JSON:-}" ]]; then
  _inc_raw=""
  if [[ -f "${STAGE_INCIDENT_JSON}" ]]; then
    _inc_raw="$(cat "${STAGE_INCIDENT_JSON}" 2>/dev/null)"
  else
    _inc_raw="${STAGE_INCIDENT_JSON}"
  fi
  if [[ -n "$_inc_raw" ]]; then
    INC_TS="$(printf '%s' "$_inc_raw" | jq -r '.ts // "unknown"' 2>/dev/null)" || INC_TS="unknown"
    INC_CLASS="$(printf '%s' "$_inc_raw" | jq -r '.payload.class // .class // "unknown"' 2>/dev/null)" || INC_CLASS="unknown"
    INC_DETAIL="$(printf '%s' "$_inc_raw" | jq -r '.payload.detail // .detail // "unknown"' 2>/dev/null)" || INC_DETAIL="unknown"
  fi
fi

# ── Write .evidence.md ─────────────────────────────────────────────────────────
# Purpose: Links the staged artifact back to its incident, eval result, and apply command.
# Contract (spec §Task 5): incident ts/class, eval_run result, drafting model, apply command.
EVIDENCE_FILE="${PROPOSED_FILE}.evidence.md"
STAGED_TS="$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo 'unknown')"
DRAFT_MODEL="${FLYWHEEL_DRAFT_MODEL:-sonnet}"

{
  printf '# Staged Patch Evidence\n\n'
  printf '## Patch ID\n`%s`\n\n' "$PATCH_ID"
  printf '## Triggering Incident\n'
  printf '- **ts**: %s\n' "$INC_TS"
  printf '- **class**: %s\n' "$INC_CLASS"
  printf '- **detail**: %s\n\n' "$INC_DETAIL"
  printf '## Eval Run Result\n'
  printf '- **verdict**: %s\n' "$EVAL_VERDICT"
  printf '- **corpus**: %d fixtures\n' "$EVAL_CORPUS"
  printf '- **passed**: %d\n' "$EVAL_PASSED"
  printf '- **failed**: %d\n' "$EVAL_FAILED"
  printf '- **regressions**: %s\n\n' "$EVAL_REGRESSIONS"
  printf '## Provenance\n'
  printf '- **draft_diff**: %s\n' "$DRAFT_DIFF"
  printf '- **target**: %s\n' "${ACTUAL_TARGET:-<unknown>}"
  printf '- **drafting_model**: %s\n' "$DRAFT_MODEL"
  printf '- **staged_at**: %s\n\n' "$STAGED_TS"
  printf '## One-Click Apply\n'
  printf '```\n'
  printf 'approve: harness eval apply %s\n' "$PATCH_ID"
  printf 'reject:  harness eval reject %s\n' "$PATCH_ID"
  printf '```\n\n'
  printf '> **NEVER auto-applied** — human approval required (staging-only law, Pillar III §Task 5).\n'
} > "$EVIDENCE_FILE" 2>/dev/null || true

_log "Wrote .evidence.md: $EVIDENCE_FILE"

# ── Register staged artifact in state index ────────────────────────────────────
# Purpose: stage-index.ndjson is the registry harness brief reads to list staged patches.
# Each line: {"id":"...", "class":"...", "proposed":"...", "evidence":"...", "verdict":"...", "ts":"..."}
STAGE_INDEX="${_STATE_DIR}/state/flywheel/stage-index.ndjson"
mkdir -p "$(dirname "$STAGE_INDEX")" 2>/dev/null || true

ENTRY="$(jq -cn \
  --arg id "$PATCH_ID" \
  --arg class "$INC_CLASS" \
  --arg detail "$INC_DETAIL" \
  --arg inc_ts "$INC_TS" \
  --arg proposed "$PROPOSED_FILE" \
  --arg evidence "$EVIDENCE_FILE" \
  --arg verdict "$EVAL_VERDICT" \
  --argjson passed "$EVAL_PASSED" \
  --argjson corpus "$EVAL_CORPUS" \
  --argjson regressions "$EVAL_REGRESSIONS" \
  --arg staged_at "$STAGED_TS" \
  '{"id":$id,"class":$class,"detail":$detail,"inc_ts":$inc_ts,
    "proposed":$proposed,"evidence":$evidence,
    "verdict":$verdict,"passed":$passed,"corpus":$corpus,
    "regressions":$regressions,"staged_at":$staged_at}' 2>/dev/null)" || \
  ENTRY="{\"id\":\"$PATCH_ID\",\"class\":\"$INC_CLASS\",\"verdict\":\"$EVAL_VERDICT\",\"staged_at\":\"$STAGED_TS\"}"

# Idempotent: replace existing entry with same id if present
if [[ -f "$STAGE_INDEX" ]] && grep -q "\"id\":\"$PATCH_ID\"" "$STAGE_INDEX" 2>/dev/null; then
  # Rewrite file filtering out the old entry for this id
  TMPIDX="$(mktemp /tmp/stage-idx-XXXXXX.ndjson)"
  grep -v "\"id\":\"$PATCH_ID\"" "$STAGE_INDEX" > "$TMPIDX" 2>/dev/null || true
  printf '%s\n' "$ENTRY" >> "$TMPIDX"
  mv "$TMPIDX" "$STAGE_INDEX" 2>/dev/null || true
else
  printf '%s\n' "$ENTRY" >> "$STAGE_INDEX" 2>/dev/null || true
fi

_log "STAGE-OK: registered $PATCH_ID in stage index"
_log "  proposed : $PROPOSED_FILE"
_log "  evidence : $EVIDENCE_FILE"
_log "  apply    : harness eval apply $PATCH_ID"

exit 0
