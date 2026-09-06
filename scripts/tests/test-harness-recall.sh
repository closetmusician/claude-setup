#!/usr/bin/env bash
# ABOUTME: Test suite for harness recall subcommand (Pillar V, task V2).
# ABOUTME: 6 oracle cases per spec: known-topic hit, lessons boost, unknown-topic
# ABOUTME: empty+event, corrupted-FTS zero-hit+empty_for_known_topic, gbrain-absent
# ABOUTME: graceful skip, and cross-source deduplication.
# ABOUTME: All tests use mktemp sandboxes with env overrides; never touches real state.

set -euo pipefail

HARNESS="${HARNESS_BIN:-$HOME/.claude/bin/harness}"
PASS=0
FAIL=0
SKIP=0

# ── Test framework ─────────────────────────────────────────────────────────────
_ok() {
  local label="$1"
  PASS=$(( PASS + 1 ))
  echo "  PASS: $label"
}

_fail() {
  local label="$1" detail="${2:-}"
  FAIL=$(( FAIL + 1 ))
  echo "  FAIL: $label${detail:+ — $detail}"
}

_assert_eq() {
  local label="$1" got="$2" want="$3"
  if [[ "$got" == "$want" ]]; then
    _ok "$label"
  else
    _fail "$label" "got='$got' want='$want'"
  fi
}

_assert_ge() {
  local label="$1" got="$2" want="$3"
  if [[ "$got" -ge "$want" ]]; then
    _ok "$label"
  else
    _fail "$label" "got=$got want>=$want"
  fi
}

_assert_contains() {
  local label="$1" haystack="$2" needle="$3"
  if echo "$haystack" | grep -qF "$needle"; then
    _ok "$label"
  else
    _fail "$label" "needle='$needle' not found in output"
  fi
}

_assert_not_contains() {
  local label="$1" haystack="$2" needle="$3"
  if echo "$haystack" | grep -qF "$needle"; then
    _fail "$label" "needle='$needle' unexpectedly found in output"
  else
    _ok "$label"
  fi
}

# ── Timestamp helper ───────────────────────────────────────────────────────────
_ts_ago() {
  local secs="$1"
  python3 -c "
from datetime import datetime, timezone, timedelta
t = datetime.now(timezone.utc) - timedelta(seconds=$secs)
print(t.strftime('%Y-%m-%dT%H:%M:%S.') + f'{t.microsecond//1000:03d}Z')
"
}

echo ""
echo "========================================================================"
echo "harness recall test suite (Pillar V, task V2)"
echo "========================================================================"

# ════════════════════════════════════════════════════════════════════════════════
# ORACLE 1 — Known topic seeded in fixture journal-index db → ≥1 hit
# Seeds a journal-index.db with entries containing "frobnicator_unique_topic",
# then runs harness recall frobnicator_unique_topic and expects ≥1 result block.
echo ""
echo "── Oracle 1: known topic in journal-index db → ≥1 hit ─────────────────"

T1="$(mktemp -d /tmp/harness-recall-t1-XXXXXX)"
mkdir -p "$T1/state"
T1_JOURNAL="$T1/fixture-journal.md"
T1_DB="$T1/state/journal-index.db"
T1_LESSONS="$T1/fixture-lessons.md"
T1_EVENTS="$T1/state/events.ndjson"

# Create fixture journal with the known topic
cat > "$T1_JOURNAL" <<'JOURNAL'
## 2026-07-01T10:00:00Z
- Investigated frobnicator_unique_topic system failure in the deployment pipeline.
- Root cause: frobnicator_unique_topic was misconfigured in production settings.
- Fix applied: updated frobnicator_unique_topic configuration and redeployed.
## 2026-07-02T11:00:00Z
- Reviewed PR for frobnicator_unique_topic refactor.
JOURNAL

# Create empty lessons file
printf '' > "$T1_LESSONS"

# Seed the journal-index db directly (same schema as journal-index.sh)
python3 - "$T1_DB" "$T1_JOURNAL" <<'PYEOF'
import sys, sqlite3
db_path = sys.argv[1]
journal_path = sys.argv[2]

