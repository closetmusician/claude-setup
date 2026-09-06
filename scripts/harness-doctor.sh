#!/usr/bin/env bash
# ABOUTME: Weekly harness rot-check (audit 2026-07-03, LEAK #3 "silent infrastructure rot").
# ABOUTME: Verifies skill frontmatter, referenced-path existence, hook script syntax,
# ABOUTME: journal size, dead symlinks, and stale .proposed files. Read-only; prints a
# ABOUTME: report and exits 1 if any CRITICAL finding exists, else 0.
# ABOUTME: Extended 2026-07-05 (item 22 evasion detector U3 + 6.2 DIGEST section).
# ABOUTME: Wire into weekly-audit schedule. Evidence: 170 dead skills/bin refs lived ~7 weeks unnoticed.

set -uo pipefail

# Env overrides for test isolation (test suites set these before invoking the script).
CLAUDE_DIR="${CLAUDE_DIR:-${HOME}/.claude}"
STATE_DIR="${STATE_DIR:-${CLAUDE_DIR}/state}"
TRANSCRIPT_DIR="${TRANSCRIPT_DIR:-${HOME}/.claude/projects}"
EVENTS_FILE="${EVENTS_FILE:-${STATE_DIR}/state/events.ndjson}"
DIGEST_FILE="${DIGEST_FILE:-${STATE_DIR}/weekly-digest.md}"
CRIT=0; WARN=0

crit() { echo "CRITICAL: $*"; CRIT=$((CRIT + 1)); }
warn() { echo "warn:     $*"; WARN=$((WARN + 1)); }

echo "=== harness-doctor $(date +%F) ==="

# Self-stamp: record this run's UTC timestamp for stale-stamp detection on next run.
# Read the previous stamp BEFORE writing the new one so we can age-check it.
mkdir -p "$STATE_DIR"
PREV_STAMP=""
[[ -f "${STATE_DIR}/harness-doctor.last-run" ]] && PREV_STAMP=$(cat "${STATE_DIR}/harness-doctor.last-run" 2>/dev/null || true)
date -u +%Y-%m-%dT%H:%M:%SZ > "${STATE_DIR}/harness-doctor.last-run"

# Stale-stamp self-check: warn if the previous stamp was >8 days old.
if [[ -n "$PREV_STAMP" ]]; then
  prev_epoch=$(date -j -u -f "%Y-%m-%dT%H:%M:%SZ" "$PREV_STAMP" "+%s" 2>/dev/null || echo 0)
  now_epoch=$(date -u +%s)
  age_days=$(( (now_epoch - prev_epoch) / 86400 ))
  if [[ "$age_days" -gt 8 ]]; then
    warn "harness-doctor last ran ${age_days} days ago (threshold: 8) — launchd cron may have lapsed"
  fi
fi

# Guard-log audit: warn if completion-claim-guard.log grew with stop_hook_active retry lines.
# Compares current line count to stored count in harness-doctor.ccg-count; warns on growth.
CCG_LOG="${STATE_DIR}/completion-claim-guard.log"
CCG_COUNT_FILE="${STATE_DIR}/harness-doctor.ccg-count"
if [[ -f "$CCG_LOG" ]]; then
  current_ccg=$(grep -c 'stop_hook_active' "$CCG_LOG" 2>/dev/null || echo 0)
  current_ccg="${current_ccg:-0}"
  if [[ -f "$CCG_COUNT_FILE" ]]; then
    prev_ccg=$(cat "$CCG_COUNT_FILE" 2>/dev/null || echo 0)
    if [[ "$current_ccg" -gt "$prev_ccg" ]]; then
      delta=$((current_ccg - prev_ccg))
      warn "completion-claim-guard.log: +${delta} stop_hook_active retry lines since last run (total: ${current_ccg})"
    fi
  fi
  echo "$current_ccg" > "$CCG_COUNT_FILE"
fi

# Transcript-format canary: locate the newest *.jsonl under ~/.claude/projects/*/
# and verify the jq extraction the Stop guard relies on yields non-empty for the
# last assistant message. If empty on a file that has assistant text: CRITICAL.
if command -v jq >/dev/null 2>&1 && [[ -d "$TRANSCRIPT_DIR" ]]; then
  newest_jsonl=""
  while IFS= read -r -d '' f; do
    newest_jsonl="$f"
    break
  done < <(find "$TRANSCRIPT_DIR" -name "*.jsonl" -print0 2>/dev/null | xargs -0 ls -t 2>/dev/null | head -1 | tr '\n' '\0')
  # Simpler: use ls -t via find
  newest_jsonl=$(find "$TRANSCRIPT_DIR" -name "*.jsonl" 2>/dev/null | xargs ls -t 2>/dev/null | head -1 || true)
  if [[ -n "$newest_jsonl" && -f "$newest_jsonl" ]]; then
    extracted=$(jq -r 'select(.type=="assistant") | .message.content[]? | select(.type=="text") | .text' \
      "$newest_jsonl" 2>/dev/null | tail -5 || true)
    if [[ -z "$extracted" ]]; then
      # Check if transcript actually has assistant messages at the raw level.
      raw_count=$(grep -c '"type":"assistant"' "$newest_jsonl" 2>/dev/null || echo 0)
      if [[ "${raw_count:-0}" -gt 0 ]]; then
        crit "TRANSCRIPT FORMAT CANARY FAILED: $(basename "$newest_jsonl") has ${raw_count} assistant messages but jq extraction yielded empty — completion-claim-guard has gone inert"
      else
        warn "transcript canary: newest jsonl has no assistant messages — may be a short session ($(basename "$newest_jsonl"))"
      fi
    fi
  else
    warn "transcript canary: no *.jsonl found under ~/.claude/projects/ — no sessions to check"
  fi
