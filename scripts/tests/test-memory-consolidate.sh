#!/usr/bin/env bash
# ABOUTME: Test suite for scripts/memory-consolidate.sh (Pillar V, task V7).
# ABOUTME: Verifies stale-annotation of superseded lesson pairs, journal.md guard,
# ABOUTME: staging-only behavior, malformed JSON tolerance, and absent-claude fallback.
# ABOUTME: All tests use mktemp sandboxes with a PATH shim for the haiku model call.

set -euo pipefail

CONSOLIDATE="${CONSOLIDATE_BIN:-$HOME/.claude/scripts/memory-consolidate.sh}"
PASS=0
FAIL=0

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

# ── Fixture builder ────────────────────────────────────────────────────────────
# Build a 5-pair + 1 non-superseded fixture lessons.md.
# Each "pair" is two bullet points on different lines.
# The mock claude call returns JSON referencing these line numbers.
#
# Layout (1-indexed lines after header):
#   Line 1: header comment
#   Line 3: PAIR-A older fact (07-02 metrics)           ← stale
#   Line 5: PAIR-A newer fact (07-03 full-history redo) ← current
#   Line 7: PAIR-B older fact (dead ~/.claude/harness/)  ← stale
#   Line 9: PAIR-B newer fact (live docs/plans/harness/) ← current
#   Line 11: PAIR-C older fact (stale episodic claim)   ← stale
#   Line 13: PAIR-C newer fact (corrected episodic)     ← current
#   Line 15: PAIR-D older fact (old session purge window) ← stale
#   Line 17: PAIR-D newer fact (180-day purge window)   ← current
#   Line 19: PAIR-E older fact (wrong push target)      ← stale
#   Line 21: PAIR-E newer fact (closetmusician only)    ← current
#   Line 23: NON-SUPERSEDED fact (unique, standalone)   ← must NOT be stale
build_fixture_lessons() {
  local dir="$1"
  cat > "$dir/lessons.md" <<'EOF'
# Fixture Lessons — V7 test

- **PAIR-A-OLD**: audit-2026-07-02 counted 46 trust incidents total across the harness history.
  This figure was based on a 30-day retention window and undercounts the full history.

- **PAIR-A-NEW**: audit-2026-07-03 full-history redo (4,355 sessions) found 46 trust incidents
  in the last 6 months. The 07-02 figure was a retention-window artifact; 07-03 is authoritative.

- **PAIR-B-OLD**: harness operating files live at ~/.claude/harness/ (legacy path from
  the original implementation before the 2026-07-03 reorganization).

- **PAIR-B-NEW**: harness operating files live at ~/.claude/docs/plans/harness/ (moved
  2026-07-03). The old ~/.claude/harness/ path is dead — do not reference it.

- **PAIR-C-OLD**: episodic-memory plugin provides reliable session recall with low latency.
  Use it freely for cross-session context retrieval in CLI and hook paths.

- **PAIR-C-NEW**: episodic-memory plugin is unreliable: better-sqlite3 errors, 32-63K token
  blowups, zero June usage, context-guard interceptions. Skip gracefully; never load full archive.

- **PAIR-D-OLD**: transcript purge window is 30 days (default cleanupPeriodDays setting).
  Usage claims from ~/.claude/projects must account for this short window.

- **PAIR-D-NEW**: transcript purge window is now 180 days (cleanupPeriodDays updated 2026-07-03).
  Pre-purge content recoverable via episodic-memory archive at ~/.config/superpowers/.

- **PAIR-E-OLD**: ~/.claude git remote has two push targets: closetmusician and ExampleOrg.
  Both receive every push from the ~/.claude repo.

- **PAIR-E-NEW**: ~/.claude remote push target is closetmusician ONLY. ExampleOrg was removed
  after the 2026-07-03 secret leak incident. Never re-add ExampleOrg as a push target.

- **NON-SUPERSEDED**: MCP tools require ToolSearch bootstrap before first use. Schemas are
  not in context by default. Always call ToolSearch before any MCP tool invocation.
EOF
}

