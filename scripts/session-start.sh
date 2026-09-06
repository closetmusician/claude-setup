#!/usr/bin/env bash
# ABOUTME: SessionStart dispatcher: runs every executable in scripts/session-start.d/ lexically.
# ABOUTME: Each drop-in is sourced with a gtimeout guard (via lib/timeout.sh) and is fail-open.
# ABOUTME: Wired as the SOLE SessionStart hook in settings.json (Q4/I-2.3 binding).
# ABOUTME: Adding new session-start behaviours: drop a numbered .sh into session-start.d/ only.
# ABOUTME: Never exits nonzero — failure of any drop-in must never break the session.

set -uo pipefail
trap 'exit 0' ERR

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DROP_IN_DIR="${SCRIPT_DIR}/session-start.d"

# Source timeout helper for bounded sub-calls (I-1.2 contract).
_TIMEOUT_SH="${SCRIPT_DIR}/lib/timeout.sh"
if [[ -f "$_TIMEOUT_SH" ]]; then
  # shellcheck disable=SC1090
  source "$_TIMEOUT_SH"
fi

# Absorb stdin into HOOK_STDIN_JSON so drop-ins can parse session_id/agent_id.
HOOK_STDIN_JSON=""
if [[ ! -t 0 ]]; then
  HOOK_STDIN_JSON="$(cat 2>/dev/null || true)"
fi
export HOOK_STDIN_JSON

# Run each executable drop-in in lexical order, each fail-open.
if [[ -d "$DROP_IN_DIR" ]]; then
  while IFS= read -r -d '' drop_in; do
    [[ -x "$drop_in" ]] || continue
    # Source each drop-in so it inherits HOOK_STDIN_JSON and the emit helper.
    # Wrap in a subshell so a bad drop-in cannot alter our environment.
    # _run_with_timeout guards against a hung drop-in (5 s limit).
    (
      if declare -f _run_with_timeout >/dev/null 2>&1; then
        # Source the drop-in inside a timeout by running bash -c with source.
        # We pass the file path via bash -c so _run_with_timeout can time it out.
        export _DROPIN_FILE="$drop_in"
        export HOOK_STDIN_JSON
        _run_with_timeout 5 bash -c 'source "$_DROPIN_FILE"' 2>/dev/null || true
      else
        source "$drop_in" 2>/dev/null || true
      fi
    ) || true
  done < <(find "$DROP_IN_DIR" -maxdepth 1 -name '*.sh' -print0 | sort -z)
fi

exit 0
