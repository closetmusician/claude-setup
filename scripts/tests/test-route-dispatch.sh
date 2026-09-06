#!/usr/bin/env bash
# ABOUTME: TDD test suite for scripts/route-dispatch.sh — difficulty-aware model dispatcher.
# ABOUTME: Covers all 4 tiers via direct rule matches, classifier shim, timeout fallback,
# ABOUTME: and malformed-stdin safety. Self-contained: mktemp fixtures, no real claude calls.
# ABOUTME: Run: bash scripts/tests/test-route-dispatch.sh — must be RED before dispatcher exists.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DISPATCH="${SCRIPT_DIR}/../route-dispatch.sh"
POLICY="${SCRIPT_DIR}/../../policy/route-policy.json"

# ── Isolated temp STATE for event capture ───────────────────────────────────
TMPROOT="$(mktemp -d /tmp/test-route-XXXXXX)"
export STATE="${TMPROOT}/governance"
EVENTS="${STATE}/state/events.ndjson"
mkdir -p "${STATE}/state"

# ── Shim directory for PATH injection ───────────────────────────────────────
SHIMDIR="${TMPROOT}/shims"
mkdir -p "${SHIMDIR}"

PASS=0
FAIL=0

_pass() { printf "  PASS: %s\n" "$1"; (( PASS++ )) || true; }
_fail() { printf "  FAIL: %s — %s\n" "$1" "$2"; (( FAIL++ )) || true; }

# Clear events file between tests
_fresh() {
  rm -f "${EVENTS}" || true
  rm -rf "${STATE}/state/.events.lock.d" || true
}

# Count route_decision events in the events file
_count_route_events() {
  [ -f "${EVENTS}" ] || { printf "0"; return; }
  grep -c '"route_decision"' "${EVENTS}" 2>/dev/null || printf "0"
}

# Get last emitted tier from events
_last_tier() {
  [ -f "${EVENTS}" ] || { printf ""; return; }
  tail -1 "${EVENTS}" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('payload',{}).get('model_tier',''))" 2>/dev/null || printf ""
}

# Get last emitted reason from events
_last_reason() {
  [ -f "${EVENTS}" ] || { printf ""; return; }
  tail -1 "${EVENTS}" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('payload',{}).get('reason',''))" 2>/dev/null || printf ""
}

echo "=== test-route-dispatch.sh ==="
echo "DISPATCH=${DISPATCH}"
echo "EVENTS=${EVENTS}"
echo ""

# ── 1: count verb → haiku ────────────────────────────────────────────────────
_fresh
T="count verb → haiku"
tier=$(printf '{"intent":"count lines in file","verb":"wc"}' | bash "${DISPATCH}" 2>/dev/null)
events_n=$(_count_route_events)
if [ "${tier}" = "haiku" ] && [ "${events_n}" -ge 1 ]; then
  _pass "${T}"
else
  _fail "${T}" "got tier='${tier}' events=${events_n}, want tier=haiku events>=1"
fi

# ── 2: diff subtask_class → haiku ───────────────────────────────────────────
_fresh
T="diff subtask_class → haiku"
tier=$(printf '{"intent":"summarize git diff","subtask_class":"diff"}' | bash "${DISPATCH}" 2>/dev/null)
events_n=$(_count_route_events)
if [ "${tier}" = "haiku" ] && [ "${events_n}" -ge 1 ]; then
  _pass "${T}"
else
  _fail "${T}" "got tier='${tier}' events=${events_n}, want tier=haiku events>=1"
fi

# ── 3: existence subtask_class → haiku ──────────────────────────────────────
_fresh
T="existence check → haiku"
tier=$(printf '{"intent":"check if file exists","subtask_class":"existence"}' | bash "${DISPATCH}" 2>/dev/null)
if [ "${tier}" = "haiku" ]; then
  _pass "${T}"
else
  _fail "${T}" "got '${tier}', want haiku"
fi

# ── 4: grep verb → haiku ────────────────────────────────────────────────────
_fresh
T="grep verb → haiku"
tier=$(printf '{"intent":"search for pattern in codebase","verb":"grep"}' | bash "${DISPATCH}" 2>/dev/null)
if [ "${tier}" = "haiku" ]; then
  _pass "${T}"
else
  _fail "${T}" "got '${tier}', want haiku"
fi

# ── 5: edit subtask_class → sonnet ──────────────────────────────────────────
_fresh
T="edit subtask_class → sonnet"
tier=$(printf '{"intent":"edit the config file","subtask_class":"edit"}' | bash "${DISPATCH}" 2>/dev/null)
events_n=$(_count_route_events)
if [ "${tier}" = "sonnet" ] && [ "${events_n}" -ge 1 ]; then
  _pass "${T}"
