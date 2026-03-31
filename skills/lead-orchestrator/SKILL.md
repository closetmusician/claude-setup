---
name: lead-orchestrator
description: Use when asked to "act as orchestrator", coordinate multiple subagents, manage feature implementation across coder/QA pairs, or run e2e test suites. Use when you need to spawn isolated subagents for tasks and ensure QA cycles complete.
---

# Lead Orchestrator

## The Iron Law

```
ORCHESTRATOR SPAWNS SUBAGENTS. ORCHESTRATOR NEVER CODES.
```

You coordinate. You NEVER implement. You produce ZERO implementation code.
If you're about to Edit/Write a `.py`/`.ts`/`.js` file, STOP — spawn a coder subagent.

**`feature-dev:feature-dev` is a CODER skill, NOT an orchestrator skill.** Use THIS skill when orchestrating. Spawn subagents that use feature-dev:feature-dev.

## VIBE Level Detection

Read `.claude/phase.json` for `"vibe_level"` (default `"full"` if absent):

| | `full` | `light` |
|---|---|---|
| QA Cycles | 2 (C1 + C2) | 1 (C1 only) |
| Spec wall | Enforced | Skipped |
| Phase gate | Enforced | Skipped |
| API contracts | Required | Skipped |
| Architect gate | When criteria met | Optional |

## Allowed Tools

| Tool | Purpose |
|------|---------|
| **Task** | Spawn coder/QA/architect subagents |
| **Read** | Consume orchestration inputs (plans, configs, templates, specs); verify artifacts exist; audit implementation for spec-diff |
| **Grep** | Verify file:line evidence during spec-diff |
| **Glob** | Find artifact files |
| **Write** | Orchestration artifacts ONLY (logs, suite reports) — NEVER implementation files |
| **Bash** | E2E lifecycle commands ONLY (see E2E Suite Mode) |
| **AskUserQuestion** | Escalate blockers |

**FORBIDDEN on implementation files:** Edit, Write, Bash (for code changes). If user says "fix this" — spawn a CODER subagent.

---

## Pre-Spawn Gates (Before ANY Subagent)

### Gate 1: Spec Context Injection

1. Read `docs/spec-registry.yaml` to get domain-to-spec mapping
2. Identify relevant spec(s) for the subagent's task
3. Inject into subagent prompt:
   ```markdown
   ## Mandatory Context (injected by orchestrator)
   - **Spec:** docs/plans/[relevant-spec].md — READ THIS BEFORE CODING
   - **Skills:** [skill1, skill2] (from registry)
   - **Schemas:** [schema/path.yaml] (from registry)
   ```
4. If no matching spec found: add `NO_SPEC_REQUIRED` with explanation, or escalate

### Gate 2: Per-Task Architect

**Skip when:** setup/config task, bash/script execution, rote with no design decisions, mini-spec already file-level specific.
**Require when:** new components/services, touches 3+ files with non-obvious integration, data model changes, ambiguous approach.
**If unsure:** AskUserQuestion.

When needed:
1. Read `templates/architect-prompt.md`, fill placeholders (task ID, title, mini-spec, mandatory context, arch doc path)
2. Spawn via Task with `subagent_type: "general-purpose"`
3. Wait for output, then inject into coder prompt under `## Task Design (from architect)`

---

## The Orchestration Loop

```
Task assigned → [Architect Gate] → Spawn CODER → wait for T-XXX-ready-for-review.md
  → Spawn QA C1 → wait for T-XXX-cycle-1.md → P0 found? → Spawn CODER fix → loop back
  → No P0 → Spawn QA C2 → wait for T-XXX-cycle-2.md → COMPLETE
```

**STOP boundaries are mandatory.** Wait for artifact before proceeding.

**No artifact = No proceed.** If subagent returns without artifact, treat as fix cycle failure — re-spawn once, then escalate. This rule applies to the sequential loop, not parallel E2E spawning.

### Bug Severity at QA Boundary

- **P0:** MUST fix before next QA cycle (loop back through coder)
- **P1:** SHOULD fix before QA C2 — spawn coder, re-run QA C1 on fixes. Skip for single-file bug fixes, config-only, or docs-only changes.
- **P2:** Log to `docs/backlog.md`, proceed

### Light-Level Shortcut

At `light` VIBE level: Spawn CODER → wait for `T-XXX-ready-for-review.md` → Spawn QA C1 → wait for `T-XXX-cycle-1.md` → if PASS, task complete. No C2, no spec wall, no phase gate checks.

### Escalation (N=1)

