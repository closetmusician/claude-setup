#!/usr/bin/env bash
# ABOUTME: Behavior tests for scripts/governance/qa-artifact-ownership-guard.sh
# ABOUTME: (PreToolUse Write|Edit|Bash). Covers: sentinel gating, orchestrator vs subagent
# ABOUTME: authorship, artifact-name variants (bypass B7), Bash heredoc/redirect bypass (F3),
# ABOUTME: governance-sentinel deletion protection with .gate-* exemption (B2), and
# ABOUTME: verification.md family coverage (F4).
# ABOUTME: Written after adversarial review docs/temp/adv-review-0703.

set -uo pipefail

GUARD="${GUARD:-$HOME/.claude/scripts/governance/qa-artifact-ownership-guard.sh}"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
PASS=0; FAIL=0

STATE="$TMP/.agents/claude-governance"
mkdir -p "$STATE"

# Self-isolate against an INHERITED HARNESS_GOV_STATE_DIR (BUG-DAYINLIFE-02): the guard
# resolves its governance dir via get_governance_state_dir(), which honors this override at
# highest precedence. Unconditionally point it at THIS test's own dir so guard and test read
# the same sentinel/manifest path, regardless of any value exported by the caller.
export HARNESS_GOV_STATE_DIR="$STATE"

run_guard() { # $1 tool_name, $2 agent_id ('' for main thread), $3 tool_input JSON
  ( cd "$TMP" && jq -cn --arg tn "$1" --arg aid "$2" --argjson ti "$3" \
      '{"tool_name":$tn,"tool_input":$ti} + (if $aid == "" then {} else {"agent_id":$aid} end)' \
    | bash "$GUARD" )
}

check() { # $1 case name, $2 expected (deny|allow), $3 actual output
  if [[ "$2" == "deny" ]]; then
    if echo "$3" | grep -q '"permissionDecision":"deny"'; then
      echo "PASS: $1"; PASS=$((PASS+1))
    else
      echo "FAIL: $1 — expected deny, got: ${3:-<empty>}"; FAIL=$((FAIL+1))
    fi
  else
    if echo "$3" | grep -q '"permissionDecision":"deny"'; then
      echo "FAIL: $1 — expected allow, got deny: $3"; FAIL=$((FAIL+1))
    else
      echo "PASS: $1"; PASS=$((PASS+1))
    fi
  fi
}

wi() { jq -cn --arg p "$1" '{"file_path":$p,"content":"x"}'; }   # Write input
bi() { jq -cn --arg c "$1" '{"command":$c}'; }                    # Bash input

# 1. No sentinel -> guard is inert even on a guarded path
rm -f "$STATE/.active"
check "1 inert without sentinel" allow "$(run_guard Write "" "$(wi "qa/FEAT-1/T-001-cycle-1.md")")"

touch "$STATE/.active"

# 2. Main thread writes a QA cycle artifact -> deny
check "2 main-thread cycle write denied" deny "$(run_guard Write "" "$(wi "qa/FEAT-1/T-001-cycle-1.md")")"

# 3. Subagent writes the same artifact -> allow
check "3 subagent cycle write allowed" allow "$(run_guard Write "agent-abc123" "$(wi "qa/FEAT-1/T-001-cycle-1.md")")"

# 4. Main thread writes a normal path -> allow
check "4 main-thread normal write allowed" allow "$(run_guard Write "" "$(wi "src/foo.py")")"

# 5. Main thread writes ready-for-review (coder artifact, F4) -> deny
check "5 main-thread ready-for-review denied" deny "$(run_guard Write "" "$(wi "qa/FEAT-1/T-001-ready-for-review.md")")"

# 6. Artifact-name variant without the hyphen (bypass B7) -> deny
check "6 name variant cycle1 denied" deny "$(run_guard Write "" "$(wi "qa/FEAT-1/T-001-cycle1.md")")"