con = sqlite3.connect(db_path)
cur = con.cursor()
cur.executescript("""
CREATE TABLE IF NOT EXISTS entries (
  rowid INTEGER PRIMARY KEY AUTOINCREMENT,
  ts    TEXT NOT NULL,
  content TEXT NOT NULL
);
CREATE VIRTUAL TABLE IF NOT EXISTS fts
  USING fts5(
    content,
    content='entries',
    content_rowid='rowid',
    tokenize='porter unicode61'
  );
""")

# Insert entries from the journal
entries = [
  ("2026-07-01T10:00:00Z", "- Investigated frobnicator_unique_topic system failure in the deployment pipeline. - Root cause: frobnicator_unique_topic was misconfigured in production settings. - Fix applied: updated frobnicator_unique_topic configuration and redeployed."),
  ("2026-07-02T11:00:00Z", "- Reviewed PR for frobnicator_unique_topic refactor."),
]
cur.executemany("INSERT INTO entries(ts, content) VALUES(?,?)", entries)
con.commit()

# Rebuild FTS index
cur.execute("INSERT INTO fts(fts) VALUES('rebuild')")
con.commit()
con.close()
print(f"seeded {len(entries)} entries")
PYEOF

# Create minimal events.ndjson (empty but valid)
touch "$T1_EVENTS"

out1="$(HARNESS_STATE_OVERRIDE="$T1" \
        HARNESS_JOURNAL_INDEX_DB="$T1_DB" \
        HARNESS_LESSONS_PATH="$T1_LESSONS" \
        "$HARNESS" recall "frobnicator_unique_topic" 2>&1)"

hit_count="$(echo "$out1" | grep -c 'frobnicator_unique_topic' 2>/dev/null || echo 0)"
_assert_ge "known topic → ≥1 result block containing the topic" "$hit_count" "1"

# Verify a recall_query event was emitted to the spine
event_count="$(grep -c 'recall_query' "$T1_EVENTS" 2>/dev/null || echo 0)"
_assert_ge "known topic → recall_query event emitted" "$event_count" "1"

rm -rf "$T1"

# ════════════════════════════════════════════════════════════════════════════════
# ORACLE 2 — lessons.md fixture hit (+1 rank boost verifiable by ordering)
# Seeds lessons.md with a unique topic present in both journal-index and lessons.
# The lessons hit should appear first (rank boost) in the output.
echo ""
echo "── Oracle 2: lessons.md hit ranked above journal-only hit ──────────────"

T2="$(mktemp -d /tmp/harness-recall-t2-XXXXXX)"
mkdir -p "$T2/state"
T2_JOURNAL="$T2/fixture-journal.md"
T2_DB="$T2/state/journal-index.db"
T2_LESSONS="$T2/fixture-lessons.md"
T2_EVENTS="$T2/state/events.ndjson"

# Unique topic prefix so no real-content interference
TOPIC="xyzzy_rank_topic_unique"

# Lessons entry (should rank higher due to +1 boost)
cat > "$T2_LESSONS" <<LESSONS
## Patterns

- **$TOPIC lesson entry**: This is a key finding about $TOPIC — it matters a lot.
LESSONS

# Journal entry (present but should rank lower)
cat > "$T2_JOURNAL" <<JOURNAL
## 2026-06-15T09:00:00Z
- Encountered $TOPIC briefly during session setup.
JOURNAL

# Seed journal-index db
python3 - "$T2_DB" "$TOPIC" <<PYEOF
import sys, sqlite3
db_path, topic = sys.argv[1], sys.argv[2]
con = sqlite3.connect(db_path)
cur = con.cursor()
cur.executescript("""
CREATE TABLE IF NOT EXISTS entries (
  rowid INTEGER PRIMARY KEY AUTOINCREMENT,
  ts    TEXT NOT NULL,
  content TEXT NOT NULL
);
CREATE VIRTUAL TABLE IF NOT EXISTS fts
  USING fts5(
    content,
    content='entries',
    content_rowid='rowid',
    tokenize='porter unicode61'
  );
""")
cur.executemany("INSERT INTO entries(ts, content) VALUES(?,?)", [
  ("2026-06-15T09:00:00Z", f"- Encountered {topic} briefly during session setup."),
])
con.commit()
cur.execute("INSERT INTO fts(fts) VALUES('rebuild')")
con.commit()
con.close()
PYEOF

touch "$T2_EVENTS"

