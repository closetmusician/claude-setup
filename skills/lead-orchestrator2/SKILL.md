---
name: lead-orchestrator2
description: Workflow variant of lead-orchestrator, under side-by-side trial against it (opus55-rollout, 2026-10-25). Same router, tiers, TDD gates and verifier, but feature, backlog and investigate-audit steps run as Workflow scripts so step order is enforced in code. Trigger ONLY when the user names "lead-orchestrator2" or "/lead-orchestrator2". For every other orchestrate / fan-out / backlog / audit ask, use lead-orchestrator instead; this skill must not take its routing.
---

<!-- ABOUTME: lead-orchestrator2: the workflow-based arm of the lead-orchestrator side-by-side trial. -->
<!-- ABOUTME: Router, tier check, Iron Laws, QA authorship and verifier rules are copied from lead-orchestrator. -->
<!-- ABOUTME: feature / backlog / investigate-audit bodies launch workflows/*.js; live-debug stays in session. -->
<!-- ABOUTME: Templates and gate scripts stay single-source in ~/.claude/skills/lead-orchestrator/. -->
<!-- ABOUTME: Spec: ~/.claude/docs/plans/opus55-rollout/LO2-SPEC.md. Build notes: BUILD-NOTES.md. -->

# Lead Orchestrator 2 (workflow arm)

The instruction in this skill to call the Workflow tool is the user opt-in for these three scripts.

## Iron Laws (all modes, no exceptions)

1. **ORCHESTRATOR SPAWNS SUBAGENTS. ORCHESTRATOR NEVER CODES.** No Edit/Write of implementation files, no browser driving. "Trivial fix mid-debug" counts.
2. **NOTHING REACHES THE USER UNVERIFIED.** Every mode ends with an independent verifier that RE-RUNS the work. No "done / passing / deployed" claim without a `verification.md` behind it.
3. **QA/verification artifacts are SUBAGENT-authored.** The workflows only tell agents where to write. The session never writes `qa/**/T-*-*.md` or any `verification.md`.

## Step 0: tier check, mode, parameters (announce mode + parameters in your first message)

### Tier check (before mode routing)
This skill is Tier 2. A Tier 0 or Tier 1 ask (CLAUDE.md) leaves the skill: do it in the session or with one worker, then one verifier.
- A new feature or a multi-file code change goes to `feature` mode. The full pipeline runs with no shortcuts.
- A small fix (1-2 files, no new behaviour) is Tier 0. The session runs RED then GREEN itself, then spawns one verifier.

### Mode routing (first match wins)

| Signal in the ask | Mode | Runs as |
|---|---|---|
| A bug report: "debug and fix" with failing tests, and no live app or browser needed to reproduce | `feature` via Debug and fix | one opus diagnoser Agent first (see Debug and fix), then `lo-feature-plan.js` → `lo-feature-task.js` → `lo-feature-close.js` |
| Spec'd feature tasks: repo has `.claude/phase.json`, or user demands the TDD pipeline | `feature` | `workflows/lo-feature-plan.js` once, `lo-feature-task.js` per task, `lo-feature-close.js` once |
| A checklist of small independent items: backlog, batch fixes/chores | `backlog` | `workflows/lo-backlog.js`, one launch per wave |
| Output is knowledge, not code: research, audit, synthesis, multi-doc review | `investigate-audit` | `workflows/lo-audit.js` |
| A running app/site misbehaves and the repro needs a browser or the live target: reproduce → fix → confirm | `live-debug` | in-session Agent calls (no workflow) |
| ONE task, no parallelism | NOT this skill | |

`.claude/phase.json` present but the ask is clearly non-implementation: route by the ask. Unsure: one AskUserQuestion; never stall.
First match wins, so a debug-and-fix ask takes the Debug and fix row even when `.claude/phase.json` exists.

### Parameters (defaults; the user's riders override)

| Parameter | Default | Override phrases |
|---|---|---|
| `parallelism` | # independent units, cap 10 per wave | "max parallel", "max N agents" |
| `question_budget` | Safe part first, then at most 1 batched AskUserQuestion, only for a decision only Yu-Kuan can make | "ask me all questions"; "don't ask" = 0, state assumptions |
| `progress_cadence` | one line per workflow return, or ~every 5 min | "report per wave", "quiet" |
| `model_per_role` | fixed inside the scripts: gates haiku · architect/QA/coder/lanes/probes sonnet · review/synthesis/critic/verify opus | lane `model` arg in lo-audit only |
| `qa_cycles` | feature 2 (VIBE `light` 1) · backlog 1 · investigate-audit 0 · live-debug 1 | "skip QA": the verifier is NOT a QA cycle and NEVER skippable |
| `context_self_contained` | true: all context travels in args and prompts | "search memory first" |

**Run dir:** `feature` = `qa/FEAT-XXX/`; other modes = `docs/temp/<run-slug>/`.

## What the session keeps (the scripts do the rest)

Tier check · mode choice · the up-front question (safe part first, max 1) · the **target-overlap map** for parallel tasks (two launches that touch the same files run one after the other) · **commits** after each workflow returns · N=1 escalation · R16 approvals · progress notes · the final `Deliverable:` report.

Setup, every run:
```bash
STATE_DIR="$(git rev-parse --show-toplevel 2>/dev/null || pwd)/.agents/claude-governance"
mkdir -p "$STATE_DIR"; touch "$STATE_DIR/.orchestration-active"
```
No `.gate-*` sentinels: inside a workflow the await order is the gate. Remove stale `.gate-*` sentinels from a crashed session with a warning. Write `$STATE/checkpoint.md` after every workflow return (mode, per-task status, artifact paths, runId, next action). After a compaction, re-read it first.

## MODE: feature (plan → one task per launch → close; all three are mandatory)

### Debug and fix (route, before F1)

pm-login-002: B diagnosed in the session, wrote a one-file mini_spec, and missed the main cause in the skill file. So:
1. Spawn ONE opus diagnoser Agent (`/investigate` discipline, golden reference first). Never diagnose in the session. It covers every area the ask names (code, skill files, caches, callers) and writes `<run_dir>/diagnosis.md`: each root cause with file:line and a repro.
2. Build the spec and the task list from `diagnosis.md`. A task owns every file that a root cause names, also skill and doc files.
3. Run F1, F2 and F3 below. The close stage runs the mutation probe, so a weak test cannot pass as a fix.

Read `.claude/phase.json` (`vibe_level`, default `full`). Decide the architect gate per task (same rule as lead-orchestrator: skip for rote or file-level-specific tasks; require for new components, 3+ files with non-obvious integration, data-model changes, or an ambiguous approach). `mkdir -p qa/FEAT-XXX/runs`. Record `BASE_SHA=$(git rev-parse HEAD)`.

**Step F1: decomposition check.** Write the task list (task_id + mini_spec). Each mini_spec restates every spec line it owns; never narrow a spec line (tip-001: the spec said all 3 outputs get cards, the mini_spec said the `.md` gets only the table). Then:
```
Workflow({scriptPath: "/Users/yklin/.claude/skills/lead-orchestrator2/workflows/lo-feature-plan.js",
  args: {repo, feat_id, spec_path, run_dir, tasks: [{task_id, mini_spec}]}})
