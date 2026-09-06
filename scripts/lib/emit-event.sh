#!/usr/bin/env bash
# ABOUTME: Pillar I event emitter — the single source every hook sources to record events.
# ABOUTME: Appends one schema-v1 NDJSON line per call to $STATE/state/events.ndjson.
# ABOUTME: Fully fail-open: any error (missing jq, bad args, lock failure, write failure)
# ABOUTME: returns 0 silently. NEVER writes to stdout or stderr.
# ABOUTME: Usage: source this file, then: emit_event <event_type> <json_payload> [k=v ...]
# FIX ADV2-SPINE (2026-07-06): atomic large-payload guard (REQ-01) + injection-safe jq
#   line build (REQ-02) + single-fork jq-now timestamp for p95 speed improvement (REQ-03).

# ── Closed enum (§2.5) ───────────────────────────────────────────────────────
# All valid event_type values. Unknown type → silently return 0 (fail-open).
_EMIT_VALID_TYPES="session_start session_end tool_call tool_error agent_spawn agent_result skill_fire trust_decision correction incident metric route_decision queue_event eval_run recall_query escalation"

# ── Payload size limit (atomicity guard, REQ-01) ─────────────────────────────
# Purpose: keep every appended line ≤ PIPE_BUF so a single write() is atomic under
#   O_APPEND on APFS/POSIX. Payloads larger than this are replaced with a truncation
#   marker so concurrent writers can never produce torn lines regardless of lock state.
# Gotchas: total line is payload + ~400 bytes of fixed fields; 3072 leaves headroom.
_EMIT_PAYLOAD_MAX=3072

# ── ms-precision timestamp helper (§Q2 chain) ───────────────────────────────
# Purpose: return a RFC3339 UTC timestamp with ms precision via the Q2 fallback chain.
# Usage: ts=$(_emit_ts)
# Gotchas: BSD date lacks %N; never call it for sub-second precision. gdate is primary.
#   Falls back to python3 then to second-precision date — all produce valid RFC3339.
#   NOTE: _emit_ts is retained for the test suite and sourced helpers; the main emit
#   path now uses jq `now` (one subprocess for both ts + line build, per REQ-03).
_emit_ts() {
  # Rung 1: gdate (GNU coreutils, verified present on this host)
  if command -v gdate >/dev/null 2>&1; then
    gdate -u +%Y-%m-%dT%H:%M:%S.%3NZ 2>/dev/null && return
  fi
  # Rung 2: python3 one-shot formatter
  if command -v python3 >/dev/null 2>&1; then
    python3 -c \
      "from datetime import datetime,timezone; print(datetime.now(timezone.utc).strftime('%Y-%m-%dT%H:%M:%S.')+str(datetime.now(timezone.utc).microsecond//1000).zfill(3)+'Z')" \
      2>/dev/null && return
  fi
  # Rung 3: second-precision fallback — still valid RFC3339 (never block)
  date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo "1970-01-01T00:00:00Z"
}

# ── Source-time constant cache ───────────────────────────────────────────────
# Purpose: resolve expensive per-emit constants ONCE at source time. Hooks source this
#   file once per invocation; caching here eliminates repeated git/jq forks.
# Gotchas: STATE env override (used by tests) takes precedence over git resolution.
#   SESSION_ID and AGENT_ID are cached from HOOK_STDIN_JSON if it is already set.

# Resolve state dir once.
# AMENDMENT 2026-07-04 (gate I-5): global durable home is always ~/.claude/state.
# Per-project .agents/claude-governance/ is destroyed on SessionEnd; events must outlive sessions.
# STATE env override (used by tests) still takes precedence.
if [ -n "${STATE:-}" ]; then
  _EMIT_STATE_DIR="$STATE"
else
  _EMIT_STATE_DIR="${HOME}/.claude/state"
fi

# Resolve project once: basename of git toplevel if available, else "~global".
# In STATE-override (test) mode, use "test" so tests don't need real git repos.
if [ -n "${STATE:-}" ]; then
  _EMIT_PROJECT="test"
else
  _EMIT_PROJECT="$(basename "$(git rev-parse --show-toplevel 2>/dev/null)")" 2>/dev/null || true
fi
[ -z "${_EMIT_PROJECT:-}" ] && _EMIT_PROJECT="~global"

# Cache session_id and agent_id from HOOK_STDIN_JSON at source time.
# Per-emit re-parse is skipped unless HOOK_STDIN_JSON changes (tracked by _EMIT_HOOK_CACHE).
_EMIT_SESSION_ID="unknown"
_EMIT_AGENT_ID=""
_EMIT_HOOK_CACHE=""
if [ -n "${HOOK_STDIN_JSON:-}" ] && command -v jq >/dev/null 2>&1; then
  _EMIT_SESSION_ID="$(printf '%s' "$HOOK_STDIN_JSON" | jq -r '.session_id // "unknown"' 2>/dev/null || echo "unknown")"
  _EMIT_AGENT_ID="$(printf '%s' "$HOOK_STDIN_JSON" | jq -r '.agent_id // empty' 2>/dev/null || echo "")"
  _EMIT_HOOK_CACHE="$HOOK_STDIN_JSON"
