# ~/.claude — A Self-Improving Agent Infrastructure

A version-controlled Claude Code configuration that enforces engineering discipline, orchestrates multi-agent workflows, and learns from every session. Built around the **VIBE Protocol** (spec-driven TDD with per-task subagent pairs) and a **three-tier memory system** that turns session ephemera into durable lessons.

## Who This Is For

Anyone using Claude Code who wants:
- Guardrails that prevent dangerous git operations and enforce TDD
- Multi-agent orchestration for feature development (coder + QA pairs)
- Automated session journaling and lesson extraction
- A library of reusable skills for code review, debugging, testing, and product management
- A system that gets smarter over time without manual effort

## Architecture Overview

```
~/.claude/
├── CLAUDE.md                    # Global instructions (loaded every session)
├── rules/                       # Engineering standards & protocol rules
│   ├── code-style.md           #   TDD, naming, documentation, debugging
│   ├── vibe-protocol.md        #   VIBE protocol quick reference
│   └── protected-files.md      #   Files that must never be deleted
├── docs/                        # Reference documentation
│   ├── vibe-manual.md          #   Full VIBE protocol (source of truth, ~700 lines)
│   └── backlog.md              #   Project backlog and work tracking
├── memory/                      # Three-tier learning system
│   ├── journal.md              #   Tier 1: Append-only session log (auto-populated)
│   ├── lessons.md              #   Tier 3: Curated cross-project patterns
│   └── MEMORY.md               #   Index of memory files (loaded into context)
├── skills/                      # 30+ reusable agent skills
│   ├── lead-orchestrator/      #   Multi-agent task coordination
│   ├── systematic-debugging/   #   4-phase root-cause analysis
│   ├── pr-review-pr/           #   Multi-persona PR review
│   ├── prd-writer/             #   Data-driven PRD generation
│   └── ...                     #   (see Skills section below)
├── scripts/                     # Hooks and automation
│   ├── git-safety-hook.sh      #   PreToolUse: blocks dangerous git ops
│   ├── session-journal.py      #   Stop: captures session activity
│   ├── synthesize-lessons.py   #   Cron: journal → lessons via Claude Sonnet
│   ├── statusline.sh           #   Live session status bar
│   └── ...
├── plugins/                     # Plugin registry and marketplace config
├── settings.json                # Hooks, permissions, sandbox, plugins
├── schedules.json               # Cron tasks (synthesis, cleanup, audit)
└── tests/                       # Tests for the infrastructure itself
```

## How It All Fits Together

```
Session Start
    │
    ├─ CLAUDE.md loaded (behavior rules, engineering standards)
    ├─ rules/ loaded (code-style, VIBE protocol, protected files)
    ├─ memory/MEMORY.md loaded (cross-session context)
    │
    ├─ PreToolUse Hook ──→ git-safety-hook.sh
    │   Blocks: git add -A, --no-verify, push --force,
    │           reset --hard, protected file deletion
    │
    ├─ [User works: skills invoked, code written, tests run]
    │
    └─ Session End
        ├─ Stop Hook ──→ session-journal.py
        │   Parses transcript, extracts intent/actions/errors/decisions
        │   Appends structured entry to memory/journal.md
        │
        └─ Notification Hook ──→ terminal-notifier (macOS alert)

Twice Daily (cron):
    synthesize-lessons.py
    ├─ Reads unprocessed journal entries
    ├─ Sends to Claude Sonnet with deduplication context
    ├─ Applies "30-day / 2-repo test" (would this help on a different project?)
    ├─ Atomically updates memory/lessons.md
    └─ Marks entries as processed

Weekly (cron):
    ├─ weekly-cleanup.sh  — Deletes stale debug/telemetry (>14 days)
    └─ weekly-audit.sh    — Health report (disk, sessions, worktrees)
```

---

## Key Components

### 1. CLAUDE.md — Global Instructions

Loaded into every conversation. Establishes:
- **No sycophancy** — honest judgment over agreeableness; push back on bad ideas
- **Proactiveness rules** — execute immediately unless ambiguous, destructive, or multi-path
- **Engineering preferences** — handle edge cases (80/20), every mistake becomes a check or doc
- References `rules/code-style.md` for detailed standards

### 2. Rules (`rules/`)

