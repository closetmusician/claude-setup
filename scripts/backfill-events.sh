#!/usr/bin/env bash
# ABOUTME: Imports historical events into the telemetry spine (events-backfill.ndjson).
# ABOUTME: Sources: journal.md (session_end), guard logs (incident), audit TSVs (agent/skill/trust).
# ABOUTME: Each line becomes schema-v1 with source:"backfill/<kind>" and content-hash dedup key.
# ABOUTME: --dry-run mode reports per-source counts without writing. Fail-open on malformed lines.
# ABOUTME: SECRET SCAN mandatory before any ingestion (I-4.2); aborts source on any hit.

set -uo pipefail

# ── Constants (env overrides accepted for testing) ────────────────────────────
JOURNAL_FILE="${JOURNAL_FILE_OVERRIDE:-${HOME}/.claude/memory/journal.md}"
STATE_DIR="${STATE_DIR_OVERRIDE:-${HOME}/.claude/state}"
AUDIT_DIR="${AUDIT_DIR_OVERRIDE:-${HOME}/.claude/docs/plans/harness/audit-2026-07-03/evidence}"

# Resolve $STATE per substrate-decision.md AMENDMENT 2026-07-04 (gate I-5).
# Global durable home: ~/.claude/state (always). Per-project path destroyed at SessionEnd.
_resolve_state() {
  printf '%s/.claude/state' "$HOME"
}
STATE="${HARNESS_STATE_OVERRIDE:-$(_resolve_state)}"
BACKFILL_FILE="${STATE}/state/events-backfill.ndjson"
DEDUP_FILE="${STATE}/state/.backfill-dedup.txt"

DRY_RUN=0
[[ "${1:-}" == "--dry-run" ]] && DRY_RUN=1

# ── Secret-scan patterns (I-4.2; mirrors secret-scan.sh) ──────────────────────
SECRET_PATTERNS='ghp_[A-Za-z0-9]{30,}|github_pat_[A-Za-z0-9_]{22,}|ATATT[A-Za-z0-9_=.-]{20,}|sk-(proj|ant|svcacct)?-?[A-Za-z0-9_-]{24,}|AKIA[A-Z0-9]{16}|xox[baprs]-[A-Za-z0-9-]{10,}|-----BEGIN [A-Z ]*PRIVATE KEY-----|glpat-[A-Za-z0-9_-]{20,}|AIza[A-Za-z0-9_-]{35}'

# Purpose: scan a file for secrets before ingestion; prints masked hits to stderr; returns hit count.
# Usage: hits=$(_secret_scan_file "label" "/path/to/file")
# Gotchas: single grep pass — fast even on large files. Never prints raw secret values.
_secret_scan_file() {
  local label="$1"
  local file="$2"
  local hits=0
  local line
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    local lineno="${line%%:*}"
    local match="${line#*:}"
    local masked="${match:0:4}***"
    echo "  SECRET? ${label}:${lineno} masked=[${masked}]" >&2
    hits=$((hits+1))
  done < <(grep -nEo "$SECRET_PATTERNS" "$file" 2>/dev/null | head -20 || true)
  printf '%d' "$hits"
}

# ── Counters (associative arrays) ─────────────────────────────────────────────
declare -A SRC_WRITTEN SRC_SKIP_DUP SRC_SKIP_BAD SRC_SKIP_SECRET
for src in journal guard_completion guard_qa_ownership guard_qa_probe tsv_sessions tsv_agents tsv_skills tsv_trust tsv_tool_errors; do
  SRC_WRITTEN[$src]=0
  SRC_SKIP_DUP[$src]=0
  SRC_SKIP_BAD[$src]=0
  SRC_SKIP_SECRET[$src]=0
done

# ── Source: journal.md (python3 single-pass) ──────────────────────────────────
# Purpose: parse journal entries into session_end events using one python3 invocation.
# Handles dedup in python, writes NDJSON or counts for --dry-run.
_ingest_journal() {
  local src="journal"
  [[ -f "$JOURNAL_FILE" ]] || { echo "[backfill] journal not found: $JOURNAL_FILE" >&2; return; }

  echo "[backfill] scanning journal for secrets..." >&2
  local scan_hits
  scan_hits=$(_secret_scan_file "journal" "$JOURNAL_FILE")
  if [[ "${scan_hits:-0}" -gt 0 ]]; then
    echo "[backfill] ABORT journal source: ${scan_hits} secret(s) found — source excluded." >&2
    SRC_SKIP_SECRET[$src]="${scan_hits}"
    return
  fi

  local result
  result="$(python3 - "$JOURNAL_FILE" "$DEDUP_FILE" "$BACKFILL_FILE" "$DRY_RUN" <<'PYEOF'
import sys, re, json, hashlib, os

journal_file, dedup_file, backfill_file, dry_run_str = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]
dry_run = dry_run_str == "1"

