#!/usr/bin/env bash
# ABOUTME: Weekly memory consolidation for the DISTILLED lessons store (Pillar V, task V7).
# ABOUTME: Detects superseded fact pairs in lessons.md via a single haiku LLM call,
# ABOUTME: annotates older facts with stale markers, writes to <target>.proposed ONLY.
# ABOUTME: Never modifies lessons.md itself. Never touches journal.md (hard guard).
# ABOUTME: Emits a correction event on success. Fail-open on missing claude/jq/timeout.

set -euo pipefail

# Fail-open trap: only activates if set -e fires; the journal.md guard uses explicit exit 1
# so it is unaffected. All other errors return 0 after logging.
_fail_open() {
  echo "memory-consolidate: unexpected error on line $1 — exiting 0 (fail-open)" >&2
  exit 0
}
trap '_fail_open $LINENO' ERR

# ── Argument handling ──────────────────────────────────────────────────────────
TARGET="${1:-$HOME/.claude/memory/lessons.md}"

# ── NON-NEGOTIABLE INVARIANT: refuse to operate on journal.md ─────────────────
# Purpose: prevent accidental modification of the append-only raw journal.
# This guard fires BEFORE fail-open logic — it exits non-zero unconditionally.
# Gotchas: matched by basename only; full-path variations are all caught.
_basename="${TARGET##*/}"
if [[ "$_basename" == "journal.md" ]]; then
  echo "memory-consolidate: REFUSED — target is journal.md (append-only invariant)" >&2
  echo "memory-consolidate: Run against lessons.md or another distilled store only." >&2
  # Disable the fail-open trap so this exits 1 properly
  trap - ERR
  exit 1
fi

# ── State dir resolution (env-overridable for tests) ──────────────────────────
STATE="${STATE:-$HOME/.claude/state}"
EVENTS_DIR="$STATE/state"

# ── Dependency guards (fail-open: missing tools → exit 0 with log) ──────────
# Disable fail-open trap temporarily for the dependency checks
trap - ERR

if ! command -v claude >/dev/null 2>&1; then
  echo "memory-consolidate: claude not found — skipping (fail-open)" >&2
  exit 0
fi

if [[ ! -f "$TARGET" ]]; then
  echo "memory-consolidate: target file not found: $TARGET — skipping (fail-open)" >&2
  exit 0
fi

# Re-enable fail-open for the rest
trap '_fail_open $LINENO' ERR

# ── Load lessons.md ────────────────────────────────────────────────────────────
# The spec guarantees lessons.md ≤ 10 KB; loading whole is safe by design.
lessons_content="$(cat "$TARGET")"

# ── LLM call via haiku (stdin pipe, wrapped in timeout) ───────────────────────
# spec: "ONE haiku call (claude -p --model haiku, stdin pipe)"
# spec: "wrap in scripts/lib/timeout.sh 60"
TIMEOUT_LIB="$(dirname "$0")/lib/timeout.sh"

LLM_PROMPT="Find pairs of facts in this lessons file that are same-topic but one supersedes the other. Output JSON only (no explanation, no markdown fences): [{\"older_fact_start_line\":N, \"newer_fact_start_line\":M, \"reason\":\"...\"}]

If there are no superseded pairs, output: []

The lessons file content follows:
---
$lessons_content"

# Run haiku with timeout. Capture output; on failure or timeout, fall through to
# malformed-JSON handler.
llm_raw=""
haiku_exit=0

# Write prompt to a tmpfile so _run_with_timeout can exec claude directly
# (bash -c subshells don't inherit unexported variables or the stdin pipe)
_prompt_tmp="$(mktemp /tmp/memory-consolidate-prompt.XXXXXX)"
printf '%s' "$LLM_PROMPT" > "$_prompt_tmp"

if [[ -f "$TIMEOUT_LIB" ]]; then
  # shellcheck source=scripts/lib/timeout.sh
  source "$TIMEOUT_LIB"
  llm_raw="$(_run_with_timeout 60 claude -p --model claude-haiku-4-5 < "$_prompt_tmp" 2>/dev/null)" || haiku_exit=$?
else
  # Fallback: run without timeout wrapper (still fail-open)
  llm_raw="$(claude -p --model claude-haiku-4-5 < "$_prompt_tmp" 2>/dev/null)" || haiku_exit=$?
fi

rm -f "$_prompt_tmp"

if [[ "$haiku_exit" -ne 0 && -z "$llm_raw" ]]; then
  echo "memory-consolidate: haiku call failed (exit $haiku_exit) — skipping (fail-open)" >&2
  trap - ERR
  exit 0
fi

# ── Parse JSON — strip markdown fences, then parse strictly ───────────────────
# Spec: "parse strictly, tolerate fences"
json_clean=""
if command -v python3 >/dev/null 2>&1; then
  json_clean="$(python3 -c "
import sys, re, json

raw = sys.stdin.read().strip()

# Strip markdown fences (common LLM output pattern)
raw = re.sub(r'^\s*\`\`\`(?:json)?\s*', '', raw, flags=re.MULTILINE)
raw = re.sub(r'\s*\`\`\`\s*$', '', raw, flags=re.MULTILINE)
raw = raw.strip()

