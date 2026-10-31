#!/usr/bin/env bash
# ABOUTME: PreToolUse guard for the Workflow tool — enforces that every agent() call in
# ABOUTME: a workflow script has an explicit model option. Reads the script from tool_input.script,
# ABOUTME: tool_input.scriptPath, or resolves a named workflow. Denies when any agent() call
# ABOUTME: lacks `model:` within its argument span. Rule: every `agent(` must have `model:`
# ABOUTME: before its closing `)`. Escape hatches: MODEL-ROLE-EXEMPT in the script, or env
# ABOUTME: HARNESS_WORKFLOW_MODEL_GUARD=0.

set -uo pipefail
trap 'exit 0' ERR

# Escape hatch 1: session-wide kill switch
[ "${HARNESS_WORKFLOW_MODEL_GUARD:-1}" = "0" ] && exit 0

if ! command -v jq >/dev/null 2>&1; then
  echo "workflow-model-guard: jq not found — model enforcement is NOT active" >&2
  exit 0
fi

INPUT="$(cat 2>/dev/null)" || INPUT=""
[ -z "$INPUT" ] && exit 0
printf '%s' "$INPUT" | jq -e . >/dev/null 2>&1 || exit 0

TOOL="$(printf '%s' "$INPUT" | jq -r '.tool_name // empty')"
[ "$TOOL" != "Workflow" ] && exit 0

TOOL_INPUT="$(printf '%s' "$INPUT" | jq -c '.tool_input // {}')"

# Escape hatch 2: MODEL-ROLE-EXEMPT in the script itself (checked after reading it)
SCRIPT=""
SCRIPT_INLINE="$(printf '%s' "$TOOL_INPUT" | jq -r '.script // empty')"
SCRIPT_PATH="$(printf '%s' "$TOOL_INPUT" | jq -r '.scriptPath // empty')"
WF_NAME="$(printf '%s' "$TOOL_INPUT" | jq -r '.name // empty')"

if [ -n "$SCRIPT_INLINE" ]; then
  SCRIPT="$SCRIPT_INLINE"
elif [ -n "$SCRIPT_PATH" ]; then
  if [ -f "$SCRIPT_PATH" ]; then
    SCRIPT="$(cat "$SCRIPT_PATH" 2>/dev/null)" || SCRIPT=""
  else
    echo "workflow-model-guard: scriptPath '${SCRIPT_PATH}' not found — allowing (cannot verify)" >&2
    exit 0
  fi
elif [ -n "$WF_NAME" ]; then
  # Named workflows are saved in the harness; we can't resolve them here without knowing the
  # workflows directory. Allow with a note rather than breaking named workflows.
  echo "workflow-model-guard: named workflow '${WF_NAME}' cannot be resolved here — allowing (cannot verify)" >&2
  exit 0
else
  echo "workflow-model-guard: no script, scriptPath, or name in tool_input — allowing" >&2
  exit 0
fi

# Check escape hatch
if printf '%s' "$SCRIPT" | grep -q 'MODEL-ROLE-EXEMPT'; then
  exit 0
fi

# Parse agent() calls and check for model option.
# Strategy: find all agent( occurrences, then for each, extract the span until its matching )
# and check if `model:` appears within it. This handles multi-line calls and nested parens.
# We use a simple heuristic: remove string literals and comments first, then search.

# Step 1: strip string literals and comments to avoid false matches
CLEAN="$(printf '%s' "$SCRIPT" \
  | perl -0777 -pe 's|//.*$||mg' \
  | perl -0777 -pe 's|/\*.*?\*/||gs' \
  | perl -0777 -pe "s/'(?:[^'\\\\]|\\\\.)*'/__STR__/g" \
  | perl -0777 -pe 's/"(?:[^"\\]|\\.)*"/__STR__/g' \
  | perl -0777 -pe 's/`(?:[^`\\]|\\.)  *`/__STR__/g')"

# Step 2: find all agent( calls and check each for model:
# We'll use perl to extract each agent(...) span and check it.
VIOLATIONS="$(printf '%s' "$CLEAN" | perl -0777 -ne '
  while (/\bagent\s*\(/g) {
    my $start = pos($_);
    my $depth = 1;
    my $span = "";
    while ($depth > 0 && $start < length($_)) {
      my $c = substr($_, $start, 1);
      $span .= $c;
      $depth++ if $c eq "(";
      $depth-- if $c eq ")";
      $start++;
    }
    # Check if model: appears in this span (outside of strings, which we removed)
    if ($span !~ /\bmodel\s*:/) {
      print "agent() call without model\n";
    }
  }
')"

if [ -n "$VIOLATIONS" ]; then
  jq -n --arg reason "WORKFLOW MODEL GUARD: every agent() call in a workflow script must have an explicit model option. Found agent() calls without model. Add model: \"sonnet\" (or haiku/opus) to each agent() call. Override: add MODEL-ROLE-EXEMPT to the script, or set HARNESS_WORKFLOW_MODEL_GUARD=0." \
    '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:$reason}}'
  exit 2
fi

exit 0
