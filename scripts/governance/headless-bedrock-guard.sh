#!/usr/bin/env bash
# ABOUTME: PreToolUse guard on Bash: denies a command that starts a headless `claude -p` / `--print`
# ABOUTME: unless that command sets CLAUDE_CODE_USE_BEDROCK=1 (prefix, env wrapper, or export).
# ABOUTME: Why: ~/.zshrc unsets the variable, so tool shells fall back to the claude.ai plan. On
# ABOUTME: 2026-10-25, 12 headless runs billed that plan ($71.20) and hit its monthly limit.
# ABOUTME: Kill switch: HARNESS_HEADLESS_BEDROCK_GUARD=0. Tests: scripts/tests/test-headless-bedrock-guard.sh
set -uo pipefail

[ "${HARNESS_HEADLESS_BEDROCK_GUARD:-1}" = "0" ] && exit 0
INPUT="$(cat)"
TOOL="$(printf '%s' "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null)"
[ "$TOOL" = "Bash" ] || exit 0
CMD="$(printf '%s' "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)"
[ -n "$CMD" ] || exit 0

# find_unsafe_launch: print the first segment that runs `claude` headless without Bedrock.
# Usage: python3 - "$CMD". Gotcha: it parses each ; && || | segment with shlex, so `claude -p`
# inside a grep pattern, a perl script or an echo string is an argument, not a launch.
VERDICT="$(python3 - "$CMD" <<'PY'
import re, shlex, sys
cmd = sys.argv[1]
exported = re.search(r'\bexport\s+CLAUDE_CODE_USE_BEDROCK=1\b', cmd) is not None
WRAPPERS = {'env', 'nohup', 'exec', 'time', 'command', 'caffeinate'}
TIMED = {'timeout', 'gtimeout'}
for seg in re.split(r'\|\||&&|[;|\n]', cmd):
    try:
        toks = shlex.split(seg, posix=True)
    except ValueError:
        toks = seg.split()
    bedrock = exported
    i = 0
    while i < len(toks):
        t = toks[i]
        if re.match(r'^[A-Za-z_][A-Za-z0-9_]*=', t):
            if t == 'CLAUDE_CODE_USE_BEDROCK=1':
                bedrock = True
            i += 1
        elif t in WRAPPERS:
            i += 1
        elif t in TIMED:
            i += 2
        elif t.startswith('-') and i > 0 and toks[i - 1] in WRAPPERS:
            i += 1
        else:
            break
    if i < len(toks) and toks[i].rsplit('/', 1)[-1] == 'claude':
        args = toks[i + 1:]
        if any(a in ('-p', '--print') for a in args) and not bedrock:
            print(seg.strip()[:160])
            break
PY
)"
[ -z "$VERDICT" ] && exit 0

# ALLOW: calls via scripts/lib/claude-bedrock.sh or claude_bedrock function
if echo "$VERDICT" | grep -qE 'scripts/lib/claude-bedrock\.sh|claude_bedrock'; then
  exit 0
fi

REASON="Headless claude without Bedrock: \"$VERDICT\". Tool shells unset CLAUDE_CODE_USE_BEDROCK (~/.zshrc), so this run would bill the claude.ai plan. Prefix the launch with CLAUDE_CODE_USE_BEDROCK=1 and use a Bedrock model ID (us.anthropic.claude-opus-5-5), or use scripts/lib/claude-bedrock.sh. Check that the init line's model is a Bedrock ID (us.anthropic.*)."
jq -cn --arg reason "$REASON" \
  '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:$reason}}'
echo "$REASON" >&2
exit 2
