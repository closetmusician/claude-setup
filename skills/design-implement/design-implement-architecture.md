# /design-implement Skill Architecture

Translates approved HTML mocks from `/design-html` into real Angular components within the `boards-cloud-client` NX monorepo.

---

## 1. Skill Interface

```
/design-implement <html-path> [options]
```

### Required Arguments

| Arg | Description | Example |
|-----|-------------|---------|
| `html-path` | Path to the approved HTML mock | `samples/gc-homepage-a5-facelift.html` |

### Optional Flags

| Flag | Default | Description |
|------|---------|-------------|
| `--feature` | Inferred from HTML filename | NX feature name (e.g., `gc-homepage`) |
| `--route` | None | Angular route path (e.g., `/home`) |
| `--lib` | Same as `--feature` | NX lib name if different from feature |
| `--client-root` | Auto-detected | Path to `boards-cloud-client/src/` |
| `--standalone` | `true` | Generate standalone components (Angular 20 default) |
| `--dry-run` | `false` | Print the plan without writing files |

### Invocation Examples

```bash
# Typical: generate from approved mock
/design-implement samples/gc-homepage-a5-facelift.html --feature gc-homepage --route /home

# Dry run to preview what gets generated
/design-implement samples/gc-homepage-a5-facelift.html --feature gc-homepage --dry-run

# Evolve: add components to an existing feature
/design-implement samples/book-viewer-v2.html --feature book-viewer --route /books/:id
```

---

## 2. Step-by-Step Workflow

### Phase 1: Parse and Plan (no files written)

**Step 1.1 -- Validate inputs**
- Confirm HTML file exists and is readable
- Auto-detect `boards-cloud-client/src/` by walking up from CWD or using known paths
- Verify NX workspace by checking for `nx.json`
- Read `DESIGN.md` from project root if present (Atlas token reference)

**Step 1.2 -- Parse the HTML mock**
- Read the full HTML file
- Extract the `<style>` block: CSS custom properties (design tokens), class definitions
- Extract the `<body>` markup: semantic structure, section boundaries, component candidates
- Build a **Section Map**: identify top-level layout zones (`<nav>`, `<header>`, `<main>`, `<aside>`, `<footer>`, `<section>`)

**Step 1.3 -- Identify component boundaries**

Apply these heuristics to decompose the monolithic HTML:

1. **Existing shell components (DO NOT generate):** Side navigation, top bar, app shell layout. These already exist in `libs/layout/`. Mark them as "provided by shell" in the plan.

2. **Page-level container (smart component):** The outermost content area becomes the feature's page component. Lives in `features/<name>/ui/src/components/`. Owns route, injects services, manages state via signals.

3. **Section-level components (presentational):** Each `<section>` or visually distinct card/widget becomes a standalone component in `libs/<name>/ui/src/components/`. Rule: if it has its own heading, border/card treatment, or could appear on a different page, it is a component.

4. **Repeated items (presentational + @for):** Any element that appears 2+ times with varying content (cards in a grid, list items, news entries) becomes a single component rendered in an `@for` loop.

5. **Interactive elements:** Buttons, inputs, dropdowns, filters map to Atlas components when available. If no Atlas equivalent exists, create a project-specific presentational component.

**Step 1.4 -- Build the Component Tree**

Output a tree like:

```
gc-homepage (page, smart)                    -- features/gc-homepage/ui
  ai-search-card (presentational)            -- libs/gc-homepage/ui
  action-items-section (presentational)      -- libs/gc-homepage/ui
    action-card (presentational, repeated)   -- libs/gc-homepage/ui
  news-widget (presentational)               -- libs/gc-homepage/ui
    news-item (presentational, repeated)     -- libs/gc-homepage/ui
  upcoming-meetings-widget (presentational)  -- libs/gc-homepage/ui
    meeting-row (presentational, repeated)   -- libs/gc-homepage/ui
```

**Step 1.5 -- Present plan to user (AskUserQuestion)**

Show:
- Component tree with placement (feature vs lib)
- Which parts of the HTML are "shell" (skipped)
- Which Atlas components will be reused vs custom components
- Estimated file count
- Ask for approval before generating

### Phase 2: Generate Component Scaffolding

**Step 2.1 -- Create NX project structure (if new feature)**

