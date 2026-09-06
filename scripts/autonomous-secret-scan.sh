#!/usr/bin/env bash
# ABOUTME: PostToolUse(Write/Edit) guard — scans files written in autonomous runs for secrets.
# ABOUTME: Catches secrets at generation time (before staging) to complement pre-commit backstop.
# ABOUTME: SCOPE INVARIANT: acts when AUTONOMOUS_RUN=1 or stdin session_id is registered.
# ABOUTME: On HIT: deletes file, writes tombstone (masked), emits P0 incident, trips kill-switch.
# ABOUTME: Fail-open on scanner errors — a scanner bug must never delete files or block the hook.

# Fail-open on any unexpected error: trap catches anything set -uo pipefail would raise.
# -e is intentionally NOT set; we use explicit || logic so the || branches run cleanly.
set -uo pipefail
trap 'exit 0' ERR

# ── Guard: jq required for JSON parsing ──────────────────────────────────────
command -v jq >/dev/null 2>&1 || exit 0

# ── Read hook stdin (PostToolUse JSON) ────────────────────────────────────────
INPUT=$(cat 2>/dev/null) || exit 0
[[ -z "$INPUT" ]] && exit 0

# ── SCOPE INVARIANT ───────────────────────────────────────────────────────────
# AUTONOMOUS_RUN=1 is sufficient to scan. If env was stripped, a registered
# stdin session_id also enters enforcement. Interactive sessions stay untouched.
STATE="${STATE:-$HOME/.claude/state}"
_GUARD_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -f "${_GUARD_DIR}/lib/autonomous-registry.sh" ]]; then
  # shellcheck disable=SC1091
  source "${_GUARD_DIR}/lib/autonomous-registry.sh"
  autonomous_registry_should_enforce "$INPUT" 2>/dev/null || exit 0
else
  if [[ "${AUTONOMOUS_RUN:-}" != "1" ]]; then
    _sid="$(printf '%s' "$INPUT" | jq -r '.session_id // ""' 2>/dev/null || true)"
    [[ -n "$_sid" ]] || _sid="${SESSION_ID:-}"
    jq -e --arg sid "$_sid" \
      'any(.[]; (.lane_id == $sid or .session_id == $sid) and .status == "active")' \
      "${STATE}/autonomous-registry.json" >/dev/null 2>&1 || exit 0
  fi
fi

FILE_PATH=$(printf '%s' "$INPUT" | jq -r '.tool_input.file_path // .tool_input.path // ""' 2>/dev/null) || exit 0
[[ -z "$FILE_PATH" || ! -f "$FILE_PATH" ]] && exit 0

# ── Locate the secret scanner ─────────────────────────────────────────────────
SECRET_SCAN="${HOME}/.claude/scripts/secret-scan.sh"
[[ -x "$SECRET_SCAN" ]] || exit 0

# ── Run secret-scan on the written file (fail-open on scanner error) ──────────
# secret-scan.sh exits 0 = clean, exits 1 = secrets found.
# We capture output for tombstone metadata (masked match only — never raw secret).
# CRITICAL: we only act on a DEFINITE exit 1 from secret-scan.sh.
# Any other error (scanner crash, permission denied, etc.) must NOT delete the file.
_scan_output=""
_scan_exit=0
_scan_output=$("$SECRET_SCAN" "$FILE_PATH" 2>&1) || _scan_exit=$?

# _scan_exit=0 means clean — silent pass
[[ "$_scan_exit" -eq 0 ]] && exit 0

# _scan_exit=1 means secrets detected — act on this definite hit only.
# Any other exit code (e.g. 2, 127) is treated as scanner error → fail-open.
if [[ "$_scan_exit" -ne 1 ]]; then
  exit 0
fi

# ── SECRET HIT — take action ──────────────────────────────────────────────────
_ts=$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo "unknown")

# 1. Emit P0 incident event (fail-open — emitter may not be wired yet in parallel build)
_EMIT_SH="$(dirname "${BASH_SOURCE[0]}")/lib/emit-event.sh"
if [[ -f "$_EMIT_SH" ]]; then
  # shellcheck disable=SC1090
  source "$_EMIT_SH" 2>/dev/null || true
  emit_event "incident" \
    "{\"severity\":\"P0\",\"class\":\"autonomous-secret-detected\",\"detail\":\"Secret found in autonomous write to $(basename "$FILE_PATH")\"}" \
    outcome=denied 2>/dev/null || true
fi

# 2. Trip kill-switch (fail-open — VII-4 may be parallel; fallback to direct sentinel write)
_KS_SH="$(dirname "${BASH_SOURCE[0]}")/lib/kill-switch.sh"
if [[ -f "$_KS_SH" ]]; then
  # shellcheck disable=SC1090
  source "$_KS_SH" 2>/dev/null || true
  kill_switch_trip "auto" "Secret detected in autonomous write: $(basename "$FILE_PATH")" 2>/dev/null || true
else
  # Fallback: write sentinel directly (kill-switch.sh absent — VII-4 parallel dependency)
  _freeze_sentinel="${STATE}/.AUTONOMOUS_FREEZE"
  printf '[%s] trigger=auto reason=Secret detected in autonomous write: %s\n' \
    "$_ts" "$(basename "$FILE_PATH")" > "$_freeze_sentinel" 2>/dev/null || true
fi

# 3. Delete the offending file
rm -f "$FILE_PATH" 2>/dev/null || true

# 4. Write tombstone with metadata — NEVER the raw secret; masked match only
_tombstone="${FILE_PATH}.DELETED-SECRET-SCAN"
{
  printf '# SECRET-SCAN INCIDENT: file deleted by autonomous-secret-scan.sh\n'
  printf 'timestamp: %s\n' "$_ts"
  printf 'deleted_path: %s\n' "$FILE_PATH"
  # Extract a masked prefix of the matched pattern (first 12 chars of first match, then "...")
  _masked=$(printf '%s' "$_scan_output" | grep -oE '[^ ]+$' | head -1 | cut -c1-12)
  printf 'matched_pattern_prefix: %s...\n' "${_masked:-[unknown]}"
  printf 'action: file_deleted\n'
  printf 'kill_switch: tripped\n'
} > "$_tombstone" 2>/dev/null || true

exit 0
