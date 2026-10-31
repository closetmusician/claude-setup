# Writing Style

ABOUTME: The one writing standard for every reply, document, draft, and agent report.
ABOUTME: ASD-STE100 Simplified Technical English, readable by a smart 18-year-old.
ABOUTME: Canonical home. CLAUDE.md points here; do not restate these rules elsewhere.
ABOUTME: Banned words live in policy/ste-style.rules. The gate is scripts/ste-lint.sh.
ABOUTME: Written 2026-09-11 after Yu-Kuan rejected the house style as "claude speak".

## 1. The standard

Write ASD-STE100 Simplified Technical English. A smart 18-year-old must understand
every sentence on the first read. This applies to replies, plans, specs, reports,
commit messages, and anything a subagent hands back.

Simple does not mean vague. Keep every exact name, number, file path, flag, and
caveat. Cut the words around them, never the facts.

## 2. The nine rules

1. **One idea per sentence.** If you use "and" to join two ideas, use two sentences.
2. **Maximum 25 words per sentence.** Maximum 20 words when you give an instruction.
3. **Active voice.** "The hook blocks the call", not "the call is blocked by the hook".
4. **Present tense** for what is true now. Past tense only for what happened.
5. **One word, one meaning.** Pick the approved word and always use it. Do not reach
   for a synonym to add variety. `policy/ste-style.rules` lists the swaps.
6. **No jargon without a definition.** If a term is unavoidable, define it in one clause.
7. **Keep the articles.** "The guard reads the file", not "guard reads file".
8. **No filler.** Delete any sentence that adds no fact. Never open with praise.
9. **Maximum two em dashes in a reply.** A full stop, a comma, or brackets are clearer.

## 3. Words to delete on sight

The full list is `policy/ste-style.rules`, which you may edit without touching code.
The worst offenders: utilize, leverage, delve, robust, seamless, comprehensive,
holistic, nuanced, crucial, pivotal, myriad, deep dive, unpack, circle back,
low-hanging fruit, move the needle. Also every opener that says nothing:
"Great question", "You're absolutely right", "It's worth noting", "That said".

## 4. What good looks like

- BAD: "It's worth noting that we can leverage the existing guard here — it's not just
  a check, it's a comprehensive safety net that will robustly handle the edge cases."
- GOOD: "Use the existing guard. It already covers the three cases you asked about."

- BAD: "I'd be happy to delve into the nuanced landscape of the caching paradigm."
- GOOD: "Here is how the cache works."

## 5. Agent dialog

Subagents never load CLAUDE.md, so the standard does not reach them by itself. Every
dispatch prompt must carry the STE contract line from
`~/.claude/docs/plans/harness/dispatch-templates.md`. A report that comes back in
house style gets rewritten before it reaches Yu-Kuan; do not pass it through.

## 6. How it is enforced

`scripts/ste-lint.sh` — a Stop hook. It reads the reply you are about to show, then
checks it against `policy/ste-style.rules` plus the sentence-length and em-dash rules.
On a fault it blocks the turn once and lists every word to change.

Scope (set by Yu-Kuan on 2026-09-11): ordinary prose, TABLE CELLS and markdown LINK TEXT
are checked. Code fences and inline code are NOT, because a real function or command name
cannot be renamed to satisfy a style rule. Nothing is removed from the reply itself; the
hook works on its own private copy.

One precision rule on top: a banned word does not count when it sits inside an identifier,
flag, path or URL. "we use it badly" style prose is caught; `scripts/fast-x.sh` and
`--fast-cache` are not.

If a finding names a real code symbol that cannot change, send the reply again unchanged.
The gate fires once per reply, so the second send goes through.

It blocks once per reply, and `stop_hook_active` lets the corrected reply through.
Fail mode is fail-open: a style gate must never strand a finished answer.

Kill switch: `HARNESS_STE_LINT=0`. Tests: `scripts/tests/test-ste-lint.sh`, 26 cases.
