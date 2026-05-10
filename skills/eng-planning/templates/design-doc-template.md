<!-- ABOUTME: Template for the feature design doc artifact produced by Step 5a. The Opus subagent reads this template and produces a filled-in design doc at docs/plans/FEAT-XXX-design.md. Contains all required sections: architecture, design decisions, task mini-specs with vertical slice enforcement, and execution DAG. -->

# Feature Design Doc Template

Produce a complete feature design doc following this structure. Include spec-registry frontmatter and ALL sections below.

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

**LANGUAGE RULE:** Requirements tables use the PRD's user-facing language. Each row cites its parent PRD JTBD or requirement ID. Implementation details (variable names, config fields, file paths) belong in Build Guidance, not here. A stakeholder who has never read the codebase must understand every row.

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

**LANGUAGE STANDARD FOR ALL TASK CONTENT:**
- Lead technical descriptions with user impact, then mechanism (with code names woven in), then code reference
- Always preserve function, class, and variable names — but embed them in explanations that make sense without them
- Edge cases must be framed as user scenarios, not internal state descriptions
- Build Guidance must explain WHAT each step accomplishes (the goal) and name the specific code to change
- BAD: "hasStreamingAssistant becomes false while isLoading is true creating a zero-render window"
- GOOD: "Two UI components race to show the response. The streaming view (`hasStreamingAssistant`) stops because the stream ended, while the history view hasn't loaded the saved message yet (`chatMessages.refresh()` resolves in the same render batch). For one frame neither renders anything, and that blank state persists."

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
