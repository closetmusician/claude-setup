#!/usr/bin/env bash
# ABOUTME: PreToolUse(Bash) hook — denies git push/merge in autonomous context (VII-1).
# ABOUTME: Purpose: Hard mechanical enforcement of staging-only law for night-runner + flywheel.
# ABOUTME: Usage: Wired in settings.json PreToolUse(Bash); reads JSON payload from stdin.
# ABOUTME: Gotchas: exits 0 only when neither AUTONOMOUS_RUN nor registry identity marks autonomy.
# ABOUTME: Denies non-closetmusician push targets and all autonomous merges.

# Fail-open on own errors: no -e; trap any ERR/unexpected exit to exit 0.
# The DENY paths are explicit — only they output block JSON.
set -uo pipefail
trap 'exit 0' ERR

# Require jq — fail-open if missing.
command -v jq >/dev/null 2>&1 || exit 0

# ── Parse payload before identity resolution ─────────────────────────────────
INPUT=$(cat)
COMMAND=$(printf '%s' "${INPUT}" | jq -r '.tool_input.command // ""' 2>/dev/null || true)

# ── PLANE SEPARATOR ──────────────────────────────────────────────────────────
# AUTONOMOUS_RUN=1 is sufficient to enter enforcement. If that env was stripped,
# a registered stdin session_id also enters enforcement.
STATE="${HARNESS_STATE_OVERRIDE:-${STATE:-$HOME/.claude/state}}"
_GUARD_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=lib/autonomous-registry.sh
if [[ -f "${_GUARD_DIR}/lib/autonomous-registry.sh" ]]; then
  # shellcheck disable=SC1091
  source "${_GUARD_DIR}/lib/autonomous-registry.sh"
  autonomous_registry_should_enforce "${INPUT}" 2>/dev/null || exit 0
else
  # Library missing: AUTONOMOUS_RUN still enters enforcement; otherwise raw registry fallback.
  if [[ "${AUTONOMOUS_RUN:-}" != "1" ]]; then
    _sid="$(printf '%s' "$INPUT" | jq -r '.session_id // ""' 2>/dev/null || true)"
    [[ -n "$_sid" ]] || _sid="${SESSION_ID:-}"
    jq -e --arg sid "$_sid" \
    'any(.[]; (.lane_id == $sid or .session_id == $sid) and .status == "active")' \
    "${STATE}/autonomous-registry.json" >/dev/null 2>&1 || exit 0
  fi
fi
[[ -z "${COMMAND}" ]] && exit 0

# ── deny_and_exit <reason> <class> ────────────────────────────────────────────
# Purpose: Emit P0 incident event, then output the deny JSON contract.
# Usage: deny_and_exit "Human-readable reason" "incident-class-slug"
# Gotchas: Sources emit-event.sh fail-open. Always exits 0 (hookSpecificOutput via stdout).
deny_and_exit() {
  local reason="${1:-autonomous plane: operation denied}"
  local class="${2:-autonomous-push-guard-deny}"

  # Emit Pillar I incident — purely additive, fail-open.
  if [[ -f "${_GUARD_DIR}/lib/emit-event.sh" ]]; then
    # shellcheck disable=SC1091
    source "${_GUARD_DIR}/lib/emit-event.sh" 2>/dev/null || true
    # Build payload via jq --arg so reason/class are properly escaped (latent: raw
    # interpolation breaks emit's jq --argjson validation if values contain quotes)
    local _apg_payload
    _apg_payload=$(jq -cn --arg cls "$class" --arg det "$reason" \
      '{"severity":"P0","class":$cls,"detail":$det}' 2>/dev/null) || \
      _apg_payload="{\"severity\":\"P0\",\"class\":\"${class}\",\"detail\":\"autonomous-push-guard-deny\"}"
    emit_event "incident" "$_apg_payload" \
      outcome=denied source="autonomous-push-guard.sh" 2>/dev/null || true
  fi

  # Output the Claude Code deny contract (mirrors git-safety-hook.sh format).
  jq -n --arg reason "${reason}" \
    '{
      "hookSpecificOutput": {
        "hookEventName": "PreToolUse",
        "permissionDecision": "deny",
        "permissionDecisionReason": $reason
      }
    }' 2>/dev/null || \
    printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"%s"}}\n' \
      "${reason}"
  exit 0
}

