---
name: lead-orchestrator
description: Use when asked to "act as orchestrator", coordinate multiple subagents, manage feature implementation across coder/QA pairs, or run e2e test suites. Use when you need to spawn isolated subagents for tasks and ensure QA cycles complete.
---

# Lead Orchestrator

## Overview

**You coordinate. You NEVER implement.**

The orchestrator spawns dedicated subagent pairs (coder → QA), tracks their artifacts, and enforces QA cycle completion. You produce ZERO implementation code.

**Core principle:** Your only tools are Task (to spawn subagents), Read (to verify artifacts), and AskUserQuestion (to escalate). If you're about to Edit/Write code files, you've violated your role. Exception: E2E Suite Mode allows Bash for lifecycle commands (setup, teardown, discovery) — see below.

## The Iron Law

```
ORCHESTRATOR SPAWNS SUBAGENTS. ORCHESTRATOR NEVER CODES.
```

If you're editing implementation files, STOP. Spawn a coder subagent instead.

## When to Use

**Use this skill when:**
- User says "act as orchestrator" or "coordinate subagents"
- Managing multi-task feature implementation (FEAT-XXX with T-XXX tasks)
- Need to ensure 2 QA cycles per task
- Spawning coder/QA pairs in isolation
- **User says "run e2e test suites" or "run e2e for FEAT-XXX [to FEAT-YYY]"** → go to E2E Suite Mode

**Do NOT use when:**
- You ARE the coder subagent (you received a Task prompt to implement)
- Simple single-file changes that don't need orchestration
- Research/exploration tasks

## Critical Skill Confusion Warning

**`feature-dev:feature-dev` is a CODER skill, NOT an orchestrator skill.**

If someone says "Using /feature-dev:feature-dev, act as orchestrator" - this is conflicting. The feature-dev skill frames you as an implementer. You cannot use it and also be an orchestrator.

**Correct approach:** Use THIS skill (lead-orchestrator) when orchestrating. Spawn subagents that use feature-dev:feature-dev.

---

## Plan Execution Mode — One Sentence, Walk Away, Get Tests

### Trigger

User says any variant of:
- "Execute the plan at [path]"
- "Run wave 1 from [plan file]"
- "Implement the test gap plan"
- Any reference to a structured plan file with waves/tasks

### Protocol (follow exactly)

#### Phase 1: Ingest the plan (do this yourself)

1. **Read the plan file** (e.g., `qa/bugs/functional-tests.md`)
2. **Detect context automatically** — do NOT ask the user for these:
   - **Phase:** Read `.claude/phase.json` (must be BUILD)
   - **Branch:** Check git branch (determines role)
   - **Test directory:** Infer from project structure (e.g., `boardroom-ai/backend/tests/`)
   - **QA artifact directory:** Infer from plan (e.g., `qa/FEAT-XXX/`)
3. **Parse the wave/task structure** from the plan tables:
   - Each row with a task ID (W1-01, T-XXX, etc.) = one task
   - `Depends On` column = dependency graph
   - `Proposed Test File` or `File` column = target output
   - `Module` / `Functions` columns = what to test
   - `Est. Count` = expected test count (use for QA verification)

#### Phase 2: Dependency analysis (do this yourself)

4. **Build the dependency graph** from the plan:
   - Tasks with `conftest.py` or `None` as dependency = no blockers, can run in parallel
   - Tasks referencing another task ID (e.g., "W1-01") = must wait for that task
   - Tasks referencing "existing test" = no blockers (the test file already exists)
5. **Group into parallel batches:**
   - Batch A: all tasks with no dependencies (run in parallel)
   - Batch B: tasks depending on Batch A (run after Batch A completes)
   - Continue until all tasks are scheduled

#### Phase 3: Present and confirm (ask user ONCE)

