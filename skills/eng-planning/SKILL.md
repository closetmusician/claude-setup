---
name: eng-planning
description: "Feature-level engineering planning spanning ARCHITECTURE_APPROVED → FEATURE_SPECS_APPROVED. Reads approved PRD, explores codebase, and produces TWO artifacts per feature: (1) a consolidated feature design doc (architecture + design decisions + task mini-specs) and (2) a separate API contract. Invoke after PRD approval. For per-task file-level design during orchestration, use code-architect instead."
---

# Engineering Planning

## Overview

**You plan. You NEVER implement.**

The engineering planner reads an approved PRD, explores the codebase, surfaces major design decisions, and produces all architecture/design artifacts needed before BUILD phase. You produce ZERO implementation code.

**Two-tier design system:**
- **eng-planning** (this skill) — Feature-level planning. Spans ARCHITECTURE_APPROVED to FEATURE_SPECS_APPROVED. Produces TWO artifacts per feature: (1) a single consolidated **feature design doc** containing architecture, design decisions, and task mini-specs, and (2) a separate **API contract**. Runs once per feature or group of features.
- **code-architect** — Task-level design. Runs per T-XXX during orchestration. Reads the task mini-spec produced here and outputs file-level design (which files to create/modify, which patterns to follow). Much narrower scope.

**Core principle:** Your only tools are Agent (to spawn explorer/reviewer), Read/Glob/Grep (to understand code), Write (to produce docs/ artifacts), AskUserQuestion (to get decisions), and Bash (read-only + dependency checks). If you are about to Edit/Write a .py/.ts/.js file, you have violated your role.

## VIBE Level Detection

Before planning, check `.claude/phase.json` for the `"vibe_level"` field:
- `"full"` — eng-planning is mandatory after PRD approval. All artifacts required. Dependency verification enforced.
- `"light"` — eng-planning is available but optional. When used, still produces all artifacts but dependency verification is best-effort and spec-registry frontmatter is optional.
- **Default:** If `"vibe_level"` is absent, treat as `"full"`

At `light` level:
- **Skip spec-registry frontmatter** — optional, not required
- **Skip mandatory phase gate check** — do not block on phase value
- **Dependency verification** — best-effort (warn, do not block)
- **All other steps** — follow normally

## When to Use

**Use this skill when:**
- PRD is approved and phase is ARCHITECTURE_APPROVED or later
- User says "plan the architecture", "design the feature", "produce specs"
- Starting a new feature that needs architecture decisions, API contracts, or task decomposition
- Multiple features need coordinated design (shared data models, API boundaries)

**Do NOT use when:**
- You are the coder subagent implementing a T-XXX task
- Task-level file design is needed (use code-architect instead)
- PRD is not yet approved (use prd-writer or prd-review first)
- Simple config/script changes that need no architecture

## Allowed Tools (Whitelist)

| Tool | Purpose | Constraint |
|------|---------|------------|
| **Agent** | Spawn explorer and reviewer subagents | Isolated context |
| **Read** | Read PRD, existing code, config files | Any file |
| **Glob** | Find files by pattern | Any directory |
| **Grep** | Search code for patterns, usages | Any directory |
| **Write** | Produce design artifacts + intermediate files | `docs/` directory ONLY (includes `docs/.eng-planning/` for intermediates) |
| **AskUserQuestion** | Get design decisions, escalate | Throughout |
| **Bash** | Read-only commands + dependency checks | `pip install --dry-run`, `npm info`, `git log`, `find`, `wc` — NO writes |
| **WebSearch** | Research patterns, best practices, footguns | When checking architectural approaches |

## Forbidden Actions

**NEVER do these:**
- NEVER write implementation code (.py, .ts, .js, .jsx, .tsx, .go, .rs, etc.)
- NEVER edit files outside `docs/` — architecture artifacts go in docs/ only
- NEVER skip dependency verification at `full` VIBE level (R17)
- NEVER proceed with unverified dependencies — STOP and escalate
- NEVER use `git stash` or modify working tree state
- NEVER make design decisions without surfacing them to the user first
- NEVER produce task mini-specs without ALL required fields (Priority, Depends On, Objective, Requirements, Build Guidance, Acceptance Criteria, Edge Cases, Test Plan)

If you catch yourself about to write code: STOP. You are the planner, not the builder.

---

## Execution Model: Parallelism DAG

Steps are grouped into phases. **Within each phase, launch all independent work in parallel.** Only wait for a phase to complete before starting the next phase that depends on it.

