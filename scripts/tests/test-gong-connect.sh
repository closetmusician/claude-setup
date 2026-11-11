#!/usr/bin/env bash
# ABOUTME: Regression suite for skills/gong-connect/bin/gong auth detection.
# ABOUTME: Bug 2026-10-08: logged-out /ajax calls return HTTP 401, which Chrome renders as its
# ABOUTME: own error page with no sign-in text. connect and the login poll read that as
# ABOUTME: "authenticated", so every stale call re-popped login forever. T4-T6: parallel callers
# ABOUTME: share ONE login. T7-T13: pool of 10, hang kill, Chrome for Testing, download.
# ABOUTME: T1/T3 hit REAL Gong; T2/T4-T13 stub only the browser (SSO needs a human).

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GONG="${SCRIPT_DIR}/../../skills/gong-connect/bin/gong"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

PASS=0; FAIL=0
ok()   { PASS=$((PASS + 1)); echo "PASS  $1"; }
bad()  { FAIL=$((FAIL + 1)); echo "FAIL  $1"; }

# A storageState with no Gong cookies = a logged-out session, without touching the real one.
printf '%s\n' '{"cookies":[],"origins":[]}' > "$TMP/empty-state.json"

# T1 — real Gong: connect with no cookies must report NOT authenticated (exit 3).
out="$(GONG_STATE="$TMP/empty-state.json" GONG_NO_AUTOLOGIN=1 "$GONG" connect 2>&1)"; rc=$?
if [ "$rc" -eq 3 ] && ! printf '%s' "$out" | grep -q 'Authenticated OK'; then
  ok "T1 connect with no cookies exits 3"
else
  bad "T1 connect with no cookies exits 3 (got rc=$rc: $out)"
fi

# T2 — login poll must not accept Chrome's 401 error page as a signed-in session.
# Stub browser: `state save` writes a snapshot, `get text body` returns the 401 page text
# captured live from Gong on 2026-10-08; every other verb succeeds silently.
cat > "$TMP/ab-401.sh" <<'EOF'
#!/usr/bin/env bash
args="$*"
case "$args" in
  *"state save"*) printf '{"cookies":[],"origins":[]}' > "${@: -1}" ;;
  *"get text body"*) printf '%s\n' "This page isn’t working" "" \
      "If the problem continues, contact the site owner." "" "HTTP ERROR 401" "Reload" ;;
esac
exit 0
EOF
chmod +x "$TMP/ab-401.sh"
printf 'ORIGINAL' > "$TMP/state.json"
out="$(AGENT_BROWSER_BIN="$TMP/ab-401.sh" GONG_STATE="$TMP/state.json" GONG_PROFILE="$TMP/profile" \
  GONG_LOGIN_TIMEOUT=4 "$GONG" login 2>&1)"; rc=$?
if [ "$rc" -eq 3 ] && ! printf '%s' "$out" | grep -q 'Authenticated' \
   && [ "$(cat "$TMP/state.json")" = "ORIGINAL" ]; then
  ok "T2 login rejects the Chrome 401 page and keeps the saved state"
else
  bad "T2 login rejects the Chrome 401 page (got rc=$rc, state=$(cat "$TMP/state.json"): $out)"
fi

# T3 — real saved session: connect must agree with a real data fetch. If the live session is
# valid both succeed; if it is stale both must fail. A mismatch is the false-positive bug.
GONG_NO_AUTOLOGIN=1 "$GONG" connect >/dev/null 2>&1; crc=$?
rows="$(GONG_NO_AUTOLOGIN=1 "$GONG" calls 1 2>/dev/null | grep -c .)"
if { [ "$crc" -eq 0 ] && [ "$rows" -ge 1 ]; } || { [ "$crc" -ne 0 ] && [ "$rows" -eq 0 ]; }; then
  ok "T3 connect agrees with a real fetch (connect rc=$crc, rows=$rows)"
else
  bad "T3 connect agrees with a real fetch (connect rc=$crc, rows=$rows)"
fi

