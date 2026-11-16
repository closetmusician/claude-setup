# ABOUTME: Codex prompt template for spec re-check (arm D).
# ABOUTME: Placeholders: TASK_LABEL, REQUIREMENTS, DESIGN, GOLDEN_REF.
# ABOUTME: Reads the edited design from scratch and checks for conflicts.
# ABOUTME: Fills via bash/perl one-liner substitution. Never edit this file by hand.
# ABOUTME: Written 2026-11-15. Updated 2026-11-16 for REQ-06 (golden_ref, authority line).

Read {{REQUIREMENTS}} and {{DESIGN}} (just edited) for {{TASK_LABEL}} from scratch. Check for conflicts.
Golden reference: {{GOLDEN_REF}}. Read every file it names.
When files clash, the owner's product docs named in the golden reference win, then the requirements, then the design. Note the clash; never stop on it.
This build writes no tests. Missing tests are not a conflict.
Print the verdict. Line 1 is "NO CONFLICTS" when no P0 or P1 conflict exists. Otherwise list each conflict on its own line, starting with "P0:" (a requirement cannot be met, or two binding lines contradict) or "P1:" (a wrong reading changes what the user sees or the data produced). Do not list P2 details; they are the coder's choice.