# Load existing dedup hashes
existing = set()
if os.path.exists(dedup_file):
    with open(dedup_file) as f:
        existing = set(l.strip() for l in f if l.strip())

written, duped, bad = 0, 0, 0
new_hashes = []
new_lines = []

header_re = re.compile(r'^## (\d{4}-\d{2}-\d{2}T[0-9:Z.+-]+) — ([^\s]+) \(([a-f0-9]+)\)')
ts = proj = sid = None

with open(journal_file, errors='replace') as f:
    for line in f:
        line = line.rstrip('\n')
        m = header_re.match(line)
        if m:
            ts, proj, sid = m.group(1), m.group(2), m.group(3)
            continue
        if line == '---' and ts and proj and sid:
            key = hashlib.sha256(f"journal:{ts}:{sid}".encode()).hexdigest()
            if key in existing:
                duped += 1
            else:
                payload = json.dumps({"project": proj, "session_id": sid, "source_file": "journal.md"})
                event = json.dumps({
                    "schema": 1, "ts": ts, "session_id": sid, "agent_id": None,
                    "event_type": "session_end", "source": "backfill/journal",
                    "project": proj, "payload": {"project": proj, "session_id": sid, "source_file": "journal.md"},
                    "tool": None, "skill": None, "outcome": None, "evidence_ref": None, "trace_id": None
                })
                existing.add(key)
                new_hashes.append(key)
                new_lines.append(event)
                written += 1
            ts = proj = sid = None

if not dry_run and new_lines:
    os.makedirs(os.path.dirname(backfill_file), exist_ok=True)
    with open(backfill_file, 'a') as f:
        f.write('\n'.join(new_lines) + '\n')
    with open(dedup_file, 'a') as f:
        f.write('\n'.join(new_hashes) + '\n')

print(f"{written}\t{duped}\t{bad}")
PYEOF
  )" 2>/dev/null || result="0\t0\t0"

  IFS=$'\t' read -r w d b <<< "$result"
  SRC_WRITTEN[$src]=$((SRC_WRITTEN[$src] + ${w:-0}))
  SRC_SKIP_DUP[$src]=$((SRC_SKIP_DUP[$src] + ${d:-0}))
  SRC_SKIP_BAD[$src]=$((SRC_SKIP_BAD[$src] + ${b:-0}))
}

# ── Source: guard logs (python3 single-pass) ───────────────────────────────────
# Format: 2026-07-03T10:46:25Z <rest of line>
# Each valid line → one event of the given type.
_ingest_guard_log() {
  local logfile="$1" src="$2" event_type="$3"
  [[ -f "$logfile" ]] || return 0

  echo "[backfill] scanning ${src} for secrets..." >&2
  local scan_hits
  scan_hits=$(_secret_scan_file "$src" "$logfile")
  if [[ "${scan_hits:-0}" -gt 0 ]]; then
    echo "[backfill] ABORT ${src}: ${scan_hits} secret(s) found — source excluded." >&2
    SRC_SKIP_SECRET[$src]="${scan_hits}"
    return
  fi

  local result
  result="$(python3 - "$logfile" "$src" "$event_type" "$DEDUP_FILE" "$BACKFILL_FILE" "$DRY_RUN" <<'PYEOF'
import sys, re, json, hashlib, os

logfile, src, event_type, dedup_file, backfill_file, dry_run_str = sys.argv[1:]
dry_run = dry_run_str == "1"

existing = set()
if os.path.exists(dedup_file):
    with open(dedup_file) as f:
        existing = set(l.strip() for l in f if l.strip())

ts_re = re.compile(r'^(\d{4}-\d{2}-\d{2}T[0-9:Z.+-]+)\s+(.+)$')
written, duped, bad = 0, 0, 0
new_hashes, new_lines = [], []

with open(logfile, errors='replace') as f:
    for line in f:
        line = line.rstrip('\n')
        if not line:
            continue
        m = ts_re.match(line)
        if not m:
            bad += 1
            continue
        ts, rest = m.group(1), m.group(2)
        key = hashlib.sha256(f"{src}:{line}".encode()).hexdigest()
        if key in existing:
            duped += 1
            continue
        event = json.dumps({
            "schema": 1, "ts": ts, "session_id": "backfill-session", "agent_id": None,
            "event_type": event_type, "source": f"backfill/{src}",
            "project": "~global", "payload": {"raw": rest, "log_source": src},
            "tool": None, "skill": None, "outcome": None, "evidence_ref": None, "trace_id": None
        })
        existing.add(key)
        new_hashes.append(key)
        new_lines.append(event)
        written += 1

if not dry_run and new_lines:
    os.makedirs(os.path.dirname(backfill_file), exist_ok=True)
    with open(backfill_file, 'a') as f:
        f.write('\n'.join(new_lines) + '\n')
    with open(dedup_file, 'a') as f:
        f.write('\n'.join(new_hashes) + '\n')

print(f"{written}\t{duped}\t{bad}")
PYEOF
  )" 2>/dev/null || result="0\t0\t0"

  IFS=$'\t' read -r w d b <<< "$result"
  SRC_WRITTEN[$src]=$((SRC_WRITTEN[$src] + ${w:-0}))
  SRC_SKIP_DUP[$src]=$((SRC_SKIP_DUP[$src] + ${d:-0}))
  SRC_SKIP_BAD[$src]=$((SRC_SKIP_BAD[$src] + ${b:-0}))
}

