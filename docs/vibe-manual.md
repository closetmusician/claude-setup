# VIBE Protocol -- Templates, Checklists & Reference Formats

> For rules and workflow logic, see `~/.claude/rules/vibe-protocol.md`.
> This file contains templates, checklists, and reference formats that subagents read on demand.

---

## 1. Repo Structure (Create If Missing)

```
CLAUDE.md                    # Repo contract: commands, conventions
Makefile                     # Standard commands (test, lint, format, etc.)
.claude/
  phase.json                 # Workflow phase gate
docs/
  prd/<project>-master-prd.md    # Master PRD
  arch/<project>-architecture.md  # System architecture + API contracts
  arch/adrs/ADR-0001.md      # Architecture Decision Records
  contracts/                   # Shared FE<->BE data contracts (R7)
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

## 2. Tech Stack (Default -- override in project CLAUDE.md)

| Layer | Stack |
|-------|-------|
| Backend | Python, Postgres + pgvector, pytest |
| Frontend | React, Tailwind CSS, vitest / RTL |
| Linting | pre-commit + ruff (+ optional mypy) |

---

## 3. Worktree Setup

```bash
mkdir -p ../wt && git fetch origin && git worktree add ../wt/FEAT-001 -b feat/FEAT-001 origin/main
```

### Session Naming
```
/rename FEAT-001-coder
/rename FEAT-001-qa
```

---

## 4. Artifact Templates and Conventions

### 4.1 Directory Structure (per-task, flat with prefix)

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

### 4.2 Required Baton File: `qa/FEAT-XXX/T-XXX-ready-for-review.md`

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

### 4.3 Required QA Cycle Files

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

---

## 5. QA Verification Checklist

### 5.1 Mandatory Verification Items (Cycle 1 - P0 Blocking)

1. **Schema-Persistence Alignment**
   - **Principle:** Validation constraints MUST match persistence constraints. If DB is unconstrained, schema MUST NOT add static constraints.
   - *Example (Pydantic/SQLAlchemy):* DB `String(50)` unconstrained -> schema must use `str = Field(max_length=50)`, NOT `Literal["a","b"]`
   - Automated check: Flag static constraints on fields whose DB model is unconstrained (see SS5.2).
   - **Test:** POST with values returned by read endpoints (READ-WRITE consistency).

2. **Security Vulnerabilities**
   - SQL injection, XSS, path traversal, API key logging
   - PII leakage, authentication bypass

3. **Spec Compliance**
   - All P0 requirements implemented
   - API contracts match OpenAPI spec
   - Database schema matches data dictionary

4. **Test Coverage**
   - All tests passing (make test)
   - Critical paths have test coverage
   - Edge cases covered

5. **Production Build Verification**
   - **Principle:** The build command MUST pass during QA, not just the test runner. Build failure = P0 blocker (deployment will fail).
   - *Example:* `npm run build` (runs `tsc -b`, strict type checking) vs `npm test` (Vitest, lenient types) -- test passing does NOT guarantee build passing.

### 5.2 Automated Code Review Gates

**Principle:** Automate schema-persistence alignment checks in CI/QA. Flag any static constraint (enum, literal) on a field whose persistence layer is unconstrained.

*Recommended approach -- QA review script (run during Cycle 1):*
```bash
#!/bin/bash
# scripts/qa-check-schema-alignment.sh
# Adapt grep paths to your project's schema/model locations.
SCHEMA_DIR="${1:-api/schemas}"
LITERAL_FILES=$(grep -rl "Literal\[" "$SCHEMA_DIR"/*.py 2>/dev/null)
if [ -n "$LITERAL_FILES" ]; then
    echo "Static constraints found in schemas -- verify against DB models:"
    echo "$LITERAL_FILES"
    echo "If DB field is unconstrained -> schema MUST NOT use Literal. FAIL."
    exit 1
fi
echo "No static-constraint mismatches found"
```
**When to bypass:** DB has CHECK constraints or enum column types (static constraint is warranted).

### 5.3 Recommended Verification Items (Cycle 2 - P1/P2)

1. **Code Quality**
   - Linting passes (make lint)
   - Type checking passes (npm run typecheck in frontend/)
   - No TODO/FIXME comments without tracking

2. **Error Handling**
   - Comprehensive error messages
   - Proper HTTP status codes
   - Graceful degradation

3. **READ-WRITE Consistency**
   - **Principle:** Values returned by read endpoints MUST be accepted by write endpoints.
   - Integration tests verify: "Can I POST what GET returns?" Dynamic list endpoints must have write-path validation tests.

---

## 6. E2E Testing

### 6.1 When to Run E2E Tests
- After fixing router registration or endpoint wiring issues
- After database migration changes
- Before merging features that touch both FE and BE
- As part of P0 visual verification during QA cycles

### 6.2 Infrastructure

**Principle:** E2E needs config, setup, teardown, and a runner. All config (URLs, ports, credentials, route maps) lives in one file -- never hardcode elsewhere.

*Example directory layout:*
```
e2e/
  config.py       # Single source of truth: URLs, ports, credentials, route maps
  setup.py        # Bootstrap: create user, login, create project, save session
  teardown.py     # Cleanup: delete test user, remove state
  run_all.py      # Runner (setup -> discover -> execute -> teardown)
  lib/api.py      # HTTP helpers (no curl, no shell escaping)
  tests/          # Scripted regression tests
  visual/         # Visual test definitions (YAML)
```

**Setup/Teardown Flow:** setup (poll health -> create user -> login -> save session) -> run tests -> teardown (delete user, remove state).

### 6.3 Two Test Modes

**Principle:** Combine scripted regression (CI-safe, repeatable) with interactive visual verification (real-time inspection).

| Mode | Tool | Purpose |
|------|------|---------|
| Scripted regression (CI, pre-merge) | bash/Python scripts | Repeatable, exit codes |
| Visual verification (QA, debugging) | Browser automation (e.g., Chrome DevTools MCP) | Real-time DOM/network/console inspection |

Visual test definitions (e.g., YAML step files) are instructions for QA agents, not automated tests.

### 6.4 Common Pitfalls
1. Shell escaping -- use native HTTP libraries for JSON payloads, never shell-escaped curl
2. Missing DB migrations -- verify container mounts include all migration files
3. Stale DB -- tear down volumes and recreate for fresh migrations on schema changes
4. Token/session expiry -- setup tokens have a TTL; re-run setup for long test sessions
5. Wrong route patterns -- verify FE routes and API prefixes match backend registration exactly

---

## 7. Progress Log Format

### 7.1 Terminal Updates (brief, visible)
```
[FEAT-001] Starting T-101: Create DB schema
[FEAT-001] T-101: Architect complete, spawning coder
[FEAT-001] T-101: Coder complete, spawning QA (Cycle 1)
[FEAT-001] T-101: Cycle 1 PASS, proceeding to Cycle 2
[FEAT-001] T-101: Cycle 2 PASS -- Committed & pushed
[FEAT-001] Starting T-102, T-103 in parallel (user approved)
[FEAT-001] T-102: Cycle 1 FAIL (P0: 2 issues) -- Spawning fix
[FEAT-001] T-102: Fix attempt failed -- ESCALATING
```

### 7.2 Progress Log File: `logs/build-YYYY-MM-DD-HHMMSS.md`
```markdown
# Build Log: FEAT-XXX -- Started: YYYY-MM-DD HH:MM:SS -- Branch: feat/FEAT-XXX

## Task Status
| Task | Status | Architect | Coder | QA-C1 | QA-C2 | Commit |
|------|--------|-----------|-------|-------|-------|--------|
| T-101 | Done | done | done | PASS | PASS | abc123 |
| T-102 | QA-C1 | done | done | FAIL(1) | - | - |

## Event Log
HH:MM -- T-101 Started (code-architect, no deps)
HH:MM -- T-101 Architect Complete -> files: schema.py, 001_initial.py -> spawning coder
HH:MM -- T-102 Cycle 1 FAIL -- P0: TypeError extraction.py:45 -> spawning fix
HH:MM -- T-102 ESCALATED -- fix cycle failed (N=1), user input required
```
**Debug info captured:** spawn times/durations, error messages, files touched, commit SHAs.

---

## 8. Feature Spec Template

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
### New Dependencies (R17 -- MANDATORY for any new package)
- `package-name>=X.Y.Z` -- [PyPI](https://pypi.org/project/package-name/) or [GitHub](https://github.com/org/repo) -- Purpose: [why needed]
- **HARD RULE:** Every dependency MUST have an installable name + URL. "Or equivalent" = BLOCKER. Speculative packages = BLOCKER. Architect MUST `pip install`/`npm install` to verify before BUILD.
## Tasks mini-spec template
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
```

**Generation:** Feature specs following this template are produced by the `eng-planning` skill (`/eng-planning [prd-path]`). Manual creation is also valid but must follow this template exactly. All specs MUST include YAML frontmatter for the spec-registry:

```yaml
---
domain: <feature-domain>
skills: [<relevant-skills>]
schemas: [<relevant-schema-paths>]
---
```

### Task Dependencies Graph
```
T-101 (no deps)
    +-- T-102 (depends on T-101)
    +-- T-103 (depends on T-101)
T-104 (no deps, can run parallel with T-101)
```

### Task Mini-Spec Rules
Every T-XXX MUST have Priority, Depends On, Objective, Requirements, Build Guidance, Acceptance Criteria, Edge Cases, Test Plan. `Build Guidance` must be SPECIFIC (patterns, classes, utilities to use) -- NOT generic principles. `Depends On` is authoritative -- architect validates but cannot override spec. Tasks are the unit of work: each gets its own architect->coder->QA cycle.

### Schema Design Spec Language (Example)
```markdown
**Requirements:**
- [P0] Filter values (stage, sector, geography) are database-driven via `/api/filters` endpoint
- [P0] Schemas MUST NOT use Literal types for these fields -- use unconstrained str with Field constraints
- [P0] Frontend MUST fetch filter values from API, never hardcode them

**Build Guidance:**
- In `api/schemas/company.py`: Use `stage: str = Field(..., min_length=1, max_length=50)` NOT `Literal`
- Verify schema matches DB model: `api/db/models.py` uses `String(50)` -> schema uses `max_length=50`
- Add integration test: POST with values from GET `/api/filters` (READ-WRITE consistency)
```

---

## 9. Definition of Done

- [ ] All T-XXX tasks pass 2 QA cycles each
- [ ] All tests pass (`make test`)
- [ ] Lint passes (`make lint`)
- [ ] User approval gate for merge

---

## 10. Kickoff Checklist

1. Verify repo commands exist; update `CLAUDE.md`
2. Create `.claude/phase.json` with `DISCOVERY` if missing
3. Start Master PRD interview using `AskUserQuestion`
4. Do not write code until phase = `BUILD`

---

## 11. Escalation Message Template

```
ESCALATION: T-XXX (FEAT-XXX)

Failed After: 1 fix attempt
Cycle: 1 (Hard Gate) | 2 (Soft Gate)
Blocker:
- P0: <file:line> -- <issue description>

Attempted Fix:
- <what was tried>
- Error: <result>

Options:
1. Provide guidance and I'll retry
2. You fix manually, I'll continue
3. Skip this task, proceed with others
4. Abort feature

Relevant Files:
- <file:line>
```

---

## 12. Debugging Protocol (Case Study)

For rules and skill invocation order, see protocol SS3.6.

**Anti-Pattern (DON'T DO THIS):**
1. See error message
2. Make assumption about cause based on error message alone
3. Immediately change code/schema/data
4. Create cascading problems or fix wrong thing

**Correct Pattern (DO THIS):**
1. **See error** -- Capture full error message, stack trace, context
2. **Investigate thoroughly:**
   - Check git history: When did it last work? What changed?
   - Review test suite: How do existing tests handle this? Do they pass?
   - Read design docs: What was the original intent? (PRD, architecture, ADRs)
   - Sample data files: Is data inconsistent with schema/contract?
   - Check schema vs API contract vs loader code: Which is correct?
   - Look at usage patterns: How many instances fail vs succeed?
3. **Form hypothesis with evidence** -- Not guesses, use concrete file paths and line numbers
4. **Present root cause analysis** -- Show evidence for each finding
5. **Propose fix that addresses root cause** -- Not symptoms
6. **Get approval before making changes** -- Especially for schema/data/architectural changes

**Example: Schema Mismatch Errors** -- When you see database type errors like "expected str, got list": DON'T assume schema is wrong. DO investigate: could be bad data generation, loader bug, or intentional design that data violates. Investigation checklist: (1) What do persistence models say? (2) What do validation schemas say? (3) What format is in data files? Sample 5-10 files. (4) What percentage matches vs violates? (5) When was this last working? Git log. (6) How do tests handle this field? (7) What was original design intent? Root cause determines fix: schema wrong (rare) -> fix schema + migrate; data generation wrong (common) -> fix generator + bad files; loader wrong -> fix validation/conversion; intentional mismatch -> design discussion. Escalate if unsure.

---

## 13. Installed CLI Tools (No Re-Discovery Needed)

These are installed and working. Use via Bash tool directly. Do NOT search for, re-verify, or re-discover them.

| Tool | Path | Use When |
|------|------|----------|
| `agent-browser` | `/opt/homebrew/bin/agent-browser` | Browser automation, e2e testing, web scraping |

**Example:** `Bash("agent-browser open https://example.com && agent-browser screenshot")`

**END OF TEMPLATES**
