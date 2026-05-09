---
name: prd-writer
description: "Helps product managers write high-quality, data-driven PRDs (Product Requirements Documents). Compact by default — consolidates redundant sections, enforces 'describe once, reference by ID', and mandates dense formatting. Use whenever a user wants to create a PRD, product spec, product brief, feature spec, or requirements document — including when they say 'write a PRD', 'help me spec this out', 'I need a product doc', 'turn this into a PRD', 'product requirements', or share rough notes/briefs asking to formalize them. Also trigger when the user wants to review, critique, or improve an existing PRD. Enforces data-driven rigor, testable hypotheses, prior-art honesty, and structured engineering estimates. Do NOT use for pure engineering design docs, architecture docs, or technical RFCs that aren't product-facing."
---

## Required Files
- `references/quality-patterns.md` — Quality patterns with density rules
- `references/discovery-brief-format.md` — Standalone stakeholder pitch format (Mode C only)
- `templates/diligent-prd-template.md` — Full PRD structure template (Mode A)
- `templates/prd-lite-template.md` — PRD-Lite 1-pager template (Mode B)

# PRD Writer (Compact)

Optimized for density. Same rigor as verbose PRDs but you must not lose specificity. Execute according to `references/quality-patterns.md`

**Density design choices:**
- Sections that repeated info (Problem + JTBD + Business Rules) are consolidated — describe once, reference by ID
- Business rules live inline in §2 requirements (simple as behaviors, complex as dedicated REQ-IDs) — no separate section
- UX Flows section is dedicated (§3) but organized by JTBD with explicit req ID references + illustrative edge flows — no redundancy
- Data Model lives under §7 Engineering (after effort estimates) — keeps all eng-facing content together
- Prose that restates tables is banned
- Wireframes: 3-5 per feature PRD for major interaction patterns
- Behavior minimums are guidance, not floors
- Compact formatting preferred (inline pipes, dense bullets) over multi-line prose

## Core Principles

Same as v1, plus three density rules:

1. **Every claim needs a number.** Never "significant improvement" — write "+1.65% OESPD."
2. **Hypotheses, not descriptions.** "If we [X], THEN [Y] because [Z]."
3. **Brutal honesty about prior art.** Document what's been tried, what failed, what's different.
4. **Show the projection math.** Expose derivation: "[base] x [rate] = [outcome]."
5. **User voice, not corporate voice.** "I don't know what to share" not "Users experience friction."
6. **Implementation-ready requirements.** Each P0/P1 gets numbered observable behaviors mapping to test cases.
7. **Hypotheses tied to measurable KPIs.** Each feature gets a KPI table (qual primary for early-stage, quant for mature).

### End-User POV Rule

**§1-3 must be written entirely from the end-user's perspective, stressing user benefits and observable impact.** Technical/engineering details belong in §7 Engineering only. §2 requirements may reference technical constraints sparingly — ONLY when they directly affect observable user behavior.

**The test:** If a sentence names a library, protocol, architecture pattern, or internal system and a product stakeholder couldn't explain why it matters to the user — it fails. Translate to user impact or move to §7.

**Bad (eng word salad in §1 Context):**
> "BoardDocs MCP computes outcomes client-side — server never validates majority. Vote state lives in DOM radio buttons until serialized. v1 (Redux + SignalR) introduced: vote reducer scoping bug (predicted P1), radios don't trigger save (MAP-17236, P2), premature dirty-state reset."

**Good (user-impact translation in §1 Context):**
> "Board members lose votes during long meetings — if a session runs 4+ hours, unsaved votes silently disappear. 3 customer-reported incidents in Q4 where official vote records didn't match what members selected on screen."

**Where the eng detail goes:** §7.2 Data Model or a "Technical Context" note within §7 Engineering. The raw investigation context (architecture, protocols, bug IDs) lives there for the dev team.

**§2 exception:** Numbered behaviors in requirements may include technical constraints when they produce observable user effects:
- OK: "Session expires after 4 hours; user sees 'Please refresh to continue voting' banner"
- NOT OK: "SignalR 2.4.1 lacks token refresh; requires WebSocket reconnection handler"

### Density Rules

8. **Describe once, reference everywhere.** Every behavior, flow, or rule has ONE canonical location. All other mentions use `-> See AC-2B` or `(per REQ-010.2)`. If you're writing the same logic in two sections, one of them is wrong.