# ── Source: TSV files (python3 single-pass) ────────────────────────────────────
# Purpose: import TSV audit rows as typed events using one python3 invocation per file.
# Gotchas: TSVs mined from transcripts may contain secrets (I-4.2) — mandatory pre-scan.
_ingest_tsv() {
  local tsvfile="$1" src="$2" event_type="$3" ts_col="$4" session_col="$5" project_col="$6"
  [[ -f "$tsvfile" ]] || return 0

  echo "[backfill] scanning ${src} for secrets..." >&2
  local scan_hits
  scan_hits=$(_secret_scan_file "$src" "$tsvfile")
  if [[ "${scan_hits:-0}" -gt 0 ]]; then
    echo "[backfill] ABORT ${src}: ${scan_hits} secret(s) found — source excluded." >&2
    SRC_SKIP_SECRET[$src]="${scan_hits}"
    return
  fi

  local result
  result="$(python3 - "$tsvfile" "$src" "$event_type" "$ts_col" "$session_col" "$project_col" \
      "$DEDUP_FILE" "$BACKFILL_FILE" "$DRY_RUN" <<'PYEOF'
import sys, re, json, hashlib, os

tsvfile, src, event_type, ts_col, session_col, project_col, dedup_file, backfill_file, dry_run_str = sys.argv[1:]
dry_run = dry_run_str == "1"

existing = set()
if os.path.exists(dedup_file):
    with open(dedup_file) as f:
        existing = set(l.strip() for l in f if l.strip())

ts_re = re.compile(r'^\d{4}-\d{2}-\d{2}')
written, duped, bad = 0, 0, 0
new_hashes, new_lines = [], []

with open(tsvfile, errors='replace') as f:
    header = f.readline().rstrip('\n').split('\t')
    col_idx = {c: i for i, c in enumerate(header)}
    ts_i = col_idx.get(ts_col, -1)
    sess_i = col_idx.get(session_col, -1)
    proj_i = col_idx.get(project_col, -1)

    if ts_i < 0:
        print(f"0\t0\t1")
        sys.exit(0)

    for line in f:
        row = line.rstrip('\n').split('\t')
        ts = row[ts_i] if ts_i < len(row) else ''
        if not ts or not ts_re.match(ts):
            bad += 1
            continue
        sid = row[sess_i] if sess_i >= 0 and sess_i < len(row) else 'backfill-unknown'
        proj = row[proj_i] if proj_i >= 0 and proj_i < len(row) else '~global'
        # Normalize project path prefix
        proj = proj.lstrip('-')
        for prefix in ('Users-yklin-Code-', 'Users-yklin-'):
            if proj.startswith(prefix):
                proj = proj[len(prefix):]
                break

        row_key = '\t'.join(row)
        key = hashlib.sha256(f"{src}:{row_key}".encode()).hexdigest()
        if key in existing:
            duped += 1
            continue

        # Build payload as dict of first ~10 columns (cap to avoid huge payloads)
        payload = {}
        for i, col in enumerate(header[:10]):
            if i < len(row):
                payload[col] = row[i]

        event = json.dumps({
            "schema": 1, "ts": ts, "session_id": sid, "agent_id": None,
            "event_type": event_type, "source": f"backfill/{src}",
            "project": proj, "payload": payload,
            "tool": None, "skill": None, "outcome": None, "evidence_ref": None, "trace_id": None
        })
        existing.add(key)
        new_hashes.append(key)
        new_lines.append(event)
        written += 1

if not dry_run and new_lines:
    os.makedirs(os.path.dirname(backfill_file), exist_ok=True)
    with open(backfill_file, 'a') as f:
        f.write('\n'.join(new_lines) + '\n')
    with open(dedup_file, 'a') as f:
        f.write('\n'.join(new_hashes) + '\n')

print(f"{written}\t{duped}\t{bad}")
PYEOF
  )" 2>/dev/null || result="0\t0\t0"

  IFS=$'\t' read -r w d b <<< "$result"
  SRC_WRITTEN[$src]=$((SRC_WRITTEN[$src] + ${w:-0}))
  SRC_SKIP_DUP[$src]=$((SRC_SKIP_DUP[$src] + ${d:-0}))
  SRC_SKIP_BAD[$src]=$((SRC_SKIP_BAD[$src] + ${b:-0}))
}