# Parallel-login cases (T4-T6). Stub browser: a headed open is one SSO "pop" (logged to
# $STUB_DIR/pops). With STUB_SSO=ok the user "finishes SSO" 2s after the first pop; with
# STUB_SSO=never they never do. Bodies are the real sign-in page text (captured 2026-10-08)
# until SSO is done, then JSON.
cat > "$TMP/ab-sso.sh" <<'EOF'
#!/usr/bin/env bash
d="$STUB_DIR"
case "$*" in
  *--headed*) echo pop >> "$d/pops"
    [ "$STUB_SSO" = ok ] && { ( sleep 2; touch "$d/authed" ) >/dev/null 2>&1 & } ;;
  *"state save"*) printf '{"cookies":[],"origins":[]}' > "${@: -1}" ;;
  *"get text body"*)
    if [ -f "$d/authed" ]; then printf '{"callTitle":"t","monologues":[]}'
    else printf '%s\n' "The Gong Revenue AI Platform" "Sign in with Enterprise SSO" "" "OR" "" \
      "Sign in with email & password" "Don't have a password?" " More sign-in options"; fi ;;
esac
exit 0
EOF
chmod +x "$TMP/ab-sso.sh"

# run_parallel <case-dir> <n> <sso-mode> <login-timeout> — start n `gong transcript` calls at
# once against a stale state; prints "<pops> <count of rc=0> <count of rc=3>".
run_parallel() {
  local d="$1" n="$2" i
  mkdir -p "$d"; : > "$d/pops"
  printf '{}' > "$d/state.json"; touch -t 202601010000 "$d/state.json"
  for i in $(seq "$n"); do
    ( STUB_DIR="$d" STUB_SSO="$3" AGENT_BROWSER_BIN="$TMP/ab-sso.sh" GONG_STATE="$d/state.json" \
        GONG_PROFILE="$d/profile" GONG_LOGIN_TIMEOUT="$4" "$GONG" transcript 1 >/dev/null 2>&1
      echo $? > "$d/rc.$i" ) &
  done
  wait
  echo "$(grep -c . "$d/pops") $(cat "$d"/rc.* | grep -cx 0) $(cat "$d"/rc.* | grep -cx 3)"
}

# T4 — 5 agents hit a stale session together: ONE SSO pop, and all 5 then succeed.
read -r pops ok0 _ <<< "$(run_parallel "$TMP/t4" 5 ok 20)"
if [ "$pops" -eq 1 ] && [ "$ok0" -eq 5 ]; then
  ok "T4 5 parallel stale calls share one login"
else
  bad "T4 5 parallel stale calls share one login (pops=$pops, succeeded=$ok0/5)"
fi

# T5 — SSO never completes: still ONE pop, and every caller fails with exit 3.
read -r pops _ rc3 <<< "$(run_parallel "$TMP/t5" 3 never 4)"
if [ "$pops" -eq 1 ] && [ "$rc3" -eq 3 ]; then
  ok "T5 a timed-out login is not repeated by the waiting callers"
else
  bad "T5 a timed-out login is not repeated by the waiting callers (pops=$pops, rc3=$rc3/3)"
fi

# T6 — a lock left by a dead process is broken, not waited on forever.
mkdir -p "$TMP/t6/state.json.login.lock"
sleep 0 & dead=$!; wait "$dead"; echo "$dead" > "$TMP/t6/state.json.login.lock/pid"
read -r pops ok0 _ <<< "$(run_parallel "$TMP/t6" 1 ok 20)"
if [ "$pops" -eq 1 ] && [ "$ok0" -eq 1 ] && [ ! -d "$TMP/t6/state.json.login.lock" ]; then
  ok "T6 a dead holder's lock is broken and the lock is released after"
else
  bad "T6 a dead holder's lock is broken (pops=$pops, succeeded=$ok0/1)"
fi

# Pool, browser and cleanup cases (T7-T13). Stub browser: logs every call as
# "<session> <idle-ms> <executable> <verb...>" to $STUB_DIR/log. `get text body` returns a
# transcript JSON after STUB_SLEEP seconds, and tracks how many callers are inside at once.
# STUB_HANG=1 makes every verb hang (exec sleep, so the timeout kills the sleep itself).
cat > "$TMP/ab-pool.sh" <<'EOF'
#!/usr/bin/env bash
d="$STUB_DIR"; sess="-"; prev=""
for a in "$@"; do [ "$prev" = "--session" ] && sess="$a"; prev="$a"; done
echo "$sess ${AGENT_BROWSER_IDLE_TIMEOUT_MS:-unset} ${AGENT_BROWSER_EXECUTABLE_PATH:-unset} $*" >> "$d/log"
[ "${STUB_HANG:-}" = 1 ] && exec sleep 30
case "$*" in
  install) [ -n "${STUB_INSTALL_TO:-}" ] && mkdir -p "$(dirname "$STUB_INSTALL_TO")" \
             && touch "$STUB_INSTALL_TO" && chmod +x "$STUB_INSTALL_TO" ;;
  *"get text body"*)
    touch "$d/active.$$"; ls "$d" | grep -c '^active\.' >> "$d/peak"
    sleep "${STUB_SLEEP:-0}"; rm -f "$d/active.$$"
    printf '{"callTitle":"Demo","callCustomers":"Acme","when":"2026-11-01","monologues":[{"timestampStr":"0:01","speakerName":"Ann","text":"hi"}]}' ;;
