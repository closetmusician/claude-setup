# Session Handoff Auto-Pickup

A handoff belongs to ONE Claude session, not to a repo. Many sessions can share a repo, so
never load a handoff just because it sits in the same project folder.

Files: `~/.claude/handoffs/<project-slug>/<session-id>.md`, written by `/handoff`.
Pointer: `~/.claude/handoffs/.by-pid/<CLAUDE_PID>` holds the path of the last handoff that
this Claude process wrote. `/clear` keeps the process (same `CLAUDE_PID`) but starts a new
session id, so the pointer is how a cleared session finds its own handoff.

At conversation start (including after `/clear`), check in this order and stop at the first hit:

1. **The user names a session id** ("pick up handoff <id>"): run the snippet below with `CLAUDE_CODE_SESSION_ID=<id>`.
2. **A resumed session** (`claude --resume <id>`): run the snippet below as is.
3. **After `/clear` in the same terminal**: load the path in `.by-pid/$CLAUDE_PID`, then delete the pointer.

```bash
H=~/.claude/handoffs
F=$(find "$H" -mindepth 2 -maxdepth 2 -name "$CLAUDE_CODE_SESSION_ID.md" 2>/dev/null | head -1)   # not a glob: * skips dot-folders like .claude
P="$H/.by-pid/$CLAUDE_PID"
if [ -z "$F" ] && [ -n "$CLAUDE_PID" ] && [ -f "$P" ]; then F=$(cat "$P"); rm -f "$H/.by-pid/$CLAUDE_PID"; fi
[ -n "$F" ] && [ -f "$F" ] && find "$F" -mmin -2880 | head -1   # prints the path only if <48h old
```

- If a match is **<48 hours old**: read it silently. Weave its context into your reply to the user's first message. Don't dump the raw block. The handoff is now consumed; don't mention it again unless asked.
- Case 1 has no age limit, because the user asked for that handoff by name.
- If a match is **>48 hours old**, or nothing matches: do nothing.
- Flat files from before 2026-11-16 (`handoffs/<slug>.md`) are never auto-loaded. Load one only when the user asks for it.
