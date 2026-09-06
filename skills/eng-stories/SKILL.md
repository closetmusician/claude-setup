---
name: eng-stories
description: "Decomposes an approved PRD into Jira-ready epics and stories with behavioral acceptance criteria extracted from existing source code, in strict PM-facing language. Use on 'decompose PRD into stories', 'break down into stories', 'break this PRD into stories', 'story breakdown', 'turn this PRD into Jira stories'. Flags: --source-repos (paths/URLs for behavioral extraction — REQUIRED in headless/batch runs), --feature-id (parallel-safe namespacing), --story-size team|large (default team: one user action, ~2 ACs), --auto-approve (batch: bypass the human approval gate), --headless (non-interactive contract), --jira <PROJECT-KEY> (post epic→story→subtask after approval). NOT for architecture docs, API contracts, or infrastructure planning (use /eng-planning), NOT for greenfield features with no existing source (use /eng-planning or manual story writing), NOT for writing/reviewing the PRD itself (/prd-writer, /prd-review)."
---

<!-- ABOUTME: PRD-to-stories decomposition skill with behavioral expansion. -->
<!-- ABOUTME: Reads a PRD + source repos, produces Jira-ready stories with source-derived ACs in strict PM-facing language. -->
<!-- ABOUTME: 12 contiguous steps: locate → tier → graph → explore → zero-coverage → generate → trace → specificity → approve → review → Jira → cleanup. -->

# /eng-stories

**Purpose:** Decompose an approved PRD into Jira-ready epics and stories with behavioral depth derived from existing source code implementations.

**When to use:** After PRD approval, when you need stories whose acceptance criteria capture the full behavioral surface of existing features — not just what the PRD says at requirement level.
**When NOT to use:** Architecture docs, API contracts, infrastructure planning → `/eng-planning`. Entirely greenfield features with no source to extract from → `/eng-planning` or manual story writing. Writing or critiquing the PRD itself → `/prd-writer`, `/prd-review`.

**Inputs:**
- PRD path (required) — argument or auto-discovered
- `--source-repos` — comma-separated paths or git URLs with existing implementations. **Required in headless mode** (or PRD frontmatter `source_repos:`); optional interactively (falls back to AskUserQuestion)
- `--feature-id` — e.g. `FEAT-01`. Namespaces intermediates under `docs/.eng-planning/<feature-id>/`. Auto-derived from PRD filename if omitted. Required for parallel batch runs
- `--story-size team|large` (default `team`; see Story Size) · `--auto-approve` (bypass the Step 9 human gate; review artifacts still written) · `--headless` (force non-interactive contract; also auto-detected) · `--jira <PROJECT-KEY>` (post epic→story→subtask after approval, Step 11)

**Output:** `docs/plans/FEAT-XXX-stories.md` (one file per feature). With `--jira`: a stripped `jira/FEAT-XXX-stories-jira.md` copy + posted Jira issues.

**Tools:** Task (subagents), Read/Glob/Grep, Write (to `docs/` only), AskUserQuestion (interactive mode ONLY), Bash (read-only commands + validation script).

---

## Mode Detection: Interactive vs Headless

HEADLESS mode is ON if ANY of: (a) `--headless` flag; (b) env `CLAUDE_BATCH_RUNNER` is set (`[ -n "${CLAUDE_BATCH_RUNNER:-}" ]`); (c) the invoking prompt says "do not ask", "non-interactive", or "batch mode". Otherwise the run is INTERACTIVE.

**Headless contract — non-negotiable:** AskUserQuestion is BANNED in headless mode. A headless session that blocks on a question is a dead batch slot (June 2026: ≥12 batch sessions hung forever on repo-resolution prompts). Every decision point resolves via this table, or fails fast with the Error Contract:

| Decision point | Interactive | Headless |
|---|---|---|
| PRD not found / ambiguous | AskUserQuestion to pick | ERROR `PRD_NOT_FOUND` / `PRD_AMBIGUOUS` |
| Source repos unresolved (Step 1) | AskUserQuestion (4 options) | ERROR `MISSING_SOURCE_REPOS` |
| Tier ambiguous (Step 2) | ask | default Standard |
| Namespace collision (Step 1) | ask resume/restart/renamespace | live heartbeat (<10 min) → ERROR `COLLISION`; stale → resume |
| Explorer coverage <50% (Step 4) | ask proceed/wait/abort | wait 60s once, then proceed; log `partial_coverage: true` |
| Approval gate (Step 9) | ask approve/changes | `--auto-approve` → record `"auto"` and continue; else write approval package, print `AWAITING_APPROVAL`, exit cleanly resumable |
| Cleanup (Step 12) | ask delete/keep | keep |
| Jira posting (Step 11) | ask or `--jira` | only with `--jira`; else emit handoff contract |

