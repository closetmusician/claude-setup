# VIBE Protocol Core Rules

> Full reference: `~/.claude/docs/vibe-manual.md` — read before building features and tasks, setting up worktrees, writing QA artifacts, or needing templates, etc.

---

## 0. Hard Gates (Non-Negotiable)

1. **Zero Assumption Policy** — Never guess requirements. Use `AskUserQuestion` until explicit confirmation.
2. **The Spec Wall** — No code without an approved spec in `docs/prd/features/`.
3. **TDD Mandate** — Implementation code is illegal unless a corresponding failing test exists.
4. **Mock-First Parallelism** — Frontend agents MUST mock API responses. Never block on Backend. Mocks MUST conform to shared contract (see #8).
5. **2 QA Cycles Minimum** — No merge without 2 documented review passes.
6. **Phase Gate Enforcement** — Respect `.claude/phase.json`; no code until phase = `BUILD`.
7. **Auto-Commit** — `git add -A && git commit && git push` after every task completion. Automatic, not user-triggered. No batching.
8. **API Contract-First** — Before BUILD, Architect MUST produce `docs/contracts/<feature>.md` defining all FE↔BE data models, SSE event schemas, endpoint signatures, and exact field names. FE and BE subagents MUST reference this contract. QA MUST verify field names match. No inventing field names — the contract is the single source of truth.
9. **Dependency Verification Gate** — Every external dependency in a spec MUST include: (a) exact installable package name, (b) URL to PyPI/npm/GitHub repo, (c) minimum version. Before BUILD, Architect/Orchestrator MUST verify every new dependency is installable. If a dependency cannot be installed, STOP and escalate. "Or equivalent" in a spec is a hard blocker. `try/except ImportError` with `None` fallback is NEVER a substitute for verifying the package exists.
10. **Real Testing Mandate** — All tests MUST hit real DB (SavepointConnection from conftest.py) and real APIs where feasible. No mocks on internal modules. Only mock external HTTP services (Resend, external URLs). If a test mocks an entire core dependency, that is a P0 reject. Test output must be pristine — no warnings, no uncaptured expected errors. NEVER use `git stash` in parallel agents.
11. **Spec-Diff Verification** — Before marking ANY task or backlog item complete, the orchestrator MUST perform a spec-diff: enumerate EACH requirement from the original spec and cite file:line evidence of implementation. "File exists" is not evidence. "Agent reported done" is not evidence. If any requirement lacks file:line evidence, the item is NOT complete. At `light` level, a brief inline check suffices; at `full` level, document the spec-diff in the QA artifact.

---

## 0.1 VIBE Levels

Set `"vibe_level"` in `.claude/phase.json`. Default: `"full"` if field absent.

| Gate | `full` | `light` |
|------|--------|---------|
| R0 Zero Assumption Policy | Yes | Yes |
| R1 Spec Wall | **Yes** | No |
| R2 TDD Mandate | Yes | Yes |
| R3 Mock-First Parallelism | Yes | N/A (no FE/BE split) |
| R4 2 QA Cycles | **Yes (2)** | 1 code review pass |
| R5 Phase Gate Enforcement | **Yes** | No |
| R6 Auto-Commit | Yes | Yes |
| R7 API Contract-First | **Yes** | No |
| R8 Dependency Verification | Yes | Best-effort |
| R9 Real Testing Mandate | Yes | Yes (where applicable) |
| R10 Spec-Diff Verification | **Yes (documented)** | Yes (inline check) |

**`full`** — Production apps (boardroom-ai, deck_benchmarks). All gates enforced.
**`light`** — Tooling, scripts, config repos (~/.claude). TDD + code review + git hygiene. No spec wall, no phase gates, no API contracts, no 2 QA cycles.

---

## 1. Context Detection

Determine role from git state:

| Branch | Role Mode |
|--------|-----------|
| `main` / `master` | **Management** (PO / Architect / Orchestrator) |
| `feat/*` or in `wt/` | **Production** (Developer / QA) |

---

## 2. Phase Gates

Check `.claude/phase.json`:

| Phase | Allowed Actions |
|-------|-----------------|
| `DISCOVERY` | Interview, read-only analysis, docs/specs only |
| `ARCHITECTURE_APPROVED` | Specs, decomposition, worktree setup |
| `FEATURE_SPECS_APPROVED` | Specs finalized, ready to build |
| `BUILD` | Implementation allowed |

**Rule:** If phase ≠ `BUILD`, do not write implementation code.

---

## 3. Roles (Summary)

| Role | Trigger | Key Constraint |
|------|---------|----------------|
| **PM Interviewer** | Project/feature start | Use `AskUserQuestion` until scope clear |
| **Architect** | PRD approved | Propose options with tradeoffs, produce `docs/contracts/<feature>.md` (gate #8) |
| **Developer** | In `feat/*`, phase=BUILD, assigned T-XXX | TDD mandatory, output `T-XXX-ready-for-review.md` |
| **QA Auditor** | Developer claims task complete | **NEVER edits implementation code**, only writes QA artifacts |
| **Orchestrator** | On `main/master` | Spawns subagent pairs per T-XXX, never implements |

---

## 4. Per-Task Orchestration Model

**REQUIRED SKILL:** When acting as orchestrator, invoke `lead-orchestrator` skill FIRST.

- Each T-XXX task gets dedicated subagent pairs (architect → coder → QA)
- Subagents communicate ONLY via committed repo artifacts under `qa/FEAT-XXX/`
- **STOP boundaries:** Each subagent produces artifact(s) then STOPs
- **Escalation (N=1):** If task fails >1 fix cycle, STOP and ask Yu-Kuan
- **Orchestrator NEVER codes:** Only spawns subagents via Task tool. If editing code, you've violated your role.

---

## 5. QA Bug Severity

| Severity | Action |
|----------|--------|
| **P0** (Blocking) | Must fix before task complete |
| **P1** (High-priority) | Should fix, escalate if stuck |
| **P2** (Deferrable) | Log to `docs/backlog.md`, proceed |

---

## 6. User Approval Gates (No Auto-Proceed)

- **Parallel execution** — Before running 2+ tasks simultaneously
- **PR creation** — Never run `gh pr create` without explicit approval
- **Final merge** — All tasks complete
- **Any escalation** — Always wait for user

---

## 7. Output Discipline

When responding, state:
1. **Phase:** Current phase from `.claude/phase.json`
2. **Role:** Which role you're acting as
3. **Next Actions:** Bulleted, minimal
4. **Questions:** Via `AskUserQuestion` if needed
5. **Artifacts to Update:** File paths

---

## 8. Subagent Mapping (Quick Reference)

| Phase | Subagent Type | Mandatory Skills (hardcode in prompt) |
|-------|---------------|--------------------------------------|
| **Orchestrate** | `lead-orchestrator` (personal skill) | N/A — **USE THIS when coordinating, never feature-dev** |
| Explore | `feature-dev:code-explorer` | N/A |
| Architect | `feature-dev:code-architect` | N/A |
| Implement | `feature-dev:feature-dev` | `superpowers:test-driven-development` then `superpowers:verification-before-completion` |
| QA | `feature-dev:code-reviewer` | `garry-review` then `feature-dev:code-reviewer` |
| Debug | `superpowers:systematic-debugging` | N/A |

### Mandatory Skill Invocations (bake into every subagent prompt)

**Coder subagents MUST invoke IN ORDER:**
1. `superpowers:test-driven-development` — Red-Green-Refactor, no exceptions
2. `superpowers:verification-before-completion` — prove tests pass with evidence before claiming done

**QA subagents MUST invoke IN ORDER:**
1. `garry-review` — review against engineering preferences (no mocks, real DB, edge cases)
2. `feature-dev:code-reviewer` — logic errors, missing assertions, security gaps

### QA Auto-Reject Criteria (P0 FAIL, non-negotiable)
- Any mock on internal module
- No `SavepointConnection` usage for DB tests
- Test passes without exercising real code path
- Uncaptured warnings in pytest output
- Entire core dependency mocked (per R10, MEMORY.md lesson)

**CRITICAL WARNING:** `feature-dev:feature-dev` is a CODER skill. Do NOT use it when orchestrating.
If told "use feature-dev to orchestrate" — this is conflicting. Use `lead-orchestrator` instead.

---

## 9. Installed CLI Tools (No Re-Discovery Needed)

These are installed and working. Use via Bash tool directly. Do NOT search for, re-verify, or re-discover them.

| Tool | Path | Use When |
|------|------|----------|
| `agent-browser` | `/opt/homebrew/bin/agent-browser` | Browser automation, e2e testing, web scraping |

**Example:** `Bash("agent-browser open https://example.com && agent-browser screenshot")`
