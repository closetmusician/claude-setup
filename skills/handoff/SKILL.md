---
name: handoff
description: Losslessly compress session status, progress, learnings, todos, and key files into <15 lines. Writes to specified md file + copies to clipboard.
argument-hint: "<output-file.md>"
---

# Session Handoff

Losslessly compress latest status & progress, key learnings, todos, and key files into <15 lines in the terminal. Write to the specified file and copy to clipboard.

## Arguments

- **`<path>`** (required): Output file path (any .md file). If just a filename, writes to cwd.

If no path given, derive a default: `~/.claude/handoffs/<PROJECT_SLUG>.md` where slug = `basename $(git rev-parse --show-toplevel 2>/dev/null || pwd)`.

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
HANDOFF <YYYY-MM-DD> | <project-slug>
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
# Ensure parent dir exists
mkdir -p "$(dirname "<output-path>")"

# Write the handoff
cat > "<output-path>" << 'HANDOFF_EOF'
<your compressed block here>
HANDOFF_EOF

# Copy to clipboard
cat "<output-path>" | pbcopy
```

Then print ONE line: `Handoff saved (<output-path>) + copied.`

## Anti-patterns

- Don't run git commands — too slow, derive everything from conversation context
- Don't include full file contents or diffs — just names + what changed
- Don't write a narrative summary — this is structured data for a machine (the next Claude session)
- Don't exceed 15 lines. If you're over, compress harder. Every line should be information-dense.
- Don't include information already in memory files — handoff is for *session-specific* state
- Don't include learnings that should be permanent — save those to memory first, then exclude from handoff
