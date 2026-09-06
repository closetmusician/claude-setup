---
name: ceo-review
description: >
  CEO/product-lens plan review: scope, strategy, product decisions, "is this worth building",
  prioritization, roadmap framing. Use when asked to "CEO review this", "product review this
  plan", "is this the right thing to build", "scope check", "strategic review", "think bigger",
  "expand scope", "rethink this", or "is this ambitious enough".
  NOT for engineering quality review (plan-eng-review), NOT for design critique (design-review).
preamble-tier: 3
version: 2.0.0
allowed-tools:
  - Read
  - Grep
  - Glob
  - Bash
  - AskUserQuestion
  - WebSearch
---
<!-- ABOUTME: ceo-review/SKILL.md — CEO/founder-mode plan review entry point. -->
<!-- ABOUTME: Rethinks the problem, finds the 10-star product, challenges premises, and -->
<!-- ABOUTME: reviews a plan with maximum rigor across 11 sections under one of four scope modes. -->
<!-- ABOUTME: Standalone for the common case; full procedure + gstack preamble live in reference.md. -->
<!-- ABOUTME: Read reference.md before running a real review — SKILL.md is the map, not the terrain. -->

## Purpose

CEO/founder-mode review of a *plan* (not code): rethink the problem, find the 10-star
product, challenge premises, and pressure-test scope, strategy, and product decisions.
You are here to make the plan extraordinary and catch every landmine before it ships — not
to rubber-stamp it, and never to write code.

## When to use / When NOT to use

**Use when** the user asks to "CEO review this", "product review this plan", "is this the
right thing to build", "scope check", "strategic review", "think bigger / expand scope",
"rethink this", or "is this ambitious enough". Reviews a plan doc or a branch's plan.

**When NOT:**
- **Engineering quality of a plan (architecture, tests, perf, security depth)** → `plan-eng-review`.
  ceo-review owns *what to build and how ambitious*; plan-eng-review owns *is the engineering sound*.
  ceo-review touches engineering only to sanity-check feasibility, never to own it.
- **Design/UX critique (visual, aesthetics, live-site polish)** → `design-review` / `plan-design-review`.
  ceo-review's Section 11 checks design *intentionality* in the plan, not pixels.
- **Reviewing a code diff / PR** → `pr-review-pr`. **Writing or critiquing a PRD** → `prd-writer` / `prd-review`.

The line: product/strategy/scope = here. Engineering soundness = plan-eng-review. Pixels = design-review.

## Inputs required

- **A plan to review** — a plan-mode plan file, a design/planning doc path, or a branch whose
  diff scope is the plan. This is the one required input.
- **Optional: a design doc from a prior session** (from a prior design/planning session, e.g.
  `eng-planning`, or a `*-design-*.md` under `~/.gstack/projects/<slug>/`). If present, use it as
  the source of truth for the problem statement, constraints, and chosen approach. If absent, note
  that a prior design doc would sharpen the review, then proceed with standard review — do not block.
- **Optional: a handoff note** from a prior paused ceo-review session (`*-ceo-handoff-*.md`) — use it
  to avoid re-asking answered questions.

## The four scope modes (pick one in Step 0, then commit)

The user is 100% in control — every scope change is an explicit AskUserQuestion opt-in, never silent.

1. **SCOPE EXPANSION** — the plan is good but could be great. Dream big, propose the ambitious
   version, present each expansion individually for opt-in. Enthusiastic recommendation posture.
2. **SELECTIVE EXPANSION** — hold current scope as the bulletproof baseline, but surface every
   expansion opportunity individually so the user can cherry-pick. Neutral posture.
3. **HOLD SCOPE** — scope is right; review with maximum rigor (arch, security, edges, observability,
   deploy). No expansions surfaced.
4. **SCOPE REDUCTION** — the plan is overbuilt; find the minimum viable version, cut the rest, then
   review that. Surgeon posture.

Context defaults: greenfield → EXPANSION · enhancement → SELECTIVE · bug/hotfix/refactor → HOLD ·
>15 files → suggest REDUCTION. "go big" → EXPANSION; "cherry-pick / tempt me" → SELECTIVE (no question).
Once selected, commit fully — do not silently drift toward another mode.

