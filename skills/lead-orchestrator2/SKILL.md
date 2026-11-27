---
name: lead-orchestrator2
description: The default for ALL orchestration and heavy coding work (owner, 2026-11-17). Use for 'build this feature', 'implement the plan', 'orchestrate', 'fan out N agents', 'spawn agent teams', 'max parallel subagents', 'work through the backlog', audits, multi-doc research, and live-site debugging. Feature mode runs arm D as a Workflow script - Codex spec fix, code only, Codex review with one row per REQ, up to 2 fix rounds, no TDD. Also has backlog, investigate-audit and live-debug modes. Use lead-orchestrator only when the user names it. NOT for Tier 0/1 work (a small fix, or one medium job for one worker).
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
This skill is Tier 2. A Tier 0 or Tier 1 ask (CLAUDE.md) leaves the skill: do it in the session or with one worker, with the checks the CLAUDE.md weight table names.
- A new feature or a multi-file code change goes to `feature` mode. The full pipeline runs with no shortcuts.
- A small fix (1-2 files, no new behaviour) is Tier 0. The session does it itself, with the checks the CLAUDE.md weight table names (arm D, no TDD).

### Mode routing (first match wins)

| Signal in the ask | Mode | Runs as |
|---|---|---|
| A bug report: "debug and fix" with failing tests, and no live app or browser needed to reproduce | `feature` via Debug and fix | one opus diagnoser Agent first (see Debug and fix), then `lo-feature-plan.js` → `lo-feature-task-d.js` per task → `lo-feature-task-d.js` with `close: true` |
| Spec'd feature tasks: repo has `.claude/phase.json`, or user demands the TDD pipeline | `feature` | `workflows/lo-feature-plan.js` once, `lo-feature-task-d.js` per task, then its `close: true` run once (on a TDD ask: `lo-feature-task.js`, `lo-feature-close.js`) |
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
3. Run F1, F2 and F3 below. The close stage reviews the whole feature diff against every REQ, so a missed root cause stays an open P0/P1.

Read `.claude/phase.json` (`vibe_level`, default `full`). Decide the architect gate per task (same rule as lead-orchestrator: skip for rote or file-level-specific tasks; require for new components, 3+ files with non-obvious integration, data-model changes, or an ambiguous approach). `mkdir -p qa/FEAT-XXX/runs`. Record `BASE_SHA=$(git rev-parse HEAD)`.

**Step F1: decomposition check.** Write the task list (task_id + mini_spec). Each mini_spec restates every spec line it owns; never narrow a spec line (tip-001: the spec said all 3 outputs get cards, the mini_spec said the `.md` gets only the table). Then:
Copy each workflow script into `<run_dir>` first, because the Workflow tool loads a script only inside the working folder.
```
Workflow({scriptPath: "<run_dir>/lo-feature-plan.js",
  args: {repo, feat_id, spec_path, run_dir, tasks: [{task_id, mini_spec}]}})
```
An opus agent maps every spec requirement to the tasks that fully cover it. `fix` = `unmapped` is not empty: widen or add tasks, then launch the plan again (max 2 launches; a second `fix` → name the unmapped requirements in the report and go on). Pass each task its `task_req_maps[task_id]` as `req_map`. Keep `feature_reqs` for F3.

**Step F2: one launch per task (arm D, owner 2026-11-15).** Launch every task that has no unmet dependency and no file overlap in the same turn.
Copy `lo-feature-task-d.js` into `<run_dir>` first (see Step F1).
```
Workflow({scriptPath: "<run_dir>/lo-feature-task-d.js",
  args: {repo, feat_id, task_id, task_label, req_ids, requirements, design, run_dir, base_ref, test_env, golden_ref, codex, smoke_cmd?, suite_cmd?}})
```
`smoke_cmd` (optional) is the command that runs the changed code path for real. The coder runs it once after coding.
`suite_cmd` (optional) is the test command to compare. The workflow runs it at `base_ref` and at HEAD. Put absolute paths to gitignored local inputs (data files, rosters) in `test_env`, because the base worktree does not have them.
Stages: `armd-spec.sh` (Codex spec fix, one round) → opus resolver only on a P0/P1 → coder (code only) → `armd-review.sh` (Codex review, REQ rows) → opus verifier only on a Codex P0 → fix round 1, round 2 only for a P0/P1 still open → `armd-final.sh`. 3-6 agents per task. Codex checks the spec once. Any P0/P1 left goes to one opus resolver, which settles it in the design from `golden_ref` and the files it names, then the coder starts. Codex is never asked again. P2 points are the coder's choice. The task escalates only if a point needs the owner (spend, outward-facing, or a recorded owner decision). Name the explainer and eng plan paths in `golden_ref`. The TDD script `lo-feature-task.js` stays only for a job where the owner asks for TDD.
`run_dir` is the absolute `<repo>/qa/FEAT-XXX/<task>` path. It must sit inside the repo, because Codex `--write` can write only there. `golden_ref` says what "correct" is. `codex` is the absolute path to `codex-companion.mjs`.

