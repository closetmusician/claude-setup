#!/usr/bin/env bash
# ABOUTME: Tests for scripts/method-lint-hook.sh (PostToolUse, warn-only, fail-open).
# ABOUTME: Feeds real PostToolUse stdin JSON ({tool_name, tool_input.file_path}).
# ABOUTME: Cases: finding -> additionalContext; clean doc, excluded path, non-doc file,
# ABOUTME: missing file, malformed and empty payload -> silent exit 0.
# ABOUTME: Run: bash ~/.claude/scripts/tests/test-method-lint-hook.sh
set -uo pipefail
HOOK="$(cd "$(dirname "$0")/.." && pwd)/method-lint-hook.sh"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
pass=0; fail=0

# Purpose: run the hook on a payload and check exit code and output. Usage: check name payload expect
# Gotchas: expect is "ctx" (must emit additionalContext) or "silent" (must print nothing).
check() {
  local name="$1" payload="$2" expect="$3" out rc
  out="$(printf '%s' "$payload" | bash "$HOOK" 2>/dev/null)"; rc=$?
  if [ $rc -ne 0 ]; then echo "FAIL $name (rc=$rc)"; fail=$((fail+1)); return; fi
  if [ "$expect" = ctx ]; then
    if printf '%s' "$out" | jq -e '.hookSpecificOutput.hookEventName=="PostToolUse" and (.hookSpecificOutput.additionalContext|test("method-lint"))' >/dev/null 2>&1; then
      pass=$((pass+1)); else echo "FAIL $name (no context: $out)"; fail=$((fail+1)); fi
  else
    if [ -z "$out" ]; then pass=$((pass+1)); else echo "FAIL $name (unexpected: $out)"; fail=$((fail+1)); fi
  fi
}
pl() { jq -n --arg t "$1" --arg f "$2" '{session_id:"s1",hook_event_name:"PostToolUse",tool_name:$t,tool_input:{file_path:$f}}'; }

mkdir -p "$T/docs/evidence"
printf '# Report\n\n## Method\n\nWe searched 20 queries.\n' > "$T/docs/bad.md"
printf '<h2>How we counted</h2><p>ok</p>\n' > "$T/docs/bad.html"
printf '# Report\n\nAsks rose 31%%.\n' > "$T/docs/good.md"
cp "$T/docs/bad.md" "$T/docs/evidence/bad.md"
cp "$T/docs/bad.md" "$T/docs/verification.md"
printf 'print("we searched")\n' > "$T/docs/x.py"

check "write md with method -> context"   "$(pl Write "$T/docs/bad.md")"  ctx
check "edit html with method -> context"  "$(pl Edit "$T/docs/bad.html")" ctx
check "clean md -> silent"                "$(pl Write "$T/docs/good.md")" silent
check "evidence/ path -> silent"          "$(pl Write "$T/docs/evidence/bad.md")" silent
check "verification.md -> silent"         "$(pl Write "$T/docs/verification.md")" silent
check "non-doc file -> silent"            "$(pl Write "$T/docs/x.py")" silent
check "missing file -> silent"            "$(pl Write "$T/docs/nope.md")" silent
check "malformed json -> silent"          '{not json' silent
check "empty payload -> silent"           '' silent
out="$(pl Write "$T/docs/bad.md" | HARNESS_METHOD_LINT=0 bash "$HOOK")"
if [ -z "$out" ]; then pass=$((pass+1)); else echo "FAIL kill switch env"; fail=$((fail+1)); fi

echo "method-lint-hook: pass=$pass fail=$fail"
[ $fail -eq 0 ]
