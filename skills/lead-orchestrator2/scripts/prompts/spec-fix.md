# ABOUTME: Codex prompt template for spec fix (arm D).
# ABOUTME: Placeholders: TASK_LABEL, REQ_IDS, REQUIREMENTS, DESIGN, RUN_DIR, GOLDEN_REF.
# ABOUTME: Fills via bash/perl one-liner substitution. Never edit this file by hand.
# ABOUTME: Written 2026-11-15. Updated 2026-11-16 for REQ-06 (golden_ref, authority line).

You are fixing a spec before coding starts. Work only inside this folder.
Read {{REQUIREMENTS}} and {{DESIGN}}. The task is {{TASK_LABEL}} (REQ ids: {{REQ_IDS}}, plus any all-task REQs).
Golden reference: {{GOLDEN_REF}}. Read every file it names.
When files clash, the owner's product docs named in the golden reference win, then the requirements, then the design. Note the clash; never stop on it.
Edit {{DESIGN}} so that every part about this task matches {{REQUIREMENTS}}. {{REQUIREMENTS}} wins when the two differ.
Never edit {{REQUIREMENTS}}.
This build writes no tests. Mark every test-plan or test-file requirement in {{DESIGN}} as "out of scope for this build: no tests". Do not delete it.
Write every point that stays ambiguous in both files to {{RUN_DIR}}/ambiguities.md, one per line. If there is none, write the single line NONE.
Start each line with exactly one tag:
- "P0:" when a requirement cannot be met as written, or two binding lines contradict each other.
- "P1:" when a wrong guess changes what the user sees or the data the feature produces, and neither file points to an answer.
- "P2:" for every other point: names, file paths, internal interfaces, formats, limits, ordering, error wording and other details. P2 is the coder's choice: the coder picks the simplest choice that meets the requirements.
Most points are P2. When unsure, ask: "would the owner care which way the coder goes?" If no, it is P2.
Never invent an answer to a P0 or P1 point. Opus settles those after you.
At the end, print a short list of the edits you made.
