#!/usr/bin/env bash
# ABOUTME: Regression suite for skills/gong-connect/bin/gong auth detection.
# ABOUTME: Bug 2026-10-08: logged-out /ajax calls return HTTP 401, which Chrome renders as its
# ABOUTME: own error page with no sign-in text. connect and the login poll read that as
# ABOUTME: "authenticated", so every stale call re-popped login forever. T4-T6: parallel callers
# ABOUTME: share ONE login. T1/T3 hit REAL Gong; T2/T4-T6 stub only the browser (SSO needs a human).

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

echo "---"
echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
