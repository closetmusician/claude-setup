---
name: eng-planning
description: "Feature-level engineering planning with conditional depth (Tier 1/2/3). Reads approved PRD, auto-detects complexity, and scales planning rigor accordingly. Tier 1 (lightweight) for minor single-repo changes, Tier 2 (standard) for moderate features, Tier 3 (comprehensive) for large-scale/multi-repo/high-risk. Supports --tier override. Produces feature design doc + optional API contract. Invoke after PRD approval."
---

# Engineering Planning

## Overview

**You plan. You NEVER implement.**

The engineering planner reads an approved PRD, explores the codebase, surfaces major design decisions, and produces all architecture/design artifacts needed before BUILD phase. You produce ZERO implementation code.

**Two-level design workflow:**
- **eng-planning** (this skill) — Feature-level planning. Spans ARCHITECTURE_APPROVED to FEATURE_SPECS_APPROVED. Produces a **feature design doc** (always) plus a separate **API contract** (when API boundaries exist or Tier 3 requires it). Runs once per feature or group of features.
- **code-architect** — Task-level design. Runs per T-XXX during orchestration. Reads the task mini-spec produced here and outputs file-level design (which files to create/modify, which patterns to follow). Much narrower scope.

**Core principle:** Your only tools are Agent (to spawn explorer/reviewer), Read/Glob/Grep (to understand code), Write (to produce docs/ artifacts), AskUserQuestion (to get decisions), and Bash (read-only commands, dependency checks, and `docs/.eng-planning/` cleanup). If you are about to Edit/Write a .py/.ts/.js file, you have violated your role.

---

## Language Standard (Non-Negotiable)

All artifacts produced by this skill — design docs, explorer reports, scope challenges, and all subagent output — must be understandable by a smart CS senior who has NOT read this codebase before. This applies to YOU and to every subagent you spawn.

### The Structure: Impact → Mechanism → Code

For every bug, problem, or technical description:

1. **User sees:** What the end user actually experiences. Use concrete language ("the chat area stays blank", "every message after the first block also gets blocked").
2. **Why this happens:** The root cause as cause-and-effect in 1-3 sentences. Use active voice, concrete nouns, and build from observable behavior to mechanism. A reader should understand the logic without knowing any variable names.
3. **Code location:** `file.ts:NNN` — what the code does wrong, in one sentence of plain English.

### What This Forbids

**BANNED: Variable-name-soup without context.** Never write sentences that ONLY name internal variables and state transitions without explaining user impact or mechanism. Code names are valuable — but they must come AFTER the plain explanation, not instead of it.

BAD (names without context):
> "If chatMessages.refresh() resolves before isLoading goes false, hasStreamingAssistant becomes false creating a zero-render window"

GOOD (plain explanation that preserves code names):
> "**User sees:** Agent finishes its work but the response area stays completely blank. **Why:** Two UI components race to display the response. The streaming view (`hasStreamingAssistant`) gives up because the stream ended, at the same moment the history view hasn't loaded the saved message yet (the `chatMessages.refresh()` callback and `isLoading` flag resolve in the same React render batch). Neither component renders anything, and that blank state persists. **Root cause:** `Chat.tsx:1287`"

The code names (`hasStreamingAssistant`, `chatMessages.refresh()`, `isLoading`) are all present — but they're woven into an explanation that makes sense without them.

### Rules for Requirements Tables (P0/P1/P2)

The requirements tables at the top of the design doc are the first thing stakeholders read. They are the **contract with stakeholders** — not with engineers.

**BANNED in requirements tables:** Internal variable names, config field names, framework-specific terms, or implementation details. Those belong in Build Guidance inside the story's mini-spec.

BAD (implementation details leaked into requirement):
> "CP-1: Root cause investigation: confirm whether false positive originates from Bedrock guardrail MISCONDUCT/PROMPT_ATTACK at MEDIUM, EMAIL anonymization, or another source"

GOOD (user-facing language matching the PRD):
> "CP-1: Determine why normal messages like 'hello' are being blocked by content policy, and document the fix plan (PRD JTBD-1)"

**Rules:**
1. Each requirement MUST cite its parent PRD requirement or JTBD (e.g., "PRD JTBD-1", "PRD CP-2").
2. Requirement descriptions use the PRD's user-facing language. If the PRD says "benign messages must never be blocked," the design doc says the same — not "disable MISCONDUCT filter at MEDIUM sensitivity."
3. Implementation specifics (which file, which config field, which variable) go EXCLUSIVELY in the story's Build Guidance section.
4. The requirements table is a contract with stakeholders. Build Guidance is a contract with engineers. Don't mix them.

### Rules for Build Guidance

- Every instruction explains WHAT the developer is doing (the goal) and WHY, then names the specific code
- File paths, line numbers, function names, and class names are mandatory — they anchor the explanation, they don't replace it

### Enforcement

Include this preamble in EVERY subagent prompt (explorer, artifact producer, reviewer):
```
LANGUAGE STANDARD: All output must be understandable by a smart CS senior unfamiliar with this codebase. For every bug/problem: lead with "User sees:" (the visible behavior), then "Why:" (cause-and-effect mechanism in plain terms with key function/class/variable names woven in), then code reference. Always preserve specific code names — but embed them in explanations that make sense without them. REQUIREMENTS TABLES (P0/P1/P2) must use user-facing language matching the PRD — no variable names, config fields, or framework terms. Implementation details go in Build Guidance only. Each requirement must cite its parent PRD JTBD or requirement ID.
```

---

## Vertical Slice Mandate (Tracer Bullets)

**Every T-XXX must be a vertical slice.** Full rules, Jira hierarchy mapping, story consolidation heuristics, and decomposition examples live in `~/.claude/skills/eng-planning/templates/design-doc-template.md` — the Step 5a subagent reads them there. The main agent enforces the principle; the template carries the details.

**Key invariants (always loaded for red-flag detection):**
- BANNED: horizontal layer planning (all schemas → all APIs → all UI)
- Single-layer tickets require `HORIZONTAL-JUSTIFIED: [reason]`
- T-XXX = Jira Story. Sub-tasks live in Build Guidance, not as separate T-XXX entries.
- Fragmentation smell test: story count > N + ceil(N/2) where N = JTBD count requires justification.

## VIBE Level Detection

**Execution:** Read `.claude/phase.json` in Step 0 (if it exists). Store `vibe_level` in `progress.json`. On resume, reuse the stored value.

- `"full"` — eng-planning is mandatory after PRD approval. All artifacts required. Dependency verification enforced. **Phase gate enforced:** if phase is before `ARCHITECTURE_APPROVED`, block and report.
- `"light"` — eng-planning is available but optional. When used, still produces all artifacts but dependency verification is best-effort and spec-registry frontmatter is optional. Phase gate: warn but continue.
- **Default:** If `.claude/phase.json` is absent or `"vibe_level"` is missing, treat as `"full"`

At `light` level:
- **Skip spec-registry frontmatter** — optional, not required
- **Skip mandatory phase gate check** — warn, do not block
- **Dependency verification** — best-effort (warn, do not block)
- **All other steps** — follow normally

## Planning Tiers

The planning pipeline scales its depth and ceremony based on the complexity of the PRD. Tier is determined in Step 0.5 (after reading the PRD) and stored in `progress.json`. The user always confirms the tier via AskUserQuestion. CLI override: `--tier 1|2|3`.

### Tier Overview

