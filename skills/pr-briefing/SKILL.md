---
name: pr-briefing
description: Generate structured PR Briefing for large PRs to guide human and AI agent reviewers. Produces parallelizable review chunks, dependency graphs, and codebase context so multiple AI agents can review independently and simultaneously.
argument-hint: "<PR-number-or-branch> [--apply]"
---

# PR Briefing Generator

Generate a structured PR Briefing that acts as a navigation map for AI agent reviewers. The briefing prioritizes files by review importance, flags risks, provides codebase architecture context, defines parallelizable review chunks with dependency graphs, and gives each chunk a concrete review checklist — so multiple AI agents can review the PR independently and simultaneously without stepping on each other.

## Arguments

- **First argument:** PR number (e.g., `53`) OR branch name (e.g., `pr/backend-agents`). If omitted, use the current branch.
- **`--apply`:** If present, update the PR description directly via `gh pr edit`. Otherwise, output the briefing for the user to review first.

## Workflow

### Phase 1: Gather Raw Data (deterministic — no judgment yet)

Run these commands to collect structured data. Do ALL of them before writing anything.

```
# 1. Identify the base branch and diff
BASE_BRANCH=main  # or whatever the PR targets
BRANCH=<from argument>

# 2. Get commit log (what was done)
git log --oneline $BASE_BRANCH..$BRANCH

# 3. Get file-level diff stats (what changed)
git diff --stat $BASE_BRANCH..$BRANCH

# 4. Get full file list with LOC per file
git diff --numstat $BASE_BRANCH..$BRANCH

# 5. Get the list of new dependencies (if any)
git diff $BASE_BRANCH..$BRANCH -- "**/requirements.txt" "**/package.json" "**/Cargo.toml" "**/go.mod"

# 6. Get import graph for critical files (for dependency graph + chunk design)
#    For each file classified as Critical in Phase 2, extract its imports:
#    Python: grep "^from \|^import " <file>
#    TypeScript/JS: grep "^import \|require(" <file>
#    Only do this for Critical Path files (max ~10), not the entire PR.

# 7. Get repo directory structure (for architecture context)
#    Run: find <repo-root> -type f -name "*.py" -o -name "*.ts" -o -name "*.tsx" | head -100
#    Or: tree -L 3 -d <repo-root>/src (or backend/, frontend/, lib/)
#    Purpose: understand the top-level directory layout so you can write the Architecture section.
```

### Phase 2: Classify Files (deterministic sorting)

Sort every changed file into one of these buckets. Use directory paths and extensions — not content analysis — for initial classification:

| Bucket | Priority | Heuristic |
|--------|----------|-----------|
| **Critical Path** | Review first | Files in `src/`, `lib/`, `backend/` that are NOT tests, NOT migrations, NOT generated. Files with most LOC changed. Files touching auth, security, encryption, external APIs. |
| **Supporting** | Review second | Models, utilities, config files, route registrations. Lower LOC than critical path. |
| **Mechanical** | Skim | Test files (`test_*.py`, `*.spec.ts`, `*.test.tsx`), migration files, lockfiles. Follow patterns. |
| **Generated / Skip** | Skip | `__pycache__/`, `*.lock` (content), `dist/`, generated reports, screenshots, build artifacts. |

**Sorting rules:**
1. Files touching `auth`, `encryption`, `security`, `secrets` → always Critical
2. Files with `test` in path → always Mechanical (unless the PR IS a test infrastructure PR)
3. Files in `migrations/` → Mechanical
4. `package-lock.json`, `pnpm-lock.yaml` → Generated/Skip
5. `.png`, `.jpg`, `.pdf` → Generated/Skip (unless the PR is about assets)
6. Everything else → sort by LOC changed (top 30% → Critical, next 40% → Supporting, bottom 30% → Mechanical)

### Phase 2.5: Build Dependency Graph and Review Chunks

After classifying files, do this additional analysis:

1. **Build the import graph.** For each Critical Path file, read its imports (Phase 1 step 6). Record which files in this PR import from which other files in this PR. Also note imports from files NOT in this PR (external dependencies within the codebase).

2. **Identify natural chunk boundaries.** Group files that share dense internal imports into the same chunk. Files that don't import each other can be in separate chunks. Guidelines:
   - Each chunk should be 3-8 files (Critical + their direct Supporting dependencies).
   - Auth/security files are ALWAYS their own chunk (Chunk A by convention).
   - Test files get their own chunk(s), split by which implementation chunk they test.
   - If the PR spans backend + frontend, those are separate chunks by default.

3. **Determine chunk dependencies.** For each chunk, note which other chunks it depends on. A chunk "depends on" another if its files import types, functions, or constants defined in the other chunk. Mark chunks with no cross-dependencies as "independent" — these can be reviewed fully in parallel.

4. **Define review order within each chunk.** Within a chunk, order files by dependency: files that are imported by others come first (they're the "leaf" dependencies), files that import others come last (they're the "consumers"). Reviewers should read in this order.

### Phase 3: Detect Context (read project-specific files)

Check for these files and incorporate their rules into the briefing:

1. **`REVIEW.md`** at repo root — if it exists, extract the "Always Flag" and "Never Flag" sections. Reference them in the briefing's Invariants section.
2. **`docs/contracts/*.md`** — if the PR touches files that should conform to a contract, mention the contract file.
3. **Linked specs** — check commit messages for references like `FEAT-XXX`, `T-XXX`, or issue numbers. If found, read the spec at `docs/prd/features/FEAT-*.md` and extract the acceptance criteria.
4. **Codebase conventions** — scan the repo for `.claude/rules/`, `CLAUDE.md`, or `CONTRIBUTING.md` to extract key patterns (DB access patterns, error handling conventions, naming rules). These feed into the "Key Patterns to Verify" section.
5. **Existing file headers** — if the project uses `ABOUTME:` headers or similar, note the convention so agents can verify compliance.

### Phase 4: Write the Briefing

Use this exact template. Every section is mandatory — write "None" if a section doesn't apply.

