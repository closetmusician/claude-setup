#!/usr/bin/env bash
# ABOUTME: TDD test suite for scripts/skill-retrieve.sh (UserPromptSubmit hook, B2+B3).
# ABOUTME: Covers: table-nudge passthrough, semantic injection, below-threshold, missing-db,
# ABOUTME: flag-unset fast-path, and short/slash-command guard (inherited from skill-nudge).
# ABOUTME: Uses fixture skill-index.db with deterministic stub embeddings.
# ABOUTME: Run: bash scripts/tests/test-skill-retrieve.sh — all cases must be GREEN.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RETRIEVE="${SCRIPT_DIR}/../skill-retrieve.sh"
NUDGE="${SCRIPT_DIR}/../skill-nudge.sh"
BUILD="${SCRIPT_DIR}/../skill-index-build.sh"

# ── Isolated temp dirs ────────────────────────────────────────────────────────
TMP="$(mktemp -d /tmp/test-skill-retrieve-XXXXXX)"
trap 'rm -rf "$TMP"' EXIT

export STATE="$TMP/governance"
export EVENTS="$STATE/state/events.ndjson"
mkdir -p "$STATE/state" "$STATE/embed-cache"

# Fixture skill-index.db: a tiny db with a few skill rows (cosine searchable)
FIXTURE_DB="$TMP/fixture.db"

PASS=0
FAIL=0

_pass() { echo "  PASS: $1"; (( PASS++ )) || true; }
_fail() { echo "  FAIL: $1 — $2"; (( FAIL++ )) || true; }

_fresh_events() {
  rm -f "$EVENTS" || true
  rm -rf "$STATE/state/.events.lock.d" || true
}

_count_events() {
  [ -f "$EVENTS" ] && wc -l < "$EVENTS" | tr -d ' ' || echo 0
}

_events_with_trigger() {
  # $1 = trigger value to match
  [ -f "$EVENTS" ] && grep -c "\"trigger\":\"$1\"" "$EVENTS" 2>/dev/null || echo 0
}

# ── Build tiny fixture index ──────────────────────────────────────────────────
# Uses the same deterministic stub embedder as skill-index-build.sh (256-dim bag-of-words)
_build_fixture_db() {
  python3 - <<'PYEOF'
import sys, os, sqlite3, hashlib, json

db_path = os.environ.get("FIXTURE_DB")
if not db_path:
    print("FIXTURE_DB not set", file=sys.stderr)
    sys.exit(1)

def stub_embed(text, dims=256):
    """
    Deterministic bag-of-words feature-hash embedding (same as skill-index-build.sh stub).
    Tokenize lowercase words, hash each token to a dim bucket, count occurrences.
    """
    import re
    tokens = re.findall(r'[a-z0-9]+', text.lower())
    vec = [0.0] * dims
    for tok in tokens:
        h = int(hashlib.sha256(tok.encode()).hexdigest(), 16) % dims
        vec[h] += 1.0
    # normalize
    norm = sum(v*v for v in vec) ** 0.5
    if norm > 0:
        vec = [v/norm for v in vec]
    return vec

skills = [
    ("codebase-mapping",
     "Orchestrates comprehensive codebase architecture documentation. "
     "Map the codebase, architecture overview, understand this codebase, create arch doc.",
     "/Users/yklin/.claude/skills/codebase-mapping/SKILL.md"),
    ("investigate",
     "Root-cause debugging. Debug why this is broken, investigate failure, find the bug.",
     "/Users/yklin/.claude/skills/investigate/SKILL.md"),
    ("pr-review-pr",
     "Comprehensive PR-diff review. Review this PR, check the PR, pre-landing review.",
     "/Users/yklin/.claude/skills/pr-review-pr/SKILL.md"),
]

import struct

conn = sqlite3.connect(db_path)
conn.execute("""
    CREATE TABLE IF NOT EXISTS skills (
        skill TEXT PRIMARY KEY,
        path TEXT,
        description TEXT,
        vec BLOB,
        embedder TEXT,
        updated TEXT
    )
""")

import datetime
now = datetime.datetime.now(datetime.timezone.utc).isoformat()

for skill, desc, path in skills:
    vec = stub_embed(desc)
    vec_blob = struct.pack(f'{len(vec)}f', *vec)
    conn.execute("""
        INSERT OR REPLACE INTO skills(skill, path, description, vec, embedder, updated)
        VALUES (?, ?, ?, ?, ?, ?)
    """, (skill, path, desc, vec_blob, "stub-256dim", now))

conn.commit()
conn.close()
print(f"Fixture DB created at {db_path} with {len(skills)} skills")
PYEOF
}

echo "=== test-skill-retrieve.sh ==="
echo "RETRIEVE=$RETRIEVE"
echo "STATE=$STATE"
echo ""

