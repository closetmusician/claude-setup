---
name: handoff
description: Losslessly compress session status, progress, learnings, todos, and key files into <15 lines. Writes one handoff per Claude session id (so parallel sessions on one repo never clobber each other) + copies to clipboard.
argument-hint: "[output-file.md]"
---

# Session Handoff

Losslessly compress latest status & progress, key learnings, todos, and key files into <15 lines in the terminal. Write to the session's handoff file and copy to clipboard.

Each handoff belongs to ONE Claude session, not to a repo. Many sessions can work in one repo at once; each gets its own file.

## Arguments

- **`[path]`** (optional): Extra output path (any .md file). If just a filename, writes to cwd. The session-keyed file below is always written too, so pickup still works.

Default path: `~/.claude/handoffs/<PROJECT_SLUG>/<SESSION_ID>.md`
- `SESSION_ID` = `$CLAUDE_CODE_SESSION_ID` (set in every Bash call). If it is empty, use `nosession-$(date +%Y%m%d-%H%M%S)` and say so.
- `PROJECT_SLUG` = `basename $(git rev-parse --show-toplevel 2>/dev/null || pwd)`. It only groups files; it never selects one.

Why a PID pointer too: `/clear` starts a NEW session id in the SAME Claude process (verified 2026-11-16: PID 61638 went from session 92405b76 to d0513f0d). The pointer `~/.claude/handoffs/.by-pid/$CLAUDE_PID` lets the cleared session find the exact handoff its own terminal wrote. Pickup rules: `~/.claude/rules/session-handoff.md`.

## Procedure

### Step 1: Reflect on the conversation

No git commands. Compress from conversation context only:
- What did the user ask for?
- What was completed?
- What was learned or discovered?
- What decisions were made (and why)?
- What's unfinished or blocked?
- What should the next session pick up?
- What key files were created or modified?

### Step 2: Compress into handoff format

Write **exactly this format**, max 15 lines total. Every field mandatory — write `none` if empty. Use semicolons to pack multiple items per line. No prose, no filler, no markdown headers.

```
HANDOFF <YYYY-MM-DD> | <project-slug> | session <SESSION_ID>
DONE: <completed work; semicolon-separated>
LEARNED: <key insights, discoveries, gotchas>
DECIDED: <decisions made + why, compressed>
TODO: <remaining work from this session>
BLOCKED: <blockers, or "none">
FILES: <key files touched w/ 3-word change summaries>
NEXT: <what to start with next session>
CTX: <anything else a cold-start session needs; omit if nothing>
```

**Compression rules:**
- Strip all articles (a, an, the) and filler words
- Use semicolons not bullets
- File paths: use basename or shortest unambiguous path
- Decisions: `chose X over Y because Z` format
- If a field would exceed 2 lines, you're not compressing hard enough

### Step 3: Write and copy

```bash
SID="${CLAUDE_CODE_SESSION_ID:-nosession-$(date +%Y%m%d-%H%M%S)}"
SLUG=$(basename "$(git rev-parse --show-toplevel 2>/dev/null || pwd)")
OUT="$HOME/.claude/handoffs/$SLUG/$SID.md"
mkdir -p "$(dirname "$OUT")" "$HOME/.claude/handoffs/.by-pid"

# Write the handoff
cat > "$OUT" << 'HANDOFF_EOF'
<your compressed block here>
HANDOFF_EOF

# Pointer for the /clear case (same process, new session id)
[ -n "$CLAUDE_PID" ] && printf '%s\n' "$OUT" > "$HOME/.claude/handoffs/.by-pid/$CLAUDE_PID"

# Optional extra copy if the user gave a path
# cp "$OUT" "<user-path>"

pbcopy < "$OUT"
```

Then print TWO lines:
- `Handoff saved ($OUT) + copied.`
- `Resume: /clear here, or "claude --resume $SID", or in any new session say "pick up handoff $SID".`

## Anti-patterns

- Don't run git commands — too slow, derive everything from conversation context
- Don't include full file contents or diffs — just names + what changed
- Don't write a narrative summary — this is structured data for a machine (the next Claude session)
- Don't exceed 15 lines. If you're over, compress harder. Every line should be information-dense.
- Don't include information already in memory files — handoff is for *session-specific* state
- Don't include learnings that should be permanent — save those to memory first, then exclude from handoff
