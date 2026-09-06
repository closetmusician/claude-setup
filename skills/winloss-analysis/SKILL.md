# Win/Loss Analysis

<!-- ABOUTME:
  Produce golden-quality "Why We Win" and "Why We Lose" executive reports for a Acme
  product line, split by region AND segment, leading with the ROOT-CAUSE "why" behind every
  number — not the Salesforce picklist. Every figure carries a basis label and a citation.
  This SKILL.md is a short router; the reference/ files carry the method. Read them on demand.
  Distilled from the Aug 2026 session that produced the reviewed July 2026 v2 BLC reports.
-->

Use when asked to "run a win/loss analysis", "build a why we win report", "why are we
losing", "competitive loss analysis", or to refresh an existing win/loss deck for a new
period. NOT for a single deal post-mortem (just read the opportunity record).

## Reference files — read the one the step points to (don't load them all up front)

| When | Read |
|---|---|
| Before any figure — the dual basis, caveats, number authority | `reference/basis-and-caveats.md` |
| Scoping the period + segment bands + empty-cell vocabulary | `reference/scope-and-segment.md` |
| Digging each finding to a controllable, sourced root cause (incl. the "silence rule") | `reference/root-cause-protocol.md` |
| Writing every sentence in Simplified Technical English — apply BEFORE drafting prose | `reference/STE-STYLE-GUIDE.md` |
| STEP 3b–3d — the analytical moves to TEST, and the rule for which ones get published | `reference/insight-patterns.md` |
| Pulling per-deal evidence (Glean→Gong bridge, `mine-account.py`) | `reference/evidence-mining.md` |
| Copy-paste dispatch prompts for every research/drafting agent | `reference/agent-prompts.md` |
| The exact report skeleton (win & lose share one) | `reference/report-structure.md` + `templates/GOLDEN-*.html` |
| The final content-quality gate (score before shipping) | `reference/quality-rubric.md` |
| A concrete end-to-end run to pattern-match | `reference/worked-example-july2026.md` |
| Reusing the golden HTML templates | `templates/README.md` |

## What golden quality means (the bar you must clear on the first go)

**Caveat first — the GOLDEN files are a MARKUP reference only, not the shape to copy.** They
passed independent Codex review on the pre-Aug-2026 gate, but they predate the amendment set in
this file: they carry dual-basis pairs, `% distribution (anecdotal)` columns, per-cell quote
floors, 262 citation markers and ~14,600 words, and they have no Key Insights table, no money
ranking and no page budget. Consult them for how a stat tile, a table or a `.quote` block is
marked up — never for length, ordering, column shape or citation density.
`reference/report-structure.md` is the sole authority on shape, and only
`GOLDEN-why-we-win.html` exists on disk (there is no golden lose file).

With that caveat, the reports clear the DEPTH bar because they do these things the failed first
drafts did not:

1. **Every rate is computed on BOTH bases and the Finance-clean figure alone is published in
   the body** — never averaged. The all-sizes counterpart lives in ONE appendix comparison
   table. See THE BASIS RULE below. This is the #1 first-go failure.
2. **Every table is accompanied by 2-4 root-cause "why" sentences in prose** drawn from a
   Gong quote, a Finance cell, or a record-level CRM read — never the picklist, and never a
   `.callout` or `.note` box. Lead with WHY, not WHAT. See the narrative-only rule in
   `reference/report-structure.md`.
3. **Every outlier cell is chased to a controllable mechanism**, quantified. Falsify the
   counter-hypotheses in the RESEARCH files; publish only the surviving conclusion — the
   rejected alternatives go to the companion appendix file, never into the report body.
4. **No "went dark / no momentum" as a cause.** Every "unresponsive / postponed / no
   interest" deal is dug to the controllable reason under the silence (thin value, our own
   AI failing a trial, a feature gap, a wrong buyer, a legal/procurement block). See the
   silence rule in `reference/root-cause-protocol.md` §4b.
5. **The two reports are a matched pair** on ONE skeleton, with identical portfolio numbers,
   scope line, competitor caveat, AND an identical compact page-1 header (`h1.section`
   "Why We {Win|Lose} — Executive Summary" + `.product-line` scope line). No magazine cover.
   The two reports render the identical ordered section list in `reference/report-structure.md`;
   the only differences are the word Win/Lose, the numbers, the theme class, and the three
   lose-only sections. Any analytical move or deep-dive in one report appears in the other in
   the same position.
6. **Every sentence is Simplified Technical English** per `reference/STE-STYLE-GUIDE.md` —
   one idea per sentence, under 30 words, active voice, every acronym expanded on first use,
   no jargon soup, no filler. Score the STE gate before shipping.
7. **No boxed asides in the body — the narrative-only rule.** No `.callout` boxes, no
   disclaimer/method/how-to-read `.note` boxes, no "Method and its limits — read before the
   numbers" block, no "Reconciliation note (Aug 2026)" `<p style="border-left…">` blocks. Every
   why, method, and caveat is prose woven next to what it explains. Say each thing once. The
   only non-prose body blocks are stat tiles, tables, `.quote`/`.attrib`, citations, and the
   Sources list.
8. **Cautiously optimistic on the product.** Uncomfortable findings are stated plainly, but
   where the evidence supports a product success it is stated AS a success — not hedged into
   mush or buried under caveats. A win report must not read as a debunking of its own thesis.
   See the product-tone rule in `reference/STE-STYLE-GUIDE.md`.
9. **Product claims are grounded, never hearsay** (the test is GROUNDING, not internal-vs-
   external). A quantitative product NUMBER (win rate, retention, attrition, adoption, ARR) is
   publishable when it traces to a Finance/FP&A workbook cell, Tableau, Salesforce, or Gainsight
   — grounded internal data is fine, no matter which dashboard surfaced it. A qualitative product
   JUDGMENT ("thin", "weak", "not good enough", "the AI failed") is publishable ONLY when a
   first-hand customer says it on a Gong call or in a verbatim Salesforce note. Internal
   Slack/Teams/opinion/OKR/enablement deck/battlecard/analyst-as-customer are BANNED as the basis
   for either. Never invent a negative product mechanism to satisfy the depth gate — no grounded
   source ⇒ open-data-request. See the source rule in `reference/basis-and-caveats.md` §2.5.
10. **Write in ASD-STE100 Simplified Technical English.** One idea per sentence. Active voice.
   Approved everyday words. No metaphor, no idiom, no rhetorical inversion. Define any
   unavoidable term in one clause at first use, or delete it.

   | Before | After |
   |---|---|
   | 'Head-to-head conquest is the exception.' | 'We rarely beat a named competitor. Only 193 of 2,497 losses (7.7%) name one.' |
   | 'Read at record level, most losses are not competitive defeats.' | 'Most losses are not defeats by a competitor. We cause them ourselves.' |
   | 'Governed AI is the stated reason to upgrade.' | 'Customers upgrade to get governed AI. 48 of 104 Enterprise upsell deals (46%) name D1P, BLC Pro or GovernAI.' |

   Banned insider terms: 're-paper' (write 'sign a new contract'), 'Finance-clean', 'all-sizes',
   'a-s', 'picklist', 'load-bearing', 'record-bound', 'the assembler', 'CRIS', 'name-flagged',
   'no-bid', 'contested-loss test', '3-quote floor'. (These terms stay usable in THIS skill file
   and in the report's appendix — they are banned from the report's reading real estate.)

A draft that stops at a picklist code, shows one un-labelled win rate, leaves a "went dark"
theme with no reason under it, carries a boxed aside or a "how to read" block, sources a
product claim to internal material, reads as a debunking of its own thesis, or reads as
jargon-heavy run-ons is incomplete — regardless of how polished it looks.

## The one thing that makes this work