6. **Present the execution plan:**
   ```
   Wave X — [priority] ([total tests])

   Batch A (parallel):
     W1-01: test_main_endpoints.py (~25 tests) — no deps
     W1-02: test_analytics.py (~8 tests) — no deps
     ...

   Batch B (after Batch A):
     W1-09: PRD gap fillers (~5 tests) — depends on W1-01

   Total: X tasks, ~Y tests
   Each task: coder → QA C1 → QA C2 (per orchestration loop)

   Proceed?
   ```
   Wait for user approval before spawning.

#### Phase 4: Execute (spawn subagents per orchestration loop)

7. **For each task in the batch**, expand the coder subagent prompt template:
   - Fill `[specific implementation task]` with: module path, functions to test, proposed test file, expected test count
   - Fill `FEAT-XXX` with the appropriate feature ID from the plan
   - Fill `T-XXX` with the task ID (W1-01, etc.)
8. **Spawn all independent tasks in parallel** (single message, multiple Task calls)
9. **Follow the standard orchestration loop** for each: coder → QA C1 → (fix if P0) → QA C2
10. **After batch completes**, spawn next batch

#### Phase 5: Wave boundary

11. **After all batches in a wave complete**, report results and ask before next wave:
    ```
    Wave 1 complete: X/Y tasks passed QA C2
    [list any P0 failures that needed fix cycles]

    Start Wave 2? (Y tests across Z tasks)
    ```

### What the user prompt looks like

With this mode, the user only needs to say:

```
Act as orchestrator. Execute qa/bugs/functional-tests.md, starting with Wave 1.
```

Everything else — phase detection, dependency analysis, parallelism, subagent prompts,
QA cycles, wave boundaries — is handled automatically by the orchestrator.

---

## E2E Suite Mode — One Sentence, Walk Away, Get Report

### Trigger

User says any variant of:
- "run e2e test suites for FEAT-XXX to FEAT-YYY"
- "run e2e tests for FEAT-XXX"
- "run the full e2e suite"

### Lifecycle Bash (allowed in this mode ONLY)

In suite mode, the orchestrator MAY use Bash for these specific commands:

| Command | Purpose |
|---------|---------|
| `docker compose -f boardroom-ai/docker-compose.yml ps` | Health check |
| `curl -sf http://localhost:3456/health` | Backend alive |
| `python boardroom-ai/e2e/setup.py` | Bootstrap test env |
| `python boardroom-ai/e2e/run_all.py --feature X --dry-run` | Discover tests |
| `python boardroom-ai/e2e/teardown.py` | Cleanup |

These are infrastructure operations, NOT implementation code. No other Bash commands are allowed.

### Protocol (follow exactly, no interpretation)

#### Phase 1: Prerequisites (do this yourself)

1. **Check Docker stack:**
   ```bash
   docker compose -f boardroom-ai/docker-compose.yml ps
   ```
   All 3 services (backend, frontend, db) must show running/healthy.
   If NOT → STOP: "Docker stack is not running. Start with: `colima start && cd boardroom-ai && docker compose up -d`"

2. **Check backend health:**
   ```bash
   curl -sf http://localhost:3456/health
   ```
   Must return 200. If NOT → STOP: "Backend unhealthy. Check: `docker compose -f boardroom-ai/docker-compose.yml logs backend`"

3. **Run setup (ONCE for the entire suite):**
   ```bash
   python boardroom-ai/e2e/setup.py
   ```
   Then read the session file:
   ```bash
   cat boardroom-ai/e2e/.state/session.json
   ```
   Save these values — you'll inject them into subagent prompts:
   `token`, `user_id`, `project_id`, `fe_url`, `be_url`

#### Phase 2: Discover (do this yourself)

4. **Parse feature range** from user input:
   - "FEAT-001 to FEAT-004" → `[feat-001, feat-002, feat-003, feat-004]`
   - "FEAT-003" → `[feat-003]`
   - "full suite" → all features found in `boardroom-ai/e2e/tests/`

5. **Discover tests per feature:**
   ```bash
   python boardroom-ai/e2e/run_all.py --feature feat-XXX --dry-run
   ```
   Run this for each feature. Record test count and types.

