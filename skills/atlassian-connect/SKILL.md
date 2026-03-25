---
name: atlassian-connect
description: "Add Atlassian MCP (JIRA + Confluence) via `claude mcp add -s project`. Shows in /mcp immediately, no restart needed."
---

<!-- ABOUTME:
  atlassian-connect - On-demand Atlassian MCP provisioning skill.
  Discovers user identity, creates a wrapper script if needed, and registers
  the Atlassian MCP server via `claude mcp add -s project` (.mcp.json).
  Shows in /mcp immediately — no restart needed.
  NEVER use `-s local` (writes to global ~/.claude.json).
-->

# Atlassian MCP On-Demand Connect

Provisions the Atlassian MCP server (JIRA + Confluence) for the current project.

## When to Use

- A skill or task needs `mcp__atlassian__*` tools but they aren't available
- User invokes `/atlassian-connect` explicitly
- The `pm-jira` skill detects missing Atlassian tools

## Procedure

### Step 1: Check if Already Configured

Run `claude mcp list 2>&1 | grep -i atlassian`. If the server already exists and is healthy, inform the user and stop. If it exists but failed, skip to Step 5 (re-add).

### Step 2: Resolve User Identity

Yu-Kuan's Atlassian email is `yklin@diligent.com`. Use this as `ATLASSIAN_USER` — do NOT ask.

### Step 3: Ensure Wrapper Script Exists

Check if `~/.claude/scripts/atlassian-mcp.sh` exists and is executable.

If missing, create it with this content:

```bash
#!/bin/bash
# ABOUTME: Wrapper script that sources shell profile before launching mcp-atlassian.
# Ensures ATLASSIAN_API_TOKEN is available even when Claude Code doesn't
# inherit the full shell environment. Works across bash/zsh users.

# Source the user's shell profile to pick up env vars
for profile in "$HOME/.zshrc" "$HOME/.bashrc" "$HOME/.bash_profile" "$HOME/.profile"; do
  if [ -f "$profile" ]; then
    source "$profile" 2>/dev/null
    break
  fi
done

# Find uvx — check common locations then PATH
UVX=""
for candidate in "$HOME/.local/bin/uvx" "/opt/homebrew/bin/uvx" "/usr/local/bin/uvx"; do
  if [ -x "$candidate" ]; then
    UVX="$candidate"
    break
  fi
done
if [ -z "$UVX" ]; then
  UVX=$(command -v uvx 2>/dev/null)
fi
if [ -z "$UVX" ]; then
  echo "ERROR: uvx not found. Install uv first: https://docs.astral.sh/uv/" >&2
  exit 1
fi

exec "$UVX" mcp-atlassian "$@"
```

Then `chmod +x` it. Also ensure `~/.claude/scripts/` directory exists first (`mkdir -p`).

### Step 4: Verify Prerequisites

Before registering, verify:
1. **uvx is installed:** Run `~/.claude/scripts/atlassian-mcp.sh --help` — should print usage
2. **API token is set:** Run `bash -c 'source ~/.zshrc 2>/dev/null || source ~/.bashrc 2>/dev/null; echo $ATLASSIAN_API_TOKEN'` — should be non-empty

If uvx is missing, tell the user to install uv: `curl -LsSf https://astral.sh/uv/install.sh | sh`

If the API token is missing, tell the user:
> Set `ATLASSIAN_API_TOKEN` in your shell profile (e.g. `~/.zshrc`).
> Generate one at: https://id.atlassian.com/manage-profile/security/api-tokens

Do NOT proceed until both prerequisites pass.

### Step 5: Register MCP Server

**NEVER use `claude mcp add -s local`** — it writes to the global `~/.claude.json`.

Use `-s project` which writes to `.mcp.json` in the repo root (add to `.gitignore` if in a git repo):

```bash
claude mcp remove atlassian -s project 2>/dev/null || true

claude mcp add -s project \
  -e JIRA_URL=https://diligentbrands.atlassian.net \
  -e JIRA_USERNAME=yklin@diligent.com \
  -e CONFLUENCE_URL=https://diligentbrands.atlassian.net \
  -e CONFLUENCE_USERNAME=yklin@diligent.com \
  -- atlassian /Users/yklin/.claude/scripts/atlassian-mcp.sh
```

If the project is a git repo, ensure `.mcp.json` is in `.gitignore`.

### Step 6: Inform User

Tell the user:
1. Atlassian MCP is registered for this project
2. Run **`/mcp`** to connect it in the current session (no restart needed)
3. It will auto-load on future sessions in this project
4. If tools still don't load, check that `ATLASSIAN_API_TOKEN` is exported in their shell profile

## Removing Atlassian from a Project

Run: `claude mcp remove atlassian -s project`
