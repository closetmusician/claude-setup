---
name: prd-writer
description: "Helps product managers write high-quality, data-driven PRDs (Product Requirements Documents). Use this skill whenever a user wants to create a PRD, product spec, product brief, feature spec, or requirements document — including when they say 'write a PRD', 'help me spec this out', 'I need a product doc', 'turn this into a PRD', 'product requirements', or share rough notes/briefs asking to formalize them into a structured product document. Also trigger when the user wants to review, critique, or improve an existing PRD. This skill enforces data-driven rigor, testable hypotheses, prior-art honesty, and structured engineering estimates. Do NOT use for pure engineering design docs, architecture docs, or technical RFCs that aren't product-facing."
---

## Required Files
- `references/quality-patterns.md` — Quality patterns reverse-engineered from exemplary PRDs (scoring criteria for each section)
- `references/discovery-brief-format.md` — Condensed 1-pager format for early-stage exploration
- `templates/diligent-prd-template.md` — Default PRD structure template (Diligent Boards conventions)

# PRD Writer

A skill for creating high-quality, data-driven Product Requirements Documents that move teams to action.

This skill combines a structured template (defaulting to the Diligent Boards format) with quality patterns extracted from exemplary PRDs. The goal is not just to fill in sections — it's to produce a PRD with the rigor, specificity, and narrative clarity that earns stakeholder buy-in.

## Core Principles

Before writing anything, internalize these — they distinguish great PRDs from templates-with-words-in-them:

1. **Every claim needs a number.** Never write "significant improvement" — write "+1.65% OESPD." Never write "good engagement" — write "9.75% CTR." If the number doesn't exist yet, say so honestly and flag it as a gap to fill.

2. **Hypotheses, not descriptions.** Features should be stated as "If we [X], THEN [Y] because [Z]" — this forces causal clarity and makes success measurable.

3. **Brutal honesty about prior art.** If something similar has been tried before (internally or by competitors), document it. What happened? Why didn't it work? What's actually different this time? A "Reasons to Be Skeptical" section builds credibility.

4. **Show the projection math.** Opportunity sizing should expose the derivation: "[base] × [rate] = [outcome]" with the rate sourced from a real precedent.

5. **User voice, not corporate voice.** Problems should be stated as "I don't know what to share" not "Users experience a content creation friction point."

6. **Implementation-ready requirements.** Every P0/P1 requirement gets a short ID (prefix + number) and numbered behavior descriptions. Each numbered item is an observable system behavior with concrete values that maps to one test case. A developer reading the PRD should be able to write a failing test for any numbered item without asking clarifying questions.

7. **Hypotheses tied to measurable KPIs.** Each feature's hypothesis gets a KPI table with primary and secondary metrics. For early-stage products (small user base, no instrumentation), use qualitative primary + quantitative secondary. For mature products, use quantitative primary.

---

## Workflow

### Step 1: Gather Context

When the user initiates a PRD, first assess what they've brought:

**If they've shared raw context** (notes, brief, brainstorm doc, pasted text, uploaded file):
- Read it carefully and extract: the product/feature being proposed, the target user, the problem being solved, any data or metrics mentioned, any prior art referenced, and the team/organizational context.
- Identify gaps — what's missing that you'll need to ask about.

**If they've started from scratch** (just a verbal description):
- Acknowledge what you understand and proceed to interview.

**If they've uploaded a custom PRD template:**
- Use their template structure instead of the default. Still apply all quality patterns.

### Step 2: Interview for Gaps

After assessing the raw input, ask targeted questions to fill gaps. Group questions efficiently — don't ask one at a time. Prioritize the questions that will most affect the PRD's quality.

**Always ask about (if not already provided):**

- **The "why now"** — What's the urgency driver? Why this quarter, not next?
- **Prior art** — Has anything similar been tried before (internally or by competitors)? What happened?
- **Success metrics** — What's the north star metric? What are guardrails?
- **Personas and RACI** — Who is this for? Who's building it? Who approves?
- **Scope boundaries** — What's explicitly out of scope for this iteration?
- **Priority tier scope** — Are P0/P1/P2 tiers within the current build scope (P0=must-ship, P1=should-ship, P2=can defer to next cycle), or across the full product timeline? This determines whether P2 items get full acceptance criteria or just descriptions.
- **KPI measurement approach** — Is this a mature product with instrumentation (quantitative primary), an early-stage product with few users (qualitative primary + quantitative secondary), or a mix? This determines how hypotheses tie to KPIs.
- **UX detail level** — Does the team need interaction flows only, interaction flows + information architecture direction, or full wireframe-level specs? For most PRDs, interaction flows + info hierarchy is the sweet spot.
- **Tech stack** — Ask the user directly for frontend/backend stack info. Don't explore the codebase unless the user asks you to — they usually know their stack and can tell you faster.

