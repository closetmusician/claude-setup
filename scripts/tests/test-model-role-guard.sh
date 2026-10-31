#!/usr/bin/env bash
# ABOUTME: TDD suite for scripts/governance/model-role-guard.sh — the Fable role guard.
# ABOUTME: Drives REAL stdin payloads (shape captured live 2026-09-11, see
# ABOUTME: docs/plans/harness/model-role-payload-capture.txt) plus REAL transcript
# ABOUTME: fixtures; identity is never injected via env (lesson_guard_identity_env_vs_stdin).
# ABOUTME: Run: bash scripts/tests/test-model-role-guard.sh — exit 0 = all green.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GUARD="${SCRIPT_DIR}/../governance/model-role-guard.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

PASS=0; FAIL=0

# make_transcript <file> <model> [last-user-text]
# Purpose: build a realistic transcript JSONL the guard resolves the model from.
# Usage: make_transcript "$TMP/t.jsonl" claude-fable-5-1 "fix the parser"
# Gotchas: entry ORDER matters — the guard reads the LAST assistant entry.
make_transcript() {
  local f="$1" model="$2" usertext="${3:-do the thing}"
  : > "$f"
  printf '%s\n' '{"type":"summary","summary":"x"}' >> "$f"
  jq -cn --arg t "$usertext" '{type:"user",isSidechain:false,message:{role:"user",content:$t}}' >> "$f"
  jq -cn --arg m "$model" '{type:"assistant",isSidechain:false,message:{role:"assistant",model:$m,content:[]}}' >> "$f"
}

# payload <transcript> <tool_name> <tool_input_json>
payload() {
  jq -cn --arg tp "$1" --arg tn "$2" --argjson ti "$3" \
    '{session_id:"test-sess",transcript_path:$tp,cwd:"/Users/yklin/.claude",
      permission_mode:"auto",hook_event_name:"PreToolUse",tool_name:$tn,
      tool_input:$ti,tool_use_id:"toolu_test"}'
}

# make_subagent <parent-transcript> <agent_id> <model>
# Purpose: build the sidechain transcript a subagent writes under
#   <parent dir>/<session id>/subagents/agent-<id>.jsonl (shape captured live 2026-09-18).
# Usage: make_subagent "$FABLE" a1b2c3 claude-sonnet-5
# Gotchas: every entry is isSidechain:true, which the main-session reader skips on purpose.
make_subagent() {
  local parent="$1" aid="$2" model="$3" d="${1%.jsonl}/subagents"
  mkdir -p "$d"
  jq -cn --arg m "$model" --arg a "$aid" '{type:"assistant",isSidechain:true,agentId:$a,message:{role:"assistant",model:$m,content:[]}}' > "$d/agent-${aid}.jsonl"
}

# make_workflow_subagent <parent-transcript> <agent_id> <model> <run_id>
# Purpose: build a workflow agent transcript under
#   <parent dir>/<session id>/subagents/workflows/wf_<run_id>/agent-<id>.jsonl
# Usage: make_workflow_subagent "$FABLE" "abc123def" "claude-sonnet-5" "fe07bf77-630"
# Gotchas: shape matches regular subagents (isSidechain:true), just different path.
make_workflow_subagent() {
  local parent="$1" aid="$2" model="$3" runid="$4"
  local d="${parent%.jsonl}/subagents/workflows/wf_${runid}"
  mkdir -p "$d"
  jq -cn --arg m "$model" --arg a "$aid" '{type:"assistant",isSidechain:true,agentId:$a,message:{role:"assistant",model:$m,content:[]}}' > "$d/agent-${aid}.jsonl"
}

# payload_agent <transcript> <agent_id> <tool_name> <tool_input_json>
# Purpose: the payload a SUBAGENT call carries — agent_id set, transcript_path = PARENT's.
payload_agent() {
  jq -cn --arg tp "$1" --arg aid "$2" --arg tn "$3" --argjson ti "$4" \
    '{session_id:"test-sess",transcript_path:$tp,cwd:"/Users/yklin/.claude",
      permission_mode:"auto",agent_id:$aid,agent_type:"general-purpose",
      hook_event_name:"PreToolUse",tool_name:$tn,tool_input:$ti,tool_use_id:"toolu_test"}'
}

