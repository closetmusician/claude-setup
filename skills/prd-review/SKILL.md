---
name: prd-review
description: "Adversarially review an EXISTING PRD for ambiguities, hidden complexity, and untestable requirements before implementation begins — 5 specialized reviewer personas probe it, findings are triaged, and specifiable fixes are applied to the document. Use when: user says 'review this PRD', 'critique this spec', 'improve this PRD', 'is this PRD ready', 'adversarial review', or when /prd-writer invokes it at Step 7. Also trigger when the user shares an existing PRD and asks if it's implementation-ready. NOT for writing a new PRD from scratch or formalizing rough notes — use /prd-writer."
---

## Required Files
- `references/persona-prompts.md` — Shared abstraction-guardrail preamble + system prompts for 5 reviewer personas

# PRD Review

Four-phase adversarial review that catches spec ambiguities before agents hit them
during implementation. Spawns 5 fresh subagents — each sees ONLY the PRD, no
conversation history — to probe from different expert perspectives.

**Model discipline (subagent tiers):** judgment work = opus, mechanical/perspective
work = sonnet. Concretely: Eng Manager (Agent 3), QA Expert (Agent 5), Synthesis
(Phase 3), and Triage (Phase 4.1) spawn with `model: opus`; Product Thinker (Agent 1),
UX Designer (Agent 2), and Customer Expert (Agent 4) with `model: sonnet`. A skill
cannot change the main agent's model — for best results invoke /prd-review from an
Opus session, but do not block on another model.

**Context discipline:** Phase 2 subagents write their findings to disk. Phases 3 and 4
subagents read files from disk — they never receive raw Phase 2 outputs in context.
The main agent reads only the final triage doc, keeping its context window thin.

**Interaction discipline (one decision per AskUserQuestion — everywhere):** every
`AskUserQuestion` call in this skill carries exactly ONE decision. Present context/tables
as plain text first, then ask decisions one at a time and wait for each answer. This
applies to premise adjustments (Phase 1.3), REQUIRES_DECISION items (Phase 4.3), the
file-pick (Step 0), resume-vs-fresh (Step 0.5), and cleanup (Step 4.5).
- *Positive example:* "Decision 1 of 4: How should duplicate names be handled? A/B/C/Defer"
  → wait → "Decision 2 of 4: ...".
- *Negative example:* one call asking "For decisions 1-3, pick A/B/C for each" — compound
  answers get mangled and the user has to say "ask decision 3 again." Never batch decisions.

## Core Principle

A PRD is ready for implementation when an agent can build every requirement without
a single AskUserQuestion call. Every ambiguity caught here saves a blocked subagent,
a wrong guess, or a rework cycle during BUILD.

**Abstraction Principle:** A PRD specifies WHAT users experience, not HOW the system
implements it. Every requirement in §1-6 must pass the stakeholder test: can a product
stakeholder read this sentence and understand why it matters to users? If it names a
library, protocol, architecture pattern, data pipeline, regex, or internal service — it
fails. Translate to user impact or defer to the TAR. Only §7 (Engineering) may contain
implementation detail.

When applying fixes, ask: would this text change if the team chose a different framework
or architecture? If yes → it belongs in the TAR, not the PRD.

---

## Workflow

### Step 0: Locate the PRD and Set Up Working Directory

Determine the PRD file path:

**If invoked with a path** (e.g., `/prd-review docs/my-feature.md`):
- Read the file. Confirm it exists and looks like a PRD.

**If invoked from /prd-writer:**
- The PRD path was passed in context. Read it.

**If invoked standalone with no path:**
- Search for recent PRD files (the git branch requires a repo; check first):
  ```bash
  if git rev-parse --git-dir >/dev/null 2>&1; then
    find . -maxdepth 3 -name "*.md" -newer "$(git rev-parse --git-dir)/HEAD" -type f 2>/dev/null | head -20
  else
    find . -maxdepth 3 -name "*.md" -mtime -14 -type f 2>/dev/null | head -20
  fi
  ```
  (Never run the `-newer .git/HEAD` form directly — it silently returns nothing outside
  a git repo and in worktrees, and the review then starts on the wrong file.)
