<!-- ABOUTME:
  The canonical end-to-end walkthrough of a golden win/loss run — the July 2026 BLC build,
  narrated beat by beat so a future run has a concrete path to copy. It shows the ORDER of
  operations and the shape of each artifact, not new method (the method lives in the sibling
  reference/ files, cross-referenced by name throughout). If you are running this skill for a
  new period, read SKILL.md first, then follow this file as the reference implementation.
-->

> **Read as HISTORY, not as the target shape.** This run predates the Aug 2026 amendment set
> (synthesis pipeline, Key Insights table, money ranking, 10-page budget, single-basis body,
> named-case counts, inline attribution). Copy its research mechanics and its root-cause depth;
> do NOT copy its length, its dual-basis pairs, its `% contribution` columns, or its quote
> floors. `reference/report-structure.md` is the authority on shape.

# Worked example — the July 2026 BLC run (the canonical pipeline)

This is the run that produced `templates/GOLDEN-why-we-{win,lose}.html`. It cleared an
independent Codex review on the structure gate and survived two adversarial provenance
passes. Treat it as the reference implementation: same order, same artifact shapes, same
gates. The method behind each beat lives in the other `reference/` files — this file is the
narrative that ties them together and shows what "done right" looked like in practice.

The whole run is one sentence of insight, earned the hard way: **BLC wins by farming the
installed base, and its biggest "losses" are mostly bookkeeping.** Everything below is how we
proved that instead of asserting it.

---

## Beat 1 — Freeze the scope before touching data

We answered the four STEP-0 questions (SKILL.md) and wrote the answers into the brief as hard
filters. The frozen scope was:

- **Period:** July 2026 only — Finance close month `Jul 2026`. Q2 2026 appears **only** as
  explicitly labelled context, never blended into a July number. (The single biggest scoping
  error is silently widening to a quarter — we did not.)
- **Product:** Board & Leadership Collaboration (Boards / BLC) only. Explicitly excluded:
  BoardEffect, Community, Entity/Subsidiary Management (MDO), Risk, Audit, Compliance,
  Ethics, ACL, Market Intelligence.
- **Regions:** AMER (AMS) + EMEA + APAC. MDO is a separate Finance reporting region and is
  out of scope.
- **Basis:** Finance-clean is the primary headline everywhere; all-sizes shown in
  parentheses. (See Beat 2 and `reference/basis-and-caveats.md`.)
- **Output:** draft HTML only. Markdown/PDF generated afterward by the orchestrator via
  `reference/convert_reports.py`.

The scope line was then written **once, identically, into both reports' covers** and frozen
in `CANONICAL-FACTS.md` (see Beat 5). Full scoping and segment-band rules:
`reference/scope-and-segment.md`.

---

## Beat 2 — Build the Finance spine and the rosters FIRST

Nothing was mined, drafted, or claimed until the deal-level spine existed. This is the
backbone every later citation resolves to.

**The spine.** Finance's monthly workbook (`20260803-BLC-July-2026-Results.xlsx`, 63 MB,
sheets `CSP` new-business and `RFL` retention) carries one row per closed opportunity. It was
extracted to two CSVs that became the system of record for every count:

- `fy27/work/csp-blc-july2026.csv` — 638 rows, the win/loss spine.
- `fy27/work/rfl-blc-july2026.csv` — 1,054 rows, the retention spine.

**The dual-basis matrix.** From the CSV we computed the region × segment win/loss matrix on
**both** bases at once — never one rate without the other. THE BASIS RULE
(`reference/basis-and-caveats.md`) defines the two filter chains:

- **Finance-clean (primary):** exclude `Duplicate Opportunity` rows AND rows flagged
  `< $5K Amendment`.
- **All-sizes (secondary):** exclude only `Duplicate Opportunity`.

The amendment filter is period-specific and lives in a control cell (July: `F8`). In July it
removed 8% of losses but **41% of wins** — because 62 of the 150 all-sizes "wins" are sub-$5K
contract amendments to existing customers ($101,237 total). That asymmetry *is* the win-side
story, so it had to be visible in every rate. The clean headline: **88 won / 344 lost =
20.37%**, ASP $18,335.92; all-sizes 150 / 374 = 28.63%.

