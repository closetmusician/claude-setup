<!-- ABOUTME: Template for the feature design doc artifact produced by Step 5a. The Opus subagent reads this template and produces a filled-in design doc at docs/plans/FEAT-XXX-design.md. Contains all required sections: architecture, design decisions, task mini-specs with vertical slice enforcement, and execution DAG. -->

# Feature Design Doc Template

## Producer Instructions (DO NOT EMIT — these guide the subagent only)

- Include spec-registry frontmatter and ALL artifact sections below.
- **Vertical Slice Mandate:** Every T-XXX must be a vertical slice (thinnest end-to-end implementation touching ALL layers). BANNED: horizontal layer planning. Single-layer tickets require `HORIZONTAL-JUSTIFIED: [reason]`. T-XXX = Jira Story; sub-tasks live in Build Guidance.
- **Story Consolidation:** Start with one story per JTBD. Split ONLY when: different architectural layers with no overlap, independent testability AND value, different risk profiles, or fan-out dependency. Keep as sub-tasks when: investigation+fix pairs (tag `INVESTIGATION-FIRST`), same file/handler, same user flow, or prerequisite chain with no fan-out. Fragmentation smell: story count > N + ceil(N/2) where N = JTBD count requires justification.
- **Jira Mapping:** FEAT-XXX = Epic. T-XXX = Story (independently deliverable, reviewable, testable). Sub-tasks = phases within Build Guidance (not separate T-XXX entries).
- **DAG Optimization:** Maximize concurrent agent execution. Minimize `blocked_by` edges — only true data/API dependencies. Additive non-overlapping modifications to the same file CAN be parallelized.
- **Language Rule:** Requirements tables use PRD user-facing language with parent PRD JTBD/ID cited. No variable names, config fields, or implementation details in requirements — those go in Build Guidance only.

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

| ID | Requirement | PRD Source |
|----|-------------|------------|
| [ID from PRD] | [User-facing description matching PRD language — no variable names, no config fields] | [PRD JTBD-N / PRD requirement ID] |

### P1 (Should Have)

| ID | Requirement | PRD Source |
|----|-------------|------------|
| [ID from PRD] | [User-facing description matching PRD language] | [PRD JTBD-N / PRD requirement ID] |

### P2 (Nice to Have)

| ID | Requirement | PRD Source |
|----|-------------|------------|
| [ID from PRD] | [User-facing description matching PRD language] | [PRD JTBD-N / PRD requirement ID] |

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

## Design Decisions

### DD-NNN: [Decision Title]
**Issue:** [What needed deciding — 1-2 sentences]
**Decision:** [What was decided — specific and concrete]
**Alternatives Considered:** [Brief description of rejected options]
**Rationale:** [Why this option won — concrete tradeoffs]

[... repeat for each decision ...]

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

## Tasks

### T-XXX: [Task Title]
**Priority:** P0 | P1 | P2
**Layers:** [DB, API, FE] | [DB, API] | HORIZONTAL-JUSTIFIED: [reason]
**Depends On:** - (none) | T-XXX, T-YYY
**Blocks:** T-XXX, T-YYY | - (none)
**Spec Reference:** `T-XXX @ docs/plans/FEAT-XXX-design.md#t-xxx`

**User sees:** [What the end user currently experiences — the visible bug, missing feature, or broken behavior. Write this so someone who has never opened the codebase understands the problem.]

**Why this happens:** [1-3 sentences explaining the root cause as cause-and-effect. Use concrete nouns ("the chat area", "the streaming response") and active voice. A smart CS senior unfamiliar with this codebase should follow the logic.]

**Objective:** [single sentence — the user-visible behavior this slice delivers AFTER the fix]

**Requirements:**
- [specific bullets — must span ALL listed layers]
**Sub-tasks:** *(optional — use for complex stories with distinct phases)*
1. [Phase/step description — e.g., "Investigate guardrail config to identify false-positive trigger"]
2. [Phase/step description — e.g., "Apply CDK fix based on investigation findings"]
3. [Phase/step description — e.g., "Verify fix on dev/staging with test messages"]
**Build Guidance:**
- Use existing `ClassName` pattern from `src/path/`
- [SPECIFIC patterns, classes, utilities — NOT generic principles]
- [Each instruction explains WHAT you're doing and WHY, not just WHERE to look]
**Acceptance Criteria:**
- [ ] [criterion — MUST include at least one cross-layer AC if multi-layer]
**Edge Cases:**
- [frame as user scenarios: "User does X while Y is happening → expected behavior"]
**Test Plan:**
- Unit: [per-layer unit tests]
- Integration: [cross-layer wiring test — proves the slice connects end-to-end]
- Slice Done Gate: [the single integration assertion that proves this vertical slice works]

---

### T-XXX: [Next Task]
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
| T-XXX | [files] | [conflicting tasks or —] |

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

## Definition of Done
- [ ] All T-XXX tasks pass 2 QA cycles each
- [ ] All slice integration tests pass end-to-end
- [ ] All tests pass (`make test`)
- [ ] Lint passes (`make lint`)
- [ ] User approval gate for merge
```
