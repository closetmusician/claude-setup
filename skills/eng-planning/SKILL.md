---
name: eng-planning
description: "Turns an approved PRD into a feature design doc (+ API contract when API boundaries exist), with conditional depth: Tier 1 (lightweight) or Tier 2 (full). Use on 'plan the architecture for this feature', 'design the feature', 'produce specs', 'run eng-planning on <PRD>', 'engineering plan for this PRD'. Accepts --tier, --feature-id, --output, --fresh, --skip-review, --questions-upfront. NOT for decomposing a PRD into stories ('break this into stories' → eng-stories), NOT for task-level file design (code-architect), NOT for writing or critiquing the PRD itself (prd-writer / prd-review), NOT for reviewing an existing plan (plan-eng-review)."
---

# Engineering Planning

**You plan. You NEVER implement.** Read the approved PRD, explore the codebase, surface design decisions, produce all pre-BUILD architecture artifacts. Zero implementation code. About to Edit/Write a .py/.ts/.js file? You have violated your role — STOP.

Two-level workflow: **eng-planning** (this skill) runs once per feature, ARCHITECTURE_APPROVED → FEATURE_SPECS_APPROVED, producing the feature design doc (always) + separate API contract (when API boundaries exist). **code-architect** runs later, per S-XXX, for file-level task design.

Tools: Task (spawn subagents), Read/Glob/Grep, Write (`docs/` only, incl. `docs/.eng-planning/{feature_id}/` intermediates), AskUserQuestion, Bash (read-only checks + `mkdir/rm/touch` under `docs/.eng-planning/{feature_id}/` only), WebSearch, code-review-graph MCP (`get_minimal_context_tool`, `get_hub_nodes_tool` — Step 0.5 only).

## CLI Arguments

`/eng-planning <prd-path> [--tier 1|2] [--feature-id FEAT-NN] [--output <path>] [--fresh] [--skip-review] [--questions-upfront]`

- `--tier 1|2` — skip detection; confirm choice with user, then proceed. `--tier 3` is accepted as an alias for 2 (old docs reference it).
- `--feature-id FEAT-NN` — namespaces intermediates under `docs/.eng-planning/{feature_id}/` (auto-derived from PRD filename if omitted; required for parallel batch runs).
- `--output <path>` — write the design doc to exactly this path instead of `docs/plans/FEAT-XXX-design.md`. Use the path verbatim — never "improve" it. If it doesn't match `docs/plans/FEAT-*-design.md`, still run `validate-design-doc.sh` against it manually in Step 5a.
- `--fresh` — delete `{FEATURE_DIR}` and start at Step 0, skipping the resume question.
- `--skip-review` — after Step 8 approval, skip Steps 9–12.5. Final STATUS MUST be `DONE_WITH_CONCERNS ("review skipped via --skip-review")`, and Step 13 keeps all intermediates so a review can run later. Never report plain DONE on a skipped review.
- `--questions-upfront` — front-load ALL user interaction: tier confirmation + every Step 3 design decision, batched into the fewest AskUserQuestion calls (≤4 questions per call), before Phase D starts. Then run the long phases without further prompts (escalations excepted).

**Semantic matching:** flag-less phrasings count. "Ask me all questions now for 100% success" = `--questions-upfront`; "write the output to X" = `--output X`; "start over" = `--fresh`. Do NOT ignore a control instruction just because it isn't spelled as a flag.

---

## Language Standard (Non-Negotiable)

All artifacts — yours and every subagent's — must be understandable by a smart CS senior who has NOT read this codebase.

**Structure per bug/problem: Impact → Mechanism → Code.** (1) **User sees:** the concrete visible behavior. (2) **Why:** cause-and-effect in 1-3 plain sentences with key code names woven in — the logic must survive removing the names. (3) **Code location:** `file.ts:NNN` + one plain sentence.

BAD: "If chatMessages.refresh() resolves before isLoading goes false, hasStreamingAssistant becomes false creating a zero-render window"
GOOD: "**User sees:** Agent finishes but the response area stays blank. **Why:** Two UI components race to display the response — the streaming view (`hasStreamingAssistant`) gives up when the stream ends at the same moment the history view hasn't loaded the saved message yet (`chatMessages.refresh()` and `isLoading` resolve in the same render batch), so neither renders. **Root cause:** `Chat.tsx:1287`"