**Error Contract (machine-readable fail-fast).** On any fatal condition: (1) Write `docs/.eng-planning/{feature_id}/error.json`: `{"error":"<CODE>","step":"<n>","detail":"...","resume":true|false,"ts":"<ISO 8601>"}`. (2) Print exactly one line: `ENG-STORIES-ERROR code=<CODE> step=<n> feature=<FEAT-XX> detail="..."`. (3) Exit — no partial story generation. Codes: `PRD_NOT_FOUND`, `PRD_AMBIGUOUS`, `MISSING_SOURCE_REPOS`, `COLLISION`, `QUOTA_EXHAUSTED`, `VALIDATION_FAILED`.

**Quota-aware checkpointing.** If any subagent spawn or API call fails with a rate-limit signal ("rate limit", "out of extra usage", "resets at", 429): (1) update `progress.json` with `last_completed_step` + `"quota_stop": true`; (2) write heartbeat with label `QUOTA_STOP`; (3) emit `ENG-STORIES-ERROR code=QUOTA_EXHAUSTED step=<n> resume=true`; (4) exit cleanly. Resume Detection picks the run back up. Do NOT retry-loop into the same wall (June 9: 15/72 sessions died mid-run). **Batch runner guidance: safe `--max-jobs` is 2; never exceed 3** — the June wave ran 4 parallel headless instances and burned the quota in one pass.

---

## Language Standard (Non-Negotiable)

Every artifact this skill produces — stories, explorer reports, behavioral inventories, all subagent output — must pass the **board-director test**: a completely non-technical person (board director, school principal, VP) understands it without asking an engineer.

**BANNED anywhere in story artifacts:** variable names, config fields, class names, framework terms, state-machine notation ("idle -> voting -> stopped"), HTTP status codes ("409 on invalid"), DB column names, API paths. There is NO technical section — ALL story content is PM-facing. Implementation details stay in the explorer reports under `docs/.eng-planning/{feature_id}/` for `/eng-planning` to consume downstream.

BAD (jargon-first):
> **Objective:** "Implement AgendaItemService with CRUD endpoints, SignalR hub broadcast on mutation"
> **Requirement:** "State machine: idle -> voting -> stopped -> finalized; server validates transitions; 409 on invalid"
> **AC:** "AgendaController.Post returns 201 with Location header"

GOOD (outcome-first, same specificity):
> **Objective:** "Board members can create, edit, reorder, and delete agenda items, with changes appearing instantly for all connected users"
> **Requirement:** "A vote moves through four stages in order: not started, voting open, voting closed, and results final. The system only allows moving forward — skipping or going backward is not allowed."
> **AC:** "Creating an agenda item shows it immediately in every board member's agenda view without refresh"

### Titles and IDs Are Story Content Too

The jargon ban applies to story TITLES and ID mnemonics, not just bodies (June defect: bodies were rewritten plain, titles stayed word salad and had to be de-jargonized by hand).

- BAD: `### S-CRUD: Agenda Item CRUD Endpoints with SignalR Broadcast`
- GOOD: `### S-AG: Manage Agenda Items in Real Time`
- ID mnemonics come from the user's domain (`S-AG` agenda, `S-VT` voting) — never tech terms (`S-API`, `S-DB`, `S-CRUD` are banned).

### Specificity Preservation (Never Drop Numbers or Mechanisms)

Rewriting jargon to plain English NEVER loses precision. Every retry count, timeout, polling interval, size limit, threshold, step count, and multi-step mechanism survives the rewrite — expressed in user-facing words. Dropping one is a P0 content loss, same as dropping a requirement.

- BAD: "poll every 1 second for up to 10 seconds" → "check periodically until ready"
- GOOD: → "check once per second for up to 10 seconds"
- BAD: "requires both org-level enable AND document-level toggle" → "can be enabled by administrators"
- GOOD: → "requires two settings: the organization turns it on globally, then each document can enable it individually"

The prose rule alone is NOT trusted — it failed twice in June (5 P1 values vaporized in one rewrite). Step 8 verifies retention mechanically with a script.

### Requirements Tables (P0/P1/P2)

The contract with stakeholders, not engineers. Each requirement cites its parent PRD requirement/JTBD and uses the PRD's user-facing language.

- BAD: "R-003: Implement SignalR hub for real-time agenda mutation broadcast with optimistic concurrency via ETag"
- GOOD: "R-003: Changes to agenda items appear instantly for all users viewing the same meeting (PRD JTBD-3)"

### Where Technical Detail Goes

Source-derived behaviors from the code explorer are routed by tag:
- **[REQ]-tagged** → user-facing requirements, workflow steps, EC-N edge cases, or `[SOURCE-DERIVED]` ACs — in plain English.
- **[IMPL]-tagged** → NOT in the story. They remain in explorer reports for `/eng-planning`.
- Out-of-PRD-scope behavior → `[OUT-OF-SCOPE: reason]` list below the story.
- Cross-cutting concerns (concurrency, accessibility, audit) → user-facing requirements ("Two users editing the same agenda both see each other's changes without losing work"), never engineering checklists ("Concurrent access: optimistic locking").

### Enforcement Preamble (include in EVERY subagent prompt — explorer, story producer, reviewer)