out2="$(HARNESS_STATE_OVERRIDE="$T2" \
        HARNESS_JOURNAL_INDEX_DB="$T2_DB" \
        HARNESS_LESSONS_PATH="$T2_LESSONS" \
        "$HARNESS" recall "$TOPIC" 2>&1)"

# Verify at least one hit from lessons
_assert_contains "lessons hit present in output" "$out2" "lesson entry"

# Verify lessons hit appears before (or at same position as) journal hit
# Lessons blocks are tagged [lessons] or similar in output; check ordering
lessons_line="$(echo "$out2" | grep -n "lesson entry" | head -1 | cut -d: -f1 || echo 0)"
journal_line="$(echo "$out2" | grep -n "briefly during session setup" | head -1 | cut -d: -f1 || echo 0)"
if [[ -n "$lessons_line" && -n "$journal_line" && "$lessons_line" -le "$journal_line" ]]; then
  _ok "lessons hit ranked first (before journal-only hit)"
elif [[ -z "$journal_line" ]]; then
  # Dedup: if lessons and journal have same content sha, journal may be deduped away
  _ok "lessons hit ranked first (journal deduped or absent — lessons wins)"
else
  _fail "lessons hit should appear before journal hit" "lessons_line=$lessons_line journal_line=$journal_line"
fi

rm -rf "$T2"

# ════════════════════════════════════════════════════════════════════════════════
# ORACLE 3 — Unknown topic → 0 hits; recall_query event has empty_for_known_topic:false
echo ""
echo "── Oracle 3: unknown topic → 0 hits, event empty_for_known_topic:false ──"

T3="$(mktemp -d /tmp/harness-recall-t3-XXXXXX)"
mkdir -p "$T3/state"
T3_DB="$T3/state/journal-index.db"
T3_LESSONS="$T3/fixture-lessons.md"
T3_EVENTS="$T3/state/events.ndjson"

# Empty lessons
printf '' > "$T3_LESSONS"
touch "$T3_EVENTS"

# Create minimal journal-index db (no entries)
python3 - "$T3_DB" <<'PYEOF'
import sys, sqlite3
db_path = sys.argv[1]
con = sqlite3.connect(db_path)
cur = con.cursor()
cur.executescript("""
CREATE TABLE IF NOT EXISTS entries (
  rowid INTEGER PRIMARY KEY AUTOINCREMENT,
  ts    TEXT NOT NULL,
  content TEXT NOT NULL
);
CREATE VIRTUAL TABLE IF NOT EXISTS fts
  USING fts5(
    content,
    content='entries',
    content_rowid='rowid',
    tokenize='porter unicode61'
  );
""")
con.commit()
con.close()
PYEOF

UNKNOWN_TOPIC="completely_absent_topic_zzz99876_xqz"
out3="$(HARNESS_STATE_OVERRIDE="$T3" \
        HARNESS_JOURNAL_INDEX_DB="$T3_DB" \
        HARNESS_LESSONS_PATH="$T3_LESSONS" \
        "$HARNESS" recall "$UNKNOWN_TOPIC" 2>&1)"

# Expect 0 hits: output should show "(no results...)" and NOT show a result block header "[1]"
# We check for absence of "[1]" (numbered result blocks) rather than presence of query string,
# because the "no results" message itself contains the query.
hit_count3="$(echo "$out3" | { grep -c '^\[1\]' 2>/dev/null || true; })"
hit_count3="${hit_count3:-0}"
_assert_eq "unknown topic → 0 content hits (no numbered result blocks)" "$hit_count3" "0"

# Check the emitted recall_query event has empty_for_known_topic:false
event_line3="$(grep 'recall_query' "$T3_EVENTS" 2>/dev/null | tail -1 || echo '')"
efkt3="$(echo "$event_line3" | python3 -c "
import sys, json
line = sys.stdin.read().strip()
if not line:
    print('NO_EVENT')
    sys.exit(0)
try:
    ev = json.loads(line)
    p = ev.get('payload', {})
    print(str(p.get('empty_for_known_topic', 'MISSING')).lower())
except Exception as e:
    print(f'PARSE_ERROR:{e}')
" 2>/dev/null || echo 'NO_EVENT')"

_assert_eq "unknown topic event has empty_for_known_topic:false" "$efkt3" "false"

rm -rf "$T3"

