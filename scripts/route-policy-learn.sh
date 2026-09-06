#!/usr/bin/env bash
# ABOUTME: Pillar IV-A flywheel learner — detects drift between route_decision events
# ABOUTME: and actual agent model usage; writes a .proposed-drift diff to policy/ when
# ABOUTME: ≥3 overrides of the same subtask_class are found.  Fully fail-open (exit 0).
# ABOUTME: Usage: scripts/route-policy-learn.sh [--since <duration>]   (default: 30d)
# ABOUTME: Writes: policy/route-policy.json.proposed-drift  (new/untracked, never applied)

set -uo pipefail
trap 'exit 0' ERR

# ── Constants ────────────────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HARNESS_BIN="${HOME}/.claude/bin/harness"
EVENTS_FILE="${HOME}/.claude/state/state/events.ndjson"
POLICY_FILE="${SCRIPT_DIR}/../policy/route-policy.json"
ROUTE_DISPATCH="${SCRIPT_DIR}/route-dispatch.sh"
PROPOSED_DRIFT="${SCRIPT_DIR}/../policy/route-policy.json.proposed-drift"

SINCE="${1:-}"
# Parse --since flag
if [ "${SINCE}" = "--since" ]; then
  SINCE="${2:-30d}"
elif [ -z "${SINCE}" ]; then
  SINCE="30d"
fi

# ── Dependency check ─────────────────────────────────────────────────────────
command -v jq >/dev/null 2>&1 || { echo "no drift (jq unavailable)"; exit 0; }

# ── Locate events source ─────────────────────────────────────────────────────
# Purpose: prefer harness query (clean deduplication), fall back to events.ndjson.
# Gotchas: harness query returns empty string on no matches (exit 0); that is valid.
#   We use a temp file to avoid subshell complications with large streams.
EVENTS_TMP="$(mktemp -t route_learn_XXXXXX 2>/dev/null)" || { echo "no drift (mktemp failed)"; exit 0; }
trap 'rm -f "${EVENTS_TMP}" 2>/dev/null; exit 0' EXIT ERR

HARNESS_OK=0
if [ -x "${HARNESS_BIN}" ]; then
  "${HARNESS_BIN}" query --type route_decision --since "${SINCE}" 2>/dev/null > "${EVENTS_TMP}" && HARNESS_OK=1 || HARNESS_OK=0
fi

if [ "${HARNESS_OK}" -eq 0 ] || [ ! -s "${EVENTS_TMP}" ]; then
  # Fall back to direct NDJSON read — filter route_decision events by event_type
  if [ -f "${EVENTS_FILE}" ]; then
    jq -c 'select(.event_type == "route_decision")' "${EVENTS_FILE}" 2>/dev/null > "${EVENTS_TMP}" || true
  fi
fi

# ── Count total events found ──────────────────────────────────────────────────
TOTAL_EVENTS=0
if [ -s "${EVENTS_TMP}" ]; then
  TOTAL_EVENTS="$(wc -l < "${EVENTS_TMP}" | tr -d ' ')" 2>/dev/null || TOTAL_EVENTS=0
fi

# ── Detect explicit-override events ──────────────────────────────────────────
# Purpose: find route_decision events where payload.reason == "explicit-override".
#   For each such event, check if the explicit tier differs from what route-dispatch.sh
#   would have said for the same descriptor (recomputed when descriptor is present).
# Gotchas: agent_spawn events may not exist yet; we count route_decision with
#   reason:"explicit-override" as the primary override signal.
OVERRIDES_TMP="$(mktemp -t route_overrides_XXXXXX 2>/dev/null)" || { echo "no drift"; exit 0; }
trap 'rm -f "${EVENTS_TMP}" "${OVERRIDES_TMP}" 2>/dev/null; exit 0' EXIT ERR

if [ -s "${EVENTS_TMP}" ]; then
  # Extract explicit-override events: {subtask_class, explicit_tier, table_tier}
  # For each override: re-run route-dispatch.sh on the descriptor to get table_tier.
  # If dispatch is unavailable, use the default_tier from policy.
  DEFAULT_TIER="sonnet"
  if [ -f "${POLICY_FILE}" ]; then
    DEFAULT_TIER="$(jq -r '.default_tier // "sonnet"' "${POLICY_FILE}" 2>/dev/null || echo "sonnet")"
  fi

  while IFS= read -r line; do
    [ -z "$line" ] && continue
    reason="$(printf '%s' "$line" | jq -r '.payload.reason // ""' 2>/dev/null || true)"
    [ "$reason" != "explicit-override" ] && continue

    sc="$(printf '%s' "$line" | jq -r '.payload.subtask_class // ""' 2>/dev/null || true)"
    explicit_tier="$(printf '%s' "$line" | jq -r '.payload.model_tier // ""' 2>/dev/null || true)"
    [ -z "$sc" ] && continue
    [ -z "$explicit_tier" ] && continue

    # Recompute table tier by running route-dispatch.sh on a minimal descriptor
    table_tier="${DEFAULT_TIER}"
    if [ -x "${ROUTE_DISPATCH}" ]; then
      computed="$(printf '%s' "{\"subtask_class\":\"${sc}\"}" | \
        bash "${ROUTE_DISPATCH}" 2>/dev/null)" || computed=""
      [ -n "$computed" ] && table_tier="$computed"
    fi

    # Only record as drift if explicit tier differs from table tier
    if [ "${explicit_tier}" != "${table_tier}" ]; then
      printf '%s\t%s\t%s\n' "${sc}" "${explicit_tier}" "${table_tier}" >> "${OVERRIDES_TMP}" || true
    fi
  done < "${EVENTS_TMP}"
