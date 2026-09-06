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

## Todo Table (optional — include for demos/sprints with <3 week runway)

| # | Task | Description / Status | Owner | ETA |
|---|------|---------------------|-------|-----|
| 1 | [Task name] | [What needs to happen] | [Name] | [Date] |
| 2 | [Task name] | [What needs to happen] | [Name] | [Date] |

[Use when the delivery context is a demo or short sprint. Replaces the Engineering Effort section (§7) as the operational tracker. Each row = one assignable work item with a clear owner. Keep it flat — no phase narratives.]

---

# 2. Jobs to Be Done & Requirements

[Each JTBD uses the same persona format as the full PRD.
P0/P1 requirements include numbered acceptance criteria (≥2 per P0)
using the same format as the full PRD. P2 requirements are one-line only.]

## JTBD-1: [Job statement]

"As a [persona], I need to [job] so that I can [outcome]."

**Evidence:** [1-2 user pain points with data/quotes]

*Hypothesis:* If we [mechanism], THEN [outcome] because [reasoning].

| | KPI |
|---|---|
| **Primary** | [qual for early-stage, quant for mature] |
| **Secondary** | [measurable backstop] |

**REQ-001: [Name]** (P0)
[1-2 sentence scope.]
1. [P0] [Observable behavior — max 2 logical statements]
2. [P0] [Error/validation behavior or edge case]

<!-- RULES: [P0]/[P1]/[P2] per item. Max 2 statements per item. Max 5 items per area.
  If >5, decompose: REQ-001a, REQ-001b (hierarchical IDs). -->

**REQ-002: [Name]** (P1)
[1-2 sentence scope.]
1. [P1] [Observable behavior]
2. [P1] [Constraint/rule]

**REQ-003: [Name]** (P2) — [P2] [One-line description only, no behaviors]

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
No full component specs or accessibility details — those come in the full PRD.
Include one illustrative edge flow if key business rules are known.]

## JTBD-1: [abbreviated]

### Flow: [Feature] → REQ-001, REQ-002
1. User [trigger with concrete example]
2. System [response]
3. Output: [format]

### Edge Flow (illustrative): [Rule Name] → REQ-001 constraint
[Optional — include if a key business rule is already known and stakeholders
need to see it in action. Keep to 2-3 steps.]
1. User [attempts constrained action]
2. System [enforces rule]
3. [Recovery/outcome]

### ASCII Wireframe: [Main Layout]
[Box-drawing wireframe of the primary interaction pattern.
1-2 wireframes total for a PRD-Lite, not 3-5.]

## Cross-Cutting UX

### Information Architecture
[Where the feature lives. What changes in navigation.]

---

# 4-6. [TBD pending full PRD]

Sections deferred until full PRD:
- §4 Risks & Out of Scope (detailed mitigations)
- §5 Legacy Reference
- §6 RACI

---

# 7. Engineering

## Rough Sizing
| Workstream | Scope | T-Shirt | Justification |
|------------|-------|---------|---------------|
| [Backend] | ... | M/L/XL | ... |
| [Frontend] | ... | M/L/XL | ... |
| [AI/ML] | ... | M/L/XL | ... |

## Data Model (if known)
[Defer to full PRD unless key schema decisions are already clear.
Note any known API contracts or data shape constraints here.]

---

# Next Steps
- [ ] [What needs to happen to move from 1-pager to full PRD?]
```

## Key Differences from Full PRD

- **Requirements:** P0/P1 get numbered acceptance criteria (≥2 per P0), same as full PRD. P2 = one-line description only
- **Business rules:** Noted parenthetically on affected REQ-IDs where known (not a separate section)
- **Hypotheses:** Include KPI tables (mandatory even at this stage)
- **UX Flows (§3):** High-level interaction flows + 1-2 key wireframes + optional illustrative edge flow (not 3-5 wireframes, no component specs or accessibility)
- **Risks / Legacy / RACI:** Deferred (§4-6 placeholders)
- **Engineering (§7):** T-shirt sizing + data model notes if known, not hour estimates
- **No separate Business Rules section:** Rules are inline with requirements

## Expansion Path

To upgrade this to a full PRD:
1. Add cross-cutting REQ-IDs for complex business rules (state machines, permission models)
3. Expand §3 UX Flows (3-5 wireframes, edge flows showing rules in action, full component specs, use cases table)
4. Fill in §4-6 as needed
5. Expand §7 Engineering (hour-range estimates + full data model with API endpoints and tracking)
6. Add §8-10 (Dependencies, Release Plan, Appendix) if applicable
7. Run `/prd-review` for adversarial review