else
  _fail "${T}" "got tier='${tier}' events=${events_n}, want tier=sonnet events>=1"
fi

# ── 6: apply verb → sonnet ──────────────────────────────────────────────────
_fresh
T="apply verb → sonnet"
tier=$(printf '{"intent":"apply patch to main.py","verb":"apply"}' | bash "${DISPATCH}" 2>/dev/null)
if [ "${tier}" = "sonnet" ]; then
  _pass "${T}"
else
  _fail "${T}" "got '${tier}', want sonnet"
fi

# ── 7: verify subtask_class → sonnet ────────────────────────────────────────
_fresh
T="verify subtask_class → sonnet"
tier=$(printf '{"intent":"oracle verify test output","subtask_class":"verify"}' | bash "${DISPATCH}" 2>/dev/null)
if [ "${tier}" = "sonnet" ]; then
  _pass "${T}"
else
  _fail "${T}" "got '${tier}', want sonnet"
fi

# ── 8: synthesis subtask_class → opus ───────────────────────────────────────
_fresh
T="synthesis subtask_class → opus"
tier=$(printf '{"intent":"synthesize architecture findings","subtask_class":"synthesis"}' | bash "${DISPATCH}" 2>/dev/null)
events_n=$(_count_route_events)
if [ "${tier}" = "opus" ] && [ "${events_n}" -ge 1 ]; then
  _pass "${T}"
else
  _fail "${T}" "got tier='${tier}' events=${events_n}, want tier=opus events>=1"
fi

# ── 9: architecture subtask_class → opus ────────────────────────────────────
_fresh
T="architecture subtask_class → opus"
tier=$(printf '{"intent":"design system architecture","subtask_class":"architecture"}' | bash "${DISPATCH}" 2>/dev/null)
if [ "${tier}" = "opus" ]; then
  _pass "${T}"
else
  _fail "${T}" "got '${tier}', want opus"
fi

# ── 10: design verb → opus ──────────────────────────────────────────────────
_fresh
T="design verb → opus"
tier=$(printf '{"intent":"design the database schema","verb":"design"}' | bash "${DISPATCH}" 2>/dev/null)
if [ "${tier}" = "opus" ]; then
  _pass "${T}"
else
  _fail "${T}" "got '${tier}', want opus"
fi

# ── 11: prose-voice subtask_class → fable ───────────────────────────────────
_fresh
T="prose-voice subtask_class → fable"
tier=$(printf '{"intent":"write stakeholder communication in yk-voice","subtask_class":"prose-voice"}' | bash "${DISPATCH}" 2>/dev/null)
events_n=$(_count_route_events)
if [ "${tier}" = "fable" ] && [ "${events_n}" -ge 1 ]; then
  _pass "${T}"
else
  _fail "${T}" "got tier='${tier}' events=${events_n}, want tier=fable events>=1"
fi

# ── 12: briefing subtask_class → fable ──────────────────────────────────────
_fresh
T="briefing subtask_class → fable"
tier=$(printf '{"intent":"draft PR briefing","subtask_class":"briefing"}' | bash "${DISPATCH}" 2>/dev/null)
if [ "${tier}" = "fable" ]; then
  _pass "${T}"
else
  _fail "${T}" "got '${tier}', want fable"
fi

# ── 13: unknown verb + PATH-shim fake claude returning "sonnet" → classifier ─
_fresh
T="unknown verb → classifier shim → sonnet with reason:classifier"
# Install a fake `claude` shim that returns "sonnet"
cat > "${SHIMDIR}/claude" << 'SHIM'
#!/usr/bin/env bash
# Fake claude: consume all args, print tier to stdout
printf "sonnet\n"
SHIM
chmod +x "${SHIMDIR}/claude"
tier=$(printf '{"intent":"xyzzy frob the widget","verb":"xyzzy-unknown"}' | PATH="${SHIMDIR}:${PATH}" bash "${DISPATCH}" 2>/dev/null)
reason=$(_last_reason)
events_n=$(_count_route_events)
if [ "${tier}" = "sonnet" ] && [[ "${reason}" == *"classifier"* ]] && [ "${events_n}" -ge 1 ]; then
  _pass "${T}"
else
  _fail "${T}" "got tier='${tier}' reason='${reason}' events=${events_n}, want tier=sonnet reason~classifier events>=1"
fi
# Remove shim after test
rm -f "${SHIMDIR}/claude"

