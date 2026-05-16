#!/bin/bash
# ABOUTME: PreToolUse hook for Agent tool — sentinel-gated template enforcement.
# Purpose: When eng-planning sentinels are active, verify Agent prompts reference required templates.
# Usage: Configured as PreToolUse hook on "Agent" in settings.json. Receives tool input JSON on stdin.
# Gotchas: Exits 0 (allow) when no sentinels active. Only enforces during eng-planning steps.

# Fast bail-out: no sentinel directory means eng-planning is not active
GATE_DIR="docs/.eng-planning"
if [ ! -d "$GATE_DIR" ]; then
  exit 0
fi

# Check for any active sentinel files
GATE_DESIGN="$GATE_DIR/.gate-design-doc"
GATE_TRACE="$GATE_DIR/.gate-traceability"
GATE_QUALITY="$GATE_DIR/.gate-quality"

# If no sentinels exist, nothing to enforce
if [ ! -f "$GATE_DESIGN" ] && [ ! -f "$GATE_TRACE" ] && [ ! -f "$GATE_QUALITY" ]; then
  exit 0
fi

# Read the Agent tool input from stdin
INPUT=$(cat)

# Extract the prompt field (handle both quoted and unquoted)
# Use python for reliable JSON parsing (available on macOS)
PROMPT=$(echo "$INPUT" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    # Handle both direct input and nested tool_input
    if 'prompt' in data:
        print(data['prompt'])
    elif 'tool_input' in data and 'prompt' in data['tool_input']:
        print(data['tool_input']['prompt'])
    else:
        print('')
except:
    print('')
" 2>/dev/null)

# If we couldn't parse the prompt, allow (don't block on parse failure)
if [ -z "$PROMPT" ]; then
  exit 0
fi

# --- Gate checks ---

if [ -f "$GATE_DESIGN" ]; then
  if ! echo "$PROMPT" | grep -qi "design-doc-template\|design-doc-scaffold"; then
    echo "ENG-PLANNING AGENT GATE: Sentinel .gate-design-doc is active (Step 5a)."
    echo ""
    echo "Your Agent prompt does NOT reference the design doc template or scaffold."
    echo "You MUST either:"
    echo "  1. Include the scaffold content from ~/.claude/skills/eng-planning/templates/design-doc-scaffold.md"
    echo "  2. OR reference design-doc-template.md in the subagent prompt"
    echo ""
    echo "Re-read SKILL.md Step 5a instructions before spawning the artifact subagent."
    exit 2
  fi
fi

if [ -f "$GATE_TRACE" ]; then
  if ! echo "$PROMPT" | grep -qi "traceability-pipeline\|traceability"; then
    echo "ENG-PLANNING AGENT GATE: Sentinel .gate-traceability is active (Step 7.5 or 12)."
    echo ""
    echo "Your Agent prompt does NOT reference the traceability pipeline template."
    echo "You MUST read ~/.claude/skills/eng-planning/templates/traceability-pipeline.md"
    echo "and include it in the subagent prompt."
    echo ""
    echo "Re-read SKILL.md Step 7.5/12 instructions."
    exit 2
  fi
fi

if [ -f "$GATE_QUALITY" ]; then
  if ! echo "$PROMPT" | grep -qi "quality-synthesis"; then
    echo "ENG-PLANNING AGENT GATE: Sentinel .gate-quality is active (Step 7.6)."
    echo ""
    echo "Your Agent prompt does NOT reference the quality synthesis template."
    echo "You MUST read ~/.claude/skills/eng-planning/templates/quality-synthesis-prompt.md"
    echo "and include it in the subagent prompt."
    echo ""
    echo "Re-read SKILL.md Step 7.6 instructions."
    exit 2
  fi
fi

# All checks passed
exit 0