| Aspect | Tier 1 (Lightweight) | Tier 2 (Standard) | Tier 3 (Comprehensive) |
|--------|---------------------|-------------------|----------------------|
| **Scope** | Minor features, single-repo, <3 requirements | Moderate features, moderate risk | Large-scale, multi-repo, high-risk, >8 requirements |
| **Explorer** | Single Sonnet, no multi-repo split | Multi-repo split IF feature requires it | Full multi-repo split |
| **Step 7.5 (Pre-approval traceability)** | SKIP | Full 3-agent pipeline | Full 3-agent pipeline |
| **Step 7.6 (Quality synthesis)** | SKIP | Opus subagent | Opus subagent |
| **Step 9 (Eng review)** | Simplified: single Sonnet, PRD + architecture only | Full template, 1 review iteration max | Full template, 2 iterations max |
| **Step 10 (Auto-fix)** | 0 re-reviews (fix specifiable, report rest) | 1 iteration max | 2 iterations max |
| **Step 12 (Final traceability)** | Simplified: 1-2 Sonnet agents, simplified matrix | Full 3-agent pipeline | Full 3-agent pipeline |
| **Artifacts** | Single design doc (contract inline if no API) | Design doc + contract if API exists | Both artifacts always |
| **Step 2.4 (WebSearch)** | Best-effort (skip unless new dependency/framework) | Targeted search (ask before skipping) | Full |

**Non-negotiable across ALL tiers:** Vertical slice mandate, DAG optimization, design decisions (Step 3), dependency verification (Step 4), codepath coverage (Step 6), DAG validation (Step 7), Step 12.5 (post-review spot-check), Step 13 (cleanup). These never scale down.

### Tier Detection Heuristics (Step 0.5)

Signals extracted from the PRD:

| Signal | Tier 1 | Tier 2 | Tier 3 |
|--------|--------|--------|--------|
| P0 requirement count | <3 | 3-8 | >8 |
| Repos touched | 1 | 1-2 | 3+ |
| New external dependencies | 0 | 1-3 | 4+ |
| New DB migrations | 0-1 | 2-4 | 5+ |
| New services/infra | 0 | 0-1 | 2+ |
| Architectural risk | Low | Medium | High |

**Scoring:** Count how many signals fall into each tier column. The tier with the most signals wins. Ties break upward (prefer higher tier). If signals are split across all three tiers, classify as **ambiguous** and query the code-review-graph (if a graph exists for the project) for impact assessment. If no graph exists or still ambiguous, ask the user.

## When to Use

**Use this skill when:**
- PRD is approved and phase is ARCHITECTURE_APPROVED or later
- User says "plan the architecture", "design the feature", "produce specs"
- Starting a new feature that needs architecture decisions, API contracts, or task decomposition
- Multiple features need coordinated design (shared data models, API boundaries)

**Do NOT use when:**
- You are the coder subagent implementing a T-XXX task
- Task-level file design is needed (use code-architect instead)
- PRD is not yet approved (use prd-writer or prd-review first)
- Simple config/script changes that need no architecture

## Allowed Tools (Whitelist)

| Tool | Purpose | Constraint |
|------|---------|------------|
| **Agent** | Spawn explorer and reviewer subagents | Isolated context |
| **Read** | Read PRD, existing code, config files | Any file |
| **Glob** | Find files by pattern | Any directory |
| **Grep** | Search code for patterns, usages | Any directory |
| **Write** | Produce design artifacts + intermediate files | `docs/` directory ONLY (includes `docs/.eng-planning/` for intermediates) |
| **AskUserQuestion** | Get design decisions, escalate | Throughout |
| **Bash** | Read-only commands, dependency checks, `docs/.eng-planning/` cleanup | `pip install --dry-run`, `npm info`, `git log`, `find`, `wc`, `rm -rf docs/.eng-planning/`, `mkdir -p docs/.eng-planning/` — NO writes outside `docs/.eng-planning/` |
| **WebSearch** | Research patterns, best practices, footguns | When checking architectural approaches |
| **MCP tools** (code-review-graph) | `get_minimal_context_tool`, `get_hub_nodes_tool` — graph-based tier detection | Step 0.5 only, when graph exists |

## Forbidden Actions

**NEVER do these:**
- NEVER write implementation code (.py, .ts, .js, .jsx, .tsx, .go, .rs, etc.)
- NEVER edit files outside `docs/` — architecture artifacts go in docs/ only
- NEVER skip dependency verification at `full` VIBE level (R17)
- NEVER proceed with unverified dependencies — STOP and escalate
- NEVER use `git stash` or modify working tree state
- NEVER make design decisions without surfacing them to the user first
- NEVER produce task mini-specs without ALL required fields (Priority, Depends On, Objective, Requirements, Build Guidance, Acceptance Criteria, Edge Cases, Test Plan)

If you catch yourself about to write code: STOP. You are the planner, not the builder.

---

## Execution Model: Parallelism DAG

Steps are grouped into phases. **Within each phase, launch all independent work in parallel.** Only wait for a phase to complete before starting the next phase that depends on it.

```
PHASE A: Bootstrap
  Step 0: Locate & read PRD
  ↓ (PRD content available)
  Step 0.5: Tier Detection (auto-detect + user confirm, or CLI override)
  ↓ (tier confirmed, remaining_steps adjusted)

PHASE B: Parallel Discovery (all items launch simultaneously)
  ├─ Step 1: Codebase Exploration (explorer subagent(s) — write to disk)
  ├─ Step 4: Dependency Verification (deps are listed in PRD — no need to wait for design decisions)
  ├─ Step 2 partial: WebSearch checks + backlog cross-reference (need only PRD, not explorer report)
  ↓ (all Phase B items complete)

PHASE C: Analysis & Decisions (sequential — each depends on prior)
  Step 2 (full): Scope Challenge synthesis (reads explorer-summary.md from disk + Phase B intermediates)
  ↓
  Step 3: Major Design Decisions (needs scope challenge; user interaction is blocking)
  ↓ (all decisions made)

PHASE D: Artifacts (parallel Opus subagents — read from disk, write to disk)
  ├─ Step 5a: Feature Design Doc ─── Opus subagent reads intermediates, writes docs/plans/
  ├─ Step 5b: API Contracts ─────── Opus subagent reads intermediates, writes docs/contracts/
  ↓ (all artifacts written, verified by main agent)

PHASE E: Enrichment (parallel, append to FEAT design doc)
  ├─ Step 6: Codepath Coverage Diagrams
  ├─ Step 7: Worktree Parallelization Strategy
  ↓ (enrichment complete)

PHASE E.5: PRD Traceability (sequential — must pass before presenting)
  Step 7.5: Run 3-agent traceability pipeline (template) → fix gaps → re-check (max 2 iterations)
  ↓ (traceability verified or gaps reported)

PHASE E.6: Quality Synthesis (Opus subagent — reads all artifacts from disk)
  Step 7.6: Independent coherence, consistency & quality check on draft artifacts
  ↓ (quality issues fixed or reported)

PHASE F: Review Gate (sequential)
  Step 8: Present Written Artifacts → approve to proceed to engineering review
  ↓
  Step 9: Spawn Engineering Review (subagent — writes findings to disk)
  ↓
  Step 10: Auto-Fix Loop (max 2 iterations)
  ↓
  Step 11: Pre-Final Output
  ↓
  Step 12: Final PRD Traceability Gate (agents read/write disk) → verify post-review
  ↓
  Step 12.5: Post-Review Coherence Spot-Check (Sonnet — targets only review-introduced changes)
  ↓
  Step 13: Final Cleanup & Output
```

### Multi-Repo Explorer Splitting

For projects with separate frontend/backend repos (e.g., Angular + .NET), split the explorer into **parallel subagents per repo**. Each explorer gets the same PRD but scoped to its sub-repo:
- Explorer A: `{project}/frontend-repo/` — FE patterns, components, services, test infra
- Explorer B: `{project}/backend-repo/` — BE patterns, API routes, DB schema, migrations

Merge their reports before Phase C. This cuts exploration wall-clock time roughly in half.

### Phase B: What Can Run Early

Steps 4, 2.4, and 2.7 need only the PRD (not the explorer report) — launch them immediately after Step 0 in parallel with exploration.

### Parallelism Rules

