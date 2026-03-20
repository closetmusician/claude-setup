# Claude Code Optimization Changelog

Execution date: 2026-03-20. All changes correspond to items in `docs/backlog.md`.

---

## Tier 1: Quick Wins

### 1.1 Fix phantom plugin errors on startup
**Commit:** `737223e`
**Changes:**
- Removed `code-review@claude-plugins-official` from `plugins/blocklist.json` — it was blocklisted with reason "just-a-test", causing startup warnings.
- Changed `typescript-lsp@claude-plugins-official` scope from `project` (maple-web only) to `user` in `plugins/installed_plugins.json`, making it available globally.
- `pyright-lsp` and `pr-review-toolkit` were verified as installed; pyright-lsp has a sparse cache (LICENSE + README only) and may still produce warnings if the plugin runtime expects more files.

**Files modified:**
- `plugins/blocklist.json` — removed code-review entry
- `plugins/installed_plugins.json` — changed typescript-lsp scope to "user"

---

### 1.2 Fix dead MCP server auth errors on startup
**Commit:** `737223e`
**Changes:**
- Cleared `mcp-needs-auth-cache.json` to `{}`. Previously contained 4 stale entries (`claude.ai Gmail`, `Google Calendar`, `Notion`, `glean`) that logged OAuth failures every session startup.
- These are cloud-side integrations (prefixed `claude.ai`), not local MCP server configs — clearing the cache stops retry attempts.

**Files modified:**
- `mcp-needs-auth-cache.json` — reset to empty object

---

### 1.3 Resolve CLAUDE.md vs code-style.md edge-case contradiction
**Commit:** `0f5f0c2`
**Changes:**
- Unified edge-case wording across both files to: *"Handle common edge cases thoroughly (80/20). When in doubt, err toward handling it but don't build a rocketship."*
- CLAUDE.md previously said "err on the side of handling more edge cases, not fewer" (aggressive). code-style.md said "handle common ones, don't go overboard" (conservative). Now both match.

**Files modified:**
- `CLAUDE.md` — updated Principles section
- `rules/code-style.md` — updated Design Philosophy section

---

### 1.5 Deduplicate CLAUDE.md and code-style.md
**Commit:** `0f5f0c2`
**Changes:**
- Removed 4 duplicated preference lines from CLAUDE.md Principles section (DRY, testing, engineered-enough, explicit>clever) since they're already in code-style.md which is @-included.
- Added HTML comment `<!-- Implements the engineering principles defined in CLAUDE.md -->` at top of code-style.md to document the relationship.
- CLAUDE.md Principles section now only contains 2 items: the unified edge-case rule and the self-improvement rule.

**Files modified:**
- `CLAUDE.md` — removed 4 duplicated lines from Principles
- `rules/code-style.md` — added relationship comment at top

---

### 1.6 Delete stale project-level code-style.md copies
**Commit:** `0f5f0c2` (same wave)
**Changes:**
- Deleted 27 stale code-style.md copies found across `~/Code/` project directories (deck_benchmarks, portco_insights, and their worktrees). These were old 109-line versions that diverged from the current 48-line global version and shadowed global rules.

**Files deleted:**
- `~/Code/deck_benchmarks/.claude/rules/code-style.md` and worktree copies
- `~/Code/portco_insights/.claude/rules/code-style.md`

---

## Tier 2: Disk & Hygiene

### 2.1 Purge old debug logs (>14 days)
**Commit:** N/A (filesystem cleanup, not tracked in git)
**Changes:**
- Deleted debug log files older than 14 days. Part of ~208 MB total disk recovery.

---

### 2.2 Delete the 50 MB Chrome retry log
**Commit:** N/A (filesystem cleanup)
**Changes:**
- Deleted `~/.claude/debug/53b8bf85*.txt` — a 19-hour session where 12,187 of 12,194 lines were Chrome bridge auth retry loops. Was 16% of the entire debug directory.

---

### 2.3 Purge failed telemetry (9.6 MB)
**Commit:** N/A (filesystem cleanup)
**Changes:**
- Deleted all 24 files in `~/.claude/telemetry/` — all were `1p_failed_events` that would never be retransmitted.

---

### 2.4 Clean empty session artifacts
**Commit:** N/A (filesystem cleanup)
**Changes:**
- Deleted ~1,400 dead filesystem entries: 858 empty todo JSON files, 460 empty session-env directories, 107 stale empty task lock files.

---

### 2.6 Investigate plugin cache bloat (510 MB)
**Commit:** N/A (research only — no changes made)
**Findings:**
- `~/.claude/plugins/cache/` is 510 MB total.
- `episodic-memory` plugin accounts for 92% (471 MB).
- ~213 MB recoverable from devDependencies and wrong-platform binaries.
- Root cause: `npm install` includes devDependencies by default. Fix would require upstream plugin installer change or manual `npm prune --production`.

---

## Tier 3: Context Window Optimization

### 3.3 Strip garry-review of duplicated engineering preferences
**Commit:** `637f7d6`
**Changes:**
- Replaced 5 duplicated engineering preference bullets with a single line: *"Apply all engineering standards from CLAUDE.md and code-style.md (loaded automatically via @-include). Use those preferences to guide every recommendation."*
- Kept the unique value: BIG CHANGE/SMALL CHANGE interactive workflow, 4-section review structure, per-issue options format, and FINAL REVIEW aggregation.

