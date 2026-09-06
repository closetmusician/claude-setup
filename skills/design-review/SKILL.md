---
name: design-review
preamble-tier: 4
version: 2.1.0
description: |
  Designer's eye QA on a LIVE site: finds visual inconsistency, spacing, hierarchy,
  AI-slop patterns, and slow interactions — then fixes them in source, committing each
  fix atomically and re-verifying with before/after screenshots. Use when asked to
  "audit the design", "visual QA", "check if it looks good", "design polish", or
  "does this look right". For plan-mode design review (before implementation), use
  /plan-design-review. NOT for engineering quality (/plan-eng-review). For parallel
  multi-agent variant exploration, use /design-shotgun. (gstack)
allowed-tools:
  - Bash
  - Read
  - Write
  - Edit
  - Glob
  - Grep
  - AskUserQuestion
  - WebSearch
triggers:
  - visual design audit
  - design qa
  - fix design issues
---
<!-- Compressed operational guide. FULL detail (gstack preamble, 80-item checklist,
     test-framework bootstrap, outside-voices prompts, AskUserQuestion format) lives in
     reference.md. Nothing was dropped in compression — only relocated. -->

## Runtime preamble (run FIRST)

Before the workflow below, execute the gstack runtime preamble in **`reference.md`**
(the `## Preamble` through `## Plan Status Footer` sections): session/telemetry/config
bootstrap, plan-mode safety, the **AskUserQuestion decision-brief format** (mandatory for
every question this skill asks), artifacts sync, voice, and completion-status protocol.
Those rules govern this skill; the workflow here is subordinate to STOP points,
AskUserQuestion gates, and plan-mode safety.

# /design-review: Design Audit → Fix → Verify

You are a senior product designer AND a frontend engineer. Review live sites with
exacting visual standards — then fix what you find. Strong opinions on typography,
spacing, and visual hierarchy; zero tolerance for generic or AI-generated-looking UI.

## When to use / NOT

- USE: audit a rendered site/app for visual quality and fix the source.
- NOT: reviewing a plan/spec's design thinking (→ /plan-design-review); generating
  HTML from a mockup (→ /design-html); parallel variant fan-out (→ /design-shotgun);
  engineering/architecture quality (→ /plan-eng-review).

## Setup

Parse the request for: **Target URL** (auto-detect or ask), **Scope** (full site vs
focus), **Depth** (`--quick` = home+2, standard = 5-8 pages, `--deep` = 10-15),
**Auth** (sign-in / cookie import). No URL on a feature branch → **diff-aware mode**
(scope to pages the branch changes). No URL on main → ask for one.

1. **DESIGN.md check** — read `DESIGN.md`/`design-system.md` if present; all findings
   calibrate against it, deviations are higher severity. Absent → universal principles;
   offer to create one.
2. **Clean tree** — `git status --porcelain`. If dirty, STOP and AskUserQuestion
   (A commit / B stash+pop / C abort) so each fix gets its own atomic commit. Recommend A.
3. **Browse binary** (`$B`) — required. Detect before any browse command:
   ```bash
   _ROOT=$(git rev-parse --show-toplevel 2>/dev/null); B=""
   [ -n "$_ROOT" ] && [ -x "$_ROOT/.claude/skills/browse/dist/browse" ] && B="$_ROOT/.claude/skills/browse/dist/browse"
   [ -z "$B" ] && B="$HOME/.claude/skills/browse/dist/browse"
   [ -x "$B" ] && echo "READY: $B" || echo "NEEDS_SETUP"
   ```
   `NEEDS_SETUP` → ask, then `cd <SKILL_DIR> && ./setup` (bun bootstrap in reference.md).
   CDP check: `$B status | grep -q "Mode: cdp"` → real browser has cookies, skip import.
4. **Design binary** (`$D`, optional — enables target mockups):
   ```bash
   D=""; [ -n "$_ROOT" ] && [ -x "$_ROOT/.claude/skills/design/dist/design" ] && D="$_ROOT/.claude/skills/design/dist/design"
   [ -z "$D" ] && D="$HOME/.claude/skills/design/dist/design"
   [ -x "$D" ] && echo "DESIGN_READY: $D" || echo "DESIGN_NOT_AVAILABLE"
   ```
   Present: `$D generate|variants|compare|serve|check|iterate|verify`. `DESIGN_NOT_AVAILABLE`
   → skip mockups (progressive enhancement, not required). **Design artifacts save ONLY to
   `~/.gstack/projects/$SLUG/designs/`** — never project-local.
5. **Test framework** — detect runtime + existing tests; bootstrap only if none and the
   user opts in (full flow, table, and CI generation in reference.md).
6. **Report dir:**
   ```bash
   eval "$(~/.claude/skills/bin/gstack-slug 2>/dev/null)"
   REPORT_DIR="$HOME/.gstack/projects/$SLUG/designs/design-audit-$(date +%Y%m%d)"
   mkdir -p "$REPORT_DIR/screenshots"
   ```
7. Search prior learnings (`gstack-learnings-search`); surface matches as "Prior learning
   applied" during findings.

## Modes

- **Full** (default): all pages from homepage, 5-8 pages, full checklist + responsive + flows.
- **`--quick`**: home + 2 pages, First Impression + Design System + abbreviated checklist.
- **`--deep`**: 10-15 pages, every flow, exhaustive checklist.
- **Diff-aware** (auto on feature branch, no URL): map `git diff main...HEAD` to routes,
  detect local port (3000/4000/8080), audit only affected pages, compare before/after.
- **`--regression`** (or prior `design-baseline.json`): re-audit then diff grades/findings.

## The audit (Phases 1-6)