# ── 14: classifier timeout → default-fallback ───────────────────────────────
_fresh
T="classifier timeout (shim sleeps 10s) → default-fallback"
# Install a slow fake `claude` shim
cat > "${SHIMDIR}/claude" << 'SHIM'
#!/usr/bin/env bash
# Slow claude: sleep longer than dispatcher timeout
sleep 10
printf "haiku\n"
SHIM
chmod +x "${SHIMDIR}/claude"
tier=$(printf '{"intent":"totally unknown task nobody mapped","verb":"blurble"}' | PATH="${SHIMDIR}:${PATH}" bash "${DISPATCH}" 2>/dev/null)
reason=$(_last_reason)
events_n=$(_count_route_events)
if [ "${tier}" = "sonnet" ] && [[ "${reason}" == *"default"* ]] && [ "${events_n}" -ge 1 ]; then
  _pass "${T}"
else
  _fail "${T}" "got tier='${tier}' reason='${reason}' events=${events_n}, want tier=sonnet(default) reason~default events>=1"
fi
rm -f "${SHIMDIR}/claude"

# ── 15: malformed stdin → exit 0 silently ───────────────────────────────────
_fresh
T="malformed stdin → exit 0 (no crash)"
rc=$(printf 'not-json{{{' | bash "${DISPATCH}" 2>/dev/null; echo $?)
# Should exit 0 and produce no output or a safe default
if [ "${rc}" = "0" ]; then
  _pass "${T}"
else
  _fail "${T}" "exited ${rc}, want exit 0"
fi

# ── 16: one route_decision per dispatch (emit invariant) ────────────────────
_fresh
T="each dispatch emits exactly one route_decision event"
printf '{"intent":"count words","verb":"wc"}' | bash "${DISPATCH}" 2>/dev/null >/dev/null
events_n=$(_count_route_events)
if [ "${events_n}" -eq 1 ]; then
  _pass "${T}"
else
  _fail "${T}" "got ${events_n} route_decision events, want exactly 1"
fi

# ── 17: BUG-ROUTE-01 — intent-only routing: no verb, phrase contains opus keyword ──
# RED on old code: VERB="" never matches ^audit$, falls through to classifier.
# GREEN after fix: INTENT phrase is matched against the verb_re keyword; routes opus.
_fresh
T="BUG-ROUTE-01: intent-only 'please audit the codebase' → opus"
tier=$(printf '{"intent":"please audit the codebase for security issues"}' | bash "${DISPATCH}" 2>/dev/null)
events_n=$(_count_route_events)
if [ "${tier}" = "opus" ] && [ "${events_n}" -ge 1 ]; then
  _pass "${T}"
else
  _fail "${T}" "got tier='${tier}' events=${events_n}, want tier=opus events>=1 (BUG-ROUTE-01)"
fi

# ── 18: BUG-ROUTE-01 variant — intent contains 'design' as keyword in phrase ──
_fresh
T="BUG-ROUTE-01: intent phrase contains 'design' → opus"
tier=$(printf '{"intent":"design the system architecture for the new API"}' | bash "${DISPATCH}" 2>/dev/null)
if [ "${tier}" = "opus" ]; then
  _pass "${T}"
else
  _fail "${T}" "got '${tier}', want opus (intent-phrase match)"
fi

# ── 19: BUG-ROUTE-01 guard — intent contains non-opus word, no verb → sonnet (default) ──
_fresh
T="BUG-ROUTE-01 guard: unrelated intent, no verb → not opus"
tier=$(printf '{"intent":"count lines in the config file"}' | bash "${DISPATCH}" 2>/dev/null)
if [ "${tier}" != "opus" ]; then
  _pass "${T}"
else
  _fail "${T}" "got opus for non-audit intent '${tier}' — over-routing"
fi

# ── 20: BUG-ROUTE-01 — intent contains 'audit' → opus ───────────────────────
_fresh
T="BUG-ROUTE-01: intent phrase 'audit the security controls' → opus"
tier=$(printf '{"intent":"audit the security controls in auth.ts"}' | bash "${DISPATCH}" 2>/dev/null)
if [ "${tier}" = "opus" ]; then
  _pass "${T}"
else
  _fail "${T}" "got '${tier}', want opus (audit keyword in intent)"
fi

# ── Cleanup ──────────────────────────────────────────────────────────────────
rm -rf "${TMPROOT}"

# ── Summary ──────────────────────────────────────────────────────────────────
echo ""
echo "Results: ${PASS} passed, ${FAIL} failed (total $((PASS + FAIL)))"
if [ "${FAIL}" -gt 0 ]; then
  exit 1
fi
exit 0
