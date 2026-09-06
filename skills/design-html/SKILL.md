---
name: design-html
preamble-tier: 2
version: 1.1.0
description: |
  Design finalization: generates production-quality Pretext-native HTML/CSS where text
  actually reflows, heights are computed, and layouts are dynamic (30KB, zero deps).
  Smart API routing picks the right Pretext patterns per design type. Works from an
  approved mockup (/design-shotgun), a CEO plan (/plan-ceo-review), design-review context
  (/plan-design-review), or a from-scratch description. Use when asked to "finalize this
  design", "turn this into HTML", "build me a page", "implement this design", or "code the
  mockup". NOT for visual QA of a live site (/design-review) or plan review
  (/plan-design-review). (gstack)
triggers:
  - build the design
  - code the mockup
  - make design real
allowed-tools:
  - Bash
  - Read
  - Write
  - Edit
  - Glob
  - Grep
  - Agent
  - AskUserQuestion
---
<!-- Compressed operational guide. FULL detail (gstack preamble, Pretext wiring patterns,
     API cheatsheet, routing cases) lives in reference.md. Nothing dropped — only relocated. -->

## Runtime preamble (run FIRST)

Execute the gstack runtime preamble in **`reference.md`** (`## Preamble` through
`## Plan Status Footer`): session/telemetry/config bootstrap, plan-mode safety, the
**AskUserQuestion decision-brief format** (mandatory for every question), artifacts sync,
voice, completion-status protocol. Those rules govern this skill.

# /design-html: Pretext-Native HTML Engine

You generate production-quality HTML where text actually works correctly — not CSS
approximations. Computed layout via Pretext: text reflows on resize, heights adjust to
content, cards size themselves, chat bubbles shrinkwrap, editorial spreads flow around
obstacles.

## When to use / NOT

- USE: turn an approved design (mockup PNG, plan, or description) into working HTML/CSS.
- NOT: critiquing a live site (→ /design-review); reviewing a plan's design (→
  /plan-design-review); Angular component implementation (→ /design-implement).

## Setup

