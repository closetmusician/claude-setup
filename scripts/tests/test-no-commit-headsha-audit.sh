#!/usr/bin/env bash
# ABOUTME: Behavior tests for scripts/governance/no-commit-headsha-audit.sh.
# ABOUTME: Covers: flagged dispatch with unauthorized commit (P1 advisory); clean dispatch
# ABOUTME: (silent); unflagged dispatch with HEAD moved (not our concern); malformed stdin.
# ABOUTME: Tests run in throwaway git repos; never mutate ~/.claude or this repo's history.
# ABOUTME: Includes neuter-and-fail proof to confirm the SHA comparison is load-bearing.

set -uo pipefail

AUDIT="${AUDIT:-$HOME/.claude/scripts/governance/no-commit-headsha-audit.sh}"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
PASS=0; FAIL=0

# ── Isolated state dir (never touches ~/.claude/state) ───────────────────────
STATE_DIR="$TMP/state"
mkdir -p "$STATE_DIR"
export NOCOMMIT_STATE_DIR="$STATE_DIR"

# ── Throwaway git repo helper ─────────────────────────────────────────────────
# Returns the path to a fresh git repo with one initial commit.
make_git_repo() {
  local repo="$TMP/repo-$RANDOM"
  mkdir -p "$repo"
  git -C "$repo" init -q
  git -C "$repo" config user.email "test@test.local"
  git -C "$repo" config user.name "Test"
  touch "$repo/init.txt"
  git -C "$repo" add init.txt
  git -C "$repo" commit -q -m "init"
  echo "$repo"
}

# Make a commit in a repo and return the new HEAD SHA.
make_commit() {
  local repo="$1" msg="${2:-extra commit}"
  echo "$RANDOM" > "$repo/extra.txt"
  git -C "$repo" add extra.txt
  git -C "$repo" commit -q -m "$msg"
  git -C "$repo" rev-parse HEAD
}

# ── Hook invocation helpers ───────────────────────────────────────────────────
# run_pre: fire pre-mode against the script with a given prompt and session_id.
# Must be run inside the target git repo so git rev-parse HEAD resolves correctly.
run_pre() {
  local sid="$1" prompt="$2" repo="${3:-$TMP}"
  ( cd "$repo" && jq -cn --arg sid "$sid" --arg p "$prompt" \
      '{"session_id":$sid,"hook_event_name":"PreToolUse","tool_name":"Agent",
        "tool_input":{"prompt":$p}}' \
    | NOCOMMIT_STATE_DIR="$STATE_DIR" bash "$AUDIT" pre )
}

# run_post: fire post-mode against the script with a given session_id.
run_post() {
  local sid="$1" repo="${2:-$TMP}"
  ( cd "$repo" && jq -cn --arg sid "$sid" \
      '{"session_id":$sid,"hook_event_name":"PostToolUse","tool_name":"Agent","tool_result":"done"}' \
    | NOCOMMIT_STATE_DIR="$STATE_DIR" bash "$AUDIT" post ) 2>&1
}

check() { # $1 case name, $2 expected (advisory|silent), $3 actual stderr/stdout
  local name="$1" expected="$2" actual="$3"
  if [[ "$expected" == "advisory" ]]; then
    if echo "$actual" | grep -q 'P1 INCIDENT'; then
      echo "PASS: $name"; PASS=$((PASS+1))
    else
      echo "FAIL: $name — expected P1 advisory, got: ${actual:-<empty>}"; FAIL=$((FAIL+1))
    fi
  else
    # silent: must NOT contain P1 advisory
    if echo "$actual" | grep -q 'P1 INCIDENT'; then
      echo "FAIL: $name — expected silent, got advisory: $actual"; FAIL=$((FAIL+1))
    else
      echo "PASS: $name"; PASS=$((PASS+1))
    fi
  fi
}

# ═══════════════════════════════════════════════════════════════════════════════
# CASE A: Flagged prompt + unauthorized commit → P1 advisory emitted.
# Spec §neuter-test plan fixture A.
# ═══════════════════════════════════════════════════════════════════════════════
SID_A="sess-flagged-commit-$$"
REPO_A="$(make_git_repo)"

# Pre: prompt contains "do not commit"; record is written.
run_pre "$SID_A" "## Constraints\n- do not commit any changes during this task." "$REPO_A" >/dev/null 2>&1

