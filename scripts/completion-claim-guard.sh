#!/usr/bin/env bash
# ABOUTME: Stop hook: blocks ending the turn on an unevidenced or fabricated completion claim.
# ABOUTME: Audit 2026-07-03 trust study: 46 real incidents/6mo. Hardened per adversarial review
# ABOUTME: (docs/temp/adv-review-0703/): evidence must VERIFY, not just look like evidence —
# ABOUTME: cited artifacts must exist on disk; claimed test counts must appear in a non-assistant
# ABOUTME: transcript line. Stage 3 (II.2): reconcile test-count claims against the evidence
# ABOUTME: ledger (events.ndjson) — requires a same-session trust_decision test-run token.
# ABOUTME: Fail-open on errors; stop_hook_active retries are logged, not free.

set -uo pipefail
trap 'exit 0' ERR

command -v jq >/dev/null 2>&1 || exit 0

# Pillar I emit — purely additive; fail-open via emit_event design + || true guard.
_CCG_EMIT_SH="${HOME}/.claude/scripts/lib/emit-event.sh"
# shellcheck disable=SC1090
[[ -f "$_CCG_EMIT_SH" ]] && source "$_CCG_EMIT_SH" 2>/dev/null || true
unset _CCG_EMIT_SH

INPUT=$(cat)

TRANSCRIPT=$(echo "$INPUT" | jq -r '.transcript_path // empty')
[[ -f "$TRANSCRIPT" ]] || exit 0

CWD=$(echo "$INPUT" | jq -r '.cwd // empty')