For a new feature `gc-homepage`:

```
src/features/gc-homepage/
  core/
    project.json          # { "name": "gc-homepage-core-feature", "prefix": "bc-gc-homepage" }
    src/
      constants/
        routes.constants.ts
      enums/
        (as needed)
      test-setup.ts
    jest.config.ts
    tsconfig.json
    tsconfig.spec.json
  ui/
    project.json          # { "name": "gc-homepage-ui-feature", "prefix": "bc-gc-homepage" }
    src/
      components/
        gc-homepage/
          gc-homepage.component.ts
          gc-homepage.component.html
          gc-homepage.component.scss
          gc-homepage.component.spec.ts
      gc-homepage.routes.ts
      gc-homepage-ui.module.ts    # or standalone bootstrap
      test-setup.ts
    jest.config.ts
    tsconfig.json
    tsconfig.spec.json

src/libs/gc-homepage/
  core/
    project.json          # { "name": "gc-homepage-core", "prefix": "bc-gc-homepage" }
    src/
      public-api.ts       # auto-generated barrel
      interfaces/
      services/
      test-setup.ts
    jest.config.ts
    tsconfig.json
    tsconfig.spec.json
  ui/
    project.json          # { "name": "gc-homepage-ui", "prefix": "bc-gc-homepage" }
    src/
      public-api.ts       # auto-generated barrel
      components/
        ai-search-card/
          ai-search-card.component.ts
          ai-search-card.component.html
          ai-search-card.component.scss
          ai-search-card.component.spec.ts
        action-card/
          ...
        (etc.)
      test-setup.ts
    jest.config.ts
    tsconfig.json
    tsconfig.spec.json
```

**Step 2.2 -- Register tsconfig paths**

Add to `src/tsconfig.json`:

```json
"@diligentcorp/boards-cloud/gc-homepage/core/*": ["features/gc-homepage/core/src/*"],
"@diligentcorp/boards-cloud/gc-homepage/ui/*": ["features/gc-homepage/ui/src/*"],
"@diligentcorp/boards-cloud/gc-homepage-lib/core/*": ["libs/gc-homepage/core/src/*"],
"@diligentcorp/boards-cloud/gc-homepage-lib/ui/*": ["libs/gc-homepage/ui/src/*"],
```

Convention: feature path uses the feature name, lib path appends `-lib` suffix. Matches the existing `new-homepage` / `new-homepage-lib` pattern.

**Step 2.3 -- Generate each component**

For each node in the Component Tree, generate four files following these exact patterns:

#### Component TypeScript (.component.ts)

```typescript
// ABOUTME: Presentational component for displaying a single action card.
// Renders an icon, title, and status tag for a board action item.
// Used inside action-items-section via @for loop.
// Standalone, OnPush, signal-based inputs.
// Atlas: uses atlas-angular-icons for action type icons.

import { ChangeDetectionStrategy, Component, input } from '@angular/core';

@Component({
  selector: 'bc-gc-homepage-action-card',
  standalone: true,
  imports: [...],
  templateUrl: './action-card.component.html',
  styleUrl: './action-card.component.scss',
  changeDetection: ChangeDetectionStrategy.OnPush,
})
export class ActionCardComponent {
  /** Action item title text. */
  public readonly title = input.required<string>();

  /** Action item category for icon selection. */
  public readonly category = input.required<ActionCategory>();

  /** Tag to display (e.g., 'Urgent', 'Review'). */
  public readonly tag = input<string>();
}
```

Key patterns to match (observed from codebase):
- `ChangeDetectionStrategy.OnPush` always
- `standalone: true` for lib components (preferred Angular 20 pattern)
- Signal-based inputs: `input()`, `input.required()`, `output()`
- Extends `ComponentBase` from `@diligentcorp/boards-cloud/core/core/base/component-base` for presentational components
- Extends `ScrollableComponentV2Base` for page-level components that scroll
- Selector prefix: `bc-<feature-name>-` (e.g., `bc-gc-homepage-action-card`)
- ABOUTME comment block at file top

#### Component SCSS (.component.scss)

