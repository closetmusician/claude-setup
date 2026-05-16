---
name: lead-orchestrator
description: Use when asked to "act as orchestrator", coordinate multiple subagents, or manage feature implementation across coder/QA pairs. Use when you need to spawn isolated subagents for tasks and ensure QA cycles complete.
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
| QA Cycles | 2 (C1: test + break, C2: re-test bugs) | 1 (C1 only) |
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

## Governance Activation

Before spawning any subagent, activate governance enforcement:

```bash
touch ~/.claude/scripts/governance/state/.active
```

This enables the pre-agent-gate (validates prompt structure), post-agent-audit (checks evidence coverage), and role-enforcement (blocks orchestrator writes) hooks. Without this file, all governance hooks are no-op.

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
4. If no matching spec found: create a lightweight doc in `docs/` or use an existing `docs/*.md` file. `NO_SPEC_REQUIRED` alone will fail the pre-agent-gate — always include a `docs/*.md` reference.
5. Fill governance sections from template: each template in `templates/` includes `## Requirement Map` and `## Constraints` placeholders. Fill `{REQUIREMENT_MAP_JSON}` with a valid requirement map (task_id + requirements array with req_id/what/done_when/escalate_if/source per item). Fill `{ESCALATION_CONDITIONS}` with task-specific escalation triggers. Do NOT omit these sections — the pre-agent-gate hook will block the spawn.

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
1.  Task assigned → [Architect Gate]
2.  Spawn CODER → wait for T-XXX-ready-for-review.md
2a. touch $STATE/.gate-pre-qa                     ← SENTINEL ON
3.  Pre-QA Gates (TDD evidence, test suite, commit ordering)
3a. validate-artifact.sh qa/FEAT-XXX/T-XXX-ready-for-review.md
3b. rm $STATE/.gate-pre-qa                        ← SENTINEL OFF
4.  Spawn GARRY-REVIEW → wait for review findings
4a. validate-artifact.sh qa/FEAT-XXX/T-XXX-review-findings.md
5.  If P0/P1 findings → Spawn CODER fix → wait for updated artifact
6.  touch $STATE/.gate-qa-c1                      ← SENTINEL ON
6a. Spawn QA TESTER C1 (test + break) → wait for T-XXX-cycle-1.md
6b. validate-artifact.sh qa/FEAT-XXX/T-XXX-cycle-1.md
6c. rm $STATE/.gate-qa-c1                         ← SENTINEL OFF
7.  If FAIL → Spawn CODER fix → re-run C1 → if still FAIL: ESCALATE (N=1)
8.  Spawn QA TESTER C2 (regression + edge cases, full only) → wait for T-XXX-cycle-2.md
8a. validate-artifact.sh qa/FEAT-XXX/T-XXX-cycle-2.md
9.  touch $STATE/.gate-spec-diff                  ← SENTINEL ON
9a. Spec-diff verification (cite file:line evidence per requirement)
9b. rm $STATE/.gate-spec-diff                     ← SENTINEL OFF
10. COMPLETE
```

Where `$STATE` = `~/.claude/scripts/governance/state`

**STOP boundaries are mandatory.** Wait for artifact before proceeding.

**No artifact = No proceed.** If subagent returns without artifact, treat as fix cycle failure — re-spawn once, then escalate. This rule applies to the sequential loop, not parallel E2E spawning.

### Pre-QA Gates

**Sentinel activation** (immediately after coder returns artifact):
```bash
touch ~/.claude/scripts/governance/state/.gate-pre-qa
```

The `orchestrator-step-gate.sh` hook will BLOCK any QA or review subagent spawns while this sentinel exists. You MUST complete all steps below to clear it.

Before spawning Garry-Review or QA Tester, the orchestrator MUST:
1. Read `qa/FEAT-XXX/T-XXX-ready-for-review.md`
2. Run structural validation:
   ```bash
   ~/.claude/skills/lead-orchestrator/scripts/validate-artifact.sh qa/FEAT-XXX/T-XXX-ready-for-review.md
   ```
   If FAIL: re-spawn coder with the specific deviations listed.
3. Verify `## TDD Evidence` table exists with at least one data row, OR every behavior has a `TDD-EXEMPT` declaration with justification
4. If missing: re-spawn coder with instruction "TDD Evidence table is missing — add RED/GREEN evidence for each behavior before resubmitting"
5. Run `make test` (or project equivalent — check Makefile, package.json, pytest, go test in that order). If exit code != 0, do NOT spawn QA. Re-spawn coder with the failing test output and instruction to fix.

