---
name: atlassian-update
description: >
  Update a Confluence page body (comment-safe: preserves inline comments, does not
  clear page history). Use when asked to "update this Confluence page", "add this to
  Confluence", "edit the wiki page". NOT for JIRA ticket updates (jira-update).
---

<!-- ABOUTME:
  atlassian-update - Comment-safe Confluence page updater.
  Fetches page body, catalogs inline comment markers, applies edits,
  validates marker integrity, PUTs with version bump, post-verifies.
  Refuses to submit if any marker would be lost.
-->

# Atlassian Update (Comment-Safe)

Safely update a Confluence page body via REST API without losing inline comments.

Confluence inline comments are anchored by `<ac:inline-comment-marker ac:ref="UUID">` tags
embedded in the page body. Removing or corrupting these tags orphans the comments — they
become invisible in the UI even though they still exist as child objects. This skill
ensures every marker survives the update.

## When to Use

- Updating Confluence page content programmatically
- User says "update this confluence page" (with or without comments)
- Any automated page edit where inline comments must be preserved
- Bulk content replacement or migration of Confluence pages
- Reading, replying to, or resolving inline comments on a Confluence page

## When NOT to Use

- Creating a new page (use Confluence UI or raw POST instead)
- Editing via the Confluence web UI (it handles markers natively)
- JIRA ticket updates → use `jira-update` instead

## Prerequisites

- Atlassian API connectivity established (run `/atlassian-connect` first if needed)
- Auth: Basic auth with `dev@example.com:$ATLASSIAN_API_TOKEN`
- Base URL: `https://example.atlassian.net`

## Inputs

The user must provide:
1. **Page identifier** — a Confluence page URL or numeric page ID
2. **What to change** — one of:
   - Specific text replacements (find/replace pairs)
   - A section to rewrite (identified by heading or content)
   - A full replacement body (riskiest — requires marker transplant)
   - Instructions describing the desired changes

## Procedure Overview

> Full commands for each phase are in `reference.md` in this skill directory.

| Phase | Action | Gate |
|---|---|---|
| 0 | Parse page ID from URL or raw ID | — |
| 1 | Snapshot: fetch body + catalog all `<ac:inline-comment-marker>` tags; fetch comment objects | STOP if user hasn't described changes |
| 2 | Apply edits using the lowest-risk strategy (see table below) | — |
| 3 | Pre-submit marker integrity check + structural validation | **HARD GATE: abort if any marker missing** |
| 4 | PUT updated page with incremented version number | Report error if 409/400/403 |
| 5 | Post-verify: re-fetch + confirm all markers intact; compare comment count | — |
| 6 | Comment operations: read/reply/resolve (optional, only if user asks) | — |
| 7 | Cleanup temp files | — |

### Edit Strategy

| Strategy | When | Risk |
|---|---|---|
| **Targeted find/replace** (preferred) | Specific text changes, section rewrites | LOW — markers untouched unless in replaced text |
| **Section replacement** | Rewriting content between headings | MEDIUM — must preserve markers within section |
| **Full body replacement** | Complete rewrite | HIGH — must transplant every marker; require explicit user approval |

## Safety Rules

1. **NEVER submit without passing Phase 3 validation.** No exceptions.
2. **NEVER delete comments.** Resolve only when explicitly requested (Phase 6).
3. **NEVER force-update** (skip version check). Always increment from current version.
4. **Report pre-existing orphans** (Phase 1) so the user knows the baseline.
5. **Default to non-destructive.** If in doubt, abort and ask.
6. **Temp files use PAGE_ID in filename** to avoid collisions across concurrent updates.

## Error Recovery

| Error | Action |
|---|---|
| Version conflict (409) | Re-fetch, re-catalog, re-apply edits, re-validate |
| Markers lost in pre-submit check | STOP. Show which markers. Ask user. |
| Markers lost in post-verify | Offer revert to previous version |
| API auth failure | Run `/atlassian-connect` to re-establish |
| Page not found (404) | Verify page ID / URL with user |
| Comment reply fails (403) | User may lack comment permissions — different from page edit permissions |
| v2 resolve returns 404 | Fall back to v1 property-based resolution (see reference.md Phase 6) |

## Output

After a successful update, display to the user:
- Update succeeded / failed
- New version number
- Marker count: before vs. after
- Comment count: before vs. after
- Link to the updated page

## API Version Strategy

This skill uses **Confluence REST API v1** as primary. v2 is used only where v1 lacks the
endpoint (inline comment resolution). Do not migrate to v2 wholesale — v2 has known gaps with
inline comment retrieval and nested comments as of 2025. Monitor
[Atlassian's deprecation notices](https://community.developer.atlassian.com/t/rfc-19-deprecation-of-confluence-cloud-rest-api-v1-endpoints/71752)
and update endpoints individually as v1 equivalents are retired.

## Revert

If post-verification fails and markers were lost, offer to revert by fetching the previous
version body and re-submitting it as a new version. See reference.md for the curl commands.
**Always ask user before reverting.**