```
An opus agent maps every spec requirement to the tasks that fully cover it. `fix` = `unmapped` is not empty: widen or add tasks, then launch the plan again (max 2 launches; a second `fix` → name the unmapped requirements in the report and go on). Pass each task its `task_req_maps[task_id]` as `req_map`. Keep `feature_reqs` for F3.

**Step F2: one launch per task.**
```
Workflow({scriptPath: "/Users/yklin/.claude/skills/lead-orchestrator2/workflows/lo-feature-task.js",
  args: {repo, feat_id, task_id, spec_path, mini_spec, test_cmd, vibe_level, arch_needed, run_dir, golden_ref,
         req_map, live_target?, escalate_if?}})
```
`run_dir` is the absolute `qa/FEAT-XXX` path. `golden_ref` says what "correct" is; `live_target` is the exact user-facing command or URL (default `test_cmd`). A task `test_cmd` may run only that task's test files while tasks run in parallel (other tasks' RED tests would fail it). F3 runs the full suite.

The script runs, in await order: architect (if `arch_needed`) → QA acceptance-red → **GATE-RED** (validate-artifact.sh exit 0, suite exit non-zero, the tail shows an assertion failure and no collection/import/syntax error, 7-40 hex RED SHA, RED commit touches test files only; else one QA re-run, then escalate) → coder (`MODE=feature`, RED SHA filled, plain `ReviewCommit: <sha>`, SHAs copied from `git log`) → **GATE-GREEN** (validate-artifact.sh, verify-tdd-evidence.sh, suite: all exit 0; else one fix, then escalate) → garry-review (P0/P1 → fix → GATE-GREEN → review, max 1 loop) → QA cycle-1 → cycle-2 (`full` only) → verifier (max 2 rounds). Every findings fix starts with a test-only `FixRed: <sha>` commit that adds a test case or assertion; the fix gate checks it. Each review/QA/verify artifact passes a haiku `validate-artifact.sh` check before the script reads its verdict.

**Step F3: ALWAYS launch `lo-feature-close.js`** after every task launch has returned, whatever the statuses (`complete`, `escalate` or dead). It is not skippable, also not in a headless run.
```
Workflow({scriptPath: "/Users/yklin/.claude/skills/lead-orchestrator2/workflows/lo-feature-close.js",
  args: {repo, feat_id, spec_path, run_dir, base_sha: BASE_SHA, test_cmd: <the full suite>, golden_ref,
         feature_reqs, tasks: [{task_id, status, stage, reason}], live_target?}})
