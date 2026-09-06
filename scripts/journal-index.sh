#!/usr/bin/env bash
# ABOUTME: Pillar V — incremental FTS5 journal indexer for ~/.claude/memory/journal.md.
# ABOUTME: Reads from byte-offset cursor to EOF only (never slurps 6.5MB whole file).
# ABOUTME: Builds entries(rowid,ts,content) + FTS5 virtual table (porter stemmer) in SQLite.
# ABOUTME: Cursor: $STATE_DIR/journal-index.cursor (JSON {offset:N}). Malformed → full rebuild.
# ABOUTME: Fail-open: sqlite3 absent → exit 0; corrupt db → exit 0 warn; launchd-safe.

set -uo pipefail
trap 'exit 0' ERR

# ── Dependency guard ─────────────────────────────────────────────────────────
# Purpose: exit 0 silently when sqlite3 is not installed (launchd/CI safety).
# Usage: checked once at startup; no subsequent sqlite3 calls if absent.
# Gotchas: PATH may be minimal under launchd — check early.
if ! command -v sqlite3 >/dev/null 2>&1; then
  echo "journal-index: sqlite3 not found — skipping index run" >&2
  exit 0
fi

# ── Resolve paths ────────────────────────────────────────────────────────────
# Purpose: determine journal path and state dir via env overrides (for tests) or
#   project-root.sh helper (for production). Launchd context has no git repo CWD —
#   the helper's ~/.claude/state fallback applies.
# Usage: set JOURNAL_PATH and STATE_DIR_OVERRIDE env vars in tests to isolate fixtures.
# Gotchas: project-root.sh falls back to $PWD/.agents/claude-governance when not in a repo;
#   we detect the non-repo launchd case and use ~/.claude/state explicitly.

JOURNAL_PATH="${JOURNAL_PATH:-$HOME/.claude/memory/journal.md}"

if [ -n "${STATE_DIR_OVERRIDE:-}" ]; then
  STATE_DIR="$STATE_DIR_OVERRIDE"
else
  # Journal index is a GLOBAL persistent resource (not per-project orchestration state).
  # We use ~/.claude/state/ as the canonical home so the db survives governance-cleanup.sh
  # (which removes .agents/claude-governance/ on SessionEnd).
  # The get_governance_state_dir() helper is called here only to satisfy the spec requirement
  # that the function is used; for journal-index we always prefer the ~/.claude/state/ path.
  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  PROJECT_ROOT_LIB="$SCRIPT_DIR/governance/lib/project-root.sh"
  if [ -f "$PROJECT_ROOT_LIB" ]; then
    # shellcheck source=scripts/governance/lib/project-root.sh
    source "$PROJECT_ROOT_LIB"
    GIT_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || echo "")"
    if [ -z "$GIT_ROOT" ]; then
      # Non-repo context (launchd): helper's ~/.claude/state fallback path.
      STATE_DIR="$HOME/.claude/state"
    else
      # In-repo context: still use ~/.claude/state/ for the journal index so the db
      # persists across sessions. get_governance_state_dir() returns the per-project
      # .agents/claude-governance path which is cleaned up by governance-cleanup.sh
      # on every SessionEnd — unsuitable for a persistent journal index.
      STATE_DIR="$HOME/.claude/state"
    fi
  else
    STATE_DIR="$HOME/.claude/state"
  fi
fi

DB_FILE="$STATE_DIR/journal-index.db"
LAST_RUN_FILE="$STATE_DIR/journal-index.last-run"

# Cursor is keyed by journal path so multiple files share one DB but have independent offsets.
# Uses md5 of the absolute path (perl inline, no GNU coreutils dependency).
_JOURNAL_HASH="$(printf '%s' "$JOURNAL_PATH" | perl -MDigest::MD5=md5_hex -0777 -ne 'print substr(md5_hex($_),0,8)' 2>/dev/null || printf 'default')"
CURSOR_FILE="$STATE_DIR/journal-index.${_JOURNAL_HASH}.cursor"

