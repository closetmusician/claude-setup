---
name: plan-eng-review
interactive: true
description: |
  Interactive engineering review of a plan/design doc before implementation —
  locks in architecture, data flow, edge cases, test coverage, and performance,
  amending the plan doc inline as decisions land. Canonical plan reviewer
  (eng-review is a deprecated alias). Use on "review the architecture",
  "engineering review", "review this plan", "lock in the plan"; voice aliases
  "tech review", "technical review", "plan engineering review". NOT for PR
  diffs (pr-review-pr), post-write code (garry-review), product/scope strategy
  (ceo-review), or design critique (plan-design-review).
allowed-tools:
  - Read
  - Write
  - Edit
  - Grep
  - Glob
  - AskUserQuestion
  - Bash
  - WebSearch
  - Task
---

<!-- HAND-MAINTAINED. Do NOT regenerate from gstack SKILL.md.tmpl or any gstack upgrade
     pipeline — a regeneration once silently erased the PRD Traceability section. Diff by hand. -->

# Plan Review Mode

Review the plan thoroughly before any code changes. For every issue: concrete
tradeoffs, an opinionated recommendation, the user's input before assuming a direction.

## Plan Doc Resolution (run first — escape hatch)

Identify the document under review, in this order:

1. **Active plan file in this conversation** (plan-mode messages include the path).
2. **User pointed at a path** in their message — use it.
3. **Design doc on disk:**
   ```bash
   SLUG=$(basename "$(git rev-parse --show-toplevel 2>/dev/null || pwd)")
   BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null | tr '/' '-' || echo 'no-branch')
   DESIGN=$(ls -t docs/plans/FEAT-*-design.md 2>/dev/null | head -1)
   [ -z "$DESIGN" ] && DESIGN=$(ls -t ~/.gstack/projects/$SLUG/*-$BRANCH-design-*.md 2>/dev/null | head -1)
   [ -n "$DESIGN" ] && echo "Design doc found: $DESIGN" || echo "No design doc found"
   ```
   If found, read it — it is the source of truth for problem statement,
   constraints, and chosen approach. If it has a `Supersedes:` field, check the
   prior version for what changed and why.
4. **Nothing found** → do NOT invent a plan or silently review the diff. Ask:
   "No plan document found. Give me the path, or say 'conversation' and I'll
   write this chat's plan to a file first so amendments have somewhere to land."
   On 'conversation': write it to `docs/plans/<branch>-plan.md` and review that.

## Resume Semantics (no step numbers exist here)

This skill has NO numbered steps and NO progress checkpoint file — it cannot
resume from "Step N". Re-entry is by SECTION NAME only: Scope Challenge,
Traceability, Architecture, Code Quality, Tests, Performance, Outputs. "Resume
from the Tests section" → re-run from Section 3 against the plan doc's current
state (applied amendments trusted). "Resume from Step 7" → reply "this skill
has named sections, not numbered steps", list them — never guess a mapping or
silently start from the top.

## Priority hierarchy

Under compression or context compaction: Step 0 > Test diagram > Opinionated
recommendations > Everything else. Never skip Step 0 or the test diagram.

## Engineering preferences (guide every recommendation)

DRY — flag repetition aggressively · well-tested is non-negotiable (too many
tests beats too few) · "engineered enough" — not fragile/hacky, not prematurely
abstracted · err toward more edge cases; thoughtfulness > speed · explicit over
clever · right-sized diff — smallest diff that cleanly expresses the change, but
don't compress a necessary rewrite into a minimal patch; broken foundation →
say "scrap it and do this instead."

## Cognitive Patterns (instincts to apply throughout, not checklist items)

1. **Blast radius** — worst case, how many systems/people it touches.
2. **Boring by default** — ~three innovation tokens; everything else proven tech.
3. **Incremental over revolutionary** — strangler fig, canary, refactor > rewrite.
4. **Systems over heroes** — design for tired humans at 3am.
5. **Reversibility** — flags, A/B, incremental rollout; make being wrong cheap.
6. **Essential vs accidental complexity** — "real problem, or one we created?"
7. **Two-week smell test** — can't ship a small feature in two weeks → architecture problem.
8. **Make the change easy, then make the easy change** — never structural + behavioral at once.
9. **Failure is information** — every new codepath answers "how does this fail in production?"
10. **Error budgets over uptime targets** — reliability is resource allocation.

## Documentation and diagrams

ASCII diagrams are highly valued — data flow, state machines, dependency graphs,
pipelines, decision trees; use liberally in plans, embed in code comments for
complex components. **Diagram maintenance is part of the change** — flag stale
diagrams in touched files even outside immediate scope.