9. **Tables speak for themselves.** Never follow a table with prose restating its contents. If the table needs explanation, the table is poorly structured — fix the table.

10. **Compact over verbose.** Prefer `Agendas 1-3: full wizard | 4-10: quick start | >10: button-only` over 4-line bullet lists saying the same thing. Use inline separators, dense bullets, and compressed conditional notation.

---

## Workflow

### Working Files (Context Preservation)

Same as v1 — intermediary checkpoint files prevent context loss.

**File naming:** Slugify the feature name (e.g., "Board Briefcase" -> `board-briefcase`). If unclear, use `prd-draft-YYYY-MM-DD`.

**Output directory:** Project's `docs/` if it exists, otherwise cwd.

**Intermediary files:** stored under `docs/temp` if it exists, otherwise cwd
- `<working-name>-context.md` — Step 1 checkpoint
- `<working-name>-interview.md` — Step 2 checkpoint
- `<working-name>-research.md` — Step 3 checkpoint

**Cleanup:** Delete all three after final PRD is generated & saved. AND ask user for permission

### Step 0: Resume Detection

Check for existing `*-context.md`, `*-interview.md`, `*-research.md` in `docs/` and project root. If found, offer to resume or start fresh. If not found, proceed to Step 0.5.

### Step 0.5: Determine Document Mode

Based on the user's request, determine which format to use:

**Mode A: Full PRD** (default)
Trigger: User asks for a "PRD", "spec", "product requirements", or provides enough context for a full document.
Template: `templates/diligent-prd-template.md` (all 12 sections)

**Mode B: PRD-Lite (1-pager / discovery brief)**
Trigger: User asks for a "1-pager", "discovery brief", "early-stage doc", or explicitly says they don't have enough data for a full PRD.
Template: `templates/prd-lite-template.md` (sections 1, 2, 3, 7 at reduced depth with TBD placeholders for 4-6)

**Mode C: Stakeholder Pitch**
Trigger: User explicitly asks for a "pitch brief", "stakeholder alignment doc", or "conversation starter."
Template: `references/discovery-brief-format.md` (standalone format, not expandable to full PRD)

If ambiguous, ask the user: "Do you want (A) a full PRD, (B) a PRD-Lite covering Problem, JTBD, and Engineering Effort — expandable to a full PRD later, or (C) a standalone stakeholder pitch?"

**Default to Mode B** when the user says "discovery brief" or "1-pager." Mode C requires explicit "pitch" or "conversation starter" language.

### Step 1: Gather Context

Assess what the user brought (raw notes, brief, verbal description, custom template). Extract: product/feature, target user, problem, data/metrics, prior art, org context. Identify gaps for interview.

**Checkpoint:** Write `<working-name>-context.md` with extracted context and identified gaps.

### Step 2: Interview for Gaps (MANDATORY — NEVER SKIP)

**HARD GATE:** Execute this step even if the user's input appears complete. "Already covered" is not a reason to skip — user confirmation IS the point. If a mandatory question was answered in Step 1, state your understanding and ask the user to confirm or correct. Do NOT silently assume. Skipping = protocol violation equivalent to skipping TDD.

**Procedure:** Present all mandatory questions grouped efficiently. Wait for answers. Follow up on anything too vague to write a requirement against. Do NOT proceed to Step 3 without answers.

#### Mandatory Questions (ask ALL)

- **M1. Why now?** Urgency driver — deadline, escalation, competitive window? What happens if this ships 6 months late?
- **M2. Prior art.** Tried before (internally, competitors, user workarounds)? What happened?
- **M3. Success metrics.** North star metric + guardrails (must NOT degrade). Reject "improve engagement" — push for a number or directional threshold.
- **M4. Scope boundaries.** What's explicitly out? Most likely scope creep risk? If nothing is out of scope, probe adjacent features that shouldn't ship in v1.
- **M5. KPI approach.** Mature (quant: analytics, A/B) or early-stage (qual: interviews, beta feedback)?
- **M6. Delivery context.** Product launch | demo/sprint (<3 weeks) | internal tool? Calibrates P0/P1/P2:

| Context | P0 emphasis | P1 emphasis | Deprioritize |
|---------|------------|------------|-------------|
| Product launch | Data governance, error handling, edge cases | Performance, polish | — |
| Demo/sprint (<3 weeks) | Core happy path, perceived quality, progress feedback | Broad format support, visual polish | Governance, persistence, data retention |
| Internal tool | Core functionality, correctness | Error handling | Polish, onboarding |

