# Quality Patterns for High-Impact PRDs (Compact)

Patterns from exemplary PRDs. v2 adds density rules that cut ~30% without losing rigor.

## Table of Contents
1. [Executive Summary](#executive-summary)
2. [Problem Definition](#problem-definition)
3. [Data-Driven Rigor](#data-driven-rigor)
4. [Differentiation & Prior Art](#differentiation)
5. [User Experience Depth](#user-experience)
6. [Engineering Estimation](#engineering)
7. [Risk & Skepticism](#risk-and-skepticism)
8. [Opportunity Sizing](#opportunity-sizing)
9. [Writing Density](#writing-density) **(NEW in v2)**

---

## 1. Executive Summary <a name="executive-summary"></a>

~100 words. Four jobs: name the gap, cite precedent, quantify the prize, state the mechanism.

**Anti-pattern:** "We will improve the experience" with no numbers.

**Pattern:**
> "[Platform] is becoming too [problem]. [Competitor] pulls [segment] away.
> [Past experiment] shows [mechanism] works — [metric]. Past [attempt] suffered [barriers].
> We solve via [approach]. [Tactic A] + [Tactic B] unlocks [projected impact]."

---

## 2. Problem Definition <a name="problem-definition"></a>

### User Problems as Evidence Inside JTBDs
**v2 change:** User pain points belong in the JTBD "Evidence" section, not in a standalone Problem Definition block. This eliminates the #1 source of cross-section redundancy.

Each pain point: first-person voice + evidence.
```
**Evidence:**
- "I [pain point]" — [data/research link]
- "I [pain point]" — [quote/study]
```

### Hypotheses Format
Testable hypothesis + KPI table per JTBD:

> *If we [mechanism], THEN [outcome] because [reasoning].*

| | KPI |
|---|---|
| **Primary** | [qual for early-stage: ">=3/5 beta users cite X"] |
| **Secondary** | [quant: ">50% items receive status update before due"] |

### Requirement IDs
Short prefix + number: `AC-1`, `BRF-2`, `AUTH-3`. Enables reference in code, tests, commits.

### Behavior Descriptions
Each P0/P1 requirement gets numbered behaviors mapping to test cases:
```
**REQ-1: Name** (P0)
[Scope paragraph.]
1. [Observable system behavior with concrete values]
2. [Happy path]
3. [Error/edge case]
```

**Rules:** Observable system behavior (not user action). Concrete values. Independently falsifiable. Happy path first, then errors, then edge cases.

**Guidance:** Most P0s should have 2+ behaviors. A single well-specified behavior is acceptable if complete.

---

## 3. Data-Driven Rigor <a name="data-driven-rigor"></a>

Every claim backed by: internal data, analogous product data, user research, or market data.

**Quantification rules:**
- Never "significant improvement" — say "+1.65% OESPD"
- Never "good engagement" — say "9.75% CTR"
- Show projection math: `[base] x [rate] = [outcome]`
- Include confidence intervals when available

---

## 4. Differentiation & Prior Art <a name="differentiation"></a>

**Prior Attempts Table:** Rows = attempts. Columns = "How different?" + "Why worth trying."

**"Reasons to Be Skeptical":** What went wrong before. Why each failure doesn't apply (or does). Honest remaining risks.

---

## 5. User Experience Depth <a name="user-experience"></a>

**v2 change:** UX detail is distributed, not centralized.

### Interaction Flows — Inline with JTBDs
Flows live inside the JTBD they serve, immediately after relevant requirements. Compact numbered steps:
```
1. User [trigger with concrete example]
2. System [response] — [visual note]
3. [Streaming/processing]
4. Output: [format], sections: [list]
```

**Rules:** Concrete inputs. Include streaming states. Describe system behavior. End with output format.

### ASCII Wireframes — Conditional
**Only for:** complex multi-panel layouts, forms with 5+ fields, multi-step state machines.
**Skip for:** simple forms, single-panel views, standard CRUD.
When included, place inline with the JTBD they illustrate.

### Component Specs — Compact Format
For new UI components only. One-line-per-component when possible:
```
**ComponentName:** Default: [treatment]. Loading: [treatment]. Error: [treatment]. Click: [behavior]. Constraints: [limits].
```

Expand to multi-line only for genuinely complex components with 4+ states.

### Information Architecture
Where the feature lives. Containment hierarchy. Navigation changes. What stays the same.

### Use Case Table
| Use Case | Feature | Trigger | Expected Output |
|---|---|---|---|

---

## 6. Engineering Estimation <a name="engineering"></a>

P0 (MVP) and P1+ tables. Component breakdown. Backend vs. client. Ranges, not points. Staffing + barriers.

---

## 7. Risk & Skepticism <a name="risk-and-skepticism"></a>

**Risks:** Operational, technical, strategic — each with mitigation. Table format.
**Out of Scope:** What you're NOT doing. One line per item with rationale.

---

## 8. Opportunity Sizing <a name="opportunity-sizing"></a>

**Evidence Pyramid:** Direct signals -> Adjacent signals -> Cross-platform -> Research.
**Projection math:** Show derivation. `[base] from [channel] at [rate] (per [precedent]) = [outcome]`.

---

## 9. Writing Density (NEW in v2) <a name="writing-density"></a>

These rules distinguish v2 from v1. They target the specific verbosity patterns found in PRD output.

### Rule: Describe Once, Reference by ID
Every behavior, flow, or rule has ONE canonical location. All other mentions reference by ID.

**Bad:** Describing the same copy-review workflow in AC-2B, then again in "Interaction Flow: Enhanced Copy," then again in Business Rules.
**Good:** Full spec in AC-2B. Interaction flow says `-> See AC-2B for full behavior.` Business rule says `(per AC-2B)`.

### Rule: Tables Speak for Themselves
Never follow a table with prose restating its contents.

**Bad:**
```
| Metric | Value |
| Users | 10K |
| CTR | 9.75% |

As shown above, we have 10K users and a CTR of 9.75%...
```
**Good:** Just the table. If it needs explanation, restructure the table.

### Rule: No Editorial Justification in Recommendations
State the pick and the deciding factor. Cut the advocacy prose.

**Bad:** "LLMs are the future of intelligent software; shipping rules-only means throwaway infrastructure..."
**Good:** "Recommendation: Option B (LLM-powered). Only approach enabling draft generation; hallucination risk manageable via structured prompts + human review."

### Rule: Compact Conditional Notation
Use inline separators for graduated/conditional logic.

**Bad (4 lines):**
```
- First 3 agendas: full wizard with onboarding tooltips
- Agendas 4-10: streamlined quick start, no tooltips
- After 10: wizard offered via button only, not auto-triggered
- Idle nudge disabled after 3 consecutive dismissals
```
**Good (1-2 lines):**
```
Agendas 1-3: full wizard + tooltips | 4-10: quick start | >10: button-only.
Idle nudge disabled after 3 dismissals. User override in settings.
```

### Rule: Scope Paragraphs Are Tight
Requirement scope paragraphs explain what + how in 2-3 sentences max. Implementation minutiae (LLM temperature, JSON schema shapes, UI micro-interactions) belong in Business Rules or Data Model, not scope paragraphs.

### Rule: Out of Scope Is One Line Each
**Bad:** "Cross-org intelligence — V1 uses org-specific history only. Anonymized cross-org patterns (leveraging Diligent's dataset) is a future exploration pending legal/privacy review."
**Good:** "Cross-org intelligence — future; pending legal/privacy review."
