---
name: glean-connect
description: "Add Glean MCP (enterprise search) to the current project's settings.local.json so it loads on next session start. Use when you need Glean search tools but they aren't loaded."
---

<!-- ABOUTME:
  glean-connect - On-demand Glean MCP provisioning skill.
  Writes the Glean MCP server config into the current project's settings.local.json.
  MCP servers load at session start, so a restart is required after running this.
  Keeps Glean tools out of projects that don't need enterprise search.
-->

# Glean MCP On-Demand Connect

Provisions the Glean MCP server (enterprise search) for the current project.

## When to Use

- A task needs Glean enterprise search but tools aren't available
- User invokes `/glean-connect` explicitly
- A skill detects missing Glean tools

## Procedure

1. **Determine the project settings path.** The current working directory maps to a Claude Code project path under `~/.claude/projects/`. The directory path uses `-` as separator (e.g., `/Users/yklin/Code/pm_os` → `-Users-yklin-Code-pm_os`).

2. **Read or create `settings.local.json`** at `~/.claude/projects/<project-path>/settings.local.json`.

3. **Merge the Glean MCP config** into the file's `mcpServers` key. The config to add:

```json
{
  "mcpServers": {
    "glean": {
      "type": "http",
      "url": "https://diligent-be.glean.com/mcp/default"
    }
  }
}
```

4. **Preserve existing settings.** If the file already exists, read it first, merge `mcpServers.glean` into the existing object, and write back. Do NOT overwrite other settings.

5. **Inform the user** that the Glean MCP has been configured for this project and they need to **restart the Claude Code session** (`/exit` then `claude`) for it to take effect.

6. **If already configured**, tell the user it's already set up and suggest restarting if tools aren't appearing.

## Removing Glean from a Project

To remove: read the project's `settings.local.json`, delete `mcpServers.glean`, write back. If `mcpServers` is now empty, remove that key too.
