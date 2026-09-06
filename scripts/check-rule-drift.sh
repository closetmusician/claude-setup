#!/usr/bin/env bash
# ABOUTME: Pillar V, task V8 — cross-repo rule-drift detector (OBJ-6).
# ABOUTME: Globs CLAUDE.md and rules/*.md across ~/Code/* repos (max depth 3) plus ~/.claude.
# ABOUTME: Finds sections with the same header in ≥2 repos whose body content hash DIFFERS.
# ABOUTME: Emits incident{class:rule-drift, severity:P2} via emit-event.sh + hoist candidate
# ABOUTME: lines to $(STATE)/rule-drift-report.txt. Idempotent per day (7d dedupe window).
# Usage: bash check-rule-drift.sh
#   Env overrides for tests: EVENTS=<path> STATE=<dir> REPO_GLOB_ROOT=<dir>
#                            RULE_DRIFT_REPORT=<path>

# ── Bash discipline ──────────────────────────────────────────────────────────
set -uo pipefail
trap 'exit 0' ERR

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ── Resolve state dir ────────────────────────────────────────────────────────
# Purpose: find the harness state directory for events.ndjson.
# Tests override via STATE env; production uses ~/.claude/state (Pillar I global durable home).
# Gotchas: never hardcode the path — always use this resolution order.
if [ -n "${STATE:-}" ]; then
  _STATE_DIR="$STATE"
else
  _STATE_DIR="${HOME}/.claude/state"
fi
mkdir -p "$_STATE_DIR/state" 2>/dev/null || true

# ── Load emit-event.sh ───────────────────────────────────────────────────────
_EMIT_LIB="${SCRIPT_DIR}/lib/emit-event.sh"
if [ -f "$_EMIT_LIB" ]; then
  # shellcheck source=/dev/null
  source "$_EMIT_LIB" 2>/dev/null || true
else
  # Fail-open: define no-op if lib absent
  emit_event() { true; }
fi

# ── Env overrides ────────────────────────────────────────────────────────────
# EVENTS: path to events.ndjson (for tests; production uses emit-event.sh resolution)
# REPO_GLOB_ROOT: root to glob for repos (default: ~/Code)
# RULE_DRIFT_REPORT: path for hoist candidate report
REPO_GLOB_ROOT="${REPO_GLOB_ROOT:-${HOME}/Code}"
RULE_DRIFT_REPORT="${RULE_DRIFT_REPORT:-${_STATE_DIR}/rule-drift-report.txt}"
EVENTS="${EVENTS:-${_STATE_DIR}/state/events.ndjson}"

# ── Require jq and python3 ───────────────────────────────────────────────────
command -v jq >/dev/null 2>&1 || { exit 0; }
command -v python3 >/dev/null 2>&1 || { exit 0; }

# ── Temp workspace ───────────────────────────────────────────────────────────
TMPWORK="$(mktemp -d /tmp/rule-drift-XXXXXX)"
trap 'rm -rf "$TMPWORK" 2>/dev/null; exit 0' EXIT ERR INT TERM

SECTIONS_TSV="${TMPWORK}/sections.tsv"
PYTHON_PARSE="${TMPWORK}/parse_sections.py"
PYTHON_DETECT="${TMPWORK}/detect_drift.py"

# ── Write Python helpers to temp files (avoids heredoc-within-heredoc) ──────
# Purpose: python3 helpers written to files so they can be invoked cleanly.
# Gotchas: bash heredocs can't be nested; using temp files is the portable pattern.

cat > "$PYTHON_PARSE" << 'PARSE_EOF'
# ABOUTME: Parses one markdown file, emits TSV: header\tbody_sha256[:16]
import sys, hashlib, re

path = sys.argv[1]
try:
    content = open(path, 'r', errors='replace').read()
except Exception:
    sys.exit(0)

lines = content.splitlines()
sections = []
current_header = None
current_body = []

for line in lines:
    m = re.match(r'^(#{1,6})\s+(.+)', line)
    if m:
        if current_header is not None:
            body = '\n'.join(current_body).strip()
            body_hash = hashlib.sha256(body.encode()).hexdigest()[:16]
            sections.append((current_header, body_hash))
        current_header = m.group(2).strip().lower()
        current_body = []
    else:
        if current_header is not None:
            current_body.append(line)

if current_header is not None:
    body = '\n'.join(current_body).strip()
    body_hash = hashlib.sha256(body.encode()).hexdigest()[:16]
    sections.append((current_header, body_hash))

for header, body_hash in sections:
    print(f"{header}\t{body_hash}")
PARSE_EOF

cat > "$PYTHON_DETECT" << 'DETECT_EOF'
# ABOUTME: Reads sections.tsv, loads existing incidents, emits shell eval lines per new drift.
# Output: one line per new divergence: DRIFT_HEADER=... DRIFT_REPO_A=... DRIFT_REPO_B=... DRIFT_DETAIL=...
import sys, json, shlex
from collections import defaultdict
from datetime import datetime, timezone, timedelta

sections_tsv = sys.argv[1]
events_file = sys.argv[2]

# Parse sections
sections = defaultdict(list)
try:
    with open(sections_tsv, 'r') as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            parts = line.split('\t', 2)
            if len(parts) != 3:
                continue
            header, body_hash, repo = parts
            sections[header].append((body_hash, repo))
except Exception:
    sys.exit(0)

# Load existing incidents for 7-day dedupe
cutoff = datetime.now(timezone.utc) - timedelta(days=7)
existing = set()
try:
    with open(events_file, 'r', errors='replace') as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            try:
                e = json.loads(line)
            except Exception:
                continue
            if e.get('event_type') != 'incident':
                continue
            p = e.get('payload', {})
            if p.get('class') != 'rule-drift':
                continue
            ts_str = e.get('ts', '')
            try:
                ts = datetime.fromisoformat(ts_str.replace('Z', '+00:00'))
                if ts < cutoff:
                    continue
            except Exception:
                continue
            detail = p.get('detail', '')
            existing.add(detail)
