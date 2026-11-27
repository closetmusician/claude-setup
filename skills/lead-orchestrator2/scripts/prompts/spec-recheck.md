# ABOUTME: Codex prompt template for spec re-check (arm D).
# ABOUTME: Placeholders: TASK_LABEL, REQUIREMENTS, DESIGN, GOLDEN_REF.
# ABOUTME: Reads the edited design from scratch and checks for conflicts.
# ABOUTME: Fills via bash/perl one-liner substitution. Never edit this file by hand.
# ABOUTME: Written 2026-11-15. Updated 2026-11-16 for REQ-06 (golden_ref, authority line). Updated 2026-11-23: design-fit check against the system explainer (owner ask after the discover-speed miss).

Read {{REQUIREMENTS}} and {{DESIGN}} (just edited) for {{TASK_LABEL}} from scratch. Check for conflicts.
Golden reference: {{GOLDEN_REF}}. Read every file it names.
When files clash, the owner's product docs named in the golden reference win, then the requirements, then the design. Note the clash; never stop on it.
This build writes no tests. Missing tests are not a conflict.
Design-fit check. Run it only when the golden reference names the owner's system design doc. Test the requirements and the design against it from first principles. Check four things. Does each recurring step's work grow with change, not with all history, and does each of its data reads name a bound (a cutoff, cursor, changed-since list, task scope or record id)? A one-time import, a requested history report or a single-record read is fine when the doc allows it. Does any search term or filter select almost everything? Does a failure or unknown value become a good value such as "keep", $0, "unchanged" or "done"? Does any line break the design doc's intent? A finding counts only when it breaks the doc's stated intent. List each break as a P1 conflict that starts "P1: EXPLAINER:", even when the requirements allow it. Quote both lines.
Print the verdict. Line 1 is "NO CONFLICTS" when no P0 or P1 conflict exists. Otherwise list each conflict on its own line, starting with "P0:" (a requirement cannot be met, or two binding lines contradict) or "P1:" (a wrong reading changes what the user sees or the data produced). Do not list P2 details; they are the coder's choice.