TDD variant, only when the owner asks for TDD on a job: The script runs, in await order: architect (if `arch_needed`) → QA acceptance-red → **GATE-RED** (validate-artifact.sh exit 0, suite exit non-zero, the tail shows an assertion failure and no collection/import/syntax error, 7-40 hex RED SHA, RED commit touches test files only; else one QA re-run, then escalate) → coder (`MODE=feature`, RED SHA filled, plain `ReviewCommit: <sha>`, SHAs copied from `git log`) → **GATE-GREEN** (validate-artifact.sh, verify-tdd-evidence.sh, suite: all exit 0; else one fix, then escalate) → garry-review (P0/P1 → fix → GATE-GREEN → review, max 1 loop) → QA cycle-1 → cycle-2 (`full` only) → verifier (max 2 rounds). Every findings fix starts with a test-only `FixRed: <sha>` commit that adds a test case or assertion; the fix gate checks it. Each review/QA/verify artifact passes a haiku `validate-artifact.sh` check before the script reads its verdict.

**Step F3: ALWAYS run the feature close** after every task launch has returned, whatever the statuses. It is not skippable, also not in a headless run.
Close = the same arm D workflow with `close: true` (owner, 2026-11-15). It skips spec and code. One read-only Codex review covers the whole feature diff (`base_ref` = BASE_SHA) against every feature REQ. Then up to 2 fix rounds for a P0/P1 with a repro. With `suite_cmd`, the workflow compares the suite at `base_ref` and at HEAD before the review. Each regression joins the fix list as `SUITE-REG`. An inconclusive compare blocks `complete`. After a fix, the Final stage compares again. Without `suite_cmd`, no suite runs. There is no mutation probe.
```
Workflow({scriptPath: "<run_dir>/lo-feature-task-d.js",
  args: {close: true, repo, feat_id, task_id: "T-ALL", task_label: "<feature> close", req_ids: <all feature REQs>,
         requirements, design, run_dir: "<repo>/qa/FEAT-XXX/close", base_ref: BASE_SHA, test_env, golden_ref, codex,
         unmapped: plan.unmapped.map((q) => q.req_id), smoke_cmd?, suite_cmd?}})
```
`complete` = no P0/P1 open after the last review. Else `partial` with the open items. The TDD close `lo-feature-close.js` runs only when the owner asks for TDD on a job.

**Waves:** for a plan file with waves, check `**Reviewed:** YES` / `**Status:** APPROVED` (missing at `full` → AskUserQuestion), build the dependency graph, and launch every task with no unmet dependency and no file overlap at once, in the same turn. Do not ask the owner first (owner, 2026-11-17). Do not wait for one task before you launch an independent one. While a wave runs, prepare the blocked tasks: spec drafts and plan checks for later waves. Progress note per wave. F3 runs once, after the last wave.

## MODE: backlog (launch `lo-backlog.js`, one wave per launch)

Enumerate items. Promote any item that needs design or touches 3+ files with non-obvious integration to `feature`. Group the rest into waves with no shared files (the script rejects an overlap).

```
Workflow({scriptPath: "<run_dir>/lo-backlog.js",
  args: {repo, run_dir, spec_path, test_cmd, golden_ref, qa_cycles, items: [{id, description, files: [...], req_map?}]}})
```
Coders get the sanctioned backlog `GOVERNANCE_EXEMPT` line and `MODE=backlog`. Only when the owner asks for tests or TDD on this job: unit tests stay RED-first. Cycle-1 runs when `qa_cycles >= 1`. The wave verifier always runs. Check off a backlog item ONLY if it is in `verified_items`.