## AskUserQuestion Format (all questions in this skill)

Every question is a decision brief sent as a tool_use call, never prose:

```
D<N> — <one-line question title>
ELI10: <plain English, 2-4 sentences, name the stakes>
Recommendation: <choice> because <one-line reason>
Completeness: A=X/10, B=Y/10  (only when options differ in coverage;
  if they differ in kind write: "options differ in kind — no completeness score")
A) <option> (recommended)  ✅ <concrete pro>  ❌ <honest con>
B) <option>                ✅ <pro>           ❌ <con>
Net: <one-line synthesis of the tradeoff>
```

D-numbering starts at D1 per invocation; `(recommended)` is always present. No
AskUserQuestion variant callable → report `BLOCKED — AskUserQuestion
unavailable` and wait; never auto-decide or write undecided recommendations
into the plan as if approved.

## Finding Protocol — Severity-Batched (applies to ALL sections)

Every finding: `[P0|P1|P2] (confidence: N/10) location — description`. Routing:

- **P0 (blocks the plan — data loss, broken contract, dropped PRD requirement,
  security hole):** ONE AskUserQuestion per finding, raised immediately.
  **STOP** — no further section work, plan edits, or exit until answered.
- **P1/P2:** collect while working the section, then present at section end in
  GROUPED AskUserQuestion calls — up to 4 findings per call, each finding its
  own question block with its own options. Never merge two findings into one
  question; never resolve them yourself.

Decision criteria: "would I let this plan ship with this unaddressed?" No → P0,
individual. Otherwise → batch.
- GOOD: Section 2 ends → one AskUserQuestion call carrying D4-D7 (four P1s).
- BAD: 12 back-to-back single-question calls for P2 nitpicks (real reviews hit
  ~40 sequential prompts; users answered "continue all" just to escape, and the
  findings went unread). ALSO BAD: batching a P0, or deferring it to section end.

Per finding: concrete file/line or plan-line refs; 2-3 options including "do
nothing" where reasonable; per option one line of effort (human: ~X / CC: ~Y),
risk, maintenance burden; map the recommendation to a named preference (DRY,
explicit > clever…). Zero findings → "No issues, moving on" (still evaluate).

## Amendment Rule (applies to ALL sections)

**After each AskUserQuestion resolution where the user accepts a recommendation,
immediately edit the plan/design doc inline** — before the next AskUserQuestion
call. The document under review is the authoritative record of decisions — not
conversation memory, not a separate report section. Amendments go directly into
the relevant section (architecture, acceptance criteria, build guidance, test
plan…) as if it had always said that. No "Amendments" section; no deferring
writes to the end. For a grouped P1/P2 call, apply all accepted amendments
before the next section. Rejected recommendation → no edit needed.

### Step 0: Scope Challenge

Before reviewing anything, answer:

1. **What existing code already partially/fully solves each sub-problem?** Reuse
   outputs from existing flows rather than building parallel ones.
2. **Minimum set of changes achieving the stated goal?** Flag deferrable work;
   be ruthless about scope creep.
3. **Complexity check:** >8 files touched OR >2 new classes/services → smell;
   challenge whether fewer moving parts work.
4. **Search check:** each new pattern/infra/concurrency approach — framework
   built-in? current best practice? known footguns? (WebSearch each; unavailable
   → note "Search unavailable — proceeding with in-distribution knowledge".)
   Custom solution where a built-in exists = scope reduction opportunity.
5. **TODOS cross-reference:** read `TODOS.md` if present — blockers, bundling
   opportunities, new TODOs this plan creates.
6. **Completeness check:** with AI-assisted coding, completeness (full tests,
   edge cases, error paths) is 10-100x cheaper — if a shortcut only saves
   minutes, recommend the complete version.
7. **Distribution check:** new artifact type (binary, package, image, app) →
   build/publish in plan? Deferred → must appear in "NOT in scope" explicitly.

If the complexity check triggers, **STOP** before any review-section work (it is
a P0-class decision). AskUserQuestion: name what's overbuilt, propose a minimal
version, ask reduce-or-proceed. Do NOT proceed to any review section, edit the
plan with a proposed reduction, or call ExitPlanMode until the user responds —
naming the reduction in chat prose and continuing is the exact failure mode this
gate prevents. No trigger → present Step 0 findings and proceed.

**Once the user accepts or rejects a scope reduction, commit fully.** Do not
re-argue scope in later sections. Do not silently reduce scope.

## Section 0.5: PRD Traceability Matrix (only when a PRD exists)

