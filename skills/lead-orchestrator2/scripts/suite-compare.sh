#!/usr/bin/env bash
# ABOUTME: Runs the test suite at base_ref (temporary git worktree) and at HEAD, then lists tests that fail only at HEAD.
# ABOUTME: Writes <run_dir>/suite-compare.md and caches the base result in <run_dir>/suite-base.txt.
# ABOUTME: Last stdout line: JSON {"ok","inconclusive","regressions","base_exit","head_exit"}.
# ABOUTME: Written 2026-11-17 (LO2 improve REQ-03e, REQ-03f, REQ-03g). Used by lo-feature-task-d.js.
# ABOUTME: Usage: suite-compare.sh <repo> <base_ref> <run_dir> <test_env> <suite_cmd>

set -euo pipefail

if [[ $# -ne 5 ]]; then
  echo "Usage: suite-compare.sh <repo> <base_ref> <run_dir> <test_env> <suite_cmd>" >&2
  exit 2
fi

REPO="$1"
BASE_REF="$2"
RUN_DIR="$3"
TEST_ENV="$4"
SUITE_CMD="$5"

cd "$REPO"
mkdir -p "$RUN_DIR"
RUN_DIR="$(cd "$RUN_DIR" && pwd)"
TOP="$(git rev-parse --show-toplevel)"
BASE_SHA="$(git rev-parse --verify "$BASE_REF^{commit}")"

# Cache key: repo top-level path, resolved base SHA, exact suite_cmd, exact test_env (REQ-03g), as a JSON list so no field can blur into the next.
KEY="$(python3 -c 'import sys, json; print(json.dumps(sys.argv[1:]))' "$TOP" "$BASE_SHA" "$SUITE_CMD" "$TEST_ENV" | shasum -a 256 | cut -d' ' -f1)"
CACHE="$RUN_DIR/suite-base.txt"

# Purpose: print the failing test ids found in one suite output file, as a sorted JSON list.
# Usage:   ids=$(failing_ids <file>)
# Gotchas: matches pytest "FAILED|ERROR <id>", TAP "not ok <n> <name>" and the LO2 form "not ok - <name>".
#          Lines with "# TODO" or "# SKIP" are not failures. Colour codes are stripped first.
failing_ids() {
  python3 - "$1" <<'IDS_PY'
import sys, re, json
text = open(sys.argv[1], errors="replace").read()
text = re.sub(r"\x1b\[[0-9;]*m", "", text)
ids = set()
for line in text.splitlines():
    m = re.match(r"^(?:FAILED|ERROR) (\S+)", line)
    if m:
        ids.add(m.group(1))
        continue
    m = re.match(r"^not ok(?: \d+)?(?: -)? (.+?)\s*$", line)
    if m and not re.search(r"#\s*(TODO|SKIP)", m.group(1), re.I):
        ids.add(m.group(1))
print(json.dumps(sorted(ids)))
IDS_PY
}

# Purpose: print the cached base result as "<exit> <ids json>" when the cache is valid, else nothing.
# Usage:   cached=$(read_cache)
# Gotchas: valid means the key matches and the "finished: yes" line is present (it is written last).
read_cache() {
  [[ -f "$CACHE" ]] || return 0
  python3 - "$CACHE" "$KEY" <<'CACHE_PY'
import sys
f = {}
for line in open(sys.argv[1], errors="replace"):
    k, _, v = line.rstrip("\n").partition(": ")
    f[k] = v
if f.get("key") == sys.argv[2] and f.get("finished") == "yes" and "exit" in f and "ids" in f:
    print(f["exit"], f["ids"])
CACHE_PY
}

# Purpose: run the suite once in a directory, saving combined output to a file.
# Usage:   rc=$(run_suite <dir> <out_file>)
# Gotchas: test_env is a command prefix such as "A=1 B=2". Prints only the exit code on stdout.
run_suite() {
  local rc=0
  ( cd "$1" && bash -c "$TEST_ENV $SUITE_CMD" ) > "$2" 2>&1 < /dev/null || rc=$?
  echo "$rc"
}

BASE_OUT="$RUN_DIR/suite-base.out"
HEAD_OUT="$RUN_DIR/suite-head.out"
BASE_CACHED=0
BASE_NOTE=""

cached="$(read_cache)"
if [[ -n "$cached" ]]; then
  BASE_CACHED=1
  BASE_EXIT="${cached%% *}"
  BASE_IDS="${cached#* }"
else
  WT_PARENT="$(mktemp -d "${TMPDIR:-/tmp}/suite-base.XXXXXX")"
  WT="$WT_PARENT/wt"
  # Always remove the temporary worktree, also when the suite or this script fails.
  cleanup() {
    git -C "$TOP" worktree remove --force "$WT" > /dev/null 2>&1 || true
    rm -rf "$WT_PARENT"
    git -C "$TOP" worktree prune > /dev/null 2>&1 || true
  }
  trap cleanup EXIT
  if git -C "$TOP" worktree add --detach "$WT" "$BASE_SHA" > /dev/null 2>&1; then
    BASE_EXIT="$(run_suite "$WT" "$BASE_OUT")"
  else
    BASE_EXIT=-1
    BASE_NOTE="git worktree add failed for $BASE_SHA"
    : > "$BASE_OUT"
  fi
  BASE_IDS="$(failing_ids "$BASE_OUT")"
  # Cache only a conclusive run: a crash with no failing ids must run again next time.
  if [[ "$BASE_EXIT" = 0 || "$BASE_IDS" != "[]" ]]; then
    {
      echo "key: $KEY"
      echo "top: $TOP"
      echo "base_sha: $BASE_SHA"
      echo "cmd: ${SUITE_CMD//$'\n'/ }"
      echo "env: ${TEST_ENV//$'\n'/ }"
      echo "exit: $BASE_EXIT"
      echo "ids: $BASE_IDS"
      echo "finished: yes"
    } > "$CACHE.tmp"
    mv "$CACHE.tmp" "$CACHE"
  fi
fi

HEAD_EXIT="$(run_suite "$REPO" "$HEAD_OUT")"
HEAD_IDS="$(failing_ids "$HEAD_OUT")"

python3 - "$BASE_EXIT" "$HEAD_EXIT" "$BASE_IDS" "$HEAD_IDS" "$BASE_OUT" "$RUN_DIR" "$BASE_CACHED" "$BASE_SHA" "$BASE_NOTE" <<'COMPARE_PY'
import sys, json, re
base_exit, head_exit = int(sys.argv[1]), int(sys.argv[2])
base_ids, head_ids = json.loads(sys.argv[3]), json.loads(sys.argv[4])
base_out, run_dir, cached, base_sha, base_note = sys.argv[5], sys.argv[6], sys.argv[7] == "1", sys.argv[8], sys.argv[9]

# A non-zero run that prints no failing id is inconclusive (for example a crash before the summary).
base_inconclusive = base_exit != 0 and not base_ids
head_inconclusive = head_exit != 0 and not head_ids
inconclusive = base_inconclusive or head_inconclusive
# A regression fails at HEAD but not at base. Ids that fail at both (for example missing local inputs) are not regressions.
regressions = [] if base_inconclusive else [i for i in head_ids if i not in base_ids]
both = [i for i in head_ids if i in base_ids]

notes = []
if base_note:
    notes.append(base_note)
if cached:
    notes.append("base result came from the cache suite-base.txt")
try:
    base_text = open(base_out, errors="replace").read() if not cached else ""
except Exception:
    base_text = ""
if both and re.search(r"No such file|FileNotFoundError|file not found", base_text, re.I):
    notes.append("base output shows missing-file errors; ids that fail at both base and HEAD are not regressions")

lines = [
    "# Suite compare",
    "",
    f"- base commit: {base_sha}",
    f"- base exit code: {base_exit}" + (" (cached)" if cached else ""),
    f"- HEAD exit code: {head_exit}",
    f"- regressions (fail at HEAD, pass at base): {len(regressions)}",
]
lines += [f"  - {i}" for i in regressions]
lines.append(f"- fail at both base and HEAD (not regressions): {len(both)}")
lines += [f"  - {i}" for i in both]
if base_inconclusive:
    lines.append("- INCONCLUSIVE: the base run exited non-zero and printed no failing test id.")
if head_inconclusive:
    lines.append("- INCONCLUSIVE: the HEAD run exited non-zero and printed no failing test id. See suite-head.out.")
lines += [f"- note: {n}" for n in notes]
open(run_dir + "/suite-compare.md", "w").write("\n".join(lines) + "\n")

print(json.dumps({
    "ok": not regressions and not inconclusive,
    "inconclusive": inconclusive,
    "regressions": regressions,
    "base_exit": base_exit,
    "head_exit": head_exit,
}))
COMPARE_PY