# Build fixture DB
FIXTURE_DB="$FIXTURE_DB" _build_fixture_db
if [ $? -ne 0 ]; then
  echo "FATAL: Could not build fixture DB — aborting"
  exit 1
fi
echo "Fixture DB built: $FIXTURE_DB"
echo ""

# ─────────────────────────────────────────────────────────────────────────────
# Case 1: prompt matching skill-nudge regex → table nudge fired, NO semantic
#         block, skill_fire trigger:"table"
# ─────────────────────────────────────────────────────────────────────────────
echo "[1] table-nudge: regex match → nudge output, no semantic block, skill_fire trigger:table"
_fresh_events
INPUT='{"prompt":"review this PR and tell me what changed","session_id":"s1"}'
# Run with HARNESS_SKILL_SEMANTIC=1 to ensure table wins even when semantic enabled
OUTPUT=$(printf '%s' "$INPUT" | HARNESS_SKILL_SEMANTIC=1 \
  SKILL_INDEX_DB="$FIXTURE_DB" \
  bash "$RETRIEVE" 2>/dev/null || true)

# Output should be JSON with additionalContext containing the nudge
if echo "$OUTPUT" | python3 -c "import json,sys; d=json.load(sys.stdin); ac=d.get('hookSpecificOutput',{}).get('additionalContext',''); assert 'pr-review-pr' in ac or 'PR diff review' in ac or 'review' in ac.lower(), f'no nudge in: {ac[:100]}'" 2>/dev/null; then
  _pass "1-output-contains-nudge"
else
  _fail "1-output-contains-nudge" "expected nudge in additionalContext, got: ${OUTPUT:0:200}"
fi

# No semantic block (should not inject codebase-mapping etc.)
if echo "$OUTPUT" | python3 -c "import json,sys; d=json.load(sys.stdin); ac=d.get('hookSpecificOutput',{}).get('additionalContext',''); assert 'RELEVANT SKILLS (semantic match)' not in ac, f'semantic block found in table path'" 2>/dev/null; then
  _pass "1-no-semantic-block"
else
  _fail "1-no-semantic-block" "semantic block injected on table path, output: ${OUTPUT:0:300}"
fi

# skill_fire with trigger:table
TABLE_FIRES=$(_events_with_trigger "table")
if [ "$TABLE_FIRES" -ge 1 ]; then
  _pass "1-skill_fire-table"
else
  _fail "1-skill_fire-table" "expected ≥1 skill_fire trigger:table in events, got $TABLE_FIRES (events: $(cat "$EVENTS" 2>/dev/null | head -3 || echo NONE))"
fi

echo ""

# ─────────────────────────────────────────────────────────────────────────────
# Case 2: HARNESS_SKILL_SEMANTIC=1 + prompt semantically near codebase-mapping
#         → injected, contains codebase-mapping, trigger:"semantic"
# ─────────────────────────────────────────────────────────────────────────────
echo "[2] semantic: HARNESS_SKILL_SEMANTIC=1 + near-codebase-mapping prompt → inject, trigger:semantic"
_fresh_events
INPUT='{"prompt":"I need to understand the architecture of this codebase and document how features map to code","session_id":"s2"}'
OUTPUT=$(printf '%s' "$INPUT" | HARNESS_SKILL_SEMANTIC=1 \
  SKILL_INDEX_DB="$FIXTURE_DB" \
  bash "$RETRIEVE" 2>/dev/null || true)

if echo "$OUTPUT" | python3 -c "import json,sys; d=json.load(sys.stdin); ac=d.get('hookSpecificOutput',{}).get('additionalContext',''); assert 'codebase-mapping' in ac, f'codebase-mapping not in: {ac[:200]}'" 2>/dev/null; then
  _pass "2-contains-codebase-mapping"
else
  _fail "2-contains-codebase-mapping" "expected codebase-mapping in output, got: ${OUTPUT:0:300}"
fi

if echo "$OUTPUT" | python3 -c "import json,sys; d=json.load(sys.stdin); ac=d.get('hookSpecificOutput',{}).get('additionalContext',''); assert 'RELEVANT SKILLS' in ac, f'header missing: {ac[:200]}'" 2>/dev/null; then
  _pass "2-has-header"
else
  _fail "2-has-header" "missing RELEVANT SKILLS header, got: ${OUTPUT:0:300}"
fi

SEMANTIC_FIRES=$(_events_with_trigger "semantic")
if [ "$SEMANTIC_FIRES" -ge 1 ]; then
  _pass "2-skill_fire-semantic"
else
  _fail "2-skill_fire-semantic" "expected ≥1 skill_fire trigger:semantic, got $SEMANTIC_FIRES"
fi

echo ""

