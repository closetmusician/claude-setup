# Content-quality rubric — the bar between a golden report and a mediocre one

Run this scored self-check on BOTH reports before you declare the run done. It is about
**depth, insight, and truth** — not HTML. Structure/format lives in
`reference/report-structure.md`; the number-authority and caveats live in
`reference/basis-and-caveats.md`; the "keep asking why" method lives in
`reference/root-cause-protocol.md`. This file is the *acceptance gate* that decides whether
the draft those files produced is actually golden.

Score each of the 10 dimensions **0 / 1 / 2**:

- **0 = FAIL** — a mediocre-report symptom is present (see the FAIL rows).
- **1 = PARTIAL** — mostly there, but at least one material finding or section slips.
- **2 = PASS** — clears the bar on every material finding, as the GOLDEN files do.

**DO NOT SHIP** if any of these is true:

- Dimension 1 (root-cause depth) or Dimension 3 (truth / no fabrication) scores **below 2**.
  These two are non-negotiable — a report that flatters or that rests a headline on a
  picklist code is worse than no report.
- **Total < 18 of 20.**
- **Any dimension scores 0.**
- **The STE ship gate fails.** Run the checklist in `reference/STE-STYLE-GUIDE.md` over BOTH
  reports as a separate hard stop, not just inside Dimension 6. Every sentence must read in
  ASD-STE100 Simplified Technical English: one idea per sentence, under 30 words, active voice,
  every acronym expanded on first use, one term per concept, no jargon without a one-clause
  gloss, no filler, no free-floating reconciliation notes. A report can score well on depth
  and still be un-shippable prose — STE is a gate of its own.

Golden-report baseline: both `templates/GOLDEN-why-we-{win,lose}.html` scored **14/14** on the
earlier 7-dimension gate. Use them as the worked reference for the depth/insight/truth examples
below — but note they would NOT pass Dimensions 8–10 (economy, root cause, language): they are
long, they repeat themes across levels, and they carry method words in the body. Copy their
rigor, not their length.

---

## 1. Causal-mechanism depth — TOP CRITERION (weight it first)

*Does each material finding name the ATTRIBUTE that changed the buyer's decision — not just a
lever we own or a cohort the dashboard cut?*

- **PASS (2):** Every headline theme and every region insight has a complete causal chain
  (`context/trigger → decision attribute → intervention → buyer-behavior change → outcome`), a
  within-cohort win/loss contrast, at least three named proof deals, one contradictory case,
  decision evidence (Gong or verbatim SFDC), and Finance sizing. The GOLDEN competitor report
  names the attribute: a competitor's contract-end or version-EOL plus a funded migration removed
  the switching cost, and it proves it with named deals ($650K across 25 opps). "Brand Strength"
  is restated as the observable attribute *"directors already run Acme on their other board
  seats"* with the Csquare call; "Chose Competitor" is read at record level (Dah Sing a no-bid
  over Hong Kong residency; Racing Victoria a GovernAI trial failure).
- **PARTIAL (1):** One secondary finding lacks a contradictory case or a complete chain, or a
  mechanism is asserted without a call-id / cell / note behind it.
- **FAIL (0):** **Any headline ends at a channel, segment, list, gate, package, price, team or
  other Acme-controlled object without naming the decision attribute** ("referral supply",
  "the new-logo target list", "expansion"). **FAIL (0):** any headline is supported only by
  Finance fields, aggregate rates, or a reason code — a cohort readout dressed as a cause.

**Owner's test:** ask of each row, "what ATTRIBUTE made this win or loss happen?" If the cell
answers only "which lever do we own?" or "which cohort is this?", it FAILS. Would deleting every
Gong/SFDC quote leave the insight, its rank and its ARR unchanged? If yes, it is descriptive
segmentation, not a causal insight — FAIL.

