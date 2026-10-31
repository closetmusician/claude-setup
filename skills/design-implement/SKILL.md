---
name: design-implement
description: |
  Use when translating an approved HTML mock into real Angular components within
  an NX monorepo. Triggers: "implement this design", "turn this HTML into Angular",
  "build components from the mock", or when a finalized HTML from /design-html exists.
---

# /design-implement

Translates approved HTML mocks into Angular components within the `boards-cloud-client` NX monorepo. Parses the HTML, decomposes it into a component tree, generates NX-compliant Angular components with Atlas SCSS tokens, wires routes, and verifies the build.

## Interface

```
/design-implement <html-path> [--feature <name>] [--route <path>] [--lib <name>] [--client-root <path>] [--standalone true|false] [--dry-run]
```

| Arg | Required | Default | Description |
|-----|----------|---------|-------------|
| `html-path` | Yes | -- | Path to the approved HTML mock file |
| `--feature` | No | Inferred from HTML filename | NX feature name (e.g., `gc-homepage`) |
| `--route` | No | None | Angular route path (e.g., `/home`) |
| `--lib` | No | Same as `--feature` | NX lib name if different from feature |
| `--client-root` | No | Auto-detected | Path to `boards-cloud-client/src/` |
| `--standalone` | No | `true` | Generate standalone components (Angular 20 default) |
| `--dry-run` | No | `false` | Print the plan without writing files |

### Examples

```bash
# Typical: generate from approved mock
/design-implement samples/gc-homepage-a5-facelift.html --feature gc-homepage --route /home

# Dry run to preview
/design-implement samples/gc-homepage-a5-facelift.html --feature gc-homepage --dry-run

# Add components to an existing feature
/design-implement samples/book-viewer-v2.html --feature book-viewer --route /books/:id
```

---

## Phase 1: Parse and Plan

No files written in this phase. Output is an approved component tree.

### 1.1 Validate Inputs

- Confirm the HTML file exists and is readable.
- Auto-detect `boards-cloud-client/src/` by walking up from CWD or searching known paths. Verify NX workspace via `nx.json`.
- Read `DESIGN.md` from project root if present (Atlas token reference).
- Read 2-3 existing components from the target codebase to learn local conventions (import style, ABOUTME format, base classes used).

### 1.2 Parse the HTML Mock

Read the full HTML file and extract:

1. **`<style>` block**: CSS custom properties (design tokens), class definitions.
2. **`<body>` markup**: Semantic structure, section boundaries, component candidates.
3. **Section Map**: Top-level layout zones (`<nav>`, `<header>`, `<main>`, `<aside>`, `<footer>`, `<section>`).

### 1.3 Identify Component Boundaries

Apply these heuristics in order:

1. **Shell elements (DO NOT generate)**: Side navigation, top bar, app shell layout. These exist in `libs/layout/`. Mark as "provided by shell" in the plan. See the Shell Boundary Rule below.

2. **Page-level container (smart component)**: The outermost content area becomes the feature's page component. Lives in `features/<name>/ui/src/components/`. Owns route, injects services, manages state via signals.

3. **Section-level components (presentational)**: Each `<section>` or visually distinct card/widget becomes a standalone component in `libs/<name>/ui/src/components/`. Rule: if it has its own heading, border/card treatment, or could appear on a different page, extract it.

4. **Repeated items (presentational + @for)**: Any element appearing 2+ times with varying content (cards in a grid, list items) becomes a single component rendered via `@for`.

5. **Interactive elements**: Buttons, inputs, dropdowns, filters map to Atlas components when available. Query Atlas MCP (`mcp__Atlas__get_atlas_component_docs`) to check availability. If no Atlas equivalent, create a project-specific presentational component.

### 1.4 Build the Component Tree

Output a tree showing each component, its type, and its target location.

Example (GC Homepage):

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

### 1.5 User Approval Gate (AskUserQuestion)

Present to the user:
- Component tree with placement (feature vs lib).
- Which parts of the HTML are "shell" (skipped).
- Which Atlas components will be reused vs custom components.
- Estimated file count.

**Do not proceed to Phase 2 without explicit approval.**

---

## Phase 2: Scaffold

Generate Angular component files following NX patterns.

### 2.1 NX Project Structure

For a new feature (example: `gc-homepage`):

