---
name: prototype-guide
description: "Prototype tiers, design token querying, screen generation, anti-bloat rules — read at Step 4.1b"
---

# Prototype Guide

This reference defines how the agent generates, publishes, and iterates on lightweight visual prototypes during Step 4.1b of the Product Research Workflow. It is also read by the standalone prototype skill.

---

## UX Principles

### The Three Laws

1. **Don't make me think.** Every screen should be self-evident.
2. **Clicks don't matter, thinking does.** Three mindless clicks beat one that requires thought.
3. **Omit, then omit again.** Every element must earn its space.

### How Users Actually Behave

* **Users scan, they don't read.** Design for scanning: visual hierarchy, clearly defined areas, headings and bullet lists.
* **Users satisfice.** They pick the first reasonable option, not the best.
* **Users muddle through.** They don't figure out how things work — they wing it.
* **Users don't read instructions.** They dive in.

### Billboard Design for Interfaces

* **Use conventions.** Logo top-left, nav top/left, search = magnifying glass.
* **Visual hierarchy is everything.** More important = more prominent.
* **Make clickable things obviously clickable.**
* **Eliminate noise.** Fix by removal, not addition.
* **Clarity trumps consistency.**

---

## Prototype Tiers

| Tier | When to use | What the agent produces |
| --- | --- | --- |
| **Wireframe** | Simple flow, 1-2 screens | Gray-box layouts with spacing and typography tokens. No color. |
| **Lo-fi mockup** | Most initiatives (default) | Design system colors, real component shapes, key states (default, empty, error, loading). |
| **Interactive click-through** | Complex multi-step flows | Lo-fi mockup + vanilla JS for navigation, state changes, simulated data. |

**Default tier**: Lo-fi mockup.

---

## Query Design Tokens (with Cache)

Before generating any HTML, query your design system for current tokens.

### Primary path — Design system API available

1. **Color tokens** — background, text, border, interactive, status
2. **Typography tokens** — font family, size, weight, line height
3. **Spacing tokens** — spacing scale
4. **Border radius tokens**
5. **Shadow tokens**
6. **Component patterns** — available components and their docs

**After every successful query**, cache tokens to `docs/product/prototypes/.design-token-cache.json`.

### Fallback path — Design system API unavailable

1. Check for cache file. Use cached tokens if available.
2. If no cache, fall back to **Material UI (MUI)** defaults. Use MUI's standard theme tokens for colors, typography, spacing, and components. This ensures prototypes still look professional and consistent without custom design system access.

---

## HTML Generation Spec

### Structure

* Standalone `.html` with all CSS inlined
* Semantic HTML5 (`<header>`, `<nav>`, `<main>`, `<section>`, `<footer>`)
* CSS grid/flexbox layout, no framework dependencies
* Design tokens (or MUI defaults) as CSS custom properties in `:root`

### Responsive and Accessible

* `contenteditable` on text elements for stakeholder editing
* `ResizeObserver` on key containers
* `prefers-color-scheme` media query for dark mode
* `prefers-reduced-motion` media query
* ARIA attributes on interactive elements
* Heading hierarchy reflecting content structure
* Focus-visible states on all interactive elements

### Content Rules

* **Real, domain-appropriate content only.** Never "Lorem ipsum" or "Your text here".
* Use realistic but clearly fake data.
* Content should match the product domain and persona context.

### AI Slop Blacklist — Never Generate These

* Purple/blue gradients as default backgrounds
* Generic 3-column feature grids
* Center-everything layouts with no visual hierarchy
* Decorative blobs, waves, or geometric patterns
* Stock photo placeholder divs
* Generic CTAs ("Get Started", "Learn More") not from source material
* Rounded-corner cards with drop shadows as default for everything
* Emoji as visual design elements
* Cookie-cutter hero sections

---

## Generate Prototype Screens

### Mode A — With codebase access

1. Search the frontend codebase for related screens and components.
2. Match the product — use existing screens as the primary visual reference.
3. Generate screens grounded in existing code.

### Mode B — Without codebase access

1. Request or reference screenshots/exports of existing product pages.
2. Generate standalone protos using design system component approach.

### For both modes:

1. Map must-have solutions from Solution Synthesis to distinct screens.
2. Generate standalone HTML files with annotation layer and navigation hints.
3. Create flow index page (`index.html`).

**File structure:**

```
docs/product/prototypes/{initiative-slug}/
  ├── index.html
  ├── screen-01-entry.html
  ├── screen-02-main-flow.html
  └── ...
```

---

## Interaction Patterns (Click-Through Tier)

### Zone Inventory
Scan HTML for interactive zones: card grids, search inputs, sidebars, notifications, navigation, action buttons, tabs/filters, expandable sections, overlay triggers.

### Implementation Rules

1. Event delegation on `document`
2. CSS transitions (200-300ms ease) for expand/collapse
3. `requestAnimationFrame` for open animation
4. Collapse-before-expand
5. Panels match existing theme
6. Preserve contenteditable
7. No external dependencies
8. JS budget: under 300 lines (simple) / 500 lines (complex)

---

## Anti-Bloat Rules

1. No JavaScript frameworks — Vanilla JS only, click-through tier only
2. No real data fetching
3. No build steps — files open directly in browser
4. No pixel perfection — layout, flow, and state coverage over polish
5. Max 8 screens per initiative

---

## Capture and Publish

1. Open each screen in Playwright and take screenshots (1440x900 desktop, 768x1024 tablet)
2. Write a prototype summary file with overview, screenshots, flow diagram, state coverage table
3. Update the Workflow Summary file

---

## Checkpoint

> Prototype is complete and published: [link].
> Generated [N] screens at [tier] level.
> Do you want to review or adjust? Say 'continue' when ready for the PRD.

**WAIT FOR RESPONSE** before proceeding.

---

## Iteration Model

Max 3 rounds of feedback before proceeding to PRD. Replace screens in place. Re-capture screenshots.

---

## Design Handoff

When a designer creates proper design tool mocks:
1. Add a note to the prototype summary file linking to the design file
2. Keep original prototypes as reference
3. Update PRD file references to point to design frames
