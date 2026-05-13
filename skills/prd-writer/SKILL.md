---
name: prd-writer
description: "Helps product managers write high-quality, data-driven PRDs (Product Requirements Documents). Compact by default — consolidates redundant sections, enforces 'describe once, reference by ID', and mandates dense formatting. Use whenever a user wants to create a PRD, product spec, product brief, feature spec, or requirements document — including when they say 'write a PRD', 'help me spec this out', 'I need a product doc', 'turn this into a PRD', 'product requirements', or share rough notes/briefs asking to formalize them. Also trigger when the user wants to review, critique, or improve an existing PRD. Enforces data-driven rigor, testable hypotheses, prior-art honesty, and structured engineering estimates. Do NOT use for pure engineering design docs, architecture docs, or technical RFCs that aren't product-facing."
---

## Required Files
- `references/quality-patterns.md` — Quality patterns with density rules
- `references/discovery-brief-format.md` — Standalone stakeholder pitch format (Mode C only)
- `templates/diligent-prd-template.md` — Full PRD structure template (Mode A)
- `templates/prd-lite-template.md` — PRD-Lite 1-pager template (Mode B)

# PRD Writer (Compact)

Optimized for density. Same rigor as verbose PRDs but you must not lose specificity. Execute according to `references/quality-patterns.md`

**Density design choices:**
- Sections that repeated info (Problem + JTBD + Business Rules) are consolidated — describe once, reference by ID
- Business rules live inline in §2 requirements (simple as behaviors, complex as dedicated REQ-IDs) — no separate section
- UX Flows section is dedicated (§3) but organized by JTBD with explicit req ID references + illustrative edge flows — no redundancy
- Data Model lives under §7 Engineering (after effort estimates) — keeps all eng-facing content together
- Prose that restates tables is banned
- Wireframes: 3-5 per feature PRD for major interaction patterns
- Acceptance criteria minimums are guidance, not floors
- Compact formatting preferred (inline pipes, dense bullets) over multi-line prose

## Core Principles

Same as v1, plus three density rules:

1. **Every claim needs a number.** Never "significant improvement" — write "+1.65% OESPD."
2. **Hypotheses, not descriptions.** "If we [X], THEN [Y] because [Z]."
3. **Brutal honesty about prior art.** Document what's been tried, what failed, what's different.
4. **Show the projection math.** Expose derivation: "[base] x [rate] = [outcome]."
5. **User voice, not corporate voice.** "I don't know what to share" not "Users experience friction."
6. **Implementation-ready requirements.** Each P0/P1 gets numbered acceptance criteria mapping to test cases.
7. **Hypotheses tied to measurable KPIs.** Each feature gets a KPI table (qual primary for early-stage, quant for mature).

### End-User POV Rule (Hard Enforcement)

**§1-6 must be written entirely in user-facing language. No exceptions.**

Implementation detail — libraries, protocols, architecture patterns, data schemas, service internals, algorithms, regex patterns, field mappings — belongs ONLY in §7 Engineering or in the TAR. If content cannot be translated to user-facing language or has no direct user/business impact, it does not belong in the PRD.

**The test:** Can a product stakeholder read this sentence and understand why it matters to users? If no — translate to user impact or remove entirely. There is no "sparingly OK" exception for §2 acceptance criteria.

**Acceptance criteria rule:** Each acceptance criterion describes observable system behavior in user terms. Concrete values (field lengths, timeouts, colors) are fine when they describe what the user sees. Internal values (array indices, token budgets, buffer sizes, data field names) fail the test.

**Bad (eng detail in §1-6):**
> "The BFF normalizes the source field on each retrieved_docs entry to a single canonical type: 'chunks, keyword' → 'documents'"

**Good (user-facing in §1-6):**
> "Citation pills are color-coded by source type: gray for documents, purple for web results, orange for news articles"

**Where the eng detail goes:** §7 Engineering or the TAR.

### Density Rules

8. **Describe once, reference everywhere.** Every behavior, flow, or rule has ONE canonical location. All other mentions use `-> See AC-2B` or `(per REQ-010.2)`. If you're writing the same logic in two sections, one of them is wrong.