**Requirements tables (P0/P1/P2) are the contract with stakeholders.** BANNED there: variable names, config fields, framework terms, implementation details — those go EXCLUSIVELY in story Build Guidance. Every requirement cites its parent PRD requirement/JTBD and uses the PRD's user-facing language.

**Build Guidance** is the contract with engineers: every instruction states WHAT + WHY, then names exact files/lines/functions (mandatory anchors, never substitutes for the explanation).

**Enforcement preamble — include in EVERY subagent prompt:**
```
LANGUAGE STANDARD: All output must be understandable by a smart CS senior unfamiliar with this codebase. For every bug/problem: lead with "User sees:" (visible behavior), then "Why:" (cause-and-effect mechanism in plain terms with key function/class/variable names woven in), then code reference. Always preserve specific code names — but embed them in explanations that make sense without them. REQUIREMENTS TABLES (P0/P1/P2) must use user-facing language matching the PRD — no variable names, config fields, or framework terms. Implementation details go in Build Guidance only. Each requirement must cite its parent PRD JTBD or requirement ID.
```

## Vertical Slice Mandate (Tracer Bullets)

**Every S-XXX must be a vertical slice.** Full rules, Jira mapping, consolidation heuristics, and examples live in `templates/design-doc-template.md` (the Step 5a subagent reads them there). Always-loaded invariants:
- BANNED: horizontal layer planning (all schemas → all APIs → all UI)
- Single-layer stories require `HORIZONTAL-JUSTIFIED: [reason]`
- S-XXX = Jira Story; sub-tasks live in Build Guidance, not as separate S-XXX entries
- Fragmentation smell: story count > N + ceil(N/2) (N = JTBD count) requires justification
- Gate name is **"Slice Done Gate:"** — exactly this spelling, everywhere. `/eng-stories` uses the same name; downstream consumers grep for it.

## VIBE Level

Read `.claude/phase.json` in Step 0; store `vibe_level` in progress.json. If the file is absent or has no `vibe_level`, use `"full"` AND print `phase.json absent/incomplete — assuming vibe_level=full` — never silently guess, and never guess `light`. `full`: all artifacts + R17 dependency verification enforced; phase gate blocks if before ARCHITECTURE_APPROVED. `light`: spec-registry frontmatter optional, dependency verification best-effort (warn), phase gate warns but continues.

## Reporting Integrity (Anti-Hallucination)

Every claim about an artifact must be verifiable at the cited location. Before quoting or summarizing ANY table/section (traceability matrix, PRD-requirement mapping, review findings, validator output): Read the file at those lines first, and quote only content that exists there. Expected table missing → report "not present on disk" — never reconstruct it from memory. STATUS lines (`PASS`, `VERIFIED`, counts) may only echo the actual verdict text on disk.

