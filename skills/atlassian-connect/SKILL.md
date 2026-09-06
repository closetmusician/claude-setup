---
name: atlassian-connect
description: "Establishes Atlassian (JIRA + Confluence) connectivity for the session — the auth bootstrap that eng-stories Jira delivery, jira-update, pm-jira, and atlassian-update depend on. Prefers direct REST API with the user's API token; registers the MCP server only as a fallback. Use when a task needs JIRA or Confluence access and connectivity is unverified, when Atlassian API calls return 401/403, or when the user says 'connect to Atlassian', 'connect to JIRA', or 'set up Confluence access'. NOT for editing Confluence page bodies (use atlassian-update) or daily JIRA triage (use pm-jira)."
---

<!-- ABOUTME:
  atlassian-connect - Atlassian connectivity skill with two modes.
  Default: direct REST API via curl (simpler, no deps beyond token).
  Fallback: MCP server via uvx mcp-atlassian (structured tools, heavier).
  Applies an explicit decision rule (Step 2); asks only when criteria are ambiguous.
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
- **Direct API:** Run `bash -c 'source ~/.zshrc 2>/dev/null; curl -sf -u dev@example.com:$ATLASSIAN_API_TOKEN "https://example.atlassian.net/rest/api/3/myself" | head -c 200'`. If this returns user JSON, direct API is already working.
- **MCP:** Run `claude mcp list 2>&1 | grep -i atlassian`. If healthy, MCP is already configured.

If either is already working, inform the user which mode is active (if both work, Direct API is the active mode for downstream callers) and stop. The contract in "After Success" below applies.

### Step 2: Choose Mode (Decision Rule)

**Default: Direct API. Proceed without asking.** Use MCP mode ONLY if at least one of these criteria holds:

1. The user explicitly asked for MCP or a persistent Atlassian server.
2. Direct API cannot be made to work — token validation still fails after one full Step 4a refresh cycle.
3. The user does frequent, varied, interactive Atlassian operations in this project AND confirms via `AskUserQuestion` that they want a persistent server registered. Only ask this question when the user's intent is genuinely ambiguous; a downstream skill needing API access is NOT ambiguous — it gets Direct API.

Examples:
- "eng-stories needs to push 40 stories to Jira" → **Direct API**. Volume of curl calls does not justify a server.
- "Set up the Atlassian MCP so it's always available in this repo" → **MCP mode** (criterion 1).
- Token refreshed via Step 4a but `/myself` still returns 403 → offer **MCP mode** (criterion 2); if the user declines, stop and report.

### Step 3: Resolve User Identity

Yu-Kuan's Atlassian email is `dev@example.com`. Use this as `ATLASSIAN_USER` — do NOT ask.

### Step 4: Verify API Token

Run: `bash -c 'source ~/.zshrc 2>/dev/null || source ~/.bashrc 2>/dev/null; echo $ATLASSIAN_API_TOKEN'`

**If token exists**, test it:
```bash
bash -c 'source ~/.zshrc 2>/dev/null; curl -sf -o /dev/null -w "%{http_code}" -u dev@example.com:$ATLASSIAN_API_TOKEN "https://example.atlassian.net/rest/api/3/myself"'
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
   curl -sf -o /dev/null -w "%{http_code}" -u dev@example.com:<NEW_TOKEN> "https://example.atlassian.net/rest/api/3/myself"
   ```
   If still failing, inform the user and stop.

Do NOT proceed to Step 5 until a valid token is confirmed.

### Step 5A: Direct API Mode

1. **Verify connectivity:** Run a test call:
   ```bash
   bash -c 'source ~/.zshrc 2>/dev/null; curl -sf -u dev@example.com:$ATLASSIAN_API_TOKEN "https://example.atlassian.net/rest/api/3/myself"'
   ```
   If this fails, suggest the user check their token, or offer to fall back to MCP mode (Step 2, criterion 2).

