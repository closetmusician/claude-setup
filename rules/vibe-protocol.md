# VIBE Protocol Core Rules

> Templates & checklists: `~/.claude/docs/vibe-manual.md`

---

## 0. Hard Gates (Non-Negotiable)

1. **R0 Zero Assumption** -- Never guess requirements. `AskUserQuestion` until explicit confirmation.
2. **R1 Spec Wall** -- No code without an approved spec in `docs/`.
3. **R2 TDD** -- No implementation without a corresponding failing test.
4. **R3 Mock-First Parallelism** -- FE agents MUST mock API responses (conforming to contract per R7). Never block on BE.
5. **R4 2 QA Cycles** -- No merge without 2 documented review passes.
6. **R5 Phase Gates** -- Respect `.claude/phase.json`; no code until phase = `BUILD`.
7. **R6 Auto-Commit** -- `git add -A && git commit && git push` after every task completion.
8. **R7 Contract-First** -- Before BUILD, Architect produces `docs/contracts/<feature>.md` (data models, SSE schemas, endpoints, field names). All agents reference this. No inventing field names.
9. **R8 Per-Task Subagents** -- Dedicated subagent pairs per T-XXX (not per feature); prevents context exhaustion.
10. **R9 Role Separation** -- Coder and QA MUST be separate subagents.
11. **R10 QA No-Edit** -- QA NEVER edits implementation code; only writes QA artifacts.
12. **R11 Review Snapshot** -- Coder commits `qa/FEAT-XXX/T-XXX-ready-for-review.md` with `ReviewCommit:<SHA>`; QA reviews that SHA.
13. **R12 STOP Boundaries** -- Each subagent produces artifact(s) then STOPs. Orchestrator decides next spawn.
14. **R13 N=1 Escalation** -- After 1 failed fix cycle, STOP and ask the user.
15. **R14 Orchestrator Non-Implementation** -- Orchestrator coordinates + merges; never implements.
16. **R15 History Rewrite Lock** -- Once any review artifact exists: no rebase, no force-push; only append commits.
17. **R16 User Approval Gates** -- Confirm via `AskUserQuestion` before parallel execution, PR creation, final merge, or skipping a task.
18. **R17 Dependency Verification** -- Every spec dependency needs: exact package name, URL, min version. Verify installable before BUILD. "Or equivalent" is a hard blocker.
19. **R18 Real Testing** -- Real DB (SavepointConnection), real APIs. No mocks on internal modules. Mock only external HTTP. Mocking entire core dependency = P0. Pristine test output. No `git stash` in parallel agents.
20. **R19 Spec-Diff** -- Before completing any item: enumerate each spec requirement, cite file:line evidence. "File exists" / "agent reported done" is not evidence.

---

## 0.1 VIBE Levels

Set `"vibe_level"` in `.claude/phase.json`. Default: `"full"`.

| Gate | `full` | `light` |
|------|--------|---------|
| R0 Zero Assumption | Yes | Yes |
| R1 Spec Wall | **Yes** | No |
| R2 TDD | Yes | Yes |
| R3 Mock-First | Yes | N/A |
| R4 2 QA Cycles | **Yes** | 1 pass |
| R5 Phase Gates | **Yes** | No |
| R6 Auto-Commit | Yes | Yes |
| R7 Contract-First | **Yes** | No |
| R8-R16 | Yes | Skip |
| R17 Dep Verification | Yes | Best-effort |
| R18 Real Testing | Yes | Yes |
| R19 Spec-Diff | **Yes (documented)** | Yes (inline) |

**`full`** -- Production apps. **`light`** -- Tooling, scripts, config repos.

---

## 1. Context Detection

| Branch | Role Mode |
|--------|-----------|
| `main` / `master` | **Management** (PO / Architect / Orchestrator) |
| `feat/*` or in `wt/` | **Production** (Developer / QA) |

---

## 2. Phase Gates

| Phase | Allowed Actions |
|-------|-----------------|
| `DISCOVERY` | Interview, read-only analysis, docs/specs only |
| `ARCHITECTURE_APPROVED` | eng-planning: arch docs, contracts, FEAT design docs |
| `FEATURE_SPECS_APPROVED` | Specs finalized, ready for BUILD |
| `BUILD` | Implementation allowed |