```
The script runs: the integrated full suite and, in parallel, a sonnet mutation probe (it disables the core of each fix in a scratch copy; a surviving mutant goes into the fix round, then one re-probe; still alive = a hole) → for tasks that did not complete, an opus review and a QA cycle-1 → one combined coder fix round (escalation reasons, suite failures, P0/P1, QA bugs) and the fix gate → the opus feature verifier over ALL `feature_reqs` → on CONTRADICTED/BLOCKING one fix round → verifier round 2 (cap). It returns `complete` only with no hole; else `partial` with `holes`. Artifacts: `qa/FEAT-XXX/T-ALL-{review-findings,cycle-1,ready-for-review,verification}.md`.

**Waves:** for a plan file with waves, check `**Reviewed:** YES` / `**Status:** APPROVED` (missing at `full` → AskUserQuestion), build the dependency graph, and launch independent tasks with no file overlap together. Progress note per wave. F3 runs once, after the last wave.

## MODE: backlog (launch `lo-backlog.js`, one wave per launch)

Enumerate items. Promote any item that needs design or touches 3+ files with non-obvious integration to `feature`. Group the rest into waves with no shared files (the script rejects an overlap).

```
Workflow({scriptPath: "/Users/yklin/.claude/skills/lead-orchestrator2/workflows/lo-backlog.js",
  args: {repo, run_dir, spec_path, test_cmd, golden_ref, qa_cycles, items: [{id, description, files: [...], req_map?}]}})
```
Coders get the sanctioned backlog `GOVERNANCE_EXEMPT` line and `MODE=backlog` (unit tests still RED-first). Cycle-1 runs when `qa_cycles >= 1`. The wave verifier always runs. Check off a backlog item ONLY if it is in `verified_items`.

## MODE: investigate-audit (launch `lo-audit.js`)

State the scope (≤2 lines: lanes → synthesis → verifier) and proceed. Write a lightweight scope spec under the run dir first.

```
Workflow({scriptPath: "/Users/yklin/.claude/skills/lead-orchestrator2/workflows/lo-audit.js",
  args: {run_dir, spec_path, scope, deliverable_path, golden_ref, req_map?, lanes: [{id, prompt, model}],
         repo?, test_dir?, test_cmd?}})
