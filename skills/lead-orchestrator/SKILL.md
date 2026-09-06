---
name: lead-orchestrator
description: Coordinates teams of parallel subagents for feature builds, backlog burn-downs, codebase/doc audits, and live-site debugging — with a mandatory independent verifier that RE-RUNS the work before any completion claim reaches the user. Four modes — feature (full TDD/QA pipeline), backlog (light), investigate-audit (fan-out + synthesize), live-debug (reproduce → fix → re-verify). Use when the user says "orchestrate", "act as orchestrator", "spawn agent teams", "max parallel subagents", "work through the backlog", "fan out N agents", or asks to execute a plan/wave file. NOT for a single task with no parallelism (do it directly or spawn one subagent), and NOT for non-engineering content synthesis with nothing to verify (plain parallel Task calls suffice).
---

# Lead Orchestrator

## Iron Laws (all modes, no exceptions)

1. **ORCHESTRATOR SPAWNS SUBAGENTS. ORCHESTRATOR NEVER CODES.** About to Edit/Write a `.py`/`.ts`/`.js`/impl file, or open a browser yourself? STOP — spawn the right subagent. "Trivial fix mid-debug" counts (worst audited violations were live-debug: 39 orchestrator edits in one session, 92e76708).
2. **NOTHING REACHES THE USER UNVERIFIED.** Every mode ends with an independent verifier subagent that RE-RUNS the work (§Verification Stage). No "done / complete / passing / deployed" claim without a `verification.md` behind it.
3. **QA/verification artifacts are SUBAGENT-authored** (§QA Authorship).

Orchestrator tools: Task (spawn) · Read/Grep/Glob (gate checks, digests) · Write (checkpoint, orchestration log ONLY) · Bash (gate/lifecycle commands: test runs for gate checks, mkdir, sentinel touch/rm) · AskUserQuestion.

## Step 0 — Pick Mode + Parameters (announce both in your first message)

### Mode routing (first match wins)

| Signal in the ask | Mode |
|---|---|
| Implementing spec'd feature tasks — repo has `.claude/phase.json`, or user demands the TDD pipeline | `feature` |
| A checklist of small independent items: "work through the backlog", batch fixes/chores | `backlog` |
| Primary output is knowledge, not code: research, audit, synthesis, codebase map, multi-doc review | `investigate-audit` |
| A running app/site misbehaves; work = reproduce → fix → confirm | `live-debug` |
| ONE task, no parallelism | NOT this skill — do it directly or spawn one subagent |

If `.claude/phase.json` exists but the ask is clearly non-implementation (audit, research, docs): route by the ask, not the file. Genuinely unsure → one AskUserQuestion; never stall.

### Parameters (defaults; the user's riders override — read their message for these)

| Parameter | Default | Override phrases |
|---|---|---|
| `parallelism` | # of independent units, cap 10 per wave | "max parallel", "max N agents" set/lift the cap |
| `question_budget` | 1 batched AskUserQuestion up front | "ask me all questions" = ask until zero ambiguity before dispatch; "don't ask" = 0, state assumptions |
| `progress_cadence` | one-line note per agent completion, or ~every 5 min in a long wave — unprompted | "report per wave", "quiet" |
| `model_per_role` | explore/extract = `sonnet` · code = `sonnet` · audit/synthesis/verify = `opus` | "use opus everywhere" etc. |
| `context_self_contained` | true — do NOT search memory/journal; all context travels inside prompts | "search memory first" = false |
| `qa_cycles` | feature 2 (VIBE `light` 1) · backlog 1 · investigate-audit 0 · live-debug 1 | "only 1 QA cycle", "skip QA" — the verifier is NOT a QA cycle and NEVER skippable |
| `temp_files` | subagents write ALL intermediates + full outputs to the run dir; return digests only | — |

**Run dir:** `feature` = `qa/FEAT-XXX/`; other modes = `docs/temp/<run-slug>/`. Governance state = `$STATE`.

## Setup (every run)

```bash
STATE_DIR="$(git rev-parse --show-toplevel 2>/dev/null || pwd)/.agents/claude-governance"   # = $STATE
mkdir -p "$STATE_DIR"; touch "$STATE_DIR/.orchestration-active"
```

