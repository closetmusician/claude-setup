#!/usr/bin/env bash
# ABOUTME: PreToolUse(Task/Agent) hook: parses GOVERNANCE-ROLE marker from dispatch prompts,
# ABOUTME: writes $STATE/run-manifest.json bindings (agent_id:null initially). Sentinel-scoped:
# ABOUTME: inert without .active governance context. Fail-open on all error paths. Zero-LLM,
# ABOUTME: BSD-safe. Enables first-write-wins role provenance in qa-artifact-ownership-guard.sh.
# ABOUTME: Design: docs/plans/harness/fable/evidence/II-3-provenance-design.md §2.

set -uo pipefail
trap 'exit 0' ERR

command -v jq >/dev/null 2>&1 || exit 0

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/project-root.sh"
# Pillar I emit — purely additive; fail-open via emit_event design + || true guard.
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/../lib/emit-event.sh" 2>/dev/null || true

STATE=$(get_governance_state_dir)

# D1: inert outside governed runs — every governance script mirrors this.
[[ -f "$STATE/.active" ]] || exit 0

INPUT=$(cat)

# Only process Task or Agent tool spawns — other tools are a no-op.
TOOL=$(printf '%s' "$INPUT" | jq -r '.tool_name // empty')
[[ "$TOOL" == "Task" || "$TOOL" == "Agent" ]] || exit 0

# Extract the dispatch prompt; no prompt means nothing to parse.
PROMPT=$(printf '%s' "$INPUT" | jq -r '.tool_input.prompt // empty')
[[ -z "$PROMPT" ]] && exit 0

# D8: spawn without GOVERNANCE-ROLE marker → fail-open, do not bind.
MARKER=$(printf '%s\n' "$PROMPT" | grep -E '^GOVERNANCE-ROLE:' | head -1)
[[ -z "$MARKER" ]] && exit 0

# Extract role and task via sed — BSD grep -E + sed -E safe (no GNU extensions).
ROLE=$(printf '%s' "$MARKER" | sed -E 's/.*role=([a-z-]+).*/\1/')
TASK=$(printf '%s' "$MARKER" | sed -E 's/.*task=([A-Za-z0-9-]+).*/\1/')

# D6: closed role set — unknown role skips binding (typo guard).
case "$ROLE" in
  qa-test-writer|coder|qa-tester|verifier|architect) ;;
  *) exit 0 ;;
esac

[[ -z "$TASK" ]] && exit 0

# derive_globs ROLE TASK → space-separated list of artifact glob patterns for this role.
# These are deterministic suffix-anchored globs (§3.3 of design) — NOT prompt-supplied.
# D4: the orchestrator's prompt cannot widen a role's allowed paths.
derive_globs() {
  local role="$1" task="$2"
  case "$role" in
    qa-test-writer) printf '*%s-acceptance-tests.md\n' "$task" ;;
    coder)          printf '*%s-ready-for-review.md\n' "$task" ;;
    qa-tester)      printf '*%s-cycle-*.md\n' "$task" ;;
    verifier)       printf '*verification.md\n*%s-verification.md\n' "$task" ;;
    architect)      printf '*%s-arch.md\n' "$task" ;;
  esac
}

# _emit_ts is sourced from emit-event.sh; fallback if not available.
ts=$(_emit_ts 2>/dev/null) || ts=$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo "1970-01-01T00:00:00Z")

MANIFEST="$STATE/run-manifest.json"
TMP_MANIFEST="$STATE/run-manifest.json.tmp.$$"

# Build the artifact_globs JSON array for this role+task.
GLOBS_JSON=$(derive_globs "$ROLE" "$TASK" | jq -R -s 'split("\n") | map(select(length > 0))')

# Synthesize run_id from trace env vars or random hex (D9 schema field, non-load-bearing).
RUN_ID="${HERMES_TRACE_ID:-${TRACE_ID:-}}"
if [[ -z "$RUN_ID" ]]; then
  RUN_ID="t_$(openssl rand -hex 4 2>/dev/null || printf '%s%s' "$RANDOM" "$RANDOM")"
fi

if [[ ! -f "$MANIFEST" ]]; then
  # First governed spawn this run — create the manifest skeleton.
  jq -cn \
    --arg run_id "$RUN_ID" \
    --arg ts "$ts" \
    --arg task "$TASK" \
    --arg role "$ROLE" \
    --argjson globs "$GLOBS_JSON" \
    '{
       "schema": 1,
       "run_id": $run_id,
       "created_by": "manifest-bind.sh",
       "created_ts": $ts,
       "tasks": [{
         "task_id": $task,
         "role": $role,
         "artifact_globs": $globs,
         "agent_id": null,
         "bound_ts": null,
         "spawn_ts": $ts
       }]
     }' > "$TMP_MANIFEST" && mv -f "$TMP_MANIFEST" "$MANIFEST" || exit 0
else
  # D5 dedup: if a (task_id, role) entry already exists, only refresh spawn_ts (idempotent).
  # Use jq -r to get plain boolean string; -e exit code alone isn't reliable in $(...)  chain.
  ALREADY=$(jq -r --arg t "$TASK" --arg r "$ROLE" \
    'any(.tasks[]; .task_id == $t and .role == $r)' "$MANIFEST" 2>/dev/null)

  if [[ "$ALREADY" == "true" ]]; then
    # Refresh spawn_ts on re-spawn (idempotent — does NOT reset agent_id/bound_ts claims).
    jq --arg t "$TASK" --arg r "$ROLE" --arg ts "$ts" \
      '(.tasks[] | select(.task_id == $t and .role == $r) | .spawn_ts) |= $ts' \
      "$MANIFEST" > "$TMP_MANIFEST" && mv -f "$TMP_MANIFEST" "$MANIFEST" || exit 0
  else
    # Append a new entry for this (task, role) pair.
    jq --arg task "$TASK" --arg role "$ROLE" --arg ts "$ts" --argjson globs "$GLOBS_JSON" \
      '.tasks += [{
         "task_id": $task,
         "role": $role,
         "artifact_globs": $globs,
         "agent_id": null,
         "bound_ts": null,
         "spawn_ts": $ts
       }]' \
      "$MANIFEST" > "$TMP_MANIFEST" && mv -f "$TMP_MANIFEST" "$MANIFEST" || exit 0
  fi
fi

# Emit agent_spawn event (additive, fail-open per Pillar I contract).
emit_event "agent_spawn" \
  "{\"task_id\":\"$TASK\",\"role\":\"$ROLE\",\"binder\":\"manifest-bind\"}" \
  outcome="bound" source="manifest-bind.sh" || true

exit 0
