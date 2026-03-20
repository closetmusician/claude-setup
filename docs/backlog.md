# Claude Code Optimization Backlog

Audit date: 2026-03-20. Generated from 4 parallel analysis agents scanning all of ~/.claude, ~/Code project configs, debug logs, telemetry, session history, and skills.

---

## Tier 1: Quick Wins (high impact, low effort)

- [x] **1.1 Fix phantom plugin errors on startup**
  `pyright-lsp`, `pr-review-toolkit`, `typescript-lsp`, `code-review` are enabled in `settings.json` but missing from marketplace cache. Every startup logs 12+ warning lines. Reinstall or toggle off in `enabledPlugins`.

- [x] **1.2 Fix dead MCP server auth errors on startup**
  `claude.ai Gmail`, `Google Calendar`, `Notion` fail OAuth every session. `Glean` fails auth too. Re-authenticate or remove from MCP config. Adds 6+ error lines and connection overhead per startup.

- [x] **1.3 Resolve CLAUDE.md vs code-style.md edge-case contradiction**
  CLAUDE.md says "err on the side of handling more edge cases, not fewer." code-style.md says "80/20 edge cases: handle common ones, don't go overboard." Unify to: "Handle common edge cases thoroughly (80/20). When in doubt, err toward handling it."

- [ ] **1.4 Fix sandbox security theater**
  `settings.json` has `sandbox.enabled: true` + `allowUnsandboxedCommands: true`, and every project overrides to `enabled: false`. Either commit to sandboxing (set `allowUnsandboxedCommands: false`) or disable globally. Current state is noise.

- [x] **1.5 Deduplicate CLAUDE.md and code-style.md**
  DRY, "explicit > clever", "engineered enough", and testing importance appear in both files. Since code-style.md is @-included, both are always in context. Keep philosophy in CLAUDE.md, concrete rules in code-style.md. Add one-liner to code-style.md: "Implements the engineering principles defined in CLAUDE.md."

- [x] **1.6 Delete stale project-level code-style.md copies**
  `deck_benchmarks/.claude/rules/code-style.md` (109 lines) and `portco_insights/.claude/rules/code-style.md` (109 lines) are old verbose versions that diverge from the current 48-line global version. They shadow global rules. Delete both.

---

## Tier 2: Disk & Hygiene (~2 GB reclaimable)

- [x] **2.1 Purge old debug logs (>14 days)**
  264 files, ~195 MB. Purely diagnostic, no functional purpose after session ends. Safe to delete.
  ```bash
  find ~/.claude/debug -name "*.txt" -mtime +14 -delete
  ```

- [x] **2.2 Delete the 50 MB Chrome retry log**
  `~/.claude/debug/53b8bf85*.txt` — 19-hour session where 12,187 of 12,194 lines are Chrome bridge auth retry loops. 16% of entire debug directory in one file.

- [x] **2.3 Purge failed telemetry (9.6 MB)**
  All 24 files in `~/.claude/telemetry/` are `1p_failed_events` that will never be retransmitted.
  ```bash
  rm -rf ~/.claude/telemetry/*
  ```

- [x] **2.4 Clean empty session artifacts**
  858 of 898 todo files are empty `[]`. 460 session-env dirs are completely empty. 107 stale empty task lock files. ~1,400 dead filesystem entries.
  ```bash
  find ~/.claude/todos -name "*.json" -empty -delete
  find ~/.claude/session-env -type d -empty -delete
  find ~/.claude/tasks -name ".lock" -empty -delete
  ```

- [ ] **2.5 Evaluate dead worktree project data (~1.6 GB)**
  12 worktree-specific directories under `~/.claude/projects/` total 1.6 GB. Verify which worktrees are truly done, then delete their project state. Top candidates:
  - `boardroom-ai-wt-agent-v2` (851 MB)
  - `boardroom-ai-wt-agents` (623 MB)
  - `deck-benchmarks-wt-api` (44 MB)

- [x] **2.6 Investigate plugin cache bloat (510 MB)**
  `~/.claude/plugins/cache/` is 510 MB. episodic-memory is 92% (471MB). ~213MB recoverable from dev deps + wrong-platform binaries. Root cause: `npm install` includes devDependencies.

- [ ] **2.7 Create a cleanup cron or session-exit hook**
  Automate debug log rotation (7-day retention), empty artifact cleanup, and stale telemetry purge. Prevents re-accumulation. Could be a Stop hook or a weekly cron.

---

## Tier 3: Context Window Optimization

- [ ] **3.1 Shrink PM-OS skills (extract pm-core)**
  `pm-morning` (~1,700 lines) and `pm-weekly` (~2,200 lines) share large chunks: Teams API patterns, classification logic, yk-voice generation, Anthropic API integration. Extract shared infrastructure into a `pm-core` or `pm-infra` skill. Target: 30-50% reduction per skill (25-40KB context savings per invocation).

