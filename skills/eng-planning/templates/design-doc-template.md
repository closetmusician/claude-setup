<!-- ABOUTME: Template for the feature design doc artifact produced by Step 5a. The Opus subagent reads this template and produces a filled-in design doc at docs/plans/FEAT-XXX-design.md. Contains all required sections: architecture, design decisions, task mini-specs with vertical slice enforcement, and execution DAG. -->

# Feature Design Doc Template

## Producer Instructions (DO NOT EMIT — these guide the subagent only)

- Include spec-registry frontmatter and ALL artifact sections below.
- **Vertical Slice Mandate:** Every S-XXX must be a vertical slice (thinnest end-to-end implementation touching ALL layers). BANNED: horizontal layer planning. Single-layer tickets require `HORIZONTAL-JUSTIFIED: [reason]`. S-XXX = Jira Story; sub-tasks live in Build Guidance.
- **Story Consolidation:** Start with one story per JTBD. Split ONLY when: different architectural layers with no overlap, independent testability AND value, different risk profiles, or fan-out dependency. Keep as sub-tasks when: investigation+fix pairs (tag `INVESTIGATION-FIRST`), same file/handler, same user flow, or prerequisite chain with no fan-out. Fragmentation smell: story count > N + ceil(N/2) where N = JTBD count requires justification.
- **Jira Mapping:** FEAT-XXX = Epic. S-XXX = Story (independently deliverable, reviewable, testable). Sub-tasks = phases within Build Guidance (not separate S-XXX entries).
- **DAG Optimization:** Maximize concurrent agent execution. Minimize `blocked_by` edges — only true data/API dependencies. Additive non-overlapping modifications to the same file CAN be parallelized.
- **Language Rule:** Requirements tables use PRD user-facing language with parent PRD JTBD/ID cited. No variable names, config fields, or implementation details in requirements — those go in Build Guidance only.

### STORY AND TASK NUMBERING CONVENTION

Stories and tasks within this design doc use **spec-local IDs** — stable references that downstream agents, the orchestrator, and the Requirements traceability table all use to cross-reference.

- **Stories:** `S-XXX` where XXX is a short mnemonic (e.g., `S-CP`, `S-AG`, `S-RN`) or a sequential number (e.g., `S-001`, `S-002`).
- **Tasks (sub-tasks within a story):** `T-{story}-{N}` where `{story}` is the story mnemonic and `{N}` is a sequential number starting at 1. Examples: `T-CP-1`, `T-CP-2`, `T-AG-1`, `T-AG-2`.
- Every numbered sub-task in Build Guidance MUST carry its `T-XXX-N` ID prefix so it can be referenced from the Requirements table's Tasks column.

### STORY DECOMPOSITION METHOD (follow in order):

1. **INVENTORY:** One row per PRD JTBD → layers touched (DB/API/BE/FE/Infra/Config), estimated file count from explorer report, external deps.

2. **DEFAULT:** One S-XXX per JTBD. Each story = vertical slice delivering that JTBD end-to-end. This is your starting point — deviate only with justification.

3. **SPLIT only if:**
   - Size smell: >15 file modifications in Build Guidance
   - Layer isolation: a layer subset ships independently with user value
   - Risk isolation: uncertain part (new dep, unfamiliar pattern) separated from routine
   - Fan-out: multiple stories need a subset of this story's output
   - Each split result must still be a vertical slice (2+ layers) unless HORIZONTAL-JUSTIFIED.

4. **MERGE back if:**
   - Two stories share the same handler/component + test file
   - One story has no independent user value without the other

5. **FOUNDATIONAL EXTRACTION:** Shared migrations/types needed by 2+ stories → max 1-2 S-000 stories (HORIZONTAL-JUSTIFIED: foundational types for N slices). If you need 3+, you're slicing wrong.

6. **FRAGMENTATION CHECK:** story_count > N + ceil(N/2) where N = JTBD count. If triggered, justify each extra story or merge back.

7. **DAG EDGES:** Depends On = data/API/component creation dependency ONLY. "Nice to do first" is not a dependency.

8. **REQUIREMENTS TABLE BACKFILL (mandatory second pass):** After ALL stories and their numbered tasks are fully defined, go BACK to the Requirements tables and fill in the Jira Story and Tasks columns. Every row must reference a concrete `S-XXX` and one or more `T-XXX-N` IDs — NEVER leave these as "TBD". This is a second pass over the document, not a first-draft placeholder. If a requirement maps to multiple tasks, list all of them comma-separated.

