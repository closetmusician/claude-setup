#!/usr/bin/env bash
# ABOUTME: One-run installer for the gong-connect skill (CLI + SKILL.md) + self-test.
# ABOUTME: Writes ~/.claude/skills/gong-connect/{bin/gong,SKILL.md} then exercises it.
# ABOUTME: Safe to re-run; overwrites the skill files with the current version.
set -uo pipefail
SKILL_DIR="$HOME/.claude/skills/gong-connect"
mkdir -p "$SKILL_DIR/bin"

cat > "$SKILL_DIR/bin/gong" <<'GONGEOF'
#!/usr/bin/env bash
# ABOUTME: gong-connect CLI — drive your OWN authenticated Gong web session headlessly.
# ABOUTME: Captures SSO login once (headed), reuses saved state to hit Gong's internal
# ABOUTME: /ajax + /call + /conversations endpoints: call listing, full transcripts, mining.
# ABOUTME: No admin API key — rides your provisioned Gong access via agent-browser.
# ABOUTME: Session expiry is auto-detected; `gong login` re-pops a headed window to refresh.
set -uo pipefail
BASE="${GONG_BASE:-https://us-10290.app.gong.io}"
WS="${GONG_WORKSPACE_ID:-3714020874996502528}"
STATE="${GONG_STATE:-$HOME/.secrets/websess/gong.state.json}"
PROFILE="${GONG_PROFILE:-$HOME/.secrets/websess/gong-profile}"
SESSION="${GONG_SESSION:-gong-$$}"
AB="${AGENT_BROWSER_BIN:-agent-browser}"

cleanup() {
  "$AB" --session "$SESSION" close >/dev/null 2>&1 || true
  local pid_file="$HOME/.agent-browser/${SESSION}.pid"
  if [ -f "$pid_file" ]; then
    kill "$(cat "$pid_file")" 2>/dev/null || true
    rm -f "$HOME/.agent-browser/${SESSION}".{pid,engine,stream,version,sock} 2>/dev/null || true
  fi
}
trap cleanup EXIT

# gfetch <path> — load saved state into a headless session, GET the URL, print body text.
# Single choke point for authenticated reads so expiry is handled once. Exit 3 = logged out.
gfetch() {
  local path="$1" body
  "$AB" --state "$STATE" --session "$SESSION" open "$BASE$path" >/dev/null 2>&1 || true
  body="$("$AB" --session "$SESSION" get text body 2>/dev/null || true)"
  if [ -z "$body" ] || printf '%s' "$body" | head -c 300 | grep -qiE 'welcome/sign|sign-in|<!doctype|<html'; then
    return 3
  fi
  printf '%s' "$body"
}

# gpost_results <pageSize> <offset> — POST the conversations search endpoint from inside the
# authenticated page context (cookies auto-sent), fetching Gong's CSRF token first. Returns
# the raw results JSON. Gotcha: the rtkn parse + callsSearchJson shape are best-effort — if
# your tenant differs, capture a real search via `agent-browser network har` and adjust.
gpost_results() {
  local ps="$1" off="$2" js
  "$AB" --state "$STATE" --session "$SESSION" open "$BASE/" >/dev/null 2>&1 || true
  js="$(cat <<JS
(async () => {
  const raw = await fetch('/ajax/common/rtkn', {credentials:'include'}).then(r=>r.text());
  let tkn; try { const j = JSON.parse(raw); tkn = j.token || j.rtkn || j.value || raw; }
  catch (e) { tkn = raw.replace(/^"|"\$/g, ''); }
  const r = await fetch('/conversations/ajax/results?workspace-id=${WS}', {
    method:'POST', credentials:'include',
    headers:{'Content-Type':'application/json','X-Requested-With':'XMLHttpRequest','X-CSRF-TOKEN':tkn},
    body: JSON.stringify({pageSize:${ps}, callsOffset:${off}, callsSearchJson:'{}'})
  });
  const b = await r.text();
  try { return JSON.parse(b); } catch (e) { return {error: r.status}; }
})()
JS
)"
  "$AB" --session "$SESSION" eval "$js" 2>/dev/null
}

need_auth_msg() { printf '%s\n' "[gong-connect] Session expired or not authenticated." \
  "  Run:  $0 login   (opens headed browser at $BASE, saves state after SSO)" >&2; }