1. **Within a phase:** Launch all items simultaneously via multiple Agent/Bash/Read calls in a single message.
2. **Between phases:** Wait for ALL items in the prior phase before starting the next.
3. **User interaction (AskUserQuestion) is blocking** — Step 3 decisions are inherently sequential (one question at a time). Do not attempt to parallelize user prompts.
4. **Artifact writes are parallel** — Step 5a (feature design doc) and Step 5b (API contract) read from the same inputs (design decisions, explorer report) and can be written simultaneously.
5. **Review is sequential** — Steps 9-10 depend on Step 8 approval. No shortcuts.

### Intermediate Files (Context Preservation)

Planning runs are long. Subagent reports vanish when the agent returns. Conversation context compresses. To prevent data loss between phases, **write intermediate outputs to disk** so later phases can re-read them instead of relying on conversation memory.

**Working directory:** `docs/.eng-planning/` (dot-prefixed = working files, not final artifacts)

| Phase | File | Written By | Consumed By |
|-------|------|-----------|-------------|
| B | `docs/.eng-planning/explorer-summary.md` | Step 1 (explorer subagent writes directly to disk) | Steps 2, 3 (main agent uses THIS instead of the full explorer report) |
| B | `docs/.eng-planning/explorer-report.md` | Step 1 (explorer subagent writes directly to disk) | Steps 5a, 5b subagents, Step 9 reviewer (full report on disk for subagents) |
| B | `docs/.eng-planning/explorer-report-fe.md` | Step 1 (FE explorer subagent, multi-repo only) | Merged into explorer-report.md by main agent |
| B | `docs/.eng-planning/explorer-report-be.md` | Step 1 (BE explorer subagent, multi-repo only) | Merged into explorer-report.md by main agent |
| B | `docs/.eng-planning/dependency-verification.md` | Step 4 | Steps 5a subagent, 8 |
| B | `docs/.eng-planning/websearch-findings.md` | Step 2.4 | Step 2 (full), Step 5a subagent |
| B | `docs/.eng-planning/backlog-crossref.md` | Step 2.7 | Step 2 (full) |
| C | `docs/.eng-planning/scope-challenge.md` | Step 2 (full synthesis) | Step 3, Step 5a subagent |
| C | `docs/.eng-planning/design-decisions.md` | Step 3 (accumulated after each user answer) | Steps 5a, 5b subagents |
| E.5 | `docs/.eng-planning/traceability/forward-trace.md` | Step 7.5 Agent 1 (Forward Tracer) | Agent 3 (Synthesis) |
| E.5 | `docs/.eng-planning/traceability/reverse-trace.md` | Step 7.5 Agent 2 (Reverse Tracer) | Agent 3 (Synthesis) |
| E.5 | `docs/.eng-planning/traceability/traceability-matrix.md` | Step 7.5 Agent 3 (Synthesis) | Steps 8, 10 |
| E.6 | `docs/.eng-planning/quality-synthesis.md` | Step 7.6 (Opus quality subagent writes to disk) | Main agent (fix issues before Step 8) |
| F | `docs/.eng-planning/review-findings.md` | Step 9 (reviewer subagent writes directly to disk) | Step 10 |
| F | `docs/.eng-planning/post-review-spotcheck.md` | Step 12.5 (Sonnet spot-check subagent) | Step 13 (main agent) |
| All | `docs/.eng-planning/progress.json` | Steps -1 through 13 (checkpoint after each major step) | Step -1 (resume detection) |

**Rules:**
1. **Subagents write to disk, not to main context.** Explorer, reviewer, artifact producers, and quality synthesis agents all write their output to disk using the Write tool. The main agent reads from disk — it does NOT ingest subagent return values. This is the primary context hygiene mechanism.
2. **Re-read from disk at phase boundaries.** At the start of Phase C, read `explorer-summary.md` + `websearch-findings.md` + `backlog-crossref.md` from disk — do not rely on conversation memory of the subagent output.
3. **Append, don't overwrite** for `design-decisions.md` — each user answer adds to the file.
4. **No intermediate cleanup until Step 13.** Intermediate files persist throughout the entire pipeline because subagents in later phases read from them. Only Step 13 (Final Cleanup) deletes the `docs/.eng-planning/` directory.
5. **The PRD is the source of truth — always read it in full when needed.** Never summarize the PRD into a lossy intermediate. It contains critical details (field constraints, business rules, edge cases in AC specs) that a summary would lose. Re-read the PRD from disk whenever a step needs it.
6. **The explorer report is a codebase summary — NEVER hold the full report in main agent context.** The explorer subagent writes both `explorer-report.md` (full) and `explorer-summary.md` (~50 lines) to disk. The main agent reads ONLY the summary. The full report stays on disk for subagents (Steps 5a, 5b, 9) to reference.
7. **Context budget:** The main agent should never hold the full PRD AND the full explorer report simultaneously. Read the PRD when needed, work from the explorer summary, and re-read targeted sections of intermediates from disk rather than holding everything in conversation memory.

---

## Step -1: Resume Detection

Before starting any work, check if a prior planning session left state on disk.

1. **Check for progress file** — `Glob: docs/.eng-planning/progress.json`
2. **If found:** Read the file. It contains the fields defined in the Checkpoint Protocol below (`prd_path`, `last_completed_step`, `tier`, `remaining_steps`, `artifacts_produced`, `step_8_approved`, `review_iteration`).
   - Report to the user: "Resuming eng-planning from Step [N] at **Tier [T]**. Steps completed: [list]. Next step: [N]."
   - **Use the stored tier** — do not re-detect. The tier was confirmed by the user in Step 0.5.
   - Re-read the full PRD from the `prd_path` stored in `progress.json`.
   - Re-read any intermediate files that still exist in `docs/.eng-planning/` (they survive until Step 13 cleanup).
   - **After determining resume point, proceed to that step. Do NOT skip remaining steps.**

3. **If not found:** Start fresh from Step 0. Create the progress file after Step 0 completes (see checkpoint instructions below).

### Checkpoint Protocol

After each major step completion, write/update `docs/.eng-planning/progress.json` with the current state. The file is a simple JSON object — overwrite it each time. Fields:

| Field | Type | Description |
|-------|------|-------------|
| `prd_path` | string | Absolute or repo-relative path to the PRD |
| `last_completed_step` | number | The step number that just finished |
| `tier` | number\|null | Planning tier (1, 2, or 3). Set in Step 0.5. null before tier detection. |
| `vibe_level` | string | `"full"` or `"light"`. Read from `.claude/phase.json` in Step 0. |
| `remaining_steps` | number[] | Steps still to execute (tier-adjusted after Step 0.5) |
| `artifacts_produced` | string[] | Paths to final artifacts written so far |
| `step_8_approved` | boolean | Whether Step 8 user approval was obtained |
| `review_iteration` | number | Current review iteration count (0, 1, or 2) |

**Checkpoint steps:** 1, 2, 3, 5, 6, 7, 7.5, 7.6, 8, 9, 10, 11, 12, 12.5, 13. Step 0 creates the initial file. Step 4 runs in parallel with Step 1 so its completion is recorded when Step 1's checkpoint fires (or whichever Phase B step completes last).

## Step 0: Locate PRD

1. **Check argument** — If the user passed a path (e.g., `/eng-planning docs/prd/features/FEAT-001-search.md`), use that file.
2. **Search if no argument** — Look in `docs/prd/`, `docs/prd/features/`, `docs/plans/` for recent PRD files:
   ```
   Glob: docs/prd/**/*.md
   Glob: docs/plans/**/*.md
   ```
3. **Ambiguous?** — If multiple candidates or none found, use AskUserQuestion:
   > "I found [N] potential PRD files: [list]. Which one should I plan against? Or provide a path."
4. **Read the PRD** — Parse it completely. Extract: objectives, requirements (P0/P1/P2), constraints, user stories, success metrics, non-goals.
5. **Store PRD path** — Record the PRD path in `progress.json` for subagent use.