```scss
// ABOUTME: Styles for the action card component.
// Uses Atlas core spacing tokens and semantic color tokens.
// Scoped to :host, all layout via flexbox.

@use 'styles/mixins' as mixins;
@use 'styles/media-queries' as media;
@use '@diligentcorp/atlas-design-tokens/dist/themes/lens/scss/core' as core;
@use '@diligentcorp/atlas-design-tokens/dist/themes/lens/scss/semantic' as semantic;

:host {
  @include mixins.component-inline-fill;

  .action-card { ... }
}
```

#### Component HTML (.component.html)

```html
<article class="action-card" [attr.data-testid]="'action-card-' + category()">
  ...
</article>
```

Key patterns:
- `data-testid` attributes on key elements (codebase uses `data-testid="descriptive-name-random6"` format)
- `i18n` attributes on user-visible text with `@@feature.component.key` format
- Atlas CSS classes for typography: `atlas-title-sm`, `atlas-text-sm`, `atlas-style-emphasis`, `atlas-style-muted`
- Signal reads via `()` in templates

### Phase 3: CSS-to-SCSS Translation

**Step 3.1 -- Map CSS custom properties to Atlas tokens**

The skill maintains a mapping table. For each CSS custom property in the HTML mock's `:root`, find the closest Atlas SCSS token:

| HTML Mock Token | Atlas SCSS Token | Import |
|----------------|-----------------|--------|
| `--bg-base` / `#f5f8f9` | `semantic.$lens-semantic-color-background-base` | `semantic` |
| `--bg-surface` / `#ffffff` | `semantic.$lens-semantic-color-background-container` | `semantic` |
| `--text-primary` / `#1e1e1e` | `semantic.$lens-semantic-color-type-default` | `semantic` |
| `--text-secondary` / `#676767` | `semantic.$lens-semantic-color-type-muted` | `semantic` |
| `--action-default` / `#455d82` | `semantic.$lens-semantic-color-action-primary-default` | `semantic` |
| `--s1..--s8` | `core.$lens-core-spacing-0-5` through `core.$lens-core-spacing-4` | `core` |
| `--border-default` / `#e6e6e6` | `semantic.$lens-semantic-color-ui-divider-default` | `semantic` |
| `--radius-card` | `semantic.$lens-semantic-border-radius-md` | `semantic` |
| `--shadow-card` | `semantic.$lens-semantic-shadow-low` | `semantic` |

**When no Atlas token matches:** Use a raw hex value with a `// TODO: no Atlas token match` comment. Do NOT invent token names.

**Step 3.2 -- Translate layout patterns**

| HTML Mock Pattern | Angular SCSS Pattern |
|-------------------|---------------------|
| `display: flex` | Keep as-is inside `:host` |
| `display: grid; grid-template-columns: ...` | Keep as-is, use Atlas spacing for gaps |
| `width: var(--sidenav-width)` | Remove (shell-provided) |
| `@media (max-width: 600px)` | `@include media.mobile-screen { }` |
| `@media (max-width: 1280px)` | `@include media.mobile-and-tablet-screen { }` |
| Fixed pixel widths for layout columns | Use SCSS variables at top of file |
| `font-family: 'Source Sans 3'` | Remove (inherited from global styles) |
| `box-sizing: border-box` | Remove (global reset) |

**Step 3.3 -- Handle fonts and typography**

The mock uses Google Fonts (`Source Sans 3`). The real app uses Atlas typography which sets the same font family globally. Translation:

| HTML Mock | Angular Template |
|-----------|-----------------|
| `font-size: 28px; font-weight: 600` | `class="atlas-title-lg atlas-style-emphasis"` |
| `font-size: 22px; font-weight: 600` | `class="atlas-title-md atlas-style-emphasis"` |
| `font-size: 16px` | Default body text, no class needed |
| `font-size: 14px` | `class="atlas-text-md"` |
| `font-size: 13px` | `class="atlas-text-sm"` |
| `font-size: 12px` | `class="atlas-text-xs"` |

### Phase 4: Route Wiring

**Step 4.1 -- Define routes in the feature**

Create `features/<name>/core/src/constants/routes.constants.ts`:

```typescript
import { route } from 'typesafe-routes';

export const gcHomepageFeaturePathSegment = 'gc-home';

export const gcHomepageRoute = route(`/${gcHomepageFeaturePathSegment}`, {}, {});
```

**Step 4.2 -- Create the feature routes file**

Create `features/<name>/ui/src/<name>.routes.ts`:

