---
name: gong-connect
description: "Search & pull full Gong call transcripts headlessly using your own SSO session (no admin API key). Use for win/loss mining, customer-quote hunting, transcript retrieval."
---

<!-- ABOUTME:
  gong-connect - headless access to your own provisioned Gong via captured web session.
  Captures SSO login once (headed agent-browser), reuses saved storageState to call Gong's
  internal /ajax + /call + /conversations endpoints. Full transcripts, call listing, mining.
  No admin key. Fragile vs public API (session expiry, internal-endpoint drift, ToS).
-->

# gong-connect

Headless read access to your own Gong (tenant `us-10290`) with no admin API key, by
reusing a captured browser session. CLI: `~/.claude/skills/gong-connect/bin/gong`.

## Auto-login (no manual step)
Every command auto-heals a stale session. If the saved session is expired or missing, the
command pops the headed SSO browser BY ITSELF, waits for you to finish SSO/MFA in that
window (polling up to `GONG_LOGIN_TIMEOUT`, default 180s), saves the refreshed session, then
retries the original command. You never run `gong login` first. Only your one-time SSO/MFA in
the popped window is required — that can't be removed (no admin key; it rides your own SSO).
Set `GONG_NO_AUTOLOGIN=1` to suppress the pop (e.g. headless cron with no display) — then a
stale session just exits 3.

## Commands
- `gong login` — pop headed browser, complete SSO, auto-save once authenticated (no keypress).
- `gong connect` — verify the saved session still authenticates.
- `gong calls [N]` — fast recent-call list (id / start / account / owner / title).
- `gong allcalls [pages] [size]` — paginate over ALL calls (id / title) via the search POST.
- `gong transcript <call-id>` — full speaker-attributed transcript.
- `gong mine <keyword> [N]` — full-history keyword search across the first N calls' transcripts.
- `gong raw <path>` — GET any internal path (e.g. `/ajax/get-call-spotlight?call-id=...`).
- `gong diag` — dump the CSRF token + search POST status/body (for debugging `allcalls`).

## Proven endpoints (tenant us-10290) — all validated working
- Call list (recent): `GET /ajax/home/calls/company-calls?workspace-id=<WS>`
- Full transcript: `GET /call/detailed-transcript?call-id=<ID>` (word-level, speaker-attributed)
- Full-corpus search: `POST /conversations/ajax/results?workspace-id=<WS>`
  body `{"pageSize":N,"callsOffset":O,"callsSearchJson":"{}"}`, header `X-CSRF-TOKEN`.
  Returns `{numOfTotalItemsThatPassedFilter, items:[{_itemType:"call", id, crmData, ...}]}`.
  Note: `items[]` have NO title field (title lives on the transcript); `callsSearchJson:"{}"`
  = all calls, paginated via `callsOffset`. CSRF token = the `.token` field of the JSON at
  `GET /ajax/common/rtkn` (`{headerName, parameterName, token}`).

## Known limits / gotchas
- `mine` pages the search POST for call IDs then pulls each transcript and greps locally —
  robust and full-corpus, but ~1 browser round-trip per call, so bound it with [N] (each call
  is a few seconds). Native in-index keyword filtering (server-side, with `searchFragments`)
  would need the free-text query mapped into `callsSearchJson` — a future speedup; local grep
  works today.
- agent-browser `eval` double-encodes a returned STRING (wraps+escapes) — `gpost_results`
  therefore returns a PARSED object (`JSON.parse` inside the eval) so jq gets real JSON. If you
  add POST calls, return objects, not `r.text()`.
- Gong signals errors as `HTTP 200 + an HTML error page`, not a 4xx — so a bad CSRF token
  looks "successful". `gong diag` distinguishes real JSON from an error page.
- Session expires on idle; on 401/login-HTML the command auto-launches login and retries
  (see Auto-login above). The persistent profile usually makes re-login silent — no MFA re-type.
- storageState = live credential. Kept in `~/.secrets/websess` (chmod 600), never in a repo.
- ToS/policy: automates your own provisioned access via Gong's INTERNAL API, which their
  terms gate behind the admin API key. Use within Acme policy; throttle requests.

## Autonomy note
This CLI is pre-authorized for autonomous execution via settings.json permissions
(`Bash(~/.claude/skills/gong-connect/bin/gong *)` and `Bash(agent-browser *)`).
Run it directly — no `!` prefix needed. It performs read-only data retrieval only.
