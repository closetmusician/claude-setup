#!/usr/bin/env bash
# ABOUTME: Shared fixtures for the governance-scope hook suites (workspace kind, role
# ABOUTME: enforcement, pre-agent gate, doc placement, read budget, read meter).
# ABOUTME: Builds REAL temp git repos and REAL PreToolUse/PostToolUse stdin payloads.
# ABOUTME: Source it from a suite; the suite owns $TMP, PASS and FAIL.
# ABOUTME: Spec: docs/plans/harness/governance-scope-spec.md §4.

# new_repo <dir> [file...]
# Purpose: create a git repo at <dir> holding the named files (empty, committed).
# Usage: new_repo "$TMP/app" package.json src/a.py
# Gotchas: files are committed so `git ls-files` sees them; dirs are created as needed.
new_repo() {
  local d="$1"; shift
  mkdir -p "$d"
  git -C "$d" init -q
  local f
  for f in "$@"; do mkdir -p "$d/$(dirname "$f")"; : > "$d/$f"; done
  git -C "$d" add -A >/dev/null 2>&1
  git -C "$d" -c user.email=t@t -c user.name=t commit -q -m init --allow-empty >/dev/null 2>&1
}

# pl <event> <cwd> <tool_name> <tool_input_json> [agent_id] [tool_response_json]
# Purpose: build one hook stdin payload in the shape Claude Code sends.
# Usage: pl PreToolUse "$REPO" Write '{"file_path":"/x/y.md"}' ""
# Gotchas: an empty agent_id means the main session (orchestrator).
pl() {
  local ev="$1" cwd="$2" tn="$3" ti="$4" aid="${5:-}" tr="${6:-null}"
  jq -cn --arg ev "$ev" --arg cwd "$cwd" --arg tn "$tn" --argjson ti "$ti" \
    --arg aid "$aid" --argjson tr "$tr" \
    '{session_id:"test-sess",transcript_path:"/nonexistent.jsonl",cwd:$cwd,
      hook_event_name:$ev,tool_name:$tn,tool_input:$ti,tool_use_id:"toolu_test"}
     + (if $aid == "" then {} else {agent_id:$aid,agent_type:"general-purpose"} end)
     + (if $tr == null then {} else {tool_response:$tr} end)'
}

# run_hook <hook> <cwd> <payload> [env assignments...]
# Purpose: run a hook from <cwd> with the payload on stdin; sets OUT and RC.
# Usage: run_hook "$HOOK" "$REPO" "$(pl ...)" HARNESS_GOV_STATE_DIR="$STATE"
# Gotchas: stderr is dropped; hooks must keep stdout for decisions only.
run_hook() {
  local hook="$1" cwd="$2" payload="$3"; shift 3
  OUT="$(cd "$cwd" && printf '%s' "$payload" | env "$@" bash "$hook" 2>/dev/null)"; RC=$?
}

# decision_of
# Purpose: classify the last run_hook result as DENY or ALLOW.
# Usage: run_hook ...; got="$(decision_of)"
# Gotchas: covers all three deny shapes in use (exit 2, permissionDecision, decision:block).
decision_of() {
  if [ "$RC" -eq 2 ] \
    || printf '%s' "$OUT" | jq -e '.hookSpecificOutput.permissionDecision == "deny"' >/dev/null 2>&1 \
    || printf '%s' "$OUT" | jq -e '.decision == "block"' >/dev/null 2>&1; then
    echo DENY
  else
    echo ALLOW
  fi
}

# check <name> <expect ALLOW|DENY> <hook> <cwd> <payload> [env assignments...]
# Purpose: run a hook and record pass/fail against the expected decision.
# Usage: check "docs md allowed" ALLOW "$HOOK" "$REPO" "$(pl ...)" HARNESS_GOV_STATE_DIR="$S"
# Gotchas: increments the suite's PASS/FAIL globals.
check() {
  local name="$1" expect="$2" hook="$3" cwd="$4" payload="$5"; shift 5
  run_hook "$hook" "$cwd" "$payload" "$@"
  local got; got="$(decision_of)"
  if [ "$got" = "$expect" ]; then
    PASS=$((PASS+1)); printf '  ok   %s\n' "$name"
  else
    FAIL=$((FAIL+1)); printf '  FAIL %s (expected %s, got %s rc=%d out=%s)\n' "$name" "$expect" "$got" "$RC" "${OUT:0:160}"
  fi
}

# assert_eq <name> <expected> <actual>
# Purpose: plain value assertion for library functions.
# Usage: assert_eq "marker docs" docs "$(get_workspace_kind "$D")"
# Gotchas: increments PASS/FAIL.
assert_eq() {
  if [ "$2" = "$3" ]; then
    PASS=$((PASS+1)); printf '  ok   %s\n' "$1"
  else
    FAIL=$((FAIL+1)); printf '  FAIL %s (expected %s, got %s)\n' "$1" "$2" "$3"
  fi
}

# fill_bytes <file> <bytes> [line_len]
# Purpose: write a text file of an exact byte size made of fixed-length lines.
# Usage: fill_bytes "$REPO/big.md" 66150
# Gotchas: line_len includes the newline; the last line may be short.
fill_bytes() {
  local f="$1" n="$2" ll="${3:-80}"
  perl -e '($n,$ll)=@ARGV; $l=("x" x ($ll-1))."\n"; $o=""; $o.=$l while length($o)+$ll<=$n; $o.=("y" x ($n-length($o))); print $o' "$n" "$ll" > "$f"
}