```
src/features/<feature-name>/
  core/
    project.json          # { "name": "<feature>-core-feature", "prefix": "bc-<feature>" }
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
    project.json          # { "name": "<feature>-ui-feature", "prefix": "bc-<feature>" }
    src/
      components/
        <feature-name>/
          <feature-name>.component.ts
          <feature-name>.component.html
          <feature-name>.component.scss
          <feature-name>.component.spec.ts
      <feature-name>.routes.ts
      <feature-name>-ui.module.ts
      test-setup.ts
    jest.config.ts
    tsconfig.json
    tsconfig.spec.json

src/libs/<feature-name>/
  core/
    project.json          # { "name": "<feature>-core", "prefix": "bc-<feature>" }
    src/
      public-api.ts       # auto-generated barrel (do NOT write manually)
      interfaces/
      services/
      test-setup.ts
    jest.config.ts
    tsconfig.json
    tsconfig.spec.json
  ui/
    project.json          # { "name": "<feature>-ui", "prefix": "bc-<feature>" }
    src/
      public-api.ts       # auto-generated barrel
      components/
        <component-name>/
          <component-name>.component.ts
          <component-name>.component.html
          <component-name>.component.scss
          <component-name>.component.spec.ts
      test-setup.ts
    jest.config.ts
    tsconfig.json
    tsconfig.spec.json
```

### 2.2 Register tsconfig Paths

Add to `src/tsconfig.json`:

```json
"@diligentcorp/boards-cloud/<feature>/core/*": ["features/<feature>/core/src/*"],
"@diligentcorp/boards-cloud/<feature>/ui/*": ["features/<feature>/ui/src/*"],
"@diligentcorp/boards-cloud/<feature>-lib/core/*": ["libs/<feature>/core/src/*"],
"@diligentcorp/boards-cloud/<feature>-lib/ui/*": ["libs/<feature>/ui/src/*"]
```

Convention: feature path uses the feature name; lib path appends `-lib` suffix.

### 2.3 Generate Each Component

For each node in the Component Tree, generate four files.

#### Component TypeScript (.component.ts)

```typescript
// ABOUTME: <Purpose of this component in one sentence.>
// <What it renders and where it is used.>
// <Data flow: inputs/outputs or services injected.>
// <Pattern: Standalone, OnPush, signal-based inputs.>
// <Atlas: which Atlas components/tokens are used.>

import { ChangeDetectionStrategy, Component, input } from '@angular/core';

@Component({
  selector: 'bc-<feature>-<component-name>',
  standalone: true,
  imports: [...],
  templateUrl: './<component-name>.component.html',
  styleUrl: './<component-name>.component.scss',
  changeDetection: ChangeDetectionStrategy.OnPush,
})
export class <ComponentName>Component {
  /** Description of input. */
  public readonly someInput = input.required<string>();

  /** Optional input with default. */
  public readonly optionalInput = input<string>();
}
```

**Patterns to match (from codebase observation):**
- `ChangeDetectionStrategy.OnPush` always.
- `standalone: true` for lib components (Angular 20 default).
- Signal-based inputs: `input()`, `input.required()`, `output()`.
- Presentational components extend `ComponentBase` from `@diligentcorp/boards-cloud/core/core/base/component-base`.
- Page-level components extend `ScrollableComponentV2Base` for scrollable routes.
- Selector prefix: `bc-<feature-name>-` (e.g., `bc-gc-homepage-action-card`).
- ABOUTME comment block at file top (5 lines).

#### Component SCSS (.component.scss)

```scss
// ABOUTME: Styles for the <component-name> component.
// Uses Atlas core spacing tokens and semantic color tokens.
// Scoped to :host, layout via flexbox/grid.

@use 'styles/mixins' as mixins;
@use 'styles/media-queries' as media;
@use '@diligentcorp/atlas-design-tokens/dist/themes/lens/scss/core' as core;
@use '@diligentcorp/atlas-design-tokens/dist/themes/lens/scss/semantic' as semantic;

:host {
  @include mixins.component-inline-fill;

  .component-class { ... }
}
```

#### Component HTML (.component.html)

```html
<article class="component-class" [attr.data-testid]="'component-name-' + someId()">
  <h3 class="atlas-title-sm atlas-style-emphasis" i18n="@@feature.component.heading">
    Heading Text
  </h3>
  ...
</article>
```