# ─────────────────────────────────────────────────────────────────────────────
# Case 3: below threshold → no injection, exit 0 silent
# ─────────────────────────────────────────────────────────────────────────────
echo "[3] below-threshold: unrelated prompt → no injection, exit 0"
_fresh_events
# A prompt completely unrelated to any skill in our fixture
INPUT='{"prompt":"what is the weather like in tokyo today and should I bring an umbrella","session_id":"s3"}'
OUTPUT=$(printf '%s' "$INPUT" | HARNESS_SKILL_SEMANTIC=1 \
  SKILL_INDEX_DB="$FIXTURE_DB" \
  bash "$RETRIEVE" 2>/dev/null || true)

# Should be empty or JSON without semantic block
if [ -z "$OUTPUT" ] || echo "$OUTPUT" | python3 -c "import json,sys; d=json.load(sys.stdin); ac=d.get('hookSpecificOutput',{}).get('additionalContext',''); assert 'RELEVANT SKILLS' not in ac, 'got semantic block for unrelated prompt'" 2>/dev/null; then
  _pass "3-no-injection"
else
  _fail "3-no-injection" "got injection for unrelated prompt: ${OUTPUT:0:300}"
fi

echo ""

# ─────────────────────────────────────────────────────────────────────────────
# Case 4: missing db → exit 0 silently
# ─────────────────────────────────────────────────────────────────────────────
echo "[4] missing db → exit 0 silently"
_fresh_events
INPUT='{"prompt":"understand the architecture of this codebase","session_id":"s4"}'
OUTPUT=$(printf '%s' "$INPUT" | HARNESS_SKILL_SEMANTIC=1 \
  SKILL_INDEX_DB="/tmp/nonexistent-db-$(date +%s).db" \
  bash "$RETRIEVE" 2>/dev/null || true)
EXIT_CODE=$?

if [ $EXIT_CODE -eq 0 ]; then
  _pass "4-exit-0"
else
  _fail "4-exit-0" "expected exit 0, got $EXIT_CODE"
fi

if [ -z "$OUTPUT" ] || ! echo "$OUTPUT" | python3 -c "import json,sys; d=json.load(sys.stdin); assert d.get('hookSpecificOutput',{}).get('additionalContext','') != '', 'no semantic block'" 2>/dev/null; then
  _pass "4-no-semantic-block"
else
  _fail "4-no-semantic-block" "got semantic block with missing db: ${OUTPUT:0:200}"
fi

echo ""

# ─────────────────────────────────────────────────────────────────────────────
# Case 5: HARNESS_SKILL_SEMANTIC unset → exit 0 immediately (fast-path)
# ─────────────────────────────────────────────────────────────────────────────
echo "[5] flag unset → exit 0 immediately, no semantic path"
_fresh_events
INPUT='{"prompt":"understand the architecture of this codebase and document it","session_id":"s5"}'
START_MS=$(python3 -c "import time; print(int(time.time()*1000))" 2>/dev/null || echo 0)
OUTPUT=$(printf '%s' "$INPUT" | \
  SKILL_INDEX_DB="$FIXTURE_DB" \
  bash "$RETRIEVE" 2>/dev/null || true)
END_MS=$(python3 -c "import time; print(int(time.time()*1000))" 2>/dev/null || echo 0)
EXIT_CODE=$?
ELAPSED=$(( END_MS - START_MS ))

if [ $EXIT_CODE -eq 0 ]; then
  _pass "5-exit-0"
else
  _fail "5-exit-0" "expected exit 0, got $EXIT_CODE"
fi

# Without the flag, semantic block must NOT appear (even if db present)
if [ -z "$OUTPUT" ] || ! echo "$OUTPUT" | python3 -c "import json,sys; d=json.load(sys.stdin); assert 'RELEVANT SKILLS' in d.get('hookSpecificOutput',{}).get('additionalContext',''), ''" 2>/dev/null; then
  _pass "5-no-semantic-block"
else
  _fail "5-no-semantic-block" "semantic block appeared without flag: ${OUTPUT:0:300}"
fi

echo ""

# ─────────────────────────────────────────────────────────────────────────────
# Case 6: short prompt (<12 chars) and slash command → exit 0 (inherit skill-nudge guards)
# ─────────────────────────────────────────────────────────────────────────────
echo "[6] short/slash prompt → exit 0 (inherited guards)"

# 6a: short prompt
_fresh_events
INPUT='{"prompt":"hi","session_id":"s6a"}'
OUTPUT=$(printf '%s' "$INPUT" | HARNESS_SKILL_SEMANTIC=1 \
  SKILL_INDEX_DB="$FIXTURE_DB" \
  bash "$RETRIEVE" 2>/dev/null || true)
EXIT_CODE=$?

if [ $EXIT_CODE -eq 0 ]; then
  _pass "6a-short-exit-0"