**The rosters.** Per region × segment, per won/lost, we wrote JSON rosters to
`v2-evidence/rosters/` (18 files: `{AMS|EMEA|APAC}_{ENT|MM|SMB}_{WON|LOST}.json`). Each
record carries acct, opp, arr, seg, subregion, stage-before-lost, reason (picklist — a
hypothesis to test, not truth), type, lead source, days, `amendment` flag, package, org type,
competitor. These rosters are what the mining agents worked from — the picklist reason is
carried only so they could disprove it. Roster mechanics: `reference/evidence-mining.md`.

---

## Beat 3 — Independent Finance audit (recompute, don't trust)

A dedicated audit agent (opus) recomputed every headline figure from the CSVs with the stdlib
`csv` parser only — pandas/openpyxl are banned by the tool-registry — and recorded MATCH /
MISMATCH against the drafting spec. Result in `v2-evidence/finance-audit.md`:

- **13 of 13 figures MATCH**, zero mismatches: the two closed-won counts, two closed-lost,
  two win rates, ASP, all-sizes won ARR, face-value lost ARR, all nine matrix cells (treated
  as one check), and the four GDR components (renewal pool $23,515,793.61, churn
  -$978,094.39, downsell -$962,601.33 → GDR 91.7473%).
- **The one unverified hop, documented honestly:** the CSV→workbook faithfulness step could
  NOT be completed — the 63 MB workbook timed out `markitdown` (exit 124 at 9 min) and
  `graph-workbook.js` needs a SharePoint URL, not a local path. So the figures are trustworthy
  **as extracts of the CSVs**, and this exact caveat was carried into both reports' appendices
  plus an open-data-request (read `F8` and the summary sheets in Excel to close it).

The lesson this beat encodes: a figure that "the agent said matches" is not verified. Recompute
independently, and when a step genuinely can't be done, say so in the report rather than
faking a tie-out.

---

## Beat 4 — Parallel root-cause mining (six agents, the relentless-why loop)

Six mining agents ran concurrently (opus), one per region × win/loss (AMER/EMEA/APAC ×
win/lose), each pointed at its rosters and running the relentless-why loop from
`reference/root-cause-protocol.md`. The contract (in `MINING-BRIEF.md`): treat the picklist as
a hypothesis, read the actual Salesforce record + Gong transcript, find a quote/cell that
confirms or contradicts it, restate as a **controllable mechanism**, quantify it, and **test the
counter-hypotheses in the research file**. (The counter-hypothesis test is a research obligation,
not a report section: publish the surviving conclusion only; the rejected alternatives and their
evidence go to the companion appendix file. "tested and rejected", "tested and ruled out",
"falsified" and "counter-hypothesis" are banned in the report body.) Mine every win and every outlier-cell loss; skip
sub-$5K amendments for root cause. Tooling (the Glean→Gong bridge, `mine-account.py`, the
fuzzy-match verification rule): `reference/evidence-mining.md`. Each agent appended to one
findings file (`w-amer-wins.md`, `l-amer-losses.md`, `l-apac-losses.md`, etc.) and returned
only a short digest.

Three signature outputs show what a finished chain looks like — picklist → record → mechanism
→ quantified → falsified:

- **AMER Mid-Market 1W/44L = 2% is coverage + packaging, not price.** Picklist said
  Unresponsive/No-Interest/Postponed (71%). Record read: 30/45 outbound-sourced, 27/45 die at
  Discovery, **39/45 never had a package or SKU entered**, and ~14/45 already run Boards (the
  logged opp was a failed cross-sell miscoded into new-logo pipeline). The lone "Chose
  Competitor" (Dyne Therapeutics) was a Compliance-Training inquiry with zero board intent.
  Mechanism: a go-to-market defect — cold outbound into under-qualified accounts with no
  fitted mid-market SKU (lowest list price $12K). **Falsified:** "MM fails differently on the
  loss side" (early-loss share 68% ≈ Enterprise and SMB); "the short MM medians prove fast
  wins" (those are *win* medians; MM losses run longer).

