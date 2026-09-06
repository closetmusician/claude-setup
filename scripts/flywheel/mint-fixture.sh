#!/usr/bin/env bash
# ABOUTME: Pillar III-1 eval fixture minter. Reads an incident JSON (file or /dev/fd) and
# ABOUTME: creates ~/.claude/evals/incidents/<class>-<nnn>/ with fixture.jsonl, input.json,
# ABOUTME: and expect.json. Idempotent: same session_id+class skips. Synthesized fixtures
# ABOUTME: are minted when the source transcript is purged (payload.purged_transcript==true).
# ABOUTME: BSD/macOS compatible. Fail-open on individual bad inputs. Exit 0 always.

set -uo pipefail
trap 'exit 0' ERR

CLAUDE_DIR="${CLAUDE_DIR:-$HOME/.claude}"
EVALS_DIR="${EVALS_DIR:-${CLAUDE_DIR}/evals/incidents}"

# Gap classes: these have no guard yet; expect.json gets expected_gap:true.
# Per spec §Task1: C7 and U3 are known-uncovered.
GAP_CLASSES="C7 U3"

# ── helpers ──────────────────────────────────────────────────────────────────

# Purpose: emit ms-precision UTC timestamp.
# Usage: ts=$(_mint_ts)
# Gotchas: BSD date has no %N; use gdate → python3 → second-precision chain (Q2).
_mint_ts() {
  if command -v gdate >/dev/null 2>&1; then
    gdate -u +%Y-%m-%dT%H:%M:%S.%3NZ 2>/dev/null && return
  fi
  if command -v python3 >/dev/null 2>&1; then
    python3 -c \
      "from datetime import datetime,timezone; \
       now=datetime.now(timezone.utc); \
       print(now.strftime('%Y-%m-%dT%H:%M:%S.')+str(now.microsecond//1000).zfill(3)+'Z')" \
      2>/dev/null && return
  fi
  date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo "1970-01-01T00:00:00Z"
}

# Purpose: check if a class is in the known-gap set (no guard exists yet).
# Usage: _is_gap_class <class>  → returns 0 (true) or 1 (false)
# Gotchas: must match exactly (C7 ≠ C7a).
_is_gap_class() {
  local class="$1"
  local g
  for g in $GAP_CLASSES; do
    [[ "$g" == "$class" ]] && return 0
  done
  return 1
}

