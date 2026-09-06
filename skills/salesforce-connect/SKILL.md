---
name: salesforce-connect
description: "Connect Claude Code to Acme's Salesforce org (example.lightning.force.com) via the official @salesforce/mcp server. Uses the sf CLI's browser OAuth login (survives Okta SSO/MFA, no admin needed) — no secret file. Read-only by default (SOQL query). Use to query Salesforce data (accounts, opportunities, cases) directly in the session."
---

<!-- ABOUTME:
  salesforce-connect - one-time bootstrap that wires Claude Code to Acme's Salesforce org.
  Logs the official `sf` CLI into the org via browser OAuth (Okta SSO/MFA safe), then registers
  the official @salesforce/mcp server with `claude mcp add`, scoped to one org (--orgs) and a
  read-only toolset (--tools run_soql_query). NO secret file — auth lives in the sf CLI's store.
  Both sf (node>=22) and the MCP server (node>=20) run via Homebrew node@24 (default node here is v20).
  On a stale session the CLI re-runs the browser login (sf can re-auth itself, unlike a Tableau PAT).
  CLI: ~/.claude/skills/salesforce-connect/bin/salesforce
-->

# salesforce-connect

Connect Claude Code to **Acme's Salesforce org** (`https://example.lightning.force.com`,
My Domain `acme`) through Salesforce's **official** MCP server. Once connected, the
Salesforce MCP tools (SOQL query, by default) are available directly in the session.
CLI: `~/.claude/skills/salesforce-connect/bin/salesforce`.

## Why this design
Salesforce ships a first-party, actively maintained MCP server (`@salesforce/mcp`,
https://github.com/salesforcecli/mcp). Like `tableau-connect` (and unlike `gong-connect`),
we wrap the supported product — so this skill is a thin auth+registration bootstrap, not a
query engine. Day-to-day queries go through the MCP tools, not this CLI.

## Auth: no secret file (the big difference from Tableau)
The MCP server does **not** do its own OAuth. It reuses whatever org the `sf` CLI is already
logged into. So the whole auth story is: **log the `sf` CLI in once via a real browser.**
- `sf org login web` opens the org's login page in a browser, where **Okta SSO + MFA run
  normally** — the human completes MFA, and `sf` captures a refresh token.
- The token lives in the `sf` CLI's own store (`~/.sfdx`), **not** in `~/.secrets`, not in
  this repo, not in git, and never on the command line.
- **No Salesforce admin action is required** for this path (unlike Connected App + JWT).

## Read-only by default
The MCP server is registered with `--tools run_soql_query` — only the SOQL query tool loads.
Its write tools (metadata deploy, permission-set assignment, DevOps commits) never turn on.
To widen the surface deliberately, set `SF_MCP_TOOLS` before `setup`
(e.g. `SF_MCP_TOOLS="run_soql_query,deploy_metadata"` — that enables writes) and re-run setup.

## One-time setup
1. Run: `~/.claude/skills/salesforce-connect/bin/salesforce setup`
   - It logs the `sf` CLI into `acme.my.salesforce.com` (browser opens → Okta/MFA),
     then registers `@salesforce/mcp` with Claude Code (scope=user), pinned to node@24.
2. Restart Claude Code (or `/mcp`) so the Salesforce tools load.

## Commands
- `salesforce setup` — browser-login the `sf` CLI, then register the MCP server. Idempotent.
- `salesforce connect` — verify the org session still authenticates (`sf org display`, no
  browser unless the session is stale).
- `salesforce status` — show the current MCP registration.
- `salesforce help` — usage + setup steps.

## Auth model & the "stale session" behavior
- **Exit 3 = stale/expired session.** Unlike a Tableau PAT (a human must click "regenerate"),
  the `sf` CLI **can re-authenticate itself** — so on exit 3 the CLI re-runs the browser
  login rather than just opening a page. Set `SF_NO_AUTOLOGIN=1` to suppress the browser pop
  (e.g. headless cron); then a stale session is reported, not fixed.
- Refresh tokens are long-lived but die on org-side session-policy timeouts or admin revoke.

## Capabilities unlocked (via the MCP tools, once connected)
- **Query data (SOQL)** — `run_soql_query`: pull rows from any object your user can read
  (Account, Opportunity, Case, Contact, custom objects), with WHERE/ORDER BY/LIMIT.
- **(Off by default)** metadata retrieve/deploy, Apex test runs, permission-set assignment,
  scratch-org ops — enable via `SF_MCP_TOOLS`/toolsets only when you actually need them.

## Known limits / gotchas
- **Node floor:** the `sf` CLI needs node >=22; the MCP server needs >=20. Default node here
  is v20 — the CLI drives both through `/opt/homebrew/opt/node@24/bin/node`. If that's
  absent: `brew install node@24`.
- **No generic describe / no DML tool in the official server.** `run_soql_query` covers
  read/analysis. If you need object *describe*, SOSL, or aggregate-query tools, the community
  `@tsmztech/mcp-server-salesforce` (reuses the same `sf` login) has them — add it alongside
  only if the gap bites.
- **`sf` install:** if `sf` isn't on PATH, the CLI runs it via node@24's `npx @salesforce/cli`
  (slower per call, but no global install needed and no node-version conflict).
- **Org scope:** the MCP server is pinned to `--orgs acme`; it can't touch other orgs.

## Autonomy note
This CLI performs a browser login and MCP registration only; it stores no secret of its own
(auth lives in the `sf` CLI's store) and prints none. It is NOT yet pre-authorized for
autonomous execution — running it currently prompts for Bash permission. To pre-authorize
(mirroring the tableau-connect precedent), add to the settings.json permissions.allow list:
`"Bash(~/.claude/skills/salesforce-connect/bin/salesforce *)"`. Until then, run it with the
`!` prefix or approve the prompt.
