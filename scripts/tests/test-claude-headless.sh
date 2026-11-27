#!/usr/bin/env bash
# ABOUTME: Test suite for scripts/lib/claude-headless.sh (headless claude on the Claude.ai plan).
# ABOUTME: Covers: Bedrock variables cleared, arguments passed through, sourced and executed modes.
# ABOUTME: Uses a fake `claude` on PATH that prints its env and args, so no real model is called.
# ABOUTME: Usage: bash scripts/tests/test-claude-headless.sh
# ABOUTME: Exit 0 if all tests pass, 1 if any fail.
set -uo pipefail
LIB="$(cd "$(dirname "$0")/../lib" && pwd)/claude-headless.sh"
FAKE="$(mktemp -d)"; trap 'rm -rf "$FAKE"' EXIT
printf '#!/usr/bin/env bash\necho "BEDROCK=${CLAUDE_CODE_USE_BEDROCK:-unset} PROFILE=${AWS_PROFILE:-unset} ARGS=$*"\n' > "$FAKE/claude"
chmod +x "$FAKE/claude"
pass=0; fail=0
check() { if [[ "$2" == *"$3"* ]]; then pass=$((pass+1)); echo "  ok   $1"; else fail=$((fail+1)); echo "  FAIL $1: got '$2'"; fi; }
out="$(PATH="$FAKE:$PATH" CLAUDE_CODE_USE_BEDROCK=1 AWS_PROFILE=x bash "$LIB" -p --model haiku)"
check "executed: Bedrock var cleared" "$out" "BEDROCK=unset"
check "executed: AWS profile cleared" "$out" "PROFILE=unset"
check "executed: args pass through"   "$out" "ARGS=-p --model haiku"
out="$(PATH="$FAKE:$PATH" CLAUDE_CODE_USE_BEDROCK=1 bash -c 'source "$1" && claude_headless -p --model opus' _ "$LIB")"
check "sourced: Bedrock var cleared"  "$out" "BEDROCK=unset"
check "sourced: args pass through"    "$out" "ARGS=-p --model opus"
echo "$pass passed, $fail failed"; [ "$fail" -eq 0 ]
