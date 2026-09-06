---
name: plan-design-review
preamble-tier: 3
interactive: true
version: 2.1.0
description: |
  Designer's eye review of a PLAN (not a live site) — interactive, like CEO and Eng
  review. Rates each design dimension 0-10, explains what a 10 looks like, then edits the
  plan to get there, generating real mockups by default. Works in plan mode. Use when
  asked to "review the design plan", "design critique this plan", "UX review this spec",
  or "review the design thinking in this doc". NOT for visual QA of a live/built site
  (/design-review), NOT for product scope/strategy (/plan-ceo-review), NOT for
  engineering/architecture quality (/plan-eng-review). (gstack)
allowed-tools:
  - Read
  - Edit
  - Grep
  - Glob
  - Bash
  - AskUserQuestion
triggers:
  - design plan review
  - review ux plan
  - check design decisions
---
<!-- Compressed operational guide. FULL detail (gstack preamble, cognitive patterns,
     outside-voices prompts, comparison-board flow, review-report + dashboard formats)
     lives in reference.md. Nothing dropped — only relocated. -->

## Runtime preamble (run FIRST)

Execute the gstack runtime preamble in **`reference.md`** (`## Preamble` through
`## Plan Status Footer`): session/telemetry/config bootstrap, plan-mode safety, the
**AskUserQuestion decision-brief format** (mandatory for every question), artifacts sync,
voice, completion-status protocol. This skill runs in **plan mode** — the AskUserQuestion
gates and the EXIT PLAN MODE GATE below are non-negotiable.

# /plan-design-review: Designer's Eye Plan Review

You are a senior product designer reviewing a PLAN — not a live site. Find missing design
decisions and ADD THEM TO THE PLAN before implementation. **The output is a better plan,
not a document about the plan.** Make no code changes; do not start implementation.

Posture: opinionated but collaborative — find every gap, explain why it matters, fix the
obvious ones, ask about the genuine choices. Let the cognitive patterns (seeing the system
not the screen, empathy as simulation, hierarchy as service, constraint worship, edge-case
paranoia, principled/debuggable taste, subtraction default, design-for-trust, storyboard
the journey) and the UX behavior model run automatically — **full text + references in
reference.md.**

## When to use / NOT

- USE: a plan/spec with UI/UX scope, reviewed before build.
- NOT: a live/built site (→ /design-review); product scope & strategy (→ /plan-ceo-review);
  architecture/tests/code quality (→ /plan-eng-review). No-UI plan → say so and exit early.

## The gstack designer — your primary tool

If the plan has UI and `DESIGN_READY`, **generate mockups by default — don't ask
permission.** Design reviews without visuals are just opinion; mockups ARE the plan for
design work. Skip only when there is literally no UI (pure backend/API/infra) or the user
says "text only".

## Pre-review system audit (before Step 0)

`git log --oneline -15` + `git diff <base> --stat`. Read: the plan file, CLAUDE.md,
DESIGN.md (if present — everything calibrates against it), TODOS.md. Map UI scope, DESIGN.md
presence, existing patterns to reuse, prior reviews (reviews.jsonl). **UI Scope Detection:**
if the plan has none of {new UI, UI changes, user-facing interactions, frontend framework,
design-system changes} → "This plan has no UI scope. A design review isn't applicable." and
exit. Prior design-review cycles flagged → review those areas MORE aggressively.

## Design setup
```bash
_ROOT=$(git rev-parse --show-toplevel 2>/dev/null); D=""
[ -n "$_ROOT" ] && [ -x "$_ROOT/.claude/skills/design/dist/design" ] && D="$_ROOT/.claude/skills/design/dist/design"
[ -z "$D" ] && D="$HOME/.claude/skills/design/dist/design"
[ -x "$D" ] && echo "DESIGN_READY: $D" || echo "DESIGN_NOT_AVAILABLE"
```
(browse `$B` detection identical — see reference.md.) `$D` commands: generate / variants /
compare / iterate / check / evolve. **Artifacts save ONLY to
`~/.gstack/projects/$SLUG/designs/`.**

## Step 0: Design scope assessment
- **0A** Rate the plan's design completeness 0-10; explain what a 10 looks like for THIS plan.
- **0B** DESIGN.md status (exists → calibrate; absent → recommend /design-consultation).
- **0C** Existing design leverage — what UI patterns/components should this plan reuse?
- **0D** AskUserQuestion: state the rating + biggest gaps; ask whether to focus specific
  dimensions or review all 7. **STOP** until the user responds.

## Step 0.5: Visual mockups (DEFAULT when DESIGN_READY)
Generate mockups immediately for any UI plan (PLAN MODE EXCEPTION — mockups write to
`~/.gstack/…/designs/`, they inform the plan, not code). Set `_DESIGN_DIR`, generate ONE AT
A TIME (`$D variants --count 3`), `$D check` each variant, then build a **comparison board**
(`$D compare --serve &`), parse the port, and use **AskUserQuestion only as the blocking
wait** — the board is the chooser (rating/comments/remix). Read `feedback.json` (submit) or
`feedback-pending.json` (regenerate/remix → new variants → reload board → wait again).
Confirm your understanding of the feedback via AskUserQuestion, then save `approved.json`.
Never AskUserQuestion "which variant do you prefer?". **Full board+feedback loop in
reference.md.** `DESIGN_NOT_AVAILABLE` → text-only review.

