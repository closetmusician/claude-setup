#!/usr/bin/env bash
# ABOUTME: SessionStart drop-in: emits a session_start event to the Pillar I telemetry spine.
# ABOUTME: Sourced (not executed) by session-start.sh dispatcher in lexical order (10-*).
# ABOUTME: Purely additive — no exit-code changes, no logic alterations to any existing hook.
# ABOUTME: Fail-open: emit_event is itself fail-open; || true guards any nonzero return.
# ABOUTME: Reads HOOK_STDIN_JSON for session_id/agent_id per emit-event.sh contract.

_EMIT_SH="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib/emit-event.sh"
if [[ -f "$_EMIT_SH" ]]; then
  # shellcheck disable=SC1090
  source "$_EMIT_SH"
  emit_event "session_start" '{"trigger":"SessionStart"}' source="10-emit.sh" || true
fi
unset _EMIT_SH