# check <name> <expected: ALLOW|DENY> <payload-json> [env assignments...]
check() {
  local name="$1" expect="$2" pl="$3"; shift 3
  local out rc
  out="$(printf '%s' "$pl" | env "$@" bash "$GUARD" 2>/dev/null)"; rc=$?
  local got="ALLOW"; [ "$rc" -eq 2 ] && got="DENY"
  if [ "$got" = "$expect" ]; then
    PASS=$((PASS+1)); printf '  ok   %s\n' "$name"
  else
    FAIL=$((FAIL+1)); printf '  FAIL %s (expected %s, got %s rc=%d)\n' "$name" "$expect" "$got" "$rc"
  fi
}

echo "=== test-model-role-guard.sh ==="

FABLE="$TMP/fable.jsonl";  make_transcript "$FABLE" "claude-fable-5-1"
OPUS="$TMP/opus.jsonl";    make_transcript "$OPUS"  "claude-opus-5"
SONNET="$TMP/sonnet.jsonl"; make_transcript "$SONNET" "claude-sonnet-5"
EXEMPT="$TMP/exempt.jsonl"; make_transcript "$EXEMPT" "claude-fable-5-1" "redo this yourself FABLE-OK"
EXEMPT_LC="$TMP/exempt-lc.jsonl"; make_transcript "$EXEMPT_LC" "claude-fable-5-1" "ok to use fable to fix this fable-ok"
make_subagent "$FABLE" sonnetkid claude-sonnet-5
make_subagent "$FABLE" fablekid  claude-fable-5-1

echo "-- Fable write-block --"
check "fable Edit source file"        DENY  "$(payload "$FABLE" Edit '{"file_path":"/repo/src/parser.ts","old_string":"a","new_string":"b"}')"
check "fable Write source file"       DENY  "$(payload "$FABLE" Write '{"file_path":"/repo/src/new.ts","content":"x"}')"
check "fable NotebookEdit"            DENY  "$(payload "$FABLE" NotebookEdit '{"notebook_path":"/repo/nb.ipynb"}')"
check "fable Edit docs/plans"         ALLOW "$(payload "$FABLE" Edit '{"file_path":"/repo/docs/plans/wave-1.md","old_string":"a","new_string":"b"}')"
check "fable Write qa artifact"       ALLOW "$(payload "$FABLE" Write '{"file_path":"/repo/qa/FEAT-1/T-001-ready-for-review.md","content":"x"}')"
check "fable Write review md"         ALLOW "$(payload "$FABLE" Write '{"file_path":"/repo/notes/design-review.md","content":"x"}')"
check "fable Write ORCHESTRATION.md"  ALLOW "$(payload "$FABLE" Write '{"file_path":"/repo/ORCHESTRATION.md","content":"x"}')"
check "fable Write handoffs"          ALLOW "$(payload "$FABLE" Write '{"file_path":"/Users/yklin/.claude/handoffs/PM.md","content":"x"}')"
check "fable Write spec"              ALLOW "$(payload "$FABLE" Write '{"file_path":"/repo/docs/auth-spec.md","content":"x"}')"

echo "-- Fable Bash --"
check "fable git commit"              ALLOW  "$(payload "$FABLE" Bash '{"command":"git commit -m \"feat: x\"","description":"commit"}')"
check "fable git push"                ALLOW  "$(payload "$FABLE" Bash '{"command":"git push origin main","description":"push"}')"
check "fable redirect to tmp"         DENY  "$(payload "$FABLE" Bash '{"command":"echo hi > /tmp/out.txt","description":"write"}')"
check "fable sed -i on source"        DENY  "$(payload "$FABLE" Bash '{"command":"sed -i \"\" s/a/b/ src/app.ts","description":"edit"}')"
check "fable read-only grep"          ALLOW "$(payload "$FABLE" Bash '{"command":"rtk proxy grep -rn foo src/","description":"search"}')"
check "fable git status"              ALLOW "$(payload "$FABLE" Bash '{"command":"git status && git diff","description":"status"}')"
check "fable stderr redirect only"    ALLOW "$(payload "$FABLE" Bash '{"command":"ls -la /repo 2>/dev/null","description":"list"}')"
check "fable sed -i on plan doc"      ALLOW "$(payload "$FABLE" Bash '{"command":"sed -i \"\" s/a/b/ docs/plans/wave-1.md","description":"edit plan"}')"