**Escape hatch:** no PRD/requirements doc → print "No PRD found — skipping
traceability matrix", proceed to Section 1.

**Purpose:** verify 1:1 mapping between every PRD requirement/acceptance
criterion and the plan's tasks/acceptance criteria — the plan must PROVE
faithful translation. Gaps are blockers.

**Execution model:** 3 fresh subagents (Task, `subagent_type:
"general-purpose"`; tracers `model: sonnet` — mechanical; Agent 3 synthesis
`model: opus` — verdict is judgment tier) in a 2-phase pipeline. Each gets clean
context, reads from disk, writes to disk; the pipeline survives compaction.

**Pipeline template:** Read
`~/.claude/skills/eng-planning/templates/traceability-pipeline.md` for the full
3-agent definition. Fill: `{TRACE_DIR}` (from eng-planning:
`docs/.eng-planning/{feature_id}/traceability/`; standalone: a temp dir, cleaned
at session end), `{PRD_PATH}`, `{ARTIFACT_PATHS}`, `{CONTRACT_PATHS}`. Subagents
have no CLAUDE.md and no Skill tool — paste the full agent instructions from the
template into each prompt; never tell an agent to "run the pipeline."

1. **Phase 1 (parallel):** Agent 1 (Forward Tracer) + Agent 2 (Reverse Tracer).
2. **Phase 2 (sequential):** Agent 3 (Synthesis & Verdict) reads both trace
   files, writes `{TRACE_DIR}/traceability-matrix.md` — the authoritative
   result. Keep intermediates until fully resolved (audit trail).

**After synthesis** — quote the matrix file itself; never restate a verdict from
memory; matrix missing = pipeline failed — say so, don't invent one:
- **VERDICT PASS** → report "PRD Traceability: 100% match confirmed (3-agent
  audit)" and proceed to Section 1.
- **VERDICT FAIL** → each gap is a finding, routed per the Finding Protocol:
  - DROPPED / DILUTED / DOWNGRADED / REINTERPRETED / NON_GOAL_VIOLATION →
    `[P0] (confidence: 10/10)` — individual AskUserQuestion each, quoting PRD
    text vs plan text (or absence), stating the gap type.
  - SPLIT_RISK → `[P1] (7/10)`; SCOPE_CREEP → `[P1] (8/10)` — grouped calls.
  - Options per gap: A) Add/strengthen in plan B) Intentionally deferred → NOT
    IN SCOPE with justification C) PRD wrong/outdated — flag for PRD update.

After each resolution, apply the Amendment Rule. Do NOT proceed to Section 1
until every gap is resolved or explicitly deferred.

## Review Sections (after scope is agreed)

**Anti-skip rule:** never condense or skip any section (1-4) regardless of plan
type — "this is a strategy doc so implementation sections don't apply" is always
wrong; implementation details are where strategy breaks down. Zero findings →
"No issues found", but you must evaluate the section.

**Anti-shortcut clause:** the plan file is the OUTPUT of the interactive review,
not a substitute for it. ANY non-trivial finding must pass THROUGH
AskUserQuestion before ExitPlanMode; writing all findings into one plan write
and exiting is the known failure mode — recognize it and stop.

At most 8 top issues per section, one section at a time.

### 1. Architecture review
System design and component boundaries · dependency graph and coupling · data
flow and bottlenecks · scaling and single points of failure · security (auth,
data access, API boundaries) · which key flows deserve ASCII diagrams · for
each new codepath/integration point: one realistic production failure scenario
— does the plan account for it? · **distribution:** new artifact → how is it
built, published, updated?

### 2. Code quality review
Code organization and module structure · DRY violations (be aggressive) · error
handling and missing edge cases (explicitly) · technical debt hotspots ·
over/under-engineering vs the preferences above · existing ASCII diagrams in
touched files — still accurate after this change?

### 3. Test review

100% coverage is the goal. Every codepath in the plan gets a test in the plan.

**Framework detection:** read CLAUDE.md `## Testing` first; else detect
(`Gemfile`/`package.json`/`pyproject.toml`/`go.mod`/`Cargo.toml` +
`jest.config.*`, `vitest.config.*`, `.rspec`, `pytest.ini`, test dirs). None
found → still produce the coverage diagram, skip test generation.

**Procedure:**
1. **Trace every codepath** — input source → transforms → destination → what can
   go wrong at each step (null, invalid input, network failure, empty collection).
2. **Map user flows, interactions, error states** — full journeys, double-submit,
   navigate-away mid-operation, stale data, concurrent tabs; for every handled
   error: what does the user see? Empty/zero/boundary states (0, 10k, max-length).