**→ Checkpoint:** Write `docs/.eng-planning/progress.json` with `last_completed_step: 0`, `prd_path` set, `remaining_steps: [0.5, 1, 2, 3, 5, 6, 7, 7.5, 7.6, 8, 9, 10, 11, 12, 12.5, 13]`, empty `artifacts_produced`, `step_8_approved: false`, `review_iteration: 0`, `traceability_pass: false`, `tier: null`.

## Step 0.5: Tier Detection

**Purpose:** Determine planning depth before any exploration or artifact production. This step runs after reading the PRD but before any subagent spawning.

### CLI Override

If the user passed `--tier 1|2|3` (e.g., `/eng-planning --tier 1 docs/prd/FEAT-001.md`), skip detection and use the specified tier. Still confirm with the user:
> "CLI override: Tier [N] ([Lightweight|Standard|Comprehensive]). Proceeding with [summary of what this tier means]. Confirm?"

### Auto-Detection

1. **Extract PRD signals.** From the PRD content read in Step 0, count:
   - Number of P0 requirements
   - Number of distinct repos/services mentioned (look for repo paths, service names, deployment targets)
   - Number of new external dependencies listed
   - Number of DB migrations implied (new tables, schema changes)
   - Number of new services or infrastructure components
   - Architectural risk indicators (new patterns, breaking changes, security-sensitive, multi-tenant)

2. **Score against thresholds** from the Tier Detection Heuristics table above (Planning Tiers section).

3. **Ambiguous signals?** If signals are split across all three tiers (no clear majority):
   - Check if a code-review-graph exists for the project: `ls .code-review-graph/graph.db 2>/dev/null`
   - **If graph exists:** Query it for impact assessment:
     - Use `get_minimal_context_tool` with `task: "assess complexity of PRD requirements"` to get graph stats and risk score
     - Use `get_hub_nodes_tool` to check if PRD-mentioned modules are architectural hotspots
     - If the feature touches hub nodes or bridge nodes → bump tier upward
   - **If no graph:** Proceed with the majority-signal tier and ask the user to confirm

4. Present tier recommendation with signal counts via AskUserQuestion. Offer all 3 tiers as options with descriptions. Wait for confirmation.

5. **Record the tier.** After user confirms, the tier governs all subsequent steps.

### Tier-Specific Step List

After tier is confirmed, update `remaining_steps` in `progress.json`:

- **Tier 1:** `[1, 2, 3, 5, 6, 7, 8, 9, 11, 12, 12.5, 13]` (skip 7.5, 7.6, 10)
- **Tier 2:** `[1, 2, 3, 5, 6, 7, 7.5, 7.6, 8, 9, 10, 11, 12, 12.5, 13]` (full, but reduced ceremony within steps)
- **Tier 3:** `[1, 2, 3, 5, 6, 7, 7.5, 7.6, 8, 9, 10, 11, 12, 12.5, 13]` (full pipeline)

**→ Checkpoint:** Update `progress.json` — `last_completed_step: 0.5`, set `tier: 1|2|3`, update `remaining_steps` per tier.

## Step 1: Codebase Exploration

**Phase B — launch in parallel with Steps 4, 2.4, 2.7.**

Spawn explorer subagent(s) to map the codebase against PRD requirements.

### Tier-Conditional Behavior
- **Tier 1:** Single Sonnet explorer. No multi-repo split regardless of project structure. Produces a focused report on the most relevant module(s) only.
- **Tier 2:** Multi-repo split IF the feature requires changes in multiple repos (as determined by PRD signals in Step 0.5). Otherwise single explorer.
- **Tier 3:** Full multi-repo split for all multi-repo projects.

1. **Read the template** — Read `~/.claude/skills/eng-planning/templates/explorer-prompt.md`
2. **Fill placeholders:**
   - `[PRD_CONTENT]` — Re-read the full PRD from the path stored in `progress.json`. Pass the full text into the subagent prompt. The subagent holds the heavy document, not you.
   - `[PROJECT_PATH]` — Absolute path to the project root (or sub-repo root for split explorers)
   - `[EXPLORER_REPORT_PATH]` — `docs/.eng-planning/explorer-report.md` (or `-fe.md`/`-be.md` for multi-repo)
   - `[EXPLORER_SUMMARY_PATH]` — `docs/.eng-planning/explorer-summary.md`
3. **Multi-repo projects (Tier 2-3 only, see above):** If the project has separate FE/BE repos AND the tier allows splitting, spawn **one explorer per repo** in parallel (see "Multi-Repo Explorer Splitting" above). Scope each explorer's `[PROJECT_PATH]` to its sub-repo. Each writes to its own `-fe.md`/`-be.md` report path. After both complete, merge into `explorer-report.md`.
4. **Spawn via Agent tool** — Use `subagent_type: "general-purpose"`, `model: "sonnet"`. Explorers are read-only pattern matching — Sonnet is the right tier. Each explorer runs in isolated context and **writes its report + summary directly to disk**. The main agent does NOT read the subagent return value.
5. **Wait for all explorers to complete.** Verify output files exist and are valid:
   ```bash
   ls -la docs/.eng-planning/explorer-report.md docs/.eng-planning/explorer-summary.md
   ```
   For each output file, verify: (a) file exists and is non-empty, (b) contains expected headings (e.g., `## Project Structure`, `## PRD Requirement Mapping`), (c) no placeholder tokens remain (e.g., `[PROJECT_PATH]`). If any check fails, re-spawn that explorer.
6. **Main agent reads ONLY `explorer-summary.md`** for subsequent steps. The full `explorer-report.md` stays on disk for subagents (Steps 5a, 5b, 9) to reference.

**→ Checkpoint:** Update `progress.json` — `last_completed_step: 1`, remove `1` from `remaining_steps`. (Step 4 runs in parallel; if it finished first, this checkpoint captures both.)

## Step 2: Scope Challenge

**Split execution:** Questions 4 and 7 run in **Phase B** (parallel with exploration). Questions 1-3, 5-6 run in **Phase C** after the explorer report is available. The full synthesis happens in Phase C.

### Phase B (early, parallel with Step 1):

**2.4 — Search check:**

**Tier-Conditional:** At **Tier 1**, skip unless the PRD introduces a new dependency or unfamiliar framework — lightweight plans do not need full web research. At **Tier 2**, if the PRD does not introduce new architectural patterns, frameworks, or infrastructure components, AskUserQuestion: "Skip WebSearch checks for this feature?" If user approves, skip 2.4 entirely. At **Tier 3**, always run.

For each architectural pattern, infrastructure component, or concurrency approach the plan might introduce:
   - Does the runtime/framework have a built-in? WebSearch: "{framework} {pattern} built-in"
   - Is the chosen approach current best practice? WebSearch: "{pattern} best practice {current year}"
   - Are there known footguns? WebSearch: "{framework} {pattern} pitfalls"
   If WebSearch is unavailable, note: "Search unavailable — proceeding with in-distribution knowledge only."
   **→ Write results to `docs/.eng-planning/websearch-findings.md`**

**2.7 — TODOS.md cross-reference:** Read `TODOS.md` / `docs/backlog.md` if they exist. Are any deferred items blocking this plan? Can any be bundled without expanding scope? Does this plan create new work to capture?
   **→ Write results to `docs/.eng-planning/backlog-crossref.md`**

### Phase C (after explorer report):

Before starting, re-read these intermediate files from Phase B:
- The **full PRD** (re-read from disk)
- `docs/.eng-planning/explorer-summary.md` (NOT the full explorer report — use the summary)
- `docs/.eng-planning/websearch-findings.md`
- `docs/.eng-planning/backlog-crossref.md`

Then answer the remaining questions:

1. **What existing code already solves each sub-problem?** For each PRD requirement, check the explorer report. Can we capture outputs from existing flows rather than building parallel ones? List reuse opportunities with file:line references.