- **DACH Swisscom $45,783 → Brainloop is internal competition.** Picklist: Chose Competitor,
  and DACH holds a big share of the "competitive" losses. Record read: Swisscom ran an RFP
  requesting "both Brainloop and Acme" and chose the **Brainloop Meeting Suite — a
  Acme-owned product**. The ARR is likely retained on the Brainloop line, so the BLC loss
  overstates BU-level revenue loss. Reported plainly, with the Salesforce citation, no
  strategy editorializing. **Falsified:** "BoardWise is taking DACH" (never the confirmed
  winner of a single mined deal); "a single ME&A vendor is beating us" (no external vendor
  named as winner of any ME&A loss). Of ~15 headline "competitive" DACH losses, only ~2 name a
  real outside rival (Sherpany).

- **APAC phantom competition: 0 of 72 true head-to-head losses.** Both Salesforce "Chose
  Competitor" rows are mislabels — Dah Sing Bank ($15K) was a Acme **no-bid** over Hong
  Kong data residency; Racing Victoria ($6,679) lost to a **failed GovernAI trial** (our own
  AI product), not a rival. Meanwhile SG Fleet ($18,836, coded "No Interest") is a failed
  Convene displacement — the picklist is wrong in *both* directions. Mechanism: coverage and
  qualification, plus data sovereignty for government buyers. **Falsified:** "stage-gating
  explains the zero competitive coding" — APAC's early-loss share (66.7%) is *lower* than
  AMER's (72.5%), yet it codes 0 of 23 late-stage losses as competitive vs EMEA's 11 of 38, so
  it is a coding-discipline gap, not a stage gap.

Findings that could not bottom out in both a mechanism and a real source became numbered
open-data-requests, not conclusions.

---

## Beat 5 — Fan-out drafting on the ONE golden skeleton

Drafting was a pipeline, not a single write. All prose obeys `~/.claude/skills/yk-voice.md`
and the ONE shared skeleton in `reference/report-structure.md` (win and lose differ only in
framing).

1. **Freeze shared numbers.** Before any section was written, the portfolio numbers, scope
   line, per-region bands, the 3×3 matrix, the basis wording, and the competitor caveat were
   frozen in `CANONICAL-FACTS.md` so both reports read identically on every shared figure.
   The per-region bands there **override** any roster-derived subtotal a fragment computed.

2. **Six section-writers → HTML fragments.** One agent per region per report (`FRAGMENT-BRIEF.md`)
   wrote a `<section class="sheet">` fragment to `v2-evidence/fragments/` (`win-amer.html`,
   `lose-emea.html`, …), using only shared `report.css` classes, citing with **local**
   footnote numbers and a trailing `<!-- CITES: 1=… -->` comment. Rule they all obeyed: lead
   with WHY — every table is followed by 2-4 root-cause bullets from the evidence file, never
   the picklist; no method/disclaimer prose in the body.

3. **Two assemblers → whole reports.** One assembler per report (`ASSEMBLER-BRIEF.md`) wrote
   the one-page exec summary (cover, 4 stat tiles, geo×segment matrix, top-themes table,
   competitor landscape, 3-bullet "how to read"), stitched the three region fragments in
   order, wrote the <0.5-page appendix, and **renumbered every fragment's local citations into
   one continuous global Sources list**, updating each in-body `<sup class="cite">N</sup>`.

4. **One coherence harmonizer per report (opus).** A final pass unified voice, expanded jargon
   on first use, and moved any stray method text to the appendix — logged in
   `harmonizer-lose.md`.

Rendering note: `report.css` is fixed to FLOW, not clip — do not run an overflow probe or
"tighten until zero"; let content break onto continuation sheets.

---

## Beat 6 — Adversarial gates (real Codex, not Claude subagents)

Per SKILL.md STEP 5, real Codex passes ran against the drafts: provenance vs the source data
(every figure traced to a research file or declared fabricated, digit-by-digit ARR on named
deals) and a **spec-conformance pass vs `reference/report-structure.md`**. The structure gate
came back **FIX-NEEDED** on both reports (`codex-spec-gate-findings.txt`) — and catching those
before "done" is exactly why the gate exists. The specific findings caught and fixed:

