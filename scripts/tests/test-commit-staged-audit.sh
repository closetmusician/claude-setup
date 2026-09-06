#!/usr/bin/env bash
# ABOUTME: Behavior tests for scripts/commit-staged-audit.sh (PreToolUse/Bash hook).
# ABOUTME: Covers: staged secret → BLOCK; clean commit → ALLOW; non-commit cmd → ALLOW;
# ABOUTME: malformed stdin → fail-open; missing scanner → fail-open; neuter check.
# ABOUTME: Field names derived from git-safety-hook.sh (known-correct PreToolUse consumer).
# ABOUTME: All fixtures drive the REAL stdin contract (tool_name + tool_input.command + cwd).

set -uo pipefail

HOOK="${HOOK:-$HOME/.claude/scripts/commit-staged-audit.sh}"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
PASS=0; FAIL=0

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

# Returns a fake GitHub PAT constructed at runtime so this source file never
# contains the literal pattern that secret-scan.sh blocks (ghp_ + 30+ chars).
# Split across two string literals joined by concatenation — scanner-safe at rest,
# byte-identical to the real pattern at runtime.
fake_pat() {
  local prefix="ghp_" suffix="ABCDEFGHIJKLMNOPQRSTUVWXYZabcdef"
  printf '%s%s' "$prefix" "$suffix"
}

# Build a minimal temp git repo at $1 and stage a file with content $2.
# Prints the repo path on stdout.
make_repo_with_staged() {
  local dir="$1" content="$2"
  git init -q "$dir"
  git -C "$dir" config user.email "test@test.com"
  git -C "$dir" config user.name "Test"
  printf '%s\n' "$content" > "$dir/secret.txt"
  git -C "$dir" add secret.txt
  echo "$dir"
}

# Feed a PreToolUse/Bash stdin payload to the hook.
# $1 = git command string, $2 = cwd for the payload
run_hook() {
  local cmd="$1" cwd="$2"
  jq -cn --arg cmd "$cmd" --arg cwd "$cwd" \
    '{"tool_name":"Bash","tool_input":{"command":$cmd},"cwd":$cwd}' \
  | bash "$HOOK"
}

# Assertion helper.
check() {
  local name="$1" want="$2" actual="$3"
  # Match both compact ("deny") and pretty-printed ("deny") JSON — jq may add spaces.
  if [[ "$want" == "block" ]]; then
    if printf '%s' "$actual" | grep -qE '"permissionDecision"[[:space:]]*:[[:space:]]*"deny"'; then
      echo "PASS: $name"; PASS=$((PASS+1))
    else
      echo "FAIL: $name — expected deny, got: ${actual:-<empty>}"; FAIL=$((FAIL+1))
    fi
  else
    if printf '%s' "$actual" | grep -qE '"permissionDecision"[[:space:]]*:[[:space:]]*"deny"'; then
      echo "FAIL: $name — expected allow, got block: $actual"; FAIL=$((FAIL+1))
    else
      echo "PASS: $name"; PASS=$((PASS+1))
    fi
  fi
}

# ---------------------------------------------------------------------------
# Test 1 — Fixture A (deny): staged file contains a secret → BLOCK
# ---------------------------------------------------------------------------
REPO1="$TMP/repo1"
# Use a GitHub PAT pattern that the scanner's regex matches (built at runtime via fake_pat).
make_repo_with_staged "$REPO1" "token=$(fake_pat)" > /dev/null
OUT1="$(run_hook "git commit -m 'test commit'" "$REPO1" 2>/dev/null; true)"
check "1 staged secret → BLOCK" block "$OUT1"

# Also verify the denial message cites the staged file name.
if printf '%s' "$OUT1" | grep -q 'secret\.txt'; then
  echo "PASS: 1b deny message names the file"; PASS=$((PASS+1))
else
  echo "FAIL: 1b deny message does not name the file; got: $OUT1"; FAIL=$((FAIL+1))
fi

# ---------------------------------------------------------------------------
# Test 2 — Fixture B (allow): staged clean file → ALLOW
# ---------------------------------------------------------------------------
REPO2="$TMP/repo2"
make_repo_with_staged "$REPO2" "hello world — no secrets here" > /dev/null
OUT2="$(run_hook "git commit -m 'clean commit'" "$REPO2" 2>/dev/null; true)"
check "2 clean staged file → ALLOW" pass "$OUT2"