```typescript
import { Route } from '@angular/router';
import { path } from '@diligentcorp/boards-cloud/core/core/routing/route-template-helper';
import { gcHomepageFeaturePathSegment, gcHomepageRoute }
  from '@diligentcorp/boards-cloud/gc-homepage/core/constants/routes.constants';
import { GcHomepageComponent } from './components/gc-homepage/gc-homepage.component';

export function routes(): Route[] {
  return [
    {
      path: path(gcHomepageRoute.template, gcHomepageFeaturePathSegment),
      component: GcHomepageComponent,
    },
  ];
}
```

**Step 4.3 -- Register in app routes**

Add to `apps/boards-frontend/src/app/app.routes.ts`:

```typescript
import { gcHomepageFeaturePathSegment }
  from '@diligentcorp/boards-cloud/gc-homepage/core/constants/routes.constants';

// In the routes array:
{
  path: gcHomepageFeaturePathSegment,
  loadChildren: () =>
    import('@diligentcorp/boards-cloud/gc-homepage/ui/gc-homepage-ui.module')
      .then(m => m.GcHomepageUiModule),
  canActivate: [authGuard, environmentGuard],
  data: { title: $localize`...` },
},
```

**Step 4.4 -- Register in features list**

Add to `apps/boards-frontend/src/app/features.ts` if the page should appear in side navigation.

### Phase 5: Barrel Files and Build

**Step 5.1 -- Run barrel file generation**

```bash
cd boards-cloud-client/src && pnpm run generate:index
```

This auto-generates `public-api.ts` files in each lib. Do not manually write barrel files.

**Step 5.2 -- Verify compilation**

```bash
cd boards-cloud-client/src && pnpm nx run boards-frontend:build --skip-nx-cache
```

**Step 5.3 -- Run tests**

```bash
cd boards-cloud-client/src && pnpm nx run <project-name>:test
```

### Phase 6: Verification

**Step 6.1 -- Visual diff (if browse available)**

If the gstack browse tool is available, navigate to the implemented route and compare against the HTML mock opened in a separate tab. Note visual discrepancies.

**Step 6.2 -- Checklist output**

Present to the user:
- [ ] All components from the plan generated
- [ ] SCSS uses Atlas tokens (no raw hex values without TODO comments)
- [ ] All user-visible text has `i18n` attributes
- [ ] All interactive elements have `data-testid` attributes
- [ ] Routes registered and lazy-loaded
- [ ] `generate:index` ran successfully
- [ ] Project compiles without errors
- [ ] Shell elements (sidenav, topbar) not duplicated

---

## 3. Translation Rules Reference

### 3.1 Smart vs Presentational Components

| Criteria | Smart (Page) | Presentational (Widget) |
|----------|-------------|----------------------|
| Location | `features/<name>/ui/src/components/` | `libs/<name>/ui/src/components/` |
| State | Owns signals, injects services | Receives data via `input()`, emits via `output()` |
| Base class | `ScrollableComponentV2Base` | `ComponentBase` |
| Module type | Declared in NgModule (or standalone with providers) | Always standalone |
| Knows about routing | Yes (injects `Router`, `ActivatedRoute`) | No |
| Fetches data | Yes (calls web API services) | No |

### 3.2 HTML Element to Angular Component Mapping

| HTML Mock Element | Angular Approach |
|-------------------|-----------------|
| `<nav class="sidenav">` | Skip: provided by `libs/layout` shell |
| `<header class="topbar">` | Skip: provided by `libs/layout` shell |
| `<section>` with heading | Standalone presentational component |
| `<article>` repeated in a grid/list | Standalone component + `@for` in parent |
| `<input type="search">` | Atlas `<atlas-input>` or `<mat-form-field>` |
| `<button>` | Atlas `<button mat-button>` with Atlas styling |
| `<a href="#">` with button styling | `<a mat-button>` or `routerLink` |
| SVG icons inline | Replace with `@diligentcorp/atlas-angular-icons` component |
| `<span class="badge">3</span>` | Atlas badge component if available |
| Gradient decorative strips | SCSS `::before`/`::after` pseudo-elements with `ai-styles` mixin |

### 3.3 CSS Property to Atlas Token Quick Reference

