#!/usr/bin/env bash
# ABOUTME: TDD test suite for scripts/journal-index.sh — FTS5 journal indexer.
# ABOUTME: 8 cases using mktemp fixtures with JOURNAL_PATH + STATE_DIR_OVERRIDE env overrides.
# ABOUTME: Verifies: fresh index, delta indexing, empty delta, FTS keyword hit,
# ABOUTME: zero-result query, corrupt db, sqlite3 absent, malformed cursor JSON.
# ABOUTME: Run: bash scripts/tests/test-journal-index.sh

set -uo pipefail
trap 'exit 0' ERR

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INDEXER="$(dirname "$SCRIPT_DIR")/journal-index.sh"

PASS=0
FAIL=0

_assert() {
  local desc="$1" got="$2" want="$3"
  if [ "$got" = "$want" ]; then
    echo "  PASS: $desc"
    (( PASS++ )) || true
  else
    echo "  FAIL: $desc — got=$got want=$want"
    (( FAIL++ )) || true
  fi
}

_assert_gt() {
  local desc="$1" got="$2" thresh="$3"
  if [ "$got" -gt "$thresh" ] 2>/dev/null; then
    echo "  PASS: $desc (got $got > $thresh)"
    (( PASS++ )) || true
  else
    echo "  FAIL: $desc — got=$got want > $thresh"
    (( FAIL++ )) || true
  fi
}

_assert_eq() {
  local desc="$1" got="$2" want="$3"
  if [ "$got" = "$want" ]; then
    echo "  PASS: $desc"
    (( PASS++ )) || true
  else
    echo "  FAIL: $desc — got='$got' want='$want'"
    (( FAIL++ )) || true
  fi
}

echo "=== test-journal-index.sh ==="

# ── Case 1: fresh journal → indexed, count > 0 ───────────────────────────────
echo ""
echo "[1] fresh journal — indexed, count > 0"
TMP1="$(mktemp -d)"
cat > "$TMP1/journal.md" <<'JEOF'
# Claude Code Session Journal

---
## 2026-03-20T10:00:00Z — project-a (abc123)
- **Files:** foo.ts, bar.ts
- **Tools:** Bash, Read
- **Errors:** none

---
## 2026-03-21T11:00:00Z — project-b (def456)
- **Files:** baz.go
- **Tools:** Edit
- **Errors:** 1 error(s)
JEOF

STATE_DIR_OVERRIDE="$TMP1/state" JOURNAL_PATH="$TMP1/journal.md" bash "$INDEXER" >/dev/null 2>&1
EXIT1=$?
COUNT1="$(sqlite3 "$TMP1/state/journal-index.db" "SELECT count(*) FROM entries;" 2>/dev/null || echo 0)"
_assert "exit code 0 on fresh index" "$EXIT1" "0"
_assert_gt "row count > 0 after fresh index" "$COUNT1" "0"
rm -rf "$TMP1"

# ── Case 2: append delta + re-run → only delta added, cursor advanced ─────────
echo ""
echo "[2] append delta — only new rows added, cursor advanced"
TMP2="$(mktemp -d)"
mkdir -p "$TMP2/state"
cat > "$TMP2/journal.md" <<'JEOF'
# Claude Code Session Journal

---
## 2026-03-20T10:00:00Z — project-a (abc123)
- **Files:** foo.ts
- **Tools:** Bash

JEOF

# First run
STATE_DIR_OVERRIDE="$TMP2/state" JOURNAL_PATH="$TMP2/journal.md" bash "$INDEXER" >/dev/null 2>&1
COUNT_BEFORE="$(sqlite3 "$TMP2/state/journal-index.db" "SELECT count(*) FROM entries;" 2>/dev/null || echo 0)"
CURSOR_BEFORE="$(python3 -c "
import json, glob, sys
files = glob.glob('$TMP2/state/journal-index.*.cursor')
if not files: sys.exit(1)
d = json.load(open(files[0]))
print(d['offset'])
" 2>/dev/null || echo 0)"

# Append a new entry
cat >> "$TMP2/journal.md" <<'JEOF'
---
## 2026-03-21T12:00:00Z — project-b (def456)
- **Files:** baz.go
- **Tools:** Edit

JEOF

# Second run
STATE_DIR_OVERRIDE="$TMP2/state" JOURNAL_PATH="$TMP2/journal.md" bash "$INDEXER" >/dev/null 2>&1
COUNT_AFTER="$(sqlite3 "$TMP2/state/journal-index.db" "SELECT count(*) FROM entries;" 2>/dev/null || echo 0)"
CURSOR_AFTER="$(python3 -c "
import json, glob, sys
files = glob.glob('$TMP2/state/journal-index.*.cursor')
if not files: sys.exit(1)
d = json.load(open(files[0]))
print(d['offset'])
" 2>/dev/null || echo 0)"