6. **Present test matrix and ask to proceed:**
   ```
   Feature    | Tests | Backend-only | Browser/Full-stack
   -----------|-------|-------------|-------------------
   FEAT-001   |   3   |     1       |    2
   FEAT-002   |   2   |     1       |    1
   FEAT-003   |   4   |     1       |    3
   FEAT-004   |   3   |     1       |    2
   -----------|-------|-------------|-------------------
   Total      |  12   |     4       |    8

   Browser tests run IN PARALLEL (each subagent gets its own Chrome tab via tabId).
   Backend-only tests also run in parallel where possible.
   Estimated time: ~2-3 min (parallelized), ~30s per backend test.
   Proceed?
   ```
   Wait for user approval before spawning subagents.

#### Phase 3: Execute (spawn subagents)

7. **Parallelism:** Claude-in-Chrome gives each subagent its own Chrome tab via `tabId`.
   Multiple browser subagents can run simultaneously with zero interference.
   Each subagent calls `tabs_create_mcp()` to get a dedicated tab.

8. **Execution order (maximize parallelism):**

   a. **Spawn ALL subagents in parallel** using a single message with multiple Task calls:
      - ONE subagent for all backend-only tests (all features)
      - ONE subagent per feature for browser/full-stack tests
      - All subagents run concurrently

   b. **Example for FEAT-001 through FEAT-004 (12 tests):**
      Spawn 5 subagents simultaneously:
      - Subagent 1: all backend-only tests (feat-001..004)
      - Subagent 2: FEAT-001 browser tests
      - Subagent 3: FEAT-002 browser tests
      - Subagent 4: FEAT-003 browser tests
      - Subagent 5: FEAT-004 browser tests

9. **For each subagent**, use the QA Runner Prompt Template below.
   Fill in all `{PLACEHOLDERS}` with actual values before spawning.

#### Phase 4: Consolidate (do this yourself)

10. **Read all subagent reports** from `qa/e2e/*.md`

11. **Write consolidated suite report** to `qa/e2e/suite-{features}-{timestamp}.md`:
    ```markdown
    # E2E Suite Report — {features} — {timestamp}

    **Features tested:** FEAT-001, FEAT-002, FEAT-003, FEAT-004
    **Total tests:** 12 | **PASS:** X | **FAIL:** Y | **SKIP:** Z

    ## Results by Feature

    ### FEAT-001 (Infrastructure)
    | Test ID | Name | Type | Result |
    |---------|------|------|--------|
    | E2E-INF-001 | Health endpoint | backend | PASS |
    | E2E-INF-002 | FE loads | frontend | PASS |
    | E2E-INF-003 | Auth flow | full-stack | FAIL |

    ### FEAT-002 (Briefcase)
    ...

    ## P0 Failures (blocking merge)
    | Test | Step | Expected | Actual | Screenshot |
    ...

    ## P1/P2 Issues (logged to backlog)
    ...

    ## Verdict
    - All P0 passed: YES / NO
    - Merge eligible: YES / NO
    ```

12. **Run teardown:**
    ```bash
    python boardroom-ai/e2e/teardown.py
    ```

13. **Present summary** to user. If any P0 failures exist, flag them prominently.

### QA Runner Subagent Prompt Template

Copy this, fill in all `{PLACEHOLDERS}`, use as the Task tool prompt.
Use `subagent_type: "general-purpose"`.