9. **Tables speak for themselves.** Never follow a table with prose restating its contents. If the table needs explanation, the table is poorly structured — fix the table.

10. **Compact over verbose.** Prefer `Agendas 1-3: full wizard | 4-10: quick start | >10: button-only` over 4-line bullet lists saying the same thing. Use inline separators, dense bullets, and compressed conditional notation.

---

## Workflow

### Working Files (Context Preservation)

Same as v1 — intermediary checkpoint files prevent context loss.

**File naming:** Slugify the feature name (e.g., "Board Briefcase" -> `board-briefcase`). If unclear, use `prd-draft-YYYY-MM-DD`.

**Output directory:** Project's `docs/` if it exists, otherwise cwd.

**Intermediary files:** stored under `docs/temp` if it exists, otherwise cwd
- `<working-name>-context.md` — Step 1 checkpoint
- `<working-name>-interview.md` — Step 2 checkpoint
- `<working-name>-research.md` — Step 3 checkpoint

**Cleanup:** Delete all three after final PRD is generated & saved. Use `AskUserQuestion` to confirm before deleting.

### Step 0: Resume Detection

Check for existing `*-context.md`, `*-interview.md`, `*-research.md` in `docs/` and project root. If found, use `AskUserQuestion` to offer resume vs. start fresh (list which checkpoint files were found). If not found, proceed to Step 0.5.

### Step 0.5: Determine Document Mode

Based on the user's request, determine which format to use:

**Mode A: Full PRD** (default)
Trigger: User asks for a "PRD", "spec", "product requirements", or provides enough context for a full document.
Template: `templates/diligent-prd-template.md` (all 12 sections)

**Mode B: PRD-Lite (1-pager / discovery brief)**
Trigger: User asks for a "1-pager", "discovery brief", "early-stage doc", or explicitly says they don't have enough data for a full PRD.
Template: `templates/prd-lite-template.md` (sections 1, 2, 3, 7 — requirements include numbered acceptance criteria (≥2 per P0), TBD placeholders for 4-6)

**Mode C: Stakeholder Pitch**
Trigger: User explicitly asks for a "pitch brief", "stakeholder alignment doc", or "conversation starter."
Template: `references/discovery-brief-format.md` (standalone format, not expandable to full PRD)

If ambiguous, use `AskUserQuestion` with these options:
- **Full PRD** — All 12 sections, production-grade
- **PRD-Lite** — Problem, JTBD, Engineering Effort; expandable to full PRD later
- **Stakeholder Pitch** — Standalone conversation starter, not expandable

**Default to Mode B** when the user says "discovery brief" or "1-pager." Mode C requires explicit "pitch" or "conversation starter" language.

### Step 1: Gather Context

Assess what the user brought (raw notes, brief, verbal description, custom template). Extract: product/feature, target user, problem, data/metrics, prior art, org context. Identify gaps for interview.

**Checkpoint:** Write `<working-name>-context.md` with extracted context and identified gaps.

### Step 2: Interview for Gaps (MANDATORY — NEVER SKIP)

**HARD GATE:** Execute this step even if the user's input appears complete. "Already covered" is not a reason to skip — user confirmation IS the point. If a mandatory question was answered in Step 1, state your understanding and ask the user to confirm or correct. Do NOT silently assume. Skipping = protocol violation equivalent to skipping TDD.

**Procedure:** Use `AskUserQuestion` for ALL interview questions. Batch into 3 rounds (max 4 questions per call). If a mandatory question was already answered in Step 1, pre-fill your understanding as the question description and ask the user to confirm or correct via the "Other" escape hatch. Do NOT proceed to Step 3 without answers to all 3 rounds.

**Follow-up rule:** After each round, review answers. If any answer is too vague to write a requirement against (e.g., "improve engagement" for M3, or "everyone" for M7), use another `AskUserQuestion` to push for specifics before moving to the next round.

#### Round 1: Context & Users (AskUserQuestion — 3 questions)