**Sentinel deactivation** (all checks passed):
```bash
rm -f ~/.claude/scripts/governance/state/.gate-pre-qa
```

Commit ordering is enforced by the `commit-order-guard.sh` PreToolUse hook — code commits are blocked until a test-only commit exists. No manual verification needed.

### Garry-Review Step

Spawn a `general-purpose` subagent with an inline review prompt (no template — `GOVERNANCE_EXEMPT`). The review covers four categories:

- **Architecture**: coupling, separation of concerns, dependency direction
- **Code Quality**: naming, duplication, complexity, YAGNI
- **Tests**: coverage gaps, assertion quality, anti-patterns from vibe-manual 6.5
- **Performance**: obvious N+1, unnecessary allocations, missing indexes

Output: `qa/FEAT-XXX/T-XXX-review-findings.md` with P0/P1/P2 findings.
If P0 or P1 found: spawn coder to fix before QA Tester.

### Bug Severity at QA Boundary

- **P0:** MUST fix before next QA cycle (loop back through coder)
- **P1:** SHOULD fix before QA C2 — spawn coder, re-run QA C1 on fixes. Skip for single-file bug fixes, config-only, or docs-only changes.
- **P2:** Log to `docs/backlog.md`, proceed

### Light-Level Shortcut

At `light` VIBE level: Spawn CODER → Pre-QA Gates → Garry-Review → fix if needed → Spawn QA Tester C1 → if PASS, task complete. No C2, no spec wall, no phase gate checks.

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
| `T-XXX-review-findings.md` | Garry-Review |
| `T-XXX-cycle-1.md` | QA Tester (Cycle 1) |
| `T-XXX-cycle-2.md` | QA Tester (Cycle 2, `full` only) |

### Spec-Diff Verification (Mandatory)

**Sentinel activation** (after QA passes, before marking task complete):
```bash
touch ~/.claude/scripts/governance/state/.gate-spec-diff
```

Before marking ANY task complete:
1. Enumerate every requirement from the original spec/task description
2. For each requirement, cite `file:line` evidence (use Grep/Read to verify)
3. "File exists" is NOT evidence — confirm the file contains required functionality
4. "Agent reported done" is NOT evidence — verify independently
5. Missing evidence = NOT complete

At `light` level: brief inline check. At `full` level: document in QA artifact.

**Sentinel deactivation** (all requirements have file:line evidence):
```bash
rm -f ~/.claude/scripts/governance/state/.gate-spec-diff
```

---

## Subagent Prompts — MANDATORY Template Protocol

HARD STOP: You MUST use the Read tool to load each template from `templates/`
and use its full content as the subagent prompt. HAND-CRAFTING PROMPTS IS
FORBIDDEN. The pre-agent-gate hook WILL reject prompts missing required sections.

### What the governance hooks validate

The `pre-agent-gate.sh` hook checks THREE things in every subagent prompt. ALL must pass or the spawn is blocked:

| Check | What it looks for | Regex/pattern |
|-------|-------------------|---------------|
| CHECK 1: Mandatory Context | `## Mandatory Context` header with at least one spec ref | `docs/.*\.md` or `REQ-[0-9]+` |
| CHECK 2: Requirement Map | Fenced ` ```json ` code block with valid structure | `task_id` (string) + `requirements[]` array, each with `req_id`, `what`, `done_when`, `escalate_if`, `source` (all non-empty strings) |
| CHECK 3: Constraints | `## Constraints` header with non-empty body | Any non-whitespace text under the header |

The `post-agent-audit.sh` hook then checks the subagent OUTPUT for evidence matching each `req_id`. Subagents must include `REQ-XX: <evidence>` lines.

### Template loading protocol

1. **Read the template:** Use the Read tool on `templates/{role}-prompt.md`
2. **Fill ALL `{PLACEHOLDERS}`** with actual values (see placeholder reference below)
3. **Verify before spawning:** (a) `docs/*.md` path present in Mandatory Context, (b) valid JSON in requirement map fenced block, (c) non-empty Constraints section
4. **Spawn via Agent tool** with the filled prompt

### Placeholder reference