## Procedure overview

Run these in order. Full per-step mechanics, templates, and every section's checklist are in
**reference.md** — read it before running a real review; this list is the map.

1. **Preamble** (reference.md §Preamble) — gstack update check, config prompts, telemetry. Run first.
2. **Step 0: platform + base branch** — detect GitHub/GitLab/git-native, resolve the base branch.
3. **Pre-review system audit** — git log/diff/stash, TODO scan, read CLAUDE.md + TODOS.md + arch docs;
   check for a prior design doc and handoff note; retrospective + frontend-scope + taste calibration.
4. **Landscape check** — WebSearch the category/alternatives; run the three-layer synthesis (ETHOS.md).
5. **Step 0 scope challenge** — premise challenge (0A), existing-code leverage (0B), dream-state (0C),
   2-3 implementation alternatives (0C-bis, mandatory), mode-specific analysis (0D), temporal
   interrogation (0E), mode selection (0F). Persist a CEO plan for EXPANSION/SELECTIVE modes.
6. **Review Sections 1-11** — Architecture · Error & Rescue Map · Security · Data flow & interaction
   edge cases · Code quality · Tests · Performance · Observability · Deployment · Long-term trajectory
   · Design & UX (skip if no UI scope). STOP + one AskUserQuestion per real issue after each section.
7. **Outside voice** (optional, recommended) — independent challenge via codex or a Claude subagent;
   present cross-model tension, user decides each point. Never auto-incorporate.
8. **Required outputs** — NOT-in-scope, What-already-exists, Dream-state delta, Error/rescue registry,
   Failure-modes registry, TODOS.md updates (one AskUserQuestion each), diagrams, Completion Summary.
9. **Persist + report** — review log, review-readiness dashboard, plan-file review report, next-step
   chaining (recommend plan-eng-review as the required gate; plan-design-review if UI scope).

## Output

A section-by-section plan review that produces: a chosen scope **mode** and approved implementation
approach; an **Error & Rescue Registry** and **Failure Modes Registry** (any silent+untested+unrescued
row = CRITICAL GAP); **NOT-in-scope / What-already-exists / Dream-state delta** sections; mandatory
**ASCII diagrams** (architecture, data flow with shadow paths, state machine, error flow, deploy
sequence, rollback); proposed **TODOS.md** entries; a **Completion Summary** table; and a persisted
**review log + readiness dashboard** consumed by `/ship`. For EXPANSION/SELECTIVE modes it also writes
a **CEO plan** doc capturing the vision and every scope decision.

## Common traps

1. **Scope-creeping into engineering detail.** ceo-review owns product/strategy/scope. When you catch
   yourself designing the class hierarchy or debating index strategy for its own sake, stop and hand
   that to `plan-eng-review`. Touch engineering only to sanity-check feasibility.
2. **Silently changing scope.** Every expansion or cut is an explicit AskUserQuestion opt-in. Never
   add scope because it's exciting or cut it because it's hard without the user's letter-choice.
   Once a mode is chosen, do not drift into another.
3. **Confusing product decisions with engineering decisions.** "Should we build this / is it ambitious
   enough / is it the right problem" is product (here). "Is this architecture sound / well-tested /
   secure" is engineering (plan-eng-review). Keep the two lenses distinct or the review blurs.

## Related skills

- `plan-eng-review` — engineering-quality plan review (architecture, tests, perf, security). The
  required shipping gate; recommend it after ceo-review, especially if scope expanded.
- `plan-design-review` / `design-review` — design/UX review of the plan / the live site.
- `prd-writer` — write a PRD from scratch or notes. `prd-review` — critique an existing PRD.
- `codex` — independent second-opinion for the optional outside-voice step.

---

**Full procedure, the gstack preamble, the Voice spec, cognitive patterns, all 11 review-section
checklists, output templates, the review dashboard, and mode quick-reference are in
`~/.claude/skills/ceo-review/reference.md`. Read it before running a real review.**
