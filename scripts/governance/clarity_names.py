# ABOUTME: Finds made-up names and letter/number references in a reply that the owner may not know.
# ABOUTME: Port of tuning/gate-fit/cands.py candidates(), plus a filter for names the owner already saw.
# ABOUTME: Pure code, no network. Used by reply-clarity-gate.py to word the rewrite message.
# ABOUTME: Spec: docs/plans/harness/reply-clarity-guard/reply-gate-spec.md REQ-12.
# ABOUTME: Run with python3 -I; the module has no side effects on import.
import collections
import re

STOP = set('the a an and or of to in on for with is are was be it this that these those by from at as we i you our your my not no yes but if then so all any each one two three new old more most less same other'.split())
REF = re.compile(r"\b(?:option|options|item|items|step|steps|reason|reasons|point|points|test|tests|lane|lanes|cut|phase|round|stage|arm|track|fix|fixes|case|q)\s+(?:[A-Z]|\d+)(?:\s*(?:,|and|&|or|-)\s*(?:[A-Z]|\d+))*\b|\b[a-d]\s*(?:&|and)\s*[a-d]\b|#\d+|\b[A-Z]{1,5}-\d+[a-z]?\b|\bP[0-3]s?\b|\b[A-Z]\d\b", re.I)
CODE = re.compile(r"`[^`\n]{2,60}`")
QUOTE = re.compile(r"[\"“']([A-Za-z][A-Za-z0-9 \-]{2,40})[\"”']")
HYPH = re.compile(r"\b[a-z]+(?:-[a-z]+)+\b")
CAPS = re.compile(r"\b[A-Z]{2,}[A-Z0-9-]*\b")
WORD = re.compile(r"[A-Za-z][A-Za-z-]+")
COMMON_CAPS = ('I', 'OK', 'PR', 'PRs', 'AI', 'API', 'URL', 'PDF', 'CSV', 'JSON', 'HTML', 'UI', 'CI', 'ETA', 'ARR', 'PM', 'US', 'UK', 'EU', 'FAQ')
PRIORITY = {'ref': 3, 'quote': 3, 'pair': 2, 'hyph': 2, 'caps': 1, 'code': 0}
# Text after a name that explains it: a bracket, a dash, a colon, an equals sign, or "means/is/...".
EXPLAINED = r"\s*(?:\(|—|–|-\s|:|=|,?\s+(?:means|is|are|which|that is|i\.e\.))"


def strip_code(t):
    """Purpose: blank out fenced code blocks. Usage: strip_code(text).
    Gotchas: inline code in single backticks stays; candidates() reads it as kind code."""
    return re.sub(r"```.*?```", " ", t, flags=re.S)


def candidates(text):
    """Purpose: count name candidates as {(kind, string): count}. Usage: candidates(reply_text).
    Gotchas: unchanged port of tuning/gate-fit/cands.py (sha256 prefix 2478e90f63e669e0); do not tune here."""
    t = strip_code(text)
    c = collections.Counter()
    for m in REF.findall(t):
        c[('ref', m.strip())] += 2
    for m in QUOTE.findall(t):
        c[('quote', m.strip())] += 2
    for m in HYPH.findall(t):
        if len(m) > 6:
            c[('hyph', m)] += 1
    for m in CAPS.findall(t):
        if m not in COMMON_CAPS:
            c[('caps', m)] += 1
    words = [w.lower() for w in WORD.findall(re.sub(CODE, ' ', t))]
    for (a, b), n in collections.Counter(zip(words, words[1:])).items():
        if n >= 2 and a not in STOP and b not in STOP and len(a) > 3 and len(b) > 3:
            c[('pair', a + ' ' + b)] += n
    for m in CODE.findall(t):
        c[('code', m.strip('`'))] += 1
    return c


def new_names(text, known):
    """Purpose: list names the reply uses but never explains and the owner has not seen.
    Usage: names = new_names(text, known_lowercase_string); best names first.
    Gotchas: a pair needs count >= 2. A name followed by a bracket, dash, colon, equals or "means" counts as explained.
    First position uses the first case-insensitive hit in the code-stripped text (end of text if not found)."""
    stripped = strip_code(text)
    found = []
    for (kind, s), n in candidates(text).items():
        if kind == 'pair' and n < 2:
            continue
        low = s.lower()
        if low in known:
            continue
        hits = list(re.finditer(re.escape(s) + EXPLAINED, stripped, re.I))
        if hits:
            continue
        pos = stripped.lower().find(low)
        found.append((-PRIORITY[kind], -n, pos if pos >= 0 else len(stripped), s))
    found.sort()
    out, seen = [], set()
    for *_, s in found:
        if s.lower() not in seen:
            seen.add(s.lower())
            out.append(s)
    return out