- Also check common locations: `docs/`, `specs/`, `/mnt/user-data/outputs/`
- Use AskUserQuestion ONCE to confirm which file to review:
  ```
  Which PRD should I review?
  A) [most recent .md file found]
  B) [second most recent]
  C) Other — provide path
  D) The PRD is the text I pasted in this conversation
  ```

**Escape hatches — never hard-stop for lack of a path:** search finds nothing → ask
once for the path (options C/D only). User pasted the PRD in conversation (or picks D)
→ write it to `.prd-review/<slug>/prd-under-review.md` and review that file (subagents
need a file path); say so in the final report header.

Read the full PRD content **unless the size guard applies (see Phase 1, Step 1.0)** —
for PRDs over 400 lines, read only the head (title + TOC) here; the extraction subagent
handles the rest. Derive a slug from the filename (e.g., `docs/my-feature.md`
→ `my-feature`; for pasted text, slugify the PRD's title). Create the working directory
for this review run:

```bash
mkdir -p .prd-review/<slug>
```

All intermediary files for this review go under `.prd-review/<slug>/`. This directory
is ephemeral — it is cleaned up (or gitignored) in Step 4.5. Store the PRD path and
slug — all subagents will need them.

### Step 0.5: Resume Protocol (check BEFORE starting Phase 1)

Review runs die to session limits mid-flight; the artifacts on disk survive. If
`.prd-review/<slug>/` already exists and contains files, do NOT restart from scratch —
detect the completed phases and resume.

**Detection (run `ls .prd-review/<slug>/` and match the FIRST row that fits):**

| Files present | Completed | Resume at |
|---|---|---|
| `triage.md` | Phases 1-4.1 | Step 4.2 (apply fixes) |
| `synthesis.md` (no triage.md) | Phases 1-3 | Step 4.1 (triage) |
| all 5 `reviewer-*.md` (no synthesis.md) | Phases 1-2 | Phase 3 (synthesis) |
| 1-4 `reviewer-*.md` | Phase 1 + partial 2 | Phase 2 — re-spawn ONLY the missing reviewers (same model tier), keep existing files |
| `premises.md` only | Phase 1 | Phase 2 |
| directory empty | nothing | Phase 1 |

**Procedure:**
1. State what was found and the inferred resume point as text.
2. Confirm with ONE AskUserQuestion: **Resume at [phase]** / **Start fresh**. If fresh:
   move the old directory to `.prd-review/<slug>-old-<YYYYMMDD-HHMM>/` (never delete
   silently — it may hold the only copy of a dead session's findings).
3. When resuming past Phase 1, read `premises.md` from disk instead of re-running the
   premise interview. If `premises.md` is missing but reviewer files exist, proceed
   without premises (they only feed the final report framing) and note that in the report.
4. When resuming at Step 4.2, ask the user (same single question) whether any triage
   fixes were already applied to the PRD in the dead session — if unsure, diff the PRD
   against the Applied Fixes list in `triage.md` before editing.

- *Positive example:* dir contains 5 reviewer files + synthesis.md → resume by spawning
  the triage subagent; total cost ≈ one subagent instead of eight.
- *Negative example:* dir contains 5 reviewer files but you re-run Phase 1 premises and
  re-spawn all 5 reviewers "to be safe" — that burns the exact context budget that killed
  the previous run.

---

### Phase 1: Big Picture Review

Before diving into requirements, challenge the foundational assumptions. This phase
runs in the main agent — EXCEPT premise-material extraction for large PRDs (Step 1.0).

**Step 1.0: Size Guard (PRDs over 400 lines)**

Check size first: `wc -l <prd-path>`.

- **≤400 lines:** read the full PRD in the main agent and proceed to Step 1.1 directly.
- **>400 lines:** do NOT pull the full PRD into main context. Spawn ONE extraction
  subagent (Task tool, `subagent_type: "general-purpose"`, `model: sonnet`) with this prompt:

  ```
  Read the PRD at [PRD_FILE_PATH]. Write to .prd-review/<slug>/big-picture-extract.md:
  1. VERBATIM copies of: TL;DR, Problem Definition, Opportunity Size (or their
     nearest-equivalent sections).
  2. A compact inventory: every section heading; every REQ-ID with its one-line name
     and priority; JTBD list.
  3. Nothing else — no analysis, no opinions.
  ```

  The main agent then reads `big-picture-extract.md` (not the PRD) for Steps 1.1-1.3.
  Phase 2-4 are unaffected in structure, but see the Phase 2 delivery note — large PRDs
  are passed to reviewers by path, not embedded.
- *Positive example:* 1,200-line master PRD → extraction subagent returns a 120-line
  extract; main context stays thin enough to survive all 4 phases.
- *Negative example:* reading a 1,200-line PRD inline "because Phase 1 is fast" — 4 of 7
  historical runs died to context exhaustion, one mid-Phase-1 with no synthesis ever produced.

**Step 1.1: Premise Extraction**

Read the PRD's Problem Definition, TL;DR, and Opportunity Size sections (from the PRD
directly, or from `big-picture-extract.md` when the size guard applied). Extract
3-5 implicit premises — falsifiable claims the PRD assumes are true.

Format each as:
```
PREMISE: [Concrete claim]
EVIDENCE IN PRD: [Quote or "none — assumed"]
RISK IF WRONG: [What breaks if this premise is false]
```

**Step 1.2: Three Challenge Questions**

Ask yourself (do not ask the user yet):
1. **Is this the right problem?** Could we solve something with bigger impact for the
   same effort? (The demand-reality forcing question.)
2. **What's the 10X framing?** Is the PRD constraining the solution space? Is there a
   "chief of staff AI" hiding inside a "calendar app"? (The CEO-mode reframe.)
3. **What happens if we do nothing?** Is the status quo actually painful enough to justify
   this work? What are users doing TODAY to solve this badly?

**Step 1.3: Present Premises and Collect Adjustments One at a Time**

Show all extracted premises as text output (not inside AskUserQuestion — the user
needs to read them all first for context). Include the strongest challenge question
from Step 1.2 at the end.

Then walk through each premise **one at a time** using separate AskUserQuestion calls.
For each premise, present:

```
PREMISE N: [Concrete claim]
Evidence: [Quote or "none — assumed"]
Risk if wrong: [What breaks]

A) Correct as stated — no change needed
B) [Suggested adjustment 1 — your best guess at how this premise might be wrong]
C) [Suggested adjustment 2 — a different way it could be wrong]
D) Other — let me reframe this premise
```

**Rules for per-premise questions:**
- Ask ONE premise per AskUserQuestion call. Wait for the response before asking the next.
- Each question MUST include 1 "correct" option + 2-3 suggested adjustments + implicit "Other" for free-text.
- Suggested adjustments should be specific and informed by the PRD's own evidence gaps.
  Do NOT use generic options like "I have a different view" — propose concrete alternative framings.
- Record the user's adjustment (or confirmation) for each premise before moving on.
- After all premises are collected, present the strongest challenge question from Step 1.2
  as a final AskUserQuestion.

After ALL premises and the challenge question are resolved, present a brief summary:
```
Adjusted premises:
- P1: [confirmed or adjusted text]
- P2: [confirmed or adjusted text]
- ...

Challenge resolution: [user's response]

Proceeding to deep review with these premises in mind.
```

**Checkpoint (required — enables Step 0.5 resume):** write the adjusted premises and
challenge resolution to `.prd-review/<slug>/premises.md` before moving on.

**Escape hatches (offer as the LAST question after all premises):**
```
A) Proceed to deep review with adjusted premises (Recommended)
B) Go deeper — run /ceo-review for full strategic treatment first
```

If user picks B: invoke the installed `ceo-review` skill via the Skill tool. After it
completes, resume Phase 2 with any updated framing. (If the Skill call fails for any
reason, say so and proceed with option A — do not stall the review.)

If user picks A: proceed to Phase 2.

---

### Phase 2: Five-Persona Spec Review

Spawn 5 fresh subagents in parallel. Each agent receives ONLY the PRD text — no
conversation history, no prior context, no premises from Phase 1. Fresh eyes only.

Each subagent **must write its complete findings to disk** before returning. The main
agent does NOT read the subagent return values directly — it reads the files from disk
after all 5 complete. This keeps Phase 2 output out of main context.

Read `references/persona-prompts.md` for the exact system prompts. Each subagent
gets the **Shared Preamble** (abstraction guardrail, top of that file) + its persona
prompt + the PRD (see delivery note) + the output file path it must write to.

**PRD delivery note (size guard, continued):** for PRDs ≤400 lines, embed the full PRD
text in each prompt (fresh-eyes guarantee, zero read dependencies). For PRDs >400 lines,
do NOT embed — composing 5 prompts each carrying the full text floods the main agent's
context. Instead replace the `THE PRD:` block with: "Your FIRST action: Read the PRD
from disk at [PRD_FILE_PATH]. Review that document and nothing else." The subagent still
sees only the PRD; only the delivery mechanism changes.

**Spawn all 5 reviewer subagents in a single message using the Task tool
(`subagent_type: "general-purpose"`). The mix is 3 sonnet + 2 opus — use the Model
line in each agent block below; do NOT downgrade the two opus personas:**

#### Agent 1: Product Thinker (sonnet)
- **Focus:** Problem-solution fit, user value, competitive positioning
- **Model:** sonnet
- **Output file:** `.prd-review/<slug>/reviewer-1-product-thinker.md`
- **Output format:** Score each sub-dimension 1-10. List issues as SPECIFIABLE or REQUIRES_DECISION.

#### Agent 2: UX Designer (sonnet)
- **Focus:** User flows, interaction states, information hierarchy, accessibility
- **Model:** sonnet
- **Output file:** `.prd-review/<slug>/reviewer-2-ux-designer.md`
- **Reviews:** Info architecture, interaction state coverage (loading/empty/error/success),
  user journey completeness, AI slop risk in UX descriptions, responsive/accessibility gaps,
  unresolved design decisions
- **Output format:** Per-dimension score 0-10. For each gap: what a 10 looks like.

#### Agent 3: Engineering Manager (opus — judgment persona)
- **Focus:** Consistency, clarity, implementability, hidden assumptions
- **Model:** opus
- **Output file:** `.prd-review/<slug>/reviewer-3-eng-manager.md`
- **Checks:**
  - Do parts of the PRD contradict each other?
  - Could an agent implement every requirement without AskUserQuestion?
  - For every data flow: what happens on nil input, empty input, upstream error?
  - For every interaction: double-click, navigate-away, slow connection, stale state,
    back button, rapid resubmit, concurrent actions
- **Output format:** Issues classified as SPECIFIABLE (propose missing spec text) or
  REQUIRES_DECISION (needs PM input). Include proposed text for SPECIFIABLE items.

#### Agent 4: Customer Expert (sonnet)
- **Focus:** Persona coverage for Acme Boards' 3 core personas
- **Model:** sonnet
- **Output file:** `.prd-review/<slug>/reviewer-4-customer-expert.md`
- **Evaluates against:**
  1. **Board Members** — Time-poor, low tech fluency. Need frictionless access to meeting
     materials, voting, governance documents. Will they understand this feature without training?
  2. **Customer Admins** — Power users who configure the platform, manage access, handle
     compliance. Does this feature respect their workflow? Can they control it?
  3. **Executives** — Data-driven. Need dashboards, reports, action item tracking across
     multiple boards. Does this feature surface the data they need?
- **Output format:** Persona coverage matrix (which features serve which persona) +
  underserved persona gaps + confusion risks per persona.

#### Agent 5: QA Expert (opus — judgment persona)
- **Focus:** Testability, feasibility, hidden complexity
- **Model:** opus
- **Output file:** `.prd-review/<slug>/reviewer-5-qa-expert.md`
- **Grades every acceptance criterion:**
  - **BAD:** "Handler works correctly" (not testable, not falsifiable)
  - **OK:** "exports validateToken function" (testable but underspecified)
  - **GOOD:** "exports validateToken(token: string): Promise<AuthResult> that returns
    AuthResult.invalid() for expired tokens" (falsifiable, one test case)
- **For each feature:** Describe one realistic scenario where an agent produces wrong
  output because the spec is ambiguous
- **Assesses:** Can this actually be built with the stated approach? Hidden complexity?
  Dependencies not mentioned? Performance implications?
- **Output format:** Per-requirement BAD/OK/GOOD grade + failure scenarios +
  SPECIFIABLE/REQUIRES_DECISION classification

**Subagent prompt template:**
```
You are a [PERSONA_NAME] reviewing a Product Requirements Document.
You have NO prior context — you see ONLY this document. Review it from
your expert perspective.

[SHARED PREAMBLE — abstraction guardrail from references/persona-prompts.md]

[PERSONA-SPECIFIC INSTRUCTIONS from references/persona-prompts.md]

Return your findings as structured markdown with:
1. Overall assessment (2-3 sentences)
2. Dimension scores (if applicable)
3. Findings list — each finding must include:
   - FINDING-N: [title]
   - Severity: HIGH / MEDIUM / LOW
   - Classification: SPECIFIABLE / REQUIRES_DECISION
   - Evidence: [quote from PRD or "missing — should exist"]
   - Proposed fix: [your suggested text, or "PM must decide: [question]"]
4. Summary: X findings (Y specifiable, Z require decisions)

CRITICAL: You MUST write your complete findings to disk at the path below
using the Write tool. Do this BEFORE returning. The main agent reads from
disk only — it does not receive your return value.

Output file: [OUTPUT_FILE_PATH]

THE PRD:
---
[FULL PRD TEXT — for PRDs >400 lines, replace this block per the delivery note:
"Your FIRST action: Read the PRD from disk at [PRD_FILE_PATH]."]
---
```

**After spawning:** verify all 5 output files exist (`ls .prd-review/<slug>/reviewer-*.md`);
re-spawn any missing agent (same model tier) before continuing.

---

### Phase 3: Synthesis (opus subagent)

Spawn **one opus synthesis subagent** (Task tool, `subagent_type: "general-purpose"`,
`model: opus`). This agent reads the 5 reviewer files directly from disk — it does NOT
receive their content in the prompt. This prevents the 5 large reports from bloating
main context.

**Model:** opus (mandatory — this is the hardest analytical step)

**Subagent prompt:**
```
You are a Senior Architect synthesizing findings from 5 PRD reviewers.

Read these files from disk:
- PRD: [PRD_FILE_PATH]
- Reviewer reports: .prd-review/<slug>/reviewer-1-product-thinker.md
                    .prd-review/<slug>/reviewer-2-ux-designer.md
                    .prd-review/<slug>/reviewer-3-eng-manager.md
                    .prd-review/<slug>/reviewer-4-customer-expert.md
                    .prd-review/<slug>/reviewer-5-qa-expert.md

Perform these four passes (in order) and write all output to:
.prd-review/<slug>/synthesis.md

PASS A — CROSS-REVIEWER SYNTHESIS
Categorize every finding from all 5 reviewers:
| Category | Meaning | Priority |
|---|---|---|
| Reinforcing | 2+ reviewers flagged the same issue | HIGHEST |
| Unique | Only one reviewer found it | MEDIUM |
| Conflicting | Reviewers disagree | HIGH — surface disagreement |

PASS B — ACCEPTANCE CRITERIA AUDIT
Walk every P0 and P1 requirement in the PRD. For each:
1. Grade as BAD / OK / GOOD (cross-check with QA Expert's grades)
2. If BAD: write a GOOD replacement
3. If OK: identify what's missing to reach GOOD at the PRD abstraction level. If the only way to reach GOOD is to specify implementation mechanism (algorithms, data schemas, internal service behavior), mark as 'GOOD-enough for PRD; implementation detail deferred to TAR.' A requirement is GOOD for a PRD when a product stakeholder can understand it and a developer can derive the test — not when it specifies HOW to build it.
Compute: N% GOOD, M% OK, P% BAD before fixes.

PASS C — SHADOW PATH TRACING
For every data flow in the PRD:
- nil/null input, empty input, upstream error, timeout
For every user interaction:
- double-click, navigate-away mid-op, slow connection (3G),
  stale state (2h old tab), back button, rapid resubmit, concurrent tabs
Flag every unspecified case as a SPECIFIABLE finding with proposed behavior text.

PASS D — FAILURE SCENARIO GENERATION
For each major feature (top-level JTBD), write one realistic failure scenario:
SCENARIO: [Feature name]
An agent implementing this PRD would [specific wrong behavior] because the
spec says "[quote]" but doesn't specify [missing detail]. Two competent
engineers would build different things here.
PROPOSED SPEC ADDITION: [exact text to add]

Write your complete synthesis to .prd-review/<slug>/synthesis.md before returning.
```

**After subagent completes:** verify `.prd-review/<slug>/synthesis.md` exists (re-spawn
once if missing). Main agent reads only the synthesis file — not the 5 raw reviewer files.

---

### Phase 4: Convergence or Escalation

#### Step 4.1: Triage (opus subagent)

Spawn **one opus triage subagent** (Task tool, `subagent_type: "general-purpose"`,
`model: opus`). It reads the synthesis file and PRD from disk, produces a deduplicated
finding table, and writes it to disk.

**Model:** opus (mandatory — triage decisions require strong judgment)

**Subagent prompt:**
```
You are a Senior PM/Architect triaging PRD review findings.

Read these files from disk:
- PRD: [PRD_FILE_PATH]
- Synthesis: .prd-review/<slug>/synthesis.md

Merge all findings into a single deduplicated list. Every finding gets
exactly one disposition:

| Disposition | Meaning | Action |
|---|---|---|
| Applied | SPECIFIABLE fix — proposed text is unambiguous | Ready to apply to PRD |
| Captured | REQUIRES_DECISION — PM must choose | Add to Decision Table |
| Dismissed | False positive or out of scope | Note reason, no action |
| TAR-DEFERRED | Finding is valid but proposed fix contains implementation detail | Write user-facing behavior into PRD; flag implementation detail for TAR |

Rules:
- Do NOT cherry-pick. Every finding from every reviewer must appear with a disposition.
- For "Applied" findings: include the exact proposed text and the target REQ-ID/section.
- For "Captured" findings: state the decision question + concrete harm if deferred.
- For "Dismissed" findings: state the reason concisely.
- For 'TAR-DEFERRED' findings: write the user-observable behavior as the PRD fix. Note the implementation detail as 'For TAR: [detail]' — this goes into the TAR, not the PRD.

Output format:

## Triage Table
| Finding | Source | Disposition | Notes |
|---|---|---|---|
...

## Applied Fixes (ready to edit into PRD)
For each Applied finding:
### FIX-N: [REQ-ID] [Title]
Target: [section or requirement ID]
Proposed text: [exact text to add or replace]

## Decisions Needed (REQUIRES_DECISION)
| # | Decision | If Deferred, What Happens |
|---|---|---|
...

## Dismissed
| Finding | Reason |
|---|---|
...

## TAR-Deferred (implementation detail for TAR, not PRD)
| Finding | User-Facing PRD Text | Implementation Detail for TAR |
|---|---|---|
...

## AC Quality
Before fixes: N% GOOD, M% OK, P% BAD
After applied fixes: N'% GOOD, M'% OK, P'% BAD (projected)

Write your complete triage to .prd-review/<slug>/triage.md before returning.
```

**After subagent completes:** verify `.prd-review/<slug>/triage.md` exists (re-spawn
once if missing). **Main agent now reads `triage.md`.** This is the only Phase 2-3 artifact the main
agent ingests. Its context window at this point contains: PRD + premises from Phase 1
+ triage doc. Everything else lives on disk.

#### Step 4.2: Apply SPECIFIABLE Fixes

For each "Applied" finding from triage.md, edit the PRD directly using the Edit tool.
Make the smallest change that resolves the ambiguity. Preserve the PRD author's voice
and structure.

#### Step 4.3: Present REQUIRES_DECISION Items (one decision at a time)

First, show the full Unresolved Decision Table from the "Decisions Needed" section of
triage.md as plain text — the user needs the whole picture before deciding anything:

```
## Unresolved Decisions

| # | Decision Needed | If Deferred, What Happens |
|---|---|---|
| 1 | [Question] | [Concrete harm from leaving this ambiguous] |
| 2 | [Question] | [Concrete harm] |
| ... | | |
```

Then walk the decisions **one at a time** — one AskUserQuestion call per decision, wait
for the answer, record it, then ask the next:

```
Decision N of T: [Question]
If deferred: [Concrete harm]

A) [Option 1 — proposed by reviewer]
B) [Option 2 — alternative]
C) Defer — accept the risk described above
```

Rules:
- Never combine two decisions into one call, and never ask the user to answer "for each"
  of several numbered items — that is the compound-question failure mode this step
  previously shipped with ("ask decision 3 again").
- Apply each decision's outcome to the PRD (or the deferred-risk list) before asking the
  next question, so a session death mid-way loses at most one decision.

#### Step 4.4: Re-Review (if fixes were applied)

If SPECIFIABLE fixes were applied to the PRD:
1. Re-read the updated PRD
2. Check that fixes don't introduce new contradictions
3. Check that applied fixes actually resolve the original finding
4. If new issues found: fix and re-check (max 3 total loops)

**Convergence guard:** If the same issue appears in 2 consecutive loops, it's not
fixable by spec text alone. Persist it in a "## Reviewer Concerns" section at the
end of the PRD and stop iterating.

#### Step 4.5: Final Report and Cleanup

Present a summary to the user:

```
## PRD Review Complete

**Reviewers:** Product Thinker, UX Designer, Engineering Manager, Customer Expert, QA Expert
**Findings:** X total (Y applied, Z require decisions, W dismissed)
**Acceptance Criteria Quality:** N% GOOD, M% OK, P% BAD (before → after)
**Iterations:** N (max 3)

### Applied Fixes (SPECIFIABLE)
1. [REQ-ID] [what was changed] — found by [reviewer]
2. ...

### Decisions Made by PM
1. [Decision] — chose [option]
2. ...

### Deferred / Reviewer Concerns
1. [Persistent issue] — risk: [what happens]
2. ...

### Persona Coverage
- Board Members: [covered / gaps]
- Customer Admins: [covered / gaps]
- Executives: [covered / gaps]

**Verdict:** PRD is [READY FOR IMPLEMENTATION / NEEDS MORE WORK]
```

A PRD is READY when:
- 0 BAD acceptance criteria remain
- 0 unresolved REQUIRES_DECISION items (all decided or explicitly deferred)
- No P0 findings from any reviewer remain unaddressed

**Cleanup (after the report):** ask via ONE AskUserQuestion whether to delete
`.prd-review/<slug>/` or keep it as an audit trail; if keeping it in a git repo whose
`.gitignore` lacks `.prd-review/`, offer to append that line.

**VIBE handoff note:** if the repo has `.claude/phase.json`, a READY verdict is the
input to the DISCOVERY → ARCHITECTURE_APPROVED transition (made by the user or
orchestrator, not this skill). Mention once; never edit phase.json yourself.

---

## Standalone vs. Invoked Behavior

**Standalone** (`/prd-review [path]`): all 4 phases, full report at the end.
**Invoked from /prd-writer Step 7:** same 4 phases; PRD path comes from /prd-writer
context; after review, control returns to /prd-writer for final iteration if needed.