- [ ] **3.2 Deduplicate browser/E2E skills (extract browser-patterns)**
  React-safe fill pattern and wait/retry patterns are copy-pasted across `browser-testing`, `e2e-qa-runner`, `e2e-test-writer`, `e2e-testing`. Extract into a shared `browser-patterns` reference file. Target: eliminate 200-300 duplicated lines.

- [x] **3.3 Strip garry-review of duplicated engineering preferences**
  Re-enumerates preferences already in CLAUDE.md and code-style.md. Keep only its unique value: the BIG CHANGE/SMALL CHANGE interactive workflow and review structure template. Replace duplicated preferences with "Apply all standards from CLAUDE.md and code-style.md."

- [ ] **3.4 Reassess autocompact threshold after skill size reductions**
  Currently `CLAUDE_AUTOCOMPACT_PCT_OVERRIDE=60`. Sessions hit 108-124K tokens before compaction. 15 frustrated back-to-back `/compact` attempts observed. After reducing skill sizes (3.1-3.3), evaluate whether 60% is still right or bump to 65-70%.

- [x] **3.5 Move lead-orchestrator subagent prompt templates to separate files**
  Extracted 5 templates to templates/ dir. SKILL.md reduced from 753→476 lines (37% reduction).

- [x] **3.6 Add explicit "Required Files" section to prd-writer**
  Skill references `references/` subdirectory files but the dependency chain is not obvious. Add a clear "Required Files" section at the top with full paths.

---

## Tier 4: Project Configuration Improvements

- [x] **4.1 Add CLAUDE.md to boardroom-ai (root)**
  Currently only exists at `DiligentGPT/boardroom-ai/CLAUDE.md` which is a different path from the working directory `~/Code/boardroom-ai/`. Has complex settings, skills, and security concerns.

- [x] **4.2 Add CLAUDE.md to nextgen**
  Active project with MCP config (chrome-devtools), complex permissions. 79 file-not-found errors in one session suggest the agent needs better project context.

- [x] **4.3 Add CLAUDE.md to maple-web**
  Has project settings.json with LSP plugins (TypeScript + C#), suggesting a mixed-stack project that would benefit from documented conventions.

- [x] **4.4 Add CLAUDE.md to portco_insights**
  Has orchestrator-state, vibe-protocol, and rules already — but no CLAUDE.md to tie them together.

- [x] **4.5 Clean up stale project settings.local.json files**
  `deck_extractor` and `diligent-platinum` use old-style granular Bash permissions (`Bash(tree:*)`, `Bash(git add:*)`) that are unnecessary given the global `"allow": ["Bash"]`. Simplify.

- [ ] **4.6 Remove commented-out pseudocode from deck_extractor CLAUDE.md**
  Lines 107-138 are commented-out orchestrator code serving no purpose.

- [ ] **4.7 Split deck_trends CLAUDE.md (241 lines)**
  Acts more as a README than agent instructions. Move informational content (architecture diagrams, dependency lists, cost estimates, project structure) to README.md. Keep CLAUDE.md focused on agent behavioral rules.

- [ ] **4.8 Remove overlapping testing rules from boardroom-ai CLAUDE.md**
  "NO mocks in E2E tests" and "All failures are your fault" are already in global `code-style.md`. Keep only project-specific additions (Playwright structure, test user credentials, auth test naming).

- [x] **4.9 Standardize chrome-devtools MCP config**
  `deck_benchmarks` standardized to match `nextgen` format (added `-y` flag, removed redundant `type: "stdio"` and empty `env`). Chrome-devtools tools (16+) are auto-deferred via `ENABLE_TOOL_SEARCH: "auto:5"`.

---

## Tier 5: New Capabilities & Creative Ideas

- [x] **5.1 Add PreToolUse hook for git safety enforcement**
  PreToolUse hook catches 5 banned git patterns (add -A/., --no-verify, push --force, reset --hard, checkout/restore .) and blocks with deny JSON. Includes heredoc/string stripping to avoid false positives.

- [x] **5.2 Enhance statusline with session health indicators**
  Current statusline is excellent. Add: compaction count (information loss indicator), active skill name, last scheduled job status.

- [x] **5.3 Create auto-journaling hook**
  Stop hook auto-appends session summaries (files changed, tools used, errors) to `memory/journal.md`. Script parses transcript JSONL on session stop.

- [x] **5.4 Create a debugging skill**
  Formalize the 4-step debugging protocol (Investigate, Pattern, Hypothesize, Fix) from code-style.md into an interactive skill that enforces the steps. Prevents jumping to fixes before understanding root cause.

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
