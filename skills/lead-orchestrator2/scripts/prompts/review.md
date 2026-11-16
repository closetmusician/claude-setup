# ABOUTME: Codex prompt template for code review (arm D).
# ABOUTME: Placeholders: BASE_REF, DESIGN, REQUIREMENTS, REQ_IDS, GOLDEN_REF.
# ABOUTME: Codex runs git diff itself, reads requirements and design, then prints the review.
# ABOUTME: Fills via bash/perl one-liner substitution. Never edit this file by hand.
# ABOUTME: Written 2026-11-15. Updated 2026-11-16 for REQ-06 (golden_ref, authority line).

Review the code changes for this task.
Run `git diff {{BASE_REF}}..HEAD -- . ':!{{DESIGN}}'` yourself.
Read {{REQUIREMENTS}} (REQ ids: {{REQ_IDS}}, plus any all-task REQs) and {{DESIGN}}.
Golden reference: {{GOLDEN_REF}}. Read every file it names.
When files clash, the owner's product docs named in the golden reference win, then the requirements, then the design. Note the clash; never stop on it.

Print the review in two parts:
(a) One table row per REQ id in this exact format: | REQ-XX | met/not met | file:line | test command |
    Mark a REQ "not met" only when the code behaviour is missing or wrong.
    Missing tests never make a row "not met": this build writes no tests.
    Every "not met" row must also appear in the defects JSON with sev P0 or P1, and with a repro when one exists.
(b) Defects table in this exact format: | id | P0/P1/P2 | file:line | repro command | what |

End with a fenced code block that starts with ``` ```json ``` and holds:
```json
{
  "defects": [
    {"id": "string", "sev": "P0|P1|P2", "has_repro": true|false, "file": "string", "repro": "string", "what": "string"}
  ]
}
```