---

## Artifact Template (emit everything below this line)

Produce the complete feature design doc following this structure:

```markdown
---
domain: <feature-domain>
skills: [<relevant-skills>]
schemas: [<relevant-schema-paths>]
---

# FEAT-XXX: [Feature Title]

**Planning Tier:** [1 — Lightweight | 2 — Standard | 3 — Comprehensive]

## Objective
[Single paragraph — what this feature accomplishes and why]

## Requirements

### P0 (Must Have)

| ID | Requirement | PRD Source | Jira Story | Tasks |
|----|-------------|------------|------------|-------|
| [ID] | [User-facing description matching PRD language — no variable names, no config fields] | [PRD JTBD-N / PRD requirement ID] | [S-XXX: Name] | [T-XXX-1, T-XXX-2, ...] |

<!-- BACKFILL RULE: Jira Story and Tasks columns MUST reference concrete S-XXX and T-XXX-N IDs defined in the Jira Stories section below. NEVER leave as "TBD". Write stories first, then backfill this table. -->

### P1 (Should Have)

| ID | Requirement | PRD Source | Jira Story | Tasks |
|----|-------------|------------|------------|-------|
| [ID] | [User-facing description matching PRD language] | [PRD JTBD-N / PRD requirement ID] | [S-XXX: Name] | [T-XXX-1, T-XXX-2, ...] |

### P2 (Nice to Have)

| ID | Requirement | PRD Source | Jira Story | Tasks |
|----|-------------|------------|------------|-------|
| [ID] | [User-facing description matching PRD language] | [PRD JTBD-N / PRD requirement ID] | [S-XXX: Name] | [T-XXX-1, T-XXX-2, ...] |

### Non-Goals
- [explicitly out of scope]

## Architecture

### System Overview
[1-2 paragraphs — how this feature fits into the existing system]

### Component Diagram
[ASCII diagram showing boundaries, data flow, external services]

### Data Flow
[ASCII diagrams for key paths — e.g., user action → API → LLM → response]

### Database Schema
[New tables, columns, types, constraints, indexes, JSONB schemas]

### Frontend Architecture
[Module structure, component hierarchy, state management approach]

### Backend Architecture
[Vertical slice structure, handler flow, service dependencies]

### Error Handling Strategy
[Retry, fallback, circuit breaker patterns — specific to this feature]

### Security Model
[Auth, data access boundaries, PII handling, audit requirements]

## Interfaces

### API Endpoints
- `POST /api/...` — [purpose] (full contract in `docs/contracts/<feature>.md`)

### DB Changes
- Table: `...`
- Indexes: `...`

### FE Changes
- Component: `...`

### New Dependencies (R17 — MANDATORY)
- `package>=X.Y.Z` — [URL] — Purpose: [why] — Verified: YES

---

## Jira Stories

### S-XXX: [Story Title]
**Priority:** P0 | P1 | P2
**Layers:** [DB, API, FE] | [DB, API] | HORIZONTAL-JUSTIFIED: [reason]
**Depends On:** — (none) | S-XXX, S-YYY
**Blocks:** S-XXX, S-YYY | — (none)
**Spec Reference:** `S-XXX @ docs/plans/FEAT-XXX-design.md#s-xxx`

**Objective:** [Single sentence — the user-visible capability this slice delivers]

**Context:** [1-2 sentences — why this matters, what user problem it solves. For bugfixes: what the user currently experiences and the root cause.]

