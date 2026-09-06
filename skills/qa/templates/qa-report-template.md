# QA Report — {domain} — {YYYY-MM-DD}

## Metadata

| Field | Value |
|-------|-------|
| Target | {url} |
| Tier | Quick / Standard / Exhaustive |
| Mode | full / diff-aware / quick / regression |
| Branch | {branch or n/a} |
| Framework detected | {Next.js / Rails / WordPress / SPA / unknown} |
| Duration | {mm:ss} |
| Pages visited | {N} |
| Screenshots | {N} (in `screenshots/`) |

## Summary

| Severity | Found | Fixed | Deferred |
|----------|-------|-------|----------|
| Critical | | | |
| High | | | |
| Medium | | | |
| Low | | | |
| **Total** | | | |

**Health score:** {baseline} → {final} (see category breakdown below)

| Category | Score | Weight |
|----------|-------|--------|
| Console | /100 | 15% |
| Links | /100 | 10% |
| Visual | /100 | 10% |
| Functional | /100 | 20% |
| UX | /100 | 15% |
| Performance | /100 | 10% |
| Content | /100 | 5% |
| Accessibility | /100 | 15% |
| **Weighted total** | **/100** | |

## Top 3 Things to Fix

1. {ISSUE-NNN — highest-severity issue, one line}
2. {ISSUE-NNN}
3. {ISSUE-NNN}

---

## Issues

<!-- One block per issue. Append immediately when found — never batch.
     Severity and category definitions: references/issue-taxonomy.md -->

### ISSUE-{NNN}: {short title}

- **Severity:** Critical / High / Medium / Low
- **Category:** Console / Links / Visual / Functional / UX / Content / Performance / Accessibility
- **Page:** {URL or route}
- **Repro steps:**
  1. {step — reference screenshots by filename}
  2. {step}
- **Expected:** {what should happen}
- **Actual:** {what happens instead}
- **Evidence:** `screenshots/issue-{NNN}-step-1.png`, `screenshots/issue-{NNN}-result.png`
- **Fix status:** verified / best-effort / reverted / deferred
- **Commit:** {SHA if fixed}
- **Files changed:** {paths if fixed}
- **Before/After:** `screenshots/issue-{NNN}-before.png` → `screenshots/issue-{NNN}-after.png` (if fixed)
- **Regression test:** {test file path + commit SHA, or "skipped: {reason}"}

---

## Console Health Summary

Aggregate of all console errors/warnings seen across pages:

| Page | Errors | Notable messages |
|------|--------|------------------|
| | | |

## Deferred Issues

| Issue | Severity | Why deferred |
|-------|----------|--------------|
| | | |

## Regression vs Baseline (regression mode only)

- Baseline: `{baseline.json path}` ({date}, score {N})
- Score delta: {baseline} → {current}
- Fixed since baseline: {list}
- New since baseline: {list}

## Ship-Readiness

**Verdict:** SHIP / SHIP WITH CONCERNS / DO NOT SHIP

- {one line justifying the verdict: remaining criticals/highs, score, reverts}

**PR summary line:**
> QA found {N} issues, fixed {M} ({verified} verified, {best-effort} best-effort, {reverted} reverted), health score {X} → {Y}.