| Placeholder | What to fill | Example |
|-------------|-------------|---------|
| `{SPEC_PATH}` | Path to relevant spec — MUST be `docs/*.md` format | `docs/pm-reporting.md` |
| `{REQUIREMENT_MAP_JSON}` | Valid JSON object (see example below) | See below |
| `{ESCALATION_CONDITIONS}` | Task-specific escalation triggers | `Auth fails after retry` |
| `T-XXX` | Task identifier | `T-001` |
| `FEAT-XXX` | Feature identifier | `FEAT-001` |

### Valid requirement map example

```json
{
  "task_id": "T-001",
  "requirements": [
    {
      "req_id": "REQ-001",
      "what": "Add input validation to login endpoint",
      "done_when": "Login rejects empty email with 400 status and descriptive error",
      "escalate_if": "Auth module structure unclear or conflicts with SSO flow",
      "source": "docs/auth-spec.md — section 2.1 input validation"
    }
  ]
}
```

### When no spec exists for the task

If the task has no formal spec, you MUST still provide a `docs/*.md` reference — the hook enforces this. Options:
- Use an existing doc: `docs/pm-reporting.md`, `docs/backlog.md`, or similar context doc
- Create a lightweight task doc in `docs/` first, then reference it
- NEVER rely on `NO_SPEC_REQUIRED` alone — it will not pass CHECK 1

| Subagent | Template | Type |
|----------|----------|------|
| Coder | `templates/coder-prompt.md` | (default) |
| Architect | `templates/architect-prompt.md` | `general-purpose` |
| Garry-Review | Inline prompt (`GOVERNANCE_EXEMPT`) | `general-purpose` |
| QA Tester | `templates/qa-tester-prompt.md` | (default) |

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
   Total: X tasks, ~Y tests. Each task: coder → garry-review → fix → QA Tester C1 → QA Tester C2
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
## Red Flags — STOP Immediately

If you catch yourself doing any of these, you've confused your role. Return to orchestration.

- **Editing implementation files** (Edit/Write on .py/.ts/.js) → spawn coder
- **Running implementation tests** → coder's job
- **Skipping QA cycles** → violation, no exceptions
- **Proceeding without artifact** → wait for it
- **Running Bash on implementation code** → Bash is for lifecycle only
- **"Just this once" / "Quick fix" / "I already know"** → spawn the subagent anyway. Subagent isolation prevents context pollution.

## Sentinel & Validation Reference

### Sentinels (in `~/.claude/scripts/governance/state/`)

| Sentinel | When Set | When Cleared | What It Blocks |
|----------|----------|--------------|----------------|
| `.gate-pre-qa` | Coder returns `ready-for-review.md` | TDD evidence verified + test suite passes + validate-artifact passes | QA Tester and Garry-Review spawns |
| `.gate-qa-c1` | Before spawning QA Tester C1 | `cycle-1.md` artifact produced and validated | QA Tester C2 spawns |
| `.gate-spec-diff` | After QA passes | All requirements have `file:line` evidence | Task completion |

### Validation Script

```bash
# Explicit invocation (after subagent returns):
~/.claude/skills/lead-orchestrator/scripts/validate-artifact.sh <path>

# Also fires automatically as PreToolUse Write hook on qa/ paths
```

**Checks per artifact type:**
- `*ready-for-review*`: `## TDD Evidence` with table rows or `TDD-EXEMPT`, `ReviewCommit:<SHA>`
- `*review-findings*`: P0/P1/P2 severity or explicit "no findings", summary section header
- `*cycle-1*` / `*cycle-2*`: PASS/FAIL/PASS_WITH_CONCERNS verdict, test output section, task reference

### Hook Scripts

| Script | Matcher | Purpose |
|--------|---------|---------|
| `scripts/validate-artifact.sh` | Write (on `qa/` paths) | Blocks malformed QA artifacts from landing |
| `scripts/orchestrator-step-gate.sh` | Agent | Blocks out-of-order subagent spawns when sentinels active |

---

## Orchestration Log

Write `logs/build-{timestamp}.md`:

```markdown
# FEAT-XXX Orchestration Log

## T-101: [Task Name]
- [ ] Coder spawned / ready-for-review.md
- [ ] Garry-Review spawned / review-findings.md
- [ ] Coder fix (if P0/P1 findings)
- [ ] QA Tester C1 spawned / cycle-1.md (PASS/FAIL)
- [ ] QA Tester C2 spawned / cycle-2.md (PASS/FAIL, full only)

```
