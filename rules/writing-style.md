# Writing Style

ABOUTME: The one writing standard for every reply, document, draft, and agent report.
ABOUTME: ASD-STE100 Simplified Technical English, readable by a smart 18-year-old.
ABOUTME: Canonical home. CLAUDE.md points here; do not restate these rules elsewhere.
ABOUTME: Banned words live in policy/ste-style.rules. The gate is scripts/ste-lint.sh.
ABOUTME: Written 2026-09-11 after Yu-Kuan rejected the house style as "claude speak".

## 1. The standard

Write in ASD-STE100 Simplified Technical English: self-explanatory, plain English with no exceptions. A smart 18-year-old must understand
every sentence on the first read with zero context. This applies to replies, plans, specs, reports,
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

## 5b. How to ask questions

This covers every AskUserQuestion call. It also covers chat replies that ask for a decision.
Two hooks check every question before the owner sees it: a word checker
(`scripts/governance/question-clarity-guard.py`) and a Haiku grader (`scripts/governance/question-clarity-grader.md`).
An unchanged resend passes the word checker. If the last two tries were both blocked, resend with
`metadata: {"source": "clarity-retry"}`. The owner never sees it, and both checks let it through.
The checker reads the chat log and refuses the tag unless two blocks in a row came first.
It exists so a question that truly needs asking is never stuck. Never use it to skip a rewrite.

Template:
- Question: the goal in one sentence. What is true now, in plain words. Then the choice. Say why you must decide, if it is not obvious.
- Header: 2-3 plain words. No codes.
- Option label: a plain verb phrase, 2-6 words. No codes. No letters as names.
- Option description: what happens, and what changes for the goal. Good: the main benefit, with a number if there is one. Bad: the main cost or risk, with a number if there is one.

Checklist. Run it before every question:
1. Could a smart 18-year-old with zero context answer from the text alone?
2. Is every code, ID, stage name or made-up name removed, or defined in plain words at first use?
3. Does the question state the goal the choice serves?
4. Does each option say what changes for that goal, with one good side and one bad side?
5. Is every number there because it changes the choice? Does one plain line say what the numbers mean?
6. Does the question point at a file, a doc section, a rule number or an agent report? If so, put the needed facts in the question.
7. If the owner must approve text, is the text in the question or the preview?
8. Do the owner's own rules already answer this? If yes, do not ask. Name the choice and go.
9. Is it one decision per question? Split a list into separate questions.
10. Do the header and every option label avoid codes?

- BAD: header "D2 paths". Question "D2: the B1 code pin copies src/. Which wins?" Option "Isolation wins".
- GOOD: header "Copy or live". Question "The saved copy of the code has different file paths than the live code. Do you want the copy to stay safe from live edits, or to match the live paths?" Option "Keep the copy safe: no code change, but the spec must say 'same bytes' instead of 'same paths'."

## 5c. How to present a choice (decision template)

Use this whenever a reply asks the owner to choose between options. Set by Yu-Kuan on 2026-11-24 from two
example docs. Take the principles, not the details of the example. The reply gate
(`scripts/governance/reply-clarity-gate.py`) sends back a choice reply without the table, or with shallow implications.

The principles:
1. **Recommendation first.** One recommendation, or two (for example a default and a fallback when something is
   unknown). Three only in extreme cases. Each comes with numbered reasons tied to the owner's bigger goal.
2. **A table of the options against the dimensions that matter for this decision.** You choose the dimensions:
   the goals, costs and risks that actually decide this choice. Nothing is fixed; "effort" or "speed" are examples only.
   Layout (Yu-Kuan, 2026-11-24): one ROW per option, one COLUMN per dimension. The last column is "Recommend":
   "Yes: <why>" or "No: <why>". Make it fit a terminal: at most 4 dimension columns, and about 12 words per cell.
3. **As many options as the decision really has.** Two, three or more. Say why these are the options.
4. **Every cell: a rating, then the consequence.** A rating (High / Medium / Low, Good / Bad, None, or a number), then
   what it means for the project: who is affected, by how much, what it costs, what could go wrong. Never a bare rating,
   and never a generic claim like "it is better".
5. **Big picture last.** What each choice means for the overall project, the main risk, and what happens if we pick wrong.
6. **Plain names.** Name each option in plain words. Never "Option B" alone, and never an internal code.

One shape, as an illustration only (options are rows, dimensions are columns, the last column is the recommendation):

```
**Recommend: <option in plain words>.** One sentence: why, in terms of the owner's goal.
1. **Headline reason.** What it means for the bigger goal, with a number if there is one.

| Option | <dimension that matters> | <another dimension> | Recommend |
|---|---|---|---|
| <option 1> | High: short consequence for the project | 2 weeks: short consequence | Yes: why, in a few words |
| <option 2> | Low: short consequence | 6 weeks: short consequence | No: why, in a few words |
| <option 3> | Medium: short consequence | 3 weeks: short consequence | No: why, in a few words |

**Big picture:** what each choice means for the overall project, the main risk, what happens if we pick wrong.
```

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

Doc checker: `scripts/governance/doc-clarity-guard.py` (PostToolUse) checks owner-facing docs against section 5c. Switch: `HARNESS_DOC_CLARITY=0`. It warns only and never blocks.