**eng-planning** spans ARCHITECTURE_APPROVED -> FEATURE_SPECS_APPROVED. Human approval transitions to BUILD. At `light` level, optional.

---

## 3. Roles

### 3.1 PM Interviewer
**Trigger:** Project/feature start. `AskUserQuestion` until scope, constraints, success metrics, edge cases all explicit. Output: PRD or FEAT design doc.

### 3.2 Architect (Feature-Level)
**Trigger:** PRD approved, phase = ARCHITECTURE_APPROVED. Invoke `eng-planning` (`/eng-planning [prd-path]`):
1. Explore codebase, challenge scope, surface design decisions via AskUserQuestion
2. Produce: arch docs, API contracts (R7), FEAT design docs with task mini-specs, failure modes
3. Verify dependencies installable (R17)
4. Spawn `/plan-eng-review` for independent tech review
5. If UI feature: spawn `/plan-design-review` for design dimension scoring (0-10)
6. Auto-fix specifiable issues (max 2 iterations); surface REQUIRES_DECISION to user

**Two-tier:** eng-planning runs ONCE per FEAT. `code-architect` runs per-task within orchestration loop (SS4).

### 3.3 Developer
**Trigger:** `feat/*` worktree, phase = BUILD, assigned T-XXX.

**Invoke IN ORDER:** `superpowers:test-driven-development` -> `superpowers:verification-before-completion`

Steps: Context load -> Dependency check (R17) -> Follow Build Guidance -> TDD loop -> Real testing (R18) -> Output `T-XXX-ready-for-review.md` with `ReviewCommit:<SHA>` (R11).

### 3.4 QA Auditor
**Trigger:** Developer claims T-XXX complete. QA NEVER edits implementation code (R10).

**Invoke IN ORDER:** `garry-review` -> `feature-dev:code-reviewer` -> `/qa`
**Also read:** `~/.claude/docs/vibe-manual.md` SS5 (QA verification checklist + automated review gates).

**Auto-Reject (P0):** mock on internal module | no SavepointConnection | test without real path | uncaptured warnings (P1) | entire core dependency mocked
**Severity:** P0 = must fix. P1 = should fix, escalate if stuck. P2 = log to `docs/backlog.md`.

**2 cycles, sequential** (C1 must PASS before C2):
- **C1 (Security & Logic, P0 gate):** garry-review -> code-reviewer -> /qa. Verify contracts (R7), auto-reject criteria (R18). Output `T-XXX-cycle-1.md`.
- **C2 (Quality & Resilience):** naming, duplication, edge cases, failure modes. Output `T-XXX-cycle-2.md`.

Re-run failing cycle after fix. N=1 escalation (R13).

### 3.5 Orchestrator
**Trigger:** `main/master`. Invoke `lead-orchestrator` skill FIRST. Never implements (R14). Spawns subagent pairs per T-XXX. Verify dependencies before spawning coders (R17). Commit + push after QA pass (R6). Merge only with user approval (R16).

### 3.6 Debugging
**Invoke IN ORDER:** `/investigate` (5-phase root-cause, auto-freeze, 3-strike escalation) -> `superpowers:systematic-debugging` (fallback).
Root cause only -- never fix symptoms. See manual SS12 for detailed debugging protocol and case study.

---

## 4. Per-Task Orchestration

### 4.1 Deterministic Loop

Subagents share NO context -- communication via committed artifacts under `qa/FEAT-XXX/`.

```
For each T-XXX (respecting depends_on):
  1. ARCHITECT (skip if trivial): spawn code-architect -> file-level design -> STOP
  2. CODER: spawn feature-dev -> TDD -> T-XXX-ready-for-review.md -> STOP
  3. QA C1 (P0 gate): spawn code-reviewer -> garry-review + code-reviewer + /qa
     -> T-XXX-cycle-1.md -> STOP
  4. IF C1 FAIL: fix -> re-run C1 -> if still fail ESCALATE (N=1)
  5. QA C2: spawn code-reviewer -> quality checks -> T-XXX-cycle-2.md -> STOP
  6. IF C2 FAIL: fix P1 (P2 -> backlog) -> re-run C2 -> if still fail ESCALATE
  7. ON PASS: git add -A && git commit && git push; update progress log
```