Spacing:
```
4px  -> core.$lens-core-spacing-0-5
8px  -> core.$lens-core-spacing-1
12px -> core.$lens-core-spacing-1-5
16px -> core.$lens-core-spacing-2
20px -> core.$lens-core-spacing-2-5
24px -> core.$lens-core-spacing-3
32px -> core.$lens-core-spacing-4
40px -> core.$lens-core-spacing-5
48px -> core.$lens-core-spacing-6
```

Colors (most common):
```
#1e1e1e -> semantic.$lens-semantic-color-type-default
#676767 -> semantic.$lens-semantic-color-type-muted
#949494 -> semantic.$lens-semantic-color-type-disabled (or muted)
#ffffff -> semantic.$lens-semantic-color-background-container
#f5f8f9 -> semantic.$lens-semantic-color-background-base (approx)
#455d82 -> semantic.$lens-semantic-color-action-primary-default
#385f99 -> semantic.$lens-semantic-color-link-default
#e6e6e6 -> semantic.$lens-semantic-color-ui-divider-default
#d3222a -> semantic.$lens-semantic-color-status-new (approx, brand red)
```

Borders:
```
1px solid #e6e6e6 -> semantic.$lens-semantic-border-width-thin solid semantic.$lens-semantic-color-ui-divider-default
border-radius: 4px -> semantic.$lens-semantic-border-radius-md
```

### 3.4 The "Shell Boundary" Rule

The HTML mock includes the full page (sidenav, topbar, content). The Angular app already has a layout shell. The skill MUST:

1. Identify the shell boundary in the mock (everything outside `<main>` or the primary content container)
2. Skip generating components for shell elements
3. Only generate the content that goes INSIDE the existing `<router-outlet>`
4. If the mock's content area has specific padding or max-width, apply those to the page component's `:host` styles

---

## 4. Skill File Structure

The skill lives in the gstack plugin directory:

```
~/.claude/skills/gstack/design-implement/
  SKILL.md              # Main skill definition (frontmatter + workflow)
  SKILL.md.tmpl         # Template before preamble injection
  vendor/               # (if needed for helper scripts)
```

Or, if project-local:

```
.claude/skills/design-implement/
  SKILL.md
```

### Skill Definition (SKILL.md frontmatter)

```yaml
---
name: design-implement
preamble-tier: 2
version: 1.0.0
description: |
  Translates approved HTML mocks from /design-html into real Angular
  components. Parses the HTML, decomposes into component tree, generates
  NX-compliant Angular components with Atlas design tokens and SCSS.
  Use when: "implement this design", "turn this HTML into Angular",
  "build components from the mock".
  Proactively suggest when user has a finalized HTML from /design-html.
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
```

### Dependencies

The skill reads but does not modify:
- Atlas MCP server (for token lookups via `mcp__Atlas__search_atlas_tokens_by_value`)
- Atlas component docs (via `mcp__Atlas__get_atlas_component_docs`)
- `DESIGN.md` (project design tokens)
- Existing codebase patterns (reads 2-3 existing components for style matching)

---

## 5. Codebase Integration Strategy

### 5.1 NX Monorepo Conventions

The skill follows the exact two-tier structure observed in the codebase:

```
features/<name>/core/  -- Route constants, enums, feature-specific types
features/<name>/ui/    -- Page component(s), module, routes file
libs/<name>/core/      -- Shared interfaces, services, constants, utils
libs/<name>/ui/        -- Reusable presentational components, pipes
```

Each directory is an NX project with its own `project.json`, `jest.config.ts`, `tsconfig.json`.

### 5.2 Import Conventions

All cross-lib imports use the `@diligentcorp/boards-cloud/<lib>/<layer>/<path>` pattern defined in `tsconfig.json` `paths`. The skill must:

1. Add path mappings to `tsconfig.json` for new libs/features
2. Use these mapped paths in all import statements (never relative paths across project boundaries)
3. Use relative paths only within the same NX project

### 5.3 Atlas Design System Integration

The skill uses two integration points:

1. **SCSS tokens**: `@use '@diligentcorp/atlas-design-tokens/dist/themes/lens/scss/core'` and `semantic`. Every SCSS file that uses spacing, colors, or typography tokens must import these.