**Finance's monthly results workbooks contain a row per closed-won/lost opportunity** —
account, region, segment, industry, package, stated reason, days-to-close, ARR. Everything
else in the corpus is derivative. Find these first, build the deal-level spine, treat
narrative decks as colour. Known locations (SharePoint › AcmeFinance, names roll forward
monthly): `<YYYYMMDD> BLC <Month> <Year> Results.xlsx` and `<YYYYMMDD> Governance <Month>
<Year> Results.xlsx` (sheet `BLC Wins` is the deal-level extract). Filter every sheet to the
product line before quoting anything.

---

## THE BASIS RULE — read `reference/basis-and-caveats.md` before any figure

**A rate has no meaning without its basis label.** This is the single biggest first-go
failure, so it is impossible to miss:

- **Finance-clean (the ONLY basis published in the report body):** exclude `Duplicate
  Opportunity` rows AND the period's small-deal amendment rows (July: `< $5K Amendment`).
- **All-sizes (the comparison basis):** exclude only `Duplicate Opportunity`. Compute it every
  run — but publish it in ONE appendix comparison table, never as a paired number in the body.
- **Never average the two. Never mix them inside one rate** (a Finance-clean numerator over an
  all-sizes denominator is a fabricated rate). Roughly eighty basis pairs in one report is not
  rigor — it is the reason the reader stops reading.

