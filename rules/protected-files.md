# Protected Files

These files are critical infrastructure and MUST NOT be deleted, moved, or emptied. (The git-safety hook hard-blocks rm of the first five by name; the harness docs below are protected by policy — deleting them is a protocol violation even though the hook does not yet block it.)
Edit in-place only; slimming content is allowed ONLY via the approval flow in
`~/.claude/docs/plans/harness/maintenance-protocol.md` §1 (show diff, get yes, back up first).

## Protected File List
- `~/.claude/CLAUDE.md` — global user instructions
- `~/.claude/docs/vibe-manual.md` — full VIBE protocol (source of truth)
- `~/.claude/rules/vibe-protocol.md` — VIBE quick reference
- `~/.claude/rules/code-style.md` — engineering standards
- `~/.claude/rules/tool-registry.md` — Office/SharePoint tool routing
- `~/.claude/rules/protected-files.md` — this file (self-protecting)
- `~/.claude/docs/plans/harness/dispatch-protocol.md` — delegation rules (CLAUDE.md routes here)
- `~/.claude/docs/plans/harness/judgment-rubrics.md` — done/escalate/stop rubrics
- `~/.claude/docs/plans/harness/dispatch-templates.md` — delegation templates
- `~/.claude/docs/plans/harness/maintenance-protocol.md` — harness change authority
- `~/.claude/docs/plans/harness/lessons-learned.md` — append-only lessons log (never truncate)

## Rules
1. NEVER `rm`, `git rm`, or overwrite these files with empty content.
2. When promoting a file from a project repo to `~/.claude/`, update all relative path
   references to absolute `~/.claude/` paths (documented pitfall — see MEMORY.md 2026-03-21).
3. If a rule or skill references a doc via relative path, verify it exists at that path
   from `~/.claude/` before proceeding.
4. Path stability is load-bearing: CLAUDE.md and skills route to these exact paths every
   session. Renames require updating every referrer in the same change.