# ---------------------------------------------------------------------------
# Test 3 — Fixture C (allow): non-commit git command → ALLOW (no trigger)
# ---------------------------------------------------------------------------
REPO3="$TMP/repo3"
make_repo_with_staged "$REPO3" "token=$(fake_pat)" > /dev/null
OUT3="$(run_hook "git status" "$REPO3" 2>/dev/null; true)"
check "3 git status (non-commit) → ALLOW (fast-path)" pass "$OUT3"

# ---------------------------------------------------------------------------
# Test 4 — Malformed stdin → fail-open (exit 0)
# ---------------------------------------------------------------------------
EXIT4=0
printf 'this is not json at all' | bash "$HOOK" > /dev/null 2>&1 || EXIT4=$?
if [[ "$EXIT4" -eq 0 ]]; then
  echo "PASS: 4 malformed stdin → fail-open exit 0"; PASS=$((PASS+1))
else
  echo "FAIL: 4 malformed stdin exited $EXIT4 (expected 0)"; FAIL=$((FAIL+1))
fi

# ---------------------------------------------------------------------------
# Test 5 — Missing scanner → fail-open (exit 0, no block)
# ---------------------------------------------------------------------------
REPO5="$TMP/repo5"
make_repo_with_staged "$REPO5" "token=$(fake_pat)" > /dev/null
EXIT5=0
OUT5="$(SCANNER="/nonexistent/scanner-$(date +%s).sh" run_hook "git commit -m 'test'" "$REPO5" 2>/dev/null; true)" || EXIT5=$?
if [[ "$EXIT5" -eq 0 ]] && ! printf '%s' "$OUT5" | grep -q '"permissionDecision":"deny"'; then
  echo "PASS: 5 missing scanner → fail-open ALLOW"; PASS=$((PASS+1))
else
  echo "FAIL: 5 missing scanner exit=$EXIT5 out=${OUT5:-<empty>}"; FAIL=$((FAIL+1))
fi

# Confirm the warning was logged to stderr.
WARN5="$(SCANNER="/nonexistent/scanner-$(date +%s).sh" run_hook "git commit -m 'test'" "$REPO5" 2>&1 >/dev/null || true)"
if printf '%s' "$WARN5" | grep -q 'fail-open\|scanner not found'; then
  echo "PASS: 5b missing scanner logs warning to stderr"; PASS=$((PASS+1))
else
  echo "FAIL: 5b expected fail-open warning in stderr, got: ${WARN5:-<empty>}"; FAIL=$((FAIL+1))
fi

# ---------------------------------------------------------------------------
# Neuter-and-fail check (per PKT-JD-02 spec §Neuter-and-fail test plan step 4)
# Comment out the scanner invocation; Fixture A MUST now allow (suite MUST fail case 1).
# ---------------------------------------------------------------------------
echo
echo "--- NEUTER-AND-FAIL CHECK ---"
NEUTERED_HOOK="$TMP/commit-staged-audit-neutered.sh"
# Create a copy of the hook with the $SCANNER call replaced with 'true' (no-op).
sed 's|"$SCANNER" "${STAGED_FILES\[@\]}"|true|g' "$HOOK" > "$NEUTERED_HOOK"
chmod +x "$NEUTERED_HOOK"

# Re-run Fixture A (staged secret) against the neutered hook directly.
NEUTER_OUT="$(jq -cn --arg cmd "git commit -m 'test commit'" --arg cwd "$REPO1" \
  '{"tool_name":"Bash","tool_input":{"command":$cmd},"cwd":$cwd}' \
  | bash "$NEUTERED_HOOK" 2>/dev/null; true)"
if ! printf '%s' "$NEUTER_OUT" | grep -qE '"permissionDecision"[[:space:]]*:[[:space:]]*"deny"'; then
  echo "PASS: neuter-and-fail confirmed — neutered hook ALLOWS the secret commit (scanner call was the enforcer)"
  PASS=$((PASS+1))
else
  echo "FAIL: neuter-and-fail — neutered hook still denies; something other than the scanner call is blocking"
  FAIL=$((FAIL+1))
fi

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
echo
echo "commit-staged-audit: $PASS passed, $FAIL failed"
[[ "$FAIL" -eq 0 ]]
