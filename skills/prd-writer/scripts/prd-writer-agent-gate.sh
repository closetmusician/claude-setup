#!/bin/bash
# ABOUTME: PreToolUse hook for Agent tool — sentinel-gated template enforcement for prd-writer.
# Purpose: When prd-writer sentinels are active, verify Agent prompts reference required templates.
# Usage: Configured as PreToolUse hook on "Agent" in settings.json. Receives tool input JSON on stdin.
# Gotchas: Exits 0 (allow) when no sentinels active. Only enforces during prd-writer drafting step.

# Fast bail-out: no sentinel directory means prd-writer is not active
GATE_DIR="docs/.prd-writer"
if [ ! -d "$GATE_DIR" ]; then
  exit 0
fi

# Check for active sentinel files
GATE_DRAFT="$GATE_DIR/.gate-prd-draft"
GATE_INTERVIEW="$GATE_DIR/.gate-interview-complete"

# If no sentinels exist, nothing to enforce
if [ ! -f "$GATE_DRAFT" ] && [ ! -f "$GATE_INTERVIEW" ]; then
  exit 0
fi

# Read the Agent tool input from stdin
INPUT=$(cat)

# Extract the prompt field
PROMPT=$(echo "$INPUT" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
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

if [ -f "$GATE_DRAFT" ]; then
  # The drafting sentinel requires that the subagent prompt references the scaffold or template
  if ! echo "$PROMPT" | grep -qi "prd-scaffold\|acme-prd-template\|prd-lite-template"; then
    echo "PRD-WRITER AGENT GATE: Sentinel .gate-prd-draft is active (Step 4 — Draft)."
    echo ""
    echo "Your Agent prompt does NOT reference the PRD scaffold or template."
    echo "You MUST either:"
    echo "  1. Include the scaffold content from ~/.claude/skills/prd-writer/templates/prd-scaffold.md"
    echo "  2. OR reference acme-prd-template.md in the subagent prompt"
    echo ""
    echo "This prevents structural amnesia after long Q&A sessions."
    echo "Re-read SKILL.md Step 4 instructions before spawning the drafting subagent."
    exit 2
  fi

  # Also verify interview context file is referenced (checkpoint from Step 2)
  if ! echo "$PROMPT" | grep -qi "interview\|context\.md\|checkpoint"; then
    echo "PRD-WRITER AGENT GATE: Sentinel .gate-prd-draft is active (Step 4 — Draft)."
    echo ""
    echo "Your Agent prompt does NOT reference the interview checkpoint file."
    echo "The drafting subagent MUST receive the interview context to produce an accurate PRD."
    echo "Include the <working-name>-interview.md checkpoint in the subagent prompt."
    exit 2
  fi
fi

if [ -f "$GATE_INTERVIEW" ]; then
  # Interview completion gate: verify all 9 mandatory questions were answered
  # This sentinel is set before Step 2 starts; removed after interview checkpoint is written
  # If spawning an agent during interview, it should reference the interview protocol
  if ! echo "$PROMPT" | grep -qi "M1\|M2\|M3\|interview\|mandatory.*question"; then
    echo "PRD-WRITER AGENT GATE: Sentinel .gate-interview-complete is active (Step 2 — Interview)."
    echo ""
    echo "Interview is still in progress. Complete all 9 mandatory questions (M1-M9)"
    echo "and write the interview checkpoint before spawning drafting agents."
    exit 2
  fi
fi

# All checks passed
exit 0