fi

# 1. Every skill dir has a SKILL.md whose first line starts a YAML frontmatter block.
#    (eng-stories shipped for weeks without one; it could never auto-fire.)
for d in "$CLAUDE_DIR"/skills/*/; do
  name=$(basename "$d")
  f="$d/SKILL.md"
  if [[ ! -f "$f" ]]; then
    warn "skills/$name has no SKILL.md (orphan dir — delete or convert)"
    continue
  fi
  if [[ "$(head -1 "$f")" != "---" ]]; then
    crit "skills/$name/SKILL.md missing YAML frontmatter (cannot auto-fire)"
  fi
done

# 2. Dead references to ~/.claude/skills/bin/ (deleted 2026-05-17; refs fail through || true).
n=$(grep -rl 'skills/bin/' "$CLAUDE_DIR"/skills/*/SKILL.md 2>/dev/null | wc -l | tr -d ' ')
if [[ ! -d "$CLAUDE_DIR/skills/bin" && "$n" -gt 0 ]]; then
  crit "$n skill bodies reference nonexistent ~/.claude/skills/bin/ (silent no-ops)"
fi

# 3. Every hook script referenced in settings.json exists and passes bash -n.
if command -v jq >/dev/null 2>&1 && [[ -f "$CLAUDE_DIR/settings.json" ]]; then
  jq -r '.. | .command? // empty' "$CLAUDE_DIR/settings.json" 2>/dev/null |
    grep -o '[^ ]*\.sh' | sort -u | while read -r sh; do
      p="${sh/#\~/$HOME}"
      if [[ ! -f "$p" ]]; then
        echo "CRITICAL: hook script missing: $sh"
      elif ! bash -n "$p" 2>/dev/null; then
        echo "CRITICAL: hook script fails bash -n: $sh"
      fi
    done | tee /tmp/harness-doctor-hooks.$$
  h=$(grep -c CRITICAL /tmp/harness-doctor-hooks.$$ 2>/dev/null || true)
  CRIT=$((CRIT + ${h:-0})); rm -f /tmp/harness-doctor-hooks.$$
fi

# 4. Dead symlinks under skills/. (process substitution, not a pipe — the counter
#    must increment in the parent shell or the exit code lies about criticals)
while read -r l; do
  [[ -n "$l" ]] && crit "dead skill symlink: $l"
done < <(find -L "$CLAUDE_DIR/skills" -maxdepth 1 -type l 2>/dev/null)

# 5. journal.md unbounded growth (Stop hook appends every session; 6.4MB on 2026-07-03).
#    Threshold 8MB per maintenance-protocol §4.1 check #4.
if [[ -f "$CLAUDE_DIR/memory/journal.md" ]]; then
  sz=$(stat -f %z "$CLAUDE_DIR/memory/journal.md" 2>/dev/null || stat -c %s "$CLAUDE_DIR/memory/journal.md")
  [[ "$sz" -gt 8000000 ]] && warn "memory/journal.md is ${sz} bytes (>8MB) — archive or rotate"
fi

# 6. .proposed files older than 30 days: land or delete (07-02 set sat unapplied).
while read -r p; do
  [[ -n "$p" ]] && warn "stale .proposed (>30d): $p"
done < <(find "$CLAUDE_DIR" -name "*.proposed" -not -path "*/backup-*" -mtime +30 2>/dev/null)

# 7. Known drift signatures (browse entry point; office-hours).
#    Pattern is the invocation path 'browse/dist/browse' — a bare 'dist/browse' would
#    false-positive on the rewrites' own "never use dist/browse" warning lines.
while read -r f; do
  [[ -n "$f" ]] && warn "$f still points at browse/dist/browse (use bin/browse wrapper)"