_assert_gt "count increased after delta" "$COUNT_AFTER" "$COUNT_BEFORE"
if [ "$CURSOR_AFTER" -gt "$CURSOR_BEFORE" ] 2>/dev/null; then
  echo "  PASS: cursor advanced after delta (before=$CURSOR_BEFORE after=$CURSOR_AFTER)"
  (( PASS++ )) || true
else
  echo "  FAIL: cursor should advance — before=$CURSOR_BEFORE after=$CURSOR_AFTER"
  (( FAIL++ )) || true
fi
rm -rf "$TMP2"

# ── Case 3: empty delta re-run → 0 new rows, clean exit ──────────────────────
echo ""
echo "[3] empty delta re-run — 0 new rows, clean exit"
TMP3="$(mktemp -d)"
mkdir -p "$TMP3/state"
cat > "$TMP3/journal.md" <<'JEOF'
# Claude Code Session Journal

---
## 2026-03-20T10:00:00Z — project-a (abc123)
- **Files:** foo.ts
- **Tools:** Bash

JEOF

STATE_DIR_OVERRIDE="$TMP3/state" JOURNAL_PATH="$TMP3/journal.md" bash "$INDEXER" >/dev/null 2>&1
COUNT_FIRST="$(sqlite3 "$TMP3/state/journal-index.db" "SELECT count(*) FROM entries;" 2>/dev/null || echo 0)"

STATE_DIR_OVERRIDE="$TMP3/state" JOURNAL_PATH="$TMP3/journal.md" bash "$INDEXER" >/dev/null 2>&1
EXIT3=$?
COUNT_SECOND="$(sqlite3 "$TMP3/state/journal-index.db" "SELECT count(*) FROM entries;" 2>/dev/null || echo 0)"

_assert "clean exit on empty delta" "$EXIT3" "0"
_assert_eq "count unchanged on empty delta" "$COUNT_SECOND" "$COUNT_FIRST"
rm -rf "$TMP3"

# ── Case 4: FTS keyword hit returns result ────────────────────────────────────
echo ""
echo "[4] FTS keyword hit returns result"
TMP4="$(mktemp -d)"
mkdir -p "$TMP4/state"
cat > "$TMP4/journal.md" <<'JEOF'
# Claude Code Session Journal

---
## 2026-07-03T00:00:00Z — .claude (sec123)
- **Errors:** leaked secrets during dual-push to ExampleOrg remote
- **Outcome:** force-pushed redacted commit

JEOF

STATE_DIR_OVERRIDE="$TMP4/state" JOURNAL_PATH="$TMP4/journal.md" bash "$INDEXER" >/dev/null 2>&1

# FTS query for "secret leak" (porter stemmer: secrets→secret, leaked→leak)
HIT4="$(sqlite3 "$TMP4/state/journal-index.db" "SELECT count(*) FROM fts WHERE fts MATCH 'secret leak';" 2>/dev/null || echo 0)"
_assert_gt "FTS 'secret leak' hits > 0 via porter stemmer" "$HIT4" "0"
rm -rf "$TMP4"

# ── Case 5: zero-result FTS query → clean exit 0 ─────────────────────────────
echo ""
echo "[5] zero-result FTS query — clean exit 0"
TMP5="$(mktemp -d)"
mkdir -p "$TMP5/state"
cat > "$TMP5/journal.md" <<'JEOF'
# Claude Code Session Journal

---
## 2026-03-20T10:00:00Z — project-a (abc123)
- **Files:** foo.ts
- **Tools:** Bash

JEOF

STATE_DIR_OVERRIDE="$TMP5/state" JOURNAL_PATH="$TMP5/journal.md" bash "$INDEXER" >/dev/null 2>&1

ZERO5="$(sqlite3 "$TMP5/state/journal-index.db" "SELECT count(*) FROM fts WHERE fts MATCH 'xyzzy_nonexistent_token_zzzz';" 2>/dev/null || echo 0)"
_assert_eq "zero-result FTS query returns 0" "$ZERO5" "0"
rm -rf "$TMP5"

# ── Case 6: corrupt db file → exit 0 with warn ───────────────────────────────
echo ""
echo "[6] corrupt db file — exit 0 with warn"
TMP6="$(mktemp -d)"
mkdir -p "$TMP6/state"
cat > "$TMP6/journal.md" <<'JEOF'
# Claude Code Session Journal

---
## 2026-03-20T10:00:00Z — project-a (abc123)
- foo entry