2. **Minimum set of changes?** What is the smallest change set that achieves the stated goal? Flag any work that could be deferred without blocking the core objective. Be ruthless about scope creep.

3. **Complexity check:** If the plan will touch more than 8 files or introduce more than 2 new services/classes, treat that as a smell. Challenge whether the same goal can be achieved with fewer moving parts. If triggered: use AskUserQuestion to propose scope reduction before proceeding.

5. **Completeness check:** Default to completeness (full test coverage, all edge cases, all error paths) — with AI-assisted coding the cost is minimal. Flag only if scope is genuinely oceanic.

6. **Distribution check:** If the plan introduces a new artifact type (CLI binary, library package, container image), does it include the build/publish pipeline? Code without distribution is code nobody can use. Check: CI/CD workflow, target platforms, installation method. If deferred, flag explicitly.

**→ Write full scope challenge synthesis to `docs/.eng-planning/scope-challenge.md`**

**If complexity check triggers (8+ files or 2+ new services):** Use AskUserQuestion to propose scope reduction. Explain what is overbuilt, propose a minimal version, ask whether to reduce or proceed as-is. Wait for answer before continuing.

**→ Checkpoint:** Update `progress.json` — `last_completed_step: 2`, remove `2` from `remaining_steps`.

## Step 3: Major Design Decisions

Re-read the PRD, `docs/.eng-planning/scope-challenge.md`, and `docs/.eng-planning/explorer-summary.md` from disk to identify every significant design decision. Categories:

- **Architecture approach** — monolith vs service, sync vs async, polling vs push
- **Data model** — schema design, relationships, migration strategy
- **Tech selection** — libraries, frameworks, tools (subject to R17 verification)
- **Integration pattern** — API style, event format, auth mechanism
- **Performance tradeoffs** — caching strategy, batch size, pagination approach

For each decision:
1. **Formulate the question** with enough context that someone unfamiliar can understand
2. **Present 2-3 options** with concrete tradeoffs (not vague pros/cons — specific costs in lines of code, latency, complexity)
3. **State your recommendation** with reasoning

**Present ALL decisions upfront via AskUserQuestion, one at a time.** Do not batch. Wait for each answer before asking the next. Record every decision with its rationale.

**→ After each decision, append to `docs/.eng-planning/design-decisions.md`.** This file accumulates all decisions so Phase D can read them from disk rather than relying on conversation context.

**→ Checkpoint (after all decisions recorded):** Update `progress.json` — `last_completed_step: 3`, remove `3` from `remaining_steps`.

Example format:
> **Design Decision 3/7: Data Storage Pattern**
>
> The PRD requires storing user preferences that are read frequently and written rarely.
>
> A) PostgreSQL JSONB column on users table — zero new infrastructure, queryable, 1 migration file. Downside: JSONB queries are slower than typed columns at scale.
> B) Dedicated preferences table with typed columns — explicit schema, better query performance. Downside: 2 new files (model + migration), schema changes need migrations.
> C) Redis cache with Postgres fallback — fastest reads. Downside: new infrastructure dependency, cache invalidation complexity, 4+ new files.
>
> RECOMMENDATION: Choose B — typed columns give you explicit schema validation and the query performance difference matters when preferences are loaded on every page view. The 2 extra files are trivial cost.

## Step 4: Dependency Verification (R17)

**Phase B — launch in parallel with Steps 1, 2.4, 2.7.** PRD-listed dependencies can be verified immediately. Dependencies introduced by design decisions in Step 3 are verified in Step 4b (after Step 3 completes).

### Step 4a: PRD-Listed Dependencies (Phase B)

For every NEW external dependency identified in the PRD:

1. **Record the dependency** — exact package name, purpose, why it is needed
2. **Verify it is installable:**
   - Python: `pip install --dry-run "<package>>=<version>"`
   - Node: `npm info <package> version`
   - Go: `go list -m <module>@<version>`
   - .NET: `dotnet list package --include-transitive | grep <package>` or check NuGet
3. **Record evidence** — name, URL (PyPI/npm/NuGet/GitHub), minimum version, verification result
4. **If any dependency FAILS verification:** STOP immediately. Use AskUserQuestion:
   > "Dependency `<package>` cannot be verified as installable. [error details]. Cannot proceed to BUILD with unverified dependencies (R17). Options: A) Find alternative, B) Remove requirement, C) Escalate to user for manual verification."

**→ Write results to `docs/.eng-planning/dependency-verification.md`**

**Format for recording (used in design docs):**
```
- `package-name>=X.Y.Z` — [PyPI](https://pypi.org/project/package-name/) — Purpose: [why needed] — Verified: YES/NO
```

At `light` VIBE level: warn on verification failure but do not block. Note: "Best-effort verification — manual check recommended before BUILD."

### Step 4b: Design-Decision Dependencies (after Step 3)

After Step 3 completes, check if any design decisions introduced new dependencies not in the PRD (e.g., a library chosen during tech selection). Verify each using the same process as Step 4a. Step 5 cannot start until both 4a and 4b pass.

## Step 5: Produce Artifacts (Opus Subagents)

Spawn **parallel Opus subagents** to produce artifacts. Each subagent reads all inputs from disk — the main agent does NOT hold these documents in context. This is the largest context-saving optimization in the pipeline.

### Tier-Conditional Artifact Strategy

- **Tier 1:** Produce a **single design doc** (`docs/plans/FEAT-XXX-design.md`). If the feature has no API endpoints, the contract section is inlined in the design doc. If it does have API endpoints, still produce a separate contract (Step 5b).
- **Tier 2:** Produce a **single design doc + separate API contract IF the feature has API endpoints**. If no API endpoints, contract is inlined. AskUserQuestion before skipping the separate contract: "This feature has no external API endpoints. Inline the contract in the design doc, or produce a separate contract file anyway?"
- **Tier 3:** **Always produce both** — design doc + separate API contract. If the feature has no API endpoints, the contract states "No external API surface introduced" and lists internal interfaces/events if any.

**The design doc MUST include a `Planning Tier: N` header** immediately after the frontmatter, before the Objective section:
```markdown
**Planning Tier:** [1 — Lightweight | 2 — Standard | 3 — Comprehensive]
```

**Output: TWO files per feature (Tier 3) or conditionally one (Tier 1-2).** Architecture, design decisions, and task specs are consolidated into a single feature design doc. Only the API contract is separate (because FE and BE teams reference it independently).

**Each subagent receives this preamble in its prompt:**
```
Read the following files from disk before producing your artifact:
- PRD: [PRD_PATH]
- Explorer report (full): docs/.eng-planning/explorer-report.md
- Explorer summary: docs/.eng-planning/explorer-summary.md
- Design decisions: docs/.eng-planning/design-decisions.md
- Scope challenge: docs/.eng-planning/scope-challenge.md
- Dependency verification: docs/.eng-planning/dependency-verification.md

Write your complete artifact to [OUTPUT_PATH] using the Write tool.

CRITICAL: Follow the Vertical Slice Mandate (defined in SKILL.md).
Every T-XXX must be a vertical slice with Layers, Slice Done Gate,
cross-layer ACs, Execution DAG, and File Conflict Matrix.
Do NOT return the artifact content — write to disk only.
```

### 5a. Feature Design Doc — `docs/plans/FEAT-XXX-design.md`

**Model:** opus (mandatory — this is the primary artifact requiring strongest reasoning)

**This is the primary artifact.** One file per feature containing architecture, design decisions, and task mini-specs.

1. **Read the template** — Read `~/.claude/skills/eng-planning/templates/design-doc-template.md`
2. **Include in the subagent prompt** — The template defines all required sections (spec-registry frontmatter, architecture, design decisions, task mini-specs with vertical slice fields, execution DAG, file conflict matrix, definition of done)
3. **The subagent fills the template** using intermediates from disk (see subagent preamble above)

**Mini-Spec Rules (non-negotiable):**