| Q# | Header | Question | Options |
|----|--------|----------|---------|
| M1 | Users | "Who exactly uses this — role, context, frequency? What do they already know?" | *(open-ended)* Single persona, Multiple personas (describe primary), Broad audience, Internal team |
| M2 | Current state | "How is this job done today? What's the specific moment of friction or failure?" | *(open-ended)* Manual workaround exists, Competitor tool used, Not done at all, Partially automated |
| M3 | Scope | "What's in scope vs. explicitly out? What's the most likely scope creep risk?" | *(open-ended)* Well-defined boundaries, Still fuzzy — help me define, V1 only — list what to defer, No constraints yet |

#### Round 2: Feature Behavior & Design (AskUserQuestion — 4 questions)

| Q# | Header | Question | Options |
|----|--------|----------|---------|
| M4 | Happy path | "Walk me through the ideal experience: what triggers it, what does the user see at each step, what's the end state?" | *(open-ended)* Simple interaction (1-2 steps), Multi-step workflow, Background process with status, Real-time/streaming |
| M5 | Design | "What should this look like? Any existing patterns to follow, design references, or specific UX expectations?" | *(open-ended)* Follow existing patterns (describe), Have references/mockups, No strong opinion — propose something, Specific requirements (describe) |
| M6 | States | "What does loading, empty, success, and error look like to the user?" | *(open-ended)* Standard patterns fine, Specific requirements (describe), Need streaming/progress states, Haven't considered — help me think through |
| M7 | Priority | "What's the 80/20? What must this absolutely nail vs. nice-to-have polish?" | *(open-ended)* Core behavior is clear (describe), Need help prioritizing, Everything feels P0, Performance/speed is the key |

#### Round 3: Edge Cases & Unhappy Paths (AskUserQuestion — 2 questions)

| Q# | Header | Question | Options |
|----|--------|----------|---------|
| M8 | Failure modes | "What happens on bad input, partial failure, timeout, or concurrent access? What are the 2-3 most likely failure modes?" | *(open-ended)* Known failure modes exist, Haven't considered yet — help me think through, Low-risk — simple CRUD, Complex — multiple failure paths |
| M9 | Recovery | "When something goes wrong, what's the user's recovery path? Can they retry, undo, or is data lost?" | *(open-ended)* Retry is sufficient, Need undo/rollback, Data loss is possible — need safeguards, Depends on failure type (describe) |

#### Ambiguity Probe (AskUserQuestion — after Round 3)

Review all collected context (Step 1 + M1-M9 answers). Use `AskUserQuestion` to surface any terms, behaviors, or scope edges where two engineers could reasonably interpret the spec differently. Propose your interpretation as options and ask the user to confirm or correct. Frame as: "I want to make sure we're aligned on these points before drafting."

**Lean into ambiguity.** Don't limit yourself to 2-3 items — surface every point where the AC could go two ways. Better to over-clarify now than produce vague requirements. Common ambiguity sources: state transitions, permission boundaries, error message content, default values, sort/filter behavior, empty states, concurrent access, "what counts as X."

#### Conditional Questions (AskUserQuestion — when relevant)

