---
name: prd-template-v3
description: "JTBD-centric PRD section structure with AI variant — read at Step 4.2"
---

# PRD Template (V3)

This is the standard PRD structure produced by Step 4.2. Apply quality patterns from the Quality Patterns reference page throughout. Source all content from the Problem Definition (Phase 2) and Solution Synthesis (Phase 4.1) — never invent information.

## How to Use This Template

* Sections marked **(required)** appear in every PRD.
* Sections marked **(if applicable)** are included only when relevant.
* Within JTBDs, requirements are ordered P0 first, then P1, then P2. P0/P1 get full numbered behaviours; P2 gets description only.
* The AI PRD variant adds sub-sections within Sections 3 and 5. See notes inline.

---

## 1. Document Info (required)

PRD title, product area, type (Standard | AI), status (Draft V1), author [NEEDS PM INPUT], created date, target quarter, link to research parent page, stakeholders.

**TL;DR:** One sentence: name the gap, the mechanism, and the projected impact. This is a pitch, not a description.

**Table of Contents:** Always include a Table of Contents after the TL;DR with auto-generated markdown links to all H2/H3 sections. This enables fast navigation and signals document maturity.

---

## 2. Problem Statement (required)

Source from Phase 2 — Problem Definition. Use user voice.

* **2.1 Business Context** — Quantified friction, competitive gaps, business impact
* **2.2 Objectives** — 3-5 measurable, linked to metrics
* **2.3 Target Users (Personas)** — Per persona: role, friction, consequence if unsolved
* **2.4 Problem Description** — WHO -> CONTEXT -> PAIN -> IMPACT. Evidence-backed.
* **2.5 Opportunity Size** — Show the projection math
* **2.6 Out of Scope** — Each exclusion with rationale and re-entry conditions

---

## 3. Jobs to Be Done & Requirements (required)

This is the core of the PRD. Each JTBD groups together all requirements needed to satisfy that job.

### Per-JTBD structure:

```
## JTBD-N: [Job statement]

"As a [persona], I need to [job] so that I can [outcome]."

**Evidence:** [Reference research pages]

**Hypothesis:** *If we* [mechanism], *THEN* [outcome] *because* [reasoning].

| | KPI |
|---|---|
| **Primary** | [measurement] |
| **Secondary** | [metric with target] |

**PREFIX-1: Descriptive name** (P0)
[Scope paragraph.]
1. [Observable system behaviour with concrete values]
2. [Another behaviour]
3. [Error/validation behaviour]

**PREFIX-2: Descriptive name** (P1)
[Scope paragraph.]
1. [Observable system behaviour]
2. [Another behaviour]

**PREFIX-3: Descriptive name** (P2)
[Description only — no numbered behaviours for P2.]
```

**Priority tiers within each JTBD:** P0 = must ship (MVP), P1 = should ship (fast follow), P2 = defer.

**AI PRD addition:** Within relevant JTBDs, add AI-specific requirements covering model selection, prompt engineering, AI UX (confidence indicators, transparency, fallbacks), human-in-the-loop triggers, safety guardrails.

**After all JTBDs:** Include "Reasons to Be Skeptical / Prior Art" section if Phase 1.4 or Phase 2 identified prior attempts.

---

## 4. UX Flows (required)

Organised by JTBD. Each flow references requirement IDs it satisfies. Don't re-describe requirements — reference by ID.

### Per-JTBD:

```
### Interaction Flow: [Feature Name] -> PREFIX-1, PREFIX-2
1. User does [trigger action with concrete example]
2. System responds with [response] — [visual treatment note]
3. [Processing state]
4. Final output renders as [format]
```

### Cross-cutting UX:

* **Information Architecture** — Where the feature lives, containment hierarchy, what doesn't change
* **Component Specs** — New components only: states, interaction behaviour, constraints
* **Use Cases Table** — Use Case | JTBD | Feature | Trigger | Expected Output
* **Design References** — Figma links or WIP status

---

## 5. Non-Functional Requirements (required)

| Category | Requirement | Details |
| --- | --- | --- |
| Performance |  |  |
| Security |  |  |
| Accessibility |  |  |
| Localisation |  |  |
| Observability |  |  |
| Reliability |  |  |

**AI PRD addition:** Add AI Quality & Performance Requirements table covering accuracy, latency, hallucination guardrails, bias monitoring, cost per inference, model versioning.

---

## 6. Data Model (if applicable)

Include when the feature introduces new data structures. Database tables/columns, API endpoint signatures, state machines, analytics event requirements.

---

## 7. Business Rules (if applicable)

Include when cross-cutting domain logic exists. Permissions & access control, validation rules, lifecycle & state transitions, calculations & derived values.

---

## 8. Legacy Reference (if applicable)

Include when this initiative replaces or significantly changes an existing system. Place after Business Rules but never before Requirements — the PRD leads with what to build, not what exists.

* **Current system behaviour** — How the existing system works today (workflows, screens, data flows)
* **Field mappings** — Old field/entity -> new field/entity correspondence
* **API contract changes** — Breaking changes, deprecation timeline, migration path
* **Screenshots / recordings** — Visual documentation of current state for reference

This section is for **context only** and does NOT drive requirements. Requirements are derived from JTBDs and the Problem Definition.

---

## 9. Dependencies & Rollout (required)

* **9.1 Dependencies** — Internal, external, in-flight, technical constraints from Phase 3.2
* **9.2 Risks & Mitigations** — Risk | Severity | Likelihood | Mitigation
* **9.3 Rollout Plan** — Phased by persona priority with success and rollback criteria
* **9.4 Success Metrics** — Leading (2-week) and lagging (30/60/90 day) indicators with confidence flags

---

## 10. Open Questions (required)

All [NEEDS PM INPUT] items plus unresolved items from Solution Synthesis.

---

## 11. Change Log (required)

Date | Section | Change | Reason | Author

---

## 12. Appendix (required)

Links to all research pages, key data points, research confidence summary.