```
LANGUAGE STANDARD: All output must be readable by a completely non-technical person — a board director or school principal who has never written code. User stories, TITLES, objectives, requirements, workflows, context, and ACs use plain English focused on user outcomes and visible behavior — no variable names, config fields, framework terms, state-machine notation, or HTTP codes ANYWHERE, including story titles and ID mnemonics. There is no technical section in story artifacts. REQUIREMENTS TABLES must use user-facing language matching the PRD — the board-director test applies. Each requirement must cite its parent PRD JTBD or requirement ID. SPECIFICITY PRESERVATION: When rewriting jargon to plain English, NEVER drop specific values — retry counts, timeout durations, polling intervals, size limits, multi-step mechanisms. "Poll every 1 second for up to 10 seconds" stays as those exact numbers. "Requires both org-level AND document-level toggle" stays as a two-step gate. Dropping a specific number or mechanism is a P0 content loss. BEHAVIORAL REQUIREMENTS: Cross-cutting concerns from behavioral inventory (concurrency, accessibility, audit, etc.) must be expressed as user-facing requirements or workflow steps in the relevant story, not as engineering checklists. SOURCE-DERIVED BEHAVIORS: [REQ]-tagged items become requirements, workflow steps, edge cases, or ACs in plain English. [IMPL]-tagged items are NOT included in the story — they stay in explorer reports for /eng-planning.
```

---

## Story Size (--story-size) & Story Shape

| Mode | Unit | Use when |
|---|---|---|
| `team` (default) | One story = ONE user action, ~2 Given/When/Then ACs, ≤250 words, compact form (template §Team-Size Story Form). Shared sections (Roles & Permissions, Field Definitions, Visibility Rules) written ONCE at feature level. | Stories go to a sprint board for engineers. June lesson: "eng are complaining the stories are too long" — 104 mini-specs ≈ 2,036 ACs vs the team's ~250-word/2-AC unit. |
| `large` | Full mini-spec per story (template §Large Story Form) — the pre-July format. | The consumer is `/eng-planning` or a document-first review, not a sprint board. |

**Both modes:** every story carries a size estimate (XS/S/M/L/XL) in the Story Index; **any story estimated L or XL (>M) MUST be split before Step 7** — no exceptions, splits stay vertical. Stories are **vertical slices**: each S-XXX delivers a coherent, independently testable unit of user-visible value. BANNED: horizontal layer planning (all schemas → all APIs → all UI); a genuinely single-layer story requires `HORIZONTAL-JUSTIFIED: [reason]`. Each story's Test Plan carries a **"Slice Done Gate:"** line — exactly this spelling; `/eng-planning` and its validators grep for it.

## Execution Flow (12 contiguous steps) + Per-Step Time Budgets

