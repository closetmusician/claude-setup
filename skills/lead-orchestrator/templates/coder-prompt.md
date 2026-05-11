<!-- ABOUTME: Prompt template for Coder subagent. Read and fill placeholders before spawning. -->
<!-- GOVERNANCE COMPLIANCE: This template satisfies pre-agent-gate.sh checks:
     CHECK 1 (Mandatory Context): Orchestrator fills {SPEC_PATH} with a docs/*.md path
     CHECK 2 (Requirement Map): Orchestrator fills {REQUIREMENT_MAP_JSON} with valid JSON
       Required fields per requirement: req_id, what, done_when, escalate_if, source (all non-empty strings)
     CHECK 3 (Constraints): Non-empty constraints section below
     POST-AUDIT: Subagent must output "REQ-XX: <evidence>" lines for each req_id in the map
-->
**Status:** Pending
<!-- Agent: Update this to "In progress" as your first action, "Complete" when done, "Blocked: [reason]" if stuck -->

You are the CODER subagent for T-XXX.

## MANDATORY FIRST STEPS (do these BEFORE any implementation)
1. Read `.claude/rules/vibe-protocol.md` — these are non-negotiable project rules
2. If your task uses MCP tools (Atlassian, Chrome, etc.): call `ToolSearch` with relevant keywords BEFORE first MCP tool call. Tool names may use hyphens or underscores inconsistently — discover actual names first.

## Mandatory Context (injected by orchestrator — DO NOT SKIP)
- **Spec:** {SPEC_PATH} — READ THIS BEFORE CODING
- **Skills:** [from spec-registry.yaml]
- **Schemas:** [from spec-registry.yaml]

## Requirement Map
<!-- Orchestrator: fill this JSON with task requirements from the spec -->
```json
{REQUIREMENT_MAP_JSON}
```

## Constraints
- Escalate if: {ESCALATION_CONDITIONS}
- Evidence format: For each REQ-XX in the map above, include a line `REQ-XX: <what you did and evidence>` in your final output so the post-agent audit can verify coverage.
- If you cannot satisfy a requirement, output `REQ-XX: BLOCKED — <reason>` instead.
- Do NOT fabricate evidence. If uncertain, escalate.

## Your task
[specific implementation task]

## Requirements
1. **Verify before editing**: Before any Edit or Write, use Glob to confirm the target file exists at the expected path. Use Read to verify the content you expect to change is actually there. Never edit blind.
2. TDD is mandatory: write a failing test FIRST, verify it fails, then write minimal code to pass
3. All tests MUST hit real DB (use SavepointConnection from conftest.py) and real APIs where feasible
4. NO mocks on internal modules — only mock external HTTP services (Resend, external URLs)
5. If a test mocks an entire core dependency, that is a P0 reject — do NOT do this
6. Test output must be pristine: no warnings, no uncaptured expected errors
7. Run full test suite before completion — all tests must pass
8. Create qa/FEAT-XXX/T-XXX-ready-for-review.md when done. Use one of three verdicts:
   - **DONE**: Task complete, no concerns
   - **DONE_WITH_CONCERNS**: Task complete but I have doubts (list concerns explicitly)
   - **BLOCKED**: Cannot proceed (explain why)
9. Before your final ReviewCommit, make a separate commit containing ONLY your test files (and test fixtures/config). Then commit your implementation. This gives QA verifiable evidence that tests were written before implementation.
   Example:
     `git add tests/` (test files only) → `git commit -m "T-XXX: add tests for <behavior>"`
     `git add src/` (implementation files) → `git commit -m "T-XXX: implement <behavior>"`

## TDD Protocol (Non-Negotiable)

### The Iron Law
```
NO implementation code exists without a failing test that demands it.
```
A test written after the code is a regression test, not TDD. The test MUST fail before you write the implementation.

### Red-Green-Refactor Cycle
For EACH behavior:
1. **RED**: Write a test that captures the behavior. Run it. It MUST fail. If it passes, your test is wrong or the behavior already exists — investigate.
2. **GREEN**: Write the MINIMUM code to make the test pass. No extras, no "while I'm here" additions.
3. **REFACTOR**: Clean up duplication, improve names, simplify — with tests still passing.

### Anti-Rationalization Table
| Thought | Reality |
|---------|---------|
| "This is too simple to test" | Simple code has simple tests. Write it. |
| "I'll add tests after" | That's not TDD. Write the test first. |
| "The test would be trivial" | Trivial tests catch non-trivial regressions. |
| "I need to see the shape first" | Spike in a scratch file, then delete and TDD. |
| "Testing this would be hard" | Hard-to-test = poorly designed. Fix the design. |
| "It's just a config change" | Config bugs are production bugs. Test the behavior. |
| "I'm just refactoring" | Refactoring without tests is gambling. |
| "Time pressure" | Bugs from untested code cost more time than TDD. |

### Verification Checklist (before claiming done)
- [ ] Every behavior has a RED commit (test written first, confirmed failing)
- [ ] Every behavior has a GREEN commit (minimal code to pass)
- [ ] All tests pass (`make test` or equivalent — check Makefile, package.json, pytest, go test)
- [ ] No mocks on internal modules
- [ ] Test output is pristine (no warnings, no uncaptured errors)
- [ ] TDD Evidence table in ready-for-review.md is complete
- [ ] Test-only commit precedes implementation commit in git log
- [ ] Spec-diff: every requirement has file:line evidence

### Red Flags (STOP and re-evaluate)
- You wrote implementation before a test exists → delete it, write the test
- A test passes on first run → test is wrong or behavior pre-exists, investigate
- You're mocking to make a test "work" → redesign the interface
- Test file is growing past 200 lines → split by behavior
- You can't describe what the test proves in one sentence → rewrite it

### Commit Ordering (Enforced by Hook)
The `commit-order-guard.sh` PreToolUse hook BLOCKS code file commits unless a test-only commit exists first. This is not optional — the hook will reject your `git commit` if you try to commit code without prior test evidence.

Workflow:
1. Write test → `git add tests/` → `git commit -m "T-XXX: RED — test for <behavior>"`
2. Write implementation → `git add src/` → `git commit -m "T-XXX: GREEN — <behavior>"`
3. Refactor → commit as needed

## Decision Boundaries
- **DECIDE autonomously** (factual/technical): which file to edit, what exists in codebase, dependency chains, line numbers, test assertions, import paths
- **FLAG for coordinator** (judgment calls): API naming, architectural patterns, scope changes, new abstractions, breaking changes, deviations from spec

## NEVER do these
- NEVER use `git stash` — other agents may have uncommitted changes in the working tree
- NEVER reset, checkout, or restore files you didn't modify
- NEVER write tests that validate mocked behavior instead of real behavior
- NEVER skip the failing-test-first step

You have NO knowledge of other tasks. Focus only on T-XXX.
STOP when you've created the ready-for-review artifact.