**Ask about if relevant:**
- Engineering effort estimates (do they have them, or should we leave placeholders?)
- Design status (Figma links, wireframes?)
- Cross-team dependencies
- Pricing tier implications
- Release timeline constraints

Use `AskUserQuestions` when presenting bounded choices (e.g., "Which of these metrics should be primary?"). Use prose questions for open-ended gaps.

### Step 3: Research & Validate

Before drafting, use web search to strengthen the PRD's data-driven foundation:

- **Market context**: Search for competitor features, industry benchmarks, or market data relevant to the product area. This helps populate the "Context, Problems, Opportunities" section.
- **Supporting evidence**: If the user makes claims about user behavior or market trends, search for public data that supports or challenges them.
- **Prior art**: Search for public information about similar features from competitors — blog posts, press releases, product announcements.

**Important guardrails for research:**
- Only include data you can verify from search results. Never fabricate statistics or sources.
- Clearly mark which data came from web search vs. user-provided context.
- If you can't find supporting data for a claim, flag it honestly: "[Data needed: no public benchmarks found for X — recommend internal research]"
- Search for counterarguments too. A PRD that only presents supporting evidence is weaker than one that acknowledges challenges.

### Step 4: Draft the PRD

Read the reference files before drafting:
1. `templates/diligent-prd-template.md` — for the section structure (unless user provided custom template)
2. `references/quality-patterns.md` — for the quality bar to hit in each section

**Drafting approach:**

Generate the full PRD as a markdown file. Apply these section-specific patterns:

#### TL;DR
Not a description — a pitch. One sentence that names the gap, the mechanism, and the projected impact. If you can't quantify the impact yet, say what metric you expect to move and in which direction.

#### Table of Contents
Always include a Table of Contents after the TL;DR with auto-generated markdown links to all H2/H3 sections. This enables fast navigation and signals document maturity.

#### Problem Definition
- State the objective, context, strategic drivers, and success measures
- Include the "why now" urgency driver
- Back context with evidence (user research, data, or at minimum a clear rationale)

#### Opportunity Size
- Show the projection math explicitly
- Reference analogous precedents with their actual metrics
- Be honest about assumptions and confidence levels

#### Jobs to Be Done & Requirements

This is the core of the PRD. Each JTBD groups together all the requirements needed to satisfy that job. This co-location makes it easy for developers to understand WHY each requirement exists.

**Per-JTBD structure:**
1. **JTBD heading** with job statement (e.g., "JTBD-1: Prepare for board meetings without manual research")
2. **Job statement** in persona format: "As a [persona], I need to [job] so that I can [outcome]."
3. **Evidence** backing the job (user research, data, quotes)
4. **Hypothesis** in italic: "*If we* [mechanism], *THEN* [outcome] *because* [reasoning]."
5. **KPI table** immediately after hypothesis:
   ```
   | | KPI |
   |---|---|
   | **Primary (qual)** | [qualitative measurement — who says what, in what context] |
   | **Secondary (quant)** | [quantitative metric with target threshold] |
   ```
   - For early-stage products: qualitative primary (e.g., "≥3/5 beta users cite X as reason they Y")
   - For mature products: quantitative primary (e.g., "+2% conversion rate")
   - Always include both — the secondary provides a measurable backstop
6. **Requirements** grouped under this JTBD, ordered P0 first, then P1, then P2. P0/P1/P2 requirements are mixed within each JTBD (not separated into priority subsections).

**Requirement ID format:** Short feature prefix + sequential number. Pick 2–3 letter prefixes from the feature name:
- "Agent Infrastructure" → INF-1, INF-2, ...
- "Board Briefcase" → BRF-1, BRF-2, ...
- "User Auth" → AUTH-1, AUTH-2, ...

**Per-requirement structure (P0/P1):**
```
**REQ-ID: Descriptive name** (P0)
[1-paragraph scope description explaining what this requirement does, how it works, and key technical details.]
1. [Observable system behavior with concrete values — maps to one test case]
2. [Another behavior — happy path]
3. [Error/validation behavior]
4. [Edge case or boundary condition]
```

P2 requirements get a lighter treatment — description only, no numbered behaviors needed.

**Rules for numbered behavior descriptions:**
- Each numbered item is an observable system behavior (what the system does, not what the user does)
- Use concrete values: field names, max lengths, valid states, sort orders ("≤200 words" not "short")
- Each item is independently falsifiable — maps to one test case
- A developer can write a failing test for any single numbered item without asking questions
- Reference specific API shapes, DB columns, or UI states when known
- If a requirement involves state transitions, enumerate valid transitions as numbered items
- Order: happy path first, then error/validation, then edge cases/boundary conditions
- **Minimum count:** Every P0 requirement must have ≥2 numbered behaviors. If you can't identify at least 2 observable behaviors, the requirement is too vague — split or rewrite it.