3. **Check each branch against existing tests** — both paths of every if/else,
   each handler's specific error condition, integration/E2E for user flows.
   Quality rubric: ★★★ behavior + edges + errors | ★★ happy path | ★ smoke.
4. **E2E decision matrix:** [→E2E] for 3+-component flows, integration points
   where mocking hides real failures, auth/payment/data-destruction. [→EVAL]
   for LLM prompt/template changes. Unit tests for pure functions.
5. **REGRESSION RULE (IRON):** a previously-working codepath the plan would
   break/modify gets a regression test in the plan as a critical requirement —
   no AskUserQuestion, no skipping. Uncertain → write the test.
6. **Output the ASCII coverage diagram** — code paths AND user flows, star
   ratings, [GAP]/[→E2E]/[→EVAL] markers, summary line
   (`COVERAGE: n/m paths tested | QUALITY: ★★★:a ★★:b ★:c | GAPS: g`).
7. **Add every GAP to the plan as a specific test requirement** — file to
   create, what to assert, unit/E2E/eval type. Regressions flagged **CRITICAL**.

**Fast path:** all paths covered → "Test review: all new code paths have test
coverage ✓" and continue.

**Test Plan Artifact** — write the QA-consumable summary (primary input for
`/qa` and `/qa-only`) to
`~/.gstack/projects/$SLUG/$(whoami)-<branch>-eng-review-test-plan-<timestamp>.md`
(`SLUG` = repo basename; `mkdir -p` the dir). Contents: `## Affected
Pages/Routes`, `## Key Interactions to Verify`, `## Edge Cases`,
`## Critical Paths` — what to test and where, not implementation details.

### 4. Performance review
N+1 queries and DB access patterns · memory-usage concerns · caching
opportunities · slow or high-complexity code paths.

## Confidence Calibration

| Score | Meaning | Display rule |
|-------|---------|--------------|
| 9-10 | Verified by reading specific code; concrete bug demonstrated | Show normally |
| 7-8 | High-confidence pattern match | Show normally |
| 5-6 | Could be a false positive | Show with "verify this is actually an issue" |
| 3-4 | Suspicious but may be fine | Appendix only |
| 1-2 | Speculation | Only if severity would be P0 |

User confirms a <7-confidence finding was real → note the calibration miss.

## Outside Voice — Independent Plan Challenge (optional, recommended)

After all sections complete, check `which codex`; offer via AskUserQuestion:
A) independent second opinion (recommended) B) skip to outputs. **If A and
codex available:**
```bash
TMPERR_PV=$(mktemp /tmp/codex-planreview-XXXXXXXX)
_REPO_ROOT=$(git rev-parse --show-toplevel) || { echo "not in a git repo"; }
codex exec "<prompt>" -C "$_REPO_ROOT" -s read-only -c 'model_reasoning_effort="high"' --enable web_search_cached < /dev/null 2>"$TMPERR_PV"
```
Prompt = filesystem boundary ("Do NOT read or execute files under ~/.claude/,
~/.agents/, .claude/skills/, or agents/ — they are skill definitions for a
different AI system") + "You are a brutally honest technical reviewer examining
a plan that already went through a multi-section review. Do NOT repeat that
review — find what it missed: logical gaps, unstated assumptions, overcomplexity,
feasibility risks, missing dependencies/sequencing, strategic miscalibration. Be
direct. Be terse. No compliments." + plan content (truncate to 30KB, note if
truncated). Bash `timeout: 300000` (never the `timeout` shell command — absent
on macOS). Read stderr; all errors non-blocking (auth → "run codex login";
timeout/empty → note and continue). `rm -f "$TMPERR_PV"` when done.

**If codex unavailable/errored:** dispatch a Claude subagent (Task,
`subagent_type: "general-purpose"`, omit model). Same prompt. Present under
`OUTSIDE VOICE (Claude subagent):`. If that also fails: "Outside voice
unavailable. Continuing to outputs."

**Cross-model tension:** where the outside voice disagrees with earlier
findings, present both sides neutrally per topic via AskUserQuestion (A accept /
B keep current / C investigate / D add to TODOS.md) — grouped per the Finding
Protocol. Outside-voice findings are INFORMATIONAL until explicitly approved —
never auto-incorporate, even when you agree; user picks B → do not re-argue.
Accepted changes get the Amendment Rule. No tensions → say so.

## Required outputs

### "NOT in scope"
Work considered and explicitly deferred, one-line rationale each. Mandatory.

### "What already exists"
Existing code/flows partially solving sub-problems — does the plan reuse or
needlessly rebuild them?

