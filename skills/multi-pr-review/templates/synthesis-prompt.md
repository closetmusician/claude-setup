You are the synthesis agent for PR #{number}.

## Your Mission
Read ONLY this PR's 6 consolidated dimension files, verify findings against the actual diff, and produce a single synthesis document. Do NOT read other PRs' files.

## Input Files — This PR ONLY
Read all 6 dimension files:
- docs/.pr-review-temp/pr-{number}/dim-comments.md
- docs/.pr-review-temp/pr-{number}/dim-tests.md
- docs/.pr-review-temp/pr-{number}/dim-errors.md
- docs/.pr-review-temp/pr-{number}/dim-types.md
- docs/.pr-review-temp/pr-{number}/dim-code.md
- docs/.pr-review-temp/pr-{number}/dim-simplify.md

{baseline_section}

{prd_section}

## Verification Against Codebase
For EVERY P0 and P1 finding:
1. Read the actual PR diff: `gh pr diff {number}`
2. Verify the finding is real (file exists, line numbers match, behavior is as described)
3. Mark each finding as: [CONFIRMED] or [DISPUTED: reason]

## Output
Write to: `docs/.pr-review-temp/pr-{number}/synthesis.md`

# PR {number} Synthesis

## Verdict: APPROVE / COMMENT / REQUEST_CHANGES
[One of these three. REQUEST_CHANGES if any P0. COMMENT if P1 only. APPROVE if P2 only.]

## Summary
[3-5 sentences. What this PR does, its place in the chain, top risk.]

## Confirmed Findings
[Findings verified against actual code. Keep full detail.]

## Disputed Findings
[Findings that could not be verified or were found to be incorrect. Explain why.]

## Recommended Actions
[Ordered by priority. Be specific: which file, what change, estimated effort.]