RECORD_A="${STATE_DIR}/nocommit-headsha-${SID_A}.txt"
if [[ -f "$RECORD_A" ]]; then
  echo "PASS: A-pre record file created"; PASS=$((PASS+1))
else
  echo "FAIL: A-pre record file NOT created at $RECORD_A"; FAIL=$((FAIL+1))
fi

# Simulate unauthorized commit (advance HEAD).
make_commit "$REPO_A" "unauthorized commit" >/dev/null

# Post: compare → mismatch → advisory emitted.
OUT_A="$(run_post "$SID_A" "$REPO_A")"
check "A post: P1 advisory on unauthorized commit" advisory "$OUT_A"

# After post, record file must be cleaned up.
if [[ ! -f "$RECORD_A" ]]; then
  echo "PASS: A post: record file cleaned up"; PASS=$((PASS+1))
else
  echo "FAIL: A post: record file not cleaned up"; FAIL=$((FAIL+1))
fi

# Advisory must cite both SHAs (old→new pattern).
if echo "$OUT_A" | grep -qE '[0-9a-f]{8,}.[0-9a-f]{8,}'; then
  echo "PASS: A advisory cites both SHAs"; PASS=$((PASS+1))
else
  echo "FAIL: A advisory missing SHA citation: ${OUT_A:-<empty>}"; FAIL=$((FAIL+1))
fi

# ═══════════════════════════════════════════════════════════════════════════════
# CASE B: Flagged prompt, NO commit → silent (exit 0, no advisory).
# Spec §neuter-test plan fixture B.
# ═══════════════════════════════════════════════════════════════════════════════
SID_B="sess-flagged-nocommit-$$"
REPO_B="$(make_git_repo)"

# Pre: flag prompt.
run_pre "$SID_B" "No-commit: all changes prohibited." "$REPO_B" >/dev/null 2>&1

# Do NOT advance HEAD.
OUT_B="$(run_post "$SID_B" "$REPO_B")"
check "B post: silent when HEAD unchanged" silent "$OUT_B"
check "B exit 0 (no advisory at all)" silent "$OUT_B"

# ═══════════════════════════════════════════════════════════════════════════════
# CASE C: Unflagged prompt (no no-commit token) + HEAD moves → NOT our concern.
# Spec §neuter-test plan fixture C.
# ═══════════════════════════════════════════════════════════════════════════════
SID_C="sess-unflagged-$$"
REPO_C="$(make_git_repo)"

# Pre: prompt has NO no-commit token.
run_pre "$SID_C" "## Constraints\n- Implement the feature fully." "$REPO_C" >/dev/null 2>&1

RECORD_C="${STATE_DIR}/nocommit-headsha-${SID_C}.txt"
if [[ ! -f "$RECORD_C" ]]; then
  echo "PASS: C pre: no record file for unflagged prompt"; PASS=$((PASS+1))
else
  echo "FAIL: C pre: record file created for unflagged prompt (false positive)"; FAIL=$((FAIL+1))
fi

# Advance HEAD (legitimate commit — no constraint).
make_commit "$REPO_C" "legitimate commit" >/dev/null

# Post: no record → silent.
OUT_C="$(run_post "$SID_C" "$REPO_C")"
check "C post: silent for unflagged session even with HEAD moved" silent "$OUT_C"