**Requirements:**
- [specific bullets — must span ALL listed layers]
**Sub-tasks:** *(optional — for complex stories with distinct phases)*
1. **T-{story}-1:** [Phase description]
2. **T-{story}-2:** [Phase description]
**Build Guidance:**
- [SPECIFIC patterns, classes, utilities from codebase — NOT generic principles]
- [Each instruction: WHAT you're doing, WHY, then the specific code location]
- **Design decision:** [Inline rationale for non-obvious choices — replaces standalone DD-NNN sections]
**Acceptance Criteria:**
- [ ] [criterion — MUST include at least one cross-layer AC if multi-layer]
**Edge Cases:**
- [User scenarios: "User does X while Y → expected behavior"]
**Test Plan:**
- Unit: [per-layer tests]
- Integration: [cross-layer wiring]
- Slice Done Gate: [single integration assertion proving the vertical slice works]

---

### S-XXX: [Next Story]
[... same template ...]

## Execution DAG (Parallel Agent Optimization)

The task graph is a DAG optimized for maximum parallel execution by independent coding agents. Tasks in the same concurrency batch have NO shared file modifications.

### Concurrency Batches

| Batch | Tasks | Can Run In Parallel | Blocked By |
|-------|-------|--------------------:|-----------|
| 1 | [tasks] | [yes/no + reason] | — |
| 2 | [tasks] | [yes/no + reason] | Batch N: [tasks] |

### DAG Visualization
[ASCII graph showing batch execution order and dependency edges]

### File Conflict Matrix

| Task | Creates/Modifies | Conflicts With |
|------|-----------------|---------------|
| S-XXX | [files] | [conflicting tasks or —] |

### Agent Assignment Rules
- Each batch launches N agents simultaneously (one per task in the batch)
- Agent receives: the task's mini-spec (via Spec Reference path), API contract, and this DAG
- Agent declares DONE only when its **Slice Done Gate** integration test passes
- Batch N+1 agents do NOT launch until ALL Batch N blocking tasks report DONE

## API Contract Summary

Full contract lives in `docs/contracts/<feature>.md` (separate file — FE and BE teams reference independently). This section summarizes the contract for quick reference within the design doc.

### Endpoints

| Method | Path | Request Body | Response Body | Status Codes |
|--------|------|-------------|---------------|-------------|
| POST | `/api/...` | `{ field: type }` | `{ field: type }` | 201, 400, 401, 500 |
| GET | `/api/...` | — | `{ field: type }` | 200, 401, 404 |

### Data Models

```
ModelName {
  id: UUID (PK)
  field: type (constraint)
  created_at: timestamp
}
```

### Error Response Shape

```json
{
  "error": {
    "code": "ERROR_CODE",
    "message": "Human-readable message",
    "details": {}
  }
}
```

### Shared Enums/Types
- `StatusEnum`: draft | active | archived
- [additional shared types referenced by both FE and BE]

### SSE Events (if applicable)
- Event: `event_name` — `{ field: type, field: type }`

## Codepath Coverage Diagram

For each vertical slice, show planned codepaths and where tests should exist. Append after implementation planning is complete.

```
PLANNED CODEPATH COVERAGE
===========================
[+] src/services/feature.py
    |
    +-- create_item()
    |   +-- [UNIT]        Happy path — valid input
    |   +-- [UNIT]        Validation failure — missing required field
    |   +-- [INTEGRATION] DB write + read-back verification
    |   +-- [UNIT]        Edge: empty string input
    |
    +-- get_items()
        +-- [UNIT]        Pagination happy path
        +-- [UNIT]        Edge: page beyond range
        +-- [E2E]         Full flow: create -> list -> verify

[+] src/api/routes.py
    |
    +-- POST /api/items
    |   +-- [INTEGRATION] Request validation + service call
    |   +-- [UNIT]        Auth middleware rejection
    |
    +-- GET /api/items
        +-- [INTEGRATION] Query params parsing + response shape

-------------------------------------
PLANNED COVERAGE: X paths
  Unit: N | Integration: N | E2E: N
-------------------------------------
```

## Failure Modes

| Codepath | Realistic Failure | Tests Cover It? | Error Handling Exists? | Silent? |
|----------|-------------------|-----------------|----------------------|---------|
| create_item() | DB connection timeout during write | Yes (integration) | Yes (retry + 503) | No |
| get_items() | Malformed pagination params | No — ADD TEST | Yes (400 response) | No |
| POST /api/items | Request body exceeds size limit | No — ADD TEST | No — ADD HANDLER | Yes! |

Flag any "Silent? Yes" entries as **P0** — silent failures in production are unacceptable.

## Appendix: Design Decision Index

Decisions are documented inline in Architecture and story specs where they apply.
This table provides a quick-reference index.

| ID | Decision | Rationale | Where Documented |
|----|----------|-----------|-----------------|
| DD-1 | [decision title] | [1-line rationale] | Architecture § [section] |
| DD-2 | [decision title] | [1-line rationale] | S-XXX Build Guidance |

## Definition of Done
- [ ] All S-XXX stories pass 2 QA cycles each
- [ ] All slice integration tests pass end-to-end
- [ ] All tests pass (`make test`)
- [ ] Lint passes (`make lint`)
- [ ] User approval gate for merge
```