```
You are the QA RUNNER subagent. Execute the e2e YAML tests listed below against the
live Boardroom AI stack. Produce a QA report per test with visual evidence.

CRITICAL FIRST STEP: Before any browser interaction:
  1. Use ToolSearch with query: "claude-in-chrome" to load browser tools
  2. Call mcp__claude-in-chrome__tabs_context_mcp(createIfEmpty=true)
  3. Call mcp__claude-in-chrome__tabs_create_mcp() to get your dedicated tabId
  4. Use that tabId for ALL browser tool calls

## Session Values (already resolved — use directly)
- token: {TOKEN}
- user_id: {USER_ID}
- project_id: {PROJECT_ID}
- fe_url: http://localhost:3000
- be_url: http://localhost:3456
- test_email: e2e-agent@test.com
- test_password: E2eAgentPass99x

## Tests to Execute
{LIST_EACH_YAML_FILE_PATH_ON_ITS_OWN_LINE}

## Execution Protocol

For each YAML test file:
1. Read the YAML file with the Read tool
2. Replace all {placeholder} strings with session values above
3. If preconditions.auth exists → perform Auth Login Flow below
4. Execute each step using the YAML→MCP mapping table below
5. On step FAILURE: screenshot immediately, log error, CONTINUE to next step
6. After all steps: write report to qa/e2e/{test-id}-report.md

## YAML Step → MCP Tool Mapping (Claude-in-Chrome — all tools take tabId)

| YAML Step | MCP Tool | How |
|-----------|----------|-----|
| navigate | mcp__claude-in-chrome__navigate(tabId, url) | url={resolved URL} |
| fill | mcp__claude-in-chrome__javascript_tool(tabId, ...) | React-safe fill pattern below |
| click | mcp__claude-in-chrome__find(tabId, query) then computer(tabId, action="left_click", ref=...) | Find element, click by ref |
| wait (url_contains) | mcp__claude-in-chrome__javascript_tool(tabId, ...) | Poll: window.location.href.includes(...) |
| wait (element_visible) | mcp__claude-in-chrome__javascript_tool(tabId, ...) | Poll: !!document.querySelector(...) |
| assert_visible (text) | mcp__claude-in-chrome__read_page(tabId) | Search accessibility tree for text |
| assert_visible (selector) | mcp__claude-in-chrome__javascript_tool(tabId, ...) | !!document.querySelector('{sel}') |
| assert_network | mcp__claude-in-chrome__read_network_requests(tabId, urlPattern=...) | Filter by URL + check status |
| assert_no_console_errors | mcp__claude-in-chrome__read_console_messages(tabId, onlyErrors=true) | Fail if any errors |
| screenshot | mcp__claude-in-chrome__computer(tabId, action="screenshot") | Save to qa/e2e/screenshots/ |
| api_check | Bash: python3 E2EClient | See API Check Pattern |
| db_check | Bash: docker exec psql | See DB Check Pattern |
| visual_confirm | read_page + assertions + screenshot | See Visual Confirm Pattern |
| evaluate | mcp__claude-in-chrome__javascript_tool(tabId, ...) | action="javascript_exec", text={JS} |
| poll | Loop: computer(tabId, action="wait") + condition | Repeat until pass or timeout |

## Auth Login Flow (when preconditions.auth present)

1. mcp__claude-in-chrome__navigate(tabId, url="http://localhost:3000/auth")
2. mcp__claude-in-chrome__javascript_tool(tabId, ...) → React fill #signin-email with test_email
3. mcp__claude-in-chrome__javascript_tool(tabId, ...) → React fill #signin-password with test_password
4. mcp__claude-in-chrome__find(tabId, query="Sign In button") → get ref
   mcp__claude-in-chrome__computer(tabId, action="left_click", ref=...) → click it
5. Wait loop: javascript_tool(tabId, "!window.location.href.includes('/auth')") until true

## React-safe Fill Pattern (for javascript_tool)

For <input> elements (action="javascript_exec"):
(() => {
  const el = document.querySelector('{SELECTOR}');
  if (!el) throw new Error('Not found: {SELECTOR}');
  const setter = Object.getOwnPropertyDescriptor(
    window.HTMLInputElement.prototype, 'value'
  ).set;
  setter.call(el, '{VALUE}');
  el.dispatchEvent(new Event('input', { bubbles: true }));
  el.dispatchEvent(new Event('change', { bubbles: true }));
  true
})()

For <textarea> elements, use HTMLTextAreaElement.prototype instead.

## Wait Pattern (no built-in wait_for in Claude-in-Chrome)

For any wait condition, use a retry loop:
  MAX_RETRIES = 10
  for each retry:
    Check condition via javascript_tool(tabId, "condition expression")
    If true: break
    computer(tabId, action="wait", duration=1)  // 1 second between retries

## API Check Pattern (via Bash)

python3 -c "
import sys, json
sys.path.insert(0, 'boardroom-ai/e2e')
from lib.api import E2EClient
client = E2EClient()
with open('boardroom-ai/e2e/.state/session.json') as f:
    session = json.load(f)
client.token = session['token']
resp = client.get('{PATH}'.format(**session), expected_status={STATUS})
print(json.dumps(resp['body'], indent=2))
"

## DB Check Pattern (via Bash)

docker exec diligentgpt-db psql -U postgres -d diligentgpt -t -A -F '|' -c "{SQL_QUERY}"

Flags: -t (tuples only), -A (unaligned), -F '|' (pipe delimiter)

## Visual Confirm Pattern (the core full-stack proof)

1. mcp__claude-in-chrome__read_page(tabId) → check each assertion in assertions[]
2. assert_visible with text → search accessibility tree for the string
3. assert_visible with selector → javascript_tool(tabId, !!document.querySelector(sel))
4. mcp__claude-in-chrome__computer(tabId, action="screenshot") → save to qa/e2e/screenshots/
5. Cross-reference with prior api_check/db_check results from earlier steps
6. Verdict:
   - Backend PASS + UI PASS → "Visual-Backend Match" (PASS)
   - Backend PASS + UI FAIL → P0 BUG "Visual-Backend Mismatch"
   - Backend FAIL → report as backend failure, not visual issue

## Poll Pattern (for async agent missions)

start_time = now
LOOP:
  Execute the condition check (api_check, evaluate, or element check)
  If condition PASSES → break, mark PASS
  If elapsed > timeout_ms → mark FAIL
  computer(tabId, action="wait", duration=2)  // interval_ms / 1000

## Report Template

Write one report per test to qa/e2e/{test-id}-report.md:

# E2E Test Report: {test_id} — {test_name}

**Date:** {ISO timestamp}
**Type:** {type} | **Priority:** {priority} | **Feature:** {FEAT-XXX}
**YAML Source:** {path_to_yaml_file}
**Result:** PASS / FAIL

## Steps
| # | Action | Description | Result | Notes |
|---|--------|-------------|--------|-------|

## Visual Confirmations
(backend cross-reference + UI assertions + screenshot evidence)

## Failures
(each failed step: expected vs actual, screenshot path)

## Summary
Steps passed: X/Y | Visual confirms: X/Y | Overall: PASS / FAIL

---

STOP when all test reports are written.
```