- `.active` is auto-created by the `activate-on-orchestrator.sh` Skill hook — governance hooks (pre-agent-gate, orchestrator-step-gate, post-agent-audit) are LIVE in **every** mode, not just feature.
- Ensure `.agents/` is in `.gitignore`. Stale `.gate-*` sentinels from a crashed session: `rm` with a warning.
- `.orchestration-active` is cleared automatically at session end by `governance-cleanup.sh` (SessionEnd hook) — do not `rm` it manually; the ownership guard denies main-thread `rm` on non-`.gate` sentinels.

## Model routing (auto)

Before spawning each subagent, pipe a task descriptor through `scripts/route-dispatch.sh` to determine the model tier:

```bash
echo '{"intent":"<one-line task>","verb":"<main verb>"}' | ~/.claude/scripts/route-dispatch.sh
```

Use the returned tier as the Agent model param for that spawn. You no longer re-type per-role model policy; it is read from policy/route-policy.json and self-tunes from history (A6).

**Explicit override always wins.** If the task itself or the user names a tier (e.g., "use opus for this", or the role table below specifies a model), that tier is used — the dispatch call is skipped. When overriding, emit the decision so the flywheel can learn:

```bash
source ~/.claude/scripts/lib/emit-event.sh
emit_event route_decision \
  "$(jq -cn --arg sc "<subtask_class>" --arg mt "<explicit-tier>" --arg r "explicit-override" \
     '{subtask_class:$sc,model_tier:$mt,reason:$r}')" \
  source=lead-orchestrator
```

---

## Dispatch Protocol (every spawn, every mode)

Build every prompt from this 15-line skeleton (it satisfies `pre-agent-gate.sh`: Mandatory Context + fenced-JSON requirement map + Constraints). Subagents see NO conversation history and do NOT load CLAUDE.md — every rule they must obey travels in the prompt.

````markdown
You are {ROLE} for {TASK_ID} ({MODE}). {One-line objective + why it matters.}
## Mandatory Context
- **Spec:** docs/<spec>.md — read before working
- **Inputs:** <paths to Read>  ·  **Output file:** <run-dir path>
## Requirement Map
```json
{"task_id":"T-XXX","requirements":[{"req_id":"REQ-01","what":"...","done_when":"<falsifiable>","escalate_if":"...","source":"docs/<spec>.md §N"}]}
```
## Constraints
- Self-contained: everything you need is above. Do not search memory.
- Write FULL output to the output file. Return ≤15-line digest: verdict, artifact path, one `REQ-XX: <file:line/URL/command evidence>` line per requirement.
- Anything you could not verify from a primary source = mark UNVERIFIED. Never fabricate a number, quote, or status.
- Never `git stash`/reset/restore files you didn't modify. {EXTRA task-specific constraints}
````

No spec exists? Point at (or create) a lightweight `docs/*.md` first — bare `NO_SPEC_REQUIRED` is hook-blocked. If `docs/spec-registry.yaml` is missing in a VIBE repo, run `~/.claude/scripts/rebuild-spec-registry.sh`.

Heavyweight roles load a template file instead (skeleton already embedded — Read it, fill ALL `{PLACEHOLDERS}`):

| Role | Prompt source | Model |
|---|---|---|
| Coder / fixer | `templates/coder-prompt.md` — fill `{MODE}`: feature / backlog / live-debug | sonnet |
| QA (all phases: acceptance-red, cycle-1, cycle-2, verify) | `templates/qa-prompt.md` — fill `{QA_PHASE}` | cycles sonnet · verify opus |
| Explorer, extractor, architect, synthesizer | inline skeleton above | per model_per_role |
| Garry-review | inline prompt, first line `GOVERNANCE_EXEMPT` — Architecture / Code Quality / Tests / Performance, P0-P2 findings to run dir | opus |

**GOVERNANCE_EXEMPT rule:** allowed ONLY where a mode section explicitly grants it (backlog + live-debug coder spawns, garry-review inline). NEVER on feature-mode coder/QA spawns. NEVER as a way to dodge the verifier.