**`code-style.md`** — Non-negotiable engineering standards:
- **TDD mandatory**: Red → Green → Refactor. No code without a failing test.
- **YAGNI**: No code > code. No backward-compat shims without permission.
- **Naming**: Domain stories (`Registry`, `execute()`) over impl details (`ZodValidator`, `ToolFactory`). Hard stop on `new/old/legacy/wrapper`.
- **Documentation**: Mandatory 5-line ABOUTME block per file, 3+ line comment per function.
- **Testing**: No mocks in E2E tests. Real DB, real APIs. Pristine test output.
- **Debugging**: Root cause only. Investigate → Pattern → Hypothesize → Fix. No symptom patches.

**`vibe-protocol.md`** — Condensed reference for the VIBE protocol (see below).

**`protected-files.md`** — Self-protecting list of files that hooks prevent from deletion.

### 3. The VIBE Protocol (`docs/vibe-manual.md`)

A spec-driven TDD workflow with per-task subagent orchestration. Two enforcement tiers:

| | `full` (production apps) | `light` (tooling, scripts) |
|---|---|---|
| TDD | Required | Required |
| Spec Wall | Required | Skip |
| Phase Gates | Enforced | Skip |
| QA Cycles | 2 minimum | 1 code review |
| API Contracts | Required | Skip |
| Real Testing | Required | Required |
| Auto-Commit | Yes | Yes |

**Hard Gates (always enforced):**

| Gate | Rule |
|------|------|
| R0 | **Zero Assumption Policy** — Never guess requirements. Ask until explicit. |
| R2 | **TDD Mandate** — No implementation without a failing test. |
| R6 | **Auto-Commit** — Commit after every task completion. No batching. |
| R10 | **Real Testing** — Hit real DB and APIs. No mocks on internal modules. |
| R11 | **Spec-Diff Verification** — Cite `file:line` evidence per requirement before marking done. |

**Phase Gates** (for `full` VIBE):
- `DISCOVERY` → interview, read-only analysis
- `ARCHITECTURE_APPROVED` → specs, decomposition
- `FEATURE_SPECS_APPROVED` → specs finalized
- `BUILD` → implementation allowed

**Five Roles:**

| Role | When | Key Rule |
|------|------|----------|
| PM Interviewer | Project start | Ask until scope is unambiguous |
| Architect | PRD approved | Produce API contracts before BUILD |
| Developer | In `feat/*`, phase=BUILD | TDD; output `T-XXX-ready-for-review.md` |
| QA Auditor | Developer claims done | Never edit implementation code |
| Orchestrator | On `main/master` | Spawn subagent pairs; never implement |

**Per-Task Orchestration Loop:**
```
ARCHITECT → design task → STOP
CODER → TDD → ready-for-review.md → STOP
QA CYCLE 1 (P0: security, logic, contracts) → PASS/FAIL → STOP
  └─ FAIL → coder fix → re-run → FAIL → ESCALATE (N=1 rule)
QA CYCLE 2 (P1 fix, P2 defer) → PASS/FAIL → STOP
ON PASS → auto-commit & push
```

### 4. Skills (`skills/`)

Reusable agent prompts invoked via `/skill-name` or the Skill tool. Grouped by purpose:

#### Development Workflow
| Skill | Purpose |
|-------|---------|
| **lead-orchestrator** | Coordinates subagent pairs (coder→QA) per task. Enforces QA cycles, manages E2E suites. The nerve center for feature development. |
| **systematic-debugging** | 4-phase root-cause protocol: Investigate → Pattern → Hypothesize → Fix. Hard gates between phases. |
| **vibe-lookup** | Quick reference for VIBE protocol rules, phases, roles, templates. |
| **new-project** | Scaffolds `.claude/`, `CLAUDE.md`, `memory/`, `qa/`, `docs/` for a new repo. |
| **codebase-mapping** | Spawns explorer + architect agents to produce architecture docs with feature-to-code mappings. |

#### Code Review & PR
| Skill | Purpose |
|-------|---------|
| **pr-review-pr** | Multi-persona PR review with auto-routing. 3 reviewers: Architecture (system design, security), Domain Specialist (business logic, tests), Ambition Backstop (YAGNI enforcement). |
| **garry-review** | Engineering preferences audit — architecture, code quality, test coverage, tradeoffs. |
| **pr-code-reviewer** | Bug detection: logic errors, null handling, race conditions. Confidence-scored findings. |
| **pr-silent-failure-hunter** | Finds catch blocks that swallow errors, tests that pass without exercising code. |
| **pr-briefing** | Generates structured review guide for large PRs (10+ files). Parallelizable chunks with dependency graphs. |
| **pr-code-simplifier** | Simplification pass: reduce complexity, eliminate redundancy, preserve functionality. |
| **pr-comment-analyzer** | Comment accuracy audit. Flags misleading, outdated, or missing documentation. |
| **pr-type-design-analyzer** | Type design evaluation: encapsulation, invariant expression, anti-pattern detection. |
| **pr-test-analyzer** | Test coverage quality: behavioral coverage, critical gaps, implementation-detail coupling. |

