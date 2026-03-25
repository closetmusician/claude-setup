# Claude Code Optimization Backlog

Audit date: 2026-03-20. Scrubbed 2026-03-21 (23 completed items removed).
P0/P1 adoption items added: 2026-03-21 (from od-learnings-2.md §4, with audit verdicts).

---

## P0 — High Impact, Low Effort (from od-learnings-2.md §4)

- [x] **P0-A: Curate journal.md → lessons.md** *(completed 2026-03-21)*
  `~/.claude/memory/lessons.md` exists with 28 entries (79 lines), categorized by topic (Tool/MCP, Debugging, Git, Orchestration, Project-Specific). MEMORY.md references it. journal.md kept as raw log.

- [x] **P0-B: Add post-commit auto-push hook** *(completed 2026-03-21)*
  `~/.claude/scripts/auto-push-hook.sh` (61 lines). Pushes work/*/feature/*/feat/* only, never main/master. Logs to `.git/push-failures.log`, exit 0 always, runs in background via disown.

- [x] **P0-C: Wire write-ahead status into lead-orchestrator** *(completed 2026-03-21)*
  All 3 templates (coder-prompt.md, qa-cycle1-prompt.md, qa-cycle2-prompt.md) have `**Status:** Pending` with agent instruction to update as first action. State machine: Pending → In progress → Complete/Blocked.

- [x] **P0-D: Evaluate repomap generator adoption** *(completed 2026-03-22 — SKIP)*
  Decision: SKIP. `codebase-mapping` skill + Explore agents cover the same use case with less maintenance burden. generate-repomap.py exists in scripts/ but codebase-mapping is the preferred approach.

---

## P1 — High Impact, Medium Effort (from od-learnings-2.md §4)

- [x] **P1-E: Named reviewer personas (start with 3)** *(completed 2026-03-21)*
  3 personas in `skills/pr-review-pr/personas/`: architecture-reviewer.md, domain-specialist.md, ambition-backstop.md. Each wraps garry-review + specific PR skills. Routing table in pr-review-pr SKILL.md (file patterns → persona). Sequential dispatch is default.

- [x] **P1-F: Enrichment phase before execution (lightweight)** *(completed 2026-03-21)*
  coder-prompt.md requirement #1: "Verify before editing: Before any Edit or Write, use Glob to confirm the target file exists at the expected path. Use Read to verify the content you expect to change is actually there. Never edit blind." Full enricher deferred.

- [x] **P1-G: Sequential review protocol** *(completed 2026-03-21)*
  pr-review-pr: "Default: Sequential dispatch (fix findings between reviewers)". lead-orchestrator: P0 loop-back enforced, P1 enforcement section added. Skip for single-file bug fixes documented.

- [x] **P1-H: Review routing layer** *(completed 2026-03-21)*
  pr-review-pr SKILL.md has full routing table (§Review Routing): file patterns + diff keywords → persona/skill selection. Auto-invocation via `git diff --name-only` + content scanning. Manual override preserved. 10+ files triggers pr-briefing first.

- [x] **P1-I: Tier VIBE protocol per-repo** *(completed 2026-03-21)*
  vibe-protocol.md §0.1: full/light gate table. lead-orchestrator: "VIBE Level Detection" section reads vibe_level, adjusts QA cycles and gate enforcement. light skips spec wall, phase gates, QA Cycle 2.

---

## Tier 1: Quick Wins (high impact, low effort)

- [x] **1.4 Add Flag vs Decide rubric to lead-orchestrator subagent prompts** *(completed 2026-03-21)*
  All 3 templates have "Decision Boundaries" section: DECIDE autonomously (file paths, dependencies, line numbers, test assertions) vs FLAG for coordinator (API naming, architecture, scope changes, breaking changes).

- [x] **1.5 Add DONE_WITH_CONCERNS verdict to subagent prompts** *(completed 2026-03-21)*
  Coder: DONE / DONE_WITH_CONCERNS / BLOCKED. QA: PASS / FAIL / PASS_WITH_CONCERNS. Concerns listed explicitly for coordinator evaluation.

- [x] **1.6 Add self-correction loop limits to lead-orchestrator** *(completed 2026-03-21)*
  lead-orchestrator SKILL.md "Self-Correction Limits": deterministic failures max 2 retries, structural failures immediate escalate. Rationale documented in lessons.md.

- [x] **1.7 Add MCP ToolSearch bootstrap + dual name variants to agent prompts** *(completed 2026-03-21)*
  coder-prompt.md step 4: "call ToolSearch with relevant keywords BEFORE first MCP tool call. Tool names may use hyphens or underscores inconsistently — discover actual names first."

- [x] **1.8 Fix sandbox security theater** *(investigated + fixed 2026-03-22)*
  **Root cause:** `allowUnsandboxedCommands: true` made the sandbox an illusion -- any command that failed sandboxed was silently retried unsandboxed. Three projects disabled sandbox entirely via `settings.local.json`.
  **Fix applied to `~/.claude/settings.json`:** Set `allowUnsandboxedCommands: false` (closes blanket escape hatch). Added `excludedCommands: ["git:*", "ssh:*", "gh:*", "docker:*"]` to run network-dependent tools outside sandbox. The `:\*` suffix is required -- bare command names only match no-argument invocations (upstream bug, GitHub #22620).
  **Upstream limitations (won't-fix, tracked by Anthropic):** `excludedCommands` bypasses filesystem sandbox but NOT network sandbox (GitHub #29274). The only reliable workaround for git/ssh is exclusion. Apple marks `sandbox-exec` as deprecated -- long-term uncertainty. Project-level `settings.local.json` overrides (`sandbox.enabled: false`) left in place as fallback until the new config is validated across all workflows.
  **Monitoring:** If sandbox still blocks operations, add specific commands to `excludedCommands` rather than re-enabling `allowUnsandboxedCommands`.

---

## Tier 2: Disk & Hygiene (~2 GB reclaimable)

- [ ] **2.5 Evaluate dead worktree project data (~1.6 GB)**
  12 worktree-specific directories under `~/.claude/projects/` total 1.6 GB. Verify which worktrees are truly done, then delete their project state. Top candidates:
  - `boardroom-ai-wt-agent-v2` (851 MB)
  - `boardroom-ai-wt-agents` (623 MB)
  - `deck-benchmarks-wt-api` (44 MB)

- [x] **2.7 Create a cleanup cron or session-exit hook** *(completed 2026-03-22)*
  `~/.claude/scripts/weekly-cleanup.sh` — runs Sunday 3 AM via `schedules.json`. 14-day retention for debug/, telemetry/, shell-snapshots/, file-history/. Protected file guard via realpath. Logs to `~/.claude/logs/cleanup.log`. First run freed ~11 MB.

---

## Tier 3: Context Window Optimization

- [ ] **3.1 Shrink PM-OS skills (extract pm-core)**
  `pm-morning` (~1,700 lines) and `pm-weekly` (~2,200 lines) share large chunks: Teams API patterns, classification logic, yk-voice generation, Anthropic API integration. Extract shared infrastructure into a `pm-core` or `pm-infra` skill. Target: 30-50% reduction per skill (25-40KB context savings per invocation).

- [ ] **3.2 Deduplicate browser/E2E skills (extract browser-patterns)**
  React-safe fill pattern and wait/retry patterns are copy-pasted across `browser-testing`, `e2e-qa-runner`, `e2e-test-writer`, `e2e-testing`. Extract into a shared `browser-patterns` reference file. Target: eliminate 200-300 duplicated lines.

- [ ] **3.4 Reassess autocompact threshold after skill size reductions**
  Currently `CLAUDE_AUTOCOMPACT_PCT_OVERRIDE=60`. Sessions hit 108-124K tokens before compaction. 15 frustrated back-to-back `/compact` attempts observed. After reducing skill sizes (3.1-3.3), evaluate whether 60% is still right or bump to 65-70%.

---

## Tier 4: Project Configuration Improvements

- [ ] **4.6 Remove commented-out pseudocode from deck_extractor CLAUDE.md**
  Lines 107-138 are commented-out orchestrator code serving no purpose.

- [ ] **4.7 Split deck_trends CLAUDE.md (241 lines)**
  Acts more as a README than agent instructions. Move informational content (architecture diagrams, dependency lists, cost estimates, project structure) to README.md. Keep CLAUDE.md focused on agent behavioral rules.

- [ ] **4.8 Remove overlapping testing rules from boardroom-ai CLAUDE.md**
  "NO mocks in E2E tests" and "All failures are your fault" are already in global `code-style.md`. Keep only project-specific additions (Playwright structure, test user credentials, auth test naming).

---

## Tier 5: New Capabilities & Creative Ideas

- [ ] **5.5 Create a refactoring skill**
  CLAUDE.md says "discuss major refactors before implementation" but there is no structured workflow. Skill should enforce: scope identification, impact analysis, plan proposal, approval gate, incremental execution.

- [x] **5.6 Create a project scaffolding skill** *(completed 2026-03-22)*
  `~/.claude/skills/new-project/SKILL.md` (140 lines). Uses AskUserQuestion for project path, VIBE level, project type, MCP needs. Generates phase.json, settings.json, CLAUDE.md, memory/lessons.md, qa/, and optionally docs/contracts/ + docs/prd/features/.

- [ ] **5.7 Add weekly self-audit scheduled job** *(REVERTED — only 1/4 spec requirements implemented)*
  Current `weekly-audit.sh` reports disk usage only. Still missing: error rate trends, most common tool failures, context window pressure. Needs rewrite to parse debug/telemetry logs for failure patterns and compaction event frequency.

- [ ] **5.8 Add cost-aware session indicator to statusline**
  Telemetry shows 117 `cost_threshold_reached` events. Add $/session with color zones (green/yellow/red) to statusline. Helps decide when to restart fresh vs. continue in degraded post-compaction state.

- [ ] **5.9 Create a journal/memory skill**
  code-style.md mandates "search journal before complex tasks" and "document architectural decisions" but there is no skill standardizing journal format, location, or search patterns. Formalize this.

- [x] **5.10 Make pr-silent-failure-hunter project-agnostic** *(completed 2026-03-22)*
  Removed hardcoded `logForDebugging`, `errorIds.ts`, `logError`, `logEvent` references from SKILL.md. Replaced with generic "check the project's CLAUDE.md and any error handling docs for project-specific logging functions" directive.

- [x] **5.11 Add Plan Review Gate before enrichment/execution** *(completed 2026-03-22)*
  lead-orchestrator SKILL.md: new "Phase 2: Plan Review Gate" checks for `**Reviewed:** YES` or `**Status:** APPROVED` markers. Blocks execution at full VIBE, warns at light. All subsequent phases renumbered.

- [x] **5.12 Add spec compliance verification to QA cycle** *(completed 2026-03-22)*
  qa-cycle2-prompt.md: new "Spec Compliance Verification" section with 3 checks — completeness (every spec requirement implemented), scope creep (no untraced extras), spirit match (intent not just letter). Findings go in cycle-2 artifact under "Spec Compliance" section.

- [ ] **5.13 Add project-local persona loading pattern**
  When building named reviewer personas (od-learnings-2 §4E), make them project-configurable via data files (`docs/personae/{name}/README.md` in the project repo) rather than forking agent definitions. Same agent prompt, different project context. Prevents persona proliferation while enabling project-specific review standards. Source: od-learnings-2 §10.8. Implement when building personas.

---

## Bugs Found by Adversarial QA Audit (2026-03-22)

Discovered by 3 independent QA teams with spec-diff verification. Test suite: `tests/`.

### P1 — Must Fix

- [x] **B1: `logError` still in pr-silent-failure-hunter** *(5.10 regression, fixed 2026-03-22)*
  `skills/pr-silent-failure-hunter/SKILL.md` line ~127 still contains `` `logError` `` as a hardcoded example grep target. 5.10 claimed all hardcoded refs removed — this one was missed.
  Test: `test_tier2_and_5_items.py::TestItem510::test_no_logError_hardcoded`

- [x] **B2: Decision Boundaries missing from newer templates** *(1.4 regression, fixed 2026-03-22)*
  `test-writer-prompt.md` and `qa-runner-prompt.md` lack the "Decision Boundaries" section that exists in the original 3 templates. Cross-cutting requirement not inherited when new templates were added.
  Test: `test_tier1_items.py::TestItem14::test_newer_templates_should_also_have_decision_boundaries`

- [x] **B7: Stale self-reference in lessons.md** *(P0-A data integrity, fixed 2026-03-22)*
  `memory/lessons.md` line 78 references `tasks/lessons.md` — should be `memory/lessons.md`. Stale path from before the file was moved.
  Test: `test_p0_items.py::TestP0A::test_self_reference_path_is_correct`

- [x] **B9: git-safety-hook.sh doesn't block `git add --all`** *(1.8 gap, fixed 2026-03-22)*
  The hook blocks `-A` and `.` but misses `--all` (the long form of `-A`). Partial coverage.
  Test: `test_cross_cutting.py::TestCX5::test_blocks_git_add_all`

### P2 — Should Fix (logged, not blocking)

- [ ] **B5: Backlog claims all personas wrap garry-review** *(P1-E overstatement)*
  P1-E completion note says "Each wraps garry-review + specific PR skills." In reality only architecture-reviewer.md wraps garry-review. domain-specialist and ambition-backstop wrap other PR skills but not garry-review. The backlog description overstates.

- [ ] **B6: auto-push-hook.sh not wired to any trigger** *(P0-B dead code)*
  The script exists and is syntactically valid, but no hook in `settings.json` or `.git/hooks/` triggers it. It's a library script awaiting per-repo symlink wiring. Script documents this, but the backlog completion note doesn't mention the wiring gap.

- [ ] **B10: P1-E backlog claims "Sequential dispatch is default"** *(inaccurate attribution)*
  Sequential dispatch is P1-G's deliverable, not P1-E's. P1-E is about personas. The backlog note for P1-E includes P1-G's claim.

- [ ] **B12: settings.local.json disables sandbox for ~/.claude** *(1.8 acknowledged)*
  `~/.claude/.claude/settings.local.json` sets `sandbox.enabled: false`, overriding the global `enabled: true`. Documented in 1.8 as "left in place as fallback" — but effectively negates 1.8 for this directory.

---

## Usage Patterns Worth Tracking

Reference data from the audit (not actionable items, but context for prioritization):

- **Session profile**: Median 12 min, 4 messages. p90 = 444 min, ~10K tokens.
- **Overhead**: 33% of prompts are meta-commands. 474 /clear, 130 /compact, 909 quick restarts.
- **Top projects**: deck_benchmarks (1,411 prompts), boardroom-ai/agent-v2 (500), pm_os (494).
- **Peak hours**: 23:00-01:00 and 17:00-18:00. Heaviest days: Monday, Sunday.
- **Tool mix**: Bash 54%, Read 14%, Edit 9%. 8% error rate (72% are Command Failed).
- **Streaming stalls**: 14 of 30 recent sessions had stalls, worst = 440 seconds. Server-side.
- **Total disk**: 3.7 GB. projects/ = 2.8 GB, plugins/ = 593 MB, debug/ = 302 MB.