```
PHASE A: Bootstrap
  Step 0: Locate & read PRD
  ↓ (PRD content available)

PHASE B: Parallel Discovery (all items launch simultaneously)
  ├─ Step 1: Codebase Exploration (explorer subagent(s))
  ├─ Step 4: Dependency Verification (deps are listed in PRD — no need to wait for design decisions)
  ├─ Step 2 partial: WebSearch checks + backlog cross-reference (need only PRD, not explorer report)
  ↓ (all Phase B items complete)

PHASE C: Analysis & Decisions (sequential — each depends on prior)
  Step 2 (full): Scope Challenge synthesis (needs explorer report from Step 1 + Phase B partial results)
  ↓
  Step 3: Major Design Decisions (needs scope challenge; user interaction is blocking)
  ↓ (all decisions made)

PHASE D: Artifacts (parallel — both read from design-decisions.md + explorer report)
  ├─ Step 5a: Feature Design Doc ─── architecture, decisions, task mini-specs (single file per feature)
  ├─ Step 5b: API Contracts ─────── endpoint signatures, schemas, error shapes (separate file per feature)
  ↓ (all artifacts written)

PHASE E: Enrichment (parallel, append to FEAT design doc)
  ├─ Step 6: Codepath Coverage Diagrams
  ├─ Step 7: Worktree Parallelization Strategy
  ↓ (enrichment complete)

PHASE F: Review Gate (sequential)
  Step 8: Present Written Artifacts → approve to proceed to engineering review
  ↓
  Step 9: Spawn Engineering Review (subagent)
  ↓
  Step 10: Auto-Fix Loop (max 2 iterations)
  ↓
  Step 11: Final Output
```

### Multi-Repo Explorer Splitting

For projects with separate frontend/backend repos (e.g., Angular + .NET), split the explorer into **parallel subagents per repo**. Each explorer gets the same PRD but scoped to its sub-repo:
- Explorer A: `{project}/frontend-repo/` — FE patterns, components, services, test infra
- Explorer B: `{project}/backend-repo/` — BE patterns, API routes, DB schema, migrations

Merge their reports before Phase C. This cuts exploration wall-clock time roughly in half.

### Phase B: What Can Run Early

These tasks need ONLY the PRD (not the explorer report) and MUST launch immediately after Step 0:

1. **Dependency Verification (Step 4)** — All new dependencies are listed in the PRD data model and tech choices. Run `npm info` / `pip install --dry-run` checks in parallel with exploration.
2. **WebSearch checks (Step 2.4)** — Pattern/framework best-practice searches need only the PRD's architectural approach, not file:line references.
3. **Backlog cross-reference (Step 2.7)** — Reading `docs/backlog.md` is independent of everything.

### Parallelism Rules

1. **Within a phase:** Launch all items simultaneously via multiple Agent/Bash/Read calls in a single message.
2. **Between phases:** Wait for ALL items in the prior phase before starting the next.
3. **User interaction (AskUserQuestion) is blocking** — Step 3 decisions are inherently sequential (one question at a time). Do not attempt to parallelize user prompts.
4. **Artifact writes are parallel** — Step 5a (feature design doc) and Step 5b (API contract) read from the same inputs (design decisions, explorer report) and can be written simultaneously.
5. **Review is sequential** — Steps 9-10 depend on Step 8 approval. No shortcuts.

### Intermediate Files (Context Preservation)

Planning runs are long. Subagent reports vanish when the agent returns. Conversation context compresses. To prevent data loss between phases, **write intermediate outputs to disk** so later phases can re-read them instead of relying on conversation memory.

**Working directory:** `docs/.eng-planning/` (dot-prefixed = working files, not final artifacts)

