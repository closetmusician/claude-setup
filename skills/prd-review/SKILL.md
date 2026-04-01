---
name: prd-review
description: "Adversarial PRD review using 5 specialized subagent personas. Probes for ambiguities, hidden complexity, and untestable requirements before execution begins. Use when: user says 'review this PRD', 'critique this spec', 'is this PRD ready', 'adversarial review', or when /prd-writer invokes it at Step 7. Also trigger when user shares an existing PRD and asks if it's implementation-ready."
---

## Required Files
- `references/persona-prompts.md` — System prompts for 5 reviewer personas

# PRD Review

Four-phase adversarial review that catches spec ambiguities before agents hit them
during implementation. Spawns 5 fresh subagents — each sees ONLY the PRD, no
conversation history — to probe from different expert perspectives.

**Model discipline:** This skill is Opus-heavy by design. The synthesis subagent
(Phase 3), Triage (Phase 4.1) AND main agents MUST run as `model: opus`. Phase 2 subagents and others can run on Sonnet. 

**Context discipline:** Phase 2 subagents write their findings to disk. Phases 3 and 4
subagents read files from disk — they never receive raw Phase 2 outputs in context.
The main agent reads only the final triage doc, keeping its context window thin. 

## Core Principle

A PRD is ready for implementation when an agent can build every requirement without
a single AskUserQuestion call. Every ambiguity caught here saves a blocked subagent,
a wrong guess, or a rework cycle during BUILD.

---

## Workflow

### Step 0: Locate the PRD and Set Up Working Directory

Determine the PRD file path:

**If invoked with a path** (e.g., `/prd-review docs/my-feature.md`):
- Read the file. Confirm it exists and looks like a PRD.

**If invoked from /prd-writer:**
- The PRD path was passed in context. Read it.

**If invoked standalone with no path:**
- Search for recent PRD files:
  ```bash
  find . -maxdepth 3 -name "*.md" -newer .git/HEAD -type f 2>/dev/null | head -20
  ```
- Also check common locations: `docs/`, `specs/`, `/mnt/user-data/outputs/`
- Use AskUserQuestion to confirm which file to review:
  ```
  Which PRD should I review?
  A) [most recent .md file found]
  B) [second most recent]
  C) Other — provide path
  ```

Read the full PRD content. Derive a slug from the filename (e.g., `docs/my-feature.md`
→ `my-feature`). Create the working directory for this review run:

```bash
mkdir -p .prd-review/<slug>
```

All intermediary files for this review go under `.prd-review/<slug>/`. This directory
is ephemeral — it can be gitignored. Store the PRD path and slug — all subagents will
need them.

---

### Phase 1: Big Picture Review

