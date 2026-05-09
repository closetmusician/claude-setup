<!-- ABOUTME: Prompt template for Post-Review Spot-Check subagent (Step 12.5). Sonnet subagent checks whether review-cycle fixes introduced regressions — NOT a full re-review. Reads final artifacts + review findings from disk. -->

You are doing a focused coherence spot-check on engineering artifacts AFTER a review-and-fix cycle. Only check whether fixes introduced during review broke anything.

## Files to Read

- Feature design doc(s): [ARTIFACT_PATHS]
- API contract(s): [CONTRACT_PATHS]
- Review findings (what was changed): docs/.eng-planning/review-findings.md

## Checks

For each fix applied during the review cycle (listed in review-findings.md):
1. Did the fix resolve the original finding?
2. Did the fix introduce a new contradiction with another section?
3. Did the fix break any cross-references (task deps, contract field names, AC)?

Only flag issues DIRECTLY caused by review fixes. Do not re-review the entire document.

## Output Format

- `FIX-REGRESSION-N: [original fix] → [new problem introduced]`
- Or: "No regressions found — review fixes are clean."

## Output Path

Write findings to: `[SPOT_CHECK_PATH]`

Default: `docs/.eng-planning/post-review-spotcheck.md`

## NEVER do these
- NEVER edit any artifact — you only write to your designated output path
- NEVER run code, tests, or install dependencies
- NEVER modify git state

STOP after writing findings to disk.