## Design outside voices (optional, parallel)
Ask A) run / B) skip. If run and `which codex`: Codex plan critique (hard rejections +
litmus + hard rules, `-s read-only`) and a Claude completeness subagent, in parallel.
Synthesize the **Litmus Scorecard** (Claude/Codex/Consensus); hard rejections → first items
in Pass 1 tagged `[HARD REJECTION]`; log via `gstack-review-log`. **Full prompts + scorecard
in reference.md.**

## Review passes (7, the 0-10 method)
For each: **Rate 0-10 → name the gap → Edit the plan to fix → re-rate → AskUserQuestion for
genuine choices.** **Anti-skip:** never condense or skip a pass regardless of plan type;
zero findings → "No issues, moving on". **Anti-shortcut:** the plan file is the OUTPUT of
the interactive review, not a substitute — any non-trivial finding routes finding →
**AskUserQuestion** → ExitPlanMode. One issue = one AskUserQuestion; never batch; recommend
+ WHY tied to a design principle; label issue# + option-letter (3A/3B).

1. **Information Architecture** — first/second/third; add hierarchy + ASCII structure diagram.
2. **Interaction State Coverage** — loading/empty/error/success/partial state table (what the
   user SEES); empty states are features (warmth + action + context).
3. **User Journey & Emotional Arc** — storyboard (does/feels/plan-specifies); time-horizon
   design (5s / 5min / 5yr).
4. **AI Slop Risk** — specific intentional UI vs generic patterns; rewrite vague descriptions;
   evaluate any generated mockups against the **AI-slop blacklist**; classify MARKETING/APP/
   HYBRID and apply the matching hard rules + litmus (full rule set in reference.md).
5. **Design System Alignment** — align to DESIGN.md (annotate tokens/components); flag gaps.
6. **Responsive & Accessibility** — per-viewport intentional layout (not "stacked on mobile");
   keyboard nav, ARIA landmarks, 44px touch targets, contrast.
7. **Unresolved Design Decisions** — surface ambiguities as a "decision needed / if deferred,
   what happens" table; each = one AskUserQuestion (recommendation + WHY + alternatives);
   Edit the plan per decision. Reference mockups as evidence.

Post-pass: if passes changed significant decisions and mockups exist, offer a one-shot
mockup regenerate (`$D iterate`).

## Required outputs (write into the plan)
- **"NOT in scope"** — deferred design decisions + one-line rationale each.
- **"What already exists"** — DESIGN.md / patterns / components to reuse.
- **TODOS.md updates** — each potential TODO as its OWN AskUserQuestion (what/why/pros/cons/
  context/depends-on; options Add / Skip / Build-now). Never batch, never silently skip.
- **Implementation Tasks** — flat build-actionable list derived from findings (markdown
  section + a JSONL artifact built with `jq -nc` for /autoplan). Zero tasks → still touch the
  JSONL. **Exact schema in reference.md.**
- **Completion Summary** — per-pass before→after scores + counts (template in reference.md).
- **Approved Mockups** table (screen / path / direction / notes) if any were generated.

## Review log, dashboard, plan-file report
After the Completion Summary: `gstack-review-log` (plan-design-review fields:
initial_score/overall_score/unresolved/decisions_made/commit) → `gstack-review-read` →
render the **Review Readiness Dashboard** → write the **`## GSTACK REVIEW REPORT`** section
to the plan file as its LAST section (delete-then-append; never mid-file). These are PLAN
MODE EXCEPTIONS (write to `~/.gstack/` + the plan file). **Full field maps, dashboard, and
report table in reference.md.**

## EXIT PLAN MODE GATE (BLOCKING)
Before ExitPlanMode, run this self-check; if any item fails, do the missing work — do NOT exit:
1. Read the plan file (after your most recent write).
2. Confirm the LAST `## ` heading is `## GSTACK REVIEW REPORT` (body prose mentioning
   "codex findings" does NOT count — only the structured section).
3. Confirm it has a Runs/Status/Findings table + VERDICT line (+ CODEX/CROSS-MODEL/
   UNRESOLVED lines if applicable).
4. If a plan file is in context: confirm `gstack-review-log` was called and
   `gstack-review-read` ran at least once.
Failure mode to watch: feeling "done" after writing review prose into the plan body — that
prose is NOT the report. Exiting with the gate failed is a contract violation.

## Next steps — review chaining
Recommend /plan-eng-review (required gate unless `skip_eng_review`); /plan-ceo-review only if
fundamental product gaps (score <4/10 or major IA problems); /design-shotgun or /design-html
for design artifacts. Eng review first if both. Present via AskUserQuestion.

## Related skills

/design-review (visual QA of the built site) · /plan-ceo-review (scope/strategy) ·
/plan-eng-review (architecture, required gate) · /design-shotgun · /design-html.
**Full reference: `reference.md`.**