# ── Remote-classification helpers ─────────────────────────────────────────────
# Returns 0 only for the explicit solo GitHub owner.
_is_solo_remote_url() {
  local url="${1:-}"
  printf '%s' "$url" | grep -qiE '(^|[:/])github\.com[:/]closetmusician/' && return 0
  printf '%s' "$url" | grep -qiE '^git@github\.com:closetmusician/' && return 0
  return 1
}

_push_targets_are_solo() {
  local remote="${1:-origin}"
  local repo_root
  repo_root="$(git rev-parse --show-toplevel 2>/dev/null || true)"
  [[ -z "${repo_root}" ]] && return 1

  local urls=""
  if [[ -n "$remote" && "$remote" != -* ]]; then
    urls="$(git -C "$repo_root" remote get-url --push --all "$remote" 2>/dev/null || true)"
  fi
  [[ -n "$urls" ]] || urls="$(git -C "$repo_root" remote -v 2>/dev/null | awk '$3 == "(push)" {print $2}' 2>/dev/null || true)"
  [[ -n "$urls" ]] || return 1

  local url
  while IFS= read -r url; do
    [[ -z "$url" ]] && continue
    _is_solo_remote_url "$url" || return 1
  done <<< "$urls"
  return 0
}

_push_remote_from_command() {
  local stripped_command="${1:-}"
  printf '%s\n' "$stripped_command" | awk '
    {
      for (i = 1; i <= NF; i++) {
        if ($i == "push") {
          j = i + 1
          while (j <= NF && $j ~ /^-/) j++
          if (j <= NF) print $j
          exit
        }
      }
    }'
}

_repo_has_only_solo_remotes() {
  local repo_root
  repo_root="$(git rev-parse --show-toplevel 2>/dev/null || true)"
  [[ -z "${repo_root}" ]] && return 1

  local urls
  urls="$(git -C "$repo_root" remote -v 2>/dev/null | awk '$3 == "(push)" {print $2}' 2>/dev/null || true)"
  [[ -n "$urls" ]] || return 1
  local url
  while IFS= read -r url; do
    [[ -z "$url" ]] && continue
    _is_solo_remote_url "$url" || return 1
  done <<< "$urls"
  return 0
}

# ── Push/merge enforcement ────────────────────────────────────────────────────

# Strip heredoc bodies and quoted strings for pattern matching (mirrors git-safety-hook.sh).
STRIPPED=$(printf '%s' "${COMMAND}" | \
  perl -0777 -pe "s/<<'?EOF'?.*?^EOF\$/__HEREDOC__/gms" 2>/dev/null | \
  sed "s/\"[^\"]*\"/__STR__/g; s/'[^']*'/__STR__/g" 2>/dev/null || \
  printf '%s' "${COMMAND}")

# Detect git push or git merge.
if printf '%s' "${STRIPPED}" | grep -qE '^\s*git\s+(push|merge)\b'; then

  # git merge is hard-denied in all autonomous contexts (branches only).
  if printf '%s' "${STRIPPED}" | grep -qE '^\s*git\s+merge\b'; then
    deny_and_exit \
      "AUTONOMOUS PLANE: git merge is hard-denied. Autonomous runs must commit to branches only — leave merges for morning review." \
      "autonomous-merge-denied"
  fi

  # git push: allow only explicit closetmusician push targets. Unknown target
  # or any non-solo remote is denied in the autonomous plane.
  PUSH_REMOTE="$(_push_remote_from_command "$STRIPPED")"
  if printf '%s' "$PUSH_REMOTE" | grep -qiE '^(https?|ssh|git)://|^git@'; then
    _is_solo_remote_url "$PUSH_REMOTE" || deny_and_exit \
      "AUTONOMOUS PLANE: git push to a shared/corporate remote is hard-denied. Stage output as a branch and leave it for morning review." \
      "autonomous-push-shared"
  elif [[ -n "$PUSH_REMOTE" ]]; then
    _push_targets_are_solo "$PUSH_REMOTE" || deny_and_exit \
      "AUTONOMOUS PLANE: git push to a shared/corporate remote is hard-denied. Stage output as a branch and leave it for morning review." \
      "autonomous-push-shared"
  elif ! _repo_has_only_solo_remotes; then
    deny_and_exit \
      "AUTONOMOUS PLANE: git push to a shared/corporate remote is hard-denied. Stage output as a branch and leave it for morning review." \
      "autonomous-push-shared"
  fi
fi

exit 0