# 7. Bash heredoc write into a cycle artifact (bypass F3) -> deny
check "7 bash heredoc into cycle denied" deny "$(run_guard Bash "" "$(bi "cat > qa/FEAT-1/T-001-cycle-2.md << 'EOF'
all good
EOF")")"

# 8a. Main thread deletes the governance sentinel (bypass B2) -> deny
check "8a sentinel rm denied (main)" deny "$(run_guard Bash "" "$(bi "rm -f .agents/claude-governance/.active")")"

# 8b. Even a subagent deleting the sentinel -> deny
check "8b sentinel rm denied (subagent)" deny "$(run_guard Bash "agent-abc123" "$(bi "rm -rf .agents/claude-governance")")"

# 9. Orchestrator removing a workflow gate sentinel is protocol (vibe §4.1 3a) -> allow
check "9 gate sentinel rm allowed" allow "$(run_guard Bash "" "$(bi "rm .agents/claude-governance/.gate-pre-coder")")"

# 10. Innocuous Bash touching qa/ read-only -> allow
check "10 innocuous bash allowed" allow "$(run_guard Bash "" "$(bi "ls qa/FEAT-1/")")"

# 11. Main thread writes a verification report (F4) -> deny
check "11 main-thread verification.md denied" deny "$(run_guard Write "" "$(wi "docs/temp/run-7/verification.md")")"

# 12. Bash redirect to a non-guarded md -> allow
check "12 bash redirect to notes allowed" allow "$(run_guard Bash "" "$(bi "echo hi > notes.md")")"

# 13. Main thread Edit on acceptance tests -> deny
check "13 main-thread acceptance edit denied" deny "$(run_guard Edit "" "$(wi "qa/FEAT-2/T-004-acceptance-tests.md")")"

# 14. Bash tee into review-findings (F3/F4) -> deny
check "14 bash tee into review-findings denied" deny "$(run_guard Bash "" "$(bi "echo done | tee qa/FEAT-1/T-001-review-findings.md")")"

# ---- Hole 1: interpreter one-liner bypass (REV-C §Probe "python -c write") ----

# 15. Main thread python3 -c writing a guarded artifact -> deny (Hole 1 DENY)
check "15 python3 -c guarded artifact denied" deny \
  "$(run_guard Bash "" "$(bi "python3 -c \"open('qa/FEAT-1/T-001-cycle-5.md','w').write('x')\"")")"

# 16. Subagent python3 -c writing same artifact -> allow (Hole 1 ALLOW)
check "16 python3 -c subagent allowed" allow \
  "$(run_guard Bash "agent-abc123" "$(bi "python3 -c \"open('qa/FEAT-1/T-001-cycle-5.md','w').write('x')\"")")"

# ---- Hole 2: symlink bypass (REV-C §Probe "Edit symlink outside qa/") ----

# 17. Main thread Edit on a symlink that resolves into qa/ -> deny (Hole 2 DENY)
mkdir -p "$TMP/safe"
ln -sf "$TMP/qa/FEAT-1/T-001-cycle-1.md" "$TMP/safe/edit-link.md"
check "17 symlink write into qa denied" deny \
  "$(run_guard Edit "" "$(wi "$TMP/safe/edit-link.md")")"

# 18. Subagent Edit on same symlink -> allow (Hole 2 ALLOW)
check "18 symlink write subagent allowed" allow \
  "$(run_guard Edit "agent-abc123" "$(wi "$TMP/safe/edit-link.md")")"

# ---- II.3 Role-Provenance Manifest checks (cases 19-24) ----
# Helper: with_manifest — drop a run-manifest.json into $STATE before running the guard.
# Usage: with_manifest '<json>' run_guard ...
with_manifest() {
  local json="$1"; shift
  printf '%s\n' "$json" > "$STATE/run-manifest.json"
  "$@"
}