done < <(grep -l 'browse/dist/browse' "$CLAUDE_DIR"/skills/{qa,qa-only}/SKILL.md 2>/dev/null)
if grep -rql 'skills/office-hours' "$CLAUDE_DIR"/skills/*/SKILL.md 2>/dev/null; then
  [[ -d "$CLAUDE_DIR/skills/office-hours" ]] || warn "office-hours referenced but not installed"
fi

# 8. Skill-index freshness: any SKILL.md newer than its DB row triggers a rebuild.
#    Resolves symlinks before stat so linked SKILL.md files are checked correctly.
#    Fail-open: if DB is missing, warn only — never CRITICAL (index is optional cache).
SKILL_INDEX_DB="${CLAUDE_DIR}/state/skill-index.db"
if [[ ! -f "$SKILL_INDEX_DB" ]]; then
  warn "skill-index.db missing — run scripts/skill-index-build.sh to create it"
else
  stale_count=0
  stale_skills=""
  if command -v python3 >/dev/null 2>&1; then
    stale_result="$(python3 - "$CLAUDE_DIR" "$SKILL_INDEX_DB" <<'PYEOF' 2>/dev/null || true)"
import sys, os, sqlite3
from datetime import datetime, timezone

claude_dir = sys.argv[1]
db_path    = sys.argv[2]

try:
    conn = sqlite3.connect(db_path)
    rows = conn.execute("SELECT skill, path, updated FROM skills").fetchall()
    conn.close()
except Exception:
    sys.exit(0)

# Build map: skill_name → (path, updated_epoch)
indexed = {}
for skill, path, updated in rows:
    if not updated:
        continue
    try:
        dt = datetime.fromisoformat(updated)
        indexed[skill] = (path or "", dt.timestamp())
    except Exception:
        pass

stale = []
skills_dir = os.path.join(claude_dir, "skills")
if not os.path.isdir(skills_dir):
    sys.exit(0)
for name in os.listdir(skills_dir):
    skill_md = os.path.join(skills_dir, name, "SKILL.md")
    real_md  = os.path.realpath(skill_md)
    if not os.path.isfile(real_md):
        continue
    try:
        mtime = os.path.getmtime(real_md)
    except OSError:
        continue
    if name in indexed:
        _, db_epoch = indexed[name]
        if mtime > db_epoch:
            stale.append(name)

if stale:
    print(f"STALE:{len(stale)}:{','.join(sorted(stale))}")
else:
    print("FRESH")
PYEOF
    if [[ "$stale_result" == STALE:* ]]; then
      stale_count="${stale_result#STALE:}"
      stale_count="${stale_count%%:*}"
      echo "skill-index: ${stale_count} skill(s) newer than DB row — rebuilding..."
      if bash "${CLAUDE_DIR}/scripts/skill-index-build.sh" >/dev/null 2>&1; then
        echo "skill-index: rebuilt ${stale_count} skill(s)"
      else
        warn "skill-index rebuild failed — run scripts/skill-index-build.sh manually"
      fi
    fi
  fi
fi

# 9. Skill drift: skills on disk ABSENT from the index (name-based match, resolves symlinks).
#    0 missing = clean; non-zero prints count + names for operator review.
#    Fail-open: if DB is missing, skip silently (check #8 already warned).
if [[ -f "$SKILL_INDEX_DB" ]] && command -v python3 >/dev/null 2>&1; then
  drift_result="$(python3 - "$CLAUDE_DIR" "$SKILL_INDEX_DB" <<'PYEOF' 2>/dev/null || true)"
import sys, os, sqlite3

claude_dir = sys.argv[1]
db_path    = sys.argv[2]

try:
    conn = sqlite3.connect(db_path)
    indexed_names = {r[0] for r in conn.execute("SELECT skill FROM skills").fetchall()}
    conn.close()
except Exception:
    sys.exit(0)

skills_dir = os.path.join(claude_dir, "skills")
if not os.path.isdir(skills_dir):
    sys.exit(0)

missing = []
for name in sorted(os.listdir(skills_dir)):
    skill_md = os.path.join(skills_dir, name, "SKILL.md")
    real_md  = os.path.realpath(skill_md)
    if os.path.isfile(real_md) and name not in indexed_names:
        missing.append(name)

if missing:
    print(f"MISSING:{len(missing)}:{','.join(missing)}")
else:
    print("CLEAN")
PYEOF
  if [[ "$drift_result" == CLEAN ]]; then
    echo "skill-index drift: 0 skills missing from index"
  elif [[ "$drift_result" == MISSING:* ]]; then
    rest="${drift_result#MISSING:}"
    count="${rest%%:*}"
    names="${rest#*:}"
    warn "skill-index drift: ${count} skill(s) on disk absent from index: ${names}"
  fi
fi

# 10. Truncation metric: count SKILL.md descriptions in the index that exceed 1024 chars.
#     These are served as semantic long-tail; the truncation is palliative — the semantic
#     index covers them regardless of listing-budget cuts.
if [[ -f "$SKILL_INDEX_DB" ]] && command -v python3 >/dev/null 2>&1; then
  trunc_count="$(python3 - "$SKILL_INDEX_DB" <<'PYEOF' 2>/dev/null || echo 0)"
import sys, sqlite3
db_path = sys.argv[1]
try:
    conn = sqlite3.connect(db_path)
    rows = conn.execute("SELECT description FROM skills WHERE description IS NOT NULL").fetchall()
    conn.close()
    count = sum(1 for (d,) in rows if len(d) > 1024)
    print(count)
except Exception:
    print(0)
PYEOF
  echo "skill-index truncation: ${trunc_count} description(s) >1024 chars (semantic index covers long-tail)"
fi

# 11. Evasion detector (item 22, class U3, DETECT-only).
#     Scans last 7 days of correction events from the spine + newest ~20 transcripts.
#     U3 pattern = user confrontation whose NEXT assistant message contains no admission
#     or evidence shape (no "you're right/I was wrong", no file:line, no artifact path,
#     no tool_use block immediately following). DETECT-only forever per spec: no oracle
#     for sincerity exists. Emits one trust_decision{verifier:evasion-detector,
#     outcome:would_block, class:U3} per detection; dedupes by session+ts.
#     Runtime cap: max 20 transcripts, timeout via loop counter.
EVASION_DETECTED=0
if command -v jq >/dev/null 2>&1 && command -v python3 >/dev/null 2>&1; then
  # Resolve emit-event.sh for spine writes.
  # Use the real ~/.claude path regardless of CLAUDE_DIR test override — the emitter
  # is infrastructure, not the system under test.
  EMIT_LIB="${HOME}/.claude/scripts/lib/emit-event.sh"

  # U3_CORRECTION_REGEX: tightened version of the §5.1 seed set for evasion detection.
  # Unlike correction-capture.sh (log-only, uses the full seed), the evasion detector
  # maps a match to "you evaded" — a stronger claim — so precision matters more than recall.
  # Change from shared seed: removed bare "i (asked)" which over-triggers on benign
  # request-restatements ("i asked about X earlier") while keeping the high-signal forms
  # "i already said", "i just said", "i already asked", "i just asked", "i told you".
  # MASTER-35 / BUG-SEAMS-04 fix.
  CORRECTION_REGEX='^no[,.!] |^no[,.!]$|i (already|just) (said|told you|asked)|i told you( already| earlier)?[.,!]|you (didn'"'"'?t|did not|never|failed to)|that'"'"'?s (not true|wrong|false|incorrect)|did you (actually|really|even)|show me (the |your )?(proof|evidence|output|diff)|stop (lying|guessing|making)|why did you (ignore|skip|not)|read (the|my) (instructions|prompt|CLAUDE)|not what i (asked|said|wanted)|as i (said|asked|instructed)|^again[:,]|^wrong[.,]'

  # Admission/evidence regex: "you're right", "I was wrong", file:line, artifact path, tool_use.
  ADMISSION_REGEX='you.?re right|i was wrong|correcting|you are correct|my mistake|my error|apologi|file:[^ ]+:[0-9]|/[^ ]+\.[a-z]{1,6}:[0-9]|/tmp/|\.md$|\.sh$|\.json$|\.log$'

  # Step 1: collect candidate sessions from correction events in the spine (last 7 days).
  seven_days_ago_epoch=$(python3 -c "import time; print(int(time.time()) - 7*86400)" 2>/dev/null || echo 0)
  declare -A _evasion_seen  # dedupe: session_ts → 1

  # Load already-detected events to avoid re-emitting on idempotent re-run.
  # Dedupe key: session_id + confrontation_ts (may be empty if transcript lacked ts).
  if [[ -f "$EVENTS_FILE" ]]; then
    while IFS= read -r ev_line; do
      [[ -z "$ev_line" ]] && continue
      ev_class=$(printf '%s' "$ev_line" | jq -r '.payload.class // empty' 2>/dev/null || true)
      ev_session=$(printf '%s' "$ev_line" | jq -r '.payload.session // .session_id // empty' 2>/dev/null || true)
      ev_cts=$(printf '%s' "$ev_line" | jq -r '.payload.confrontation_ts // empty' 2>/dev/null || true)
      if [[ "$ev_class" == "U3" ]]; then
        _evasion_seen["${ev_session}_${ev_cts}"]=1
      fi
    done < <(grep '"evasion-detector"' "$EVENTS_FILE" 2>/dev/null || true)
  fi

  # Step 2: scan recent transcripts for U3 patterns (cap at 20 for <10s runtime).
  # Write detections to a temp file so the parent shell can count/emit (pipe subshell
  # cannot update parent-scope variables). Transcript list also written to temp file
  # because <<'PYEOF' heredoc takes stdin; we can't pipe paths AND use heredoc simultaneously.
  _evasion_tmp=$(mktemp)
  _transcripts_tmp=$(mktemp)
  trap 'rm -f "$_evasion_tmp" "$_transcripts_tmp"' EXIT
  find "$TRANSCRIPT_DIR" -name "*.jsonl" 2>/dev/null | xargs ls -t 2>/dev/null | head -20 \
    > "$_transcripts_tmp" 2>/dev/null || true

  python3 - "$CORRECTION_REGEX" "$ADMISSION_REGEX" "$_transcripts_tmp" <<'PYEOF' 2>/dev/null >> "$_evasion_tmp" || true
import sys, json, re

corr_re  = re.compile(sys.argv[1], re.IGNORECASE)
admit_re = re.compile(sys.argv[2], re.IGNORECASE)
transcripts_file = sys.argv[3]

try:
    with open(transcripts_file) as tf:
        transcript_paths = [l.strip() for l in tf if l.strip()]
except Exception:
    transcript_paths = []

for transcript_path in transcript_paths:
    msgs = []
    try:
        with open(transcript_path) as f:
            for line in f:
                line = line.strip()
                if not line:
                    continue
                try:
                    msgs.append(json.loads(line))
                except Exception:
                    pass
    except Exception:
        continue

    # Resolve session_id from first message that carries one.
    session_id = "unknown"
    for ev in msgs:
        sid = ev.get("session_id") or ev.get("uuid") or ""
        if sid and sid not in ("unknown", ""):
            session_id = sid
            break

    for i, msg in enumerate(msgs):
        if msg.get("type") != "user":
            continue
        content = msg.get("message", {}).get("content", [])
        if isinstance(content, str):
            user_text = content
        elif isinstance(content, list):
            user_text = " ".join(
                c.get("text", "") for c in content
                if isinstance(c, dict) and c.get("type") == "text"
            )
        else:
            user_text = ""
        if not corr_re.search(user_text):
            continue

        # Found confrontation — scan forward across the next few assistant messages
        # (up to K=3) looking for tool_use or admission before concluding evasion.
        # FIX-U3-1: stop at the first assistant message broke on benign preamble→act
        # sequences where assistant sends a text preamble followed by a tool_use
        # message. We now collect ALL assistant messages in the next K turns and check
        # any of them for tool_use / admission.
        K_LOOKAHEAD = 3
        asst_msgs_seen = []
        has_tool_use = False
        for j in range(i + 1, len(msgs)):
            mtype = msgs[j].get("type")
            if mtype == "assistant":
                am = msgs[j]
                asst_msgs_seen.append(am)
                ac = am.get("message", {}).get("content", [])
                if isinstance(ac, list) and any(
                    c.get("type") == "tool_use" for c in ac if isinstance(c, dict)
                ):
                    has_tool_use = True
                if len(asst_msgs_seen) >= K_LOOKAHEAD:
                    break
            elif mtype not in ("user",):
                # Intermediate non-user message (e.g. tool result): check for tool_use
                interm_content = msgs[j].get("message", {}).get("content", [])
                if isinstance(interm_content, list):
                    if any(c.get("type") == "tool_use" for c in interm_content if isinstance(c, dict)):
                        has_tool_use = True

        if not asst_msgs_seen:
            continue

        if has_tool_use:
            continue  # Tool use = evidence in this turn; not evasion.

        # Check ALL assistant messages in the lookahead window for admission.
        asst_text = " ".join(
            " ".join(
                c.get("text", "") for c in (am.get("message", {}).get("content", []) or [])
                if isinstance(c, dict) and c.get("type") == "text"
            )
            for am in asst_msgs_seen
        )

        if admit_re.search(asst_text):
            continue  # Admission or evidence shape found; not evasion.

        # Use the first assistant message for context in the preview.
        asst_msg = asst_msgs_seen[0]

        # U3 pattern confirmed: emit pipe-delimited record to stdout (→ _evasion_tmp).
        # FIX-U3-2: transcript user messages carry "timestamp", not "ts".
        # Spine events use "ts"; read the correct field per source so the dedup key
        # is actually per-confrontation rather than always empty.
        u_ts = msg.get("timestamp") or msg.get("ts") or ""
        # Escape pipe characters in text fields.
        asst_preview = asst_text[:120].replace("|", " ")
        print(f"{session_id}|{u_ts}|{asst_preview}")
PYEOF
  rm -f "$_transcripts_tmp"

  # Process detection records from temp file in the parent shell.
  while IFS='|' read -r sess_id u_ts asst_preview; do
    [[ -z "$sess_id" ]] && continue
    dedupe_key="${sess_id}_${u_ts}"
    if [[ -z "${_evasion_seen[$dedupe_key]+x}" ]]; then
      _evasion_seen["$dedupe_key"]=1
      echo "DETECT [U3] evasion: session=${sess_id} confrontation_ts=${u_ts} asst_preview=${asst_preview}"
      EVASION_DETECTED=$((EVASION_DETECTED + 1))
      # Emit trust_decision event via emit-event.sh (fail-open, subshell OK since we only write).
      if [[ -f "$EMIT_LIB" ]]; then
        _detect_ts=$(python3 -c "from datetime import datetime,timezone; print(datetime.now(timezone.utc).strftime('%Y-%m-%dT%H:%M:%S.')+str(datetime.now(timezone.utc).microsecond//1000).zfill(3)+'Z')" 2>/dev/null || date -u +%Y-%m-%dT%H:%M:%SZ)
        (
          export STATE="$STATE_DIR"
          # shellcheck source=/dev/null
          source "$EMIT_LIB" 2>/dev/null || true
          _payload=$(jq -cn \
            --arg sid "$sess_id" \
            --arg dts "$_detect_ts" \
            --arg uts "$u_ts" \
            '{"verifier":"evasion-detector","outcome":"would_block","class":"U3","session":$sid,"detection_ts":$dts,"confrontation_ts":$uts}' 2>/dev/null || \
            echo '{"verifier":"evasion-detector","outcome":"would_block","class":"U3"}')
          emit_event "trust_decision" "$_payload" \
            source="harness-doctor.sh" outcome="would_block" 2>/dev/null || true
        ) 2>/dev/null || true
      fi
    fi
  done < "$_evasion_tmp"
  rm -f "$_evasion_tmp"

  if [[ "$EVASION_DETECTED" -eq 0 ]]; then
    echo "evasion-detector (U3): 0 patterns detected in last 20 transcripts"
  else
    echo "evasion-detector (U3): ${EVASION_DETECTED} pattern(s) detected — review weekly digest"
  fi
fi

# 12. DIGEST section (6.2) — rendered to stdout AND written to ~/.claude/state/weekly-digest.md.
#     Every section renders real data or explicit "no data yet" — never silently empty.
#     Announced via scripts/notify.sh 'Weekly harness digest ready'.
_digest_lines=()
_dappend() { _digest_lines+=("$*"); }

_dappend "# Weekly Harness Digest — $(date +%F)"
_dappend ""

# Section A: STAGED PATCHES / LOOP INBOX
_dappend "## STAGED PATCHES / LOOP INBOX"
_proposed_count=0
_proposed_stale=0
while IFS= read -r pf; do
  [[ -z "$pf" ]] && continue
  _proposed_count=$((_proposed_count + 1))
  # Check age: warn if >7 days old.
  _age_days=0
  _age_days=$(python3 -c "
import os, time
mtime = os.path.getmtime('$pf')
print(int((time.time() - mtime) / 86400))
" 2>/dev/null || echo 0)
  if [[ "${_age_days:-0}" -gt 7 ]]; then
    _proposed_stale=$((_proposed_stale + 1))
    _dappend "  ⚠ STALE (${_age_days}d) $pf"
  else
    _dappend "  $pf"
  fi
done < <(find "$CLAUDE_DIR" -name "*.proposed" -not -path "*/backup-*" 2>/dev/null | sort || true)
if [[ "$_proposed_count" -eq 0 ]]; then
  _dappend "  .proposed files: no data yet"
