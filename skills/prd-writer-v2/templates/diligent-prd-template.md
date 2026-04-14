# Diligent PRD Template (Compact)

Default PRD template — Diligent Boards conventions. Apply quality patterns from `quality-patterns.md` throughout.

**v2 changes:** User pain points live in JTBDs (not Problem Definition). Interaction flows live inline with JTBDs (not separate UX section). UX section covers only structural/cross-cutting concerns.

## Template Structure

```markdown
# [Project Name]

**Area:** [Product / Focus Area]
**Timeframe:** [Quarter - Year]
**TL;DR:** [1-liner: gap + mechanism + projected impact]

## Table of Contents
[Auto-generated markdown links to all H2/H3 sections]

---

# 1. Problem Definition

## Objective
[One sentence: what are you trying to do?]

## Context & Strategic Drivers
[Why this matters. Why now. Strategic alignment. Competitive landscape.
Reference past attempts and outcomes. Do NOT list user pain points here — those
belong as evidence within each JTBD in section 2.]

## Opportunity Size
[Show math: [base] x [rate] = [outcome]. Include conservative/optimistic.
Do NOT restate the table in prose afterward.]

## Success Measures
| Level | Metric |
|-------|--------|
| **Target** | [The ONE metric to optimize] |
| **Secondary** | [Should improve or stay neutral] |
| **Guardrail** | [Must NOT regress] |

---

# 2. Jobs to Be Done & Requirements

[Each JTBD is self-contained: problem, evidence, hypothesis, KPIs, requirements,
and interaction flows — all in one place. This eliminates redundancy between
Problem Definition, Requirements, and UX sections.]

## JTBD-1: [Job statement]

"As a [persona], I need to [job] so that I can [outcome]."

**Evidence:** [User pain points with data/quotes — THIS is where user voice lives]

*Hypothesis:* If we [mechanism], THEN [outcome] because [reasoning].

| | KPI |
|---|---|
| **Primary** | [qual for early-stage, quant for mature] |
| **Secondary** | [measurable backstop] |

**REQ-001: [Name]** (P0)
[Scope paragraph: what, how, key details.]
1. [Observable system behavior with concrete values]
2. [Happy path behavior]
3. [Error/validation behavior]

### Interaction Flow: [Feature Name]
[Inline with the JTBD. Compact numbered steps.]
1. User [trigger]
2. System [response]
3. [Processing/streaming step]
4. Output: [format + sections]

**REQ-002: [Name]** (P1)
[Scope paragraph]
1. [Observable behavior]

**REQ-003: [Name]** (P2)
[Description only]

## JTBD-2: [Job statement]
[...same self-contained structure...]

## Options Analysis (if applicable)
| Dimension | Option A | Option B (Recommended) |
|-----------|----------|----------------------|
| User value | ... | ... |
| Eng cost | ... | ... |
| Risk | ... | ... |

[State the pick and deciding factor. Do NOT restate the table.]

---

# 3. Data Model (if applicable)

[DB tables/columns, API endpoints, state machines, tracking events.]

## API Endpoints
| Method + Path | Purpose | Req ID |
|---------------|---------|--------|
| ... | ... | ... |

## Tracking Requirements
| Event | Payload |
|-------|---------|
| ... | ... |

---

# 4. Business Rules (if applicable)

[Cross-cutting domain logic only. Skip for simple features.
Each rule references the Req IDs it applies to.]

## Permissions & Access Control
[Role-based rules, org restrictions.]

## Validation Rules
[Cross-field, conditional, format rules.]

## Lifecycle & State Transitions
[Valid transitions, triggers, cascading effects.]

---

# 5. Risks & Out of Scope

## Risks with Mitigations
| Risk | Severity | Mitigation |
|------|----------|------------|
| ... | ... | ... |

## Out of Scope
- **[Feature]** — [Why deferred. One line each.]

---

# 6. Legacy Reference (if replacing existing system)

[Current behavior, field mappings, API contracts. Context only — does NOT drive requirements.]

---

# 7. User Experience (Structural)

[v2: This is NOT the largest section. Interaction flows live inline with JTBDs.
This section covers only cross-cutting UX structure.]

## Information Architecture
[Where feature lives. Containment hierarchy. Navigation additions. What doesn't change.]

## ASCII Wireframes (if complex layouts exist)
[Only for multi-panel layouts, forms with 5+ fields, or multi-step state machines.
Place inline with the JTBD they illustrate when possible.]

## Component Specs (new components only)
**ComponentName:** Default: [treatment]. Loading: [treatment]. Error: [treatment]. Click: [behavior]. Constraints: [limits].

## Keyboard & Accessibility
[WCAG requirements. Keyboard nav. ARIA attributes.]

## Use Cases Table
| Use Case | Feature | Trigger | Expected Output |
|---|---|---|---|
| ... | ... | ... | ... |

## Designs
[Link to Figma or note WIP status.]

---

# 8. RACI (if applicable)

| R | A | C | I |
|---|---|---|---|
| PM: | | | |
| ENG: | | | |

---

# 9. Engineering Effort

## P0: MVP
| Component | Scope | Hours (Human) | Hours (Agentic) | BE/FE | Deps |
|-----------|-------|---------------|-----------------|-------|------|
| ... | ... | ... | ... | ... | ... |
| **Total** | | **X** | **Y** | | |

## P1: Fast-Follow (if applicable)
[Same table format. Barriers listed after.]

---

# 10. Other Dependencies (if applicable)

[Cross-product deps, settings toggles, cross-team support, pricing tiers.
Use tables. Include only sections that apply.]

---

# 11. Release Plan (if applicable)

[Service releases, standard process, additional steps.]

---

# 12. Appendix (if applicable)

[Post-launch analysis questions. V2 roadmap. Detailed data.]
```

## Template Notes

- Core sections: 1-5. Everything else is optional based on project complexity.
- JTBD section is the core — self-contained with evidence, requirements, AND interaction flows.
- **Describe once:** If a behavior is fully specified in a requirement, interaction flows and business rules reference by ID, not re-describe.
- **Tables speak for themselves:** Never follow a table with prose restating its contents.
- Diligent-specific sections (RACI, Settings, Pricing) — omit if using custom template.