# ── Source: tool_errors.tsv (custom — no ts column; synthesize from month) ────
# Synthesizes ts as YYYY-MM-01T00:00:00Z from the month column.
_ingest_tool_errors_tsv() {
  local src="tsv_tool_errors"
  local tsvfile="${AUDIT_DIR}/tool_errors.tsv"
  [[ -f "$tsvfile" ]] || return 0

  echo "[backfill] scanning ${src} for secrets..." >&2
  local scan_hits
  scan_hits=$(_secret_scan_file "$src" "$tsvfile")
  if [[ "${scan_hits:-0}" -gt 0 ]]; then
    echo "[backfill] ABORT ${src}: ${scan_hits} secret(s) found — source excluded." >&2
    SRC_SKIP_SECRET[$src]="${scan_hits}"
    return
  fi

  local result
  result="$(python3 - "$tsvfile" "$src" "$DEDUP_FILE" "$BACKFILL_FILE" "$DRY_RUN" <<'PYEOF'
import sys, re, json, hashlib, os

tsvfile, src, dedup_file, backfill_file, dry_run_str = sys.argv[1:]
dry_run = dry_run_str == "1"

existing = set()
if os.path.exists(dedup_file):
    with open(dedup_file) as f:
        existing = set(l.strip() for l in f if l.strip())

month_re = re.compile(r'^\d{4}-\d{2}$')
written, duped, bad = 0, 0, 0
new_hashes, new_lines = [], []

with open(tsvfile, errors='replace') as f:
    header = f.readline().rstrip('\n').split('\t')  # month project tool err_120
    for line in f:
        row = line.rstrip('\n').split('\t')
        if len(row) < 2:
            bad += 1
            continue
        month = row[0] if row else ''
        if not month or not month_re.match(month):
            bad += 1
            continue
        ts = f"{month}-01T00:00:00Z"
        proj = row[1] if len(row) > 1 else '~global'
        proj = proj.lstrip('-')
        for prefix in ('Users-yklin-Code-', 'Users-yklin-'):
            if proj.startswith(prefix):
                proj = proj[len(prefix):]
                break
        tool = row[2] if len(row) > 2 else ''
        err  = row[3] if len(row) > 3 else ''

        row_key = '\t'.join(row)
        key = hashlib.sha256(f"{src}:{row_key}".encode()).hexdigest()
        if key in existing:
            duped += 1
            continue

        event = json.dumps({
            "schema": 1, "ts": ts, "session_id": "backfill-session", "agent_id": None,
            "event_type": "tool_error", "source": f"backfill/{src}",
            "project": proj, "payload": {"tool": tool, "err_120": err, "month": month},
            "tool": tool or None, "skill": None, "outcome": None, "evidence_ref": None, "trace_id": None
        })
        existing.add(key)
        new_hashes.append(key)
        new_lines.append(event)
        written += 1

if not dry_run and new_lines:
    os.makedirs(os.path.dirname(backfill_file), exist_ok=True)
    with open(backfill_file, 'a') as f:
        f.write('\n'.join(new_lines) + '\n')
    with open(dedup_file, 'a') as f:
        f.write('\n'.join(new_hashes) + '\n')

print(f"{written}\t{duped}\t{bad}")
PYEOF
  )" 2>/dev/null || result="0\t0\t0"

  IFS=$'\t' read -r w d b <<< "$result"
  SRC_WRITTEN[$src]=$((SRC_WRITTEN[$src] + ${w:-0}))
  SRC_SKIP_DUP[$src]=$((SRC_SKIP_DUP[$src] + ${d:-0}))
  SRC_SKIP_BAD[$src]=$((SRC_SKIP_BAD[$src] + ${b:-0}))
}