# Last assistant text blocks (tail keeps this O(1) on huge transcripts).
LAST=$(tail -80 "$TRANSCRIPT" | jq -rs '
  [ .[] | select(.type=="assistant") | .message.content
    | if type=="array" then (map(select(.type=="text") | .text) | join(" ")) else . end
  ] | last // empty' 2>/dev/null)
[[ -z "$LAST" ]] && exit 0

LOG_DIR="$HOME/.claude/state"
mkdir -p "$LOG_DIR" 2>/dev/null || true

# Loop protection: a continuation forced by a previous block cannot be re-blocked,
# but it is no longer a free pass (bypass B4) — log it so harness-doctor can audit
# whether the retry actually added evidence or just restated the claim.
if [[ "$(echo "$INPUT" | jq -r '.stop_hook_active // false')" == "true" ]]; then
  printf '%s stop_hook_active retry: %.300s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$LAST" \
    >> "$LOG_DIR/completion-claim-guard.log" 2>/dev/null || true
  exit 0
fi

block() {
  # trust_decision emit on deny — purely additive; before the block JSON output.
  emit_event "trust_decision" '{"guard":"completion-claim-guard","claim_type":"completion"}' \
    outcome="denied" source="completion-claim-guard.sh" || true
  jq -cn --arg r "$1" '{"decision":"block","reason":$r}'
  exit 0
}

# Resolve a cited path token against ~, absolute, or the session cwd. Echoes the
# resolved path if checkable, nothing if the token cannot be resolved (fail-open per token).
resolve_path() {
  local p="$1"
  case "$p" in
    "~"*) echo "${HOME}${p:1}" ;;
    /*)   echo "$p" ;;
    *)    [[ -n "$CWD" ]] && echo "$CWD/$p" ;;
  esac
}

# --- Class C1: existence-denial misreport ("file not found" while it exists) -------------
# Only paths on the same line as the denial phrase are checked, to avoid punishing
# messages that mention other, genuinely present paths elsewhere.
DENIAL='(does not|doesn'"'"'?t) exist|no such file( or directory)?|(file|path|directory|binary|script) (was )?not found'
if echo "$LAST" | grep -qiE "$DENIAL"; then
  while IFS= read -r line; do
    while IFS= read -r tok; do
      [[ -z "$tok" ]] && continue
      rp="$(resolve_path "$tok")"
      if [[ -n "$rp" && -e "$rp" ]]; then
        block "State misreport (completion-claim-guard, class C1 — 13/46 audited incidents): the final message claims '$tok' does not exist, but it exists at $rp. Re-check the environment and correct the claim before finishing."
      fi
    done < <(echo "$line" | grep -oE '(~|/)[A-Za-z0-9._/-]{3,}' | head -5)
  done < <(echo "$LAST" | grep -iE "$DENIAL" | head -5)
fi

# --- Completion-claim signatures (case-insensitive; broadened per bypass finding B3) -----
# BUG-ADV2-01 fix: added natural-language done-synonyms ("good to go", "wrapped up",
# "in place and behaving", "all set", "has been completed", "shipped").
# Precision rule: each new phrase requires a COMPLETION-SHAPED context to avoid false
# positives on benign uses ("ready when you are" → not a claim; "tests are good" → no match).
CLAIM='(all( [0-9]+)? tests? pass(ed)?|tests? (are |now )?(all )?passing|deployed and (verified|working)|successfully (deployed|implemented|completed|fixed|migrated)|implementation (is )?(now )?complete|(task|work|everything|migration|feature|fix) is (complete|completed|done|finished)|completed successfully|everything works|works as expected|fully (implemented|fixed|working|tested)|done and verified|verified (and )?working|\ball done\b|\bLGTM\b|ready (for review|to merge)|fix(es)? (is |are |has been |have been )?applied|ci (is )?(green|passing|passes)|\bgood to go\b|\bwrapped (this |it )?up\b|\ball set\b|(change|work|it|everything|this) is in place\b|has been completed\b|\bshipped (it|this|the (fix|change|feature|update))\b)'
echo "$LAST" | grep -qiE "$CLAIM" || exit 0

# --- Evidence stage 1: shape check. Vacuous markers from the original version ("$ ",
# bare "screenshot", "git status shows") are gone — every accepted shape is verifiable.
SHAPE_COUNT='[0-9]+ (tests? )?(pass|passed|passing)'
SHAPE_EXIT='exit code [0-9]'
SHAPE_CITE='[A-Za-z0-9_./~-]+\.[A-Za-z]{1,5}:[0-9]+'
SHAPE_ARTIFACT='(~|/|[A-Za-z0-9_-]+/)[A-Za-z0-9._/-]*\.(png|md|log|txt|json|html|jsonl)'
SHAPE_COMMIT='(commit|ReviewCommit:?) ?[0-9a-f]{7,40}'
if ! echo "$LAST" | grep -qiE "$SHAPE_COUNT|$SHAPE_EXIT|$SHAPE_CITE|$SHAPE_COMMIT" \
   && ! echo "$LAST" | grep -qiE "$SHAPE_ARTIFACT"; then
  block "Completion claimed without evidence in the final message (completion-claim-guard, audit 2026-07-03: 46 unverified-claim incidents/6mo). Include at least one of: the verifying command output (exit code / N passed), a file:line citation, an artifact path, or a commit SHA — or rephrase the claim as unverified."
fi

# --- Evidence stage 2: verify the shapes (adversarial finding F1: the oracle must check
# the FACT, not the claim text).

# (a) Cited artifact paths must exist. A cited-but-missing artifact is fabricated evidence.
while IFS= read -r tok; do
  [[ -z "$tok" ]] && continue
  rp="$(resolve_path "$tok")"
  if [[ -n "$rp" && ! -e "$rp" ]]; then
    block "Fabricated evidence (completion-claim-guard): the final message cites artifact '$tok' but nothing exists at $rp. Produce the artifact, cite the real path, or state the claim as unverified."
  fi
done < <(echo "$LAST" | grep -oiE "$SHAPE_ARTIFACT" | head -10)

# (b) Claimed test counts must appear in a non-assistant transcript line (i.e. in actual
# tool output, not only in the model's own prose anywhere in the session).
while IFS= read -r cnt; do
  [[ -z "$cnt" ]] && continue
  n=$(echo "$cnt" | grep -oE '^[0-9]+')
  # Tool-output line formats vary ("84 passed", "Tests: 84 passed") — require the count
  # and the word passed/passing on the same non-assistant line, not an exact phrase.
  if ! grep -iE "pass(ed|ing)" "$TRANSCRIPT" 2>/dev/null | grep -v '"type":"assistant"' | grep -qE "(^|[^0-9])$n([^0-9]|$)"; then
    block "Unverified test count (completion-claim-guard): the final message claims '$cnt' but no tool output in this session contains that count. Run the tests and cite their real output, or state the claim as unverified."
  fi
done < <(echo "$LAST" | grep -oiE "$SHAPE_COUNT" | head -5)

# (c) file:line citations pointing at slash-containing paths must exist on disk.
while IFS= read -r cite; do
  [[ -z "$cite" ]] && continue
  f="${cite%:*}"
  [[ "$f" != */* ]] && continue
  rp="$(resolve_path "$f")"
  if [[ -n "$rp" && ! -e "$rp" ]]; then
    block "Fabricated citation (completion-claim-guard): the final message cites '$cite' but $rp does not exist. Cite a real file:line or state the claim as unverified."
  fi