try:
    pairs = json.loads(raw)
    if not isinstance(pairs, list):
        sys.exit(1)
    # Validate each pair has required fields
    clean = []
    for p in pairs:
        if isinstance(p, dict) and 'older_fact_start_line' in p and 'newer_fact_start_line' in p:
            clean.append(p)
    print(json.dumps(clean))
except (json.JSONDecodeError, Exception) as e:
    sys.exit(1)
" <<< "$llm_raw" 2>/dev/null)" || {
    echo "memory-consolidate: LLM output is not valid JSON — skipping (fail-open)" >&2
    trap - ERR
    exit 0
  }
else
  echo "memory-consolidate: python3 not found — skipping (fail-open)" >&2
  trap - ERR
  exit 0
fi

# ── Apply stale annotations ────────────────────────────────────────────────────
# For each superseded pair: annotate the line at older_fact_start_line with a
# <!-- stale: superseded by line M — $DATE --> comment on the same line (after the content).
# The newer fact is kept verbatim. The result is written to <target>.proposed.
PROPOSED="${TARGET}.proposed"
DATE=$(date +%Y-%m-%d 2>/dev/null || echo "unknown")

pair_count=0
annotated_count=0

python3 - "$TARGET" "$PROPOSED" "$DATE" <<PYEOF
import sys, json, os

target_path = sys.argv[1]
proposed_path = sys.argv[2]
date = sys.argv[3]

with open(target_path, 'r') as f:
    lines = f.readlines()

# Parse pairs from stdin (already validated JSON)
pairs_raw = sys.stdin.read().strip()
PYEOF

# We need to pass the json_clean to python3 via stdin — restructure as a here-string
python3_output="$(python3 - "$TARGET" "$PROPOSED" "$DATE" "$json_clean" <<'PYEOF'
import sys, json, os

target_path = sys.argv[1]
proposed_path = sys.argv[2]
date = sys.argv[3]
pairs_json = sys.argv[4]

with open(target_path, 'r') as f:
    lines = f.readlines()  # 1-indexed when accessed as lines[n-1]

try:
    pairs = json.loads(pairs_json)
except Exception:
    pairs = []

annotated = set()  # 1-indexed line numbers that get stale marker
for pair in pairs:
    older = pair.get('older_fact_start_line')
    newer = pair.get('newer_fact_start_line')
    reason = pair.get('reason', '')
    if isinstance(older, int) and 1 <= older <= len(lines):
        annotated.add((older, newer, reason))

# Build proposed lines: annotate older lines by appending stale comment
result_lines = []
stale_count = 0
for i, line in enumerate(lines):
    line_num = i + 1  # 1-indexed
    matched = None
    for (older, newer, reason) in annotated:
        if older == line_num:
            matched = (older, newer, reason)
            break
    if matched:
        older, newer, reason = matched
        # Append stale marker on the same line (before the newline)
        stripped = line.rstrip('\n').rstrip('\r')
        stale_marker = f'  <!-- stale: superseded by line {newer} — {date} -->'
        result_lines.append(stripped + stale_marker + '\n')
        stale_count += 1
    else:
        result_lines.append(line)

with open(proposed_path, 'w') as f:
    f.writelines(result_lines)

print(stale_count)
PYEOF
)" || {
  echo "memory-consolidate: annotation step failed — skipping (fail-open)" >&2
  trap - ERR
  exit 0
}

annotated_count="${python3_output:-0}"
pair_count="$(python3 -c "import json, sys; pairs=json.loads(sys.argv[1]); print(len(pairs))" "$json_clean" 2>/dev/null || echo 0)"

echo "memory-consolidate: staged $annotated_count stale annotations from $pair_count pairs → $PROPOSED" >&2

# ── Emit correction event ─────────────────────────────────────────────────────
# Spec: "emit ONE event via scripts/lib/emit-event.sh"
# Category: "memory-consolidation", pairs: N, staged: "lessons.md.proposed"
EMIT_LIB="$(dirname "$0")/lib/emit-event.sh"

_staged_basename="${PROPOSED##*/}"
EVENT_PAYLOAD="{\"category\":\"memory-consolidation\",\"pairs\":$annotated_count,\"staged\":\"$_staged_basename\"}"

if [[ -f "$EMIT_LIB" ]]; then
  # shellcheck source=scripts/lib/emit-event.sh
  ( STATE="$STATE" source "$EMIT_LIB" 2>/dev/null && \
    emit_event "correction" "$EVENT_PAYLOAD" source="memory-consolidate" 2>/dev/null ) || true
else
  # Minimal direct append fallback (tests may not have emit-event.sh on the trimmed PATH)
  mkdir -p "$EVENTS_DIR" 2>/dev/null || true
  local_ts="$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo '1970-01-01T00:00:00Z')"
  local_line="{\"ts\":\"$local_ts\",\"schema\":1,\"session_id\":\"memory-consolidate\",\"agent_id\":null,\"event_type\":\"correction\",\"source\":\"memory-consolidate\",\"project\":\"~global\",\"payload\":$EVENT_PAYLOAD,\"tool\":null,\"skill\":null,\"outcome\":null,\"evidence_ref\":null,\"trace_id\":null}"
  printf '%s\n' "$local_line" >> "$EVENTS_DIR/events.ndjson" 2>/dev/null || true
fi

trap - ERR
exit 0
