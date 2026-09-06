#!/usr/bin/env bash
# ABOUTME: Pillar IV-A difficulty-aware model dispatcher — reads a subtask descriptor JSON
# ABOUTME: on stdin and prints the appropriate model tier (haiku|sonnet|opus|fable) to stdout.
# ABOUTME: Matches route-policy.json rules top-down; falls back to haiku classifier call;
# ABOUTME: falls back to policy default_tier on classifier failure/timeout. Always exit 0.
# ABOUTME: Usage: echo '{"intent":"count lines","verb":"wc"}' | scripts/route-dispatch.sh

set -uo pipefail
trap 'exit 0' ERR
command -v jq >/dev/null 2>&1 || exit 0

# ── Path setup ───────────────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="${SCRIPT_DIR}/lib"
POLICY_FILE="${SCRIPT_DIR}/../policy/route-policy.json"
CLASSIFY_PROMPT="${SCRIPT_DIR}/templates/route-classify-prompt.md"

# Source event emitter (fail-open: if absent, define a no-op)
# Purpose: emit route_decision events without blocking the dispatch path.
# Gotchas: sourcing can fail if lib is absent; no-op fallback keeps dispatcher alive.
if [ -f "${LIB_DIR}/emit-event.sh" ]; then
  # shellcheck source=scripts/lib/emit-event.sh
  source "${LIB_DIR}/emit-event.sh" 2>/dev/null || true
else
  emit_event() { return 0; }
fi

# Source timeout wrapper (fail-open: if absent, define a no-op passthrough)
# Purpose: wrap classifier call with bounded wall-clock limit.
# Gotchas: _run_with_timeout is best-effort; if absent, command runs unrestricted.
if [ -f "${LIB_DIR}/timeout.sh" ]; then
  # shellcheck source=scripts/lib/timeout.sh
  source "${LIB_DIR}/timeout.sh" 2>/dev/null || true
fi
# Ensure _run_with_timeout exists even if sourcing failed
if ! declare -f _run_with_timeout >/dev/null 2>&1; then
  _run_with_timeout() { local _s="$1"; shift; "$@"; }
fi

# ── Read stdin ───────────────────────────────────────────────────────────────
# Purpose: consume and validate the subtask descriptor; malformed input exits silently.
# Gotchas: we must read ALL stdin before doing any work; partial read can hang pipelines.
STDIN_JSON="$(cat 2>/dev/null)" || STDIN_JSON=""

# Guard: malformed or empty JSON → exit 0 silently
if [ -z "${STDIN_JSON}" ]; then
  exit 0
fi
if ! printf '%s' "${STDIN_JSON}" | jq -e . >/dev/null 2>&1; then
  exit 0
fi

# ── Parse descriptor fields ──────────────────────────────────────────────────
INTENT="$(printf '%s' "${STDIN_JSON}" | jq -r '.intent // ""' 2>/dev/null || true)"
VERB="$(printf '%s' "${STDIN_JSON}" | jq -r '.verb // ""' 2>/dev/null || true)"
TOOL="$(printf '%s' "${STDIN_JSON}" | jq -r '.tool // ""' 2>/dev/null || true)"
SUBTASK_CLASS="$(printf '%s' "${STDIN_JSON}" | jq -r '.subtask_class // ""' 2>/dev/null || true)"
CALLER_TIER="$(printf '%s' "${STDIN_JSON}" | jq -r '.tier // ""' 2>/dev/null || true)"

# ── Caller-provided tier override (invariant: always wins) ───────────────────
# Purpose: explicit caller tier bypasses all routing logic per policy invariant.
if [ -n "${CALLER_TIER}" ]; then
  printf '%s\n' "${CALLER_TIER}"
  PAYLOAD=$(jq -cn \
    --arg sc "${SUBTASK_CLASS}" \
    --arg mt "${CALLER_TIER}" \
    --arg r  "caller-override" \
    '{subtask_class:$sc, model_tier:$mt, reason:$r}' 2>/dev/null) || PAYLOAD="{}"
  emit_event route_decision "${PAYLOAD}" source=route-dispatch.sh
  exit 0
fi

# ── Load policy ──────────────────────────────────────────────────────────────
# Purpose: read default_tier and classifier config from route-policy.json.
# Gotchas: if policy is absent or unparseable, fall back to hardcoded "sonnet".
DEFAULT_TIER="sonnet"
CLASSIFIER_ENABLED="true"
CLASSIFIER_MAX_MS="800"