**Skip Architect:** setup/config, bash commands, rote tasks, or Build Guidance already file-level specific.

### 4.2 Spawning Model

**Within-task (architect -> coder -> C1 -> C2): FOREGROUND (blocking).** Each step waits for prior artifact.
**Cross-task independent pipelines: BACKGROUND (`run_in_background: true`).** Orchestrator monitors artifacts.
**Rule:** C1 and C2 are always sequential -- C2 depends on C1's findings.

### 4.3 Parallelism & Commits

**Lane Model:** Main worktree = Orchestrator. Feature lanes = `../wt/FEAT-001`, `../wt/FEAT-002`, etc. Features must be independently testable, minimal coupling, mergeable in any order (or define dependency order).

- Parse `depends_on` from mini-specs; independent tasks can run in parallel (ask user first, R16).
- Parallel tasks run in SAME feature worktree, isolated subagent contexts.
- **Pre-flight conflict check:** Architect identifies files each task modifies. If overlap -> warn user. If no overlap -> safe to parallel. If overlap approved -> orchestrator handles merge during serialization.
- **Commit serialization:** Queue ordered by dependencies. First completed task commits immediately. Subsequent tasks pull latest first; auto-merge on conflict; ESCALATE if merge fails (N=1).
- Feature complete: ask user to merge -> `git merge --squash` -> full suite -> log decisions -> cleanup.

---

## 5. Escalation & User Gates

**N=1 Rule:** QA fail -> fix -> re-run. If fix fails -> ESCALATE immediately. See manual SS11 for escalation message template.

| Gate | When |
|------|------|
| Parallel execution | Before 2+ simultaneous tasks |
| PR creation | Before `gh pr create` |
| Final merge | All tasks passed QA |
| Skip task | During escalation |
| Any escalation | Always wait for user |

---

## 6. Schema Design

Validation constraints MUST mirror persistence constraints. No static enums/literals on dynamic or extensible fields. See manual SS8.2 for spec language examples.

---

## 7. Output Discipline

State: (1) Phase, (2) Role, (3) Next Actions, (4) Questions, (5) Artifacts to Update.

---

## 8. Subagent Mapping

| Phase | Subagent Type | Mandatory Skills | Output |
|-------|---------------|-----------------|--------|
| **Orchestrate** | `lead-orchestrator` | N/A -- **never feature-dev** | Task coordination |
| Explore | `feature-dev:code-explorer` | N/A | Patterns, dependencies report |
| Architect (Feature) | `eng-planning` | + `/plan-eng-review`; if UI: + `/plan-design-review` | Arch docs, contracts, FEAT design docs |
| Architect (Task) | `feature-dev:code-architect` | N/A | Files to create/modify, test mapping |
| Implement | `feature-dev:feature-dev` | `superpowers:test-driven-development` then `superpowers:verification-before-completion` | Code + tests + `T-XXX-ready-for-review.md` |
| QA | `feature-dev:code-reviewer` | `garry-review` -> `feature-dev:code-reviewer` -> `/qa` | `T-XXX-cycle-1.md`, `T-XXX-cycle-2.md` |
| Debug | `/investigate` | Fallback: `superpowers:systematic-debugging` | Diagnosis + fix |
| Fix Bugs | `feature-dev:feature-dev` | Same as Implement | Targeted fixes |

**WARNING:** `feature-dev:feature-dev` is CODER only. Use `lead-orchestrator` when orchestrating.

---

## 9. Plugin Usage

`/feature-dev`: structured discovery -> planning -> implementation. `/code-review`: QA gate. `/qa`: diff-aware testing + regression generation. `/investigate`: root-cause debugging. `/plan-eng-review`: arch review. `/plan-design-review`: design review (UI features).

---

## 10. Integration & Merge

All tasks pass QA + user approval -> `git merge --squash` -> full suite -> log decisions -> cleanup branch/worktree.
