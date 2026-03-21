# VIBE CODE PROTOCOL: Spec-Driven TDD with Per-Task Orchestration

> **Purpose:** Run Yu-Kuan's project end-to-end using spec-driven + TDD workflow with **per-task subagent pairs** (coder+QA) to prevent context exhaustion and loop stalls.
> **Primary objective:** Ship correct software with high confidence, minimal thrash, and strict process discipline.
> **Key change:** Spawn dedicated subagent pairs per T-XXX task (not per feature), commit after each task passes QA.

---
## 0. Rule Index (Hard Gates)
1. **R0 Zero Assumption Policy** -- Never guess requirements. Use `AskUserQuestion` until explicit confirmation.
2. **R1 The Spec Wall** -- No code without an approved spec in `docs/prd/features/`.
3. **R2 TDD Mandate** -- Implementation code is illegal unless a corresponding failing test exists.
4. **R3 Mock-First Parallelism** -- Frontend agents MUST mock API responses. Never block on Backend. Mocks MUST conform to the shared contract artifact (R16) — never invent field names.
5. **R4 2 QA Cycles Minimum** -- No merge without 2 documented review passes.
6. **R5 Phase Gate Enforcement** -- Respect `.claude/phase.json`; no code until phase = `BUILD`.
7. **R6 Auto-Commit** -- `git add -A && git commit && git push` after every task completion. Automatic, not user-triggered. No batching.
8. **R7 Per-Task Subagent Lifecycle** -- Dedicated subagent pairs per T-XXX task (not per feature); prevents context exhaustion.
9. **R8 Role Separation** -- Coder and QA MUST run as separate subagents/sessions; do not reuse a single agent for both roles.
10. **R9 QA No-Edit** -- QA NEVER edits implementation code (source files, tests, configs); QA only writes QA artifacts.
11. **R10 Review Snapshot** -- Coder MUST commit `qa/FEAT-XXX/T-XXX-ready-for-review.md` containing `ReviewCommit:<SHA>` + commands run; QA reviews that SHA, not "latest HEAD".
12. **R11 STOP Boundaries** -- After producing required artifact(s), each subagent MUST STOP. Orchestrator decides next spawn.
13. **R12 N=1 Escalation** -- After 1 failed fix cycle, Orchestrator STOPs and asks Yu-Kuan via `AskUserQuestion`.
14. **R13 Orchestrator Non-Implementation** -- Orchestrator coordinates + merges; never implements feature code.
15. **R14 History Rewrite Lock** -- Once any `qa/FEAT-XXX/T-XXX-ready-for-review.md` exists: no rebase, no force-push; only append commits.
16. **R15 User Approval Gates** -- Always confirm with `AskUserQuestion` before parallel execution, final merge, or skipping a task.
17. **R16 API Contract-First** -- Before BUILD, Architect MUST produce a shared contract artifact (`docs/contracts/<feature>.md`) defining all data models, SSE event schemas, and endpoint signatures exchanged between FE and BE. Both FE and BE subagents MUST reference this contract. QA MUST verify field names match the contract. No "invent your own field names" — the contract is the single source of truth.
18. **R17 Dependency Verification Gate** -- Every external dependency in a spec MUST include: (a) exact installable package name, (b) URL to PyPI/npm/GitHub repo, (c) minimum version. Before BUILD, the Architect or Orchestrator MUST verify every new dependency is installable (`pip install`, `npm install`). If a dependency cannot be installed, STOP and escalate — do not code against it, do not mock it, do not proceed. "Or equivalent" in a spec is a **hard blocker** requiring clarification before any code is written. A `try/except ImportError` with a `None` fallback is a deployment workaround, NEVER a substitute for verifying the package exists.
19. **R18 Real Testing Mandate** -- All tests MUST hit real DB (`SavepointConnection` from `conftest.py`) and real APIs where feasible (Anthropic haiku for agent integration). No mocks on internal modules — only mock external HTTP services (Resend, external URLs). If a test mocks an entire core dependency, that is a **P0 reject**. Test output must be pristine — no warnings, no uncaptured expected errors. NEVER use `git stash` in parallel agents (clobbers other agents' uncommitted work).

---
## 1. Context Detection (Start Here)
Determine your environment from git state:

| Branch | Role Mode |
|--------|-----------|
| `main` / `master` | **Management** (PO / Architect / Orchestrator) |
| `feat/*` or in `worktrees/` | **Production** (Developer / QA) |

---
## 2. Phase Gate System
Use `.claude/phase.json` to enforce workflow progression:
```json
{ "phase": "DISCOVERY" }
```
| Phase | Allowed Actions |
|-------|-----------------|
| `DISCOVERY` | Interview, read-only analysis, docs/specs only |
| `ARCHITECTURE_APPROVED` | Specs, decomposition, worktree setup |
| `FEATURE_SPECS_APPROVED` | Specs finalized, ready to build |
| `BUILD` | Implementation allowed |
**Rule:** If phase != `BUILD`, do not write implementation code (R5).

---
## 3. Repo Structure (Create If Missing)
```
CLAUDE.md                    # Repo contract: commands, conventions
Makefile                     # Standard commands (test, lint, format, etc.)
.claude/
  phase.json                 # Workflow phase gate
docs/
  prd/benchmarking-prototype-master-prd.md    # Master PRD
  arch/benchmarking-prototype-architecture.md  # System architecture + API contracts
  arch/adrs/ADR-0001.md      # Architecture Decision Records
  contracts/                   # Shared FE↔BE data contracts (R16)
    agent-sse.md               # SSE event schemas, field names, types
    <feature>.md               # One per feature with cross-boundary data models
  decisions.md               # Quick decisions log (lightweight ADR supplement)
docs/prd/
  features/FEAT-001-*.md     # Feature specs
qa/
  FEAT-001/
    T-101-ready-for-review.md  # Coder handoff per task
    T-101-cycle-1.md           # QA cycle 1 (P0 hard gate)
    T-101-cycle-2.md           # QA cycle 2 (P1/P2)
logs/
  build-YYYY-MM-DD-HHMMSS.md   # Progress log per build
```
### CLAUDE.md Must Include:
- Project commands: `make test`, `make lint`, `make format`, `make typecheck`
- DB commands: `make db-up`, `make db-reset`, `make migrate`
- Code style rules
- Worktree conventions

---
## 4. Tech Stack (Strict)
| Layer | Stack |
|-------|-------|
| Backend | Python, Postgres + pgvector, pytest |
| Frontend | React, Tailwind CSS, vitest / RTL |
| Linting | pre-commit + ruff (+ optional mypy) |

---
## 5. Roles
### 5.1 PM Interviewer (Requirements Extraction)
Trigger: Project start or new feature. Use `AskUserQuestion` until scope is clear, constraints explicit, success metrics exist, edge cases enumerated. Output: `docs/prd/benchmarking-prototype-master-prd.md` or `docs/prd/features/FEAT-XXX-*.md`.

### 5.2 Principal Architect
Trigger: PRD approved. Use `/feature-dev:code-architect` task subagent and superpowers. Propose 2-3 architecture options with tradeoffs. Define DB schema + API contracts (OpenAPI style). **MUST produce `docs/contracts/<feature>.md` for every cross-boundary data flow (R16)** — SSE event schemas, REST payloads, shared enums/types with exact field names. **MUST verify every new external dependency is installable before approving for BUILD (R17)** — run `pip install` / `npm install`, confirm the package exists, document the URL. If a dependency doesn't exist or is speculative, the design CANNOT proceed to BUILD. Output: `docs/arch/benchmarking-prototype-architecture.md`, `docs/arch/adrs/ADR-XXXX.md`, `docs/contracts/<feature>.md` (R16), `docs/decisions.md` (for quick decisions). Decompose into 3-5 feature tasks with minimal coupling.

### 5.3 Developer (Task Builder)
Trigger: Inside `feat/*` worktree, phase = `BUILD`, assigned a specific T-XXX task. Requirements: use a subagent and invoke skills IN ORDER below; use `superpowers:systematic-debugging` when stuck; R8 applies.

**Mandatory Skill Invocations (in order, non-negotiable):**
1. `superpowers:test-driven-development` — Red-Green-Refactor for every test
2. `superpowers:verification-before-completion` — prove tests pass with evidence before claiming done

**Steps:** (1) Context Load: read PRD, Architecture, `decisions.md`, feature spec, task mini-spec. (2) **Dependency Check (R17):** If the task introduces or uses a new external dependency, verify it is installable NOW — `pip install <pkg>` or `npm install <pkg>`. If it fails, STOP immediately and escalate. Do NOT write code against a package you cannot import. Do NOT use `try/except ImportError` as a substitute for a real package. (3) Build Guidance: follow task `Build Guidance`. (4) TDD Loop: RED failing tests for acceptance criteria, GREEN minimal code, REFACTOR. (5) **Real Testing (R18):** All tests must use `SavepointConnection` for real DB. No mocks on internal modules. Real API calls where feasible. Output: `qa/FEAT-XXX/T-XXX-ready-for-review.md` with `ReviewCommit:<SHA>` (R10).

### 5.4 QA Auditor
Trigger: Developer claims "Task T-XXX Complete" (per-task, not per-feature). Hard constraint: QA NEVER edits implementation code (R9). QA ONLY writes: `qa/FEAT-XXX/T-XXX-ready-for-review.md` (review), `T-XXX-cycle-1.md`, `T-XXX-cycle-2.md`. On FAIL: QA documents blockers; Orchestrator spawns coder to fix.

**Mandatory Skill Invocations (in order, non-negotiable):**
1. `garry-review` — review against engineering preferences (no mocks, real DB, DRY, edge cases)
2. `feature-dev:code-reviewer` — logic errors, missing assertions, security gaps

**QA Auto-Reject Criteria (P0 FAIL, non-negotiable per R18):**
- Any mock on internal module = P0 reject
- No `SavepointConnection` usage for DB tests = P0 reject
- Test passes without exercising real code path = P0 reject
- Uncaptured warnings in pytest output = P1 reject
- Entire core dependency mocked wholesale = P0 reject (per R17/MEMORY.md lesson)

**Bug Severity Classification (QA decides):**
| Severity | Category | Examples | Action |
|----------|----------|----------|--------|
| **P0** | Blocking | Functional errors, logic bugs, data corruption, typecheck failures | Must fix before task complete |
| **P1** | High-priority | Lint errors, critical gaps, missing error handling | Should fix, escalate if stuck |
| **P2** | Deferrable | Style nits, minor improvements, "nice to have" | Log to `docs/backlog.md`, proceed |

Must perform exactly 2 cycles per task, parallelize a separate subagent for each:
- **Cycle 1 -- Security & Logic (Hard Gate for P0):** Invoke `garry-review` then `feature-dev:code-reviewer`. Check SQL injection, PII leaks, auth issues; verify adherence to Architecture, `decisions.md`, and task Build Guidance; **verify all FE↔BE field names match `docs/contracts/*.md` (R16)**; **flag as P0 if tests mock an entire external dependency rather than exercising the real package — mocks that replace a core dependency wholesale prove orchestration logic only, not real integration (R17)**; **apply R18 auto-reject criteria: any mock on internal module = P0, no SavepointConnection = P0, test passes without exercising real path = P0, uncaptured warnings = P1**; run `make test`, `make lint`; output `qa/FEAT-XXX/T-XXX-cycle-1.md` with `STATUS: PASS|FAIL`.
- **Cycle 2 -- Quality & Resilience (P1 fix, P2 defer):** check naming, duplication, error handling, edge cases; verify empty states, timeouts, failure modes; output `qa/FEAT-XXX/T-XXX-cycle-2.md` with `STATUS: PASS|FAIL`.

Cycle Iteration Rule: exactly two named gates per task; a gate can be re-run until PASS; on FAIL spawn coder to fix blockers then re-run ONLY the failing cycle; after 1 failed fix cycle ESCALATE (N=1); don't redo already-passed cycles unless diff meaningfully impacts them. Task complete when both cycles pass, all tests green, `/code-review` issues resolved -> commit + push.

### 5.5 Lead Orchestrator (Task Driver)
Trigger: On `main/master` worktree (Management mode). Creates feature lanes + assigns FEAT IDs. **Before spawning any coder for a feature, verify ALL new external dependencies are installable (R17).** If any dependency cannot be installed, STOP the entire feature and escalate to Yu-Kuan — do not spawn coders to build against phantom packages. Per-task orchestration: spawn dedicated subagent pairs (architect + coder + QA) per T-XXX. Manage dependencies: run independent tasks in parallel (user confirmation), queue dependent tasks. Enforce artifact-only handoffs and STOP boundaries (R11). Commit + push after each task passes QA (R6). Merge to main only after user approval gate (R15).

**Subagent Mapping:**
| Phase | Subagent Type | Mandatory Skills (hardcode in prompt) | Output |
|-------|---------------|--------------------------------------|--------|
| Explore | `feature-dev:code-explorer` | N/A | Patterns, dependencies report |
| Architect | `feature-dev:code-architect` | N/A | Task design, file changes needed |
| Implement | `feature-dev:feature-dev` | `superpowers:test-driven-development` then `superpowers:verification-before-completion` | Code + tests + `T-XXX-ready-for-review.md` |
| QA | `feature-dev:code-reviewer` | `garry-review` then `feature-dev:code-reviewer` | `T-XXX-cycle-1.md`, `T-XXX-cycle-2.md` |
| Debug | `superpowers:systematic-debugging` | N/A | Diagnosis + fix |
| Fix Bugs | `feature-dev:feature-dev` | `superpowers:test-driven-development` then `superpowers:verification-before-completion` | Targeted fixes |

Skip Architect When: task is setup/config (e.g., "add env variable"); task is a bash command or script execution; task is extremely rote with no design decisions.

### 5.6 Debugging Protocol: Root Cause First

**Critical Rule:** When encountering bugs or errors, ALWAYS root cause thoroughly before implementing fixes.

**Anti-Pattern (DON'T DO THIS):**
1. See error message
2. Make assumption about cause based on error message alone
3. Immediately change code/schema/data
4. Create cascading problems or fix wrong thing

**Correct Pattern (DO THIS):**
1. **See error** - Capture full error message, stack trace, context
2. **Investigate thoroughly:**
   - Check git history: When did it last work? What changed?
   - Review test suite: How do existing tests handle this? Do they pass?
   - Read design docs: What was the original intent? (PRD, architecture, ADRs)
   - Sample data files: Is data inconsistent with schema/contract?
   - Check schema vs API contract vs loader code: Which is correct?
   - Look at usage patterns: How many instances fail vs succeed?
3. **Form hypothesis with evidence** - Not guesses, use concrete file paths and line numbers
4. **Present root cause analysis** - Show evidence for each finding
5. **Propose fix that addresses root cause** - Not symptoms
6. **Get approval before making changes** - Especially for schema/data/architectural changes

**Example Case Study: Schema Mismatch Errors**

When you see database type errors like "expected str, got list":
- ❌ **DON'T** assume schema is wrong and immediately change it
- ✅ **DO** investigate: Could be bad data generation, loader bug, or intentional design that data violates

**Investigation checklist:**
1. What does the schema say? (`api/db/models.py`)
2. What does the API contract say? (`api/schemas/*.py`)
3. What format is in the data files? Sample 5-10 files
4. What percentage of data matches schema vs violates it?
5. When was this code last working? Git log
6. How do tests handle this field? Check test fixtures
7. What was the original design intent? Check docs

**Root cause determines fix:**
- If schema is wrong (rare): fix schema + migrate data
- If data generation is wrong (common): fix data generator + bad data files
- If loader is wrong: fix loader validation/conversion
- If it's intentional mismatch: need design discussion

**Escalation:** If you're unsure after investigation, escalate to Yu-Kuan with your findings. Don't guess.

---
## 6. Parallelization via Git Worktrees
### 6.0 Lead Orchestrator (Per-Task Driver Loop)
**Goal:** In `main/master` (Management mode), Orchestrator runs each feature by spawning dedicated subagent pairs per T-XXX (architect + coder + QA). They do not share chat/context and communicate ONLY via committed repo artifacts under `qa/FEAT-XXX/`.

**Per-Task Deterministic Loop**
```
For each T-XXX in feature spec (respecting depends_on order):
  1. ARCHITECT (skip if trivial/rote): spawn `feature-dev:code-architect`; read task mini-spec + existing code patterns; output task design + files to create/modify; STOP.
  2. CODER: spawn `feature-dev:feature-dev`; MUST invoke `superpowers:test-driven-development` FIRST then `superpowers:verification-before-completion` before claiming done; TDD to acceptance criteria; all tests use real DB via SavepointConnection (R18); run `make test` + `make lint`; git commit `qa/FEAT-XXX/T-XXX-ready-for-review.md` with ReviewCommit:<SHA>; STOP.
  3. QA CYCLE 1 (P0 Hard Gate): spawn `feature-dev:code-reviewer`; MUST invoke `garry-review` FIRST then `feature-dev:code-reviewer`; checkout ReviewCommit; apply auto-reject criteria (R18); classify bugs P0/P1/P2; git commit `qa/FEAT-XXX/T-XXX-cycle-1.md` with STATUS: PASS|FAIL; STOP.
  4. IF CYCLE 1 FAIL: spawn coder to fix P0; re-run Cycle 1; if still fail -> ESCALATE (N=1).
  5. QA CYCLE 2 (P1 fix, P2 defer): spawn `feature-dev:code-reviewer`; quality/resilience checks; git commit `qa/FEAT-XXX/T-XXX-cycle-2.md` with STATUS: PASS|FAIL; STOP.
  6. IF CYCLE 2 FAIL: spawn coder to fix P1 (P2 -> `docs/backlog.md`); re-run Cycle 2; if still fail -> ESCALATE.
  7. ON PASS -- MANDATORY before next task: `git add -A && git commit -m "T-XXX: [desc]" && git push`; update progress log; proceed.
```

**Dependency-Aware Parallelism**
- Parse `depends_on` from each T-XXX mini-spec; tasks with no unmet dependencies can run in parallel.
- User confirmation required: `AskUserQuestion` "T-102 and T-103 have no dependencies. Run in parallel? (same worktree, sequential commits)".
- Commits are serialized by orchestrator to avoid conflicts.

**Parallel Execution Model: Same Worktree, Isolated Contexts**
- Parallel tasks run in the SAME feature worktree (e.g., `../wt/FEAT-001`)
- Each task gets isolated subagent context (separate chat sessions/Task tool invocations)
- Orchestrator serializes commits in dependency order to prevent conflicts
- Example: T-102 and T-103 both depend on T-101 and can run in parallel
  - Both spawn simultaneously after T-101 commits
  - T-102 finishes first → orchestrator commits to `feat/FEAT-001`
  - T-103 finishes second → orchestrator commits on top of T-102's commit
  - Each subagent works from its spawn point; orchestrator handles integration

**Pre-Flight Conflict Check**
Before approving parallel execution:
1. Architect phase identifies files each task will modify (from task design output)
2. If file overlap detected → warn user: "⚠️ T-102 and T-103 both modify `src/api/filters.py`. Proceed in parallel? (may require manual merge)"
3. If no overlap → proceed safely in parallel
4. If overlap approved → orchestrator must handle merge conflicts during commit serialization

**Orchestrator Commit Serialization Strategy**
When multiple parallel tasks complete:
1. Orchestrator maintains commit queue ordered by task dependencies
2. First completed task commits immediately to feature branch
3. Subsequent tasks:
   - Pull latest from feature branch before final commit
   - If changes conflict → orchestrator attempts auto-merge
   - If auto-merge fails → ESCALATE with conflict details (N=1 rule applies)
4. Each commit includes: `git add -A && git commit -m "T-XXX: [desc]" && git push`
5. Update progress log after each successful commit

**Feature Completion & Merge**
- When ALL tasks pass both QA cycles: update progress log; ask user "FEAT-XXX complete. All N tasks passed QA. Merge to main?".
- Merge (Orchestrator only): `git merge --squash feat/FEAT-XXX`, run full suite, log decisions, delete branch+worktree.

### 6.1 Lane Model
Main worktree = Orchestrator (PRD, Architecture, integration). Feature lanes = separate worktrees: `../wt/FEAT-001`, `../wt/FEAT-002`, etc.

### 6.2 Worktree Setup
```bash
mkdir -p ../wt
git fetch origin
git worktree add ../wt/FEAT-001 -b feat/FEAT-001 origin/main
```

### 6.3 Session Naming
```
/rename FEAT-001-coder
/rename FEAT-001-qa
```

### 6.4 Feature Decomposition Criteria
Features must be independently testable, minimal coupling, and mergeable in any order (or define dependency order).

### 6.5 Artifact Templates and Conventions
**Directory Structure (per-task, flat with prefix):**
```
qa/FEAT-001/
  T-101-ready-for-review.md   # Coder's handoff for T-101
  T-101-cycle-1.md            # QA hard gate (P0)
  T-101-cycle-2.md            # QA soft gate (P1/P2)
  T-102-ready-for-review.md
  T-102-cycle-1.md
  T-102-cycle-2.md
  ...
```
**Required Baton File: `qa/FEAT-XXX/T-XXX-ready-for-review.md`**
The coder MUST create this file to signal "task complete" and provide QA with a deterministic review snapshot:
```markdown
Task: T-XXX
ReviewCommit: <SHA>
CommandsRun:
- make test (PASS/FAIL)
- make lint (PASS/FAIL)
Summary:
- <what changed for this task>
RiskAreas:
- <where QA should focus>
Verify:
- <manual steps or pointers>
```
**Required QA Cycle Files**
**`qa/FEAT-XXX/T-XXX-cycle-1.md` (Security & Logic -- P0 HARD GATE):**
```markdown
Task: T-XXX
STATUS: PASS|FAIL
Scope: Security & Logic (P0 blocking)
CommandsRun: make test; make lint; /code-review
ReviewCommit: <SHA>
P0 Blocking Issues (if FAIL):
1) <file:line> -- <issue> -- <severity P0> -- <expected fix> -- <verification>
P1 Issues Found (for Cycle 2):
1) <file:line> -- <issue> -- <severity P1>
Verified (if PASS):
- <bullets>
```
**`qa/FEAT-XXX/T-XXX-cycle-2.md` (Quality & Resilience -- P1 fix, P2 defer):**
```markdown
Task: T-XXX
STATUS: PASS|FAIL
Scope: Quality & Resilience
CommandsRun: make test; make lint (and /code-review if needed)
ReviewCommit: <SHA>
P1 Issues (must fix):
1) <file:line> -- <issue> -- <severity P1> -- <expected fix> -- <verification>
P2 Issues (deferred to docs/backlog.md):
1) <file:line> -- <issue> -- <severity P2>
Verified (if PASS):
- <bullets>
```

#### 6.5.1 QA Verification Checklist

**Mandatory Verification Items (Cycle 1 - P0 Blocking):**

1. **Schema-DB Alignment** (added 2026-01-19 after BUG: schema Literal mismatch)
   - Verify Pydantic schemas match DB model constraints
   - Check: If DB field is unconstrained string → Schema MUST NOT use `Literal` types
   - Check: If spec requires "dynamic" behavior → Schema MUST accept any valid string
   - Automated check: Flag any `Literal` types in `api/schemas/*.py` when corresponding DB field in `api/db/models.py` is unconstrained
   - **Test**: Attempt POST with values from `/api/filters` endpoint (READ-WRITE consistency)

2. **Security Vulnerabilities** (existing)
   - SQL injection, XSS, path traversal, API key logging
   - PII leakage, authentication bypass

3. **Spec Compliance** (existing)
   - All P0 requirements implemented
   - API contracts match OpenAPI spec
   - Database schema matches data dictionary

4. **Test Coverage** (existing)
   - All tests passing (make test)
   - Critical paths have test coverage
   - Edge cases covered

5. **Production Build Verification** (added 2026-02-04 after deployment failure)
   - `npm run build` must pass in frontend/ directory
   - This runs `tsc -b` which enforces strict TypeScript checking
   - Note: `npm test` (Vitest) has lenient type processing - it does NOT catch all type errors
   - **Failure here = P0 blocker** - deployment will fail

**Recommended Verification Items (Cycle 2 - P1/P2):**

1. **Code Quality**
   - Linting passes (make lint)
   - Type checking passes (npm run typecheck in frontend/)
   - No TODO/FIXME comments without tracking

2. **Error Handling**
   - Comprehensive error messages
   - Proper HTTP status codes
   - Graceful degradation

3. **READ-WRITE Consistency** (added 2026-01-19)
   - Integration tests verify: "Can I POST what GET returns?"
   - Dynamic endpoints (like `/api/filters`) must have write-path validation tests

#### 6.5.2 Automated Code Review Gates (added 2026-01-19)

**Purpose:** Prevent schema-DB alignment issues through automated checks during QA cycles.

**Implementation Approaches:**

1. **Pre-commit Hook** (lightweight check)
   ```bash
   #!/bin/bash
   # .git/hooks/pre-commit or scripts/check-schema-alignment.sh

   # Check for Literal imports in schema files
   if grep -r "from typing import.*Literal" api/schemas/*.py; then
       echo "⚠️  WARNING: Found Literal types in schemas"
       echo "    Verify these match DB constraints in api/db/models.py"
       echo "    If DB field is unconstrained → schema MUST NOT use Literal"
   fi
   ```

2. **QA Review Script** (run during Cycle 1)
   ```bash
   # scripts/qa-check-literal-types.sh

   echo "Checking for schema-DB alignment issues..."

   # Find all Literal usage in schemas
   LITERAL_FILES=$(grep -l "Literal\[" api/schemas/*.py)

   if [ -n "$LITERAL_FILES" ]; then
       echo "⚠️  Found Literal types in schemas:"
       echo "$LITERAL_FILES"
       echo ""
       echo "Manual verification required:"
       echo "1. Check api/db/models.py for corresponding fields"
       echo "2. If DB field is String(N) without CHECK constraint → FAIL"
       echo "3. If spec requires 'dynamic' behavior → FAIL"
       echo ""
       exit 1
   fi

   echo "✓ No Literal types found in schemas"
   ```

3. **Pytest Check** (automated test)
   ```python
   # api/tests/test_schema_db_alignment.py

   def test_no_literal_types_for_unconstrained_db_fields():
       """Ensure Pydantic schemas don't use Literal for unconstrained DB fields."""
       import ast
       from pathlib import Path

       schema_files = Path("api/schemas").glob("*.py")
       issues = []

       for schema_file in schema_files:
           tree = ast.parse(schema_file.read_text())
           for node in ast.walk(tree):
               if isinstance(node, ast.Subscript):
                   if getattr(node.value, 'id', None) == 'Literal':
                       # Found Literal usage
                       issues.append(f"{schema_file}:{node.lineno}")

       assert not issues, f"Found Literal types in schemas: {issues}"
   ```

**Recommended Approach:** Use script #2 during QA Cycle 1 + add as manual checklist item.

**When to Bypass:** If DB has CHECK constraints or enum types, Literal is acceptable (but discourage per D-038).

#### 6.5.3 E2E Testing (added 2026-02-22)

**Purpose:** Full-stack browser-level verification using real backend, database, and frontend. Complements unit/integration tests and Playwright UI tests.

**When to Run E2E Tests:**
- After fixing router registration or endpoint wiring issues
- After database migration changes
- Before merging features that touch both FE and BE
- As part of P0 visual verification during QA cycles

**Infrastructure: `boardroom-ai/e2e/`**

All e2e test configuration lives in `boardroom-ai/e2e/config.py` — the single source of truth for URLs, ports, credentials, and route maps. Never hardcode these values elsewhere.

```
boardroom-ai/e2e/
  config.py       # URLs, ports, credentials, route maps
  setup.py        # Bootstrap: create user, login, create project
  teardown.py     # Cleanup: delete test user, remove state
  run_all.py      # Test runner (setup → discover → execute → teardown)
  lib/api.py      # Python HTTP helpers (no curl, no shell escaping)
  tests/          # Scripted regression tests (bash + env vars)
  visual/         # Chrome DevTools visual test definitions (YAML)
```

**Setup/Teardown Flow:**
1. `python boardroom-ai/e2e/setup.py` — polls /health, creates user, logs in, creates project, saves session to `.state/session.json`
2. Run tests (scripted or visual)
3. `python boardroom-ai/e2e/teardown.py` — deletes test user, removes state

**Two Tool Modes:**

| Use Case | Tool | Why |
|----------|------|-----|
| Scripted regression (CI, pre-merge) | **bash scripts** (`tests/test_*.sh`) | Repeatable, exit codes, no MCP needed |
| P0 visual verification (QA agent) | **Chrome DevTools MCP** | Real-time DOM/network/console inspection |
| Ad-hoc debugging | **Chrome DevTools MCP** | Interactive element inspection |

**P0 Visual Tests (YAML):**
Visual test definitions in `e2e/visual/` are structured YAML files that QA agents execute step-by-step using Chrome DevTools MCP. They are NOT automated — they are instructions. See `e2e/visual/README.md` for execution guide.

**Common Pitfalls (learned from FT-6 e2e session):**
1. Missing DB migrations — verify `docker-compose.yml` mounts all files from `backend/migrations/`
2. Wrong FE routes — use `/project/{id}` (singular), not `/projects/{id}`
3. Wrong API prefixes — action-items and agent use `/api/` prefix; auth, projects do NOT
4. Shell escaping — use Python `urllib` for JSON payloads, never `curl` with inline JSON
5. Port mapping — BE is 3456 externally (8000 inside container), FE is 3000 (8080 inside)
6. No test user — run `setup.py` before any test; it creates via `/test/create-user`
7. Stale DB — `docker compose down -v && up -d` for fresh migrations on schema changes
8. JWT expiry — tokens from `setup.py` last ~1 hour; re-run setup for long test sessions

### 6.6 History Rewrite Rule (Artifact Stability)
Once any `qa/FEAT-XXX/T-XXX-ready-for-review.md` exists on a feature branch: **no rebase**, **no force-push**, only append commits. Rationale: squash merge later, but QA artifacts must remain stable and traceable; rebasing can confuse which SHA was reviewed.

### 6.7 Progress Logging & Communication
**Terminal Updates (brief, visible):**
```
[FEAT-001] Starting T-101: Create DB schema
[FEAT-001] T-101: Architect complete, spawning coder
[FEAT-001] T-101: Coder complete, spawning QA (Cycle 1)
[FEAT-001] T-101: Cycle 1 PASS, proceeding to Cycle 2
[FEAT-001] T-101: Cycle 2 PASS ✓ -- Committed & pushed
[FEAT-001] Starting T-102, T-103 in parallel (user approved)
[FEAT-001] T-102: Cycle 1 FAIL (P0: 2 issues) -- Spawning fix
[FEAT-001] T-102: Fix attempt failed -- ESCALATING
```
**Progress Log File:** `logs/build-YYYY-MM-DD-HHMMSS.md`
```markdown
# Build Log: FEAT-XXX
Started: YYYY-MM-DD HH:MM:SS
Branch: feat/FEAT-XXX

## Task Status
| Task | Status | Architect | Coder | QA-C1 | QA-C2 | Commit |
|------|--------|-----------|-------|-------|-------|--------|
| T-101 | ✓ Done | ✓ | ✓ | PASS | PASS | abc123 |
| T-102 | 🔄 QA-C1 | ✓ | ✓ | FAIL(1) | - | - |
| T-103 | ⏳ Blocked | - | - | - | - | - |

## Event Log
### HH:MM:SS -- T-101 Started
- Spawned: code-architect
- Dependencies: none
### HH:MM:SS -- T-101 Architect Complete
- Files identified: src/db/schema.py, migrations/001_initial.py
- Spawning: feature-dev (coder)
### HH:MM:SS -- T-102 Cycle 1 FAIL
- P0: TypeError in extraction.py:45 -- missing null check
- P0: Test test_extract_empty fails -- expected [] got None
- Spawning: feature-dev (fix)
### HH:MM:SS -- T-102 ESCALATED
- Reason: Fix cycle failed (N=1 limit reached)
- Blocker: Unclear how to handle empty API response
- User input required
```
**Debug Info Captured:** subagent spawn times and durations; exact error messages from failures; file paths touched per task; commit SHAs.

### 6.8 Escalation Policy & User Gates
**Escalation Policy (N=1):**
```
Task fails QA Cycle -> Spawn coder to fix -> Re-run same cycle
  ↓
If fix fails -> ESCALATE immediately (no second attempt)
```
**Escalation Message Format:**
```markdown
🚨 ESCALATION: T-XXX (FEAT-XXX)

**Failed After:** 1 fix attempt
**Cycle:** 1 (Hard Gate) | 2 (Soft Gate)
**Blocker:**
- P0: <file:line> -- <issue description>

**Attempted Fix:**
- <what was tried>
- Error: <result>

**Options:**
1. Provide guidance and I'll retry
2. You fix manually, I'll continue
3. Skip this task, proceed with others
4. Abort feature

**Relevant Files:**
- <file:line>
```
**User Approval Gates:**
| Gate | When | Question |
|------|------|----------|
| **Parallel execution** | Before running 2+ tasks simultaneously | "T-XXX and T-YYY have no dependencies. Run in parallel? (same worktree)" |
| **Final merge** | All tasks complete | "FEAT-XXX complete. All N tasks passed QA. Merge to main?" |
| **Skip task** | User chooses during escalation | "Skipping T-XXX. Continue with T-YYY?" |
**No Auto-Proceed On:** any escalation; parallel execution; merge to main.

---
## 7. Feature Spec Template
```markdown
# FEAT-XXX: [Title]
## Objective
[1-2 lines]
## Requirements / Non-goals
[p0/1/2 - each requirement is a numbered bullet with 1-2 sentences describing our problem to solve, rationale, desired outcome, expected behavior, and other key details]
- In scope: [requirements 1...N]...
- Out of scope: ...
## Interfaces
### API Endpoints
- `POST /api/...` -- ...
### DB Changes
- Table: `...`
- Indexes: `...`
### FE Changes
- Component: `...`
### New Dependencies (R17 — MANDATORY for any new package)
- `package-name>=X.Y.Z` — [PyPI](https://pypi.org/project/package-name/) or [GitHub](https://github.com/org/repo) — Purpose: [why needed]
- **HARD RULE:** Every dependency MUST have an installable name + URL. "Or equivalent" = BLOCKER. Speculative packages = BLOCKER. Architect MUST `pip install`/`npm install` to verify before BUILD.
## Tasks
### T-101: [Task Title]
**Priority:** P0 | P1 | P2
**Depends On:** - (none) | T-100, T-102
**Objective:** [What this task accomplishes - single sentence]
**Requirements:**
- [Specific requirement 1]
- [Specific requirement 2]
**Build Guidance:**
- Use existing `ClassName` pattern from `src/path/`
- Parse with Pydantic models, not raw dict access
- Batch operations (chunk size N) to avoid memory issues
- Reuse `UtilityName` from `utils/path.py`
- [Specific architectural/code guidance - NOT generic principles like "keep it DRY"]
**Acceptance Criteria:**
- [ ] [Criterion 1]
- [ ] [Criterion 2]
**Edge Cases:**
- [Edge case 1 and expected behavior]
**Test Plan:**
- Unit: [What to test]
- Integration: [What to test]
---
### T-102: [Task Title]
**Priority:** P0
**Depends On:** T-101
**Objective:** [...]
**Requirements:**
- [...]
**Build Guidance:**
- [Specific guidance for this task]
**Acceptance Criteria:**
- [ ] [...]
**Edge Cases:**
- [...]
**Test Plan:**
- [...]
---
[Continue for all tasks...]
## Task Dependencies Graph
```
T-101 (no deps)
    └── T-102 (depends on T-101)
    └── T-103 (depends on T-101)
T-104 (no deps, can run parallel with T-101)
```
## Definition of Done
- [ ] All T-XXX tasks pass 2 QA cycles each
- [ ] All tests pass (`make test`)
- [ ] Lint passes (`make lint`)
- [ ] User approval gate for merge
```
**Task Mini-Spec Rules:** every T-XXX MUST have Priority, Depends On, Objective, Requirements, Build Guidance, Acceptance Criteria, Edge Cases, Test Plan. `Build Guidance` must be SPECIFIC (patterns, classes, utilities to use) -- NOT generic principles. `Depends On` is authoritative -- architect validates but cannot override spec. Tasks are the unit of work: each gets its own architect->coder->QA cycle.

**Schema Design Rules (added 2026-01-19 after BUG: schema Literal mismatch):**

When specifying data models and validation schemas:

1. **PROHIBIT `Literal` Types for Dynamic Fields**
   - If requirement states "dynamic", "database-driven", "user-configurable", or "extensible" → Schemas MUST NOT use `Literal` types
   - Example: "Filter values are dynamic from database" → `stage: str = Field(...)` NOT `stage: Literal["early", "growth", "late"]`
   - Bad: Showing hardcoded validation error examples when requiring dynamic behavior
   - Good: Explicitly state "schemas MUST use unconstrained string fields, NOT Literal types"

2. **Schema-DB Alignment**
   - If DB model uses unconstrained strings → Pydantic schema MUST match (no `Literal` constraint)
   - If DB has CHECK constraint → Pydantic schema MAY use `Literal` (but prefer unconstrained for flexibility per D-038)
   - Build Guidance MUST specify: "Verify schema constraints match DB model constraints"

3. **Validation Error Messages**
   - When showing example validation errors in specs, add note: "(Example values - actual validation is dynamic)"
   - Avoid examples that imply hardcoded lists when behavior is dynamic

**Example Spec Language (GOOD):**
```markdown
**Requirements:**
- [P0] Filter values (stage, sector, geography) are database-driven via `/api/filters` endpoint
- [P0] Schemas MUST NOT use Literal types for these fields — use unconstrained str with Field constraints
- [P0] Frontend MUST fetch filter values from API, never hardcode them

**Build Guidance:**
- In `api/schemas/company.py`: Use `stage: str = Field(..., min_length=1, max_length=50)` NOT `Literal`
- Verify schema matches DB model: `api/db/models.py` uses `String(50)` → schema uses `max_length=50`
- Add integration test: POST with values from GET `/api/filters` (READ-WRITE consistency)
```

---
## 8. Plugin Usage
`/feature-dev`: use at feature start for structured discovery -> planning -> implementation. `/code-review`: run during QA cycles; treat as a gate -- resolve findings before merge.

---
## 9. Integration & Merge
Trigger: all T-XXX tasks pass both QA cycles + user approval gate. Steps: (1) User approval question; (2) Merge `git merge --squash feat/FEAT-XXX`; (3) System check full suite (`pytest` + `npm test`); (4) Log decisions to `docs/decisions.md`; (5) Cleanup delete worktree and branch.

---
## 10. Output Discipline
When responding, use this format: (1) **Phase:** DISCOVERY / ARCHITECTURE_APPROVED / FEATURE_SPECS_APPROVED / BUILD (2) **Role:** PM Interviewer / Architect / Developer / QA / Orchestrator (3) **Next Actions:** (bulleted, minimal) (4) **Questions:** (via `AskUserQuestion` if needed) (5) **Artifacts to Update:** (file paths).

---
## 11. Kickoff Checklist
1. Verify repo commands exist; update `CLAUDE.md`
2. Create `.claude/phase.json` with `DISCOVERY` if missing
3. Start Master PRD interview using `AskUserQuestion`
4. Do not write code until phase = `BUILD`

**END OF PROTOCOL**