**Patterns:**
- `data-testid` attributes on key elements.
- `i18n` attributes on user-visible text with `@@feature.component.key` format.
- Atlas CSS classes for typography: `atlas-title-sm`, `atlas-text-sm`, `atlas-style-emphasis`, `atlas-style-muted`.
- Signal reads via `()` in templates.

#### Component Spec (.component.spec.ts)

Generate a minimal test that verifies the component creates:

```typescript
import { ComponentFixture, TestBed } from '@angular/core/testing';
import { <ComponentName>Component } from './<component-name>.component';

describe('<ComponentName>Component', () => {
  let fixture: ComponentFixture<<ComponentName>Component>;
  let component: <ComponentName>Component;

  beforeEach(async () => {
    await TestBed.configureTestingModule({
      imports: [<ComponentName>Component],
    }).compileComponents();

    fixture = TestBed.createComponent(<ComponentName>Component);
    component = fixture.componentInstance;
    // Set required inputs before detectChanges
    fixture.componentRef.setInput('someInput', 'test-value');
    fixture.detectChanges();
  });

  it('should create', () => {
    expect(component).toBeTruthy();
  });
});
```

### Smart vs Presentational Reference

| Criteria | Smart (Page) | Presentational (Widget) |
|----------|-------------|----------------------|
| Location | `features/<name>/ui/src/components/` | `libs/<name>/ui/src/components/` |
| State | Owns signals, injects services | Receives data via `input()`, emits via `output()` |
| Base class | `ScrollableComponentV2Base` | `ComponentBase` |
| Module type | NgModule (or standalone with providers) | Always standalone |
| Routing | Yes (injects `Router`, `ActivatedRoute`) | No |
| Data fetching | Yes (calls web API services) | No |

---

## Phase 3: CSS-to-SCSS Translation

### 3.1 Map CSS Custom Properties to Atlas Tokens

For each CSS custom property in the HTML mock's `:root`, find the closest Atlas SCSS token. Use the Atlas MCP tool (`mcp__Atlas__search_atlas_tokens_by_value`) for lookups when the tables below do not cover a value.

#### Spacing

| Mock Value | Atlas SCSS Token |
|------------|-----------------|
| `4px` | `core.$lens-core-spacing-0-5` |
| `8px` | `core.$lens-core-spacing-1` |
| `12px` | `core.$lens-core-spacing-1-5` |
| `16px` | `core.$lens-core-spacing-2` |
| `20px` | `core.$lens-core-spacing-2-5` |
| `24px` | `core.$lens-core-spacing-3` |
| `32px` | `core.$lens-core-spacing-4` |
| `40px` | `core.$lens-core-spacing-5` |
| `48px` | `core.$lens-core-spacing-6` |

#### Colors

| Mock Value | Atlas SCSS Token |
|------------|-----------------|
| `#1e1e1e` | `semantic.$lens-semantic-color-type-default` |
| `#676767` | `semantic.$lens-semantic-color-type-muted` |
| `#949494` | `semantic.$lens-semantic-color-type-disabled` |
| `#ffffff` | `semantic.$lens-semantic-color-background-container` |
| `#f5f8f9` | `semantic.$lens-semantic-color-background-base` |
| `#455d82` | `semantic.$lens-semantic-color-action-primary-default` |
| `#385f99` | `semantic.$lens-semantic-color-link-default` |
| `#e6e6e6` | `semantic.$lens-semantic-color-ui-divider-default` |
| `#d3222a` | `semantic.$lens-semantic-color-status-new` |

#### Borders

| Mock Value | Atlas SCSS Token |
|------------|-----------------|
| `1px solid #e6e6e6` | `semantic.$lens-semantic-border-width-thin solid semantic.$lens-semantic-color-ui-divider-default` |
| `border-radius: 4px` | `semantic.$lens-semantic-border-radius-md` |

#### Shadows

| Mock Value | Atlas SCSS Token |
|------------|-----------------|
| Card shadow | `semantic.$lens-semantic-shadow-low` |

**When no Atlas token matches**: Use the raw hex value with a `// TODO: no Atlas token match -- value: #abc123` comment. Do NOT invent token names. After generation, report a summary of unmatched tokens.

