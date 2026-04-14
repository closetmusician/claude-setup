---
name: prd-writer-v2
description: "Compact PRD writer — same rigor as prd-writer but 30-40% shorter output. Consolidates redundant sections, enforces 'describe once, reference by ID', and mandates dense formatting. Use when you want a tight, implementation-ready PRD without prose bloat. Same triggers as prd-writer: 'write a PRD', 'spec this out', 'product requirements', etc."
---

## Required Files
- `references/quality-patterns.md` — Quality patterns with density rules
- `references/discovery-brief-format.md` — Condensed 1-pager format for early-stage exploration
- `templates/diligent-prd-template.md` — Compact PRD structure template

# PRD Writer v2 (Compact)

Fork of prd-writer optimized for density. Same quality bar, ~30-40% fewer lines.

**What changed from v1:**
- Sections that repeated info (Problem + JTBD + Interaction Flows) are consolidated — describe once, reference by ID
- Prose that restates tables is banned
- Wireframes are conditional on complexity, not mandatory
- Behavior minimums are guidance, not floors
- Compact formatting preferred (inline pipes, dense bullets) over multi-line prose

## Core Principles

Same as v1, plus three density rules:

1. **Every claim needs a number.** Never "significant improvement" — write "+1.65% OESPD."
2. **Hypotheses, not descriptions.** "If we [X], THEN [Y] because [Z]."
3. **Brutal honesty about prior art.** Document what's been tried, what failed, what's different.
4. **Show the projection math.** Expose derivation: "[base] x [rate] = [outcome]."
5. **User voice, not corporate voice.** "I don't know what to share" not "Users experience friction."
6. **Implementation-ready requirements.** Each P0/P1 gets numbered observable behaviors mapping to test cases.
7. **Hypotheses tied to measurable KPIs.** Each feature gets a KPI table (qual primary for early-stage, quant for mature).

### Density Rules (NEW in v2)

8. **Describe once, reference everywhere.** Every behavior, flow, or rule has ONE canonical location. All other mentions use `-> See AC-2B` or `(per BR-3)`. If you're writing the same logic in two sections, one of them is wrong.

9. **Tables speak for themselves.** Never follow a table with prose restating its contents. If the table needs explanation, the table is poorly structured — fix the table.

10. **Compact over verbose.** Prefer `Agendas 1-3: full wizard | 4-10: quick start | >10: button-only` over 4-line bullet lists saying the same thing. Use inline separators, dense bullets, and compressed conditional notation.

---

## Workflow

### Working Files (Context Preservation)

Same as v1 — intermediary checkpoint files prevent context loss.

**File naming:** Slugify the feature name (e.g., "Board Briefcase" -> `board-briefcase`). If unclear, use `prd-draft-YYYY-MM-DD`.

**Output directory:** Project's `docs/` if it exists, otherwise cwd.

**Intermediary files:**
- `<working-name>-context.md` — Step 1 checkpoint
- `<working-name>-interview.md` — Step 2 checkpoint
- `<working-name>-research.md` — Step 3 checkpoint

**Cleanup:** Delete all three after final PRD is saved.

### Step 0: Resume Detection

Check for existing `*-context.md`, `*-interview.md`, `*-research.md` in `docs/` and project root. If found, offer to resume or start fresh. If not found, proceed to Step 1.

### Step 1: Gather Context

Assess what the user brought (raw notes, brief, verbal description, custom template). Extract: product/feature, target user, problem, data/metrics, prior art, org context. Identify gaps for interview.

**Checkpoint:** Write `<working-name>-context.md` with extracted context and identified gaps.

### Step 2: Interview for Gaps

Ask targeted questions to fill gaps. Group questions efficiently.

**Always ask (if not already provided):**
- Why now? What's the urgency driver?
- Prior art — tried before (internally/competitors)? What happened?
- Success metrics — north star + guardrails?
- Scope boundaries — what's explicitly out?
- KPI measurement approach — mature (quant primary) or early-stage (qual primary)?

**Ask if relevant:**
- Personas and RACI
- UX detail level (flows only / flows + IA / wireframes)
- Tech stack
- Engineering effort estimates
- Cross-team dependencies
- Pricing/release constraints