1. Every T-XXX MUST have ALL fields: Priority, **Layers**, Depends On, Blocks, Spec Reference, Objective, Requirements, Build Guidance, Acceptance Criteria, Edge Cases, Test Plan (with Slice Done Gate).
2. **Vertical Slice Enforcement:** Every T-XXX must list 2+ layers in the `Layers` field UNLESS tagged `HORIZONTAL-JUSTIFIED: [reason]`. Single-layer tickets without justification are rejected.
3. **Layers field** must accurately reflect which architectural layers the ticket touches. Valid layers: `DB`, `API`, `BE` (non-API backend), `FE`, `Infra`, `Config`.
4. **Spec Reference** must use format: `T-XXX @ docs/plans/FEAT-XXX-design.md#t-xxx` — gives the consuming agent the exact file path and anchor to read its full spec.
5. **Acceptance Criteria** must include at least ONE cross-layer assertion for multi-layer tickets (e.g., "POST /api/x returns 201 AND UI shows confirmation").
6. **Slice Done Gate** (in Test Plan) is mandatory — the single integration test that proves the vertical slice wires together across all listed layers.
7. Build Guidance must be SPECIFIC — name the exact patterns, classes, and utilities from the codebase to use. NOT generic principles like "keep it DRY" or "follow SOLID".
8. `Depends On` / `Blocks` are authoritative — the orchestrator uses them to build the DAG and determine concurrency batches. Never create false dependencies.
9. **DAG optimization:** Minimize blocking edges. Two tasks that touch the same file additively (e.g., both add a new route to `routes.py`) CAN be parallelized if the additions are non-overlapping — note this in the File Conflict Matrix with "(additive, safe to parallel)".
10. **Story-Level Granularity:** Each T-XXX = one Jira Story. Apply the Story-Level Consolidation rules in `design-doc-template.md`. Start with one story per JTBD, split only with justification. Run the fragmentation smell test.
11. **Sub-tasks within stories:** Complex stories document internal phases as an ordered list in Build Guidance under a `**Sub-tasks:**` heading. These are NOT separate T-XXX entries.

**After 5a subagent completes:** Verify the artifact exists:
```bash
ls -la docs/plans/FEAT-*-design.md
```

### 5b. API Contracts — `docs/contracts/<feature>.md`

**Model:** opus (mandatory — contracts require precise field-level reasoning)

**Separate file** because FE and BE teams reference it independently. Per R16: one contract per feature with cross-boundary data flow. Follow the "API Contract Summary" template in `~/.claude/skills/eng-planning/templates/design-doc-template.md` — must include endpoint signatures, data models, error shapes, shared enums, and SSE events (if applicable).

Include spec-registry frontmatter at `full` level (see Spec-Registry Frontmatter section below).

**After 5b subagent completes:** Verify the artifact exists:
```bash
ls -la docs/contracts/*.md
```

**No intermediate cleanup at this stage.** Intermediates persist for subagents in later phases (reviewer in Step 9 benefits from `explorer-report.md`, etc.). All cleanup happens in Step 13.

**→ Checkpoint:** Update `progress.json` — `last_completed_step: 5`, remove `5` from `remaining_steps`, populate `artifacts_produced` with the paths of all artifacts written in 5a and 5b.

## Step 6: Codepath Coverage Diagram

For each FEAT design doc, produce codepath coverage and failure modes analysis. Append to the FEAT design doc using the templates in `~/.claude/skills/eng-planning/templates/design-doc-template.md` (sections "Codepath Coverage Diagram" and "Failure Modes").

Flag any "Silent? Yes" entries as P0 — silent failures in production are unacceptable.

**→ Checkpoint:** Update `progress.json` — `last_completed_step: 6`, remove `6` from `remaining_steps`.

## Step 7: DAG Validation & Worktree Parallelization Strategy

**Purpose:** Validate the Execution DAG produced in Step 5a is correct, resolve file conflicts, and produce the final orchestrator-ready execution plan. This step stress-tests the DAG from Step 5a against real filesystem knowledge from the explorer report.

**Step 7 is mandatory.** For single-task plans, record "single-task DAG, no conflicts possible" and checkpoint.

### 7.1 DAG Integrity Check

Re-read the feature design doc from disk. Verify:
1. **No cycles** — Follow all `Depends On` edges. If A→B→C→A, fix by removing the weakest edge.
2. **No orphan tasks** — Every task must be reachable from at least one root (a task with no dependencies).
3. **No phantom dependencies** — Every `Depends On` reference must point to a task that exists.
4. **Batch assignment is correct** — Recalculate batches from the DAG edges. Tasks in the same batch must have NO blocking dependency on each other.

### 7.2 File Conflict Deep Analysis

Using the explorer report (`docs/.eng-planning/explorer-report.md`), verify the File Conflict Matrix from Step 5a:

1. **For each pair of tasks in the same concurrency batch:**
   - List ALL files each task will create or modify (not just the obvious ones — include test files, config, shared types)
   - If overlap exists: Can the modifications be purely additive (e.g., both add a new export to an index file)?
     - **Additive + non-overlapping lines:** Mark "(additive, safe to parallel)" in matrix
     - **Conflicting modifications:** Move one task to a later batch, add `Depends On` edge

2. **Shared type/interface files** — If multiple tasks define types in a shared file (e.g., `types.ts`, `models.py`), propose one of:
   - Extract a T-000 "shared types" task (tagged `HORIZONTAL-JUSTIFIED: foundational types required by multiple slices`)
   - Or confirm the additions are purely additive and non-conflicting

### 7.3 Final Execution Plan (append to feature design doc)

```markdown
## Worktree Execution Plan

### Agent Count
- Maximum parallel agents: [N] (= largest batch size)
- Total sequential batches: [M]
- Estimated wall-clock batches: [M] (each batch runs in ~1 agent session)

### Execution Sequence
| Batch | Tasks (parallel) | Blocked By | Max Agents |
|-------|-----------------|-----------|-----------|
| 1 | T-101, T-104 | — | 2 |
| 2 | T-102, T-103 | T-101 | 2 |
| 3 | T-105 | T-102, T-103 | 1 |

### Worktree Assignment
- All tasks execute in the same feature worktree (shared branch)
- Batch serialization: Orchestrator waits for ALL tasks in Batch N to pass their Slice Done Gate before launching Batch N+1
- Merge strategy within batch: First-to-finish commits immediately; later tasks pull + auto-merge; ESCALATE on conflict (N=1 rule)

### Conflict Resolution Notes
- [Any specific notes about additive modifications, index files, etc.]
```

**→ Checkpoint:** Update `progress.json` — `last_completed_step: 7`, remove `7` from `remaining_steps`.

## Step 7.5: PRD Traceability Self-Check

**Tier-Conditional:** **Tier 1 — SKIP this step entirely.** Tier 1 traceability is handled by a simplified check at Step 12 instead. **Tier 2 and Tier 3 — execute fully.**

**Purpose:** Before presenting artifacts for approval, verify 1:1 mapping between PRD requirements/acceptance criteria and engineering tasks/acceptance criteria. Catch gaps before the approval gate.

1. **Read the template** — Read `~/.claude/skills/eng-planning/templates/traceability-pipeline.md`
2. **Fill placeholders:**
   - `{TRACE_DIR}` = `docs/.eng-planning/traceability/`
   - `{PRD_PATH}` = PRD path from `progress.json`
   - `{ARTIFACT_PATHS}` = design doc path(s) from `artifacts_produced`
   - `{CONTRACT_PATHS}` = contract path(s) from `artifacts_produced` (if any)
3. **Execute the 3-agent pipeline** as defined in the template (2 parallel tracers + 1 synthesis agent).
4. **Read `docs/.eng-planning/traceability/traceability-matrix.md`** from disk — this is the authoritative result.

**If VERDICT is PASS:** Proceed to Step 8.

