# Quality Patterns for High-Impact PRDs

These patterns are reverse-engineered from exemplary PRDs and represent the difference between a "fill-in-the-blank" PRD and one that actually moves a team to action.

## Table of Contents
1. [Executive Summary Patterns](#executive-summary)
2. [Problem Definition Patterns](#problem-definition)
3. [Data-Driven Rigor](#data-driven-rigor)
4. [Differentiation & Prior Art](#differentiation)
5. [User Experience Depth](#user-experience)
6. [Engineering Estimation](#engineering)
7. [Risk & Skepticism Honesty](#risk-and-skepticism)
8. [Opportunity Sizing](#opportunity-sizing)
9. [Writing Style & Tone](#writing-style)

---

## 1. Executive Summary Patterns <a name="executive-summary"></a>

A great exec summary does four things in ~100 words:
- **Names the strategic gap** — what's broken or missing in the market/product
- **Cites a concrete precedent** — a past signal that this direction has legs
- **Quantifies the prize** — a specific number for potential impact
- **States the mechanism** — HOW the product achieves the result, not just WHAT it does

**Anti-pattern:** Vague "we will improve the experience" language with no numbers.

**Example pattern:**
> "[Platform] is becoming too [problem]. [Competitor] is pulling [segment] away. 
> Learnings from [past experiment] show [mechanism] can work — [evidence: metric].
> However, [past attempt] suffered from [barriers]. We solve these through [approach].
> By combining [tactic A] + [tactic B], we can unlock [projected impact]. Let's [call to action]."

---

## 2. Problem Definition Patterns <a name="problem-definition"></a>

### User Problems as First-Person Statements
Frame problems from the user's voice, not the company's. Each problem should be:
- A real pain point backed by research or data (link to source)
- Stated as "I [verb]..." not "Users need..."
- Paired with evidence (research links, quotes, data)

**Pattern:**
```
As a user:
- I [problem statement] (link to supporting research)
- I [problem statement] (link to data)
- I [problem statement] (link to user quote/study)
```

### Hypotheses Format
Each core feature should be stated as a testable hypothesis paired with a KPI measurement table:

**Pattern:**
> *[Feature name]:* If we [do X], THEN [expected outcome] by [mechanism/reason].

| | KPI |
|---|---|
| **Primary (qual)** | ≥N/M beta users [specific observable behavior or statement] |
| **Secondary (quant)** | [metric] [threshold] (e.g., ">50% of items receive status update before due date") |

This forces clarity on causality AND makes success measurable with concrete thresholds. For early-stage products with few users, qualitative metrics (direct user feedback) are primary — quantitative metrics serve as secondary validation signals. For mature products with instrumentation, flip the priority.

### Numbered Requirement IDs
Every requirement gets a short prefix ID (2–3 letters from the feature name) + sequential number:
- Enables direct reference in code comments, test names, and commit messages
- Maps 1:1 to TDD test cases
- Makes PRD reviews traceable ("Does INF-3 handle the edge case where...?")

**Pattern:** `PREFIX-N: Descriptive name` — followed by acceptance criteria lines.

### Acceptance Criteria (AC lines)
Each P0/P1 requirement gets multiple AC lines. Each AC must be independently testable:
```
- **REQ-1: Name** — Scope description.
  - AC: Happy path criterion with concrete values
  - AC: Error/edge case criterion
  - AC: Boundary condition criterion
```

**Rules:**
- Use concrete values ("≤200 words", "returns empty list", "status transitions: queued → running → succeeded")
- Reference API shapes, DB columns, or UI states when known
- Each AC = one test case (a developer can write a failing test without asking questions)
- State transitions should enumerate valid paths

---

## 3. Data-Driven Rigor <a name="data-driven-rigor"></a>

Every claim in a strong PRD is backed by one of:
- **Internal experiment data** — past A/B tests, pilot results, metrics
- **Analogous product data** — similar features on the same or competing platforms
- **User research** — qualitative studies, surveys, interviews
- **Market data** — industry benchmarks, competitor metrics

### Quantification Rules
- Never say "significant improvement" — say "+1.65% SS OESPD"
- Never say "good engagement" — say "click through rate of 9.75%"
- Never say "some users liked it" — say "380K stories created"
- Always include confidence intervals or stat sig markers when available (e.g., "0.035±0.062")
- When projecting, show the math: "[base metric] × [conversion rate] = [projected outcome]"

### Comparison Tables with Metrics
When referencing past experiments or competing approaches, use a structured comparison:

| Approach | Result | Why it matters |
|----------|--------|---------------|
| [Past experiment A] | [Specific metric] | [Learning] |
| [Past experiment B] | [Specific metric] | [Learning] |

---

## 4. Differentiation & Prior Art <a name="differentiation"></a>

Strong PRDs are brutally honest about what's been tried before. The pattern:

### Prior Attempts Table
Create a comparison matrix showing:
- **Rows**: Each past attempt or competing approach
- **Columns**: "How is this different?" and "Why it's worth trying"

This forces the author to articulate exactly what's novel — not just "we're doing it better" but specifically what mechanism is different.

### "Reasons to Be Skeptical" Section
An exceptional PRD includes an explicit section on why this might NOT work, with:
- What went wrong in past attempts (with links/data)
- Why each failure doesn't apply here (or does)
- Honest assessment of remaining risks

This builds credibility and shows the PM has done their homework.

---

## 5. User Experience Depth <a name="user-experience"></a>

A PRD's UX section should be sufficient for frontend implementation without Figma mockups. It has four layers:

### Information Architecture
Define where the feature lives and how it relates to existing navigation:
- **Containment hierarchy** (top → bottom): what contains what
- **Navigation additions**: new tabs, sidebar items, routes — and what does NOT change
- **Cross-cutting concerns**: features accessible from multiple entry points

**Pattern:**
```
**Hierarchy (top → bottom):**
1. [Existing container] — [description]
2. [Existing/new element] — [description, how it nests]
3. [New element] — [description, what it contains]

**Navigation additions:**
- [New nav item] in [location] — [what it surfaces]
- No new [things that don't change]
```

### Interaction Flows (Per Feature)
Write a separate numbered flow for each major user journey. These replace vague "producer/consumer flow" descriptions with concrete step-by-step sequences.

**Pattern:**
```
### Interaction Flow: [Feature Name]
1. User [trigger action with concrete example: `@briefcase prep me for Thursday's meeting`]
2. [System response] — [visual treatment: "Agent working..." indicator with subtle animation]
3. [Real-time step: SSE events stream in, each step as a collapsible row...]
4. [Processing/intermediate state]
5. Final output renders as [format] with sections: [list each section]
6. [Post-output action if applicable]
```

**Rules for good interaction flows:**
- Use concrete example inputs, not placeholders
- Include real-time/streaming states where applicable
- Describe what the system does at each step, not just what the user sees
- Note visual treatment briefly (animation, loading states, expansion behavior)
- End with the final output format and any post-output actions

### Component Specs
For each new UI component, define states and behavior — enough for a developer to implement without asking questions.

**Pattern:**
```
**ComponentName:**
- [Default state]: [visual treatment + content layout]
- [Loading/Live state]: [expanded by default, animation, spinner location]
- [Completed state]: [collapsed summary + expand affordance]
- [Error state]: [visual treatment, error message placement]
- [Empty state]: [placeholder text, call-to-action]
- Click/expand: [what happens on interaction]
- Constraints: [max lines, truncation, scroll behavior]
```

Reference design system primitives when known (e.g., "shadcn/ui Collapsible, Badge, Card, Tabs").
Reference design tokens for visual treatment (e.g., "`bg-muted/50`, rounded corners, subtle border").

### Use Case Table
Map concrete use cases to features, triggers, and expected outputs:

| Use Case | Feature | Trigger | Expected Output |
|---|---|---|---|
| [Scenario name] | [Which feature] | [Exact user input example] | [What the system produces] |

This replaces the older hypothesis-mapped table with a more actionable format that includes the trigger (what the user actually types/clicks) and the expected output (what the system produces).

### Learnings-to-Solutions Mapping
For products building on past attempts, create a funnel analysis showing:
- Each step in the user journey
- Current metric at that step
- Identified barrier
- How the new approach solves it

---

## 6. Engineering Estimation <a name="engineering"></a>

### Prioritized Estimation Tables
Break estimates into P0 (MVP) and P1+ (future), with:
- Individual component breakdown
- Backend vs. Client split
- Total with ranges (not single numbers)
- Staffing needs stated explicitly

**Pattern:**
| Component | Eng Weeks | Backend vs. Client |
|-----------|-----------|-------------------|
| [Specific component] | [Range] | [Split] |
| **Total** | **[Range]** | **[Summary]** |

*Eng Needed: [specific roles and count]*

### Barriers Section
After estimates, explicitly call out risks to the timeline:
- Platform dependencies
- Team dependencies
- Known unknowns

---

## 7. Risk & Skepticism Honesty <a name="risk-and-skepticism"></a>

### Cons/Risk Section
Every PRD should have an explicit section covering:
- Operational risks (maintenance burden, content creation overhead)
- Technical risks (scaling, dependencies)
- Strategic risks (cannibalizing other features, user fatigue)
- Proposed mitigations for each

### Out of Scope
Explicitly state what you are NOT doing. This prevents scope creep and sets expectations.

---

## 8. Opportunity Sizing <a name="opportunity-sizing"></a>

### Evidence Pyramid
Build the case with multiple layers:
1. **Direct signals** — metrics from the exact product/feature being proposed
2. **Adjacent signals** — metrics from similar features on the same platform
3. **Cross-platform signals** — metrics from competitors doing something similar
4. **Research signals** — qualitative research supporting the direction

### Projection Math
Show the derivation:
> "We can unlock [X] from [channel A] and at [conversion rate] (as seen with [precedent]), 
> an additional [Y] from [channel B]."

---

## 9. Writing Style & Tone <a name="writing-style"></a>

- **Confident but honest** — State convictions clearly, acknowledge uncertainties explicitly
- **Link-dense** — Every claim should link to its source (research, data, past experiments)
- **Specific over general** — "380K stories created" not "strong engagement"
- **Action-oriented** — End sections with what happens next, not just what is
- **Narrative thread** — The PRD should tell a story: problem → evidence → solution → projected impact
- **Use the user's voice** — Quote user research directly when available
- **Future vision teaser** — End with where this could go if successful, creating excitement without over-promising