| Phase | File | Written By | Consumed By |
|-------|------|-----------|-------------|
| A | `docs/.eng-planning/prd-summary.md` | Step 0 (main agent extracts key facts from PRD) | Steps 2, 3, 5a, 5b (main agent uses THIS, not the full PRD) |
| B | `docs/.eng-planning/explorer-report.md` | Step 1 (orchestrator, from subagent output) | Steps 2, 3, 5a, 5b |
| B | `docs/.eng-planning/explorer-report-fe.md` | Step 1 (FE explorer, multi-repo only) | Merged into explorer-report.md |
| B | `docs/.eng-planning/explorer-report-be.md` | Step 1 (BE explorer, multi-repo only) | Merged into explorer-report.md |
| B | `docs/.eng-planning/dependency-verification.md` | Step 4 | Steps 5a, 8 |
| B | `docs/.eng-planning/websearch-findings.md` | Step 2.4 | Step 2 (full), Step 5a |
| B | `docs/.eng-planning/backlog-crossref.md` | Step 2.7 | Step 2 (full) |
| C | `docs/.eng-planning/scope-challenge.md` | Step 2 (full synthesis) | Step 3, Step 5a |
| C | `docs/.eng-planning/design-decisions.md` | Step 3 (accumulated after each user answer) | Steps 5a, 5b |
| F | `docs/.eng-planning/review-findings.md` | Step 9 (from reviewer subagent output) | Step 10 |
| All | `docs/.eng-planning/progress.json` | Steps -1 through 11 (checkpoint after each major step) | Step -1 (resume detection) |

**Rules:**
1. **Write immediately after each phase completes.** When a subagent returns a report, write it to disk in the same message before proceeding.
2. **Re-read from disk at phase boundaries.** At the start of Phase C, read `explorer-report.md` + `websearch-findings.md` + `backlog-crossref.md` from disk — do not rely on conversation memory of the subagent output.
3. **Append, don't overwrite** for `design-decisions.md` — each user answer adds to the file.
4. **Partial cleanup at Step 5c, full cleanup at Step 11.** Step 5c deletes intermediate content files (explorer reports, websearch findings, etc.) but preserves `progress.json` (needed for session resume) and `review-findings.md` (needed for Step 10). Step 11 deletes the entire `docs/.eng-planning/` directory as final cleanup.
5. **If a step needs data from a prior phase:** Read it from the intermediate file, not from conversation context. This is the whole point — conversation context may have been compressed.
6. **Context budget: the main agent should NEVER hold the full PRD and full explorer report simultaneously.** After Step 0, the main agent works from `prd-summary.md` (not the full PRD). The full PRD is passed to subagents via their prompts — subagents hold the heavy documents, the main agent holds summaries. Do NOT re-read the full PRD in later steps.
7. **Do NOT read individual codebase files after Step 1.** The explorer report IS the codebase summary. If you need file:line details, they are in the explorer report. Reading source files directly in Steps 2-11 defeats the purpose of the explorer subagent.

---

## Step -1: Resume Detection

Before starting any work, check if a prior planning session left state on disk.

1. **Check for progress file** — `Glob: docs/.eng-planning/progress.json`
2. **If found:** Read the file. It contains:
   ```json
   {
     "prd_path": "docs/prd/features/FEAT-XXX.md",
     "last_completed_step": 3,
     "remaining_steps": [5, 6, 7, 8, 9, 10, 11],
     "artifacts_produced": [
       "docs/plans/FEAT-XXX-design.md",
       "docs/contracts/feature.md"
     ],
     "step_8_approved": false,
     "review_iteration": 0
   }
   ```
   - Report to the user: "Resuming eng-planning from Step [N]. Steps completed: [list]. Next step: [N]."
   - Re-read the PRD from `prd_path`.
   - Re-read any intermediate files that still exist in `docs/.eng-planning/` (they survive until Step 5c cleanup).
   - **After determining resume point, proceed to that step. Do NOT skip remaining steps.**

3. **If not found:** Start fresh from Step 0. Create the progress file after Step 0 completes (see checkpoint instructions below).

### Checkpoint Protocol

After each major step completion, write/update `docs/.eng-planning/progress.json` with the current state. The file is a simple JSON object — overwrite it each time. Fields:

| Field | Type | Description |
|-------|------|-------------|
| `prd_path` | string | Absolute or repo-relative path to the PRD |
| `last_completed_step` | number | The step number that just finished |
| `remaining_steps` | number[] | Steps still to execute |
| `artifacts_produced` | string[] | Paths to final artifacts written so far |
| `step_8_approved` | boolean | Whether Step 8 user approval was obtained |
| `review_iteration` | number | Current review iteration count (0, 1, or 2) |

**Checkpoint steps:** 1, 2, 3, 5, 6, 7, 8, 9, 10, 11. Step 0 creates the initial file. Step 4 runs in parallel with Step 1 so its completion is recorded when Step 1's checkpoint fires (or whichever Phase B step completes last).

## Step 0: Locate PRD

