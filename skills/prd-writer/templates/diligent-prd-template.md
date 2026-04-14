# Diligent PRD Template

This is the default PRD template based on Diligent Boards conventions. When generating a full PRD, follow this structure. Apply quality patterns from `quality-patterns.md` throughout.

## Template Structure

```markdown
# [Project Name]

**Area:** [Product / Focus Area]
**Timeframe:** [Quarter - Year]
**TL;DR:** [1-liner for what this project is about]

## Table of Contents
[Auto-generated markdown links to all H2/H3 sections]

---

# 1. Problem Definition

## Objective
[One sentence: what are you trying to do?]

## Context & Strategic Drivers
[Describe the problem or opportunity. Include:
- Why this matters to customers
- Why now? What business needs drive prioritization?
- How this ties to strategic goals / vision
- Key user insights and competitive insights
- Reference past attempts and their outcomes]

## Opportunity Size
[Show your math. Use baseline metrics, conversion rates from comparable products,
and clear reasoning. Include optimistic and conservative estimates.]

## Success Measures
[Define metric hierarchy:]
- **Target Metric:** [The ONE metric to optimize]
- **Secondary Metrics:** [Should improve or stay neutral]
- **Guardrail Metrics:** [Must NOT regress]

---

# 2. Jobs to Be Done & Requirements

[Each JTBD groups together the requirements needed to satisfy that job.
Requirements within each JTBD are ordered P0 first, then P1, then P2.]

## JTBD-1: [Job statement]

"As a [persona], I need to [job] so that I can [outcome]."

[Evidence backing this job — user research, data, quotes]

*Hypothesis:* If we [mechanism], THEN [outcome] because [reasoning].

| | KPI |
|---|---|
| **Primary (qual)** | [qualitative measurement] |
| **Secondary (quant)** | [quantitative metric with target threshold] |

**REQ-001: [Name]** (P0)
[1-paragraph scope description explaining what this requirement does,
how it works, and key technical details.]
1. [Observable system behavior with concrete values — maps to one test case]
2. [Another behavior — happy path]
3. [Error/validation behavior]
4. [Edge case or boundary condition]

**REQ-002: [Name]** (P0)
[Scope paragraph]
1. [Observable system behavior]
2. [Another behavior]

**REQ-003: [Name]** (P1)
[Scope paragraph]
1. [Observable system behavior]
2. [Another behavior]

**REQ-004: [Name]** (P2)
[Description only — no numbered behaviors needed for P2]

## JTBD-2: [Job statement]

"As a [persona], I need to [job] so that I can [outcome]."

[Evidence backing this job]

**REQ-005: [Name]** (P0)
[Scope paragraph]
1. [Observable system behavior]
2. [Another behavior]
3. [Edge case]

[...continue for each JTBD...]

## Options Analysis (if applicable)
[For larger projects, assess 2-3 different approaches:]

| Dimension | Option A | Option B | Option C (Recommended) |
|-----------|----------|----------|----------------------|
| User value | ... | ... | ... |
| Business value | ... | ... | ... |
| Eng cost | ... | ... | ... |
| Risk | ... | ... | ... |

[If past attempts exist, include a Differentiation table — see quality-patterns.md Pattern 4]

---

# 3. UX Flows

[Organized by JTBD — each subsection maps flows to the job it serves.
Flows reference requirement IDs (e.g., REQ-001) to connect "what to build"
with "what the user experiences." Don't re-describe requirements — reference them.]

## JTBD-1: [Job statement — abbreviated]

### Interaction Flow: [Feature Name] → REQ-001, REQ-002
1. User does [trigger action with concrete example]
2. System responds with [response] — [visual treatment note]
3. [Real-time streaming/processing step if applicable]
4. Final output renders as [format] with sections: [list sections]
5. [Post-output action if any]

### ASCII Wireframe: [Component/Flow Name]
[Use box-drawing characters: ┌ ┐ └ ┘ ─ │ ├ ┤
Show layout, key fields, and interaction affordances.
Focus on complex multi-panel layouts, forms with many fields,
state machines, and multi-step workflows.]

## JTBD-2: [Job statement — abbreviated]

### Interaction Flow: [Feature Name] → REQ-005
[...same structure...]

## Cross-Cutting UX

### Information Architecture
[Where feature lives. Containment hierarchy. Navigation additions. What doesn't change.]

### Component Specs (new components only)
[States, visual treatment, constraints for genuinely new UI components.]

### Use Cases Table
| Use Case | JTBD | Feature | Trigger | Expected Output |
|---|---|---|---|---|
| [Scenario name] | JTBD-1 | [Which feature] | [Exact user input] | [What system produces] |

## Designs
[Link to Figma or embed design references. Note if designs are WIP.]

---

# 4. Data Model (if applicable)

[When the feature introduces new data structures, document them here:]
- New database tables/columns with types, FKs, constraints
- API endpoint signatures and response shapes
- State machines with valid transitions

## Data or Tracking Requirements
| Tracking Change | Details |
|----------------|---------|
| ... | ... |

---

# 5. Business Rules (if applicable)

[Document domain logic that cuts across multiple requirements or JTBDs.
This section captures rules that are too cross-cutting for a single requirement
but too important to leave implicit.]

## Permissions & Access Control
[Who can do what. Role-based rules, org-level restrictions, delegation logic.]

## Validation Rules
[Field-level and entity-level validation constraints not covered by individual
requirements. Cross-field dependencies, conditional validation, format rules.]

## Lifecycle & State Transitions
[Entity lifecycle rules that span multiple JTBDs. Valid state transitions,
automatic triggers, time-based rules, cascading effects.]

## Calculations & Derived Values
[Formulas, aggregation rules, derived fields. How computed values update
when inputs change.]

---

# 6. Risks & Out of Scope

## Cons/Risks with Mitigations
[For each risk: state it, rate severity, list mitigations]

## Out of Scope
[Explicitly state what you're NOT doing and why]

---

# 7. Legacy Reference (if replacing existing system)

[When replacing a legacy system, document current behavior here as reference
material. Include: how the current system works, screenshots, field mappings,
API contracts. This section is for context — it does NOT drive requirements.
Never place legacy system details before the JTBD & Requirements section.]

---

# 8. RACI

| Responsible (Doing the Work) | Accountable (Owners + Approvers) | Consulted (Providing Feedback) | Informed (Knows this is happening) |
|------------------------------|----------------------------------|-------------------------------|-----------------------------------|
| PM: [name] | [name] | [names] | [names] |
| ENG: [name] | | | |
| DES: [name] | | | |

---

# 9. Engineering Effort

[Break down by component. Include parallelization notes.]

## P0: MVP

| Component | Scope Description | Est. Hours (Human) | Est. Hours (Agentic/Claude Code) | Backend vs. Client | Dependencies |
|-----------|------------------|-------------------|--------------------------------|-------------------|-------------|
| ... | ... | ... | ... | ... | ... |
| **Total** | | **X hrs** | **Y hrs** | | |

*Eng Needed: [specific roles]*
*Parallelization notes: [what can run in parallel]*

## P1: Fast-Follow (if applicable)

| Component | Scope Description | Est. Hours (Human) | Est. Hours (Agentic/Claude Code) | Backend vs. Client | Dependencies |
|-----------|------------------|-------------------|--------------------------------|-------------------|-------------|
| ... | ... | ... | ... | ... | ... |

*Barriers to consider:* [list specific risks to timeline]

---

# 10. Other Dependencies & Requirements

### Cross Product Dependencies
| Product | Details |
|---------|---------|
| Mobile/Web | [Does this need to exist across platforms?] |
| ... | ... |

### Settings Toggles
| Toggle | Functionality | Default State |
|--------|-------------|---------------|
| ASA / Director Settings | [description] | On/Off |
| BWCA / Admin Site Settings | [description] | On/Off |
| CSP / CSM admin page | [description] | On/Off |

### Cross Team Support
| Type of Support | Needs Review | Point of Contact |
|----------------|-------------|-----------------|
| Legal | Y/N | [name] |
| Security | Y/N | [name] |
| Translation | Y/N | [name] |
| Product Marketing | Y/N | [name] |
| Help Center Content | Y/N | [name] |
| Training Team | Y/N | [name] |

### Pricing Tiers
| Pricing Plan | Description | Feature Included |
|-------------|------------|-----------------|
| All Legacy Plans | Existing contracts | Y/N |
| Foundation | SMBs / Private under $100M | Y/N |
| Essential | Small Public Companies | Y/N |
| Pro | Medium Public Companies | Y/N |
| Plus | Large Public Global Companies | Y/N |

---

# 11. Release Plan

## Service Releases
| Service | Required? |
|---------|----------|
| Bcore (2-3 week release time) | Y/N |

## Standard Release Process
| Step | Details |
|------|---------|
| Dogfooding & QA | [date/status] |
| Pre-Release Communications (2 weeks before) | [channels/audience] |
| Release Communications | [channels/audience] |

## Additional Steps
| Step | Details |
|------|---------|
| Beta/Pilot program? | [details] |
| Customer-specific build? | [details] |

---

# 12. Appendix (if applicable)

[Include only when sufficient data exists. Candidates:]
- Opportunity sizing details with source data
- Reasons to be skeptical (with mitigations)
- Learnings from past attempts (detailed tables)
- Alternative designs explored
- Competitive analysis

## Post Launch Analysis
[Questions to answer after release. How long needed for analysis?]
```

## Template Notes

- Not every section is required for every project. Small projects can skip Options Analysis, Business Rules, Data Model, Pricing Tiers, Legacy Reference, etc.
- Core sections: §1 Problem Definition, §2 JTBD & Requirements, §3 UX Flows — these three form the backbone of every PRD
- §2 JTBD & Requirements is the core — each JTBD groups its requirements together so developers understand the "why." Requirements flow from the JTBD; don't restate the problem inside each requirement.
- §3 UX Flows is organized by JTBD — each flow references the requirement IDs it satisfies, connecting "what to build" with "what the user sees." Don't re-describe requirements; reference by ID.
- Requirements within each JTBD are ordered P0 first, then P1, then P2 (not separated into priority subsections)
- Always include a Table of Contents after the TL;DR with auto-generated markdown links to all H2/H3 sections
- Diligent-specific sections (RACI, Settings Toggles, Cross Team Support, Pricing Tiers) are positioned after core sections — omit if using a custom template
- The Legacy Reference section (§7) is optional — only include when replacing an existing system
- The Business Rules section (§5) is optional — only include when cross-cutting domain logic exists that doesn't fit within individual requirements
- Always ask the user which Diligent product area they're working in (Boards, Entities, ESG, etc.) to contextualize appropriately
