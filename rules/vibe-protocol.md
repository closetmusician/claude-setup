# VIBE Protocol — Hard Gates & Loop (quick reference)

Applies ONLY in repos with `.claude/phase.json`. Full manual: `~/.claude/docs/vibe-manual.md`.
Orchestration mechanics + prompt templates: `~/.claude/skills/lead-orchestrator/` (invoke the skill).

## Context (branch → role mode)
`main`/`master` = Management (PO / Architect / Orchestrator — never implement, R14).
`feat/*` or inside `wt/` = Production (Developer / QA).

## Hard Gates (non-negotiable)
- **R0 Zero Assumption** — never guess requirements; AskUserQuestion until explicit.
- **R1 Spec Wall** — no code without an approved spec in `docs/`.
- **R2 TDD, two layers** — QA Test Writer commits acceptance tests RED first (sentinel `.gate-pre-coder`); Coder writes unit tests RED → minimal GREEN for both. No evidence & no TDD-EXEMPT ⇒ P0 reject.
- **R3 Mock-First Parallelism** — FE mocks API responses conforming to contract; never block on BE.
- **R4 QA cycles** — 2 documented passes (`full`) / 1 (`light`) before merge.
- **R5 Phase Gates** — respect `.claude/phase.json`; no code until phase = BUILD.
- **R6 Auto-Commit** — after every task completion: `git status` → stage explicitly (`git add <paths>` or `git add -u`; NEVER `git add -A` — the safety hook denies it) → commit → push. RED/GREEN micro-commits encouraged.
- **R7 Contract-First** — `docs/contracts/<feature>.md` before BUILD; no invented field names.
- **R8 Per-Task Subagents** — dedicated pairs per T-XXX.
- **R9/R10** — Coder ≠ QA; QA never edits implementation code (QA test files are QA artifacts, not coder TDD evidence).
- **R11 Review Snapshot** — `qa/FEAT-XXX/T-XXX-ready-for-review.md` with `ReviewCommit:<SHA>`.
- **R12 STOP Boundaries** — each subagent produces artifact(s), then STOPs; orchestrator decides next spawn.
- **R13 N=1 Escalation** — one failed fix cycle → STOP and ask Yu-Kuan (message template: manual §11).
- **R14** — Orchestrator never implements. **R15** — once review artifacts exist: no rebase/force-push, append only.
- **R16 User Approval Gates** — before: parallel execution, PR creation, final merge, skipping a task, any escalation.
- **R17 Dependency Verification** — exact package/URL/min-version, verified installable before BUILD; "or equivalent" is a blocker.
- **R18 Real Testing** — real DB (SavepointConnection), real APIs; mock ONLY external third-party HTTP; mocking a core internal dependency = P0; pristine output; no `git stash` in parallel agents.
- **R19 Spec-Diff** — completion requires per-requirement file:line evidence; "file exists"/"agent said done" is not evidence.
- **Schema parity** — validation constraints MUST mirror persistence constraints; no static enums/literals on dynamic/extensible fields (examples: manual §Schema Design).

## Levels (`vibe_level` in `.claude/phase.json`; default `full`)
| Gate | full | light |
|---|---|---|
| R1 Spec Wall, R5 Phase Gates, R7 Contract-First | Yes | No |
| R4 QA cycles | 2 | 1 |
| R8–R16 | Yes | Skip |
| R17 | Yes | Best-effort |
| R0, R2, R3, R6, R18, R19 | Yes | Yes (R19 inline) |
`full` = production apps. `light` = tooling, scripts, config repos.

## Phases
DISCOVERY (interview/docs only) → ARCHITECTURE_APPROVED (eng-planning: arch, contracts, FEAT docs) → FEATURE_SPECS_APPROVED → BUILD (implementation allowed). Human approval moves to BUILD.

## Per-Task Loop (skeleton — full mechanics in lead-orchestrator skill)
```
For each T-XXX (respecting depends_on):
  1. ARCHITECT (code-architect; skip if trivial/file-level guidance exists) → STOP
  2. QA-TEST-WRITER → acceptance tests from PRD/design ACs, run MUST FAIL, commit RED → STOP
  3. PRE-CODER GATE: validate artifact; suite exit != 0 (genuinely RED); log RED SHA
     (sentinel .gate-pre-coder ON before, OFF after; $STATE = <root>/.agents/claude-governance)
  4. CODER (TDD inlined in coder-prompt.md) → GREEN for acceptance+unit → ready-for-review + ReviewCommit → STOP
  5. PRE-QA GATE: TDD evidence, suite green, commit ordering
  6. GARRY-REVIEW → findings → STOP; P0/P1 ⇒ coder fix → STOP
  7. QA C1 (run suite + write tests + try to break) → cycle-1 report → STOP
  8. C1 FAIL ⇒ fix → re-run C1; still failing ⇒ ESCALATE (N=1)
  9. QA C2 (`full` only): real e2e hitting real DB + regression; do NOT re-test C1 bugs → cycle-2 → STOP
 10. PASS ⇒ stage explicitly + commit + push; update progress log
```
Severity: P0 = must fix (blocks) · P1 = should fix, escalate if stuck · P2 = log to `docs/backlog.md`.
Within-task: FOREGROUND sequential. Cross-task independent pipelines: background, artifact-monitored, user-approved (R16). QA artifacts live in `qa/FEAT-XXX/` (+`runs/`); ephemeral — squash-merge removes them.
Subagents MUST persist intermediates (notes, partial analyses, digests) to `docs/temp/` or `$STATE` — never hold them only in context; compaction destroys in-context state mid-pipeline.

## Subagent models per role
Explore / code-architect / coder / QA = **sonnet**; audit, garry-review, synthesis, final verification = **opus**. Override only on user request.

## Roles, subagent/skill mapping, merge flow → lead-orchestrator skill (`~/.claude/skills/lead-orchestrator/SKILL.md`, feature mode = the full VIBE pipeline); escalation template → manual §11.
Debugging: `/investigate` first; `superpowers:systematic-debugging` only if that plugin is enabled.
Output discipline each turn: state Phase, Role, Next Actions, Questions, Artifacts to Update.
