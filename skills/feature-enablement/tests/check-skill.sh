#!/usr/bin/env bash
# ABOUTME: Static structure checks for the feature-enablement skill (v2.1 evidence step)
# ABOUTME: Asserts required commands, files, config defaults, template sections and prompt rules
# ABOUTME: Usage: bash tests/check-skill.sh  (from anywhere; resolves the skill root itself)
# ABOUTME: Exit 0 = all checks pass; otherwise prints "FAIL: <check>" lines and exits 1
# ABOUTME: Live behaviour is verified separately in tests/verification-2026-11.md

S="$(cd "$(dirname "$0")/.." && pwd)"
SKILL="$S/SKILL.md"
CFG="$S/config.yaml"
TPL="$S/templates/messaging-foundation-template.md"
REF="$S/references/evidence-sources.md"
GONG="$S/prompts/gong-evidence.md"
PENDO="$S/prompts/pendo-sizing.md"
fails=0

# has FILE NAME FIXED-STRING -- fail unless FILE contains the literal string
has() {
  grep -qF -- "$3" "$1" 2>/dev/null || { echo "FAIL: $2"; fails=$((fails+1)); }
}

# SKILL.md: evidence command, prompt/reference wiring, metadata keys, external-use gate
if ! head -3 "$SKILL" | grep -q '^description: Use when '; then
  echo "FAIL: skill: description starts with Use when"
  fails=$((fails+1))
fi
has "$SKILL" "skill: evidence command section" '### `/feature-enablement evidence`'
has "$SKILL" "skill: references reference file" 'references/evidence-sources.md'
has "$SKILL" "skill: references pendo prompt" 'prompts/pendo-sizing.md'
has "$SKILL" "skill: references gong prompt" 'prompts/gong-evidence.md'
has "$SKILL" "skill: Evidence_Last_Run metadata" 'Evidence_Last_Run'
has "$SKILL" "skill: Pendo_Proxy metadata" 'Pendo_Proxy'
has "$SKILL" "skill: external-use question" 'OK to use usage figures externally?'
has "$SKILL" "skill: version 2.1 footer" 'Version:** 2.1'
grep -qF '**Gong call links**' "$SKILL" && { echo "FAIL: skill: Gong call links prompt still present"; fails=$((fails+1)); }
has "$S/CHANGELOG.md" "changelog: v2.1 entry" '## v2.1'

# Template: misconceptions section and evidence source lines
has "$TPL" "template: Known Field Misconceptions" '### Known Field Misconceptions'
has "$TPL" "template: Pendo Sizing source line" '**Pendo Sizing:**'
has "$TPL" "template: Gong Evidence source line" '**Gong Evidence:**'

# Reference file: exists, every entry dated, no customer names
if [ -f "$REF" ]; then
  python - "$REF" <<'PY' || fails=$((fails+1))
import re, sys
text = open(sys.argv[1], encoding="utf-8").read()
blocks = re.split(r"(?m)^### ", text)[1:]
bad = [b.splitlines()[0] for b in blocks if "Last verified: 20" not in b]
if not blocks:
    print("FAIL: reference: no ### entries"); sys.exit(1)
if bad:
    print("FAIL: reference: undated entries: " + "; ".join(bad)); sys.exit(1)
PY
  grep -q 'account:' "$REF" && { echo "FAIL: reference: contains a Gong account: value"; fails=$((fails+1)); }
else
  echo "FAIL: reference: file missing"; fails=$((fails+1))
fi

# Gong prompt rules
for s in 'found | thin | unavailable' '1,000' 'Write tool' 'speaker is unclear' 'inline' 'old names' 'replaced the query' 'anywhere in the file' 'None found' 'PRD fact probes'; do
  has "$GONG" "gong prompt: '$s'" "$s"
done

# Pendo prompt rules
for s in 'measured | skipped | unavailable' 'Last verified' '6 months' 'Rejected candidates'; do
  has "$PENDO" "pendo prompt: '$s'" "$s"
