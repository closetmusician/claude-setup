---
name: strategic-tools
description: "HMW reframing, insight statements, pre-mortem, Nielsen heuristics review, stakeholder objection map, executive one-pager — read at multiple steps"
---

# Strategic Tools

A collection of high-value frameworks used at specific workflow steps. Each tool includes when to use it, how to execute it, and the expected output format.

---

## Tool 1: "How Might We" Reframing

**Used at**: Phase 1→2 transition (after Discover, before Define synthesis)
**Source**: IDEO, Stanford d.school, Google Design Sprint

### What It Is

After completing Phase 1 discovery, reframe each major finding as a "How Might We" (HMW) question before synthesising Phase 2. This opens the solution space before you narrow it — preventing premature convergence on the first obvious solution.

### How to Execute

1. Review the top findings from each Phase 1 file
2. For each significant pain point, friction, or unmet need, write a HMW question:

**Format**: "How might we [verb] for [persona] so that [outcome]?"

**Rules**:
* Broad enough to allow unexpected solutions, narrow enough to be actionable
* One clear verb — not "How might we improve" (too vague) but "How might we reduce the time" or "How might we eliminate the need for"
* Always include the persona — different personas may need different framings of the same problem
* The outcome should be the user's outcome, not the business's

3. Generate 8-15 HMW questions across all Phase 1 findings
4. Cluster into themes (you'll often find 3-5 natural clusters)
5. Select the top 5-8 that best capture the research — these become the creative brief for Phase 3

### Example Transformations

| Finding | Bad HMW | Good HMW |
|---------|---------|----------|
| "Admins don't know which permissions to set" | "HMW improve the permissions page?" | "HMW help admins feel confident they've set the right permissions without reading documentation?" |
| "New users abandon onboarding at step 3" | "HMW fix onboarding?" | "HMW get new users to their first 'aha moment' before they decide whether to stay?" |
| "Users export to Excel to do what the product should do" | "HMW reduce Excel usage?" | "HMW make the in-product analysis feel as flexible as a spreadsheet without the manual work?" |

### Output Format

Include in `07-problem-definition.md` as a section after Key Findings:

```markdown
## How Might We

| # | HMW Question | Source Finding | Persona(s) | Cluster |
|---|-------------|----------------|------------|---------|
| 1 | How might we... | [Phase 1 file + finding] | [persona] | [theme] |
```

---

## Tool 2: Insight Statements

**Used at**: Phase 2 (Problem Definition), replacing or augmenting the Key Findings section
**Source**: IDEO, frog design, Fjord (Accenture Song)

### What It Is

A three-part statement that forces causal reasoning, not just observation. The best research agencies in the world use this format because it separates what you saw from what it means from what you should do about it.

### Format

> **We observed** [specific behaviour or data point],
> **which tells us** [interpretation — what it means about the user's mental model, motivation, or constraint],
> **so we believe** [actionable inference — what this implies for the solution].

### Rules

* **"We observed"** must be grounded in a specific Phase 1 finding — not a general impression. Cite the source file.
* **"Which tells us"** is the interpretation layer. This is where your expertise matters. What does the behaviour *mean*? What mental model explains it?
* **"So we believe"** is a hypothesis, not a conclusion. It's falsifiable. It should point toward a solution direction without prescribing one.

### Example

> **We observed** that 68% of new users who reach the sharing dialog abandon without completing a share (Step 1.3, Friction Inventory #2),
> **which tells us** that the cognitive load of choosing permissions, recipients, and message content simultaneously exceeds the user's willingness to invest effort at this point in their journey,
> **so we believe** that separating the "who" decision from the "what permissions" decision — or providing smart defaults — would significantly reduce abandonment.

### Anti-Patterns

* **Observation without interpretation**: "We observed that users leave the page." — So what? Why? What does it tell you?
* **Interpretation without evidence**: "Which tells us users find it confusing." — How do you know it's confusion vs. indifference vs. irrelevance?
* **Prescription instead of hypothesis**: "So we believe we should add a wizard." — This is a solution, not an inference. Keep it one level above.

### Output Format

Replace or augment the "Key findings" section in `07-problem-definition.md`:

```markdown
## Key Insights

### Insight 1: [Title]
**We observed** [specific finding from Phase 1 with citation]
**which tells us** [interpretation]
**so we believe** [actionable hypothesis]
**Confidence**: High / Medium / Low
```

---

## Tool 3: Pre-Mortem

**Used at**: Step 4.1 (Solution Synthesis), after the MVP recommendation but before prototyping
**Source**: Gary Klein (psychologist), adopted by Amazon, Google, Basecamp

### What It Is

Imagine the initiative shipped 6 months ago and **failed catastrophically**. Now write the post-mortem. This inverts the normal optimism of solution design and surfaces risks that planning-mode brains overlook.

### How to Execute

1. Read the Solution Synthesis MVP recommendation
2. Assume it's 6 months post-launch and the initiative has been declared a failure
3. Write 5-7 plausible failure scenarios — each must be:
   * **Specific** — not "users didn't like it" but "users completed onboarding but never returned because [specific reason]"
   * **Plausible** — could actually happen given what you know from the research
   * **Distinct** — each scenario represents a different failure mode

4. For each scenario, assess:
   * **Likelihood**: High / Medium / Low (given current evidence)
   * **Detectability**: Would we know this is happening before it's too late? What signal would we see?
   * **Current mitigation**: Does the MVP recommendation already address this? How?
   * **Recommended action**: What should the PRD include to prevent or detect this?

### Failure Mode Categories

| Category | Example |
|----------|---------|
| **Adoption failure** | Users don't discover or don't try the feature |
| **Activation failure** | Users try it once but don't reach the "aha moment" |
| **Retention failure** | Users get initial value but don't return |
| **Persona mismatch** | Built for the wrong persona, or the primary persona doesn't have the problem we assumed |
| **Competitive failure** | A competitor shipped something better while we were building |
| **Integration failure** | The feature doesn't fit into users' existing workflow |
| **Measurement failure** | We can't tell if it's working because we're measuring the wrong thing |

### Output Format

Include in `12-solution-synthesis.md` as a section after Risks & Open Questions:

```markdown
## Pre-Mortem: How This Could Fail

*Assume it's [date + 6 months]. The initiative launched on time and budget but has been declared a failure. Here's what happened:*

### Scenario 1: [Failure headline]
**What happened**: [Specific narrative — 2-3 sentences]
**Likelihood**: High / Medium / Low
**Detectability**: [What signal would we see? When?]
**Current mitigation**: [Does the MVP address this?]
**Recommended action**: [What the PRD should include]

### Scenario 2: ...
```

---

## Tool 4: Nielsen's 10 Usability Heuristics Review

**Used at**: Step 4.3 Phase B, as part of the UX Designer persona review
**Source**: Jakob Nielsen (1994), updated by NNGroup — the single most validated usability framework in existence

### The 10 Heuristics

The UX Designer persona (Review Persona #2) should explicitly evaluate the PRD's UX flows against each heuristic:

| # | Heuristic | What to check in the PRD |
|---|-----------|-------------------------|
| **H1** | **Visibility of system status** | Does the PRD specify feedback for every user action? Loading states, progress indicators, confirmation messages, real-time updates? |
| **H2** | **Match between system and real world** | Does the PRD use the user's language (from Phase 1.1 personas), not internal jargon? Are metaphors and icons intuitive? |
| **H3** | **User control and freedom** | Can users undo, go back, cancel, escape? Does the PRD specify undo for destructive actions? |
| **H4** | **Consistency and standards** | Does the PRD reference existing product patterns? Are similar actions handled the same way? |
| **H5** | **Error prevention** | Does the PRD specify constraints, confirmations, and defaults that prevent errors before they happen? |
| **H6** | **Recognition rather than recall** | Are options visible rather than hidden? Does the PRD minimise memory load (e.g., showing recent items, smart defaults)? |
| **H7** | **Flexibility and efficiency of use** | Does the PRD specify both novice and expert paths? Shortcuts, bulk actions, keyboard access? |
| **H8** | **Aesthetic and minimalist design** | Does the PRD avoid information overload? Is every UI element justified? |
| **H9** | **Help users recognise, diagnose, and recover from errors** | Does the PRD specify error messages in plain language with actionable next steps? |
| **H10** | **Help and documentation** | Does the PRD specify contextual help, tooltips, or onboarding for complex features? |

### Scoring

Score each heuristic 0-4 for the PRD's coverage:

| Score | Meaning |
|-------|---------|
| 0 | No usability problem — heuristic fully addressed |
| 1 | Cosmetic problem — noted but low priority |
| 2 | Minor problem — should be fixed but not blocking |
| 3 | Major problem — important to fix, degrades UX significantly |
| 4 | Catastrophe — must fix before ship, users will fail |

### Output Format

Add to the UX Designer persona's findings in Step 4.3:

```markdown
### Nielsen Heuristic Review
| # | Heuristic | Score (0-4) | Finding | Proposed Fix |
|---|-----------|:-----------:|---------|-------------|
| H1 | Visibility of system status | 2 | [specific gap] | [specific fix] |
```

---

## Tool 5: Stakeholder Objection Map

**Used at**: Step 4.2 (PRD V1), as a dedicated section in the PRD
**Source**: Experienced PM craft — the PRD is a persuasion document as much as a spec

### What It Is

Before submitting the PRD for review, anticipate the top objections stakeholders will raise — and pre-answer them. This isn't defensive; it's respectful. It shows you've considered their perspective and builds confidence in the recommendation.

### How to Execute

1. Identify 5-7 likely objections across stakeholder types:

| Stakeholder | Typical objection patterns |
|------------|--------------------------|
| **Engineering lead** | "This is too big for one cycle", "We have tech debt blocking this", "The data model doesn't support this" |
| **Design lead** | "This doesn't match our design system", "The flow is too complex", "We need user testing first" |
| **Executive/VP** | "Why now?", "How does this move [KPI]?", "What's the competitive risk of not doing this?", "Can we do this faster?" |
| **Sales/CS** | "Customers are asking for [different thing]", "This won't solve [their top complaint]" |
| **Legal/Compliance** | "Data privacy implications?", "Regulatory risk?" |

2. For each objection, write a pre-answer that:
   * Acknowledges the concern genuinely (not dismissively)
   * References specific evidence from the research
   * Proposes a concrete path forward (not "we'll figure it out")

### Output Format

Include in the PRD as Section 9.5 (after Rollout, before Open Questions):

```markdown
## 9.5 Anticipated Objections

| # | Likely Objection | Stakeholder | Pre-Answer | Evidence |
|---|-----------------|-------------|-----------|---------|
| 1 | "This is too big for Q3" | Engineering | The P0 scope is 3-5 features with clear boundaries. P1/P2 are explicitly deferred. Phase rollout (Section 9.3) sequences by persona priority. | Solution Synthesis dependency map |
| 2 | "Why not just fix [X] first?" | VP Product | [X] is a symptom. Research shows the root cause is [Y] (Problem Definition, Finding #3). Fixing [X] alone leaves the core friction at [Z]%. | Phase 1.3 friction inventory |
```

---

## Tool 6: Executive One-Pager

**Used at**: After Step 4.3 (PRD V2 complete), as a final output
**Source**: Amazon 6-pager tradition (condensed), Stripe's "one-pager" culture

### What It Is

A single-page summary for the executive who will decide whether to fund/approve the initiative. They won't read the PRD. They'll read this, then ask questions.

### Template

```markdown
# [Initiative Title] — Executive Summary

**Author**: [NEEDS PM INPUT]  |  **Date**: [date]  |  **Status**: Ready for Review

## The Problem (2-3 sentences)
[User-voice problem statement from Phase 2. Who, what's broken, why it matters now.]

## The Opportunity (2-3 sentences)
[Opportunity sizing with projection math. What improvement is realistic based on precedent.]

## The Recommendation (3-5 bullets)
[MVP must-haves from Solution Synthesis. Each as: "Feature — why it matters"]

## Why Now
[Competitive pressure, strategic alignment, cost of delay, or window of opportunity]

## Key Risk
[The single biggest risk and how the PRD mitigates it]

## Success Metric
[Primary KPI with target threshold and measurement timeline]

## Ask
[What decision is needed: approve for Q[X], assign design resources, etc.]
```

### Output Format

Write to `15-executive-summary.md` in the research folder. Update the Workflow Summary.

---

## Reference Index

| Tool | Used at | Output location |
|------|---------|----------------|
| HMW Reframing | Phase 1→2 transition | `07-problem-definition.md` |
| Insight Statements | Phase 2 | `07-problem-definition.md` |
| Pre-Mortem | Step 4.1 | `12-solution-synthesis.md` |
| Nielsen Heuristics | Step 4.3 Phase B | UX Designer persona findings |
| Stakeholder Objection Map | Step 4.2 | `14-prd-v1.md` Section 9.5 |
| Executive One-Pager | After Step 4.3 | `15-executive-summary.md` |