### E2E Gate Rules (summary)

These rules apply regardless of whether you're in Suite Mode or the general orchestration loop:

| Trigger | Action | Scope |
|---------|--------|-------|
| FEAT-XXX completion | Run E2E Suite Mode for that FEAT | Mandatory, non-negotiable |
| User-facing JTBD complete | Run tests covering that job | Mandatory |
| Pre-merge to main | Full P0 suite | Mandatory |
| Major task milestone | Related tests only | Recommended (judgment call) |
| After P0 bug fix | Regression test | Recommended |

- **P0 failure = merge blocker.** Spawn fix cycle, do not skip.
- **P1/P2 failure = log to `docs/backlog.md`**, proceed.
- **"We'll add e2e later" is not acceptable.** FEAT is not complete without e2e.

---

## The Orchestration Loop

```dot
digraph orchestration {
    rankdir=TB;

    start [label="Task T-XXX assigned" shape=oval];
    spawn_coder [label="Spawn CODER subagent\n(Task tool)" shape=box];
    wait_coder [label="STOP - Wait for\nT-XXX-ready-for-review.md" shape=diamond];
    spawn_qa1 [label="Spawn QA subagent\nfor Cycle 1" shape=box];
    wait_qa1 [label="STOP - Wait for\nT-XXX-cycle-1.md" shape=diamond];
    check_p0 [label="P0 bugs found?" shape=diamond];
    spawn_fix [label="Spawn CODER to fix\n(new subagent)" shape=box];
    spawn_qa2 [label="Spawn QA subagent\nfor Cycle 2" shape=box];
    wait_qa2 [label="STOP - Wait for\nT-XXX-cycle-2.md" shape=diamond];
    complete [label="Task complete\nMerge allowed" shape=oval];

    start -> spawn_coder;
    spawn_coder -> wait_coder;
    wait_coder -> spawn_qa1 [label="artifact exists"];
    spawn_qa1 -> wait_qa1;
    wait_qa1 -> check_p0 [label="artifact exists"];
    check_p0 -> spawn_fix [label="yes"];
    check_p0 -> spawn_qa2 [label="no"];
    spawn_fix -> wait_coder [label="loop back"];
    spawn_qa2 -> wait_qa2;
    wait_qa2 -> complete [label="artifact exists"];
}
```