done < <(echo "$LAST" | grep -oE "$SHAPE_CITE" | head -10)

# (d) "exit code N" evidence must appear in a non-assistant transcript line (tool output).
# Pure prose "exit code 0" with no backing tool output is unverified. This closes the
# REV-C mutation gap: altering SHAPE_EXIT broke no test because exit-code evidence was
# never exercised by any prior test.
while IFS= read -r ex; do
  [[ -z "$ex" ]] && continue
  # Extract the code number; look for it adjacent to "exit" on a non-assistant line.
  code=$(echo "$ex" | grep -oE '[0-9]+$')
  if ! grep -v '"type":"assistant"' "$TRANSCRIPT" 2>/dev/null \
       | grep -qiE "exit[[:space:]](code[[:space:]])?$code"; then
    block "Unverified exit-code evidence (completion-claim-guard): the final message claims '$ex' but no tool output in this session records that exit code. Run the command and include its real output, or state the claim as unverified."
  fi
done < <(echo "$LAST" | grep -oiE "$SHAPE_EXIT" | head -5)

# (e) Commit SHA evidence must appear in a non-assistant transcript line (tool output, e.g.
# from a git command). Prose-only commit SHAs are unverified. Closes the second REV-C
# mutation gap (same category as exit-code: shape check with no stage-2 verifier).
while IFS= read -r sha_tok; do
  [[ -z "$sha_tok" ]] && continue
  # Extract the hex SHA portion (≥7 chars).
  sha=$(echo "$sha_tok" | grep -oE '[0-9a-f]{7,40}')
  [[ -z "$sha" ]] && continue
  if ! grep -v '"type":"assistant"' "$TRANSCRIPT" 2>/dev/null \
       | grep -qiE "$sha"; then
    block "Unverified commit evidence (completion-claim-guard): the final message cites commit '$sha' but no tool output in this session contains that SHA. Run the git command and include its real output, or state the claim as unverified."
  fi
done < <(echo "$LAST" | grep -oiE "$SHAPE_COMMIT" | head -5)

# --- Stage 3: Ledger reconciliation (Pillar II.2) -----------------------------------
# Cross-checks claimed test-run counts against events.ndjson (the evidence spine, written
# by evidence-ledger.sh PostToolUse). A claim of "N passed" must have a trust_decision
# test-run event with matching passed count in the CURRENT session.
#
# CONSTRAINTS (non-negotiable):
# (a) Never weaker than today: Stages 1+2 already passed at this point — Stage 3 is
#     strictly additive and can only add a block, never remove one.
# (b) If the session has ZERO ledger events (ledger not yet wired), Stage 3 passes
#     through silently — no block. This avoids false-blocking every session today.
# (c) Fail-open on all internal errors (jq absent, file missing, malformed line, etc.).
# (d) BSD-safe: uses grep/jq only; reads NDJSON directly (no harness CLI).
# (e) Reads BOTH candidate spine paths: global first, then $STATE-local.
# (f) HARNESS_STATE_OVERRIDE env overrides both paths (used by tests).
# (g) Session ID comes from the hook INPUT (falls back to "unknown" which means
#     no session filtering → ledger check is skipped if session is unknown).

_s3_block=0
_s3_skip=0

# Only run Stage 3 if jq is available (already checked at top, but be explicit).
if ! command -v jq >/dev/null 2>&1; then
  _s3_skip=1
fi

# Resolve session ID from INPUT (the hook's stdin JSON).
S3_SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // empty' 2>/dev/null) || S3_SESSION_ID=""
# If session_id is unknown/empty, skip Stage 3 entirely (no session → no filter → no signal).
if [[ -z "$S3_SESSION_ID" || "$S3_SESSION_ID" == "unknown" ]]; then
  _s3_skip=1
fi

