#!/usr/bin/env bash
# ABOUTME: PostToolUse hook to stop Codex brokers after foreground task/review calls.
# ABOUTME: Acts only on foreground codex-companion.mjs task/review/adversarial-review commands.
# ABOUTME: Runs the helper detached so the hook returns in under 1 second.
# ABOUTME: Written 2026-11-22 per codex-broker-cleanup-spec.md. Fail-open.
# ABOUTME: Wired in ~/.claude/settings.json under hooks.PostToolUse with matcher Bash.

# No `set -e`: a hook must always exit 0, even on bad input (Codex review P2, 2026-11-23).
set -u

# Parse hook input from stdin. A jq error leaves the field empty, and the checks below exit 0.
payload="$(cat)"

# Extract tool input fields.
tool_name="$(printf '%s' "$payload" | jq -r '.tool_name // empty' 2>/dev/null)"
command="$(printf '%s' "$payload" | jq -r '.tool_input.command // empty' 2>/dev/null)"
run_in_background="$(printf '%s' "$payload" | jq -r '.tool_input.run_in_background // false' 2>/dev/null)"
cwd="$(printf '%s' "$payload" | jq -r '.cwd // empty' 2>/dev/null)"

# Act only on Bash tool calls.
if [[ "$tool_name" != "Bash" ]]; then
  exit 0
fi

# Act only on codex-companion.mjs commands with task/review/adversarial-review.
if [[ ! "$command" =~ codex-companion\.mjs ]]; then
  exit 0
fi

if [[ ! "$command" =~ (task|review|adversarial-review) ]]; then
  exit 0
fi

# Skip background commands.
if [[ "$command" =~ --background ]]; then
  exit 0
fi

if [[ "$run_in_background" == "true" ]]; then
  exit 0
fi

# Determine workspace folder.
# If the command starts with "cd <path> &&", use that path.
# Otherwise use .cwd from the hook input.
# Bash regex has no back-references, so each quote style gets its own pattern.
folder="$cwd"
re_dq='^cd[[:space:]]+"([^"]+)"[[:space:]]*&&'
re_sq="^cd[[:space:]]+'([^']+)'[[:space:]]*&&"
re_plain='^cd[[:space:]]+([^[:space:]&;]+)[[:space:]]*&&'
if [[ "$command" =~ $re_dq ]] || [[ "$command" =~ $re_sq ]] || [[ "$command" =~ $re_plain ]]; then
  folder="${BASH_REMATCH[1]}"
  # Expand a leading ~.
  [[ "$folder" == "~"* ]] && folder="${HOME}${folder:1}"
fi
[[ -z "$folder" ]] && exit 0

# Run the helper detached.
nohup node "$HOME/.claude/scripts/codex-broker-stop.mjs" "$folder" >/dev/null 2>&1 &

exit 0
