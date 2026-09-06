# Report structure — the v2 golden skeleton (win AND lose share it)

ABOUTME: The exact, reusable page-by-page blueprint every Why-We-Win / Why-We-Lose report
ABOUTME: must follow. It replaces the old v1 asymmetric structure where win and lose had
ABOUTME: different skeletons and buried the "why" under process narration.
ABOUTME: BOTH reports use this SAME skeleton — only the framing (win vs loss) differs.
ABOUTME: This file is the SINGLE authoritative structure spec. The one worked example is
ABOUTME: templates/GOLDEN-why-we-win.html; the lose report uses the same skeleton, lose framing.

## The narrative-only rule — every explanation is prose, never a box

The reader meets one continuous argument in prose. Use prose, tables, stat tiles, and evidence
quotes only. **No boxed asides of any kind** — no `.callout` box, no `.note` used as a
disclaimer/caveat/method/"how to read"/reconciliation aside, no "How to read this report"
section, no "Method and its limits" block. Every why, mechanism, caveat, basis definition, and
method limit is an ordinary `<p>` woven next to the table or finding it explains; method details
go in the Appendix. Keep the rigor; lose the box. Lead the paragraph with the point, then the
number, in Simplified Technical English.

**Attribution — inline, in the source's own name.** Write `— Bank of Hawaii, Gong, Mar 2026`.
Superscript `<sup class="cite">` markers are permitted only in the region and appendix sections,
never on the decision page, and never stacked — where a paragraph makes one claim backed by the
same source throughout, cite once at the paragraph end. The full source register ships as a
separate file (`why-we-win-sources.md` / `why-we-lose-sources.md`), not as a page of the report.
(This single rule replaces the earlier per-figure superscript convention, which produced 262
markers in one report — one per ~57 words.)

**The only non-prose, non-table blocks allowed in the body are:** stat tiles
(`.stats`/`.stat`), data tables (`table`/`table.plain`), verbatim customer-voice quotes
(`.rep-head` + `.quote` + `.attrib`), superscript citations, and the Sources list. Nothing
else.

**Say each thing once.** A fact, mechanism, or through-line appears in exactly one place. If
the exec summary states the through-line, the region sections and Strategic Implications
reference it, they do not restate it. Duplicated "Why" content is a defect, not emphasis.

The `.quote`/`.attrib` block is NOT an aside — it is primary evidence and stays. The
`.callout` and disclaimer-`.note` CSS classes remain defined in `report.css` (pre-existing;
do not delete), but the reports must not use them.

## The single shared skeleton — identical section order in both reports

Both reports render the SAME ordered sections. The ONLY differences allowed are the word
Win/Lose, the theme class, the numbers, and the three LOSE-ONLY sections marked below. Any
analytical move, region-specific finding, or deep-dive that appears in one report MUST appear
in the other in the same position, unless it is on the lose-only list.

Order (both reports):
1. Decision page (one sheet): compact header + scope line → **LEAD paragraph, ≤5 sentences and
   ≤120 words: sentence 1 is THE single biggest driver with its number, from `KEY-INSIGHTS.md`
   §1; sentences 2–4 are ranked drivers #2 and #3; no citation markers, no method words, no
   Appendix pointer** → **two tables (item 1b): the ranked-reasons table FIRST, then the Key
   Insights table** →
   4 stat tiles → geo×segment matrix + prose why. **Page 1 ends there** — the top-themes table,
   its prose why, the competitor table and the competitor finding are region-sheet elements, not
   page-1 elements. NO basis
   paragraph, NO matrix legend, NO "read the columns" text, and [LOSE] NO method-and-its-limits
   paragraph in the body — all of that is Appendix-only per supporting rule #7.
1b. **Two tables, in this order: the ranked-reasons table FIRST, then the Key Insights table.**
   Table 1 is the at-a-glance stack rank (what wins/loses, how often, how much); Table 2 is the
   detail (mechanism, proof, intervention). **Table 1 rows and Table 2 rows describe the SAME root
   causes in the SAME rank order.**

   **Table 1 — Ranked reasons (comes FIRST).** A `table.plain`, own-side only: the Why-We-Win
   report ranks WIN reasons, the Why-We-Lose report ranks LOSS reasons. Columns, in this exact
   order:
   `Rank | Root cause | Share of coded won deals | Won ARR`.
   - **Rank**: 1, 2, 3 … descending by Won ARR.
   - **Root cause**: the disaggregated decision sub-attribute in plain words (max ~10 words).
   - **Share of coded won deals**: a COUNT with its denominator, written `34 of 71 coded wins`.
     It is the share of the CODED/mined won deals in this cell, NOT of the full finance book,
     because only a sample is coded. Where the count is a mined floor, say "mined floor".
   - **Won ARR** (right-aligned `num`): the coded-attribute-floor ARR.
   - Descending by Won ARR. Maximum six rows; the rest fold into a single "long tail" row.
   - **One prose sentence under the table states the basis once**: the shares are of the coded
     win sample, not the full book.
   - The **[LOSE]** report's Table 1 has the same shape with `Share of coded lost deals` and
     `Lost ARR`.

   Exact HTML shape for Table 1 (win report):
   ```
   <h2>Why we win here — ranked by won ARR</h2>
   <table class="plain">
     <thead><tr><th class="num">Rank</th><th>Root cause</th><th>Share of coded won deals</th><th class="num">Won ARR</th></tr></thead>
     <tbody>
       <tr><td class="num">1</td><td>A director already runs Acme on another board</td><td>34 of 71 coded wins</td><td class="num">$703,054</td></tr>
       ...
     </tbody>
   </table>
   <p>These shares are of the coded win sample, not the full book; the picklist is blank on 46% of wins.</p>
   ```

   **Table 2 — Key Insights — four to five causal mechanisms, one screen (comes SECOND).** A
   `table.plain`:
   `# | Insight | Causal mechanism + proof deals | Share of the book | Won/Lost ARR | What we change`.
   Rows come from `KEY-INSIGHTS.md` §2, in rank order, and each comes from an analytical-gate
   `PASS` cluster. **This table carries 4 to 5 rows. Minimum 4, unless fewer than 4 `PASS`
   clusters genuinely exist — then say so in one sentence.** This is a floor to reach for, NOT a
   licence to pad: an unfilled floor is reported honestly, never filled with a `DESCRIPTIVE`
   cohort dressed as a cause. The `Causal mechanism + proof deals` cell is written as two or three
   short plain sentences, in ASD-STE100 Simplified Technical English. No `→` arrows. No `;`
   semicolons joining clauses. Example: "A director on the buying board already runs Acme
   elsewhere. That removes the board's adoption risk, so the buyer chooses Acme. Proof: Viper
   Energy, Fossil, Zura Bio." The `What we change` cell names the intervention and must NOT repeat
   the cause. A channel, segment, list, package, price, or team without an attribute fails. Keep
   six columns — do NOT add a seventh; full deal evidence lives on the region sheet or in the
   companion appendix. One prose sentence after the table states what share of the book the set
   explains and names the rest as long tail. This is the page a reader who reads nothing else must
   be able to read. Both tables are identical in shape in both reports.

   **ASD-STE100 STE is a hard gate.** Before writing any prose or any table cell, read and apply
   `reference/STE-STYLE-GUIDE.md`. No `→` and no clause-joining `;` anywhere in report output. One
   idea per sentence, active voice, under 30 words, every acronym expanded on first use.