- **Basis rule slips** — a couple of rates surfaced without their both-bases label; corrected
  to always show clean headline + all-sizes in parens.
- **Table schema** — APAC segment tables (and AMER-MM, EMEA-SMB in the win report) were
  missing the `% contribution` / representative-customers columns; every theme table was
  standardized to `Theme | Mechanism (the why) | % | Representative customers`.
- **Lead-with-why gaps** — several tables had no "why" beside them; 2-4 "why" sentences were
  added after each (e.g. the exec-summary top-themes table, EMEA ranked-losses). (Historical
  note: this July pass phrased the fix as adding a `.callout` block — the skill LATER reversed
  that; every "why" is now prose, and `.callout` boxes are banned. See the narrative-only rule
  in `reference/report-structure.md`.)
- **Method-in-body** — denominator/reconciliation/"Note:" text (the AMER-MM 44-vs-45 count,
  the EMEA 130→116→109 reconciliation, the APAC "% of 72" framing) was moved out of the body
  into the appendix and open-data-requests; the body kept only insight.
- **VoC tagging** — Voice-of-the-Customer quotes were tagged with geo AND segment for each
  cell.
- **Glossary** — a compact glossary (BLC, AMER/EMEA/APAC, ENT/MM/SMB, DACH/UKI/ME&A/FR&BE,
  SFDC, D1P, GovernAI, GDR, ASP/ARR/SKU) was added to each appendix, with first-use expansion
  in the cover bullets.

Every finding was re-verified against the research before fixing (auditors are occasionally
wrong), then all were fixed and the gate re-run to pass. Citations were mechanically
re-checked: every `class="cite">N` resolves, numbering continuous, no report cited as its own
source.

---

## Beat 7 — The through-line the run produced

The whole pipeline converged on one matched-pair insight — stated identically in both reports'
strategic-implications sections, evidence-only, no strategy editorializing:

- **Why we win:** BLC wins by **farming the installed base** — expansion, referral, and
  director familiarity — not by net-new competitive conquest. 53 of 88 clean wins (60%) are
  expansion of existing Boards accounts; 52 of 88 (59%) are referral-sourced; named-competitor
  takeaways are rare (~6 of 88). SMB first-board greenfield is the new-logo engine (27 of 35
  clean new logos).
- **Why we lose:** the biggest "losses" are largely **CRM-hygiene, internal-Brainloop moves,
  and miscodes** read at record level — 244 of 344 (71%) close before Proposal. **Genuine
  competitive defeat is narrow and concentrated:** SMB price in AMER (BoardWorks/OnBoard ~2×)
  and Sherpany in DACH (~50% cheaper + Swiss hosting). The one structural gap that is not a
  coding problem is **Mid-Market coverage and packaging** (AMER MM 2%; MM Outbound 0W/41L
  worldwide; no SKU fitted to a mid-market company).

Both halves are the same event seen from two sides, which is why the reports share a skeleton
and every portfolio number.

---

## The order, in one glance (copy this sequencing)

1. Freeze scope (STEP 0) → write it once into both covers and `CANONICAL-FACTS.md`.
2. Extract the Finance CSV spine → compute the dual-basis matrix → write per-cell rosters.
3. Independently recompute every headline figure; document any hop you couldn't verify.
4. Fan out one mining agent per region × win/loss; each runs the relentless-why loop and
   returns a findings file, not prose.
5. Freeze shared numbers → fragment-writers → assemblers (renumber cites) → harmonizer.
6. Real Codex provenance + structure gates; verify each finding, fix, re-run to pass.
7. State the matched-pair through-line; ship draft HTML.

Sibling references: THE BASIS RULE, frozen-figure contract, mandatory-caveats checklist →
`reference/basis-and-caveats.md`. Relentless-why loop → `reference/root-cause-protocol.md`.
Glean→Gong bridge + `mine-account.py` → `reference/evidence-mining.md`. Skeleton + class list
→ `reference/report-structure.md`. Scope/segment bands → `reference/scope-and-segment.md`.
HTML→PDF/MD → `reference/convert_reports.py`. Styling → `reference/report.css`.
