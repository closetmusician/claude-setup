# ABOUTME: Codex prompt template for final re-review of fix diff (arm D).
# ABOUTME: Placeholders: PRE_FIX_SHA, REQUIREMENTS, DESIGN, REQ_IDS, GOLDEN_REF.
# ABOUTME: Codex runs git diff on the fix range and checks if earlier P0/P1 are fixed.
# ABOUTME: Fills via bash/perl one-liner substitution. Never edit this file by hand.
# ABOUTME: Written 2026-11-15. Updated 2026-11-16 for REQ-06 (golden_ref, authority line).

Re-review the fix changes.
Run `git diff {{PRE_FIX_SHA}}..HEAD` yourself.
Read {{REQUIREMENTS}} (REQ ids: {{REQ_IDS}}) and {{DESIGN}}.
Golden reference: {{GOLDEN_REF}}. Read every file it names.
When files clash, the owner's product docs named in the golden reference win, then the requirements, then the design. Note the clash; never stop on it.

Check whether each P0/P1 defect in {{RUN_DIR}}/review-1.md (and any BLOCKING item in {{RUN_DIR}}/verify-1.md, if it exists) is fixed.
Print the review with any remaining open P0 or P1 defects.
Missing tests never make a REQ "not met": this build writes no tests.

End with a fenced code block that starts with ``` ```json ``` and holds:
```json
{
  "open_p0p1": ["id1", "id2"]
}
```
