#!/usr/bin/env bash
# ABOUTME: VI-1 queue-validate — validate a queue task file against the storage schema.
# ABOUTME: Called by `harness queue add` and the night runner before dispatching any task.
# ABOUTME: Returns 0 for valid, 1 for invalid (prints reason to stdout so caller can append it).
# ABOUTME: HARD-REJECT: source:backlog-auto is FORBIDDEN — Yu-Kuan promotes by hand.
# ABOUTME: Usage: bash queue-validate.sh <task-file.md> [--quiet]

set -uo pipefail

# ── Required frontmatter keys (binding per pillar-6-work-economy.md §1.2) ────
_REQUIRED_KEYS=(id repo intent priority acceptance max_minutes model status created source lane)
_VALID_SOURCES=(explicit loop-inbox flywheel flywheel-intake self-improvement)
_VALID_STATUSES=(enqueued approved rejected started staged done invalid needs-user)
_VALID_PRIORITIES=(high normal low)
_VALID_MODELS=(haiku sonnet)
_MAX_MINUTES=45

# ── Argument parsing ──────────────────────────────────────────────────────────
TASK_FILE="${1:-}"
QUIET="${2:-}"

if [[ -z "$TASK_FILE" ]]; then
  echo "queue-validate: usage: queue-validate.sh <task-file.md> [--quiet]" >&2
  exit 1
fi

if [[ ! -f "$TASK_FILE" ]]; then
  echo "INVALID: file not found: $TASK_FILE"
  exit 1
fi

# ── Extract YAML frontmatter block (between first pair of --- lines) ──────────
# Purpose: parse the frontmatter as key: value pairs. Multi-line values (like
#   the acceptance list) are handled by extracting list items separately.
# Gotchas: Only reads the first frontmatter block; ignores the body.
_get_fm_value() {
  # Extract the scalar value for a given frontmatter key.
  # Usage: _get_fm_value "key" < frontmatter
  local key="$1"
  # Match "key: value" lines (not list items); strip leading/trailing whitespace.
  grep -E "^${key}:[[:space:]]" "$FM_FILE" 2>/dev/null \
    | head -1 \
    | sed "s/^${key}:[[:space:]]*//" \
    | sed 's/[[:space:]]*$//' \
    | sed 's/^"//;s/"$//' \
    | sed "s/^'//;s/'$//"
}

_has_acceptance_items() {
  # Check that there is at least one non-empty acceptance list item (lines starting with "  - ").
  grep -E '^[[:space:]]*-[[:space:]]+".+"|^[[:space:]]*-[[:space:]]+[^#[:space:]]' "$FM_FILE" 2>/dev/null \
    | grep -v '^\s*#' \
    | grep -q . 2>/dev/null
}

# Extract frontmatter to a temp file
FM_FILE="$(mktemp /tmp/qv-fm-XXXXXX)"
trap 'rm -f "$FM_FILE"' EXIT

# Read between first and second "---" lines
python3 - "$TASK_FILE" "$FM_FILE" <<'PYEOF' 2>/dev/null || true
import sys
src, dst = sys.argv[1], sys.argv[2]
in_fm = False
lines = []
with open(src, 'r', errors='replace') as f:
    for i, line in enumerate(f):
        stripped = line.rstrip()
        if i == 0 and stripped == '---':
            in_fm = True
            continue
        if in_fm:
            if stripped == '---':
                break
            lines.append(line)
with open(dst, 'w') as f:
    f.writelines(lines)
PYEOF

if [[ ! -s "$FM_FILE" ]]; then
  echo "INVALID: no YAML frontmatter block found (must start with ---)"
  exit 1
fi

# ── Extract key values ────────────────────────────────────────────────────────
ID_VAL="$(_get_fm_value id)"
SOURCE_VAL="$(_get_fm_value source)"
STATUS_VAL="$(_get_fm_value status)"
PRIORITY_VAL="$(_get_fm_value priority)"
MODEL_VAL="$(_get_fm_value model)"
MAX_MIN_VAL="$(_get_fm_value max_minutes)"
INTENT_VAL="$(_get_fm_value intent)"
REPO_VAL="$(_get_fm_value repo)"
CREATED_VAL="$(_get_fm_value created)"

ERRORS=()