# Build mock claude binary that returns deterministic JSON for 5 pairs.
# The mock ignores its arguments and returns canned JSON referencing fixture line numbers.
# Pair line numbers in the fixture (1-indexed):
#   PAIR-A: older=3, newer=5
#   PAIR-B: older=7, newer=9
#   PAIR-C: older=11, newer=13
#   PAIR-D: older=15, newer=17
#   PAIR-E: older=19, newer=21
build_mock_claude() {
  local bin_dir="$1"
  cat > "$bin_dir/claude" <<'MOCKEOF'
#!/usr/bin/env bash
# Mock claude binary — returns canned 5-pair superseded JSON regardless of arguments.
# Reads stdin (consumes it) and prints JSON to stdout.
cat /dev/stdin > /dev/null  # consume stdin
cat <<'JSON'
[
  {"older_fact_start_line": 3,  "newer_fact_start_line": 5,  "reason": "07-03 redo supersedes 07-02 metric (retention-window artifact)"},
  {"older_fact_start_line": 7,  "newer_fact_start_line": 9,  "reason": "docs/plans/harness/ supersedes dead ~/.claude/harness/ path"},
  {"older_fact_start_line": 11, "newer_fact_start_line": 13, "reason": "corrected episodic-memory assessment supersedes old reliability claim"},
  {"older_fact_start_line": 15, "newer_fact_start_line": 17, "reason": "180-day purge window supersedes old 30-day default"},
  {"older_fact_start_line": 19, "newer_fact_start_line": 21, "reason": "closetmusician-only push supersedes old dual-push target"}
]
JSON
MOCKEOF
  chmod +x "$bin_dir/claude"
}

# Build mock claude that returns malformed JSON
build_mock_claude_malformed() {
  local bin_dir="$1"
  cat > "$bin_dir/claude" <<'MOCKEOF'
#!/usr/bin/env bash
cat /dev/stdin > /dev/null
echo "this is not json { broken }"
MOCKEOF
  chmod +x "$bin_dir/claude"
}

# Build mock claude that emits JSON wrapped in markdown fences (common LLM output)
build_mock_claude_fenced() {
  local bin_dir="$1"
  cat > "$bin_dir/claude" <<'MOCKEOF'
#!/usr/bin/env bash
cat /dev/stdin > /dev/null
cat <<'JSON'
```json
[
  {"older_fact_start_line": 3,  "newer_fact_start_line": 5,  "reason": "fence-wrapped"},
  {"older_fact_start_line": 7,  "newer_fact_start_line": 9,  "reason": "fence-wrapped"},
  {"older_fact_start_line": 11, "newer_fact_start_line": 13, "reason": "fence-wrapped"},
  {"older_fact_start_line": 15, "newer_fact_start_line": 17, "reason": "fence-wrapped"},
  {"older_fact_start_line": 19, "newer_fact_start_line": 21, "reason": "fence-wrapped"}
]
```
JSON
MOCKEOF
  chmod +x "$bin_dir/claude"
}

echo ""
echo "========================================================================"
echo "memory-consolidate test suite (Pillar V, task V7)"
echo "========================================================================"

# ════════════════════════════════════════════════════════════════════════════════
# ORACLE 1 — 5 seeded superseded pairs → ≥4 get stale markers in .proposed
# ════════════════════════════════════════════════════════════════════════════════
echo ""
echo "ORACLE 1: 5 seeded pairs → ≥4 stale markers in .proposed output"

TD=$(mktemp -d /tmp/test-consolidate-1-XXXXXX)
BIN="$TD/bin"
mkdir -p "$BIN"
build_fixture_lessons "$TD"
build_mock_claude "$BIN"

ORIG_MD5=$(md5 -q "$TD/lessons.md" 2>/dev/null || md5sum "$TD/lessons.md" | awk '{print $1}')

# Run with mock claude on PATH
output=$(PATH="$BIN:$PATH" \
  STATE="$TD" \
  bash "$CONSOLIDATE" "$TD/lessons.md" 2>&1) && rc=0 || rc=$?

if [[ -f "$TD/lessons.md.proposed" ]]; then
  stale_count=$(grep -c 'stale:' "$TD/lessons.md.proposed" || echo 0)
  _assert_ge "oracle-1: ≥4 stale markers in .proposed" "$stale_count" 4
else
  _fail "oracle-1: .proposed file not created"
  stale_count=0
fi

