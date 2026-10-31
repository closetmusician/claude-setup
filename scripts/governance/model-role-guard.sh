#!/usr/bin/env bash
# ABOUTME: PreToolUse guard keeping Fable in its lane: master orchestration and
# ABOUTME: review/critique only, never hands-on work. Blocks Edit/Write/NotebookEdit
# ABOUTME: and mutating Bash in a Fable session outside the plan/spec/review allowlist,
# ABOUTME: and blocks any Agent/Task spawn that does not name a worker tier.
# ABOUTME: Fail mode: DENY on every resolved violation; allow-with-loud-stderr-warning
# ABOUTME: only when session identity cannot be resolved (a closed gate there would
# ABOUTME: brick every session before its first assistant turn is written to disk).

set -uo pipefail
trap 'exit 0' ERR

# Escape hatch 1 (session-wide kill switch) — an explicit mode signal, not identity.
[ "${HARNESS_MODEL_ROLE_GUARD:-1}" = "0" ] && exit 0

if ! command -v jq >/dev/null 2>&1; then
  echo "model-role-guard: jq not found — Fable role enforcement is NOT active" >&2
  exit 0
fi

INPUT="$(cat 2>/dev/null)" || INPUT=""
[ -z "$INPUT" ] && exit 0
printf '%s' "$INPUT" | jq -e . >/dev/null 2>&1 || exit 0

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/../lib/emit-event.sh" 2>/dev/null || emit_event() { return 0; }

TOOL="$(printf '%s' "$INPUT" | jq -r '.tool_name // empty')"
TRANSCRIPT="$(printf '%s' "$INPUT" | jq -r '.transcript_path // empty')"
AGENT_ID="$(printf '%s' "$INPUT" | jq -r '.agent_id // empty')"
TOOL_INPUT="$(printf '%s' "$INPUT" | jq -c '.tool_input // {}')"

# Only these tools are in scope; everything else (Read/Grep/Glob/...) passes straight through.
case "$TOOL" in
  Edit|Write|NotebookEdit|Bash|Agent|Task) ;;
  *) exit 0 ;;
esac

# Escape hatch 2 (per-call token inside the tool call itself).
printf '%s' "$TOOL_INPUT" | grep -q 'MODEL-ROLE-EXEMPT' && exit 0

# ─── Reverse a file portably (BSD tail -r, GNU tac) ───
_rev() { tail -r "$1" 2>/dev/null || tac "$1" 2>/dev/null; }

# tier_from_model <model-id>
# Purpose: map a model id string to a tier name.
# Usage: tier_from_model "claude-sonnet-5" → sonnet
# Gotchas: substring match; an empty or unknown id returns "".
tier_from_model() {
  case "$1" in
    *fable*|*mythos*) echo "fable" ;;
    *opus*)           echo "opus" ;;
    *sonnet*)         echo "sonnet" ;;
    *haiku*)          echo "haiku" ;;
    *)                echo "" ;;
  esac
}

# resolve_tier <transcript_path> [agent_id]
# Purpose: derive the model of the agent making THIS call. The PreToolUse payload
#   carries no model field (capture 2026-09-11, model-role-payload-capture.txt). A
#   subagent call carries agent_id but the PARENT's transcript_path (capture
#   2026-09-18, model-role-payload-capture-subagent.txt), so the parent's model must
#   never be used for it.
# Usage: TIER="$(resolve_tier "$TRANSCRIPT" "$AGENT_ID")"
#        → fable|opus|sonnet|haiku | "worker" (subagent, own transcript not on disk yet) | "" (unknown)
# Gotchas: main session → LAST non-sidechain assistant entry. Subagent → LAST assistant
#   entry of <transcript dir>/<session id>/subagents/agent-<agent_id>.jsonl (regular subagents)
#   or subagents/workflows/wf_*/agent-<agent_id>.jsonl (workflow agents). Every entry
#   there is isSidechain:true. `fromjson?` skips partially-written lines.
resolve_tier() {
  local tp="$1" aid="${2:-}" raw="" sub=""
  [ -n "$tp" ] && [ -f "$tp" ] || return 0
  if [ -n "$aid" ]; then
    sub="${tp%.jsonl}/subagents/agent-${aid}.jsonl"
    if [ -f "$sub" ]; then
      raw="$(_rev "$sub" | jq -R -r 'fromjson? | select(.type=="assistant") | .message.model // empty' 2>/dev/null | head -1)"
      tier_from_model "$raw"
      return 0
    fi
    # Workflow agents: subagents/workflows/wf_*/agent-<agent_id>.jsonl
    local wf_sub
    wf_sub="$(find "${tp%.jsonl}/subagents/workflows" -type f -name "agent-${aid}.jsonl" 2>/dev/null | head -1)"
    if [ -n "$wf_sub" ] && [ -f "$wf_sub" ]; then
      raw="$(_rev "$wf_sub" | jq -R -r 'fromjson? | select(.type=="assistant") | .message.model // empty' 2>/dev/null | head -1)"
      tier_from_model "$raw"
      return 0
    fi
    echo "model-role-guard: subagent ${aid} has no transcript at '${sub}' yet — treating it as a worker (its spawn already named a tier)" >&2
    echo "worker"
    return 0
  fi
  raw="$(_rev "$tp" | jq -R -r 'fromjson? | select(.type=="assistant" and (.isSidechain != true)) | .message.model // empty' 2>/dev/null | head -1)"
  tier_from_model "$raw"
}