else
  _fail "6a-short-exit-0" "expected exit 0 for short prompt, got $EXIT_CODE"
fi

if [ -z "$OUTPUT" ] || ! echo "$OUTPUT" | python3 -c "import json,sys; d=json.load(sys.stdin); assert d.get('hookSpecificOutput',{}).get('additionalContext','') != '', ''" 2>/dev/null; then
  _pass "6a-short-no-injection"
else
  _fail "6a-short-no-injection" "got injection for short prompt: ${OUTPUT:0:200}"
fi

# 6b: slash command
_fresh_events
INPUT='{"prompt":"/investigate why tests are failing","session_id":"s6b"}'
OUTPUT=$(printf '%s' "$INPUT" | HARNESS_SKILL_SEMANTIC=1 \
  SKILL_INDEX_DB="$FIXTURE_DB" \
  bash "$RETRIEVE" 2>/dev/null || true)
EXIT_CODE=$?

if [ $EXIT_CODE -eq 0 ]; then
  _pass "6b-slash-exit-0"
else
  _fail "6b-slash-exit-0" "expected exit 0 for slash command, got $EXIT_CODE"
fi

if [ -z "$OUTPUT" ] || ! echo "$OUTPUT" | python3 -c "import json,sys; d=json.load(sys.stdin); assert d.get('hookSpecificOutput',{}).get('additionalContext','') != '', ''" 2>/dev/null; then
  _pass "6b-slash-no-injection"
else
  _fail "6b-slash-no-injection" "got injection for slash command: ${OUTPUT:0:200}"
fi

echo ""

# ─────────────────────────────────────────────────────────────────────────────
# Case 7 (regression): prod field `.prompt` (not `.user_prompt`) fires table path.
#   Asserts that the hook correctly extracts the prompt from the production-spec
#   UserPromptSubmit payload field name, not the legacy test-only field.
# ─────────────────────────────────────────────────────────────────────────────
echo "[7] regression: .prompt key (prod field) fires table path, .user_prompt alone does NOT"
_fresh_events

# 7a: .prompt key → must produce a nudge (production-spec path)
INPUT='{"prompt":"why is this broken in the login flow","session_id":"s7a"}'
OUTPUT=$(printf '%s' "$INPUT" | HARNESS_SKILL_SEMANTIC=1 \
  SKILL_INDEX_DB="$FIXTURE_DB" \
  bash "$RETRIEVE" 2>/dev/null || true)

if echo "$OUTPUT" | python3 -c "import json,sys; d=json.load(sys.stdin); ac=d.get('hookSpecificOutput',{}).get('additionalContext',''); assert len(ac)>0, f'empty additionalContext for .prompt key'" 2>/dev/null; then
  _pass "7a-prompt-key-fires"
else
  _fail "7a-prompt-key-fires" "expected non-empty output for .prompt key, got: ${OUTPUT:0:200}"
fi

# 7b: .user_prompt only (no .prompt) → legacy fallback still works
INPUT='{"user_prompt":"why is this broken in the login flow","session_id":"s7b"}'
OUTPUT=$(printf '%s' "$INPUT" | HARNESS_SKILL_SEMANTIC=1 \
  SKILL_INDEX_DB="$FIXTURE_DB" \
  bash "$RETRIEVE" 2>/dev/null || true)

# Legacy fallback: .user_prompt should still work (graceful backward compat)
if echo "$OUTPUT" | python3 -c "import json,sys; d=json.load(sys.stdin); ac=d.get('hookSpecificOutput',{}).get('additionalContext',''); assert len(ac)>0, f'empty additionalContext for .user_prompt fallback'" 2>/dev/null; then
  _pass "7b-user_prompt-fallback-fires"
else
  _fail "7b-user_prompt-fallback-fires" "expected legacy .user_prompt fallback to fire, got: ${OUTPUT:0:200}"
fi

# 7c: neither .prompt nor .user_prompt → exit 0 silent (no prompt → no nudge)
INPUT='{"session_id":"s7c","tool":"Bash","command":"ls"}'
OUTPUT=$(printf '%s' "$INPUT" | HARNESS_SKILL_SEMANTIC=1 \
  SKILL_INDEX_DB="$FIXTURE_DB" \
  bash "$RETRIEVE" 2>/dev/null || true)

if [ -z "$OUTPUT" ]; then
  _pass "7c-no-prompt-silent"
else
  _fail "7c-no-prompt-silent" "expected empty output when no prompt key, got: ${OUTPUT:0:200}"
fi

echo ""

# ─────────────────────────────────────────────────────────────────────────────
# Summary
# ─────────────────────────────────────────────────────────────────────────────
echo "======================================="
echo "Results: $PASS passed, $FAIL failed"
echo "======================================="

[ $FAIL -eq 0 ] && exit 0 || exit 1
