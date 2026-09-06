---
name: connect-all
description: "Master connect: bring every data source online in one command — Glean (enterprise search), Gong (call transcripts), Tableau (BI data), and Salesforce (CRM data). Use when starting work that spans sources, or to verify everything is authenticated at once."
---

<!-- ABOUTME:
  connect-all - the umbrella connect skill. One command connects/verifies every data source.
  Thin orchestrator: owns NO auth logic. It invokes each sub-skill's own connect verb
  (glean auth status, gong/tableau/salesforce connect) and prints a per-source summary.
  Non-interactive by default (no browser pops); a stale source is reported, not auto-fixed.
  CLI: ~/.claude/skills/connect-all/bin/connect-all
-->

# connect-all

Bring **every data source online in one command**. Instead of running `/glean-connect`,
`/gong-connect`, `/tableau-connect`, and `/salesforce-connect` separately, run this once and
it connects (or verifies) all four, then prints a status summary.

CLI: `~/.claude/skills/connect-all/bin/connect-all`

## What it connects
| Source | What it unlocks | Delegates to |
|---|---|---|
| **Glean** | Enterprise search across work docs | the `glean` CLI (`glean auth status`) |
| **Gong** | Call transcripts, win/loss mining | `~/.claude/skills/gong-connect/bin/gong connect` |
| **Tableau** | BI data, dashboards, metadata, Pulse (via MCP) | `~/.claude/skills/tableau-connect/bin/tableau connect` |
| **Salesforce** | CRM data — accounts, opportunities, cases (SOQL via MCP) | `~/.claude/skills/salesforce-connect/bin/salesforce connect` |

## Design: invocation, not duplication
This skill contains **no authentication logic of its own**. It calls each sub-skill's
existing `connect` verb and aggregates the results. Fix a broken source with its own tool —
this is a status roll-up, not a replacement. Each connect skill remains the single source of
truth for its own auth.

## Commands
- `connect-all` — connect/verify all four (Glean, Gong, Tableau, Salesforce).
- `connect-all gong salesforce` — only the named sources (any subset of
  `glean gong tableau salesforce`).
- `connect-all help` — usage.

## Behavior
- **Non-interactive:** runs with `GONG_NO_AUTOLOGIN=1`, `TABLEAU_NO_AUTOLOGIN=1`, and
  `SF_NO_AUTOLOGIN=1`, so a stale source is **reported**, never auto-fixed with a surprise
  browser pop mid-sweep.
- **Non-fatal per source:** one source failing never blocks the others. Exit code is 0 only
  if every attempted source connected; non-zero if any failed.
- **To auto-fix a stale source, run its own CLI** (these DO pop the login/re-mint flow):
  - Glean: `glean auth login`
  - Gong: `~/.claude/skills/gong-connect/bin/gong login`
  - Tableau: `~/.claude/skills/tableau-connect/bin/tableau connect`
  - Salesforce: `~/.claude/skills/salesforce-connect/bin/salesforce connect`

## When to use
- Starting a task that spans sources (e.g. win/loss work touching Gong + Tableau + Glean).
- A quick "is everything authenticated?" check at the start of a session.
- NOT for querying — once connected, use each source's own tools (Glean search wrapper,
  gong CLI, Tableau MCP tools).

## Autonomy note
This CLI performs read-only auth checks and delegates to the sub-skills; it stores no
secrets and prints none. It is NOT yet pre-authorized for autonomous execution — running it
prompts for Bash permission. To pre-authorize, add to settings.json permissions.allow:
`"Bash(~/.claude/skills/connect-all/bin/connect-all *)"` (the sub-skill CLIs it calls need
their own allow entries too — see each sub-skill's SKILL.md).