_assert_eq "oracle-1: exit 0" "$rc" "0"

# ════════════════════════════════════════════════════════════════════════════════
# ORACLE 2 — Non-superseded pair must NOT be marked stale
# ════════════════════════════════════════════════════════════════════════════════
echo ""
echo "ORACLE 2: non-superseded NON-SUPERSEDED line untouched in .proposed"

if [[ -f "$TD/lessons.md.proposed" ]]; then
  # The NON-SUPERSEDED line should appear in the .proposed file but WITHOUT stale marker
  ns_lines=$(grep 'NON-SUPERSEDED' "$TD/lessons.md.proposed" || echo "")
  if [[ -z "$ns_lines" ]]; then
    _fail "oracle-2: NON-SUPERSEDED line missing from .proposed entirely"
  elif echo "$ns_lines" | grep -q 'stale:'; then
    _fail "oracle-2: NON-SUPERSEDED line was incorrectly marked stale"
  else
    _ok "oracle-2: NON-SUPERSEDED line present and not stale"
  fi
else
  _fail "oracle-2: .proposed file missing (skipping)"
fi

rm -rf "$TD"

# ════════════════════════════════════════════════════════════════════════════════
# ORACLE 3 — journal.md as target → exit non-zero, no .proposed created
# ════════════════════════════════════════════════════════════════════════════════
echo ""
echo "ORACLE 3: journal.md target → non-zero exit, no output file"

TD=$(mktemp -d /tmp/test-consolidate-3-XXXXXX)
BIN="$TD/bin"
mkdir -p "$BIN"
build_mock_claude "$BIN"

# Create a fake journal.md
echo "fake journal content" > "$TD/journal.md"

journal_rc=0
PATH="$BIN:$PATH" STATE="$TD" bash "$CONSOLIDATE" "$TD/journal.md" 2>/dev/null && journal_rc=0 || journal_rc=$?

if [[ "$journal_rc" -ne 0 ]]; then
  _ok "oracle-3: journal.md guard exits non-zero (rc=$journal_rc)"
else
  _fail "oracle-3: expected non-zero exit for journal.md target, got 0"
fi

if [[ -f "$TD/journal.md.proposed" ]]; then
  _fail "oracle-3: .proposed file was created for journal.md (must not be)"
else
  _ok "oracle-3: no .proposed file created for journal.md"
fi

rm -rf "$TD"

# ════════════════════════════════════════════════════════════════════════════════
# ORACLE 4 — lessons.md unmodified byte-for-byte after run (staging only)
# ════════════════════════════════════════════════════════════════════════════════
echo ""
echo "ORACLE 4: lessons.md unmodified after run (staged to .proposed only)"

TD=$(mktemp -d /tmp/test-consolidate-4-XXXXXX)
BIN="$TD/bin"
mkdir -p "$BIN"
build_fixture_lessons "$TD"
build_mock_claude "$BIN"

BEFORE=$(md5 -q "$TD/lessons.md" 2>/dev/null || md5sum "$TD/lessons.md" | awk '{print $1}')

PATH="$BIN:$PATH" STATE="$TD" bash "$CONSOLIDATE" "$TD/lessons.md" 2>/dev/null || true

AFTER=$(md5 -q "$TD/lessons.md" 2>/dev/null || md5sum "$TD/lessons.md" | awk '{print $1}')

_assert_eq "oracle-4: lessons.md byte-for-byte unchanged" "$AFTER" "$BEFORE"

rm -rf "$TD"

# ════════════════════════════════════════════════════════════════════════════════
# ORACLE 5 — Malformed LLM JSON → exit 0, no .proposed, warn
# ════════════════════════════════════════════════════════════════════════════════
echo ""
echo "ORACLE 5: malformed LLM JSON → exit 0, no .proposed, warn to stderr"

TD=$(mktemp -d /tmp/test-consolidate-5-XXXXXX)
BIN="$TD/bin"
mkdir -p "$BIN"
build_fixture_lessons "$TD"
build_mock_claude_malformed "$BIN"

malformed_rc=0
PATH="$BIN:$PATH" STATE="$TD" bash "$CONSOLIDATE" "$TD/lessons.md" 2>/dev/null && malformed_rc=0 || malformed_rc=$?

