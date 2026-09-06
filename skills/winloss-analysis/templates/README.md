<!-- ABOUTME: Guide to the ONE GOLDEN report — a STRUCTURAL REFERENCE, not a file to clone.
     ABOUTME: Structure authority is reference/report-structure.md; writeout mechanics are SKILL.md
     ABOUTME: STEP 4b. Consult GOLDEN-why-we-win.html one section at a time for markup; NEVER copy
     ABOUTME: the whole file and swap the data (that stalls the run and drifts stale numbers in).
     ABOUTME: Re-derive every figure from the new Finance workbook; carry no number forward. -->

# GOLDEN report — structural reference

`GOLDEN-why-we-win.html` is the **structural reference** for both win/loss reports — a real Board
& Leadership Collaboration (BLC) win report that passed independent Codex review. Use it to see
**how one section is marked up**: a stat band, a theme table, a competitor `table.plain`, a
`.quote`/`.attrib` block, the running header/footer. There is only ONE golden file on purpose — a
second parallel example drifts out of sync with the first and with the rules. The lose report uses
the **same skeleton** with lose framing, the three lose-only sections, and `<body class="theme-lose">`.

**It is a reference, not a master.** Do NOT copy the whole file and swap in new data. That
approach (a) makes the report a slave to a prior period's structure instead of the spec, and (b)
forces one agent to load the entire golden plus every research file and emit ~80KB in a single
write — which stalls the run (it failed twice in Aug 2026, frozen ~30 min each). Author each
section from the spec and its research; write incrementally. **The two sanctioned writeout paths
and the mandatory independent auditor live in `SKILL.md` STEP 4b — follow one of them.**

**The structure source of truth is `../reference/report-structure.md`, not this file.** That file
owns the section order, the narrative-only (no-box) rule, the exec-summary composition, and the
competitor-table spec. If this file and `report-structure.md` ever disagree, `report-structure.md`
wins — and the disagreement is a bug to fix.

## How to use it

1. **Read the spec first** — `../reference/report-structure.md` for the section order and rules,
   `SKILL.md` STEP 4b for which writeout path to use.
2. **Consult the golden per section, not as a whole** — when you write a stat band or a table,
   open the matching section of `GOLDEN-why-we-win.html` to copy the class usage and markup shape
   (see KEEP below). Do not load the whole file to clone it.
3. **Author from research** — write each section's numbers and prose from the Finance spine and
   the mining files, not from the golden's data (see REPLACE below).
4. **Re-derive every figure from the new period's Finance workbook** — never carry a number
   forward (see the warning at the end).

## Stylesheet — link the fixed `report.css`

Both reports share one stylesheet: `../reference/report.css`. That stylesheet was **fixed to
flow, not clip** — the earlier build set `.sheet { overflow: hidden; height: <fixed>in }`, which
silently cut off any section longer than one page; `report.css` now uses `overflow: visible` and
`min-height` so long sections continue onto a following page. The GOLDEN file ALSO carries a
small in-file `@media screen` / `@media print` override block as belt-and-suspenders (it forces
`height:auto` + `overflow:visible` on screen and lets sections break across pages in print) —
**keep that block**; it does not touch the shared stylesheet.

Note when copying: the GOLDEN file as checked in links `report.css` with a **bare, same-directory
href** (`<link rel="stylesheet" href="report.css">`), but the stylesheet actually lives one level
up at `../reference/report.css`. When you place your copy, point the `<link>` at wherever
`report.css` sits relative to it (e.g. `../reference/report.css`) so it resolves — otherwise the
report renders unstyled.

## KEEP (structure and markup — verbatim)

- **The sheet/page structure.** Each logical page is a `<section class="sheet tighten">` with the
  `<!-- ===== PAGE/SHEET N ===== -->` markers and the running header (`.rh` / `.rh-left` /
  `.rh-right`) and footer furniture. Keep the section sequence in `report-structure.md`: one-page
  **decision page** first (stat tiles + lead paragraph + **Key Insights** table + the matrix, and
  NOTHING else — no themes table and no competitor table on page 1), then the three **region
  sections** (AMER/EMEA/APAC), each opening with its **top-three insight block** and carrying the
  themes table, the competitor table and its outlier deep-dive **only where that outlier's
  mechanism is not already one of the region's top-three insights**, then **Actions / Strategic
  Implications**, the **Appendix** (+ Glossary) and
  **Open Data Requests**. **Sources ship as a SEPARATE FILE** (`why-we-{win,lose}-sources.md`),
  not as a page of the report. The lose report adds the late-stage-silence deep-dive and a
  ONE-entry retention cross-reference (the full retention treatment is its own decision brief).
  **The whole report is 10 PAGES OF RENDERED PDF, appendix 2 of those 10, and no sheet runs over
  650 words.** A `.sheet` div is not a page — it has `min-height` and `overflow: visible`, so it
  grows and one div can print as three pages. Render the PDF before the audit and count there.