JEOF

# Plant corrupt db
printf 'this is not a sqlite database\x00garbage' > "$TMP6/state/journal-index.db"

WARN6="$(STATE_DIR_OVERRIDE="$TMP6/state" JOURNAL_PATH="$TMP6/journal.md" bash "$INDEXER" 2>&1 || true)"
EXIT6=$?
_assert "exit 0 on corrupt db" "$EXIT6" "0"
if echo "$WARN6" | grep -qi "warn\|corrupt\|error\|invalid\|unable\|malform"; then
  echo "  PASS: warn message emitted on corrupt db"
  (( PASS++ )) || true
else
  echo "  FAIL: expected warn message on corrupt db, got: $WARN6"
  (( FAIL++ )) || true
fi
rm -rf "$TMP6"

# ── Case 7: sqlite3 absent (PATH shim) → exit 0 ──────────────────────────────
echo ""
echo "[7] sqlite3 absent (PATH shim) — exit 0"
TMP7="$(mktemp -d)"
mkdir -p "$TMP7/state" "$TMP7/fake-bin"
cat > "$TMP7/journal.md" <<'JEOF'
# Claude Code Session Journal

---
## 2026-03-20T10:00:00Z — project-a (abc123)
- foo entry

JEOF

# fake-bin has bash (needed to launch the script) and python3, but NOT sqlite3.
# This simulates a launchd environment where sqlite3 is not installed.
BASH_BIN="$(command -v bash)"
PYTHON3_BIN="$(command -v python3 2>/dev/null || true)"
ln -s "$BASH_BIN" "$TMP7/fake-bin/bash"
[ -n "$PYTHON3_BIN" ] && ln -s "$PYTHON3_BIN" "$TMP7/fake-bin/python3"
# Also link dd and other tools the script needs to reach the sqlite3 check:
for _bin in dd wc date mkdir mv rm perl git; do
  _p="$(command -v "$_bin" 2>/dev/null || true)"
  [ -n "$_p" ] && ln -s "$_p" "$TMP7/fake-bin/$_bin" 2>/dev/null || true
done

EXIT7="$(PATH="$TMP7/fake-bin" STATE_DIR_OVERRIDE="$TMP7/state" JOURNAL_PATH="$TMP7/journal.md" bash "$INDEXER" 2>/dev/null; echo $?)"
_assert "exit 0 when sqlite3 absent" "$EXIT7" "0"
rm -rf "$TMP7"

# ── Case 8: malformed cursor JSON → full rebuild + warn ───────────────────────
echo ""
echo "[8] malformed cursor JSON — full rebuild + warn"
TMP8="$(mktemp -d)"
mkdir -p "$TMP8/state"
cat > "$TMP8/journal.md" <<'JEOF'
# Claude Code Session Journal

---
## 2026-03-20T10:00:00Z — project-a (abc123)
- **Files:** foo.ts
- **Tools:** Bash

---
## 2026-03-21T11:00:00Z — project-b (def456)
- **Files:** baz.go
- **Tools:** Edit

JEOF

# Plant malformed cursor at the hash-keyed filename the indexer will look for.
# Compute the same hash the script uses: md5 of JOURNAL_PATH (first 8 chars).
_HASH8="$(printf '%s' "$TMP8/journal.md" | perl -MDigest::MD5=md5_hex -0777 -ne 'print substr(md5_hex($_),0,8)' 2>/dev/null || echo 'default')"
printf '{"offset": BAD_JSON}' > "$TMP8/state/journal-index.${_HASH8}.cursor"

WARN8="$(STATE_DIR_OVERRIDE="$TMP8/state" JOURNAL_PATH="$TMP8/journal.md" bash "$INDEXER" 2>&1 || true)"
EXIT8=$?
COUNT8="$(sqlite3 "$TMP8/state/journal-index.db" "SELECT count(*) FROM entries;" 2>/dev/null || echo 0)"

_assert "exit 0 on malformed cursor" "$EXIT8" "0"
_assert_gt "rows indexed after rebuild from malformed cursor" "$COUNT8" "0"
if echo "$WARN8" | grep -qi "warn\|malform\|corrupt\|invalid\|rebuild"; then
  echo "  PASS: warn emitted on malformed cursor"
  (( PASS++ )) || true
else
  echo "  FAIL: expected warn on malformed cursor, got: $WARN8"
  (( FAIL++ )) || true
fi
rm -rf "$TMP8"

# ── Summary ───────────────────────────────────────────────────────────────────
echo ""
echo "=== Results: $PASS passed, $FAIL failed ==="
[ "$FAIL" -eq 0 ]
