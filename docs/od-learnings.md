# Od-Claude Setup Analysis & Learnings

> **Date:** 2026-03-20
> **Source:** Deep comparison of Dónal O'Duffy's od-claude repo vs. Yu-Kuan's ~/.claude/ setup
> **Purpose:** Objective pros/cons, actionable improvements, and things to reconsider

---

## Table of Contents

1. [Setup Overview](#1-setup-overview)
2. [Objective Pros & Cons](#2-objective-pros--cons)
3. [What to Adopt](#3-what-to-adopt-from-od-claude)
4. [What to Reconsider in Our Setup](#4-what-to-reconsider-in-our-setup)
5. [What NOT to Adopt](#5-what-not-to-adopt)
6. [Implementation Details](#6-implementation-details)
7. [Architecture Patterns Worth Studying](#7-architecture-patterns-worth-studying)
8. [Repo Adoption Audit](#8-repo-adoption-audit)

---

## 1. Setup Overview

### Od-claude Architecture

Od-claude is a complete agent orchestration system built around the **First Officer Doctrine** — Claude is the EM (Engineering Manager), Dónal is the PM. Clear authority boundaries, not a master/servant relationship.

**Key structural elements:**

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

**The pipeline:** Brainstorming → Planning → Enrichment → Review → Execution → Code Review → Ship

**Named reviewer personas (8 total):**

| Agent | Model | Domain | Role |
|-------|-------|--------|------|
| **Patrik** | Opus | Architecture, code quality, security | Primary reviewer. "Standards should be HIGHER given AI handles overhead." |
| **Zolí** | Opus | Ambition advocacy | Backstop only. Challenges conservatism: "Should we refactor instead of patching?" |
| **Sid** | Opus | Unreal Engine, gameplay, systems design | Game dev specialist. Researches UE docs rather than guessing. |
| **Palí** | Opus | Front-end, CSS, design tokens, components | Design system adherence. Pragmatic — "close enough" often correct. |
| **Fru** | Sonnet | UX flow, trust signals, clarity | User-facing review. "Does this make sense to a human?" |
| **Camelia** | Opus | ML/AI, statistics, data modeling | Quantitative lens complementing Patrik's engineering lens. |
| **Enricher** | Sonnet | Research, codebase survey | Gathers facts without making decisions. Fills plan stubs with real file paths, patterns, deps. |
| **Executor** | Sonnet | Implementation | "The typist, not the architect." Follows specs faithfully, validates, escalates if ambiguous. |

### Our Setup Architecture

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
│   └── auto-journal.sh              # Append-only session log
├── memory/journal.md                # Searchable session history
└── docs/, plans/, projects/, tasks/
```

---

## 2. Objective Pros & Cons

### Our Advantages Over Od-claude

| Dimension | What We Have | Why It Matters |
|-----------|-------------|----------------|
| **VIBE Protocol (10 hard gates)** | Phase management, role detection from git branch, spec wall, 2 QA cycles minimum | More formalized quality gates. Phase.json enforcement is a real safeguard od-claude lacks. |
| **PM-OS Integration** | 7 skills + cron scheduling (daily triage, JIRA, weekly briefing) | Unique — od-claude has nothing like it. Automated PM workflows are a genuine force multiplier. |
| **Browser Testing** | Claude-in-Chrome MCP, React-safe fills, parallel tab isolation, condition-based waits | More mature browser automation. Od-claude doesn't have this infrastructure at all. |
| **Git Safety Hook** | PreToolUse blocks `git add -A`, `--no-verify`, `--force`, `reset --hard` | Proactive enforcement vs. relying on CLAUDE.md instructions. Hooks > instructions. |
| **Status Line** | Real-time: model, session ID, context %, git status, AWS creds, disk | Situational awareness od-claude doesn't have. |
| **Auto-Journal** | Append-only session log on every Stop hook (files, tools, errors) | Searchable history across sessions. Od-claude relies on handoffs instead — harder for forensics. |
| **E2E Framework** | YAML test cases, QA runner, test writer, 8 documented common mistakes | Battle-tested patterns with real failure modes documented. |
| **Scheduling** | `schedules.json` with 4 cron-driven automated tasks | Autonomous PM work without manual invocation. |

### Od-claude's Advantages Over Us

| Dimension | What They Have | Why It Matters |
|-----------|---------------|----------------|
| **Named reviewer personas** | 8 distinct characters with written mandates and model assignments | Named personas produce more consistent, reproducible reviews. "Patrik" drifts less than "review this." |
| **Enrichment phase** | Sonnet researcher fills file paths, patterns, deps before execution | Most executor failures come from underspecified plans. Enrichment is cheap (~2 min); rework it prevents is expensive. |
| **Plugin architecture** | 4 toggleable domain groups, per-project activation | Game-dev skills don't load for web projects. Clean separation, no context pollution. |
| **Composable review routing** | Domain-specific routing tables that compose across plugins | Sid for UE → Patrik as backstop. Palí for frontend → Fru for UX → Patrik. Automatic routing by code signals. |
| **Ambition backstop (Zolí)** | Challenges conservative recommendations | Nobody in our setup asks "should we be more ambitious?" Conservative patches never get challenged. |
| **Write-ahead status protocol** | Two-layer breadcrumbs (tracker + document header) | Crash recovery is unambiguous. No expensive triage needed to figure out where an agent stopped. |
| **Convention-based CI** | 9 stdlib-only validation scripts, discovered by naming pattern | Add `validate-*.py` → runs automatically. No Docker, no external deps. |
| **Portable replication specs** | 5 documented specs for bootstrapping new repos | New project → `docs/replication-guide.md` → fully configured in minutes. |
| **Lessons file (52 entries)** | Living engineering patterns, reviewed every session, trimmed to stay useful | Hard-won patterns don't get lost. Format: bold title + 1-2 sentence rule, max 3 lines per entry. |
| **Sequential review with fix-before-next** | Reviewer 1 → fix all findings → Reviewer 2 sees clean artifact | Insight compounds. Each reviewer builds on the previous, not duplicating findings. |
| **Executor/Enricher model split** | Sonnet for execution (cheap, fast), Opus for judgment (deep, expensive) | Right model for right task. Expensive judgment is pre-baked; cheap executors follow specs. |

---

## 3. What to Adopt from Od-claude

### P0 — High Impact, Low Effort

#### A. Write-Ahead Status Protocol

**What:** Before starting any phase, mark status in both the tracker and the document header. Two-layer breadcrumbs for crash recovery.

**Why:** When agents crash mid-execution, recovery state is currently ambiguous. This makes it unambiguous.

**How od-claude implements it:**

```markdown
<!-- In the plan/task document header -->
**Status:** Execution in progress (started 2026-03-20T14:30Z)
```

```json
// In orchestrator-state.json
{
  "T-001": {
    "status": "execution_in_progress",
    "started_at": "2026-03-20T14:30Z",
    "agent": "executor-sonnet"
  }
}
```

**State machine:**
```
Pending → In Progress → Complete
                ↓
          Blocked — [reason]
```

**Crash interpretation:**
- Tracker "in progress" + Document "pending" → agent crashed on init
- Both "in progress" → agent mid-work
- Document "complete" + Tracker "in progress" → agent finished, coordinator crashed

**Implementation:** Add status header to all plan/task documents. Update lead-orchestrator to mark status before dispatch and after verification.

---

#### B. Repo Bootstrap Template

**What:** A checklist/template for bootstrapping new repos with our Claude Code infrastructure.

**Why:** 4 of our 7 repos have decorative or missing Claude Code integration. A template eliminates the scaffolding tax.

**What to include:**

```markdown
# New Repo Bootstrap Checklist

## Required Files
- [ ] `.claude/phase.json` — set to DISCOVERY
- [ ] `.claude/settings.json` — copy from template, adjust permissions
- [ ] `CLAUDE.md` — project-specific context (tech stack, ports, conventions)
- [ ] `memory/lessons.md` — empty, will accumulate
- [ ] `qa/` — empty directory, will hold QA artifacts

## Optional (enable per project type)
- [ ] `.claude/settings.local.json` — project-specific MCP/plugin config
- [ ] `docs/contracts/` — API contracts (for FE↔BE projects)
- [ ] `docs/prd/features/` — feature specs
- [ ] `.claude/skills/` — project-specific skill overrides
```

---

#### C. Orchestrator-State.json for pm_os

**What:** Add central tracking file for pm_os's 22 active worktrees.

**Why:** Spawning 22 concurrent worktrees without visibility is risky. No central tracking = no idea what's in flight.

**Template:**

```json
{
  "last_updated": "2026-03-20T19:00Z",
  "active_tasks": {
    "wt-pm-morning-fix": {
      "status": "in_progress",
      "branch": "feat/pm-morning-fix",
      "started": "2026-03-18",
      "description": "Fix morning triage output format"
    }
  },
  "completed": [],
  "blocked": []
}
```

---

### P1 — High Impact, Medium Effort

#### D. Named Reviewer Personas (Start with 3)

**What:** Replace generic "garry-review" with 3 named reviewers with distinct domains and written mandates.

**Why:** Named characters produce measurably more consistent output than generic "review this." Characters have domain expertise, stable perspectives, and reproducible judgment.

**Recommended starting set:**

| Name | Domain | Perspective | When to Route |
|------|--------|-------------|---------------|
| **Reviewer 1** (Architecture) | Code quality, architecture, security, documentation | Senior engineer with exacting standards | All PRs, all refactors |
| **Reviewer 2** (Domain Expert) | Rotate per project — web/data/PM tooling | Domain specialist | Feature work in their domain |
| **Reviewer 3** (Ambition Backstop) | Challenges conservatism | "Should we refactor instead of patching?" | High-effort tasks, architectural decisions |

**Od-claude's persona template (from Patrik):**

```markdown
# [Name] — [Domain] Reviewer

## Model
[opus/sonnet]

## Domain
[What this reviewer specializes in]

## Perspective
[1-2 sentences capturing their worldview and standards]

## Review Process
1. [Pass 1]: Structure & architecture
2. [Pass 2]: Implementation correctness
3. [Pass 3]: Documentation & naming
4. [Pass 4]: Edge cases & error handling

## Verdict Types
- REJECTED — Fundamental issues, must redesign
- REQUIRES_CHANGES — Specific fixes needed
- APPROVED_WITH_NOTES — Minor suggestions, can merge
- APPROVED — Ship it

## Output Format
[JSON structure + human summary]

## Core Principle
[One sentence that grounds this reviewer's identity]
```

**Tradeoff:** More setup work upfront. Risk of persona bloat if you add too many too fast. Start with 3, add more only when you feel a gap.

**Effort:** 2-3 hours to design and test personas.

---

#### E. Enrichment Phase

**What:** Add a Sonnet-powered research step between planning and execution. The enricher surveys the codebase and fills plan stubs with concrete file paths, existing patterns, and dependency info.

**Why:** Most executor failures come from underspecified plans. Enrichment catches wrong assumptions before code is written. It's cheap (~2 minutes, Sonnet cost) and the rework it prevents is expensive.

**Key design principles from od-claude:**

1. **Enricher does NOT make architectural decisions** — only gathers facts
2. **Enricher flags ambiguity** — "I found 3 possible patterns for this; coordinator should decide"
3. **Write-ahead status** — marks "Enrichment in progress" before starting
4. **Three sub-phases:** Phase 0 (repo map), Phase 1 (survey), Phase 2 (plan annotation)

**When to trigger:** Only for tasks touching 3+ files. Trivial changes skip enrichment.

**Implementation sketch:**

```markdown
# Enricher Skill

## Trigger
Invoked by lead-orchestrator when a plan stub references 3+ files or has uncertain file paths.

## Process
1. Read the plan stub
2. Survey codebase for:
   - Actual file paths (verify they exist)
   - Existing patterns in surrounding code
   - Import/dependency graph for affected files
   - Test file locations and conventions
3. Annotate the plan stub with findings
4. Flag anything ambiguous for coordinator decision

## Model
Sonnet (fast, cheap — judgment already happened in planning)

## Tools
Read, Glob, Grep, Bash (exploration only). NO Edit/Write on implementation files.

## Output
Annotated plan stub with:
- ✅ Verified file paths
- 📋 Existing patterns to follow
- ⚠️ Ambiguities flagged for coordinator
- 📦 Dependencies identified
```

**Effort:** 3-4 hours to build and calibrate.

---

#### F. Wire or Delete Dormant Skills

**What:** boardroom-ai has garry-review and vibe-lookup skills defined but showing no evidence of activation.

**Action:** Either integrate them into lead-orchestrator's QA cycle or delete them. Dead skills erode trust in the skill system.

---

#### G. Enforce or Explicitly Relax VIBE Gates Per-Repo

**What:** VIBE protocol defines 10 non-negotiable gates, but only deck_benchmarks consistently enforces them.

**Options:**

| Option | Tradeoff |
|--------|----------|
| **Full enforcement everywhere** | Maximum quality, maximum ceremony. Overkill for pm_os (tooling, not product). |
| **Tiered enforcement** | Define "full VIBE" vs. "light VIBE" profiles. Projects declare which they use in phase.json. |
| **Status quo** | Aspirational rules that aren't enforced erode trust in ALL rules. Not recommended. |

**Recommendation:** Tiered. Add a `"vibe_level": "full" | "light"` field to phase.json. Light = TDD + review required, no spec wall, no 2 QA cycles. Full = everything.

---

### P2 — Medium Impact, Low Effort

#### H. Cherry-Pick CI Scripts

Two od-claude validation scripts are portable and immediately valuable:

**`check-secrets.py`** — Scans for accidental API keys, AWS credentials, GitHub tokens in committed files. Stdlib-only, copy as-is.

**`check-file-sizes.py`** — Prevents files >1MB from entering the repo. Catches accidental binary commits.

Both are convention-based: name them `check-*.py` in a `.github/scripts/` directory and add a runner.

---

#### I. Sequential Review for High-Stakes Work

**What:** When routing through 2+ reviewers, apply ALL fixes from Reviewer 1 before dispatching Reviewer 2.

**Why:** Each reviewer sees clean work, not known-issues. Insight compounds instead of duplicating.

**When:** PRDs, architecture decisions, major refactors. Skip for routine bug fixes.

**Od-claude's rule:** "Multi-persona reviews are always sequential, never parallel. Each reviewer sees a clean, corrected artifact."

---

## 4. What to Reconsider in Our Setup

### A. 10 Hard Gates — Are They All Enforced?

The VIBE protocol defines 10 non-negotiable gates. Our repo audit shows:

| Repo | Phase Gate | Spec Wall | TDD | 2 QA Cycles | Contract-First |
|------|-----------|-----------|-----|-------------|----------------|
| deck_benchmarks | ✅ | ✅ | ✅ | ✅ | ✅ |
| pm_os | ✅ | ❌ | ❌ | ❌ | N/A |
| boardroom-ai | ❌ (no phase.json) | ❌ | Partial | ❌ | ❌ |
| nextgen | ✅ | ❌ | ❌ | ❌ | ❌ |
| portco_insights | ✅ (frozen) | ❌ | ❌ | ❌ | ❌ |
| maple-web | ❌ | ❌ | ❌ | ❌ | ❌ |

**Problem:** Aspirational rules that aren't enforced erode trust in all rules. Either enforce or explicitly tier.

### B. 22 Worktrees in pm_os Without State Machine

Heavy parallel orchestration with no central tracking. If a worktree is abandoned, there's no record of what it was doing or whether it completed.

### C. Skills Defined But Not Invoked

boardroom-ai has garry-review and vibe-lookup skills with no activation evidence. Dead infrastructure creates confusion about what's actually in use.

### D. Cross-Repo Lessons Gap

- deck_benchmarks has `learning.md` (3.8K) — project-specific, not shared
- pm_os has TOKEN-7 incident but no lessons.md capturing it
- No shared lessons repository across projects

**Recommendation:** Establish `~/.claude/memory/lessons.md` (like od-claude's 52-entry file) as the cross-repo patterns store. Project-specific lessons stay in `tasks/<project>/lessons.md`.

---

## 5. What NOT to Adopt

### A. The Full 7-Stage Pipeline

Od-claude's pipeline: Brainstorming → Planning → Enrichment → Review → Execution → Code Review → Ship.

**Why not:** This is a lot of ceremony for small changes. Our 4-stage (spec → TDD → QA cycle 1 → QA cycle 2) is already rigorous. Adopt enrichment (Section 3E) as an add-on, but don't restructure the whole pipeline.

### B. 8 Named Personas

**Why not:** Persona proliferation. Maintaining 8 distinct reviewer personalities is overhead. Diminishing returns past 3-4. Start with 3, add more only when you feel the gap.

### C. Auto-Push on Every Commit

Od-claude pushes to remote on every commit via post-commit hook. Our `git-safety-hook.sh` blocks `git add -A`. These philosophies conflict — od-claude commits fast and loose; we gate carefully.

**Keep our safety hooks.** They're stricter and that's intentional. Enforcement > instructions.

### D. Advisory-Only CI

Od-claude's status checks don't block merge. Our VIBE hard gates are stricter.

**Keep our blocking gates.** They're a feature, not a limitation.

### E. Plugin Architecture (Not Yet)

Organizing skills into toggleable domain groups would require significant refactoring. Our flat structure works with <30 skills. Revisit if skill count doubles or context pollution becomes a real problem.

### F. Handoff System

Od-claude uses a handoff directory for cross-session continuity. Our auto-journal + file-based plans serve this purpose. The journal is actually better for forensics (searchable, append-only).

---

## 6. Implementation Details

### Od-claude's Enricher — How It Actually Works

**Three sub-phases:**

1. **Phase 0 — Repo Map:** Generate/read a structural overview of the codebase (aider-inspired). Lists key files ranked by importance.

2. **Phase 1 — Survey:** For each plan stub, verify:
   - Do the referenced files actually exist?
   - What patterns does surrounding code follow?
   - What are the imports/dependencies?
   - Where are the test files?
   - Are there asset dependencies (marketplace packs, external SDKs)?

3. **Phase 2 — Annotate:** Write findings back into the plan document. Each stub gets:
   - Verified file paths (or corrections)
   - Pattern notes ("this module uses factory pattern, follow it")
   - Dependency graph
   - Test file locations
   - Ambiguity flags for coordinator

**Key constraint:** Enricher NEVER makes architectural decisions. It flags them: "I found 3 patterns for this — coordinator should decide which to follow."

### Od-claude's Review Routing — How It Actually Works

```markdown
# Routing Algorithm

1. Read universal routing (coordinator/routing.md)
2. Scan enabled plugins for root routing.md files
3. Merge into composite routing table
4. Match code signals against table:
   - Frontend files (.tsx, .css, components/) → Palí → Fru → Patrik
   - Game logic (.cpp, Blueprints/) → Sid → Patrik
   - ML/data (.py, models/, notebooks/) → Camelia → Patrik
   - Architecture, cross-cutting, fallback → Patrik
5. Route to matched reviewer(s)
6. If High effort: mandatory Zolí backstop after primary review
```

### Od-claude's Executor — Validation Matrix

The executor determines which validation commands to run based on project signals:

| Signal File | Validation Command |
|-------------|-------------------|
| `tsconfig.json` | `tsc --noEmit` |
| `pyproject.toml` | `poetry check && pytest` |
| `*.uproject` | Unreal build command |
| `package.json` | `npm test` or `yarn test` |
| `Cargo.toml` | `cargo check && cargo test` |

**Stop conditions:**
- **Fixable:** Type error, logic bug, missing import → fix and continue
- **Structural:** Architecture wrong, spec contradictory, dependency missing → STOP and escalate

### Od-claude's Lessons File — Format

```markdown
# Lessons

- **Strict status checks need --auto fallback** — GitHub's strict_required_status_checks reject even up-to-date branches when required checks haven't run on the latest commit
- **Deny-all gitignore patterns forbidden** — Default failure must be "tracked too much", never "silently lost"
- **Plugin cache doesn't auto-sync** — After editing plugin files, must copy to ~/.claude/plugins/cache/
- **Dispatched executors always Sonnet** — Opus judgment is pre-baked in enrichment; executors follow specs
- **Single-agent designs on large sets fail** — Pattern: Opus coordinator decides *how many* workers, Sonnet does mechanical work
- **Write skeleton file first** — Prevents losing output if agent runs out of tokens mid-research
```

**Format rules:**
- Bold title + 1-2 sentence rule
- Max 3 lines per entry
- 50-entry cap, trim when exceeded
- Entry bar: "Will this save time in the next 4 weeks?"
- Merge with existing entries if related

---

## 7. Architecture Patterns Worth Studying

### Pattern: Model Assignment by Cognitive Demand

Od-claude deliberately assigns models based on what the task requires:

| Task Type | Model | Rationale |
|-----------|-------|-----------|
| Architectural decisions | Opus | Requires deep judgment, tradeoff analysis |
| Code review | Opus | Requires identifying subtle issues, quality standards |
| Ambition backstop | Opus | Requires challenging assumptions, seeing bigger picture |
| Codebase research | Sonnet | Mechanical fact-gathering, no judgment needed |
| Code execution | Sonnet | Following specs faithfully, speed > depth |
| UX review | Sonnet | Checking flow clarity, lower cognitive ceiling |

**Our opportunity:** We use Opus everywhere. For lead-orchestrator's coder subagents, we could specify Sonnet when the plan is well-enriched and save significant cost/time.

### Pattern: Convention-Based Discovery

Od-claude's CI scripts are discovered by naming pattern, not registered in a config file:

```python
# run-all-checks.py discovers scripts automatically
for script in sorted(scripts_dir.glob("validate-*.py")):
    run(script)
for script in sorted(scripts_dir.glob("check-*.py")):
    run(script)
```

**Benefit:** Adding a new check = dropping a file. No config editing, no workflow updates. The naming convention IS the registry.

### Pattern: Crash-Safe State Machine

Od-claude's write-ahead protocol treats agent orchestration like a database transaction:

```
1. Coordinator marks tracker: "dispatching T-001 to executor"
2. Coordinator commits tracker
3. Executor marks document header: "Execution in progress"
4. Executor does work
5. Executor marks document header: "Execution complete"
6. Coordinator verifies, marks tracker: "T-001 complete"
```

If any step crashes, the state is unambiguous from the breadcrumbs alone. No need for expensive triage to figure out what happened.

### Pattern: Ambition Backstop

Zolí's role is unique — never a primary reviewer, only invoked to challenge conservative recommendations:

**Questions Zolí asks:**
- "Is this a patch where a refactor is the right move?"
- "Given AI can handle the complexity, should we be more ambitious?"
- "Are we avoiding this because it's hard, or because it's actually YAGNI?"

**When invoked:**
- Mandatory for high-effort tasks
- Optional for medium-effort
- Skip for low-effort

This is a structural check against the natural tendency of LLMs to propose safe, minimal changes.

---

## 8. Repo Adoption Audit

**How well is our Claude Code infrastructure actually used across repos?**

| Repo | Type | Phase | VIBE Depth | QA Artifacts | Verdict |
|------|------|-------|------------|--------------|---------|
| **deck_benchmarks** | Python + React | BUILD | Deep (9 config files) | 76+ FEAT/BUG dirs, 2 QA cycles | Reference implementation |
| **pm_os** | Node.js tooling | BUILD | Medium (2 files) | 1 feature dir, 22 worktrees | Heavy orchestration, light QA |
| **boardroom-ai** | React + FastAPI | No phase.json | Medium (3 files + skills) | Sparse (1 BUG dir) | Good config, light execution |
| **nextgen** | Angular + .NET | BUILD | Minimal (1 file) | 1 BUG dir | Early setup phase |
| **portco_insights** | Unknown | BUILD (frozen) | Minimal (2 files) | Empty /qa | Dormant — scaffolded, never used |
| **maple-web** | C#/.NET | No phase.json | Minimal (2 files) | No /qa | Using Claude as editor only |
| **PM** | Unknown | N/A | None | None | Not integrated |

**Key takeaway:** Only deck_benchmarks demonstrates full VIBE compliance. The gap between our infrastructure sophistication and actual adoption is the biggest risk. Either enforce everywhere (via bootstrap template) or explicitly tier repos into "full" vs. "light" VIBE profiles.

---

## Priority Action Summary

| Priority | Action | Source | Effort |
|----------|--------|--------|--------|
| **P0** | Add write-ahead status protocol to orchestrator | od-claude | Low (1-2h) |
| **P0** | Create repo bootstrap template | od-claude | Low (1-2h) |
| **P0** | Add orchestrator-state.json to pm_os | od-claude pattern | Low (30min) |
| **P1** | Build 3 named reviewer personas | od-claude | Medium (2-3h) |
| **P1** | Add enrichment phase for 3+ file tasks | od-claude | Medium (3-4h) |
| **P1** | Wire garry-review into lead-orchestrator or delete | Audit finding | Low (1h) |
| **P1** | Enforce or explicitly relax VIBE gates per-repo | Audit finding | Low (1h) |
| **P1** | Establish cross-repo lessons.md | od-claude | Low (1h) |
| **P2** | Cherry-pick check-secrets.py + check-file-sizes.py | od-claude | Low (1h) |
| **P2** | Sequential review for high-stakes work | od-claude | Low (convention) |
| **P2** | Model assignment by cognitive demand (Sonnet for executors) | od-claude | Low (config) |
| **Keep** | Git safety hooks (superior to od-claude) | Ours | — |
| **Keep** | PM-OS automation (unique advantage) | Ours | — |
| **Keep** | Browser testing infra (od-claude lacks this) | Ours | — |
| **Keep** | Status line + auto-journal (better observability) | Ours | — |
| **Keep** | VIBE hard gates (stricter than od-claude's advisory CI) | Ours | — |