**Priority tiers are within each JTBD's build scope**, not across the full product:
- P0 = must ship for the job to be satisfiable
- P1 = should ship, but the job is achievable without it
- P2 = nice to have, defer to next cycle

Include a differentiation table if there are meaningful prior attempts. Include "Reasons to Be Skeptical" if prior art exists — this is a sign of strength, not weakness.

After all JTBDs, include summary tables if they help comprehension:
- **Tool/API Registry** — what tools/endpoints exist, which JTBD uses them, new vs. wraps existing
- **New Database Objects** — tables and columns with types, FKs, constraints
- **Frontend Changes** — component list with brief descriptions

#### Data Model (if applicable)
When the feature introduces new data structures, document them after JTBD & Requirements:
- Database tables/columns with types, foreign keys, constraints
- API endpoint signatures and response shapes
- State machines with valid transitions
- Tracking/analytics requirements

This section is for domain-heavy PRDs where the data model is complex enough to warrant its own section rather than being embedded in individual requirements.

#### Business Rules (if applicable)
Document domain logic that cuts across multiple requirements or JTBDs. This section captures rules that are too cross-cutting for a single requirement but too important to leave implicit:
- **Permissions & Access Control** — role-based rules, org-level restrictions, delegation logic
- **Validation Rules** — cross-field dependencies, conditional validation, format rules
- **Lifecycle & State Transitions** — entity lifecycle rules spanning multiple JTBDs, automatic triggers, time-based rules, cascading effects
- **Calculations & Derived Values** — formulas, aggregation rules, how computed values update when inputs change

Skip this section for simple features where all business logic fits within individual requirements.

#### Risk
- Be explicit about operational, technical, and strategic risks
- Propose mitigations
- State what's out of scope

#### Legacy Reference (optional)
When replacing a legacy system, include a "Legacy Reference" section after Risks documenting current behavior. Never place it before requirements — the PRD leads with what to build, not what exists. Include: how the current system works, screenshots, field mappings, API contracts. This section is for context only and does NOT drive requirements.

#### User Experience

Structure UX to be sufficient for frontend implementation without Figma. Five subsections:

**1. Information Architecture**
- State where the new feature lives relative to existing navigation (e.g., "Agents live within the existing chat UI. No new top-level navigation.")
- Define the containment hierarchy top→bottom (e.g., Project → Chat → Agent invocation → Action items)
- List navigation additions explicitly (new tabs, sidebar items, etc.)
- State what does NOT change ("No new top-level nav items")

**2. ASCII Wireframes (for major interaction patterns)**
For major interaction patterns (3-5 per feature PRD), include ASCII wireframe diagrams inline with the JTBD they illustrate. Use box-drawing characters (┌ ┐ └ ┘ ─ │ ├ ┤). Wireframes should show layout, key fields, and interaction affordances. Not every JTBD needs a wireframe — focus on complex multi-panel layouts, forms with many fields, state machines, and multi-step workflows.

```
┌─────────────────────────────────────────┐
│ Meeting Prep Agent                   ×  │
├─────────────────────────────────────────┤
│ ┌─────────────────────────────────────┐ │
│ │ ▶ Step 1: Fetching agenda items...  │ │
│ │   Step 2: Analyzing documents...    │ │
│ │   Step 3: Generating briefing...    │ │
│ └─────────────────────────────────────┘ │
│                                         │
│ ┌─────────────────────────────────────┐ │
│ │ Briefing Output                     │ │
│ │ ─────────────────────               │ │
│ │ Key Topics: ...                     │ │
│ │ Action Items: ...                   │ │
│ │                    [Copy] [Export]   │ │
│ └─────────────────────────────────────┘ │
└─────────────────────────────────────────┘
```

**3. Interaction Flows (per feature)**
Write a separate numbered flow for each major feature or user journey. Each flow:
- Starts with the user trigger (what the user does)
- Numbers each step sequentially
- Describes what the system does at each step (not just what the user sees)
- Includes real-time/streaming states where applicable (e.g., "SSE events stream in: each step appears as a compact, collapsible row")
- Ends with the final output format and any post-output actions
- Uses concrete example inputs (e.g., "`@briefcase prep me for Thursday's board meeting`")

```
### Interaction Flow: [Feature Name]
1. User does [trigger action]
2. System responds with [response] — [visual treatment note]
3. [Real-time streaming/processing step if applicable]
4. Final output renders as [format] with sections: [list sections]
5. [Post-output action if any]
```

