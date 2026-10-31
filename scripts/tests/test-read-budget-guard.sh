#!/usr/bin/env bash
# ABOUTME: TDD suite for scripts/governance/read-budget-guard.sh (spec C6).
# ABOUTME: An orchestrating session may not pull more than 32 KB (8 KB for code) into
# ABOUTME: context in one Read or Bash read. Ranged, piped-to-count, and redirected reads pass.
# ABOUTME: Run: bash scripts/tests/test-read-budget-guard.sh — exit 0 = all green.
# ABOUTME: Spec: docs/plans/harness/governance-scope-spec.md §3 C6, §4.

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="${SCRIPT_DIR}/../governance/read-budget-guard.sh"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
PASS=0; FAIL=0
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib/gov-hook-fixtures.sh"

ARMED="$TMP/state"; mkdir -p "$ARMED"; touch "$ARMED/.active"
GATED="$TMP/state-gate"; mkdir -p "$GATED"; touch "$GATED/.gate-pre-coder"
IDLE="$TMP/state-idle"; mkdir -p "$IDLE"

R="$TMP/pm"; new_repo "$R" a.md
mkdir -p "$R/temp" "$R/src" "$R/.claude/rules"
fill_bytes "$R/temp/src-ai-roadmap.md" 66150    # the 64.6 KB file from the 2026-10-11 log
fill_bytes "$R/small.md" 20000
fill_bytes "$R/src/big.py" 10240
fill_bytes "$R/src/small.py" 4096
fill_bytes "$R/.claude/rules/long.md" 60000
printf 'PNGDATA' > "$R/shot.png"; fill_bytes "$R/shot.png" 200000

rd() { pl PreToolUse "$R" Read "$1" "${2:-}"; }
sh() { pl PreToolUse "$R" Bash "$(jq -cn --arg c "$1" '{command:$c}')" "${2:-}"; }
A=(HARNESS_GOV_STATE_DIR="$ARMED")

echo "=== test-read-budget-guard.sh ==="
echo "-- Read --"
check "Read 64.6 KB md denied"            DENY  "$HOOK" "$R" "$(rd "{\"file_path\":\"$R/temp/src-ai-roadmap.md\"}")" "${A[@]}"
check "Read 20 KB md allowed"             ALLOW "$HOOK" "$R" "$(rd "{\"file_path\":\"$R/small.md\"}")" "${A[@]}"
check "Read big md with limit 100 allowed" ALLOW "$HOOK" "$R" "$(rd "{\"file_path\":\"$R/temp/src-ai-roadmap.md\",\"offset\":10,\"limit\":100}")" "${A[@]}"
check "Read 10 KB .py denied"             DENY  "$HOOK" "$R" "$(rd "{\"file_path\":\"$R/src/big.py\"}")" "${A[@]}"
check "Read 4 KB .py allowed"             ALLOW "$HOOK" "$R" "$(rd "{\"file_path\":\"$R/src/small.py\"}")" "${A[@]}"
check "Read image allowed"                ALLOW "$HOOK" "$R" "$(rd "{\"file_path\":\"$R/shot.png\"}")" "${A[@]}"
check "Read .claude/rules always allowed" ALLOW "$HOOK" "$R" "$(rd "{\"file_path\":\"$R/.claude/rules/long.md\"}")" "${A[@]}"
check "Read missing file allowed"         ALLOW "$HOOK" "$R" "$(rd "{\"file_path\":\"$R/nope.md\"}")" "${A[@]}"

echo "-- Bash --"
check "replay: cat 64.6 KB md denied"     DENY  "$HOOK" "$R" "$(sh "cat temp/src-ai-roadmap.md")" "${A[@]}"
check "cat absolute path denied"          DENY  "$HOOK" "$R" "$(sh "cat $R/temp/src-ai-roadmap.md")" "${A[@]}"
check "cd then cat denied"                DENY  "$HOOK" "$R" "$(sh "cd $R/temp && cat src-ai-roadmap.md")" "${A[@]}"
check "cat small.md allowed"              ALLOW "$HOOK" "$R" "$(sh "cat small.md")" "${A[@]}"
check "cat big | wc -l allowed"           ALLOW "$HOOK" "$R" "$(sh "cat temp/src-ai-roadmap.md | wc -l")" "${A[@]}"
check "head -n 20 big allowed"            ALLOW "$HOOK" "$R" "$(sh "head -n 20 temp/src-ai-roadmap.md")" "${A[@]}"
check "head -1000 big denied"             DENY  "$HOOK" "$R" "$(sh "head -1000 temp/src-ai-roadmap.md")" "${A[@]}"
check "sed -n 1,40p big allowed"          ALLOW "$HOOK" "$R" "$(sh "sed -n '1,40p' temp/src-ai-roadmap.md")" "${A[@]}"
check "tail -n 30 big allowed"            ALLOW "$HOOK" "$R" "$(sh "tail -n 30 temp/src-ai-roadmap.md")" "${A[@]}"
check "markitdown > file allowed"         ALLOW "$HOOK" "$R" "$(sh "markitdown temp/src-ai-roadmap.md > out.md")" "${A[@]}"
check "markitdown to stdout denied"       DENY  "$HOOK" "$R" "$(sh "markitdown temp/src-ai-roadmap.md")" "${A[@]}"
check "cat big.py denied (code cap)"      DENY  "$HOOK" "$R" "$(sh "cat src/big.py")" "${A[@]}"
check "git log allowed (no read verb)"    ALLOW "$HOOK" "$R" "$(sh "git log --oneline -5")" "${A[@]}"
check "quoted path in echo not a read"    ALLOW "$HOOK" "$R" "$(sh "echo 'cat temp/src-ai-roadmap.md'")" "${A[@]}"
check "sed -i on big file allowed"      ALLOW "$HOOK" "$R" "$(sh "sed -i '' 's/x/z/' temp/src-ai-roadmap.md")" "${A[@]}"
HEREDOC=$'cat > out.md <<\'EOF\'\ncat temp/src-ai-roadmap.md\nEOF'
check "heredoc body is data"            ALLOW "$HOOK" "$R" "$(sh "$HEREDOC")" "${A[@]}"
check "sed without -n prints whole file" DENY  "$HOOK" "$R" "$(sh "sed 's/x/z/' temp/src-ai-roadmap.md")" "${A[@]}"