2. **Inform the user:** Atlassian is connected via direct API. Provide quick-reference examples:

   **JIRA — search issues (v3, POST with JSON body):**
   ```bash
   bash -c 'source ~/.zshrc 2>/dev/null; curl -sf -u dev@example.com:$ATLASSIAN_API_TOKEN -H "Content-Type: application/json" -X POST "https://example.atlassian.net/rest/api/3/search/jql" -d "{\"jql\":\"assignee=currentUser()\",\"maxResults\":10,\"fields\":[\"key\",\"summary\",\"status\"]}"'
   ```

   **JIRA — get issue:**
   ```bash
   bash -c 'source ~/.zshrc 2>/dev/null; curl -sf -u dev@example.com:$ATLASSIAN_API_TOKEN "https://example.atlassian.net/rest/api/3/issue/PROJ-123"'
   ```

   **Confluence — search:**
   ```bash
   bash -c 'source ~/.zshrc 2>/dev/null; curl -sf -u dev@example.com:$ATLASSIAN_API_TOKEN "https://example.atlassian.net/wiki/rest/api/content/search?cql=type=page+and+text~\"search+term\"&limit=10"'
   ```

   **Confluence — get page by ID:**
   ```bash
   bash -c 'source ~/.zshrc 2>/dev/null; curl -sf -u dev@example.com:$ATLASSIAN_API_TOKEN "https://example.atlassian.net/wiki/rest/api/content/PAGE_ID?expand=body.storage"'
   ```

3. **Done.** No MCP registration needed. Future skills that need Atlassian should use these curl patterns (see "After Success" contract below).

### Step 5B: MCP Server Mode

Only if a Step 2 criterion selected MCP (user chose it, or direct API failed and user wants to try MCP).

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
     -e JIRA_URL=https://example.atlassian.net \
     -e JIRA_USERNAME=dev@example.com \
     -e CONFLUENCE_URL=https://example.atlassian.net \
     -e CONFLUENCE_USERNAME=dev@example.com \
     -- atlassian /Users/yklin/.claude/scripts/atlassian-mcp.sh
   ```

   If the project is a git repo, ensure `.mcp.json` is in `.gitignore`.

4. **Inform the user:**
   - Atlassian MCP is registered for this project
   - Run **`/mcp`** to connect it in the current session (no restart needed)
   - It will auto-load on future sessions in this project

## After Success: What Downstream Callers Can Assume

Once this skill reports success in **Direct API mode**, any skill in the same session (eng-stories Jira delivery, jira-update, pm-jira, atlassian-update) can assume:

- `ATLASSIAN_API_TOKEN` is exported in `~/.zshrc` and validated (HTTP 200 from `/rest/api/3/myself`).
- The token is NOT in the Claude process environment — every call must source the profile first: `bash -c 'source ~/.zshrc 2>/dev/null; curl -sf -u dev@example.com:$ATLASSIAN_API_TOKEN "<url>"'`.
- Base URL is `https://example.atlassian.net`, user is `dev@example.com`, JIRA API is **v3 only** (see API Reference below — v2 search returns 410).
- Do NOT re-run token setup or invent an auth flow. If a call returns 401/403 mid-task, re-invoke `/atlassian-connect` instead.

If **MCP mode** was chosen instead: the `atlassian` MCP server is registered at project scope; its tools become available after `/mcp` in the current session or automatically on the next session start. Downstream skills should use the MCP tools, not curl.

## Removing Atlassian MCP from a Project

Run: `claude mcp remove atlassian -s project`

## API Reference (for skills using direct mode)

Base URL: `https://example.atlassian.net`
Auth: Basic auth — `dev@example.com:$ATLASSIAN_API_TOKEN`
API version: **v3** (v2 search endpoint was retired 2025 — returns 410)

| Operation | Endpoint | Notes |
|-----------|----------|-------|
| JIRA: Search JQL | `POST /rest/api/3/search/jql` | JSON body: `{"jql":"...","maxResults":N,"fields":["key","summary",...]}` |
| JIRA: Get issue | `GET /rest/api/3/issue/{key}` | |
| JIRA: My issues | `POST /rest/api/3/search/jql` | JQL: `assignee=currentUser()` |
| JIRA: Add comment | `POST /rest/api/3/issue/{key}/comment` | v3 uses ADF: `{"body":{"type":"doc","version":1,"content":[{"type":"paragraph","content":[{"type":"text","text":"..."}]}]}}` |
| JIRA: Transition | `POST /rest/api/3/issue/{key}/transitions` | |
| JIRA: Get myself | `GET /rest/api/3/myself` | Connectivity check |
| Confluence: Search | `GET /wiki/rest/api/content/search?cql={cql}` | |
| Confluence: Get page | `GET /wiki/rest/api/content/{id}?expand=body.storage` | |
| Confluence: Get children | `GET /wiki/rest/api/content/{id}/child/page` | |

## Auto-Chain: Confluence Page Editing

If the user's intent is to **edit or update a Confluence page** (not just read it), invoke `/atlassian-update` after connectivity is established. That skill handles inline-comment-marker preservation, pre/post verification, and safe PUT semantics.