2. AMER — stat band (with win rate) → **the region's ranked-reasons table FIRST (same shape as
   exec Table 1, own-side only, descending ARR), then the region's insight block (same table
   shape as Key Insights, sourced from `INSIGHTS-<region>.md`, descending ARR, 3–4 rows, up to
   5)** → reasons-why table
   (ARR-ordered, max 5 rows) + prose why → per-region competitor table (confirmed named-case
   count) → Voice of the Customer → region-specific finding woven in prose →
   **[LOSE] the region's controllable share of lost ARR** → segment nest
   (ENT+Strat → MM → SMB; a cell with no distinct finding gets one sentence, not a section).
3. AMER outlier deep-dive — **CONDITIONAL: only where the abnormal cell's mechanism is not
   already one of the region's top-three insights; otherwise it is absorbed into that insight as
   two sentences and no section is written.** Where written, it sits immediately after the AMER
   segment nest — SAME position in both reports.
4. EMEA — same shape as AMER (+ the EMEA outlier deep-dive, on the same condition).
5. APAC — same shape as AMER (+ the APAC outlier deep-dive, on the same condition).
6. [LOSE ONLY] Late-stage-silence deep-dive (the biggest loss population read at record level).
7. [LOSE ONLY] Retention cross-reference — ONE entry: the booked ARR lost from the base and the
   largest controllable churn reason. The full retention treatment ships as its own decision
   brief, not as a chapter of the loss report.
8. Actions / Strategic Implications — max 5 rows, descending ARR at stake.
9. Appendix (basis defs, the ONE all-sizes comparison table, caveats, contested-loss test) +
   Glossary — 2 pages maximum.
10. Open Data Requests.
11. Sources — a SEPARATE FILE shipped alongside the report, not a page of it.

Region-specific findings (Canada-vs-US in AMER, sub-region-beats-segment in EMEA, the
amendment correction in APAC) are woven into the region's narrative prose — NEVER a standalone
`<h2>` aside — and are present in BOTH reports for the same region (the win and lose Canada
paragraph, the win and lose EMEA sub-region paragraph, etc.), differing only in win vs loss
framing.

## Population matching — both sides of every ratio share ONE filter chain

Any published ratio, any "X wins against Y losses" pair, and any win-rate or loss-rate
comparison must have **both sides counted under the SAME filter chain**. The chain is the full
set of filters that produced the number: period, region, deal type (New / Upsell / Renewal),
source or channel, segment, stage, and reason-code set. State that chain once, in the sentence
or in its citation, and make both sides answer to it.

Two figures that are each individually correct do not make a correct comparison. In the 2026d
run a sheet published "win 43 times and stall 158 times": the 43 was APAC upsell wins with
referral EXCLUDED, and the 158 was APAC upsell stalls with referral INCLUDED and restricted to
three silence codes. Both figures reproduced from the rosters. The ratio they formed did not
exist — on the win side's own chain the loss count was 125, and the ratio moved from 3.5-to-1
to 2.8-to-1.

Rules:
- Write the chain down BEFORE you compute the second side, then count the second side with it.
- If the number you want on the other side only exists on a different chain, either recount it
  on the shared chain or **do not publish the pair**. Publishing the two figures in separate
  sentences, each labelled with its own chain, is allowed; joining them with "against",
  "versus", "for every", or a ratio is not.
- A rate (`% won`, `% lost`) is a ratio: its numerator and denominator are two sides and must
  share the chain. A numerator scoped to a region over a portfolio denominator is a FAIL.
- The independent auditor checks this mechanically (SKILL.md auditor checklist): for every
  ratio it names the chain and reproduces both counts under it.

## The one rule that defines v2: lead with WHY, not WHAT

Every table of numbers is immediately preceded or followed by PROSE sentences that explain
the ROOT CAUSE behind the numbers — the mechanism, drawn from transcripts and CRM record
reads, not the Salesforce picklist. Write the "why" as narrative paragraphs, never as a
`.callout` box or a `.note` aside (see the narrative-only rule above). "What won / what lost"
without "why" is the v1 defect this structure exists to kill. If a why cannot be sourced from
the evidence, say the why is unknown in a sentence and file an Open Data Request — never pad
with process narration or disclaimers.

Supporting rules:
1. **The WHOLE opening paragraph is about why we win/lose — not just its first sentence.** The
   exec body opens with the single strongest reason, then two-to-three more sentences of
   mechanism (the next strongest drivers, each sourced). Basis and method do NOT belong in this
   paragraph. The classic FAILURE — and it looks like a fix, so name it — is one why-sentence
   followed by three caveat sentences (the Finance-clean basis, the amendment count, the
   blank-competitor-field point). That is still a caveat dump; demoting caveats from sentence 1
   to sentences 2–4 does NOT satisfy this rule. Push basis, modelled-ARR and competitor-capture
   text to the Appendix. **The lead carries NO signpost and NO Appendix pointer** — the last
   sentence is the emphasis position and belongs to a finding.
   NEVER open with a basis, scope, or caveat sentence. No "How to Read This Report" section, no
   3-bullet how-to-read insert, no bulleted box. All fine print (full basis defs, reason-code
   register, contested-loss test) lives in the single Appendix under half a page.
