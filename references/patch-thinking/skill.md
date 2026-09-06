---
name: patch-thinking-settings
description: "Patch ~/.claude/settings.json to force fixed thinking budget (disable adaptive thinking, set max tokens, high effort, visible summaries). Creates timestamped backup. Idempotent."
---

<!-- ABOUTME:
  patch-thinking-settings - Forces fixed reasoning budget in Claude Code.
  Patches ~/.claude/settings.json with env vars and top-level settings.
  Creates a timestamped backup before mutation. Validates JSON before and after.
  Idempotent — safe to invoke repeatedly.
-->

# Patch Thinking Settings

Forces a fixed reasoning budget by patching `~/.claude/settings.json`.

## Settings Applied

| Key | Location | Value | Purpose |
|-----|----------|-------|---------|
| `CLAUDE_CODE_DISABLE_ADAPTIVE_THINKING` | `env` | `"1"` | Forces fixed reasoning budget instead of adaptive |
| `MAX_THINKING_TOKENS` | `env` | `"128000"` | Maximum fixed budget per turn |
| `CLAUDE_CODE_EFFORT_LEVEL` | `env` | `"high"` | Highest priority effort override |
| `showThinkingSummaries` | top-level | `true` | Makes thinking visible in output |

## Procedure

1. **Read** `~/.claude/settings.json`. If it doesn't exist or isn't valid JSON, STOP and tell the user.

2. **Backup.** Copy the file to `~/.claude/backups/settings.json.<YYYYMMDD-HHMMSS>.bak`. Create the `backups/` directory if needed. Tell the user the backup path.

3. **Merge env vars.** Add/overwrite these keys inside the existing `env` object (preserve all other env vars):
   - `"CLAUDE_CODE_DISABLE_ADAPTIVE_THINKING": "1"`
   - `"MAX_THINKING_TOKENS": "128000"`
   - `"CLAUDE_CODE_EFFORT_LEVEL": "high"`

4. **Set top-level key.** Set `"showThinkingSummaries": true` at the root of the JSON object.

5. **Write** the patched JSON back to `~/.claude/settings.json`. Use the Write tool (not Bash). Preserve all other keys — permissions, hooks, plugins, sandbox, etc.

6. **Validate.** Read the file back and confirm it parses as valid JSON. If not, restore from backup immediately.

7. **Report.** Show the user what changed (diff-style: before → after for each key). Remind them to **restart Claude Code** for changes to take effect.

## Idempotency

If all four settings are already at the target values, report "already configured" and skip the backup/write.

## Rollback

If the user asks to undo, restore the most recent backup from `~/.claude/backups/`.