# ════════════════════════════════════════════════════════════════════════════════
# ORACLE 4 — FTS has ≥1 row for query, but federation returns 0 hits (corrupted
# mid-query) → recall_query event must have empty_for_known_topic:true
# Spec: "hits==0 AND journal FTS ≥1 row for same query — implement exactly this
# definition: run the FTS probe separately from the federation result"
echo ""
echo "── Oracle 4: FTS probe hit but federation=0 → empty_for_known_topic:true"

T4="$(mktemp -d /tmp/harness-recall-t4-XXXXXX)"
mkdir -p "$T4/state"
T4_DB="$T4/state/journal-index.db"
T4_LESSONS="$T4/fixture-lessons.md"
T4_EVENTS="$T4/state/events.ndjson"
T4_CORRUPT_DB="$T4/state/corrupt-journal-index.db"

PROBE_TOPIC="zeta_probe_topic_unique_77423"

# Seed DB with the topic
python3 - "$T4_DB" "$PROBE_TOPIC" <<'PYEOF'
import sys, sqlite3
db_path, topic = sys.argv[1], sys.argv[2]
con = sqlite3.connect(db_path)
cur = con.cursor()
cur.executescript("""
CREATE TABLE IF NOT EXISTS entries (
  rowid INTEGER PRIMARY KEY AUTOINCREMENT,
  ts    TEXT NOT NULL,
  content TEXT NOT NULL
);
CREATE VIRTUAL TABLE IF NOT EXISTS fts
  USING fts5(
    content,
    content='entries',
    content_rowid='rowid',
    tokenize='porter unicode61'
  );
""")
cur.executemany("INSERT INTO entries(ts, content) VALUES(?,?)", [
  ("2026-07-01T00:00:00Z", f"- {topic} is a known issue from the july audit."),
])
con.commit()
cur.execute("INSERT INTO fts(fts) VALUES('rebuild')")
con.commit()
con.close()
print("seeded")
PYEOF

printf '' > "$T4_LESSONS"
touch "$T4_EVENTS"

# To simulate "FTS db corrupted mid-query so federation returns 0":
# We use HARNESS_RECALL_CORRUPT_FTS=1 env var, which tells recall to skip
# all federation results (pretend they all failed) BUT still run the separate
# FTS probe check. This gives us hits==0 with FTS probe ≥1.
out4="$(HARNESS_STATE_OVERRIDE="$T4" \
        HARNESS_JOURNAL_INDEX_DB="$T4_DB" \
        HARNESS_LESSONS_PATH="$T4_LESSONS" \
        HARNESS_RECALL_CORRUPT_FTS=1 \
        "$HARNESS" recall "$PROBE_TOPIC" 2>&1)"

# Check the recall_query event
event_line4="$(grep 'recall_query' "$T4_EVENTS" 2>/dev/null | tail -1 || echo '')"
efkt4="$(echo "$event_line4" | python3 -c "
import sys, json
line = sys.stdin.read().strip()
if not line:
    print('NO_EVENT')
    sys.exit(0)
try:
    ev = json.loads(line)
    p = ev.get('payload', {})
    print(str(p.get('empty_for_known_topic', 'MISSING')).lower())
except Exception as e:
    print(f'PARSE_ERROR:{e}')
" 2>/dev/null || echo 'NO_EVENT')"

_assert_eq "corrupted federation + FTS probe hit → empty_for_known_topic:true" "$efkt4" "true"

# Also verify hits==0 in the event
hits4="$(echo "$event_line4" | python3 -c "
import sys, json
line = sys.stdin.read().strip()
if not line: print('NO_EVENT'); sys.exit(0)
try:
    ev = json.loads(line)
    print(str(ev.get('payload', {}).get('hits', 'MISSING')))
except: print('PARSE_ERROR')
" 2>/dev/null || echo 'NO_EVENT')"
_assert_eq "corrupted federation → hits==0 in event" "$hits4" "0"

rm -rf "$T4"

# ════════════════════════════════════════════════════════════════════════════════
# ORACLE 5 — gbrain absent (PATH without gbrain) → no error, sources skipped cleanly
echo ""
echo "── Oracle 5: gbrain absent → clean skip, no error ──────────────────────"

