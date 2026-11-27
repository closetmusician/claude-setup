#!/usr/bin/env bash
# ABOUTME: Waits for one run-stage.sh launch to finish, for at most max_seconds, then prints one line.
# ABOUTME: Not done: prints WAITING. Done with exit 0 and a JSON object on the last output line: prints that line.
# ABOUTME: Any other finish prints {"stage_error": true, "exit_code": N, "out": "<path>"}.
# ABOUTME: Written 2026-11-17 (LO2 improve REQ-01b). Pair script: run-stage.sh.
# ABOUTME: Usage: wait-stage.sh <run_dir> <stage_name> <token> <max_seconds>

set -euo pipefail

if [[ $# -ne 4 || ! "$4" =~ ^[0-9]+$ ]]; then
  echo "Usage: wait-stage.sh <run_dir> <stage_name> <token> <max_seconds>" >&2
  exit 2
fi

RUN_DIR="$1"
STAGE="$2"
TOKEN="$3"
MAX="$4"

OUT="$RUN_DIR/$STAGE.$TOKEN.out"
DONE="$RUN_DIR/$STAGE.$TOKEN.done"

# Poll once a second; SECONDS is the shell's own timer.
start=$SECONDS
while [[ ! -e "$DONE" ]]; do
  if (( SECONDS - start >= MAX )); then
    echo "WAITING"
    exit 0
  fi
  sleep 1
done

python3 - "$DONE" "$OUT" <<'REPORT'
import sys, json
done_path, out_path = sys.argv[1], sys.argv[2]
try:
    code = int(open(done_path).read().strip())
except Exception:
    code = -1

def stage_error():
    print(json.dumps({"stage_error": True, "exit_code": code, "out": out_path}))

if code != 0:
    stage_error()
    sys.exit(0)
try:
    lines = [l for l in open(out_path, errors="replace").read().splitlines() if l.strip()]
    last = lines[-1].strip()
    if isinstance(json.loads(last), dict):
        print(last)
        sys.exit(0)
except Exception:
    pass
stage_error()
REPORT
