# Diligent PRD Template (Compact)

Default PRD template — Diligent Boards conventions. Apply quality patterns from `quality-patterns.md` throughout.

**v2 changes:** User pain points live in JTBDs (not Problem Definition). UX Flows section (§3) is organized by JTBD with explicit req ID references — dedicated but mapped, no redundancy. Describe once, reference by ID.

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

[Each JTBD groups problem, evidence, hypothesis, KPIs, and requirements.
UX flows live in §3 and reference back by req ID.]

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

**REQ-002: [Name]** (P1)
[Scope paragraph]
1. [Observable behavior]

**REQ-003: [Name]** (P2)
[Description only]

## JTBD-2: [Job statement]
[...same structure...]

## Options Analysis (if applicable)
| Dimension | Option A | Option B | Option C (Recommended) |
|-----------|----------|----------|----------------------|
| User value | ... | ... | ... |
| Business value | ... | ... | ... |
| Eng cost | ... | ... | ... |
| Risk | ... | ... | ... |

- **Recommendation:** Option C — [deciding factor]
- [Key tradeoff bullet]
- [Key tradeoff bullet]

---

# 3. UX Flows

[Organized by JTBD. Each flow references req IDs it satisfies.
Don't re-describe requirements — reference by ID.]

## JTBD-1: [abbreviated]

### Flow: [Feature] → REQ-001, REQ-002
1. User [trigger with concrete example]
2. System [response] — [visual treatment]
3. [Processing/streaming step]
4. Output: [format + sections]

### ASCII Wireframe: [Component/Flow Name]
[Use box-drawing characters: ┌ ┐ └ ┘ ─ │ ├ ┤
Show layout, key fields, and interaction affordances.
Include 3-5 wireframes per feature PRD for major interaction patterns.]

## JTBD-2: [abbreviated]
[...same structure...]

## Cross-Cutting UX

### Information Architecture
[Where feature lives. Containment hierarchy. What doesn't change.]

### Component Specs (new components only)
**ComponentName:**
- [Default state]: [visual treatment + content layout]
- [Loading/Live state]: [expanded by default, animation, spinner location]
- [Completed state]: [collapsed summary + expand affordance]
- [Error state]: [visual treatment, error message placement]
- [Empty state]: [placeholder text, call-to-action]
- Click/expand: [what happens on interaction]
- Constraints: [max lines, truncation, scroll behavior]

### Use Cases Table
| Use Case | JTBD | Feature | Trigger | Expected Output |
|---|---|---|---|---|
| ... | ... | ... | ... | ... |

### Designs
[Link to Figma or note WIP status.]

---

# 4. Data Model (if applicable)

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

# 5. Business Rules (if applicable)

[Cross-cutting domain logic only. Skip for simple features.
Each rule references the Req IDs it applies to.]

## Permissions & Access Control
[Role-based rules, org restrictions.]

## Validation Rules
[Cross-field, conditional, format rules.]

## Lifecycle & State Transitions
[Valid transitions, triggers, cascading effects.]

---

# 6. Risks & Out of Scope

## Risks with Mitigations
| Risk | Severity | Mitigation |
|------|----------|------------|
| ... | ... | ... |

## Out of Scope
- **[Feature]** — [Why deferred. One line each.]

---

# 7. Legacy Reference (if replacing existing system)

[Current behavior, field mappings, API contracts. Context only — does NOT drive requirements.]

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

- Core sections: §1 Problem Definition, §2 JTBD & Requirements, §3 UX Flows. Everything else is optional based on project complexity.
- §2 JTBD section is the core — evidence, requirements, and rationale. Requirements flow from the JTBD; don't restate the problem inside each requirement.
- §3 UX Flows is organized by JTBD — each flow references req IDs it satisfies, connecting "what to build" with "what the user sees." No re-describing requirements.
- **Describe once:** If a behavior is fully specified in a requirement, UX flows and business rules reference by ID, not re-describe.
- **Tables speak for themselves:** Never follow a table with prose restating its contents.
- Diligent-specific sections (RACI, Settings, Pricing) — omit if using custom template.