## MODE: investigate-audit (launch `lo-audit.js`)

State the scope (≤2 lines: lanes → synthesis → verifier) and proceed. Write a lightweight scope spec under the run dir first.

```
Workflow({scriptPath: "<run_dir>/lo-audit.js",
  args: {run_dir, spec_path, scope, deliverable_path, golden_ref, req_map?, lanes: [{id, prompt, model}],
         repo?, test_dir?, test_cmd?}})
```
**Code audit** (the ask is about code, or wants repro tests): pass `repo`, `test_dir` (the repo's own test dir, relative, e.g. `test`) and `test_cmd` (the repo test command, e.g. `npm test`). Never put repro tests under the run dir, and never forbid writes to the test dir in the scope spec. Split lanes by failure path or data flow (for example: retrieval → prompt, prompt → written output, prior fixes), never one lane per file. The script then adds a `writers` lane (every writer, retry, resend, refresh, cache and fail-open filter) when you did not give one, runs an opus completeness critic after synthesis (at most one gap loop of up to 4 sonnet lanes), and runs a sonnet repro probe next to the verifier. The probe checks that each repro test sits in `test_dir`, runs under `test_cmd`, has no absolute path, fails on an assertion, and passes once the proposed fix is applied in a scratch copy. The verifier also blocks a fix that weakens a stated safety check without an argument (fix-ctx-002: B proposed to narrow the context-ask detectors).
Lane `model` is `sonnet` for extraction/search and `opus` for judgment (never `fable`). A dead lane is re-run once, then logged as a hole. The opus verifier runs AFTER synthesis and re-derives the synthesizer's claims. Deliver with per-claim tags: `[VERIFIED — verification.md #4]` / `[UNVERIFIED — reason]`. The deliverable's top part may hold an UNVERIFIED claim only with its tag inline. The return lists them in `unverified_claims`. The session never repeats an UNVERIFIED claim in a reply, status update, summary or handoff without its tag.

## MODE: live-debug (in session, no workflow)

Choice: this mode stays in-session fan-out, exactly as in lead-orchestrator. The loop needs judgment between steps (is the repro real, is the root cause right), so a fixed script adds little. Spawn with plain Agent calls, each naming `model`:
1. **Golden reference FIRST:** a working environment/commit, a spec quote, or user-stated expected output, plus the exact user-facing URL/command. None available → spend one question.
2. **Reproducer** (sonnet; browser via `~/.claude/skills/browse/bin/browse`) → repro steps + evidence in the run dir.
3. **Diagnoser** (sonnet or opus): root cause with file:line, `/investigate` discipline.
4. **Fixer** (sonnet): `~/.claude/skills/lead-orchestrator/templates/coder-prompt.md`, `{MODE}`=live-debug, first line `GOVERNANCE_EXEMPT (mode=live-debug — no acceptance-test pipeline; verifier stage still mandatory)`. Only when the owner asks for tests or TDD on this job: write the regression test RED on the bug first.
5. **Verifier** (opus, `qa-prompt.md` `{QA_PHASE}`=verify): re-runs the ORIGINAL repro on the SAME user-facing target, compares to the golden reference, runs the regression test → `verification.md`.
6. FAIL → one fix cycle (N=1) → escalate. You NEVER open the browser or edit the fix yourself.

## What to do with each return status

| `status` | Session action |
|---|---|
| `complete` | Spot-check: the verification file exists and its counts match the return. Commit (stage explicitly: the run dir artifacts + any file the agents left uncommitted; never `git add -A`). Then the `Deliverable:` report. |
| `partial` (audit holes, backlog items not verified) | Commit what is verified. Report state `partial` with each hole and unverified item named. Repeat an UNVERIFIED claim only with its `[UNVERIFIED — reason]` tag. |
| any status (`partial` or `escalate`) with `kind: 'infra'` | An agent died (model login, AWS 403, rate limit). Check the model login first (AWS SSO, rate limit). Fix it, then relaunch once with `resumeFromRunId`. Do not read the run's half-written files and redo the stage by hand. |
| `escalate` | AskUserQuestion only when the question_budget rule allows it (spend, an outward-facing action, a secret or credential, or a recorded owner decision). Otherwise the session takes the reversible default that keeps the requirements, names it in one line, and goes on. The session may relaunch a task ONCE without asking, after it fixes an infra cause or takes a reversible default. A second escalate on the same task still asks the owner. Feature task: record it, finish the other tasks, then run F3. |

**Headless note:** in a `claude -p` run, or when the user said "do not ask questions", an `escalate` never stalls the run and never ends it early. Commit the task's artifacts, continue the independent tasks, then run the feature close (F3: `lo-feature-task-d.js` with `close: true`). Its fix rounds are the one in-session fix attempt. Only its result decides done or partial. A `partial` report names every hole and every unmapped requirement.

**Resume:** after the user decides, relaunch the same `scriptPath` with `resumeFromRunId`. The unchanged prefix (the spec and code stages) comes back from cache.

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

## End of run

After the final `Deliverable:` report, run `rm -f "$STATE_DIR/.orchestration-active" "$STATE_DIR/.active"`.
A leftover `.active` turns on the old lead-orchestrator gates for later plain spawns.
Do not clear `.active` at setup. The `activate-on-orchestrator.sh` Skill hook re-creates it on every LO2 load.

## Stop routine

Run this when the user says stop, halt, kill or cancel about the run.
1. List the running work: workflows, agents, background Bash tasks, Monitors and `CronList` loops.
2. First snapshot the process tree under each background Bash task: run `ps -axo pid,ppid,pgid,lstart,command` and walk down from the task's shell pid. Keep pid, pgid and start time of every descendant. Then call `TaskStop` on each task. Call `CronDelete` (or `ScheduleWakeup` with `stop: true`) on each loop this run made.
3. Kill every process group listed in each run dir's `.run-pids`. Each record holds `<pgid> <stage> <token> <start time>`. Before any signal, read the pgid leader's start time with `ps -o lstart= -p <pgid>`. Skip the record when the time differs from the record, or the leader is gone and no group member is alive. Never signal pgid 0, 1 or your own group. Run `kill -TERM -<pgid>`, then `kill -KILL -<pgid>` after 5 s. Never kill by name alone, because another run may use the same scripts.
4. Kill the snapshot processes from step 2 that still run. Kill a process only when its start time still equals the snapshot. Do not walk the tree again now, because stopped shells leave reparented children.
5. Wait 30 seconds, then check again. Stop any agent that came back.
6. Remove `.orchestration-active` and `.active` from `$STATE_DIR`.
7. Report what stopped. The evidence is a check that no process group from `.run-pids` and no listed descendant is still alive. Other processes of the user do not count.
8. Start no new work until the user says go.

## Escalation & red flags

- **N=1:** a task that escalates twice asks the owner. Structural problems (missing deps, wrong architecture) escalate at once. In arm D, a spec P0/P1 goes to the opus resolver first; it escalates only if a point needs the owner.
- **Scope drift:** do not rewrite args mid-run to chase tangents. Re-anchor to the scope statement or ask.
- **One relaunch rule:** the session may relaunch a task ONCE on its own after fixing an infra cause or taking a reversible default. A second escalate on the same task still asks the owner.
- STOP if you catch yourself: editing implementation files · writing a qa/ or verification artifact · reporting "complete" without verification.md · skipping the verifier · ending a feature run without the feature close (F3).

## Reference

| Item | Path |
|---|---|
| Workflows | `~/.claude/skills/lead-orchestrator2/workflows/{lo-feature-plan,lo-feature-task-d,lo-feature-task,lo-feature-close,lo-backlog,lo-audit}.js` |
| Tests | `for t in ~/.claude/skills/lead-orchestrator2/tests/test-*.mjs; do node "$t"; done` |
| Templates (single source) | `~/.claude/skills/lead-orchestrator/templates/{coder,qa}-prompt.md` |
| Gate scripts | `~/.claude/skills/lead-orchestrator/scripts/{validate-artifact,verify-tdd-evidence}.sh` |
| Model guard | `~/.claude/scripts/governance/workflow-model-guard.sh` (every `agent()` names `model`) |
