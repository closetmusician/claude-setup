---
name: atlassian-connect
description: "Connect to Atlassian (JIRA + Confluence). Defaults to direct API token — falls back to MCP only when needed."
---

<!-- ABOUTME:
  atlassian-connect - Atlassian connectivity skill with two modes.
  Default: direct REST API via curl (simpler, no deps beyond token).
  Fallback: MCP server via uvx mcp-atlassian (structured tools, heavier).
  Asks the user which mode upfront, defaults to direct API.
-->

# Atlassian Connect

Connects the current session to Atlassian (JIRA + Confluence). Two modes:

1. **Direct API** (default) — uses `curl` with the user's API token. Zero deps, lightweight.
2. **MCP Server** — registers `mcp-atlassian` via `claude mcp add`. Structured tools, heavier.

## When to Use

- A skill or task needs Atlassian access (JIRA tickets, Confluence pages)
- User invokes `/atlassian-connect` explicitly
- The `pm-jira` skill detects missing Atlassian connectivity

## Procedure

### Step 1: Check Existing Connectivity

Check both modes:
- **Direct API:** Run `bash -c 'source ~/.zshrc 2>/dev/null; curl -sf -u yklin@diligent.com:$ATLASSIAN_API_TOKEN "https://diligentbrands.atlassian.net/rest/api/2/myself" | head -c 200'`. If this returns user JSON, direct API is already working.
- **MCP:** Run `claude mcp list 2>&1 | grep -i atlassian`. If healthy, MCP is already configured.

If either is already working, inform the user which mode is active and stop.

### Step 2: Ask User Which Mode

Use `AskUserQuestion` to ask:

> **How should we connect to Atlassian?**
>
> - **Direct API (Recommended)** — Uses curl with your API token. Simpler, no extra dependencies.
> - **MCP Server** — Registers a persistent MCP server with structured tools. Heavier but useful if you do frequent, varied Atlassian operations.

Default recommendation: Direct API.

### Step 3: Resolve User Identity

Yu-Kuan's Atlassian email is `yklin@diligent.com`. Use this as `ATLASSIAN_USER` — do NOT ask.

### Step 4: Verify API Token

Run: `bash -c 'source ~/.zshrc 2>/dev/null || source ~/.bashrc 2>/dev/null; echo $ATLASSIAN_API_TOKEN'`

**If token exists**, test it:
```bash
bash -c 'source ~/.zshrc 2>/dev/null; curl -sf -o /dev/null -w "%{http_code}" -u yklin@diligent.com:$ATLASSIAN_API_TOKEN "https://diligentbrands.atlassian.net/rest/api/2/myself"'
```
- `200` — token is valid, proceed.
- `401` or `403` — token is expired/revoked. Tell the user and go to **Step 4a**.

**If token is empty or missing**, go to **Step 4a**.

### Step 4a: Token Setup / Refresh

1. Tell the user their token is missing or expired and they need a new one.
2. Tell the user to go to https://id.atlassian.com/manage-profile/security/api-tokens and create a new API token.
3. Use `AskUserQuestion` to ask: **"Paste your new Atlassian API token:"** (single text input, no options needed — user will use "Other" to paste).
4. Once the user provides the token, write it to their shell profile:
   ```bash
   # Remove any existing ATLASSIAN_API_TOKEN export lines, then append the new one
   sed -i '' '/^export ATLASSIAN_API_TOKEN=/d' ~/.zshrc
   echo 'export ATLASSIAN_API_TOKEN=<NEW_TOKEN>' >> ~/.zshrc
   ```
5. Verify the new token works:
   ```bash
   curl -sf -o /dev/null -w "%{http_code}" -u yklin@diligent.com:<NEW_TOKEN> "https://diligentbrands.atlassian.net/rest/api/2/myself"
   ```
   If still failing, inform the user and stop.

Do NOT proceed to Step 5 until a valid token is confirmed.

### Step 5A: Direct API Mode

1. **Verify connectivity:** Run a test call:
   ```bash
   bash -c 'source ~/.zshrc 2>/dev/null; curl -sf -u yklin@diligent.com:$ATLASSIAN_API_TOKEN "https://diligentbrands.atlassian.net/rest/api/2/myself"'
   ```
   If this fails, suggest the user check their token, or offer to fall back to MCP mode.

2. **Inform the user:** Atlassian is connected via direct API. Provide quick-reference examples:

   **JIRA — search issues:**
   ```bash
   bash -c 'source ~/.zshrc 2>/dev/null; curl -sf -u yklin@diligent.com:$ATLASSIAN_API_TOKEN "https://diligentbrands.atlassian.net/rest/api/2/search?jql=assignee=currentUser()&maxResults=10"'
   ```

   **JIRA — get issue:**
   ```bash
   bash -c 'source ~/.zshrc 2>/dev/null; curl -sf -u yklin@diligent.com:$ATLASSIAN_API_TOKEN "https://diligentbrands.atlassian.net/rest/api/2/issue/PROJ-123"'
   ```

   **Confluence — search:**
   ```bash
   bash -c 'source ~/.zshrc 2>/dev/null; curl -sf -u yklin@diligent.com:$ATLASSIAN_API_TOKEN "https://diligentbrands.atlassian.net/wiki/rest/api/content/search?cql=type=page+and+text~\"search+term\"&limit=10"'
   ```

   **Confluence — get page by ID:**
   ```bash
   bash -c 'source ~/.zshrc 2>/dev/null; curl -sf -u yklin@diligent.com:$ATLASSIAN_API_TOKEN "https://diligentbrands.atlassian.net/wiki/rest/api/content/PAGE_ID?expand=body.storage"'
   ```

3. **Done.** No MCP registration needed. Future skills that need Atlassian should use these curl patterns.

### Step 5B: MCP Server Mode

Only if the user chose MCP, or direct API failed and user wants to try MCP.

1. **Ensure wrapper script exists.** Check if `~/.claude/scripts/atlassian-mcp.sh` exists and is executable. If missing, create it:

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

   Then `mkdir -p ~/.claude/scripts && chmod +x ~/.claude/scripts/atlassian-mcp.sh`.

2. **Verify uvx:** Run `~/.claude/scripts/atlassian-mcp.sh --help`. If uvx is missing, tell user: `curl -LsSf https://astral.sh/uv/install.sh | sh`

3. **Register MCP server.** **NEVER use `-s local`** (writes to global `~/.claude.json`).

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

4. **Inform the user:**
   - Atlassian MCP is registered for this project
   - Run **`/mcp`** to connect it in the current session (no restart needed)
   - It will auto-load on future sessions in this project

## Removing Atlassian MCP from a Project

Run: `claude mcp remove atlassian -s project`

## API Reference (for skills using direct mode)

Base URL: `https://diligentbrands.atlassian.net`
Auth: Basic auth — `yklin@diligent.com:$ATLASSIAN_API_TOKEN`

| Operation | Endpoint |
|-----------|----------|
| JIRA: My issues | `GET /rest/api/2/search?jql=assignee=currentUser()` |
| JIRA: Get issue | `GET /rest/api/2/issue/{key}` |
| JIRA: Search JQL | `GET /rest/api/2/search?jql={jql}` |
| JIRA: Add comment | `POST /rest/api/2/issue/{key}/comment` (body: `{"body": "..."}`) |
| JIRA: Transition | `POST /rest/api/2/issue/{key}/transitions` |
| Confluence: Search | `GET /wiki/rest/api/content/search?cql={cql}` |
| Confluence: Get page | `GET /wiki/rest/api/content/{id}?expand=body.storage` |
| Confluence: Get children | `GET /wiki/rest/api/content/{id}/child/page` |
