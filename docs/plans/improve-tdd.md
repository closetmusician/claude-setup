# TDD Enforcement Improvement Plan

**Date:** 2026-05-10
**Status:** Proposed (v4)
**Source:** 3 Sonnet auditors → Opus synthesis → Codex adversarial (42 findings) → YAGNI trim → hard-gate analysis

---

## Problem

TDD in VIBE is policy fiction. The rules are well-written (R2 = "non-negotiable") but the enforcement chain is broken at every link:

1. **QA never checks for TDD evidence.** `qa-cycle1-prompt.md` auto-reject list has 5 criteria — none mention TDD. The vibe-manual says "missing TDD evidence = P0 FAIL" but the template agents actually read doesn't include it.
2. **QA never runs tests.** QA invokes `garry-review` and `code-reviewer` — both code review skills. `CommandsRun: make test` in artifact templates is a field the agent fills in, not an instruction to execute.
3. **The orchestrator can't verify TDD happened.** It waits for `T-XXX-ready-for-review.md` to exist. It never reads the file or runs any commands.
4. **No machine-enforced check exists.** Every TDD gate is instruction-based. The two machine-enforced gates (governance hooks) govern requirement coverage only. An instruction-based check depends on the agent actually following the instruction — which is the problem we're trying to solve.

---

## Fix (6 changes, 3 files)

### Phase 0 — Instruction-based gates (15 min)

All edits to `skills/lead-orchestrator/templates/qa-cycle1-prompt.md`.

**Change 1: Add TDD Evidence to auto-reject list**

After the existing 5 auto-reject criteria, add:
```
- TDD Evidence table missing or empty in ready-for-review.md with no TDD-EXEMPT declaration (R2 = P0 FAIL)
```

**Change 2: QA must run tests independently**

After the existing MANDATORY FIRST STEPS, add:
```
4. Run the test suite independently. Check Makefile for `test` target, then
   package.json `test` script, then pytest/go test as appropriate. ALL tests
   must pass — failing tests = FAIL regardless of review findings. If a test
   fails, re-run once (flaky = P1, real failure = P0). Paste the final summary
   into cycle-1.md under `## QA Test Run`.
```

**Change 3: TDD-EXEMPT scrutiny**

Add to auto-reject list:
```
- TDD-EXEMPT declared on a file whose primary purpose is executable logic
  (functions, classes, conditionals). Allowed exemptions: pure config, generated
  code, type-only files, constants, declarative route tables, migrations, docs.
  If uncertain, flag P1 for coordinator.
```

### Phase 1 — Orchestrator gates, including one hard deterministic check (20 min)

Edit `skills/lead-orchestrator/SKILL.md`. After the "No artifact = No proceed" section, add:

```
### Pre-QA TDD Verification

Before spawning QA C1, the orchestrator MUST:
1. Read `qa/FEAT-XXX/T-XXX-ready-for-review.md`
2. Verify `## TDD Evidence` table exists with at least one data row, OR every
   behavior has a `TDD-EXEMPT` declaration with justification
3. If missing: re-spawn coder with instruction "TDD Evidence table is missing —
   add RED/GREEN evidence for each behavior before resubmitting"
4. Run `make test` (or project equivalent — check Makefile, package.json,
   pytest, go test in that order). If exit code != 0, do NOT spawn QA.
   Re-spawn coder with the failing test output and instruction to fix.
```

Step 4 is the hard deterministic check. It runs actual code, checks an exit
code, and blocks progress on failure. Unlike every other check in this plan,
it does not depend on an agent choosing to follow an instruction.

**Why this matters:** QA is also told to run tests (Change 2). But QA is a
separate subagent following instructions — it might skip the step. The
orchestrator running tests itself before spawning QA means tests are verified
at two independent points: once by machine (orchestrator, hard gate), once by
instruction (QA, soft gate). If QA skips its test run, the orchestrator already
caught test failures.

### Phase 2 — TDD ordering verification (optional, adds workflow change)

Edit `skills/lead-orchestrator/templates/coder-prompt.md`. Add to the commit instructions:

```
Before your final ReviewCommit, make a separate commit containing ONLY your
test files (and test fixtures/config). Then commit your implementation. This
gives QA verifiable evidence that tests were written before implementation.