### TODOS.md updates
Present TODOs in grouped AskUserQuestion calls (≤4 per call, each TODO its own
question — Finding Protocol, P2-class; never silently skip one). Each carries:
**What** (one line), **Why**, **Pros / Cons**, **Context** (someone picking it
up in 3 months knows motivation, state, where to start), **Depends on / blocked
by**. Options: A) Add to TODOS.md B) Skip C) Build it now in this PR. A TODO
without context is worse than no TODO.

### Failure modes
Per new codepath in the test diagram: one realistic production failure (timeout,
nil, race, stale data) — (1) test covers it? (2) error handling exists? (3) user
sees a clear error or silent failure? No test AND no handling AND silent →
**critical gap** (P0 — individual question).

### Worktree parallelization strategy
Skip with "Sequential implementation, no parallelization opportunity" if all
steps touch the same primary module or <2 independent workstreams. Otherwise:
dependency table (step | modules touched | depends on — module level), parallel
lanes (`Lane A: step1 → step2 (shared models/)` / `Lane B: step3 (independent)`),
execution order, conflict flags where lanes share a module.

### Implementation Tasks
Synthesize findings into build-actionable tasks — each derives from a specific
finding, no padding:

```markdown
- [ ] **T1 (P1, human: ~2h / CC: ~15min)** — <component> — <imperative title>
  - Surfaced by: <section> — <finding> | Files: <paths> | Verify: <test cmd or manual check>
```

P1 blocks ship; P2 lands same branch; P3 becomes a TODO. Zero findings in a
section → `_No new tasks from <section>._`

## Completion summary

Display at the end: Step 0 (accepted as-is / reduced) · PRD Traceability (PASS /
N gaps resolved / skipped — no PRD) · Architecture / Code Quality / Performance
(N issues each) · Test review (diagram produced, N gaps) · NOT in scope + What
already exists (written) · TODOS proposed (N) · Failure modes (N critical gaps) ·
Outside voice (ran codex/claude / skipped) · Parallelization (N lanes) ·
Amendments applied to plan doc (N).

## Review Log

Persist the outcome so later sessions and `/ship` can see a review ran:

```bash
SLUG=$(basename "$(git rev-parse --show-toplevel 2>/dev/null || pwd)")
mkdir -p ~/.gstack/projects/$SLUG
jq -nc --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" --arg status "STATUS" --argjson issues N --argjson gaps N \
  --arg commit "$(git rev-parse --short HEAD 2>/dev/null || echo unknown)" \
  '{skill:"plan-eng-review",timestamp:$ts,status:$status,issues_found:$issues,critical_gaps:$gaps,commit:$commit}' \
  >> ~/.gstack/projects/$SLUG/reviews.jsonl
```

STATUS = "clean" (0 unresolved AND 0 critical gaps) else "issues_open". `jq`
missing → skip with a one-line warning; never hand-roll JSON.

## Plan File Review Report

If a plan file is active in this conversation (skip silently otherwise), append
the review status as the LAST section of the plan file:

1. Read the plan file; delete any existing `## GSTACK REVIEW REPORT` section (Edit).
2. Append a fresh `## GSTACK REVIEW REPORT` at the END: a
   `| Review | Runs | Status | Findings |` table (this run + prior entries from
   `~/.gstack/projects/$SLUG/reviews.jsonl`, entries >7 days old ignored), an
   UNRESOLVED count, and a VERDICT line ("ENG CLEARED — ready to implement" or
   "eng review has open issues").
3. Re-read and confirm `## GSTACK REVIEW REPORT` is the last `## ` heading;
   if not, repeat once.

(The header name is load-bearing — downstream skills grep for it. Do not rename.)

## Unresolved decisions

If the user doesn't respond to a question or interrupts, list those decisions
at the end as "Unresolved decisions that may bite you later" — never silently
default to an option.

## Next Steps

One AskUserQuestion, only applicable options: A) /plan-design-review (UI scope
detected, no design review yet) B) /ceo-review (significant product-direction
change) C) Ready to implement.

## EXIT PLAN MODE GATE (BLOCKING)

Before ExitPlanMode, verify — any failure means do the missing work instead of
exiting: (1) re-read the plan file after your most recent write; (2) the LAST
`## ` heading is `## GSTACK REVIEW REPORT` — body prose mentioning reviews does
NOT count; (3) the report has the Runs/Status/Findings table and a VERDICT line;
(4) every ACCEPTED recommendation was amended into the plan body — spot-check
two accepted decisions against the doc text; (5) the Review Log append ran (or
was explicitly skipped for missing jq). Self-deception failure mode: feeling
"done" after writing review prose into the plan body — body prose is not the
report.