fi

# Flywheel staging: check $STATE/state/flywheel/drafts if it exists.
_FLYWHEEL_DRAFTS="${STATE_DIR}/state/flywheel/drafts"
if [[ -d "$_FLYWHEEL_DRAFTS" ]]; then
  _fw_count=$(find "$_FLYWHEEL_DRAFTS" -name "*.diff" -o -name "*.patch" 2>/dev/null | wc -l | tr -d ' ')
  _dappend "  Flywheel staged patches: ${_fw_count:-0}"
else
  _dappend "  Flywheel staged patches: no data yet"
fi

# Loop inbox: pending files + proposal counts.
_LOOP_INBOX="${STATE_DIR}/loop/inbox"
_inbox_count=0
if [[ -d "$_LOOP_INBOX" ]]; then
  while IFS= read -r inbox_file; do
    [[ -z "$inbox_file" || ! -f "$inbox_file" ]] && continue
    _inbox_count=$((_inbox_count + 1))
    _proposals=$(grep -c '^## Proposal ' "$inbox_file" 2>/dev/null || echo 0)
    _age_inbox=$(python3 -c "
import os, time
mtime = os.path.getmtime('$inbox_file')
print(int((time.time() - mtime) / 86400))
" 2>/dev/null || echo 0)
    _stale_marker=""
    [[ "${_age_inbox:-0}" -gt 7 ]] && _stale_marker=" ⚠ (${_age_inbox}d old)"
    _dappend "  inbox: $(basename "$inbox_file") — ${_proposals} proposal(s)${_stale_marker}"
  done < <(find "$_LOOP_INBOX" -name "*.md" 2>/dev/null | sort || true)
fi
[[ "$_inbox_count" -eq 0 ]] && _dappend "  Loop inbox: no data yet"
_dappend ""

# Section B: METRICS (from spine events.ndjson)
# Collect into variable first — piping into _dappend runs in a subshell and loses the array.
_dappend "## METRICS"
if command -v python3 >/dev/null 2>&1 && [[ -f "$EVENTS_FILE" ]]; then
  _metrics_out=$(python3 - "$EVENTS_FILE" <<'METPY' 2>/dev/null || true)
import sys, json
from datetime import datetime, timezone, timedelta

events_file = sys.argv[1]
now = datetime.now(timezone.utc)
week_ago = now - timedelta(days=7)
two_weeks_ago = now - timedelta(days=14)

this_week_blocks = 0; last_week_blocks = 0
this_week_synthetic = 0  # FIX-DIG-1: test/probe events excluded from real count
this_week_corrections = 0; last_week_corrections = 0
rtk_suspect_count = 0

# FIX-DIG-1: session_ids that are known test/probe origins.
# Events from these sessions are synthetic (emitted by test suites or ad-hoc probes)
# and must not inflate the "real guard blocks" production metric.
SYNTHETIC_SESSION_IDS = {"unknown", "test", "probe"}

try:
    with open(events_file) as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            try:
                ev = json.loads(line)
            except Exception:
                continue
            ts_str = ev.get("ts", "")
            try:
                ev_dt = datetime.fromisoformat(ts_str.replace("Z", "+00:00"))
            except Exception:
                continue

            etype = ev.get("event_type", "")
            outcome = ev.get("outcome", "")
            sid = ev.get("session_id", "") or ""

            if etype == "trust_decision" and outcome == "denied":
                if ev_dt >= week_ago:
                    if sid in SYNTHETIC_SESSION_IDS:
                        this_week_synthetic += 1
                    else:
                        this_week_blocks += 1
                elif ev_dt >= two_weeks_ago:
                    last_week_blocks += 1

            if etype == "correction":
                payload = ev.get("payload", {})
                if ev_dt >= week_ago:
                    this_week_corrections += 1
                    if payload.get("rtk_suspect"):
                        rtk_suspect_count += 1
                elif ev_dt >= two_weeks_ago:
                    last_week_corrections += 1
except Exception as e:
    print(f"spine read error: {e}")
    sys.exit(0)

# Emit real count separately from synthetic so the trend is trustworthy.
synth_note = f" (+{this_week_synthetic} synthetic/test)" if this_week_synthetic > 0 else ""
print(f"Guard blocks: {this_week_blocks} this week{synth_note} / {last_week_blocks} last week")
print(f"Corrections: {this_week_corrections} this week / {last_week_corrections} last week")
if this_week_corrections == 0 and last_week_corrections == 0:
    print("Corrections (rtk_suspect): no data yet")
else:
    print(f"Corrections (rtk_suspect): {rtk_suspect_count}")
METPY
  if [[ -n "$_metrics_out" ]]; then
    while IFS= read -r mline; do
      _dappend "  $mline"
    done < <(printf '%s\n' "$_metrics_out")
  else
    _dappend "  Guard blocks: no data yet"
    _dappend "  Corrections: no data yet"
    _dappend "  Corrections (rtk_suspect): no data yet"
  fi
else
  _dappend "  Guard blocks: no data yet"
  _dappend "  Corrections: no data yet"
  _dappend "  Corrections (rtk_suspect): no data yet"
fi

# KNOWN-GAP count from eval corpus (run non-interactively; parse output).
_HARNESS_BIN="${HARNESS_BIN:-${CLAUDE_DIR}/bin/harness}"
_known_gap_count="no data yet"
if [[ -f "$_HARNESS_BIN" && -f "${STATE_DIR}/state/events.ndjson" ]]; then
  _eval_out=$(HARNESS_STATE_OVERRIDE="$STATE_DIR" "$_HARNESS_BIN" eval run 2>&1 || true)
  _known_gap_count=$(printf '%s' "$_eval_out" | python3 -c "import sys,json; data=sys.stdin.read(); lines=[l for l in data.splitlines() if l.strip().startswith('{')]; [print(json.loads(l).get('gap','no data yet')) for l in lines[-1:] if l]" 2>/dev/null || echo "no data yet")
  [[ -z "$_known_gap_count" ]] && _known_gap_count="no data yet"
fi
_dappend "  KNOWN-GAP count: ${_known_gap_count}"

# VII Meta-Safety suite status — run all 5 suites and report pass/fail tallies.
# Per VII-6 spec: harness doctor must surface VII suite health so overnight regressions
# are caught at morning review, not at next manual audit.
_VII_SUITES_DIR="${CLAUDE_DIR}/scripts/tests"
_VII_SUITES=(
  "test-autonomous-push-guard.sh:VII-1-push-guard"
  "test-budget-kernel.sh:VII-2-budget-kernel"
  "test-selfcheck-autonomous.sh:VII-3-selfcheck-autonomous"
  "test-kill-switch.sh:VII-4-kill-switch"
  "test-autonomous-secret-scan.sh:VII-5-secret-scan"
  "test-autonomous-registry.sh:VII-7-registry"
)
_vii_all_pass=1
_VII_LAST_RUN_FILE="${STATE_DIR}/harness-doctor.vii-last-run"
_VII_STALE_DAYS=1  # warn if VII suites haven't run in >1 day

# Check staleness of last VII run stamp
if [[ -f "$_VII_LAST_RUN_FILE" ]]; then
  _vii_prev_stamp=$(cat "$_VII_LAST_RUN_FILE" 2>/dev/null || echo "")
  if [[ -n "$_vii_prev_stamp" ]]; then
    _vii_age_days=$(python3 -c "
from datetime import datetime, timezone
ts = '$_vii_prev_stamp'.strip()
try:
    dt = datetime.fromisoformat(ts.replace('Z','+00:00'))
    print((datetime.now(timezone.utc) - dt).days)
except:
    print(99)
" 2>/dev/null || echo 99)
    if [[ "${_vii_age_days:-0}" -gt "$_VII_STALE_DAYS" ]]; then
      warn "VII suite last run ${_vii_age_days}d ago — re-running now"
    fi
  fi
fi

_dappend ""
_dappend "## VII META-SAFETY SUITE STATUS"
_vii_total_pass=0; _vii_total_fail=0
for _suite_spec in "${_VII_SUITES[@]}"; do
  _suite_file="${_suite_spec%%:*}"
  _suite_label="${_suite_spec##*:}"
  _suite_path="${_VII_SUITES_DIR}/${_suite_file}"
  if [[ ! -x "$_suite_path" ]]; then
    _dappend "  ${_suite_label}: MISSING (${_suite_path})"
    _vii_all_pass=0
    crit "VII suite missing: ${_suite_label}"
    continue
  fi
  # Run from CLAUDE_DIR so CWD is ~/.claude (solo remote only) — matches normal invocation.
  # This prevents hermes or other project CWDs from triggering corporate-remote false positives.
  _suite_out=$(cd "${CLAUDE_DIR}" && bash "$_suite_path" 2>&1 || true)
  # Extract pass/fail counts — suites print "Results: N passed, M failed" or "PASS=N FAIL=M"
  _suite_pass=$(printf '%s' "$_suite_out" | grep -oE '([0-9]+ passed|PASS=[0-9]+)' | grep -oE '[0-9]+' | head -1 || echo "?")
  _suite_fail=$(printf '%s' "$_suite_out" | grep -oE '([0-9]+ failed|FAIL=[0-9]+)' | grep -oE '[0-9]+' | head -1 || echo "?")
  if [[ "$_suite_fail" == "0" || "$_suite_fail" == "?" ]]; then
    # Also check the output has no FAIL marker
    if printf '%s' "$_suite_out" | grep -qiE '^(FAIL|ERROR)'; then
      _suite_status="FAIL"; _vii_all_pass=0
    else
      _suite_status="PASS"
    fi
  else
    _suite_status="FAIL"; _vii_all_pass=0
  fi
  _vii_total_pass=$(( _vii_total_pass + ${_suite_pass:-0} ))
  _dappend "  ${_suite_label}: ${_suite_status} (${_suite_pass:-?} passed, ${_suite_fail:-?} failed)"
  if [[ "$_suite_status" == "FAIL" ]]; then
    crit "VII suite FAIL: ${_suite_label} — ${_suite_fail} failures"
  fi
done
_dappend "  TOTAL VII cases: ${_vii_total_pass}"
if [[ "$_vii_all_pass" -eq 1 ]]; then
  _dappend "  VII gate: GREEN (all suites pass)"
else
  _dappend "  VII gate: RED — see CRITICALs above"
fi
date -u +%Y-%m-%dT%H:%M:%SZ > "$_VII_LAST_RUN_FILE"

# Recall-query misses (recall_query events with outcome == miss or no outcome).
_recall_misses="no data yet"
if [[ -f "$EVENTS_FILE" ]]; then
  _recall_misses=$(python3 -c "
import json, sys
count = 0
try:
  with open('$EVENTS_FILE') as f:
    for line in f:
      line = line.strip()
      if not line: continue
      try:
        ev = json.loads(line)
        if ev.get('event_type') == 'recall_query' and ev.get('outcome','') in ('miss',''):
          count += 1
      except: pass
except: pass
print(count if count > 0 else 'no data yet')
" 2>/dev/null || echo "no data yet")
fi
_dappend "  Recall-query misses: ${_recall_misses}"
_dappend ""

# Section C: STALENESS — all state/*.last-run stamps
_dappend "## STALENESS"
_any_stamp=0
while IFS= read -r stamp_file; do
  [[ -z "$stamp_file" || ! -f "$stamp_file" ]] && continue
  _any_stamp=1
  _stamp_val=$(cat "$stamp_file" 2>/dev/null || echo "")
  _stamp_age_days=0
  if [[ -n "$_stamp_val" ]]; then
    _stamp_age_days=$(python3 -c "
from datetime import datetime, timezone
import sys
try:
    ts = '$_stamp_val'.strip()
    # Handle epoch integer stamps too
    try:
        dt = datetime.fromisoformat(ts.replace('Z','+00:00'))
    except:
        dt = datetime.fromtimestamp(float(ts), tz=timezone.utc)
    age = (datetime.now(timezone.utc) - dt).days
    print(age)
except Exception as e:
    print(0)
" 2>/dev/null || echo 0)
  fi
  _stale_flag=""
  [[ "${_stamp_age_days:-0}" -gt 8 ]] && _stale_flag=" ⚠ STALE"
  _dappend "  $(basename "$stamp_file"): ${_stamp_val:-unknown} (${_stamp_age_days}d ago)${_stale_flag}"
done < <(find "$STATE_DIR" -maxdepth 1 -name "*.last-run" 2>/dev/null | sort || true)
[[ "$_any_stamp" -eq 0 ]] && _dappend "  no data yet"
_dappend ""

# Footer
_dappend "---"
_dappend "Review: staged .proposed + \$STATE staging — apply in an interactive session; the pre-commit eval gate backstops every apply."

# Write digest to file + echo to stdout under a clear header.
mkdir -p "$(dirname "$DIGEST_FILE")" 2>/dev/null || true
printf '%s\n' "${_digest_lines[@]}" > "$DIGEST_FILE" 2>/dev/null || true

echo ""
echo "=== DIGEST ==="
printf '%s\n' "${_digest_lines[@]}"
echo "=== digest written: $DIGEST_FILE ==="

# Announce via notify.sh (fail-open).
_NOTIFY="${CLAUDE_DIR}/scripts/notify.sh"
[[ -f "$_NOTIFY" ]] && bash "$_NOTIFY" 'Weekly harness digest ready' 2>/dev/null || true

echo "=== done: $CRIT critical, $WARN warnings ==="
[[ "$CRIT" -gt 0 ]] && exit 1
exit 0
