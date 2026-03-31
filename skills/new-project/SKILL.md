---
name: new-project
description: Scaffold a project with standardized Claude Code integration files (.claude/, CLAUDE.md, memory/, qa/, docs/)
argument-hint: "[project-path]"
allowed-tools: ["Bash", "Read", "Write", "Edit", "AskUserQuestion"]
---

# Project Scaffolding

Bootstrap a project directory with standardized Claude Code integration files so every repo starts with consistent VIBE protocol support.

**Argument (optional):** "$ARGUMENTS" — project path. If absent, ask.

## Step 1: Gather Requirements

Use `AskUserQuestion` for each unknown. Do NOT assume defaults.

1. **Project path** — Absolute path to the project root. Use $ARGUMENTS if provided.
2. **Project name** — Human-readable name (used in CLAUDE.md header).
3. **VIBE level** — `full` (production app, all gates) or `light` (tooling/scripts, relaxed gates). Explain the difference if asked.
4. **Project type** — One of:
   - `python-backend` — Python service (FastAPI, Flask, etc.)
   - `nodejs` — Node.js / TypeScript project
   - `fullstack` — Combined frontend + backend
   - `script-tooling` — Scripts, CLI tools, config repos
5. **MCP config needed?** — Yes/No. If yes, which servers? (Atlassian, Chrome DevTools, filesystem, etc.)

## Step 2: Validate

- Verify the project path exists: `ls -d <path>`. Create it if it does not exist (confirm first).
- Check if `.claude/` already exists — warn and ask before overwriting anything.

## Step 3: Generate Files

Create these files in the project directory. Use `Write` for each.

### Required (all projects)

**`.claude/phase.json`**
```json
{
  "phase": "DISCOVERY",
  "vibe_level": "<full|light>"
}
```

**`.claude/settings.json`**
```json
{
  "permissions": {
    "allow": [],
    "deny": []
  }
}
```

**`CLAUDE.md`** — Replace `<PROJECT_NAME>` with actual name:
```markdown
# ABOUTME: Project-level Claude Code instructions.
# ABOUTME: Defines context, tech stack, conventions.
# ABOUTME: Imports global rules from ~/.claude/.
# ABOUTME: Update as the project evolves.
# ABOUTME: Created by /new-project scaffolding skill.

# <PROJECT_NAME>

## Project Description
TODO: Add project description.

## Tech Stack
TODO: Add tech stack.

## Project Structure
TODO: Add project structure overview.

## Development
TODO: Add development commands.

## Conventions
Follows global engineering standards from `~/.claude/rules/code-style.md`.
```

**`memory/lessons.md`**
```markdown
# ABOUTME: Project-specific lessons learned and patterns.
# ABOUTME: Captures mistakes, decisions, and insights.
# ABOUTME: Append-only — never delete entries.
# ABOUTME: Read by agents to avoid repeating errors.
# ABOUTME: Created by /new-project scaffolding skill.

# Lessons Learned
```

**`qa/.gitkeep`** — Empty directory for QA artifacts.

### Conditional (full VIBE only)

If vibe_level is `full`, also create `docs/contracts/.gitkeep` and `docs/plans/.gitkeep`.

### Conditional (MCP config)

If MCP servers are needed, create **`.claude/settings.local.json`**:
```json
{ "mcpServers": { "<server-name>": { "command": "<cmd>", "args": [], "env": {} } } }
```

Known servers:
- **atlassian** — `npx @anthropic/atlassian-mcp-server`, env: `ATLASSIAN_SITE_URL`, `ATLASSIAN_USER_EMAIL`, `ATLASSIAN_API_TOKEN`
- **chrome-devtools** — `npx @anthropic/chrome-devtools-mcp-server`
- **filesystem** — `npx @anthropic/filesystem-mcp-server` with path args

For unknown servers, leave a placeholder with TODO.

## Step 4: Git Init

Run `git -C <path> rev-parse --is-inside-work-tree 2>/dev/null`.

- **Not a repo** — Ask: "Initialize git repository?" If yes, run `git init && git add -A && git commit -m "Initial scaffold from /new-project"` in the project dir.
- **Already a repo** — Ask if the user wants to commit the scaffolding files.

## Step 5: Summary

Print a summary listing every file and directory created:

```
Scaffolded <PROJECT_NAME> at <path>:

  .claude/phase.json          — DISCOVERY phase, <vibe_level> level
  .claude/settings.json       — Project settings
  CLAUDE.md                   — Project context (fill in TODOs)
  memory/lessons.md           — Lessons learned log
  qa/                         — QA artifacts directory
  [docs/contracts/]           — API contracts (full VIBE only)
  [docs/plans/]               — Feature specs (full VIBE only)
  [.claude/settings.local.json] — MCP server config

Next steps:
  1. Fill in the TODOs in CLAUDE.md
  2. Begin DISCOVERY phase — interview and scope the project
```