- **M7. Target user(s).** Who exactly — role, context, frequency? Primary persona if multiple? What do they know/not know when encountering this feature?
- **M8. Current workflow.** How is this job done today? Specific moment of friction or failure?
- **M9. Error & edge cases.** What happens on bad input, partial failure, timeout, concurrent access? Recovery path? Probe the 2-3 most likely failure modes if the user hasn't considered them.
- **M10. Dependencies.** Other teams, systems, data sources, API contracts, or shared databases that constrain the design?

#### Ambiguity Probe

After mandatory questions, review all collected context (Step 1 + M1-M10 answers) and ask: **"What in this spec could two engineers reasonably interpret differently?"** Surface any terms, behaviors, or scope edges where misreading is plausible — propose your interpretation and ask the user to confirm or correct.

#### Conditional Questions (ask when relevant)

Personas/RACI | UX detail level (flows / IA / wireframes) | tech stack constraints | effort expectations / deadlines | cross-team coordination | pricing/release constraints | data sensitivity / compliance | accessibility requirements

#### Completion Criteria

Complete when: all M1-M10 answered or confirmed, ambiguity probe resolved, and each answer is concrete enough that two engineers would make the same implementation decision.

**Checkpoint:** Write `<working-name>-interview.md` with all M1-M10 answers, ambiguity resolutions, and conditional Q&A.

### Step 3: Research & Validate

Use web search to strengthen data-driven foundation:
- Competitor features, industry benchmarks, market data
- Evidence supporting or challenging user claims
- Prior art (blog posts, press releases, product announcements)

**Guardrails:** Only verified data. Mark web-sourced vs. user-provided. Flag gaps honestly. Search for counterarguments too.

**Checkpoint:** Write `<working-name>-research.md` with findings.

### Step 4: Draft the PRD

Read reference files before drafting:
1. `templates/diligent-prd-template.md` — section structure
2. `references/quality-patterns.md` — quality bar + density rules

**Section-specific guidance:**

#### TL;DR
One sentence: gap + mechanism + projected impact. Not a description — a pitch.

#### Table of Contents
Always include. Auto-generated links to all H2/H3.

#### Problem Definition
Objective, context, strategic drivers, success measures. Include "why now." Back with evidence. **Do NOT include user pain points here** — those belong in JTBDs as evidence. **All language must be user/business-facing.** No architecture, protocols, libraries, or eng investigation notes. If the "why now" is technical debt or system fragility, frame it as user impact ("users lose data during long sessions") not eng cause ("SignalR lacks token refresh").

#### Opportunity Size
Show projection math. Reference precedents. Be honest about assumptions.

#### Jobs to Be Done & Requirements

**This is the core. Each JTBD is self-contained — problem, evidence, hypothesis, KPIs, requirements, AND business rules all in one place.**

**Anti-bloat principle:** Requirements *fall from* the JTBD — each exists because the job can't be done without it. The JTBD provides the "why"; requirements provide the "what." Don't restate the problem inside each requirement. One sentence of scope, then straight to behaviors.

**Per-JTBD structure:**
1. JTBD heading with job statement
2. Job statement in persona format
3. Evidence (user pain points with data — this is where "user voice" lives, not in Problem Definition)
4. Hypothesis: *If we [X], THEN [Y] because [Z].*
5. KPI table (qual primary for early-stage, quant for mature)
6. Requirements ordered P0 -> P1 -> P2
7. Cross-Cutting Rules subsection (only when complexity warrants dedicated REQ-IDs)

**Requirement ID format:** 2-3 letter prefix + number (e.g., AC-1, BRF-2).

**Per-requirement structure (P0/P1):**
```
**REQ-ID: Name** (P0)
[1-paragraph scope. What it does, how it works, key details.]
1. [Observable system behavior — maps to one test case]
2. [Another behavior]
3. [Error/edge case]
4. [Permission/validation constraint if applicable]
```

**P2:** Description only, no numbered behaviors.

**Business rules placement (mix approach):**
- **Simple constraints** (field validation, role checks, format rules): inline as numbered behaviors under the REQ they govern (e.g., "4. Only users with Editor role can invoke")
- **Complex cross-cutting rules** (permission models spanning multiple REQs, state machines, lifecycle transitions): dedicated REQ-IDs in a "Cross-Cutting Rules" subsection within the JTBD or at end of §2