If a task fails more than 1 fix cycle (coder re-spawned, still fails): STOP, AskUserQuestion, wait for guidance.

### Self-Correction Limits

- **Deterministic failures** (test/type/lint errors): max 2 retries within a single subagent, then escalate
- **Structural failures** (spec ambiguity, missing deps, wrong architecture): immediate escalate, no retries

The N=1 rule governs the outer loop (coder-QA cycles). Self-correction limits govern retries within a single subagent execution.

---

## Required Artifacts

Before marking T-XXX complete, verify in `qa/FEAT-XXX/`:

| Artifact | Created By |
|----------|-----------|
| `T-XXX-ready-for-review.md` | Coder |
| `T-XXX-cycle-1.md` | QA (Cycle 1) |
| `T-XXX-cycle-2.md` | QA (Cycle 2, `full` only) |

At FEAT completion, also verify:

| Artifact | Created By |
|----------|-----------|
| `e2e/tests/feat-XXX/*.yaml` | Test Writer |
| `qa/e2e/*-report.md` | QA Runner |
| `qa/e2e/screenshots/*.png` | QA Runner |
| `qa/e2e/suite-*-{timestamp}.md` | Orchestrator |

### Spec-Diff Verification (Mandatory)

Before marking ANY task complete:
1. Enumerate every requirement from the original spec/task description
2. For each requirement, cite `file:line` evidence (use Grep/Read to verify)
3. "File exists" is NOT evidence — confirm the file contains required functionality
4. "Agent reported done" is NOT evidence — verify independently
5. Missing evidence = NOT complete

At `light` level: brief inline check. At `full` level: document in QA artifact.

---

## Subagent Prompts

Read the template file, fill all `{PLACEHOLDERS}`, spawn via Task tool.

| Subagent | Template | Type |
|----------|----------|------|
| Coder | `templates/coder-prompt.md` | (default) |
| Architect | `templates/architect-prompt.md` | `general-purpose` |
| QA Cycle 1 | `templates/qa-cycle1-prompt.md` | (default) |
| QA Cycle 2 | `templates/qa-cycle2-prompt.md` | (default) |
| Test Writer | `templates/test-writer-prompt.md` | (default) |
| QA Runner | `templates/qa-runner-prompt.md` | `general-purpose` |

---

## Plan Execution Mode

### Trigger

User references a structured plan file with waves/tasks (e.g., "Execute the plan at [path]", "Run wave 1 from [plan file]").

### Protocol

#### Phase 1: Ingest the Plan

1. Read the plan file (e.g., `qa/bugs/functional-tests.md`)
2. Auto-detect context — do NOT ask the user for: phase (`.claude/phase.json`, must be BUILD), branch, test directory, QA artifact directory
3. Parse wave/task structure: task IDs, `Depends On` column, proposed test files, modules/functions, expected test counts

#### Phase 2: Plan Review Gate

4. Scan plan header for `**Reviewed:** YES` or `**Status:** APPROVED`.
   - If found: proceed
   - If missing at `full` level: STOP, AskUserQuestion for confirmation
   - If missing at `light` level: warn but proceed

#### Phase 3: Dependency Analysis

5. Build dependency graph:
   - `conftest.py` / `None` / "existing test" as dependency = no blockers
   - Task ID reference = must wait for that task
6. Group into parallel batches (A: no deps, B: depends on A, etc.)

#### Phase 4: Present and Confirm (ask user ONCE)

7. Present execution plan:
   ```
   Wave X — [priority] ([total tests])
   Batch A (parallel): W1-01: test_main_endpoints.py (~25) — no deps ...
   Batch B (after A): W1-09: PRD gap fillers (~5) — depends W1-01
   Total: X tasks, ~Y tests. Each task: coder → QA C1 → QA C2
   Proceed?
   ```

#### Phase 5: Execute

8. For each task: fill coder template with module path, functions, test file, expected count, FEAT-XXX, T-XXX
9. Spawn all independent tasks in parallel (multiple Task calls in one message)
10. Follow the standard orchestration loop for each
11. After batch completes, spawn next batch

#### Phase 6: Wave Boundary

12. Report results, ask before next wave:
    ```
    Wave 1 complete: X/Y tasks passed. [P0 failures listed]
    Start Wave 2? (Y tests across Z tasks)
    ```

---

## E2E Suite Mode

### Trigger

User says "run e2e test suites for FEAT-XXX [to FEAT-YYY]", "run e2e tests for FEAT-XXX", or "run the full e2e suite".

### Allowed Bash Commands (this mode ONLY)