**Design binary** (`$D`, optional — enables vision spec extraction) and **browse** (`$B`,
optional — enables viewport verification):
```bash
_ROOT=$(git rev-parse --show-toplevel 2>/dev/null); D=""
[ -n "$_ROOT" ] && [ -x "$_ROOT/.claude/skills/design/dist/design" ] && D="$_ROOT/.claude/skills/design/dist/design"
[ -z "$D" ] && D="$HOME/.claude/skills/design/dist/design"
[ -x "$D" ] && echo "DESIGN_READY: $D" || echo "DESIGN_NOT_AVAILABLE"
B=""; [ -n "$_ROOT" ] && [ -x "$_ROOT/.claude/skills/browse/dist/browse" ] && B="$_ROOT/.claude/skills/browse/dist/browse"
[ -z "$B" ] && B="$HOME/.claude/skills/browse/dist/browse"
[ -x "$B" ] && echo "BROWSE_READY: $B" || echo "BROWSE_NOT_AVAILABLE"
```
`DESIGN_NOT_AVAILABLE` → read the mockup PNG inline instead of `$D prompt`.
`BROWSE_NOT_AVAILABLE` → `open` files instead of `$B` verification. **Design artifacts
save ONLY to `~/.gstack/projects/$SLUG/designs/`**, never project-local. Ground the build
in the UX behavior model (Krug's laws, scanning, hierarchy — full text in reference.md).

## Workflow

### Step 0: Input detection & routing
```bash
eval "$(~/.claude/skills/bin/gstack-slug 2>/dev/null)"
```
Check for context under `~/.gstack/projects/$SLUG/`: `designs/*/approved.json`,
`ceo-plans/*.md`, `designs/*/variant-*.png`, `designs/*/finalized.html`, and repo
`DESIGN.md`. Route (full case logic in reference.md):
- **Case A — `approved.json` exists** (design-shotgun ran): read approved variant +
  feedback + screen name; if prior `finalized.html`, ask evolve vs fresh.
- **Case B — CEO plan / variants but no approval**: read context; ask run /design-shotgun,
  design directly (plan-driven), or provide a PNG path.
- **Case C — nothing**: ask /plan-ceo-review, /plan-design-review, /design-shotgun, or
  "just describe it" (freeform).
Output a context summary: Mode (approved-mockup|plan-driven|freeform|evolve) / visual
reference / CEO plan / design tokens / screen name.

### Step 1: Design analysis
`$D prompt --image <png> --output json` for a structured spec (colors, typography, layout,
components) if `DESIGN_READY`; else Read the PNG and describe it; plan-driven/freeform →
build the spec from plan prose or AskUserQuestion. `DESIGN.md` tokens override system-level
values. Emit an "Implementation spec": colors (hex), fonts (family+weights), spacing scale,
component list, layout type. Real content only — never lorem ipsum.

### Step 2: Pretext tier routing
Classify the design into a tier — each uses different Pretext APIs (table in reference.md):
Simple/Card-grid → `prepare()`+`layout()`; Chat/messaging → `prepareWithSegments()`+
`walkLineRanges()`; Content-heavy → `prepareWithSegments()`+`layoutNextLine()`; Complex
editorial → full engine + `layoutWithLines()`. State the chosen tier and why.

### Step 2.5: Framework detection
`package.json` grep for react/svelte/vue/angular/solid/preact. If found, ask vanilla HTML
(recommended first pass) vs framework component, then TS vs JS. Default: vanilla, no question.

### Step 3: Generate Pretext-native HTML
Write ONE self-contained file to
`~/.gstack/projects/$SLUG/designs/<screen-name>-YYYYMMDD/finalized.html` (framework →
`.tsx|.svelte|.vue`). Embed Pretext: prefer the vendored `skills/design-html/vendor/
pretext.js` inlined in a `<script>`; else CDN `esm.sh/@chenglou/pretext` with a FALLBACK
comment. Framework output → install `@chenglou/pretext` via the detected package manager.
**Always include**: CSS custom-property tokens, Google Fonts + `document.fonts.ready` gate
before first `prepare()`, semantic HTML5, Pretext relayout (not just media queries),
breakpoints 375/768/1024/1440, ARIA + heading hierarchy + focus-visible, `contenteditable`
+ MutationObserver re-prepare, ResizeObserver re-layout, `prefers-color-scheme` +
`prefers-reduced-motion`, real content. **Never** the AI-slop blacklist (purple/blue
gradients, 3-col feature grids, center-everything, decorative blobs, stock-photo divs,
generic CTAs, default rounded-shadow cards, emoji, generic testimonials, cookie-cutter
heroes). **Use the 4 Pretext wiring patterns + API cheatsheet verbatim from reference.md.**

### Step 3.5: Live reload server
`python3 -m http.server 0 --bind 127.0.0.1 &` in the output dir; parse the port; tell the
user the URL and "refresh (Cmd+R) after edits". Fallback `open <file>`. Kill the server
when Step 4 exits.

### Step 4: Preview + refinement loop
If `$B`, screenshot at 375/768/1440 and Read inline; check text overflow, layout collapse,
responsive breakage; fix before presenting. Loop: user opens the page (resize reflows,
click-to-edit recomputes), gives feedback; apply **surgical Edit-tool changes** (never
regenerate — preserves contenteditable edits); brief summary; re-verify. "done"/"ship
it"/"perfect" exits. Max 10 iterations, then ask continue vs done.

### Step 5: Save & next steps
Offer to extract a `DESIGN.md` from the HTML tokens if none exists. Write `finalized.json`
metadata (source mockup/plan, mode, html file, pretext_tier, framework, iterations, date,
screen, branch). Ask next: copy into codebase / iterate more / done.

## Common traps

- **Source-of-truth fidelity over code elegance** — when a mockup exists, pixel-match it
  (`width: 312px` beats a grid class). Feedback is truth in plan-driven/freeform mode.
- **Always use Pretext** even for simple designs — correct height on resize; 30KB, worth it.
- **Surgical edits** in the loop (Edit, not Write) — the user may have edited via contenteditable.
- **Real content only** — extract from mockup / plan / description; never placeholder text.
- **One page per invocation** — multi-page designs run /design-html once per page.

## Related skills

/design-shotgun (explore variants → approved.json) · /plan-design-review (review plan
design) · /design-review (visual QA of the built site) · /design-implement (Angular).
**Full reference: `reference.md`.**