esac
exit 0
EOF
chmod +x "$TMP/ab-pool.sh"
touch "$TMP/fake-cft"; chmod +x "$TMP/fake-cft"

# pool_env <case-dir> — env for a stubbed call: own pool dir, own HOME, fake Chrome for Testing.
pool_env() {
  mkdir -p "$1/home"; : >> "$1/log"
  echo "STUB_DIR=$1 HOME=$1/home AGENT_BROWSER_BIN=$TMP/ab-pool.sh GONG_POOL_DIR=$1/pool \
GONG_STATE=$1/state.json GONG_PROFILE=$1/profile GONG_NO_AUTOLOGIN=1 GONG_CHROME=$TMP/fake-cft"
}

# T7 — 14 callers at once: never more than 10 inside the browser together, only the 10
# pool sessions are used, and every caller still succeeds.
d="$TMP/t7"; mkdir -p "$d"
for i in $(seq 14); do
  ( env $(pool_env "$d") STUB_SLEEP=1 "$GONG" transcript "$i" >/dev/null 2>&1; echo $? > "$d/rc.$i" ) &
done
wait
peak="$(sort -n "$d/peak" | tail -1)"
sessions="$(awk '{print $1}' "$d/log" | sort -u | tr '\n' ' ')"
okc="$(cat "$d"/rc.* | grep -cx 0)"
bad_sess="$(awk '{print $1}' "$d/log" | sort -u | grep -cvE '^gong-pool-([1-9]|10)$')"
if [ "$peak" -le 10 ] && [ "$okc" -eq 14 ] && [ "$bad_sess" -eq 0 ]; then
  ok "T7 14 parallel callers share a pool of at most 10 browsers (peak=$peak)"
else
  bad "T7 pool of at most 10 (peak=$peak, succeeded=$okc/14, sessions=$sessions)"
fi

# T8 — a hung browser is killed: gong exits 6 (hung, NOT 3 = logged out, so no login pop)
# within the command timeout plus the 5s close limit, asks the session to close, and kills
# the session's daemon from its pid file.
d="$TMP/t8"; mkdir -p "$d/home/.agent-browser"
sleep 300 & daemon=$!; disown "$daemon"; echo "$daemon" > "$d/home/.agent-browser/gong-pool-1.pid"
start=$(date +%s)
env $(pool_env "$d") STUB_HANG=1 GONG_AB_TIMEOUT=2 "$GONG" transcript 1 >/dev/null 2>&1; rc=$?
took=$(( $(date +%s) - start ))
sleep 1
if [ "$rc" -eq 6 ] && [ "$took" -le 10 ] && grep -q 'gong-pool-1 .* close' "$d/log" \
   && ! kill -0 "$daemon" 2>/dev/null; then
  ok "T8 a hung browser is killed and gong exits (rc=$rc in ${took}s)"
else
  bad "T8 hung browser killed (rc=$rc, took=${took}s, daemon alive=$(kill -0 "$daemon" 2>/dev/null && echo yes || echo no))"
  kill "$daemon" 2>/dev/null
fi

# T9 — every browser call runs Chrome for Testing with an idle shutdown (default 15s).
d="$TMP/t9"; mkdir -p "$d"
env $(pool_env "$d") "$GONG" transcript 1 >/dev/null 2>&1
wrong="$(awk -v exe="$TMP/fake-cft" '$2 != "15000" || $3 != exe' "$d/log" | grep -c .)"
if [ -s "$d/log" ] && [ "$wrong" -eq 0 ]; then
  ok "T9 browser calls pin Chrome for Testing and a 15s idle shutdown"