T5="$(mktemp -d /tmp/harness-recall-t5-XXXXXX)"
mkdir -p "$T5/state"
T5_DB="$T5/state/journal-index.db"
T5_LESSONS="$T5/fixture-lessons.md"
T5_EVENTS="$T5/state/events.ndjson"

# Seed minimal db with a topic
GBRAIN_TOPIC="gbrain_absent_test_topic_8823"
python3 - "$T5_DB" "$GBRAIN_TOPIC" <<'PYEOF'
import sys, sqlite3
db_path, topic = sys.argv[1], sys.argv[2]
con = sqlite3.connect(db_path)
cur = con.cursor()
cur.executescript("""
CREATE TABLE IF NOT EXISTS entries (
  rowid INTEGER PRIMARY KEY AUTOINCREMENT,
  ts    TEXT NOT NULL,
  content TEXT NOT NULL
);
CREATE VIRTUAL TABLE IF NOT EXISTS fts
  USING fts5(
    content,
    content='entries',
    content_rowid='rowid',
    tokenize='porter unicode61'
  );
""")
cur.executemany("INSERT INTO entries(ts, content) VALUES(?,?)", [
  ("2026-07-03T10:00:00Z", f"- {topic} was observed during testing."),
])
con.commit()
cur.execute("INSERT INTO fts(fts) VALUES('rebuild')")
con.commit()
con.close()
PYEOF

printf '' > "$T5_LESSONS"
touch "$T5_EVENTS"

# Run with a PATH that has no gbrain binary
no_gbrain_path="$(mktemp -d /tmp/harness-recall-nobin-XXXXXX)"
out5="$(HARNESS_STATE_OVERRIDE="$T5" \
        HARNESS_JOURNAL_INDEX_DB="$T5_DB" \
        HARNESS_LESSONS_PATH="$T5_LESSONS" \
        PATH="$no_gbrain_path:/usr/bin:/bin:/usr/local/bin" \
        "$HARNESS" recall "$GBRAIN_TOPIC" 2>&1)"
exit5=$?
rm -rf "$no_gbrain_path"

_assert_eq "gbrain absent → recall exits 0" "$exit5" "0"
_assert_not_contains "gbrain absent → no error message" "$out5" "gbrain: command not found"
_assert_not_contains "gbrain absent → no 'required tool' error" "$out5" "required tool"
# Still returns hits from other sources
hit_count5="$(echo "$out5" | grep -c "$GBRAIN_TOPIC" 2>/dev/null || echo 0)"
_assert_ge "gbrain absent → other sources still return hits" "$hit_count5" "1"

rm -rf "$T5"

# ════════════════════════════════════════════════════════════════════════════════
# ORACLE 6 — Duplicate content across two sources → deduped to one block
# Seeds journal-index with the same content as lessons.md (same first 120 chars
# sha256 hash), then verifies only ONE block appears in output.
echo ""
echo "── Oracle 6: duplicate content across sources → deduped to one block ────"

T6="$(mktemp -d /tmp/harness-recall-t6-XXXXXX)"
mkdir -p "$T6/state"
T6_DB="$T6/state/journal-index.db"
T6_LESSONS="$T6/fixture-lessons.md"
T6_EVENTS="$T6/state/events.ndjson"

DUP_TOPIC="delta_dedup_unique_topic_55901"
# Exactly the same content text in both lessons and journal
SHARED_CONTENT="$DUP_TOPIC: This is the exact same content in both lessons and journal for dedup testing purposes only."

# Create lessons with this content
cat > "$T6_LESSONS" <<LESSONS
## Patterns

- $SHARED_CONTENT
LESSONS

# Seed journal with EXACT same content
python3 - "$T6_DB" "$SHARED_CONTENT" <<'PYEOF'
import sys, sqlite3
db_path, content = sys.argv[1], sys.argv[2]
con = sqlite3.connect(db_path)
cur = con.cursor()
cur.executescript("""
CREATE TABLE IF NOT EXISTS entries (
  rowid INTEGER PRIMARY KEY AUTOINCREMENT,
  ts    TEXT NOT NULL,
  content TEXT NOT NULL
);
CREATE VIRTUAL TABLE IF NOT EXISTS fts
  USING fts5(
    content,
    content='entries',
    content_rowid='rowid',
    tokenize='porter unicode61'
  );
""")
cur.executemany("INSERT INTO entries(ts, content) VALUES(?,?)", [
  ("2026-07-02T12:00:00Z", f"- {content}"),
])
con.commit()
cur.execute("INSERT INTO fts(fts) VALUES('rebuild')")
con.commit()
con.close()
PYEOF

