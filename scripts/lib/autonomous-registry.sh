#!/usr/bin/env bash
# ABOUTME: Pillar VII autonomous-lane registry — sourced library for night-runner + push-guard.
# ABOUTME: Backed by $STATE/autonomous-registry.json; records every sanctioned autonomous lane.
# ABOUTME: Fail-safe: any read error (missing file, corrupt JSON) → treat as NOT registered.
# ABOUTME: BSD-safe (no GNU-isms); all jq calls use --arg; never sets global shell opts.
# ABOUTME: Usage: source this file, then call autonomous_registry_* functions directly.

# ── Internal path helper ──────────────────────────────────────────────────────
# Purpose: Resolve the registry JSON path from $STATE, defaulting to ~/.claude/state.
# Usage: _ar_path
# Gotchas: Never errors; always returns a path string (directory may not yet exist).
_ar_path() {
  local state_dir="${STATE:-$HOME/.claude/state}"
  printf '%s/autonomous-registry.json' "${state_dir}"
}

# ── autonomous_registry_session_from_input ───────────────────────────────────
# Purpose: Resolve the Claude Code hook identity from stdin JSON, falling back to
#   the legacy SESSION_ID env only when stdin lacks session_id.
# Usage: sid="$(autonomous_registry_session_from_input "$INPUT")"
autonomous_registry_session_from_input() {
  local input="${1:-}"
  local sid=""
  if command -v jq >/dev/null 2>&1 && [[ -n "$input" ]]; then
    sid="$(printf '%s' "$input" | jq -r '.session_id // ""' 2>/dev/null || true)"
  fi
  [[ -n "$sid" ]] || sid="${SESSION_ID:-}"
  printf '%s' "$sid"
}

# ── autonomous_registry_should_enforce ───────────────────────────────────────
# Purpose: Decide whether an autonomous guard should enter enforcement.
# Usage: autonomous_registry_should_enforce "$INPUT"
# Gotchas: AUTONOMOUS_RUN=1 is sufficient to enforce. Registry membership also
#   enters enforcement for hooks invoked with stripped env. Interactive sessions
#   with neither signal remain untouched.
autonomous_registry_should_enforce() {
  local input="${1:-}"
  if [[ "${AUTONOMOUS_RUN:-}" == "1" ]]; then
    return 0
  fi

  local sid
  sid="$(autonomous_registry_session_from_input "$input")"
  [[ -n "$sid" ]] || return 1
  autonomous_registry_is_registered "$sid"
}

# ── autonomous_registry_register ─────────────────────────────────────────────
# Purpose: Add a new active entry for lane_id + task_id to the registry JSON.
# Usage: autonomous_registry_register <lane_id> <task_id> [json_metadata]
#   json_metadata: optional valid JSON object string (e.g. '{"session_id":"abc"}')
# Gotchas: Overwrites any existing entry for lane_id (idempotent re-register).
#   Returns a registration token (lane_id:ts) on stdout for callers that want it.
autonomous_registry_register() {
  local lane_id="${1:-}"
  local task_id="${2:-}"
  local meta="${3:-}"
  [[ -z "${meta}" ]] && meta='{}'

  if [[ -z "${lane_id}" || -z "${task_id}" ]]; then
    return 1
  fi

  local registry
  registry="$(_ar_path)"
  local dir
  dir="$(dirname "${registry}")"

  # Ensure state directory exists
  mkdir -p "${dir}" 2>/dev/null || true

  local ts
  ts="$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo "1970-01-01T00:00:00Z")"
  local token="${lane_id}:${ts}"

  # Validate meta is parseable JSON; fall back to empty object on failure
  if ! printf '%s' "${meta}" | jq . >/dev/null 2>&1; then
    meta='{}'
  fi

  # Parse session_id from metadata if present
  local session_id=""
  session_id="$(printf '%s' "${meta}" | jq -r '.session_id // ""' 2>/dev/null || true)"

  # Build the new entry JSON
  local new_entry
  new_entry="$(jq -n \
    --arg lane_id "${lane_id}" \
    --arg task_id "${task_id}" \
    --arg session_id "${session_id}" \
    --arg ts "${ts}" \
    --arg token "${token}" \
    --argjson meta "${meta}" \
    '{lane_id: $lane_id, task_id: $task_id, session_id: $session_id,
      started_at: $ts, status: "active", token: $token, meta: $meta}' \
    2>/dev/null)"

  if [[ -z "${new_entry}" ]]; then
    # jq build failed — skip write, still return token
    printf '%s\n' "${token}"
    return 0
  fi

  # Load existing registry or start fresh; strip prior entry for this lane_id
  local existing="[]"
  if [[ -f "${registry}" ]]; then
    existing="$(jq --arg lid "${lane_id}" \
      '[.[] | select(.lane_id != $lid)]' \
      "${registry}" 2>/dev/null)"
    if [[ -z "${existing}" ]]; then
      existing="[]"
    fi
  fi

  # Append and write atomically
  local tmp="${registry}.tmp.$$"
  local merged
  merged="$(printf '%s' "${existing}" | \
    jq --argjson entry "${new_entry}" '. + [$entry]' 2>/dev/null)" || return 1
  if [[ -n "${merged}" ]]; then
    printf '%s\n' "${merged}" > "${tmp}" 2>/dev/null \
      && mv "${tmp}" "${registry}" 2>/dev/null \
      || { rm -f "${tmp}" 2>/dev/null || true; return 1; }
  else
    return 1
  fi

  printf '%s\n' "${token}"
}

