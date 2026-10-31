#!/usr/bin/env bash
# ABOUTME: Contract test: a wired PreToolUse hook that blocks (exit 2) must put its reason where
# ABOUTME: Claude Code reads it. On exit 2 the harness shows the model stderr only and drops stdout.
# ABOUTME: Born 2026-10-31: commit-order-guard.sh blocked 3 commits as "No stderr output".
# ABOUTME: Part 1 is static over every hook in settings.json. Part 2 runs commit-order-guard live.
# ABOUTME: Run: bash scripts/tests/test-hook-stderr-contract.sh  (exit 0 = all green).

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); printf '  ok   %s\n' "$1"; }
bad() { FAIL=$((FAIL+1)); printf '  FAIL %s\n' "$1"; }

echo "part 1: every wired PreToolUse hook that exits 2 writes to stderr or emits deny JSON"
# A hook passes if it has no exit 2, or it sends output to stderr (>&2, exec 1>&2, sys.stderr),
# or it prints permissionDecision JSON, which the harness reads from stdout.
while IFS= read -r f; do
  [ -f "$f" ] || continue
  verdict="$(perl -e 'local $/; open F, $ARGV[0] or exit; my $s = <F>;
    exit unless $s =~ /exit\s+2\b|sys\.exit\(2\)/;
    print(($s =~ />&2|sys\.stderr|permissionDecision/) ? "ok" : "bad")' "$f")"
  case "$verdict" in
    ok)  ok "${f#"$ROOT"/}" ;;
    bad) bad "${f#"$ROOT"/} exits 2 but never writes to stderr" ;;
  esac
done < <(jq -r '.hooks.PreToolUse[]?.hooks[]?.command' "$ROOT/settings.json" \
           | perl -ne 'print "$1\n" while m{(/\S+\.(?:sh|py))}g' | sort -u)

echo "part 2: commit-order-guard block reason reaches stderr"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/repo" "$TMP/state"; touch "$TMP/state/.active"
git -C "$TMP/repo" init -q -b main
echo "x = 1" > "$TMP/repo/app.py"; git -C "$TMP/repo" add app.py
payload='{"tool_name":"Bash","tool_input":{"command":"git commit -m wip"}}'
out="$(cd "$TMP/repo" && printf '%s' "$payload" | HARNESS_GOV_STATE_DIR="$TMP/state" \
        bash "$ROOT/scripts/governance/commit-order-guard.sh" 2>"$TMP/err")"; rc=$?
if [ "$rc" -eq 2 ]; then ok "guard blocks a code-only commit"; else bad "guard blocks a code-only commit (rc=$rc)"; fi
if grep -q "commit-order-guard" "$TMP/err"; then ok "reason on stderr"; else bad "reason on stderr"; fi
if [ -z "$out" ]; then ok "nothing on stdout"; else bad "nothing on stdout"; fi

printf '=== %d passed, %d failed ===\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