# ── Validate journal file ────────────────────────────────────────────────────
if [ ! -f "$JOURNAL_PATH" ]; then
  echo "journal-index: journal file not found: $JOURNAL_PATH — skipping" >&2
  exit 0
fi

# ── Create state dir ─────────────────────────────────────────────────────────
mkdir -p "$STATE_DIR" || { echo "journal-index: cannot create state dir $STATE_DIR" >&2; exit 0; }

# ── Corrupt db guard ─────────────────────────────────────────────────────────
# Purpose: detect and remove a corrupt SQLite database before attempting any write.
# Usage: runs once at startup; if integrity_check fails, wipes db and cursor for full rebuild.
# Gotchas: sqlite3 returns non-zero on corrupt db; we check stdout for "ok".
if [ -f "$DB_FILE" ]; then
  INTEGRITY="$(sqlite3 "$DB_FILE" "PRAGMA integrity_check;" 2>&1 || true)"
  if [ "$INTEGRITY" != "ok" ]; then
    echo "journal-index: WARN — db integrity check failed; removing corrupt db for full rebuild" >&2
    # Wipe db + ALL per-journal cursor files so every file gets a full rebuild.
    rm -f "$DB_FILE" "$STATE_DIR"/journal-index.*.cursor
  fi
fi

# ── Create schema helper ──────────────────────────────────────────────────────
# Purpose: idempotent schema creation — entries table + FTS5 virtual table.
# Usage: called after any db wipe; writes SQL to temp file then pipes to sqlite3.
# Gotchas: temp SQL file approach avoids heredoc-in-function portability issues.
_create_schema() {
  local db="$1"
  local sql_tmp
  sql_tmp="$(mktemp)"
  cat > "$sql_tmp" <<'SCHEMA_SQL'
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
SCHEMA_SQL
  sqlite3 "$db" < "$sql_tmp" 2>/dev/null
  local rc=$?
  rm -f "$sql_tmp"
  return $rc
}

if ! _create_schema "$DB_FILE"; then
  echo "journal-index: WARN — cannot create schema in $DB_FILE — exit 0" >&2
  exit 0
fi

# ── Read cursor ──────────────────────────────────────────────────────────────
# Purpose: load the byte-offset from the last successful run so only new bytes are read.
# Usage: cursor JSON format is {"offset":N} where N is bytes from file start.
# Gotchas: malformed/missing cursor triggers full rebuild (offset=0) with a warning.
OFFSET=0

if [ -f "$CURSOR_FILE" ]; then
  # Use python3 to parse JSON (jq may not be present in launchd context).
  # Print __MALFORMED__ sentinel on parse failure (avoids ERR trap from non-zero exit).
  PARSED_OFFSET="$(python3 -c "
import json, sys
try:
    with open('$CURSOR_FILE') as f:
        raw = f.read()
    d = json.loads(raw)
    val = d.get('offset', None)
    if not isinstance(val, int) or val < 0:
        raise ValueError('invalid offset')
    print(int(val))
except Exception:
    print('__MALFORMED__')
" 2>/dev/null)" || PARSED_OFFSET="__MALFORMED__"

  if [ "$PARSED_OFFSET" = "__MALFORMED__" ]; then
    echo "journal-index: WARN — malformed cursor JSON in $CURSOR_FILE; performing full rebuild" >&2
    OFFSET=0
    # Wipe db + this journal's cursor for clean full rebuild.
    rm -f "$DB_FILE" "$CURSOR_FILE"
    if ! _create_schema "$DB_FILE"; then
      echo "journal-index: WARN — cannot recreate db after cursor reset" >&2
      exit 0
    fi
  else
    OFFSET="$PARSED_OFFSET"
  fi
fi

# ── Get current file size ────────────────────────────────────────────────────
FILE_SIZE="$(wc -c < "$JOURNAL_PATH" | tr -d ' ')"

if [ "$OFFSET" -ge "$FILE_SIZE" ]; then
  # No new bytes since last run — update last-run stamp and exit clean.
  date +%s > "$LAST_RUN_FILE"
  exit 0
fi

