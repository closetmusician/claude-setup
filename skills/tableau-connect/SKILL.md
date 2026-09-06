---
name: tableau-connect
description: "Connect Claude Code to Acme's Tableau Cloud (site acme1) via the official @tableau/mcp-server using a Personal Access Token. Use to query BI data (VizQL), metadata/lineage (GraphQL), content (REST), and Pulse metrics."
---

<!-- ABOUTME:
  tableau-connect - one-time bootstrap that wires Claude Code to Acme's Tableau Cloud.
  Registers the official Tableau MCP server (@tableau/mcp-server, PAT auth) with `claude mcp add`,
  pinned to Homebrew node@24 (the server needs node>=22.7.5; default node here is v20).
  The PAT lives in ~/.secrets/tableau.env (chmod 600), never in this repo, git, or the chat.
  On a stale/expired PAT the CLI opens the Tableau PAT-settings page to re-mint.
-->

# tableau-connect

Connect Claude Code to **Acme's Tableau Cloud** (`https://prod-useast-a.online.tableau.com`,
site `acme1`) through Tableau's **official** MCP server. Once connected, the Tableau MCP
tools (data queries, metadata, content, Pulse) are available directly in the session.
CLI: `~/.claude/skills/tableau-connect/bin/tableau`.

## Why this design
Tableau ships a first-party, actively maintained MCP server (`@tableau/mcp-server`,
https://github.com/tableau/tableau-mcp). Unlike `gong-connect` (which reverse-engineers
internal endpoints via a captured browser session), we wrap the supported product — so this
skill is a thin auth+registration bootstrap, not a query engine. Day-to-day queries go
through the MCP tools, not this CLI.

## One-time credential setup (secret never touches Claude or git)
1. In Tableau (top-right avatar) → **My Account Settings** → **Personal Access Tokens** →
   create a token. Copy the secret — Tableau shows it **once**.
2. Save it to `~/.secrets/tableau.env`, then `chmod 600 ~/.secrets/tableau.env`:
   ```
   TABLEAU_PAT_NAME=claude-code
   TABLEAU_PAT_VALUE=<the-secret-shown-once>
   ```
   (`~/.secrets/**` is Read-denied to Claude in settings.json — only this wrapper reads it.)
3. Run: `~/.claude/skills/tableau-connect/bin/tableau setup`
4. Restart Claude Code (or `/mcp`) so the Tableau tools load.

## Commands
- `tableau setup` — verify the PAT via REST sign-in, then register the MCP server with
  Claude Code (`claude mcp add`, user scope), pinned to node@24. Idempotent.
- `tableau connect` — verify the saved PAT still authenticates (REST sign-in probe).
- `tableau status` — show the current MCP registration (PAT value redacted).
- `tableau help` — usage + first-time setup steps.

## Auth model & the "stale session" behavior
- Auth is a **Personal Access Token** (Tableau Cloud requires MFA, so username/password
  won't work; PAT is the right automation credential).
- **Exit 3 = stale/invalid PAT (HTTP 401).** A PAT can't be re-minted headlessly (a human
  must click "regenerate"), so instead of gong's silent auto-relogin, the CLI **opens the
  Tableau PAT-settings page** and tells you the one manual step. Set `TABLEAU_NO_AUTOLOGIN=1`
  to suppress the browser pop (e.g. headless cron).

## Capabilities unlocked (via the MCP tools, once connected)
- **Query data (VizQL Data Service)** — pull rows from published datasources with filters,
  aggregations, sorting. No visualization needed. Requires a *published* datasource.
- **Metadata / lineage (Metadata API, GraphQL)** — what feeds what, upstream/downstream,
  impact analysis.
- **Content management (REST API)** — list/find workbooks, views, datasources, users,
  permissions; most-viewed content; render views.
- **Pulse metrics** — metric values and insights (Tableau Cloud; needs Data Management
  license on the site).

## Known limits / gotchas
- **Node floor:** the server needs node >=22.7.5. Default node here is v20 — the CLI pins
  the server to `/opt/homebrew/opt/node@24/bin/node`. If that's absent: `brew install node@24`.
- **PAT expiry:** dies after **15 days of inactivity** or **1 year** max. If Tableau access
  goes 401, run `tableau connect` — on failure it opens the re-mint page.
- **No concurrent sessions per PAT:** reusing the same PAT terminates the prior session. If
  you run parallel agents against Tableau, mint a second PAT.
- **VizQL availability:** requires published datasources and (on some tiers) a Data
  Management license. If VizQL tools 403/return empty, check the site license with an admin.
- **Site-scoped:** the PAT is valid only for site `acme1`; cross-site calls return 403.

## Autonomy note
This CLI performs read-only auth verification and MCP registration only; it never prints the
PAT secret (all outputs redact it) and never writes the secret into this repo or git.
It is NOT yet pre-authorized for autonomous execution — running it currently prompts for
Bash permission. To pre-authorize (mirroring the gong-connect precedent), add to the
settings.json permissions.allow list:
`"Bash(~/.claude/skills/tableau-connect/bin/tableau *)"`. Until then, run it with the `!`
prefix or approve the prompt.