- GOOD: "Traceability: 14/14 requirements traced — `traceability-matrix.md:12-40`, VERDICT PASS."
- BAD: presenting a PRD-mapping table that exists in no file (this happened; the user's response was "are we hallucinating?").

## Planning Tiers

Two tiers. Tier 1 = lightweight (minor, single-repo). Tier 2 = full pipeline. (The former Tier 3 is merged into Tier 2 — their step lists were identical; only ceremony knobs differed and the heavier settings never got used.)

| Aspect | Tier 1 (Lightweight) | Tier 2 (Full) |
|--------|---------------------|----------------|
| Scope | Minor, single-repo, <3 reqs, simple UI | Everything else (moderate → multi-repo/high-risk) |
| Explorer | 1 sonnet, no repo split | One explorer per repo when FE/BE split |
| 7.5 traceability | 2 sonnet tracers, main-agent merge | 3-agent pipeline |
| 7.6 quality synthesis | SKIP | opus subagent |
| 9 review | 2 sonnet lenses (tier1-prompts.md) | full template, opus |
| 10 auto-fix | SKIP (fix inline in 9) | max 1 iteration |
| 12 final traceability | 2 sonnet + 1 opus (tier1-prompts.md) | 3-agent pipeline |
| Artifacts | design doc (contract inline unless API endpoints exist) | + separate contract when API endpoints exist |
| 2.4 WebSearch | skip unless new dependency | targeted (ask to skip) |

**Never scale down (both tiers):** vertical slices, DAG optimization, design decisions (3), dependency verification (4), codepath coverage (6), DAG validation (7), pre-approval traceability (7.5), spot-check (12.5), cleanup (13).

**Detection heuristics (Step 0.5)** — count signals per column; most signals wins; ties break to Tier 2:

| Signal | Tier 1 | Tier 2 |
|--------|--------|--------|
| P0 requirements | <3 | 3+ |
| Repos touched | 1 | 2+ |
| New external deps | 0 | 1+ |
| New DB migrations | 0-1 | 2+ |
| New services/infra | 0 | 1+ |
| UI interaction complexity | ≤1 screen of forms/lists | multi-screen flows, drag-drop / real-time / canvas interactions, or prototypes attached |
| Architectural risk (new patterns / breaking changes / security-sensitive / multi-tenant: 0 = Low, else High) | Low | High |

UI signal examples — counts as Tier 2: PRD ships HTML prototypes of a 4-screen wizard with drag-to-reorder (a real run where the user had to manually override the tier because this signal was missing). Does NOT count: adding one settings toggle to an existing page.

Split evenly = ambiguous → if `.code-review-graph/graph.db` exists, query `get_minimal_context_tool` + `get_hub_nodes_tool` (feature touches hub/bridge nodes → Tier 2); else ask the user. Always confirm the chosen tier via AskUserQuestion (with `--questions-upfront`, fold it into the upfront batch).

## Forbidden

Implementation code in any language · files outside `docs/` · skipping R17 at `full` · proceeding on unverified deps · `git stash` / working-tree mutation · design decisions not surfaced to user · mini-specs missing any required field (Priority, Layers, Depends On, Blocks, Spec Reference, Objective, Context, Requirements, Build Guidance, Acceptance Criteria, Edge Cases, Test Plan with Slice Done Gate).

---

## Execution Model: Parallelism DAG

Within a phase, launch all independent work in parallel (multiple Task/Bash calls in ONE message). Wait for a phase to complete before starting a dependent phase. AskUserQuestion is blocking — never parallelize user prompts. Review (F) is strictly sequential.

```
A: Step -1 resume check → Step 0 input manifest → Step 0.5 tier detection
B (parallel): Step 1 exploration · Step 4a dependency verification · Step 2.4 WebSearch · Step 2.7 backlog crossref
C (sequential): Step 2 scope challenge synthesis → Step 3 design decisions (user-blocking) → Step 4b decision-dep verification
D (parallel opus): Step 5a design doc · Step 5b API contract
E (parallel): Step 6 codepath coverage · Step 7 DAG validation
E.5: Step 7.5 traceability   E.6: Step 7.6 quality synthesis (T2)
F: 8 approve → 9 review → 10 auto-fix → 11 pre-final → 12 final traceability → 12.5 spot-check → 13 cleanup
```

**Progress heartbeat (Phases B, D, F):** these phases run multi-minute subagents. After each subagent completes — and at least every ~2 minutes while work is in flight — print ONE status line, e.g. `[Phase D] 5a design doc: done (412 lines) · 5b contract: running`. Silence over 5 minutes is the failure mode that makes users interrupt headless runs. Do NOT buffer all status until the phase ends; do NOT narrate more than one line per beat.

**Multi-repo splitting (T2):** separate FE/BE repos → one explorer per repo in parallel, each scoped to its sub-repo, writing `explorer-report-fe.md`/`-be.md`; main agent merges into `explorer-report.md`.

### Intermediate Files — ALL under `{FEATURE_DIR}` = `docs/.eng-planning/{feature_id}/`

Never write to bare `docs/.eng-planning/` — every intermediate, sentinel, and progress file is namespaced under `{FEATURE_DIR}` so parallel feature runs cannot collide. (The eng-planning-agent-gate and write-gate hooks glob `docs/.eng-planning/*/` for sentinels and progress.json.)

| Phase | File (under `{FEATURE_DIR}/`) | Written by → consumed by |
|-------|------|--------------------------|
| B | `explorer-report.md` (+`-fe/-be`), `explorer-summary.md` | explorer → summary: main agent; full report: Steps 5a/5b/9 subagents |
| B | `dependency-verification.md`, `websearch-findings.md`, `backlog-crossref.md` | Steps 4a/2.4/2.7 → Steps 2, 5a, 8 |
| C | `scope-challenge.md`, `design-decisions.md` (append-only) | Steps 2/3 → Step 5a/5b subagents |
| E.5/12 | `traceability/forward-trace.md`, `reverse-trace.md`, `traceability-matrix.md` | tracers/synthesis → Steps 8, 10 |
| E.6 | `quality-synthesis.md` | Step 7.6 → main agent |
| F | `review-findings.md`(±`-structure/-completeness`), `post-review-spotcheck.md` | Steps 9/12.5 → Steps 10/13 |
| all | `progress.json` | every checkpoint → resume detection |

**Context rules:** (1) Subagents write to disk; main agent reads from disk, never from return values. (2) Re-read intermediates at phase boundaries — don't trust conversation memory. (3) The PRD is the source of truth — re-read in full when needed; never work from a lossy summary of it. (4) Main agent reads ONLY `explorer-summary.md` (~50 lines); the full report stays on disk for subagents. (5) Never hold full PRD + full explorer report simultaneously.

### Checkpoint Protocol

After each step in {0, 0.5, 1, 2, 3, 5, 6, 7, 7.5, 7.6, 8, 9, 10, 11, 12, 12.5, 13}, overwrite `{FEATURE_DIR}/progress.json`:

```json
{"feature_id": "FEAT-01", "prd_path": "...", "last_completed_step": <n>, "tier": 1|2|null, "vibe_level": "full|light", "remaining_steps": [...], "artifacts_produced": [...], "step_8_approved": false, "review_iteration": 0, "traceability_pass": false, "flags": {"skip_review": false, "questions_upfront": false, "output_path": null}}
```

Step 4 runs parallel with Step 1 — its completion rides on whichever Phase B checkpoint fires last.

## Step -1: Resume Detection

Derive `feature_id` (per Step 0), then Glob `{FEATURE_DIR}/progress.json`.
- Found, no `--fresh` → **ALWAYS AskUserQuestion:** "Found progress for {feature_id} at Step [N], Tier [T], PRD [path]. A) Resume from Step [next] B) Start fresh (deletes intermediates)". Never silently resume (stale progress once resumed the wrong run) and never silently restart (destroys paid-for work).
- Resume → use the STORED tier (don't re-detect), re-read PRD from stored `prd_path` + surviving intermediates, continue from the next step — never skip remaining steps.
- Fresh (chosen or `--fresh`) → `rm -rf {FEATURE_DIR}`, start at Step 0.
- Not found → Step 0.

## Step 0: Input Manifest & Feature ID

1. **Inventory inputs before deep-reading anything.** Print a manifest: PRD path (REQUIRED) · prototypes/mocks (optional) · prior design version (vN redos) · flags in effect.
   - **PRD:** argument path if given; else Glob `docs/prd/**/*.md`, `docs/plans/**/*.md`; ambiguous/none → AskUserQuestion. User pasted requirements inline with no file → write them to `docs/prd/<slug>.md` and confirm via AskUserQuestion FIRST — never plan from conversation-only requirements (unanchored input caused the worst template-fidelity failure on record).
   - **Prototypes/HTML mocks are first-class inputs:** list each file, read them, cite them in design decisions. **Prototype-only rule:** if any scope exists ONLY in prototypes (no PRD requirement text covers it) → AskUserQuestion BEFORE Phase D: "Screens X/Y exist only in the prototype — treat as P0 requirements, P2, or out of scope?" Negative example: silently inventing requirements-table rows from screenshots.
   - **vN redo:** read the prior design doc + its review findings; state in the manifest what is being redone and why.
2. Read the PRD completely: objectives, P0/P1/P2 requirements, constraints, user stories, success metrics, non-goals.
3. `feature_id`: `--feature-id` arg → env `CLAUDE_FEATURE_ID` → PRD filename leading number (`01-meeting-management.md` → `FEAT-01`) → else `FEAT-<slugified-filename-stem>`.
4. `mkdir -p {FEATURE_DIR}`; write initial progress.json (`last_completed_step: 0`, full `remaining_steps`, `flags`).

## Step 0.5: Tier Detection

`--tier` given → confirm with user and proceed. Else extract the seven signals from the PRD + manifest, score against the heuristics table, resolve ambiguity via code graph or user, and present the recommendation with signal counts via AskUserQuestion (offer both tiers). Record tier + tier-adjusted `remaining_steps` (Tier 1 removes 7.6 and 10; `--skip-review` removes 9–12.5).

## Step 1: Codebase Exploration (Phase B)

1. Read `templates/explorer-prompt.md`; fill `[PRD_CONTENT]` (full PRD text — the subagent holds the heavy doc, not you), `[PROJECT_PATH]`, `[EXPLORER_REPORT_PATH]`, `[EXPLORER_SUMMARY_PATH]` (paths under `{FEATURE_DIR}`).
2. Spawn via Task, `subagent_type: "general-purpose"`, `model: "sonnet"` (read-only pattern matching — mechanical tier). Multi-repo: one explorer per repo in parallel.
3. On completion verify each output: exists, non-empty, has expected headings (`## Project Structure`, `## PRD Requirement Mapping`), no leftover `[PLACEHOLDER]` tokens. Any check fails → re-spawn that explorer once; fails again → escalate.
4. Main agent reads ONLY `explorer-summary.md`.

## Step 2: Scope Challenge

**Phase B (immediately after Step 0, parallel with Step 1):**
- **2.4 WebSearch** (per tier table): for each pattern/infra/concurrency approach the plan might introduce — built-in available? current best practice? known footguns? WebSearch unavailable → note "proceeding with in-distribution knowledge" and continue. → `{FEATURE_DIR}/websearch-findings.md`
- **2.7 Backlog crossref:** read `TODOS.md`/`docs/backlog.md` if present — blocking deferred items? bundling opportunities? new work created? → `{FEATURE_DIR}/backlog-crossref.md`

**Phase C (after explorer):** re-read full PRD + `explorer-summary.md` + both Phase B files, then answer:
1. **Reuse** — what existing code already solves each sub-problem (file:line refs)?
2. **Minimum change set** — smallest set achieving the goal; flag deferrable work ruthlessly.
3. **Complexity smell** — >8 files or >2 new services/classes → AskUserQuestion proposing scope reduction (what's overbuilt, minimal alternative); wait for the answer.
4. **Completeness** — default to full coverage/edge cases/error paths; flag only genuinely oceanic scope.
5. **Distribution** — new artifact type (CLI, package, image) must include build/publish pipeline or an explicit deferral flag.

→ `{FEATURE_DIR}/scope-challenge.md`

## Step 3: Major Design Decisions

From PRD + scope-challenge + explorer-summary, identify every significant decision: architecture approach, data model, tech selection (R17-subject), integration pattern, performance tradeoffs. For each: context-complete question, 2-3 options with CONCRETE costs (LoC, latency, files, complexity — not vague pros/cons), and your recommendation with reasoning. Default: present via AskUserQuestion one at a time. With `--questions-upfront`: batch all decisions into the fewest calls (≤4 questions each) NOW — later phases must not prompt again except for escalations.

Example option line: "A) JSONB column on users — zero new infra, queryable, 1 migration. Downside: slower than typed columns at scale."

**→ Append each decision + rationale to `{FEATURE_DIR}/design-decisions.md`** (Step 5a inlines them with `**Design decision:**` prefix and indexes them in the Appendix).

## Step 4: Dependency Verification (R17)

**4a (Phase B, PRD-listed deps) / 4b (post-Step 3, decision-introduced deps) — same process:** for every NEW external dependency: record name+purpose; verify installable (`pip install --dry-run "<pkg>>=<ver>"` / `npm info <pkg> version` / `go list -m <mod>@<ver>` / NuGet check); record `- \`pkg>=X.Y.Z\` — [registry URL] — Purpose — Verified: YES/NO`. Any FAIL at `full` → STOP, AskUserQuestion (alternative / drop requirement / manual verify). At `light`: warn, note "best-effort — manual check recommended", continue. Step 5 requires 4a+4b done. → `{FEATURE_DIR}/dependency-verification.md`

## Step 5: Produce Artifacts (parallel opus subagents)

Tier rules: T1 single design doc (contract inline unless API endpoints exist — then separate contract too). T2 design doc + separate contract if API endpoints (else AskUserQuestion inline-vs-file). Design doc carries `**Planning Tier:** [N]` right after frontmatter.

**Shared subagent preamble** (both 5a and 5b prompts):
```
Read from disk before producing your artifact:
- PRD: [PRD_PATH]
- {FEATURE_DIR}/explorer-report.md and explorer-summary.md
- {FEATURE_DIR}/design-decisions.md, scope-challenge.md, dependency-verification.md
Write your complete artifact to [OUTPUT_PATH] with the Write tool. Do NOT return the content.

CRITICAL: Vertical Slice Mandate + Story Decomposition Method (in the template). Every S-XXX:
vertical slice with Layers, Slice Done Gate, cross-layer ACs, Execution DAG, File Conflict
Matrix. Inline design decisions (**Design decision:** prefix) + Appendix index row each.
CRITICAL: IDs — stories S-XXX; sub-tasks T-{story}-{N}; every numbered Build Guidance sub-task
carries its T-XXX-N prefix.
CRITICAL: Requirements table backfill (MANDATORY second pass) — after writing all stories,
go BACK and fill Jira Story + Tasks columns with concrete S-XXX / T-XXX-N. Never "TBD".
This is the single most common artifact defect — verify before finishing.
```

### 5a. Feature Design Doc → `docs/plans/FEAT-XXX-design.md` or `--output` path (`model: "opus"` — primary artifact)

Pre-flight (BOTH required — do not skip even if the run "feels simple"):
```bash
touch docs/.eng-planning/{feature_id}/.gate-design-doc   # sentinel: agent-gate hook enforces template usage
cp ~/.claude/skills/eng-planning/templates/design-doc-scaffold.md <design-doc-path>
```
Read `templates/design-doc-template.md`; the subagent prompt must include its Producer Instructions + the scaffold path (subagent fills every `<!-- TODO: Fill -->`; no section removed).

Post-production gate:
```bash
~/.claude/skills/eng-planning/scripts/validate-design-doc.sh <design-doc-path>
```
Non-zero → re-spawn with the listed missing sections; do not proceed until it passes. Then `rm -f docs/.eng-planning/{feature_id}/.gate-design-doc`.

Mini-spec invariants (validator-enforced): all 12 fields per S-XXX; 2+ layers or `HORIZONTAL-JUSTIFIED`; Layers ∈ {DB, API, BE, FE, Infra, Config}; Spec Reference `S-XXX @ <design-doc-path>#s-xxx`; ≥1 cross-layer AC for multi-layer stories; Slice Done Gate in every Test Plan; Build Guidance names exact patterns/classes/files (never "follow SOLID"); Depends On/Blocks authoritative for the DAG — no false edges; additive same-file changes may parallelize (note "(additive, safe to parallel)" in the File Conflict Matrix); one story per JTBD by default + fragmentation smell test; complex stories document phases under `**Sub-tasks:**` in Build Guidance.

### 5b. API Contract → `docs/contracts/<feature>.md` (`model: "opus"`)

Per **R7** (Contract-First): one contract per feature with cross-boundary data flow. Follow the "API Contract Summary" section of `design-doc-template.md`: endpoint signatures, data models, error shapes, shared enums, SSE events. Spec-registry frontmatter at `full` (below).

After D: `ls` both artifacts to confirm they exist; keep all intermediates (cleanup only in Step 13).

## Step 6: Codepath Coverage & Failure Modes

Append to the design doc per the template's "Codepath Coverage Diagram" and "Failure Modes" sections. Any `Silent? Yes` failure mode = P0 finding.

## Step 7: DAG Validation & Execution Plan

Single-task plan → record "single-task DAG, no conflicts possible" and checkpoint. Otherwise:
1. **Integrity:** no cycles (break the weakest edge), no orphan tasks, no phantom `Depends On` refs, batches recalculated from edges (same-batch tasks must share no blocking edge).
2. **File conflicts:** using `explorer-report.md`, list ALL files each same-batch story touches (tests/config/shared types included). Overlap → additive+non-overlapping = "(additive, safe to parallel)"; conflicting = move one story later + add edge. Shared type files → extract a `HORIZONTAL-JUSTIFIED` S-000 or confirm additive.
3. **Append `## Worktree Execution Plan`** to the design doc: agent count (max parallel = largest batch), batch table (Batch | Stories | Blocked By | Max Agents), worktree assignment (single feature worktree; orchestrator waits for each batch's Slice Done Gates; first-to-finish commits, later tasks pull+auto-merge, conflict → ESCALATE N=1), conflict notes.

## Step 7.5: PRD Traceability (pre-approval)

```bash
touch docs/.eng-planning/{feature_id}/.gate-traceability   # sentinel: agent-gate hook enforces pipeline template
mkdir -p {FEATURE_DIR}/traceability
```
- **Tier 1:** 2 parallel sonnet tracers per `templates/tier1-prompts.md`; main agent merges to `traceability-matrix.md` with VERDICT. FAIL → fix, re-run both (max 1 iteration).
- **Tier 2:** Read `templates/traceability-pipeline.md`; fill `{TRACE_DIR}` = `{FEATURE_DIR}/traceability/`, `{PRD_PATH}`, `{ARTIFACT_PATHS}`, `{CONTRACT_PATHS}`; run the 3-agent pipeline (2 sonnet tracers ∥, then opus synthesis).

Read `traceability-matrix.md` from disk (Reporting Integrity applies — echo its verdict, never restate from memory). PASS → Step 7.6/8. FAIL → fix every gap per the template's Gap Resolution Rules, re-run the FULL pipeline fresh (max 2 iterations); persistent gaps → report them in Step 8. Then `rm -f docs/.eng-planning/{feature_id}/.gate-traceability`.

## Step 7.6: Quality Synthesis (Tier 2 only; `model: "opus"`)

```bash
touch docs/.eng-planning/{feature_id}/.gate-quality
```
Read `templates/quality-synthesis-prompt.md`; fill `[PRD_PATH]`, `[ARTIFACT_PATHS]`, `[CONTRACT_PATHS]`, `[TRACEABILITY_MATRIX_PATH]` = `{FEATURE_DIR}/traceability/traceability-matrix.md`, `[EXPLORER_REPORT_PATH]` = `{FEATURE_DIR}/explorer-report.md`, `[QUALITY_SYNTHESIS_PATH]` = `{FEATURE_DIR}/quality-synthesis.md`. Spawn general-purpose/opus (holistic fresh-eyes coherence check). Read the findings; fix SPECIFIABLE autonomously; surface REQUIRES_DECISION via AskUserQuestion. Then `rm -f docs/.eng-planning/{feature_id}/.gate-quality`.

**MANDATORY CHECKPOINT — you are NOT done.** Steps 8-13 (review gate) are non-negotiable unless `--skip-review` is set (which still requires Step 8 approval + Step 13 with intermediates kept + DONE_WITH_CONCERNS). Do not declare victory after producing artifacts. Proceed to Step 8 now.

## Step 8: Present for Approval

Present: artifact paths with 1-line summaries, story/task counts, new questions (AskUserQuestion), remaining 7.5 gaps if any. Ask: "Approve to proceed to engineering review? Describe any changes first." Rejected → edit, re-present (loop). Approved → Step 9 (or Step 13 under `--skip-review`).

## Step 9: Engineering Review

- **Tier 1:** 2 parallel sonnet reviewers (Structure + Completeness) per `templates/tier1-prompts.md`; merge → fix SPECIFIABLE inline → report REQUIRES_DECISION → skip Step 10, go to 11.
- **Tier 2:** Read `templates/review-prompt.md`; fill `[ARTIFACT_PATHS]`, `[PRD_PATH]`, `[PROJECT_PATH]`, `[REVIEW_FINDINGS_PATH]` = `{FEATURE_DIR}/review-findings.md`, `[TRACEABILITY_MATRIX_PATH]` = `{FEATURE_DIR}/traceability/traceability-matrix.md`. Spawn `subagent_type: "general-purpose"`, `model: "opus"` (adversarial judgment tier). Reviewer sees ONLY artifacts + PRD (no planning conversation) and writes findings to disk. Verify the file exists; read it from disk.

This internal reviewer fulfils the VIBE protocol's independent-review requirement in-skill; for an interactive human-facing pass, `/plan-eng-review` (and `/plan-design-review` for UI features) exist as follow-ups.

## Step 10: Auto-Fix Loop (Tier 2 only: max 1 iteration)

Categorize findings: **SPECIFIABLE** (fix by editing an artifact — do it autonomously) vs **REQUIRES_DECISION** (AskUserQuestion). After fixes, re-spawn Step 9 to verify. Track: N findings / X fixed / Y escalated. Issues persist after the cap → log as known issues in the design doc and proceed.

## Step 11: Pre-Final

Confirm all artifacts on disk. No cleanup yet — Step 12 needs them.

**MANDATORY CHECKPOINT — Steps 12-13 are not optional.** Review fixes may have broken traceability or coherence; verify final state, then clean up.

## Step 12: Final PRD Traceability Gate

```bash
touch docs/.eng-planning/{feature_id}/.gate-traceability
rm -rf {FEATURE_DIR}/traceability/ && mkdir -p {FEATURE_DIR}/traceability/
```
- **Tier 1:** 2 sonnet tracers + 1 opus synthesis per `templates/tier1-prompts.md` (parallel tracers, fresh agents).
- **Tier 2:** re-run `templates/traceability-pipeline.md` with all FRESH agents (tracers sonnet, synthesis opus — Step 7.5's agents are gone).

PASS → `PRD Traceability: VERIFIED (100% forward trace, confirmed post-review)`. FAIL → fix gaps only (do NOT re-enter Steps 9-10), max 1 full re-run; persistent gaps → `DONE_WITH_CONCERNS` + gap list. Then `rm -f docs/.eng-planning/{feature_id}/.gate-traceability`.

## Step 12.5: Post-Review Spot-Check (`model: "sonnet"` — targeted, not a re-review)

Read `templates/spot-check-prompt.md`; fill `[ARTIFACT_PATHS]`, `[CONTRACT_PATHS]`, `[REVIEW_FINDINGS_PATH]` = `{FEATURE_DIR}/review-findings.md`, `[SPOT_CHECK_PATH]` = `{FEATURE_DIR}/post-review-spotcheck.md`. Spawn general-purpose/sonnet. Question: "did the review-cycle fixes break anything?" Regressions → fix directly; a regression needing a design decision → AskUserQuestion.

## Step 13: Cleanup & Output

1. Final checkpoint (`last_completed_step: 13`, `remaining_steps: []`). 2. `rm -rf docs/.eng-planning/{feature_id}/` — EXCEPT under `--skip-review`: keep intermediates and say so. 3. Report (every PASS/count echoed from disk per Reporting Integrity):

```
STATUS: DONE | DONE_WITH_CONCERNS | BLOCKED
ARTIFACTS: <design-doc-path> — [arch + N decisions + N stories]
           docs/contracts/<feature>.md — [N endpoints, N models]
INTERMEDIATES: cleaned | kept (--skip-review)
REVIEW: [passed after N iterations | concerns listed | SKIPPED via --skip-review]
PRD TRACEABILITY: 7.5 [PASS|N gaps] · 12 [VERIFIED 100%|N gaps listed]
QUALITY SYNTHESIS: [N issues resolved | N remaining]   SPOT-CHECK: [clean | N fixed]
NEXT: update .claude/phase.json → FEATURE_SPECS_APPROVED; orchestrator may spawn coders for S-XXX
```

BLOCKED = unverified dependency, unresolved design decision, or missing PRD information — state which.

## Spec-Registry Frontmatter (`full` level)

Every produced spec starts with YAML frontmatter carrying `domain: <feature-domain>`, `skills: [<relevant-skills>]`, `schemas: [<relevant-schema-paths>]`. Enables the orchestrator's Spec Context Injection. At `light`: recommended, not required.

## Red Flags — STOP Immediately

Edit/Write on implementation files · generic Build Guidance ("follow SOLID") · skipping/proceeding-past dependency verification at `full` · deciding without presenting options · artifacts outside `docs/` (except an explicit `--output` path) · missing required sections/fields · horizontal-layer decomposition or single-layer story without `HORIZONTAL-JUSTIFIED` · artificial Depends On edges · missing `Layers`/`Slice Done Gate` · quoting a table you have not Read from disk this phase. All mean: you've confused your role — return to planning.

## Escalation

Ambiguous PRD requirement after re-read → AskUserQuestion. Dependency unverifiable, no alternative → BLOCKED. Complexity check suggests fundamental redesign → present findings, wait. Explorer shows the codebase can't support the PRD → escalate immediately. Prototype-only scope with no user answer → do not enter Phase D. Do not guess.