echo "-- Fable git: ship-forward is allowed, history-rewriting is not --"
check "git add explicit paths"   ALLOW "$(payload "$FABLE" Bash '{"command":"git add src/parser.ts docs/plans/x.md","description":"stage"}')"
check "git add -u"               ALLOW "$(payload "$FABLE" Bash '{"command":"git add -u","description":"stage"}')"
check "git tag"                  ALLOW "$(payload "$FABLE" Bash '{"command":"git tag v1.2.0","description":"tag"}')"
check "git fetch"                ALLOW "$(payload "$FABLE" Bash '{"command":"git fetch origin","description":"fetch"}')"
check "git show"                 ALLOW "$(payload "$FABLE" Bash '{"command":"git show HEAD --stat","description":"show"}')"
check "git log"                  ALLOW "$(payload "$FABLE" Bash '{"command":"git log --oneline -5","description":"log"}')"
check "git apply"                DENY  "$(payload "$FABLE" Bash '{"command":"git apply /tmp/fix.patch","description":"apply patch"}')"
check "git checkout file"        DENY  "$(payload "$FABLE" Bash '{"command":"git checkout -- src/parser.ts","description":"discard"}')"
check "git restore"              DENY  "$(payload "$FABLE" Bash '{"command":"git restore src/parser.ts","description":"restore"}')"
check "git reset --hard"         DENY  "$(payload "$FABLE" Bash '{"command":"git reset --hard origin/main","description":"reset"}')"
check "git revert"               DENY  "$(payload "$FABLE" Bash '{"command":"git revert abc123","description":"revert"}')"
check "git stash pop"            DENY  "$(payload "$FABLE" Bash '{"command":"git stash pop","description":"stash"}')"
check "git clean"                DENY  "$(payload "$FABLE" Bash '{"command":"git clean -fd","description":"clean"}')"
check "git merge"                DENY  "$(payload "$FABLE" Bash '{"command":"git merge feat/x","description":"merge"}')"
check "git rebase"               DENY  "$(payload "$FABLE" Bash '{"command":"git rebase main","description":"rebase"}')"
check "git commit still fine for non-fable" ALLOW "$(payload "$SONNET" Bash '{"command":"git rebase main","description":"rebase"}')"

echo "-- Non-Fable sessions are untouched --"
check "opus Edit source file"         ALLOW "$(payload "$OPUS" Edit '{"file_path":"/repo/src/parser.ts","old_string":"a","new_string":"b"}')"
check "sonnet git commit"             ALLOW "$(payload "$SONNET" Bash '{"command":"git commit -m x","description":"commit"}')"
check "fable Read is never blocked"   ALLOW "$(payload "$FABLE" Read '{"file_path":"/repo/src/parser.ts"}')"

echo "-- Subagents of a Fable session resolve their OWN tier (bug 2026-09-18) --"
check "sonnet subagent Edit source"   ALLOW "$(payload_agent "$FABLE" sonnetkid Edit '{"file_path":"/repo/src/parser.ts","old_string":"a","new_string":"b"}')"
check "sonnet subagent heredoc write" ALLOW "$(payload_agent "$FABLE" sonnetkid Bash '{"command":"cat > src/x.js <<EOF\nx\nEOF","description":"write"}')"
check "fable subagent Edit source"    DENY  "$(payload_agent "$FABLE" fablekid Edit '{"file_path":"/repo/src/parser.ts","old_string":"a","new_string":"b"}')"
check "subagent transcript not yet on disk" ALLOW "$(payload_agent "$FABLE" ghostkid Edit '{"file_path":"/repo/src/parser.ts","old_string":"a","new_string":"b"}')"
check "subagent spawn still needs a model" DENY "$(payload_agent "$FABLE" sonnetkid Agent '{"description":"x","prompt":"y"}')"

echo "-- Workflow agents resolve their OWN tier (Gap 1 fix) --"
make_workflow_subagent "$FABLE" "wf_sonnet" "claude-sonnet-5" "abc123-456"
make_workflow_subagent "$FABLE" "wf_fable" "claude-fable-5-1" "abc123-456"
check "sonnet workflow agent Edit source"     ALLOW "$(payload_agent "$FABLE" "wf_sonnet" Edit '{"file_path":"/repo/src/parser.ts","old_string":"a","new_string":"b"}')"
check "fable workflow agent Edit source"      DENY  "$(payload_agent "$FABLE" "wf_fable" Edit '{"file_path":"/repo/src/parser.ts","old_string":"a","new_string":"b"}')"
check "workflow agent not on disk yet"        ALLOW "$(payload_agent "$FABLE" "wf_ghost" Edit '{"file_path":"/repo/src/parser.ts","old_string":"a","new_string":"b"}')"
check "workflow agent spawn needs model"      DENY  "$(payload_agent "$FABLE" "wf_sonnet" Agent '{"description":"x","prompt":"y"}')"