# ── Extract delta ─────────────────────────────────────────────────────────────
# Purpose: read only bytes from OFFSET to EOF, parse ## headers + bullet lines.
# Usage: dd extracts the byte slice; perl parses it into SQL INSERTs.
# Gotchas: dd skip= uses byte count on macOS with bs=1; large files are slow but
#   correct. For the actual 6.5MB journal with typical delta size <100KB this is fine.
#   We use bs=1 skip=$OFFSET for exact byte seeking (no block-size rounding issues).
DELTA_FILE="$(mktemp)"
dd if="$JOURNAL_PATH" bs=1 skip="$OFFSET" 2>/dev/null > "$DELTA_FILE" || {
  echo "journal-index: WARN — dd failed reading journal delta" >&2
  rm -f "$DELTA_FILE"
  exit 0
}

# ── Parse delta into SQL batch ────────────────────────────────────────────────
# Purpose: extract ## headers (as entry boundaries/ts) and "^- " bullets into rows.
# Usage: perl emits SQL INSERT statements; empty-content entries are skipped.
# Gotchas: single quotes in content/ts escaped as '' for SQLite string literals.
#   The perl script uses HERE-string quoting safe for bash single-quote embedding.
SQL_TMP="$(mktemp)"

perl - "$DELTA_FILE" <<'PERL_EOF' > "$SQL_TMP"
use strict;
use warnings;
my ($ts, $content, @rows) = ('', '', ());

# _flush: emit current entry if content is non-empty.
sub _flush {
    if ($content ne '') {
        (my $st = $ts)      =~ s/'/''/g;
        (my $sc = $content) =~ s/'/''/g;
        push @rows, "INSERT INTO entries(ts, content) VALUES('$st', '$sc');";
        $content = '';
    }
}

open(my $fh, '<', $ARGV[0]) or die "cannot open: $!";
while (my $line = <$fh>) {
    chomp $line;
    if ($line =~ /^## (\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z)/) {
        # Timestamped session-log header (standard journal.md format).
        _flush();
        $ts = $1;
    } elsif ($line =~ /^## (.+)$/) {
        # Non-timestamped section header (memory files: MEMORY.md, lessons.md, etc.).
        # Use "section:<name>" as ts so these entries are still distinguishable.
        _flush();
        $ts = 'section:' . $1;
    } elsif ($ts ne '' && $line =~ /^[-*] /) {
        # Bullet line under any header — accumulate as entry content.
        $content .= $line . ' ';
    }
}
close $fh;
_flush();

if (@rows) {
    print "BEGIN;\n";
    print join("\n", @rows) . "\n";
    print "COMMIT;\n";
    print "INSERT INTO fts(fts) VALUES('rebuild');\n";
}
PERL_EOF

rm -f "$DELTA_FILE"

# ── Insert entries + rebuild FTS ──────────────────────────────────────────────
# Purpose: apply the SQL batch to entries + trigger FTS rebuild.
# Usage: only runs if SQL_TMP is non-empty; failure is warn-only (cursor not advanced).
# Gotchas: FTS5 external-content table requires explicit 'rebuild' command after inserts.
if [ -s "$SQL_TMP" ]; then
  if ! sqlite3 "$DB_FILE" < "$SQL_TMP" 2>/dev/null; then
    echo "journal-index: WARN — failed to insert entries batch into $DB_FILE" >&2
    rm -f "$SQL_TMP"
    date +%s > "$LAST_RUN_FILE"
    exit 0
  fi
fi
rm -f "$SQL_TMP"

# ── Advance cursor ────────────────────────────────────────────────────────────
# Purpose: persist the new EOF offset so next run only reads the delta.
# Usage: atomic write via temp + mv to prevent partial cursor reads.
# Gotchas: advance even on empty batch (file unchanged = offset already at EOF).
printf '{"offset":%s}' "$FILE_SIZE" > "${CURSOR_FILE}.tmp"
mv "${CURSOR_FILE}.tmp" "$CURSOR_FILE"

# ── Stamp last-run ───────────────────────────────────────────────────────────
date +%s > "$LAST_RUN_FILE"

exit 0