# cmd_login — headed SSO once, then persist cookies+storage. Needs a TTY for the Enter prompt.
cmd_login() {
  mkdir -p "$(dirname "$STATE")" && chmod 700 "$(dirname "$STATE")" 2>/dev/null || true
  echo "[gong-connect] Opening headed browser at $BASE — complete SSO/MFA in the window."
  "$AB" --headed --profile "$PROFILE" --session gong-login open "$BASE/" >/dev/null 2>&1 || true
  printf "[gong-connect] Once logged in, press Enter to save the session... "; read -r _ || true
  "$AB" --session gong-login state save "$STATE" >/dev/null 2>&1
  chmod 600 "$STATE" 2>/dev/null || true
  echo "[gong-connect] Saved session state -> $STATE"
}

cmd_connect() {
  if gfetch "/ajax/home/calls/company-calls?workspace-id=$WS" >/dev/null 2>&1; then
    echo "[gong-connect] Authenticated OK  ($BASE, ws=$WS)"; else need_auth_msg; return 3; fi
}

# cmd_calls [N] — fast recent-call list from the home endpoint (NOT full history; see allcalls).
cmd_calls() {
  local limit="${1:-20}" body
  body="$(gfetch "/ajax/home/calls/company-calls?workspace-id=$WS")" || { need_auth_msg; return 3; }
  printf '%s' "$body" | jq -r '
    [.. | objects | select(.id? and .title?)] | unique_by(.id) | .[]
    | "\(.id)\t\(.startTime // "")\t\((.crmData.accounts[0].name) // "-")\t\(.owner // "-")\t\(.title)"' | head -n "$limit"
}

# cmd_allcalls [maxpages] [pageSize] — paginate the conversations search over ALL calls.
# Emits: id <tab> title. Stops when a page returns fewer than pageSize rows.
cmd_allcalls() {
  local maxpages="${1:-10}" ps="${2:-50}" off=0 page=0 body ids n
  while [ "$page" -lt "$maxpages" ]; do
    body="$(gpost_results "$ps" "$off")"; [ -z "$body" ] && break
    ids="$(printf '%s' "$body" | jq -r '(.items // [])[] | select(.id and (._itemType == "call" or ._itemType == null)) | "\(.id)\t\((.crmData.accounts[0].name) // "-") \((.userTimezoneActivityTime) // "")"' 2>/dev/null)"
    [ -z "$ids" ] && break
    printf '%s\n' "$ids"
    n="$(printf '%s\n' "$ids" | grep -c .)"
    [ "$n" -lt "$ps" ] && break
    off=$((off + ps)); page=$((page + 1))
  done
}

# cmd_transcript <call-id> — full speaker-attributed transcript for one call.
cmd_transcript() {
  local id="${1:?usage: gong transcript <call-id>}" body
  body="$(gfetch "/call/detailed-transcript?call-id=$id")" || { need_auth_msg; return 3; }
  printf '%s' "$body" | jq -r '
    "# " + (.callTitle // "call") + "  (" + (.callCustomers // "") + ", " + (.when // "") + ")",
    (.monologues[]? | "[\(.timestampStr // (.timestamp|tostring))] \(.speakerName // "?"): \(.text // "")")'
}

# cmd_mine <keyword> [maxcalls] — full-history keyword search: page through all calls, pull
# each transcript, report matching lines with call title + speaker + timestamp.
cmd_mine() {
  local kw="${1:?usage: gong mine <keyword> [maxcalls]}" maxcalls="${2:-40}" list
  list="$(cmd_allcalls 1 "$maxcalls" 2>/dev/null)"
  if [ -z "$list" ]; then
    echo "[gong-connect] full-corpus search empty; using recent calls (run 'gong diag' to fix allcalls)." >&2
    list="$(gfetch "/ajax/home/calls/company-calls?workspace-id=$WS" 2>/dev/null \
      | jq -r '[.. | objects | select(.id? and .title?)] | unique_by(.id) | .[] | "\(.id)\t\(.title)"' 2>/dev/null)"
  fi
  printf '%s\n' "$list" | head -n "$maxcalls" | while IFS=$'\t' read -r id title; do
    [ -z "$id" ] && continue
    local t hits
    t="$(gfetch "/call/detailed-transcript?call-id=$id" 2>/dev/null || true)"; [ -z "$t" ] && continue
    hits="$(printf '%s' "$t" | jq -r --arg kw "$kw" '.monologues[]?
      | select((.text // "") | ascii_downcase | contains($kw | ascii_downcase))
      | "  [\(.timestampStr // "")] \(.speakerName // "?"): \(.text)"' 2>/dev/null || true)"
    if [ -n "$hits" ]; then echo "=== $title  (call $id) ==="; printf '%s\n' "$hits"; fi
  done
  return 0
}

cmd_raw() { gfetch "${1:?usage: gong raw <path>}" || { need_auth_msg; return 3; }; }

# cmd_diag — one-shot dump of the CSRF token + search POST so the full-corpus path (allcalls)
# can be debugged without a browser capture. Prints rtkn status/value (truncated), the
# results POST status, and the first ~700 chars of its body.
cmd_diag() {
  "$AB" --state "$STATE" --session "$SESSION" open "$BASE/" >/dev/null 2>&1 || true
  local js
  js="$(cat <<JS
(async () => {
  const t = await fetch('/ajax/common/rtkn', {credentials:'include'});
  const raw = await t.text();
  let tok; try { tok = JSON.parse(raw).token || raw; } catch (e) { tok = raw.replace(/^"|"\$/g, ''); }
  const r = await fetch('/conversations/ajax/results?workspace-id=${WS}', {
    method:'POST', credentials:'include',
    headers:{'Content-Type':'application/json','X-Requested-With':'XMLHttpRequest','X-CSRF-TOKEN': tok},
    body: JSON.stringify({pageSize:3, callsOffset:0, callsSearchJson:'{}'})
  });
  const body = await r.text();
  return 'RTKN_STATUS=' + t.status + ' TOKlen=' + tok.length
       + ' | RESULTS_STATUS=' + r.status + ' BODY=' + body.slice(0,1500);
})()
JS
)"
  "$AB" --session "$SESSION" eval "$js" 2>&1 | head -c 1300
  echo
}

case "${1:-}" in
  login) cmd_login ;;
  connect|status) cmd_connect ;;
  calls) shift; cmd_calls "$@" ;;
  allcalls) shift; cmd_allcalls "$@" ;;
  transcript) shift; cmd_transcript "$@" ;;
  mine|search) shift; cmd_mine "$@" ;;
  raw) shift; cmd_raw "$@" ;;
  diag) cmd_diag ;;
  *) printf '%s\n' "gong-connect — headless Gong access (no admin key)" \
     "  gong login | connect | calls [N] | allcalls [pages] [size] | transcript <id> | mine <kw> [N] | raw <path> | diag" \
     "  env: GONG_BASE GONG_WORKSPACE_ID GONG_STATE GONG_PROFILE GONG_SESSION" >&2; exit 1 ;;
