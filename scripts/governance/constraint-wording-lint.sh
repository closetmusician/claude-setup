#!/usr/bin/env bash
# ABOUTME: PreToolUse/Agent hook: WARN-ONLY lint for unqualified absolute constraint wording.
# ABOUTME: Flags absolute prohibition phrases in ## Constraints sections that lack an inline
# ABOUTME: exception clause (EXCEPT/except the/authorized/packet authorizes), which can cause
# ABOUTME: downstream classifiers to over-block sanctioned operations (H-32 / lane6 PROP-3).
# ABOUTME: Fail-open on ALL errors; NEVER blocks a spawn (exit 0 always).

set -uo pipefail

# Safety net: never block on any hook failure.
trap 'exit 0' ERR

# Bail gracefully if jq is missing.
if ! command -v jq &>/dev/null; then
  exit 0
fi

# ─── Read full payload from stdin (never env) ───────────────────────────────
PAYLOAD="$(cat)"

# ─── Only inspect Agent tool calls ──────────────────────────────────────────
TOOL_NAME="$(printf '%s' "$PAYLOAD" | jq -r '.tool_name // empty' 2>/dev/null)"
if [[ "$TOOL_NAME" != "Agent" ]]; then
  exit 0
fi

# ─── Extract prompt ──────────────────────────────────────────────────────────
PROMPT="$(printf '%s' "$PAYLOAD" | jq -r '.tool_input.prompt // empty' 2>/dev/null)"
if [[ -z "$PROMPT" ]]; then
  exit 0
fi

# ─── Only scan prompts that contain a ## Constraints section ─────────────────
if ! printf '%s' "$PROMPT" | grep -q '## Constraints'; then
  exit 0
fi

# ─── Extract the ## Constraints body ─────────────────────────────────────────
CONSTRAINTS_BODY="$(printf '%s' "$PROMPT" | sed -n '/^## Constraints/,/^## /{/^## Constraints/d; /^## /d; p;}')"

# ─── Qualifier patterns that suppress a warning ──────────────────────────────
# If any of these appear near an absolute phrase, it's already qualified.
QUALIFIER_RE='EXCEPT|except the|authorized|packet authorizes'

# ─── Absolute prohibition patterns to flag ───────────────────────────────────
# Drawn directly from the two observed over-block incidents (H-32).
ABSOLUTE_PATTERNS=(
  "MOVES only"
  "do not edit"
  "never write files"
  "no Bash"
  "never use"
)

# ─── Scan for unqualified absolute phrases ───────────────────────────────────
WARNINGS=()
for PATTERN in "${ABSOLUTE_PATTERNS[@]}"; do
  # Check if the constraints body contains this absolute phrase (case-insensitive)
  if printf '%s' "$CONSTRAINTS_BODY" | grep -qi "$PATTERN"; then
    # Check if a qualifier appears anywhere in the constraints body
    if ! printf '%s' "$CONSTRAINTS_BODY" | grep -qiE "$QUALIFIER_RE"; then
      WARNINGS+=("$PATTERN")
    fi
  fi
done

# ─── If no warnings, allow silently ──────────────────────────────────────────
if [[ "${#WARNINGS[@]}" -eq 0 ]]; then
  exit 0
fi

# ─── Emit additionalContext warning (NEVER a deny decision) ──────────────────
FIRST_WARN="${WARNINGS[0]}"
WARN_TEXT="[constraint-wording-lint] Constraint phrase \"${FIRST_WARN}\" is unqualified; add its inline exception (e.g. '${FIRST_WARN}, EXCEPT the rows this packet authorizes') so a downstream classifier does not block sanctioned edits. This is an advisory warning only — the spawn is not blocked."

# Append any additional unqualified patterns
if [[ "${#WARNINGS[@]}" -gt 1 ]]; then
  for i in "${!WARNINGS[@]}"; do
    [[ "$i" -eq 0 ]] && continue
    WARN_TEXT="${WARN_TEXT} | Also unqualified: \"${WARNINGS[$i]}\""
  done
fi

jq -cn \
  --arg ctx "$WARN_TEXT" \
  '{
    "hookSpecificOutput": {
      "hookEventName": "PreToolUse",
      "permissionDecision": "allow",
      "additionalContext": $ctx
    }
  }'

exit 0
