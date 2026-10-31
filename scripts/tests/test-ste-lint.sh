#!/usr/bin/env bash
# ABOUTME: TDD suite for scripts/ste-lint.sh — the Stop-hook writing-style gate.
# ABOUTME: Drives REAL stdin payloads and REAL transcript fixtures, matching the Stop
# ABOUTME: contract used by scripts/completion-claim-guard.sh (stop_hook_active,
# ABOUTME: transcript_path, {"decision":"block"}). Identity never comes from env.
# ABOUTME: Run: bash scripts/tests/test-ste-lint.sh — exit 0 = all green.

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LINT="${SCRIPT_DIR}/../ste-lint.sh"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
PASS=0; FAIL=0
N=0

# say <text> → build a transcript whose last assistant message is <text>, echo its path.
# Gotchas: each call gets a fresh uuid so the once-per-message guard does not mask a test.
say() {
  N=$((N+1))
  local f="$TMP/t$N.jsonl"
  jq -cn '{type:"user",isSidechain:false,message:{role:"user",content:"go"}}' > "$f"
  jq -cn --arg t "$1" --arg u "uuid-$N" \
    '{type:"assistant",isSidechain:false,uuid:$u,message:{role:"assistant",model:"claude-opus-5",content:[{type:"text",text:$t}]}}' >> "$f"
  printf '%s' "$f"
}

payload() { jq -cn --arg tp "$1" --argjson sha "${2:-false}" \
  '{session_id:"test",transcript_path:$tp,hook_event_name:"Stop",stop_hook_active:$sha}'; }

# check <name> <BLOCK|PASS> <payload> [env...]
check() {
  local name="$1" expect="$2" pl="$3"; shift 3
  local out got
  out="$(printf '%s' "$pl" | env STE_SEEN_DIR="$TMP/seen$RANDOM" "$@" bash "$LINT" 2>/dev/null)"
  if printf '%s' "$out" | jq -e '.decision == "block"' >/dev/null 2>&1; then got=BLOCK; else got=PASS; fi
  if [ "$got" = "$expect" ]; then PASS=$((PASS+1)); printf '  ok   %s\n' "$name"
  else FAIL=$((FAIL+1)); printf '  FAIL %s (expected %s, got %s)\n' "$name" "$expect" "$got"; fi
}

echo "=== test-ste-lint.sh ==="

echo "-- clean writing passes --"
check "short active sentences" PASS "$(payload "$(say "I fixed the guard. It blocks the call now. The tests pass.")")"
check "plain technical text"   PASS "$(payload "$(say "The hook reads the model from the transcript. No field in the payload holds it.")")"

echo "-- banned vocabulary blocks --"
check "utilize"      BLOCK "$(payload "$(say "We utilize the cache to speed up reads.")")"
check "leverage"     BLOCK "$(payload "$(say "You can leverage the existing guard here.")")"
check "robust"       BLOCK "$(payload "$(say "This gives you a robust check.")")"
check "comprehensive" BLOCK "$(payload "$(say "Here is a comprehensive list of the files.")")"
check "delve"        BLOCK "$(payload "$(say "Let me delve into the cause.")")"
check "in order to"  BLOCK "$(payload "$(say "I changed it in order to fix the bug.")")"

echo "-- claude-speak phrases block --"
check "you're absolutely right" BLOCK "$(payload "$(say "You are absolutely right about the cause.")")"
check "great question"         BLOCK "$(payload "$(say "Great question. The answer is yes.")")"
check "it's worth noting"      BLOCK "$(payload "$(say "It is worth noting that the file moved.")")"
check "not just X, it's Y"     BLOCK "$(payload "$(say "This is not just a bug, it is a design flaw.")")"
check "deep dive"              BLOCK "$(payload "$(say "Here is a deep dive on the guard.")")"

echo "-- structure rules block --"
check "over-long sentence" BLOCK "$(payload "$(say "The guard reads the session model from the transcript file because the payload that Claude Code sends to a hook does not carry any field that names the model at all.")")"
check "em dash pile-up"    BLOCK "$(payload "$(say "I fixed it — really — and then — again — it broke.")")"

echo "-- nothing is exempt: tables and code are checked too --"
check "banned word in a code fence" PASS "$(payload "$(say "Run this:
\`\`\`bash
utilize --robust --comprehensive
\`\`\`
It works.")")"
check "inline code"        PASS "$(payload "$(say "The flag is \`--utilize-cache\` and it works.")")"
check "file path"          PASS "$(payload "$(say "See scripts/leverage-robust-comprehensive.sh for the code.")")"
check "table cell prose"   BLOCK "$(payload "$(say "| item | note |
|---|---|
| guard | It is worth noting that this is robust. |")")"
check "prose after a fence" BLOCK "$(payload "$(say "Run it:
\`\`\`bash
ls -la
\`\`\`
We utilize the cache here.")")"
check "long shell line in fence is not a sentence" PASS "$(payload "$(say "Run this:
\`\`\`bash
find . -type f -name '*.md' -print0 | xargs -0 perl -ne 'print if /TODO/' | sort -u | head -40 | awk '{ print \$1, \$2 }'
\`\`\`
It works.")")"
check "url with a banned word" PASS "$(payload "$(say "See https://example.com/robust-guide for more.")")"
check "link text is checked"  BLOCK "$(payload "$(say "Read [the comprehensive guide](https://example.com/g) first.")")"
check "banned word ending a sentence" BLOCK "$(payload "$(say "The check is robust. It passes.")")"

echo "-- never loops, never bricks --"
check "stop_hook_active"   PASS "$(payload "$(say "We utilize the cache.")" true)"
check "missing transcript" PASS "$(payload "$TMP/nope.jsonl")"
check "malformed payload"  PASS "not json"
check "empty payload"      PASS ""
check "kill switch"        PASS "$(payload "$(say "We utilize the cache.")")" HARNESS_STE_LINT=0

# Once per message: the same assistant message must not be blocked twice.
SEEN="$TMP/seen-shared"; T="$(say "We utilize the cache.")"
printf '%s' "$(payload "$T")" | env STE_SEEN_DIR="$SEEN" bash "$LINT" >/dev/null 2>&1
OUT2="$(printf '%s' "$(payload "$T")" | env STE_SEEN_DIR="$SEEN" bash "$LINT" 2>/dev/null)"
if printf '%s' "$OUT2" | jq -e '.decision == "block"' >/dev/null 2>&1; then
  FAIL=$((FAIL+1)); printf '  FAIL same message blocked twice\n'
else PASS=$((PASS+1)); printf '  ok   same message blocked only once\n'; fi

# The block must name the offending word so the rewrite is mechanical.
OUT3="$(printf '%s' "$(payload "$(say "We utilize the cache.")")" | env STE_SEEN_DIR="$TMP/s3" bash "$LINT" 2>/dev/null)"
if printf '%s' "$OUT3" | jq -r '.reason' 2>/dev/null | grep -qi 'utilize'; then
  PASS=$((PASS+1)); printf '  ok   block names the offending word\n'
else FAIL=$((FAIL+1)); printf '  FAIL block names the offending word\n'; fi
if printf '%s' "$OUT3" | jq -r '.reason' 2>/dev/null | grep -qi '\buse\b'; then
  PASS=$((PASS+1)); printf '  ok   block gives the approved replacement\n'
else FAIL=$((FAIL+1)); printf '  FAIL block gives the approved replacement\n'; fi

echo; echo "=== $PASS passed, $FAIL failed ==="
[ "$FAIL" -eq 0 ]
