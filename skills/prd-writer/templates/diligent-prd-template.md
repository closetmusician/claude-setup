# Diligent PRD Template (Compact)

Default PRD template — Diligent Boards conventions. Apply quality patterns from `quality-patterns.md` throughout.

**Structural rules:** User pain points live in JTBDs (not Problem Definition). UX Flows section (§3) is organized by JTBD with explicit req ID references — dedicated but mapped, no redundancy. Business rules are specified inline within §2 requirements (simple rules as acceptance criteria, complex cross-cutting rules as dedicated REQ-IDs). Describe once, reference by ID.

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
belong as evidence within each JTBD in section 2.
ALL language must be user/business-facing. No architecture, protocols, or eng
investigation notes. Frame technical debt as user impact. See quality-patterns §9.]

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
Business rules are specified here — simple constraints inline as acceptance
criteria under the REQ they govern; complex cross-cutting rules (permissions,
state machines, lifecycle) as their own dedicated REQ-IDs.
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
4. [Permission/access constraint, if applicable — e.g. "Only users with Editor role can invoke"]
5. [Validation rule, if applicable — e.g. "Input rejects values exceeding 500 chars; shows inline error"]

**REQ-002: [Name]** (P1)
[Scope paragraph]
1. [Observable behavior]
2. [Constraint/rule that governs this behavior, if applicable]

**REQ-003: [Name]** (P2)
[Description only]

### Cross-Cutting Rules (when complexity warrants dedicated REQ-IDs)

[Use dedicated REQ-IDs for rules that span multiple requirements or JTBDs.
Only use this pattern for genuinely cross-cutting logic — permissions models,
state machines, complex validation chains. Simple per-requirement constraints
stay inline above.]

**REQ-010: [Permission Model / State Machine / Lifecycle Name]** (P0)
[What this rule governs and why it's cross-cutting.]
1. [State/role definition with concrete values]
2. [Transition rule or access matrix entry]
3. [Cascading effect or side-effect]
4. [Error state when rule is violated]

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
Don't re-describe requirements — reference by ID.
Include illustrative edge-case flows showing business rules in action.
These are representative, not exhaustive — eng planning will expand
into the full edge-case matrix.]


### Information Architecture
[Where feature lives. Containment hierarchy. What doesn't change.]


## JTBD-1: [abbreviated]

### Flow: [Feature] → REQ-001, REQ-002
1. User [trigger with concrete example]
2. System [response] — [visual treatment]
3. [Processing/streaming step]
4. Output: [format + sections]

### Edge Flow: [Rule Enforcement] → REQ-010, REQ-001.4
[Illustrative scenario showing a business rule in action.
Purpose: make the rule concrete for stakeholders and designers.
Eng planning will enumerate full edge-case matrix.]
1. User [attempts action that triggers rule]
2. System [checks constraint — reference REQ-ID.behavior#]
3. System [enforces rule — shows error/blocks/redirects]
4. User [recovery path or escalation]

### ASCII Wireframe: [Component/Flow Name]
[Use box-drawing characters: ┌ ┐ └ ┘ ─ │ ├ ┤
Show layout, key fields, and interaction affordances.
Include 3-5 wireframes per feature PRD for major interaction patterns.]

## JTBD-2: [abbreviated]
[...same structure...]


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

# 4. Risks & Out of Scope

## Risks with Mitigations
| Risk | Severity | Mitigation |
|------|----------|------------|
| ... | ... | ... |

## Out of Scope
- **[Feature]** — [Why deferred. One line each.]

---

# 5. Legacy Reference (if replacing existing system)

[Current behavior, field mappings, API contracts. Context only — does NOT drive requirements.]

---

# 6. RACI (if applicable)

| R | A | C | I |
|---|---|---|---|
| PM: | | | |
| ENG: | | | |

---

# 7. Engineering

## 7.1 Effort Estimates

### P0: MVP
| Component | Scope | Hours (Human) | Hours (Agentic) | BE/FE | Deps |
|-----------|-------|---------------|-----------------|-------|------|
| ... | ... | ... | ... | ... | ... |
| **Total** | | **X** | **Y** | | |

### P1: Fast-Follow (if applicable)
[Same table format. Barriers listed after.]

## 7.2 Data Model (if applicable)

[DB tables/columns, API endpoints, state machines, tracking events.]

### API Endpoints
| Method + Path | Purpose | Req ID |
|---------------|---------|--------|
| ... | ... | ... |

### Tracking Requirements
| Event | Payload |
|-------|---------|
| ... | ... |

---

# 8. Other Dependencies (if applicable)

[Cross-product deps, settings toggles, cross-team support, pricing tiers.
Use tables. Include only sections that apply.]

---

# 9. Release Plan (if applicable)

[Service releases, standard process, additional steps.]

---

# 10. Appendix (if applicable)

[Post-launch analysis questions. V2 roadmap. Detailed data.]
```

## Template Notes

- Core sections: §1 Problem Definition, §2 JTBD & Requirements, §3 UX Flows. Everything else is optional based on project complexity.
- §2 JTBD section is the core — evidence, requirements, rationale, AND business rules. Simple constraints (permissions, validation) are acceptance criteria under the REQ they govern. Complex cross-cutting rules (state machines, permission models spanning multiple REQs) get their own REQ-IDs within the JTBD or in a "Cross-Cutting Rules" subsection.
- §3 UX Flows is organized by JTBD — each flow references req IDs it satisfies. Include illustrative edge-case flows showing rules in action (representative, not exhaustive — eng planning expands these).
- **Describe once:** If a behavior is fully specified in a requirement, UX flows reference by ID, not re-describe. Edge flows illustrate rules for stakeholder comprehension.
- **Tables speak for themselves:** Never follow a table with prose restating its contents.
- §7 Engineering groups effort estimates and data model together — effort first (the "how big"), data model second (the "what shape").
- Diligent-specific sections (RACI, Settings, Pricing) — omit if using custom template.
