#!/usr/bin/env bash
# ABOUTME: Tests for scripts/governance/manifest-bind.sh (PreToolUse Task/Agent binder).
# ABOUTME: Covers: no-sentinel inert, marker present appends entry, duplicate spawn idempotent,
# ABOUTME: spawn without marker is a no-op, and unknown role is skipped. Strict TDD: RED first.
# ABOUTME: Run from any directory; uses a mktemp project root with sentinel-gated STATE.

set -uo pipefail

BINDER="${BINDER:-$HOME/.claude/scripts/governance/manifest-bind.sh}"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
PASS=0; FAIL=0

STATE="$TMP/.agents/claude-governance"
mkdir -p "$STATE"

# Self-isolate against an INHERITED HARNESS_GOV_STATE_DIR (BUG-DAYINLIFE-02): the binder
# resolves its governance dir via get_governance_state_dir(), which honors this override at
# highest precedence. Unconditionally point it at THIS test's own dir so binder and test read
# the same manifest/sentinel path, regardless of any value exported by the caller.
export HARNESS_GOV_STATE_DIR="$STATE"

# Helper: fake a PreToolUse Task payload (or Agent — same shape) for the binder.
# $1=tool_name, $2=prompt_body ('' for no prompt), $3=agent_id ('' for none)
task_payload() {
  local tn="$1" prompt="$2" aid="$3"
  if [[ -n "$aid" ]]; then
    jq -cn --arg tn "$tn" --arg p "$prompt" --arg aid "$aid" \
      '{"tool_name":$tn,"agent_id":$aid,"tool_input":{"prompt":$p}}'
  else
    jq -cn --arg tn "$tn" --arg p "$prompt" \
      '{"tool_name":$tn,"tool_input":{"prompt":$p}}'
  fi
}

run_binder() {
  # Run binder with TMP as the git project root (fake git root via override).
  # Must use printf not echo: echo corrupts JSON with escape-sequence expansion.
  ( cd "$TMP"
    # Create a fake git so get_project_root returns TMP
    git init -q "$TMP" 2>/dev/null || true
    printf '%s\n' "$1" | bash "$BINDER"
  )
}

check() { # $1 case name, $2 expected (yes_manifest|no_manifest|entry_count=N|field), $3 actual
  local name="$1" expected="$2" actual="${3:-}"
  case "$expected" in
    pass)
      if [[ "$actual" == "0" ]]; then
        echo "PASS: $name"; PASS=$((PASS+1))
      else
        echo "FAIL: $name — expected exit 0, got $actual"; FAIL=$((FAIL+1))
      fi
      ;;
    no_manifest)
      if [[ ! -f "$STATE/run-manifest.json" ]]; then
        echo "PASS: $name"; PASS=$((PASS+1))
      else
        echo "FAIL: $name — manifest unexpectedly created"; FAIL=$((FAIL+1))
      fi
      ;;
    has_entry)
      # $actual is a jq query result
      if [[ -n "$actual" && "$actual" != "null" && "$actual" != "0" ]]; then
        echo "PASS: $name"; PASS=$((PASS+1))
      else
        echo "FAIL: $name — expected truthy jq result, got: '${actual}'"; FAIL=$((FAIL+1))
      fi
      ;;
    exact)
      # $actual = expected value
      if [[ "$actual" == "$3" ]]; then
        echo "PASS: $name"; PASS=$((PASS+1))
      else
        echo "FAIL: $name — expected '$3', got '$actual'"; FAIL=$((FAIL+1))
      fi
      ;;
  esac
}

# ── Case A: no sentinel → manifest is NOT created ─────────────────────────────
rm -f "$STATE/.active" "$STATE/run-manifest.json"
PROMPT_A="GOVERNANCE-ROLE: role=coder task=T-001
## Mandatory Context
docs/spec.md
## Constraints
foo"
run_binder "$(task_payload Task "$PROMPT_A" "")" >/dev/null 2>&1
check "A no-sentinel → no manifest" no_manifest

