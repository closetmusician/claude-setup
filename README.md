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
├── CLAUDE.md                    # Shared team instructions (loaded every session)
├── install.sh                   # Team installer (backs up, clones, configures)
├── rules/                       # Engineering standards & protocol rules
│   ├── code-style.md           #   TDD, naming, documentation, debugging
│   ├── vibe-protocol.md        #   VIBE protocol quick reference
│   ├── protected-files.md      #   Files that must never be deleted
│   ├── personal.md             #   [gitignored] Your personal overrides
│   └── personal.md.example     #   Template for personal.md
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

> **Note:** Additional PM workflow skills (`pm-morning`, `pm-weekly`, `pm-jira`, etc.) are personal and gitignored. Symlink your own from `~/Code/pm_os/skills/` if needed.

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

## Getting Started

There are three ways to use this repo, from full install to just reading for ideas.

---

### Option 1: Full Install (Recommended for Diligent team)

```bash
# If you already have ~/.claude, the installer backs it up automatically
git clone https://github.com/closetmusician/claude-setup.git ~/.claude
~/.claude/install.sh
```

**What the installer does:**
1. **Backs up** your existing `~/.claude/` to `~/.claude-backup-<timestamp>/`
2. **Substitutes paths** — `settings.json` ships with `__HOME__` placeholders; the installer replaces them with your actual home directory and marks the file `assume-unchanged` so git ignores your local paths
3. **Creates personal file stubs** — `rules/personal.md`, `memory/journal.md`, `memory/lessons.md` (all gitignored, won't conflict with the team)
4. **Installs macOS dependencies** — `terminal-notifier` via Homebrew (for desktop notifications when Claude finishes a task)
5. **Sets script permissions** — ensures all `scripts/*.sh` are executable

**After install, do this one thing:**
```bash
vim ~/.claude/rules/personal.md
```
Set your name so Claude addresses you correctly. See `rules/personal.md.example` for the template. This file is gitignored — your preferences stay local.

**Updating** — pull the latest shared config anytime:
```bash
cd ~/.claude && git pull
```
Your personal files are gitignored, so pulls won't conflict. If `settings.json` gains new hooks or plugins upstream, re-run `~/.claude/install.sh` to re-substitute paths.

#### What changes apply automatically vs what you'll want to review

**Applies immediately (opinionated — you get these out of the box):**
- `CLAUDE.md` — Team behavior rules: no sycophancy, push back on bad ideas, stop and ask when confused
- `rules/code-style.md` — TDD mandatory, YAGNI, naming conventions, documentation standards, debugging protocol
- `settings.json` hooks — Git safety (blocks `push --force`, `git add -A`, `--no-verify`), session journaling, desktop notifications
- `settings.json` permissions — Auto-allows Bash, Read, Edit, Write, Glob, Grep, WebSearch, Task. Denies reading secrets/SSH keys, editing /etc
- `settings.json` sandbox — Enabled with auto-allow for Bash; git/ssh/gh/docker excluded
- Plugin pre-configuration — superpowers, pr-review-toolkit, code-review, pyright-lsp, typescript-lsp, code-simplifier, code-review-graph

**Review and customize to taste:**
- `rules/vibe-protocol.md` — The VIBE protocol is a spec-driven multi-agent workflow. Great for larger features, overkill for one-off scripts. Read it and decide if it fits your work
- `docs/vibe-manual.md` — Full 700-line VIBE reference. Only relevant if you use the protocol
- Skills in `skills/` — 25+ skills are available. Browse the [Skills section](#4-skills-skills) below to see what's there. You don't need to learn them all; Claude will invoke relevant ones automatically based on the task
- `rules/protected-files.md` — Lists files the git-safety hook prevents from deletion. You may want to add your own critical files
- Plugin choices in `settings.json` `enabledPlugins` — disable any you don't want

**Won't apply (personal, gitignored):**
- `rules/personal.md` — Your name, safe phrases, personal behavior overrides
- `memory/journal.md`, `memory/lessons.md` — Your session history (auto-populated over time)
- `settings.local.json` — Per-user permission overrides
- `schedules.json` — Cron tasks (synthesis, cleanup). Set these up yourself if you want automated lesson extraction

---

### Option 2: Cherry-Pick What You Want

Don't want the full repo as your `~/.claude`? Copy individual pieces into your existing setup:

1. **Guardrails only** — Copy `CLAUDE.md` + `rules/code-style.md` + `scripts/git-safety-hook.sh` and wire the hook in your `settings.json`:
   ```json
   "hooks": {
     "PreToolUse": [{ "matcher": "Bash", "hooks": [{ "type": "command", "command": "~/.claude/scripts/git-safety-hook.sh" }] }]
   }
   ```

2. **Add session journaling** — Copy `scripts/session-journal.py` + `scripts/auto-journal.sh`, create `memory/journal.md`, and wire the Stop hook

3. **Add skills** — Copy individual `skills/` directories. Good starters:
   - `systematic-debugging` — 4-phase root-cause analysis
   - `garry-review` — Engineering preferences code review
   - `pr-review-pr` — Multi-persona PR review
   - `new-project` — Scaffolds Claude Code config for new repos

---

### Option 3: Learn From the Patterns (No Install Needed)

You don't have to clone this repo to benefit from it. Here are the key patterns you can steal for your own `~/.claude/` setup:

#### Pattern: Git safety hooks
`scripts/git-safety-hook.sh` blocks dangerous git operations (force-push, `git add -A`, `--no-verify`, `reset --hard`) via a `PreToolUse` hook on `Bash`. It strips heredocs to prevent obfuscation. Wire any script as a PreToolUse hook to add guardrails.

#### Pattern: Session journaling
`scripts/session-journal.py` parses Claude Code's transcript JSONL at session end, extracts structured data (intent, actions, decisions, errors), and appends to a journal file. No LLM calls, runs in <2s. Over time you build a searchable history of everything Claude did across all your projects.

#### Pattern: Rules as separate files
Instead of one massive `CLAUDE.md`, split concerns into `rules/*.md` files. Claude Code loads all `.md` files in `rules/` automatically. This lets you version-control team standards separately from personal preferences, and swap rules in/out per project.

#### Pattern: Personal overrides via gitignored file
`CLAUDE.md` references `@~/.claude/rules/personal.md` which is gitignored. Team members get shared behavior from tracked files, but customize their name, preferences, and working style locally. No merge conflicts on personal taste.

#### Pattern: `__HOME__` path templating
`settings.json` can't use environment variables, so paths must be absolute. Store `__HOME__` as a placeholder in the tracked file, substitute with `sed` at install time, and `git update-index --assume-unchanged` to hide the local diff. Clean git history, working local paths.

#### Pattern: Notification abstraction
`scripts/notify.sh` wraps `terminal-notifier` (macOS) / `notify-send` (Linux) with a silent no-op fallback. Hooks that call this never fail on machines without notification tools installed.

#### Pattern: Skills as reusable prompts
Each `skills/<name>/SKILL.md` is a structured prompt that Claude invokes when relevant. They encode workflow discipline (debugging protocol, review checklists, TDD gates) so you don't have to repeat yourself. Start with one skill for your most common pain point and grow from there.

#### Pattern: Plugins for team-shared capabilities
`settings.json` `enabledPlugins` + `extraKnownMarketplaces` pre-configures plugins from GitHub-hosted marketplaces. Team members get the same plugin set on clone without manual installation.

### What's Shared vs Personal

| Shared (tracked in git) | Personal (gitignored) |
|---|---|
| `CLAUDE.md` (team base) | `rules/personal.md` (your overrides) |
| `rules/code-style.md`, `vibe-protocol.md` | `memory/journal.md`, `memory/lessons.md` |
| `skills/` (team skill library) | `settings.local.json` |
| `scripts/` (hooks, automation) | `schedules.json` |
| `docs/` (protocol reference) | `skills/pm-*`, `skills/yk-voice.md` |
| `settings.json` (with `__HOME__` placeholders) | |

---

## What's Version-Controlled vs Ephemeral

**Tracked in git** (shared team configuration):
- `CLAUDE.md`, `rules/` (except `personal.md`), `docs/`, `skills/` (except `pm-*`, `yk-voice.md`), `scripts/`
- `settings.json` (with `__HOME__` placeholders, installer substitutes)
- `plugins/blocklist.json`, `plugins/config.json`
- `install.sh`, `tests/`

**Personal** (gitignored, per-user):
- `rules/personal.md` — your name, preferences, behavior overrides
- `memory/journal.md`, `memory/lessons.md` — your session history
- `settings.local.json` — your local permission overrides
- `schedules.json` — your cron tasks

**Ephemeral** (in `.gitignore`, regenerated per session):
- `debug/`, `todos/`, `session-env/`, `file-history/`, `paste-cache/`
- `tasks/`, `history.jsonl`, `cache/`, `telemetry/`
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