_assert_eq "oracle-5: malformed JSON → exit 0" "$malformed_rc" "0"

if [[ -f "$TD/lessons.md.proposed" ]]; then
  _fail "oracle-5: .proposed created despite malformed JSON (should not be)"
else
  _ok "oracle-5: no .proposed for malformed JSON"
fi

rm -rf "$TD"

# ════════════════════════════════════════════════════════════════════════════════
# ORACLE 6 — claude absent → exit 0 (fail-open)
# ════════════════════════════════════════════════════════════════════════════════
echo ""
echo "ORACLE 6: claude absent → exit 0, graceful fail-open"

TD=$(mktemp -d /tmp/test-consolidate-6-XXXXXX)
BIN="$TD/bin"
mkdir -p "$BIN"
build_fixture_lessons "$TD"

# Create a claude shim that pretends the binary is absent (simulates PATH with no real claude).
# We put a stub on PATH that exits 127 so command -v succeeds but the call fails,
# which exercises the fail-open path the same way as a true absence.
# Simpler: create a claude stub that exits 1 with no output — the script's fail-open
# triggers because haiku_exit != 0 AND llm_raw is empty.
cat > "$BIN/claude" <<'STUBEOF'
#!/usr/bin/env bash
# Stub: simulates missing/broken claude binary
exit 127
STUBEOF
chmod +x "$BIN/claude"

absent_rc=0
PATH="$BIN:$PATH" STATE="$TD" bash "$CONSOLIDATE" "$TD/lessons.md" 2>/dev/null && absent_rc=0 || absent_rc=$?

_assert_eq "oracle-6: claude absent → exit 0" "$absent_rc" "0"

rm -rf "$TD"

# ════════════════════════════════════════════════════════════════════════════════
# ORACLE 7 — fence-wrapped JSON is tolerated (common LLM output pattern)
# ════════════════════════════════════════════════════════════════════════════════
echo ""
echo "ORACLE 7: fence-wrapped JSON from LLM → .proposed with ≥4 stale markers"

TD=$(mktemp -d /tmp/test-consolidate-7-XXXXXX)
BIN="$TD/bin"
mkdir -p "$BIN"
build_fixture_lessons "$TD"
build_mock_claude_fenced "$BIN"

PATH="$BIN:$PATH" STATE="$TD" bash "$CONSOLIDATE" "$TD/lessons.md" 2>/dev/null || true

if [[ -f "$TD/lessons.md.proposed" ]]; then
  stale_count=$(grep -c 'stale:' "$TD/lessons.md.proposed" || echo 0)
  _assert_ge "oracle-7: fence-wrapped → ≥4 stale markers" "$stale_count" 4
else
  _fail "oracle-7: .proposed not created for fence-wrapped JSON"
fi

rm -rf "$TD"

# ════════════════════════════════════════════════════════════════════════════════
# ORACLE 8 — correction event emitted to STATE/state/events.ndjson
# ════════════════════════════════════════════════════════════════════════════════
echo ""
echo "ORACLE 8: correction event emitted after successful consolidation"

TD=$(mktemp -d /tmp/test-consolidate-8-XXXXXX)
BIN="$TD/bin"
mkdir -p "$BIN"
mkdir -p "$TD/state"
build_fixture_lessons "$TD"
build_mock_claude "$BIN"

PATH="$BIN:$PATH" STATE="$TD" bash "$CONSOLIDATE" "$TD/lessons.md" 2>/dev/null || true

events_file="$TD/state/events.ndjson"
if [[ -f "$events_file" ]]; then
  if grep -q '"memory-consolidation"' "$events_file"; then
    _ok "oracle-8: correction event with memory-consolidation category emitted"
  else
    _fail "oracle-8: events.ndjson exists but no memory-consolidation event found"
  fi
else
  _fail "oracle-8: events.ndjson not created (event not emitted)"
fi

rm -rf "$TD"

# ════════════════════════════════════════════════════════════════════════════════
# Summary
# ════════════════════════════════════════════════════════════════════════════════
echo ""
echo "========================================================================"
echo "Results: $PASS passed, $FAIL failed"
echo "========================================================================"

[[ "$FAIL" -eq 0 ]] && exit 0 || exit 1