echo "-- Escape hatches --"
check "fable-ok lowercase in user message" ALLOW "$(payload "$EXEMPT_LC" Edit '{"file_path":"/repo/src/parser.ts","old_string":"a","new_string":"b"}')"
check "FABLE-OK in user message"      ALLOW "$(payload "$EXEMPT" Edit '{"file_path":"/repo/src/parser.ts","old_string":"a","new_string":"b"}')"
check "MODEL-ROLE-EXEMPT in call"     ALLOW "$(payload "$FABLE" Bash '{"command":"git commit -m x # MODEL-ROLE-EXEMPT","description":"commit"}')"
check "env kill switch"               ALLOW "$(payload "$FABLE" Edit '{"file_path":"/repo/src/parser.ts","old_string":"a","new_string":"b"}')" HARNESS_MODEL_ROLE_GUARD=0

echo "-- Spawn tier discipline (every session) --"
check "Agent with no model"           DENY  "$(payload "$OPUS" Agent '{"description":"implement parser","prompt":"write the parser"}')"
check "Agent model=sonnet"            ALLOW "$(payload "$OPUS" Agent '{"description":"implement parser","prompt":"write it","model":"sonnet"}')"
check "Agent model=haiku"             ALLOW "$(payload "$OPUS" Agent '{"description":"rename sweep","prompt":"apply regex","model":"haiku"}')"
check "Agent model=bogus"             DENY  "$(payload "$OPUS" Agent '{"description":"x","prompt":"y","model":"gpt-4"}')"
check "Task with no model"            DENY  "$(payload "$OPUS" Task '{"description":"implement","prompt":"do it","subagent_type":"general-purpose"}')"
check "fable worker for real work"    DENY  "$(payload "$OPUS" Agent '{"description":"implement the parser","prompt":"write code","model":"fable"}')"
check "fable worker for review"       ALLOW "$(payload "$OPUS" Agent '{"description":"adversarial review of wave 1","prompt":"critique this","model":"fable"}')"
check "fork from fable parent"        DENY  "$(payload "$FABLE" Agent '{"description":"finish the build","prompt":"go","subagent_type":"fork","model":"sonnet"}')"
check "fork from opus parent"         ALLOW "$(payload "$OPUS" Agent '{"description":"finish the build","prompt":"go","subagent_type":"fork","model":"opus"}')"

echo "-- Degenerate input never crashes --"
check "malformed json"                ALLOW "not json at all"
check "missing transcript"            ALLOW "$(payload "$TMP/nope.jsonl" Edit '{"file_path":"/repo/src/a.ts"}')"
check "empty payload"                 ALLOW ""

# Unresolvable identity must WARN loudly, not fail silently (hook-authoring §8).
WARN_OUT="$(payload "$TMP/nope.jsonl" Edit '{"file_path":"/repo/src/a.ts"}' | bash "$GUARD" 2>&1 >/dev/null)"
if printf '%s' "$WARN_OUT" | grep -q "model-role-guard"; then
  PASS=$((PASS+1)); printf '  ok   unresolvable model warns on stderr\n'
else
  FAIL=$((FAIL+1)); printf '  FAIL unresolvable model warns on stderr (got: %s)\n' "$WARN_OUT"
fi

# A deny must carry a machine-readable reason Claude Code understands.
DENY_OUT="$(payload "$FABLE" Edit '{"file_path":"/repo/src/parser.ts"}' | bash "$GUARD" 2>/dev/null)"
if printf '%s' "$DENY_OUT" | jq -e '.hookSpecificOutput.permissionDecision == "deny"' >/dev/null 2>&1; then
  PASS=$((PASS+1)); printf '  ok   deny emits permissionDecision JSON\n'
else
  FAIL=$((FAIL+1)); printf '  FAIL deny emits permissionDecision JSON\n'
fi

echo
echo "=== $PASS passed, $FAIL failed ==="
[ "$FAIL" -eq 0 ]