**If VERDICT is FAIL:** Fix every gap autonomously using the Gap Resolution Rules in the template. After fixing, **re-run the full pipeline** (all fresh agents — do NOT reuse prior ones). Maximum 2 iterations. If gaps persist after 2 iterations, report remaining gaps when presenting in Step 8. Keep all intermediate files in `docs/.eng-planning/traceability/` — they are the audit trail for Steps 8 and 10.

**→ Checkpoint:** Update `progress.json` — `last_completed_step: 7.5`, remove `7.5` from `remaining_steps`. Add `traceability_pass: true|false` and `traceability_gaps_remaining: N`.

## Step 7.6: Quality Synthesis (Opus Subagent)

**Tier-Conditional:** **Tier 1 — SKIP this step entirely.** The simplified review at Step 9 and traceability at Step 12 provide sufficient coverage for lightweight features. **Tier 2 and Tier 3 — execute fully.**

**Purpose:** Before presenting artifacts to the user, get an independent Opus-level assessment of internal consistency, coherence, and overall quality. This catches issues that individual steps miss because they each see a slice — this agent sees everything together with fresh eyes.

**Model:** opus (mandatory for all tiers that execute this step — this is a holistic reasoning task)

Spawn **one Opus subagent** that reads all artifacts from disk with no conversation history.

1. **Read the template** — Read `~/.claude/skills/eng-planning/templates/quality-synthesis-prompt.md`
2. **Fill placeholders:** `[PRD_PATH]`, `[ARTIFACT_PATHS]`, `[CONTRACT_PATHS]`, `[QUALITY_SYNTHESIS_PATH]` = `docs/.eng-planning/quality-synthesis.md`
3. **Spawn via Agent tool** — Use `subagent_type: "general-purpose"`, `model: "opus"`. Subagent writes findings to disk.

**After subagent completes:** Read `docs/.eng-planning/quality-synthesis.md`. Fix all SPECIFIABLE findings autonomously by editing the artifacts. Present REQUIRES_DECISION findings to the user via AskUserQuestion before proceeding to Step 8.

**→ Checkpoint:** Update `progress.json` — `last_completed_step: 7.6`, remove `7.6` from `remaining_steps`.

---

### MANDATORY CHECKPOINT — YOU ARE NOT DONE

**STOP HERE and read this.** Steps 8-12 (Phase F: Review Gate) are MANDATORY. You have produced artifacts in Steps 5-7.5 — you have NOT had them independently reviewed. The review chain (present artifacts → engineering review → auto-fix → final output → final traceability gate) is non-negotiable. Do not declare victory. Do not report completion. Do not summarize what you did and stop. You MUST proceed to Step 8 now.

---

## Step 8: Present Written Artifacts for Approval

Artifacts were already written to disk in Step 5. Present what was written and get approval to proceed to engineering review.

1. **Artifacts written:**
   - `docs/plans/FEAT-XXX-design.md` — [1-line summary: architecture + N decisions + N tasks]
   - `docs/contracts/<feature>.md` — [1-line summary: N endpoints, N data models]

2. **Task count:** [N total tasks across all features]

3. **New questions** that emerged during planning (if any) — surface via AskUserQuestion

4. **Ask:** "Approve to proceed to engineering review? If you want changes to the artifacts, describe them and I will edit before proceeding."

5. **If rejected:** Edit the artifacts based on user feedback, then re-present. Loop until approved.

6. **If approved:** Proceed to Step 9.

**→ Checkpoint:** Update `progress.json` — `last_completed_step: 8`, remove `8` from `remaining_steps`, set `step_8_approved: true`.

## Step 9: Spawn Engineering Review

### Tier-Conditional Review Depth

- **Tier 1 (Simplified Review):** Do NOT use the full `review-prompt.md` template. Instead, spawn a **single Sonnet subagent** with this focused prompt:
  ```
  You are reviewing engineering planning artifacts for a lightweight feature.
  Read the PRD at [PRD_PATH] and the design doc at [ARTIFACT_PATHS].
  
  Check ONLY:
  1. Does every PRD requirement map to at least one task?
  2. Are task dependencies correct (no cycles, no phantoms)?
  3. Does the architecture section make sense for this scope?
  4. Are acceptance criteria testable and specific?
  5. Any obvious gaps, contradictions, or missing edge cases?
  
  For each finding: [SEVERITY: P0|P1|P2] [file:section] — description
  Category: SPECIFIABLE | REQUIRES_DECISION
  
  Write findings to: [REVIEW_FINDINGS_PATH]
  ```
  The review writes to `docs/.eng-planning/review-findings.md`. After this, proceed directly to Step 11 (skip Step 10 — no re-review for Tier 1). Fix any SPECIFIABLE findings from the single review pass. Report REQUIRES_DECISION to user.

- **Tier 2:** Use the full `review-prompt.md` template. **Maximum 1 review iteration** in Step 10.
- **Tier 3:** Use the full `review-prompt.md` template. **Maximum 2 review iterations** in Step 10.

**For Tier 2 and Tier 3, proceed with the standard flow below:**

After approval and artifact creation, spawn a fresh review subagent.

1. **Read the template** — Read `~/.claude/skills/eng-planning/templates/review-prompt.md`
2. **Fill placeholders:**
   - `[ARTIFACT_PATHS]` — List of all artifact file paths produced in Step 5
   - `[PRD_PATH]` — Path to the approved PRD
   - `[PROJECT_PATH]` — Absolute path to the project root
   - `[REVIEW_FINDINGS_PATH]` — `docs/.eng-planning/review-findings.md`
3. **Spawn via Agent tool** — Use `subagent_type: "general-purpose"`. The reviewer runs in isolated context (sees ONLY the artifacts, not the planning conversation) and **writes findings directly to disk**. The main agent does NOT read the subagent return value.
4. **Wait for completion.** Verify the file exists:
   ```bash
   ls -la docs/.eng-planning/review-findings.md
   ```
5. **Main agent reads `review-findings.md` from disk** for Step 10.

**→ Checkpoint:** Update `progress.json` — `last_completed_step: 9`, remove `9` from `remaining_steps`.

## Step 10: Auto-Fix Loop

### Tier-Conditional Iteration Limits
- **Tier 1:** SKIP this step entirely. Tier 1 fixes SPECIFIABLE findings inline during Step 9 and proceeds directly to Step 11.
- **Tier 2:** Maximum **1 iteration**. Fix specifiable, re-run review once. If issues persist, report and proceed.
- **Tier 3:** Maximum **2 iterations**. Full auto-fix loop as described below.

Parse the review findings. Categorize each:

- **SPECIFIABLE** — Can be fixed by editing an artifact (typo in contract, missing edge case in test plan, incomplete dependency record). Fix autonomously.
- **REQUIRES_DECISION** — Involves a design choice the user must make (different architecture approach, scope change, new dependency). Surface via AskUserQuestion.

After applying SPECIFIABLE fixes, re-spawn the review (Step 9) to verify fixes. **Maximum 2 total review iterations.** If issues persist after 2 iterations, report remaining findings to user and proceed.

Iteration tracking:
```
Review iteration 1: [N findings] — [X specifiable, Y decision-required]
  Fixed: [list of specifiable fixes]
  Escalated: [list of decision-required items]
Review iteration 2: [N findings] — [all specifiable? then done]
```

If iteration 2 still has specifiable findings: log them as known issues in the design doc and proceed.

**→ Checkpoint:** Update `progress.json` — `last_completed_step: 10`, remove `10` from `remaining_steps`, set `review_iteration` to the final iteration count.

## Step 11: Pre-Final Output

Confirm all artifacts have been written to disk. Do NOT clean up intermediate files yet — Step 12 needs the final artifacts in place for the traceability gate.

**→ Checkpoint:** Update `progress.json` — `last_completed_step: 11`, remove `11` from `remaining_steps`.

---

### MANDATORY CHECKPOINT — STEPS 12-13 ARE NOT OPTIONAL