if [[ "$_s3_skip" -eq 0 ]]; then
  # Resolve spine file paths: HARNESS_STATE_OVERRIDE takes precedence (test injection);
  # otherwise read the global spine first, then the project-local spine, and merge.
  # We collect all matching lines into a single combined search target.
  S3_GLOBAL_SPINE="${HOME}/.claude/state/state/events.ndjson"
  # Project-local: resolve via git toplevel (same logic as emit-event.sh).
  S3_LOCAL_TOPLEVEL="$(git rev-parse --show-toplevel 2>/dev/null)" || S3_LOCAL_TOPLEVEL=""
  if [[ -n "${S3_LOCAL_TOPLEVEL:-}" ]]; then
    S3_LOCAL_SPINE="${S3_LOCAL_TOPLEVEL}/.agents/claude-governance/state/events.ndjson"
  else
    S3_LOCAL_SPINE=""
  fi

  # HARNESS_STATE_OVERRIDE: point at a specific state dir (tests inject this).
  if [[ -n "${HARNESS_STATE_OVERRIDE:-}" ]]; then
    S3_GLOBAL_SPINE="${HARNESS_STATE_OVERRIDE}/state/events.ndjson"
    S3_LOCAL_SPINE=""  # tests use a single override dir; don't also read global
  fi

  # Collect all ledger lines for this session from available spines.
  # Fail-open: if grep fails (file missing), _S3_SESSION_LINES stays empty.
  _S3_SESSION_LINES=""
  for _spine in "$S3_GLOBAL_SPINE" "$S3_LOCAL_SPINE"; do
    [[ -z "$_spine" || ! -f "$_spine" ]] && continue
    _chunk=$(grep -F "\"$S3_SESSION_ID\"" "$_spine" 2>/dev/null) || _chunk=""
    [[ -n "$_chunk" ]] && _S3_SESSION_LINES="${_S3_SESSION_LINES}${_chunk}"$'\n'
  done

  # CONSTRAINT (b): if NO ledger events exist for this session, Stage 3 passes through.
  # Count only lines that are valid JSON (malformed lines are simply ignored — fail-open).
  _S3_VALID_EVENT_COUNT=0
  while IFS= read -r _ev_line; do
    [[ -z "$_ev_line" ]] && continue
    _ev_parsed=$(echo "$_ev_line" | jq -e '.event_type' 2>/dev/null) || continue
    _S3_VALID_EVENT_COUNT=$(( _S3_VALID_EVENT_COUNT + 1 ))
  done < <(printf '%s\n' "$_S3_SESSION_LINES")

  if [[ "$_S3_VALID_EVENT_COUNT" -eq 0 ]]; then
    # No ledger events for this session → ledger is unwired; pass through silently.
    _s3_skip=1
  fi
fi

# Stage 3 reconciliation: for each claimed test count, require a matching ledger token.
# Only fires when _s3_skip=0 (ledger is present and has events for this session).
if [[ "$_s3_skip" -eq 0 ]]; then
  while IFS= read -r cnt; do
    [[ -z "$cnt" ]] && continue
    # Extract the numeric count from the claim (e.g. "21 passed" → "21").
    claimed_n=$(echo "$cnt" | grep -oE '^[0-9]+')
    [[ -z "$claimed_n" ]] && continue

    # Look for a trust_decision test-run event with matching passed count in this session.
    # Evidence: evidence_ref format is "<N>passed@<sha16>"; also check payload.passed field.
    # Fail-open: if jq parse fails on a line, skip that line and continue.
    _found_token=0
    while IFS= read -r _ev_line; do
      [[ -z "$_ev_line" ]] && continue
      # Fail-open: skip malformed lines.
      _ev_type=$(echo "$_ev_line" | jq -re '.event_type' 2>/dev/null) || continue
      [[ "$_ev_type" != "trust_decision" ]] && continue
      _ev_claim=$(echo "$_ev_line" | jq -re '.payload.claim // empty' 2>/dev/null) || continue
      [[ "$_ev_claim" != "test_count" ]] && continue
      # Match by payload.passed field.
      _ev_passed=$(echo "$_ev_line" | jq -re '.payload.passed // empty' 2>/dev/null) || _ev_passed=""
      if [[ "$_ev_passed" == "$claimed_n" ]]; then
        _found_token=1
        break
      fi
      # Also match by evidence_ref prefix: "<N>passed@...".
      _ev_eref=$(echo "$_ev_line" | jq -re '.evidence_ref // empty' 2>/dev/null) || _ev_eref=""
      if [[ "$_ev_eref" == "${claimed_n}passed@"* ]]; then
        _found_token=1
        break
      fi
    done < <(printf '%s\n' "$_S3_SESSION_LINES")

    if [[ "$_found_token" -eq 0 ]]; then
      block "Ledger mismatch (completion-claim-guard Stage 3, Pillar II.2): the final message claims '$cnt' but no test-run ledger event in this session recorded a passed count of $claimed_n. The evidence spine only shows: $(printf '%s\n' "$_S3_SESSION_LINES" | jq -r 'select(.event_type=="trust_decision" and .payload.claim=="test_count") | .payload.passed' 2>/dev/null | tr '\n' ',' | sed 's/,$//') passed. Run the tests and cite their real output, or state the claim as unverified."
    fi
  done < <(echo "$LAST" | grep -oiE "$SHAPE_COUNT" | head -5)
