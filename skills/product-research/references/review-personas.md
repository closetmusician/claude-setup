---
name: review-personas
description: "5 expert review personas for adversarial PRD refinement — read at Step 4.3"
---

# PRD Review Personas

Five expert review lenses for Step 4.3 (PRD Refinement). The agent adopts each persona sequentially, reviewing the PRD from that perspective. Each persona produces structured findings classified as SPECIFIABLE (propose the fix) or REQUIRES_DECISION (PM must choose).

---

## How to Use These Personas

Step 4.3 runs in three phases:

1. **Phase A — Structural Review:** Consistency/completeness check.
2. **Phase B — Five-Persona Review:** Adopt each persona sequentially. Produce findings per persona.
3. **Phase C — Synthesis & Triage:** Cross-reference, deduplicate, apply fixes, surface decisions.

Every finding is classified as **SPECIFIABLE** (propose the exact missing text) or **REQUIRES_DECISION** (PM must make a product call).

---

## Persona 1: Product Thinker

**Focus:** Problem-solution fit, user value, competitive positioning, hypothesis clarity.

**Review dimensions (score each 1-10):**

1. **Demand reality** — What's the strongest evidence someone actually wants this? Not interest — behaviour, payment, or panic.
2. **Status quo honesty** — What are users doing RIGHT NOW to solve this badly? Concrete workarounds, costs, and pain.
3. **Narrowest wedge** — Is this the smallest version someone would actually use? Flag feature creep and YAGNI.
4. **Competitive positioning** — Does the PRD honestly address prior art? Is there a "Reasons to Be Skeptical" section?
5. **Opportunity math** — Is the projection math shown with real precedents?
6. **Hypothesis clarity** — Are features stated as "If we [X], THEN [Y] because [Z]" with measurable KPI tables?

---

## Persona 2: UX Designer

**Focus:** User flows, interaction states, information hierarchy, accessibility.

**Seven review passes:**

1. **Information Architecture** — Where does this feature live? Navigation clear? Containment hierarchy specified?
2. **Interaction State Coverage** — For every component: default, loading, empty, error, success, overflow states specified? Score: % of components with all states.
3. **User Journey Completeness** — Can you walk the full flow per persona? Dead ends? Happy and unhappy paths?
4. **Vague UX Language** — Flag "clean and intuitive", "user-friendly", "seamless" — replace with specific interaction descriptions.
5. **Design System Alignment** — References existing patterns? Component specs defined for new components?
6. **Responsive & Accessibility** — Mobile, keyboard nav, screen reader, touch targets?
7. **Unresolved Design Decisions** — Each unresolved UX question: what breaks for users if deferred?

Rate each pass 0-10. For scores below 8, describe what a 10 looks like.

---

## Persona 3: Engineering Manager

**Focus:** Consistency, clarity, implementability, hidden assumptions.

**Four review passes:**

1. **Structural Consistency** — Requirements reference each other correctly? JTBDs contradictory? Priority tiers make sense? P2 blocking a P0?
2. **Implementation Clarity** — For every P0/P1: could you write a failing test from numbered behaviours? Concrete values? State transitions enumerated?
3. **Edge Case & Error Coverage** — Every data flow: nil input, empty input, upstream error, timeout. Every interaction: double-click, navigate-away, slow connection, stale state, back button, rapid resubmit, concurrent tabs.
4. **Hidden Assumptions** — Auth assumptions? Permission assumptions? Data freshness? Scale? Ordering dependencies?

For SPECIFIABLE: propose exact text with requirement ID. For REQUIRES_DECISION: state question and what breaks if unanswered.

---

## Persona 4: Persona Coverage Expert

**Focus:** Whether each initiative persona is adequately served and no persona is left behind.

**Important:** Uses the initiative's own personas from the research — not hardcoded product personas. Read the Problem Definition (Phase 2) for prioritised personas.

**Review structure:**

1. **Persona Coverage Matrix** — For each requirement: Benefit / Risk / N/A per persona
2. **Underserved Persona Gaps** — Which persona gets the least value? What's missing?
3. **Confusion Risks** — Any feature that would confuse a persona or conflict with their mental model?
4. **Adoption Barriers** — What prevents each persona from using this? Training? Workflow change? Dependency chain?
5. **Persona Dependency Chain** — Does the rollout plan respect the activation chain (e.g., Admin configures before Manager uses)?

---

## Persona 5: QA Expert

**Focus:** Testability, feasibility, hidden complexity.

**Acceptance Criteria Grading:**

Grade every numbered behaviour in every P0/P1 requirement:

* **BAD** — Not testable. "Handler works correctly", "System performs well", "Experience is intuitive"
* **OK** — Testable but underspecified. Two engineers would write different tests. "Returns error for invalid input"
* **GOOD** — Falsifiable. Maps to exactly one test case. "Returns 422 with body {error: 'email_taken'} when email already exists"

Rewrite BAD/OK as GOOD. Compute: N% GOOD, M% OK, P% BAD.

**Shadow Path Tracing:** For every data flow: nil, empty, upstream error, timeout. For every interaction: double-click, navigate-away, slow connection, stale state, back button, rapid resubmit, concurrent tabs. Flag unspecified cases.

**Failure Scenario Generation:** For each JTBD: one realistic scenario where an engineer builds the wrong thing because the spec is ambiguous. Include proposed spec addition.

**Feasibility Assessment:** Can this be built? Hidden complexity? Missing dependencies? Performance implications?

---

## Finding Format

```
FINDING-N: [Title]
Persona: [which reviewer]
Severity: HIGH / MEDIUM / LOW
Classification: SPECIFIABLE / REQUIRES_DECISION
Target: [Section or PREFIX-N]
Evidence: [Quote from PRD or "missing — should exist"]
Proposed fix: [Exact text] OR [Decision question + what breaks if deferred]
```

---

## Triage Rules

After all 5 personas review:

1. **Reinforcing** (2+ personas flagged same issue) -> HIGHEST priority
2. **Unique** (one persona) -> MEDIUM priority
3. **Conflicting** (personas disagree) -> HIGH priority — surface disagreement

Every finding gets a disposition:

| Disposition | Meaning | Action |
| --- | --- | --- |
| **Applied** | SPECIFIABLE fix with unambiguous text | Apply to PRD |
| **Captured** | REQUIRES_DECISION — PM must choose | Surface as decision item |
| **Dismissed** | False positive or out of scope | Note reason |

Do NOT cherry-pick. Every finding from every persona must appear with a disposition.
