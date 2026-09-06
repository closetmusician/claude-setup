# ABOUTME: Story artifact template for /eng-stories skill.
# ABOUTME: Produces Jira-ready stories with user-facing language throughout.
# ABOUTME: Contains producer instructions + full artifact structure.
# ABOUTME: Two story forms: Team-Size (default — sprint-board unit) and Large (full mini-spec).
# ABOUTME: Placeholders: [FEAT_ID] feature identifier, [STORY_SIZE] team|large.

# Stories Template — eng-stories

## Producer Instructions (DO NOT EMIT — these guide the subagent only)

- Include ALL artifact sections below.
- **Story Size Mode (`[STORY_SIZE]`):**
  - **`team` (default):** one story = ONE user action, ~2 Given/When/Then ACs, ≤250 words. Use the **Team-Size Story Form**. Sections shared across stories (Roles & Permissions, Field Definitions, Default Values, Visibility Rules) are written ONCE at feature level — never repeated per story. This is the sprint-board unit engineers actually pull; June 2026 lesson: 104 mini-specs with 2,036 ACs were rejected as "too long" by the eng team whose unit is ~250 words / 2 ACs.
  - **`large`:** full mini-spec per story. Use the **Large Story Form**. For document-first review or `/eng-planning` consumption — not for a sprint board.
  - **Both modes:** every story gets an Estimate (XS/S/M/L/XL) in the Story Index. **Any story you would estimate L or XL MUST be split (vertically) before you emit it.** The validator rejects L/XL rows.
- **Language Standard (Non-Negotiable):** All story content — TITLES, ID mnemonics, user stories, objectives, context, requirements, workflows, ACs — use plain English that a completely non-technical person can read. No variable names, config fields, class names, framework terms, or state-machine notation ANYWHERE. There is no technical section in the story artifact — all content is PM-facing.

  **The test:** Hand the requirement to a board director or school principal. If they need an engineer to explain it, rewrite it.

  **BAD** (jargon as description):
  > **Objective:** "Implement AgendaItemService with CRUD endpoints and SignalR hub broadcast on mutation"
  > **Requirement:** "State machine: idle -> voting -> stopped -> finalized; server validates transitions; 409 on invalid"
  > **AC:** "AgendaController.Post returns 201 with Location header"

  **GOOD** (outcome-first, same technical depth preserved):
  > **Objective:** "Board members can create, edit, reorder, and delete agenda items, with changes appearing instantly for all connected users"
  > **Requirement:** "A vote moves through four stages in order: not started, voting open, voting closed, and results final. The system only allows moving forward to the next stage — skipping or going backward is not allowed."
  > **AC:** "Creating an agenda item shows it immediately in every board member's view without refresh"

- **Titles and IDs (jargon ban applies to them too):**
  - **BAD:** `### S-CRUD: Agenda Item CRUD Endpoints with SignalR Broadcast`
  - **GOOD:** `### S-AG: Manage Agenda Items in Real Time`
  - ID mnemonics come from the user's domain (`S-AG` agenda, `S-VT` voting) — never tech terms (`S-API`, `S-DB`, `S-CRUD` banned).
- **Specificity Preservation:** When rewriting technical language to plain English, NEVER drop specific values. Retry counts, timeout durations, polling intervals, size limits, multi-step mechanisms must survive the rewrite. "Poll every 1 second for up to 10 seconds" stays as those exact numbers, not "polls at short intervals." "Requires both org-level enable AND document-level toggle" stays as a two-step gate, not "can be enabled." Dropping a specific number or mechanism is a P0 content loss — same severity as dropping a requirement. A script diffs your output against the behavioral inventory; vaporized numbers WILL be caught.
- **Story Decomposition (Vertical Slices — aligned with /eng-planning):** Every S-XXX is a **vertical slice**: a coherent, independently testable unit of user-visible value, cutting through whatever parts of the system that requires. **BANNED: horizontal layer decomposition** (all data setup → all backend → all screens). A story that genuinely covers only one layer must carry `HORIZONTAL-JUSTIFIED: [reason]` next to its Priority line (legitimate example: shared foundational data setup required by 2+ stories).
- **Story Consolidation (large mode):** Keep as sub-tasks when: investigation+fix pairs (tag `INVESTIGATION-FIRST`), same file/handler, same user flow, or prerequisite chain with no fan-out. Fragmentation smell: story_count > N + ceil(N/2) where N = JTBD count requires justification. **(team mode: consolidation does not apply — one user action per story is the unit; expect story counts well above JTBD count.)**
- **Jira Mapping:** FEAT-XXX = Epic. S-XXX = Story (independently deliverable, reviewable, testable). Sub-tasks = phases within the story (not separate S-XXX entries).
- **DAG Optimization:** Maximize concurrent agent execution. Minimize `blocked_by` edges — only true data/API dependencies. Additive non-overlapping modifications to the same file CAN be parallelized.
- **Requirements Language (Strict PM-Facing):** Requirements tables are the contract with stakeholders — not engineers. No variable names, config fields, state-machine notation, HTTP status codes, or implementation details anywhere.

  **BAD:** "R-003: Implement SignalR hub for real-time agenda mutation broadcast with optimistic concurrency via ETag"
  **GOOD:** "R-003: Changes to agenda items appear instantly for all users viewing the same meeting"