**STOP.** You must proceed through Steps 12, 12.5, and 13 before declaring completion. The review loop (Steps 9-10) may have introduced fixes that broke traceability or coherence. Steps 12-12.5 verify the final state. Step 13 cleans up and reports.

---

## Step 12: Final PRD Traceability Gate

**Purpose:** After the full review cycle (Steps 9-10) and fix iterations, verify the final artifacts still maintain 1:1 PRD traceability. Review fixes may have introduced new gaps or broken existing mappings.

### Tier-Conditional Traceability

- **Tier 1 (Simplified Traceability):** Instead of the full 3-agent pipeline, spawn **1-2 independent Sonnet agents** to produce a simplified traceability matrix:
  - **If PRD + design doc combined < 200 lines:** Spawn 1 Sonnet agent that reads both documents and produces a simplified forward+reverse traceability matrix.
  - **If PRD + design doc combined >= 200 lines:** Spawn 2 Sonnet agents in parallel — one for forward trace (PRD→eng), one for reverse trace (eng→PRD). Merge results.
  - Agent prompt: "Read the PRD at [path] and the design doc at [path]. For each PRD requirement, verify it maps to at least one engineering task with matching acceptance criteria. For each engineering task, verify it traces back to a PRD requirement. Write a simplified traceability matrix to `docs/.eng-planning/traceability/traceability-matrix.md` with VERDICT: PASS or FAIL and any gaps found."
  - The agent(s) must be independent — they have NOT seen the planning conversation. This is the verification guarantee.
  - If FAIL: fix gaps, re-run simplified check (max 1 iteration).

- **Tier 2 and Tier 3:** Use the shared 3-agent traceability pipeline template.

**For Tier 2 and Tier 3, proceed with the standard flow:**

1. **Clean prior traceability state (Step 7.5 artifacts are superseded) and re-run the pipeline:**
   ```bash
   rm -rf docs/.eng-planning/traceability/
   mkdir -p docs/.eng-planning/traceability/
   ```
   Read `~/.claude/skills/eng-planning/templates/traceability-pipeline.md`, fill placeholders with `{TRACE_DIR}` = `docs/.eng-planning/traceability/`, and execute. All fresh sonnet agents — the Step 7.5 agents are long gone. The final traceability matrix replaces any prior audit trail.

2. **If VERDICT is PASS:** Proceed to final output with `PRD Traceability: VERIFIED (100% forward trace, confirmed post-review)`.

3. **If VERDICT is FAIL:**
   - Fix gaps using the same rules as Step 7.5 (DROPPED → add task, DILUTED → strengthen AC, etc.)
   - Do NOT re-enter the full review loop (Steps 9-10) — only fix traceability gaps
   - Maximum 1 fix iteration with full pipeline re-run
   - If gaps persist after 1 iteration: report status as `DONE_WITH_CONCERNS` and list remaining traceability gaps

**→ Checkpoint:** Update `progress.json` — `last_completed_step: 12`, remove `12` from `remaining_steps`.

## Step 12.5: Post-Review Coherence Spot-Check (Sonnet)

**Purpose:** The review loop (Steps 9-10) and traceability gate (Step 12) may have introduced fixes that broke consistency. This is a lighter, targeted check — NOT a full re-synthesis. The question is specifically: "did the fixes break anything?"

**Model:** sonnet (lighter check — the heavy lifting was done in Steps 7.6 and 9)

1. **Read the template** — Read `~/.claude/skills/eng-planning/templates/spot-check-prompt.md`
2. **Fill placeholders:** `[ARTIFACT_PATHS]`, `[CONTRACT_PATHS]`, `[SPOT_CHECK_PATH]` = `docs/.eng-planning/post-review-spotcheck.md`
3. **Spawn via Agent tool** — Use `subagent_type: "general-purpose"`, `model: "sonnet"`. Subagent writes findings to disk.

**After subagent completes:** Read `post-review-spotcheck.md`. If regressions found, fix them directly. These should be small — if a regression requires a design decision, surface it via AskUserQuestion.

**→ Checkpoint:** Update `progress.json` — `last_completed_step: 12.5`, remove `12.5` from `remaining_steps`.

## Step 13: Final Cleanup & Output

1. **Checkpoint BEFORE cleanup:**

**→ Checkpoint:** Update `progress.json` — `last_completed_step: 13`, `remaining_steps: []`.

2. **Delete the entire `docs/.eng-planning/` directory:**

```bash
rm -rf docs/.eng-planning/
```

The final artifacts in `docs/plans/` and `docs/contracts/` are the permanent record.

3. **Report completion status:**

- **DONE** — All artifacts produced, review passed, traceability verified, no outstanding concerns.
- **DONE_WITH_CONCERNS** — All artifacts produced, but concerns remain. List each concern explicitly.
- **BLOCKED** — Cannot complete. State what is blocking (unverified dependency, unresolved design decision, missing PRD information).

Final output format:
```
STATUS: DONE | DONE_WITH_CONCERNS | BLOCKED

ARTIFACTS PRODUCED:
- docs/plans/FEAT-XXX-design.md — [architecture + N decisions + N tasks]
- docs/contracts/<feature>.md — [N endpoints, N data models]

INTERMEDIATE FILES: Cleaned up (docs/.eng-planning/ removed)

REVIEW: [Passed after N iterations | Concerns listed below]

PRD TRACEABILITY:
- Step 7.5 (pre-approval): [PASS | PASS after N fix iterations | N gaps reported]
- Step 12 (post-review): [VERIFIED 100% | N gaps remaining — listed below]

QUALITY SYNTHESIS: [Step 7.6 findings: N issues, all resolved | N concerns remaining]
POST-REVIEW SPOT-CHECK: [Clean | N regressions found and fixed]

NEXT STEPS:
- Update .claude/phase.json to FEATURE_SPECS_APPROVED
- Orchestrator can begin spawning coder subagents for T-XXX tasks
```

## Spec-Registry Frontmatter

Every spec produced at `full` VIBE level must include frontmatter:

```yaml
---
domain: <feature-domain>
skills: [<relevant-skills>]
schemas: [<relevant-schema-paths>]
---
```

This enables the orchestrator (Step 0: Spec Context Injection) to automatically find and inject relevant specs into subagent prompts. Without this frontmatter, coders may miss context.

At `light` VIBE level: frontmatter is recommended but not required.

## Red Flags — STOP Immediately

If you catch yourself:
- Opening Edit/Write on .py/.ts/.js files → STOP, you are the planner
- Writing implementation code in any language → STOP
- Producing a mini-spec without Build Guidance → STOP, add specific guidance
- Writing generic Build Guidance ("follow SOLID", "keep it DRY") → STOP, name specific files/classes/patterns
- Skipping dependency verification at `full` level → STOP, verify first
- Proceeding after dependency verification failure → STOP, escalate
- Making design decisions without presenting options → STOP, ask user
- Writing artifacts outside docs/ → STOP, wrong location
- Producing a FEAT design doc without all required sections → STOP, complete it
- Running implementation tests or modifying test files → STOP, that is coder work
- **Decomposing by horizontal layer** (all schemas → all APIs → all UI) → STOP, re-slice vertically
- Producing a T-XXX with only 1 layer and no `HORIZONTAL-JUSTIFIED` tag → STOP, add justification or re-slice
- Creating artificial `Depends On` edges between tasks that don't truly depend on each other → STOP, maximize parallelism
- Producing a mini-spec without `Layers` field or `Slice Done Gate` → STOP, add them

**All of these mean: You have confused your role. Return to planning.**

## Escalation

If at any point:
- A PRD requirement is ambiguous and cannot be resolved by re-reading → AskUserQuestion
- Dependency verification fails and no alternative exists → STOP and report BLOCKED
- The complexity check suggests fundamental redesign → present findings, wait for user
- Explorer report reveals the codebase cannot support the PRD requirements → escalate immediately

Do not guess. Do not assume. Ask.