fi

# --- Stage 4 (C3): Citation gate for numeric claims (Phase 4.2, item 20) ---------
# Purpose: detect/block numeric result claims ("handles 500 req/sec", "latency dropped to
#   80ms") presented as measured results.
#
# Block-vs-detect rule (FIX-C3-1 + FIX-C3-2, adversarial review 2026-07-05):
#   CITED+VERIFIED   — number present in a non-assistant transcript line → pass (no event).
#   PERCENTAGE ("N%") — bare percentage claims are DETECT-only, NEVER block.
#                       "100% done", "cut scope by 30%", "100% of the suite passes" are
#                       idiomatic completion rhetoric that regex cannot distinguish from a
#                       measured result.  Reserving BLOCK for percentages would produce
#                       too many user-facing false positives.  These always emit a
#                       would_block event (shadow observation) but never gate the Stop.
#   CITED+UNVERIFIED — a concrete-unit number (ms, x, req/s, ops, etc.) NOT in any
#                      non-assistant line AND whose citation shape is NEAR the numeric
#                      token (within ~80 chars) → DETECT always; BLOCK when sentinel live.
#                      "Near" means: the citation shape appears in the same sentence or
#                      within 80 chars of the matched number's position in the message.
#   UNCITED PROSE    — concrete-unit number with no citation shape nearby → DETECT only,
#                      never block (avoids false-positive hell on innocent summaries).
#
# Sentinel ~/.claude/state/.citation-gate-live enables the BLOCK path after shadow observation.
# Fail-open: any parse error, missing transcript, or malformed regex → exit 0 silently.
#
# Numeric regex design: match result-magnitude expressions that look like measured outcomes.
#   Matches (blockable): "500 req/sec", "80ms", "12 errors/min", "3.2x faster".
#   Matches (detect-only/percentage): "46%", "30%", "100%", "reduced by 30%".
#   Excludes (hard-excluded by the regex):
#     • Versions: v2.1.0 / 1.2.3 style (dotted triplets)
#     • Dates: YYYY-MM-DD and YYYY/MM/DD
#     • Times: HH:MM:SS
#     • file:line: path/file.ext:NNN (already handled by SHAPE_CITE above)
#     • Issue/PR refs: #NNN
#     • Bare integers < 10 (too common as ordinals/counts; too many innocent hits)
#     • Integers in parentheses like (7) or [5] (footnotes / list markers)
#   Pattern explanation:
#     (?<![/#:.]) — not preceded by /, #, :, . (eliminates dates, file:line, PR refs, versions)
#     \b[0-9]{2,}(\.[0-9]+)?\s*(%|x\b|ms\b|s\b|req|err|ops|rps|qps|k\b|M\b|G\b)
#       OR
#     (improved|reduced|dropped|increased|cut|faster|slower|higher|lower|up|down)\s+
#       (by\s+)?[0-9]{2,}
#
# Note: grep -P (PCRE) used for negative lookbehind. Perl5-compatible. Falls back to
#   plain ERE (no lookbehind) if -P is not available — slightly higher false-positive rate
#   but still safe and fail-open.

_C3_SENTINEL="$HOME/.claude/state/.citation-gate-live"
_C3_BLOCK_LIVE=false
[[ -f "$_C3_SENTINEL" ]] && _C3_BLOCK_LIVE=true