### 3.2 Layout Pattern Translation

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

### 3.3 Typography Translation

| HTML Mock | Angular Approach |
|-----------|-----------------|
| `font-size: 28px; font-weight: 600` | `class="atlas-title-lg atlas-style-emphasis"` |
| `font-size: 22px; font-weight: 600` | `class="atlas-title-md atlas-style-emphasis"` |
| `font-size: 16px` | Default body text, no class needed |
| `font-size: 14px` | `class="atlas-text-md"` |
| `font-size: 13px` | `class="atlas-text-sm"` |
| `font-size: 12px` | `class="atlas-text-xs"` |

### 3.4 HTML Element to Angular Component Mapping

| HTML Mock Element | Angular Approach |
|-------------------|-----------------|
| `<nav class="sidenav">` | Skip: provided by `libs/layout` shell |
| `<header class="topbar">` | Skip: provided by `libs/layout` shell |
| `<section>` with heading | Standalone presentational component |
| `<article>` repeated in a grid/list | Standalone component + `@for` in parent |
| `<input type="search">` | Atlas `<atlas-input>` or `<mat-form-field>` |
| `<button>` | Atlas `<button mat-button>` with Atlas styling |
| `<a href="#">` with button styling | `<a mat-button>` or `routerLink` |
| SVG icons inline | Replace with `@diligentcorp/atlas-angular-icons` |
| `<span class="badge">3</span>` | Atlas badge component if available |
| Gradient decorative strips | SCSS `::before`/`::after` pseudo-elements |

---

## Phase 4: Route Wiring

### 4.1 Route Constants

Create `features/<name>/core/src/constants/routes.constants.ts`:

```typescript
// ABOUTME: Route constants for the <feature> feature.
// Defines the path segment and typesafe route for lazy-loaded routing.
// Imported by both the feature routes file and app-level route registration.

import { route } from 'typesafe-routes';

export const <featureCamel>FeaturePathSegment = '<route-segment>';

export const <featureCamel>Route = route(`/${<featureCamel>FeaturePathSegment}`, {}, {});
```

### 4.2 Feature Routes File

Create `features/<name>/ui/src/<name>.routes.ts`:

```typescript
// ABOUTME: Route definitions for the <feature> feature.
// Maps the feature path segment to the page component.
// Lazy-loaded via loadChildren in app.routes.ts.

import { Route } from '@angular/router';
import { path } from '@diligentcorp/boards-cloud/core/core/routing/route-template-helper';
import { <featureCamel>FeaturePathSegment, <featureCamel>Route }
  from '@diligentcorp/boards-cloud/<feature>/core/constants/routes.constants';
import { <PageComponent> } from './components/<page-name>/<page-name>.component';

export function routes(): Route[] {
  return [
    {
      path: path(<featureCamel>Route.template, <featureCamel>FeaturePathSegment),
      component: <PageComponent>,
    },
  ];
}
```

### 4.3 Register in App Routes

Add to `apps/boards-frontend/src/app/app.routes.ts`:

```typescript
import { <featureCamel>FeaturePathSegment }
  from '@diligentcorp/boards-cloud/<feature>/core/constants/routes.constants';

// In the routes array:
{
  path: <featureCamel>FeaturePathSegment,
  loadChildren: () =>
    import('@diligentcorp/boards-cloud/<feature>/ui/<feature>-ui.module')
      .then(m => m.<FeaturePascal>UiModule),
  canActivate: [authGuard, environmentGuard],
  data: { title: $localize`<Feature Title>` },
},
```

### 4.4 Side Navigation (optional)

If the page should appear in side navigation, add to `apps/boards-frontend/src/app/features.ts`.

---

## Phase 5: Build Verification

### 5.1 Generate Barrel Files (MANDATORY)

```bash
cd boards-cloud-client/src && pnpm run generate:index
```

This auto-generates `public-api.ts` files. **Never write barrel files manually.** Always run this before any build step.

### 5.2 Type-Check and Build

```bash
cd boards-cloud-client/src && pnpm nx run boards-frontend:build --skip-nx-cache
```

If NX does not recognize new projects, run `pnpm nx reset` first.

### 5.3 Run Tests

```bash
cd boards-cloud-client/src && pnpm nx run <project-name>:test
```