| Step | What | budget_min | On overrun (self-applied, don't wait for the watchdog) |
|---|---|---|---|
| 1 | Locate PRD + resolve source repos (mode detect, collision guard, persist) | 3 | fail fast per mode table |
| 2 | Tier detection (Light / Standard) | 1 | default Standard |
| 3 | Code graph bootstrap (per repo; MCP-absent → fallback immediately) | 6 | abandon graphs, use fallback clusters |
| 4 | Cluster-parallel exploration + behavioral extraction [sonnet per (repo, cluster)] | 12 | proceed with whatever summaries exist (≥50% rule) |
| 5 | Zero-coverage discovery (no-source PRD areas → domain questionnaire) | 3 | write questionnaire from what's mapped so far |
| 6 | Story generation [opus] + structural validation script | 12 | validate what was produced; one retry max |
| 7 | Traceability + depth trace + source reconciliation | 10 | stop after 1 fix iteration |
| 8 | Specificity verification (script-diff: inventory vs stories) | 3 | disposition remaining flags as P1 in report |
| 9 | Approval gate (ask \| --auto-approve \| headless AWAITING_APPROVAL exit) | 2 | headless: exit AWAITING_APPROVAL |
| 10 | Story quality review [sonnet] | 6 | fix P0s only, defer P1s to report |
| 11 | Jira delivery (only --jira flag or explicit request) | 10 | stop posting, emit handoff contract for remainder |
| 12 | Cleanup & report | 2 | — |

## Heartbeat Protocol (batch runs only)

**Only when env `CLAUDE_BATCH_RUNNER` is set:** at the START of every step, Write `docs/.eng-planning/{feature_id}/heartbeat.json`:
```json
{"step": "4", "label": "Cluster-parallel exploration", "ts": "<ISO 8601>", "budget_min": 12, "feature_id": "FEAT-XX"}
```
The watchdog treats a run as hung when `now > ts + budget_min` (not a flat 5 minutes — long steps were being killed, short hangs tolerated). Interactive runs skip heartbeats entirely — there is no watchdog to feed.

---

## Step 1: Locate PRD & Resolve Source Repos

### 1a: Locate PRD
1. Use the argument path if given; else Glob `docs/prd/`, `docs/prd/features/`, `docs/plans/`
2. Not found / ambiguous → interactive: AskUserQuestion; headless: ERROR `PRD_NOT_FOUND` / `PRD_AMBIGUOUS`
3. Read the PRD completely — objectives, P0/P1/P2 requirements, constraints, user stories, success metrics, non-goals

### 1b: Derive Feature ID & Guard Against Parallel-Run Collision
1. `--feature-id` CLI arg → env `CLAUDE_FEATURE_ID` → PRD filename leading number (`01-meeting-management.md` → `FEAT-01`) → no leading number: `FEAT-<slugified-filename-stem>`.
2. **All intermediates go under `docs/.eng-planning/{feature_id}/` — never bare `docs/.eng-planning/`.** Everything is namespaced; this is what makes parallel feature runs safe.
3. **Collision guard:** if `docs/.eng-planning/{feature_id}/progress.json` exists AND (its `prd_path` differs from this run's PRD, OR its `heartbeat.json` is fresher than 10 minutes — another session is live): do NOT share or overwrite that state. Interactive: AskUserQuestion (resume / restart clean / fresh namespace `{feature_id}-r2`). Headless: live heartbeat → ERROR `COLLISION`; stale + same PRD → resume.

### 1c: Resolve Source Repos (MANDATORY)
Resolution order:
1. CLI `--source-repos` (comma-separated paths or git URLs)
2. PRD frontmatter `source_repos:` field
3. Episodic memory (best-effort — MCP may be absent headless): `mcp__plugin_episodic-memory_episodic-memory__search` with `["source repos", "<PRD name>"]`
4. Else — interactive: AskUserQuestion with options **Enter repo paths** / **Enter git URLs** / **Auto-discover under ~/Code/** (`find ~/Code/ -maxdepth 2 -name ".git" -type d | sed 's|/.git||' | sort`, confirm via multiSelect) / **Skip (checklist-only mode)** (no behavioral extraction — PRD + PM judgment alone). **Headless: ERROR `MISSING_SOURCE_REPOS` — never guess repos, never silently degrade to checklist-only.**

Git URLs: resolve to a local clone via `git remote get-url origin` matching; no local clone → warn (interactive) that behavioral extraction requires local source.

### 1d: Persist Repos (write-once, never lost)
1. **PRD frontmatter** — add/update `source_repos:` list (Edit tool; create frontmatter if absent)
2. **Progress file** — `docs/.eng-planning/{feature_id}/progress.json`: `{"feature_id", "prd_path", "source_repos", "mode": "interactive|headless", "story_size", ...}`
3. **Episodic memory** — write `~/.claude/projects/<project>/memory/eng-stories-repos-<prd-slug>.md` (name/description/type frontmatter + repo list + date); update MEMORY.md index

**Checkpoint:** `last_completed_step: "1"`

## Step 2: Tier Detection

Count P0 requirements in the PRD. **<5 P0 reqs + single feature area → Light** (1 agent per cluster — still parallel — 2-agent traceability). **>=5 P0 reqs or multi-feature area → Standard** (all clusters across all repos in parallel, 3-agent traceability). Both tiers: sonnet story review. Ambiguous → interactive: ask; headless: Standard.
**Checkpoint:** `last_completed_step: "2"`, `tier`

## Step 3: Code Graph Bootstrap

**Fast path:** `ls docs/.eng-planning/{feature_id}/clusters-*.json` — valid cluster files (non-empty, ≥1 cluster) → skip to Step 4 (saves 8-12 min on re-runs).

**MCP availability guard:** confirm the code-review-graph MCP tools are actually loaded in THIS session before calling them (headless sessions often lack MCP — 4 June sessions burned 8-12 min discovering this). If absent, go straight to the fallback in item 4. Never retry MCP calls that report "No such tool".

For each repo in `source_repos`:
1. `mcp__plugin_code-review-graph_code-review-graph__list_graph_stats_tool(repo_root=<repo>)` — graph with nodes > 0 → go to 3
2. `mcp__plugin_code-review-graph_code-review-graph__build_or_update_graph_tool(repo_root=<repo>, full_rebuild=true, postprocess="full")` — all repo builds in parallel (10-60s each)
3. `mcp__plugin_code-review-graph_code-review-graph__list_communities_tool(repo_root=<repo>, detail_level="standard", sort_by="size")` → write `docs/.eng-planning/{feature_id}/clusters-{repo-name}.json`: `{"repo", "graph_available": true, "clusters": [{"id","name","size","cohesion","members_sample"}], "fallback_clusters": null}`
4. **Fallback (MCP absent, build fails, or <3 communities) — MUST complete in under 60 seconds.** Do NOT explore the tree. Use the predefined categories immediately: `["API/Routes layer", "Data/Models layer", "UI/Components layer", "Auth/Permissions", "Business logic/Services", "Infrastructure/Config"]`, keep only categories whose directory exists (ONE glob check each), write the cluster file with `"graph_available": false` right away.

**Checkpoint:** `last_completed_step: "3"`, `clusters_per_repo`

## Step 4: Cluster-Based Parallel Exploration + Behavioral Extraction

Exploration parallelizes by **(repo, cluster)** pair — no hard cap (3 repos × [5,4,3] clusters = 12 agents).

**4a — Exploration matrix:** from each `clusters-{repo-name}.json`: graph clusters → `(repo, cluster_name, members)`; fallback → `(repo, category, null)`. Route PRD requirements to each pair (graph members vs requirement keywords; fallback: category-name matching) so each explorer knows what behaviors to hunt.

**4b — Spawn all explorers:** one per pair — **ALL Task calls in a single message** (that is what makes them parallel; there is no `run_in_background` parameter on Task). Do not wait on or poll individual agents. Template: `templates/explorer-prompt.md`. Per-agent placeholders: `[PROJECT_PATH]`, `[PRD_CONTENT]` (full text), `[CLUSTER_NAME]`, `[CLUSTER_SCOPE]`, `[GRAPH_AVAILABLE]`, `[REPO_ROOT]`, `[PRD_REQUIREMENTS]` (routed subset), `[EXPLORER_REPORT_PATH]` = `docs/.eng-planning/{feature_id}/explorer-{repo-name}-{cluster-slug}.md`, `[EXPLORER_SUMMARY_PATH]` = `.../summary-…`, `[BEHAVIORAL_INVENTORY_PATH]` = `.../behaviors-…`. **Model:** sonnet. Each agent: structural exploration within its cluster boundary + behavioral extraction for its routed requirements (embedded, not a separate phase) + writes to its own unique paths. A spawn failure carrying a rate-limit signal → Quota-aware checkpointing (above).

**If source repos were skipped (interactive checklist-only):** skip Steps 4-5 entirely; story generation runs on PRD + PM judgment.

**4c — Non-blocking verification:** do NOT poll file counts, wait for stragglers, or block until 100%.
1. Wait ~30 seconds, then run ONE check: `ls docs/.eng-planning/{feature_id}/summary-*.md | wc -l`
2. **≥50% of expected summaries** → proceed immediately (late output = bonus context; Step 7 catches gaps).
3. **<50%** → wait 60 more seconds, re-check ONCE. Still <50% → interactive: AskUserQuestion (proceed partial / wait once more / abort); headless: proceed, set `partial_coverage: true`, list missing clusters in the stories-doc appendix. Never loop-poll silently.
4. Spawn a background sonnet agent to merge per-cluster files into `explorer-report.md` + `behavioral-inventory.md` — audit artifacts only; Step 6 never blocks on them.

**Checkpoint:** `last_completed_step: "4"`

## Step 5: Zero-Coverage Discovery

Main agent, fast (~3 min). For each PRD P0/P1 requirement, count matching entries across `behaviors-*.md`. Areas with ZERO source behaviors are the real miss category (June audit: every genuine gap was absent from both PRD detail and code — and the skill stayed silent about them). For each zero-coverage area, write `docs/.eng-planning/{feature_id}/domain-questionnaire.md`: 2-4 concrete questions a PM must answer before the stories are trustworthy — "What should happen when…", "Who is allowed to…", "What are the limits/defaults for…". These questions also go into the stories doc's **Open Questions (Domain Questionnaire)** appendix (template section) and the Step 9 approval package. **Never generate confident-looking stories for a zero-coverage area without flagging it — silence here is the failure mode.** No zero-coverage areas → write the file with "None — all PRD areas have source coverage."

**Checkpoint:** `last_completed_step: "5"`

## Step 6: Story Generation

**Primary output.** Spawn ONE subagent, `model: "opus"` (story decomposition = judgment tier), to produce `docs/plans/FEAT-XXX-stories.md`. Pre-flight: `mkdir -p docs/plans/`. Template: `templates/stories-template.md` (producer instructions, both story-size forms, numbering).

**Subagent prompt = the Enforcement Preamble (above) + this block:**

```
Read from disk before producing your artifact:
- PRD: [PRD_PATH]
- Per-cluster explorer reports (read ALL): docs/.eng-planning/{feature_id}/explorer-*.md
- Per-cluster summaries + behavioral inventories: summary-*.md, behaviors-*.md
- domain-questionnaire.md (open questions appendix input)
- Merged report if it exists (optional convenience — per-cluster files are the source of
  truth; do NOT wait for the merge)
Write your complete artifact to [OUTPUT_PATH] with the Write tool. Do NOT return the content.

STORY SIZE: [team|large]. team → §Team-Size Story Form: one story per user action,
~2 Given/When/Then ACs, ≤250 words, shared sections once at feature level.
large → §Large Story Form (full mini-spec). Either way: estimate every story XS-XL in the
Story Index; any story you would estimate L or XL MUST be split (vertically) before you emit it.
CRITICAL: Writing style. Every sentence readable by a non-technical person. Short sentences,
one idea each. NO compound noun stacks, NO state-machine notation, NO implementation terms
ANYWHERE — including story TITLES and ID mnemonics (S-AG "Manage Agenda Items", never
S-CRUD "Agenda CRUD Endpoints"). More than two technical nouns in a row = rewrite it.
CRITICAL: Specificity preservation. Never drop retry counts, timeouts, polling intervals,
size limits, thresholds, or multi-step mechanisms when rewriting to plain English. Dropping
a load-bearing number or mechanism is a P0 content loss. A script will diff your ACs
against the behavioral inventory — vaporized numbers WILL be caught.
CRITICAL: Vertical slices. One story per JTBD by default, each an independently testable
slice of user value. Horizontal single-layer stories require HORIZONTAL-JUSTIFIED: [reason].
Every story's Test Plan includes a "Slice Done Gate:" line.
CRITICAL: IDs. Stories S-XXX (domain mnemonics); sub-tasks T-{story}-{N}.
CRITICAL: Requirements table backfill (MANDATORY second pass). After writing ALL stories, go
BACK and fill the Jira Story and Tasks columns with concrete S-XXX / T-XXX-N. Never "TBD".
CRITICAL: Source-derived behaviors. Route by tag: [REQ] → plain-English requirements,
workflow steps, edge cases, or [SOURCE-DERIVED] ACs. [IMPL] → NOT in the story (stays in
explorer reports for /eng-planning). Out of PRD scope → [OUT-OF-SCOPE: reason].
CRITICAL: Cross-cutting behaviors are user-facing requirements, never engineering checklists.
CRITICAL: Design decisions. AC depends on an unresolved choice → tag DECISION_REQUIRED:
[question]. Do not block on resolving it.
```

**Structural validation:**
```bash
~/.claude/skills/eng-stories/scripts/validate-stories.sh docs/plans/FEAT-XXX-stories.md --size {team|large}
```
Exit 1 → re-run the subagent citing the specific missing sections; re-validate ONCE. Second failure → interactive: ask; headless: ERROR `VALIDATION_FAILED`.

**Checkpoint:** `last_completed_step: "6"`

## Step 7: Traceability + Depth Trace + Source Reconciliation

Pre-flight: `mkdir -p docs/.eng-planning/{feature_id}/traceability/`. Template: `templates/traceability-pipeline.md`. Placeholders: `{TRACE_DIR}`, `{PRD_PATH}`, `{ARTIFACT_PATHS}`, `{BEHAVIORAL_INVENTORY_PATH}` = `.../behavioral-inventory.md` (per-cluster `behaviors-*.md` are the fallback if the background merge hasn't finished).

**Light tier — 2 parallel sonnet agents:** Agent 1 (Forward Tracer): every PRD requirement maps to ≥1 story — MATCH/DROPPED/DILUTED/DOWNGRADED/SPLIT_RISK/REINTERPRETED → `forward-trace.md`. Agent 2 (Reverse + Depth): reverse trace (TRACED/SCOPE_CREEP/ENG_NECESSITY, no orphans) + depth (source behaviors vs story ACs; >3x more behaviors than ACs → THIN_STORY) → `reverse-depth-trace.md`. Main agent merges into `traceability-matrix.md`.

**Standard tier — 3 parallel sonnet agents:** Forward, Reverse, and Agent 3 (Depth + Source Reconciliation): per PRD feature, verify each source behavior appears in ≥1 story AC; categorize uncovered ones → `behavioral-coverage-report.md`. Main agent merges all traces.

| Uncovered category | Definition | Action |
|----------|-----------|--------|
| DEPTH_GAP (~70%) | In PRD + code, story AC too abstract | Auto-expand: add source-derived ACs |
| EXTRACTION_GAP (~20%) | In code, P1/P2-or-absent in PRD | Flag for PM scope decision |
| NEW_REQUIREMENT (~10%) | Not in code or PRD | Flag for discovery + cross-link to domain questionnaire |

**PASS** (all dimensions clean) → Step 8. **FAIL** → fix DEPTH_GAPs autonomously (add ACs, then re-check story size — a story pushed past M by new ACs gets split), flag EXTRACTION_GAP/NEW_REQUIREMENT for Step 9, re-run pipeline (max 1 iteration). Also verify: no jargon in titles/objectives/requirements/ACs, no orphan stories.

**Checkpoint:** `last_completed_step: "7"`, `traceability_pass`

## Step 8: Specificity Verification (script — the prose rule is not trusted alone)

```bash
~/.claude/skills/eng-stories/scripts/validate-stories.sh docs/plans/FEAT-XXX-stories.md \
  --size {team|large} --inventory docs/.eng-planning/{feature_id}/
```
The script extracts every number+unit token (timeouts, intervals, retries, limits, percentages, counts) from `behaviors-*.md`/`behavioral-inventory.md` and flags tokens whose number never appears in the stories doc. Exit 2 → for EACH flagged value: (1) locate its context in the inventory; (2) check the stories doc for a word-form equivalent ("once per second" covers "1 second"); (3) genuinely lost → restore it into the relevant AC/requirement in plain English; (4) intentionally excluded (out-of-scope/[IMPL]) → say why. Record every disposition in `docs/.eng-planning/{feature_id}/specificity-report.md` — no flag is dismissed without a written disposition. Re-run until exit 0 or all flags dispositioned.

**Checkpoint:** `last_completed_step: "8"`

## Step 9: Approval Gate

Assemble the approval package — story summary (N stories × priority × size mode), behavioral coverage (found/covered %, DEPTH_GAPs expanded, EXTRACTION_GAPs, NEW_REQUIREMENTs), DECISION_REQUIRED items, domain-questionnaire open questions, specificity-report summary — and write it to `docs/.eng-planning/{feature_id}/approval-package.md` in ALL modes (it is the human's async review artifact; never skip writing it).

- **Interactive:** present, then "Approve stories, or request changes?" — rejected → edit + re-present; approved → Step 10.
- **`--auto-approve` (any mode):** record `step_9_approved: "auto"`, continue to Step 10.
- **Headless without `--auto-approve`:** set `progress.json` `status: "AWAITING_APPROVAL"`, print `ENG-STORIES-STATUS: AWAITING_APPROVAL feature=<FEAT-XX> package=<path>`, exit cleanly. A later interactive session (or `--auto-approve` re-run) resumes at Step 10. Do NOT dangle waiting on a question nobody will answer (June: 9 sessions died at this gate and Step 10 never ran).

**Checkpoint:** `last_completed_step: "9"`, `step_9_approved: true|"auto"`

## Step 10: Story Quality Review (`model: "sonnet"`)

Single subagent; prompt = Enforcement Preamble + PRD path + stories path + these 7 checks; findings as `[P0|P1|P2] [story-id:section] — description` to `docs/.eng-planning/{feature_id}/review-findings.md`:

1. **LANGUAGE (board-director test)** — flag ANY jargon anywhere INCLUDING titles and ID mnemonics: variable names, framework terms, config fields, state-machine notation, HTTP codes, class names, file paths. P0 if a title/objective/user story/requirement/workflow reads like code.
2. **SPECIFICITY PRESERVED** — P0 if a concrete source value (retry count, timeout, interval, limit, multi-flag gate) became vague language ("short delay", "periodically", "can be enabled"). Cross-check `specificity-report.md` dispositions.
3. **ACs TESTABLE** — flag "works correctly", "handles errors properly", "as expected".
4. **REQUIREMENTS DETAILED ENOUGH** — engineer knows what to build, QA knows what to test, without a separate technical doc.
5. **WORKFLOWS COVER ERROR PATHS** — flag happy-path-only workflows (large mode; team mode: error behavior must appear in ACs/edge cases).
6. **NO ORPHAN STORIES** — every story traces to a PRD requirement.
7. **SIZE & THIN STORIES** — no story estimated >M; previously-flagged THIN stories expanded; AC count proportional to source behavior count.

Main agent fixes P0/P1 directly in the story doc (no re-review cycle); P2s reported in final output.

**Checkpoint:** `last_completed_step: "10"`

## Step 11: Jira Delivery (optional — only `--jira <PROJECT-KEY>` or explicit user request)

The pipeline's real terminus is Jira (June: 14 epics / 134 stories / 413 subtasks posted by hand-orchestrated sessions — twice). Encoded:

1. **Strip:** copy the stories doc to `docs/.eng-planning/{feature_id}/jira/FEAT-XXX-stories-jira.md`, deleting any `Legacy Implementation Reference` and `Build Guidance` sections (legacy-format docs) — internal analysis never ships to Jira.
2. **Field mapping** (epic first, then stories, then subtasks — parents before children):

| Artifact | Jira type | Fields |
|---|---|---|
| FEAT-XXX | Epic | summary = feature title; description = Objective + Story Index |
| S-XXX | Story (parent = epic) | summary = story title; description = User Story, Business Value, Success Metric, Preconditions, Workflow (large mode), Requirements, ACs as checklist, Edge Cases; priority P0→Highest, P1→High, P2→Medium |
| T-XXX-N | Sub-task (parent = story) | summary = sub-task text |

3. **Post:** invoke the `atlassian-connect` skill (Skill tool) for authenticated API access. Record every created issue key in `docs/.eng-planning/{feature_id}/jira/posted.json`.
4. **Verify by re-query, not by memory:** list issues under the epic; compare story AND subtask counts to the doc. Mismatch → report exactly which are missing; do not re-post blindly (duplicate-issue risk).
5. **No `--jira` flag (or headless without it):** emit a HANDOFF CONTRACT block in the final report — the jira-ready file path, the mapping table above, and "run `/jira-update` or `/atlassian-connect` with this file + a project key". Never post to Jira un-asked.

**Checkpoint:** `last_completed_step: "11"`, `jira: {posted: N|"handoff"}`

## Step 12: Cleanup & Report

1. `last_completed_step: "12"`, `remaining_steps: []`
2. Report the working dir location. Interactive: AskUserQuestion — **Delete now** (`rm -rf docs/.eng-planning/{feature_id}/`) / **Keep for reference**. **Honor the answer exactly — if the user says Keep, nothing under the namespace is deleted, ever** (June defect: cleanup ran against the user's stated choice). Headless: always keep.
3. Report:

```
STATUS: DONE | DONE_WITH_CONCERNS | AWAITING_APPROVAL
ARTIFACTS: docs/plans/FEAT-XXX-stories.md — [N stories, M ACs, size mode]
BEHAVIORAL COVERAGE: found N · covered M (X%) · DEPTH_GAPs expanded D · EXTRACTION_GAPs E · NEW_REQUIREMENTs R
OPEN QUESTIONS: [N]   SPECIFICITY: [flags F, restored G, dispositioned H]
DECISION_REQUIRED: [N]   REVIEW: [P0/P1 fixed, N P2s deferred]
JIRA: [posted epic+N stories+M subtasks | HANDOFF CONTRACT: <jira-ready file> + /jira-update]
NEXT: PM answers questionnaire + EXTRACTION_GAP/NEW_REQUIREMENT scope calls · resolve
DECISION_REQUIRED before BUILD · /eng-planning for architecture + contracts · or straight to
BUILD only if architecture is trivial AND the repo's VIBE level doesn't mandate R1/R7
```

## Intermediate Files (all under `docs/.eng-planning/{feature_id}/`)

| Step | File | Written by → consumed by |
|------|------|--------------------------|
| all | `heartbeat.json` (batch only), `error.json` (on failure) | each step → batch watchdog / runner |
| 1 | `progress.json` | all steps → resume + collision guard |
| 3 | `clusters-{repo-name}.json` | main agent → Step 4 |
| 4 | `explorer-/summary-/behaviors-{repo}-{cluster}.md`; merged `explorer-report.md`, `behavioral-inventory.md` | explorers / background merge → 6, 7, 8 |
| 5 | `domain-questionnaire.md` | main agent → 6 (appendix), 9 |
| 6 | `docs/plans/FEAT-XXX-stories.md` | story generator → 7-11 |
| 7 | `traceability/{forward-trace,reverse-depth-trace,behavioral-coverage-report,traceability-matrix}.md` | tracers/main → 9, 10 |
| 8 | `specificity-report.md` | main agent → 9, 10 |
| 9 | `approval-package.md` | main agent → human / resuming session |
| 10 | `review-findings.md` | reviewer → 12 |
| 11 | `jira/FEAT-XXX-stories-jira.md`, `jira/posted.json` | main agent → verification, handoff |

**Context rules:** subagents write to disk, main agent reads from disk (never return values); re-read at step boundaries; the PRD is the source of truth (read in full, never a lossy summary); main agent holds summaries only — never full PRD + full explorer report simultaneously.

## Resume Detection

At start (after deriving `feature_id` per 1b, including the collision guard): read `progress.json` if present — fields: `feature_id`, `prd_path`, `last_completed_step` (string), `tier`, `source_repos`, `story_size`, `mode`, `clusters_per_repo`, `step_9_approved`, `traceability_pass`, `quota_stop`, `status`. Resume from the NEXT step; re-read PRD + surviving intermediates. `quota_stop: true` → clear it and continue. `status: AWAITING_APPROVAL` → interactive: run Step 9 ask; `--auto-approve`: record and go to Step 10. **Legacy step ids** from pre-July runs map: 0→1, 0.5→2, 0.7→3, 1→4, 5a→6, 7.5→7, 8→9, 9→10, 13→12. Not found → Step 1.

## Red Flags — STOP Immediately

- Edit/Write on .py/.ts/.js/.cs files → you are the planner
- AskUserQuestion in headless mode → dead batch slot; use the defaults table or the Error Contract
- Jargon anywhere in the story — including TITLES and ID mnemonics (S-CRUD, "…CRUD Endpoints…"), objectives that read like code ("Implement XService…"), class names, paths, HTTP codes, state-machine notation → artifacts are 100% PM-facing
- A number/duration/mechanism in the inventory missing from stories with no disposition → Step 8 is not done
- Story estimated L/XL surviving past Step 7 → split it (vertically)
- Horizontal-layer decomposition, single-layer story without `HORIZONTAL-JUSTIFIED`, or Test Plan missing its `Slice Done Gate:` line → re-slice / add it
- Zero-coverage PRD area with confident stories and no questionnaire entry → silence is the failure mode
- Retrying a rate-limited spawn in a loop → checkpoint + exit resumably instead
- Engineering-checklist requirement ("Concurrent access: optimistic locking") → rewrite as user-facing behavior
- Artificial Depends On edges → maximize parallelism; skipping behavioral extraction when source_repos is provided → that's the whole point
- Writing progress/heartbeat/cluster files outside `docs/.eng-planning/{feature_id}/` → parallel runs will collide
- Deleting intermediates after the user chose "Keep" → honor the cleanup answer exactly

## Maintenance (when editing this skill or its templates)

After ANY edit to SKILL.md, `templates/*`, or `scripts/*`: (1) grep the skill + templates for references to renamed/removed steps, sections, files, or flags (stale refs were a June defect class); (2) `bash -n scripts/*.sh`; (3) confirm every MCP tool name cited here exists in a live session's tool list before citing new ones (hallucinated MCP names shipped once already).
