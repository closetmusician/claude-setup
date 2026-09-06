#!/usr/bin/env bash
# ABOUTME: TDD test suite for scripts/check-rule-drift.sh (Pillar V, task V8).
# ABOUTME: Tests cross-repo rule-drift detection: same header + divergent body → incident;
# ABOUTME: identical body → no incident; header unique to one repo → no incident;
# ABOUTME: same-day dedupe → 0 new incidents; unreadable repo dir → exit 0.
# ABOUTME: Run: bash scripts/tests/test-check-rule-drift.sh — RED first, then GREEN.

set -uo pipefail

SCRIPT="${SCRIPT_OVERRIDE:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/check-rule-drift.sh}"

PASS=0
FAIL=0

_ok() {
  PASS=$(( PASS + 1 ))
  echo "  PASS: $1"
}

_fail() {
  FAIL=$(( FAIL + 1 ))
  echo "  FAIL: $1${2:+ — $2}"
}

_assert_eq() {
  local label="$1" got="$2" want="$3"
  if [[ "$got" == "$want" ]]; then
    _ok "$label"
  else
    _fail "$label" "got='$got' want='$want'"
  fi
}

_assert_ge() {
  local label="$1" got="$2" want="$3"
  if [[ "$got" -ge "$want" ]]; then
    _ok "$label"
  else
    _fail "$label" "got='$got' want>='$want'"
  fi
}

# Count rule-drift incidents in events file — returns integer, handles grep -c exit 1 on 0 matches
_count_drift() {
  local f="$1"
  # grep -c exits 1 on 0 matches; capture count then discard exit code
  { grep -c '"rule-drift"' "$f" 2>/dev/null; true; } | tail -1
}

echo ""
echo "========================================================================"
echo "check-rule-drift test suite (Pillar V, task V8)"
echo "========================================================================"

# ════════════════════════════════════════════════════════════════════════════
# ORACLE 1 — Same header, divergent body → exactly 1 rule-drift incident + hoist line
# Two fixture repos with an identical section header but different body content.
# Must emit exactly 1 rule-drift incident and append exactly 1 hoist line to report.
echo ""
echo "── Oracle 1: same header + divergent body → 1 incident + 1 hoist line ───"

T1="$(mktemp -d /tmp/crd-t1-XXXXXX)"
mkdir -p "$T1/state/state"
EVENTS_FILE="$T1/state/state/events.ndjson"
touch "$EVENTS_FILE"

# Create two fixture repos
REPO_A="$T1/repos/alpha"
REPO_B="$T1/repos/beta"
mkdir -p "$REPO_A" "$REPO_B"

cat > "$REPO_A/CLAUDE.md" <<'EOF'
# Alpha Project

## No sycophancy
Never say "You're absolutely right!" or otherwise flatter.
Be honest and push back when needed.

## Another Section
Some other content here unique to alpha.
EOF

cat > "$REPO_B/CLAUDE.md" <<'EOF'
# Beta Project

## No sycophancy
Always be honest. Never use flattery. Push back on bad ideas.
This is a different wording from alpha.

## Beta Only Section
Unique to beta repo.
EOF

REPORT_FILE="$T1/state/rule-drift-report.txt"

out1="$(EVENTS="$EVENTS_FILE" STATE="$T1/state" REPO_GLOB_ROOT="$T1/repos" RULE_DRIFT_REPORT="$REPORT_FILE" bash "$SCRIPT" 2>&1)" || true
exit1=$?
_assert_eq "exit 0 on divergent body" "$exit1" "0"

incident_count1="$(_count_drift "$EVENTS_FILE")"
_assert_eq "exactly 1 rule-drift incident emitted" "$incident_count1" "1"

hoist_count1="$(grep -c 'hoist candidate' "$REPORT_FILE" 2>/dev/null || echo 0)"
_assert_ge "at least 1 hoist candidate in report" "$hoist_count1" "1"

header_in_incident="$(python3 -c "
import sys, json
with open('$EVENTS_FILE') as f:
    for line in f:
        line = line.strip()
        if not line: continue
        try:
            e = json.loads(line)
            if e.get('event_type') == 'incident' and e.get('payload', {}).get('class') == 'rule-drift':
                d = e['payload'].get('detail', '')
                if 'no sycophancy' in d.lower() or 'No sycophancy' in d:
                    print('yes')
                    sys.exit(0)
        except Exception:
            pass
print('no')
" 2>/dev/null || echo "no")"
_assert_eq "incident detail mentions the diverged header" "$header_in_incident" "yes"

rm -rf "$T1"

# ════════════════════════════════════════════════════════════════════════════
# ORACLE 2 — Same header, identical body → 0 incidents
# Two repos with exactly the same section content → no drift detected.
echo ""
echo "── Oracle 2: same header + identical body → 0 incidents ────────────────"

T2="$(mktemp -d /tmp/crd-t2-XXXXXX)"
mkdir -p "$T2/state/state"
EVENTS2="$T2/state/state/events.ndjson"
touch "$EVENTS2"
REPO_A2="$T2/repos/gamma"
REPO_B2="$T2/repos/delta"
mkdir -p "$REPO_A2" "$REPO_B2"

SHARED_CONTENT='## No sycophancy
Never say "You'"'"'re absolutely right!" or otherwise flatter.
Be honest and push back when needed.'

printf '# Gamma\n\n%s\n' "$SHARED_CONTENT" > "$REPO_A2/CLAUDE.md"
printf '# Delta\n\n%s\n' "$SHARED_CONTENT" > "$REPO_B2/CLAUDE.md"

