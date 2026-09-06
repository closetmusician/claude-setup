#!/usr/bin/env bash
# ABOUTME: PreToolUse(Write|Edit|Bash) hook: QA/verification artifacts must be authored by
# ABOUTME: subagents, not the orchestrator main thread. Audit 2026-07-03: 100% of 188 cycle
# ABOUTME: files were orchestrator-written — QA theater. Hardened per adversarial review
# ABOUTME: (docs/temp/adv-review-0703): also guards Bash writes (heredoc/redirect bypass),
# ABOUTME: ready-for-review/verification/review-findings families and name variants, and
# ABOUTME: denies mid-run deletion of governance state (cleanup is a SessionEnd hook).
# ABOUTME: II.3 extension: manifest_role_check enforces role-level provenance via first-write-wins
# ABOUTME: claim in run-manifest.json — a coder can no longer write a qa-tester's artifacts.
# ABOUTME: Sentinel-gated like its governance siblings; fail-open on any error.

set -uo pipefail
trap 'exit 0' ERR

command -v jq >/dev/null 2>&1 || exit 0

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/project-root.sh"
# Pillar I emit — purely additive; fail-open via emit_event design + || true guard.
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/../lib/emit-event.sh" 2>/dev/null || true

# Only active during governed orchestration runs.
[[ ! -f "$(get_governance_state_dir)/.active" ]] && exit 0

INPUT=$(cat)

TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // empty')
AGENT_ID=$(echo "$INPUT" | jq -r '.agent_id // .agentId // empty')

# Governance state dir (resolved once for this invocation).
STATE=$(get_governance_state_dir)

deny() {
  # trust_decision emit on deny — purely additive; before deny JSON output.
  emit_event "trust_decision" '{"guard":"qa-artifact-ownership-guard","claim_type":"artifact_write"}' \
    outcome="denied" source="qa-artifact-ownership-guard.sh" || true
  jq -cn --arg r "$1" \
    '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":$r}}'
  # Probe log (finding F10): if agent_id is ever renamed/absent in this build, denials of
  # legitimate subagent writes are diagnosable from the recorded payload keys.
  printf '%s deny tool=%s agent_id=%s keys=%s\n' \
    "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$TOOL_NAME" "${AGENT_ID:-none}" \
    "$(echo "$INPUT" | jq -r 'keys | join(",")' 2>/dev/null)" \
    >> "$HOME/.claude/state/qa-artifact-ownership-guard.log" 2>/dev/null || true
  exit 0
}

mkdir -p "$HOME/.claude/state" 2>/dev/null || true