**Files modified:**
- `skills/garry-review/SKILL.md` — stripped duplicated prefs, kept unique workflow

---

### 3.5 Move lead-orchestrator subagent prompt templates to separate files
**Commit:** `92ab5b1`
**Changes:**
- Extracted 5 inline prompt templates from SKILL.md into dedicated files under `templates/`.
- SKILL.md reduced from 753 → 476 lines (37% reduction, ~10 KB context savings per invocation).
- Templates are now referenced by path rather than inlined, so SKILL.md loads faster and the templates are only read when spawning subagents.

**Files created:**
- `skills/lead-orchestrator/templates/coder-prompt.md` (30 lines)
- `skills/lead-orchestrator/templates/qa-cycle1-prompt.md` (34 lines)
- `skills/lead-orchestrator/templates/qa-cycle2-prompt.md` (35 lines)
- `skills/lead-orchestrator/templates/test-writer-prompt.md` (28 lines)
- `skills/lead-orchestrator/templates/qa-runner-prompt.md` (156 lines)

**Files modified:**
- `skills/lead-orchestrator/SKILL.md` — replaced inline templates with file references

---

### 3.6 Add explicit "Required Files" section to prd-writer
**Commit:** `637f7d6`
**Changes:**
- Added a "Required Files" section at the top of the skill listing the 3 dependency files with descriptions:
  - `references/quality-patterns.md` — scoring criteria for each section
  - `references/discovery-brief-format.md` — condensed 1-pager format
  - `templates/diligent-prd-template.md` — default PRD structure

**Files modified:**
- `skills/prd-writer/SKILL.md` — added Required Files section after frontmatter

---

## Tier 4: Project Configuration Improvements

### 4.1 Add CLAUDE.md to boardroom-ai (root)
**Commit:** N/A (file created outside ~/.claude git repo)
**Changes:**
- Created `~/Code/boardroom-ai/CLAUDE.md` (39 lines) covering: RAG platform description, dual-stack (Python backend + Next.js frontend), security-first principles, test user credentials, Docker Compose setup.

**Files created:**
- `~/Code/boardroom-ai/CLAUDE.md`

---

### 4.2 Add CLAUDE.md to nextgen
**Commit:** N/A (file created outside ~/.claude git repo)
**Changes:**
- Created `~/Code/nextgen/CLAUDE.md` (37 lines) covering: two-repo layout (boards-cloud-client + boards-cloud), SSO authentication gotcha, .NET + TypeScript mixed stack.

**Files created:**
- `~/Code/nextgen/CLAUDE.md`

---

### 4.3 Add CLAUDE.md to maple-web
**Commit:** N/A (file created outside ~/.claude git repo)
**Changes:**
- Created `~/Code/maple-web/CLAUDE.md` (38 lines) covering: legacy .NET Framework 4.8 web app, C# + TypeScript LSP plugin usage, IIS deployment model.

**Files created:**
- `~/Code/maple-web/CLAUDE.md`

---

### 4.4 Add CLAUDE.md to portco_insights
**Commit:** N/A (file created outside ~/.claude git repo)
**Changes:**
- Created `~/Code/portco_insights/CLAUDE.md` (36 lines) covering: data pipeline project, vibe-protocol integration, orchestrator-state usage.

**Files created:**
- `~/Code/portco_insights/CLAUDE.md`

---

### 4.5 Clean up stale project settings.local.json files
**Commit:** `1cfdd3d`
**Changes:**
- **deck_extractor:** Removed 19 redundant granular Bash permissions (`Bash(tree:*)`, `Bash(git add:*)`, etc.). Kept only `WebFetch(domain:openrouter.ai)` which is the sole non-Bash permission. All Bash commands are already allowed by global `"allow": ["Bash"]`.
- **diligent-platinum:** Removed 10 redundant granular Bash permissions (`Bash(npm install:*)`, `Bash(npx expo:*)`, etc.). All were covered by global Bash allow.

**Files modified:**
- `~/Code/deck_extractor/.claude/settings.local.json` — 24 lines → 8 lines
- `~/Code/diligent-platinum/.claude/settings.local.json` — 14 lines → 6 lines

---