if [ -f "${POLICY_FILE}" ] && jq -e . "${POLICY_FILE}" >/dev/null 2>&1; then
  DEFAULT_TIER="$(jq -r '.default_tier // "sonnet"' "${POLICY_FILE}" 2>/dev/null || echo "sonnet")"
  CLASSIFIER_ENABLED="$(jq -r '.classifier.enabled // "true"' "${POLICY_FILE}" 2>/dev/null || echo "true")"
  CLASSIFIER_MAX_MS="$(jq -r '.classifier.max_ms // "800"' "${POLICY_FILE}" 2>/dev/null || echo "800")"
fi

# ── Top-down rule matching ────────────────────────────────────────────────────
# Purpose: iterate policy rules and return the first match (subtask_class, tool, verb_re).
# Gotchas: verb_re is matched against BOTH verb and intent fields via POSIX ERE (grep -E).
#   Rule order matters — rules are evaluated strictly top-down.
_match_rules() {
  [ -f "${POLICY_FILE}" ] || return 1

  local rule_count
  rule_count="$(jq '.rules | length' "${POLICY_FILE}" 2>/dev/null || echo 0)"
  local i=0
  while [ "${i}" -lt "${rule_count}" ]; do
    local tier reason
    tier="$(jq -r ".rules[${i}].tier" "${POLICY_FILE}" 2>/dev/null || echo "")"
    reason="$(jq -r ".rules[${i}].reason" "${POLICY_FILE}" 2>/dev/null || echo "")"

    # Check subtask_class exact match
    local rule_sc
    rule_sc="$(jq -r ".rules[${i}].match.subtask_class // \"\"" "${POLICY_FILE}" 2>/dev/null || echo "")"
    if [ -n "${rule_sc}" ] && [ "${SUBTASK_CLASS}" = "${rule_sc}" ]; then
      printf '%s\t%s' "${tier}" "${reason}"
      return 0
    fi

    # Check tool exact match
    local rule_tool
    rule_tool="$(jq -r ".rules[${i}].match.tool // \"\"" "${POLICY_FILE}" 2>/dev/null || echo "")"
    if [ -n "${rule_tool}" ] && [ "${TOOL}" = "${rule_tool}" ]; then
      printf '%s\t%s' "${tier}" "${reason}"
      return 0
    fi

    # Check verb_re — matched against verb field AND intent field (BUG-ROUTE-01 fix).
    # Per the comment at L88: "verb_re is matched against BOTH verb and intent fields via
    # POSIX ERE (grep -E)."  Previously only VERB was tested; INTENT was parsed but unused.
    # For VERB: use the rule pattern as-is (exact anchored match is intentional for verbs).
    # For INTENT: strip ^ and $ anchors so a keyword embedded in a phrase can match.
    #   e.g. verb_re="^design$" + intent="design the system" → matches on the word "design".
    local rule_vre
    rule_vre="$(jq -r ".rules[${i}].match.verb_re // \"\"" "${POLICY_FILE}" 2>/dev/null || echo "")"
    if [ -n "${rule_vre}" ]; then
      # Verb match: use rule pattern directly (exact)
      if printf '%s' "${VERB}" | grep -qE "${rule_vre}" 2>/dev/null; then
        printf '%s\t%s' "${tier}" "${reason}"
        return 0
      fi
      # Intent match: relax anchors so a keyword anywhere in the intent phrase matches.
      # Strip leading ^ and trailing $ to allow substring / word match within the intent.
      local intent_vre
      intent_vre="$(printf '%s' "${rule_vre}" | sed 's/^\^//;s/\$$//')"
      if [ -n "${INTENT}" ] && [ -n "${intent_vre}" ] && \
         printf '%s' "${INTENT}" | grep -qEi "(^|[^[:alpha:]])${intent_vre}([^[:alpha:]]|$)" 2>/dev/null; then
        printf '%s\t%s' "${tier}" "${reason}"
        return 0
      fi
    fi

    i=$(( i + 1 ))
  done
  return 1
}

# Run rule matching
MATCH_RESULT="$(_match_rules 2>/dev/null || true)"

if [ -n "${MATCH_RESULT}" ]; then
  TIER="$(printf '%s' "${MATCH_RESULT}" | cut -f1)"
  RULE_REASON="$(printf '%s' "${MATCH_RESULT}" | cut -f2-)"
  printf '%s\n' "${TIER}"
  PAYLOAD=$(jq -cn \
    --arg sc "${SUBTASK_CLASS}" \
    --arg mt "${TIER}" \
    --arg r  "table:${RULE_REASON}" \
    '{subtask_class:$sc, model_tier:$mt, reason:$r}' 2>/dev/null) || PAYLOAD="{}"
  emit_event route_decision "${PAYLOAD}" source=route-dispatch.sh
  exit 0
fi

