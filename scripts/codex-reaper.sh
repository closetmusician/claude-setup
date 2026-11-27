#!/bin/bash
# ABOUTME: Stops leaked Codex process trees: codex app-servers, plugin brokers and orphaned Codex tool servers.
# ABOUTME: Each Codex job starts tool servers (node_repl, MCP servers) that never exit; they pile up into thousands.
# ABOUTME: A tree is stopped only if its root is older than MIN_AGE_H hours AND it used no CPU time during IDLE_S seconds.
# ABOUTME: Run hourly by ~/Library/LaunchAgents/com.yklin.codex-reaper.plist. Log: ~/.claude/state/codex-reaper.log.
# ABOUTME: Dry run: DRY_RUN=1 bash codex-reaper.sh (lists the trees, stops nothing).
set -u
MIN_AGE_H=${MIN_AGE_H:-6}
IDLE_S=${IDLE_S:-15}
DRY_RUN=${DRY_RUN:-0}
LOG=${LOG:-$HOME/.claude/state/codex-reaper.log}
mkdir -p "$(dirname "$LOG")"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
ROOT_RE=${ROOT_RE:-'app-server-broker\.mjs|bin/codex app-server'}
ORPHAN_RE=${ORPHAN_RE:-'node_repl|chrome-devtools-mcp|cua-repl'}

# Purpose: write a process snapshot: pid ppid etime cputime-centiseconds args.
# Usage:   snap FILE
# Gotchas: macOS ps has no etimes; cputime is "[dd-][hh:]mm:ss.cc" and becomes hundredths of a second here.
snap() {
  ps -Ao pid=,ppid=,etime=,time=,args= | awk '{
    t=$4; d=0; if (index(t,"-")) { split(t,x,"-"); d=x[1]; t=x[2] }
    n=split(t,a,":"); s=0; for (i=1;i<=n;i++) s=s*60+a[i]; $4=int((d*86400+s)*100+0.5); print }' > "$1"
}

# Purpose: print the start time of a pid (empty if gone).
# Usage:   started 1234
# Gotchas: used to prove a pid still names the same process before a signal (pid reuse).
started() { ps -o lstart= -p "$1" 2>/dev/null; }

# Purpose: turn an etime value ([[dd-]hh:]mm:ss) into seconds.
# Usage:   secs 01-02:03:04  ->  93784
# Gotchas: leading zeros are forced to base 10.
secs() {
  local e=$1 d=0 h=0 m=0 s=0 a b c
  [[ $e == *-* ]] && { d=${e%%-*}; e=${e#*-}; }
  IFS=: read -r a b c <<< "$e"
  if [ -n "$c" ]; then h=$a; m=$b; s=$c; else m=$a; s=$b; fi
  echo $(( 10#$d*86400 + 10#$h*3600 + 10#$m*60 + 10#$s ))
}

# Purpose: print a pid and every descendant pid from a snapshot file.
# Usage:   tree FILE 1234
# Gotchas: a process born after the snapshot is missed; the fresh snapshot just before the kill limits this.
tree() {
  local c
  echo "$2"
  for c in $(awk -v p="$2" '$2==p{print $1}' "$1"); do tree "$1" "$c"; done
}

# Purpose: true if any ancestor of a pid is itself a root candidate.
# Usage:   has_root_ancestor FILE 1234
# Gotchas: stops at pid 1 or at a pid missing from the snapshot.
has_root_ancestor() {
  local p
  p=$(awk -v q="$2" '$1==q{print $2}' "$1")
  while [ -n "$p" ] && [ "$p" -gt 1 ]; do
    awk -v q="$p" -v re="$ROOT_RE" '$1==q && $0 ~ re {f=1} END{exit !f}' "$1" && return 0
    p=$(awk -v q="$p" '$1==q{print $2}' "$1")
  done
  return 1
}

# Purpose: total CPU time (hundredths of a second) used by a list of pids in a snapshot.
# Usage:   cpu_sum FILE "1 2 3"
cpu_sum() { awk -v l="$2" 'BEGIN{n=split(l,a," "); for(i=1;i<=n;i++) w[a[i]]=1} ($1 in w){t+=$4} END{print t+0}' "$1"; }

# 1. First snapshot. Roots: brokers and app-servers with no root ancestor, plus orphaned tool servers.
snap "$TMP/s1"
ROOTS=""
while read -r pid ppid et rest; do
  [ "$(secs "$et")" -lt $(( MIN_AGE_H * 3600 )) ] && continue
  if echo "$rest" | grep -Eq "$ROOT_RE"; then
    has_root_ancestor "$TMP/s1" "$pid" || ROOTS="$ROOTS $pid"
  elif [ "$ppid" = 1 ] && echo "$rest" | grep -Eq "$ORPHAN_RE"; then
    ROOTS="$ROOTS $pid"
  fi
done < "$TMP/s1"

# 2. Idle window: a tree that uses any CPU time in this window is busy and is left alone.
[ -n "$ROOTS" ] && sleep "$IDLE_S"

stopped=0
for r in $ROOTS; do
  # 3. Fresh snapshot per tree, so new children are included and CPU use is current.
  snap "$TMP/s2"
  awk -v p="$r" '$1==p{f=1} END{exit !f}' "$TMP/s2" || continue
  pids=$(tree "$TMP/s2" "$r" | tr '\n' ' ')
  before=$(cpu_sum "$TMP/s1" "$pids"); after=$(cpu_sum "$TMP/s2" "$pids")
  # A pid new since s1 has no "before" value, so any CPU it used counts as busy.
  [ "$after" -gt "$before" ] && continue
  n=$(echo $pids | wc -w | tr -d ' ')
  echo "$(date '+%F %T') root=$r procs=$n dry_run=$DRY_RUN" >> "$LOG"
  [ "$DRY_RUN" = 1 ] && { stopped=$((stopped + n)); continue; }
  # 4. Signal only pids whose start time is unchanged (no pid reuse).
  for p in $pids; do echo "$p $(started "$p")"; done > "$TMP/ids"
  while read -r p st; do [ -n "$st" ] && kill -TERM "$p" 2>/dev/null; done < "$TMP/ids"
  sleep 3
  while read -r p st; do
    [ -n "$st" ] && [ "$(started "$p")" = "$st" ] && kill -KILL "$p" 2>/dev/null
  done < "$TMP/ids"
  stopped=$((stopped + n))
done
echo "$(date '+%F %T') done: $stopped processes $([ "$DRY_RUN" = 1 ] && echo 'would be stopped' || echo stopped)" >> "$LOG"
tail -1 "$LOG"