# Numeric result pattern — PCRE preferred (negative lookbehind for false-positive exclusion).
# Captures: percentage, multiplier, duration (ms/s), throughput (req/s, ops, rps etc.),
#   magnitude improvements ("reduced by 30", "latency dropped to 80").
_C3_PATTERN='(?<![/#:._v])\b([0-9]{2,}(\.[0-9]+)?\s*(%|x\b|ms\b|\bs\b|req|err|ops|rps|qps|k\b|M\b|G\b)|(improved|reduced|dropped|increased|cut|faster|slower|higher|lower|scaled)\s+(by\s+|to\s+)?[0-9]{2,})'

# Test if grep -P is available (macOS ships with BSD grep which may lack -P).
_C3_GREP_P=false
echo "" | grep -P '' >/dev/null 2>&1 && _C3_GREP_P=true

# Extract numeric result claims from the final assistant message.
# Cap at 5 to bound events and processing time.
_c3_extract_claims() {
  if [[ "$_C3_GREP_P" == "true" ]]; then
    echo "$LAST" | grep -oP "$_C3_PATTERN" 2>/dev/null | head -5
  else
    # ERE fallback: slightly broader match (no lookbehind)
    echo "$LAST" | grep -oE '[0-9]{2,}(\.[0-9]+)?\s*(%%|x |ms |req|ops|rps|%)|((improved|reduced|dropped|increased|cut|faster|slower)\s+(by\s+|to\s+)?[0-9]{2,})' 2>/dev/null | head -5
  fi
}

# FIX-C3-2: classify a matched token as a bare percentage (rhetoric class).
# Purpose: distinguish "100% done" / "30%" rhetoric from concrete-unit claims.
# Usage: _c3_is_percentage_only "$tok" "$num" "$full_message"
#   Returns 0 (true/rhetoric) if the token is a bare percentage with no other concrete unit.
# Gotchas: "3.2x" and "80ms" are NOT percentages; "30%" and "100%" ARE.
#   Verb-improvement forms like "reduced by 30" look unitless in the token alone, but
#   the original message may have "dropped to 80ms" where "ms" follows the number — we
#   check the full message for num+unit to avoid false-rhetoric classification.
_c3_is_percentage_only() {
  local tok="$1" num="${2:-}" msg="${3:-}"
  # Ends with optional-spaces + % → bare percentage, always rhetoric
  if echo "$tok" | grep -qE '%\s*$' 2>/dev/null; then
    return 0  # bare percentage token
  fi
  # Verb-improvement forms ("reduced by 30", "dropped to 80") have no unit in the token.
  # But if the original message contains num+unit (e.g. "80ms"), it IS a concrete claim.
  if echo "$tok" | grep -qiE '^(improved|reduced|dropped|increased|cut|faster|slower|higher|lower|scaled)\s' 2>/dev/null; then
    # Check if the numeric value is followed by a concrete unit in the original message.
    if [[ -n "$num" && -n "$msg" ]] && \
       echo "$msg" | grep -qiE "\b${num}\s*(ms|x\b|req|ops|rps|qps|err|\bs\b|k\b|M\b|G\b)" 2>/dev/null; then
      return 1  # verb-improvement but num has a concrete unit in context → blockable
    fi
    # No unit found in context → treat as rhetoric
    return 0
  fi
  return 1  # concrete-unit numeric (ms, x, req/s, etc.) → eligible for block
}

# FIX-C3-1: check if a citation shape is NEAR the matched number in the message.
# Purpose: avoid classifying a number as "cited" just because the message contains any
#   file path anywhere.  The citation must be in the same sentence or within ~80 chars.
# Usage: _c3_citation_near "$LAST" "$numeric_value"
#   Returns 0 (true) if a citation shape is found within 80 chars of the number.
# Gotchas: uses python3 for offset search; falls back to whole-message grep (fail-open)
#   if python3 is unavailable.  A false-open result (treating far citation as near) is
#   safer than false-blocking (treating near citation as absent).
_c3_citation_near() {
  local msg="$1" num="$2"
  # Fast path: if no citation shape in the whole message, skip the proximity check.
  if ! echo "$msg" | grep -qiE "$SHAPE_CITE|$SHAPE_ARTIFACT" 2>/dev/null; then
    return 1  # no citation anywhere → not near
  fi
  # Proximity check via python3 (available on all supported hosts).
  if command -v python3 >/dev/null 2>&1; then
    python3 - <<PYEOF 2>/dev/null
import re, sys
msg = """$msg"""
num = "$num"
# Find all positions of the numeric value in the message.
num_pat = re.compile(r'(?<![0-9.])' + re.escape(num) + r'(?![0-9.])')
cite_pat = re.compile(
    r'[A-Za-z0-9_./~-]+\.[A-Za-z]{1,5}:[0-9]+'     # file:line
    r'|(~|/|[A-Za-z0-9_-]+/)[A-Za-z0-9._/-]*\.(png|md|log|txt|json|html|jsonl)',  # artifact path
    re.IGNORECASE
)
WINDOW = 80
for nm in num_pat.finditer(msg):
    ns, ne = nm.start(), nm.end()
    lo = max(0, ns - WINDOW)
    hi = min(len(msg), ne + WINDOW)
    if cite_pat.search(msg[lo:hi]):
        sys.exit(0)  # citation found near the number
sys.exit(1)          # no citation within window
PYEOF
    return $?
  fi
  # Fallback: python3 absent → treat whole-message citation as near (fail-open).
  return 0
}