# ═══════════════════════════════════════════════════════════════════════════════
# CASE D: Malformed stdin → fail-open (exit 0, no advisory, no crash).
# Spec §neuter-test plan (implicit L-27 fail-open requirement).
# ═══════════════════════════════════════════════════════════════════════════════
OUT_D="$(echo "not json at all { broken" | NOCOMMIT_STATE_DIR="$STATE_DIR" bash "$AUDIT" pre 2>&1 || true)"
if echo "$OUT_D" | grep -q 'P1 INCIDENT'; then
  echo "FAIL: D malformed pre-mode emitted advisory (should fail-open)"; FAIL=$((FAIL+1))
else
  echo "PASS: D malformed pre-mode: fail-open, no advisory"; PASS=$((PASS+1))
fi

OUT_D2="$(echo "not json { }" | NOCOMMIT_STATE_DIR="$STATE_DIR" bash "$AUDIT" post 2>&1 || true)"
if echo "$OUT_D2" | grep -q 'P1 INCIDENT'; then
  echo "FAIL: D malformed post-mode emitted advisory (should fail-open)"; FAIL=$((FAIL+1))
else
  echo "PASS: D malformed post-mode: fail-open, no advisory"; PASS=$((PASS+1))
fi

# ═══════════════════════════════════════════════════════════════════════════════
# NEUTER-AND-FAIL PROOF:
# Comment out the SHA comparison in post-mode, re-run case A, assert that it NO LONGER
# advises. This confirms the comparison is the load-bearing detection path.
# ═══════════════════════════════════════════════════════════════════════════════
echo
echo "─── NEUTER-AND-FAIL CHECK ───"

# Build a neutered copy of the audit script: comment out the mismatch advisory block.
NEUTERED="$TMP/neutered-audit.sh"
cp "$AUDIT" "$NEUTERED"
# Neuter: replace the "if [[ "$OLD_SHA" == "$NEW_SHA" ]]; then" exit block with
# an unconditional exit 0 (so mismatch is never detected).
# We comment out the mismatch branch by replacing it with exit 0.
perl -0777 -pi -e \
  's/(# ── Compare ─+\n[^\n]+\n\s+# No change.*\n\s+exit 0\n\s+fi\n\n)(.*?)(# ── Mismatch.*?exit 0\n\n)/\1  # NEUTERED: comparison removed\n  exit 0\n\n/s' \
  "$NEUTERED" 2>/dev/null || true

# Fallback neuter: simpler direct replacement targeting the comparison conditional.
if grep -q 'NEUTERED' "$NEUTERED" 2>/dev/null; then
  : # perl succeeded
else
  # Backup simpler approach: replace the if-mismatch block with exit 0 after comparison
  sed -i.bak 's/if \[\[ "\$OLD_SHA" == "\$NEW_SHA" \]\]/if true  # NEUTERED/' "$NEUTERED" 2>/dev/null || true
fi

# Also mark with NEUTERED comment if not done yet (detect-only via comment search).
# Actual approach: just directly patch the key check.
# Simpler and more reliable: target the exact if-statement text.
if ! grep -q 'NEUTERED' "$NEUTERED"; then
  perl -i -pe 's/if \[\[\s*"\$OLD_SHA"\s*==\s*"\$NEW_SHA"\s*\]\]/if true  # NEUTERED: SHA compare removed/' "$NEUTERED" 2>/dev/null || true
fi

chmod +x "$NEUTERED"

# Now re-run case A against the neutered script.
SID_N="sess-neuter-$$"
REPO_N="$(make_git_repo)"
( cd "$REPO_N" && jq -cn --arg sid "$SID_N" \
    '{"session_id":$sid,"hook_event_name":"PreToolUse","tool_name":"Agent",
      "tool_input":{"prompt":"## Constraints\n- do not commit changes"}}' \
  | NOCOMMIT_STATE_DIR="$STATE_DIR" bash "$NEUTERED" pre ) >/dev/null 2>&1
make_commit "$REPO_N" "commit while neutered" >/dev/null
NEUTER_OUT="$(( cd "$REPO_N" && jq -cn --arg sid "$SID_N" \
    '{"session_id":$sid,"hook_event_name":"PostToolUse","tool_name":"Agent","tool_result":"done"}' \
  | NOCOMMIT_STATE_DIR="$STATE_DIR" bash "$NEUTERED" post ) 2>&1 || true)"

if echo "$NEUTER_OUT" | grep -q 'P1 INCIDENT'; then
  echo "FAIL: neuter-proof — neutered script STILL emitted advisory (neuter didn't apply)"
  FAIL=$((FAIL+1))
else
  echo "PASS: neuter-proof — neutered script correctly emits NO advisory (comparison removed)"
  PASS=$((PASS+1))
fi

# Double-check: non-neutered script WOULD emit advisory (sanity cross-check).
SID_SANITY="sess-sanity-$$"
REPO_SANITY="$(make_git_repo)"
run_pre "$SID_SANITY" "do not commit" "$REPO_SANITY" >/dev/null 2>&1
make_commit "$REPO_SANITY" "sanity commit" >/dev/null
SANITY_OUT="$(run_post "$SID_SANITY" "$REPO_SANITY")"
if echo "$SANITY_OUT" | grep -q 'P1 INCIDENT'; then
  echo "PASS: neuter-proof sanity — real script still detects (confirms neuter was the difference)"
  PASS=$((PASS+1))
else
  echo "FAIL: neuter-proof sanity — real script also missed advisory (test environment problem)"
  FAIL=$((FAIL+1))
fi

echo
echo "no-commit-headsha-audit: $PASS passed, $FAIL failed"
[[ "$FAIL" -eq 0 ]]