# Artifact families the main thread must never author (R10/R11/R14): QA cycles,
# acceptance tests, ready-for-review, review findings, verification reports.
# Loose globs on purpose — name variants (cycle1, QA-001-…) were a bypass (finding B7).
# BUG-ADV2-02 fix: match is case-insensitive — lowercase the path before matching so
# qa/CYCLE-1.md is treated identically to qa/cycle-1.md on macOS case-insensitive FS.
is_guarded_artifact() {
  local lower
  lower=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')
  case "$lower" in
    *qa/*cycle*.md|*qa/*acceptance*.md|*qa/*ready-for-review*.md|*qa/*review-findings*.md|*verification.md)
      return 0 ;;
  esac
  return 1
}

# ── II.3: Role-Provenance Manifest helpers ─────────────────────────────────────
# Purpose: enforce that each governed role's artifacts can only be authored by the agent
#   that first claimed the role (first-write-wins). Fail-open on every error path.
# Design: docs/plans/harness/fable/evidence/II-3-provenance-design.md §3.

# derive_globs ROLE TASK → newline-separated glob patterns for this role's artifacts.
# Must match §3.3 of the design — NOT read from the prompt (D4).
_derive_globs() {
  local role="$1" task="$2"
  case "$role" in
    qa-test-writer) printf '*%s-acceptance-tests.md\n' "$task" ;;
    coder)          printf '*%s-ready-for-review.md\n' "$task" ;;
    qa-tester)      printf '*%s-cycle-*.md\n' "$task" ;;
    verifier)       printf '*verification.md\n*%s-verification.md\n' "$task" ;;
    architect)      printf '*%s-arch.md\n' "$task" ;;
  esac
}

# project_relative FILE_PATH → project-relative path for glob matching.
# BSD-safe: strips project root prefix when absolute; returns raw fp on error (fail-open).
_project_relative() {
  local fp="$1"
  local root
  root=$(get_project_root 2>/dev/null) || root=""
  if [[ -n "$root" && "$fp" == "$root"* ]]; then
    printf '%s' "${fp#"$root"/}"
  else
    printf '%s' "$fp"
  fi
}

# _glob_matches PATTERN STRING → 0 if string matches the suffix-anchored pattern, 1 otherwise.
# Patterns from derive_globs are near-literal with at most trailing * or *-cycle-*.
# Uses bash case for glob matching (POSIX-compatible, no subshell).
_glob_matches() {
  local pattern="$1" str="$2"
  case "$str" in
    $pattern) return 0 ;;
  esac
  return 1
}

# claim_binding ENTRY_INDEX AID — atomically set agent_id+bound_ts on the matched entry.
# Uses tmp+mv (D9) so a concurrent guard claim + binder append won't tear the manifest.
_claim_binding() {
  local idx="$1" aid="$2"
  local manifest="$STATE/run-manifest.json"
  local ts; ts=$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo "1970-01-01T00:00:00Z")
  local tmp="$STATE/run-manifest.json.tmp.$$"
  jq --argjson i "$idx" --arg aid "$aid" --arg ts "$ts" \
    '.tasks[$i].agent_id = $aid | .tasks[$i].bound_ts = $ts' \
    "$manifest" > "$tmp" && mv -f "$tmp" "$manifest" || true
  emit_event "trust_decision" \
    "{\"guard\":\"qa-artifact-ownership-guard\",\"claim_type\":\"role_claim\",\"entry_idx\":$idx}" \
    outcome="claimed" source="qa-artifact-ownership-guard.sh" || true
}

# manifest_role_check FILE_PATH AGENT_ID
# Returns: 0=allow-early, 1=deny (caller calls deny), exits inline for allow paths.
# Fail-open on every error: missing manifest, bad schema, jq error → return 0 (today's behavior).
_manifest_role_check() {
  local fp="$1" aid="$2"
  local manifest="$STATE/run-manifest.json"

  # FAIL-OPEN: no manifest → today's behavior (allow subagent)
  [[ -f "$manifest" ]] || return 0

  # FAIL-OPEN: schema != 1 → forward-compat safety
  local schema; schema=$(jq -r '.schema // 0' "$manifest" 2>/dev/null)
  [[ "$schema" == "1" ]] || return 0

  # Normalize to project-relative path for glob matching.
  local rel; rel=$(_project_relative "$fp")

  # Find the first manifest entry whose artifact_globs matches rel.
  # Iterate over entries — jq array iteration is the cleanest BSD-safe approach.
  local entry_count; entry_count=$(jq '.tasks | length' "$manifest" 2>/dev/null || echo 0)
  local i bound entry_role entry_task
  for ((i=0; i<entry_count; i++)); do
    local globs_len; globs_len=$(jq --argjson i "$i" '.tasks[$i].artifact_globs | length' "$manifest" 2>/dev/null || echo 0)
    local j
    for ((j=0; j<globs_len; j++)); do
      local glob_pat; glob_pat=$(jq -r --argjson i "$i" --argjson j "$j" '.tasks[$i].artifact_globs[$j]' "$manifest" 2>/dev/null)
      [[ -z "$glob_pat" || "$glob_pat" == "null" ]] && continue
      if _glob_matches "$glob_pat" "$rel"; then
        # Found a matching entry at index i.
        bound=$(jq -r --argjson i "$i" '.tasks[$i].agent_id // empty' "$manifest" 2>/dev/null)
        if [[ -z "$bound" ]]; then
          # Unclaimed: first-write-wins claim. Allow.
          _claim_binding "$i" "$aid"
          return 0
        fi
        if [[ "$bound" == "$aid" ]]; then
          # Right agent. Allow.
          return 0
        fi
        # Wrong agent — DENY. Build message from manifest entry.
        entry_role=$(jq -r --argjson i "$i" '.tasks[$i].role // "unknown"' "$manifest" 2>/dev/null)
        WRONG_ROLE_MSG="This QA artifact (${fp}) is bound to ${entry_role}/${bound} in run-manifest.json, but the writer is ${aid}. A subagent may not write another role's QA artifact — that is how a coder's test gets miscounted as QA evidence (R10). Route the write through the spawned ${entry_role} agent, or if this is a legitimate re-spawn, have the orchestrator clear the stale binding with: manifest-rebind.sh ${entry_task:-?} ${entry_role}."
        return 1
      fi
    done
  done

  # Path not bound to any role → allow (no regression, D8 fail-open).
  return 0
}

if [[ "$TOOL_NAME" == "Bash" ]]; then
  CMD=$(echo "$INPUT" | jq -r '.tool_input.command // empty')
  [[ -z "$CMD" ]] && exit 0

  # Sentinel protection (bypass B2): mid-run deletion of the governance master sentinel
  # or state dir is never legitimate — activation is a PostToolUse Skill hook, cleanup is
  # a SessionEnd hook. Applies to subagents too. Workflow sentinels (.gate-*) are exempt:
  # the orchestrator manages those per protocol (vibe-protocol §4.1 steps 2a/3a).
  # (Residual: arbitrary Bash can delete files indirectly; this catches the direct class,
  # harness-doctor audits the rest.)
  if echo "$CMD" | grep -qE '\brm\b|\bunlink\b|\bshred\b|[[:space:]]-delete\b' \
     && echo "$CMD" | grep -q 'claude-governance' \
     && ! echo "$CMD" | grep -qE 'claude-governance/\.gate'; then
    deny "Governance state is hook-managed (activated by activate-on-orchestrator.sh, cleaned by governance-cleanup.sh at SessionEnd). Deleting sentinels mid-run disables every governance guard at once — that is not cleanup, it is gate removal. If governance is misfiring, stop and tell the user."
  fi

  # II.3: subagent Bash role check — extract any guarded-artifact token from the command
  # and run manifest_role_check for Bash-branch parity (§3.5 design). If no guarded token
  # is found, fall through to today's behavior (exit 0 for subagents, deny for main thread).
  if [[ -n "$AGENT_ID" ]]; then
    # Extract first guarded-artifact path token from the command for role-provenance check.
    # Use a double-quoted heredoc-safe regex (avoids single-quote embedding issues).
    # BSD grep -oE: extract the matching substring. Guarded families: cycle, acceptance,
    # ready-for-review, review-findings (same families as is_guarded_artifact above).
    BASH_GUARDED_PATH=$(printf '%s' "$CMD" | \
      grep -oiE "qa/[^[:space:];|>&]*(cycle|acceptance|ready-for-review|review-findings)[^[:space:];|>&]*\.md" \
      | head -1)
    if [[ -n "$BASH_GUARDED_PATH" ]]; then
      rc=0
      _manifest_role_check "$BASH_GUARDED_PATH" "$AGENT_ID" || rc=$?
      if [[ $rc -eq 1 ]]; then
        _deny_msg="${WRONG_ROLE_MSG:-This QA artifact is bound to a different role in run-manifest.json. Wrong-role write denied (R10).}"
        deny "$_deny_msg"
      fi
    fi
    exit 0
  fi

  # Heredoc/redirect/copy bypass (finding F3): shell writes into guarded artifact paths.
  # BUG-ADV2-03 fix: added sed -i, dd of=, truncate -s, rsync … (common file-write commands
  # that were absent from the original verb enumeration).  The sed/dd patterns anchor on the
  # guarded path token directly, consistent with the redirect/tee/cp coverage already here.
  # BUG-ADV2-02: all qa/ path matchers use -i (case-insensitive) so CYCLE-1.md = cycle-1.md.
  if echo "$CMD" | grep -qiE '(>>?|\btee\b|\bcp\b|\bmv\b|\binstall\b)[^;&|]*qa/[^;&|]*(cycle|acceptance|ready-for-review|review-findings)[^;&|]*\.md' \
     || echo "$CMD" | grep -qiE '(>>?|\btee\b|\bcp\b|\bmv\b|\binstall\b)[^;&|]*verification\.md' \
     || echo "$CMD" | grep -qiE '\bsed\b[^;&|]*-i[^;&|]*(qa/[^;&|]*(cycle|acceptance|ready-for-review|review-findings)[^;&|]*\.md|verification\.md)' \
     || echo "$CMD" | grep -qiE '\bdd\b[^;&|]*of=(qa/[^;&|]*(cycle|acceptance|ready-for-review|review-findings)[^;&|]*\.md|verification\.md)' \
     || echo "$CMD" | grep -qiE '\btruncate\b[^;&|]*(qa/[^;&|]*(cycle|acceptance|ready-for-review|review-findings)[^;&|]*\.md|verification\.md)' \
     || echo "$CMD" | grep -qiE '\brsync\b[^;&|]*(qa/[^;&|]*(cycle|acceptance|ready-for-review|review-findings)[^;&|]*\.md|verification\.md)'; then
    deny "QA artifacts must be authored by the QA subagent, not the orchestrator (R10/R14) — writing them via shell redirection instead of the Write tool is the same violation. Audit 2026-07-03: 100% of cycle files were orchestrator-written. Spawn the subagent and have IT write this file."
  fi

  # Interpreter one-liner bypass (REV-C Hole 1): python/perl/ruby/node -c/-e whose
  # command string contains a guarded artifact path. 80/20 regex: flag is present AND
  # a guarded path pattern appears anywhere in the command string.
  if echo "$CMD" | grep -qE '\b(python3?|perl|ruby|node)\b.*-[ce]\b' \
     && { echo "$CMD" | grep -qiE 'qa/[^[:space:]"'"'"'\\]*(cycle|acceptance|ready-for-review|review-findings)[^[:space:]"'"'"'\\]*\.md' \
          || echo "$CMD" | grep -qiE 'verification\.md'; }; then
    deny "QA artifacts must be authored by the QA subagent, not the orchestrator (R10/R14) — interpreter one-liners that write guarded artifacts are the same violation. Audit 2026-07-03: 100% of cycle files were orchestrator-written. Spawn the subagent and have IT write this file."
  fi
  # trust_decision emit on Bash allow — purely additive.
  emit_event "trust_decision" '{"guard":"qa-artifact-ownership-guard","claim_type":"bash_write","path":"bash"}' \
    outcome="allowed" source="qa-artifact-ownership-guard.sh" || true
  exit 0
fi

# Write/Edit path.
# II.3: move FILE_PATH extraction above the agent early-out so manifest_role_check has the path.
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')
[[ -z "$FILE_PATH" ]] && exit 0

# II.3: subagent manifest role check replaces the simple "[[ -n AGENT_ID ]] && exit 0".
# If the manifest clears it (right agent, unclaimed, or no manifest) → allow early.
# If the manifest denies it (wrong agent) → deny with WRONG_ROLE_MSG.
if [[ -n "$AGENT_ID" ]]; then
  rc=0
  _manifest_role_check "$FILE_PATH" "$AGENT_ID" || rc=$?
  if [[ $rc -eq 0 ]]; then
    emit_event "trust_decision" '{"guard":"qa-artifact-ownership-guard","claim_type":"artifact_write","path":"write_edit"}' \
      outcome="allowed" source="qa-artifact-ownership-guard.sh" || true
    exit 0
  fi
  # rc == 1: wrong agent
  _deny_msg="${WRONG_ROLE_MSG:-This QA artifact is bound to a different role in run-manifest.json. Wrong-role write denied (R10).}"
  deny "$_deny_msg"
fi

if is_guarded_artifact "$FILE_PATH"; then
  deny "QA artifacts must be authored by the QA subagent, not the orchestrator (R10/R14). Audit 2026-07-03: 100% of cycle files were orchestrator-written — that is QA theater, not QA. Spawn the QA subagent and have IT write this file. If no QA subagent has run, the cycle has not happened."
fi

# Symlink bypass (REV-C Hole 2): if the literal path is a symlink, check the raw
# readlink target (works even for dangling symlinks). If the target exists and is
# resolvable with realpath, also check the fully-resolved canonical path. Both checks
# use is_guarded_artifact so multi-hop chains and dangling symlinks are both covered.
# BSD-safe (macOS bash 3.2). Fail-open: errors in resolution skip the check.
if [[ -L "$FILE_PATH" ]]; then
  RAW_TARGET=$(readlink "$FILE_PATH" 2>/dev/null | head -1)
  if [[ -n "$RAW_TARGET" ]] && is_guarded_artifact "$RAW_TARGET"; then
    deny "QA artifacts must be authored by the QA subagent, not the orchestrator (R10/R14). The path '${FILE_PATH}' is a symlink targeting a guarded QA artifact. Audit 2026-07-03: 100% of cycle files were orchestrator-written — that is QA theater, not QA. Spawn the QA subagent and have IT write this file."
  fi
  # Also check fully-resolved path when the target exists on disk.
  RESOLVED=$(realpath "$FILE_PATH" 2>/dev/null | head -1)
  if [[ -n "$RESOLVED" ]] && is_guarded_artifact "$RESOLVED"; then
    deny "QA artifacts must be authored by the QA subagent, not the orchestrator (R10/R14). The path '${FILE_PATH}' is a symlink resolving to a guarded QA artifact. Audit 2026-07-03: 100% of cycle files were orchestrator-written — that is QA theater, not QA. Spawn the QA subagent and have IT write this file."
  fi
fi

# trust_decision emit on Write/Edit allow — purely additive.
emit_event "trust_decision" '{"guard":"qa-artifact-ownership-guard","claim_type":"artifact_write","path":"write_edit"}' \
  outcome="allowed" source="qa-artifact-ownership-guard.sh" || true
exit 0