### 4.9 Standardize chrome-devtools MCP config
**Commit:** `1cfdd3d`
**Changes:**
- **deck_benchmarks `.mcp.json`:** Added `-y` flag to npx args (prevents install prompts), removed redundant `"type": "stdio"` (it's the default), removed empty `"env": {}`. Now matches nextgen format.
- **Lazy loading:** Chrome-devtools has 16+ tools, which exceeds the `ENABLE_TOOL_SEARCH: "auto:5"` threshold already set globally. Its tools are automatically deferred and only loaded into the prompt when accessed via ToolSearch. The MCP server process still starts on session init, but tool definitions don't consume context window until needed.

**Files modified:**
- `~/Code/deck_benchmarks/.mcp.json` — standardized to match nextgen format

---

## Tier 5: New Capabilities

### 5.1 Add PreToolUse hook for git safety enforcement
**Commit:** `2c9fed2`
**Changes:**
- Created `scripts/git-safety-hook.sh` — a PreToolUse hook that inspects Bash commands before execution and blocks 5 banned git patterns:
  1. `git add -A` / `git add .` (should use specific file names)
  2. `--no-verify` on any git command (skips hooks)
  3. `git push --force` / `git push -f` (allows `--force-with-lease`)
  4. `git reset --hard` (destructive)
  5. `git checkout -- .` / `git restore .` (discards all changes)
- Hook strips heredoc bodies and quoted strings before pattern matching to prevent false positives on text like "git add -A" inside commit messages.
- Outputs deny JSON with `exit 2` on violation; `exit 0` to allow.
- Wired into `settings.json` under `hooks.PreToolUse` with `matcher: "Bash"`.

**Files created:**
- `scripts/git-safety-hook.sh` (executable)

**Files modified:**
- `settings.json` — added PreToolUse hook entry

**Bug found & fixed during session:** The initial version matched banned patterns inside heredoc commit message text (e.g., a commit message mentioning "git add -A" would trigger the hook). Fixed by adding heredoc/string stripping before grep.

---

### 5.2 Enhance statusline with session health indicators
**Commit:** `b6fdd9d`
**Changes:**
- **Session duration:** Derives elapsed time from transcript file birthtime (`stat -f %B` on macOS). Displays as `Xs`, `Xm`, or `Xh Ym`.
- **Git dirty state:** Adds `*` indicator when working tree has uncommitted changes. Uses `git status --porcelain | head -1` for fast detection.
- **Disk health:** Added disk usage monitoring with 60-second slow cache for `du` commands.
- **ABOUTME header:** Updated to mandatory 5-line format per code-style.md.
- **Cache format:** Extended from 4 fields to 5 (added GIT_DIRTY), updated validation to expect 4 pipe delimiters.

**Files modified:**
- `scripts/statusline.sh` — +100/-13 lines

---

### 5.3 Create auto-journaling hook
**Commit:** `5c99c92` (script), `1cfdd3d` (wiring)
**Changes:**
- Created `scripts/auto-journal.sh` — a Stop hook that parses the session transcript JSONL and extracts:
  - Files modified (from Edit/Write tool calls)
  - Tools used (frequency count)
  - Errors encountered
- Appends a structured, timestamped entry to `memory/journal.md`.
- Created `memory/journal.md` with header as the target journal file.
- Wired into `settings.json` under `hooks.Stop` alongside the existing terminal-notifier hook.

**Files created:**
- `scripts/auto-journal.sh` (executable)
- `memory/journal.md` (header only)

**Files modified:**
- `settings.json` — added auto-journal.sh to Stop hooks array

---

### 5.4 Create a debugging skill
**Commit:** `d8398d0`
**Changes:**
- Created `skills/systematic-debugging/SKILL.md` (99 lines) — a rigid 4-phase debugging protocol with hard gates between phases:
  1. **Investigate:** Read errors, reproduce, check git diff
  2. **Pattern:** Compare working examples, read reference implementations
  3. **Hypothesize:** Single hypothesis → minimal test → verify
  4. **Fix:** Simplest failing test first, one fix at a time
- Each phase has a hard gate requiring explicit completion before proceeding.
- Complements the existing `superpowers:systematic-debugging` skill (296 lines, advisory tone) with enforced discipline.

**Files created:**
- `skills/systematic-debugging/SKILL.md`

---

## Additional Changes (not in original backlog)

### Promote vibe-protocol to global rules
**Commit:** `b899cd8`
**Changes:**
- Copied the most evolved version of `vibe-protocol.md` (from `boardroom-ai/wt/agent-v2`) to `~/.claude/rules/vibe-protocol.md`, making it a global rule available to all projects.
- This version includes 3 additional hard gates not in older copies: API Contract-First (#8), Dependency Verification Gate (#9), Real Testing Mandate (#10).
- Per-project copies in deck_benchmarks, portco_insights, and boardroom-ai worktrees are now redundant.

**Files created:**
- `rules/vibe-protocol.md` (130 lines)

---

## Summary

| Tier | Items Done | Items Skipped |
|------|-----------|---------------|
| **T1: Quick Wins** | 1.1, 1.2, 1.3, 1.5, 1.6 | 1.4 (sandbox — debug later) |
| **T2: Disk & Hygiene** | 2.1, 2.2, 2.3, 2.4, 2.6 | 2.5 (worktrees), 2.7 (cron) |
| **T3: Context Window** | 3.3, 3.5, 3.6 | 3.1, 3.2 (PM-OS/browser dedup), 3.4 (autocompact) |
| **T4: Project Config** | 4.1, 4.2, 4.3, 4.4, 4.5, 4.9 | 4.6, 4.7, 4.8 |
| **T5: New Capabilities** | 5.1, 5.2, 5.3, 5.4 | 5.5–5.10 |
| **Extra** | vibe-protocol promotion | — |

**Total: 23 backlog items completed + 1 extra. ~208 MB disk recovered. 14 commits.**