#### Testing & QA
| Skill | Purpose |
|-------|---------|
| **e2e-test-writer** | Generates YAML test cases from PRD requirements. Classification: full-stack, frontend, backend. |
| **e2e-qa-runner** | Executes YAML tests via Claude-in-Chrome MCP. Per-tab isolation for parallelism. |
| **e2e-testing** | E2E prerequisites checklist, 8 common failure modes, troubleshooting decision tree. |
| **browser-testing** | Patterns for Claude-in-Chrome: React-safe fills, condition-based waits, parallel tabs. |

#### Product Management
| Skill | Purpose |
|-------|---------|
| **prd-writer** | Data-driven PRD generation. Enforces testable hypotheses, prior-art honesty, JTBD structure, KPI tables. Includes quality patterns reference and critique mode. |
| **video-script-creator** | Converts documents into video scripts with scene breakdowns. Multiple narrative arc templates. |
| **pm-morning** | Daily triage: scans Teams, Outlook, JIRA for overnight activity. Produces prioritized action report. |
| **pm-weekly** | Weekly status email: evidence extraction from Teams + Outlook, cross-source dedup, executive draft. |
| **pm-jira** | JIRA/Confluence monitor: tracks ticket changes, generates draft responses. |

#### Connectors
| Skill | Purpose |
|-------|---------|
| **atlassian-connect** | Adds Atlassian MCP (JIRA + Confluence) to project settings. |
| **glean-connect** | Adds Glean MCP (enterprise search) to project settings. |

### 5. Scripts & Automation (`scripts/`)

#### Hooks (triggered by Claude Code events)
| Script | Hook | Purpose |
|--------|------|---------|
| `git-safety-hook.sh` | PreToolUse (Bash) | Blocks `git add -A`, `--no-verify`, `push --force`, `reset --hard`, protected file deletion. Strips heredocs to prevent obfuscation. |
| `auto-journal.sh` → `session-journal.py` | Stop | Parses transcript JSONL. Extracts intent, actions, decisions, errors, struggles, outcome. Appends to `memory/journal.md`. Deterministic (no LLM calls), runs in <2s. |
| `pm-send-synthesize-hook.sh` | SessionEnd | Checks if PM feedback needs synthesis; spawns async if so. |
| `statusline.sh` | StatusLine | 2-line status bar: model, session ID, git branch, context %, cost, duration, disk, AWS expiry. Cached (5s fast / 60s slow TTL). |

#### Scheduled (via `schedules.json`)
| Script | Schedule | Purpose |
|--------|----------|---------|
| `synthesize-lessons.py` | 2x daily | Reads unprocessed journal entries → Claude Sonnet extraction → atomic update to `lessons.md`. File-locked, crash-safe. |
| `weekly-cleanup.sh` | Sundays 3am | Deletes stale files (>14 days) from debug/, telemetry/, shell-snapshots/, file-history/. Protects critical files. |
| `weekly-audit.sh` | Sundays 4am | Health report: disk usage, top directories, session activity, stale worktrees. |

#### Manual
| Script | Purpose |
|--------|---------|
| `generate-repomap.py` | Git-activity-ranked codebase summary for LLM context. Supports Python, JS/TS, Go, Rust, Ruby. |
| `auto-push-hook.sh` | Post-commit auto-push for feature branches. Install as `.git/hooks/post-commit`. |

### 6. Memory System (`memory/`)

A three-tier pipeline: **capture → synthesize → curate**.

```
Tier 1: journal.md (real-time, deterministic)
   Every session auto-appended by session-journal.py
   Format: timestamp, project, intent, actions, decisions, errors, struggles, outcome
   Entries marked <!-- processed: YYYY-MM-DD --> after synthesis

Tier 2: synthesize-lessons.py (semantic, twice daily)
   Reads unprocessed journal entries
   Sends to Claude Sonnet with "30-day / 2-repo test":
     "Would this help someone on a DIFFERENT project, 30 days from now?"
   Deduplicates against existing lessons
   Atomic write to lessons.md

Tier 3: lessons.md (curated, high-signal)
   Categories: Tool & MCP, Debugging, Git & Workflow, Orchestration, Project-Specific
   Selection bar: "Will this save time in 4 weeks?"
   Loaded on demand by agents needing historical context
```