- **Body class usage** exactly as-is — the classes the golden actually uses in the body:
  `.stat/.num/.lbl/.sub` stat tiles, `.rep-head`, `.quote` / `.attrib`, `.cite` superscripts,
  `.section`, `.product-line`, `.rf`, `.tighten`.
- **Lead with WHY in PROSE — and cap it.** The lead paragraph is **at most five sentences and 120
  words**. Sentence 1 states THE single biggest driver with its number, straight from
  `KEY-INSIGHTS.md` §1. Sentences 2–4 give ranked drivers #2 and #3, one each. A fourth driver, a
  refutation, or a nuance belongs in the region sections, not here. Method and basis do NOT belong
  here: one why-sentence followed by three caveat sentences is the classic FAILURE, not a fix.
  Push basis/amendment/competitor-capture caveats to the Appendix — and add **NO pointer to them**.
  The paragraph carries no citation markers, no method words, and must not end on a methodology
  signpost; the last sentence is the emphasis position and belongs to a finding.
  The golden carries **no `.callout` boxes and no "How to read this report"
  note** — every why, method, and caveat is ordinary `<p>` prose next to what it explains. Do NOT
  add a `.callout`, a disclaimer `.note`, or a how-to-read block.
- **The geo × segment Voice of the Customer** blocks — a `Voice of the Customer` `.rep-head` with
  `.attrib` carrying geo AND segment. **There is no per-cell quote floor.** Cap the report at 15
  quote blocks (one block = one `.rep-head` group), keep one per mechanism, and never print the
  same quote twice. Headers carry the cell name ONLY — no "(5 verified)", no "below the 3-quote
  floor". A quote from a Acme employee, including a Salesforce close note, is labelled
  "Deal evidence", not customer voice.
- **The competitor tables** — region and segment sheets only (never page 1). Each follows its
  section's themes table, lists 3–5 competitors, and
  carries the `Confirmed named cases (count)` column — never a percentage on a small named
  sample. In the LOSE report the slice's Finance "Chose Competitor" rate is stated ONCE above the
  table. **In the WIN report it is not**: "Chose Competitor" exists only on lost records, so a
  win-side table introduced by that rate proves a win with a loss denominator. The win report
  states the competitive share of WINS from won-deal notes, or prints the counts with no rate and
  files an Open Data Request.
- **The Appendix glossary** (every abbreviation defined: BLC, AMER/EMEA/APAC, ENT/MM/SMB, DACH,
  SFDC, GDR, Finance-clean, etc.) and the **appendix basis/caveats** prose (including the Gong-
  access caveat where quotes rest on Glean snippets + Salesforce notes).
- **Attribution** — INLINE, in the source's own name (`— Bank of Hawaii, Gong, Mar 2026`).
  `<sup class="cite">N</sup>` markers are allowed only in the region and appendix sections, never
  on the decision page and never stacked; they map to the SEPARATE sources file. The golden file's
  262 markers are the defect this rule replaces — do not copy that density.

## REPLACE (the data — all of it)

- **Every figure** — win/loss counts, rates, ARR totals, per-cell numbers, stat tiles.
- **Every quote** and its attribution (customer, call, won/lost) — all from the new period's
  verified transcripts/notes.
- **Every period label** — titles, running headers, cover text, section headings ("July 2026" ->
  the new period).
- **Every citation** — rebuild the SEPARATE sources file (`why-we-{win,lose}-sources.md`) for the
  new period. Prefer inline attribution in the body (`— Bank of Hawaii, Gong, Mar 2026`);
  superscript markers survive only in the region and appendix sections, never on the decision
  page. No dangling cite numbers, no orphan sources.

## Warning — re-derive every number; carry nothing forward

Do **not** carry any prior-period number forward. Every figure in the new report must be
**re-derived from the new period's Finance workbook, on the Finance-clean basis** (in-scope
regions, the report product line only, excluding `Duplicate Opportunity` rows and rows flagged
`< $5K Amendment`). Compute the all-sizes basis too, but publish it ONLY in the single appendix
comparison table — never paired with a body figure, a stat tile, or a matrix cell.
A stale headline rate or ARR total that
survived a copy-paste is the most likely and most damaging error in this workflow. If a number
cannot be traced to the new workbook, it does not go in the report.