# ── Main ───────────────────────────────────────────────────────────────────────
main() {
  if [[ "$DRY_RUN" -eq 1 ]]; then
    echo "[backfill] DRY-RUN mode — no files will be written"
  else
    mkdir -p "${STATE}/state" || true
    echo "[backfill] Writing to: ${BACKFILL_FILE}"
    echo "[backfill] Dedup index: ${DEDUP_FILE}"
  fi
  echo ""

  echo "=== Source: journal ==="
  _ingest_journal

  echo "=== Source: guard_completion ==="
  _ingest_guard_log \
    "${STATE_DIR}/completion-claim-guard.log" \
    "guard_completion" "incident"

  echo "=== Source: guard_qa_ownership ==="
  _ingest_guard_log \
    "${STATE_DIR}/qa-artifact-ownership-guard.log" \
    "guard_qa_ownership" "trust_decision"

  echo "=== Source: guard_qa_probe ==="
  _ingest_guard_log \
    "${STATE_DIR}/qa-artifact-ownership-guard-probe-0-3.log" \
    "guard_qa_probe" "trust_decision"

  echo "=== Source: tsv_sessions ==="
  _ingest_tsv \
    "${AUDIT_DIR}/sessions.tsv" \
    "tsv_sessions" "session_start" "first_ts" "session" "project"

  echo "=== Source: tsv_agents ==="
  _ingest_tsv \
    "${AUDIT_DIR}/agent_events.tsv" \
    "tsv_agents" "agent_spawn" "ts" "session" "project"

  echo "=== Source: tsv_skills ==="
  _ingest_tsv \
    "${AUDIT_DIR}/skill_events.tsv" \
    "tsv_skills" "skill_fire" "ts" "session" "project"

  echo "=== Source: tsv_trust ==="
  _ingest_tsv \
    "${AUDIT_DIR}/trust_events.tsv" \
    "tsv_trust" "trust_decision" "ts" "session" "project"

  echo "=== Source: tsv_tool_errors ==="
  _ingest_tool_errors_tsv

  # ── Report ────────────────────────────────────────────────────────────────────
  local total_written=0 total_dup=0 total_bad=0 total_secret=0
  echo ""
  echo "╔══════════════════════════════════════════════════════════╗"
  [[ "$DRY_RUN" -eq 1 ]] \
    && echo "║  DRY-RUN SUMMARY (no writes performed)                    ║" \
    || echo "║  BACKFILL SUMMARY                                         ║"
  echo "╠══════════════════════════════════════════════════════════╣"
  printf "║  %-28s %6s %6s %6s %6s ║\n" "source" "written" "dedup" "bad" "secret"
  echo "╠══════════════════════════════════════════════════════════╣"
  for src in journal guard_completion guard_qa_ownership guard_qa_probe tsv_sessions tsv_agents tsv_skills tsv_trust tsv_tool_errors; do
    printf "║  %-28s %6d %6d %6d %6d ║\n" \
      "$src" "${SRC_WRITTEN[$src]}" "${SRC_SKIP_DUP[$src]}" "${SRC_SKIP_BAD[$src]}" "${SRC_SKIP_SECRET[$src]}"
    total_written=$((total_written + SRC_WRITTEN[$src]))
    total_dup=$((total_dup + SRC_SKIP_DUP[$src]))
    total_bad=$((total_bad + SRC_SKIP_BAD[$src]))
    total_secret=$((total_secret + SRC_SKIP_SECRET[$src]))
  done
  echo "╠══════════════════════════════════════════════════════════╣"
  printf "║  %-28s %6d %6d %6d %6d ║\n" "TOTAL" \
    "$total_written" "$total_dup" "$total_bad" "$total_secret"
  echo "╚══════════════════════════════════════════════════════════╝"

  if [[ "$DRY_RUN" -eq 0 && "$total_secret" -gt 0 ]]; then
    echo ""
    echo "[backfill] WARNING: $total_secret secret(s) detected — those sources were excluded." >&2
  fi
  if [[ "$DRY_RUN" -eq 0 ]]; then
    local written_count=0
    [[ -f "$BACKFILL_FILE" ]] && written_count=$(wc -l < "$BACKFILL_FILE")
    echo ""
    echo "[backfill] Backfill file now has ${written_count} events total."
    echo "[backfill] To merge into main events log, run:"
    echo "           cat '${BACKFILL_FILE}' >> '${STATE}/state/events.ndjson'"
  fi
}

main