# 19. manifest-bound + correct agent writes its role artifact -> allow
M19=$(jq -cn '{
  "schema":1,"run_id":"t_test","created_by":"test","created_ts":"2026-01-01T00:00:00.000Z",
  "tasks":[{"task_id":"T-001","role":"coder","artifact_globs":["qa/FEAT/T-001-ready-for-review.md"],
             "agent_id":"a_coder","bound_ts":"2026-01-01T00:00:01.000Z","spawn_ts":"2026-01-01T00:00:00.000Z"}]
}')
check "19 manifest-bound correct agent allow" allow \
  "$(with_manifest "$M19" run_guard Write "a_coder" "$(wi "qa/FEAT/T-001-ready-for-review.md")")"

# 20. manifest-bound + WRONG agent writes another role's artifact -> deny (core check)
M20=$(jq -cn '{
  "schema":1,"run_id":"t_test","created_by":"test","created_ts":"2026-01-01T00:00:00.000Z",
  "tasks":[{"task_id":"T-001","role":"qa-tester","artifact_globs":["qa/FEAT/T-001-cycle-1.md"],
             "agent_id":"a_qa","bound_ts":"2026-01-01T00:00:01.000Z","spawn_ts":"2026-01-01T00:00:00.000Z"}]
}')
check "20 manifest-bound wrong agent deny" deny \
  "$(with_manifest "$M20" run_guard Write "a_coder" "$(wi "qa/FEAT/T-001-cycle-1.md")")"

# 21. manifest present, role UNCLAIMED (agent_id:null), first writer claims -> allow
M21=$(jq -cn '{
  "schema":1,"run_id":"t_test","created_by":"test","created_ts":"2026-01-01T00:00:00.000Z",
  "tasks":[{"task_id":"T-001","role":"coder","artifact_globs":["qa/FEAT/T-001-ready-for-review.md"],
             "agent_id":null,"bound_ts":null,"spawn_ts":"2026-01-01T00:00:00.000Z"}]
}')
check "21 unclaimed role first-write claim allow" allow \
  "$(with_manifest "$M21" run_guard Write "a_x" "$(wi "qa/FEAT/T-001-ready-for-review.md")")"
# Also assert the claim was persisted into run-manifest.json
if [[ -f "$STATE/run-manifest.json" ]]; then
  BOUND=$(jq -r '.tasks[0].agent_id // empty' "$STATE/run-manifest.json" 2>/dev/null)
  if [[ "$BOUND" == "a_x" ]]; then
    echo "PASS: 21b claim persisted (agent_id=a_x)"; PASS=$((PASS+1))
  else
    echo "FAIL: 21b claim NOT persisted — got '${BOUND:-<empty>}'"; FAIL=$((FAIL+1))
  fi
else
  echo "FAIL: 21b run-manifest.json missing after claim"; FAIL=$((FAIL+1))
fi

# 22. manifest present, path NOT bound (different task) -> allow (no regression)
M22=$(jq -cn '{
  "schema":1,"run_id":"t_test","created_by":"test","created_ts":"2026-01-01T00:00:00.000Z",
  "tasks":[{"task_id":"T-001","role":"coder","artifact_globs":["qa/FEAT/T-001-ready-for-review.md"],
             "agent_id":"a_coder","bound_ts":"2026-01-01T00:00:01.000Z","spawn_ts":"2026-01-01T00:00:00.000Z"}]
}')
check "22 unbound path allow (no regression)" allow \
  "$(with_manifest "$M22" run_guard Write "a_z" "$(wi "qa/FEAT/T-999-cycle-1.md")")"

# 23. NO manifest, subagent QA write -> allow (regression floor — matches today's behavior)
rm -f "$STATE/run-manifest.json"
check "23 no manifest subagent allow" allow \
  "$(run_guard Write "a_any" "$(wi "qa/FEAT/T-001-cycle-1.md")")"