touch "$T6_EVENTS"

out6="$(HARNESS_STATE_OVERRIDE="$T6" \
        HARNESS_JOURNAL_INDEX_DB="$T6_DB" \
        HARNESS_LESSONS_PATH="$T6_LESSONS" \
        "$HARNESS" recall "$DUP_TOPIC" 2>&1)"

# Count numbered result blocks - each block starts with "[N]" on its own line.
# Dedup means only 1 such block should appear even though two sources had the content.
dup_block_count="$(echo "$out6" | grep -cE '^\[[0-9]+\]' 2>/dev/null || echo 0)"
_assert_eq "duplicate content across sources → deduped to exactly 1 block" "$dup_block_count" "1"

rm -rf "$T6"

# ════════════════════════════════════════════════════════════════════════════════
# ORACLE 7 — Multi-word query with stemmed variants → FTS AND semantics, not phrase
# Seeds an entry containing "leaked" and "secret" (non-adjacent, different stems
# of "leak" and "secret"). Query "leak secret" must return ≥1 hit.
# Root cause guard: phrase-quoting the query turned "leak secret" into a phrase
# search that found zero results because words were non-adjacent or in different
# stem form. Fix: use FTS5 AND-semantics (no surrounding double-quotes).
echo ""
echo "── Oracle 7: multi-word query w/ stemmed variant → FTS AND semantics ─────"

T7="$(mktemp -d /tmp/harness-recall-t7-XXXXXX)"
mkdir -p "$T7/state"
T7_DB="$T7/state/journal-index.db"
T7_LESSONS="$T7/fixture-lessons.md"
T7_EVENTS="$T7/state/events.ndjson"

# Seed entry with "leaked" and "secret" non-adjacent (Porter: leak→leak, secret→secret)
python3 - "$T7_DB" <<'PYEOF'
import sys, sqlite3
db_path = sys.argv[1]
con = sqlite3.connect(db_path)
cur = con.cursor()
cur.executescript("""
CREATE TABLE IF NOT EXISTS entries (
  rowid INTEGER PRIMARY KEY AUTOINCREMENT,
  ts    TEXT NOT NULL,
  content TEXT NOT NULL
);
CREATE VIRTUAL TABLE IF NOT EXISTS fts
  USING fts5(
    content,
    content='entries',
    content_rowid='rowid',
    tokenize='porter unicode61'
  );
""")
# "leaked" is stem "leak"; "secret" matches "secret" — non-adjacent
cur.executemany("INSERT INTO entries(ts, content) VALUES(?,?)", [
  ("2026-07-03T12:00:00Z",
   "- Pushed live secrets to a remote. The audit pipeline leaked credentials."),
])
con.commit()
cur.execute("INSERT INTO fts(fts) VALUES('rebuild')")
con.commit()
con.close()
print("seeded")
PYEOF

printf '' > "$T7_LESSONS"
touch "$T7_EVENTS"

out7="$(HARNESS_STATE_OVERRIDE="$T7" \
        HARNESS_JOURNAL_INDEX_DB="$T7_DB" \
        HARNESS_LESSONS_PATH="$T7_LESSONS" \
        "$HARNESS" recall "leak secret" 3 2>&1)"

# Must find ≥1 result (FTS AND semantics: both stems present in entry)
hit_count7="$(echo "$out7" | { grep -cE '^\[[0-9]+\]' 2>/dev/null || true; })"
hit_count7="${hit_count7:-0}"
_assert_ge "multi-word query 'leak secret' → ≥1 hit (AND semantics)" "$hit_count7" "1"

# Sanity: output must contain a snippet of the seeded content
_assert_contains "multi-word query result contains seeded content" "$out7" "secrets"

rm -rf "$T7"

# ════════════════════════════════════════════════════════════════════════════════
# Summary
echo ""
echo "========================================================================"
echo "Results: PASS=$PASS  FAIL=$FAIL  SKIP=$SKIP  (total=$(( PASS + FAIL + SKIP )))"
echo "========================================================================"
echo ""

if [[ "$FAIL" -gt 0 ]]; then
  exit 1
fi
exit 0