# Purpose: derive the next available monotonic 3-digit sequence number for a class.
# Usage: _next_seq <class>
# Gotchas: reads existing dirs under EVALS_DIR; zero-pads to 3 digits.
_next_seq() {
  local class="$1"
  local max=0
  local d n
  while IFS= read -r d; do
    [[ -z "$d" ]] && continue
    n="${d##*-}"
    # strip leading zeros for arithmetic
    n=$(( 10#$n )) 2>/dev/null || continue
    [[ $n -gt $max ]] && max=$n
  done < <(find "$EVALS_DIR" -maxdepth 1 -type d -name "${class}-*" 2>/dev/null | sed "s|.*/||")
  printf '%03d' $(( max + 1 ))
}

# Purpose: check if this session_id+class combo has already been minted (idempotency).
# Usage: _already_minted <class> <session_id>  → 0 if minted, 1 if not
# Gotchas: searches expect.json files in all class-prefixed dirs for the session_id.
_already_minted() {
  local class="$1"
  local session_id="$2"
  local d
  while IFS= read -r d; do
    [[ -z "$d" ]] && continue
    if grep -qF "$session_id" "$d/fixture.jsonl" 2>/dev/null; then
      return 0
    fi
  done < <(find "$EVALS_DIR" -maxdepth 1 -type d -name "${class}-*" 2>/dev/null)
  return 1
}

# ── per-incident mint ─────────────────────────────────────────────────────────

# Purpose: mint a single eval fixture dir from an incident JSON object.
# Usage: _mint_one <incident_json_string>
# Gotchas: returns 0 always (fail-open). Skips if already minted (idempotency check).
_mint_one() {
  local incident="$1"

  # Validate it's parseable JSON with required fields
  if ! echo "$incident" | jq -e '.event_type' >/dev/null 2>&1; then
    echo "[mint-fixture] SKIP: not valid JSON" >&2
    return 0
  fi

  # Extract key fields
  local class session_id purged ts
  class="$(echo "$incident" | jq -r '.payload.class // empty' 2>/dev/null)"
  session_id="$(echo "$incident" | jq -r '.session_id // empty' 2>/dev/null)"
  purged="$(echo "$incident" | jq -r '.payload.purged_transcript // false' 2>/dev/null)"
  ts="$(echo "$incident" | jq -r '.ts // empty' 2>/dev/null)"

  # Require class and session_id
  if [[ -z "$class" || -z "$session_id" ]]; then
    echo "[mint-fixture] SKIP: missing class or session_id" >&2
    return 0
  fi

  # Sanitize class: strip non-alphanumeric except hyphens
  class="$(echo "$class" | tr -cd 'A-Za-z0-9-')"
  [[ -z "$class" ]] && { echo "[mint-fixture] SKIP: empty class after sanitize" >&2; return 0; }

  # Idempotency check
  if _already_minted "$class" "$session_id"; then
    echo "[mint-fixture] SKIP: already minted class=$class session_id=$session_id" >&2
    return 0
  fi

  # Ensure evals dir exists
  mkdir -p "$EVALS_DIR" 2>/dev/null || true

  # Allocate next sequence number and create the fixture dir
  local seq fix_dir
  seq="$(_next_seq "$class")"
  fix_dir="${EVALS_DIR}/${class}-${seq}"

  # Guard against race: if dir already exists (concurrent run), skip
  if ! mkdir "$fix_dir" 2>/dev/null; then
    echo "[mint-fixture] SKIP: dir $fix_dir already exists (concurrent mint?)" >&2
    return 0
  fi

  local now_ts
  now_ts="$(_mint_ts)"

  # Determine if this is a synthesized fixture (transcript purged)
  local is_synthesized=false
  [[ "$purged" == "true" || "$purged" == "1" ]] && is_synthesized=true

  # ── fixture.jsonl ────────────────────────────────────────────────────────
  # Reproduces the incident event as the hook/transcript slice.
  # When synthesized, adds synthesized:true marker and a synthetic context entry.
  if [[ "$is_synthesized" == "true" ]]; then
    # Synthetic: derive context from incident payload.detail
    local detail
    detail="$(echo "$incident" | jq -r '.payload.detail // "no detail available"' 2>/dev/null)"
    jq -cn \
      --arg ts "$now_ts" \
      --arg session_id "$session_id" \
      --arg class "$class" \
      --arg detail "$detail" \
      '{
        type: "synthetic_context",
        ts: $ts,
        session_id: $session_id,
        class: $class,
        synthesized: true,
        note: "Transcript purged — synthesized from incident payload.detail",
        detail: $detail
      }' >> "$fix_dir/fixture.jsonl" 2>/dev/null || true
    jq -cn \
      --arg ts "$now_ts" \
      --arg session_id "$session_id" \
      --arg class "$class" \
      '{
        type: "incident_replay",
        ts: $ts,
        session_id: $session_id,
        class: $class,
        synthesized: true
      }' >> "$fix_dir/fixture.jsonl" 2>/dev/null || true
  else
    # Real: use the incident event itself as the transcript slice
    echo "$incident" >> "$fix_dir/fixture.jsonl" 2>/dev/null || true
  fi

  # ── input.json ──────────────────────────────────────────────────────────
  # The hook stdin payload (scenario input). transcript_path is rewritten by runner.
  jq -cn \
    --arg session_id "$session_id" \
    --arg class "$class" \
    --arg ts "${ts:-$now_ts}" \
    --arg fix_dir "$fix_dir" \
    '{
      session_id: $session_id,
      class: $class,
      incident_ts: $ts,
      transcript_path: "\($fix_dir)/fixture.jsonl",
      hook_event_name: "PostToolUse",
      tool_name: "Bash"
    }' > "$fix_dir/input.json" 2>/dev/null || true

  # ── expect.json ─────────────────────────────────────────────────────────
  # Expected guard decision. expected_gap:true for uncovered classes (C7, U3).
  local expected_gap=false
  _is_gap_class "$class" && expected_gap=true

  # Default decision: block for incident classes; gap classes report KNOWN-GAP not FAIL
  local decision="block"
  [[ "$expected_gap" == "true" ]] && decision="known-gap"

  jq -cn \
    --arg class "$class" \
    --arg decision "$decision" \
    --argjson expected_gap "$expected_gap" \
    '{
      hook: "completion-claim-guard.sh",
      class: $class,
      expect: $decision,
      reason_contains: $class,
      expected_gap: $expected_gap
    }' > "$fix_dir/expect.json" 2>/dev/null || true

  echo "[mint-fixture] MINTED: $fix_dir (class=$class session_id=$session_id synthesized=$is_synthesized gap=$expected_gap)" >&2
  echo "$fix_dir"
  return 0
}

# ── main ─────────────────────────────────────────────────────────────────────

# Purpose: main entry. Reads incident JSON from first arg (file path or process subst).
# Usage: mint-fixture.sh <incident_file_or_path>
# Gotchas: if no arg given, reads from stdin. Fail-open: bad inputs are skipped.

main() {
  # Require jq
  if ! command -v jq >/dev/null 2>&1; then
    echo "[mint-fixture] ERROR: jq is required but not found" >&2
    exit 0
  fi

  local input_file="${1:--}"  # default to stdin

  # Read all input: may be one JSON object or multiple lines
  local content
  if ! content="$(cat "$input_file" 2>/dev/null)"; then
    echo "[mint-fixture] SKIP: cannot read input from $input_file" >&2
    exit 0
  fi

  if [[ -z "$(echo "$content" | tr -d '[:space:]')" ]]; then
    echo "[mint-fixture] SKIP: empty input" >&2
    exit 0
  fi

  # Try to parse as: (a) single JSON object, (b) NDJSON (one object per line)
  local minted=0

  # Strategy: try each non-empty line as a separate JSON object first (NDJSON).
  # If the whole content is one object, this still works (one line after trim).
  # Fail-open: lines that aren't valid JSON are skipped.
  while IFS= read -r line; do
    [[ -z "$(echo "$line" | tr -d '[:space:]')" ]] && continue
    # Validate JSON before attempting mint
    if echo "$line" | jq -e . >/dev/null 2>&1; then
      result="$(_mint_one "$line")"
      [[ -n "$result" ]] && minted=$(( minted + 1 ))
    else
      echo "[mint-fixture] SKIP: line is not valid JSON" >&2
    fi
  done <<< "$content"

  echo "[mint-fixture] Done. Minted $minted fixture(s)." >&2
  exit 0
}

main "$@"