**Checkpoint:** Write `<working-name>-interview.md` with decisions and Q&A.

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
Objective, context, strategic drivers, success measures. Include "why now." Back with evidence. **Do NOT include user pain points here** — those belong in JTBDs as evidence.

#### Opportunity Size
Show projection math. Reference precedents. Be honest about assumptions.

#### Jobs to Be Done & Requirements

**This is the core. Each JTBD is self-contained — problem, evidence, hypothesis, KPIs, and requirements all in one place.**

**Per-JTBD structure:**
1. JTBD heading with job statement
2. Job statement in persona format
3. Evidence (user pain points with data — this is where "user voice" lives, not in Problem Definition)
4. Hypothesis: *If we [X], THEN [Y] because [Z].*
5. KPI table (qual primary for early-stage, quant for mature)
6. Requirements ordered P0 -> P1 -> P2

**Requirement ID format:** 2-3 letter prefix + number (e.g., AC-1, BRF-2).

**Per-requirement structure (P0/P1):**
```
**REQ-ID: Name** (P0)
[1-paragraph scope. What it does, how it works, key details.]
1. [Observable system behavior — maps to one test case]
2. [Another behavior]
3. [Error/edge case]
```

**P2:** Description only, no numbered behaviors.

**Behavior description rules:**
- Observable system behavior, not user action
- Concrete values: field names, max lengths, valid states
- Each independently falsifiable (one test case per item)
- Order: happy path -> error/validation -> edge cases
- **Guidance:** Most P0s should have 2+ behaviors, but a single well-specified behavior is fine if it's complete

**Priority tiers within each JTBD's build scope:** P0 = must ship, P1 = should ship, P2 = defer.

**Interaction flows belong HERE, inline with the JTBD they serve.** Write a compact numbered flow immediately after the relevant requirement(s). Do NOT duplicate them in a separate UX section.

#### Data Model (if applicable)
Tables/columns, API endpoints, state machines, tracking requirements.

#### Business Rules (if applicable)
Cross-cutting domain logic: permissions, validation, lifecycle rules, calculations. Skip for simple features.

#### Risk
Risks with mitigations + out of scope. Be explicit.

#### Legacy Reference (optional)
Only when replacing existing system. Context only — does NOT drive requirements.

#### User Experience

**v2 change: This is NOT the largest section.** Most interaction detail lives inline with JTBDs. This section covers only structural/cross-cutting UX concerns:

**1. Information Architecture** — Where the feature lives in existing navigation. Containment hierarchy. What does NOT change.

**2. ASCII Wireframes (conditional)** — Only for complex multi-panel layouts, forms with 5+ fields, or multi-step state machines. Simple features skip this. When included, place inline with the JTBD they illustrate (not here).

**3. Component Specs** — For genuinely new UI components only. States, visual treatment, constraints. Use compact format:
```
**ComponentName:** Default: [treatment]. Loading: [treatment]. Error: [treatment]. Click: [behavior]. Constraints: [limits].
```

**4. Keyboard & Accessibility** — WCAG requirements, keyboard navigation, ARIA attributes.

**5. Use Cases Table** — Map scenarios to features, triggers, outputs.

#### Engineering Estimates
Ranges, not points. Backend vs. client split. Staffing needs. Blockers/dependencies.

### Step 5: Output and Present

1. Save PRD as `.md` to output directory
2. Delete checkpoint files
3. Brief summary: what it proposes, key data anchors, sections needing review, next steps

### Step 6: Iterate

Update in place. Each iteration reduces flagged items.

### Step 7: Adversarial Review (Recommended)

Offer `/prd-review` after user is satisfied. Same as v1.

---

## Critique Mode

Same as v1. Score against quality patterns, organize feedback (structural/rigor/clarity/honesty gaps), offer rewrites.

---

## Template Override

Use user's template structure. Apply quality patterns regardless. Suggest missing sections but don't force.

---

## Edge Cases

- **No data:** Flag honestly as "[Data gap: recommend X research]"
- **Very early stage:** Focus on Problem + Opportunity. Mark other sections TBD.
- **User pushes back on rigor:** Help identify obtainable metrics. Frame gaps as action items.
- **Multiple audiences:** Note where detail levels need adjustment.