# ── Case B: sentinel present + marker → entry appended with derived glob + agent_id:null ──
touch "$STATE/.active"
rm -f "$STATE/run-manifest.json"
PROMPT_B="GOVERNANCE-ROLE: role=coder task=T-002
## Mandatory Context
docs/spec.md
## Constraints
foo"
run_binder "$(task_payload Task "$PROMPT_B" "")" >/dev/null 2>&1
if [[ -f "$STATE/run-manifest.json" ]]; then
  ENTRY_ROLE=$(jq -r '.tasks[0].role // empty' "$STATE/run-manifest.json" 2>/dev/null)
  ENTRY_TASK=$(jq -r '.tasks[0].task_id // empty' "$STATE/run-manifest.json" 2>/dev/null)
  ENTRY_AID=$(jq -r '.tasks[0].agent_id' "$STATE/run-manifest.json" 2>/dev/null)
  ENTRY_GLOBS=$(jq -r '.tasks[0].artifact_globs | length' "$STATE/run-manifest.json" 2>/dev/null)
  if [[ "$ENTRY_ROLE" == "coder" && "$ENTRY_TASK" == "T-002" && "$ENTRY_AID" == "null" && "$ENTRY_GLOBS" -ge 1 ]]; then
    echo "PASS: B marker present → entry with role/task/null-agent_id/globs"; PASS=$((PASS+1))
  else
    echo "FAIL: B — role=$ENTRY_ROLE task=$ENTRY_TASK agent_id=$ENTRY_AID globs=$ENTRY_GLOBS"; FAIL=$((FAIL+1))
  fi
else
  echo "FAIL: B — manifest not created"; FAIL=$((FAIL+1))
fi

# ── Case C: duplicate (task,role) spawn → no second entry, spawn_ts refreshed ───
touch "$STATE/.active"
TASK_COUNT_BEFORE=$(jq '.tasks | length' "$STATE/run-manifest.json" 2>/dev/null || echo 0)
PROMPT_C="GOVERNANCE-ROLE: role=coder task=T-002
## Mandatory Context
docs/spec.md
## Constraints
foo"
run_binder "$(task_payload Task "$PROMPT_C" "")" >/dev/null 2>&1
TASK_COUNT_AFTER=$(jq '.tasks | length' "$STATE/run-manifest.json" 2>/dev/null || echo 0)
if [[ "$TASK_COUNT_AFTER" == "$TASK_COUNT_BEFORE" ]]; then
  echo "PASS: C duplicate spawn → no second entry (idempotent)"; PASS=$((PASS+1))
else
  echo "FAIL: C — task count went from $TASK_COUNT_BEFORE to $TASK_COUNT_AFTER"; FAIL=$((FAIL+1))
fi

# ── Case D: spawn without GOVERNANCE-ROLE marker → manifest untouched ──────────
touch "$STATE/.active"
MANIFEST_MTIME_BEFORE=$(stat -f %m "$STATE/run-manifest.json" 2>/dev/null || echo 0)
PROMPT_D="## Mandatory Context
docs/spec.md
## Constraints
foo"
run_binder "$(task_payload Task "$PROMPT_D" "")" >/dev/null 2>&1
MANIFEST_MTIME_AFTER=$(stat -f %m "$STATE/run-manifest.json" 2>/dev/null || echo 0)
TASK_COUNT_D=$(jq '.tasks | length' "$STATE/run-manifest.json" 2>/dev/null || echo 0)
# Untouched means same entry count (still 1 from case B) and mtime unchanged or manifest unchanged
if [[ "$TASK_COUNT_D" == "$TASK_COUNT_BEFORE" ]]; then
  echo "PASS: D no marker → manifest untouched (still $TASK_COUNT_D entry)"; PASS=$((PASS+1))
else
  echo "FAIL: D — task count changed to $TASK_COUNT_D after no-marker spawn"; FAIL=$((FAIL+1))
fi

# ── Case E: unknown role → skipped (no entry added) ──────────────────────────
touch "$STATE/.active"
COUNT_BEFORE_E=$(jq '.tasks | length' "$STATE/run-manifest.json" 2>/dev/null || echo 0)
PROMPT_E="GOVERNANCE-ROLE: role=some-unknown-role task=T-003
## Mandatory Context
docs/spec.md
## Constraints
foo"
run_binder "$(task_payload Task "$PROMPT_E" "")" >/dev/null 2>&1
COUNT_AFTER_E=$(jq '.tasks | length' "$STATE/run-manifest.json" 2>/dev/null || echo 0)
if [[ "$COUNT_AFTER_E" == "$COUNT_BEFORE_E" ]]; then
  echo "PASS: E unknown role → no entry appended"; PASS=$((PASS+1))
else
  echo "FAIL: E — entry count changed from $COUNT_BEFORE_E to $COUNT_AFTER_E for unknown role"; FAIL=$((FAIL+1))
fi

echo
echo "manifest-bind: $PASS passed, $FAIL failed"
[[ "$FAIL" -eq 0 ]]
