# Od-Claude Deep Synthesis Report v2

> **Date:** 2026-03-21
> **Source:** 12-agent parallel deep analysis of Dónal O'Duffy's od-claude repo vs. Yu-Kuan's ~/.claude/ setup
> **Prior analysis:** See `od-learnings.md` for v1 (2026-03-20)
> **Purpose:** Comprehensive objective comparison, actionable improvements, and tradeoff analysis

---

## Table of Contents

1. [Setup Overview & Scale Comparison](#1-setup-overview--scale-comparison)
2. [Objective Pros & Cons](#2-objective-pros--cons)
3. [Deep-Dive: Key Architecture Patterns](#3-deep-dive-key-architecture-patterns)
4. [What to Adopt (Prioritized Recommendations)](#4-what-to-adopt-prioritized-recommendations)
5. [What to Reconsider (Second Thoughts)](#5-what-to-reconsider-second-thoughts)
6. [What NOT to Adopt](#6-what-not-to-adopt)
7. [Implementation Sketches](#7-implementation-sketches)
8. [Repo Adoption Audit](#8-repo-adoption-audit)
9. [Priority Action Summary](#9-priority-action-summary)
10. [Deep Patterns Missed in v2](#10-deep-patterns-missed-in-v2-added-2026-03-21)
11. [Reference Artifacts](#11-reference-artifacts-extracted-from-od-claude-docs)

---

## 1. Setup Overview & Scale Comparison

### At a Glance

| Dimension | **Yu-Kuan** | **Dónal (od-claude)** |
|-----------|-------------|----------------------|
| **Skills** | 27 custom + 14 superpowers + 7 PM-OS | 17 coordinator skills + 9 commands |
| **Agents/Personas** | garry-review + 8 PR skills + lead-orchestrator | 9 named personas (Patrik, Zolí, Sid, Palí, Fru, Camelia, Enricher, Executor) |
| **Plugins** | 20 installed (5 marketplaces) | 5 composable plugins (coordinator + 3 domain + holodeck-docs); 77 files, 744 KB total |
| **CI/CD** | None for ~/.claude config | 6 blocking checks + weekly health + convention-based discovery |
| **E2E Testing** | Full YAML-based framework with Claude-in-Chrome | None (verification is behavioral only) |
| **PM Automation** | Full PM-OS (7 skills, 26 Node.js scripts, Teams/Outlook/JIRA) | None |
| **Git Workflow** | git-safety-hook.sh (PreToolUse), auto-journal on Stop | Post-commit auto-push, session-start safety commit, branch conventions |
| **Review Architecture** | Skills-based (garry-review + PR toolkit suite) | Named personas with composable routing + sequential review |
| **Task Tracking** | VIBE protocol (TodoWrite + phase gates) | Two-layer (TodoWrite + file plans + write-ahead status + handoffs) |
| **Lessons/Memory** | memory/journal.md (130+ entries, append-only) + docs/ | memory/lessons.md (52 curated entries, periodically trimmed at ~175 lines) |
| **Projects** | 15 repos, 41 project memories tracked | Single meta-repo (control center for all projects) |
| **Model Strategy** | Opus primary for everything | Opus for judgment, Sonnet for execution (explicit tiering) |

### Yu-Kuan's Architecture

```
~/.claude/
├── CLAUDE.md                        # User standards & behavior rules
├── settings.json                    # Permissions, hooks, MCP, plugins
├── schedules.json                   # 4 cron-driven PM-OS automations
├── rules/
│   ├── code-style.md               # Mandatory engineering standards
│   └── vibe-protocol.md            # Full orchestration & QA protocol
├── skills/                          # 20+ custom skills (flat structure)
│   ├── lead-orchestrator/           # Multi-agent task coordination
│   ├── garry-review/                # Code review against preferences
│   ├── prd-writer/                  # Data-driven PRD generation
│   ├── e2e-testing/                 # Full-stack browser testing
│   ├── e2e-qa-runner/               # YAML test execution
│   ├── browser-testing/             # Parallel Chrome automation
│   ├── systematic-debugging/        # Root-cause analysis
│   ├── pm-morning/                  # → symlink to pm_os
│   ├── pm-jira/                     # → symlink to pm_os
│   ├── pm-weekly/                   # → symlink to pm_os
│   └── [+ more PR review & workflow skills]
├── scripts/
│   ├── git-safety-hook.sh           # PreToolUse: blocks unsafe git patterns
│   ├── statusline.sh                # Real-time context bar
│   └── auto-journal.sh             # Append-only session log
├── memory/journal.md                # Searchable session history
└── docs/, plans/, projects/, tasks/
```

### Dónal's Architecture

```
~/.claude/ (od-claude)
├── CLAUDE.md                        # "Constitution" — global principles
├── plugins/oduffy-custom/           # 4 toggleable domain plugins
│   ├── coordinator/                 # Always enabled
│   │   ├── agents/                  # 4 core: Patrik, Zolí, Enricher, Executor
│   │   ├── commands/                # 9 slash commands
│   │   ├── skills/                  # 17 workflow skills
│   │   ├── hooks/hooks.json         # SessionStart, PreToolUse, PostToolUse
│   │   └── routing.md               # Universal reviewer routing table
│   ├── game-dev/                    # Sid + UE MCP (optional)
│   ├── web-dev/                     # Palí + Fru (optional)
│   └── data-science/               # Camelia (optional)
├── docs/                            # Portable replication specs
├── plans/                           # 117 archived plans
├── tasks/                           # 394+ session task directories
│   └── lessons.md                   # 52 global engineering patterns
├── projects/                        # Per-project memory
├── handoffs/                        # Cross-session continuity
└── .github/                         # CI: 9 validation scripts + 2 workflows
```

**Dónal's pipeline:** Brainstorming → Planning → Enrichment → Review → Execution → Code Review → Ship

---

## 2. Objective Pros & Cons

### Where Yu-Kuan's Setup Wins

| Advantage | Detail |
|-----------|--------|
| **PM-OS is unmatched** | 7-skill automation pipeline scanning 139 Teams channels, Outlook, JIRA daily. 10x speedup with Node.js v3 backend. 26 scripts (~10.9K lines), zero npm deps. Saves 2-3 hours/day. Dónal has nothing comparable. |
| **E2E testing framework** | Declarative YAML tests, per-tab browser parallelism via Claude-in-Chrome, full-stack `visual_confirm` pattern catches UI-backend mismatches. Production-grade. Dónal's verification is behavioral only. |
| **Broader skill coverage** | 8 specialized PR review skills (silent-failure-hunter, type-design-analyzer, test-analyzer, etc.) provide more granular code review than Dónal's all-in-one reviewer agents. |
| **VIBE protocol is more prescriptive** | 10 hard gates with explicit phase enforcement (`.claude/phase.json`). Phase gate + role detection from git branch is more structured than Dónal's behavioral approach. |
| **Real-world integration depth** | Atlassian MCP, Claude-in-Chrome MCP, Glean MCP, agent-browser — integrated with production workplace tools. Dónal's integrations are Context7 + holodeck-docs (documentation-only). |
| **PRD writing skill** | `prd-writer` with data-driven rigor (hypotheses, KPI tables, prior art analysis) is a strong product skill Dónal lacks. |
| **Auto-journaling** | Stop hook auto-appends session summary to `memory/journal.md`. Captures context without effort. Dónal's handoffs require manual invocation. |
| **Codebase mapping** | `codebase-mapping` skill produces architecture docs with feature-to-code mapping. Dónal's `generate-repomap.py` is lighter-weight (structural only, no feature mapping). |
| **Status line** | Real-time: model, session ID, context %, git status, AWS creds, disk. Situational awareness Dónal lacks. |
| **Git safety hooks** | PreToolUse blocks `git add -A`, `--no-verify`, `--force`, `reset --hard`. Proactive enforcement. Dónal relies on CLAUDE.md instructions (hooks > instructions). |
| **Scheduling** | `schedules.json` with 4 cron-driven automated tasks. Autonomous PM work without manual invocation. |

### Where Dónal's Setup Wins

| Advantage | Detail |
|-----------|--------|
| **Named reviewer personas** | 8 distinct characters with written mandates, domain expertise, model assignments, and backstop relationships. Produces more consistent, deeper, reproducible reviews than generic skill-based review. "Patrik" drifts less than "review this." |
| **Sequential review with fix-between** | Hard rule: fix ALL findings from Reviewer 1 before dispatching Reviewer 2. Compounds insights. Each reviewer sees clean work, not known-issues. |
| **Enrichment-before-execution pipeline** | Sonnet enricher fills plan stubs with actual file paths, function signatures, code patterns BEFORE executor touches code. Cheap (~2 min). Prevents "wrong file" class of errors. |
| **Model tiering (Opus/Sonnet)** | Explicit strategy: Opus for judgment (reviewers), Sonnet for execution (enricher, executor). Right model for right task. Lower cost without sacrificing quality where it matters. |
| **CI/CD validation pipeline** | 9 stdlib-only scripts (secrets, file sizes, gitignore policy, frontmatter, references, JSON schemas). Convention-based discovery: add `validate-*.py` → runs automatically. |
| **Write-ahead status protocol** | Two-layer breadcrumb (tracker + document header) updated BEFORE work starts. Crash recovery is unambiguous — no expensive triage. |
| **Composable plugin routing** | Domain plugins contribute routing fragments merged at dispatch time. Adding game-dev/web-dev/data-science doesn't touch coordinator code. |
| **Handoff system** | Structured cross-session state capture with anti-amnesia chaining (each handoff reads prior). Provides resumption narrative, not just facts. |
| **Repomap generator** | Git-activity-ranked structural summary (recency 50% + frequency 35% + size-inverse 15%) for LLM cold-start context. 630-line stdlib-only script. |
| **Gitignore policy enforcement** | Philosophy: "tracked too much > silently lost." CI-enforced ban on deny-all patterns. Prevents worst git disaster class. |
| **Documentation as portable specs** | Every infrastructure component documented as both reference AND replication guide. Designed for adoption across repos. |
| **Lessons curation discipline** | 19 entries, periodically trimmed when >50, max 3 lines each. Bold title + 1-2 sentence rule. Entry bar: "Will this save time in the next 4 weeks?" vs. journal's 130+ append-only entries. |
| **Ambition backstop (Zolí)** | Unique role — never primary reviewer, only invoked to challenge conservative recommendations. Nobody in our setup asks "should we be more ambitious?" |

### Where Both Are Strong (Parallel Approaches)

| Area | Yu-Kuan | Dónal |
|------|---------|-------|
| **TDD mandate** | VIBE gate #3 | Skill + code-style rule |
| **No mocks on internals** | VIBE gate #10 (SavepointConnection) | Real Testing Mandate |
| **Orchestrator isolation** | lead-orchestrator skill ("never codes") | Same principle, plugin architecture |
| **Zero assumption policy** | VIBE gate #1 | First Officer Doctrine (escalation) |
| **Push-back culture** | "MUST push back on bad ideas" | "Silent compliance = failure of the role" |
| **Crash-safe commit hygiene** | Git safety hooks (preventive) | Auto-push + safety commits (recovery) |

---

## 3. Deep-Dive: Key Architecture Patterns

### 3.1 Named Reviewer Personas (Dónal)

Dónal's 9 agents have written mandates, domain lenses, and explicit backstop relationships:

| Agent | Model | Domain | Role | Key Trait |
|-------|-------|--------|------|-----------|
| **Patrik** | Opus | Architecture, code quality, security | Primary reviewer for all code | "Standards should be HIGHER given AI handles overhead." |
| **Zolí** | Opus | Ambition advocacy | Backstop only — challenges conservatism | "Should we refactor instead of patching?" |
| **Sid** | Opus | Unreal Engine, gameplay, systems design | Game dev specialist | Researches UE docs rather than guessing. Has `sid-knowledge.md` war-stories KB. |
| **Palí** | Opus | Front-end, CSS, design tokens, components | Design system adherence | Pragmatic — "close enough" often correct. |
| **Fru** | Sonnet | UX flow, trust signals, clarity | User-facing review | "Does this make sense to a human?" |
| **Camelia** | Opus | ML/AI, statistics, data modeling | Quantitative lens | Complements Patrik's engineering lens. |
| **Enricher** | Sonnet | Research, codebase survey | Gathers facts without decisions | Fills plan stubs with real file paths, patterns, deps. |
| **Executor** | Sonnet | Implementation | "The typist, not the architect." | Follows specs faithfully, validates, escalates if ambiguous. |

**Review routing algorithm:**
```
1. Read universal routing (coordinator/routing.md)
2. Scan enabled plugins for routing.md fragments
3. Merge into composite routing table
4. Match code signals:
   - Frontend (.tsx, .css, components/) → Palí → Fru → Patrik
   - Game logic (.cpp, Blueprints/) → Sid → Patrik
   - ML/data (.py, models/, notebooks/) → Camelia → Patrik
   - Architecture, cross-cutting → Patrik
5. High-effort tasks → mandatory Zolí backstop after primary review
```

**Structured output schemas:** Each reviewer produces JSON with verdict type (REJECTED, REQUIRES_CHANGES, APPROVED_WITH_NOTES, APPROVED), findings array with severity, and human-readable summary. Not free-form text.

### 3.2 Enrichment Pipeline (Dónal)

**Three sub-phases:**

1. **Phase 0 — Repo Map:** Generate/read git-activity-ranked structural overview (~2 sec)
2. **Phase 1 — Survey:** For each plan stub, verify actual file paths, surrounding code patterns, imports/dependencies, test file locations, asset dependencies
3. **Phase 2 — Annotate:** Write findings back into the plan document with verified paths, pattern notes, dependency graph, ambiguity flags

**Key constraint:** Enricher NEVER makes architectural decisions. It flags: "I found 3 patterns for this — coordinator should decide which to follow."

**Why it matters:** Most executor failures come from underspecified plans. Enrichment catches wrong assumptions before code is written. ~2 min with Sonnet; rework it prevents is 10-30 min.

### 3.3 Write-Ahead Status Protocol (Dónal)

Treats agent orchestration like a database transaction:

```
1. Coordinator marks tracker: "dispatching T-001 to executor"
2. Coordinator commits tracker
3. Executor marks document header: "Execution in progress"
4. Executor does work
5. Executor marks document header: "Execution complete"
6. Coordinator verifies, marks tracker: "T-001 complete"
```

**Crash interpretation (unambiguous):**
- Tracker "in progress" + Document "pending" → agent crashed on init
- Both "in progress" → agent mid-work
- Document "complete" + Tracker "in progress" → agent finished, coordinator crashed

**State machine:**
```
Pending → In Progress → Complete
                ↓
          Blocked — [reason]
```

### 3.4 PM-OS Architecture (Yu-Kuan — Unique Advantage)

**Dual implementation pattern:**

| Pattern | Used For | Approach | Performance |
|---------|----------|----------|-------------|
| **Pure LLM** | pm-login, pm-jira, pm-pulse, pm-send | Claude reads skill, orchestrates 14+ steps via tool calls | Flexible but slow |
| **Hybrid Node.js + LLM** | pm-morning, pm-weekly | Node.js deterministic pipeline, LLM for semantic tasks only | 6-10x speedup |

**Parallel scanning architecture (pm-morning v3):**
```
Orchestrator (main session)
├── Partition 48 tier-1 channels → 4 interleaved workers
├── Spawn workers 0-3 with cloned auth state
├── Workers scan 12 channels each in parallel → disk output
├── Orchestrator collects from disk (no context penalty)
├── Merge + deduplicate + classify + prioritize
└── Draft responses (40-50K tokens total, safe margin)
```

**Performance baselines:**

| Workflow | LLM-only | Node.js v3 | Speedup |
|----------|----------|------------|---------|
| Morning scan (48 channels) | ~33 min | ~5 min | **6.6x** |
| Classification (150 items) | ~18 min | ~2 min | **9x** |
| Weekly evidence (7-day) | ~20-25 min | ~2-3 min | **10x** |

### 3.5 E2E Testing Framework (Yu-Kuan — Unique Advantage)

- **YAML-based declarative test cases** conforming to `test-case.schema.yaml`
- **13 step types** including `visual_confirm` (mandatory for full-stack tests)
- **Per-tab browser isolation** — each subagent gets its own Chrome tab via `tabId`
- **QA runner produces structured artifacts** with visual evidence (screenshots)
- **8 documented common mistakes** from real failure modes

### 3.6 Convention-Based CI Discovery (Dónal)

```python
# run-all-checks.py discovers scripts automatically
for script in sorted(scripts_dir.glob("validate-*.py")):
    run(script)
for script in sorted(scripts_dir.glob("check-*.py")):
    run(script)
```

**Available checks (all stdlib-only, no Docker/external deps):**
- `check-secrets.py` — API keys, AWS creds, GitHub tokens
- `check-file-sizes.py` — prevents files >1MB
- `validate-gitignore.py` — bans deny-all patterns
- `validate-frontmatter.py` — skill/agent YAML header compliance
- `validate-references.py` — catches broken cross-references
- `validate-json-schemas.py` — config file schema validation
- `health-check.py` — weekly scheduled full health scan
- `generate-repomap.py` — git-activity-ranked structural summary (630 lines)

### 3.7 Lessons Curation vs. Append-Only Journal

| Dimension | Dónal (lessons.md) | Yu-Kuan (journal.md) |
|-----------|-------------------|---------------------|
| **Entries** | 52 curated (was 19, grown organically) | 130+ append-only |
| **Format** | Bold title + 1-2 sentence rule, max 3 lines | Session summaries (files, tools, errors) |
| **Curation** | Trimmed when >50 entries or ~175 lines | Never trimmed |
| **Entry bar** | "Will this save time in 4 weeks?" | Automatic (everything captured) |
| **Session-start value** | High (distilled, actionable) | Medium (raw, needs scanning) |
| **Forensic value** | Low (too distilled for debugging) | High (full session records) |

**Key insight:** Both serve different purposes. The ideal is Dónal's curated lessons (for session-start context) + Yu-Kuan's journal (for forensic investigation). They're complementary, not competing.

---

## 4. What to Adopt (Prioritized Recommendations)

### P0 — High Impact, Low Effort

#### A. Curate journal.md → lessons.md

**What:** Extract high-signal patterns from 130+ journal entries into a curated `~/.claude/memory/lessons.md` (max 50 entries, max 3 lines each).

**Why:** Agents reading 19 curated lessons at session start is far more useful than skimming 130+ raw entries.

**Format (from Dónal):**
```markdown
- **Bold title** — 1-2 sentence actionable rule. Max 3 lines.
```

**Keep journal.md as raw log** — it's the forensic record. Lessons.md is the distilled wisdom.

#### B. Add Post-Commit Auto-Push Hook

**What:** 8 lines of bash that auto-push work/* and feature/* branches after every commit.

**Why:** Crash insurance. If agent dies mid-work, latest commit is on remote.

```bash
#!/bin/sh
branch=$(git symbolic-ref --short HEAD 2>/dev/null)
case "$branch" in
  work/*|feature/*|feat/*)
    git push origin "$branch" 2>/dev/null &
    ;;
esac
```

**Tradeoff:** Near-zero. Silent background push on branch only.

#### C. Write-Ahead Status Protocol

**What:** Before starting any phase, mark status in both tracker and document header.

**How:** Add `**Status:** [state] (started [timestamp])` to all plan/task document headers. Update lead-orchestrator to set status before dispatch and after verification.

#### D. Copy Repomap Generator

**What:** Dónal's `generate-repomap.py` (630 lines, stdlib-only). Git-activity-ranked structural summary for LLM cold-start context.

**Why:** Eliminates 30-60s of blind Glob/Grep exploration per agent dispatch.

**Scoring weights:** recency 50% + commit frequency 35% + size-inverse 15%.

### P1 — High Impact, Medium Effort

#### E. Named Reviewer Personas (Start with 3)

Replace generic `garry-review` with 3 named reviewers:

| Name | Domain | Perspective | When to Route |
|------|--------|-------------|---------------|
| **Architecture Reviewer** | Code quality, architecture, security, docs | Exacting senior engineer | All PRs, all refactors |
| **Domain Specialist** | Rotates per project (web/data/PM) | Domain expert lens | Feature work in their domain |
| **Ambition Backstop** | Challenges conservatism | "Should we refactor instead of patching?" | High-effort tasks, arch decisions |

**Persona template (from Dónal):**
```markdown
# [Name] — [Domain] Reviewer

## Model
[opus/sonnet]

## Domain
[Specialization]

## Perspective
[1-2 sentences: worldview and standards]

## Review Process
1. Structure & architecture
2. Implementation correctness
3. Documentation & naming
4. Edge cases & error handling

## Verdict Types
- REJECTED — Fundamental issues
- REQUIRES_CHANGES — Specific fixes needed
- APPROVED_WITH_NOTES — Minor, can merge
- APPROVED — Ship it

## Output Format
[JSON structure + human summary]
```

**Tradeoff:** 2-3 hours to design and test. Risk of persona bloat if you add too many. Start with 3, add only when you feel a gap.

#### F. Enrichment Phase Before Execution

**What:** Sonnet-powered research step between planning and execution. Enricher surveys codebase, fills plan stubs with concrete file paths, existing patterns, dependency info.

**When to trigger:** Only for tasks touching 3+ files.

**Implementation sketch:**
```markdown
# Enricher Skill

## Trigger
Invoked by lead-orchestrator when plan references 3+ files or has uncertain paths.

## Process
1. Read plan stub
2. Survey codebase: verify file paths, find existing patterns, trace imports, locate tests
3. Annotate plan with findings
4. Flag ambiguities for coordinator decision

## Model
Sonnet (fast, cheap — judgment already happened in planning)

## Tools
Read, Glob, Grep, Bash (exploration only). NO Edit/Write.

## Output
Annotated plan with: ✅ Verified paths, 📋 Existing patterns, ⚠️ Ambiguities, 📦 Dependencies
```

**Effort:** 3-4 hours. **Saves:** 10-30 min per execution cycle by preventing wrong-file errors.

#### G. Sequential Review Protocol

**What:** When routing through 2+ reviewers, fix ALL findings from Reviewer 1 before dispatching Reviewer 2.

**Dónal's rule:** "Multi-persona reviews are always sequential, never parallel. Each reviewer sees a clean, corrected artifact."

**When:** PRDs, architecture decisions, major refactors. Skip for routine bug fixes.

#### H. Review Routing Layer

**What:** Auto-select which of your 8 PR skills to invoke based on change signals.

```
Frontend files (.tsx, .css) → pr-code-reviewer + pr-type-design-analyzer
Test changes → pr-test-analyzer
Error handling → pr-silent-failure-hunter
Complex PRs → pr-briefing → parallel review dispatch
```

**Why:** Removes the burden of remembering which 3 of 8 skills to invoke per review.

#### I. Tier VIBE Protocol Per-Repo

**What:** Add `"vibe_level": "full" | "light"` to `phase.json`.

| Level | Gates Applied |
|-------|---------------|
| **Full** | All 10 hard gates, 2 QA cycles, spec wall, API contracts |
| **Light** | TDD + review required, no spec wall, no 2 QA cycles |

**Why:** Aspirational rules that aren't enforced erode trust in ALL rules. Currently only deck_benchmarks demonstrates full VIBE compliance.

### P2 — Medium Impact, Lower Priority

#### J. Cherry-Pick CI Scripts

Copy Dónal's portable validation scripts:
- `check-secrets.py` — scans for leaked keys (copy as-is)
- `check-file-sizes.py` — prevents >1MB files (copy as-is)
- `run-all-checks.py` — convention-based runner

#### K. Model Tiering Strategy

**What:** Dispatch coder subagents with `model: "sonnet"` when plan stubs are well-enriched. Reserve Opus for reviewers and orchestration.

**Tradeoff:** Lower cost per execution cycle. Risk: Sonnet may miss nuance on complex tasks. Mitigation: if executor reports BLOCKED, escalate to Opus.

#### L. Repo Bootstrap Template

Checklist for bootstrapping new repos:

```markdown
# New Repo Bootstrap

## Required
- [ ] `.claude/phase.json` — set to DISCOVERY
- [ ] `.claude/settings.json` — from template
- [ ] `CLAUDE.md` — project-specific context
- [ ] `memory/lessons.md` — empty
- [ ] `qa/` — empty

## Optional (per project type)
- [ ] `.claude/settings.local.json` — project MCP/plugins
- [ ] `docs/contracts/` — API contracts
- [ ] `docs/prd/features/` — feature specs
```

---

## 5. What to Reconsider (Second Thoughts)

### In Our Setup

#### A. VIBE Protocol Adoption Gap

10 hard gates defined, but actual enforcement:

| Repo | Phase Gate | Spec Wall | TDD | 2 QA Cycles | Contract-First |
|------|-----------|-----------|-----|-------------|----------------|
| deck_benchmarks | ✅ | ✅ | ✅ | ✅ | ✅ |
| pm_os | ✅ | ❌ | ❌ | ❌ | N/A |
| boardroom-ai | ❌ | ❌ | Partial | ❌ | ❌ |
| nextgen | ✅ | ❌ | ❌ | ❌ | ❌ |
| portco_insights | ✅ (frozen) | ❌ | ❌ | ❌ | ❌ |
| maple-web | ❌ | ❌ | ❌ | ❌ | ❌ |

**Options:**
1. **Enforce everywhere** — Maximum quality, maximum ceremony. Overkill for pm_os/tooling.
2. **Tier per repo** (recommended) — "full VIBE" for production, "light VIBE" for tooling/exploratory.
3. **Status quo** — Aspirational rules not enforced erode trust in ALL rules.

#### B. 130+ Entry Append-Only Journal

Signal-to-noise degrades over time.

**Options:**
1. **Curate into lessons.md** (recommended) — Keep journal as raw log
2. **Rotate monthly** — Archive old entries, keep last 30 days
3. **Keep as-is** — If not hitting context issues

#### C. 8 Separate PR Review Skills

pr-code-reviewer, pr-code-simplifier, pr-comment-analyzer, pr-review-pr, pr-silent-failure-hunter, pr-test-analyzer, pr-type-design-analyzer, pr-briefing. 8 skills for one activity.

**Options:**
1. **Consolidate into named personas** — Each persona invokes relevant skills internally
2. **Keep granular** — If you frequently use individual skills in isolation
3. **Create review routing layer** (recommended) — Auto-selects which skills to invoke based on change signals

#### D. Skills Defined But Not Invoked

boardroom-ai has garry-review and vibe-lookup skills with no activation evidence. Dead skills erode trust in the system.

**Action:** Wire into lead-orchestrator's QA cycle or delete.

#### E. 22 Worktrees in pm_os Without State Machine

Heavy parallel orchestration with no central tracking. Abandoned worktrees leave no record.

**Action:** Add `orchestrator-state.json` for central visibility.

#### F. Cross-Repo Lessons Gap

- deck_benchmarks: has `learning.md` (3.8K) — project-specific
- pm_os: TOKEN-7 incident but no lessons.md
- No shared lessons repository across projects

**Action:** Establish `~/.claude/memory/lessons.md` as cross-repo store. Project-specific lessons in `tasks/<project>/lessons.md`.

### In Dónal's Setup (What NOT to Adopt Blindly)

#### G. The Full 8-Stage Pipeline is Heavy

Brainstorm → Write Plan → Enrich → Review Enrichment → Execute → Spec Compliance → Code Quality → Ambition Backstop → Ship.

**Second thought:** For PM + AI moving fast, 8 gates may be overkill for most tasks. Adopt enrichment phase and sequential review, but don't restructure the whole pipeline.

#### H. Named Personas Can Be Cargo-Cult

Patrik and Zolí work because Dónal invested in deep mandates. Simply naming an agent "Reviewer Bob" without written mandate and explicit standards doesn't produce better reviews.

**Second thought:** If you adopt personas, invest the time to write real mandates (100+ lines each). Half-hearted personas are worse than good generic skills.

#### I. Synchronous Auto-Push May Not Scale

Dónal's post-commit hook pushes synchronously. For small repos fine; for large repos adds latency.

**Second thought:** Use async push (`&` in background) for larger repos.

#### J. Gitignore Policy Enforcement Conflict

Dónal's "deny-all forbidden" may conflict with existing .gitignore patterns.

**Second thought:** Audit existing .gitignore files before adopting. Some repos may have legitimate deny-all patterns for generated code.

---

## 6. What NOT to Adopt

| Item | Why Not |
|------|---------|
| **Full 7-stage pipeline** | Our 4-stage (spec → TDD → QA C1 → QA C2) is already rigorous. Adopt enrichment as add-on, don't restructure. |
| **8 named personas** | Persona proliferation. Diminishing returns past 3-4. Start with 3. |
| **Auto-push on every commit** | Our git-safety-hook blocks unsafe patterns. Auto-push is recovery-oriented (Dónal's approach); we're prevention-oriented. Keep our hooks. |
| **Advisory-only CI** | Dónal's status checks don't block merge. Our VIBE hard gates are stricter. Keep blocking gates. |
| **Plugin architecture (not yet)** | Reorganizing ~30 skills into toggleable domain groups requires significant refactoring. Our flat structure works. Revisit if skills double or context pollution becomes real. |
| **Handoff system** | Our auto-journal + file-based plans serve this purpose. Journal is actually better for forensics (searchable, append-only). |

---

## 7. Implementation Sketches

### 7.1 Enricher Skill (Full Spec)

```markdown
# Enricher

## Trigger
Invoked by lead-orchestrator when:
- Plan references 3+ files
- Plan has uncertain file paths
- Complex dependency graph

## Model
Sonnet (fast, cheap)

## Process
### Phase 0 — Repo Map
Generate or read structural overview. Key files ranked by importance.

### Phase 1 — Survey
For each plan stub:
- Do referenced files exist? (Glob)
- What patterns does surrounding code follow? (Read)
- What are imports/dependencies? (Grep)
- Where are test files? (Glob)
- Asset dependencies? (Read)

### Phase 2 — Annotate
Write back into plan document:
- ✅ Verified file paths (or corrections)
- 📋 Pattern notes ("module uses factory pattern, follow it")
- 📦 Dependency graph
- 🧪 Test file locations
- ⚠️ Ambiguity flags for coordinator

## Constraint
NEVER make architectural decisions. Flag them.

## Tools Allowed
Read, Glob, Grep, Bash (exploration only). NO Edit/Write on implementation files.
```

### 7.2 Review Routing Table

```markdown
# Review Routing

## Signal Matching
| File Pattern | Primary Reviewer | Secondary | Backstop |
|-------------|-----------------|-----------|----------|
| *.tsx, *.css, components/ | pr-code-reviewer + pr-type-design-analyzer | pr-comment-analyzer | — |
| *test*, *spec* | pr-test-analyzer | pr-code-reviewer | — |
| catch, try, error, fallback | pr-silent-failure-hunter | pr-code-reviewer | — |
| 10+ files changed | pr-briefing → parallel dispatch | — | — |
| Architecture/refactor | Full suite | — | Ambition backstop |

## Sequential Dispatch Rule
Fix ALL findings from Reviewer 1 before dispatching Reviewer 2.
```

### 7.3 Repomap Scoring Algorithm

Dónal's `generate-repomap.py` ranks files by:

```
score = (recency_weight × 0.50) + (frequency_weight × 0.35) + (size_inverse × 0.15)

Where:
- recency = days since last commit (exponential decay)
- frequency = number of commits touching this file
- size_inverse = 1 / file_size (smaller files rank higher — they're usually more important)
```

Files are then grouped by directory and presented as a structural tree with importance annotations.

### 7.4 Lessons.md Format Spec

```markdown
# Lessons

<!-- Max 50 entries. Trim when exceeded. Entry bar: "Will this save time in 4 weeks?" -->
<!-- Bold title + 1-2 sentence rule. Max 3 lines per entry. -->
<!-- Merge with existing entries if related. -->

- **Title** — Actionable rule in 1-2 sentences.
- **Title** — Rule. Additional context if needed.
```

---

## 8. Repo Adoption Audit

| Repo | Type | Phase | VIBE Depth | QA Artifacts | Verdict |
|------|------|-------|------------|--------------|---------|
| **deck_benchmarks** | Python + React | BUILD | Deep (9 configs) | 76+ FEAT/BUG dirs, 2 QA cycles | Reference implementation |
| **pm_os** | Node.js tooling | BUILD | Medium (2 files) | 1 feature dir, 22 worktrees | Heavy orchestration, light QA |
| **boardroom-ai** | React + FastAPI | No phase.json | Medium (3 files + skills) | Sparse (1 BUG dir) | Good config, light execution |
| **nextgen** | Angular + .NET | BUILD | Minimal (1 file) | 1 BUG dir | Early setup |
| **portco_insights** | Unknown | BUILD (frozen) | Minimal (2 files) | Empty /qa | Dormant |
| **maple-web** | C#/.NET | No phase.json | Minimal (2 files) | No /qa | Claude as editor only |
| **PM** | Unknown | N/A | None | None | Not integrated |

**Key takeaway:** Only deck_benchmarks demonstrates full VIBE compliance. The gap between infrastructure sophistication and actual adoption is the biggest risk.

---

## 9. Priority Action Summary

| Priority | Action | Source | Effort | Impact |
|----------|--------|--------|--------|--------|
| **P0** | Curate journal.md → lessons.md | Dónal pattern | Low (1-2h) | High |
| **P0** | Add post-commit auto-push hook | Dónal | Low (30min) | Medium |
| **P0** | Add write-ahead status protocol | Dónal | Low (1-2h) | High |
| **P0** | Copy repomap generator | Dónal | Low (30min) | Medium |
| **P1** | Build 3 named reviewer personas | Dónal | Medium (2-3h) | High |
| **P1** | Add enrichment phase for 3+ file tasks | Dónal | Medium (3-4h) | High |
| **P1** | Create review routing layer | Audit finding | Medium (2h) | High |
| **P1** | Tier VIBE protocol per-repo | Audit finding | Low (1h) | High |
| **P1** | Wire or delete dormant skills | Audit finding | Low (1h) | Medium |
| **P1** | Establish cross-repo lessons.md | Dónal pattern | Low (1h) | Medium |
| **P2** | Cherry-pick CI scripts (secrets, file sizes) | Dónal | Low (1h) | Medium |
| **P2** | Sequential review for high-stakes work | Dónal | Low (convention) | Medium |
| **P2** | Model tiering (Sonnet for executors) | Dónal | Low (config) | Medium |
| **P2** | Create repo bootstrap template | Dónal | Low (1-2h) | Medium |
| **P2** | Add orchestrator-state.json to pm_os | Dónal pattern | Low (30min) | Low |
| **Keep** | Git safety hooks (superior to od-claude) | Ours | — | — |
| **Keep** | PM-OS automation (unique advantage) | Ours | — | — |
| **Keep** | Browser testing infra (od-claude lacks) | Ours | — | — |
| **Keep** | Status line + auto-journal | Ours | — | — |
| **Keep** | VIBE hard gates (stricter than advisory CI) | Ours | — | — |
| **Keep** | E2E YAML testing framework | Ours | — | — |

---

## 10. Deep Patterns Missed in v2 (Added 2026-03-21)

> Added after 4-agent parallel deep study of plugins/, repomap, CI scripts, commands, skills, and research/ directory. These patterns were not captured in the original 12-agent analysis.

### 10.1 Holodeck-Docs: The Missing 5th Plugin

The original analysis counted 4 plugins. There are actually **5** — `holodeck-docs` is a separate plugin wrapping UE documentation retrieval and Python execution MCP servers.

**Components:**
- 2 agents: `ue-docs-researcher` (Sonnet, fast doc retrieval), `ue-python-executor` (Sonnet, sandboxed Python)
- 2 commands: `/lookup` (documentation), `/run-python` (execution)
- 2 skills: `ue-docs-lookup`, `python-execution-routing`
- CLAUDE.md with 8-tier retrieval hierarchy (quick_ue_lookup → ue_expert_examples → check_ue_patterns → Context7 → lookup_ue_class → search_ue_docs → ask_unreal_expert → get_session_primer)

**Key design choice — context isolation:** Multi-step doc lookups dispatched to `ue-docs-researcher` agent (Sonnet) to protect coordinator context. Single focused lookups call MCP tool directly. Same pattern for Python execution — complex scripts via agent, simple via direct tool call.

**Data quality gate:** AI-generated RAG content has ~1-in-4 error rate vs ~0 for human blogs. Requires Sid MCP review before AI content enters RAG. This is a concrete example of "verify external data sources" that we could learn from.

### 10.2 Aider vs Repomap: Detailed Prior Art Analysis

The `research/` directory contains two detailed comparison documents (303 + 184 lines) not referenced in v2. Key divergences:

| Aspect | Aider | Dónal's Repomap |
|--------|-------|-----------------|
| **Ranking signal** | PageRank on dependency graph (architectural centrality) | Git activity (operational relevance) |
| **Parser** | tree-sitter with 50+ language grammars | `ast.parse` (Python), regex (Markdown/Shell/JSON) — 4 types only |
| **Cross-file refs** | Yes — enables PageRank and edge weighting | No — Phase 3 future work |
| **Dependencies** | networkx, tree-sitter, pygments, diskcache (~200MB) | stdlib only (zero deps) |
| **Cache backend** | SQLite via diskcache | JSON file, keyed by `path:sha256(content)` |
| **Budget default** | 1,024 tokens (scales 8× when no chat files) | 4,000 tokens fixed |
| **Conversation awareness** | Deep (×50 chat-file boost, ×10 identifier boost) | None — session-based agents |

**Assessment from their docs:** Git-activity ranking works well for Markdown/Python-heavy repos with active development. It erodes for: (1) large codebases with stable foundational code (recency buries important ancient files), (2) non-Python/Markdown languages (empty entries for C++, TypeScript, Go, Rust). Phase 3 plan: tree-sitter + reference graph for code-heavy projects.

**Adoption note for us:** If we copy repomap, we should be aware that its ranking is session-operational ("what's been worked on lately") not architectural ("what's structurally important"). For our repos with mixed languages, the 4-parser limitation matters. Consider tree-sitter if deploying to boardroom-ai (React/TypeScript).

### 10.3 Repomap Algorithm Precision (Beyond the Summary)

v2 documented the scoring weights. The deep study reveals critical implementation details:

- **Exponential decay half-life:** ~14 days (`exp(-0.05 × days)`). Files not touched in 28 days score ~25% of today's edits.
- **Frequency normalization:** `min(log1p(commits_90d) / log1p(50), 1.0)` — log-scaled, caps at 50 commits in 90 days.
- **Budget fitting:** Iterative greedy (not binary search). Allows **30% overshoot** on last entry. Token estimate: `word_count × 1.3` (known to underestimate).
- **Cache key:** `filepath:sha256(file_content)` — content-addressed, not mtime. More correct: file checkout/copy changes mtime without changing content.
- **Atomic writes:** `tempfile.mkstemp()` + `os.replace()` prevents partial writes on crash. Both for output and cache.
- **Important files front-injection:** ~20 patterns including CLAUDE.md, ARCHITECTURE.md, README*, pyproject.toml, Dockerfile, .github/workflows (prefix match). Injected before score-ranked files.
- **Non-git fallback:** `git ls-files` failure → filesystem walk. `git log` failure → filesystem mtime ranking. Script completes successfully with degraded quality.
- **Edge cases:** Empty repos (warning, early return), binary files (UTF-8 decode test on first 8KB), symlinks (path only, 0 lines), >10K line files (path only, no parse), syntax errors (logged, skipped, script continues).

### 10.4 Executor Verdict System: Self-Doubt as Status

v2 mentioned executor model tiering but missed the **verdict system** — a sophisticated status reporting protocol:

| Verdict | Meaning | Coordinator Action |
|---------|---------|-------------------|
| **DONE** | Clean completion, all exit criteria met | Route to review |
| **DONE_WITH_CONCERNS** | Completed but has explicit doubts | Route to review with concerns highlighted |
| **BLOCKED** | Cannot proceed — structural issue | Diagnose: spec problem vs execution problem |
| **NEEDS_CONTEXT** | Missing information from codebase | May re-dispatch with additional context |

**Key insight:** "Self-doubt is a reportable status, not a failure." DONE_WITH_CONCERNS lets executors flag uncertainty without blocking. The coordinator then decides whether concerns are real. This is more nuanced than pass/fail and prevents both false confidence and unnecessary escalation.

**Structured escalation format:** When BLOCKED, executor reports: type (fixable vs structural), what was attempted, blocker description, what stub needs to change, suggested resolution, files touched with status.

### 10.5 Flag vs Decide: The Enricher's Boundary Protocol

The enricher has a **crisp rubric** separating what it can decide autonomously from what requires coordinator judgment:

**Enricher DECIDES (factual/technical):**
- Which file contains specific code
- What assets exist on disk
- Dependency chains and import graphs
- Line numbers and current function behavior
- Caller tracing

**Enricher FLAGS (architectural/judgment):**
- Naming public APIs
- Creating new abstractions
- Choosing design patterns
- Scope questions
- Third-party library fit
- Breaking changes

**Why this matters for us:** Our `lead-orchestrator` doesn't have this distinction. Subagents either do everything (executor) or nothing (reviewer). An enricher with a clear "research vs judgment" boundary would reduce unnecessary escalation while preventing autonomous architectural decisions.

### 10.6 Opus Tech Lead Pattern for Large Stubs

When a stub is too large for a single Sonnet executor context:

1. Dispatch **Opus agent as tech lead** (NOT from coordinator — protects coordinator context)
2. Tech lead decomposes stub into natural seams
3. Dispatches Sonnet executors sequentially, verifying each output
4. Makes micro-decisions within spec's intent without escalating
5. Reports single completion report to coordinator (not per-sub-task stream)

**Key constraint:** This is explicitly NOT the coordinator doing the work. The coordinator dispatches the Opus tech lead as a separate agent, preserving its own context for orchestration. This is the only exception to the "always Sonnet for executor" rule.

### 10.7 Review Pipeline Gates Not Previously Captured

Three distinct pipeline gates that compound to prevent wasted work:

**A. Plan Review Gate (before enrichment):**
Before enriching ANY stubs, verify the source plan was reviewed. If not reviewed: HALT and require `/review-dispatch` or PM override. Prevents wasting enrichment cycles on structurally broken plans.

**B. Fix-Application Gate (between reviewers):**
"STOP. Apply ALL Reviewer 1 feedback into stubs before proceeding. Every P0, P1, P2, and nit — nothing deferred, nothing 'noted.'" This is harsher than v2 captured. Reviews are work orders, not suggestions.

**C. Spec Compliance Verification (after execution):**
Distinct from validation (tests pass). Three questions:
- Did executor implement everything spec specifies? (completeness)
- Did executor build anything spec does NOT specify? (scope creep)
- Does implementation match spec's intent, not just letter? (spirit)

An executor can pass validation but fail spec compliance — built the wrong thing correctly.

### 10.8 Project-Local Persona Loading

Agents can load **project-specific persona files** without code duplication:
- Palí loads `docs/personae/pali/README.md` (Figma-specific review, Tailwind tables, design logs, token inventory)
- Fru loads `docs/personae/fru/README.md` (audience profiles, design constraints, domain terminology)

**Pattern:** Same agent prompt, different project context via data file. This avoids forking agent definitions per project. The persona is a configuration, not code.

**Adoption value:** If we build named reviewers, making them project-configurable via data files in the project repo (not changes to the skill/agent definition) is the right architecture.

### 10.9 MCP Tool Lazy-Loading with Dual Name Variants

All agents using MCP tools follow a defensive loading pattern:

1. **Bootstrap via ToolSearch** before first use — schemas aren't in context by default
2. **List BOTH hyphenated AND underscored variants** in agent prompts (e.g., `mcp__holodeck-docs__quick_ue_lookup` AND `mcp__holodeck_docs__quick_ue_lookup`) because tool name normalization is inconsistent
3. **Graceful degradation** if MCP unavailable — fall back to manual API calls, Grep, or Context7

**Why this matters for us:** We have Atlassian MCP and Claude-in-Chrome MCP. If agents don't bootstrap ToolSearch first, MCP calls silently fail. The dual-variant pattern prevents a class of "tool not found" errors we may be hitting.

### 10.10 Self-Correction Loop Discipline

When executor output fails validation:

| Failure Type | Action | Max Attempts |
|-------------|--------|--------------|
| **Deterministic** (test failures, type errors, lint) | Re-dispatch executor | 2 iterations |
| **Structural** (spec ambiguity, missing dependency) | Escalate to coordinator immediately | 0 (no retry) |

After 2 failed re-dispatches → escalate. The assumption: 2 failures on the same deterministic issue indicate a spec problem, not an execution problem. More retries waste tokens on a broken spec.

### 10.11 Palí's "Close Enough" Decision Framework

Operationalizes pragmatism with explicit rules (not subjective judgment):

| Situation | Decision |
|-----------|----------|
| Token exists | Use it |
| Within 10% of existing token | Use existing + flag in review |
| New token needed, used 3+ places | Create new token |
| One-off value | Use closest existing + flag |
| Uncertain | Ask Fru, then PM |

**Absolute zero-tolerance:** `!important` in CSS is a **P0 blocker** — always REJECTED, no exceptions.

**Why this matters:** This turns a subjective design review ("is this close enough?") into a repeatable decision tree. We could apply similar operationalization to our PR review skills.

### 10.12 Fru's 5-Dimension UX Review Framework

Structured UX review across 5 orthogonal dimensions:

1. **Trust & Transparency** — expectations, feedback, error states, data handling
2. **Cognitive Flow** — information hierarchy, unnecessary decisions, mental models, terminology
3. **Visual Clarity** — hierarchy, distinguishability, contrast, animations
4. **Error Prevention & Recovery** — guarding, undo, edge cases, validation
5. **Accessibility** — keyboard, screen reader, color, touch targets

Two modes: **Full Flow Review** (comprehensive, all 5 dimensions) or **Quick Spot Check** (1 strength, 1 critical issue, 1 quick win). Mode selection based on effort level.

### 10.13 CI Script Hidden Patterns

**Suppression mechanisms (not documented in v2):**
- `check-secrets.py`: Supports `# noqa: secrets` inline suppression AND `.secrets-allowlist` file. Warns when allowlist entries reference deleted files.
- `validate-gitignore.py`: Threshold-based detection — flags deny-all only when `exceptions ≥ 3 AND exceptions/total > 0.5` (avoids false positives on small gitignores).
- `validate-references.py`: **Code-block-aware** link validation — `iter_lines_outside_code_blocks()` skips false positives in documentation code examples.

**Advisory vs Blocking classification:**
- `health-check.py` **always exits 0** — advisory only. Creates GitHub issue with "health-check" label if findings. Checks: stale work/* branches >7 days, cache freshness >14 days, large files >1MB.
- All validate-* and check-* scripts exit non-zero on failure → block CI.

**Portability classification:**
- **Copy as-is:** check-secrets.py, check-file-sizes.py, validate-gitignore.py, run-all-checks.py
- **Adapt per-repo:** validate-frontmatter.py (custom schemas), validate-references.py (custom targets), validate-json-schemas.py (custom schemas), health-check.py (custom checks)

### 10.14 Plugin Registration 3-File Complexity

Plugin installation requires editing **3 separate JSON files** — not documented in v2:

1. `known_marketplaces.json` — marketplace source reference (type: directory/github/url, installLocation, lastUpdated)
2. `installed_plugins.json` — install records with `pluginname@marketplace` keys, scope, installPath, version
3. `settings.json` — `enabledPlugins` boolean map + `extraKnownMarketplaces`

**Critical bug:** `claude plugin install` **silently fails** for directory-based local marketplaces. Manual JSON editing required. This is a known limitation they work around, not a design choice.

### 10.15 Additional Patterns Worth Noting

**Agent color assignments:** Each agent has a terminal color for visual identification: Enricher=Cyan, Executor=Green, Patrik=Red, Zolí=Yellow, Sid=Magenta, Palí=Blue, Fru=Yellow, Camelia=Cyan. Minor but shows attention to developer experience.

**SUBAGENT-STOP gate:** `skill-discovery` skill includes a gate that prevents subagents from triggering cascading skill discovery. Prevents infinite recursion where a subagent thinks it needs a skill, which triggers skill-discovery, which triggers another subagent.

**Session-start safety commit:** If uncommitted changes exist at session start: `git add -A && git commit -m "session-start safety commit"`. Prevents mid-session state loss from a prior crashed session.

**Auto-push silent failure:** Post-commit hook always exits 0, even on push failure. Failures logged to `.git/push-failures.log` with ISO timestamp. Never blocks commits. Design philosophy: pushing is crash insurance, not a gate.

**Writing-skills TDD:** TDD discipline applied to skill/documentation authoring, not just code. Supplementary docs include `anthropic-best-practices.md`, `persuasion-principles.md`, `testing-skills-with-subagents.md`. Skills are tested with subagent dispatch to verify they produce expected behavior.

**Context7 supplement strategy:** Primary tools are domain-specific (Sid has UE MCP, Palí/Fru have design libraries). Context7 covers supplementary areas (Palí: React/Tailwind; Sid: vanilla C++; Camelia: PyTorch/pandas). Layered verification across multiple sources increases confidence.

**Instruction priority hierarchy:** Explicitly codified in `skill-discovery`: User explicit instructions > Coordinator skills > Default system prompt. Ensures human always has final word while codified practices override defaults.

**Hooks for cost optimization:** PreToolUse hook on WebSearch/WebFetch suggests dispatching a Sonnet research agent instead. This is a cost-saving nudge — web research burns coordinator Opus context on potentially large fetches that a cheaper Sonnet can handle.

**Replication guide execution order:** When adopting the infrastructure to a new repo: (1) CI/CD Pipeline → (2) Git Workflow → (3) Task Management → (4) Branch Protection Ruleset → (5) Repository Map. Order matters — CI must exist before git workflow relies on it.

**Memory file type system:** Memory entries use YAML frontmatter with type enum: `user` (preferences), `feedback` (lessons), `project` (active state), `reference` (supporting docs). Validated by `validate-frontmatter.py`.

**Research directory:** Contains `AIDER-ASSESSMENT.md` (303 lines) and `AIDER-REPOMAP-COMPARISON.md` (184 lines) — detailed prior art analysis. Shows systematic "study before build" discipline for infrastructure decisions. 117 archived plans in `docs/plans/` demonstrate the same pattern at scale.

---

## 11. Reference Artifacts (extracted from od-claude docs/)

Concrete implementation artifacts from Dónal's repo. These are the scripts and specs behind the patterns described in sections 3.3, 7, and 10.15 above.

### 11.1 Auto-Push Post-Commit Hook

Full script for `.git/hooks/post-commit`:

```bash
#!/bin/bash
# Auto-push to remote on non-main branches. Synchronous — reliability over speed.

BRANCH=$(git branch --show-current 2>/dev/null)

# Only push on work/* or feature/* branches, never main
case "$BRANCH" in
  work/*|feature/*) ;;
  *) exit 0 ;;
esac

# Push synchronously. Log failures but don't block the commit (exit 0 always).
if ! git push origin "$BRANCH" --set-upstream 2>/dev/null; then
  echo "[$(date -Iseconds)] PUSH FAILED on $BRANCH" >> "$(git rev-parse --show-toplevel)/.git/push-failures.log"
fi

exit 0
```

**Async variant for large repos** (background the push):

```bash
(git push origin "$BRANCH" --set-upstream 2>/dev/null || \
  echo "[$(date -Iseconds)] PUSH FAILED on $BRANCH" >> \
  "$(git rev-parse --show-toplevel)/.git/push-failures.log") &
```

Design decisions: synchronous for small repos (negligible latency); silent failure with log to `.git/push-failures.log`; `--set-upstream` on every push (idempotent); never pushes `main`.

### 11.2 Session-Start Safety Commit

Before any branch detection or checkout:

1. `git status` — if ANY uncommitted changes exist (staged, unstaged, untracked):
   ```bash
   git add -A && git commit -m "session-start safety commit"
   ```
2. Auto-push hook fires, pushing the safety commit to remote.
3. If nothing to commit, continue silently.

Non-negotiable — no permission asked. Captures state from prior crashed sessions before anything else happens.

### 11.3 Branch Staleness Check

After settling on a branch at session start:

1. `git merge-base HEAD origin/main` → find divergence point
2. `git log -1 --format=%ci <merge-base-hash>` → get that commit's date
3. Calculate age in days.

**If >2 days diverged:** alert user, recommend merging before new work. Wait for explicit approval. **If ≤2 days:** continue silently.

### 11.4 Handoff System

Bridges session gaps — captures everything TodoWrite knows that would be lost when the session ends.

| Location | Purpose | Lifecycle |
|----------|---------|-----------|
| `.claude/handoffs/*.md` | Active handoffs, available for pickup | Written by `/handoff`, consumed by `/session-start` |
| `archive/handoffs/*.md` | Consumed handoffs, kept as paper trail | Moved here when a handoff is loaded |

**Filename convention:** `{YYYY-MM-DD}_{HHMMSS}_{session-id}.md` (first 8 chars of session UUID, or `manual`).

**Document structure:**

```markdown
# Session Handoff — [DATE]

## What Was Accomplished
## Current State (build status, tests, branch, remote sync, uncommitted changes)
## In-Progress Work
## Key Decisions Made
## Blockers or Issues
## Recommended Next Steps
## Files Modified This Session
```

**Loading protocol:**
1. List all `.md` in `.claude/handoffs/` chronologically
2. User selects which to load, or "None" for fresh start
3. Selected handoffs read into context and archived (moved to `archive/handoffs/`)
4. Unselected remain for other agents or future sessions

**Critical:** Write handoff file FIRST before any git operations. Handoffs typically invoked near compaction — get knowledge onto disk before doing anything else.

### 11.5 Write-Ahead Status Protocol & Crash Recovery

Every plan document has a `**Status:**` field. Update *before* starting a phase, not just on completion.

**Two-layer breadcrumb:**
1. **Tracker layer** — Coordinator marks status before dispatching any agent and commits. This is the WAL record.
2. **Document layer** — Agent marks its own status line as its first action after reading.

**Crash recovery matrix:**

| Tracker says | Document says | Diagnosis |
|-------------|--------------|-----------|
| In progress | Pending | Agent never started (dispatched but crashed on init) |
| In progress | In progress | Agent was mid-work (check for partial progress) |
| In progress | Complete | Agent finished, coordinator crashed before updating tracker |

**Full pipeline state machine:**

```
Pending enrichment
    → Enrichment in progress
        → Enriched — pending review
            → Under review by [Name]
                → Enriched and reviewed
                    → Execution in progress
                        → Execution complete — pending verification
                            → Done
```

Any phase can also transition to `Blocked — [reason]` and back.

**Minimal state machine** (for projects without enrichment/review):

```
Pending → In progress → Complete
              ↕
          Blocked — [reason]
```

---

## 12. P0/P1 Implementation Checklist (Added 2026-03-21)

> Cross-reference with `docs/backlog.md` P0/P1 sections. Check off when implemented.

### P0 — High Impact, Low Effort

- [x] **P0-A: Curate journal.md → lessons.md** — 28 entries in lessons.md (79 lines), 5 categories. MEMORY.md references it.
  - Completed 2026-03-21.

- [x] **P0-B: Post-commit auto-push hook** — `scripts/auto-push-hook.sh` (61 lines). All criteria met.
  - Completed 2026-03-21.

- [x] **P0-C: Wire write-ahead status into lead-orchestrator** — All 3 templates have `**Status:** Pending` + agent update instructions.
  - Completed 2026-03-21.

- [x] **P0-D: Evaluate repomap generator** — Decision: SKIP. codebase-mapping skill + Explore agents cover the use case.
  - Completed 2026-03-22.

### P1 — High Impact, Medium Effort

- [x] **P1-E: Named reviewer personas (3)** — 3 personas in `pr-review-pr/personas/` with routing table. Adapted: garry-review + PR skills, not standalone personas.
  - Completed 2026-03-21.

- [x] **P1-F: Enrichment phase before execution** — Lightweight version in coder-prompt.md: "Verify before editing" with Glob/Read. Full enricher deferred.
  - Completed 2026-03-21.

- [x] **P1-G: Sequential review protocol** — pr-review-pr defaults to sequential dispatch. lead-orchestrator enforces P0/P1 fix-before-proceed.
  - Completed 2026-03-21.

- [x] **P1-H: Review routing layer** — Full routing table in pr-review-pr SKILL.md with auto-invocation logic and manual override.
  - Completed 2026-03-21.

- [x] **P1-I: Tier VIBE protocol per-repo** — vibe-protocol.md §0.1 + lead-orchestrator VIBE Level Detection. full/light gate table documented.
  - Completed 2026-03-21.
