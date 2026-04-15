# PRD-Lite (1-Pager) Template

Subset of the full PRD template for early-stage features. Uses the same section numbers, JTBD format, and requirement ID scheme as the full PRD — so this document can be expanded in place without restructuring.

**When to use:** User asks for a "1-pager", "discovery brief", "early-stage doc", or doesn't have enough data for a full PRD.

## Template Structure

```markdown
# [Project Name]

**Area:** [Product / Focus Area]
**Timeframe:** [Quarter - Year]
**TL;DR:** [1-liner: gap + mechanism + projected impact]

---

# 1. Problem Definition

## Objective
[One sentence: what are you trying to do?]

## Context & Strategic Drivers
[2-3 sentences: Why this matters. Why now. Strategic alignment.
Do NOT list user pain points here — those belong as evidence within each JTBD in section 2.]

## Opportunity Size
[Back-of-envelope: [base] x [rate] = [outcome]. One conservative estimate.]

## Success Measures
| Level | Metric |
|-------|--------|
| **Target** | [The ONE metric to optimize] |
| **Secondary** | [Should improve or stay neutral] |
| **Guardrail** | [Must NOT regress] |

---

# 2. Jobs to Be Done & Requirements

[Each JTBD uses the same persona format as the full PRD.
Requirements are listed with IDs and priorities but without numbered behaviors.]

## JTBD-1: [Job statement]

"As a [persona], I need to [job] so that I can [outcome]."

**Evidence:** [1-2 user pain points with data/quotes]

*Hypothesis:* If we [mechanism], THEN [outcome] because [reasoning].

| | KPI |
|---|---|
| **Primary** | [qual for early-stage, quant for mature] |
| **Secondary** | [measurable backstop] |

1. **REQ-001: [Name]** (P0) — [One-line description of what it does]

2. **REQ-002: [Name]** (P1) — [One-line description]

3. **REQ-003: [Name]** (P2) — [One-line description]

## JTBD-2: [Job statement]
[...same structure...]

## Options Analysis (if applicable)
| Dimension | Option A | Option B | Option C (Recommended) |
|-----------|----------|----------|----------------------|
| User value | ... | ... | ... |
| Eng cost | ... | ... | ... |
| Risk | ... | ... | ... |

- **Recommendation:** Option C — [deciding factor]
- [Key tradeoff bullet]

## Reasons to Be Skeptical
[What's been tried before, what failed, what's different this time. 2-4 bullets.]

---

# 3. UX Flows

[Reduced depth: high-level interaction flows and 1-2 key wireframes.
No full component specs or accessibility details — those come in the full PRD.]

## JTBD-1: [abbreviated]

### Flow: [Feature] → REQ-001, REQ-002
1. User [trigger with concrete example]
2. System [response]
3. Output: [format]

### ASCII Wireframe: [Main Layout]
[Box-drawing wireframe of the primary interaction pattern.
1-2 wireframes total for a PRD-Lite, not 3-5.]

## Cross-Cutting UX

### Information Architecture
[Where the feature lives. What changes in navigation.]

---

# 4-8. [TBD pending full PRD]

Sections deferred until full PRD:
- §4 Data Model (tables, APIs, tracking)
- §5 Business Rules (permissions, validation, lifecycle)
- §6 Risks & Out of Scope (detailed mitigations)
- §7 Legacy Reference
- §8 RACI

---

# 9. Engineering Effort

## Rough Sizing
| Workstream | Scope | T-Shirt | Justification |
|------------|-------|---------|---------------|
| [Backend] | ... | M/L/XL | ... |
| [Frontend] | ... | M/L/XL | ... |
| [AI/ML] | ... | M/L/XL | ... |

---

# Open Questions
- [ ] [Question that needs answering before committing to a full PRD]
- [ ] ...

# Next Steps
- [ ] [What needs to happen to move from 1-pager to full PRD?]
```

## Key Differences from Full PRD

- **Requirements:** ID + priority + one-line description only (no numbered behaviors)
- **Hypotheses:** Include KPI tables (mandatory even at this stage)
- **UX Flows (§3):** High-level interaction flows + 1-2 key wireframes (not 3-5, no component specs or accessibility)
- **Data Model / Business Rules / Risks / Legacy / RACI:** Deferred (§4-8 placeholders)
- **Engineering Effort:** T-shirt sizing, not hour estimates

## Expansion Path

To upgrade this to a full PRD:
1. Add numbered behaviors to each requirement (2+ per P0)
2. Expand §3 UX Flows (3-5 wireframes, full component specs, accessibility, use cases table)
3. Expand §4 Data Model (full schema, tracking events, field constraints)
4. Fill in §5-8 as needed
5. Replace T-shirt sizing with hour-range estimates
6. Run `/prd-review` for adversarial review