# Run Stage 4 only if the final message contains at least one completion claim.
# (The CLAIM grep already ran above and we'd have exited if no claim — so we're past that gate.)
# Only scan for numeric claims if the CLAIM regex was already matched (we're still running).

_c3_has_claim=false
while IFS= read -r _c3_tok; do
  [[ -z "$_c3_tok" ]] && continue
  _c3_has_claim=true

  # Step 1: Is the number present in a non-assistant transcript line (verified)?
  # Extract the first numeric value from the token — it may be anywhere (e.g. "dropped to 80").
  # Use || true so pipefail from a no-match grep does not fire the ERR trap.
  _c3_num=$(echo "$_c3_tok" | grep -oE '[0-9]+(\.[0-9]+)?' | head -1) || true
  if [[ -n "$_c3_num" ]]; then
    if grep -v '"type":"assistant"' "$TRANSCRIPT" 2>/dev/null \
       | grep -qE "(^|[^0-9.])$_c3_num([^0-9.]|$)"; then
      # Number is present in tool output → verified; no event, no block.
      continue
    fi
  fi

  # Step 2: Number NOT in tool output.
  # FIX-C3-2: percentage-only tokens are DETECT-only, never block.
  if _c3_is_percentage_only "$_c3_tok" "${_c3_num:-}" "$LAST"; then
    # PERCENTAGE RHETORIC — DETECT always; NEVER block (even when sentinel live).
    emit_event "trust_decision" \
      '{"guard":"citation-gate","claim_type":"numeric","class":"C3","subclass":"percentage-rhetoric"}' \
      outcome="would_block" source="completion-claim-guard.sh" || true
    # Do NOT block: percentage rhetoric is detect-only, per block-vs-detect rule.
    continue
  fi

  # FIX-C3-1: check if a citation shape is NEAR the numeric token (within ~80 chars).
  if _c3_citation_near "$LAST" "${_c3_num:-$_c3_tok}"; then
    # CITED (near) but unverifiable — DETECT always; BLOCK when sentinel live.
    emit_event "trust_decision" \
      '{"guard":"citation-gate","claim_type":"numeric","class":"C3","subclass":"cited-unverified"}' \
      outcome="would_block" source="completion-claim-guard.sh" || true

    if [[ "$_C3_BLOCK_LIVE" == "true" ]]; then
      block "Unverified numeric claim (completion-claim-guard, citation-gate C3): the final message cites a numeric result ('$_c3_tok') alongside an artifact/file citation, but the number does not appear in any tool output in this session. Cite the real tool output that produced this number, or state the claim as unverified."
    fi
  else
    # UNCITED PROSE (or citation too far) — DETECT only, never block (per coverage matrix).
    emit_event "trust_decision" \
      '{"guard":"citation-gate","claim_type":"numeric","class":"C3","subclass":"uncited-prose"}' \
      outcome="would_block" source="completion-claim-guard.sh" || true
    # Do NOT block: uncited prose is PROSE-class, no hard gate.
  fi
done < <(_c3_extract_claims)

# trust_decision emit on allow — purely additive; fired only when all checks pass.
emit_event "trust_decision" '{"guard":"completion-claim-guard","claim_type":"completion"}' \
  outcome="allowed" source="completion-claim-guard.sh" || true
exit 0