**Sizing-floor FAIL (0):** the insight's published ARR exceeds the ARR of the deals where the
attribute is actually evidenced (its coded-attribute floor). Sizing a mechanism proven on $703K
of deals to a $2.67M cohort is over-claiming — the attribute is real but the number is a readout.
A separately-labelled cohort context figure is fine; an inflated headline ARR is not.
**Fusion FAIL (0):** two distinct attributes fused into one compound cause without the same
deals carrying both parts, or an ownership/outcome bucket ("Acme loses to itself", "stalled
expansion") presented as a decision attribute.

---

## 2. Insight over description — does it explain, or just report?

*Does each table earn its place with "why" bullets, and is there a cross-report through-line?*

- **PASS (2):** The report opens with ONE headline insight a reader can repeat from memory,
  followed by three-to-five drivers ranked by ARR with shares that sum to a stated coverage
  figure. Every region sheet opens with its own top-three insight block. Every table still
  carries its 2–4 sentence prose why. **A report where every table has a why paragraph but no
  reader can name the top finding scores 0, not 2 — per-table quality is necessary and not
  sufficient.** (GOLDEN win report has a "Why these themes, not others"
  prose paragraph after its top-themes table — which now sits on the region sheets, not page 1;
  every segment table carries a prose "why"
  paragraph — never a `.callout` box.) There
  is a single **cross-report through-line** stated explicitly and consistently in both reports
  — in the GOLDEN pair it is *installed-base farming / expansion + referral, NOT net-new
  conquest* (win) mirrored by *genuine competitive loss is narrow; most "losses" are miscodes,
  internal-Brainloop moves, and coverage gaps* (lose). The two reports read as one argument
  seen from two sides.
- **PARTIAL (1):** Most tables have why-bullets, but at least one major table (e.g. exec
  top-themes, or a segment table) is left as bare rows or only a `.note`. Or the through-line
  exists but is implicit / stated in only one of the two reports.
- **FAIL (0):** Tables restate the numbers with no mechanism bullets — the report reads as
  "what happened" with no "why". No cross-report spine.

**The three obligations this dimension also scores** (SKILL.md STEP 3b–3d):
1. **Growth versus rate.** A rate story is not a money story. Every claim built on a win rate
   states whether it also holds in money and in new customers — a cell that wins most often
   because it is mostly expansion grows the base and adds almost no customers. Where two
   published findings pull against each other, the report names the tension in one short block.
   Absent = PARTIAL at best.
2. **Expected ARR per opportunity.** Wherever an Action moves volume between channels or
   segments, both sides carry an expected ARR per opportunity (win rate × that channel's ASP),
   not just the two win rates. A rate comparison alone is not a budget decision.
3. **[LOSE] Controllable share of the loss book, in dollars and as a share** — with a per-region
   figure. A lost-ARR total with no answer to "how much of it could we have had" is a PARTIAL.

**Self-check:** Cover each table's why-bullets and ask "could a reader derive these bullets
from the row values alone?" If yes, they are description, not insight. Can you state the
one-sentence through-line, and does it appear in BOTH reports? Is each of the three obligations
above discharged, or knowingly absent with a reason?

---

## 3. Truth / no fabrication — NON-NEGOTIABLE

*Every number traces to Finance on a named basis; nothing modelled is dressed up as measured.*

- **PASS (2):** Every rate/count/ASP is computed on the Finance-clean basis and **that single
  figure is published in the body**; the all-sizes counterpart lives in the ONE appendix
  comparison table — never averaged, never paired down the body. Lost ARR is labelled
  **"lost opportunity ARR — not booked revenue"**, never "ARR lost" and **never "modelled"**: it
  is a direct `REPORTING_ARR` sum over the lost records, and calling a sum a model invites the
  reader to discount a correct number. "Modelled" is reserved for a figure that is genuinely
  derived rather than summed, and the derivation is named on the same line.
  No derived percentage is presented as a measured field.
  Competitor presence is reported as a **confirmed named-case COUNT**, never a percentage of a
  small named sample; the capture limitation
  (`OPP_COMPETITOR_PROSPECT_CURRENTLY_USES` is **0% populated / 434 of 434**, so every count is
  a floor) is stated once, in the appendix. Every surviving citation resolves in the separate
  sources file; no document cites itself.
  **Any per-competitor head-to-head win rate is counted by the SKILL.md STEP 2 method — from
  the RECORD (structured field + free-text notes on BOTH win and loss sides, all product lines,
  including renewal-churn losses), NOT quote-gated** — and is labelled a FLOOR biased upward
  (incumbent losses are under-named). A head-to-head rate built only from quote-backed deals, or
  only from the loss side, or only from the structured field, is a fabricated ratio and fails here.
  **Both sides of every ratio share ONE filter chain** (period, region, deal type,
  source/channel, segment, stage, reason code) — a ratio built from two populations is a
  fabrication of the comparison even when each figure is separately correct, and it is scored
  here, not under economy (see `reference/report-structure.md` §Population matching).
  **Citation markers are `<sup class="cite">`; `grep -c 'span class="cite"'` returns 0** —
  `report.css` and `convert_reports.py` both match `sup` only, so a span marker is an invisible
  citation and a lost footnote.
- **PARTIAL (1):** One stray rate on the wrong basis, or one competitor row carrying a
  percentage instead of a count, or one figure carried forward / re-rounded instead of copied
  exactly.
- **FAIL (0):** Any invented number/quote/date; a modelled figure presented as an outcome; a
  direct sum labelled "modelled"; a region population published over a portfolio denominator; a
  derived % masquerading as a measured field; an averaged basis; a rate whose numerator and
  denominator use different bases; a product NUMBER (adoption/attrition/retention/win rate)
  with no Finance/Tableau/Salesforce/Gainsight cell behind it; or a negative product JUDGMENT
  ("thin/weak/failed/not good enough") with no first-hand customer quote (Gong/SFDC) — an
  ungrounded knock or an internal-opinion basis (Slack/Teams/OKR/deck) is a truth defect.

**Self-check:** Can every figure be traced to the Finance spine CSV or a named research file?
Does any sentence imply the competitor field measured something? Was every head-to-head win rate
counted from records on BOTH sides (not quote-gated, not loss-side-only, not structured-field-only)
and labelled a floor? Does the word "modelled" appear
on any figure that is a direct sum (it must not)? Does any insight print a region numerator over
a portfolio denominator, or drop a qualifier its source attached ("this is a floor")?
Is every body figure on the one Finance-clean basis, with the
all-sizes comparison confined to the single appendix table? Does any product claim rest on an
internal source? If so it fails Dim 3.

---

## 4. Falsification — did strong claims survive a real test?

*Did the RESEARCH test the counter-hypotheses — and did the report publish only the survivor?*

> **The counter-hypothesis test is a research obligation, not a report section.** It is scored on
> the research files, not on body prose. The report publishes the surviving conclusion; the
> rejected alternatives and their evidence live in the appendix or the companion appendix file.
> **"tested and rejected", "tested and ruled out", "falsified" and "counter-hypothesis" in the
> body are a Dim 10 violation**, and three or more of them is a Dim 4 PARTIAL as well — the
> report is defending itself instead of stating a finding.

- **PASS (2):** Every strong / surprising claim was tested against the alternatives in the
  research files, and the body carries the conclusion alone. GOLDEN lose
  report explicitly refutes *"BoardWise is taking DACH"* (never the confirmed winner of any
  mined deal) and *"a single ME&A vendor is beating us"* (0 external winners named); GOLDEN win
  report refutes *GovernAI as an SMB buying driver* (seller-led attach, not customer pull) and
  shows APAC's referral edge survives the amendment correction — each tested in the research and
  published as a plain finding.
  **The rejected alternatives belong in the appendix or the companion appendix file, never in
  body real estate.** A report whose headline is what the
  numbers are NOT ("conquest is the exception", "most losses are not competitive defeats") has
  published its footnote and buried its finding: state the positive driver first, and the
  refutation where it does its work. State only what the evidence rules out: stage data can
  falsify "a competitive evaluation happened", it cannot falsify "product or price had no
  effect".
- **PARTIAL (1):** The headline claims are tested, but one strong secondary claim is asserted
  with no alternative considered in the research — or the body carries three or more
  counter-hypothesis sentences that belong in the appendix.
- **FAIL (0):** Strong claims stand alone with no counter-hypothesis tested anywhere — a finding
  with no tested alternative is under-cooked.

**Self-check:** For each "the real story is X" claim, what would have made it false, and does a
research file show that test? Then search the report body for "tested and rejected", "tested and
ruled out", "falsified" and "counter-hypothesis" — every hit outside the appendix is a defect.

---

## 5. Outlier treatment — every abnormal cell is chased, and reported ONCE

*Does every abnormal cell get chased and quantified — in a deep-dive OR inside the insight that
already carries its mechanism?*

- **PASS (2):** Every cell outside the normal ~15–30% band, every "0 of N", and every
  "Chose Competitor" is chased and quantified, in ONE of two allowed shapes:
  (a) **absorbed into the region insight**, with the cell and its rate named there — required
  where the mechanism is already one of that region's top-three insights; or
  (b) a **dedicated deep-dive** with numbered mechanisms, record-level
  evidence and a quantified verdict — required only where no region insight carries the
  mechanism. Shape (a) is a PASS, not a shortfall: a deep-dive that restates a region insight
  costs roughly 1.5 rendered pages and is scored as duplication under Dim 8.
  GOLDEN examples of shape (b): AMER Mid-Market
  **2% (1W/44L)** gets its own section (subsidy-driven lone win; cold-outbound 0-for-41);
  EMEA **DACH 3.8%** gets a section (Swisscom $45,783 is an internal Brainloop move);
  APAC **0 of 72** true competitive losses gets the phantom-competition finding; APAC's
  inflated **42.9% → 26.7%** amendment correction is shown before any APAC win-rate number.
- **PARTIAL (1):** Most outliers handled, but one abnormal cell is mentioned without its
  mechanism chain or quantification.
- **FAIL (0):** An outlier cell is reported as a bare number with no dig anywhere, or the
  inflated raw rate is published without the correction. **A deep-dive that is absent because the
  region insight already carries the mechanism is NOT a FAIL** — the auditor records "outlier
  absorbed into insight N".

**Self-check:** List every cell outside 15–30%, every 0-of-N, every Chose-Competitor row.
For each, is it either absorbed into the region insight (cell and rate named) or given a
deep-dive with a mechanism chain and a quantified verdict — and never both?

---

## 6. Structure fidelity — the golden skeleton is present

*(Detail deferred to `reference/report-structure.md`; this is the presence check only.)*

- **PASS (2):** Exec one-page summary whose LEAD paragraph is about why we win/lose across its
  whole length (opens with the strongest reason, continues with mechanism sentences; NOT one
  why-sentence + three caveat sentences, and NOT a basis/scope/caveat opening) + 4 stat tiles + geo×segment 3×3 matrix (outlier
  bolded) + why-prose — **and page 1 ends there**: the top-themes table, the competitor
  `table.plain` (following the themes table, 3-5 competitors, with the
  `Confirmed named cases (count)` column) and the one-line competitor
  finding are region-sheet elements, and a page-1 sheet carrying either table is a FAIL
  + ZERO basis/method/how-to-read
  annotation ANYWHERE in the body (no basis paragraph, no matrix legend, no "read the columns"
  prose, no [LOSE] method-and-its-limits paragraph — all Appendix-only, per report-structure.md
  supporting rule #7; and ZERO Appendix pointers, including at the end of the exec lead), no
  `.callout`/`.note`-disclaimer boxes; per-region sections nested **Ent→MM→SMB**; Voice of the
  Customer carrying **geo AND segment**; outlier deep-dives where the mechanism is not already a
  region insight (otherwise absorbed into it); Actions / Strategic Implications (≤5 rows,
  ARR-ranked, owned, each acting on a bedrock root cause and each judging what WE do about our
  own evidence — see Dim 7 for the scope bound); numbered Sources (every cite resolves, no self-cite); Appendix; Glossary;
  Open Data Requests. Both reports on the ONE skeleton with identical portfolio numbers, scope
  line, competitor caveat, AND an identical compact page-1 header (`h1.section` "Why We
  {Win|Lose} — Executive Summary" + `.product-line`; no magazine cover). Prose is Simplified
  Technical English (acronyms expanded on first use, sentences under 30 words, no jargon
  soup), and there is NO footnote or dated "Reconciliation note" aside in the body.
- **PARTIAL (1):** Skeleton mostly present but one required element missing or off (e.g. VoC
  not tagged by segment, a `.callout` or "how to read" box survives, glossary absent, the two
  reports open with different page-1 headers, or a few run-on/unexpanded-acronym STE misses).
- **FAIL (0):** Multiple required sections missing, the two reports diverge on portfolio
  numbers / scope / caveat, a dated reconciliation note survives in the body, the prose is
  pervasively non-STE (jargon soup, run-ons), **OR any basis/method/how-to-read annotation
  sentence appears in the body outside the Appendix** (a basis-definition paragraph, an
  amendment-mechanics sentence, a modelled-ARR explanation, a "the competitor field is blank so
  names are anecdotal / a lower bound" preamble, a matrix/table how-to-read legend, or the LOSE
  method-and-its-limits paragraph in the exec). This is "sausage-making" and is a hard FAIL —
  scan every body sheet, not just the exec.

**Self-check:** Run the spec-conformance pass in `reference/report-structure.md`. Is there a
prose "why" paragraph after every table (and ZERO `.callout` boxes)? Is the exec summary LEAD
paragraph about why we win/lose across its whole length — not a caveat dump moved down one line?
Is the matrix present? Is every body figure on the one Finance-clean basis, with the all-sizes
comparison confined to the single appendix table? Are theme tables ARR-ordered, max 5 rows?
Themes ranked by
mechanism, not picklist? Do both reports open with the SAME compact header? Any acronym
unexpanded on first use, any "Reconciliation note" aside, any "went dark" theme with no reason
under it? Does the report carry 15 quote blocks or fewer, with no quote printed twice, no
verification count in any quote header, and Acme-authored quotes labelled "Deal evidence"?

---

## 7. Honesty — counter-evidence in, editorializing out

*Are the uncomfortable findings included, and does the report stay in its lane?*

- **PASS (2):** Counter-evidence is present (GOLDEN win report includes the Associated
  Engineering board that *"prefers to rely on their own critical thinking rather than
  utilizing AI tools"* and price objections on wins; GOLDEN lose report flags the Vulcan
  won-vs-churn system conflict). Coding gaps are surfaced as **findings** and as numbered
  **open-data-requests** (the `F8` amendment-control-cell question; the empty competitor
  field; the win/loss count reconciliations). Internal-product moves (Brainloop / GovernAI /
  BoardEffect) are reported **plainly, without strategy or other-team editorializing** — the
  GOLDEN Swisscom prose literally notes *"Reported plainly, per spec — not editorialising
  about strategy."*
- **PARTIAL (1):** Some counter-evidence present, but the report tilts flattering, OR it tilts
  the other way — an evidence-supported product win is hedged into mush or buried under
  caveats, so the report reads more negative than the data warrants.
- **FAIL (0):** Only flattering evidence; or the report editorializes BEYOND ITS OWN EVIDENCE —
  a PMF verdict, a market-traction call, or a judgment of another team's performance. Note the
  bound is SCOPE, not silence: the Actions section is *required* to judge what we should do
  about this book of deals (`report-structure.md` final-pages item 1), and naming a lever we
  control is judgment, not editorializing. "The product has no PMF" is the failure.

**Self-check:** Is there at least one uncomfortable fact per report that cuts against the
headline? Is every data-quality gap both a caveat AND an open-data-request? Any sentence that judges PMF, market traction, or another
team rather than judging what WE do about the evidence in this report? Is every evidence-supported product win stated as
a win (with the caveat attached, not dominant)? A win report that reads as a debunking of its
own thesis fails the cautiously-optimistic tone bar.

---

## 8. Economy — is the report short enough to be read?

*Does the report stay inside its page budget, and does it say each thing exactly once?*

> **Count PDF pages, never `.sheet` divs.** `.sheet` has `min-height` and `overflow: visible`,
> so a sheet grows and one div can print as three pages. A report can pass a 10-sheet check and
> print 16 pages. Render the PDF before scoring this dimension.

- **PASS (2):** within the 10-page budget **measured on the rendered PDF**, with the appendix at
  2 pages or fewer; page 1 carries only the tiles, the lead, the Key
  Insights table and the matrix; no mechanism or caveat restated without new numbers across exec
  / region / segment / Strategic Implications; no column repeating one value down every row; no
  basis pairs outside the appendix.
- **PARTIAL (1):** within the PDF page budget but one mechanism restated at two levels with no
  new numbers.
- **Word count is a GUIDE, not a scored gate.** ~650 words per sheet is a length proxy; the
  rendered PDF page count is what this dimension scores. Do not dock a report whose sheet runs
  long but still prints as one page. Stated [LOSE] allowances: Actions sheet ~750 words,
  appendix page 2 ~710 words.
- **FAIL (0):** over the page ceiling on the rendered PDF; or a page-1 sheet carrying a themes
  table or a competitor table; or a region row that repeats the portfolio row's numbers and
  wording; or an outlier deep-dive that restates its region insight.

**Self-check:** Count the pages **in the PDF** (`pdfinfo`, or the renderer's page count) — a
`.sheet` count is not an answer. Then list every top theme and where it appears: a name at two
levels is fine only if the lower row brings its own numbers and its own mechanism.

---

## 9. Causal proof — does the attribute separate outcomes?

*Does each headline connect a decision attribute to changed buyer behavior and a measured
outcome, proven by named deals?*

- **PASS (2):** every headline names the decision attribute, the cohort boundary, the buyer
  change, the outcome, three named proof deals, and one contradictory case, with a citation on
  every rung.
- **PARTIAL (1):** one row has the attribute but weak contrast evidence.
- **FAIL (0):** any row ends at an exposure label or a lever we own — `referral`, `target list`,
  `expansion`, `installed base`, `qualification`, `channel`, `new logo`, `coverage`, `package`,
  `price`, `team`, 'brand strength', 'the customer went quiet'. **FAIL (0):** the cited proof
  deals do not support the stated attribute.

**Self-check:** hide the `What we change` cell. The `Causal mechanism + proof deals` cell must
still explain WHY the outcome happened. If all it names is a lever or a cohort, the chain is not
finished.

---

## 10. Language — ASD-STE100, and no method words in reading real estate

*Is the prose controlled English, and is the sausage-making out of sight?*

- **PASS (2):** ASD-STE100 throughout. No metaphor, no idiom, no undefined insider term, no
  method word and no hedge word outside the appendix.
- **PARTIAL (1):** three or fewer violations.
- **FAIL (0):** a method word or hedge word in the exec lead, the Key Insights table, a table
  header or a quote header.

**Self-check:** Search the report for "Finance-clean", "all-sizes", "a-s", "basis",
"denominator", "verified quotes", "below the floor", "open-data-request", "unsourced", "lower
bound", "counter-hypothesis", "sample", "picklist", "methodology", "re-paper", "modelled",
"modeled", "tested and rejected", "tested and ruled out", "falsified". Every hit outside
the appendix is a violation.

---

## Pre-empt the exact defects the GOLDEN reports' own Codex audits caught

The first drafts of the GOLDEN pair **failed** their Codex spec-gate on these specific
points. Fix them in the draft so the audit does not have to. (Source:
`fy27/output/research-july/v2-evidence/codex-spec-gate-findings.txt`.)

1. **Schema drift in segment tables.** AMER Mid-Market and EMEA/APAC segment tables used ad-hoc
   headers (`Deal | Why it won | ARR`) and dropped the money column. Every theme
   table must use `Theme | Mechanism | Won/Lost ARR | % of total | Representative customers`,
   ordered by ARR with a maximum of five rows, and both number columns must be populated even
   for a 1-of-1 cell.
2. **Missing why-prose after tables.** The exec "Top themes" table and several segment tables
   were left with numbers only, or the why lived in a `.callout` box. Every table needs an
   adjacent 2-4 mechanism prose paragraph — no box, no bare rows.
3. **Method/basis text leaking into the body.** Denominator, reconciliation, and count-caveat
   language ("percentages use the 38 deeply-mined wins…"; the 44-vs-45 MM count) sat in the
   narrative. Keep the body to insight + why; push basis/reconciliation to the Appendix.
4. **VoC not tagged by geo × segment.** Voice-of-the-Customer quotes lacked per-segment
   placement. Every `.quote`/`.attrib` must carry BOTH geography AND segment, and each segment
   subsection should have its own VoC.
5. **Undefined jargon / no glossary.** BLC, AMER/EMEA/APAC, MM/ENT, D1P, CSP, RFL, SFDC, GDR
   appeared unexpanded. Provide a one-place glossary and expand on first use (yk-voice plain
   English).

If your draft repeats any of these five, it is not golden yet — fix before the adversarial
audit in SKILL.md Step 5.

## Parity is bounded by evidence access, not effort (Aug 2026 annual run)

The full-year 2026 run first stalled: after 5 adversarial-review iterations the WIN report
cleared the bar (structure YES, quality 12/14 on the then-14-point, 7-dimension scale) but the
LOSE report capped at 9/14, because the
Gong full-transcript endpoint was SSO-expired during mining and the single largest loss
population (the 938 late-stage silence-coded deals that reached Demonstrate or later) had no
record-level root cause. The rubric correctly refused a truth=2 / root-cause=2 score while the
biggest cell was an honest "cause unknown". The gap was then CLOSED once `gong login` was
re-run: mining the top 20 of those 938 at record level lifted root-cause depth to 2 (9 of 20
were qualification failures, 3 product gaps, 2 unrecoverable), and the reviewers confirmed it.
Two lessons: (1) confirm `gong login` is live BEFORE promising loss-side parity — the loss
report is truth-capped without it; (2) scope every record-level conclusion to the deals you
actually read (here, the top 20 by value) and keep the rest picklist-coded — a claim that a
20-deal sample characterizes a 938-deal population is a truth defect the reviewers will catch.
