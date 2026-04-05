# Deep Comparative Study: gstack Skills System

> Generated 2026-03-30 via /lead-orchestrator
> Wave 1: 4 exploration agents + 2 comparison agents
> Wave 2: 10 parallel deep-dive explorer agents + 3 Opus synthesis agents
> Total: 19 subagents across 2 waves

---

## Table of Contents

1. [How gstack's skill system works](#1-how-gstacks-skill-system-works)
2. [Why docs/skills.md AND individual skill folders?](#2-why-docsskillsmd-and-individual-skill-folders)
3. [Which skills to adopt into VIBE Protocol](#3-which-skills-to-adopt-into-vibe-protocol)
4. [Installation plan: gstack into our .claude setup](#4-installation-plan)
5. [How to use the design CLI](#5-how-to-use-the-design-cli)
6. [/prd-review skill design](#6-prd-review-skill-design)

---

## 1. How gstack's Skill System Works

### Architecture: Template Pipeline → AI Instructions

gstack is a **template-compiled skill system**. Every slash command is a SKILL.md file
generated from a `.tmpl` template via 13 resolver modules.

```
Source of truth:        ship/SKILL.md.tmpl (human-edited, ~200 lines)
                              │
                              ▼
Template engine:        scripts/gen-skill-docs.ts
                        + 13 resolver modules in scripts/resolvers/
                              │
                              ▼
Generated output:       ship/SKILL.md (1500-2000 lines, AI-readable)
                        .agents/skills/ship/SKILL.md (Codex variant)
                        .factory/skills/ship/SKILL.md (Factory variant)
```

A `ship/SKILL.md.tmpl` that says `{{PREAMBLE}}` expands to 1200+ lines of
initialization, voice directives, telemetry, session tracking, and user preferences.
A `{{REVIEW_DASHBOARD}}` placeholder expands to the review readiness dashboard logic.
A `{{TEST_COVERAGE_AUDIT_SHIP}}` expands to the full codepath-tracing coverage system.

### The 13 Resolvers (What They Inject)

| Resolver Module | Key Placeholders | What It Generates |
|---|---|---|
| **preamble.ts** (590 lines) | `PREAMBLE`, `TEST_FAILURE_TRIAGE` | Update checks, session tracking, telemetry, voice directive (4 tiers), AskUserQuestion format, Completeness Principle, repo mode detection |
| **review.ts** (870 lines) | `REVIEW_DASHBOARD`, `ADVERSARIAL_STEP`, `SPEC_REVIEW_LOOP`, `PLAN_COMPLETION_AUDIT_*`, `CODEX_SECOND_OPINION` | Review status tracking, spec review loops, adversarial passes, plan verification, cross-model synthesis |
| **design.ts** (391 lines) | `DESIGN_METHODOLOGY`, `DESIGN_HARD_RULES`, `DESIGN_MOCKUP`, `DESIGN_SHOTGUN_LOOP`, `DESIGN_REVIEW_LITE` | 80-item design audit, AI slop blacklist (10 patterns), comparison board loop, mockup generation |
| **testing.ts** (573 lines) | `TEST_BOOTSTRAP`, `TEST_COVERAGE_AUDIT_*` | Framework detection + setup, codepath tracing, ASCII coverage diagrams, coverage gates |
| **browse.ts** (130 lines) | `COMMAND_REFERENCE`, `SNAPSHOT_FLAGS`, `BROWSE_SETUP` | Auto-generated command table (55 commands), snapshot flag reference, binary detection |
| **utility.ts** | `BASE_BRANCH_DETECT`, `QA_METHODOLOGY`, `DEPLOY_BOOTSTRAP`, `CHANGELOG_WORKFLOW` | Platform detection, QA modes, deploy platform auto-detect, version/changelog workflow |
| **learnings.ts** | `LEARNINGS_SEARCH`, `LEARNINGS_LOG` | Cross-project learning recall, pattern logging with confidence scores |
| **confidence.ts** | `CONFIDENCE_CALIBRATION` | 1-10 scoring rubric for review findings |
| **composition.ts** | `INVOKE_SKILL` | Skill chaining (parent invokes child, skips duplicate preamble) |
| **constants.ts** | (internal) | AI slop blacklist, OpenAI rejection criteria, litmus checks |
| **types.ts** | (internal) | TemplateContext, HostPaths, Host type definitions |

### How Skills Chain Together

gstack uses **linear composition**, not DAG-based orchestration:

```
/office-hours → design doc → /plan-ceo-review → /plan-eng-review
     │                              │                    │
     │ writes design doc     reads design doc     writes test plan
     │ to ~/.gstack/         persists decisions    to ~/.gstack/
     ▼                              ▼                    ▼
    [BUILD]                  /review reads diff    /qa reads test plan
                             two-pass review       diff-aware testing
                                    │                    │
                                    ▼                    ▼
                             /ship orchestrates everything:
                             merge → test → review → version → PR
                                    │
                                    ▼
                             /land-and-deploy → /canary
```

State passes between skills via:
- **Files on disk**: `~/.gstack/projects/{slug}/` (design docs, test plans, review logs, learnings)
- **Git state**: Branch diff is primary input for review/qa/ship
- **Review dashboard**: JSONL log tracking which reviews ran + staleness
- **Learnings JSONL**: Cross-session pattern memory with confidence decay

### The Review Readiness Dashboard

Central coordination mechanism across all review/ship skills:

```
+====================================================================+
|                    REVIEW READINESS DASHBOARD                       |
+====================================================================+
| Review          | Runs | Last Run            | Status    | Required |
|-----------------|------|---------------------|-----------|----------|
| Eng Review      |  1   | 2026-03-16 15:00    | CLEAR     | YES      |
| CEO Review      |  1   | 2026-03-16 14:30    | CLEAR     | no       |
| Design Review   |  0   | —                   | —         | no       |
| Adversarial     |  0   | —                   | —         | no       |
| Outside Voice   |  0   | —                   | —         | no       |
+--------------------------------------------------------------------+
| VERDICT: CLEARED — Eng Review passed                                |
+====================================================================+
```

### Pros vs Cons

**PROS:**
1. Comprehensive lifecycle coverage (31 skills, ideation→retro)
2. Self-documenting via template pipeline (SKILL.md stays in sync with code)
3. Multi-host compilation (Claude, Codex, Factory from one template)
4. 100+ E2E tests validate skills actually work
5. Real browser automation (Playwright CLI, 100ms/command)
6. Design tooling (AI mockups, comparison boards, AI slop detection)
7. Cross-model review (/codex independent second opinion)
8. Institutional memory (learnings JSONL, confidence-scored, cross-project)
9. Progressive safety layers (/careful → /freeze → /guard)
10. Fix-First pattern (auto-fix mechanical issues, ask for judgment calls)

**CONS:**
1. No formal orchestration (linear chaining, not task DAGs)
2. No spec wall (trusts testing, not specs)
3. No TDD mandate (test bootstrap is optional)
4. No phase gates (any skill can run anytime)
5. Preamble bloat (1200+ lines per skill)
6. Template complexity (13 resolvers, hard to customize)
7. No enterprise integration (zero PM tooling)
8. Opinionated voice (Garry Tan's builder style baked in)
9. Binary distribution (arm64 macOS only, rebuild needed for other platforms)

---

## 2. Why docs/skills.md AND Individual Skill Folders?

They serve **completely different audiences**:

### `docs/skills.md` — For Humans (1,167 lines)

- Written by Garry Tan in first person
- Philosophy, real anecdotes, workflow narratives
- Describes WHAT each skill does and WHY
- Organized as a lifecycle story: ideation → planning → design → build → QA → ship → retro
- **NOT read by Claude Code at runtime**
- Purpose: README-grade documentation that sells the product and teaches the philosophy

Example from `/plan-ceo-review` section:
> "This is my **founder mode**. I want the model to think with taste, ambition, user
> empathy, and a long time horizon. I do not want it taking the request literally.
> I want it asking a more important question first: **What is this product actually for?**"

### `*/SKILL.md` (32 files) — For AI (1500-2000 lines each)

- Auto-generated from `.tmpl` templates
- Exact step-by-step workflows, bash commands, decision trees
- Injected with shared methodology via {{PLACEHOLDER}} resolvers
- **Read by Claude Code when skill is invoked**
- Purpose: Executable instructions that Claude follows precisely

Example from ship/SKILL.md (generated):
```
Step 3.4: Run test coverage audit
{{TEST_COVERAGE_AUDIT_SHIP}}
[expands to 200+ lines of codepath tracing, ASCII diagram generation,
coverage gate logic, and test auto-generation instructions]
```

### `*/SKILL.md.tmpl` (32 files) — Source of Truth

- Human-editable template files (~100-300 lines each)
- Use `{{PLACEHOLDER}}` syntax for shared components
- Frontmatter declares: name, preamble-tier, description, allowed-tools, benefits-from
- **Never read by Claude Code** — only the generator reads them
- Purpose: DRY source that compiles into host-specific SKILL.md files

### Summary

```
docs/skills.md          → HUMAN reads to understand the product
*/SKILL.md.tmpl         → HUMAN edits to change skill behavior
*/SKILL.md              → AI reads to execute the skill
scripts/resolvers/*.ts  → CODE generates shared components
```

---

## 3. Which Skills to Adopt into VIBE Protocol

### Tier 1: ADOPT NOW (high value, low effort)

| Skill | VIBE Phase | Value | Effort |
|---|---|---|---|
| **`/browse`** (55-command Playwright CLI) | BUILD, QA | 10-30x faster browser QA than Claude-in-Chrome MCP | 30 min: run `./setup`, update e2e skills to use `$B` commands |
| **`/plan-ceo-review`** (founder-mode strategy review) | DISCOVERY | Structured "10-star product" thinking with 4 modes + 18 cognitive patterns | Already installed after `./setup`. Use during DISCOVERY phase. |
| **`/plan-eng-review`** (architecture + diagrams) | ARCHITECTURE_APPROVED | Forces hidden assumptions via diagrams. Produces test plan artifact. | Already installed. Use as Architect deliverable for phase gate. |
| **`/review`** (two-pass code review) | BUILD (QA Cycle 1) | Fix-First pattern, confidence-scored findings, auto-fixes mechanical issues | Supplement garry-review for fast pre-landing gates |
| **`/cso`** (OWASP + STRIDE security audit) | BUILD | No equivalent in current setup. Infrastructure-first security scanning. | Already installed. Run before shipping auth/payment features. |

### Tier 2: ADOPT SOON (good value, moderate effort)

| Skill | VIBE Phase | Value | Effort |
|---|---|---|---|
| **`/qa`** (diff-aware QA + bug fix loop) | BUILD (QA) | Organic bug discovery + regression test auto-generation | Supplement YAML tests for exploratory QA |
| **`/ship`** (automated release) | BUILD (done) | One-command: merge base → test → review → version → PR | Integrate with R6 auto-commit |
| **`/canary`** (post-deploy monitoring) | Post-BUILD | Console error + perf regression detection | Add to land-and-deploy as final step |
| **`/design-review`** (80-item visual audit) | BUILD | AI slop detection + fix loop. Only design QA in ecosystem. | Run on frontend changes |
| **`/learn`** (cross-project learnings) | All phases | Confidence-scored JSONL with decay. Complements MEMORY.md. | Set up per-project JSONL |
| **`/benchmark`** (Core Web Vitals tracking) | BUILD/QA | Performance regression detection with baseline comparison | Run before perf-sensitive changes |

### Skip (overlap or conflict with VIBE)

| Skill | Reason |
|---|---|
| `/careful`, `/freeze`, `/guard`, `/unfreeze` | VIBE has git-safety hook + task-spec-gate (stronger) |
| `/gstack-upgrade` | Meta-skill. Just `git pull && ./setup`. |
| `/connect-chrome` | Demo/visualization only |
| `/setup-deploy`, `/setup-browser-cookies` | One-time utilities, run once then forget |

---

## 4. Installation Plan

### Phase 1: Install gstack globally (30 seconds)

```bash
cd ~/Code/gstack
./setup --no-prefix
```

**What happens:**
1. Builds browse binary (Playwright CLI, ~10s)
2. Builds design binary (GPT-4 Image API CLI, ~5s)
3. Ensures Playwright Chromium installed
4. Creates `~/.gstack/` state directory
5. Creates symlinks in `~/.claude/skills/` for all 31 skills

**Your 32 custom skills are NOT touched.** gstack creates new symlinks alongside them:

```
~/.claude/skills/
├── pm-jira/              ← YOUR skill (untouched)
├── pm-morning/           ← YOUR skill (untouched)
├── lead-orchestrator/    ← YOUR skill (untouched)
├── prd-writer/           ← YOUR skill (untouched)
├── ... (28 more of yours)
│
├── gstack/               ← NEW: repo symlink
├── qa/                   ← NEW: → gstack/qa
├── ship/                 ← NEW: → gstack/ship
├── review/               ← NEW: → gstack/review
├── browse/               ← NEW: → gstack/browse
├── office-hours/         ← NEW: → gstack/office-hours
├── ... (26 more gstack symlinks)
```

**Potential naming conflicts:** Check before installing:
```bash
ls ~/.claude/skills/ | grep -E '^(qa|ship|review|browse|investigate|benchmark|canary|learn)$'
```
If any conflict, use `./setup --prefix` to namespace as `/gstack-qa`, `/gstack-ship`, etc.

### Phase 2: Setup design CLI

```bash
~/.claude/skills/gstack/design/dist/design setup
# Enter OpenAI API key (needs image generation permission)
# Runs smoke test
```

### Phase 3: Verify everything works

```bash
# Browse CLI
~/.claude/skills/gstack/browse/dist/browse goto https://example.com
~/.claude/skills/gstack/browse/dist/browse snapshot -i
~/.claude/skills/gstack/browse/dist/browse stop

# Test a skill
# In Claude Code, type: /office-hours
```

### Phase 4: Update existing QA skills to use browse CLI

Replace `mcp__claude-in-chrome__*` references in browser-testing and e2e-* skills:

| Before (MCP) | After (Browse CLI) |
|---|---|
| `mcp__claude-in-chrome__navigate(url)` | `$B goto <url>` |
| `mcp__claude-in-chrome__read_page()` | `$B snapshot -i` |
| `mcp__claude-in-chrome__find(sel)` | `$B snapshot -s "sel"` |
| `mcp__claude-in-chrome__form_input(sel, val)` | `$B fill "sel" "val"` |
| `mcp__claude-in-chrome__computer(click, x, y)` | `$B click @e3` |
| `mcp__claude-in-chrome__computer(screenshot)` | `$B screenshot` |
| `mcp__claude-in-chrome__read_console_messages()` | `$B console --errors` |

Keep Claude-in-Chrome as fallback for parallel tab-isolated tests.

---

## 5. How to Use the Design CLI

### Setup (one time)

```bash
$D setup
# Or: echo '{"api_key": "sk-..."}' > ~/.gstack/openai.json && chmod 600 ~/.gstack/openai.json
```

Where `$D` = `~/.claude/skills/gstack/design/dist/design`

### Generate a Mockup (~$0.15, ~45s)

```bash
$D generate \
  --brief "Board meeting portal. Dark sidebar with meeting list. Main area: agenda items, documents, action items. Professional, minimal, Inter font." \
  --output /tmp/board-mockup.png
```

### Explore Multiple Directions (~$0.45, ~90s)

```bash
$D variants --brief "Board portal homepage" --count 3 --output-dir /tmp/variants/
$D compare --images "/tmp/variants/variant-A.png,variant-B.png,variant-C.png" --output /tmp/board.html --serve
# Browser opens with comparison board. Rate, comment, submit or regenerate.
```

### Iterate on Chosen Direction (~$0.10/iteration)

```bash
RESULT=$($D generate --brief "Meeting agenda view" --output /tmp/v1.png)
SESSION=$(echo "$RESULT" | jq -r '.sessionFile')
$D iterate --session "$SESSION" --feedback "Larger titles, add attendee avatars" --output /tmp/v2.png
```

### Improve Existing UI (~$0.15)

```bash
$B screenshot --output /tmp/current.png
$D evolve --screenshot /tmp/current.png --brief "Modernize. Better typography." --output /tmp/improved.png
```

### Extract Design System (~$0.005)

```bash
$D extract --image /tmp/approved.png
# Writes DESIGN.md with colors, typography, spacing, layout
```

### Verify Implementation (~$0.005)

```bash
$B goto https://staging.myapp.com && $B screenshot --output /tmp/live.png
$D verify --mockup /tmp/approved.png --screenshot /tmp/live.png
# Returns pass/fail + match score + differences
```

### All 13 Commands

| Command | Purpose | Cost |
|---|---|---|
| `setup` | API key + smoke test | Free |
| `generate` | Single mockup from brief | $0.15 |
| `variants` | N style variants (max 7) | $0.15×N |
| `compare` | HTML comparison board | Free |
| `serve` | HTTP feedback server | Free |
| `iterate` | Refine with threaded feedback | $0.10 |
| `check` | Vision quality gate | $0.005 |
| `evolve` | Improve existing screenshot | $0.15 |
| `extract` | Design tokens → DESIGN.md | $0.005 |
| `prompt` | Implementation instructions from mockup | $0.005 |
| `diff` | Visual diff between mockups | $0.005 |
| `verify` | Compare implementation vs mockup | $0.005 |
| `gallery` | Timeline HTML of all explorations | Free |

### Typical Session Cost

```
3 variants ($0.45) + 2 iterations ($0.20) + extract ($0.005) + verify ($0.005) = ~$0.66
```

---

## 6. /prd-review Skill Design

### Architecture Decision

Per user's choice: **Both** — standalone `/prd-review` skill AND a hook in `/prd-writer`.

```
~/.claude/skills/prd-review/
├── SKILL.md              ← Main skill definition
├── references/
│   └── persona-prompts.md ← System prompts for 5 reviewer personas
└── templates/
    └── review-report.md  ← Output template
```

Plus: Add a "Step 7: Adversarial Review" to prd-writer/SKILL.md that invokes /prd-review.

### Persona Model (3 Sonnet + 2 Opus)

| # | Persona | Model | Dimension | Source Patterns |
|---|---|---|---|---|
| 1 | **Product Thinker** | Sonnet | Big picture, ambition, user value | gstack `/office-hours` 6 forcing questions + `/plan-ceo-review` premise challenge |
| 2 | **UX Designer** | Sonnet | User experience, interaction design, accessibility | gstack `/design-review` first-impression framework + `/plan-design-review` 7-pass methodology |
| 3 | **Engineering Manager** | Opus | Consistency, clarity, implementability | gstack `/plan-eng-review` diagram-forcing + od-claude Patrik's 4-pass structured review |
| 4 | **Customer Expert** | Sonnet | Persona fit (Board Members, Admins, Executives) | Domain-specific: Diligent Boards personas + user needs mapping |
| 5 | **QA Expert** | Opus | Testability, feasibility, hidden complexity | gstack adversarial step + od-claude enricher BAD/OK/GOOD spectrum |

### Four-Phase Workflow

#### Phase 1: Big Picture Review (adapted from gstack, with optional escalation)

**Methodology baked into prompt** (from `/office-hours` + `/plan-ceo-review`):

1. **Is this the right problem?** Could we solve something with bigger impact?
2. **What's the 10X approach?** How can we approach this for maximum user benefit?
3. **Is the framing constraining us?** Are we building a calendar app when we should be building a chief of staff AI?
4. **Premise challenge:** Present 3-5 falsifiable claims about the product for PM validation.

**Optional gstack escalation:** If user says "go deeper" → invoke actual `/office-hours` or `/plan-ceo-review` skill for full treatment.

**Output:** Premises accepted/rejected, framing adjustments, scope recommendation.

#### Phase 2: Fresh Subagent Spec Review (5 parallel agents)

Spawn 5 fresh subagents with NO prior context. Each sees ONLY the PRD document.

**Agent 1: Product Thinker** (Sonnet)
- Reviews: Problem-solution fit, user value proposition, competitive positioning
- Draws from: gstack 6 forcing questions (demand reality, status quo, desperate specificity, narrowest wedge, observation & surprise, future-fit)
- Output format: Score (1-10) per sub-dimension + issues as SPECIFIABLE or REQUIRES_DECISION

**Agent 2: UX Designer** (Sonnet)
- Reviews: User flows, interaction states (loading/empty/error/success), accessibility, information hierarchy
- Draws from: gstack design-review first-impression framework ("This communicates [X]. I notice [Y]. First 3 things eye goes to: [1][2][3]. One-word verdict: [Z]")
- Reviews 7 passes: Info architecture, interaction state coverage, user journey, AI slop risk, design system alignment, responsive/accessibility, unresolved design decisions
- Output format: Per-dimension score (0-10) + what a 10 looks like + specific gaps

**Agent 3: Engineering Manager** (Opus)
- Reviews: Consistency (do parts agree?), clarity (could agent implement without AskUserQuestion?), hidden assumptions
- Draws from: gstack `/plan-eng-review` diagram-forcing methodology + od-claude Patrik's 4-pass review (Structure, Implementation, Documentation, Edge Cases)
- For every data flow: trace nil input, empty input, upstream error
- For every interaction: double-click, navigate-away, slow connection, stale state, back button, rapid resubmit, concurrent actions
- Output format: Issues classified as SPECIFIABLE (propose missing text) vs REQUIRES_DECISION (needs PM)

**Agent 4: Customer Expert** (Sonnet)
- Reviews: How well the PRD serves 3 Boards personas:
  1. **Board Members** — Time-poor, low tech fluency, need frictionless access to meeting materials, voting, governance documents
  2. **Customer Admins** — Power users who configure the platform, manage access, handle compliance requirements
  3. **Executives** — Data-driven, need dashboards, reports, action item tracking across multiple boards
- For each feature: which persona benefits? Which is underserved? Which might be confused?
- Output format: Persona coverage matrix + gaps

**Agent 5: QA Expert** (Opus)
- Reviews: Can requirements be turned into discrete, testable, falsifiable acceptance criteria?
- Grades every acceptance criterion: BAD / OK / GOOD (from od-claude enricher)
  - BAD: "Handler works correctly" (not testable)
  - OK: "exports validateToken function" (testable but vague)
  - GOOD: "exports validateToken(token: string): Promise<AuthResult> that returns AuthResult.invalid() for expired tokens" (falsifiable)
- For each feature: describe one realistic scenario where an agent produces wrong output due to spec ambiguity
- Hidden complexity analysis: Can this actually be built with the stated approach?
- Output format: Per-requirement BAD/OK/GOOD grade + failure scenarios + SPECIFIABLE/REQUIRES_DECISION classification

#### Phase 3: Executability Adversarial Pass

**Prompt:** "Think like an agent implementing this PRD without asking any clarifying questions.
Find every point where two competent engineers would build different things."

Adapted from gstack `generateAdversarialStep()` + od-claude enricher:

1. Grade every acceptance criterion: BAD/OK/GOOD
2. For each feature: one realistic failure scenario due to spec ambiguity
3. Trace data flow shadow paths (nil input, empty input, upstream error)
4. Check interaction edge cases (double-click, navigate-away, stale state, concurrent actions)
5. Classify findings: **SPECIFIABLE** (reviewer proposes missing spec text) vs **REQUIRES_DECISION** (needs PM input)

**Auto-scaling** (from gstack adversarial step):
- Small PRD (<20 requirements): Single pass
- Medium PRD (20-50): Two passes (structured + adversarial)
- Large PRD (50+): Three passes (structured + adversarial + cross-reviewer synthesis)

#### Phase 4: Convergence or Escalation

Adapted from gstack convergence guard + od-claude triage table:

1. Aggregate all findings from Phases 2-3
2. Deduplicate: findings flagged by 2+ reviewers = HIGH confidence
3. Apply SPECIFIABLE fixes to PRD directly (propose missing spec text)
4. Present REQUIRES_DECISION items via AskUserQuestion
5. Re-review after fixes (max 3 loops)
6. **Convergence guard:** If same issues recur across iterations, persist as "Reviewer Concerns" section and stop
7. Produce unresolved decision table: `DECISION NEEDED | IF DEFERRED, WHAT HAPPENS`
8. Every finding gets triage disposition: Applied / Captured / Dismissed with reason

### Integration with /prd-writer

Add to `/prd-writer` SKILL.md after current Step 6 (Iterate):

```markdown
### Step 7: Adversarial Review (Optional but Recommended)

After the PRD is drafted and the user is satisfied with the content, offer adversarial review:

"Your PRD is ready for review. Would you like to run an adversarial review?
This spawns 5 independent reviewers who read ONLY the PRD (no prior context)
and probe for ambiguities, gaps, and hidden complexity.

A) Run /prd-review now (Recommended)
B) Skip — I'll review it myself
C) Run later — save PRD first"

If A: Invoke /prd-review skill via Agent tool, passing the PRD file path.
If B: Skip and proceed to final output.
If C: Save PRD, tell user to run `/prd-review <path>` when ready.
```

### Key gstack Patterns Reused

| Pattern | gstack Source | How We Use It |
|---|---|---|
| Spec Review Loop | `review.ts:generateSpecReviewLoop()` | Phase 2 structure (5-dimension review, max 3 iterations) |
| Adversarial Step | `review.ts:generateAdversarialStep()` | Phase 3 (auto-scaled by PRD size) |
| Convergence Guard | `review.ts` | Phase 4 (persist recurring issues as "Reviewer Concerns") |
| Fix-First | `/review` skill | SPECIFIABLE fixes applied directly; REQUIRES_DECISION surfaced to PM |
| BAD/OK/GOOD | od-claude enricher | Phase 2 Agent 5 (QA Expert) acceptance criteria grading |
| Premise Challenge | `/plan-ceo-review` | Phase 1 (3-5 falsifiable claims) |
| First-Impression Framework | `/design-review` | Phase 2 Agent 2 (UX Designer) methodology |
| Diagram-Forcing | `/plan-eng-review` | Phase 2 Agent 3 (EM) hidden assumption detection |
| 6 Forcing Questions | `/office-hours` | Phase 1 (optional deep mode) |
| Confidence Calibration | `confidence.ts` | All phases (1-10 per finding, <5 suppressed) |
| Triage Disposition | od-claude review-integrator | Phase 4 (Applied/Captured/Dismissed) |
| Decision Classification | gstack `/autoplan` | Phase 4 (SPECIFIABLE vs REQUIRES_DECISION) |

---

## Appendix A: gstack Skill Inventory (31 skills)

### Strategy & Planning (5)
| Skill | Specialist | Key Capability |
|---|---|---|
| `/office-hours` | YC Partner | 6 forcing questions, reframes problems, 2 modes (startup/builder) |
| `/plan-ceo-review` | Founder | "10-star product" thinking, 4 modes (expand/selective/hold/reduce), 18 cognitive patterns |
| `/plan-eng-review` | Tech Lead | Diagram-forced architecture review, test plan artifact, hidden assumption detection |
| `/plan-design-review` | Designer | 7-pass interactive design review, rates dimensions 0-10, fixes plan gaps |
| `/autoplan` | Pipeline | Chains CEO→Design→Eng with 6 auto-decision principles |

### Design (4)
| Skill | Specialist | Key Capability |
|---|---|---|
| `/design-consultation` | Design Partner | Build DESIGN.md from scratch, font/color/spacing system, AI slop avoidance |
| `/design-review` | Designer Who Codes | 80-item visual audit + fix loop, AI slop score (A-F), atomic commits |
| `/design-shotgun` | Design Explorer | Generate 3-5 AI mockup variants, comparison board, taste memory |
| `/design-html` | Design Engineer | Approved mockup → production HTML with Pretext text engine |

### QA & Testing (5)
| Skill | Specialist | Key Capability |
|---|---|---|
| `/browse` | QA Engineer | 55-command Playwright CLI, ARIA snapshot + @refs, 100ms/command |
| `/qa` | QA Lead | Diff-aware QA + bug fix + regression test generation, health scoring |
| `/qa-only` | QA Reporter | Same methodology as /qa, report only (no fixes) |
| `/setup-browser-cookies` | Session Manager | Import real browser cookies for authenticated testing |
| `/benchmark` | Performance Engineer | Core Web Vitals tracking, regression detection, trend analysis |

### Shipping & Deploy (5)
| Skill | Specialist | Key Capability |
|---|---|---|
| `/review` | Staff Engineer | Two-pass (critical+informational), Fix-First, confidence-scored, Greptile integration |
| `/ship` | Release Engineer | One-command: merge → test → coverage audit → review → version → CHANGELOG → PR |
| `/land-and-deploy` | Release Engineer | Merge PR → wait CI → deploy → canary verify. Multi-platform. |
| `/canary` | SRE | Post-deploy monitoring loop (console errors, perf regression, visual checks) |
| `/document-release` | Technical Writer | Auto-sync all project docs to match shipped code |

### Utility & Safety (8)
| Skill | Key Capability |
|---|---|
| `/investigate` | 5-phase root-cause debugging with auto-freeze + 3-strike escalation |
| `/retro` | Weekly metrics: per-person breakdown, shipping streaks, test health, session analysis |
| `/codex` | Cross-model review via OpenAI Codex CLI (review/challenge/consult modes) |
| `/cso` | OWASP Top 10 + STRIDE security audit (9 phases, infrastructure-first) |
| `/learn` | Cross-project learning management (search, prune, export, stats) |
| `/careful` | Destructive command warnings (rm -rf, DROP TABLE, force-push) |
| `/freeze` + `/unfreeze` | Directory-scoped edit boundary |
| `/guard` | Combines /careful + /freeze |

### Meta (3)
| Skill | Key Capability |
|---|---|
| `/gstack-upgrade` | Self-update with changelog display |
| `/setup-deploy` | One-time deploy platform detection + config persistence |
| `/connect-chrome` | Headed Chrome with Side Panel extension |

## Appendix B: Key Resolver Functions for /prd-review

These are the exact gstack functions we're adapting:

**`generateSpecReviewLoop()`** (review.ts):
- Dispatches fresh subagent with document path
- Reviews on 5 dimensions: Completeness, Consistency, Clarity, Scope, Feasibility
- Fix + re-dispatch loop (max 3 iterations)
- Convergence guard: persist recurring issues as "Reviewer Concerns"

**`generateAdversarialStep()`** (review.ts):
- Auto-scales by diff/doc size (<50 lines: skip, 50-199: medium, 200+: large)
- Medium: single adversarial pass
- Large: 4 passes (Claude structured + Claude adversarial + Codex structured + Codex adversarial)
- Cross-model synthesis: reinforcing, unique-to-source, conflicting findings

**`generateConfidenceCalibration()`** (confidence.ts):
- 9-10: Verified → show normally
- 7-8: High confidence → show normally
- 5-6: Moderate → show with caveat
- 3-4: Low → suppress, appendix only
- 1-2: Speculation → only if P0

**Design First-Impression Framework** (design.ts):
- "This communicates [X]"
- "I notice [Y]"
- "First 3 things my eye goes to: [1], [2], [3]"
- "One-word verdict: [Z]"

Adapted for PRD: "This PRD communicates [core value]. I notice [distinctive/missing]. The 3 strongest requirements are [1][2][3]. One-word verdict: [clarity level]."

Here's the document converted to markdown:

---

# How gstack Enforces Explicit Skill Invocation

gstack uses a defense-in-depth strategy across 5 layers — no single mechanism is relied on alone.

---

## Layer 1: Routing Table in the Root Skill (`SKILL.md.tmpl:11-31`)

The root gstack `SKILL.md` acts as a routing table that maps user intent → skill name. It's loaded into context on every gstack session:

- Brainstorming a new idea → suggest `/office-hours`
- Reviewing a plan (strategy) → suggest `/plan-ceo-review`
- Debugging errors → suggest `/investigate`
- Ready to deploy / create PR → suggest `/ship`
- ...

This is the primary steering mechanism — Claude sees an explicit mapping and follows it.

---

## Layer 2: Frontmatter Trigger Metadata (per-skill)

Every skill's YAML frontmatter contains "Use when" and "Proactively suggest" phrases that tell Claude Code's harness when to surface the skill. This is enforced by static validation tests:

`test/skill-validation.test.ts:1310-1345` — fails the build if any skill is missing these phrases:

```typescript
const SKILLS_REQUIRING_TRIGGERS = ['qa', 'qa-only', 'ship', 'review', ...];
// Must have "Use when" in frontmatter
expect(frontmatter).toMatch(/Use when/i);
// Must have "Proactively suggest"
expect(frontmatter).toMatch(/Proactively suggest/i);
```

---

## Layer 3: Hard Behavioral Gates (per-skill)

Skills contain explicit "DO NOT" instructions that prevent Claude from inlining adjacent skill behavior:

- `/qa-only`: "Never fix bugs. Find and document only."
- `/review`: "Do NOT make any code changes."
- `/office-hours`: "HARD GATE: Do NOT invoke any implementation skill, write any code..."
- `/ship`: "non-interactive, fully automated workflow. Do NOT ask for confirmation."

These gates prevent **skill bleed** — where one skill starts doing another skill's job.

---

## Layer 4: E2E Routing Tests (`test/skill-routing-e2e.test.ts`)

This is the **runtime enforcement layer**. 12 developer journey scenarios run Claude with natural-language prompts (no `/skill-name` syntax) and assert that:

1. The `Skill` tool was called (not zero calls)
2. The correct skill was routed to

```typescript
const skillCalls = result.toolCalls.filter(tc => tc.tool === 'Skill');
expect(skillCalls.length).toBeGreaterThan(0); // Must invoke via Skill tool
expect([expectedSkill]).toContain(actualSkill); // Must be the RIGHT skill
```

- If Claude answers the question directly without invoking a skill → **test failure**
- If it picks the wrong skill → **test failure**

These tests use realistic prompts like *"The endpoint returns 500 errors, can you figure it out?"* and verify `/investigate` is invoked.

---

## Layer 5: Preamble Injection via Template System (`scripts/gen-skill-docs.ts`)

Every generated `SKILL.md` gets a standardized `{{PREAMBLE}}` block containing:

- **AskUserQuestion format** — standardized interaction protocol
- **Completeness Principle** — always do the full thing, don't shortcut
- **Completion Status Protocol** — `DONE`/`BLOCKED`/`NEEDS_CONTEXT` boundaries
- **Contributor Mode** — self-reflective quality tracking
- **Proactive config** — respects `gstack-config set proactive false`

The template system ensures no skill can diverge from the shared contract. `SKILL.md` files are generated artifacts — hand-editing them would be overwritten on next build.

---

## Supporting Mechanisms

- **Tool allowlisting** in frontmatter (`allowed-tools: [Bash, Read, ...]`) — Claude Code's harness restricts what tools a skill can use
- **Proactive opt-out** (`gstack-config set proactive false`) — users who don't want suggestions can disable them, and the root `SKILL.md` respects this
- **`CLAUDE.md` instructions** — project-level config tells Claude to use gstack skills for browsing/workflows rather than raw tools

---

## What's Missing (Gaps)

The enforcement is strong but has known limitations aligned with the research you shared:

- **No input mediation layer** — there's no "adaptive mediator" rewriting user intent before Claude sees it. The routing table is static, not dynamic.
- **No constraint repetition (SNOWBALL)** — key routing instructions appear once in context, not re-injected per turn. Multi-turn drift could cause Claude to stop routing to skills after many turns.
- **No runtime circuit breaker** — if Claude starts inlining a skill mid-session, there's no real-time detection. The E2E tests catch this in CI, not in production.
- **Context window pressure** — as conversation grows, the routing table and preamble may get compressed/truncated, weakening enforcement.