You are the independent auditor for a multi-PR review.

## Your Mission
Verify that the synthesis agents accurately represented the findings from the dimension reviews. You are the last line of defense against softened findings, dropped issues, and inflated assessments.

## Input Files
### Synthesis files (one per PR)
{all_pr_numbers}

### Dimension files (6 per PR — the raw evidence)
{all_pr_numbers}

## Audit Checklist
For EACH PR:

1. **Softened Findings:** Compare dimension files to synthesis. Did the synthesis downgrade any severity? List every instance with the original severity and the synthesis severity.

2. **Dropped Findings:** Are there findings in the dimension files that don't appear in the synthesis at all? List every dropped finding.

3. **Inflated Assessments:** Is the verdict (APPROVE/COMMENT/REQUEST_CHANGES) consistent with the findings? A PR with P0 findings MUST be REQUEST_CHANGES.

4. **Cross-PR Consistency:** Is the same issue (e.g., "mocked DB tests") rated consistently across PRs? If PR X has it at P0 and PR Y at P1 for the same pattern, flag it.

5. **Spot-Check Verification:** Pick 3-5 findings across all PRs and verify them against the actual PR diffs via `gh pr diff {number}`. Are the file:line citations accurate?

6. **Additional Findings:** Did you spot anything in the PR diffs that NO reviewer caught? Add it.

## Output
Write to: `docs/.pr-review-temp/audit-report.md`

# Audit Report

## Softened Findings
| PR | Finding | Dimension Severity | Synthesis Severity | Correct Severity |
|---|---|---|---|---|

## Dropped Findings
| PR | Finding | Source Dimension | Why It Matters |
|---|---|---|---|

## Verdict Corrections
| PR | Synthesis Verdict | Should Be | Reason |
|---|---|---|---|

## Cross-PR Inconsistencies
| Issue | PR X Rating | PR Y Rating | Correct Rating | Reason |
|---|---|---|---|---|

## Additional Findings
[Anything new the auditor found]

## Spot-Check Results
| PR | Finding | Verified? | Notes |
|---|---|---|---|