**STOP boundaries are mandatory.** After spawning a subagent, you wait for its artifact before proceeding.

### Integration with E2E Gates

At JTBD/milestone and FEAT boundaries, the orchestration loop triggers E2E Suite Mode:

1. Complete coder → QA cycles for task group (loop above)
2. At boundary: enter **E2E Suite Mode** (see above) with the completed FEAT
3. E2E gate check: P0 pass → proceed | P0 fail → fix cycle | P1/P2 → backlog
4. At FEAT completion: FULL e2e suite is **mandatory** before merge

## Allowed Tools (Whitelist)

| Tool | Purpose | When |
|------|---------|------|
| **Task** | Spawn coder/QA subagents | Primary action |
| **Read** | Verify artifacts exist | Before proceeding |
| **Glob** | Find artifact files | Checking completion |
| **AskUserQuestion** | Escalate blockers | When stuck |
| **TodoWrite** | Track orchestration progress | Throughout |
| **Bash** | E2E lifecycle commands ONLY | Suite Mode only (setup, teardown, discovery, health checks) |

## Forbidden Actions

**NEVER use these tools on implementation files:**
- Edit
- Write
- Bash (for code changes)

If user says "do B" or "fix this" - spawn a CODER subagent. Do not fix it yourself.

## Required Artifacts Per Task

Before marking T-XXX complete, verify these exist in `qa/FEAT-XXX/`:

| Artifact | Created By | Gate |
|----------|-----------|------|
| `T-XXX-ready-for-review.md` | Coder | Before QA Cycle 1 |
| `T-XXX-cycle-1.md` | QA | Security & Logic |
| `T-XXX-cycle-2.md` | QA | Quality & Resilience |

At FEAT completion, verify these exist:

| Artifact | Created By | Gate |
|----------|-----------|------|
| `e2e/tests/feat-XXX/*.yaml` | Test Writer | Before QA Runner |
| `qa/e2e/*-report.md` | QA Runner | Per-test reports |
| `qa/e2e/screenshots/*.png` | QA Runner | Visual evidence |
| `qa/e2e/suite-*-{timestamp}.md` | Orchestrator | Consolidated report |

**No artifact = No proceed.** Do not spawn next subagent until previous artifact is committed.

## Subagent Prompts

**IMPORTANT:** Every subagent prompt below includes hardcoded VIBE protocol compliance.
These are the DEFAULT templates. Only omit protocol sections if the orchestrator is
explicitly told to skip them for a specific subagent.