# ── autonomous_registry_is_registered ────────────────────────────────────────
# Purpose: Check whether a lane_id (or session_id) has an active entry in the registry.
# Usage: autonomous_registry_is_registered <lane_id_or_session_id>
#   Returns exit 0 if an active entry is found, nonzero otherwise.
# Gotchas: Any read error, missing file, or corrupt JSON → returns nonzero (fail-safe,
#   errs toward denying autonomous privilege per CON-13 spec §0).
autonomous_registry_is_registered() {
  local id="${1:-}"
  [[ -z "${id}" ]] && return 1

  command -v jq >/dev/null 2>&1 || return 1

  local registry
  registry="$(_ar_path)"
  [[ -f "${registry}" ]] || return 1

  # Fail-safe: any jq parse error → return 1 (not registered)
  local result
  result="$(jq -e --arg id "${id}" \
    'any(.[]; (.lane_id == $id or .session_id == $id) and .status == "active")' \
    "${registry}" 2>/dev/null)" || return 1

  [[ "${result}" == "true" ]]
}

# ── autonomous_registry_deregister ───────────────────────────────────────────
# Purpose: Mark a lane's entry as done (removes from active pool).
# Usage: autonomous_registry_deregister <lane_id>
# Gotchas: Fails silently if lane_id not found or registry unreadable — safe to call always.
autonomous_registry_deregister() {
  local lane_id="${1:-}"
  [[ -z "${lane_id}" ]] && return 0

  command -v jq >/dev/null 2>&1 || return 0

  local registry
  registry="$(_ar_path)"
  [[ -f "${registry}" ]] || return 0

  local updated
  updated="$(jq --arg lid "${lane_id}" \
    'map(if .lane_id == $lid then .status = "done" else . end)' \
    "${registry}" 2>/dev/null)"

  if [[ -n "${updated}" ]]; then
    local tmp="${registry}.tmp.$$"
    printf '%s\n' "${updated}" > "${tmp}" 2>/dev/null \
      && mv "${tmp}" "${registry}" 2>/dev/null \
      || rm -f "${tmp}" 2>/dev/null || true
  fi
  return 0
}

# ── autonomous_registry_reset ─────────────────────────────────────────────────
# Purpose: Clear all entries from the registry (call at start of each new night run).
# Usage: autonomous_registry_reset
# Gotchas: Overwrites the registry with an empty array. Safe even if file absent.
autonomous_registry_reset() {
  local registry
  registry="$(_ar_path)"
  local dir
  dir="$(dirname "${registry}")"
  mkdir -p "${dir}" 2>/dev/null || true
  printf '[]\n' > "${registry}" 2>/dev/null || true
  return 0
}