Example:
  git add tests/          # test files only
  git commit -m "T-XXX: add tests for <behavior>"
  git add src/            # implementation files
  git commit -m "T-XXX: implement <behavior>"
```

Edit `skills/lead-orchestrator/SKILL.md`. Add to Pre-QA TDD Verification:

```
5. (At `full` VIBE level) Run `git log -n 5 --name-only --pretty=format:"%h %s"`.
   Verify at least one commit touching only test files precedes the final
   implementation commit. If not found, warn but do not block — the coder may
   have legitimate reasons (refactors, shared files). Log for QA to review.
```

**Tradeoff:** This is the only check that verifies TDD ordering (tests written
before implementation), not just test existence. But it requires changing the
coder's commit workflow. It is a warn-not-block because the boundary between
"test file" and "implementation file" is fuzzy (test helpers, shared types,
fixtures in implementation directories). QA uses judgment on ambiguous cases.

---

## Enforcement layers (after all phases)

| Check | Type | What it proves | Where |
|-------|------|---------------|-------|
| TDD Evidence in auto-reject | Instruction (QA) | Evidence was produced | qa-cycle1-prompt.md |
| TDD-EXEMPT scrutiny | Instruction (QA) | Exemptions are legitimate | qa-cycle1-prompt.md |
| QA runs `make test` | Instruction (QA) | Tests pass (independent) | qa-cycle1-prompt.md |
| Orchestrator reads baton | Instruction (Orch) | Evidence exists before QA | SKILL.md |
| Orchestrator runs `make test` | **Machine (hard gate)** | **Tests pass (deterministic)** | SKILL.md |
| Test-first commit ordering | Instruction (Orch) | Tests committed before impl | SKILL.md (Phase 2) |

One machine-enforced gate. Two independent test execution points (orchestrator + QA). One ordering check. Three instruction-based artifact checks. Defense in depth without over-engineering.

---

## What we cut (and why)

| Proposal | Cut reason |
|----------|-----------|
| `[RED]`/`[GREEN]` micro-commits | Overkill. Phase 2 uses separate test/impl commits instead — lighter, same ordering proof. |
| `red_sha`/`green_sha` in TDD Evidence | Falls with micro-commits. Orchestrator runs tests and checks git log directly. |
| post-agent-audit.sh hard block | Governance hooks fire after every subagent (coder, QA, architect) with no role context. Can't reliably target coder-completion only. Orchestrator has full role context — put the gate there. |
| RED commit structural constraints | Fuzzy boundary between impl/test-helper/shared-type. QA code review handles it. |
| Production build verification | Real concern, wrong plan. Quality issue, not TDD. |
| SHA checkout verification | Enormous complexity for marginal gain. |
| Test isolation via worktree | Solving an unobserved problem. |
| Test count regression / skip detection | Over-monitoring. QA reviews tests. |

---

## Verification

After implementation, verify:

1. `grep "TDD Evidence" qa-cycle1-prompt.md` — hit in auto-reject section
2. `grep "test suite independently" qa-cycle1-prompt.md` — hit in mandatory steps
3. `grep "TDD-EXEMPT" qa-cycle1-prompt.md` — hit in auto-reject section
4. `grep "Pre-QA TDD Verification" SKILL.md` — hit in orchestration loop
5. `grep "make test" SKILL.md` — hit in Pre-QA section (the hard gate)
6. (Phase 2) `grep "test files" coder-prompt.md` — hit in commit instructions
7. **End-to-end positive:** Orchestration loop. Coder produces passing tests + TDD Evidence → orchestrator runs `make test` (pass) → QA spawned, runs tests independently.
8. **End-to-end negative:** Coder produces code with failing test → orchestrator runs `make test` (fail, exit != 0) → QA NOT spawned, coder re-spawned with error output.
9. **Evidence gap:** Coder omits TDD Evidence → orchestrator re-spawns before running tests.

---

## Provenance

v1: 576-line plan, 12 findings, 42 adversarial responses. v2: post-Codex, honest about limits. v3: YAGNI trim to 4 changes, 2 files — overcorrected by having zero machine-enforced checks. v4: added orchestrator `make test` as the one hard deterministic gate (Option B from tradeoff analysis), and separate test/impl commits as an optional ordering check (Option C). Dropped post-agent-audit.sh hook (Option A) because governance hooks lack role context to fire only on coder completion.