# ── Classifier fallback ───────────────────────────────────────────────────────
# Purpose: call haiku classifier when no rule matched; bounded by CLASSIFIER_MAX_MS.
# Gotchas: if classifier output is not exactly one valid tier word, treat as failure.
#   Classifier timeout → default-fallback (never block indefinitely).
#   This function runs in its own clean subshell to avoid ERR trap interference.
_run_classifier() {
  # Purpose: invoke the haiku classifier and return a single tier word to stdout.
  # Gotchas: this function runs inside a $() subshell whose ERR trap is inherited;
  #   we use a helper script file + `bash <helper>` to get a completely clean shell
  #   where the outer trap cannot interfere. The helper is written to a temp file,
  #   run once, and deleted. Fail-open: any step failure → return 1 (non-zero).
  #   IMPORTANT: do NOT redirect stdin in the bash call — PATH must be inherited from
  #   the caller's env, not re-specified. Callers must place PATH=... before `bash`,
  #   not before `printf` or other pipeline commands (bash does NOT inherit env
  #   prefixes placed on other pipeline stages).

  # Write classifier logic to a temp script.
  # Use -t syntax (macOS/BSD compatible): -t creates unique files in $TMPDIR.
  local _clf_tmp
  _clf_tmp="$(mktemp -t clf_XXXXXX 2>/dev/null)" || return 1
  # Pass required vars as env so the fresh shell can see them
  cat > "${_clf_tmp}" << 'CLF_SCRIPT'
#!/usr/bin/env bash
# Classifier helper — runs in a fresh shell with no inherited traps.
set -e
CLASSIFY_PROMPT="${_CLF_PROMPT}"
CLASSIFIER_MAX_MS="${_CLF_MAX_MS}"
STDIN_JSON="${_CLF_STDIN}"
source "${_CLF_TIMEOUT_LIB}" 2>/dev/null || _run_with_timeout() { local _s="$1"; shift; "$@"; }
[ -f "${CLASSIFY_PROMPT}" ] || exit 1
command -v claude >/dev/null 2>&1 || exit 1
prompt_content="$(cat "${CLASSIFY_PROMPT}")"
timeout_secs=$(( (CLASSIFIER_MAX_MS + 999) / 1000 ))
[ "${timeout_secs}" -lt 1 ] && timeout_secs=1
result="$(_run_with_timeout "${timeout_secs}" claude \
  -p --model haiku --allowedTools "" --max-turns 1 \
  "${prompt_content}"$'\n\n'"Task descriptor: ${STDIN_JSON}" 2>/dev/null)"
word="$(printf '%s' "${result}" | grep -E '^(haiku|sonnet|opus|fable)$' | tail -1)"
[ -n "${word}" ] || exit 1
printf '%s' "${word}"
CLF_SCRIPT
  chmod +x "${_clf_tmp}" 2>/dev/null || true
  local _clf_word
  _clf_word="$( \
    _CLF_PROMPT="${CLASSIFY_PROMPT}" \
    _CLF_MAX_MS="${CLASSIFIER_MAX_MS}" \
    _CLF_STDIN="${STDIN_JSON}" \
    _CLF_TIMEOUT_LIB="${LIB_DIR}/timeout.sh" \
    bash "${_clf_tmp}" 2>/dev/null \
  )" || true
  rm -f "${_clf_tmp}" 2>/dev/null || true
  [ -n "${_clf_word}" ] || return 1
  printf '%s' "${_clf_word}"
}

if [ "${CLASSIFIER_ENABLED}" = "true" ]; then
  CLASSIFIER_TIER="$(_run_classifier 2>/dev/null || true)"
  if [ -n "${CLASSIFIER_TIER}" ]; then
    printf '%s\n' "${CLASSIFIER_TIER}"
    PAYLOAD=$(jq -cn \
      --arg sc "${SUBTASK_CLASS}" \
      --arg mt "${CLASSIFIER_TIER}" \
      --arg r  "classifier" \
      '{subtask_class:$sc, model_tier:$mt, reason:$r}' 2>/dev/null) || PAYLOAD="{}"
    emit_event route_decision "${PAYLOAD}" source=route-dispatch.sh
    exit 0
  fi
fi

# ── Default fallback ──────────────────────────────────────────────────────────
# Purpose: last-resort fallback when rules miss and classifier fails/times out.
printf '%s\n' "${DEFAULT_TIER}"
PAYLOAD=$(jq -cn \
  --arg sc "${SUBTASK_CLASS}" \
  --arg mt "${DEFAULT_TIER}" \
  --arg r  "default-fallback" \
  '{subtask_class:$sc, model_tier:$mt, reason:$r}' 2>/dev/null) || PAYLOAD="{}"
emit_event route_decision "${PAYLOAD}" source=route-dispatch.sh
exit 0