- **Where technical behaviors go:** Source-derived behavioral requirements from the code explorer are NOT placed in a technical section:
  - `[REQ]`-tagged items: rewrite as user-facing requirements, workflow steps, edge cases, or `[SOURCE-DERIVED]` ACs — in plain English.
  - `[IMPL]`-tagged items: do NOT add to the story. Consumed by `/eng-planning` downstream.
  - Out-of-PRD-scope behavior: `[OUT-OF-SCOPE: reason]` in a separate list below the story.
- **Behavioral Requirements:** Cross-cutting concerns (concurrent access, audit logging, accessibility) MUST be expressed as user-facing requirements or workflow steps — never an engineering checklist. "Two users editing the same agenda at the same time both see each other's changes without losing work" is a requirement. "Concurrent access: handled via optimistic locking" is not.
- **Detailed Requirements:** Specific enough that an engineer knows what to build WITHOUT a separate technical doc — through specificity of behavior, not code references: exact field names as users see them, specific numbers/limits, error messages users see, edge case behaviors.
- **Detailed Workflows (large mode):** Cover happy path + key error paths + recovery. Each step specific enough that a QA tester could write a test from it. (team mode: error behavior goes into the ~2 ACs and Edge Cases instead of a Workflow section.)
- **DECISION_REQUIRED:** When an AC depends on an unresolved design choice, tag it: `DECISION_REQUIRED: [question]`. Do not block or invent an answer.
- **Open Questions:** Copy the zero-coverage domain questionnaire (from `domain-questionnaire.md`) into the Open Questions appendix verbatim. Never omit it — silence about zero-coverage areas is the known failure mode.

### Story Decomposition Method

Follow these steps in order:

1. **INVENTORY:** One row per PRD JTBD -> areas affected, estimated file count from explorer report, external deps. Coverage planning only, not story structure.
2. **DEFAULT unit:** `team` mode — one story per USER ACTION within each JTBD (create, edit, delete, reorder, share are five stories, not one). `large` mode — one story per JTBD as a vertical slice.
3. **SPLIT only if** (any mode): estimate exceeds M; a subset ships independently with user value; risk isolation; fan-out (multiple stories need a subset of this story's output). Splits stay vertical — never split INTO layers.
4. **MERGE back if** (large mode): two stories share the same handler/component + test file, or one has no independent user value without the other.
5. **FOUNDATIONAL EXTRACTION:** Shared groundwork needed by 2+ stories -> max 1-2 S-000 stories tagged `HORIZONTAL-JUSTIFIED: foundational, required by 2+ stories`. Needing 3+ means you're splitting too fine.
6. **FRAGMENTATION CHECK (large mode only):** story_count > N + ceil(N/2) where N = JTBD count → justify each extra story or merge back.
7. **DAG EDGES:** Depends On = data/API/component creation dependency ONLY. "Nice to do first" is not a dependency.
8. **REQUIREMENTS TABLE BACKFILL (mandatory second pass):** After ALL stories are defined, go BACK to the Requirements tables and fill Jira Story + Tasks columns with concrete S-XXX / T-XXX-N. NEVER "TBD".
9. **LANGUAGE CHECK (mandatory final pass):** Re-read every TITLE, ID mnemonic, user story, objective, context, requirement, workflow step, and AC. Board-director test on each. State-machine notation, HTTP codes, class names, config fields — banned everywhere.

### Story and Task Numbering Convention

- **Stories:** `S-XXX` — short domain mnemonic (`S-AG`, `S-VT`) or sequential (`S-001`). Mnemonics from the user's domain, never tech terms.
- **Tasks (sub-tasks within a story):** `T-{story}-{N}`, sequential from 1: `T-AG-1`, `T-AG-2`.

---

## Artifact Template

```markdown
---
domain: <feature-domain>
story_size: team|large
source_repos: [<paths-used-for-behavioral-extraction>]
---

# [FEAT_ID]: [Feature Title] — Stories

## Story Index

| Story ID | Title | Priority | Estimate | Dependencies |
|----------|-------|----------|----------|--------------|
| S-XXX | [plain-English title] | P0 | XS/S/M (never L/XL — split those) | — (none) |
| S-YYY | [plain-English title] | P1 | S | S-XXX |

## Objective
[Single paragraph — what this feature accomplishes and why, in plain English]

## Roles & Permissions  *(feature-level — shared by all stories; per-story only in large mode when a story differs)*

| Role | Permission | Description |
|------|-----------|-------------|
| [role name] | [plain description of what they can do] | [when/why this applies] |

## Field Definitions  *(feature-level, team mode — for forms/data entry across stories)*

| Field | Type | Required | Default | Constraints |
|-------|------|----------|---------|-------------|
| [field name] | [text/date/number/choice] | Yes/No | [default or —] | [e.g., "1-255 characters", "must be in the future"] |

## Default Values
- **[Field name]:** [default value and when it applies]

## Visibility Rules  *(who sees what, and when)*
- **[Role/status condition]:** [what is visible/hidden and why]

## Requirements

### P0 (Must Have)
| ID | Requirement | PRD Source | Jira Story | Tasks |
|----|-------------|-----------|------------|-------|
| R-001 | [plain English — a non-technical person must understand this] | [PRD req ID] | S-XXX | T-XXX-1, T-XXX-2 |

### P1 (Should Have)
[same structure]

### P2 (Nice to Have)
[same structure]

### Non-Goals
[explicitly out-of-scope items from PRD]

## Jira Stories

<!-- ================= TEAM-SIZE STORY FORM (default) ================= -->
### S-XXX: [One user action, plain English — e.g., "Reorder Agenda Items"]
**Priority:** P0 | **Estimate:** XS/S/M | **Depends On:** — (none) | S-YYY
**Spec Reference:** `S-XXX @ docs/plans/[FEAT_ID]-stories.md#s-xxx`

**User Story:**
As a [role], I want to [single action], so that [benefit].

**Business Value:** [one sentence] | **Success Metric:** [one measurable outcome]

**Preconditions:** [1-2 bullets — what must be true before this action]

**Acceptance Criteria:** *(~2 — Given/When/Then, user-testable, specific values preserved)*
- [ ] Given [context], when [action], then [observable outcome with exact numbers/limits]
- [ ] Given [failure/edge context], when [action], then [what the user sees and how they recover]

**Edge Cases:** *(only if source-derived; 1-2 max — bigger sets mean the story should split)*
- **EC-1:** Scenario: […] / Expected Behavior: […] / Rationale: […]

**Test Plan:**
- Slice Done Gate: [single end-to-end assertion proving the user-visible objective — exact spelling required; /eng-planning validators grep for it]

<!-- ================= LARGE STORY FORM (--story-size large) ================= -->
### S-XXX: [Story Title]
**Priority:** P0 | P1 | P2  *(single-layer stories only: append `HORIZONTAL-JUSTIFIED: [reason]`)*
**Estimate:** XS/S/M
**Depends On:** — (none) | S-XXX, S-YYY
**Blocks:** S-XXX, S-YYY | — (none)
**Spec Reference:** `S-XXX @ docs/plans/[FEAT_ID]-stories.md#s-xxx`

**User Story:**
As a [role], I want to [action], so that [benefit].

**Business Value:** [Why this matters — one sentence.]
**Success Metric:** [One measurable outcome]

**Objective:** [Single sentence — what the user can do or what changes for them.]

**Context:** [1-2 sentences — why this matters, what user problem it solves.]

**Roles & Permissions:**

| Role | Permission | Description |
|------|-----------|-------------|
| [role name] | [plain description] | [when/why this applies] |

**Preconditions:**
1. [What must be true before this story's workflow begins]

**Workflow:** *(step-by-step — happy path, key error paths, recovery)*
1. [User action or system response — plain English]
2. [Next step — include what the user sees]
3. [If something goes wrong at step N: what the user sees and how they recover]

**Requirements:**
- [Specific, detailed bullets in user-facing language — exact field names as users see them, specific numbers/limits, error behaviors]

**Field Definitions:** *(for stories involving forms or data entry)*

| Field | Type | Required | Default | Constraints |
|-------|------|----------|---------|-------------|
| [field name] | [type] | Yes/No | [default or —] | [constraints] |

**Default Values:**
- **[Field name]:** [default value and when it applies]

**Visibility Rules:**
- **[Role/status condition]:** [what is visible/hidden and why]

**Sub-tasks:** *(optional — distinct phases)*
1. **T-{story}-1:** [Phase description]

**Acceptance Criteria:**
- [ ] [criterion — user-testable behavior in plain English]
- [ ] [SOURCE-DERIVED] [criterion from behavioral inventory, rewritten as user-facing behavior]

**Edge Cases:**

**EC-1: [Short title]**
- **Scenario:** [What the user does or what happens]
- **Expected Behavior:** [What the system should do]
- **Rationale:** [Why this behavior is correct]

**Test Plan:**
- Unit: [what to test per component]
- Integration: [how components work together]
- Slice Done Gate: [single end-to-end assertion proving this story's user-visible objective is met]

**Out-of-Scope Behaviors:** *(only if behavioral inventory surfaced behaviors outside PRD scope)*
- [OUT-OF-SCOPE: behavior — reason]

---

## Execution DAG

### Dependency Order
| Batch | Stories (parallel) | Blocked By |
|-------|--------------------|------------|
| 1 | S-XXX, S-YYY | — |
| 2 | S-ZZZ | S-XXX |

### DAG Visualization
[ASCII graph showing dependency edges]

### File Conflict Matrix
| Story | Creates/Modifies | Conflicts With |
|-------|-----------------|----------------|
| S-XXX | [files] | — (none) |
| S-YYY | [files] | S-XXX (additive, safe to parallel) |

## Behavioral Coverage Summary

**Source repos analyzed:** [paths]
**Total source behaviors found:** N
**Covered in story ACs/requirements:** M (X%)
**Source-derived items added:** D
**Out-of-scope behaviors noted:** O

### Uncovered Behaviors (for PM decision)
| Behavior | Source | Category | Suggested Action |
|----------|--------|----------|-----------------|
| [behavior] | [file:line] | EXTRACTION_GAP | Flag for PM scope decision |
| [behavior] | — | NEW_REQUIREMENT | Flag for product discovery |

## Open Questions (Domain Questionnaire)
*(verbatim from domain-questionnaire.md — PRD areas with zero source coverage; a PM must answer these before the affected stories are trustworthy)*
| Area | Question | Why it matters |
|------|----------|----------------|
| [PRD area] | [What should happen when… / Who is allowed to… / What are the limits for…] | [risk if unanswered] |

## DECISION_REQUIRED Items
| Story | AC | Question |
|-------|----|----------|
| S-XXX | [AC text] | [design question that needs resolution] |

## Definition of Done
- [ ] All titles, IDs, user stories, objectives, requirements, workflows, and ACs use plain English (board-director test passed)
- [ ] Every story is a vertical slice (or carries HORIZONTAL-JUSTIFIED) with a Slice Done Gate in its Test Plan
- [ ] No story estimated above M — oversized stories split before delivery
- [ ] All source-derived behaviors are either in ACs/requirements or explicitly out-of-scope
- [ ] Specific values (numbers, durations, limits, mechanisms) preserved from source — specificity script clean or dispositioned
- [ ] All DECISION_REQUIRED items resolved before BUILD
- [ ] Open Questions (zero-coverage areas) answered by PM or explicitly accepted as risk
- [ ] PM has reviewed EXTRACTION_GAP and NEW_REQUIREMENT items
- [ ] Requirements table Jira Story and Tasks columns fully backfilled
- [ ] Cross-cutting behavioral requirements (concurrency, accessibility, audit, etc.) expressed as user-facing requirements in relevant stories
```
