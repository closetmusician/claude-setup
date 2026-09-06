# Part B — MOR deck (Boards section) map + editing method

The Boards section of the MOR deck is a fixed set of slides. In the July 2026 deck they were
slides 58–62 (+ a Q2 retrospective on 61); locate them by title, not number, since numbering drifts.

## Slide map (fill / refresh these)
- **Exec Summary** ("Governance BU: Boards Executive Summary"): July Recap (why-led bullets, STE100,
  measured), August Strategy & Priorities, Key Discussion Points. This is the slide people read —
  make the **root cause lead** each recap bullet, per `style-ste100.md`.
- **GDR slide** ("Boards GDR: … vs Target"): two 4×4 tables (regional GDR, segment GDR) each with a
  **Notes column** to fill with the root cause; a "Key Churn Drivers" box; churn-mitigation + Q3
  outlook boxes.
- **Bookings slide** ("Boards Bookings: … vs Target/YA"): a 7×6 region×segment table; a 7×2 **Notes
  table** to fill with root causes; Key Initiatives + Q3 outlook boxes.
- **Quantitative summary**: large July-QTD / YTD / pipeline-gen tables (region × segment). Reference
  data — usually already complete; touch lightly.
- **Q2 retrospective / outlook**: fix any placeholder title ("XXX"); leave `[need source]` cells that
  genuinely need a Finance sheet not in the corpus — do NOT invent them.

## Editing method
- The registry PPT tools (`graph-edit-pptx.js`, `ooxml-surgery.py`) only accept a **SharePoint URL**,
  not a local file. The deck is local, so use **python-pptx** (`uv run --with python-pptx python`).
  This is the sanctioned local path — the wrapper tools use python-pptx under the hood.
- **Back up first**: `cp` the original into `output/` (and it is git-tracked). Never edit without a backup.
- **Inspect before editing**: dump shape indices, types, and table cell grids for the target slides;
  target edits by exact shape index / cell coordinate. Do not touch the `think-cell data - do not
  delete` OLE object or LINE shapes.
- **Augment vs rewrite** (the user's rule): fill blank cells and add depth by default; rewrite prose
  only where you are confident and it adds color (e.g., a placeholder title, or a recap bullet that
  must lead with the why). Preserve run formatting — copy the font from an adjacent run when adding text.
- **Verify**: reopen the saved deck with python-pptx and confirm all slides read (no corruption)
  before reporting done.

## Accuracy carry-over
Any correction the report makes MUST also land on the slides (e.g., D1P headline is YTD not month;
a churn "example" that is forward-risk not this-month; a mis-coded competitive loss; a corrected
ratio). The deck and the report must not disagree.