After the ambiguity probe, if any of these topics are relevant but unaddressed, batch the most relevant 2-4 into one `AskUserQuestion` call:
Timeline/urgency | Prior art (what's been tried) | North star metric | KPI approach (qual vs quant) | Delivery context (launch vs demo vs internal) | Dependencies on other teams/systems | Data sensitivity / compliance | Accessibility requirements | Cross-team coordination | Pricing/release constraints

**Delivery context calibration** (apply when delivery context is known):

| Context | P0 emphasis | P1 emphasis | Deprioritize |
|---------|------------|------------|-------------|
| Product launch | Data governance, error handling, edge cases | Performance, polish | — |
| Demo/sprint (<3 weeks) | Core happy path, perceived quality, progress feedback | Broad format support, visual polish | Governance, persistence, data retention |
| Internal tool | Core functionality, correctness | Error handling | Polish, onboarding |

#### Completion Criteria

Complete when: all M1-M9 answered or confirmed via `AskUserQuestion`, ambiguity probe resolved, and each answer is concrete enough that two engineers would make the same implementation decision.

**No deferred questions.** Every open question must be resolved via `AskUserQuestion` during this step and incorporated directly into the PRD. Never output an "Open Questions" section — that's a failure to do your job. If a question truly can't be answered yet, flag it as a `[Data gap: recommend X research]` inline where the answer would go, not in a separate section.

**Checkpoint:** Write `<working-name>-interview.md` with all M1-M10 answers, ambiguity resolutions, and conditional Q&A.

### Step 3: Research & Validate

Use web search to strengthen data-driven foundation:
- Competitor features, industry benchmarks, market data
- Evidence supporting or challenging user claims
- Prior art (blog posts, press releases, product announcements)

**Guardrails:** Only verified data. Mark web-sourced vs. user-provided. Flag gaps honestly. Search for counterarguments too.

**Checkpoint:** Write `<working-name>-research.md` with findings.

### Step 4: Draft the PRD

Read reference files before drafting:
1. `templates/diligent-prd-template.md` — section structure
2. `references/quality-patterns.md` — quality bar + density rules

**Section-specific guidance:**

#### TL;DR
One sentence: gap + mechanism + projected impact. Not a description — a pitch.

#### Table of Contents
Always include. Auto-generated links to all H2/H3.

#### Problem Definition
Objective, context, strategic drivers, success measures. Include "why now." Back with evidence. **Do NOT include user pain points here** — those belong in JTBDs as evidence. **All language must be user/business-facing.** No architecture, protocols, libraries, or eng investigation notes. If the "why now" is technical debt or system fragility, frame it as user impact ("users lose data during long sessions") not eng cause ("SignalR lacks token refresh").

#### Opportunity Size
Show projection math. Reference precedents. Be honest about assumptions.

#### Jobs to Be Done & Requirements

**This is the core. Each JTBD is self-contained — problem, evidence, hypothesis, KPIs, requirements, AND business rules all in one place.**

**Anti-bloat principle:** Requirements *fall from* the JTBD — each exists because the job can't be done without it. The JTBD provides the "why"; requirements provide the "what." Don't restate the problem inside each requirement. One sentence of scope, then straight to behaviors.

**Per-JTBD structure:**
1. JTBD heading with job statement
2. Job statement in persona format
3. Evidence (user pain points with data — this is where "user voice" lives, not in Problem Definition)
4. Hypothesis: *If we [X], THEN [Y] because [Z].*
5. KPI table (qual primary for early-stage, quant for mature)
6. Requirements ordered P0 -> P1 -> P2
7. Cross-Cutting Rules subsection (only when complexity warrants dedicated REQ-IDs)

**Requirement ID format:** 2-3 letter prefix + number (e.g., AC-1, BRF-2).

**Per-requirement structure (P0/P1):**
```
**REQ-ID: Name** (P0)
[1-paragraph scope. What it does, how it works, key details.]
1. [Acceptance criterion — maps to one test case]
2. [Another criterion]
3. [Error/edge case]
4. [Permission/validation constraint if applicable]
```

**P2:** Description only, no acceptance criteria.

**Business rules placement (mix approach):**
- **Simple constraints** (field validation, role checks, format rules): inline as acceptance criteria under the REQ they govern (e.g., "4. Only users with Editor role can invoke")
- **Complex cross-cutting rules** (permission models spanning multiple REQs, state machines, lifecycle transitions): dedicated REQ-IDs in a "Cross-Cutting Rules" subsection within the JTBD or at end of §2

**Acceptance criteria rules:**
- Observable system behavior, not user action
- Concrete values: field names, max lengths, valid states
- Each independently falsifiable (one test case per item)
- Order: happy path -> error/validation -> edge cases -> constraints/permissions
- **Minimum count:** Every P0 requirement must have ≥2 acceptance criteria. If you can't identify at least 2, the requirement is too vague — split or rewrite it.

**Priority tiers within each JTBD's build scope:** P0 = must ship, P1 = should ship, P2 = defer.

#### UX Flows

Dedicated section immediately after JTBD & Requirements. Organized by JTBD — each flow references requirement IDs it satisfies. **JTBDs define the "what"; UX flows show the "how."** Don't re-describe requirements, reference by ID (`-> See AC-2`).

**Per-JTBD UX subsection:**

**1. Interaction Flows** — Compact numbered flow per user journey. Each flow:
- References requirement IDs it satisfies (e.g., `→ AC-1, AC-2`)
- Numbered steps: user trigger → system response → final output
- Concrete example inputs
- Streaming/real-time states where applicable

```
### JTBD-1: [abbreviated]
#### Flow: [Feature] → AC-1, AC-2
1. User [trigger]
2. System [response]
3. Output: [format]
```

**2. Edge Flows (illustrative)** — Show business rules in action via representative scenarios. Purpose: make constraints concrete for stakeholders and designers. These are NOT exhaustive — eng planning will expand into the full edge-case matrix. Include 1-2 per JTBD when meaningful rules exist.

```
### Edge Flow: [Rule Name] → REQ-010, REQ-001.4
1. User [attempts action that triggers rule]
2. System [checks constraint]
3. System [enforces — error/block/redirect]
4. User [recovery path]
```

**Guidance note in template:** "Eng planning will enumerate the full edge-case matrix from these illustrative flows."

**3. ASCII Wireframes (for major interaction patterns)** — Include 3-5 per feature PRD. Use box-drawing characters (┌ ┐ └ ┘ ─ │ ├ ┤). Focus on complex multi-panel layouts, forms with many fields, state machines, and multi-step workflows. Place with the JTBD flow they illustrate.

**Cross-cutting UX (once, after all JTBD flows):**

**4. Information Architecture** — Where feature lives. Containment hierarchy. What doesn't change.

**5. Component Specs (new components only):**
For each new UI component, define:
- **States**: all visual states (default, loading, completed, error, empty)
- **Visual treatment**: background, borders, colors, layout (reference design system tokens)
- **Interaction behavior**: click, expand, filter, hover
- **Constraints**: max lines, truncation, scroll behavior

```
**ComponentName:**
- [State]: [visual treatment + content layout]
- [State]: [visual treatment + content layout]
- Click/expand: [behavior]
- Constraints: [limits]
```

**6. Use Cases Table** — Map scenarios to JTBDs, features, triggers, outputs.

#### Risks & Out of Scope
Risks with mitigations + out of scope. Be explicit.

#### Legacy Reference (optional)
Only when replacing existing system. Context only — does NOT drive requirements.

#### Engineering (§7)
Two subsections: (1) Effort Estimates — ranges, not points; backend vs. client split; staffing needs; blockers/dependencies. (2) Data Model (if applicable) — tables/columns, API endpoints, state machines, tracking requirements. Effort first, data model second.

### Step 5: Output and Present

1. Save PRD as `.md` to output directory
2. Delete checkpoint files
3. Brief summary: what it proposes, key data anchors, sections needing review, next steps

### Step 6: Iterate

Update in place. Each iteration reduces flagged items.

### Step 7: Adversarial Review (Recommended)

Use `AskUserQuestion` to offer `/prd-review` after user is satisfied:
- **Run adversarial review** — 5 specialized personas probe for ambiguities and hidden complexity
- **Skip for now** — PRD is ready as-is

---

## Critique Mode

Same as v1. Score against quality patterns, organize feedback (structural/rigor/clarity/honesty gaps), offer rewrites.

---

## Template Override

Use user's template structure. Apply quality patterns regardless. Suggest missing sections but don't force.

---

## Edge Cases

- **No data:** Flag honestly as "[Data gap: recommend X research]"
- **Very early stage:** Use Mode B (PRD-Lite) per Step 0.5. Same section structure as full PRD, same behavior requirements for P0/P1, reduced depth for §3 UX Flows, TBD markers for §4-6.
- **User pushes back on rigor:** Help identify obtainable metrics. Frame gaps as action items.
- **Multiple audiences:** Note where detail levels need adjustment.