**Behavior description rules:**
- Observable system behavior, not user action
- Concrete values: field names, max lengths, valid states
- Each independently falsifiable (one test case per item)
- Order: happy path -> error/validation -> edge cases -> constraints/permissions
- **Minimum count:** Every P0 requirement must have ≥2 numbered behaviors. If you can't identify at least 2 observable behaviors, the requirement is too vague — split or rewrite it.

**Priority tiers within each JTBD's build scope:** P0 = must ship, P1 = should ship, P2 = defer.

#### UX Flows

Dedicated section immediately after JTBD & Requirements. Organized by JTBD — each flow references requirement IDs it satisfies. **JTBDs define the "what"; UX flows show the "how."** Don't re-describe requirements, reference by ID (`-> See AC-2`).

**Per-JTBD UX subsection:**

**1. Interaction Flows** — Compact numbered flow per user journey. Each flow:
- References requirement IDs it satisfies (e.g., `→ AC-1, AC-2`)
- Numbered steps: user trigger → system response → final output
- Concrete example inputs
- Streaming/real-time states where applicable

```
### JTBD-1: [abbreviated]
#### Flow: [Feature] → AC-1, AC-2
1. User [trigger]
2. System [response]
3. Output: [format]
```

**2. Edge Flows (illustrative)** — Show business rules in action via representative scenarios. Purpose: make constraints concrete for stakeholders and designers. These are NOT exhaustive — eng planning will expand into full acceptance criteria. Include 1-2 per JTBD when meaningful rules exist.

```
### Edge Flow: [Rule Name] → REQ-010, REQ-001.4
1. User [attempts action that triggers rule]
2. System [checks constraint]
3. System [enforces — error/block/redirect]
4. User [recovery path]
```

**Guidance note in template:** "Eng planning will enumerate the full edge-case matrix from these illustrative flows."

**3. ASCII Wireframes (for major interaction patterns)** — Include 3-5 per feature PRD. Use box-drawing characters (┌ ┐ └ ┘ ─ │ ├ ┤). Focus on complex multi-panel layouts, forms with many fields, state machines, and multi-step workflows. Place with the JTBD flow they illustrate.

**Cross-cutting UX (once, after all JTBD flows):**

**4. Information Architecture** — Where feature lives. Containment hierarchy. What doesn't change.

**5. Component Specs (new components only):**
For each new UI component, define:
- **States**: all visual states (default, loading, completed, error, empty)
- **Visual treatment**: background, borders, colors, layout (reference design system tokens)
- **Interaction behavior**: click, expand, filter, hover
- **Constraints**: max lines, truncation, scroll behavior

```
**ComponentName:**
- [State]: [visual treatment + content layout]
- [State]: [visual treatment + content layout]
- Click/expand: [behavior]
- Constraints: [limits]
```

**6. Use Cases Table** — Map scenarios to JTBDs, features, triggers, outputs.

#### Risks & Out of Scope
Risks with mitigations + out of scope. Be explicit.

#### Legacy Reference (optional)
Only when replacing existing system. Context only — does NOT drive requirements.

#### Engineering (§7)
Two subsections: (1) Effort Estimates — ranges, not points; backend vs. client split; staffing needs; blockers/dependencies. (2) Data Model (if applicable) — tables/columns, API endpoints, state machines, tracking requirements. Effort first, data model second.

### Step 5: Output and Present

1. Save PRD as `.md` to output directory
2. Delete checkpoint files
3. Brief summary: what it proposes, key data anchors, sections needing review, next steps

### Step 6: Iterate

Update in place. Each iteration reduces flagged items.

### Step 7: Adversarial Review (Recommended)

Offer `/prd-review` after user is satisfied. Same as v1.

---

## Critique Mode

Same as v1. Score against quality patterns, organize feedback (structural/rigor/clarity/honesty gaps), offer rewrites.

---

## Template Override

Use user's template structure. Apply quality patterns regardless. Suggest missing sections but don't force.

---

## Edge Cases

- **No data:** Flag honestly as "[Data gap: recommend X research]"
- **Very early stage:** Use Mode B (PRD-Lite) per Step 0.5. Same section structure as full PRD, reduced depth, TBD markers for §3-8.
- **User pushes back on rigor:** Help identify obtainable metrics. Frame gaps as action items.
- **Multiple audiences:** Note where detail levels need adjustment.