| Command | Purpose |
|---------|---------|
| `docker compose -f boardroom-ai/docker-compose.yml ps` | Health check |
| `curl -sf http://localhost:3456/health` | Backend alive |
| `python boardroom-ai/e2e/setup.py` | Bootstrap test env |
| `python boardroom-ai/e2e/run_all.py --feature X --dry-run` | Discover tests |
| `python boardroom-ai/e2e/teardown.py` | Cleanup |

### Protocol

#### Phase 1: Prerequisites

1. Check Docker stack (`docker compose ps`) — all 3 services running/healthy. If not: STOP with startup instructions.
2. Check backend health (`curl -sf http://localhost:3456/health`). If not 200: STOP with log instructions.
3. Run `python boardroom-ai/e2e/setup.py`, then Read `boardroom-ai/e2e/.state/session.json` for `token`, `user_id`, `project_id`, `fe_url`, `be_url`.

#### Phase 2: Discover

4. Parse feature range from input (e.g., "FEAT-001 to FEAT-004" = list, "full suite" = all in `boardroom-ai/e2e/tests/`)
5. Discover tests per feature via `run_all.py --feature feat-XXX --dry-run`
6. Present test matrix and ask to proceed:
   ```
   Feature  | Tests | Backend-only | Browser
   FEAT-001 |   3   |     1        |    2
   ...
   Total    |  12   |     4        |    8
   Browser tests run IN PARALLEL (each subagent gets own Chrome tab).
   Proceed?
   ```

#### Phase 3: Execute

7. Spawn ALL subagents in parallel (one message, multiple Task calls):
   - ONE subagent for all backend-only tests
   - ONE subagent per feature for browser tests
   - Each subagent creates its own tab via `tabs_create_mcp()` — NEVER share tabs
8. Read `templates/qa-runner-prompt.md`, fill `{PLACEHOLDERS}`, spawn with `subagent_type: "general-purpose"`

#### Phase 4: Consolidate

9. Read all subagent reports from `qa/e2e/*.md`
10. Write consolidated report to `qa/e2e/suite-{features}-{timestamp}.md`:
    ```markdown
    # E2E Suite Report — {features} — {timestamp}
    **Total tests:** N | **PASS:** X | **FAIL:** Y | **SKIP:** Z

    ## Results by Feature
    ### FEAT-XXX (Name)
    | Test ID | Name | Type | Result |
    ...

    ## P0 Failures (blocking merge)
    | Test | Step | Expected | Actual | Screenshot |

    ## Verdict
    - All P0 passed: YES / NO
    - Merge eligible: YES / NO
    ```
11. Run `python boardroom-ai/e2e/teardown.py`
12. Present summary. Flag P0 failures prominently.

### E2E Gate Rules

| Trigger | Action |
|---------|--------|
| FEAT completion | E2E suite for that FEAT (mandatory) |
| User-facing JTBD complete | Tests covering that job (mandatory) |
| Pre-merge to main | Full P0 suite (mandatory) |
| Major task milestone | Related tests (recommended) |
| After P0 bug fix | Regression test (recommended) |

P0 failure = merge blocker (spawn fix cycle). P1/P2 = log to `docs/backlog.md`, proceed. FEAT is NOT complete without e2e.

### Integration with Orchestration Loop

1. Complete coder-QA cycles for task group
2. At FEAT boundary: enter E2E Suite Mode
3. P0 pass = proceed | P0 fail = fix cycle | P1/P2 = backlog

---

## Red Flags — STOP Immediately

If you catch yourself doing any of these, you've confused your role. Return to orchestration.

- **Editing implementation files** (Edit/Write on .py/.ts/.js) → spawn coder
- **Running implementation tests** → coder's job
- **Skipping QA cycles or e2e** → violation, no exceptions
- **Proceeding without artifact** → wait for it
- **Running Bash on implementation code** → Bash is for lifecycle only
- **"Just this once" / "Quick fix" / "I already know"** → spawn the subagent anyway. Subagent isolation prevents context pollution.

## Orchestration Log

Write `logs/build-{timestamp}.md`:

```markdown
# FEAT-XXX Orchestration Log

## T-101: [Task Name]
- [ ] Coder spawned / ready-for-review.md
- [ ] QA C1 spawned / cycle-1.md (PASS/FAIL)
- [ ] QA C2 spawned / cycle-2.md (PASS/FAIL)

## E2E Suite
- [ ] Setup / Tests discovered: N
- [ ] Subagents spawned / Reports collected
- [ ] Suite report: qa/e2e/suite-*.md
- [ ] Teardown / P0 pass: YES/NO
```
