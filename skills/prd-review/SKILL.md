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

## Core Principle

A PRD is ready for implementation when an agent can build every requirement without
a single AskUserQuestion call. Every ambiguity caught here saves a blocked subagent,
a wrong guess, or a rework cycle during BUILD.

---

## Workflow

### Step 0: Locate the PRD

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

Read the full PRD content. Store it — all subagents will receive this text.

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

**Step 1.3: Present Premises to User**

Show the premises and challenge questions. Use AskUserQuestion:
```
I found these implicit premises in the PRD. Confirm or adjust before the
deep review:

1. PREMISE: [claim] — Evidence: [quote]. Risk if wrong: [consequence].
2. PREMISE: [claim] — ...
3. ...

Challenge: [The strongest challenge question from 1.2]

A) Premises are correct, proceed to deep review
B) Let me adjust some premises first
C) Go deeper — run /office-hours or /plan-ceo-review for full treatment
```

If user picks C: invoke the actual gstack skill via the Skill tool (`office-hours` or
`plan-ceo-review`). After it completes, resume Phase 2 with any updated framing.

If user picks A or B: apply adjustments and proceed.

---

### Phase 2: Five-Persona Spec Review

Spawn 5 fresh subagents in parallel. Each agent receives ONLY the PRD text — no
conversation history, no prior context, no premises from Phase 1. Fresh eyes only.

Read `references/persona-prompts.md` for the exact system prompts. Each subagent
gets its persona prompt + the full PRD text.

**Spawn all 5 in a single message using the Agent tool:**

#### Agent 1: Product Thinker (Sonnet)
- **Focus:** Problem-solution fit, user value, competitive positioning
- **Model:** sonnet
- **Draws from:** gstack 6 forcing questions (demand reality, status quo, desperate
  specificity, narrowest wedge, observation & surprise, future-fit)
- **Output format:** Score each sub-dimension 1-10. List issues as SPECIFIABLE or REQUIRES_DECISION.

#### Agent 2: UX Designer (Sonnet)
- **Focus:** User flows, interaction states, information hierarchy, accessibility
- **Model:** sonnet
- **Draws from:** gstack design-review first-impression framework + 7-pass design methodology
- **Reviews:** Info architecture, interaction state coverage (loading/empty/error/success),
  user journey completeness, AI slop risk in UX descriptions, responsive/accessibility gaps,
  unresolved design decisions
- **Output format:** Per-dimension score 0-10. For each gap: what a 10 looks like.

#### Agent 3: Engineering Manager (Opus)
- **Focus:** Consistency, clarity, implementability, hidden assumptions
- **Model:** opus
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

THE PRD:
---
[FULL PRD TEXT]
---
```

**Wait for all 5 agents to complete.** Read all 5 outputs.

---

### Phase 3: Executability Adversarial Pass

This phase runs in the main agent after reading all Phase 2 outputs. It synthesizes
findings and adds its own adversarial analysis.

**Step 3.1: Cross-Reviewer Synthesis**

Categorize every finding from Phase 2:

| Category | Meaning | Priority |
|---|---|---|
| **Reinforcing** | 2+ reviewers flagged the same issue | HIGHEST — definitely a real problem |
| **Unique** | Only one reviewer found it | MEDIUM — may be real or perspective-specific |
| **Conflicting** | Reviewers disagree about a requirement | HIGH — surface the disagreement to PM |

**Step 3.2: Acceptance Criteria Audit**

Walk every P0 and P1 requirement in the PRD. For each:
1. Grade as BAD / OK / GOOD (use QA Expert's grades, verify independently)
2. If BAD: write a GOOD replacement (SPECIFIABLE)
3. If OK: identify what's missing to reach GOOD

**Step 3.3: Shadow Path Tracing**

For every data flow in the PRD:
- What happens on nil/null input?
- What happens on empty input (empty string, empty array)?
- What happens when upstream service errors?
- What happens on timeout?

For every user interaction:
- Double-click on submit button?
- Navigate away mid-operation?
- Slow connection (3G)?
- Stale state (opened tab 2 hours ago)?
- Back button after completion?
- Rapid resubmit?
- Concurrent actions from two tabs?

If any of these are unspecified in the PRD, add them as SPECIFIABLE findings with
proposed behavior.

**Step 3.4: Failure Scenario Generation**

For each major feature (top-level JTBD), write one realistic scenario:
```
SCENARIO: [Feature name]
An agent implementing this PRD would [specific wrong behavior] because
the spec says [quote] but doesn't specify [missing detail]. Two competent
engineers would build different things here.
PROPOSED SPEC ADDITION: [exact text to add]
```

---

### Phase 4: Convergence or Escalation

**Step 4.1: Compile All Findings**

Merge findings from Phases 2 and 3 into a single deduplicated list.
Every finding gets exactly one disposition:

| Disposition | Meaning | Action |
|---|---|---|
| **Applied** | SPECIFIABLE fix — proposed text is unambiguous | Apply directly to PRD |
| **Captured** | REQUIRES_DECISION — PM must choose | Add to Unresolved Decision Table |
| **Dismissed** | False positive or out of scope | Note reason, no action |

**Do not cherry-pick.** Every finding from every reviewer must appear in the triage
table with a disposition.

**Step 4.2: Apply SPECIFIABLE Fixes**

For each "Applied" finding, edit the PRD directly using the Edit tool. Make the
smallest change that resolves the ambiguity. Preserve the PRD author's voice and
structure.

**Step 4.3: Present REQUIRES_DECISION Items**

Build an Unresolved Decision Table and present via AskUserQuestion:

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

**Step 4.4: Re-Review (if fixes were applied)**

If SPECIFIABLE fixes were applied to the PRD:
1. Re-read the updated PRD
2. Check that fixes don't introduce new contradictions
3. Check that applied fixes actually resolve the original finding
4. If new issues found: fix and re-check (max 3 total loops)

**Convergence guard:** If the same issue appears in 2 consecutive loops, it's not
fixable by spec text alone. Persist it in a "## Reviewer Concerns" section at the
end of the PRD and stop iterating.

**Step 4.5: Final Report**

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