REPORT2="$T2/state/rule-drift-report.txt"
EVENTS="$EVENTS2" STATE="$T2/state" REPO_GLOB_ROOT="$T2/repos" RULE_DRIFT_REPORT="$REPORT2" bash "$SCRIPT" 2>&1 || true
incident_count2="$(_count_drift "$EVENTS2")"
_assert_eq "identical body → 0 incidents" "$incident_count2" "0"

rm -rf "$T2"

# ════════════════════════════════════════════════════════════════════════════
# ORACLE 3 — Header unique to one repo → 0 incidents
# A section that appears in only one repo cannot drift → no incident.
echo ""
echo "── Oracle 3: header unique to one repo → 0 incidents ───────────────────"

T3="$(mktemp -d /tmp/crd-t3-XXXXXX)"
mkdir -p "$T3/state/state"
EVENTS3="$T3/state/state/events.ndjson"
touch "$EVENTS3"
REPO_A3="$T3/repos/epsilon"
REPO_B3="$T3/repos/zeta"
mkdir -p "$REPO_A3" "$REPO_B3"

cat > "$REPO_A3/CLAUDE.md" <<'EOF'
# Epsilon

## Unique To Epsilon Only
This section exists only in epsilon, so it cannot drift.
EOF

cat > "$REPO_B3/CLAUDE.md" <<'EOF'
# Zeta

## Unique To Zeta Only
Completely different section. No overlap with epsilon headers.
EOF

REPORT3="$T3/state/rule-drift-report.txt"
EVENTS="$EVENTS3" STATE="$T3/state" REPO_GLOB_ROOT="$T3/repos" RULE_DRIFT_REPORT="$REPORT3" bash "$SCRIPT" 2>&1 || true
incident_count3="$(_count_drift "$EVENTS3")"
_assert_eq "unique header → 0 incidents" "$incident_count3" "0"

rm -rf "$T3"

# ════════════════════════════════════════════════════════════════════════════
# ORACLE 4 — Same-day re-run → 0 new incidents (idempotent dedupe)
# Seed the events file with an existing rule-drift incident from today.
# Running the script again must NOT emit a duplicate incident.
echo ""
echo "── Oracle 4: same-day re-run → 0 new incidents (dedupe) ────────────────"

T4="$(mktemp -d /tmp/crd-t4-XXXXXX)"
mkdir -p "$T4/state/state"
EVENTS4="$T4/state/state/events.ndjson"
REPO_A4="$T4/repos/eta"
REPO_B4="$T4/repos/theta"
mkdir -p "$REPO_A4" "$REPO_B4"

cat > "$REPO_A4/CLAUDE.md" <<'EOF'
# Eta

## Coding standards
Write clean code always. No hacks.
EOF

cat > "$REPO_B4/CLAUDE.md" <<'EOF'
# Theta

## Coding standards
Write clean code. Avoid hacks. Review before merging.
EOF

TODAY="$(python3 -c "from datetime import datetime, timezone; print(datetime.now(timezone.utc).strftime('%Y-%m-%dT%H:%M:%S.000Z'))")"

# Pre-seed with existing incident for same header+repo pair
cat > "$EVENTS4" <<EOF
{"ts":"${TODAY}","schema":1,"session_id":"unknown","event_type":"incident","source":"check-rule-drift.sh","project":".claude","payload":{"severity":"P2","class":"rule-drift","detail":"section 'coding standards' diverges between $REPO_A4 and $REPO_B4"},"tool":null,"skill":null,"outcome":null,"evidence_ref":null,"trace_id":null}
EOF

lines_before4="$(wc -l < "$EVENTS4")"
REPORT4="$T4/state/rule-drift-report.txt"
EVENTS="$EVENTS4" STATE="$T4/state" REPO_GLOB_ROOT="$T4/repos" RULE_DRIFT_REPORT="$REPORT4" bash "$SCRIPT" 2>&1 || true
lines_after4="$(wc -l < "$EVENTS4")"

new_incidents4=$(( lines_after4 - lines_before4 ))
_assert_eq "same-day re-run emits 0 new incidents" "$new_incidents4" "0"

rm -rf "$T4"

# ════════════════════════════════════════════════════════════════════════════
# ORACLE 5 — Unreadable / empty repo dir → exit 0 (fail-open)
# A repo glob root that is empty or has unreadable files must not crash the script.
echo ""
echo "── Oracle 5: unreadable/empty repo dir → exit 0 ────────────────────────"

T5="$(mktemp -d /tmp/crd-t5-XXXXXX)"
mkdir -p "$T5/state/state"
EVENTS5="$T5/state/state/events.ndjson"
touch "$EVENTS5"

# Empty root — no CLAUDE.md files at all
EMPTY_ROOT="$T5/empty_repos"
mkdir -p "$EMPTY_ROOT"

REPORT5="$T5/state/rule-drift-report.txt"
out5="$(EVENTS="$EVENTS5" STATE="$T5/state" REPO_GLOB_ROOT="$EMPTY_ROOT" RULE_DRIFT_REPORT="$REPORT5" bash "$SCRIPT" 2>&1)" || true
exit5=$?
_assert_eq "empty repo root → exit 0" "$exit5" "0"

# No incidents in empty root
incident_count5="$(_count_drift "$EVENTS5")"
_assert_eq "empty repo root → 0 incidents" "$incident_count5" "0"

rm -rf "$T5"

# ════════════════════════════════════════════════════════════════════════════
echo ""
echo "========================================================================"
echo "Results: PASS=$PASS  FAIL=$FAIL  (total=$(( PASS + FAIL )))"
echo "========================================================================"
echo ""

if [[ "$FAIL" -gt 0 ]]; then
  exit 1
fi
exit 0
