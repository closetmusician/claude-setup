#!/usr/bin/env bash
# ABOUTME: Shared timeout wrapper for the self-improving harness (Pillar I).
# ABOUTME: Routes through gtimeout (GNU coreutils) when present, else perl watchdog,
# ABOUTME: else python3 watchdog. Always fail-open: if all backends are absent, the
# ABOUTME: command is run without a timeout rather than erroring.
# ABOUTME: Usage: source this file, then call: _run_with_timeout <seconds> <cmd> [args...]

# _run_with_timeout: run <cmd> [args...] with a <seconds> wall-clock limit.
# Purpose: provide a portable timeout wrapper that works on macOS (where the
#   built-in `timeout` is absent and only gtimeout/GNU coreutils is available).
# Usage: _run_with_timeout 5 jq --version
# Gotchas: fail-open — if no timeout backend is present the command runs unrestricted;
#   callers must accept that the timeout is best-effort on very constrained systems.
_run_with_timeout() {
  local secs="$1"
  shift

  # Backend 1: gtimeout (GNU coreutils, verified present on this host)
  if command -v gtimeout >/dev/null 2>&1; then
    gtimeout "$secs" "$@"
    return $?
  fi

  # Backend 2: perl watchdog (available on macOS base install)
  if command -v perl >/dev/null 2>&1; then
    perl -e '
      use POSIX ":sys_wait_h";
      my $secs = shift;
      my $pid = fork;
      if ($pid == 0) { exec @ARGV or exit 127; }
      local $SIG{ALRM} = sub { kill "TERM", $pid; exit 124; };
      alarm $secs;
      waitpid($pid, 0);
      alarm 0;
      exit ($? >> 8);
    ' "$secs" "$@"
    return $?
  fi

  # Backend 3: python3 watchdog
  if command -v python3 >/dev/null 2>&1; then
    python3 -c "
import subprocess, sys, signal, os
secs = int(sys.argv[1])
args = sys.argv[2:]
proc = subprocess.Popen(args)
def _kill(s, f): proc.terminate(); sys.exit(124)
signal.signal(signal.SIGALRM, _kill)
signal.alarm(secs)
proc.wait()
signal.alarm(0)
sys.exit(proc.returncode)
" "$secs" "$@"
    return $?
  fi

  # Fail-open: no backend available — run without timeout
  "$@"
}
