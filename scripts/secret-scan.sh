#!/usr/bin/env bash
# ABOUTME: Scans staged git content for high-confidence secret patterns and blocks the commit.
# ABOUTME: Born from the 2026-07-03 incident: transcript-derived audit TSVs were committed with a
# ABOUTME: live GitHub PAT, Atlassian token, and OpenAI key. Pattern-based (low false-positive),
# ABOUTME: scans only staged additions. Exit 1 + file:line report on any hit; exit 0 when clean.
# ABOUTME: Also usable ad hoc: `secret-scan.sh <file>...` scans given files instead of the index.

set -uo pipefail

# High-confidence provider token patterns. Deliberately specific — this guard must almost never
# false-positive, or it trains the user to bypass it (the 392-wrongful-block lesson).
PATTERNS='ghp_[A-Za-z0-9]{30,}|github_pat_[A-Za-z0-9_]{22,}|ATATT[A-Za-z0-9_=.-]{20,}|sk-(proj|ant|svcacct)?-?[A-Za-z0-9_-]{24,}|AKIA[A-Z0-9]{16}|xox[baprs]-[A-Za-z0-9-]{10,}|-----BEGIN [A-Z ]*PRIVATE KEY-----|glpat-[A-Za-z0-9_-]{20,}|AIza[A-Za-z0-9_-]{35}'

hits=0
report() { echo "  SECRET? $1"; hits=$((hits+1)); }

if [[ $# -gt 0 ]]; then
  # Ad-hoc mode: scan named files.
  for f in "$@"; do
    [[ -f "$f" ]] || continue
    while IFS= read -r line; do report "$f:$line"; done < <(grep -nEo "$PATTERNS" "$f" 2>/dev/null | cut -d: -f1 | sort -un)
  done
else
  # Pre-commit mode: scan staged ADDED lines only (unaffected by RTK — grep here is in-script).
  while IFS= read -r f; do
    [[ -z "$f" ]] && continue
    # Added lines for this file in the staged diff; report file + matched token, not full line.
    if git diff --cached -U0 -- "$f" 2>/dev/null | grep -E '^\+' | grep -qE "$PATTERNS"; then
      report "$f (staged) — $(git diff --cached -U0 -- "$f" | grep -E '^\+' | grep -oE "$PATTERNS" | head -1 | cut -c1-12)…"
    fi
  done < <(git diff --cached --name-only 2>/dev/null)
fi

if [[ "$hits" -gt 0 ]]; then
  echo "secret-scan: BLOCKED — $hits potential secret(s) in staged content." >&2
  echo "Redact (perl -pi) or unstage the file, then re-commit. Override (rare): SECRET_SCAN_SKIP=1 git commit …" >&2
  [[ "${SECRET_SCAN_SKIP:-0}" == "1" ]] && { echo "secret-scan: SECRET_SCAN_SKIP=1 set — allowing." >&2; exit 0; }
  exit 1
fi
exit 0