1. **Check argument** — If the user passed a path (e.g., `/eng-planning docs/prd/features/FEAT-001-search.md`), use that file.
2. **Search if no argument** — Look in `docs/prd/`, `docs/prd/features/`, `docs/plans/` for recent PRD files:
   ```
   Glob: docs/prd/**/*.md
   Glob: docs/plans/**/*.md
   ```
3. **Ambiguous?** — If multiple candidates or none found, use AskUserQuestion:
   > "I found [N] potential PRD files: [list]. Which one should I plan against? Or provide a path."
4. **Read the PRD** — Parse it completely. Extract: objectives, requirements (P0/P1/P2), constraints, user stories, success metrics, non-goals.
5. **Write PRD summary to disk** — Immediately write `docs/.eng-planning/prd-summary.md` containing: feature name, objectives (1-2 sentences each), all requirements grouped by priority, constraints, non-goals, new dependencies listed, and success metrics. This is a structured extraction, not a copy. **After this point, the main agent works from `prd-summary.md` — do NOT re-read the full PRD.** The full PRD text is only used when filling `[PRD_CONTENT]` in subagent prompt templates (Step 1 explorer, Step 9 reviewer). Store the PRD path for subagent use but do not hold the full PRD content in conversation context.

**→ Checkpoint:** Write `docs/.eng-planning/progress.json` with `last_completed_step: 0`, `prd_path` set, `remaining_steps: [1, 2, 3, 5, 6, 7, 8, 9, 10, 11]`, empty `artifacts_produced`, `step_8_approved: false`, `review_iteration: 0`.

## Step 1: Codebase Exploration

**Phase B — launch in parallel with Steps 4, 2.4, 2.7.**

Spawn explorer subagent(s) to map the codebase against PRD requirements.

1. **Read the template** — Read `~/.claude/skills/eng-planning/templates/explorer-prompt.md`
2. **Fill placeholders:**
   - `[PRD_CONTENT]` — Re-read the full PRD from the path stored in `progress.json`. Pass the full text into the subagent prompt. The subagent holds the heavy document, not you.
   - `[PROJECT_PATH]` — Absolute path to the project root (or sub-repo root for split explorers)
3. **Multi-repo projects:** If the project has separate FE/BE repos, spawn **one explorer per repo** in parallel (see "Multi-Repo Explorer Splitting" above). Scope each explorer's `[PROJECT_PATH]` to its sub-repo. Merge their reports after both complete.
4. **Spawn via Agent tool** — Use `subagent_type: "general-purpose"`. Each explorer runs in isolated context and returns a structured report.
5. **Wait for all explorer reports** — Do not proceed to Phase C until all explorers return. The reports contain: project structure, tech stack, existing patterns with file:line references, code mapped to PRD requirements, dependency map, test infrastructure, DB schema.
6. **Write to disk immediately.** For single-repo: write the report to `docs/.eng-planning/explorer-report.md`. For multi-repo: write each sub-report to `docs/.eng-planning/explorer-report-fe.md` and `docs/.eng-planning/explorer-report-be.md`, then merge into `docs/.eng-planning/explorer-report.md`.

**→ Checkpoint:** Update `progress.json` — `last_completed_step: 1`, remove `1` from `remaining_steps`. (Step 4 runs in parallel; if it finished first, this checkpoint captures both.)

## Step 2: Scope Challenge

**Split execution:** Questions 4 and 7 run in **Phase B** (parallel with exploration). Questions 1-3, 5-6 run in **Phase C** after the explorer report is available. The full synthesis happens in Phase C.

### Phase B (early, parallel with Step 1):

**2.4 — Search check:** For each architectural pattern, infrastructure component, or concurrency approach the plan might introduce:
   - Does the runtime/framework have a built-in? WebSearch: "{framework} {pattern} built-in"
   - Is the chosen approach current best practice? WebSearch: "{pattern} best practice {current year}"
   - Are there known footguns? WebSearch: "{framework} {pattern} pitfalls"
   If WebSearch is unavailable, note: "Search unavailable — proceeding with in-distribution knowledge only."
   **→ Write results to `docs/.eng-planning/websearch-findings.md`**

**2.7 — TODOS.md cross-reference:** Read `TODOS.md` / `docs/backlog.md` if they exist. Are any deferred items blocking this plan? Can any be bundled without expanding scope? Does this plan create new work to capture?
   **→ Write results to `docs/.eng-planning/backlog-crossref.md`**

### Phase C (after explorer report — read from `docs/.eng-planning/explorer-report.md`):

