# Protected Files

These files are critical infrastructure and MUST NOT be deleted, moved, or emptied.
Any agent or session that needs to modify them should edit in-place only.

## Protected File List
- `~/.claude/docs/vibe-manual.md` — Full VIBE protocol manual (source of truth)
- `~/.claude/rules/vibe-protocol.md` — VIBE protocol quick reference
- `~/.claude/rules/code-style.md` — Engineering standards
- `~/.claude/rules/protected-files.md` — This file (self-protecting)
- `~/.claude/CLAUDE.md` — Global user instructions

## Rules
1. NEVER `rm`, `git rm`, or overwrite these files with empty content.
2. When promoting a file from a project repo to `~/.claude/`, update all relative path references to absolute `~/.claude/` paths.
3. If a rule or skill references a doc via relative path, verify the file exists at that path from `~/.claude/` before proceeding.