else
  bad "T9 Chrome for Testing + idle shutdown ($wrong wrong calls): $(head -3 "$d/log")"
fi

# T10 — no Chrome for Testing and the install fails: exit 4, the browser never opens.
d="$TMP/t10"; mkdir -p "$d"
env $(pool_env "$d") GONG_CHROME= "$GONG" transcript 1 >/dev/null 2>&1; rc=$?
if [ "$rc" -eq 4 ] && grep -q ' install$' "$d/log" && ! grep -q ' open ' "$d/log"; then
  ok "T10 a missing Chrome for Testing stops gong instead of using the real Chrome"
else
  bad "T10 missing Chrome for Testing (rc=$rc): $(cat "$d/log")"
fi

# T10b — the one-time install hangs: gong gives up after GONG_INSTALL_TIMEOUT with exit 4.
d="$TMP/t10b"; mkdir -p "$d"; start=$(date +%s)
env $(pool_env "$d") GONG_CHROME= STUB_HANG=1 GONG_INSTALL_TIMEOUT=2 "$GONG" transcript 1 >/dev/null 2>&1; rc=$?
took=$(( $(date +%s) - start ))
if [ "$rc" -eq 4 ] && [ "$took" -le 6 ]; then
  ok "T10b a hung Chrome for Testing install times out with exit 4 (${took}s)"
else
  bad "T10b hung install times out (rc=$rc in ${took}s)"
fi

# T11 — no Chrome for Testing yet: gong installs it, then runs with the installed copy.
d="$TMP/t11"; mkdir -p "$d"
cft="$d/home/.agent-browser/browsers/chrome-1.0/Google Chrome for Testing.app/Contents/MacOS/Google Chrome for Testing"
env $(pool_env "$d") GONG_CHROME= STUB_INSTALL_TO="$cft" "$GONG" transcript 1 >/dev/null 2>&1; rc=$?
if [ "$rc" -eq 0 ] && grep -q ' open ' "$d/log" && grep ' open ' "$d/log" | grep -qF "chrome-1.0/Google"; then
  ok "T11 gong installs Chrome for Testing when missing and then uses it"
else
  bad "T11 install then use (rc=$rc): $(cat "$d/log")"
fi

# T12 — `gong download` writes each transcript into the working folder and prints the paths.
d="$TMP/t12"; mkdir -p "$d/work"
out="$(cd "$d/work" && env $(pool_env "$d") "$GONG" download 111 222 2>/dev/null)"; rc=$?
if [ "$rc" -eq 0 ] && grep -q 'Ann: hi' "$d/work/gong-111.txt" 2>/dev/null \
   && jq -e '.monologues' "$d/work/gong-222.json" >/dev/null 2>&1 \
   && printf '%s' "$out" | grep -q 'gong-111.txt' && printf '%s' "$out" | grep -q 'gong-222.txt'; then
  ok "T12 download saves gong-<id>.txt and .json in the working folder"
else
  bad "T12 download to working folder (rc=$rc, out=$out, files=$(ls "$d/work"))"
fi

# T13 — pool slots: a dead holder's slot is reclaimed; with every slot held by a live
# process, a caller gives up after GONG_POOL_WAIT with exit 5.
d="$TMP/t13"; mkdir -p "$d/pool/slot-1"
sleep 0 & dead=$!; wait "$dead"; echo "$dead" > "$d/pool/slot-1/pid"
env $(pool_env "$d") GONG_POOL_SIZE=1 "$GONG" transcript 1 >/dev/null 2>&1; rc_dead=$?
sleep 300 & live=$!; mkdir -p "$d/pool/slot-1"; echo "$live" > "$d/pool/slot-1/pid"
start=$(date +%s)
env $(pool_env "$d") GONG_POOL_SIZE=1 GONG_POOL_WAIT=2 "$GONG" transcript 1 >/dev/null 2>&1; rc_busy=$?
took=$(( $(date +%s) - start )); kill "$live" 2>/dev/null
if [ "$rc_dead" -eq 0 ] && [ "$rc_busy" -eq 5 ] && [ "$took" -le 8 ]; then
  ok "T13 dead slots are reclaimed and a full pool times out with exit 5"
else
  bad "T13 slot reclaim / full pool (dead-slot rc=$rc_dead, busy rc=$rc_busy in ${took}s)"
fi

echo "---"
echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