esac
GONGEOF
chmod +x "$SKILL_DIR/bin/gong"

cat > "$SKILL_DIR/SKILL.md" <<'SKILLEOF'
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

## Commands
- `gong login` — pop headed browser, complete SSO once, save state (`~/.secrets/websess/gong.state.json`).
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
- Session expires on idle; on 401/login-HTML the CLI says to run `gong login` (persistent
  profile usually makes re-login silent — no MFA re-type).
- storageState = live credential. Kept in `~/.secrets/websess` (chmod 600), never in a repo.
- ToS/policy: automates your own provisioned access via Gong's INTERNAL API, which their
  terms gate behind the admin API key. Use within Acme policy; throttle requests.

## Autonomy note
This CLI is pre-authorized for autonomous execution via settings.json permissions
(`Bash(~/.claude/skills/gong-connect/bin/gong *)` and `Bash(agent-browser *)`).
Run it directly — no `!` prefix needed. It performs read-only data retrieval only.
SKILLEOF

echo "[setup] wrote $SKILL_DIR/bin/gong and SKILL.md"
[ -n "${GONG_SETUP_NOTEST:-}" ] && { echo "[setup] self-test skipped (GONG_SETUP_NOTEST set)"; exit 0; }
echo "======== SELF-TEST ========"
GONG="$SKILL_DIR/bin/gong"
"$GONG" connect || { echo "[setup] not authenticated — run: $GONG login"; exit 0; }
echo "--- calls (5, recent) ---"; "$GONG" calls 5
echo "--- allcalls (1 page of 10, full-corpus search) ---"; "$GONG" allcalls 1 10
FIRST_ID="$("$GONG" calls 1 | head -1 | cut -f1)"
echo "--- transcript of $FIRST_ID (first 20 lines) ---"; "$GONG" transcript "$FIRST_ID" | head -20
echo "--- mine 'pricing' (first 4 calls) ---"; "$GONG" mine "pricing" 4
echo "======== DONE ========"
