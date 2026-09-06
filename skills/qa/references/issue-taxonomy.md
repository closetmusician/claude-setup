# QA Issue Taxonomy

Severity and category definitions used by /qa and the report template, plus the
per-page exploration checklist referenced in Phase 4.

## Severity (decision criteria)

| Severity | Threshold | Example that qualifies | Example that does NOT |
|----------|-----------|------------------------|-----------------------|
| **Critical** | Core flow broken, data loss, security exposure, or page unusable | Checkout submit button throws and order is never created | Checkout works but the spinner is off-center (→ Low) |
| **High** | Feature malfunctions or misleads; user can't complete a secondary flow, or sees wrong data | Search returns results for the wrong query term | Search results lack hover states (→ Medium/Low) |
| **Medium** | Feature works but with friction, confusing states, or non-blocking errors | Form loses input on validation error; console errors on every nav | A label wraps awkwardly at 375px (→ Low) |
| **Low** | Cosmetic: spacing, typos, alignment, polish; no functional impact | Footer link color fails contrast by a small margin | Broken image on the pricing page (→ Medium: content users rely on) |

Tie-breaker: if the issue would make a first-time user think the app is broken or
untrustworthy, rate it one level higher.

## Categories (must match the health-score rubric)

| Category | What belongs here |
|----------|-------------------|
| Console | JS errors/exceptions, failed requests logged, hydration errors |
| Links | Broken links (404/500), dead anchors, wrong destinations |
| Visual | Layout breakage, overlap, clipping, broken images, z-index issues |
| Functional | Buttons/forms/flows that don't work or produce wrong results |
| UX | Dead ends, missing feedback, confusing states, lost input, focus traps |
| Content | Typos, placeholder text left in, wrong/stale copy, missing empty-state text |
| Performance | Slow loads (>3s), layout shift, unresponsive interactions, memory growth |
| Accessibility | Missing alt text/labels, keyboard traps, contrast failures, focus order |

## Per-Page Exploration Checklist (Phase 4)

Run at every page visited (Standard/Exhaustive tiers; Quick tier skips this):

1. **Visual scan** — inspect the annotated screenshot: overlap, clipping, broken
   images, misalignment, horizontal scroll at desktop width.
2. **Interactive elements** — click every button, link, toggle, and menu. Does each
   do something visible? Dead controls are Functional issues.
3. **Forms** — fill and submit each form three ways: valid input, empty submit,
   invalid/edge input (overlong string, wrong format, script tag). Check that errors
   are shown, input is preserved, and double-submit doesn't duplicate.
4. **Navigation** — every path in and out: nav links, breadcrumbs, back button after
   an action, deep-link to the page directly.
5. **States** — empty state (no data), loading state (throttle or watch first paint),
   error state (trigger a failed request if possible), overflow (long names, many rows).
6. **Console** — check for new errors after each interaction, not just on load.
7. **Responsiveness** — if the page is user-facing, check the 375x812 viewport:
   menu collapses, no horizontal scroll, tap targets not overlapping.

Depth judgment: spend the most time on revenue/core paths (home, dashboard, checkout,
search, auth) and the least on static pages (about, terms, privacy).
