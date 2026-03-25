# Curated Lessons
<!-- ABOUTME: High-signal patterns extracted from journal.md and session learnings. -->
<!-- ABOUTME: Each entry passes the bar: "Will this save time in 4 weeks?" -->
<!-- ABOUTME: Updated: 2026-03-21 -->
<!-- ABOUTME: Source: journal.md, od-learnings.md, od-learnings-2.md -->
<!-- ABOUTME: Maintained by P0-A curation process -->

## Tool & MCP Patterns

- **MCP tools require ToolSearch bootstrap before first use**: Schemas are not in context by default. Always call ToolSearch before invoking any MCP tool (Atlassian, Chrome DevTools, etc.) or the call silently fails.

- **List both hyphenated and underscored MCP tool name variants**: Tool name normalization is inconsistent. Reference both `mcp__holodeck-docs__quick_ue_lookup` AND `mcp__holodeck_docs__quick_ue_lookup` in agent prompts to prevent "tool not found" failures.

- **Dispatch web research to Sonnet subagent, not coordinator**: WebSearch/WebFetch burn coordinator Opus context on potentially large fetches. Dispatch a Sonnet research agent instead — cheaper and protects coordinator context budget.

- **Chrome DevTools MCP needs condition-based waits**: React apps re-render after fills. Use `wait_for_element` or `wait_for_network_idle` between steps, not fixed sleeps. Fixed sleeps cause flaky E2E tests.

- **Skills must be wired into orchestration or deleted**: Dead skills (defined but never invoked) erode trust in the skill system. If garry-review or vibe-lookup show no activation evidence, either integrate into lead-orchestrator's QA cycle or remove.

## Debugging Patterns