2. **Rank by money.** Each theme carries (a) its won or lost ARR in dollars and (b) its share of
   total won/lost as a plain percentage of a stated denominator — never a compound statistic
   ("74% carry a soft code; 72% of those die pre-Proposal" is not a share). Order rows by ARR,
   highest first. Where ARR is genuinely unavailable, fall back down this ladder and name the
   rung you used in the column header: won/lost ARR → pipeline ARR → win rate × ASP → win rate.
   **A ranking by record count alone is not accepted** — record counts put the cheapest problems
   at the top. Maximum FIVE theme rows per table. Every row must be countable and priced:
   "subset", "a handful of confirmed deals" and "load-bearing in ≥9 notes" are not rows. If
   themes overlap, split them until they do not, or merge them — one sentence saying "the shares
   are not mutually exclusive" is a licence to avoid the analysis and is no longer accepted.
   State the residual: "these five explain X% of the book."
2b. **Shipped beats planned.** Count only capabilities present in closed wins as current drivers.
   Early-access and planned capabilities go in a short "future leverage" box with their dates,
   never inside the same conclusion as a shipped driver. A differentiator claimed on a named
   subset ("DACH + ME&A subset") is a deal qualifier, not a proven broad win driver, unless a
   counted population is published — and it may not appear in the Key Insights table without one.
3. **Rank themes by sourced mechanism, not picklist frequency.** The win/loss-reason
   picklist is unreliable in both directions; do not rank by it. Rule 2 sets the ORDER (money);
   this rule sets what a theme may be BUILT from (a sourced mechanism, never a coded frequency).
4. **Simplified Technical English, always.** Write every sentence to the STE standard in
   `reference/STE-STYLE-GUIDE.md` BEFORE drafting: one idea per sentence, under 30 words,
   active voice, every acronym expanded on first use in the body, one term per concept, no
   jargon without a one-clause gloss, no filler. Score the report on the STE gate before
   shipping. No editorializing about strategy or another team's performance.
   No metaphor, no idiom, no rhetorical inversion. Define any unavoidable term in one clause at
   first use, or delete it.

   | Before | After |
   |---|---|
   | "Head-to-head conquest is the exception." | "We rarely beat a named competitor. Only 193 of 2,497 losses (7.7%) name one." |
   | "Read at record level, most losses are not competitive defeats." | "Most losses are not defeats by a competitor. We cause them ourselves." |
   | "Governed AI is the stated reason to upgrade." | "Customers upgrade to get governed AI. 48 of 104 Enterprise upsell deals (46%) name D1P, BLC Pro or GovernAI." |

   Banned insider terms in the report: "re-paper" (write "sign a new contract"), "Finance-clean",
   "all-sizes", "a-s", "picklist", "load-bearing", "record-bound", "the assembler", "CRIS",
   "name-flagged", "no-bid", "contested-loss test", "3-quote floor".
5. **No footnotes, no dated asides, no "reconciliation notes".** Never leave a free-floating
   `<p style="border-left...">` "Reconciliation note (Aug 2026)" or "editor's note" in the
   body. Weave every rationale, correction, and caveat directly into the sentence it belongs
   to. If a number changed after a later review, state the correct
   number and the one-clause reason in place. Superscript source citations stay; prose
   "notes" do not. (This was a July 2026 defect: two reports carried dated reconciliation
   asides that had to be folded back into the prose.)
6. **Never stop at "went dark / no momentum / unresponsive".** These are NOT root causes —
   they are how a deal ended, not why. Dig every material "unresponsive / postponed / no
   interest" deal to the controllable reason underneath the silence, quoted from a
   transcript or a record note. Worked July 2026 examples: AMER Mid-Market silence bottomed
   out in thin shipped-AI value at mid-market boards (the customer already runs Copilot or
   Claude); APAC "no interest" losses were Acme's OWN board-facing AI failing a free
   trial (summaries too long, could not extract the recommendation section); EMEA "went
   dark" deals were feature gaps, a 10-month AI legal block, or our own vendor-onboarding
   failure. A theme row that says only "went dark / coverage failure" without the reason
   under it is incomplete — see `reference/root-cause-protocol.md` §"the silence rule".
7. **Method belongs in the appendix. Nowhere else.** No basis name, no denominator discussion, no
   sampling statement, no evidence-sufficiency judgment, no data-quality complaint and no hedge
   appears in the body, in a table, in a table header, in a quote header, in a stat-tile label or
   in the exec lead. Banned in reading real estate: "Finance-clean", "all-sizes", "a-s", "basis",
   "denominator", "verified quotes", "below the floor", "3-quote floor", "filed as an
   open-data-request", "unsourced", "unconfirmed", "lower bound", "anecdotal", "the sample",
   "picklist", "the assembler", "counter-hypothesis", "methodology".

   **Report the best finding the data supports, and report it plainly.** "The competitor field is
   blank on 99.96% of losses" is a note for the appendix. "At least 193 of 2,497 losses (7.7%)
   name a competitor" is the finding. Write the finding.

   The appendix carries, once each: the basis definition, one all-sizes comparison table, a "What
   we could not see" box of 8 lines maximum, the glossary and the Open Data Requests. The appendix
   is 2 pages maximum.

The two reports are a matched pair: the shared portfolio numbers, the scope line, the basis
wording, and the competitor caveat must read identically in both.

Say each thing once. The through-line, the basis, the competitor caveat, and each region's
mechanism appear in exactly one place; later sections reference them, they do not restate
them. Duplicated "Why" content across the exec, region, and Strategic-Implications sections
is a defect.

---

## Page 1 — ONE-PAGE executive summary

This is a single `.sheet`. In order:

1. **Compact header + one scope line — IDENTICAL treatment in BOTH reports.** Use
   `<h1 class="section">Why We Win — Executive Summary</h1>` (or "Why We Lose — Executive
   Summary") followed immediately by a `<p class="product-line">` scope line: product line
   (e.g. BLC only), the three regions (AMER / EMEA / APAC spelled out on first use), the
   and the period. No basis clause — the basis definitions live in the Appendix. Then go
   straight into the stat tiles.
   **Do NOT use the old magazine cover** (`h1.cover-title` "WHY WE WIN" + `.cover-sub` +
   `.cover-meta` + a "Portfolio at a Glance" `<h2>`). That asymmetric cover was a visual
   mismatch between the two reports; the July 2026 refine unified them onto the compact
   `h1.section` + `.product-line` header the lose report already used. The two reports must
   open the same way — same header class, same scope-line shape — differing only in the word
   Win vs Lose.
2. **The LEAD paragraph — the WHOLE paragraph is why we win/lose, at attribute level
   (MANDATORY).** Immediately after the scope line, a `<p>` of AT MOST five sentences and 120
   words. Sentence 1 names the decision attribute, the cohort boundary, the buyer-behavior change,
   the measured outcome, and one named proof deal — it is the one line the reader will repeat, and
   it comes straight from `KEY-INSIGHTS.md` §1. Use this shape: `In <cohort>, <attribute> changed
   <buyer behavior>, which produced <outcome>; <Deal> is the clearest proof.` Sentences 2–4 give
   the next ranked causal mechanisms, each naming an attribute and at least one proof deal. Do NOT
   lead with a channel, segment, list, lever, method, caveat, or refutation. A cohort readout
   ("expansion is half the won money; referral converts at 44.2%") is exactly the failure this
   rule exists to kill — it is a Tableau decomposition, not a cause. Example (win): "Where a
   competitor's contract was ending, a funded book migration removed the switching cost and the
   board moved; that play won $650K across 25 deals, Fossil the clearest." Example (lose): "In
   DACH, buyers who required Swiss data hosting we do not offer chose Sherpany; the hosting gap,
   not price, decided Swisscom and CYP."
   **Do NOT fill this paragraph with basis/method.** The classic FAILURE that looks like a fix
   is one why-sentence followed by three caveat sentences (the basis, the amendment count, the
   blank competitor field) — that is a caveat dump moved down one line, and it FAILS this rule.
   Basis and caveats live in the Appendix. **The paragraph carries NO Appendix pointer at all**
   — the last sentence is the emphasis position and belongs to a finding. Keep each sentence under
   30 words (STE); split the required elements across two sentences if needed, while keeping
   sentence 1 causal. A methodology, scope, cohort-readout, or caveat-heavy opening is a FAIL.
3. **Portfolio at a glance — 4 stat tiles** (`.stats` > `.stat` > `.num`/`.lbl`/`.sub`).
   **BOOKED REVENUE in tile 1. OPPORTUNITY ARR in tile 2, with "not booked revenue" inside the
   `.lbl` itself.** Both are direct `REPORTING_ARR` sums — **never label either "modelled"**.
   Use "modelled" only for a figure that is genuinely derived rather than summed, and name the
   derivation on the same line. Style booked revenue and opportunity ARR differently so they
   cannot be read as the same currency.
   - Win: closed-won count, win rate, won ARR (booked), ASP.
   - Lose: booked ARR lost from the base, closed-lost count, face-value lost-opportunity ARR
     ("not booked revenue" — never tile 1), **the controllable share of lost ARR** (tile 3;
     see the controllability rule, SKILL.md STEP 3d).
   **Each tile carries ONE figure on the one Finance-clean basis.** No all-sizes counterpart in
   the `.sub`, and NO `<sup class="cite">` marker — the decision page carries no citation markers
   (attribution rule, top of this file). The `.sub` holds a plain-language qualifier or nothing.
4. **Geo x segment 3x3 matrix.** Rows = AMER / EMEA / APAC; columns = Enterprise+Strategic /
   Mid-Market / SMB. Each cell = `W / L` and the win rate, **on the one Finance-clean basis — no
   parenthesised all-sizes rate**. A cell reading `140W / 336L · 29.4% (a-s 39.3%)` is four
   numbers plus an undefined abbreviation and is banned. Bold the standout cell (e.g. a 2%
   outlier). One PROSE sentence under
   it defines the cell format. Then **3-5 "why" sentences (prose)** on the standout cells —
   not a restatement of the numbers, the mechanism behind them. No `.note` box, no bullets.
**Page 1 ENDS at item 4.** It carries four things and no more: the stat tiles, the lead
paragraph, the Key Insights table and the matrix (with its "why" sentences). The top-themes
table, its prose "why" paragraph, the competitor table and the one-line competitor finding are
**NOT page-1 elements** — they are region-sheet elements ("Per region" items 2, 3 and 5 below).
Items 5 and 6 that follow are the canonical SHAPE definitions those region elements use; they
are not a second copy for page 1. A page-1 sheet carrying a themes table or a competitor table
is a FAIL, and it is the single largest cause of a report printing 16 PDF pages against a
10-page cap.

5. **Top themes table (region sheets)** with columns: `Theme | Mechanism (the "why") | Won/Lost ARR | % of
   total | Representative customers`. Both number columns and the Representative customers
   column are mandatory. **Order rows by ARR, highest first; maximum FIVE rows; state the
   residual** ("these five explain X% of the book") — see supporting rule 2. Follow the table with one PROSE paragraph ("why these
   themes, not others") that states the mechanism behind the ranking; if themes overlap, say
   so in that same paragraph (percentages are not mutually exclusive). No `.callout`, no
   `.note` box.
6. **Competitor landscape (region sheets) — MUST follow that section's themes table.** A compact
   `table.plain` with **3–5 named competitors** (per geo, and per segment where evidence names
   any rival). Two quantitative columns, from two different sources — do NOT conflate them:
   `Competitor | Confirmed named cases (count) | Where it shows up | Read (the "why")`.
   - **`Confirmed named cases (count)`** = the number of records that name this competitor —
     **never a percentage**. A percentage computed on 5, 12, or 24 named records reads as market
     share in an executive table, and the word "anecdotal" in the header does not repair it.
     Write "four confirmed named cases", not "4 of 24 named (17%)". The capture limitation goes
     in the appendix, once: the competitor field
     (`OPP_COMPETITOR_PROSPECT_CURRENTLY_USES`) is filled on 0.04% of records, so every
     competitive count is a floor.
   - **The slice's competitive-loss rate** — the fully-populated
     `OPP_PRIMARY_CLOSED_REASON = "Chose Competitor"` share of Closed Lost, computed directly
     from the Finance workbook — is ONE number for the whole slice and it is shown ONCE, in the
     sentence above the table — never repeated down a column. A column whose every cell holds
     the same value is noise. It answers "how much of this cell is lost to competition at all";
       the count column answers "to whom".
   - **[WIN REPORT] Never introduce a win-side competitor table with a loss-side rate.**
     "Chose Competitor" exists only on lost records, so a win-side conclusion carried by that
     rate proves a win with a loss denominator. The win report's intro sentence states the
     competitive share of **wins**, computed from won-deal notes. If the won-side fill rate
     cannot support a rate, publish the confirmed named-case counts with NO rate at all and file
     the competitive share of wins as a numbered Open Data Request.
   - **Carry the price point where the evidence has it.** Where the mining files hold a rival's
     published or quoted price, assemble the price ladder across rivals and publish it — a price
     column, or one prose line under the table. "Our price sits at the top of the market" is an
     assertion until the ladder is printed.
   The intro sentence states the finding, not the method: give the slice's competitive rate (per
   the report-side rule above) and the count of named rivals. The capture limitation lives in the
   appendix, once — it does not appear here. This exact table shape is used in
   every per-region AND per-segment competitor table, and it ALWAYS comes immediately after
   that section's themes table.
7. **ZERO basis/method/how-to-read annotation in the body — Appendix-only (HARD RULE).** The
   report body (exec summary + EVERY region page + segment nests + outlier deep-dives +
   Strategic Implications) states FINDINGS ONLY. Every sentence that explains HOW the data was
   made is "sausage-making" and is BANNED from the body — it lives ONLY in footnotes
   (`<sup class="cite">` targets) and the Appendix. Banned from the body: basis definitions
   ("Finance-clean excludes sub-$5K amendments and duplicates"); the amendment-filter mechanics
   ("removes 642 of 1,431 wins because most are renewals"); modelled-ARR explanations ("ARR is
   modelled from ASP times won count"); competitor-field / anecdotal method prose ("the field is
   blank on 99.96%, so names are anecdotal / a lower bound"; "read the two columns together");
   table/matrix how-to-read legends ("each cell reads clean W/L with all-sizes in parens"; "the
   percentages do not sum to 100%"); reason-code-reliability lectures; and reconciliation /
   denominator caveats ("on an all-record basis"; "the two views disagree by $X"). What STAYS in
   the body: the single Finance-clean FIGURE itself (`24.0%`, matrix cells, tile numbers); a
   short necessary label on a figure ("not booked revenue" on the lost-ARR tile — **never
   "(modelled)"**, which is false on a direct sum); and findings, including
   root-cause mechanisms. **NO method text is allowed in the body at all** — no pointer, no
   `.note`, no bullet list, no "how to read" block anywhere. (This removes the earlier
   single-one-clause-Appendix-pointer allowance: both FY27 exec leads ended on that pointer,
   which spent the emphasis position on methodology.)
   **Dual-basis pairs leave the body.** Publish the Finance-clean figure ALONE everywhere in the
   body, including the exec stat tiles, the geo×segment matrix and each region's stat band. The
   all-sizes counterpart lives in ONE appendix table. Roughly eighty basis pairs in one report is
   not rigor — it is the reason the reader stops reading. (This replaces the earlier
   "dual-basis reporting is required in the body" exemption.)
8. **Method & its limits (LOSE report only) — Appendix, NOT the exec body.** The loss book's
   method content (what the prior period's headline was and whether it reproduces; a one-clause
   correction of any prior deck's arithmetic; the structural distorters — reason-code
   truncation, stage-gating, the 0%-competitor field, retention-in-a-different-currency) is
   MANDATORY as content but lives in the **Appendix**, never woven into the exec narrative. The
   exec body carries none of it — and no pointer to it either (rule #7).
   This reverses the earlier "weave it into the exec" guidance, which repeatedly produced a
   sausage-making exec that the reviewer flagged; the content did not change, only its home.

---

## Per region (AMER, then EMEA, then APAC) — same shape each time

Each region gets **2 pages, and those 2 pages include its segment nest and its outlier
deep-dive** (SKILL.md page-budget table). `report.css` flows rather than clips, so nothing is
ever cut off — but spilling onto a third sheet means the section is too long: cut it, do not
let it run. EVERY region section, in BOTH reports, MUST carry all three of: (i) the
region's win/loss rate (the stat band), (ii) the major reasons why it wins/loses (the ranked
theme table with prose "why"), and (iii) a per-region competitor table with the confirmed
named-case count. A region section must carry all three unless the evidence yields no finding
for one, in which case state that in one sentence. For EACH region, in this order:

1. **Region stat band** — 4 `.stat` tiles: wins/losses AND the win rate (both mandatory), ARR,
   ASP (win) or face-value lost ARR / ASP-of-lost (lose), Finance-clean figure only (the
   all-sizes counterpart lives in the ONE appendix comparison table, per supporting rule #7).
   The win rate (%won or %lost) is a required tile, not optional.
1a. **The region's ranked-reasons table — FIRST, before the insight block.** The same shape as the
   exec Table 1 (`Rank | Root cause | Share of coded won deals | Won ARR`), own-side only, scoped
   to THIS region, descending by Won ARR, maximum six rows with the rest folded into a "long tail"
   row. One prose sentence under it states the basis once: the shares are of the coded win sample
   for this region, not the full book. The **[LOSE]** report uses `Share of coded lost deals` and
   `Lost ARR`. **The region's ranked-reasons rows and its insight rows describe the same root
   causes in the same rank order.**
1b. **The region's insight block** — the same `table.plain` shape as the page-1 Key
   Insights table (`# | Insight | Causal mechanism + proof deals | Share of the book | Won/Lost ARR |
   What we change`), sourced from `INSIGHTS-<region>.md`, in descending ARR order. **This table
   carries 3 to 4 rows, up to 5 where the evidence supports it. Minimum 3, unless fewer than 3
   `PASS` clusters exist for that region — then say so in one sentence.** This is a floor to reach
   for, NOT a licence to pad; an unfilled floor is reported honestly, never filled with a
   `DESCRIPTIVE` cohort. Each row comes from an analytical-gate `PASS` cluster; the mechanism cell
   is two or three short plain sentences in ASD-STE100 Simplified Technical English, with no `→`
   arrows and no clause-joining `;` semicolons (example form: "A director on the buying board
   already runs Acme elsewhere. That removes the board's adoption risk, so the buyer chooses
   Acme. Proof: Viper Energy, Fossil, Zura Bio."). It comes right after the ranked-reasons
   table, before any cell detail. Cell detail comes AFTER the insight,
   and only where the cell says something the region insight does not. A cell with no distinct
   finding gets one sentence, not a section. **A theme may be a top row at two levels only where
   the lower-level row carries evidence, numbers and a root cause the higher-level row does not.
   A region row that repeats the portfolio row's numbers or its root-cause wording is a FAIL. A
   region row that sizes the same theme with that region's own numbers and adds a
   region-specific mechanism is correct and is not a duplicate.** Never print a region numerator
   over a portfolio denominator: a finding evidenced in one region is published at region level
   only, unless it is recomputed portfolio-wide from the rosters (SKILL.md STEP 3d,
   "Single-region populations").
1c. **[LOSE] The region's controllable share of lost ARR** — one figure on the region stat band
   or in the sentence under it, on the same class assignment the portfolio table uses.
2. **Ranked theme table** with columns `Theme | Mechanism (the "why") | Won/Lost ARR | % of total
   won/lost | Representative customers`. **Order rows by ARR, highest first; maximum FIVE rows**
   (supporting rule 2 owns the money ladder and the residual statement). Rank by sourced
   mechanism, never by record count. The win/loss-reason field's blank rate and the
   reconstruction method belong in the appendix, not in a prose sentence here.
3. **A prose "why" paragraph with EVERY table** — one short paragraph, immediately before or
   after the table, stating the 2-4 root-cause mechanisms behind the numbers in Simplified
   Technical English, each with its citation. This is the whole point of v2. Do NOT use a
   `.callout` or any box — the why is narrative (see the narrative-only rule). One thought =
   one sentence; several = one tight paragraph.
4. **Voice of the Customer.** Each `.quote` carries an `.attrib` with BOTH geo AND segment, the
   source, and a citation, e.g. `— Catherine Smith, CAO, Csquare (AMER · SMB, new logo) · Gong<sup
   class="cite">7</sup>`. Group them under a `.rep-head` (or `.rep-quote` wrapper).
   **Quote-block headers carry the cell name only.** They must NOT carry a verification count or
   a sufficiency judgment — "(5 verified)", "2 verified quotes, below the floor", "below the
   3-quote floor" are banned from headers and from body prose. Evidence gaps live in the Open
   Data Requests appendix, once. Include a quote because it is good evidence — full stop.
   **Cap the report at 15 quote blocks**; keep the ones carrying a mechanism a number cannot,
   one per mechanism, and never print the same quote twice. Counting rule for the cap: one quote
   block = one `.rep-head` group, however many `.quote` elements sit inside it. A quote spoken or
   written by a Acme employee — including a Salesforce close note — is not customer voice:
   label those blocks "Deal evidence". (This replaces the earlier ≥3-quotes-per-cell floor, which
   turned the crispest artifact in the report into a data-completeness disclaimer.)
5. **Per-region competitor landscape (both reports; ALWAYS follows the region's
   themes table)** — a compact `table.plain` with the same shape as the exec competitor table:
   `Competitor | Confirmed named cases (count) | Where it appears | Read/Mechanism (the "why")`,
   scoped to THIS region, with **3–5 named competitors** where the evidence supports them.
   The intro sentence states the region's competitive-loss rate ONCE and the count of named
   rivals — it states the finding, not the method. The capture limitation lives in the appendix,
   once. If fewer than 3 external competitors are named in the region's evidence, list what the
   mining found and file an open-data-request for the rest — and if none is named, say so in one
   sentence and show the internal / do-nothing alternatives instead. Do not omit the element
   where a finding exists; where none exists, one sentence replaces it.
6. **A region-specific finding, woven into the region narrative as prose (never a standalone
   `<h2>` aside), and PRESENT IN BOTH REPORTS for that region:**
   - AMER: Canada-vs-US split (same "why", different volume / different failure stage).
   - EMEA: sub-region beats segment (UKI dominance, DACH outlier).
     **Lead-source rule (applies everywhere, not just EMEA):** NEVER compute a headline
     referral / marketing / outbound share straight off the Salesforce lead-source picklist —
     it is lossy (the golden EMEA data carried Outbound-tagged deals that were actually
     inbound/referral). Verify at record level before publishing ANY source-mix number; if it
     is still unverified, label it explicitly as picklist-derived rather than stating it as
     fact.
   - APAC: the amendment correction (sub-$5K amendments inflate the raw rate), referral
     conversion, phantom competition; a by-country view.
   State the analytical move plainly: always test whether sub-region beats segment; always
   note what a grouping (e.g. folding Strategic into Enterprise) conceals.

### Within each region, nest per SEGMENT — always Enterprise+Strategic → Mid-Market → SMB

For each segment inside the region (in that fixed order). **A cell with no distinct finding gets
ONE SENTENCE, not a section** — a segment cell with no distinct reason mix stays one prose
sentence and does NOT force an empty table. The elements below are the shape a cell takes WHEN it
has something the region insight does not already say:
- **A ranked-reasons table FIRST, but ONLY where the segment has a distinct reason mix.** Same
  shape as the exec Table 1 (`Rank | Root cause | Share of coded won deals | Won ARR`, own-side
  only; **[LOSE]** uses `Share of coded lost deals` and `Lost ARR`), scoped to this geo×segment
  cell, descending by ARR, with one prose sentence under it stating the coded-sample basis once.
  Its rows and the cell's insight rows describe the same root causes in the same rank order. A
  cell with no distinct mix skips this table and stays one prose sentence.
- A SHORTER ranked theme table, ordered by ARR (smaller samples — keep it tight; `table.plain`
  is fine).
- A prose "why" paragraph (still required with the table; never a `.callout` box).
- **Highlights** (win report) / **Lowlights** (lose report) — the notable deals, each with a
  one-line mechanism.
- **VoC quotes for that geo×segment cell**, each `.attrib` carrying geo AND segment. There is no
  per-cell quote floor — the report-wide cap is 15 quote blocks, one per mechanism (region item
  4). A cell with no good quote gets no quote block and no note about its emptiness.

---

## Outlier deep-dive — CONDITIONAL, and only where it is not already an insight

**The condition.** An abnormal cell gets its own section ONLY where its mechanism is not already
one of that region's top-three insights. Where the region insight already carries the mechanism,
the outlier is **absorbed** into that insight as two sentences naming the cell and its rate, and
no separate section is written. The auditor records "outlier absorbed into insight N" — that is a
PASS, not a FAIL. A deep-dive that re-runs mechanisms already printed in the region insight block
costs roughly 1.5 rendered pages and buys the reader nothing.

Where the condition IS met — an abnormal cell (e.g. AMER Mid-Market at 1W/44L = 2%, EMEA DACH at
3.8%) whose mechanism no region insight carries — it gets its
OWN section immediately after that region's segment nest — SAME position in both reports (not
collected into a single end-of-report page in one report and embedded per-region in the
other). Structure it as a mechanism chain with per-deal evidence:
- A one-line finding as a prose lead sentence (no box).
- Numbered mechanisms ("Mechanism 1 …", "Mechanism 2 …"), each with record-level evidence
  (deal name, ARR, coded reason, and the transcript/note that contradicts or explains it).
- **NO counter-hypothesis prose.** The counter-hypothesis test is a research obligation, not a
  report section. Publish the surviving conclusion only; the rejected alternatives and their
  evidence go to the companion appendix file. "tested and rejected", "tested and ruled out",
  "falsified" and "counter-hypothesis" are banned from the body.
- A verdict restating the coded reason as a controllable mechanism (coverage / packaging /
  qualification / residency / internal-product), quantified. **Supporting rule 2b applies here:**
  a verdict may name a capability (residency, governed AI) as the mechanism only if that
  capability is SHIPPED and present in closed deals — an early-access or planned capability
  belongs in the "future leverage" box, not in a verdict.

Worked examples to copy: the durable APAC referral-conversion and UKI referral-engine
findings in GOLDEN-why-we-win.html. For the lose report, build the equivalent outlier chains
(e.g. an AMER Mid-Market 2% chain, a DACH internal-competition finding) on this same skeleton
— the lose framing, the same mechanism-chain structure.

---

## Retention — its own decision brief, plus ONE line in the loss report

> **ONE INSTRUCTION, so there is nothing to reconcile.** Retention is a different population,
> period and currency from the new-business loss book. It has its own denominators, actions and
> owners, so it ships as its OWN decision brief — **not as a `.sheet` inside the loss report.**
> This supersedes the earlier "the lose report MUST carry a dedicated Retention / GDR `.sheet`"
> instruction and the earlier "give it its own `.sheet`, do not bury it" instruction. Neither
> applies. Retention is not dropped and it is not buried — it is relocated to a document that can
> do it justice.

**In the LOSS REPORT — exactly one cross-reference, and nothing else.** One sentence carrying
the booked ARR lost from the base and the largest controllable churn reason, placed after the
region sections and before Actions. The booked retention figure ALSO leads the loss report's
stat tiles: lost opportunity ARR is never the first tile, and opportunity ARR and booked revenue
are styled differently so they cannot be read as the same currency. Neither is labelled
"modelled" — both are direct sums. Never write "retention loses more
money" — the populations are not comparable. Write "retention is the larger quantified exposure."

**In the RETENTION BRIEF — everything below.** The brief is a separate deliverable with its own
page budget, its own stat band, its own actions and its own owners. Build it with the numbered
treatment that follows.

1. **Retention stat band, same Finance basis.** Renewal pool, gross-dollar-retention (GDR)
   vs target, account churn, and downsell — each cited. State plainly that this is a
   DIFFERENT population and period from the new-business loss book (renewals of the installed
   base, not lost new deals). NEVER write "retention loses more money" — the populations
   aren't comparable. Say instead: "retention is the larger quantified exposure."
2. **The SAME root-cause treatment as the loss themes** — this is not a numbers dump. Apply
   every move from the region sections:
   - **Reclassify miscoded churn at record level.** Worked example: **BT −$304,924 coded
     "Legal Issue" is really a PRICE loss** (Gong: "about a third of what we are paying
     today"); correcting BT and CCLA flips addressable churn from **32.3% → 51.2%**. Show the
     correction, don't accept the picklist.
   - **Surface what a grouping HIDES.** **Strategic is the worst-retaining segment at
     89.26%**, hidden entirely by folding Strategic into Enterprise. Always break the grouping
     that conceals the worst cell.
   - **Show all conflicting GDR cuts without averaging.** When there are multiple GDR figures
     (e.g. six July cuts), show them all, explain the gap (brand-scope: the BLC line contains
     Brainloop, CGlytics, Manzama, Acme One), and flag mislabelled cuts (a `GDR` sheet
     saved filtered to Segment=Enterprise is an Enterprise number mislabelled as BLC). Never
     average them into one headline.
   - **REFUTE fabricated stats explicitly.** The "22.5% of Enterprise accounts publishing zero
     board books" claim is a **chart y-axis gridline in $M, not a statistic** — name it as
     refuted, don't silently omit it.
3. **A prose sentence** stating the brief's headline: retention is the larger quantified
   exposure than new-business loss. Never write "retention loses more money" — the populations
   are not comparable. No box. (This is the BRIEF's headline; the loss report itself carries only
   the one-line cross-reference specified at the top of this section.)

## Final pages

1. **Strategic Implications — maximum five rows, ordered by ARR at stake.** Columns:
   `What we do · Because (one line of evidence) · Owner · ARR at stake · First step in 30 days`.
   Rows come from `KEY-INSIGHTS.md` §2, in the same order, and each row acts on that insight's
   bedrock root cause — not on its symptom. A row that restates its finding is not a
   recommendation: "Resource the land-and-expand engine" FAILS; "Build a director-affiliation
   register from the 150 Brand Strength wins and route every multi-board director to CS" PASSES.
   **The `First step in 30 days` cell must name a counted population and the file, report table
   or system it comes from.** A first step whose population is not counted somewhere in this
   report is a FAIL: "Extract every director who sits on a board we already run" names no source
   and no count and FAILS; "Extract the 196 accounts behind insight 2, name the directors, and
   hand the list to Customer Success" PASSES.
   **Where an action changes a channel or segment mix, the `Because` cell must carry the expected
   ARR per opportunity for both sides of the change, not only the two win rates.** "Referral wins
   44.2% against outbound at 17.8%" is a rate comparison; "one extra referral new-logo
   opportunity is worth about $12.4K of expected ARR against about $3.5K for an outbound one" is
   the budget decision the reader has to make.
   **Name the conflict where two actions pull against each other**, and sequence them — a plan
   that raises the win rate by leaning on expansion does not add customers. One short closing
   paragraph, not a chapter.
   The section must NOT contain the sentence "it does not judge strategy" or any equivalent —
   **judging what WE should do about our own evidence is the point of the section.** The bound is
   scope, not silence: judge inside the report's own evidence (this book of deals, this period),
   and stay out of PMF verdicts, market-traction calls, and another team's performance. Naming a
   lever we control and a 30-day step is judgment; "the product has no PMF" is editorializing.
2. **Sources — a SEPARATE FILE, not a page of the report.** The full source register ships as
   `why-we-win-sources.md` / `why-we-lose-sources.md` alongside the report: a numbered `<ol>`
   equivalent, each entry with a title and source detail, naming the Finance workbook (+ sheet +
   spine CSV), a named research/evidence file, or a Gong call-id. NEVER cite the report as its
   own source. Every superscript marker that survives in the report must resolve to an entry in
   that file.
3. **Appendix — 2 pages maximum.** Holds ALL of: the two basis definitions (Finance-clean
   vs all-sizes and the sub-$5K amendment filter), the 0%-competitor-field caveat, the
   reason-code reliability note, the contested-loss test definition (stated so it can be
   reproduced), the Gong-access caveat, the CSV→workbook tie-out caveat, **[LOSE] the outcome-class
   assignment rule as a table, naming each class controllable or not controllable**, and **the
   rejected counter-hypotheses with their evidence** (they are banned from the body; they live
   here or in the companion appendix file). Terse.
4. **Glossary** (an `<h2>` inside the Appendix, `table.plain`). Define and, on first use in
   the body, expand: **BLC** (Board & Leadership Collaboration), **AMER / EMEA / APAC**,
   **ENT / MM / SMB**, **D1P** (Acme One Platform), **ASP** (average selling price),
   **ARR** (annual recurring revenue), **CSP / RFL** (the two Finance source sheets),
   **SFDC** (Salesforce), **GDR** (gross dollar retention).
5. **Open Data Requests** — numbered table `# | Open question | Owner suggested`. Each is a
   specific, answerable question with a suggested owner — the things that would materially
   change what the report can say. **The list must cover the gating unknown behind each published
   insight**: for every Key Insights row, ask what single unmeasured fact would most change what
   that row can claim (for an installed-base insight: saturation, attach rate, remaining
   headroom), and file it here if this run cannot measure it.

The final sections render in ONE fixed order in BOTH reports: Actions / Strategic Implications →
Appendix (+ Glossary) → Open Data Requests. Sources ship as a separate file. The two reports
must not diverge on this order. Multiple sections may share a sheet, but the sequence is fixed.

---

## Rendering

- **Single self-contained HTML per report**, `<link rel="stylesheet" href="report.css">`.
- **`report.css` is now fixed to FLOW, not clip.** Earlier it set `.sheet { height: 11in;
  overflow: hidden; }`, which silently cut any content taller than a page. It now uses
  `min-height` + `overflow: visible` (screen and `@media print`), so a long section spans
  two sheets instead of being clipped. Do NOT run an overflow probe and do NOT "tighten until
  zero overflow" — that was the wrong fix. Let content flow.
- **The in-file `<style>` overflow-override block is now legacy / unneeded** because
  `report.css` already flows. The golden win file still carries it (harmless belt-and-braces);
  keep it only as that legacy override — add no other `<style>` and invent no CSS.
- **`<body class="theme-win">`** for the win report, **`<body class="theme-lose">`** for the
  lose report. That single class swaps the palette; nothing else changes.
- **Use only shared classes defined in `report.css`.** The core content classes are:
  `.sheet .stats .stat .num .lbl .sub .rep-head .quote .attrib .callout .cite .note .plain
  .sources .src-title`. The page-furniture classes `report.css` also defines and the golden
  files use are `.rh` (running header) / `.rf` (running footer), `.cover-title` /
  `.cover-sub` / `.cover-meta`, `h1.section`, `.product-line`, `.callout-head`, `.rep-quote`,
  and `.tighten`. Do not invent any class outside this set.
- **Draft HTML only.** PDF / Markdown / Word are generated afterward by the orchestrator —
  do not build all four every run.
- **Identical running header and footer shape in both reports.** Running header:
  `<div class="rh"><span class="rh-left">Acme — Board &amp; Leadership Collaboration</span><span class="rh-right">Why We {Win|Lose} · {PERIOD}</span></div>`
  on every sheet. Running footer:
  `<div class="rf"><span>Confidential — Internal Use Only</span><span>Page N</span></div>`
  on every sheet. The two reports differ only in the word Win/Lose. Do not use one furniture
  style in one report and a different one in the other. Page numbers are sequential with no
  duplicates.
- **No boxes anywhere.** No `.callout`, no disclaimer/method/how-to-read `.note`, no "Method
  and its limits" block, no "How to read" list. Every why, method, and caveat is prose (see
  the narrative-only rule). The `.callout`/`.note` CSS classes stay defined in `report.css`
  but the reports must not use them.
- **`templates/GOLDEN-why-we-win.html` is the one authoritative worked example.** Copy its
  markup patterns exactly for BOTH reports; the lose report uses the identical skeleton with
  lose framing, the three lose-only sections, and `<body class="theme-lose">`.

---

## Pre-flight checklist (the full spec is above; this is the tick-list)

Do not restate the spec here — check the spec sections. The additions this version enforces:

```
ANALYTICAL GATE (before drafting — SKILL.md)
  [ ] ANALYTICAL-GATE.md exists; every selected insight is PASS
  [ ] deal-ledger.csv + ATTRIBUTE-CLUSTERS-<region>.md exist; KEY-INSIGHTS.md holds only PASS rows
CAUSAL CONTENT (every Key Insights + region top-three row)
  [ ] mechanism cell = two or three short plain STE sentences naming the attribute, the buyer
        change, the outcome, then "Proof: 3 named deals" (NOT a cohort label). No -> arrows, no
        clause-joining ; semicolons
  [ ] no row ends at referral / target list / expansion / installed base / qualification /
        channel / new logo / coverage / package / price / team
  [ ] each row has a within-cohort win/loss contrast and one contradictory case
  [ ] LEAD sentence 1 names an attribute, a cohort, an outcome and a proof deal — not a readout
  [ ] removing all Gong/SFDC evidence would invalidate every causal insight (Finance alone can't)
CONFORMANCE (unchanged — run at STEP 5, AFTER the analytical gate)
  [ ] 10 PDF pages, appendix <=2, counted from the rendered PDF — the 10-page target FLEXES for
        the two-table change (owner accepted); each report still fights for tightness. State the
        flex, do NOT silently break the cap
  [ ] each section (exec + region + segment-with-distinct-mix) leads with the ranked-reasons
        table, then the insights table; both describe the same root causes in the same rank order
  [ ] citation markup: grep -c 'span class="cite"' == 0 on both reports
  [ ] no method/hedge word outside the appendix; no .callout/.note boxes; STE throughout
  [ ] both reports: identical portfolio numbers, scope, header, ordered section list
```