# ── HARD-REJECT: source:backlog-auto FORBIDDEN ────────────────────────────────
# Purpose: Enforce the finalized intake decision from apply-master-plan.md §7:
#   backlog P2s are NOT auto-ingested. User promotes by hand.
# Gotchas: This check runs BEFORE all other validation; a backlog-auto task
#   is rejected immediately regardless of other fields.
if [[ "$SOURCE_VAL" == "backlog-auto" ]]; then
  echo "INVALID: source:backlog-auto is FORBIDDEN — backlog items must be promoted by hand (harness queue add)"
  exit 1
fi

# ── Required key presence ─────────────────────────────────────────────────────
# Note: 'acceptance' is a YAML list, not a scalar — check for key presence only,
# then verify items separately below. 'lane' may be null (allowed).
for key in "${_REQUIRED_KEYS[@]}"; do
  # Check that the key exists in the frontmatter at all (key: on its own line)
  if ! grep -qE "^${key}:[[:space:]]*" "$FM_FILE" 2>/dev/null; then
    if [[ "$key" != "lane" ]]; then
      ERRORS+=("missing required key: $key")
    fi
    continue
  fi
  # For scalar keys (not acceptance, not lane), require a non-empty value
  if [[ "$key" != "acceptance" && "$key" != "lane" ]]; then
    val="$(_get_fm_value "$key")"
    if [[ -z "$val" ]]; then
      ERRORS+=("missing value for required key: $key")
    fi
  fi
done

# ── Intent must be non-empty ──────────────────────────────────────────────────
if [[ -z "$INTENT_VAL" ]]; then
  ERRORS+=("intent must be a non-empty imperative sentence")
fi

# ── source must be in valid enum ──────────────────────────────────────────────
if [[ -n "$SOURCE_VAL" ]]; then
  valid_src=0
  for s in "${_VALID_SOURCES[@]}"; do
    [[ "$SOURCE_VAL" == "$s" ]] && valid_src=1 && break
  done
  if [[ "$valid_src" -eq 0 ]]; then
    ERRORS+=("invalid source: '$SOURCE_VAL' (allowed: ${_VALID_SOURCES[*]})")
  fi
fi

# ── acceptance must have at least one mechanical command ─────────────────────
if ! _has_acceptance_items; then
  ERRORS+=("acceptance must contain at least one command item (e.g. - \"bash test.sh exits 0\")")
fi

# ── max_minutes must be a positive integer ≤ 45 ──────────────────────────────
if [[ -n "$MAX_MIN_VAL" ]]; then
  if ! [[ "$MAX_MIN_VAL" =~ ^[0-9]+$ ]]; then
    ERRORS+=("max_minutes must be a positive integer, got: '$MAX_MIN_VAL'")
  elif [[ "$MAX_MIN_VAL" -gt "$_MAX_MINUTES" ]]; then
    ERRORS+=("max_minutes ($MAX_MIN_VAL) exceeds hard cap ($_MAX_MINUTES)")
  elif [[ "$MAX_MIN_VAL" -eq 0 ]]; then
    ERRORS+=("max_minutes must be > 0")
  fi
fi

# ── model must be in valid enum (opus requires user name in body) ─────────────
if [[ -n "$MODEL_VAL" ]]; then
  valid_model=0
  for m in "${_VALID_MODELS[@]}"; do
    [[ "$MODEL_VAL" == "$m" ]] && valid_model=1 && break
  done
  if [[ "$valid_model" -eq 0 && "$MODEL_VAL" != "opus" ]]; then
    ERRORS+=("invalid model: '$MODEL_VAL' (allowed: haiku, sonnet; opus requires user name in body)")
  fi
  # Note: opus allowed but requires user name in body (checked separately by runner at dispatch)
fi

# ── priority must be in valid enum ───────────────────────────────────────────
if [[ -n "$PRIORITY_VAL" ]]; then
  valid_pri=0
  for p in "${_VALID_PRIORITIES[@]}"; do
    [[ "$PRIORITY_VAL" == "$p" ]] && valid_pri=1 && break
  done
  if [[ "$valid_pri" -eq 0 ]]; then
    ERRORS+=("invalid priority: '$PRIORITY_VAL' (allowed: high, normal, low)")
  fi
fi

# ── Emit result ───────────────────────────────────────────────────────────────
if [[ "${#ERRORS[@]}" -gt 0 ]]; then
  for err in "${ERRORS[@]}"; do
    echo "INVALID: $err"
  done
  exit 1
fi

[[ "$QUIET" != "--quiet" ]] && echo "OK: $ID_VAL"
exit 0