**4. Component Specs**
For each new UI component, define:
- **States**: list all visual states (default, loading/live, completed, error, empty)
- **Visual treatment**: background, borders, colors, layout (reference design system tokens if known, e.g., "`bg-muted/50`, rounded corners")
- **Content layout**: what appears where within the component
- **Interaction behavior**: what happens on click, expand, filter, hover
- **Constraints**: max lines, truncation rules, scroll behavior

```
**ComponentName:**
- [State]: [visual treatment + content layout]
- [State]: [visual treatment + content layout]
- Click/expand: [behavior]
- Constraints: [limits]
```

**5. Use Cases Table**
Map concrete use cases to features, triggers, and expected outputs:
```
| Use Case | Feature | Trigger | Expected Output |
|---|---|---|---|
| [Scenario name] | [Which feature] | [Exact user input example] | [What the system produces] |
```

If no Figma mockups exist, state this explicitly and note that component behavior specs above serve as the implementation reference. Reference design system primitives (e.g., "implements against shadcn/ui Collapsible, Badge, Card, Tabs").

#### Engineering Estimates
- Use ranges, not point estimates
- Split backend vs. client
- State staffing needs explicitly
- Call out known blockers and dependencies

### Step 5: Output and Present

1. Save the PRD as a markdown file (`.md`) to `/mnt/user-data/outputs/`
2. Present the file to the user
3. Provide a brief summary in chat covering:
   - What the PRD proposes (1 sentence)
   - Key data points that anchor the proposal
   - Sections flagged for user review (missing data, assumptions, open questions)
   - Suggested next steps

### Step 6: Iterate

After the user reviews, they may want to:
- **Fill gaps** — Provide missing data, metrics, or context for flagged sections
- **Adjust scope** — Add/remove features, change prioritization
- **Refine tone** — Make it more/less aggressive, more/less detailed
- **Add sections** — Appendix content, additional analysis

Update the file in place and re-present. Each iteration should reduce the number of flagged items.

### Step 7: Adversarial Review (Recommended)

After the PRD is drafted and the user is satisfied with the content, offer adversarial review.

Use AskUserQuestion:
```
Your PRD is ready for adversarial review. This spawns 5 independent expert reviewers
(Product Thinker, UX Designer, Engineering Manager, Customer Expert, QA Expert) who
read ONLY the PRD with zero prior context. They probe for ambiguities, hidden complexity,
untestable requirements, and persona coverage gaps.

Typical result: 10-20 findings, half auto-fixed, half surfaced as decisions for you.

A) Run /prd-review now (Recommended)
B) Skip — I'll review it myself
C) Run later — save PRD first
```

**If A:** Invoke the `/prd-review` skill using the Skill tool, with the PRD file path as argument. After the review completes and fixes are applied, present the updated PRD to the user for final approval.

**If B:** Skip and proceed to final output. Note in the PRD metadata that adversarial review was skipped.

**If C:** Save the PRD, tell the user: "Run `/prd-review <path>` when ready. The review works on any saved PRD."

---

## Critique Mode

If the user shares an existing PRD and asks for feedback, review, or improvement:

1. Read the document carefully
2. Score it against the quality patterns (not as a literal score, but as a structured critique)
3. Organize feedback into:
   - **Structural gaps** — Missing sections that the template expects
   - **Rigor gaps** — Claims without data, vague metrics, missing projection math
   - **Clarity gaps** — Hypotheses not stated as if/then, user problems in corporate voice
   - **Honesty gaps** — Missing prior art analysis, no "reasons to be skeptical," no risk section
   - **Tactical suggestions** — Specific improvements with examples of what "good" looks like
4. Offer to rewrite specific sections or the entire document

---

## Template Override

If the user provides their own PRD template:
- Use their section structure as the skeleton
- Apply all quality patterns from `references/quality-patterns.md` regardless of template
- If their template is missing sections that the quality patterns strongly recommend (e.g., prior art comparison, risk/skepticism), suggest adding them but don't force it
- Note any sections from their template that you don't have enough context to fill and flag them

---

## Edge Cases

- **No data available**: If the product area has no prior experiments or public benchmarks, be honest. Write "[Data gap: recommend X research before finalizing]" rather than fabricating numbers. Suggest what data would strengthen the section.
- **Very early stage**: If this is exploratory (no eng estimates, no designs), focus on Problem Definition and Opportunity Size. Mark other sections as "TBD pending [milestone]."
- **User pushes back on rigor**: If the user says "I don't have metrics for this" — that's fine. Help them identify what metrics they COULD get and where. Frame gaps as action items, not blockers.
- **Multiple audiences**: If the PRD serves both executive review and eng handoff, note where detail levels might need adjustment for different readers.