Before starting, re-read intermediate files from Phase B (do NOT re-read the full PRD — use `prd-summary.md`):
- `docs/.eng-planning/prd-summary.md`
- `docs/.eng-planning/explorer-report.md`
- `docs/.eng-planning/websearch-findings.md`
- `docs/.eng-planning/backlog-crossref.md`

Then answer the remaining questions:

1. **What existing code already solves each sub-problem?** For each PRD requirement, check the explorer report. Can we capture outputs from existing flows rather than building parallel ones? List reuse opportunities with file:line references.

2. **Minimum set of changes?** What is the smallest change set that achieves the stated goal? Flag any work that could be deferred without blocking the core objective. Be ruthless about scope creep.

3. **Complexity check:** If the plan will touch more than 8 files or introduce more than 2 new services/classes, treat that as a smell. Challenge whether the same goal can be achieved with fewer moving parts. If triggered: use AskUserQuestion to propose scope reduction before proceeding.

5. **Completeness check (lake vs ocean):** Is the plan doing the complete version or a shortcut? With AI-assisted coding, the cost of completeness (100% test coverage, full edge case handling, complete error paths) is 10-100x cheaper than with a human team. If a shortcut saves human-hours but only saves minutes with CC, recommend the complete version. Boil the lake, flag the ocean.

6. **Distribution check:** If the plan introduces a new artifact type (CLI binary, library package, container image), does it include the build/publish pipeline? Code without distribution is code nobody can use. Check: CI/CD workflow, target platforms, installation method. If deferred, flag explicitly.

**→ Write full scope challenge synthesis to `docs/.eng-planning/scope-challenge.md`**

**If complexity check triggers (8+ files or 2+ new services):** Use AskUserQuestion to propose scope reduction. Explain what is overbuilt, propose a minimal version, ask whether to reduce or proceed as-is. Wait for answer before continuing.

**→ Checkpoint:** Update `progress.json` — `last_completed_step: 2`, remove `2` from `remaining_steps`.

## Step 3: Major Design Decisions

Re-read `docs/.eng-planning/scope-challenge.md` and `docs/.eng-planning/explorer-report.md` from disk. Use these intermediates (not the full PRD) to identify every significant design decision. Categories:

- **Architecture approach** — monolith vs service, sync vs async, polling vs push
- **Data model** — schema design, relationships, migration strategy
- **Tech selection** — libraries, frameworks, tools (subject to R17 verification)
- **Integration pattern** — API style, event format, auth mechanism
- **Performance tradeoffs** — caching strategy, batch size, pagination approach

For each decision:
1. **Formulate the question** with enough context that someone unfamiliar can understand
2. **Present 2-3 options** with concrete tradeoffs (not vague pros/cons — specific costs in lines of code, latency, complexity)
3. **State your recommendation** with reasoning

**Present ALL decisions upfront via AskUserQuestion, one at a time.** Do not batch. Wait for each answer before asking the next. Record every decision with its rationale.

**→ After each decision, append to `docs/.eng-planning/design-decisions.md`.** This file accumulates all decisions so Phase D can read them from disk rather than relying on conversation context.

**→ Checkpoint (after all decisions recorded):** Update `progress.json` — `last_completed_step: 3`, remove `3` from `remaining_steps`.

Example format:
> **Design Decision 3/7: Data Storage Pattern**
>
> The PRD requires storing user preferences that are read frequently and written rarely.
>
> A) PostgreSQL JSONB column on users table — zero new infrastructure, queryable, 1 migration file. Downside: JSONB queries are slower than typed columns at scale.
> B) Dedicated preferences table with typed columns — explicit schema, better query performance. Downside: 2 new files (model + migration), schema changes need migrations.
> C) Redis cache with Postgres fallback — fastest reads. Downside: new infrastructure dependency, cache invalidation complexity, 4+ new files.
>
> RECOMMENDATION: Choose B — typed columns give you explicit schema validation and the query performance difference matters when preferences are loaded on every page view. The 2 extra files are trivial cost.

## Step 4: Dependency Verification (R17)

**Phase B — launch in parallel with Steps 1, 2.4, 2.7.** Dependencies are listed in the PRD; no need to wait for design decisions.

For every NEW external dependency identified in the PRD:

1. **Record the dependency** — exact package name, purpose, why it is needed
2. **Verify it is installable:**
   - Python: `pip install --dry-run <package>>=<version>`
   - Node: `npm info <package> version`
   - Go: `go list -m <module>@<version>`
   - .NET: `dotnet list package --include-transitive | grep <package>` or check NuGet