# 24. manifest-bound wrong agent via Bash redirect -> deny (Bash-branch parity)
M24=$(jq -cn '{
  "schema":1,"run_id":"t_test","created_by":"test","created_ts":"2026-01-01T00:00:00.000Z",
  "tasks":[{"task_id":"T-001","role":"qa-tester","artifact_globs":["qa/FEAT/T-001-cycle-1.md"],
             "agent_id":"a_qa","bound_ts":"2026-01-01T00:00:01.000Z","spawn_ts":"2026-01-01T00:00:00.000Z"}]
}')
check "24 manifest-bound wrong agent bash redirect deny" deny \
  "$(with_manifest "$M24" run_guard Bash "a_coder" "$(bi "echo x > qa/FEAT/T-001-cycle-1.md")")"

# ---- BUG-ADV2-02: case-insensitive path matching (REQ-02) ----
# Tests 25-28: uppercase variants must deny for main thread, allow for subagent.

# 25. Main thread writes qa/X/CYCLE-1.md (uppercase) → deny
check "25 uppercase CYCLE-1.md main-thread denied" deny \
  "$(run_guard Write "" "$(wi "qa/FEAT-1/T-001-CYCLE-1.md")")"

# 26. Subagent writes qa/X/CYCLE-1.md (uppercase) → allow
check "26 uppercase CYCLE-1.md subagent allowed" allow \
  "$(run_guard Write "agent-abc123" "$(wi "qa/FEAT-1/T-001-CYCLE-1.md")")"

# 27. Main thread writes qa/X/Cycle_1.MD (mixed case) → deny
check "27 mixed-case Cycle_1.MD main-thread denied" deny \
  "$(run_guard Write "" "$(wi "qa/FEAT-1/T-001-Cycle_1.MD")")"

# 28. Subagent writes qa/X/Cycle_1.MD → allow
check "28 mixed-case Cycle_1.MD subagent allowed" allow \
  "$(run_guard Write "agent-abc123" "$(wi "qa/FEAT-1/T-001-Cycle_1.MD")")"

# ---- BUG-ADV2-03: sed -i / dd of= Bash write bypass (REQ-03) ----
# Tests 29-34: sed/dd and related write commands on guarded paths.

# 29. Main thread sed -i targeting a cycle artifact → deny
check "29 sed -i cycle artifact main-thread denied" deny \
  "$(run_guard Bash "" "$(bi "sed -i 's/a/b/' qa/FEAT-1/T-001-cycle-1.md")")"

# 30. Subagent sed -i targeting same artifact → allow
check "30 sed -i cycle artifact subagent allowed" allow \
  "$(run_guard Bash "agent-abc123" "$(bi "sed -i 's/a/b/' qa/FEAT-1/T-001-cycle-1.md")")"

# 31. Main thread dd of=qa/…cycle… → deny
check "31 dd of= cycle artifact main-thread denied" deny \
  "$(run_guard Bash "" "$(bi "dd if=/dev/stdin of=qa/FEAT-1/T-001-cycle-1.md")")"

# 32. Subagent dd of=qa/…cycle… → allow
check "32 dd of= cycle artifact subagent allowed" allow \
  "$(run_guard Bash "agent-abc123" "$(bi "dd if=/dev/stdin of=qa/FEAT-1/T-001-cycle-1.md")")"

# 33. Main thread sed -i with uppercase path (CYCLE-1.md) → deny (BUG-02 + BUG-03 combined)
check "33 sed -i UPPERCASE cycle path main-thread denied" deny \
  "$(run_guard Bash "" "$(bi "sed -i 's/a/b/' qa/FEAT-1/T-001-CYCLE-1.md")")"

# 34. Subagent sed -i with uppercase path → allow
check "34 sed -i UPPERCASE cycle path subagent allowed" allow \
  "$(run_guard Bash "agent-abc123" "$(bi "sed -i 's/a/b/' qa/FEAT-1/T-001-CYCLE-1.md")")"

echo
echo "qa-artifact-ownership-guard: $PASS passed, $FAIL failed"
[[ "$FAIL" -eq 0 ]]