2. **Angular components**: Atlas provides Angular component wrappers (`@diligentcorp/atlas-angular-icons` for icons, Atlas components via the Atlas MCP docs). The skill should query the Atlas MCP to check component availability before generating custom implementations.

### 5.4 Barrel File Generation

The project uses auto-generated barrel files (`public-api.ts`). The skill MUST:

1. Not manually write `public-api.ts` files
2. Run `pnpm run generate:index` after all components are created
3. Verify the generated barrel files include the new components

### 5.5 Module vs Standalone Strategy

The codebase is in transition. Pattern observed:

- **Lib components**: Always `standalone: true`
- **Feature page components**: Some still use NgModule (`standalone: false`), some are standalone
- **New code should prefer standalone** (Angular 20 default)

The skill should generate standalone components by default. For the page-level component, generate a thin NgModule that imports the standalone components and registers routes (matching the `NewHomepageUiModule` pattern), OR use standalone bootstrapping if the user prefers.

---

## 6. Risks and Mitigations

### R1: HTML mock includes shell elements that already exist

**Risk:** Generating duplicate sidenav/topbar components that conflict with the layout shell.
**Mitigation:** Step 1.3 explicitly identifies shell elements and marks them "skip." The skill reads `libs/layout/` to understand the existing shell boundary. AskUserQuestion confirms the boundary before generation.

### R2: CSS values don't have exact Atlas token matches

**Risk:** Some design values in the mock may not map 1:1 to Atlas tokens (especially custom gradients, non-standard spacing, brand-specific colors).
**Mitigation:** The skill places a `// TODO: no Atlas token match -- value: #abc123` comment on unmatched values. After generation, it reports a summary of unmatched tokens for manual review.

### R3: Generated components may not compile on first pass

**Risk:** Import paths, missing dependencies, or NX configuration issues.
**Mitigation:** Phase 5 runs `generate:index` and attempts a build. The skill iteratively fixes compilation errors (up to 3 attempts per the escalation protocol). If it cannot resolve, it stops and reports.

### R4: Mock layout doesn't account for dynamic data

**Risk:** The HTML mock uses hardcoded text/counts. The Angular components need to handle empty states, loading states, and variable-length content.
**Mitigation:** The skill generates components with placeholder inputs for dynamic data. It adds skeleton loading states using the existing `SkeletonComponent` pattern. It flags sections that need API integration as `// TODO: wire to service` in the smart component.

### R5: Stale NX cache after adding new projects

**Risk:** NX may not recognize new projects without cache reset.
**Mitigation:** Run with `--skip-nx-cache` on first build. The skill also runs `pnpm nx reset` if project discovery fails.

### R6: i18n extraction IDs may conflict

**Risk:** The `@@feature.component.key` i18n IDs could collide with existing translations.
**Mitigation:** Use the feature name as namespace prefix (e.g., `@@gcHomepage.actionCard.title`). Check for conflicts by grepping existing `.xlf` files.

---

## 7. Effort Breakdown

| Task | Estimate (CC+gstack) | Notes |
|------|----------------------|-------|
| Skill SKILL.md authoring | 30 min | Workflow steps, preamble, allowed-tools |
| HTML parser logic (embedded in prompt) | 0 | No code; skill uses LLM reasoning to parse |
| Atlas token mapping table | 15 min | Build from DESIGN.md + Atlas MCP queries |
| NX scaffolding templates | 20 min | project.json, tsconfig, jest.config patterns |
| Component generation templates | 20 min | .ts, .html, .scss, .spec.ts patterns |
| Route wiring logic | 10 min | Routes, module, app.routes.ts registration |
| Testing/verification steps | 10 min | Build check, generate:index, visual diff |
| **Total** | **~2 hours** | First version, ready for dogfooding |

### What the skill does NOT do (v1 scope boundary)

- Does not generate services or API integration code (outputs `// TODO` markers)
- Does not generate e2e tests (only unit test stubs with `it('should create')`)
- Does not modify the layout shell or global navigation
- Does not handle multi-page flows (one HTML mock = one route)
- Does not generate state management (NgRx/signals stores) beyond simple component signals

### Future extensions (v2+)

- Accept a Figma URL directly (via Atlas MCP `get_figma_node_data`)
- Generate service stubs from mock data visible in the HTML
- Multi-page flows from multiple HTML mocks
- Automatic visual regression comparison via gstack browse
