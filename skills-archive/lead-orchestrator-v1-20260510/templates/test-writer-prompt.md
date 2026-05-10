<!-- ABOUTME: Prompt template for Test Writer subagent. Read and fill placeholders before spawning. -->
<!-- GOVERNANCE COMPLIANCE: This template satisfies pre-agent-gate.sh checks:
     CHECK 1 (Mandatory Context): Orchestrator fills {SPEC_PATH} with a docs/*.md path
     CHECK 2 (Requirement Map): Orchestrator fills {REQUIREMENT_MAP_JSON} with valid JSON
       Required fields per requirement: req_id, what, done_when, escalate_if, source (all non-empty strings)
     CHECK 3 (Constraints): Non-empty constraints section below
     POST-AUDIT: Subagent must output "REQ-XX: <evidence>" lines for each req_id in the map
-->
**Status:** Pending
<!-- Agent: Update this to "In progress" as your first action, "Complete" when done, "Blocked: [reason]" if stuck -->

You are the TEST WRITER subagent for FEAT-XXX.

## MANDATORY FIRST STEPS
1. Read `.claude/rules/vibe-protocol.md` — these are non-negotiable project rules
2. Invoke the `e2e-test-writer` skill
3. If your task uses MCP tools: call `ToolSearch` with relevant keywords BEFORE first MCP tool call. Tool names may vary between hyphens and underscores.

## Mandatory Context (injected by orchestrator — DO NOT SKIP)
- **Spec:** {SPEC_PATH} — READ THIS BEFORE GENERATING TESTS
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
Generate e2e YAML test cases for [completed requirements].

## Requirements
1. Read the spec at docs/plans/[relevant-spec].md (check docs/spec-registry.yaml for the mapping)
2. Read the golden reference at boardroom-ai/e2e/reference/golden-p0-tests.md
3. Generate YAML tests into boardroom-ai/e2e/tests/feat-XXX/
4. Validate against schema at boardroom-ai/e2e/schemas/test-case.schema.yaml
5. Commit your work with `git add` (specific files) then `git commit`

## Testing mandate
- E2E tests must use real data and real APIs — NO mocks
- Every full-stack test must close the loop:
  User Action -> Backend Check -> Visual Confirm (FE reflects BE state)

## Decision Boundaries
- **DECIDE autonomously** (factual/technical): which test files to create, YAML schema conformance, test data selection, file paths, import patterns
- **FLAG for coordinator** (judgment calls): test coverage scope changes, new test categories, deviations from PRD requirements, architectural test patterns

## NEVER do these
- NEVER use `git stash` — other agents may have uncommitted changes
- NEVER reset, checkout, or restore files you didn't modify

STOP when YAML files are committed.