### 5.4 Iterative Fix

If build fails, fix compilation errors (up to 3 attempts). Common issues:
- Missing import paths in `tsconfig.json`.
- Missing `project.json` configuration.
- Incorrect barrel exports (re-run `generate:index`).

If 3 attempts fail, STOP and report the errors to the user.

---

## Phase 6: Visual Verification

### 6.1 Visual Diff

If the gstack browse tool or a dev server is available, navigate to the implemented route and compare against the HTML mock opened in a separate tab. Note visual discrepancies.

### 6.2 Completion Checklist

Present to the user:

- [ ] All components from the plan generated
- [ ] SCSS uses Atlas tokens (no raw hex values without TODO comments)
- [ ] All user-visible text has `i18n` attributes
- [ ] All interactive elements have `data-testid` attributes
- [ ] Routes registered and lazy-loaded
- [ ] `generate:index` ran successfully
- [ ] Project compiles without errors
- [ ] Shell elements (sidenav, topbar) not duplicated
- [ ] Unmatched token summary reported (if any)

---

## Shell Boundary Rule

The HTML mock includes the full page (sidenav, topbar, content). The Angular app already has a layout shell. You MUST:

1. **Identify the shell boundary**: Everything outside `<main>` or the primary content container in the mock is shell.
2. **Skip shell elements**: Do not generate components for `<nav class="sidenav">`, `<header class="topbar">`, or the `<div class="app-shell">` wrapper.
3. **Generate only content**: Build what goes INSIDE the existing `<router-outlet>`.
4. **Preserve content-area styles**: If the mock's content area has specific padding or max-width, apply those to the page component's `:host` styles.

Detection heuristics:
- Elements with classes like `sidenav`, `side-nav`, `sidebar`, `topbar`, `top-bar`, `navbar`, `app-shell`, `app-layout` are shell.
- `<nav>` elements containing site-wide navigation links are shell.
- `<header>` elements with logo/search/account controls are shell.
- The content boundary is typically `<main>`, or the first child after sidenav/topbar containers.

---

## Scope Boundaries (v1)

**Does:**
- Decompose HTML into Angular components with Atlas tokens.
- Generate component files (`.ts`, `.html`, `.scss`, `.spec.ts`).
- Wire lazy-loaded routes via typesafe-routes.
- Run barrel generation and build verification.

**Does not:**
- Generate services or API integration (outputs `// TODO: wire to service`).
- Generate e2e tests (only unit test stubs).
- Modify the layout shell or global navigation.
- Handle multi-page flows (one HTML mock = one route).

---

## Phase 7: Handoff Artifact

After Phase 6, write `docs/design-implement-output.md` summarizing what was produced. This artifact serves two purposes: (1) human-readable review of what was scaffolded, (2) machine-readable input for `/eng-planning` when hardening to production.

```markdown
# Design-Implement Output — {Feature Name}

**Source mock:** {path to HTML mock}
**Date:** {YYYY-MM-DD}
**Route:** {Angular route path}

## Component Tree
{Indented tree of generated components with file paths}
- `src/features/{feature}/ui/` — page component (smart, NgModule)
  - `src/libs/{feature}/ui/` — child components (presentational, standalone)

## CSS-to-Atlas Mapping Decisions
| Mock Token/Value | Atlas SCSS Token | Status |
|-----------------|-----------------|--------|
| {hex or CSS var} | {Atlas token} | Matched / TODO / Override |

## Shell Boundary
- **Skipped:** {list of shell elements identified and excluded}
- **Content root:** {element used as the content boundary}

## Unresolved Items
- [ ] API stubs: {list of `// TODO: wire to service` locations with file:line}
- [ ] Unmatched tokens: {count and list}
- [ ] Dynamic data: {sections that need real data sources}
- [ ] i18n: {any ID conflicts or missing translations}
- [ ] Interactive behavior: {JS interactivity from prototype that needs Angular reimplementation}

## For eng-planning
When running `/eng-planning` for the production phase, read this file alongside the PRD.
The component structure is already scaffolded — focus architecture decisions on:
- API contract design for each `// TODO: wire to service` location
- State management approach for interactive behaviors listed above
- Permission model for route guards
- Error states and loading skeletons
```
- Generate state management beyond simple component signals.