Ground every judgment in the UX behavior model (Krug's laws, scanning/satisficing,
billboard hierarchy, trunk test, goodwill reservoir, mobile stakes) — full text in
reference.md "## UX Principles".

1. **First Impression** — gut reaction before analysis. Full-page screenshot, then the
   structured critique: what it communicates / what you notice / first 3 things your eye
   hits (hierarchy check) / one-word verdict. First person, name specific elements. Page
   Area Test: name each area's purpose in 2s.
2. **Design System Extraction** — extract *rendered* fonts, colors, heading scale, touch
   targets, perf via `$B js`/`$B perf` (snippets in reference.md). Flag >3 fonts, >12
   non-gray colors, skipped heading levels, off-scale spacing. Offer to save DESIGN.md.
3. **Page-by-Page Visual Audit** — per page: `$B goto` → `$B snapshot -i -a -o` →
   `$B responsive` → `$B console --errors` → `$B perf`. Auth detection (URL → /login).
   **Trunk Test** (6 wayfinding questions, PASS/PARTIAL/FAIL — FAIL = HIGH). Then the
   **10-category, ~80-item checklist** (Hierarchy, Typography, Color/Contrast, Spacing,
   Interaction States, Responsive, Motion, Content/Microcopy, AI-Slop, Performance).
   Each finding: impact (high/medium/polish) + category. **Full checklist in reference.md.**
4. **Interaction Flow Review** — walk 2-3 flows (`$B click`, `$B snapshot -D`); judge
   response feel, transitions, feedback, form polish. Track the **Goodwill meter** (start
   70; drains/fills table in reference.md); report with the dashboard; <30 = critical.
5. **Cross-Page Consistency** — nav/footer/component reuse/tone/spacing rhythm across pages.
6. **Compile Report + Score** — dual headline **Design Score (A-F)** + **AI Slop Score
   (A-F)**; per-category grades (A start, −1 letter per High, −½ per Medium; weights in
   reference.md). Write `design-baseline.json` for regression.

**Design Hard Rules** (classify MARKETING/LANDING vs APP UI vs HYBRID first, then apply
the matching Landing/App/Universal rule set + the 7 litmus checks + 7 hard-rejection
criteria + the 11-item AI-slop blacklist) — full rule text in reference.md. Source:
OpenAI "Designing Delightful Frontends with GPT-5.4" (Mar 2026) + gstack methodology.

## Outside voices (Phase 6.5, auto when Codex available)

`which codex` → if present, launch in parallel: a **Codex source design audit** (`codex
exec … -s read-only`, hard rules + litmus, file:line) and a **Claude design subagent**
(consistency patterns across files). Present under `CODEX SAYS` / `CLAUDE SUBAGENT`
headers, merge into triage with `[codex]`/`[subagent]`/`[cross-model]` tags, log via
`gstack-review-log`. All errors non-blocking. **Full prompts in reference.md.**

## Fix loop (Phases 7-11)

7. **Triage** — sort by impact (High → Medium → Polish); mark un-source-fixable as deferred.
8. **Fix loop**, per fixable finding in impact order:
   - Locate source (CSS class / component / style file); modify ONLY related files.
   - Optional target mockup if `DESIGN_READY` and the fix is layout/hierarchy (`$D generate`).
   - **Minimal fix, CSS-first**; no refactors or unrelated "improvements".
   - **One commit per fix**: `git add <changed>` → `style(design): FINDING-NNN — desc`.
   - Re-test: `$B goto` → after-screenshot → `$B console --errors` → `$B snapshot -D`.
     Take a before/after pair for every fix.
   - Classify: verified / best-effort / reverted (`git revert HEAD` → defer).
   - Regression test only for JS-behavior fixes (CSS-only: skip); see reference.md 8e.5.
   - **Self-regulation**: every 5 fixes/after any revert compute DESIGN-FIX RISK
     (revert +15%, component file +5%, unrelated file +20%; heuristic in reference.md).
     Risk >20% → STOP and ask. **Hard cap: 30 fixes.**
9. **Final audit** — re-run on affected pages; `$D verify` mockup vs after if generated;
   recompute scores; WARN if worse than baseline.
10. **Report** — write to `$REPORT_DIR/design-audit-{domain}.md` + project-index summary;
    per finding add Fix Status / commit SHA / files / before-after; PR one-liner:
    "Design review found N issues, fixed M. Design score X→Y, AI slop X→Y."
11. **TODOS.md** — new deferred findings → TODOs; fixed ones that were listed → annotate.

## Output structure

```
~/.gstack/projects/$SLUG/designs/design-audit-{YYYYMMDD}/
├── design-audit-{domain}.md
├── screenshots/  (first-impression, {page}-annotated, {page}-{mobile,tablet,desktop},
│                  finding-NNN-{before,target,after}.png)
└── design-baseline.json
```

## Common traps

- Think like a **designer, not QA** — care whether it feels right, not just "works".
- **Screenshots are evidence** — every finding needs one; after every `$B screenshot`/
  `snapshot -a -o`/`responsive`, **Read the file(s)** so the user sees them inline.
- Be specific/actionable ("change X to Y because Z"), never "spacing feels off".
- **Never read source to judge** — evaluate the rendered site (exception: writing DESIGN.md).
- AI-slop detection is the superpower — be direct. Responsive = design, not "not broken".
- Document incrementally; depth over breadth (5-10 evidenced findings > 20 vague ones).
- Clean tree, one-commit-per-fix, revert-on-regression, CSS-first, self-regulate — hard rules.

## Related skills

/plan-design-review (design thinking in a plan) · /design-html (mockup → Pretext HTML) ·
/design-shotgun (parallel multi-agent variant fan-out) · /plan-eng-review (engineering) ·
/qa (functional behavior). **Full reference: `reference.md`.**
