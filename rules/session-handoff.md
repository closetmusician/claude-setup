# Session Handoff Auto-Pickup

At conversation start (including after `/clear`), derive the project slug and check for a matching handoff:

```bash
PROJECT_SLUG=$(basename "$(git rev-parse --show-toplevel 2>/dev/null || pwd)")
# Check: ~/.claude/handoffs/$PROJECT_SLUG.md
```

- If it exists and is **<48 hours old**: read it silently. When the user's first message arrives, weave relevant context into your response naturally — don't dump the raw block. The handoff has been consumed; don't reference it again unless asked.
- If it exists and is **>48 hours old**: ignore it (stale).
- If it doesn't exist: do nothing.

Handoff files are project-keyed so parallel sessions across different repos don't clobber each other.
