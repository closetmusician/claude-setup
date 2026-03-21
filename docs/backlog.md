# Claude Code Optimization Backlog

Audit date: 2026-03-20. Scrubbed 2026-03-21 (23 completed items removed).

---

## Tier 1: Quick Wins (high impact, low effort)

- [ ] **1.4 Add Flag vs Decide rubric to lead-orchestrator subagent prompts**
  Subagents currently either do everything (executor) or nothing (reviewer). Add an explicit boundary: subagents DECIDE factual/technical questions autonomously (which file, what exists, dependency chains, line numbers) and FLAG judgment calls for coordinator (naming APIs, choosing patterns, scope, abstractions, breaking changes). Eliminates unnecessary round-trips while preventing autonomous architectural decisions. Source: od-learnings-2 §10.5. ~30 min prompt edit.

- [ ] **1.5 Add DONE_WITH_CONCERNS verdict to subagent prompts**
  Current subagents return pass/fail. Add a third status: "completed but I have doubts." Lets agents flag uncertainty without blocking. Coordinator decides whether concerns are real. Prevents both false confidence and premature escalation. Source: od-learnings-2 §10.4. One-line addition to subagent prompt templates.

- [ ] **1.6 Add self-correction loop limits to lead-orchestrator**
  When subagent output fails validation: max 2 retries for deterministic failures (test/type/lint errors), immediate escalate for structural failures (spec ambiguity, missing deps). Assumption: 2 failures on same deterministic issue = spec problem, not execution problem. Prevents infinite token waste on broken specs. Source: od-learnings-2 §10.10. Convention change in orchestrator prompts.

- [ ] **1.7 Add MCP ToolSearch bootstrap + dual name variants to agent prompts**
  Agents using Atlassian/Chrome MCP must: (1) call ToolSearch before first MCP use, (2) list both hyphenated AND underscored tool name variants. Tool name normalization is inconsistent — agents may be hitting silent "tool not found" failures. Source: od-learnings-2 §10.9. Quick audit of existing prompts + template fix.

- [ ] **1.8 Fix sandbox security theater**
  `settings.json` has `sandbox.enabled: true` + `allowUnsandboxedCommands: true`, and every project overrides to `enabled: false`. Either commit to sandboxing (set `allowUnsandboxedCommands: false`) or disable globally. Current state is noise.

---

## Tier 2: Disk & Hygiene (~2 GB reclaimable)

- [ ] **2.5 Evaluate dead worktree project data (~1.6 GB)**
  12 worktree-specific directories under `~/.claude/projects/` total 1.6 GB. Verify which worktrees are truly done, then delete their project state. Top candidates:
  - `boardroom-ai-wt-agent-v2` (851 MB)
  - `boardroom-ai-wt-agents` (623 MB)
  - `deck-benchmarks-wt-api` (44 MB)

- [ ] **2.7 Create a cleanup cron or session-exit hook**
  Automate debug log rotation (7-day retention), empty artifact cleanup, and stale telemetry purge. Prevents re-accumulation. Could be a Stop hook or a weekly cron.

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

- [ ] **5.6 Create a project scaffolding skill**
  `portco_insights` was scaffolded by copying `deck_benchmarks` (identical orchestrator-state, vibe-protocol, code-style.md). A `new-project` skill generating clean CLAUDE.md, .claude/rules, and MCP config from templates would be more reliable.

- [ ] **5.7 Add weekly self-audit scheduled job**
  5th schedule that runs weekly and reports: disk usage trends, error rate trends, most common tool failures, context window pressure. This audit, automated. Write to `~/Code/pm_os/reports/claude-health/`.

- [ ] **5.8 Add cost-aware session indicator to statusline**
  Telemetry shows 117 `cost_threshold_reached` events. Add $/session with color zones (green/yellow/red) to statusline. Helps decide when to restart fresh vs. continue in degraded post-compaction state.

- [ ] **5.9 Create a journal/memory skill**
  code-style.md mandates "search journal before complex tasks" and "document architectural decisions" but there is no skill standardizing journal format, location, or search patterns. Formalize this.

- [ ] **5.10 Make pr-silent-failure-hunter project-agnostic**
  Currently references `logForDebugging`, `errorIds.ts` and other codebase-specific patterns. Move project-specific patterns to project CLAUDE.md. Make the skill generic with a "check project CLAUDE.md for project-specific error handling patterns" directive.

- [ ] **5.11 Add Plan Review Gate before enrichment/execution**
  Before enriching or executing any plan stubs, verify the source plan was reviewed. If not: HALT and require review or PM override. Prevents wasting enrichment/execution cycles on structurally broken plans. Depends on having an enrichment phase (od-learnings-2 §4F). Source: od-learnings-2 §10.7A.

- [ ] **5.12 Add spec compliance verification to QA cycle**
  Distinct from validation (tests pass). Three checks after execution: (1) Did executor implement everything spec specifies? (completeness), (2) Did executor build anything spec does NOT specify? (scope creep), (3) Does implementation match spec's intent, not just letter? (spirit). An executor can pass all tests but fail spec compliance — built the wrong thing correctly. Source: od-learnings-2 §10.7C. Medium effort — update garry-review or lead-orchestrator QA prompts.

- [ ] **5.13 Add project-local persona loading pattern**
  When building named reviewer personas (od-learnings-2 §4E), make them project-configurable via data files (`docs/personae/{name}/README.md` in the project repo) rather than forking agent definitions. Same agent prompt, different project context. Prevents persona proliferation while enabling project-specific review standards. Source: od-learnings-2 §10.8. Implement when building personas.

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