# user_said_exempt <transcript_path>
# Purpose: escape hatch 3 — Yu-Kuan typing FABLE-OK (any case) in his own message.
# Gotchas: tool results are also type "user"; entries carrying toolUseResult are
#   skipped so tool output can never smuggle the token in.
user_said_exempt() {
  local tp="$1" line=""
  [ -n "$tp" ] && [ -f "$tp" ] || return 1
  line="$(_rev "$tp" | perl -ne 'next if /"toolUseResult"/; if (/"type":"user"/) { print; exit }' 2>/dev/null)"
  printf '%s' "$line" | grep -qi 'FABLE-OK'
}

deny_and_exit() {
  local reason="$1"
  emit_event "incident" '{"class":"model_role_deny","guard":"model-role-guard"}' \
    outcome="denied" source="model-role-guard.sh" || true
  jq -n --arg reason "$reason" \
    '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:$reason}}'
  exit 2
}

TIER="$(resolve_tier "$TRANSCRIPT" "$AGENT_ID")"

# ─── Spawn-tier discipline — applies in EVERY session, whatever the parent model ───
# An omitted `model` makes the subagent inherit the parent, which is exactly how
# Fable ends up doing hands-on work one level down.
if [ "$TOOL" = "Agent" ] || [ "$TOOL" = "Task" ]; then
  MODEL_ARG="$(printf '%s' "$TOOL_INPUT" | jq -r '.model // empty')"
  SUBTYPE="$(printf '%s' "$TOOL_INPUT" | jq -r '.subagent_type // empty')"
  INTENT="$(printf '%s' "$TOOL_INPUT" | jq -r '[.description, .prompt] | map(select(. != null)) | join(" ")')"
  REVIEW_RE='review|critiqu|redline|adversarial|audit|verif|second opinion|assess|evaluat|orchestrat|synthesi'

  if [ "$SUBTYPE" = "fork" ] && [ "$TIER" = "fable" ]; then
    deny_and_exit "MODEL ROLE GUARD: a fork always inherits the parent model, so forking from a Fable session puts Fable on the front line. Spawn a fresh agent with an explicit model (sonnet for execution, haiku for mechanical batches, opus for judgment) instead. Override: add MODEL-ROLE-EXEMPT to the call."
  fi

  if [ -z "$MODEL_ARG" ]; then
    deny_and_exit "MODEL ROLE GUARD: every Agent/Task spawn must name a worker tier — an omitted model silently inherits the parent's. Add model: haiku (mechanical batches), sonnet (standard execution — the default when unsure), or opus (architecture, synthesis, adversarial review). See ~/.claude/rules/model-roles.md."
  fi

  case "$MODEL_ARG" in
    haiku|sonnet|opus|fable) ;;
    *) deny_and_exit "MODEL ROLE GUARD: '${MODEL_ARG}' is not a worker tier. Use haiku, sonnet, opus, or fable (review/critique only). See ~/.claude/rules/model-roles.md." ;;
  esac

  if [ "$MODEL_ARG" = "fable" ] && ! printf '%s' "$INTENT" | grep -qiE "$REVIEW_RE"; then
    deny_and_exit "MODEL ROLE GUARD: Fable subagents are for orchestration and review/critique only, and this dispatch reads as production work. Send it to sonnet (or haiku if it is mechanical, opus if it needs judgment). Override: add MODEL-ROLE-EXEMPT to the prompt."
  fi
fi

# ─── Everything below is Fable-only enforcement ───
if [ -z "$TIER" ]; then
  echo "model-role-guard: could not resolve the session model from '${TRANSCRIPT:-<none>}' — Fable write-block NOT enforced for this call" >&2
  exit 0