fi

# ── Tally overrides per subtask_class ────────────────────────────────────────
# Purpose: find classes with ≥3 overrides where explicit_tier != table_tier.
DRIFT_TMP="$(mktemp -t route_drift_XXXXXX 2>/dev/null)" || { echo "no drift"; exit 0; }
trap 'rm -f "${EVENTS_TMP}" "${OVERRIDES_TMP}" "${DRIFT_TMP}" 2>/dev/null; exit 0' EXIT ERR

DRIFT_FOUND=0
if [ -s "${OVERRIDES_TMP}" ]; then
  # Group by subtask_class+explicit_tier, count occurrences
  # Format per line: subtask_class \t explicit_tier \t table_tier
  # Find groups with count ≥ 3
  sort "${OVERRIDES_TMP}" | uniq -c | while read -r count sc_tier_table; do
    # uniq -c emits: <count> <subtask_class>\t<explicit_tier>\t<table_tier>
    count_n="$(printf '%s' "$count" | tr -d ' ')"
    if [ "${count_n}" -ge 3 ] 2>/dev/null; then
      printf '%d\t%s\n' "${count_n}" "${sc_tier_table}" >> "${DRIFT_TMP}" || true
    fi
  done 2>/dev/null || true
fi

if [ -s "${DRIFT_TMP}" ]; then
  DRIFT_FOUND=1
fi

# ── No drift case ─────────────────────────────────────────────────────────────
if [ "${DRIFT_FOUND}" -eq 0 ]; then
  echo "no drift"
  # Remove any stale proposed file
  rm -f "${PROPOSED_DRIFT}" 2>/dev/null || true
  exit 0
fi

# ── Build proposed-drift file ─────────────────────────────────────────────────
# Purpose: write a human-readable .proposed diff with evidence block showing which
#   override events triggered the change.  Never modifies the live policy file.
# Gotchas: the .proposed-drift file is new/untracked — git status must show zero
#   tracked-file modifications from this run.
mkdir -p "$(dirname "${PROPOSED_DRIFT}")" 2>/dev/null || true

{
  printf '# route-policy.json.proposed-drift\n'
  printf '# Generated: %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo "unknown")"
  printf '# Source: route-policy-learn.sh --since %s\n' "${SINCE}"
  printf '# DO NOT APPLY directly — review and promote manually.\n'
  printf '#\n'
  printf '# Evidence block:\n'
  printf '#   Events scanned: %d route_decision events\n' "${TOTAL_EVENTS}"
  printf '#   Drift triggers (subtask_class with ≥3 explicit-override events\n'
  printf '#   where explicit tier ≠ table tier):\n'
  while IFS=$'\t' read -r count rest; do
    printf '#     count=%s  %s\n' "${count}" "${rest}"
  done < "${DRIFT_TMP}" 2>/dev/null || true
  printf '#\n'
  printf '# Proposed rule additions (add to top of rules[] for priority):\n'

  while IFS=$'\t' read -r count row; do
    # row format after uniq: subtask_class \t explicit_tier \t table_tier
    sc="$(printf '%s' "${row}" | cut -f1)"
    etier="$(printf '%s' "${row}" | cut -f2)"
    printf '#\n'
    printf '# subtask_class "%s": used explicitly %d times as "%s" (table says "%s")\n' \
      "${sc}" "${count}" "${etier}" "$(printf '%s' "${row}" | cut -f3)"
    jq -cn \
      --arg sc "${sc}" \
      --arg tier "${etier}" \
      --arg reason "learned-from-${count}-overrides" \
      '{"match":{"subtask_class":$sc},"tier":$tier,"reason":$reason}' \
      2>/dev/null || true
  done < "${DRIFT_TMP}" 2>/dev/null || true

  printf '\n# Full current policy for reference:\n'
  if [ -f "${POLICY_FILE}" ]; then
    cat "${POLICY_FILE}" 2>/dev/null || true
  fi
} > "${PROPOSED_DRIFT}" 2>/dev/null || true

echo "drift detected — wrote ${PROPOSED_DRIFT}"
exit 0