**MEMORY.md** is a lightweight index loaded into every conversation context. It contains pointers to memory files and key facts (environment quirks, lessons learned, patterns).

### 7. Plugins

Managed via `plugins/installed_plugins.json` with 6 registered marketplaces.

**Key enabled plugins:**
- `superpowers` — Meta-skills for TDD, verification, debugging, brainstorming, git worktrees
- `pr-review-toolkit` — PR review agents (code reviewer, silent failure hunter, type analyzer, test analyzer)
- `code-review` — Standalone code review
- `code-review-graph` — Knowledge-graph-powered review with blast-radius analysis
- `pyright-lsp` / `typescript-lsp` — Language server integration
- `code-simplifier` — Code simplification agent

### 8. Settings (`settings.json`)

Key configuration:
- **Sandbox enabled** with auto-allow for Bash; git/ssh/gh/docker excluded from sandbox
- **Permissions**: Allow Bash, Read, Edit, Write, Glob, Grep, WebSearch, Task. Deny secrets, SSH keys, /etc edits.
- **Auto-compaction at 60%** context window usage
- **Always-thinking enabled** (extended thinking on all tasks)
- **Hook wiring**: PreToolUse → git-safety, Stop → journal + notification, SessionEnd → synthesis, Notification → alert sound

---

## Adopting This Setup

### Minimal (just the guardrails)

1. Copy `CLAUDE.md` and `rules/code-style.md` to your `~/.claude/`
2. Copy `scripts/git-safety-hook.sh` and wire it in `settings.json`:
   ```json
   "hooks": {
     "PreToolUse": [{ "matcher": "Bash", "hooks": [{ "type": "command", "command": "~/.claude/scripts/git-safety-hook.sh" }] }]
   }
   ```
3. Copy `rules/protected-files.md` and update the file paths to your own critical files

### Adding the memory system

4. Copy `scripts/session-journal.py` and `scripts/auto-journal.sh`
5. Wire the Stop hook:
   ```json
   "Stop": [{ "matcher": "", "hooks": [{ "type": "command", "command": "~/.claude/scripts/auto-journal.sh" }] }]
   ```
6. Create `memory/journal.md` (empty) and `memory/MEMORY.md` (index)
7. Optionally set up `synthesize-lessons.py` on a cron for automatic lesson extraction (requires `ANTHROPIC_API_KEY`)

### Adding skills

8. Copy individual `skills/` directories you want. Key starter set:
   - `systematic-debugging` — enforces root-cause analysis
   - `garry-review` or `pr-code-reviewer` — code review
   - `new-project` — repo scaffolding
9. For full orchestration, copy `lead-orchestrator` and `docs/vibe-manual.md`

### Full setup

10. Copy the entire repo and customize:
    - Edit `CLAUDE.md` for your own preferences and behavior rules
    - Edit `rules/code-style.md` for your engineering standards
    - Update `rules/protected-files.md` with your critical files
    - Remove skills you don't need (PM skills are domain-specific)
    - Set up `schedules.json` for automated synthesis and cleanup

---

## What's Version-Controlled vs Ephemeral

**Tracked in git** (the durable configuration):
- `CLAUDE.md`, `rules/`, `docs/`, `skills/`, `scripts/`, `memory/`
- `settings.json`, `schedules.json`, `.gitignore`
- `plugins/installed_plugins.json`, `blocklist.json`, `known_marketplaces.json`
- `tests/`

**Ephemeral** (in `.gitignore`, regenerated per session):
- `debug/`, `todos/`, `session-env/`, `file-history/`, `paste-cache/`
- `plans/`, `tasks/`, `history.jsonl`, `cache/`, `telemetry/`
- `plugins/cache/`, `plugins/repos/`, `plugins/marketplaces/`
- `projects/` (per-project transcripts), `logs/`, `downloads/`

---

## Design Principles

1. **Fail silently, never block** — All hooks and scripts exit 0 on error. Safety checks degrade gracefully.
2. **Atomic writes** — `synthesize-lessons.py` writes to temp file then renames. No corruption on crash.
3. **Deterministic where possible** — Session journaling uses no LLM calls. Fast, predictable, auditable.
4. **Self-improving** — Every session feeds the journal → synthesis → lessons pipeline. Patterns compound.
5. **Portable** — Scripts use `perl` instead of GNU sed for macOS compatibility. No Linux-only tools.
6. **Layered enforcement** — CLAUDE.md (behavior) → rules/ (standards) → hooks (runtime guards) → skills (workflow).