```
**Code audit** (the ask is about code, or wants repro tests): pass `repo`, `test_dir` (the repo's own test dir, relative, e.g. `test`) and `test_cmd` (the repo test command, e.g. `npm test`). Never put repro tests under the run dir, and never forbid writes to the test dir in the scope spec. Split lanes by failure path or data flow (for example: retrieval → prompt, prompt → written output, prior fixes), never one lane per file. The script then adds a `writers` lane (every writer, retry, resend, refresh, cache and fail-open filter) when you did not give one, runs an opus completeness critic after synthesis (at most one gap loop of up to 4 sonnet lanes), and runs a sonnet repro probe next to the verifier. The probe checks that each repro test sits in `test_dir`, runs under `test_cmd`, has no absolute path, fails on an assertion, and passes once the proposed fix is applied in a scratch copy. The verifier also blocks a fix that weakens a stated safety check without an argument (fix-ctx-002: B proposed to narrow the context-ask detectors).
Lane `model` is `sonnet` for extraction/search and `opus` for judgment (never `fable`). A dead lane is re-run once, then logged as a hole. The opus verifier runs AFTER synthesis and re-derives the synthesizer's claims. Deliver with per-claim tags: `[VERIFIED — verification.md #4]` / `[UNVERIFIED — reason]`.

## MODE: live-debug (in session, no workflow)

Choice: this mode stays in-session fan-out, exactly as in lead-orchestrator. The loop needs judgment between steps (is the repro real, is the root cause right), so a fixed script adds little. Spawn with plain Agent calls, each naming `model`:
1. **Golden reference FIRST:** a working environment/commit, a spec quote, or user-stated expected output, plus the exact user-facing URL/command. None available → spend one question.
2. **Reproducer** (sonnet; browser via `~/.claude/skills/browse/bin/browse`) → repro steps + evidence in the run dir.
3. **Diagnoser** (sonnet or opus): root cause with file:line, `/investigate` discipline.
4. **Fixer** (sonnet): `~/.claude/skills/lead-orchestrator/templates/coder-prompt.md`, `{MODE}`=live-debug, first line `GOVERNANCE_EXEMPT (mode=live-debug — no acceptance-test pipeline; verifier stage still mandatory)`. Regression test RED on the bug first.
5. **Verifier** (opus, `qa-prompt.md` `{QA_PHASE}`=verify): re-runs the ORIGINAL repro on the SAME user-facing target, compares to the golden reference, runs the regression test → `verification.md`.
6. FAIL → one fix cycle (N=1) → escalate. You NEVER open the browser or edit the fix yourself.

## What to do with each return status

| `status` | Session action |
|---|---|
| `complete` | Spot-check: the verification file exists and its counts match the return. Commit (stage explicitly: the run dir artifacts + any file the agents left uncommitted; never `git add -A`). Then the `Deliverable:` report. |
| `partial` (audit holes, backlog items not verified) | Commit what is verified. Report state `partial` with each hole and unverified item named. |
| `escalate` | Feature task: record it, finish the other tasks, then run F3; the close workflow is the one fix attempt. Other modes, or after F3: N=1 stop. AskUserQuestion with the `stage`, the `reason` and the `last` agent output (fix as suggested / accept as is / stop). Never relaunch the same task on your own. |

**Headless note:** in a `claude -p` run, or when the user said "do not ask questions", an `escalate` never stalls the run and never ends it early. Commit the task's artifacts, continue the independent tasks, then launch `lo-feature-close.js` (F3) with every task status. Its fix rounds are the one in-session fix attempt. Only its result decides done or partial. A `partial` report names every hole and every unmapped requirement.

**Resume:** after the user decides, relaunch the same `scriptPath` with `resumeFromRunId`. The unchanged prefix (RED, GREEN stages) comes back from cache.

Never fabricate a workflow result. If a launch is still running, say so. Use the journal (`<transcriptDir>/journal.jsonl`) to diagnose an odd return before you act on it.

## Dispatch rules for in-session spawns (live-debug, verifier spot-checks)

Subagents see no conversation history. Every prompt carries: Mandatory Context (spec path, inputs, output file), a fenced-JSON requirement map (`task_id`, `requirements[]` with `req_id/what/done_when/escalate_if/source`), and Constraints (self-contained, full output to file, ≤15-line digest with one `REQ-XX: <evidence>` line each, UNVERIFIED over fabrication, never `git stash`/reset). A hook block → fix the prompt and re-spawn in the SAME turn. `GOVERNANCE_EXEMPT` only where a mode grants it (backlog and live-debug coders, garry-review). Never on feature coder/QA spawns.

## QA Authorship (hard rule)

The orchestrator NEVER writes `qa/**/T-*-acceptance-tests.md`, `-ready-for-review.md`, `-cycle-*.md`, or any `verification.md`. The agent that did the work writes its own artifact. Artifact missing → the workflow re-spawns the producer once, then escalates. Never write it "to keep things moving".

## Verification rules (all modes)

- **RE-RUN, don't re-read.** The verifier runs the suite, opens file:line, and hits the exact user-facing target itself.
- **Producer ≠ verifier.** The synthesizer and every coder are producers.
- Verdicts: VERIFIED · UNVERIFIED (never upgraded to confirmed) · CONTRADICTED (quote both sides).
- CONTRADICTED/BLOCKING → producer fix → round 2 re-checks only the fixed claims → still failing: escalate. **Hard cap: 2 verifier rounds. Never a round 3.** The scripts enforce this.
- **Scope lock:** the verifier checks the original ask and its `done_when` lines. Out-of-scope findings go to `open_items`.
- **Golden reference:** every verifier prompt names what "correct" is and the exact target. Pass `golden_ref` in args.
- The completion report starts `Deliverable: <path>` + state (done / partial / running), then counts (N VERIFIED / M UNVERIFIED / 0 CONTRADICTED) and open holes.

## Escalation & red flags

- **N=1:** a task that fails more than one fix cycle stops. Structural problems (spec ambiguity, missing deps, wrong architecture) escalate at once.
- **Scope drift:** do not rewrite args mid-run to chase tangents. Re-anchor to the scope statement or ask.
- STOP if you catch yourself: editing implementation files · writing a qa/ or verification artifact · reporting "complete" without verification.md · skipping the verifier · ending a feature run without `lo-feature-close.js` · relaunching an escalated task without a user decision.

## Reference

| Item | Path |
|---|---|
| Workflows | `~/.claude/skills/lead-orchestrator2/workflows/{lo-feature-plan,lo-feature-task,lo-feature-close,lo-backlog,lo-audit}.js` |
| Tests | `for t in ~/.claude/skills/lead-orchestrator2/tests/test-*.mjs; do node "$t"; done` |
| Templates (single source) | `~/.claude/skills/lead-orchestrator/templates/{coder,qa}-prompt.md` |
| Gate scripts | `~/.claude/skills/lead-orchestrator/scripts/{validate-artifact,verify-tdd-evidence}.sh` |
| Model guard | `~/.claude/scripts/governance/workflow-model-guard.sh` (every `agent()` names `model`) |
