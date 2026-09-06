# [Project Name]

**Area:** [Product / Focus Area]
**Timeframe:** [Quarter - Year]
**TL;DR:** <!-- TODO: Fill — 1-liner: gap + mechanism + projected impact -->

## Table of Contents
<!-- TODO: Fill — auto-generated markdown links to all H2/H3 sections -->

---

# 1. Problem Definition

## Objective
<!-- TODO: Fill — one sentence: what are you trying to do? -->

## Context & Strategic Drivers
<!-- TODO: Fill — why this matters, why now, strategic alignment, competitive landscape.
Do NOT list user pain points here — those belong as evidence within each JTBD in section 2.
ALL language must be user/business-facing. No architecture, protocols, or eng notes. -->

## Opportunity Size
<!-- TODO: Fill — show math: [base] x [rate] = [outcome]. Conservative/optimistic. -->

## Success Measures
| Level | Metric |
|-------|--------|
| **Target** | <!-- TODO: Fill --> |
| **Secondary** | <!-- TODO: Fill --> |
| **Guardrail** | <!-- TODO: Fill --> |

---

# 2. Jobs to Be Done & Requirements

<!-- Structure: Each JTBD groups problem, evidence, hypothesis, KPIs, and requirements.
Business rules: simple constraints inline as acceptance criteria under the REQ they govern;
complex cross-cutting rules as their own dedicated REQ-IDs.
UX flows live in §3 and reference back by req ID. -->

## JTBD-1: <!-- TODO: Fill — job statement -->

"As a [persona], I need to [job] so that I can [outcome]."

**Evidence:** <!-- TODO: Fill — user pain points with data/quotes -->

*Hypothesis:* If we [mechanism], THEN [outcome] because [reasoning].

| | KPI |
|---|---|
| **Primary** | <!-- TODO: Fill --> |
| **Secondary** | <!-- TODO: Fill --> |

**REQ-001: [Name]** (P0)
<!-- TODO: Fill — 1-2 sentence scope: what it does, key constraint -->
1. [P0] <!-- TODO: Fill — observable system behavior (max 2 logical statements) -->
2. [P0] <!-- TODO: Fill — happy path behavior -->
3. [P0] <!-- TODO: Fill — error/validation behavior -->

<!-- RULES:
  - Every numbered item starts with [P0], [P1], or [P2]. Area header is the default; items may override.
  - Max 2 logical statements per item (period- or semicolon-separated). Split if more.
  - Max 5 items per area. If >5, decompose into sub-areas: REQ-001a, REQ-001b, etc.
  - Each sub-area inherits parent priority and follows the same ≤5 / 2-statement rules.
  - Every P0 requirement area MUST have ≥2 acceptance criteria. -->

<!-- TODO: Fill — add more REQ-XXX entries as needed. P0 requires ≥2 criteria each. Max 5 items per area. -->

## JTBD-2: <!-- TODO: Fill — or remove if single-JTBD feature -->

<!-- TODO: Fill — same structure as JTBD-1 -->

## Options Analysis (if applicable)
<!-- TODO: Fill — or remove section if no options analysis needed -->
| Dimension | Option A | Option B | Option C (Recommended) |
|-----------|----------|----------|----------------------|
| User value | | | |
| Business value | | | |
| Eng cost | | | |
| Risk | | | |

---

# 3. UX Flows

<!-- Organized by JTBD. Each flow references req IDs it satisfies.
Don't re-describe requirements — reference by ID.
Include illustrative edge-case flows showing business rules in action. -->

### Information Architecture
<!-- TODO: Fill — where feature lives, containment hierarchy, what doesn't change -->

## JTBD-1: <!-- TODO: Fill — abbreviated job statement -->

### Flow: [Feature] → REQ-001, REQ-002
<!-- TODO: Fill — numbered steps: user trigger → system response → output -->

### Edge Flow: [Rule Enforcement] → REQ-XXX
<!-- TODO: Fill — illustrative scenario showing a business rule in action -->

### ASCII Wireframe: [Component/Flow Name]
<!-- TODO: Fill — box-drawing wireframe. 3-5 wireframes per feature PRD. -->

## JTBD-2: <!-- TODO: Fill — or remove -->

### Component Specs (new components only)
<!-- TODO: Fill — or remove if no new components -->

### Use Cases Table
| Use Case | JTBD | Feature | Trigger | Expected Output |
|---|---|---|---|---|
| <!-- TODO: Fill --> | | | | |

### Designs
<!-- TODO: Fill — link to Figma or note WIP status -->

---

# 4. Risks & Out of Scope

## Risks with Mitigations
| Risk | Severity | Mitigation |
|------|----------|------------|
| <!-- TODO: Fill --> | | |

## Out of Scope
<!-- TODO: Fill — features deferred with one-line rationale each -->

---

# 5. Legacy Reference (if replacing existing system)
<!-- TODO: Fill — current behavior, field mappings, API contracts. Or remove section if greenfield. -->

---

# 6. RACI (if applicable)
<!-- TODO: Fill — or remove if not applicable -->

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
| <!-- TODO: Fill --> | | | | | |
| **Total** | | **X** | **Y** | | |

### P1: Fast-Follow (if applicable)
<!-- TODO: Fill — same table format, or remove -->

## 7.2 Data Model (if applicable)
<!-- TODO: Fill — DB tables/columns, API endpoints, state machines, tracking events. Or remove. -->

### API Endpoints
| Method + Path | Purpose | Req ID |
|---------------|---------|--------|
| <!-- TODO: Fill --> | | |

### Tracking Requirements
| Event | Payload |
|-------|---------|
| <!-- TODO: Fill --> | |

---

# 8. Other Dependencies (if applicable)
<!-- TODO: Fill — cross-product deps, settings, cross-team. Or remove. -->

---

# 9. Release Plan (if applicable)
<!-- TODO: Fill — or remove -->

---

# 10. Appendix (if applicable)
<!-- TODO: Fill — post-launch questions, V2 roadmap, detailed data. Or remove. -->
