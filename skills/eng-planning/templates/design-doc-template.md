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
### P0 (Must Have)
- [requirement]

### P1 (Should Have)
- [requirement]

### P2 (Nice to Have)
- [requirement]

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
**Objective:** [single sentence — the user-visible behavior this slice delivers]
**Requirements:**
- [specific bullets — must span ALL listed layers]
**Build Guidance:**
- Use existing `ClassName` pattern from `src/path/`
- [SPECIFIC patterns, classes, utilities — NOT generic principles]
**Acceptance Criteria:**
- [ ] [criterion — MUST include at least one cross-layer AC if multi-layer]
**Edge Cases:**
- [edge case and expected behavior]
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

## Definition of Done
- [ ] All T-XXX tasks pass 2 QA cycles each
- [ ] All slice integration tests pass end-to-end
- [ ] All tests pass (`make test`)
- [ ] Lint passes (`make lint`)
- [ ] User approval gate for merge
```