### When a hook blocks a spawn — fix and re-spawn in the SAME turn

`pre-agent-gate` / `orchestrator-step-gate` blocks come with a reason. Read it → fix the prompt (add the missing section, run the gate checks it names, or add the mode-sanctioned GOVERNANCE_EXEMPT line) → re-spawn immediately, same turn. Ending the turn idle after a block is a violation (≥4 audited sessions stalled this way — "why did you just sit on your hands?").
- Positive: block says "Missing requirement map" → add the fenced JSON → re-spawn in the same message.
- Negative: replying "the governance hook blocked me, awaiting instructions" and stopping.

## QA Authorship (hard rule)

The orchestrator NEVER writes `qa/**/T-*-acceptance-tests.md`, `qa/**/T-*-ready-for-review.md`, `qa/**/T-*-cycle-*.md`, or any `verification.md`. The subagent that did the work authors its own artifact. Audit evidence: every one of the 188 QA cycle files across 25 sessions (102 C1 + 86 C2) was written by the orchestrator main thread — checklist satisfied, the independence it certifies never existed (QA theater).
- Positive: QA digest says "PASS — artifact at qa/FEAT-01/T-003-cycle-1.md" → you verify the file exists and validate it.
- Negative: QA agent returned findings in its message but wrote no file, so you write cycle-1.md "to keep things moving" → theater. Re-spawn it with "artifact missing — write it" instead.

---

## MODE: feature — full VIBE pipeline (gates + sentinels intact)

Route here when: spec'd implementation tasks in a repo with `.claude/phase.json` (full protocol: `~/.claude/rules/vibe-protocol.md`), or the user demands TDD/QA pipeline.
- Positive: "act as orchestrator for FEAT-03" in a repo at phase BUILD.
- Negative: "orchestrate agents to audit these 6 PRDs for gaps" — knowledge output, no implementation → `investigate-audit`.

**Permission vs gate:** "skip permissions" / "auto-approve" = skip tool-approval dialogs ONLY — never TDD, QA cycles, sentinels, or artifacts. Uncertain → it does not mean skip; ask.

Read `.claude/phase.json` for `vibe_level` (default `full`): `light` = 1 QA cycle, no spec wall/phase gate/contracts, architect optional.

**Architect gate (per task):** skip when setup/config, rote, or the mini-spec is already file-level specific (e.g., "add the route to the existing router table per Build Guidance" — files named). Require when new components/services, 3+ files with non-obvious integration, data-model changes, or ambiguous approach (e.g., "add real-time presence", no files named). Architect uses the inline skeleton, `sonnet`, writes `qa/FEAT-XXX/T-XXX-arch.md` → that path is `{ARCH_DESIGN_PATH}` for QA/coder prompts (else `N/A`).

### Per-task loop

```
1.  [Architect gate] → T-XXX-arch.md (or skip)
2.  Spawn QA {QA_PHASE}=acceptance-red → T-XXX-acceptance-tests.md
2a. touch $STATE/.gate-pre-coder                    ← blocks coder spawns (step-gate hook)
3.  Pre-coder gates:  scripts/validate-artifact.sh <artifact>  (FAIL → re-spawn QA w/ deviations)
    · run test suite — exit code MUST be non-zero (RED). Passing? re-spawn QA to strengthen tests
    · log RED SHA from artifact → {ACCEPTANCE_TESTS_RED_SHA} in coder prompt
    · rm $STATE/.gate-pre-coder
4.  Spawn CODER ({MODE}=feature) → T-XXX-ready-for-review.md
4a. touch $STATE/.gate-pre-qa                       ← blocks QA/review spawns
5.  Pre-QA gates:     validate-artifact.sh <artifact>
    · TDD Evidence table ≥1 row (or per-behavior TDD-EXEMPT w/ justification) — missing → re-spawn coder
    · scripts/verify-tdd-evidence.sh <artifact>     (RED SHAs test-only, RED precedes GREEN)
    · run test suite — exit code MUST be 0 (GREEN)  → rm $STATE/.gate-pre-qa
6.  Spawn GARRY-REVIEW → T-XXX-review-findings.md → validate. P0/P1 → coder fix → back to 5
7.  touch $STATE/.gate-qa-c1 → Spawn QA {QA_PHASE}=cycle-1 (test + break) → T-XXX-cycle-1.md
    → validate → rm sentinel.  FAIL → coder fix → re-run C1 → still FAIL: ESCALATE (N=1)
8.  Spawn QA {QA_PHASE}=cycle-2 (full only): REAL e2e vs real DB + regression; NOT re-testing C1
    bugs → T-XXX-cycle-2.md → validate
9.  touch $STATE/.gate-spec-diff → Spawn VERIFIER ({QA_PHASE}=verify, opus): re-runs suite, spec-diffs
    every requirement to file:line → qa/FEAT-XXX/T-XXX-verification.md → all reqs VERIFIED → rm sentinel
10. COMPLETE — checkpoint, commit+push, one-line progress note, next task
```