echo "-- review fixes (2026-10-11) --"
fill_bytes "$R/big.json" 40000
fill_bytes "$R/a.md" 20001; fill_bytes "$R/b.md" 20001
fill_bytes "$R/big.pdf" 310000
perl -e 'print "z" x 100000' > "$R/min.json"
check "cat -n big | sed -n 10,50p allowed"  ALLOW "$HOOK" "$R" "$(sh "cat -n temp/src-ai-roadmap.md | sed -n '10,50p'")" "${A[@]}"
check "jq -r .version big.json allowed"     ALLOW "$HOOK" "$R" "$(sh "jq -r '.version' big.json")" "${A[@]}"
check "jq . big.json denied (identity)"     DENY  "$HOOK" "$R" "$(sh "jq . big.json")" "${A[@]}"
check "awk NR<5 big allowed"                ALLOW "$HOOK" "$R" "$(sh "awk 'NR<5' temp/src-ai-roadmap.md")" "${A[@]}"
check "tail -n +1 big denied"               DENY  "$HOOK" "$R" "$(sh "tail -n +1 temp/src-ai-roadmap.md")" "${A[@]}"
check "sed -n 1500,\$p past end allowed"    ALLOW "$HOOK" "$R" "$(sh "sed -n '1500,\$p' temp/src-ai-roadmap.md")" "${A[@]}"
check "for loop cat big denied"             DENY  "$HOOK" "$R" "$(sh "for f in x; do cat temp/src-ai-roadmap.md; done")" "${A[@]}"
check "subshell cat big denied"             DENY  "$HOOK" "$R" "$(sh "( cat temp/src-ai-roadmap.md )")" "${A[@]}"
check "cat big | grep -v denied"            DENY  "$HOOK" "$R" "$(sh "cat temp/src-ai-roadmap.md | grep -v zzz")" "${A[@]}"
check "two reads sum over cap denied"       DENY  "$HOOK" "$R" "$(sh "cat a.md; cat b.md")" "${A[@]}"
check "markitdown -o file allowed"          ALLOW "$HOOK" "$R" "$(sh "markitdown temp/src-ai-roadmap.md -o out.md")" "${A[@]}"
check "pdftotext IN OUT allowed"            ALLOW "$HOOK" "$R" "$(sh "pdftotext big.pdf out.txt")" "${A[@]}"
check "cat big | head -n 300 allowed"       ALLOW "$HOOK" "$R" "$(sh "cat temp/src-ai-roadmap.md | head -n 300")" "${A[@]}"
check "Read pdf with pages allowed"         ALLOW "$HOOK" "$R" "$(rd "{\"file_path\":\"$R/big.pdf\",\"pages\":\"1\"}")" "${A[@]}"
check "Read one-line min.json limit 5 allowed" ALLOW "$HOOK" "$R" "$(rd "{\"file_path\":\"$R/min.json\",\"limit\":5}")" "${A[@]}"

echo "-- scope --"
check "subagent cat big allowed"          ALLOW "$HOOK" "$R" "$(sh "cat temp/src-ai-roadmap.md" agent1)" "${A[@]}"
check "no sentinel allowed"               ALLOW "$HOOK" "$R" "$(sh "cat temp/src-ai-roadmap.md")" HARNESS_GOV_STATE_DIR="$IDLE"
check ".gate-* sentinel arms the guard"   DENY  "$HOOK" "$R" "$(sh "cat temp/src-ai-roadmap.md")" HARNESS_GOV_STATE_DIR="$GATED"
check "kill switch allows"                ALLOW "$HOOK" "$R" "$(sh "cat temp/src-ai-roadmap.md")" "${A[@]}" HARNESS_READ_BUDGET=0
check "cap override via env"              ALLOW "$HOOK" "$R" "$(sh "cat temp/src-ai-roadmap.md")" "${A[@]}" READ_CAP_BYTES=100000
check "malformed JSON allowed"            ALLOW "$HOOK" "$R" "not json" "${A[@]}"

echo
echo "=== $PASS passed, $FAIL failed ==="
[ "$FAIL" -eq 0 ]