fi
[ "$TIER" != "fable" ] && exit 0
user_said_exempt "$TRANSCRIPT" && exit 0

# Artifacts a Fable orchestrator owns and may therefore write itself.
ALLOW_RE='(^|/)(docs/plans|qa|handoffs)/|(^|/)specs?/|(^|/)ORCHESTRATION\.md$|[^/]*review[^/]*\.md$|[^/]*spec[^/]*\.md$'
DELEGATE="Delegate it: Agent(model: \"sonnet\") for standard execution, \"haiku\" for mechanical batches, \"opus\" for judgment calls. Override: say FABLE-OK in your message, or add MODEL-ROLE-EXEMPT to the call."

if [ "$TOOL" = "Edit" ] || [ "$TOOL" = "Write" ] || [ "$TOOL" = "NotebookEdit" ]; then
  FILE="$(printf '%s' "$TOOL_INPUT" | jq -r '.file_path // .notebook_path // empty')"
  if ! printf '%s' "$FILE" | grep -qE "$ALLOW_RE"; then
    deny_and_exit "MODEL ROLE GUARD: Fable orchestrates and reviews; it does not edit files. '${FILE}' is not a plan, spec, or review artifact. ${DELEGATE}"
  fi
  exit 0
fi

# ─── Mutating Bash ───
CMD="$(printf '%s' "$TOOL_INPUT" | jq -r '.command // empty')"
[ -z "$CMD" ] && exit 0

# Neutralise heredoc bodies and quoted strings so a commit message or echoed text
# cannot masquerade as a mutation (same trick as skill-routing-guard.sh).
STRIPPED="$(printf '%s' "$CMD" \
  | perl -0777 -pe "s/<<'?EOF'?.*?^EOF\$/__HEREDOC__/gms" \
  | sed "s/\"[^\"]*\"/__STR__/g; s/'[^']*'/__STR__/g")"
# Drop pure stream plumbing (2>/dev/null, 2>&1, >&2) before looking for redirects.
CLEAN="$(printf '%s' "$STRIPPED" | sed -E 's/[0-9]?>&[0-9]//g; s/[0-9]>[[:space:]]*\/dev\/null//g; s/&>[[:space:]]*\/dev\/null//g')"

MUTATING=0
printf '%s' "$CLEAN" | grep -qE '(^|[;&|`(]|[[:space:]])(rm|mv|cp|mkdir|rmdir|touch|ln|chmod|chown|dd|truncate|install|tee|patch|unlink)([[:space:]]|$)' && MUTATING=1
printf '%s' "$CLEAN" | grep -qE 'sed([[:space:]]+-[a-zA-Z]+)*[[:space:]]+-i|perl[[:space:]]+-[a-zA-Z]*i' && MUTATING=1
# Git splits in two. Moving work FORWARD (add, commit, push, tag) is orchestrator
# duty and stays with Fable. Anything that rewrites or discards existing state is
# hands-on repair work and is delegated.
printf '%s' "$CLEAN" | grep -qE 'git[[:space:]]+(rm|mv|checkout|switch|restore|reset|revert|merge|rebase|stash|apply|cherry-pick|init|clean|config|filter-branch)' && MUTATING=1
printf '%s' "$CLEAN" | grep -qE '(npm|pnpm|yarn|pip|pip3|uv|cargo|gem|brew)[[:space:]]+(install|add|remove|uninstall|publish|link)' && MUTATING=1
printf '%s' "$CLEAN" | grep -qE '>>?' && MUTATING=1

[ "$MUTATING" -eq 0 ] && exit 0

# A mutation is allowed only when every path it names is an orchestrator artifact.
PATHS="$(printf '%s' "$CLEAN" | tr ' \t' '\n\n' | grep -E '^[A-Za-z0-9_~.@+-]*/[A-Za-z0-9_~./@+-]*$' | grep -v '/$' || true)"
if [ -z "$PATHS" ]; then
  deny_and_exit "MODEL ROLE GUARD: Fable orchestrates and reviews; it does not run commands that change state. '${CMD}' mutates something this guard cannot prove is a plan, spec, or review artifact. ${DELEGATE}"
fi
while IFS= read -r p; do
  [ -z "$p" ] && continue
  if ! printf '%s' "$p" | grep -qE "$ALLOW_RE"; then
    deny_and_exit "MODEL ROLE GUARD: Fable orchestrates and reviews; it does not edit files. '${p}' is not a plan, spec, or review artifact. ${DELEGATE}"
  fi
done <<< "$PATHS"

exit 0
