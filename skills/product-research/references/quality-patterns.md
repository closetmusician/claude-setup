---
name: quality-patterns
description: "9 quality patterns defining the bar for each PRD section — read at Step 4.2"
---

# Quality Patterns for PRDs

These patterns define the quality bar for the PRD produced in Step 4.2. They are reverse-engineered from exemplary PRDs and distinguish a document that moves teams to action from one that merely fills in sections.

Read this file before drafting the PRD in Step 4.2.

---

## Core Principles

1. **Every claim needs a number.** Never write "significant improvement" — write the specific metric. Never write "good engagement" — write the rate. If the number doesn't exist yet, say so honestly and mark as [NEEDS PM INPUT] with what data would fill the gap.
2. **Hypotheses, not descriptions.** Features should be stated as "If we [X], THEN [Y] because [Z]." This forces causal clarity and makes success measurable.
3. **Brutal honesty about prior art.** If something similar has been tried before (internally or by competitors), document it. What happened? Why didn't it work? What's actually different this time? A "Reasons to Be Skeptical" section builds credibility.
4. **Show the projection math.** Opportunity sizing should expose the derivation: "[base] x [rate] = [outcome]" with the rate sourced from a real precedent. Use Phase 1.4 (Industry & Competitor Research) and Phase 1.6 (Metrics) data.
5. **User voice, not corporate voice.** Problems should be stated as "I don't know what to share" not "Users experience a content creation friction point." Use persona language from Phase 1.1 and 1.2.
6. **Implementation-ready requirements.** Every P0/P1 requirement gets a short ID (prefix + number) and numbered behaviour descriptions. Each numbered item is an observable system behaviour with concrete values that maps to one test case.
7. **Hypotheses tied to measurable KPIs.** Each JTBD's hypothesis gets a KPI table with primary and secondary metrics. For early-stage products or features without instrumentation, use qualitative primary + quantitative secondary. For mature products, use quantitative primary.

---

## Pattern 1: TL;DR as a Pitch

The TL;DR is not a description — it's a pitch. One sentence that names the gap, the mechanism, and the projected impact.

**Anti-pattern:** "This PRD proposes improvements to the sharing experience."
**Pattern:** "[Product area] loses [X% of users / $Y revenue / Z deals] because [specific friction]. By [mechanism from Solution Synthesis], we can [projected impact]. [Precedent from Phase 1.4] shows this approach works."

---

## Pattern 2: Problem Definition with User Voice

Frame problems from the user's perspective, not the company's. Each problem should be a real pain point backed by Phase 1 research, stated in first person ("I [verb]..." not "Users need..."), and paired with evidence.

---

## Pattern 3: Hypothesis + KPI Format

Each JTBD gets an explicit hypothesis with a KPI measurement table:

> _If we_ [mechanism from Solution Synthesis], _THEN_ [outcome] _because_ [reasoning from Problem Definition].

| | KPI |
|---|---|
| **Primary** | [measurement approach — qual or quant depending on product maturity] |
| **Secondary** | [metric with target threshold] |

---

## Pattern 4: Requirement ID System

Every requirement gets a short prefix ID (2-3 letters from the feature name) + sequential number: `PREFIX-N: Descriptive name`

Examples: SHR-1, QNA-2, COL-3

---

## Pattern 5: Numbered Behaviour Descriptions

Each P0/P1 requirement gets numbered behaviour descriptions. Each numbered item is an observable system behaviour that maps to one test case.

**Rules:** concrete values, independently falsifiable, happy path first then errors then edge cases, minimum 2 per P0, P2 gets description only.

---

## Pattern 6: Data-Driven Rigor

Every claim backed by research data, internal experiment data, analogous product data, or user research. Never say "significant improvement" — cite the metric. Show projection math with precedents.

---

## Pattern 7: Prior Art & "Reasons to Be Skeptical"

Include prior attempts table and honest risk assessment when Phase 1.4 or Phase 2 identified prior attempts.

---

## Pattern 8: Opportunity Sizing

Build with direct signals (Phase 1.6), friction signals (Phase 1.3), competitive signals (Phase 1.4), qualitative signals (Phase 1.1/1.2). Show the projection math.

---

## Pattern 9: Anti-Bloat Principle

Requirements should fall naturally from the JTBD they live under — each one exists because the job cannot be done without it. If a requirement doesn't clearly serve its parent JTBD, it is either misplaced or unnecessary.

**Test:** For every requirement, ask: "If I remove this, can the JTBD still be satisfied?" If yes, the requirement is either a nice-to-have (move to P2) or belongs under a different JTBD.

**Anti-pattern:** Requirements that restate the problem or motivation inside each requirement body. The JTBD provides the "why"; requirements provide the "what" — one sentence of scope, then straight to observable behaviours.

---

## Pattern 10: Writing Style

Confident but honest, link-dense, specific over general, user voice, decisive, VP-readable.