3. **Record evidence** — name, URL (PyPI/npm/NuGet/GitHub), minimum version, verification result
4. **If any dependency FAILS verification:** STOP immediately. Use AskUserQuestion:
   > "Dependency `<package>` cannot be verified as installable. [error details]. Cannot proceed to BUILD with unverified dependencies (R17). Options: A) Find alternative, B) Remove requirement, C) Escalate to user for manual verification."

**→ Write results to `docs/.eng-planning/dependency-verification.md`**

**Format for recording (used in design docs):**
```
- `package-name>=X.Y.Z` — [PyPI](https://pypi.org/project/package-name/) — Purpose: [why needed] — Verified: YES/NO
```

At `light` VIBE level: warn on verification failure but do not block. Note: "Best-effort verification — manual check recommended before BUILD."

## Step 5: Produce Artifacts

Generate all design artifacts autonomously. All files go under `docs/`.

**Output: TWO files per feature.** Architecture, design decisions, and task specs are consolidated into a single feature design doc. Only the API contract is separate (because FE and BE teams reference it independently).

### 5a. Feature Design Doc — `docs/plans/FEAT-XXX-design.md`

**This is the primary artifact.** One file per feature containing architecture, design decisions, and task mini-specs. Must include spec-registry frontmatter and ALL of the following sections:

```markdown
---
domain: <feature-domain>
skills: [<relevant-skills>]
schemas: [<relevant-schema-paths>]
---

# FEAT-XXX: [Feature Title]

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

[... repeat for each decision from Step 3 ...]

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
**Depends On:** - (none) | T-XXX, T-YYY
**Objective:** [single sentence]
**Requirements:**
- [specific bullets]
**Build Guidance:**
- Use existing `ClassName` pattern from `src/path/`
- [SPECIFIC patterns, classes, utilities — NOT generic principles]
**Acceptance Criteria:**
- [ ] [criterion]
**Edge Cases:**
- [edge case and expected behavior]
**Test Plan:**
- Unit: [what to test]
- Integration: [what to test]

---

### T-XXX: [Next Task]
[... same template ...]

## Task Dependencies Graph
```
T-101 (no deps)
    +-- T-102 (depends on T-101)
    +-- T-103 (depends on T-101)
T-104 (no deps, parallel with T-101)
```

## Definition of Done
- [ ] All T-XXX tasks pass 2 QA cycles each
- [ ] All tests pass (`make test`)
- [ ] Lint passes (`make lint`)
- [ ] User approval gate for merge
```

**Mini-Spec Rules (non-negotiable):** Every T-XXX MUST have ALL fields: Priority, Depends On, Objective, Requirements, Build Guidance, Acceptance Criteria, Edge Cases, Test Plan. Build Guidance must be SPECIFIC — name the exact patterns, classes, and utilities from the codebase to use. NOT generic principles like "keep it DRY" or "follow SOLID". Depends On is authoritative — the orchestrator uses it to determine execution order and parallelism.

### 5b. API Contracts — `docs/contracts/<feature>.md`

**Separate file** because FE and BE teams reference it independently. Per R16: one contract per feature with cross-boundary data flow. Must include:
- Spec-registry frontmatter (at `full` level)
- REST endpoint signatures (method, path, request body, response body, status codes)
- Data models with exact field names, types, and constraints
- SSE event schemas (if applicable) — event name, data shape, field types
- Error response shapes — consistent error format with codes
- Shared enums/types referenced by both FE and BE

Include frontmatter:
```yaml
---
domain: <feature-domain>
skills: [<relevant-skills>]
schemas: [<relevant-schema-paths>]
---
```

### 5c. Cleanup Intermediate Content Files

All intermediate CONTENT files have been consumed and their content is now in the final artifacts. Delete them, but **preserve `progress.json`** (needed for resume across sessions) and `review-findings.md` (needed for Step 10):

```bash
rm -f docs/.eng-planning/explorer-report.md
rm -f docs/.eng-planning/explorer-report-fe.md
rm -f docs/.eng-planning/explorer-report-be.md
rm -f docs/.eng-planning/dependency-verification.md
rm -f docs/.eng-planning/websearch-findings.md
rm -f docs/.eng-planning/backlog-crossref.md
rm -f docs/.eng-planning/scope-challenge.md
rm -f docs/.eng-planning/design-decisions.md
```