done

# Final-review fixes: main-session wiring
python - "$SKILL" "$GONG" "$PENDO" <<'PY' || fails=$((fails+1))
import sys
skill, gong, pendo = (open(p, encoding="utf-8").read() for p in sys.argv[1:4])
def section(text, start):
    i = text.index(start); j = text.find("\n### `", i + 1)
    return text[i:j if j > 0 else None]
bad = []
if "OK to use usage figures externally?" not in section(skill, "### `/feature-enablement demo`"):
    bad.append("C1 demo applies external-use gate")
if "skip steps 3–5" in skill:
    bad.append("I1 update stale-evidence branch skips PM review")
if "skip to step 3" in pendo or "still run step 2" not in pendo:
    bad.append("I2 confirmed proxy still gets liveness check")
if "Recompute the Gong window" not in skill:
    bad.append("I3 Gong window recomputed each run")
if "absolute path" not in skill or "| `{{PRD_PATH}}`" not in skill:
    bad.append("I4 placeholder mapping + absolute reference path")
for name, p in (("gong", gong), ("pendo", pendo)):
    if "reference file cannot be read" not in p:
        bad.append(f"I4 {name} prompt handles unreadable reference")
if "6 months" not in gong:
    bad.append("I5 gong prompt staleness rule")
if bad:
    print("FAIL: " + "; ".join(bad)); sys.exit(1)
PY
# Customer names: screened via a local, untracked denylist (one name per line, never shipped)
python - "$S" <<'PY' || fails=$((fails+1))
import pathlib, re, sys
root = pathlib.Path(sys.argv[1])
deny_file = root / "tests" / "customer-denylist.local"
if not deny_file.exists():
    sys.exit(0)
names = [n.strip() for n in deny_file.read_text(encoding="utf-8").splitlines() if n.strip()]
hits = []
for p in root.rglob("*"):
    if p.is_file() and p.suffix in {".md", ".yaml", ".sh", ".html"} and p.name != deny_file.name:
        text = p.read_text(encoding="utf-8", errors="ignore")
        for n in names:
            if re.search(r"(?<![A-Za-z])" + re.escape(n) + r"(?![A-Za-z])", text, re.I):
                hits.append(f"{p.relative_to(root)}: {n}")
if hits:
    print("FAIL: customer names in shipped files: " + "; ".join(hits)); sys.exit(1)
PY

# Config: parses and carries the spec defaults
python - "$CFG" <<'PY' || fails=$((fails+1))
import sys, yaml
c = yaml.safe_load(open(sys.argv[1], encoding="utf-8"))
e = (c or {}).get("evidence") or {}
want = {
    ("reference_file",): "references/evidence-sources.md",
    ("pendo", "window_days"): 90,
    ("pendo", "max_candidates"): 4,
    ("gong", "window_months"): 12,
    ("gong", "max_transcripts"): 15,
    ("gong", "demand_signal"): True,
}
bad = []
for path, val in want.items():
    cur = e
    for k in path:
        cur = cur.get(k) if isinstance(cur, dict) else None
    if cur != val:
        bad.append(f"evidence.{'.'.join(path)}={cur!r} (want {val!r})")
if bad:
    print("FAIL: config: " + "; ".join(bad)); sys.exit(1)
PY

# No backspace characters (the \b -> chr(8) heredoc trap)
python - "$S" <<'PY' || fails=$((fails+1))
import pathlib, sys
hits = [str(p) for p in pathlib.Path(sys.argv[1]).rglob("*")
        if p.is_file() and p.suffix in {".md", ".yaml", ".sh", ".html"}
        and "\x08" in p.read_text(encoding="utf-8", errors="ignore")]
if hits:
    print("FAIL: backspace chars in: " + ", ".join(hits)); sys.exit(1)
PY

[ "$fails" -eq 0 ] && echo "ALL CHECKS PASS" && exit 0
echo "$fails check(s) failed"; exit 1