Before diving into requirements, challenge the foundational assumptions. This phase
runs in the main agent (no subagent needed — it's fast and cheap).

**Step 1.1: Premise Extraction**

Read the PRD's Problem Definition, TL;DR, and Opportunity Size sections. Extract
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
   same effort? (Adapted from gstack /office-hours demand reality question)
2. **What's the 10X framing?** Is the PRD constraining the solution space? Is there a
   "chief of staff AI" hiding inside a "calendar app"? (Adapted from gstack /plan-ceo-review)
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

**Escape hatches (offer as the LAST question after all premises):**
```
A) Proceed to deep review with adjusted premises (Recommended)
B) Go deeper — run /office-hours or /plan-ceo-review for full strategic treatment
```

If user picks B: invoke the actual gstack skill via the Skill tool (`office-hours` or
`plan-ceo-review`). After it completes, resume Phase 2 with any updated framing.

If user picks A: proceed to Phase 2.

---

### Phase 2: Five-Persona Spec Review

Spawn 5 fresh subagents in parallel. Each agent receives ONLY the PRD text — no
conversation history, no prior context, no premises from Phase 1. Fresh eyes only.

Each subagent **must write its complete findings to disk** before returning. The main
agent does NOT read the subagent return values directly — it reads the files from disk
after all 5 complete. This keeps Phase 2 output out of main context.

Read `references/persona-prompts.md` for the exact system prompts. Each subagent
gets its persona prompt + the full PRD text + the output file path it must write to.

**Spawn all 5 Sonnet subagents in a single message using the Agent tool:**

#### Agent 1: Product Thinker (Sonnet)
- **Focus:** Problem-solution fit, user value, competitive positioning
- **Model:** sonnet
- **Output file:** `.prd-review/<slug>/reviewer-1-product-thinker.md`
- **Draws from:** gstack 6 forcing questions (demand reality, status quo, desperate
  specificity, narrowest wedge, observation & surprise, future-fit)
- **Output format:** Score each sub-dimension 1-10. List issues as SPECIFIABLE or REQUIRES_DECISION.

#### Agent 2: UX Designer (Sonnet)
- **Focus:** User flows, interaction states, information hierarchy, accessibility
- **Model:** sonnet
- **Output file:** `.prd-review/<slug>/reviewer-2-ux-designer.md`
- **Draws from:** gstack design-review first-impression framework + 7-pass design methodology
- **Reviews:** Info architecture, interaction state coverage (loading/empty/error/success),
  user journey completeness, AI slop risk in UX descriptions, responsive/accessibility gaps,
  unresolved design decisions
- **Output format:** Per-dimension score 0-10. For each gap: what a 10 looks like.

#### Agent 3: Engineering Manager (Opus)
- **Focus:** Consistency, clarity, implementability, hidden assumptions
- **Model:** opus
- **Output file:** `.prd-review/<slug>/reviewer-3-eng-manager.md`
- **Draws from:** gstack /plan-eng-review diagram-forcing + od-claude Patrik 4-pass review
- **Checks:**
  - Do parts of the PRD contradict each other?
  - Could an agent implement every requirement without AskUserQuestion?
  - For every data flow: what happens on nil input, empty input, upstream error?
  - For every interaction: double-click, navigate-away, slow connection, stale state,
    back button, rapid resubmit, concurrent actions
- **Output format:** Issues classified as SPECIFIABLE (propose missing spec text) or
  REQUIRES_DECISION (needs PM input). Include proposed text for SPECIFIABLE items.

#### Agent 4: Customer Expert (Sonnet)
- **Focus:** Persona coverage for Diligent Boards' 3 core personas
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

#### Agent 5: QA Expert (Opus)
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
[FULL PRD TEXT]
---
```

**After spawning:** Verify all 5 output files exist before proceeding:
```bash
ls -la .prd-review/<slug>/reviewer-*.md
```
If any file is missing, re-spawn that specific agent before continuing.

---

### Phase 3: Synthesis (Opus Subagent)

Spawn **one Opus synthesis subagent**. This agent reads the 5 reviewer files directly
from disk — it does NOT receive their content in the prompt. This prevents the 5 large
reports from bloating main context.

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
3. If OK: identify what's missing to reach GOOD
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

**After subagent completes:** Verify the file exists:
```bash
ls -la .prd-review/<slug>/synthesis.md
```

Main agent reads only the synthesis file — not the 5 raw reviewer files.

---

### Phase 4: Convergence or Escalation

#### Step 4.1: Triage (Opus Subagent)

Spawn **one Opus triage subagent**. It reads the synthesis file and PRD from disk,
produces a deduplicated finding table, and writes it to disk.

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

Rules:
- Do NOT cherry-pick. Every finding from every reviewer must appear with a disposition.
- For "Applied" findings: include the exact proposed text and the target REQ-ID/section.
- For "Captured" findings: state the decision question + concrete harm if deferred.
- For "Dismissed" findings: state the reason concisely.

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

## AC Quality
Before fixes: N% GOOD, M% OK, P% BAD
After applied fixes: N'% GOOD, M'% OK, P'% BAD (projected)

Write your complete triage to .prd-review/<slug>/triage.md before returning.
```

**After subagent completes:** Verify the file exists:
```bash
ls -la .prd-review/<slug>/triage.md
```

**Main agent now reads `triage.md`.** This is the only Phase 2-3 artifact the main
agent ingests. Its context window at this point contains: PRD + premises from Phase 1
+ triage doc. Everything else lives on disk.

#### Step 4.2: Apply SPECIFIABLE Fixes

For each "Applied" finding from triage.md, edit the PRD directly using the Edit tool.
Make the smallest change that resolves the ambiguity. Preserve the PRD author's voice
and structure.

#### Step 4.3: Present REQUIRES_DECISION Items

Build an Unresolved Decision Table from the "Decisions Needed" section of triage.md
and present via AskUserQuestion:

```
## Unresolved Decisions

| # | Decision Needed | If Deferred, What Happens |
|---|---|---|
| 1 | [Question] | [Concrete harm from leaving this ambiguous] |
| 2 | [Question] | [Concrete harm] |
| ... | | |

For each decision, choose:
A) [Option 1 — proposed by reviewer]
B) [Option 2 — alternative]
C) Defer — accept the risk described above
```

#### Step 4.4: Re-Review (if fixes were applied)

If SPECIFIABLE fixes were applied to the PRD:
1. Re-read the updated PRD
2. Check that fixes don't introduce new contradictions
3. Check that applied fixes actually resolve the original finding
4. If new issues found: fix and re-check (max 3 total loops)

**Convergence guard:** If the same issue appears in 2 consecutive loops, it's not
fixable by spec text alone. Persist it in a "## Reviewer Concerns" section at the
end of the PRD and stop iterating.

#### Step 4.5: Final Report

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

---

## Standalone vs. Invoked Behavior

**Standalone** (`/prd-review` or `/prd-review docs/my-feature.md`):
- Runs all 4 phases
- Full report at the end

**Invoked from /prd-writer Step 7:**
- Same 4 phases
- PRD path passed from /prd-writer context
- After review, returns control to /prd-writer for final iteration if needed