Do this NOW, before proceeding to Step 6. The review subagent (Step 9) reads from the final artifacts in `docs/plans/` and `docs/contracts/`, not from intermediates. `progress.json` and `review-findings.md` are NOT intermediates — they are infrastructure files needed by later steps.

**→ Checkpoint:** Update `progress.json` — `last_completed_step: 5`, remove `5` from `remaining_steps`, populate `artifacts_produced` with the paths of all artifacts written in 5a and 5b.

## Step 6: Codepath Coverage Diagram

For each FEAT design doc, produce an ASCII diagram showing planned codepaths and where tests should exist. Append to the FEAT design doc.

### Codepath Diagram Format
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

### Failure Modes Analysis

For each new codepath, append a failure modes section:

```markdown
## Failure Modes

| Codepath | Realistic Failure | Tests Cover It? | Error Handling Exists? | Silent? |
|----------|-------------------|-----------------|----------------------|---------|
| create_item() | DB connection timeout during write | Yes (integration) | Yes (retry + 503) | No |
| get_items() | Malformed pagination params | No — ADD TEST | Yes (400 response) | No |
| POST /api/items | Request body exceeds size limit | No — ADD TEST | No — ADD HANDLER | Yes! |
```

Flag any "Silent? Yes" entries as P0 — silent failures in production are unacceptable.

**→ Checkpoint:** Update `progress.json` — `last_completed_step: 6`, remove `6` from `remaining_steps`.

## Step 7: Worktree Parallelization Strategy

**Skip this step if fewer than 2 independent workstreams.**

Append to the feature design doc:

### Dependency Table
| Task | Depends On | Modifies Files | Parallel Lane |
|------|-----------|----------------|---------------|
| T-101 | - | schema.py, migration | Lane A |
| T-102 | T-101 | routes.py, service.py | Lane A |
| T-103 | - | components/*.tsx | Lane B |
| T-104 | T-101 | tests/*.py | Lane A |

### Parallel Lanes
```
Lane A (Backend):  T-101 --> T-102 --> T-104
Lane B (Frontend): T-103 (independent)
```

### Execution Order
1. Batch 1: T-101, T-103 (parallel — no shared files)
2. Batch 2: T-102 (depends on T-101)
3. Batch 3: T-104 (depends on T-101)

### Conflict Flags
- T-102 and T-104 both depend on T-101 but modify different files — safe to parallelize after T-101 completes
- [Flag any file overlap between tasks in same batch]

**→ Checkpoint:** Update `progress.json` — `last_completed_step: 7`, remove `7` from `remaining_steps`.

---

### MANDATORY CHECKPOINT — YOU ARE NOT DONE

**STOP HERE and read this.** Steps 8-11 (Phase F: Review Gate) are MANDATORY. You have produced artifacts in Steps 5-7 — you have NOT reviewed them. The review chain (present artifacts -> engineering review -> auto-fix -> final output) is non-negotiable. Do not declare victory. Do not report completion. Do not summarize what you did and stop. You MUST proceed to Step 8 now.

---

## Step 8: Present Written Artifacts for Approval

Artifacts were already written to disk in Step 5. Present what was written and get approval to proceed to engineering review.

1. **Artifacts written:**
   - `docs/plans/FEAT-XXX-design.md` — [1-line summary: architecture + N decisions + N tasks]
   - `docs/contracts/<feature>.md` — [1-line summary: N endpoints, N data models]

2. **Task count:** [N total tasks across all features]

3. **New questions** that emerged during planning (if any) — surface via AskUserQuestion

4. **Ask:** "Approve to proceed to engineering review? If you want changes to the artifacts, describe them and I will edit before proceeding."

5. **If rejected:** Edit the artifacts based on user feedback, then re-present. Loop until approved.

6. **If approved:** Proceed to Step 9.

**→ Checkpoint:** Update `progress.json` — `last_completed_step: 8`, remove `8` from `remaining_steps`, set `step_8_approved: true`.

## Step 9: Spawn Engineering Review

After approval and artifact creation, spawn a fresh review subagent.

1. **Read the template** — Read `~/.claude/skills/eng-planning/templates/review-prompt.md`
2. **Fill placeholders:**
   - `[ARTIFACT_PATHS]` — List of all artifact file paths produced in Step 5
   - `[PRD_PATH]` — Path to the approved PRD
   - `[PROJECT_PATH]` — Absolute path to the project root
3. **Spawn via Agent tool** — Use `subagent_type: "general-purpose"`. The reviewer runs in isolated context (sees ONLY the artifacts, not the planning conversation). This ensures genuine independence.
4. **Wait for review output** — The reviewer produces findings in severity/confidence format.
5. **→ Write review findings to `docs/.eng-planning/review-findings.md`** so Step 10 can read them from disk.

**→ Checkpoint:** Update `progress.json` — `last_completed_step: 9`, remove `9` from `remaining_steps`.

## Step 10: Auto-Fix Loop (max 2 iterations)

Parse the review findings. Categorize each:

- **SPECIFIABLE** — Can be fixed by editing an artifact (typo in contract, missing edge case in test plan, incomplete dependency record). Fix autonomously.
- **REQUIRES_DECISION** — Involves a design choice the user must make (different architecture approach, scope change, new dependency). Surface via AskUserQuestion.

After applying SPECIFIABLE fixes, re-spawn the review (Step 9) to verify fixes. **Maximum 2 total review iterations.** If issues persist after 2 iterations, report remaining findings to user and proceed.

Iteration tracking:
```
Review iteration 1: [N findings] — [X specifiable, Y decision-required]
  Fixed: [list of specifiable fixes]
  Escalated: [list of decision-required items]
Review iteration 2: [N findings] — [all specifiable? then done]
```

If iteration 2 still has specifiable findings: log them as known issues in the design doc and proceed.

**→ Checkpoint:** Update `progress.json` — `last_completed_step: 10`, remove `10` from `remaining_steps`, set `review_iteration` to the final iteration count.

## Step 11: Final Output

Confirm all artifacts have been written to disk. **Final cleanup** — delete the entire `docs/.eng-planning/` directory (progress.json, review-findings.md, and any stragglers from Step 5c):

```bash
rm -rf docs/.eng-planning/
```

The final artifacts in `docs/plans/` and `docs/contracts/` are the permanent record. The progress file has served its purpose and is deleted with the directory.

Report completion status:

- **DONE** — All artifacts produced, review passed, no outstanding concerns.
- **DONE_WITH_CONCERNS** — All artifacts produced, but concerns remain. List each concern explicitly.
- **BLOCKED** — Cannot complete. State what is blocking (unverified dependency, unresolved design decision, missing PRD information).

Final output format:
```
STATUS: DONE | DONE_WITH_CONCERNS | BLOCKED

ARTIFACTS PRODUCED:
- docs/plans/FEAT-XXX-design.md — [architecture + N decisions + N tasks]
- docs/contracts/<feature>.md — [N endpoints, N data models]

INTERMEDIATE FILES: Cleaned up (docs/.eng-planning/ removed)

REVIEW: [Passed after N iterations | Concerns listed below]

NEXT STEPS:
- Update .claude/phase.json to FEATURE_SPECS_APPROVED
- Orchestrator can begin spawning coder subagents for T-XXX tasks
```

## Spec-Registry Frontmatter

Every spec produced at `full` VIBE level must include frontmatter:

```yaml
---
domain: <feature-domain>
skills: [<relevant-skills>]
schemas: [<relevant-schema-paths>]
---
```

This enables the orchestrator (Step 0: Spec Context Injection) to automatically find and inject relevant specs into subagent prompts. Without this frontmatter, coders may miss context.

At `light` VIBE level: frontmatter is recommended but not required.

## Red Flags — STOP Immediately

If you catch yourself:
- Opening Edit/Write on .py/.ts/.js files → STOP, you are the planner
- Writing implementation code in any language → STOP
- Producing a mini-spec without Build Guidance → STOP, add specific guidance
- Writing generic Build Guidance ("follow SOLID", "keep it DRY") → STOP, name specific files/classes/patterns
- Skipping dependency verification at `full` level → STOP, verify first
- Proceeding after dependency verification failure → STOP, escalate
- Making design decisions without presenting options → STOP, ask user
- Writing artifacts outside docs/ → STOP, wrong location
- Producing a FEAT design doc without all required sections → STOP, complete it
- Running implementation tests or modifying test files → STOP, that is coder work

**All of these mean: You have confused your role. Return to planning.**

## Escalation

If at any point:
- A PRD requirement is ambiguous and cannot be resolved by re-reading → AskUserQuestion
- Dependency verification fails and no alternative exists → STOP and report BLOCKED
- The complexity check suggests fundamental redesign → present findings, wait for user
- Explorer report reveals the codebase cannot support the PRD requirements → escalate immediately

Do not guess. Do not assume. Ask.