except Exception:
    pass

# Emit shell var lines for each new divergence
for header, entries in sections.items():
    if len(entries) < 2:
        continue
    hashes = set(h for h, _ in entries)
    if len(hashes) < 2:
        continue
    seen_pairs = set()
    for i in range(len(entries)):
        for j in range(i + 1, len(entries)):
            h_i, r_i = entries[i]
            h_j, r_j = entries[j]
            if r_i == r_j:
                continue  # Same repo — within-repo variant, not cross-repo drift
            if h_i == h_j:
                continue
            pair = tuple(sorted([r_i, r_j]))
            if pair in seen_pairs:
                continue
            seen_pairs.add(pair)
            detail = "section '{}' diverges between {} and {}".format(header, r_i, r_j)
            detail_alt = "section '{}' diverges between {} and {}".format(header, r_j, r_i)
            if detail in existing or detail_alt in existing:
                continue
            print("{} {} {} {}".format(
                "DRIFT_HEADER=" + shlex.quote(header),
                "DRIFT_REPO_A=" + shlex.quote(r_i),
                "DRIFT_REPO_B=" + shlex.quote(r_j),
                "DRIFT_DETAIL=" + shlex.quote(detail),
            ))
DETECT_EOF

# ── Collect all rule files ───────────────────────────────────────────────────
# Purpose: find every CLAUDE.md and rules/*.md across REPO_GLOB_ROOT (depth 3)
#   plus ~/.claude itself. Writes repo\tfile pairs.
# Gotchas: skip unreadable dirs silently; bound depth to cap runtime.

_collect_rule_files() {
  local claude_home="${HOME}/.claude"
  # Only include ~/.claude when using the default root (not in test mode with overridden root)
  if [ "${REPO_GLOB_ROOT}" = "${HOME}/Code" ]; then
    if [ -f "${claude_home}/CLAUDE.md" ]; then
      printf '%s\t%s\n' "$claude_home" "${claude_home}/CLAUDE.md"
    fi
    while IFS= read -r f; do
      printf '%s\t%s\n' "$claude_home" "$f"
    done < <(find "${claude_home}/rules" -maxdepth 1 -name "*.md" 2>/dev/null || true)
  fi

  if [ ! -d "$REPO_GLOB_ROOT" ]; then
    return 0
  fi

  while IFS= read -r repo_dir; do
    [ -d "$repo_dir" ] || continue

    if [ -f "${repo_dir}/CLAUDE.md" ]; then
      printf '%s\t%s\n' "$repo_dir" "${repo_dir}/CLAUDE.md"
    fi
    while IFS= read -r f; do
      printf '%s\t%s\n' "$repo_dir" "$f"
    done < <(find "${repo_dir}/.claude/rules" -maxdepth 1 -name "*.md" 2>/dev/null || true)
    while IFS= read -r f; do
      printf '%s\t%s\n' "$repo_dir" "$f"
    done < <(find "${repo_dir}/rules" -maxdepth 1 -name "*.md" 2>/dev/null || true)
  done < <(find "$REPO_GLOB_ROOT" -maxdepth 1 -mindepth 1 -type d 2>/dev/null || true)
}

# ── Collect sections into TSV ────────────────────────────────────────────────
while IFS=$'\t' read -r repo file; do
  while IFS=$'\t' read -r header body_hash; do
    printf '%s\t%s\t%s\n' "$header" "$body_hash" "$repo"
  done < <(python3 "$PYTHON_PARSE" "$file" 2>/dev/null || true)
done < <(_collect_rule_files 2>/dev/null || true) > "$SECTIONS_TSV" 2>/dev/null || true

# ── Detect drift and emit incidents ─────────────────────────────────────────
# Purpose: for each new divergence, emit an incident event + append hoist line.
# Gotchas: eval is used to set DRIFT_* vars from python3 output; jq --arg only.
while IFS= read -r emit_cmd; do
  [ -z "$emit_cmd" ] && continue
  eval "$emit_cmd" 2>/dev/null || continue

  PAYLOAD="$(jq -cn \
    --arg severity "P2" \
    --arg class "rule-drift" \
    --arg header "${DRIFT_HEADER:-}" \
    --arg repo_a "${DRIFT_REPO_A:-}" \
    --arg repo_b "${DRIFT_REPO_B:-}" \
    --arg detail "${DRIFT_DETAIL:-}" \
    '{severity:$severity,class:$class,rule_header:$header,repos:[$repo_a,$repo_b],hoistable:true,detail:$detail}' \
    2>/dev/null)" || continue

  [ -z "$PAYLOAD" ] && continue

  # Export STATE so emit_event (a bash function, not subprocess) routes to correct file
  export STATE="$_STATE_DIR"
  emit_event "incident" "$PAYLOAD" source=check-rule-drift.sh 2>/dev/null || true

  # Append hoist candidate line to report
  mkdir -p "$(dirname "$RULE_DRIFT_REPORT")" 2>/dev/null || true
  printf 'hoist candidate: rule "%s" diverges between %s and %s — consider promoting canonical version to ~/.claude/rules/\n' \
    "${DRIFT_HEADER:-}" "${DRIFT_REPO_A:-}" "${DRIFT_REPO_B:-}" >> "$RULE_DRIFT_REPORT" 2>/dev/null || true

done < <(python3 "$PYTHON_DETECT" "$SECTIONS_TSV" "$EVENTS" 2>/dev/null || true)

exit 0