The amendment filter is period-specific and lives in a control cell in the Finance workbook
— FIND it and CONFIRM it with Finance every run (do not carry July's forward). In July it
removed 8% of losses but 41% of wins, which is the entire win-side story (installed-base
farming, not conquest). `reference/basis-and-caveats.md` also owns the **mandatory-caveats
checklist** and the **number-authority hierarchy + correction log** — apply both.

---

## STEP 0 — Scope the run (ask, don't assume)

Ask via **AskUserQuestion**, batched, before any research. Record answers verbatim into the
brief. If the user does not respond, state the defaults in your first reply and proceed.

```
Q1 header "Period"   — "Which period should the analysis cover?"
  · Previous full month (Recommended)  — e.g. July 2026 only; sharpest recent signal
  · Current quarter to date            — more volume, blurs the month
  · Named month or range               — user supplies
Q2 header "Product"  — "Which product line?"
  · Board & Leadership Collaboration only (Recommended)
  · BLC + Entities · Whole Governance BU
Q3 header "Segments" — "Segment inside each region?"
  · Yes — Ent (incl. Strategic) / MM / SMB (Recommended)  · Region only
Q4 header "Output"   — "Which formats?"
  · Draft HTML only (Recommended)      — PDF/MD/Word generated afterward if asked
  · HTML + PDF · All four
```

- **Period default = the previous full calendar month.** Do not silently widen to a quarter
  — that buries the recent signal and was the single biggest scoping error. Compute it
  explicitly (one-liner in `reference/scope-and-segment.md`), never let an agent infer it.
- **Product default:** BLC only. State what is excluded (Risk, Audit, Compliance,
  Ethics/Whistleblower, Entity/Subsidiary Mgmt, MDO, BoardEffect, Community).
- **Regions default:** AMER + EMEA + APAC.
- **Output default: draft HTML only.** PDF / Markdown / Word are generated afterward by the
  orchestrator if the user asks — do not build all four every run.

Full scoping + segmentation rules (segment bands, empty-cell vocabulary, minimum reportable
cell): `reference/scope-and-segment.md`.

---

## STEP 1 — Write the research brief (the contract)

Create `<out>/research/BRIEF.md` before spawning anything. It must contain:

- The period, product line and regions from Step 0, as **hard filters**.
- **THE BASIS RULE** (above), verbatim — every research figure names its filter chain and both
  bases; the REPORT body then publishes the Finance-clean figure alone.
- **The no-hallucination rule:** every number, name, quote and date comes from a real
  retrieved document; record `[Doc Title | datasource | date | URL/id]` for each; if
  unsourced, write the claim + `[need sources]`. Never round, restate, blend, or carry a
  figure forward. Copy figures exactly.
- **The relentless root-cause protocol** — paste the Iron Rule, the 6-step loop, and the
  dig-deepest triggers from `reference/root-cause-protocol.md` (see Step 2).
- The tooling notes and the mining contract (paste from `reference/evidence-mining.md`) so
  no agent rediscovers the same broken paths.
- The output contract (below).

Agent output contract per file: `## Coverage assessment` · `## Deal ledger` (append rows to
`research/deal-ledger.csv`, one row per deal-to-attribute observation, using the ledger schema
in `reference/evidence-mining.md`) · `## Attribute clusters` (built ONLY after the ledger exists;
each cluster keeps its opportunity IDs, source handles, three proof deals and one contradictory
case) · `## Hypotheses tested` (confirmed/falsified + evidence) · `## Gaps — [need sources]` ·
`## Search log`.

An aggregate theme row does NOT satisfy the contract. Every published cluster retains the deal
IDs and proof deals behind it, or it is descriptive and does not enter synthesis as a cause.

Tell agents: **be exhaustive on searching, conservative on claiming. A finding that stops at
a picklist code is incomplete. Do not write the report — only findings.**

---

## STEP 2 — Fan out research, each agent running the ROOT-CAUSE protocol

**Every mining agent runs the relentless root-cause protocol
(`reference/root-cause-protocol.md`).** Paste its Iron Rule + 6-step loop into each prompt.
For every material cell / theme / named deal the agent must:

1. **Define the comparable cohort** and its common filter chain (period, region, segment,
   motion, basis). State which wins and losses are eligible.
2. **Read each deal record** — Salesforce close notes, stage history, Gong transcript — and
   keep its opportunity ID attached.
3. **Extract one observable decision attribute** from a Gong quote (with call-id) or a verbatim
   SFDC note. The picklist code alone is NEVER sufficient, and a Finance cell alone can size a
   finding but cannot establish its cause.
4. **Apply one stated text-to-attribute rule** to wins and losses alike.
5. **Contrast outcomes** — count wins and losses with and without the attribute inside the
   cohort; name at least one contradictory case.
6. **Write the complete causal chain**: `trigger → attribute → intervention → buyer change →
   outcome`. The controllable lever (coverage, packaging/SKU, qualification, pricing,
   shipped-vs-planned gap, data residency, or internal-product cannibalization — Brainloop /
   GovernAI / BoardEffect / CGlytics / Manzama) is the INTERVENTION, not the cause.
7. **Quantify the cluster** with Finance data — # deals, % of cell, ARR, and at least three
   named proof deals.
8. **Test one alternative explanation in your RESEARCH file** — mandatory; a finding with no
   tested alternative is under-cooked. This never reaches the report body: the report publishes
   the surviving conclusion, and the rejected alternatives go to the appendix or the companion
   appendix file.

A Finance-only cohort is descriptive. A channel, segment, list, gate, package, price, or team is
not a root cause without the decision attribute inside it. A candidate that fails this test
becomes an Open Data Request or appendix finding — it cannot enter synthesis as a root cause.

A finding that cannot bottom out in both a controllable mechanism AND a tier-1–4 source
becomes a numbered **open-data-request**, not a conclusion. Dig every deal in any outlier
cell (a rate well outside the normal ~15–30% band, any "0 of N", any "Chose Competitor").

Roster-first: build per-region×segment won/lost rosters from the Finance CSV spine, then
prioritize (mine EVERY win; losses by outlier-cell → ARR → Chose-Competitor/late-stage →
Unresponsive tail sample; skip sub-$5K amendments for root-cause). Full mining mechanics,
the Glean→Gong bridge, the fuzzy-match verification rule, and `mine-account.py`:
`reference/evidence-mining.md`.

**Win-side miners MUST read the competitor win/loss report and its deep-dives when they exist,
and code every product / AI / competitive takeaway into the deal ledger with a decision
sub-attribute.** Canonical inputs (named so a future run finds them):
`fy27/competitors/reports/all-boards-competitors-vs-acme.md`, `fy27/competitors/deepdives/`,
and any prebuilt `research/PRODUCT-WIN-EVIDENCE.md` digest. A win ledger that is missing
product / competitive wins when a competitor report exists is a mining FAIL, not an acceptable
outcome — the report's named product takeaways must appear in the ledger.

Spawn concurrently, model `opus`, each writing one file to `<out>/research/`. **The moment you
fan out these miners, arm the every-1-minute agent-check loop (STEP 4b, "The agent-check loop") —
this is the wave the Aug 2026 network crash killed mid-run, so the loop watches it too, not just
the drafting writers.** **Ready-to-fill dispatch prompts for every lane below — plus the
fragment-writer, assembler and coherence-harmonizer drafting agents — are in
`reference/agent-prompts.md`; paste from there rather than hand-writing each prompt.** The six region×win/loss miners (the `w-*`/`l-*` rows)
are the core the golden reports were built on; the differentiators / competitors / GTM lanes
are cross-cutting support.

| Agent | File | Brief |
|---|---|---|
| Finance data | `f1-finance-data.md` | **Run first if serialising.** Extract deal-level `BLC Wins` + win-rate/ASP series. Produce counts, ARR, ARR/deal, median days, win rate, ASP — **by region AND segment, on BOTH bases**. Find & confirm the amendment control cell. This is the spine. |
| AMER wins | `w1-amer-wins.md` | Sourced win mechanisms, named deals, displacement, industry mix; test Canada-vs-US |
| EMEA wins | `w2-emea-wins.md` | Same + hosting/residency, regulatory hooks; test sub-region-beats-segment |
| APAC wins | `w3-apac-wins.md` | Same + exchange-listing, residency, referral conversion |
| Differentiators | `w4-differentiators.md` | AI (shipped vs planned — GA dates), privacy, security, licensing, network, analyst position. **Product NUMBERS trace to a Finance/Tableau/Salesforce/Gainsight cell; product JUDGMENTS quote a first-hand customer (Gong/SFDC); no ungrounded knock, no internal-opinion basis — restate from a grounded source or mark `[need grounded source]`** (see `reference/basis-and-caveats.md` §2.5). |
| AMER losses | `l1-amer-losses.md` | Loss mechanisms, competitor, ARR, named deals; dig outlier cells |
| EMEA losses | `l2-emea-losses.md` | Same — pull raw CRM records; dig DACH & any outlier |
| APAC losses | `l3-apac-losses.md` | Same — read every "Chose Competitor" at record level |
| Competitors | `l4-competitors.md` | **Enumerate 3-5 named competitors per region (and per segment where the evidence names any).** The Salesforce competitor field is ~99% blank, so mine the free-text close notes on EVERY "Chose Competitor" loss and the Gong calls — do NOT stop at the dead structured field. For each: region, segment, pricing, mined deal count, battlecard, and which claims are unevidenced. **Return THREE numbers per rival: (a) its CONFIRMED NAMED-CASE COUNT (a plain count, never a percentage — a % over 5-24 named records reads as market share); (b) its HEAD-TO-HEAD WIN/LOSS RATIO per the mandatory method below; and (c) the slice's Finance "Chose Competitor" loss rate (`OPP_PRIMARY_CLOSED_REASON`, fully populated) as ONE number for the slice.** Fewer than 3 named after mining ⇒ list what you found + file an open-data-request. **One rival per agent when a head-to-head rate is the deliverable — a single agent covering five rivals under-mines each; give the top rivals a dedicated agent (see the per-competitor win-rate method below).** |
| Loss taxonomy & pricing | `l5-loss-reasons-pricing.md` | Picklist mechanics & reliability, our price card, competitor price points, product gaps, roadmap dates |
| Regional GTM | `x1-regional-gtm.md` | Headcount, coverage, TAM, regulation, channel, localisation, AI-region capability |

### Per-competitor head-to-head win rate — MANDATORY METHOD (count first, quote second)

A head-to-head win rate is `wins-naming-X ÷ (wins-naming-X + losses-naming-X)`. It sets the
whole competitive narrative, so it must be counted correctly. This method exists because a
prior run reported Board Intelligence at 2W/3L when the true audited count was 7W/11L (up to
~9W/22L at the inclusive floor) — a 6× under-count that inverted the story from "we beat BI"
to "we lose to BI more than we win." The five errors that caused it are banned below.

**The five banned mistakes (each one inflates or shrinks the rate):**
1. **Quote-gating.** NEVER require a Gong/customer quote for a deal to count. The unit is the
   RECORD, not the quote. A closed opportunity whose note names the rival counts even with no
   quote — most losses to a cheap incumbent have a note but no polished quote. Quotes are
   overlaid AFTER the count, decoratively, only where they exist.
2. **Structured-field-only reading.** The SFDC competitor field is ~0.3% populated (often 0%
   for a given rival). You MUST mine FREE TEXT — opportunity name, close/AE notes, SSR forms —
   via `glean search -d salescloud "<rival>" --page-size 100` paged to the END, for EVERY name
   variant and misspelling. Cross-check the deal-level CSV spine; keep Glean-only records the
   CSV misses (BoardEffect-line, old-format `0066T` opp IDs, post-cutoff closes) and note the source.
3. **Mining the loss side only.** You MUST mine the WIN side too — closed-WON deals whose notes
   name the rival (displacement/takeaway wins are titled "X Steal / X Takeaway"). Counting only
   losses, or only wins, both give a false ratio.
4. **Missing churn/renewal losses.** A customer leaving TO a rival is logged as a separate
   "Renewal / Cancelled" opp with a companion Closed-Lost record — easy to miss if you scan only
   new-business opps. Include renewal-churn losses (they are real competitive losses).
5. **Wrong product-line scope.** Some rivals fight almost entirely on an adjacent line (e.g.
   OnBoard/BoardPro in BoardEffect SMB/nonprofit), invisible to a BLC-only pull. Search the
   rival across ALL board-portal lines, then state the line split.

**Required output per rival:** `Won X / Lost Y = Z% win rate` (all deal types) AND the new-logo
split (`OPP_TYPE = New`), with the raw W/L counts shown beside every rate so sample size is
visible. Add a reconciliation line: how many via Glean, how many in the CSV, net after dedupe.

**Always label the rate a FLOOR, biased upward.** A rep had to type the rival's name for a deal
to appear, and reps name a rival more on takeaway WINS than on quiet losses to a comfortable
incumbent — so incumbent win rates (Nasdaq, Sherpany, iBabs) read HIGH and the true rate is
lower. Say this next to the number; never present a mined head-to-head as a clean CRM rate.

**Scale the fan-out:** when a head-to-head rate is a deliverable, give each TOP rival its OWN
audit agent (one competitor per agent) — a single agent covering five rivals under-mines each.
Dispatch prompt: `reference/agent-prompts.md` (competitor-audit template).

**False-positive scrubs (verify every one by reading the note):** our own "Boards Pro" SKU ≠
competitor "BoardPro"; Dutch "… B.V." suffix ≠ BoardVantage; "onboarding" / "on board with" ≠
OnBoard; "convention" ≠ Convene; "additional director license" ≠ Director's Desk; "im Board"
German phrase ≠ I'mBoard; a personal mention ("friend at Board Intelligence") ≠ a competitive deal.

---

## STEP 3 — Segment inside every region (mandatory)

Regional splits alone hide the story — the segments behave like different businesses. Full
rules, bands, and empty-cell vocabulary: `reference/scope-and-segment.md`. In short:

- Segments: **Enterprise (fold Strategic in)**, **Mid-Market**, **SMB**.
- **AMER and EMEA: always split.** **APAC: split if the data supports it, else group and say
  so** — never fabricate a split to fill a table.
- Per region × segment report at least: deal count, ARR, ARR/deal, win rate, ASP, dominant
  **sourced mechanism** (not picklist reason).
- Always test whether **sub-region beats segment** (UKI vs DACH), and always **note what a
  grouping conceals** (folding Strategic hides the worst-retaining tier).

**Split the motions inside the geography.** The region → segment structure stays. Inside it,
the win report must report installed-base expansion, net-new greenfield, and competitive
displacement as distinct populations with their own rates, themes and proof — a single blended
win rate hides three different buyers, opponents and cycles. The loss report must first assign
every record ONCE to an observed outcome class: correct qualification exit · failed buying
process · stalled expansion · confirmed commercial or product defeat · unknown. Themes are a
SECOND, separately labelled view built on top of that funnel. Never let overlapping themes
render as a 100% decomposition.

---

## STEP 3b–3d — Synthesize before you draft (MANDATORY; three stages, separate agents)

All 11 findings files now exist. No drafting agent runs until all three stages are complete.
Every synthesis agent uses model `opus`.

**STEP 3b — Region attribute synthesis (one agent per region, in parallel).** Each agent reads
the deal ledger, its region's source records and the Finance spine, and writes
`<out>/research/ATTRIBUTE-CLUSTERS-<region>.md` and `<out>/research/INSIGHTS-<region>.md`. For
each candidate cluster it records: (1) cohort and boundary; (2) decision attribute and
text-to-attribute rule; (3) wins and losses read; (4) outcomes with and without the attribute;
(5) at least three named proof deals; (6) one contradictory case; (7) the complete causal chain;
(8) deal count, share and ARR.
- Apply the analytical gate BEFORE ranking. Mark each candidate `PASS`, `DESCRIPTIVE`, or
  `UNKNOWN`. **Disaggregate before you demote** (`reference/root-cause-protocol.md`, "Disaggregate
  before you demote"): a broad attribute (product, AI, security, referral) that appears on BOTH
  wins and losses is NOT thereby a non-cause. Subdivide it until you find the specific observable
  sub-attribute that separates the comparable wins from the comparable losses, then publish THAT
  sub-attribute. Mark a candidate `DESCRIPTIVE` ONLY after a genuine subdivision attempt finds no
  separating sub-attribute. AI stays table stakes unless a separating sub-attribute is found.
- Rank only `PASS` candidates by ARR. Select the top three to four for `INSIGHTS-<region>.md` (up
  to five where the evidence supports it; minimum three unless fewer than three `PASS` clusters
  exist for that region — then say so in one sentence). These counts are floors to reach for, not
  a licence to pad. Demote all others with a reason: too small, duplicate, or evidence too thin. A
  `DESCRIPTIVE` cohort (expansion, referral, new logo) that survives a genuine subdivision attempt
  with no separating sub-attribute is NOT eligible for the top selection.

**STEP 3c — Cross-region synthesis (one agent).** Reads all three `ATTRIBUTE-CLUSTERS-<region>.md`
files, the three `INSIGHTS-<region>.md` files AND the deal ledger, and writes
`<out>/research/INSIGHTS-CROSS.md`. Merge only clusters that share the SAME attribute rule and
causal chain — a shared exposure label (both regions "win on referral") is NOT a shared mechanism;
keep different attributes separate even when they use the same channel or segment. A genuine
portfolio attribute is stated once at portfolio level, never three times.

**STEP 3d — Portfolio synthesis, gated then ranked by money (one agent).** Reads the cluster
files, the region files, the cross-region file, the deal ledger and the Finance spine, and writes
`<out>/research/KEY-INSIGHTS.md`. It ranks ONLY analytical-gate `PASS` clusters — never a
`DESCRIPTIVE` or `UNKNOWN` cohort — and verifies every portfolio mechanism against the underlying
deal rows (do not read only the region insight files):
1. **THE headline** — one sentence naming the single biggest CAUSAL driver of wins (and of
   losses): its decision attribute, the buyer change it produced, a named proof deal, and its
   number. Not a list. One sentence. Not a cohort decomposition ("expansion is half the money").
2. **Four to five ranked insights, ordered by ARR** (minimum four unless fewer than four `PASS`
   clusters genuinely exist — then say so in one sentence; these are floors to reach for, not a
   licence to pad) (see the money ladder in
   `reference/report-structure.md` supporting rule 2 when ARR is not available), each with its
   cohort boundary, its decision attribute and causal chain, its three named proof deals, its
   contradictory case, its share of the book, its won or lost ARR, and the intervention we
   control. State what share of the book the set covers, and call the rest "long tail". Separate
   cohort views (expansion, new logo, referral) must NOT compete as independent root-cause
   insights — they are one decomposition of the same book, not three causes.
3. **The portfolio demoted list**, merged from the region demoted lists — including every
   Finance-only cohort that has no separating attribute this run.

**Single-region populations.** A finding whose evidenced population sits in one region is
published at region level only, unless STEP 3d recomputes it portfolio-wide from
`research/rosters/`. Never print a region numerator over a portfolio denominator. If the
portfolio recomputation cannot be done this run, either name the region inside the insight text
("In AMER, customers buy…") or file it as an Open Data Request and publish a 3-row table.
Carry every qualifier the source file attaches to the figure — a source that says "$X is a
floor" makes "$X" alone a FAIL.

**Lift the strongest-in-one-cell finding.** Where a finding is strongest in one segment or one
region but the same mechanism is present portfolio-wide, STEP 3d recomputes it portfolio-wide
and publishes it at portfolio level. "It was mined inside AMER" is not a reason to keep a
portfolio-sized finding at region level.

### The three analytical obligations every synthesis stage must discharge

These are tests, not sections. Run each one and state the answer where the evidence lands.

1. **Growth versus rate — a rate story is not a money story.** For every claim built on a win
   rate, test whether the same claim holds in money and in new customers, and STATE which one it
   is. A cell that wins most often because it is mostly expansion grows the installed base and
   adds almost no customers; say so in the same breath as the rate. Where two published findings
   pull against each other, name the tension in one short block — "a plan that targets the win
   rate grows the base; it does not add customers" — and do not resolve it with a hedge.
2. **Expected ARR per opportunity, wherever a channel or segment mix is in play.** Convert the
   competing win rates into expected ARR per opportunity (win rate × average selling price for
   that channel) and publish both sides. "Referral wins 44.2% against outbound at 17.8%" is a
   rate comparison; "one extra referral new-logo opportunity is worth about $12.4K of expected
   ARR against about $3.5K for an outbound one" is a budget decision. The second is required
   wherever an Action moves volume between channels or segments.
3. **[LOSE] The controllable share of the loss book, in dollars.** See the controllability rule
   below — the first question a leadership reader asks of a lost-ARR total is "how much of it
   could we have had", and the report must answer it in dollars and as a share.

**[LOSE] Controllability.** Assign every lost deal to exactly one outcome class, and mark each
class controllable or not controllable. Publish the controllable share of lost ARR as stat
tile 3, and the per-region controllable share on each region sheet. The assignment rule goes in
the appendix as a table. A class that fuses correct exits with unknowns is a FAIL.

**[LOSE] Region vs portfolio — precedence, when the two assignment rules differ.** A region
miner often builds a stricter local rule (e.g. EMEA/APAC silence-code sets) before the portfolio
rule is reconciled. When they disagree, follow this order and do not improvise:
1. **Recompute the region's class rows onto the PORTFOLIO rule, from the rosters.** This is
   almost always possible — the rosters carry every field the portfolio rule uses. "Recomputation
   is impossible" is a claim you must prove against the roster fields, not a default. In the
   2026d run one region declared it impossible and published its own 61.3%; a later agent
   recomputed the same region on the portfolio rule in one pass and got 64.2%. Try before you
   declare.
2. **Only if genuinely impossible** (a field the portfolio rule needs is absent from that
   region's roster — name the field): publish the region rule, label the figure inline as
   computed on a different assignment rule, AND record that differing rule in the appendix
   assignment-rule table as its own row.
3. **Never print a share that contradicts the table above it on the same sheet.** The region's
   controllable share, the region's class table and the portfolio class table must reconcile —
   same rule, same rosters, same totals. Two regions publishing on two different rules inside
   one report is a FAIL, whichever rule each picked.

**Open Data Requests must cover the gating unknown behind each published insight.** For every
Key Insights row, ask what single unmeasured fact would most change what the row can claim
(for an installed-base insight: saturation, attach rate, remaining headroom). If this run cannot
measure it, it is a numbered Open Data Request.

`KEY-INSIGHTS.md` and the matching `INSIGHTS-<region>.md` are hard inputs to every STEP 4b agent.
A region fragment writer may only elaborate an insight from its own region file. The assembler
builds the exec lead and Strategic Implications directly from `KEY-INSIGHTS.md` §1 and §2, in
that order. Demoted themes and per-cell detail go to the companion research appendix file.
A run that reaches STEP 4 without all five synthesis files is out of protocol.

### The analytical gate — runs BEFORE any drafting agent (MANDATORY)

Write `<out>/research/ANALYTICAL-GATE.md`, one row per candidate insight (schema in
`reference/agent-prompts.md`). A row passes ONLY if it has all of: a decision attribute; a stated
text-to-attribute rule; a within-cohort win/loss contrast; three named proof deals; one
contradictory case; a complete causal chain; decision evidence (Gong or verbatim SFDC); and
Finance sizing on the approved basis.

Any failed row is removed from `KEY-INSIGHTS.md` and `INSIGHTS-<region>.md` before drafting.
Drafting starts only when every selected insight is `PASS`. This gate runs FIRST — before the
10-page, citation-markup, and Simplified Technical English conformance gates, which are unchanged
and run at STEP 5. A well-formatted report must not hide an unresolved mechanism: if the
analytical gate fails, drafting does not start.

### Name the decision attribute, or it is not an insight (applies to every synthesis stage)

Build this chain for every candidate insight:
`context or trigger → decision attribute or friction → Acme intervention → buyer-behavior
change → outcome`. The root cause is the **decision attribute** and its effect on buyer
behavior. The intervention is the lever we control. Do not merge the two.

**Banned terminal labels.** An insight that stops at any of these FAILS the gate — each names a
cohort, a channel, or a lever we own, never the attribute that changed the decision:
`referral` · `target list` · `expansion` · `installed base` · `qualification` · `channel` ·
`new logo` · `coverage` · `package` · `price` · `team` · 'Unresponsive' · 'budget' · 'brand
strength' · 'the customer went quiet'. These labels can define a cohort or an intervention; they
cannot fill the `Causal mechanism + proof deals` field without a separating attribute.

A candidate passes only when it has a within-cohort win/loss contrast, at least three named
proof deals, one contradictory case, and cited decision evidence. A broad attribute that appears
on both wins and losses is NOT a non-cause: subdivide it until the separating sub-attribute
surfaces, then publish that sub-attribute (see "Disaggregate before you demote" in
`reference/root-cause-protocol.md`). If any element is still missing after a genuine subdivision
attempt, mark it `DESCRIPTIVE — NOT A ROOT CAUSE` and demote it before annual-recurring-revenue
ranking. AI stays table stakes absent a separating sub-attribute.

**Worked shape** (finish it from the data; do not publish the chain below as a conclusion):
loss coded 'Unresponsive' → the named contact was not the buyer (Central States: a junior
admin; Mitsui: no board meetings) → the attribute separating these losses from comparable wins
is **no board-meeting cadence at the account** → our qualification gate does not test for it →
**the gate is the intervention; the missing board-cadence attribute is the cause**.

Where a rung cannot be evidenced, stop at the last evidenced rung, name the missing data as
Open Data Request #1, and record it in the appendix — never in the body. The attribute-level
cause goes in the `Causal mechanism + proof deals` column of the Key Insights table and drives
the matching Strategic Implications row.

---

## STEP 4 — Draft the reports on the ONE golden skeleton

The authoritative skeleton is `reference/report-structure.md`. `templates/GOLDEN-why-we-win.html`
is a **structural REFERENCE** — consult one section at a time to see how a stat band, a table, or
a `.quote` block is marked up. It is NOT a master to clone. **Win and lose share ONE skeleton** —
only the framing differs; build the lose report from the same skeleton with lose framing and the
three lose-only sections.

**Do NOT copy the golden file and swap the data — that approach is banned.** It forces one agent
to load the whole golden HTML plus every research file and then emit the entire ~80KB report in a
single write, which stalls the run (this failed twice in Aug 2026). Author each section from the
structure spec and its own research, and write incrementally. The two sanctioned writeout paths —
and the mandatory independent synthesizer/auditor — are in **STEP 4b below**; follow one of them.
The skeleton, in brief:

- **Page 1 = ONE-page decision page:** cover + scope line → **LEAD paragraph of AT MOST five
  sentences and 120 words. Sentence 1 names the decision ATTRIBUTE, the cohort boundary, the
  buyer-behavior change, the outcome and one named proof deal — shape: "In <cohort>, <attribute>
  changed <buyer behavior>, producing <outcome>; <Deal> proves it" — taken straight from
  `KEY-INSIGHTS.md` §1. Sentences 2–4 give the next ranked causal mechanisms, each with an
  attribute and a proof deal. A cohort readout ("expansion is half the money; referral converts
  at 44.2%") is the failure this rule kills — it is a dashboard decomposition, not a cause. The
  paragraph must not end on a methodology pointer; the last sentence is the emphasis position and
  belongs to a finding. No citation markers and no method words in this paragraph** →
  **Key Insights table** (Table 2; 4–5 analytical-gate `PASS` rows from `KEY-INSIGHTS.md` §2 —
  minimum four unless fewer `PASS` clusters exist — in descending
  ARR order: `# | Insight | Causal mechanism + proof deals | Share of the book | Won/Lost ARR |
  What we change`, where the mechanism cell is two or three short plain sentences in ASD-STE100
  Simplified Technical English — no `→` arrows and no clause-joining `;` semicolons — naming the
  attribute, the buyer change, the outcome and three proof deals, and never a cohort label (for
  example: "A director on the buying board already runs Acme elsewhere. That removes the
  board's adoption risk, so the buyer chooses Acme. Proof: Viper Energy, Fossil, Zura Bio."),
  then ONE sentence giving the share of the book the set
  explains and naming the rest as long tail) → 4 stat tiles (Finance-clean figure only; **booked revenue in tile 1; opportunity ARR in
  tile 2, with "not booked revenue" inside the label. Both are direct `REPORTING_ARR` sums —
  never label either "modelled". Use "modelled" only for a figure that is genuinely derived
  rather than summed, and name the derivation on the same line.** **[LOSE] tile 3 is the
  controllable share of lost ARR** — see the controllability rule in STEP 3d) →
  **geo × segment 3×3 matrix** (W/L +
  win rate on the one basis; bold the outlier) → 3-5 "why" sentences (prose). **Page 1 ENDS
  there.** The top-themes table, its prose "why" paragraph, the competitor table and the
  one-line competitor finding are **NOT page-1 elements**. They live on the region sheets, where
  `reference/report-structure.md` "Per region" items 2, 3 and 5 already mandate a copy of each.
  Page 1 carries four things and no more: stat tiles, the lead paragraph, the Key Insights table
  and the matrix. **NO basis/method/how-to-read annotation
  prose ANYWHERE in the body — Appendix-only** (no basis paragraph, no matrix legend, no "read
  the columns", no modelled-ARR/amendment/capture-limitation explanation, and [LOSE] no
  method-and-its-limits paragraph); and NO Appendix pointer at all, including at the end of the
  exec lead.
  Sausage-making in the body is a scored rubric FAIL (Dim 6) and an auditor check (Template 11
  #4b). See report-structure.md supporting rule #7.
- **Per region (AMER, EMEA, APAC):** stat band (with win rate) → **Table 1 (ranked reasons, own
  side, comes first) → the region's insight block of 3–4 rows (up to 5 where the evidence
  supports it; minimum three unless fewer `PASS` clusters exist for that region), in descending
  ARR order, each with its root cause, sourced from
  `INSIGHTS-<region>.md` (same table shape as the Key Insights table)** → ranked theme table (ranked by
  **sourced mechanism**, not coded frequency) → **a prose "why" paragraph of 2-4 mechanisms
  with EVERY table** → **per-region competitor table (FOLLOWS the themes table; 3-5 competitors;
  the confirmed named-case count). [WIN] The competitor table's one-line intro states the
  competitive share of WINS, computed from won-deal notes. If the won-side fill rate cannot
  support a rate, publish the confirmed named-case counts with no rate at all and file the
  competitive share of wins as an Open Data Request. Never introduce a win-side competitor table
  with a loss-side rate ("Chose Competitor" exists only on lost records).** → Voice of the
  Customer (`.quote`/`.attrib` carrying geo AND segment; headers carry the cell name only; ≤15
  quote blocks report-wide; Acme-authored quotes labelled "Deal evidence") → region-specific
  finding woven as prose → **nest per segment** (Ent+Strat → MM → SMB): shorter ARR-ordered
  table, prose "why" paragraph, highlights/lowlights, VoC — and a cell with no distinct finding
  gets ONE SENTENCE, not a section.
- **Outlier deep-dive (CONDITIONAL):** an abnormal cell gets its own section ONLY where its
  mechanism is not already one of the region's top-three insights. Where the region insight
  already carries the mechanism, the outlier is absorbed into that insight as two sentences
  naming the cell and its rate, and no separate section is written. The auditor records
  "outlier absorbed into insight N" — that is a PASS, not a FAIL. Where a separate section IS
  written: numbered mechanisms with record-level evidence, and a quantified verdict.
  **The counter-hypothesis test is a research obligation, not a report section.** Publish the
  surviving conclusion only; the rejected alternatives and their evidence go to the companion
  appendix file. "tested and rejected", "tested and ruled out", "falsified" and
  "counter-hypothesis" are banned in the body.
- **Final:** Strategic Implications — **maximum FIVE rows, ordered by ARR at stake, each row
  `What we do · Because (one line of evidence) · Owner · ARR at stake · First step in 30 days`,
  each acting on its insight's bedrock root cause. The `First step in 30 days` cell must name a
  counted population and the file, report table or system it comes from. A first step whose
  population is not counted somewhere in this report is a FAIL. Where an action changes a channel
  or segment mix, the `Because` cell must carry the expected ARR per opportunity for both sides
  of the change, not only the two win rates** → **Sources ship as a SEPARATE FILE**
  (`why-we-win-sources.md` / `why-we-lose-sources.md`; every surviving marker resolves there,
  never self-cite) → Appendix ≤ 2 pages (basis defs,
  0%-field caveat, reason-code reliability, contested-loss test, Gong-access, CSV tie-out,
  the rejected counter-hypotheses, and [LOSE] the outcome-class assignment rule as a table
  naming each class controllable or not controllable) →
  Glossary → Open Data Requests.
- **Page budget — HARD GATE: 10 rendered PDF pages per report; ~650 words per sheet is a GUIDE,
  not a gate.** The two-table change (RANKED-REASONS + INSIGHTS per section) grows page count, so
  the 10-page target FLEXES for this run (owner accepted). State the flex — do not silently break
  the cap — and each report still fights for tightness. Count PDF pages, never `.sheet` divs
  (`.sheet` flows, so one div can print as two or three pages). An over-guide sheet that still renders inside 10 PDF pages is NOT a defect —
  never cut a sourced finding, caveat or root cause to chase a word count. Over 10 PDF pages: cut
  economy first (wording, repeated numbers, per-cell detail to the companion appendix file), never
  a finding. [LOSE] stated allowances: Actions sheet ~750 words, appendix page 2 ~710 words. Every
  mandated element has a home inside the 10:

  | Pages | Holds |
  |---|---|
  | 1 | Decision page: lead paragraph + Key Insights table + stat tiles + geo×segment matrix |
  | 2 each ×3 = 6 | AMER, EMEA, APAC — each region's 2 pages INCLUDE its segment nest AND its outlier deep-dive |
  | 1 | Actions (≤5 rows). [LOSE] also the late-stage-silence finding + the one-line retention cross-reference |
  | 2 | Appendix, with the Glossary and Open Data Requests INSIDE those 2 pages |
  | **10** | **Total, both reports.** Sources are a separate file and do not consume a page. |

Rendering: one self-contained HTML per report, `<link rel="stylesheet" href="report.css">`,
`<body class="theme-win">` / `theme-lose`. **`report.css` is now fixed to FLOW, not clip**
(`min-height` + `overflow: visible`) — do NOT run an overflow probe and do NOT "tighten until
zero"; let content flow onto continuation sheets. Use only the shared classes; invent no CSS.
The GOLDEN win file carries a legacy in-file override block — keep it as-is, add nothing.

Full skeleton, class list, and the ASCII checklist: `reference/report-structure.md`.
The two reports must read **identically** on shared portfolio numbers, scope, basis, and the
competitor caveat (`reference/basis-and-caveats.md` §3 owns the frozen-figure contract).

---

## STEP 4b — HOW to write the reports (anti-stall; never one monolithic write)

A single agent that loads the golden file plus every research file and then emits the whole
report in one write WILL stall on a large report. This is the single most common failure of this
skill. Never do it. Pick ONE of the two paths below by report size, and in BOTH paths an
**independent synthesizer/auditor** — a different agent from whoever wrote the prose — verifies
the assembled report before it ships. The writer never signs off on its own work.

### Output contract — TWO tables per section (RANKED-REASONS first, INSIGHTS second)

The exec summary, EACH region section (AMER / EMEA / APAC), AND each segment subsection that has
a distinct reason mix carry TWO tables in this order. (A segment cell with no distinct mix stays
one prose sentence — the existing rule — it does NOT force an empty table.)

**Table 1 — Ranked reasons (comes FIRST).** A `table.plain`, own-side only: the Why-We-Win report
ranks WIN reasons, the Why-We-Lose report ranks LOSS reasons. Columns, in this order:

`Rank | Root cause | Share of coded won deals | Won ARR`

- **Rank**: 1, 2, 3 … descending by Won ARR.
- **Root cause**: the disaggregated decision sub-attribute in plain words (max ~10 words).
- **Share of coded won deals**: a COUNT with its denominator, written `34 of 71 coded wins`. It is
  the share of the CODED / mined won deals in this cell, NOT the full finance book — only a sample
  is coded. One prose sentence under the table states this basis once. Where the count is a mined
  floor, say "mined floor".
- **Won ARR** (right-aligned `num`): the coded-attribute-floor ARR.
- Descending by Won ARR. Max 6 rows; the rest fold into a "long tail" row.
- The [LOSE] report's Table 1 has the same shape with `Share of coded lost deals` and `Lost ARR`.

**Table 2 — Insights (the EXISTING table, kept, expanded).** Same six-column `table.plain` shape
as today: `# | Insight | Causal mechanism + proof deals | Share of the book | Won/Lost ARR | What
we change`. It carries MORE rows (see STEP 3b/3d counts) and comes SECOND, after Table 1.

**Table 1 rows and Table 2 rows describe the SAME root causes in the SAME rank order.** Table 1 is
the at-a-glance stack rank (what wins, how often, how much); Table 2 is the detail (mechanism,
proof, intervention). Exact HTML shape and the shared-basis sentence: `reference/report-structure.md`.

Estimate size first: count the sections (exec + 3 regions × [region + segment nest + outlier] +
final pages). A refresh that reuses an existing report's quotes is usually SMALL; a from-scratch
build across three regions is usually LARGE.

### Path A — Single 1M-context writer (small reports, or a targeted refresh)
Use when the report is a refresh of an existing file, or a compact build (≈≤10 sections). Spawn
ONE writer agent, but constrain it so it cannot hang:
- **Use the 1M-context Opus** (the current session's 1M model, e.g. `us.anthropic.claude-opus-4-8[1m]`
  — use whichever `…[1m]` Opus id the running session reports) so the inputs fit with headroom.
  State the model explicitly in the dispatch; do not let it default to a smaller context.
- **Read each input ONCE, then write** — forbid re-reading files in a loop (the observed stall
  was an agent re-scanning inputs instead of writing).
- **Write incrementally: one `Edit`/`Write` call per section (page), appending** — NEVER hold the
  whole report in context to emit in a single call. For a refresh, edit the existing file
  section-by-section in place.
- Return a ≤15-line digest (numbers used, per-section competitor rows, gaps) — not the HTML.
Then run the independent auditor (below).

### Path B — Fragment writers + assembler (large / from-scratch reports) — DEFAULT for a full build
This is the golden-report pipeline and the safe default when in doubt. Fan out, then stitch:
1. **Fragment writers (parallel), model `opus`** — one agent per report section (Win/AMER,
   Win/EMEA, Win/APAC, plus cross-cutting; same for Lose). Each composes ONE self-contained HTML
   fragment from its research files only and writes it to `{OUT}/fragments/<wl>-<region>.html`.
   Prompt = `reference/agent-prompts.md` Template 8. Small input, small output — cannot stall.
2. **Assembler (one per report), model `opus`** — stitches the fragments into the full report,
   builds the wrapper prose (exec summary, strategic implications, appendix), reconciles every
   headline to the Finance spine, and renumbers citations globally. Prompt = Template 9. It reads
   small fragments, not the giant golden file, so it does not choke.
3. **Coherence harmonizer, model `opus`** — one pass across both reports for one voice and
   consistent numbers. Prompt = Template 10.

### The independent synthesizer/auditor (MANDATORY in BOTH paths)
After the report exists, spawn a SEPARATE agent (never the writer/assembler) to verify it against
the sources before anyone claims it done. It must, from the rendered file + the Finance spine:
- confirm every headline number matches the spine, and segment counts SUM to region and portfolio
  totals (this catches a stale-spine copy — the Aug 2026 defect where 755/379/197/179 survived);
- confirm paragraph 1 of the exec summary LEADS with why we win across its whole length and does
  NOT devolve into a caveat dump (one why-sentence followed by three caveat sentences is a FAIL —
  method/basis belongs in the Appendix, not paragraph 1);
- confirm every competitor table has 3–5 rivals, both columns, and follows its themes table;
- confirm zero `.callout`/"how to read" boxes and that every `cite">N` resolves;
- **mechanical check — citation markup.** Run `grep -c 'span class="cite"' <report>.html` on BOTH
  reports. The count must be **0**. Every marker is `<sup class="cite">N</sup>`; `report.css`
  styles `sup.cite` and has NO `span.cite` rule, so a span marker prints as full-size body text
  and the citation disappears. `reference/convert_reports.py` also matches on `sup` only, so a
  span marker silently vanishes from the Markdown/DOCX conversion too. Any hit is a FAIL with
  file:line. (Two consecutive cold runs shipped this defect — check it every time, never assume
  the assembler got it right. `templates/GOLDEN-why-we-win.html` is the reference: 104 markers,
  all `sup`.);
- **mechanical check — Simplified Technical English (STE) syntax.** Grep the rendered report for
  `→`, `&rarr;`, and clause-joining `; ` inside table cells AND body prose. Any hit is a FAIL with
  file:line — `→` arrows and clause-joining semicolons are banned in ALL report output, including
  table cells (`reference/STE-STYLE-GUIDE.md`). The analyst reasoning-chain notation
  (`context → attribute → intervention → change → outcome`) is an analyst tool only and must never
  appear in report output;
- **mechanical check — both sides of a ratio share one filter chain.** For every published
  ratio, "X wins against Y losses" pair, win-rate or loss-rate comparison, name the ONE filter
  chain (period, region, deal type, source/channel, segment, stage, reason code) and confirm
  BOTH sides were counted under it. A pair that mixes populations — e.g. 43 non-referral upsell
  wins against 158 all-source upsell stalls — is a FAIL even when each figure is separately
  correct. Report the chain you tested and the count you reproduced for each side;
- confirm the exec lead is ≤5 sentences and ≤120 words, and its sentence 1 matches
  `KEY-INSIGHTS.md` §1 in substance;
- confirm the Key Insights table exists, has 4–5 rows (minimum four unless fewer `PASS` clusters
  exist) in descending order of ARR (or of the named
  fallback rung), and every row traces to `KEY-INSIGHTS.md` §2 — no demoted theme is promoted
  into it;
- confirm every region sheet carries Table 1 (ranked reasons) ahead of its insight block of 3–4
  rows (up to 5), traced to `INSIGHTS-<region>.md`, and that Table 1 and the insight block share
  the same causes in the same rank order;
- confirm every Key Insights row and every region insight row names a decision ATTRIBUTE with a
  within-cohort win/loss contrast, three named proof deals, one contradictory case and a complete
  causal chain; list any row that ends at a channel, segment, list, gate, package, price, team or
  other exposure label (referral, target list, expansion, installed base, qualification, new
  logo), or that rests only on Finance fields, with file:line, as a FAIL;
- confirm that where a theme is a top row at two levels, the lower-level row carries evidence,
  numbers and a root cause the higher-level row does not. A region row that repeats the portfolio
  row's numbers or its root-cause wording is a FAIL. A region row that sizes the same theme with
  that region's own numbers and adds a region-specific mechanism is correct and is not a
  duplicate;
- confirm no insight prints a region numerator over a portfolio denominator, and that every
  qualifier its source file attaches to the figure ("this is a floor") survives into the report;
- confirm no method word and no hedge word appears outside the appendix; list every hit with
  file:line as a FAIL. Search list: "Finance-clean", "all-sizes", "a-s", "basis", "denominator",
  "verified quotes", "below the floor", "open-data-request", "unsourced", "lower bound",
  "counter-hypothesis", "sample", "picklist", "methodology", "modelled", "modeled",
  "tested and rejected", "tested and ruled out", "falsified";
- confirm the report is 10 pages or fewer and the appendix is 2 pages or fewer, **counted from
  the rendered PDF**;
- **[LOSE]** confirm every lost deal sits in exactly one outcome class, each class is marked
  controllable or not controllable, the controllable share of lost ARR is a stat tile, and each
  region sheet carries its own controllable share. A class that fuses correct exits with unknowns
  is a FAIL;
- confirm every `First step in 30 days` names a counted population and the file, report table or
  system it comes from; a first step whose population is not counted somewhere in this report is
  a FAIL. Where an action changes a channel or segment mix, confirm the `Because` cell carries
  the expected ARR per opportunity for both sides of the change.
It returns a PASS/FAIL list with file\:line evidence. On any FAIL, fix and re-audit — the writer
does not get to declare its own output correct.

**Render the PDF BEFORE the audit. The auditor counts PDF pages, never `.sheet` divs — a sheet
div has `min-height` and `overflow: visible`, so it is not a page. More than 10 PDF pages is a
FAIL: cut content to the companion appendix file and re-render.** Render with
`reference/convert_reports.py` (or the headless-Chrome command in the Tooling section), hand the
auditor the PDF path with the HTML, and re-render after every fix round so the page count the
auditor reads is the current one.

**Orchestrator liveness + agent-check loop.** Judge an agent by its OUTPUT FILE and the
task-completion / API-error notification — never by transcript mtime or size (a frozen transcript
is not a stall; the agent may be mid-read). Treat an agent as stalled only when BOTH hold: its
output file is absent or unchanged, AND wall-clock since launch exceeds the floor (~5 min for a
fragment writer or single miner; ~12 min for an assembler, harmonizer or auditor). On a genuine
stall or an API-error notification, stop and relaunch on the same prompt; on a second death, the
orchestrator applies that bounded task itself rather than relaunching a third time.

Arm this automatically: the moment you fan out a parallel wave (STEP 2 miners, or STEP 4b writers
/ assemblers / auditors), schedule an every-1-minute `CronCreate` self-check (`*/1 * * * *`,
`recurring: true`, session-only). Each fire: check every in-flight agent's output file, print a
one-line status, and nudge the pipeline forward the moment a stage completes (all miners done →
STEP 3b/3c/3d → analytical gate → STEP 4b writers → assembler → harmonizer → auditors → render).
`CronDelete` it once both reports are audited clean AND rendered.

---

## STEP 5 — Adversarial audit (do not skip)

Run **three real Codex passes in parallel** (not Claude subagents):

```bash
node "$HOME/.claude/plugins/cache/openai-codex/codex/<ver>/scripts/codex-companion.mjs" \
  task --wait "<prompt>"
```

Write `<out>/AUDIT-BRIEF.md` first, naming the source-of-truth files, the finding categories
(FABRICATED / DISTORTED / MIS-CITED / UNMARKED GAP / SCOPE VIOLATION / COHERENCE / QUALITY),
and the mandatory-caveats checklist so auditors verify each was handled. Distinct lenses:

1. **Provenance, Win report** — every figure traced to a research file or declared fabricated.
2. **Provenance, Lose report** — same, plus digit-by-digit ARR checks on named-deal tables.
3. **Scope, coherence, fidelity** — cross-report contradictions, out-of-scope figures, basis
   consistency, whether the report is *over*-hedged.

Then run a **fourth Codex pass: spec-conformance against `reference/report-structure.md`** —
**is each report's exec-summary LEAD paragraph about why we win/lose across its WHOLE length —
opening with the strongest reason and continuing with mechanism sentences (a basis/scope/caveat
opening FAILS, and so does one why-sentence followed by three caveat sentences — that is a caveat
dump moved down one line, the #1 first-go failure)**, does every required section exist, is every table accompanied by a prose "why"
paragraph (and are there ZERO `.callout`/`.note`-disclaimer/"how to read"/method boxes), is the
geo×segment matrix present, is EVERY body figure on the one Finance-clean basis with the
all-sizes comparison confined to a single appendix table, are theme tables ordered by ARR with
at most five rows and a stated residual,
**does every competitor table (each region + each segment; NONE on page 1) FOLLOW that section's themes
table, list 3-5 competitors, and carry the `Confirmed named cases (count)` column with NO
percentage on a small named sample**, does every region section carry a win-rate tile + Table 1
(ranked reasons) + an insight block of 3–4 rows (up to 5) + reasons-why table + competitor table,
is the report ≤15 quote blocks
with no quote printed twice and no verification count in any quote header,
**is the exec lead ≤5 sentences and ≤120 words, leading with a decision ATTRIBUTE + named proof
deal (not a cohort readout), with no citation marker, no method word and no Appendix pointer;
does a Key Insights table of 4–5 ARR-ordered `PASS` rows follow it (minimum four unless fewer
`PASS` clusters exist), with every `Causal mechanism + proof deals` cell written as two or three
short plain sentences (no `→` arrow, no clause-joining `;`) naming an attribute, a buyer change,
an outcome and three proof deals (NOT a channel, segment, list, or lever, and NOT a Finance-only
cohort); does Table 1 (ranked reasons) precede the Key Insights table at exec, each region and
each segment-with-distinct-mix, own-side only, sharing the same causes in the same rank order; does every theme that is a top
row at two levels give the lower-level row its own numbers and its own mechanism (a region row
repeating the portfolio row's numbers or wording is a FAIL, a region row sizing the same theme
with its own numbers is correct); does any insight print a region numerator over a portfolio denominator;
is the report ≤10 pages **counted from the rendered PDF, never from `.sheet` divs** with the
appendix ≤2; are the Actions ≤5 rows with an owner, an ARR at stake and a 30-day first step each
that names a counted population and its source; [LOSE] does the report publish the controllable
share of lost ARR as a stat tile and per region**, **is the body FREE of basis/method/how-to-read
annotation sentences everywhere (Appendix-only — a basis paragraph, matrix legend, modelled-ARR
or amendment explanation, capture-limitation preamble, or LOSE method-and-its-limits
paragraph in the body is a FAIL; scan every sheet)**, do the two reports render the identical
ordered section list and identical running header/footer (only Win/Lose + lose-only sections
differ), **is every product NUMBER grounded in a Finance/Tableau/Salesforce/Gainsight cell and
every negative product JUDGMENT grounded in a first-hand customer quote (no ungrounded knock,
no internal-opinion basis)**, do BOTH reports open with the identical compact `h1.section`
header (no magazine cover), is every acronym expanded on first use (STE), is there any leftover
"Reconciliation note" / dated `border-left` aside (there must be none), and does any theme row
stop at "went dark / no momentum" without the reason under it? This gate must pass before done.

Tell auditors: "Be adversarial. Assume claims are wrong until found in a research file. A
short list of real defects beats a long list of speculation." **Verify each finding against
the research yourself before fixing** — auditors are occasionally wrong — then fix all and
re-verify. Also verify mechanically: every `class="cite">N` resolves, source numbering is
continuous, and read the rendered pages back.

**STE conformance grep (hard gate).** Grep both rendered reports for `→`, `&rarr;`, and
clause-joining `; ` inside table cells and body prose. Any hit is a FAIL with file:line — `→`
arrows and clause-joining semicolons are banned in ALL report output, including table cells
(`reference/STE-STYLE-GUIDE.md`). List this in the auditor checklist. The internal analyst
reasoning-chain notation (`context → attribute → intervention → change → outcome`) may stay as an
analyst tool, never in report output.

**Final content-quality gate — score both reports on `reference/quality-rubric.md` before
declaring done.** It scores 10 depth/insight/truth/economy/root-cause/language dimensions 0/1/2;
DO NOT SHIP below 18/20, if any dimension is 0, or if root-cause-depth or truth scores below 2. It also lists the five
defects the GOLDEN reports' own Codex audits caught — pre-empt them.

---

## Tooling (paste into the brief; detailed mining in `reference/evidence-mining.md`)

- `glean-search.js --read` returns **metadata only** and crashes on the array/object
  mismatch. Use `-q "…" --json` with jq, or `glean search --max-snippet-size 5000`.
- Full document text: `glean documents get --json '{"documentSpecs":[{"url":"…"}],
  "includeFields":["DOCUMENT_CONTENT"]}'` — returns Gong transcripts, Confluence bodies,
  Salesforce field values.
- Gong transcripts: `glean search -d gong "<account>"` for call-ids (in the `?id=` URL
  param), then `~/.claude/skills/gong-connect/bin/gong transcript <id>`. Subagents need the
  allow-rule `"Bash(*/skills/gong-connect/bin/gong:*)"` or they stall on a permission prompt.
- Office files: `node ~/Code/pm_os/bin/graph-file-ops.js download --url X --output Y` (both
  flags required), then `uvx --from 'markitdown[all]' markitdown`.
- `graph-workbook.js` 504s on workbooks >60MB — download and parse locally with openpyxl
  (`read_only=True, data_only=True`).
- Rendering: if Playwright's browser is missing, use
  `/Applications/Google Chrome.app/Contents/MacOS/Google Chrome --headless --disable-gpu
  --print-to-pdf=out.pdf --no-pdf-header-footer --virtual-time-budget=6000 file:///…`.
- Guard against synthetic Glean data — some queries return fictional companies from AI
  board-pack fixtures. If names look invented, they are; exclude them.

## Deliverables

`<out>/` — the two reports as **draft HTML** (PDF/MD/Word only if the user asked) ·
`research/` (11 findings files + `deal-ledger.csv` + `ATTRIBUTE-CLUSTERS-<region>.md` ×3 + the 5
synthesis files — `INSIGHTS-<region>.md` ×3, `INSIGHTS-CROSS.md`, `KEY-INSIGHTS.md` — +
`ANALYTICAL-GATE.md` + BRIEF, kept so every figure is re-verifiable) ·
the separate sources file per report · the companion research appendix file holding every
demoted theme and per-cell detail cut for the page budget ·
`AUDIT-BRIEF.md` · optionally `refs/sources/` with archived source documents plus a MANIFEST
mapping each to the claims it supports. Gitignore the confidential Office binaries; track the
text extracts and manifest.