- **macOS BSD vs GNU tool incompatibility**: Shell scripts using GNU-specific syntax (sed `c\`, extended regex flags) silently fail on macOS. Use `perl` for portable text processing. A script with `set -euo pipefail` will fail silently at the first incompatible command.

- **`set -euo pipefail` masks root cause**: When a script fails at line 1 due to a portability issue, ALL subsequent commands are skipped. The symptom (nothing works) looks unrelated to the cause (one bad sed command). Debug by testing each command in isolation.

- **2 failed retries on the same error means spec problem, not execution problem**: After 2 failed re-dispatches on a deterministic failure (test, type error, lint), escalate immediately. More retries waste tokens on a broken spec.

- **Distinguish fixable vs structural failures**: Fixable (type error, missing import) — re-dispatch executor. Structural (spec ambiguity, missing dependency, architecture wrong) — STOP and escalate. Never retry structural failures.

- **Self-doubt is a reportable status**: Executors should report DONE_WITH_CONCERNS when uncertain, not mask doubts behind clean DONE. Lets coordinator decide if concerns are real without blocking or false confidence.

## Git & Workflow Patterns

- **Promoting project files to `~/.claude/` requires updating all relative paths**: When vibe-protocol.md was promoted from boardroom-ai, its `docs/vibe-manual.md` reference broke because the relative path no longer resolved. Always grep for relative refs and convert to absolute `~/.claude/` paths.

- **Never `git add -A` without `git status` first**: The safety hook blocks this, but the principle matters: blind staging catches secrets, large binaries, and temp files. Always review what you are staging.

- **Post-commit auto-push is crash insurance, not a gate**: Push work/feature/feat branches in background after every commit. Always exit 0 — push failure must never block commits. Log failures to `.git/push-failures.log`.

- **Session-start safety commit prevents state loss**: If uncommitted changes exist from a prior crashed session, commit them immediately before any branch operations. Non-negotiable — state preservation trumps clean history.

- **Check branch staleness before starting work**: `git merge-base HEAD origin/main` to find divergence point. If >2 days diverged, warn user and recommend merge before new work. Stale branches cause painful merge conflicts.

## Orchestration Patterns

- **Enrichment before execution prevents wrong-file errors**: A lightweight Sonnet research step (~2 min) that verifies file paths, finds existing patterns, and traces imports before executor starts. Only trigger for tasks touching 3+ files. 90% of benefit from adding "verify file paths before editing" to coder prompts.

- **Enricher flags, never decides**: The enricher gathers facts (file paths, patterns, dependencies) but NEVER makes architectural decisions. When it finds ambiguity ("3 patterns found for this"), it flags for coordinator to decide.

- **Sequential review compounds insight**: Fix ALL findings from Reviewer 1 before dispatching Reviewer 2. Each reviewer sees clean work, not known-issues. Skip for single-file bug fixes.

- **Opus for judgment, Sonnet for execution**: Architectural decisions and code review need Opus. Codebase research and spec-following implementation work well with Sonnet. If Sonnet executor reports BLOCKED, escalate to Opus.

- **Orchestrator never codes**: The lead-orchestrator spawns subagent pairs per task. If the orchestrator is editing code, it has violated its role. Spawn, verify, coordinate — nothing else.

- **Write-ahead status makes crash recovery unambiguous**: Mark status in both tracker and document header BEFORE work starts. Tracker "in progress" + Document "pending" = agent crashed on init. Both "in progress" = agent mid-work. Document "complete" + Tracker "in progress" = agent finished, coordinator crashed.

- **Large stubs need Opus tech lead, not direct Sonnet execution**: When a stub exceeds single Sonnet context, dispatch an Opus tech lead as a separate agent (not the coordinator) to decompose into sub-tasks and verify each output. Only exception to "Sonnet for execution."

- **Escalation N=1**: If a task fails more than one fix cycle, STOP and ask the user. Do not endlessly retry — it burns tokens and usually indicates a spec or understanding problem.

- **Parallel agents that produce/consume each other's output need a shared contract BEFORE spawning**: Without an explicit schema, each agent invents its own format. The consumer silently fails on the producer's output. _Example: session-journal.py output `**Actions:**` but synthesize-lessons.py expected `**Files:**`/`**Tools:**` — every entry was silently classified as "trivial" and skipped. The entire pipeline was DOA._

- **"File exists" is not verification — spec-diff is**: After an agent reports completion, compare EACH original spec requirement against implementation evidence (file:line). Grep for keywords catches cosmetic compliance, not functional compliance. _Example: weekly-audit.sh was checked off as complete because the file existed and looked reasonable, but only delivered 1 of 4 spec requirements (disk usage but not error trends, tool failures, or context pressure)._

- **Agent self-reports are claims, not evidence — apply your own QA process**: An agent reporting "tested and working" is equivalent to a developer saying "it works on my machine." The orchestrator must verify independently, especially for integration between agents. _Example: both session-journal.py and synthesize-lessons.py agents reported successful tests, but neither tested against the other's actual output format. Zero QA cycles were applied to agent work despite our own lead-orchestrator mandating 2 QA cycles per task._

- **"Check them off as you go" creates completion pressure that degrades verification**: When the goal shifts from "verify correctness" to "mark items done," the orchestrator optimizes for checking boxes over quality. Resist this — verification comes first, checkoff is a consequence of verification, never the goal itself.

## Project-Specific Patterns

- **VIBE protocol needs tiered enforcement**: Only deck_benchmarks demonstrates full VIBE compliance. Aspirational rules not enforced erode trust in ALL rules. Add `"vibe_level": "full"|"light"` to phase.json. Light = TDD + review. Full = all 10 gates.

- **PM-OS Node.js hybrid is 6-10x faster than pure LLM**: Deterministic pipeline in Node.js with LLM only for semantic tasks (classification, summarization). Morning scan: 33 min LLM-only vs 5 min hybrid. Use this pattern for any high-volume workflow.

- **Parallel worker pattern for scanning**: Partition channels across N interleaved workers with cloned auth state. Workers write to disk, orchestrator collects from disk (no context penalty). Merge + deduplicate at the end.

- **Cross-repo lessons need a shared store**: Individual repos have project-specific learnings (deck_benchmarks has learning.md, pm_os has TOKEN-7 incident) but no shared knowledge base. This file (`memory/lessons.md`) serves as the cross-repo patterns store.

- **Repo bootstrap template eliminates scaffolding tax**: New repos need: `.claude/phase.json` (DISCOVERY), `.claude/settings.json`, `CLAUDE.md`, `memory/lessons.md`, `qa/`. Without a template, 4 of 7 repos end up with decorative or missing Claude Code integration.

- **Convention-based CI discovery beats config registration**: Name scripts `validate-*.py` or `check-*.py` in a known directory. A runner globs for them automatically. Adding a check = dropping a file. No config editing needed.

- **AI-generated RAG content has ~1-in-4 error rate**: Content sourced from AI-generated documentation needs verification before entering any knowledge base. Human-written sources (blogs, official docs) have near-zero error rate by comparison. Always verify provenance.

- **Plugin install via `claude plugin install` silently fails for local directories**: Manual JSON editing across 3 files (known_marketplaces.json, installed_plugins.json, settings.json) is the workaround. Known limitation, not a design choice.
