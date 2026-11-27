# ABOUTME: Codex prompt template for spec fix (arm D).
# ABOUTME: Placeholders: TASK_LABEL, REQ_IDS, REQUIREMENTS, DESIGN, RUN_DIR, GOLDEN_REF.
# ABOUTME: Fills via bash/perl one-liner substitution. Never edit this file by hand.
# ABOUTME: Written 2026-11-15. Updated 2026-11-16 for REQ-06 (golden_ref, authority line). Updated 2026-11-23: design-fit check against the system explainer (owner ask after the discover-speed miss).

You are fixing a spec before coding starts. Work only inside this folder.
Read {{REQUIREMENTS}} and {{DESIGN}}. The task is {{TASK_LABEL}} (REQ ids: {{REQ_IDS}}, plus any all-task REQs).
Golden reference: {{GOLDEN_REF}}. Read every file it names.
When files clash, the owner's product docs named in the golden reference win, then the requirements, then the design. Note the clash; never stop on it.
Edit {{DESIGN}} so that every part about this task matches {{REQUIREMENTS}}. {{REQUIREMENTS}} wins when the two differ.
Never edit {{REQUIREMENTS}}.
Design-fit check, before you edit. Run it only when the golden reference names the owner's system design doc (for example a system explainer). Test the requirements and the design against that doc from first principles, not only against each other:
- For each recurring step (a daily or scheduled run): does its work grow with what changed since the last good run, not with all saved history? Each data read in a recurring step names its bound: a cutoff, a cursor, a changed-since list, a task scope or a record id. A one-time import, a requested history report or a single-record read is fine when the design doc allows it.
- Does any search term, filter or match select almost every item? A term must be specific enough to identify the thing it looks for.
- Does any failure, missing value or unknown value turn into a good value, such as "keep", $0, "unchanged" or "done"?
- Does any line copy a rule or decision that already lives somewhere else?
- Does any line break the intent of the system design doc, even if the requirements allow it?
A finding counts only when it breaks the design doc's stated intent; quote the doc line that it breaks. Write each finding to {{RUN_DIR}}/ambiguities.md as one line that starts "P1: EXPLAINER:", even when it is a definite break and not an ambiguity. Quote the spec line and the design doc line (file and location). It is P1 even when the requirements allow it, because the owner's design doc wins. These lines are an exception to the severity rules and the "Most points are P2" rule below.
This build writes no tests. Mark every test-plan or test-file requirement in {{DESIGN}} as "out of scope for this build: no tests". Do not delete it.
Write every point that stays ambiguous in both files to {{RUN_DIR}}/ambiguities.md, one per line. If there is none, write the single line NONE.
Start each line with exactly one tag:
- "P0:" when a requirement cannot be met as written, or two binding lines contradict each other.
- "P1:" when a wrong guess changes what the user sees or the data the feature produces, and neither file points to an answer.
- "P2:" for every other point: names, file paths, internal interfaces, formats, display limits, ordering, error wording and other details. A choice that sets which or how much data a recurring step selects or reads (its read bound or selection rule) is never P2. It is P1. Batch and page sizes stay P2. P2 is the coder's choice: the coder picks the simplest choice that meets the requirements.
Most points are P2. When unsure, ask: "would the owner care which way the coder goes?" If no, it is P2.
Never invent an answer to a P0 or P1 point. Opus settles those after you.
At the end, print a short list of the edits you made.