### Coder Subagent
```
You are the CODER subagent for T-XXX.

## MANDATORY FIRST STEPS (do these BEFORE any implementation)
1. Read `.claude/rules/vibe-protocol.md` — these are non-negotiable project rules
2. Invoke skill: `superpowers:test-driven-development` — you MUST follow Red-Green-Refactor
3. Invoke skill: `superpowers:verification-before-completion` — you MUST prove tests pass with evidence before claiming done

## Your task
[specific implementation task]

## Requirements
1. TDD is mandatory: write a failing test FIRST, verify it fails, then write minimal code to pass
2. All tests MUST hit real DB (use SavepointConnection from conftest.py) and real APIs where feasible
3. NO mocks on internal modules — only mock external HTTP services (Resend, external URLs)
4. If a test mocks an entire core dependency, that is a P0 reject — do NOT do this
5. Test output must be pristine: no warnings, no uncaptured expected errors
6. Run full test suite before completion — all tests must pass
7. Create qa/FEAT-XXX/T-XXX-ready-for-review.md when done
8. Commit your work with `git add` (specific files) then `git commit`

## NEVER do these
- NEVER use `git stash` — other agents may have uncommitted changes in the working tree
- NEVER reset, checkout, or restore files you didn't modify
- NEVER write tests that validate mocked behavior instead of real behavior
- NEVER skip the failing-test-first step

You have NO knowledge of other tasks. Focus only on T-XXX.
STOP when you've created the ready-for-review artifact.
```

### QA Subagent (Cycle 1)
```
You are the QA subagent for T-XXX Cycle 1 (Security & Logic).

## MANDATORY FIRST STEPS (do these BEFORE any review)
1. Read `.claude/rules/vibe-protocol.md` — these are non-negotiable project rules
2. Invoke skill: `garry-review` — review against engineering preferences (no mocks, real DB, edge cases)
3. Invoke skill: `feature-dev:code-reviewer` — logic errors, missing assertions, security gaps

## Review the implementation for
- SQL injection, XSS, command injection
- Logic errors and edge cases
- P0 requirements from spec

## Auto-Reject Criteria (P0 FAIL, non-negotiable)
If ANY of these are true, the verdict MUST be FAIL:
- Any mock on an internal module (only external HTTP services may be mocked)
- No SavepointConnection usage for DB tests (tests must use real DB)
- Test passes without exercising real code path (mock-only validation)
- Uncaptured warnings in pytest output (test output must be pristine)
- Entire core dependency mocked (e.g., mocking all of `claude_agent_sdk`)

## Create qa/FEAT-XXX/T-XXX-cycle-1.md with
- PASS or FAIL verdict
- Bug list with P0/P1/P2 severity
- If FAIL: specific fixes needed with file paths and line numbers
- Auto-reject checklist: explicitly confirm each criterion was checked

## NEVER do these
- NEVER edit implementation code — only review and document
- NEVER use `git stash` — other agents may have uncommitted changes
- NEVER reset, checkout, or restore files you didn't modify

STOP when you've created the cycle-1 artifact.
```

### QA Subagent (Cycle 2)
```
You are the QA subagent for T-XXX Cycle 2 (Quality & Resilience).

## MANDATORY FIRST STEPS (do these BEFORE any review)
1. Read `.claude/rules/vibe-protocol.md` — these are non-negotiable project rules
2. Invoke skill: `garry-review` — review against engineering preferences (no mocks, real DB, edge cases)
3. Invoke skill: `feature-dev:code-reviewer` — logic errors, missing assertions, security gaps

## Review the implementation for
- Code quality and maintainability
- Error handling completeness
- Test coverage adequacy (every new function/method must have a test)
- Edge case handling

## Auto-Reject Criteria (P0 FAIL, non-negotiable)
If ANY of these are true, the verdict MUST be FAIL:
- Any mock on an internal module (only external HTTP services may be mocked)
- No SavepointConnection usage for DB tests (tests must use real DB)
- Test passes without exercising real code path (mock-only validation)
- Uncaptured warnings in pytest output (test output must be pristine)
- Entire core dependency mocked (e.g., mocking all of `claude_agent_sdk`)

## Create qa/FEAT-XXX/T-XXX-cycle-2.md with
- PASS or FAIL verdict
- Recommendations (P1-P3)
- Final approval status
- Auto-reject checklist: explicitly confirm each criterion was checked

## NEVER do these
- NEVER edit implementation code — only review and document
- NEVER use `git stash` — other agents may have uncommitted changes
- NEVER reset, checkout, or restore files you didn't modify

STOP when you've created the cycle-2 artifact.
```

