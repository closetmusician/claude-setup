#!/usr/bin/env bash
# ABOUTME: Starts one stage command in the background, in its own process group, and returns a launch token at once.
# ABOUTME: Output goes to <run_dir>/<stage>.<token>.out and the exit code to <run_dir>/<stage>.<token>.done.
# ABOUTME: Records "<pgid> <stage> <token> <start time>" in <run_dir>/.run-pids and kills a live earlier launch of the same stage.
# ABOUTME: Written 2026-11-17 (LO2 improve REQ-01a, REQ-01e). Pair script: wait-stage.sh.
# ABOUTME: Usage: run-stage.sh <run_dir> <stage_name> -- <command...>   (stdout = the token only)

set -euo pipefail

if [[ $# -lt 4 || "$3" != "--" ]]; then
  echo "Usage: run-stage.sh <run_dir> <stage_name> -- <command...>" >&2
  exit 2
fi

RUN_DIR="$1"
STAGE="$2"
shift 3

if [[ ! "$STAGE" =~ ^[A-Za-z0-9_-]+$ ]]; then
  echo "run-stage.sh: stage_name may hold only letters, digits, _ and -" >&2
  exit 2
fi

mkdir -p "$RUN_DIR"
PIDS="$RUN_DIR/.run-pids"

# Purpose: print the start time of one process as one trimmed line, or nothing when it is gone.
# Usage:   start_time <pid>
# Gotchas: ps pads the time with spaces, so runs of spaces collapse to one. Always exits 0 (set -e safe).
start_time() {
  ps -o lstart= -p "$1" 2>/dev/null | tr -s ' ' | sed 's/^ //; s/ $//' || true
}

# Purpose: stop an earlier launch of this stage that still runs, so it cannot write late.
# Usage:   kill_live_launches   (reads $PIDS, uses $STAGE and $RUN_DIR)
# Gotchas: checks liveness whether or not .done exists (a finished wrapper can leave children).
#          Before any signal it re-reads the group leader's start time and skips the record when the
#          time differs (pid reuse). A record with start time "unknown" checks group liveness only. A gone leader with live members is safe: the kernel keeps the pgid.
#          Never signals pgid 0, 1 or this script's own group. TERM first, KILL after 5 s.
#          Writes 143 to .done only when no .done exists. Logs to times.txt.
kill_live_launches() {
  [[ -f "$PIDS" ]] || return 0
  local pgid stage tok lstart cur own i
  own="$(ps -o pgid= -p $$ 2>/dev/null | tr -d ' ' || true)"
  while read -r pgid stage tok lstart; do
    [[ "$stage" = "$STAGE" && -n "$tok" && -n "$lstart" ]] || continue
    [[ "$pgid" =~ ^[0-9]+$ ]] || continue
    (( pgid > 1 )) || continue
    [[ "$pgid" != "$own" ]] || continue
    kill -0 -- "-$pgid" 2>/dev/null || continue
    cur="$(start_time "$pgid")"
    [[ "$lstart" = "unknown" || -z "$cur" || "$cur" = "$lstart" ]] || continue
    kill -TERM -- "-$pgid" 2>/dev/null || true
    for i in 1 2 3 4 5 6 7 8 9 10; do
      kill -0 -- "-$pgid" 2>/dev/null || break
      sleep 0.5
    done
    if kill -0 -- "-$pgid" 2>/dev/null; then
      kill -KILL -- "-$pgid" 2>/dev/null || true
    fi
    [[ -e "$RUN_DIR/$STAGE.$tok.done" ]] || echo 143 > "$RUN_DIR/$STAGE.$tok.done"
    date -u +"%FT%TZ run-stage killed live $STAGE launch $tok (pgid $pgid)" >> "$RUN_DIR/times.txt"
  done < "$PIDS"
}

kill_live_launches

TOKEN="$(date +%s)-$RANDOM$RANDOM"
OUT="$RUN_DIR/$STAGE.$TOKEN.out"
DONE="$RUN_DIR/$STAGE.$TOKEN.done"

# perl makes the child a group leader (macOS has no setsid), writes its OWN start time to a file, then runs the wrapper shell.
# The wrapper writes the exit code to a temp file and renames it, so wait-stage never reads half a file.
# The own start time cannot be lost when the command exits before the parent runs ps.
STARTFILE="$RUN_DIR/$STAGE.$TOKEN.start"
perl -e '
  setpgrp(0, 0);
  my $file = shift @ARGV;
  my $t = `ps -o lstart= -p $$ 2>/dev/null`;
  $t =~ s/\s+/ /g; $t =~ s/^ //; $t =~ s/ $//;
  if ($t ne "" && open(my $fh, ">", "$file.tmp")) { print $fh "$t\n"; close $fh; rename "$file.tmp", $file; }
  exec @ARGV;
' "$STARTFILE" bash -c '
  out="$1"; done="$2"; shift 2
  "$@" > "$out" 2>&1 < /dev/null
  rc=$?
  echo "$rc" > "$done.tmp" && mv "$done.tmp" "$done"
' stage-wrapper "$OUT" "$DONE" "$@" > /dev/null 2>&1 < /dev/null &
PGID=$!
disown "$PGID" 2>/dev/null || true

# Wait up to 5 s for the launched process to record its start time. Never write an empty start time.
LSTART=""
for i in $(seq 1 50); do
  [[ -s "$STARTFILE" ]] && { LSTART="$(cat "$STARTFILE")"; break; }
  sleep 0.1
done
if [[ -z "$LSTART" ]]; then
  LSTART="unknown"
  date -u +"%FT%TZ run-stage: no start time for $STAGE launch $TOKEN, recorded as unknown" >> "$RUN_DIR/times.txt"
fi
rm -f "$STARTFILE"

echo "$PGID $STAGE $TOKEN $LSTART" >> "$PIDS"
date -u +"%FT%TZ run-stage started $STAGE token $TOKEN (pgid $PGID)" >> "$RUN_DIR/times.txt"

echo "$TOKEN"