```markdown
## PR Briefing

### Intent
[One paragraph: what this PR does and WHY. Derived from commit messages and linked specs.]

---

### Codebase Architecture Context

[Concise map of the repo structure relevant to this PR. An agent receiving this briefing has never seen this codebase before. Tell them where things are and how the pieces connect.]

**Repo layout (relevant directories):**
```
repo-root/
├── backend/              — [purpose, e.g., "Python API server (FastAPI)"]
│   ├── agents/           — [purpose, e.g., "AI agent subsystem: SDK, workers, events"]
│   ├── auth.py           — [purpose]
│   └── tests/            — [purpose, e.g., "pytest, uses SavepointConnection for real DB"]
├── frontend/             — [purpose, e.g., "React SPA (Vite + TypeScript)"]
│   ├── src/hooks/        — [purpose]
│   └── e2e/              — [purpose]
├── infrastructure/       — [purpose, e.g., "AWS CDK stacks"]
└── docs/                 — [purpose]
```

**How the pieces connect:** [2-3 sentences describing the data flow relevant to this PR. E.g., "Frontend calls backend REST endpoints. Backend agents/ subsystem uses Claude SDK for AI, persists results via persistence.py, streams progress via SSE events.py."]

---

### Change Map (ordered by review priority)

#### Critical Path (review these first)
- `path/to/file.py` — [One sentence: what this file does and why it matters]
[Max 10 files. If more than 10 are critical, group related files.]

#### Supporting Changes
- `path/to/file.py` — [One sentence]
[Max 15 files.]

#### Mechanical / Safe to Skim
- `path/pattern/*.py` — [Group description, e.g., "12 test files following existing patterns"]
[Group by pattern, not individual files.]

#### Generated / Skip
- `path/pattern/` — [Why these should be skipped]

---

### File Dependency Graph

[For Critical Path files only. Show what each file imports from other files in this PR, and what it imports from outside the PR that an agent needs to understand.]

| File | Imports from this PR | Imports from outside PR |
|------|---------------------|------------------------|
| `endpoint.py` | `models.py` (Agent, Mission), `sdk_runner.py` (run_agent), `persistence.py` (save_result) | `auth.py` (require_auth), `db_connection` |
| `sdk_runner.py` | `models.py` (AgentConfig), `budget.py` (check_budget) | `claude-agent-sdk` (ClaudeSDKClient) |
| `worker.py` | `sdk_runner.py` (run_agent), `events.py` (emit_event) | `rq` (job queue) |
[Only Critical Path files. Skip test files and mechanical changes.]

**Key insight for reviewers:** [One sentence summarizing the dependency direction. E.g., "models.py is the leaf — everything imports from it. Review it first. endpoint.py is the root consumer — review it last."]

---

### Suggested Review Order

[Explicit ordering with reasoning. Not just "critical first" but dependency-aware ordering.]

1. **`models.py`** — Read first. Defines all data types used everywhere else. No imports from other PR files.
2. **`persistence.py`** — Read second. Imports only from models.py. Understanding the DB schema informs all other files.
3. **`sdk_runner.py`** — Read third. Imports models.py + budget.py. Core execution logic. Must understand this before worker.py or endpoint.py.
4. **`worker.py`** — Read fourth. Calls sdk_runner.run(). Understanding the runner informs how worker errors propagate.
5. **`endpoint.py`** — Read last among critical. Imports from models, sdk_runner, persistence. Everything flows through here.

[Order MUST follow the import graph: files with no PR-internal imports first, files that import from many PR files last.]

---

### Review Chunks (for parallel assignment)

[Each chunk is an independent unit of review. Agents assigned to different chunks should NOT need to coordinate.]

#### Chunk A: [Name, e.g., "Auth & Security"]
**Files:** `auth.py`, `encryption.py`, `policy.py`
**Why independent:** Auth is consumed by other chunks but does not import from them. Can be reviewed without reading agent pipeline code.
**Depends on:** None (fully independent)
**Review order within chunk:** `encryption.py` → `auth.py` → `policy.py`

**Review checklist:**
- [ ] Verify JWT validation logic handles expired/malformed tokens with specific error types (not bare `Exception`)
- [ ] Confirm encryption key rotation is backward-compatible with existing encrypted rows
- [ ] Check that all auth-protected routes use `@require_auth` decorator, not manual token parsing
- [ ] Verify no secrets/keys are hardcoded — all must come from env vars
[Checklist items MUST be specific to the actual code in this PR. Generic items like "check error handling" are banned.]

#### Chunk B: [Name, e.g., "Agent Pipeline"]
**Files:** `models.py`, `sdk_runner.py`, `worker.py`, `endpoint.py`, `persistence.py`
**Why independent:** Core agent execution flow. Imports auth (Chunk A) but doesn't need auth internals to review.
**Depends on:** Chunk A (uses auth decorators, but interface is stable)
**Review order within chunk:** `models.py` → `persistence.py` → `sdk_runner.py` → `worker.py` → `endpoint.py`

**Review checklist:**
- [ ] Verify `sdk_runner.py` handles `TimeoutError` and `RateLimitError` distinctly — not a bare `except Exception`
- [ ] Confirm `worker.py` uses atomic job claiming (SELECT FOR UPDATE or equivalent) to prevent double-pickup
- [ ] Check that `persistence.py` uses `with db_connection() as conn:` pattern — no raw connection management
- [ ] Verify `endpoint.py` validates all user input before passing to sdk_runner
- [ ] Confirm `models.py` field names match the API contract in `docs/contracts/<feature>.md`
[Every item references specific code behavior, not generic advice.]

#### Chunk C: [Name, e.g., "Event System"]
**Files:** `events.py`, `event_processor.py`, `event_writers.py`
**Depends on:** Chunk B (uses models from models.py)
**Review order within chunk:** `event_writers.py` → `event_processor.py` → `events.py`

**Review checklist:**
- [ ] [Specific checks for this chunk's code]

#### Chunk T: [Name, always "Tests"]
**Files:** `tests/test_*.py` (split across sub-chunks if >15 files)
**Depends on:** All implementation chunks (but can be reviewed in parallel — agents just need to know WHAT is tested, not HOW the impl works)
**Split strategy:** Assign test files matching each implementation chunk to the same agent that reviewed that chunk. E.g., `test_sdk_runner.py` goes to the agent that reviewed Chunk B.

**Review checklist:**
- [ ] All tests use `SavepointConnection` for DB access — no raw connections, no connection leaks
- [ ] No mocks on internal modules — only external HTTP services (Resend, external URLs) may be mocked
- [ ] Each test file has at least one "happy path" test and one "error path" test
- [ ] Test output is pristine — expected errors are captured/asserted, not printed to stderr
- [ ] Assertions test behavior/return values, not implementation details
[Adapt these to the actual test patterns found in Phase 3.]

---

### Cross-Chunk Integration Points

[Where chunks interact. Agents reviewing one chunk need to know these boundaries exist, even if they don't review the other chunk.]

| Integration Point | Chunk A (source) | Chunk B (consumer) | What to verify |
|-------------------|-----------------|-------------------|----------------|
| Auth middleware | `auth.py` exports `require_auth` | `endpoint.py` uses `@require_auth` | If auth signature changes, all endpoints break |
| Data models | `models.py` exports `Agent, Mission` | `events.py` imports them | If model fields change, event serialization breaks |
| DB connection | `auth.py` exports `db_connection` | `persistence.py` uses it | Connection pool settings affect all consumers |
[Only list integration points between chunks — not within a chunk.]

**Cross-chunk rule:** If you find a bug at an integration point, flag it with `[CROSS-CHUNK]` so the reviewer of the other chunk is notified.

---

### Key Patterns to Verify

[Specific conventions this codebase uses. Derived from CLAUDE.md, REVIEW.md, CONTRIBUTING.md, or inferred from existing code. Agents should check that new code in this PR follows these patterns consistently.]

- **DB access:** All database operations use `with db_connection() as conn:` — never raw `psycopg2.connect()`. Functions receive `conn` as a parameter, they don't create their own.
- **Cost tracking:** Every LLM call must be followed by `record_cost_event(model, tokens_in, tokens_out, cost)`. Missing cost tracking = lost money.
- **Email:** All email sends go through Resend (`application_emails.py` or `alerts.py`). Never Supabase edge functions. If you see Supabase email code, flag it.
- **Error handling:** Catch specific exceptions (`TimeoutError`, `AuthenticationError`), never bare `except Exception`. Log the error with `logger.error()` including context.
- **File headers:** Every `.py` file must start with a 5-line `ABOUTME:` block describing the file's purpose. Check new files for compliance.
- **Config source:** Deployment-specific defaults come from `.diligent/catalog/boardroom-ai.yaml`. Env vars override. No hardcoded URLs or email addresses.
[Derive these from the actual project. Don't invent generic patterns. If you can't find documented patterns, note "No documented conventions found — infer from existing code style."]

---

### Parallelization Guide

**Maximum parallel agents:** [N, where N = number of independent chunks]

| Agent | Assigned Chunk | Estimated Effort | Prerequisites |
|-------|---------------|-----------------|---------------|
| Agent 1 | Chunk A (Auth/Security) | [S/M/L based on file count + complexity] | None — start immediately |
| Agent 2 | Chunk B (Core Pipeline) | [S/M/L] | None — start immediately |
| Agent 3 | Chunk C (Event System) | [S/M/L] | Can start immediately; note dependency on Chunk B models |
| Agent 4+ | Chunk T (Tests), split by impl chunk | [S/M/L] | Can start immediately; assign test files matching each agent's impl chunk |

**Coordination rules:**
- Agents work independently. No shared state, no cross-chunk discussion needed during review.
- If an agent finds a cross-chunk issue, they log it as `[CROSS-CHUNK: Chunk X → Chunk Y] description` in their findings.
- After all agents complete, a single agent (or human) reviews cross-chunk findings and checks integration points.

**Effort estimates:** S = <5 files, straightforward logic. M = 5-10 files or complex logic. L = >10 files or security-critical.

---

### Dependencies Introduced
| Package | Version | Verified | Source URL |
|---------|---------|----------|------------|
[If none: "None — no new dependencies."]

### Invariants (things that must NOT break)
[Pull from REVIEW.md if it exists. Otherwise, infer from the codebase.]
- [Invariant 1]
- [Invariant 2]

### Known Risks / Areas Needing Extra Scrutiny
- `file:lines` — [Specific concern with file and line reference]
[Be concrete. "Error handling could be better" is useless. "sdk_runner.py:L45-80 catches broad Exception, could mask SDK auth failures" is useful.]

### Test Coverage Summary
- [N] new test files, [M] assertions
- Missing: [specific untested paths]
[If no tests: "No tests in this PR. [Is that expected? Flag if implementation code exists without tests.]"]

---
Generated with [Claude Code](https://claude.com/claude-code) | PR Briefing Skill
```

### Phase 5: Deliver

- **Without `--apply`:** Output the briefing in a code block for the user to review. Ask if they want to apply it.
- **With `--apply`:** Run `gh pr edit <number> --body "<briefing>"` to update the PR description directly. Show the user a confirmation with a link to the PR.
- **Large briefings:** If the briefing exceeds GitHub's PR description character limit (~65,535 chars), split it: put the core sections (Intent through Change Map) in the PR description, and add the agent-specific sections (Chunks, Dependency Graph, Parallelization Guide) as a PR comment via `gh pr comment <number> --body "<agent-sections>"`.

## Edge Cases

- **PR has no implementation code** (docs-only, config-only): Still generate the briefing but note "No implementation code — review surface is documentation/config only" in Intent. Skip Review Chunks and Parallelization Guide (single agent is sufficient).
- **PR has 500+ files:** Group aggressively in Mechanical/Skip buckets. Call out the top 20 files by LOC in Critical/Supporting. Chunk the Mechanical bucket into sub-chunks by directory.
- **No REVIEW.md exists:** Skip the REVIEW.md integration. Suggest creating one.
- **Branch not pushed yet:** Use local diff against base branch. Note that the PR hasn't been created yet.
- **Small PR (<10 files):** Still generate all sections, but the Parallelization Guide may recommend 1-2 agents. Don't force artificial chunking — if the PR is a single coherent change, say "Single chunk — no parallelization needed."
- **PR spans multiple languages/stacks:** Each language/stack is automatically a separate chunk. E.g., "Chunk A: Backend (Python)", "Chunk B: Frontend (TypeScript)", "Chunk C: Infrastructure (CDK/TypeScript)".

## Anti-Patterns (don't do these)

- Don't read every file's content to classify it. Use paths and LOC for classification. Only read imports for Critical Path files (Phase 2.5).
- Don't list 50 files individually in Critical Path. Group. Max 10.
- Don't write vague risks like "could have performance issues." Be specific or don't mention it.
- Don't invent dependencies that aren't in the diff. Only list what `--numstat` shows in dependency files.
- Don't web search for package URLs. Check `requirements.txt` or `package.json` in the diff.
- Don't create artificial chunks just to fill the template. If 3 files are tightly coupled, they're one chunk. Don't split them into 3 chunks of 1 file each.
- Don't write generic review checklists. "Check error handling" is banned. "Verify sdk_runner.py catches TimeoutError distinctly from AuthenticationError at L45" is correct.
- Don't guess at codebase patterns. Derive Key Patterns from actual files (CLAUDE.md, REVIEW.md, CONTRIBUTING.md, existing code). If you can't find patterns, say so.