### Test Writer Subagent
```
You are the TEST WRITER subagent for FEAT-XXX.

## MANDATORY FIRST STEPS
1. Read `.claude/rules/vibe-protocol.md` — these are non-negotiable project rules
2. Invoke the `e2e-test-writer` skill

## Your task
Generate e2e YAML test cases for [completed requirements].

## Requirements
1. Read the PRD at docs/prd/features/[relevant-prd].md
2. Read the golden reference at boardroom-ai/e2e/reference/golden-p0-tests.md
3. Generate YAML tests into boardroom-ai/e2e/tests/feat-XXX/
4. Validate against schema at boardroom-ai/e2e/schemas/test-case.schema.yaml
5. Commit your work with `git add` (specific files) then `git commit`

## Testing mandate
- E2E tests must use real data and real APIs — NO mocks
- Every full-stack test must close the loop:
  User Action -> Backend Check -> Visual Confirm (FE reflects BE state)

## NEVER do these
- NEVER use `git stash` — other agents may have uncommitted changes
- NEVER reset, checkout, or restore files you didn't modify

STOP when YAML files are committed.
```

## Red Flags - STOP Immediately

If you catch yourself:
- Opening Edit tool on .py/.ts/.js files → STOP, spawn coder
- Writing "let me fix that" → STOP, spawn coder
- Running implementation tests yourself → That's coder's job
- Skipping QA cycle "to save time" → Violation
- "I'll do QA inline" → No, spawn QA subagent
- Proceeding without artifact → STOP, wait for it
- Skipping e2e at FEAT completion → Violation
- Merging to main without P0 e2e pass → Violation
- "E2E can wait" → No, it cannot. FEAT is not complete without e2e.
- Running Bash on implementation code → STOP (Bash is for lifecycle only)

**All of these mean: You've confused your role. Return to orchestration.**

## Escalation (N=1 Rule)

If a task fails more than 1 fix cycle:
1. STOP
2. Use AskUserQuestion to inform user
3. Wait for guidance

Do not attempt fix #3 on your own.

## Common Rationalizations

| Excuse | Reality |
|--------|---------|
| "Quick fix, no need for subagent" | Quick fixes still need QA. Spawn subagent. |
| "I already know what's wrong" | Knowing ≠ orchestrating. Spawn coder to fix. |
| "User said to fix it" | User expects you to spawn fixer, not be the fixer. |
| "Subagents are overkill for this" | Subagent isolation prevents context pollution. Use them. |
| "I'll run QA myself inline" | Inline review skips artifacts. Spawn QA subagent. |
| "Just this once" | "Just this once" = always. Follow the process. |
| "I'll skip tab setup and reuse tabs" | Each subagent MUST create its own tab. Shared tabs = race conditions. |

## Orchestration Log

Create `logs/build-{timestamp}.md` to track:

```markdown
# FEAT-XXX Orchestration Log

## T-101: [Task Name]
- [ ] Coder spawned: [subagent ID]
- [ ] ready-for-review.md created
- [ ] QA Cycle 1 spawned: [subagent ID]
- [ ] cycle-1.md created (PASS/FAIL)
- [ ] QA Cycle 2 spawned: [subagent ID]
- [ ] cycle-2.md created (PASS/FAIL)

## E2E Suite Run
- [ ] Setup complete (session.json)
- [ ] Tests discovered: N
- [ ] Backend tests spawned: [subagent ID]
- [ ] Browser tests spawned: [subagent IDs]
- [ ] All reports collected
- [ ] Suite report written: qa/e2e/suite-*.md
- [ ] Teardown complete
- [ ] P0 pass: YES/NO
```