**STOP boundaries:** wait for each artifact. No artifact → re-spawn once → escalate. Commit ordering is enforced by the `commit-order-guard.sh` hook. Severity at QA boundary: P0 must fix; P1 should fix before C2 (skip for single-file/config/docs-only); P2 → `docs/backlog.md`.

**Artifacts** (`mkdir -p qa/FEAT-XXX/runs`; test code stays in project `tests/`; qa/ dir squashed away at merge): `T-XXX-arch.md`, `-acceptance-tests.md`, `-ready-for-review.md`, `-review-findings.md`, `-cycle-1/2.md`, `-verification.md`, `runs/T-XXX-{red|green|c1|c2}-<timestamp>.txt`.

**Plan Execution (waves):** user points at a plan file with waves/tasks → Read it; auto-detect phase/branch/test dir (don't ask); check `**Reviewed:** YES` or `**Status:** APPROVED` (missing at `full` → AskUserQuestion; at `light` → warn, proceed); build dependency graph; present batches ONCE ("Proceed?"); spawn independent tasks in parallel (one message, respecting `parallelism`); run the per-task loop for each; progress note + confirmation at each wave boundary.

---

## MODE: backlog — light pipeline (no acceptance-test gate; verifier mandatory)

Route here when: a list of small, independent items — `docs/backlog.md`, an issue list, a TODO checklist — each item roughly one file-cluster, no cross-item design.
- Positive: "spawn agent teams to work through all open items in docs/backlog.md, max parallel".
- Negative: a backlog line reading "redesign the auth layer" — that item is a feature (design decisions, many files) → run it through `feature` mode instead.

1. Read the backlog; enumerate items; any item needing design or touching 3+ files with non-obvious integration → escalate or promote to `feature` mode.
2. **Conflict pre-flight:** group items into waves so no two agents in one wave touch the same files.
3. Per item, spawn a coder: `templates/coder-prompt.md`, `{MODE}`=backlog, first line `GOVERNANCE_EXEMPT (mode=backlog — no acceptance-test pipeline in this mode; verifier stage still mandatory)`. Without that line the step-gate hook blocks any fix/implement prompt when no acceptance tests exist on disk — that is by design in feature mode and sanctioned-around here. Unit tests are still RED-first; commit per item.
4. `qa_cycles`=1 (default): after each wave, spawn QA `{QA_PHASE}`=cycle-1 scoped to the wave's diffs — try to break the changed behavior. `qa_cycles`=0 (user said skip QA): skip this step; the verifier below still runs.
5. **Wave verifier** (`{QA_PHASE}`=verify, opus): re-runs the test suite itself and spec-diffs each item's claim to file:line → `docs/temp/<run-slug>/verification.md`.
6. Check off a backlog item ONLY when it is VERIFIED in verification.md — never on a coder's self-report. Progress note per wave; checkpoint after every wave.

---

## MODE: investigate-audit — fan-out + synthesize (no TDD artifacts; verifier mandatory)

Route here when: the deliverable is knowledge — research studies, adversarial audits, codebase maps, multi-doc reviews, synthesis reports. No implementation edits. (~25% of historical demand ran through the TDD pipeline needlessly; this mode is why that stops.)
- Positive: "Orchestrate max parallel subagents to execute gov-tam-study-v2.md, be thorough and self-verify before informing me."
- Negative: "orchestrate agents to fix all the failing CI jobs" — code changes → `backlog`.

1. **Scope statement** (≤2 lines): decomposition + lane count. State it and proceed — it is a statement, not a question (unless destructive work or `question_budget` says ask). "Scope: 6 research lanes → 1 synthesis → 1 verification pass. Proceeding — say stop to adjust."
2. **Waves of workers** via the inline skeleton; `sonnet` for extraction/search lanes, `opus` for judgment lanes; one output file per agent in `docs/temp/<run-slug>/` (e.g., `wave1-agent3-<topic>.md`).
3. **Progress notes** per cadence. Agent returns empty/dies → re-spawn ONCE → still failing: report the hole in the progress note and continue other lanes. Never silently drop a lane.
4. **Synthesis** (`opus`) writes the draft deliverable. The synthesizer is a PRODUCER — its output gets verified too.
5. **Verifier** (`{QA_PHASE}`=verify, opus, fresh agent, AFTER synthesis): re-derives claims from primary sources → `verification.md`. Why last: b676137b — every worker was audited, then the synthesizer ran last and hallucinated "no opt-in required" into the final matrix; nobody audited the synthesizer. Also 301c24ba: fabricated $150–300M figure + inaccessible sources reported "confirmed".
6. **Deliver** with per-claim tags — `[VERIFIED — verification.md #4]` / `[UNVERIFIED — source paywalled]` — plus counts and open holes.

No qa/ directory, no TDD artifacts, no sentinels beyond `.orchestration-active`.

---

## MODE: live-debug — reproduce → fix → re-verify vs golden reference

Route here when: a running app/site/service misbehaves and the deliverable is a confirmed fix.
- Positive: "staging checkout is broken — orchestrate agents to find it, fix it, and verify against prod behavior."
- Negative: "why is this function slow?" — one question, no parallel work → `/investigate` directly, no orchestrator.

1. **Golden reference FIRST:** pin down "correct" before touching anything — a working environment/commit, a spec quote, or user-stated expected output, plus the exact user-facing URL/command. No reference available → spend one question.
2. **REPRODUCER subagent** (browser work via the browse skill, `~/.claude/skills/browse/bin/browse`): reproduce on the exact user-facing target; write repro steps + evidence (screenshots/output) to the run dir.
3. **DIAGNOSER subagent:** root cause with file:line, `/investigate` discipline — no symptom fixes. Small scope → may be the same agent as 2.
4. **FIXER:** `templates/coder-prompt.md`, `{MODE}`=live-debug, `GOVERNANCE_EXEMPT (mode=live-debug — no acceptance-test pipeline; verifier stage still mandatory)`. Root-cause fix + a regression test that is RED on the bug first.
5. **VERIFIER** (`{QA_PHASE}`=verify): re-executes the ORIGINAL repro steps against the SAME user-facing target (not the fixer's local check — d8450959 "verified 31/31" against the wrong URL), compares to the golden reference, runs the regression test → `verification.md` with command/screenshot evidence.
6. FAIL → one fix cycle (N=1) → escalate.

`qa_cycles`=1 is the verify pass; 2 adds a `{QA_PHASE}`=cycle-1 agent breaking surrounding behavior. This mode has the worst self-implementation record — you NEVER open the browser or edit the fix yourself (Iron Law 1).

---

## Verification Stage (mandatory in EVERY mode — the completion gate)

Before ANY completion claim to the user, spawn ONE fresh verifier: `templates/qa-prompt.md`, `{QA_PHASE}`=verify, model `opus`.

- **RE-RUN, don't re-read.** "Tests pass" → verifier runs the suite itself. "Code does X" → verifier opens file:line itself. "Deployed/works" → verifier hits the exact URL/command the USER will use. "Source says Y" → verifier opens the source. Producer citations are leads, not evidence.
- **Producer ≠ verifier.** Whoever wrote the code, tests, or synthesis is a producer; the last producer to touch content can never be the checker.
- Verdicts: VERIFIED (re-derived, evidence cited) · UNVERIFIED (source/check inaccessible — NEVER upgraded to confirmed) · CONTRADICTED (quote both sides).
- Output `verification.md` in the run dir: claim table (claim ≤15 words | where | verdict | file:line / URL / command output), counts, BLOCKING list. Sample floor: all claims if ≤15, else all figures/quotes/status claims + a 10-claim random sample (state what was sampled).
- Verifier reports, never fixes. CONTRADICTED/BLOCKING → producer fix → re-verify only the fixed claims → still failing: escalate with both sides quoted.
- Your completion report = deliverable paths + counts (N VERIFIED / M UNVERIFIED / 0 CONTRADICTED) + open holes. A completion report without verification.md is a violation (≥9 user-caught fake completions in this skill's history; 46 trust incidents in 6 months harness-wide).
- Positive: verifier reruns `make test`, greps the 4 claimed file changes, hits the deployed URL → 12/12 VERIFIED.
- Negative: verifier "confirms" by reading ready-for-review.md and repeating its claims — that is re-reading, not re-running.

## Context Budget & Compaction Survival

- **Digest contract:** every subagent returns ≤15 lines; full output lives on disk. An agent that dumps its artifact into the return message → use the disk path, never re-broadcast the dump.
- Orchestrator reads digests and artifact verdict/summary sections; open a full artifact only to adjudicate a gate.
- **Checkpoint:** after EVERY gate clearance / wave boundary, rewrite `$STATE/checkpoint.md`: mode, parameters, per-task status table (done / in-flight / pending + artifact paths), next action. After a compaction — or whenever earlier context looks truncated — your FIRST action is re-reading checkpoint.md. Evidence: 49% of 204 audited sessions compacted mid-orchestration (worst: 40 compactions, one unrecoverable); post-compaction drift caused wrong-file work.
- `context_self_contained`=true (default): no memory/journal searches by orchestrator or subagents.

## Escalation & Red Flags

- **N=1:** any task failing >1 fix cycle → STOP, AskUserQuestion. Deterministic failures (test/type/lint): ≤2 retries inside one subagent, then escalate. Structural (spec ambiguity, missing deps, wrong architecture): escalate immediately.
- **Scope drift:** rewriting worker prompts mid-run to chase tangents = the 04-20 RCA root cause ("Stop searching, you're going overboard"). Re-anchor to the scope statement or ask.
- STOP immediately if you catch yourself: editing implementation files or driving the browser · writing any qa/ or verification artifact · reporting "complete" without verification.md · skipping the verifier "because it's a small run" · idling after a hook block · "just this once / I already know" → spawn the subagent anyway.

## Reference — sentinels & scripts

| Sentinel (`$STATE/`) | Set | Cleared | Blocks |
|---|---|---|---|
| `.orchestration-active` | run start (all modes) | run end | gates `~/.claude/scripts/orchestrator-context-guard.sh` |
| `.active` | auto (`activate-on-orchestrator.sh` Skill hook) | session end | enables pre-agent-gate / step-gate / post-agent-audit |
| `.gate-pre-coder` | acceptance-tests.md returned | validated + confirmed RED | coder spawns |
| `.gate-pre-qa` | ready-for-review.md returned | TDD evidence + suite GREEN | QA/review spawns |
| `.gate-qa-c1` | before C1 spawn | cycle-1.md validated | C2 spawns |
| `.gate-spec-diff` | after QA pass | verification.md all-VERIFIED | task completion |

Scripts: `~/.claude/skills/lead-orchestrator/scripts/validate-artifact.sh` (also fires as a Write hook on `qa/` paths) · `scripts/verify-tdd-evidence.sh` · `scripts/orchestrator-step-gate.sh`; governance hooks in `~/.claude/scripts/governance/`. `post-agent-audit.sh` checks subagent output for `REQ-XX: <evidence>` lines.

Orchestration log: `logs/build-{timestamp}.md` (feature) or `docs/temp/<run-slug>/orchestration-log.md` — one checklist block per task/wave: agents spawned, artifacts, verdicts, verification counts.
