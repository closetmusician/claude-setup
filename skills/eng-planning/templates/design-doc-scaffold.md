---
domain: <feature-domain>
skills: [<relevant-skills>]
schemas: [<relevant-schema-paths>]
---

# FEAT-XXX: [Feature Title]

**Planning Tier:** [1 — Lightweight | 2 — Standard | 3 — Comprehensive]

## Objective
<!-- TODO: Fill — single paragraph, what this feature accomplishes and why -->

## Requirements

### P0 (Must Have)

| ID | Requirement | PRD Source | Jira Story | Tasks |
|----|-------------|------------|------------|-------|
<!-- TODO: Fill — one row per P0 requirement. User-facing language matching PRD. Jira Story and Tasks columns reference S-XXX and T-XXX-N IDs from Jira Stories section. -->

<!-- BACKFILL RULE: Jira Story and Tasks columns MUST reference concrete S-XXX and T-XXX-N IDs defined in the Jira Stories section below. NEVER leave as "TBD". Write stories first, then backfill this table. -->

### P1 (Should Have)

| ID | Requirement | PRD Source | Jira Story | Tasks |
|----|-------------|------------|------------|-------|
<!-- TODO: Fill — one row per P1 requirement, or state "No P1 requirements" -->

### P2 (Nice to Have)

| ID | Requirement | PRD Source | Jira Story | Tasks |
|----|-------------|------------|------------|-------|
<!-- TODO: Fill — one row per P2 requirement, or state "No P2 requirements" -->

### Non-Goals
<!-- TODO: Fill — explicitly out-of-scope items -->

## Architecture

### System Overview
<!-- TODO: Fill — 1-2 paragraphs, how this feature fits into the existing system -->

### Component Diagram
<!-- TODO: Fill — ASCII diagram showing boundaries, data flow, external services -->

### Data Flow
<!-- TODO: Fill — ASCII diagrams for key paths (user action -> API -> service -> response) -->

### Database Schema
<!-- TODO: Fill — new tables, columns, types, constraints, indexes, JSONB schemas. "No DB changes" if N/A -->

### Frontend Architecture
<!-- TODO: Fill — module structure, component hierarchy, state management. "No FE changes" if N/A -->

### Backend Architecture
<!-- TODO: Fill — vertical slice structure, handler flow, service dependencies -->

### Error Handling Strategy
<!-- TODO: Fill — retry, fallback, circuit breaker patterns specific to this feature -->

### Security Model
<!-- TODO: Fill — auth, data access boundaries, PII handling, audit requirements -->

## Interfaces

### API Endpoints
<!-- TODO: Fill — list endpoints with purpose, reference docs/contracts/<feature>.md. "No new API endpoints" if N/A -->

### DB Changes
<!-- TODO: Fill — tables, indexes. "No DB changes" if N/A -->

### FE Changes
<!-- TODO: Fill — components. "No FE changes" if N/A -->

### New Dependencies (R17 — MANDATORY)
<!-- TODO: Fill — `package>=X.Y.Z` — [URL] — Purpose: [why] — Verified: YES. "No new dependencies" if none -->

---

## Jira Stories

### S-XXX: [Story Title]
**Priority:** P0 | P1 | P2
**Layers:** [DB, API, FE] | [DB, API] | HORIZONTAL-JUSTIFIED: [reason]
**Depends On:** — (none) | S-XXX, S-YYY
**Blocks:** S-XXX, S-YYY | — (none)
**Spec Reference:** `S-XXX @ docs/plans/FEAT-XXX-design.md#s-xxx`

**Objective:** [Single sentence — the user-visible capability this slice delivers]

**Context:** [1-2 sentences — why this matters, what user problem it solves]

**Requirements:**
- [specific bullets — must span ALL listed layers]
**Sub-tasks:** *(optional — for complex stories with distinct phases)*
1. **T-{story}-1:** [Phase description]
2. **T-{story}-2:** [Phase description]
**Build Guidance:**
- [SPECIFIC patterns, classes, utilities from codebase — NOT generic principles]
- [Each instruction: WHAT you're doing, WHY, then the specific code location]
- **Design decision:** [Inline rationale for non-obvious choices]
**Acceptance Criteria:**
- [ ] [criterion — MUST include at least one cross-layer AC if multi-layer]
**Edge Cases:**
- [User scenarios: "User does X while Y → expected behavior"]
**Test Plan:**
- Unit: [per-layer tests]
- Integration: [cross-layer wiring]
- Slice Done Gate: [single integration assertion proving the vertical slice works]

---

<!-- TODO: Fill — add more S-XXX stories as needed, each following the template above -->

## Execution DAG (Parallel Agent Optimization)

The task graph is a DAG optimized for maximum parallel execution by independent coding agents. Tasks in the same concurrency batch have NO shared file modifications.

### Concurrency Batches

| Batch | Tasks | Can Run In Parallel | Blocked By |
|-------|-------|--------------------:|-----------|
<!-- TODO: Fill — one row per batch -->

### DAG Visualization
<!-- TODO: Fill — ASCII graph showing batch execution order and dependency edges -->

### File Conflict Matrix

| Task | Creates/Modifies | Conflicts With |
|------|-----------------|---------------|
<!-- TODO: Fill — one row per S-XXX -->

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
<!-- TODO: Fill — one row per endpoint. "No API endpoints" if N/A -->

### Data Models
<!-- TODO: Fill — model definitions with fields, types, constraints. "No new data models" if N/A -->

### Error Response Shape
<!-- TODO: Fill — JSON error response schema -->

### Shared Enums/Types
<!-- TODO: Fill — shared types referenced by both FE and BE. "None" if N/A -->

### SSE Events (if applicable)
<!-- TODO: Fill — event definitions. "No SSE events" if N/A -->

## Codepath Coverage Diagram
<!-- TODO: Fill — ASCII diagram showing planned test coverage per function/codepath -->

## Failure Modes

| Codepath | Realistic Failure | Tests Cover It? | Error Handling Exists? | Silent? |
|----------|-------------------|-----------------|----------------------|---------|
<!-- TODO: Fill — one row per failure mode. Flag "Silent? Yes" as P0 -->

## Appendix: Design Decision Index

Decisions are documented inline in Architecture and story specs where they apply.
This table provides a quick-reference index.

| ID | Decision | Rationale | Where Documented |
|----|----------|-----------|-----------------|
<!-- TODO: Fill — one row per design decision -->

## Definition of Done
- [ ] All S-XXX stories pass 2 QA cycles each
- [ ] All slice integration tests pass end-to-end
- [ ] All tests pass (`make test`)
- [ ] Lint passes (`make lint`)
- [ ] User approval gate for merge