fi

# ── Main emit function ───────────────────────────────────────────────────────
# Purpose: build one schema-v1 JSON line and append it to events.ndjson under a
#   mkdir-lock with 5s stale-steal TTL. Fail-open on every error path.
# Usage: emit_event <event_type> <json_payload> [key=value ...]
#   event_type   — one of the §2.5 closed enum values
#   json_payload — a JSON object string (may be '{}'); built by caller
#   key=value    — optional overrides: tool=Bash skill=qa outcome=denied
#                  evidence_ref=… trace_id=… source=… agent_id=…
# Gotchas: NEVER outputs to stdout or stderr. The ONLY write is
#   printf '%s\n' "$LINE" >> "$events_file". Returns 0 always.
emit_event() {
  # Wrap entire body so ANY error exits 0 (fail-open, 7 enumerated paths)
  _emit_event_inner "$@" 2>/dev/null
  return 0
}

_emit_event_inner() {
  # Guard 1: jq must be present (line builder uses jq -cn exclusively)
  command -v jq >/dev/null 2>&1 || return 0

  local event_type="${1:-}"
  local json_payload="${2:-{\}}"
  shift 2 2>/dev/null || shift "$#" 2>/dev/null || true

  # Guard 2: event_type must be non-empty and in the closed enum
  [ -z "$event_type" ] && return 0
  local valid=0
  local et
  for et in $_EMIT_VALID_TYPES; do
    [ "$et" = "$event_type" ] && valid=1 && break
  done
  [ "$valid" -eq 0 ] && return 0

  # Guard 3: sampling gate for tool_call (never sample tool_error — errors are the signal)
  # Uses $RANDOM (0-32767) — no subprocess fork needed.
  if [ "$event_type" = "tool_call" ]; then
    local sample_pct="${HARNESS_TOOL_SAMPLE:-0.05}"
    local sample_int
    sample_int=$(awk "BEGIN{printf \"%d\", $sample_pct * 100}" 2>/dev/null || echo "5")
    # threshold: RANDOM < 32768 * rate → equivalent check using integer arithmetic
    local threshold=$(( sample_int * 328 ))   # 32768/100 ≈ 328
    [ "$RANDOM" -ge "$threshold" ] && return 0
  fi

  # Resolve state dir — use cached value; update cache if STATE env changed (test isolation)
  local state_dir
  if [ -n "${STATE:-}" ] && [ "${STATE}" != "${_EMIT_STATE_DIR:-}" ]; then
    state_dir="$STATE"
    # Do NOT update global cache here — subshells in stress tests each have their own copy
  else
    state_dir="${_EMIT_STATE_DIR:-}"
  fi
  [ -z "$state_dir" ] && return 0

  local events_file="$state_dir/state/events.ndjson"
  local lock_dir="$state_dir/state/.events.lock.d"

  # Guard 5: mkdir -p the state dir (fail-open)
  mkdir -p "$state_dir/state" 2>/dev/null || return 0

  # Use cached session_id/agent_id; only re-parse if HOOK_STDIN_JSON changed
  local session_id="$_EMIT_SESSION_ID"
  local agent_id="$_EMIT_AGENT_ID"
  if [ -n "${HOOK_STDIN_JSON:-}" ] && [ "${HOOK_STDIN_JSON}" != "${_EMIT_HOOK_CACHE:-}" ]; then
    # HOOK_STDIN_JSON changed since source time — re-parse once (hook set it after sourcing)
    session_id="$(printf '%s' "$HOOK_STDIN_JSON" | jq -r '.session_id // "unknown"' 2>/dev/null || echo "unknown")"
    agent_id="$(printf '%s' "$HOOK_STDIN_JSON" | jq -r '.agent_id // empty' 2>/dev/null || echo "")"
    # Update module-level cache so subsequent emits in same invocation reuse the parsed values
    _EMIT_SESSION_ID="$session_id"
    _EMIT_AGENT_ID="$agent_id"
    _EMIT_HOOK_CACHE="$HOOK_STDIN_JSON"
  fi

  # Use cached project (or "test" if STATE override changed)
  local project
  if [ -n "${STATE:-}" ] && [ "${STATE}" != "${_EMIT_STATE_DIR:-}" ]; then
    project="test"
  else
    project="$_EMIT_PROJECT"
  fi

  # Parse optional k=v overrides
  local source_val="${BASH_SOURCE[1]##*/}"
  source_val="${source_val:-emit-event.sh}"
  local tool_val="" skill_val="" outcome_val="" evidence_ref_val="" trace_id_val=""
  local override_agent_id=""

  local kv
  for kv in "$@"; do
    case "$kv" in
      tool=*)          tool_val="${kv#tool=}" ;;
      skill=*)         skill_val="${kv#skill=}" ;;
      outcome=*)       outcome_val="${kv#outcome=}" ;;
      evidence_ref=*)  evidence_ref_val="${kv#evidence_ref=}" ;;
      trace_id=*)      trace_id_val="${kv#trace_id=}" ;;
      source=*)        source_val="${kv#source=}" ;;
      agent_id=*)      override_agent_id="${kv#agent_id=}" ;;
    esac
  done

  # Apply agent_id override
  [ -n "$override_agent_id" ] && agent_id="$override_agent_id"

  # ── Payload size guard (REQ-01 atomicity) ───────────────────────────────────
  # Purpose: keep total line ≤ PIPE_BUF so a single O_APPEND write is atomic.
  #   Oversized payloads are replaced with a truncation marker rather than torn.
  # Gotchas: ${#var} is byte-count in bash; UTF-8 sequences count as 1 each
  #   (conservative — actual UTF-8 bytes may be more, but we guard at 3072 chars).
  local payload_used="$json_payload"
  if [ "${#json_payload}" -gt "${_EMIT_PAYLOAD_MAX:-3072}" ]; then
    payload_used='{"_trunc":true,"_reason":"payload exceeded 3072 byte limit"}'
  fi

  # ── Build the JSON line via jq -cn (REQ-02 injection safety + REQ-03 speed) ─
  # Purpose: use jq --arg / --argjson for every field so:
  #   (a) string fields are properly escaped — no injection via caller-supplied values;
  #   (b) payload is validated as well-formed JSON (--argjson rejects invalid JSON,
  #       triggering fail-open return 0 rather than emitting a corrupt line);
  #   (c) `now` produces ms-precision UTC timestamp in one subprocess call,
  #       eliminating the separate gdate fork (REQ-03 latency reduction).
  # Gotchas: `now * 1000 | floor` is ms-precision only to jq's float precision (~µs).
  #   `strftime` on macOS jq 1.6+ handles %Y-%m-%dT%H:%M:%S correctly.
  #   If jq rejects payload_used as invalid JSON, jq exits nonzero → LINE is empty →
  #   the `[ -z "$LINE" ]` guard returns 0 (fail-open — no corrupt line written).
  local LINE
  LINE=$(jq -cn \
    --arg      sid        "$session_id" \
    --arg      etype      "$event_type" \
    --arg      src        "$source_val" \
    --arg      prj        "$project" \
    --argjson  payload    "$payload_used" \
    --arg      agent      "${agent_id:-}" \
    --arg      tool       "${tool_val:-}" \
    --arg      skill      "${skill_val:-}" \
    --arg      outcome    "${outcome_val:-}" \
    --arg      evidence   "${evidence_ref_val:-}" \
    --arg      trace      "${trace_id_val:-}" \
    '{
      ts:           ( now * 1000 | floor
                      | . as $ms
                      | ( ($ms / 1000) | floor | strftime("%Y-%m-%dT%H:%M:%S") )
                        + "."
                        + ( ($ms % 1000) | tostring
                            | if length < 3 then ("000" + .) else . end | .[-3:] )
                        + "Z" ),
      schema:       1,
      session_id:   $sid,
      agent_id:     ( if $agent == "" then null else $agent end ),
      event_type:   $etype,
      source:       $src,
      project:      $prj,
      payload:      $payload,
      tool:         ( if $tool     == "" then null else $tool     end ),
      skill:        ( if $skill    == "" then null else $skill    end ),
      outcome:      ( if $outcome  == "" then null else $outcome  end ),
      evidence_ref: ( if $evidence == "" then null else $evidence end ),
      trace_id:     ( if $trace    == "" then null else $trace    end )
    }' 2>/dev/null)

  [ -z "$LINE" ] && return 0

  # ── Write path: O_APPEND is the primary atomicity guarantee ──────────────────
  # Spec §1 design note: "line ≤ PIPE_BUF (4 KB) is atomic under O_APPEND alone;
  # the lock is belt-and-suspenders, not correctness-critical."
  # The payload size guard above ensures every line is ≤ ~3.5 KB, so a single
  # printf '%s\n' via O_APPEND is atomic on POSIX/APFS without a lock.
  # The mkdir-lock is intentionally REMOVED from the hot path (it cost ~8ms per
  # emit on macOS/APFS — 53% of the p95 budget). It can be re-enabled by setting
  # EMIT_USE_LOCK=1 in environments where O_APPEND atomicity is not guaranteed.
  #
  # Gotchas: never add a subprocess or fork here; this is the critical write path.
  if [ "${EMIT_USE_LOCK:-0}" = "1" ]; then
    # Optional lock path (disabled by default — see above)
    local _lock=0
    if mkdir "$lock_dir" 2>/dev/null; then
      _lock=1
    else
      local lock_mtime now age
      lock_mtime=$(stat -f %m "$lock_dir" 2>/dev/null || echo 0)
      now=$(date +%s)
      age=$(( now - lock_mtime ))
      if [ "$age" -gt 5 ]; then
        rm -rf "$lock_dir" 2>/dev/null && mkdir "$lock_dir" 2>/dev/null && _lock=1 || true
      fi
    fi
    printf '%s\n' "$LINE" >> "$events_file" || true
    [ "$_lock" = "1" ] && rm -rf "$lock_dir" 2>/dev/null || true
  else
    # Fast path: single atomic O_APPEND write (safe for lines ≤ ~4KB per size guard)
    printf '%s\n' "$LINE" >> "$events_file" || true
  fi

  return 0
}
