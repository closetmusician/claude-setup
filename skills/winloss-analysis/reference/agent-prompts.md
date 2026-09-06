<!-- ABOUTME: Copy-paste dispatch prompts for the win/loss research + assembly agents.
     ABOUTME: The orchestrator fills the {PLACEHOLDERS} per run and pastes each block into a
     ABOUTME: subagent Task. They exist so the FIRST fan-out dispatches deep root-cause miners,
     ABOUTME: not shallow fact-collectors — every miner runs the 6-step relentless-why loop.
     ABOUTME: Proven shape: Finance spine -> per-region miners -> fragment writers -> assemblers -> harmonizer. -->

# Agent prompt templates — win/loss research and assembly

These are ready-to-use dispatch prompts. The orchestrator fills the `{PLACEHOLDERS}` and
pastes each block into a subagent (model `opus` for every one — never downgrade). They
encode the mining contract that actually produced the July 2026 BLC golden reports, so the
first fan-out digs the *why*, not just the *what*.

**How to use this file**
1. Run STEP 0/1 of `SKILL.md` first — you need the confirmed period, product line, regions,
   segments, and the Finance CSV/workbook path before any of these prompts have real values.
2. Add the gong allow-rule to a `settings.json` before fanning out miners (see the preamble's
   tooling block) — without it subagents stall on a permission prompt they cannot answer.
3. Dispatch **Template 1 (Finance spine + rosters) FIRST and alone.** Every miner depends on
   its roster JSONs. Do not start miners until the spine agent returns its rosters path.
4. Then dispatch the **six region×win/loss miners in ONE message** (parallel).
5. When all six miner files exist, WRITE THE REPORTS per `SKILL.md` STEP 4b — pick the path by
   size. Large / from-scratch build (the default): dispatch the **fragment writers** (Template 8,
   one per report section) in parallel, then the **two assemblers** (Template 9), then the single
   **coherence harmonizer** (Template 10). Small report or targeted refresh: one 1M-context writer
   that reads each input once and writes incrementally (one section per Edit call). NEVER copy the
   golden file and swap the data, and NEVER emit the whole report in one write — both stall the run.
6. After each report exists, **render the PDF FIRST**, then dispatch the **independent auditor**
   (Template 11) — a DIFFERENT
   agent from the writer/assembler — and hand it the PDF path with the HTML. It reconciles
   numbers to the spine (segment sums included), counts **PDF pages, never `.sheet` divs**,
   checks the lead paragraph and competitor tables, and returns SHIP / FIX-AND-RE-AUDIT.
   Re-render after every fix round so the page count the auditor reads is the current one.
   The writer never signs off on its own work.

`{PLACEHOLDERS}` used below:
`{PERIOD}` (e.g. "July 2026") · `{PRODUCT}` (e.g. "Board & Leadership Collaboration (BLC)") ·
`{REGION}` (AMER | EMEA | APAC) · `{WL}` (wins | losses) · `{OUT}` (the run's output root) ·
`{ROSTERS}` (`{OUT}/research/rosters/`) · `{PATH}` (the agent's own output file) ·
`{FINANCE_CSV}` (the Finance-clean deal list) · `{FINANCE_XLSX}` (the source workbook) ·
`{REPO}` (repo root you run tools from, e.g. `/Users/yklin/Code/PM`) ·
`{OUTLIER_CELLS}` (this run's abnormal region×segment cells, filled after the spine returns).

---

## SHARED PREAMBLE — paste at the top of EVERY research agent (Templates 1–8)

> You are one of several parallel research agents building the {PERIOD} "{PRODUCT}" win/loss
> reports. Your job is to find the ACTUAL root cause of why customers bought or rejected
> {PRODUCT} deals that closed in {PERIOD} — the third-level *why*, not the surface count.
> A theme with no transcript or quote behind it is worth less than one deal quoted verbatim
> with a citation. **Depth beats breadth.**
>
> ### Scope filter — treat as a hard wall
> - Period: **{PERIOD} only.** Do not widen to a quarter or half-year. A wider window buries
>   the recent signal — that was the single biggest scoping error in the original run.
> - Product line: **{PRODUCT} only.** Explicitly EXCLUDE Risk, Audit, Compliance,
>   Ethics/Whistleblower, Entity/Subsidiary Mgmt, MDO, BoardEffect, Community. Filter on the
>   reporting-solution field, not the folder — three "EMEA Boards" losses in the last run were
>   actually BoardEffect.
> - Basis: **Finance-clean.** Every number you cite must trace to the roster JSON or the
>   Finance workbook `{FINANCE_XLSX}` / `{FINANCE_CSV}`. Do not invent, round, restate, or
>   "clean up" a figure — copy it exactly. Do not carry a figure over from a reference deck
>   unless the source itself states it.
> - Skip `amendment:true` rows for root-cause — they are sub-$5K contract tweaks (add-a-user,
>   add-a-committee), not competitive sales. Note them only as a basis caveat.
>
> ### The no-hallucination rule (verbatim, non-negotiable)
> Every number, percentage, company name, quote, and date must come from a real retrieved
> document. Record `[Doc Title | datasource | date | URL-or-call-id]` for each. If you cannot
> source a claim, write it and append `[need sources]` — never guess, never extrapolate,
> never cite a report as its own source. A short honest file beats a long invented one.
>
> ### The causal-attribute loop — RUN THIS ON EVERY CANDIDATE FINDING
> A candidate finding = any region×segment cell, any theme that will get a table row, any named
> deal you cite, and every outlier. For each, do all nine steps and write them down:
> 1. **Define one comparable cohort.** Hold period, region, segment, motion and basis constant.
>    State which wins and losses are eligible.
> 2. **Read each eligible record.** Open the individual Salesforce close notes, the opportunity
>    stage history (where did the deal die?), and the Gong transcript. Keep the opportunity ID
>    attached to every observation. Never summarize from the aggregate. Treat the picklist as a
>    hypothesis to disprove — it blames competitors who were never in the room and hides real
>    losses under "no interest."
> 3. **Extract the observable attribute or friction that changed the decision.** An observable
>    property of the buyer, account, offer, product, process, competitor, or event. Not a
>    channel, segment, list, or lever.
> 4. **State ONE text-to-attribute rule and apply it to BOTH wins and losses.** Capture the exact
>    source handle (Gong call-id + date, or verbatim SFDC note author + date). A Finance cell can
>    SIZE the finding but cannot establish the attribute.
> 5. **Count outcomes with and without the attribute inside the cohort.**
> 6. **Name at least three proof deals and one contradictory deal** — a deal where the attribute
>    was present but the outcome did not follow, or the outcome occurred without it.
> 7. **Write the causal chain:** `trigger → attribute → intervention → buyer change → outcome`.
>    The controllable lever (coverage, packaging/SKU, qualification, pricing, shipped-vs-planned
>    gap, data residency, or internal-product cannibalization — Brainloop, GovernAI, BoardEffect,
>    CGlytics, Manzama) is the INTERVENTION, not the cause.
> 8. **Quantify with Finance:** deal count, % of the cohort, ARR. ("14 of 45 non-amendment MM
>    losses, 31%, ~$188K ARR.")
> 9. **Test one alternative explanation in your research file.** A finding with no tested
>    alternative is under-cooked.
>
> `Referral`, `target list`, `expansion`, `installed base`, `qualification`, `channel`, `new
> logo`, `coverage`, `package`, `price` and `team` are NOT terminal causes — they are exposure
> labels or levers we own.
>
> **Disaggregate before you demote (win side and loss side).** A broad capability (product, AI,
> security, referral) that appears on BOTH wins and losses is NOT thereby a non-cause. Subdivide it
> until you find the specific observable sub-attribute that separates the comparable wins from the
> comparable losses, and publish THAT. Worked example: "product" appears on wins and losses;
> subdivide to "Acme One Platform sold as ONE consolidated licence" — it wins at 46.4% against
> 10.4% for non-platform deals, and the one platform LOSS (AG2R La Mondiale) happened only when the
> same platform was pitched as two separate products. Mark a candidate `DESCRIPTIVE` ONLY after a
> genuine subdivision attempt finds no separating sub-attribute. AI stays table stakes unless a
> separating sub-attribute (a governed, approved place for board data — risk containment, not
> feature superiority) is found; never claim AI as a net product win.
>
> A candidate without a separating attribute, a within-cohort contrast,
> decision-source evidence, three proof deals and one contradictory case is DESCRIPTIVE: mark it
> `NOT PUBLISHABLE AS ROOT CAUSE`. If it cannot bottom out in an attribute AND a hard source, it
> becomes a numbered **open-data-request** (specific answerable question + suggested owner), not a
> soft assertion in the body.
>
> ### Source-strength ladder — every conclusion rests on tiers 1–4
> 1 Gong verbatim (call-id + date) — beats everything · 2 Finance/FP&A workbook cell (sheet+cell)
> · 3 Tableau/dashboard metric (verify the axis — a $M gridline is not a percentage) · 4
> Salesforce record note (verbatim, author+date) · 5 Picklist code — a hypothesis to disprove,
> NEVER sufficient alone. When two sources conflict the higher tier wins; when Finance and a
> deck disagree, Finance wins (say so, show both).
>
> ### Source rule for PRODUCT claims (hard rule — the test is GROUNDING, not internal-vs-external)
> A **product claim** = any statement about what the product does, ships, lacks, wins on, loses
> on, its adoption, retention, attrition, quality, or roadmap. Two tests, by claim type.
> (A) A quantitative product NUMBER (win rate, retention/churn/attrition, adoption, ARR) is
> publishable when it traces to a grounded data cell — Finance/FP&A workbook, Tableau/analytics
> dashboard, Salesforce, or Gainsight. Grounded internal data is fine; a retention or attrition
> number is allowed even though it is "internal".
> (B) A qualitative product JUDGMENT ("thin", "weak", "not good enough", "the AI failed") is
> publishable ONLY when a first-hand customer says it on a Gong call (call-id + date) or in a
> verbatim Salesforce note (author + date).
> BANNED for BOTH as the basis: internal Slack/Teams, internal opinion, "N internal sources
> say…", an enablement deck, an OKR slide's editorial claim, a battlecard, or an analyst quote
> presented as customer voice. Never invent a negative product mechanism to hit the depth gate —
> no grounded source ⇒ restate from a grounded source or file an open-data-request. (Owned in
> `reference/basis-and-caveats.md` §2.5.)
>
> ### Fuzzy-Glean verification rule — CRITICAL
> Glean returns FUZZY matches. A returned call may be a different product line at the same
> company (a Compliance-Training / Highbond / ACL call surfacing under a board-portal account)
> or a different company with a similar name. Before you quote ANY call, confirm it maps to the
> real {PERIOD} {PRODUCT} opportunity for that account: check the **speakers** (are they from
> this account?), the **product** discussed (is it {PRODUCT}?), and the **date** (near the
> closing month). Cite only calls you verified. Quoting an unverified fuzzy match is how a
> wrong "why" gets into the report. Also guard against synthetic test data — some Glean queries
> return fictional companies from AI board-pack fixtures; if names look invented, exclude them.
>
> ### Your evidence tools (all authenticated; do not rediscover the plumbing)
> Run everything from `{REPO}`.
> - **One-shot miner (start every account here):**
>   `{REPO}/.venv/bin/python3 fy27/output/tools/mine-account.py "Account Name"` — runs Glean
>   across gong+salescloud+gainsight, prints call titles/snippets/call-ids and the SFDC +
>   Gainsight context, and pulls full transcripts for the top calls. Copy this tool into the
>   new period's `tools/` and adapt (account list, datasources, transcript cap) rather than
>   rebuilding it — it bakes in the parse and call-id extraction below.
> - **Glean direct (narrower follow-ups):** `glean search -d gong "<account> pricing"` (Gong
>   only) · `glean search -d salescloud "<account>"` (opp fields, close notes, competitor
>   free-text) · `glean search -d gainsight "<account>"` (CS notes) · omit `-d` for all sources.
>   Parsing gotcha: glean prints its JSON then a trailing release notice — parse the FIRST
>   object with `json.JSONDecoder().raw_decode(out.lstrip())`, ignore everything after.
> - **Full Gong transcript by id:** `~/.claude/skills/gong-connect/bin/gong transcript <id>`
>   (call-ids appear in Gong URLs as `?id=<digits>`; extract with `[?&]id=(\d+)`).
> - **Local corpus:** grep `fy27/refs/sources/` for pre-pulled `Gong-*.md` / `Salesforce-*.md`.
> - **Auth/autonomy gotchas:** check `glean auth status` before starting; the gong CLI is
>   blocked from autonomous subagent runs UNLESS a `settings.json` has
>   `"Bash(*/skills/gong-connect/bin/gong:*)"` — the orchestrator must add this before fan-out.
>   The Gong transcript endpoint is intermittently flaky (returns empty or HTML on re-auth
>   need); when it fails, fall back to Glean-indexed Gong snippets + Salesforce close notes
>   (both citable if verified), and note the fallback in your caveats.
>
> ### Digest-to-file contract (Rule 1)
> Mining produces far more text than fits in an orchestrator's context. You MUST:
> - **Append findings to `{PATH}` AS YOU GO** — never hold transcripts or partial analyses only
>   in context; compaction destroys in-context state mid-run.
> - **Return to the orchestrator ONLY a ≤15-line digest plus your file path.** Never return
>   transcripts or the full findings body.
>
> ### Voice and hard rules
> - **ASD-STE100 Simplified Technical English (STE) is the mandatory writing standard for every
>   word you write — findings, digests, and prose alike** (`reference/STE-STYLE-GUIDE.md`): one
>   idea per sentence, under 30 words, active voice, every acronym expanded on first use, one
>   term per concept, no jargon without a one-clause gloss, no filler. Apply it BEFORE you write.
> - yk-voice: plain English, specific (name the customer, the mechanism, the number), no hype,
>   no jargon left undefined. State uncomfortable findings plainly; do NOT editorialize about
>   strategy or another team's performance — write the artifact, not a verdict. Tone on the
>   product is cautiously optimistic: where the evidence supports a product success, state it as
>   a success and attach the caveat in the same breath. Do not hedge a well-sourced win into
>   mush; do not write a win report as a debunking of its own thesis (`reference/STE-STYLE-GUIDE.md`,
>   product-tone rule).
> - Every quote carries a citation to a verified call/doc. No citation → don't use it.
> - **NO-AUTO-COMMIT:** do not run git commit/add/push. Leave your output file in place and
>   report its path.

---

## Template 1 — Finance spine + rosters (DISPATCH FIRST, ALONE)

> [PASTE SHARED PREAMBLE]
>
> **Role: Finance spine and roster builder. You run before anyone else; every miner depends on
> your output. Build the deal-level truth and the target lists first.**
>
> 1. **Locate and load the Finance-clean deal list.** Extract the deal-level `BLC Wins`-style
>    sheet from `{FINANCE_XLSX}` (workbooks >60MB 504 through graph-workbook.js — download with
>    `node ~/Code/pm_os/bin/graph-file-ops.js download --url X --output Y` then parse locally
>    with openpyxl `read_only=True, data_only=True`), or read `{FINANCE_CSV}` if already
>    extracted. Filter to {PRODUCT} and {PERIOD} exactly. Watch the traps: exclude MDO from any
>    "global" total; exclude Entity/BoardEffect rows; a "14 deals, $1.1M, 132 days, $76K avg"
>    line is Entities, not Boards.
> 2. **Build the dual-basis matrix FIRST.** Produce a region×segment matrix on BOTH bases:
>    (a) raw/all-in, and (b) Finance-clean (amendments and out-of-scope rows removed). For each
>    cell give: won count, lost count, win rate, ARR, ARR/deal, median days-to-close, ASP, and
>    dominant win/loss picklist reason. Group Strategic into Enterprise. Segment bands:
>    Enterprise $1.5B+ · Mid-Market $251M–$1.49B · SMB <$250M (only the MM band was ever
>    confirmed verbatim in a source — mark the others as unconfirmed if you cannot verify them).
>    Show both bases side by side; never average them. This matrix is the spine every downstream
>    number reconciles to.
> 3. **Flag the OUTLIER cells.** Normal single-cell win rates sit in a 15–30% band. List every
>    cell outside it (abnormally high OR low) — these get the deepest deal-by-deal dig by the
>    miners. Call out any "0 of N competitive" or "0W/NL" cell explicitly (a zero is almost
>    never real — usually a coding artifact). Hand the miners a ready `{OUTLIER_CELLS}` list.
> 4. **Build per-region×segment×W/L rosters as JSON** under `{ROSTERS}`, one file per
>    `{REGION}_{SEG}_{WL}.json` (REGION=AMS|EMEA|APAC, SEG=ENT|MM|SMB, WL=WON|LOST). Each record:
>    `acct, opp, arr, seg, subregion, stage_before_lost, reason` (picklist — a HYPOTHESIS to
>    test, not truth), `type, source` (lead source), `days, amendment` (true = sub-$5K
>    amendment), `pkg, org, comp` (competitor free-text). Rosters give every miner a bounded
>    target list and a priority order — miners do not mine blind.
>
> Append the matrix (both bases), the outlier list, and a per-region deal-count summary to
> `{PATH}` as you go. Write the roster JSONs to `{ROSTERS}`.
>
> **Digest to return (≤15 lines):** total in-scope deals and ARR; the region×segment matrix
> headline numbers on the Finance-clean basis; the outlier cells with their rates; the roster
> file paths under `{ROSTERS}`; `{PATH}`. Nothing else.

---

## Template 2–7 — Region × win/loss miners (DISPATCH ALL SIX IN ONE MESSAGE)

Instantiate once per `{REGION}` ∈ {AMER, EMEA, APAC} × `{WL}` ∈ {wins, losses}. Fill `{REGION}`,
`{WL}`, and point `{PATH}` at that lane's file (e.g. `{OUT}/research/w1-amer-wins.md`,
`l1-amer-losses.md`, `w2-emea-wins.md`, `l2-emea-losses.md`, `w3-apac-wins.md`,
`l3-apac-losses.md`). Paste in the `{OUTLIER_CELLS}` the spine agent returned.

> [PASTE SHARED PREAMBLE]
>
> **Role: {REGION} {WL} miner. Your rosters are the `{REGION}_*_{WL}.json` files in
> `{ROSTERS}`. Load them first — they are your bounded, prioritized target list.**
>
> ### What to mine (prioritize — you cannot deep-mine everything)
> - **If {WL} = wins:** mine EVERY win in your region across all segments. Wins are fewer and
>   are the richest material for "why we win." For each: what actually closed it — displacement
>   of a named incumbent, a shipped capability (get GA dates; distinguish shipped from planned),
>   data residency/hosting we could offer, a regulatory or exchange-listing hook, price, or
>   network effect. Bottom out on the controllable win mechanism, quoted.
>   **Read the competitor win/loss report and its deep-dives WHEN THEY EXIST — this is a hard
>   input, not optional.** Canonical inputs: `fy27/competitors/reports/all-boards-competitors-vs-acme.md`,
>   `fy27/competitors/deepdives/`, and any prebuilt `research/PRODUCT-WIN-EVIDENCE.md` digest. Code
>   EVERY product, AI and competitive takeaway they name into the deal ledger with a decision
>   sub-attribute (keep the opportunity ID). **A win ledger that is missing product/competitive
>   wins when a competitor report exists is a mining FAIL, not an acceptable outcome** — the report's
>   named product takeaways MUST appear as ledger rows.
> - **If {WL} = losses:** mine by priority order —
>   (a) **every loss in an OUTLIER cell** from `{OUTLIER_CELLS}` — see the deep-dig rule below;
>   (b) **top losses by ARR**;
>   (c) **every loss coded "Chose Competitor" OR that reached Proposal or later** — late-stage
>       losses carry the real competitive signal, and the competitor field is ~0–3% populated,
>       so every "Chose Competitor" is a free-text claim to read at record level and either
>       confirm with a tier-1–4 source or expose as a mislabel;
>   (d) **sample the Unresponsive / No-Interest / Postponed tail** — test whether these are
>       really coverage/qualification failures rather than product losses.
>
> ### DIG DEEPEST on outlier cells
> For any cell in `{OUTLIER_CELLS}` that falls in your {REGION}×{WL} scope, **read every single
> deal in it.** Abnormally low cells (near-zero win rate, "0 of N competitive", "0W/NL") are
> where miscodings, no-bids, internal-product moves, and phantom competition hide — a zero is
> almost never real. Reproduce the worked-chain shape for each: **picklist said X → record
> shows Y → controllable mechanism Z → quantified → counter-hypothesis falsified.** (Gold-
> standard chains to imitate live in `reference/root-cause-protocol.md` §4: AMER MM 2% =
> coverage+packaging not price; DACH/Swisscom→Brainloop = internal competition + miscodings;
> APAC 0-of-72 = phantom competition; and the retention/fabricated-stat chains.)
>
> ### What to produce (deal ledger FIRST, clusters AFTER — append as you go)
> - **Deal-ledger rows** — append one row per deal-to-attribute observation to
>   `{OUT}/research/deal-ledger.csv`, using the ledger schema in
>   `reference/evidence-mining.md`. Keep the opportunity ID attached. Record `UNKNOWN` when the
>   evidence names no decision attribute — never infer one from a Finance field.
> - **Attribute clusters** — build ONLY after the ledger exists, using the cluster schema in
>   `reference/evidence-mining.md`. For each cluster show the within-cohort win/loss contrast
>   (wins and losses with and without the attribute), at least three named proof deals, one
>   contradictory deal, the causal chain `trigger → attribute → intervention → buyer change →
>   outcome`, and the Finance size (count, % of the region's {WL}, ARR). Mark each `PASS`,
>   `DESCRIPTIVE`, or `UNKNOWN`.
> - **Voice of customer** — pull 5+ verified verbatim quotes per geo×segment cell as raw
>   material; each attributed (customer, call/doc id, won or lost) and carrying geo AND segment.
>   Where a cell has fewer, pull all that exist; never fabricate to fill.
> - **Outlier deep-dive** — if your scope owns one, the mechanism with per-deal evidence.
> - **Hypotheses tested** — each with confirmed/refuted + the evidence, in your research file.
>
> ### Done-check before you call your section done
> Every deal has an opportunity ID in the ledger · every published cluster names a decision
> attribute (not a channel/segment/list/lever) with a stated text-to-attribute rule · every
> cluster has a within-cohort win/loss contrast, three proof deals and one contradictory case ·
> every outlier cell in scope had every deal read · every mechanism is quantified (# deals, % of
> cell, ARR) · every "Chose Competitor" was read at record level · every conclusion rests on a
> tier-1–4 source · a cluster with no separating attribute is marked `DESCRIPTIVE`, and anything
> that couldn't bottom out is a numbered open-data-request, not a soft body assertion.
>
> **Digest to return (≤15 lines):** your top 3–5 `PASS` attribute clusters (each: attribute →
> buyer change → outcome, with 3 proof deals and its %/ARR); any `DESCRIPTIVE` cohort you had to
> demote and why; the outlier verdict if you own one; the count of "Chose Competitor" claims read
> and how many survived; open-data-requests raised; the ledger path, the cluster-table path, and
> `{PATH}`.

---

## Template 8 — Section fragment writer (parallel, one per report section)

The golden reports were built fast and consistent by parallel per-region section writers, each
emitting a self-contained HTML fragment, then stitched by assemblers. Dispatch one per section:
per region for each of the two reports (e.g. Win/AMER, Win/EMEA, Win/APAC, Lose/AMER, Lose/EMEA,
Lose/APAC), plus the cross-cutting sections (Win/differentiators, Lose/competitor-landscape).
Fill `{REGION}`, `{WL}`, `{PATH}` (the fragment file, e.g. `{OUT}/fragments/lose-emea.html`),
and `{SOURCE_FILES}` (the miner + spine files this fragment draws from).

> [PASTE SHARED PREAMBLE — you write from mined evidence only; do not invent to fill a section]
>
> **Role: HTML fragment writer for the {WL} report, {REGION} section (or the named cross-cutting
> section). You do NOT re-mine — you compose from the research files `{SOURCE_FILES}`. If a claim
> is not in those files, do not write it; raise it as a gap instead.**
>
> **HARD INPUTS: `{OUT}/research/ANALYTICAL-GATE.md`, `{OUT}/research/ATTRIBUTE-CLUSTERS-{REGION}.md`,
> `{OUT}/research/INSIGHTS-{REGION}.md`, and `{OUT}/research/KEY-INSIGHTS.md`.** Stop if any file
> is missing, and stop if a selected insight is not marked `PASS` — the run is out of protocol
> (SKILL.md STEP 3b–3d). You may only elaborate a `PASS` insight from your own region. Copy its
> decision attribute, its causal chain, its named proof deals, its cohort boundary and its Finance
> size from the passed cluster — do NOT replace them with a channel, segment, or Acme lever. A
> theme on the DEMOTED list does not go in the fragment; it goes to the companion research
> appendix file.
>
> Write a self-contained HTML fragment to `{PATH}` following the reference structure:
> **One fragment shape for BOTH win and lose fragments** (the single shared skeleton): stat band
> (with win rate, Finance-clean figure only — no all-sizes pair) → **the region's RANKED-REASONS
> table (Table 1, comes FIRST)** — a `table.plain`, own-side only (`# | Root cause | Share of coded
> {won|lost} deals | {Won|Lost} ARR`), descending by {Won|Lost} ARR, MAX 6 rows, the rest folded
> into a "long tail" row. "Share of coded {won|lost} deals" is a count with its denominator,
> written `34 of 71 coded wins` — the share of the CODED/mined deals in this cell, NOT the full
> finance book; one prose sentence under the table states this basis once (say "mined floor" where
> the count is a mined floor) → **the region's insight block (Table 2, comes SECOND) — 3 to 4 rows,
> up to 5 where the evidence supports it** (`# | Insight | Causal mechanism + proof deals | Share of
> the book | Won/Lost ARR | What we change`, descending ARR, straight from `INSIGHTS-{REGION}.md`;
> the `Causal mechanism + proof deals` cell is TWO or THREE short plain sentences in ASD-STE100
> Simplified Technical English, no `→` arrows and no clause-joining `;` — never a cohort label. Model
> cell: "A director on the buying board already runs Acme elsewhere. That removes the board's
> adoption risk, so the buyer chooses Acme. Proof: Viper Energy, Fossil, Zura Bio." Minimum 3
> rows unless fewer than 3 `PASS` clusters exist for this region — then say so in one sentence).
> Table 1 rows and Table 2 rows describe the SAME root causes in the SAME rank order →
> reasons-why theme
> table **ordered by ARR, maximum FIVE rows**, ranked by sourced mechanism never by record count
> + prose "why" → per-region competitor table (`Confirmed named cases (count)` — never a
> percentage on a small named sample) → Voice of the Customer → region-specific
> finding woven in prose → **segment analysis** (Ent/MM/SMB — a cell with no distinct finding
> gets ONE SENTENCE, not a section). Do not use a different order for
> wins than for losses. (Retention, the late-stage-silence deep-dive, cross-region patterns, and
> recommendations are assembler-owned lose-only sections — do not duplicate them here.)
>
> **[LOSE] Region vs portfolio outcome-class rule — precedence (SKILL.md STEP 3d).** Your region
> miner may have built a stricter local assignment rule than the reconciled portfolio rule in
> `KEY-INSIGHTS.md`. When they differ, in this order:
> 1. **Recompute your region's class rows onto the PORTFOLIO rule, from `{ROSTERS}`.** The
>    rosters carry the fields the portfolio rule uses, so this is nearly always possible.
>    "Impossible to recompute" is a claim you must prove by naming the missing roster field —
>    it is not a default. A 2026d region declared it impossible and published its own regional
>    share; a later agent recomputed it on the portfolio rule in one pass and got a different
>    number. Try first.
> 2. **Only if genuinely impossible:** publish the region rule, label the figure inline as
>    computed on a different assignment rule, and emit a `<!-- ASSIGNMENT-RULE: ... -->` note so
>    the assembler adds that rule as its own row in the appendix assignment-rule table.
> 3. **Never print a share that contradicts the table above it on the same sheet.** Your
>    controllable share, your class table and the portfolio class table must reconcile on one
>    rule, one roster set, one total.
>
> **Population matching — both sides of every ratio share ONE filter chain.** Any ratio,
> "X wins against Y losses" pair, win-rate or loss-rate comparison you publish must have both
> sides counted under the SAME filter chain (period, region, deal type, source/channel, segment,
> stage, reason code). Write that chain into the fragment's `<!-- SOURCES -->` block. In 2026d a
> sheet compared 43 non-referral upsell wins against 158 all-source upsell stalls: each figure
> was real, the comparison was not. If the loss side you want is only available on a wider or
> narrower filter, either recount it on the win side's chain or do not publish the pair.
>
> **No boxes.** Write every "why", mechanism, and caveat as prose `<p>` next to its table.
> Do NOT emit `.callout` or disclaimer `.note` elements — the narrative-only rule
> (`reference/report-structure.md`) bans them. The only non-prose blocks you may emit are
> stat tiles, tables, and `.quote`/`.attrib` customer-voice blocks.
>
> Every competitor table — exec, region, and segment — ALWAYS follows that section's themes
> table, lists 3–5 named competitors, and carries ONE quantitative column:
> `Confirmed named cases (count)` = the number of records that name this rival. **Never a
> percentage** — a percentage computed on 5, 12 or 24 named records reads as market share in an
> executive table, and the word "anecdotal" in the header does not repair it. Write "four
> confirmed named cases", not "4 of 24 named (17%)". The slice's competitive-loss rate
> (`OPP_PRIMARY_CLOSED_REASON = "Chose Competitor"` share of Closed Lost, from the Finance
> workbook) is ONE number for the whole slice: state it ONCE in the sentence above the table,
> never as a column repeated down every row. The capture limitation (the competitor field is
> filled on 0.04% of records, so every count is a floor) goes in the appendix, once — not here.
> If fewer than 3 rivals are named after mining, list what you found and
> file an open-data-request for the rest.
>
> Rules that keep it credible: reproduce every figure exactly (label anything rounded, derived,
> or blended); show BOTH values when sources conflict, never average; label marketing claims as
> marketing and AI market estimates as estimates; distinguish shipped from planned for every
> capability with dates; put the honest counter-evidence in; cut exclusivity claims ("the only
> platform that…") — they almost never survive; "aligned to" ISO/IEC 42001 ≠ "certified to."
> Product claims are grounded, never hearsay (the test is GROUNDING, not internal-vs-external).
> A quantitative product NUMBER (win rate, retention, attrition, adoption, ARR) is publishable
> when it traces to a Finance/FP&A workbook cell, Tableau, Salesforce, or Gainsight — grounded
> internal data is fine. A qualitative product JUDGMENT ("thin", "weak", "not good enough", "the
> AI failed") is publishable ONLY when a first-hand customer says it on a Gong call or in a
> verbatim Salesforce note. Internal Slack/Teams/opinion/OKR/enablement deck/battlecard are
> BANNED as the basis for either — restate from a grounded source or mark `[need grounded
> source]`. Never invent a negative product mechanism to hit the depth gate (source allowlist,
> `reference/basis-and-caveats.md` §2.5).
>
> **ASD-STE100 STE is a hard gate.** Before writing any prose or any table cell, read and apply
> `reference/STE-STYLE-GUIDE.md`. No `→` arrows and no clause-joining `;` semicolons anywhere in
> report output. One idea per sentence, active voice, under 30 words, every acronym expanded on
> first use. The analyst reasoning notation (`context → attribute → intervention → change →
> outcome`) is an internal tool ONLY — it must never appear in report output.
>
> **Write in Simplified Technical English (`reference/STE-STYLE-GUIDE.md`):** one idea per
> sentence, under 30 words, active voice, every acronym expanded on first use, one term per
> concept, no jargon without a one-clause gloss, no filler. **No metaphor, no idiom, no
> rhetorical inversion** — write "We rarely beat a named competitor. Only 193 of 2,497 losses
> (7.7%) name one", not "Head-to-head conquest is the exception". Banned insider terms:
> "re-paper" (write "sign a new contract"), "Finance-clean", "all-sizes", "a-s", "picklist",
> "load-bearing", "record-bound", "the assembler", "CRIS", "name-flagged", "no-bid",
> "contested-loss test", "3-quote floor". **Never leave a "went dark / no
> momentum / unresponsive" theme without the controllable reason under it** (silence rule,
> `reference/root-cause-protocol.md` §4b). **No footnotes or dated "reconciliation note" asides,
> and NO basis/method/how-to-read annotation prose in the fragment at all** — no basis
> definitions, no amendment-filter mechanics, no modelled-ARR explanation, no
> "the competitor field is blank / names are anecdotal / a lower bound" preamble, no matrix or
> table how-to-read legend. Those live ONLY in the Appendix (assembler-owned) and footnotes.
> Your fragment states FINDINGS. **Never label a direct sum "modelled"** — lost opportunity ARR
> is a direct `REPORTING_ARR` sum, so write "not booked revenue", and reserve "modelled" for a
> figure that is genuinely derived, with the derivation named on the same line. **No
> counter-hypothesis prose either**: the test belongs in your research file, the report carries
> the surviving conclusion alone — "tested and rejected", "tested and ruled out", "falsified" and
> "counter-hypothesis" are banned from the fragment. Explanatory sentences
> are not allowed, and neither is a dual-basis pair — publish the Finance-clean figure ALONE
> (report-structure.md supporting rule #7). **Never splice a
> customer's words with the sales rep's into one quote** — attribute each speaker separately.
> **Quote-block headers carry the cell name ONLY** — no "(5 verified)", no "2 verified quotes,
> below the floor", no "below the 3-quote floor". There is no per-cell quote floor. Include a
> quote because it is good evidence. Never print the same quote twice. A quote spoken or written
> by a Acme employee — including a Salesforce close note — is not customer voice: label that
> block "Deal evidence".
>
> **Every win/loss RATE uses one consistent basis for BOTH numerator and denominator.** When
> you compute a split rate (for example "on-platform vs off-platform win rate"), filter the
> LOSSES with the same basis you filter the WINS — drop duplicate-opportunity rows from both.
> A win count on one basis over a loss count on another is a fabricated rate. Publish the
> Finance-clean FIGURE ALONE in the fragment — the all-sizes counterpart belongs in the single
> appendix comparison table the assembler owns, never as a paired number in your prose, tiles,
> matrix cells or tables. (This was a real
> defect: a "42.7% vs 9.4%" platform lever mixed duplicate losses into the denominator; the
> correct clean figure was 46.4% vs 10.4%.) Re-derive every rate from the spine at draft time.
>
> **Do not attribute a whole cohort to one mechanism without cohort-level evidence.** "All 75
> net-new APAC wins are platform-plus-AI" is a fabrication if the findings only name a few
> examples. Say "several named wins show X" and give the count you can source. Likewise, put a
> named customer under the theme its OWN record supports — do not move a Security-reason account
> into the Brand row to fill a cell.
>
> **Scope every figure to the report's period.** If a number covers a wider window than the
> report's period (a rolling campaign total, a prior-year comparison), label the window inline
> ("Sep 2025–Jun 2026 campaign, not the report window") — do not present it as an in-period figure.
>
> **Attribution:** prefer INLINE attribution in the source's own name — `— Bank of Hawaii, Gong,
> Mar 2026`. Superscript markers are allowed in region and appendix content only, never stacked;
> where a paragraph makes one claim backed by the same source throughout, attribute once at the
> paragraph end. Where you do emit a marker, use local placeholders `<sup class="cite">[[cust:CALLID]]</sup>` or
> `[[fin:sheet!cell]]` inline — the assembler renumbers them globally. **The wrapper tag is `sup`,
> never `span`: `report.css` styles `sup.cite` only — there is no `span.cite` rule, so a
> `<span class="cite">` marker prints as full-size body text and stops reading as a citation.**
> Do NOT hand-number
> citations; parallel fragments would collide. Emit a `<!-- SOURCES: ... -->` comment block at
> the end of the fragment listing every marker → `[Doc Title | datasource | date | URL/call-id]`
> so the assembler can build the Sources appendix.
>
> Use the reference CSS classes (`.sheet`, `.stat-tile`, running header/footer) from
> `reference/report.css` — do not invent new styling. Match the surrounding fragment style.
>
> **Digest to return (≤15 lines):** the section's headline stat line; # theme rows and # quotes
> included; any figure you could not source (listed as gaps for the assembler); `{PATH}`.

---

## Template 9 — Report assembler (one per report: Why We Win, Why We Lose)

Two assemblers run after all fragments exist — one stitches the Win report, one the Lose report.
Fill `{WL}`, `{FRAGMENTS}` (the fragment dir), `{PATH}` (the assembled report, e.g.
`{OUT}/why-we-win.html`), and `{SPINE}` (the Finance spine file for the matrix + totals).

> [PASTE SHARED PREAMBLE — you assemble; you do not invent. Every figure traces to a fragment,
> the spine, or a research file.]
>
> **Role: {WL} report assembler. Stitch the section fragments in `{FRAGMENTS}` into one
> print-ready HTML report at `{PATH}`, following the reference structure.**
>
> **ASD-STE100 STE is a hard gate.** Before writing any prose or any table cell, read and apply
> `reference/STE-STYLE-GUIDE.md`. No `→` arrows and no clause-joining `;` semicolons anywhere in
> report output. One idea per sentence, active voice, under 30 words, every acronym expanded on
> first use. The analyst reasoning notation (`context → attribute → intervention → change →
> outcome`) is an internal tool ONLY — it must never appear in report output.
>
> **HARD INPUTS: `{OUT}/research/ANALYTICAL-GATE.md`, `{OUT}/research/KEY-INSIGHTS.md`, the three
> `INSIGHTS-<region>.md` files, and the three `ATTRIBUTE-CLUSTERS-<region>.md` files.** Build the
> report ONLY from rows marked `PASS`. You build the exec lead from `KEY-INSIGHTS.md` §1 and the
> Key Insights table and the Actions section from §2, in that order — you do not choose the
> headline yourself. The lead and every insight row must name the decision ATTRIBUTE and its proof
> deals; the action cell names the intervention. Do NOT turn a `DESCRIPTIVE` or `UNKNOWN` cohort
> into a conclusion. If any file is missing, STOP and report: the run is out of protocol (SKILL.md
> STEP 3b–3d).
>
> **PAGE BUDGET — HARD GATE: 10 RENDERED PDF PAGES. GUIDE: ~650 words per sheet.** Words are a
> proxy; pages are the gate. If a sheet runs over the guide but the report still renders inside
> 10 PDF pages, that is NOT a defect — never cut a sourced finding to chase the word count.
> **[LOSE] stated allowances: the Actions sheet up to ~750 words (it carries Actions + the
> late-stage-silence finding + the retention cross-reference) and appendix page 2 up to ~710
> words (method + glossary + Open Data Requests). Both measured at those lengths and both still
> render as ONE page.** Count PDF pages, never
> `.sheet` divs — `.sheet` has `min-height` and `overflow: visible`, so a sheet grows and one div
> can print as three pages. Every mandated element is allocated inside the 10. Decision page
> (tiles + lead + Key Insights + matrix, and nothing else — the themes and competitor tables are
> region elements) = 1; each region = 2 pages **including its segment nest
> AND any outlier deep-dive it still needs** (3 × 2 = 6); Actions = 1, and for the LOSE report that same page
> carries the late-stage-silence finding and the ONE-line retention cross-reference; Appendix = 2,
> with the Glossary and the Open Data Requests INSIDE those 2 pages, not as extra sheets. Sources
> are a separate file and consume no page. Total 10. A section that spills onto an extra sheet has
> busted the budget — cut it, do not let it run. A cell with no insight behind it
> gets ONE SENTENCE, not a section. Content you cut for length is NOT deleted — move it to the
> companion research appendix file that ships with the report. Say each thing ONCE: a theme is
> stated at the level where it is strongest and is not repeated at the other levels.
>
> **Write incrementally — never emit the whole report in one call.** Create the file with the
> wrapper head + exec summary, then append each fragment/section with its own `Edit`/`Write` call.
> Read each fragment ONCE; do not re-scan inputs in a loop. Holding the entire ~80KB report in
> context for a single write stalls the run — this is the #1 failure mode of this skill (STEP 4b).
> You are NOT the final sign-off: an independent auditor verifies your output against the spine
> after you finish (SKILL.md STEP 4b).
>
> 1. **Build the wrapper the fragments don't own** — and write ALL of its prose (executive
>    summary, method, strategic implications, recommendations, appendix, glossary) in ASD-STE100
>    Simplified Technical English (STE), `reference/STE-STYLE-GUIDE.md`: one idea per sentence,
>    under 30 words, active voice, every acronym expanded on first use, one term per concept, no
>    jargon without a one-clause gloss, no filler. The fragments arrive in STE; keep the wrapper
>    in STE too, so the whole report reads as one controlled-English voice. Both reports open
>    IDENTICALLY: an
>    `<h1 class="section">Why We {Win|Lose} — Executive Summary</h1>` + a `<p class="product-line">`
>    scope line, then straight into the 4 stat tiles. Do NOT use the old magazine cover
>    (`h1.cover-title` + `.cover-sub` + `.cover-meta` + a "Portfolio at a Glance" `<h2>`).
>    Both reports render the SAME ordered sections — the single shared skeleton in
>    `reference/report-structure.md`. The only differences allowed are the word Win/Lose, the
>    numbers, the theme class, and the LOSE-ONLY sections marked below. Follow this one order for
>    BOTH reports; the lose assembler additionally renders the method prose, the late-stage-
>    silence deep-dive, and the retention section:
>    1. Decision page (one sheet): compact header + scope line → **LEAD paragraph of AT MOST five
>       sentences and 120 words. Sentence 1 names the decision ATTRIBUTE, the cohort boundary, the
>       buyer-behavior change, the measured outcome and one named proof deal — shape: "In <cohort>,
>       <attribute> changed <buyer behavior>, producing <outcome>; <Deal> proves it." It comes
>       straight from `KEY-INSIGHTS.md` §1. Sentences 2–4 give the next ranked causal mechanisms,
>       each naming an attribute and a proof deal. A cohort readout ("expansion is half the money;
>       referral converts at 44.2%") is the failure this rule kills — it is a Tableau
>       decomposition, not a cause. The paragraph must NOT end on a methodology pointer; the last
>       sentence is the emphasis position and belongs to a finding. NO citation markers and NO
>       method words in this paragraph** → **RANKED-REASONS TABLE (Table 1, comes FIRST, before the
>       Key Insights table): a `table.plain`, own-side only (the Why-We-Win report ranks WIN
>       reasons; the Why-We-Lose report ranks LOSS reasons) —
>       `Rank | Root cause | Share of coded {won|lost} deals | {Won|Lost} ARR`, descending by
>       {Won|Lost} ARR, MAX 6 rows with the rest folded into a "long tail" row. Root cause = the
>       disaggregated decision sub-attribute in plain words (max ~10 words). "Share of coded
>       {won|lost} deals" is a COUNT with its denominator, written `34 of 71 coded wins` — the share
>       of the CODED/mined deals in this cell, NOT the full finance book; ONE prose sentence under
>       the table states this basis once (say "mined floor" where the count is a mined floor).
>       {Won|Lost} ARR is the coded-attribute-floor ARR, right-aligned. Table 1 rows and the Key
>       Insights (Table 2) rows describe the SAME root causes in the SAME rank order** → **KEY
>       INSIGHTS `table.plain` (Table 2, comes SECOND): 4–5 rows straight from
>       `KEY-INSIGHTS.md` §2, in descending ARR order —
>       `# | Insight | Causal mechanism + proof deals | Share of the book | Won/Lost ARR | What we change`
>       (the `Causal mechanism + proof deals` cell is TWO or THREE short plain sentences in
>       ASD-STE100 STE, no `→` arrows and no clause-joining `;` — never a cohort label; model cell:
>       "A director on the buying board already runs Acme elsewhere. That removes the board's
>       adoption risk, so the buyer chooses Acme. Proof: Viper Energy, Fossil, Zura Bio.") —
>       followed by ONE sentence giving the share of the book the set explains and
>       naming the rest as long tail. Minimum 4 rows unless fewer than 4 `PASS` clusters genuinely
>       exist — then say so in one sentence. Only analytical-gate `PASS` rows; no demoted theme may
>       be promoted into this table.** → 4 stat tiles
>       (**booked REVENUE in tile 1; opportunity ARR in tile 2 with "not booked revenue" IN the
>       label. Both are direct `REPORTING_ARR` sums — NEVER label either "modelled"; reserve
>       "modelled" for a genuinely derived figure and name the derivation on the same line.
>       [LOSE] tile 3 = the controllable share of lost ARR**; the
>       Finance-clean figure alone — the all-sizes counterpart goes in the ONE appendix
>       comparison table) → geo×segment matrix + prose "why".
>       **PAGE 1 ENDS THERE.** The top-themes table, its prose "why", the competitor table and
>       the one-line competitor finding are **region-sheet elements, NOT page-1 elements** — a
>       page-1 sheet carrying either table is a FAIL and is the single largest cause of a report
>       printing 16 PDF pages against a 10-page cap. Page 1 carries four things: tiles, lead, Key
>       Insights table, matrix. Aim under ~650 words (guide, not a gate — the gate is the page).
>       NO basis/method/how-to-read prose anywhere in the exec (no
>       basis paragraph, no matrix legend, no "read the columns", and [LOSE] NO
>       method-and-its-limits paragraph) — ALL of that goes to the Appendix, per
>       report-structure.md supporting rule #7. **NO Appendix pointer at all**, including at the
>       end of the exec lead. Put the full basis defs, the ONE all-sizes comparison table,
>       amendment-gap, opportunity-ARR note, 0%-competitor caveat, reason-code register,
>       contested-loss test, **the rejected counter-hypotheses with their evidence, [LOSE] the
>       outcome-class assignment rule as a table naming each class controllable or not
>       controllable,** and (LOSE) method-and-its-limits in
>       the Appendix section you build — 2 pages maximum.
>    2. AMER → EMEA → APAC, each in the same shape: stat band (with win rate) → the region's
>       RANKED-REASONS table (Table 1, FIRST — `Rank | Root cause | Share of coded {won|lost} deals |
>       {Won|Lost} ARR`, descending by ARR, max 6 rows, own-side only, one basis sentence under it)
>       → the region's insight block (Table 2, SECOND — same table shape as Key Insights, with the
>       `Causal mechanism + proof deals` column written as plain sentences with no `→`/`;`, from
>       `INSIGHTS-<region>.md`, descending ARR; 3 to 4 rows, up to 5 where the evidence supports it,
>       minimum 3 unless fewer than 3 `PASS` clusters exist for that region — then say so) →
>       reasons-why table,
>       ARR-ordered, max 5 rows
>       + prose "why" → per-region competitor table (follows the themes table; 3–5 rivals;
>       confirmed named-case count. **[WIN] its intro states the competitive share of WINS from
>       won-deal notes — never a loss-side "Chose Competitor" rate; if the won-side fill rate
>       cannot support a rate, print the counts with no rate and file an Open Data Request**)
>       → Voice of the Customer → region-specific finding woven in
>       prose → **[LOSE] the region's controllable share of lost ARR** → segment nest (a cell with
>       no distinct finding gets ONE SENTENCE, not a section)
>       → that region's outlier deep-dive **ONLY where its mechanism is not already one of that
>       region's top-three insights; otherwise absorb it into that insight as two sentences
>       naming the cell and its rate, and write no separate section — that is correct, not a
>       shortfall. NO counter-hypothesis prose in the body in either shape.**
>    3. [LOSE ONLY] Late-stage-silence deep-dive.
>    4. [LOSE ONLY] Retention cross-reference — ONE entry: the booked ARR lost from the base and
>       the largest controllable churn reason. The booked retention figure LEADS the loss
>       report's stat tiles; lost opportunity ARR is never tile 1, and opportunity ARR and booked
>       revenue are styled differently. Neither is labelled "modelled". The full retention
>       treatment ships as its own decision brief, not as a chapter here.
>    5. ACTIONS / Strategic Implications — MAXIMUM FIVE rows, descending ARR at stake:
>       `What we do · Because (one line of evidence) · Owner · ARR at stake · First step in 30 days`.
>       Rows come from `KEY-INSIGHTS.md` §2 in the same order, and each acts on that insight's
>       BEDROCK root cause, not its symptom. "Resource the land-and-expand engine" FAILS; "Build
>       a director-affiliation register from the 150 Brand Strength wins and route every
>       multi-board director to CS" PASSES. **Every `First step in 30 days` names a COUNTED
>       population and the file, report table or system it comes from — a first step whose
>       population is not counted somewhere in this report is a FAIL. Where an action changes a
>       channel or segment mix, the `Because` cell carries the expected ARR per opportunity for
>       BOTH sides (win rate × that channel's ASP), not only the two win rates. Where two actions
>       pull against each other, name the conflict in one closing paragraph and sequence them.**
>       The section must NOT contain "it does not judge
>       strategy" or any equivalent — judging is the point of the section. (The win report folds
>       the global differentiators fragment in here.)
>       → Appendix (+ Glossary, 2 pages max) → numbered open-data-requests. **Sources ship as a
>       SEPARATE FILE** (`why-we-win-sources.md` / `why-we-lose-sources.md`), not as a page of
>       the report.
>    Both reports must read identically on the shared portfolio numbers, scope line, basis
>    wording, competitor caveat, and this page-1 header treatment.
> 2. **Reconcile every headline to `{SPINE}`.** The cover tiles, exec summary, and portfolio
>    table must match the Finance-clean matrix exactly. Recompute any "global" total by summing
>    only in-scope regions — never trust a pre-blended figure that might include MDO/Entities.
> 3. **Renumber citations globally.** Walk the fragments in order, replace each
>    `[[...]]` placeholder marker with a sequential superscript **`<sup class="cite">N</sup>` —
>    the tag is `sup`, NEVER `span`**, and build one continuous Sources appendix from the
>    fragments' `<!-- SOURCES -->` blocks. Every `cite">N` must resolve to exactly one appendix
>    entry; no dangling numbers; numbering continuous.
>
>    **`span.cite` is a known recurring defect — two consecutive cold runs shipped it.**
>    `report.css` carries a `sup.cite` rule and NO `span.cite` rule, so a `<span class="cite">`
>    marker inherits body size and the reader sees a stray full-size number, not a citation.
>    Before you report done, run `grep -c 'span class="cite"' <report>.html` on BOTH reports and
>    require the count to be **0**. A non-zero count is a defect you fix, not a note you pass on.
> 4. **Verify mechanically before you finish.** `report.css` now FLOWS content onto
>    continuation sheets (`min-height` + `overflow: visible`); do NOT run an overflow probe and
>    do NOT "tighten until zero overflow" — that was the wrong fix. Let long sections flow. Check
>    instead: every `cite">N` resolves, numbering is continuous, both reports open with the same
>    compact header, no "Reconciliation note" / dated `border-left` aside survives, every acronym
      is expanded on first use (STE), and no theme stops at "went dark" without a reason.
>    Also check: the exec lead is ≤5 sentences and ≤120 words, leads with a decision ATTRIBUTE +
>    proof deal (not a cohort readout), with no citation marker and no Appendix pointer; a
>    RANKED-REASONS table (Table 1) precedes the Key Insights table at the exec and each region;
>    the Key Insights table has 4–5 ARR-ordered `PASS` rows and every `Causal mechanism + proof
>    deals` cell is plain sentences (no `→`, no clause-joining `;`) naming the sub-attribute, the
>    buyer change and the outcome with 3 proof deals (NOT a channel, segment,
>    list, or lever); where a theme is a top row at two levels the LOWER row
>    carries its own numbers, evidence and mechanism (repeating the portfolio row's numbers or
>    wording is a FAIL); no insight prints a region numerator over a portfolio denominator; and
>    no method or hedge word appears
>    outside the appendix ("Finance-clean", "all-sizes", "a-s", "basis", "denominator",
>    "verified quotes", "below the floor", "open-data-request", "unsourced", "lower bound",
>    "counter-hypothesis", "sample", "picklist", "methodology", "re-paper", "modelled",
>    "modeled", "tested and rejected", "tested and ruled out", "falsified").
>    **Then convert to PDF per `reference/convert_reports.py` BEFORE the audit and count the
>    PDF pages. The report is ≤10 PDF pages with the appendix ≤2 — never count `.sheet` divs
>    (`.sheet` has `min-height` + `overflow: visible`, so one div can print as three pages).
>    Over 10 PDF pages: cut content to the companion appendix file and re-render. Hand the
>    auditor the PDF path with the HTML.**
>
> **Report the RENDERED PDF page count, never the `.sheet` count.** You MUST render the PDF
> (`reference/convert_reports.py` or the headless-Chrome command) and read its page count before
> you claim page-conformance. "10 sheets" is NOT "10 pages" — `.sheet` flows, so 10 sheets often
> print as 14–16 pages. Claiming pass on the sheet count is a defect; the last cold run shipped a
> 16-page lose report that self-reported "10 sheets, pass". If the PDF is over 10 pages, move
> content (the summary matrix, extra Voice-of-Customer blocks, detailed action steps, the
> glossary) to the companion appendix file and re-render until the PDF is ≤10 — do not delete a
> sourced finding.
>
> **Digest to return (≤15 lines):** the RENDERED PDF page count (state you rendered it); total
> citations resolved (and 0 dangling confirmed); each insight's headline ARR next to its
> coded-attribute floor (flag any where headline > floor); any headline that would not reconcile
> to the spine (flag, do not paper over); unfilled gaps carried from fragments; `{PATH}` and the
> PDF path.

---

## Template 10 — Coherence harmonizer (one Opus pass across BOTH reports, run LAST)

Runs once, after both reports are assembled. Fill `{WIN_REPORT}`, `{LOSE_REPORT}`, `{SPINE}`,
and `{PATH}` (a short change-log file, e.g. `{OUT}/harmonize-log.md`).

> [PASTE SHARED PREAMBLE — you may edit the reports in place for voice and number consistency;
> you may NOT introduce any figure or claim not already sourced in a research file.]
>
> **Role: coherence harmonizer. Read the full `{WIN_REPORT}` and `{LOSE_REPORT}` end to end and
> make them read as ONE voice with mutually consistent numbers. This is judged by what you
> actually did in this transcript — the reasoning and edits visible here — NOT by file mtimes.
> A file that was merely re-saved is not harmonized. Show your work.**
>
> Do all of these and log each change to `{PATH}` with a before→after and the reason:
> 1. **Cross-report number consistency.** Any figure that appears in both reports (total in-scope
>    deals, ARR, a region's win rate, a named-deal ARR, a competitor count) MUST be identical and
>    MUST match `{SPINE}`. Where an earlier draft showed two conflicting values, keep both ONLY
>    if the sources genuinely conflict (then show both, label them, never average) — otherwise
>    reconcile to the higher-tier source and fix every instance.
> 2. **One voice, in Simplified Technical English.** Uniform yk-voice throughout, held to the
>    ASD-STE100 STE standard (`reference/STE-STYLE-GUIDE.md`): plain English, one idea per
>    sentence, under 30 words, active voice, every acronym expanded on first use, one term per
>    concept, no hype, no undefined jargon, no filler, no strategy editorializing. Run the
>    STE-STYLE-GUIDE ship gate over both reports and fix every miss in place — a run-on, a
>    passive-voice sentence, an unexpanded acronym, or an alternating term for one concept is a
>    defect to correct here. Kill hedging drift — the same finding must be stated with the same
>    confidence in both reports (don't call APAC's 0-of-72 "phantom competition" in one and
>    "possible miscoding" in the other). But do NOT over-hedge a well-sourced finding into mush.
> 3. **Shared framing + body-sausage sweep.** The coverage caveat, the competitor-field
>    lower-bound disclaimer, and the shipped-vs-planned convention must be stated consistently
>    across both reports — AND they live in the Appendix, not the body. As you harmonize, sweep
>    both bodies and MOVE any basis/method/how-to-read annotation sentence out of the exec and
>    region pages into the Appendix (basis defs, amendment mechanics, modelled-ARR explanation,
>    "field blank so anecdotal / lower bound" preambles, matrix/table how-to-read legends,
>    reconciliation caveats, the LOSE method-and-its-limits paragraph). The body keeps
>    single-basis Finance-clean numbers, one-word labels, findings, and NOTHING else — there is
>    no allowed Appendix pointer and no allowed basis pair. Move every all-sizes counterpart out
>    of the body into the ONE appendix comparison table: the body publishes the Finance-clean
>    figure alone. This is a scored FAIL in
>    the rubric (Dim 6) and an auditor check (Template 11 #4b) — fix it here so it never ships.
> 4. **Verb precision and survivors' claims.** "aligned to" ≠ "certified to"; cut exclusivity
>    claims; "the larger quantified exposure in available evidence," not "loses more money."
> 5. **Citations still resolve** after any edit — re-check no dangling numbers, appendix intact.
>
> **Digest to return (≤15 lines):** count of number-consistency fixes and the specific figures
> reconciled; count of voice/hedging edits; any contradiction you could NOT resolve (flag it,
> do not hide it); confirmation citations still resolve in both; `{PATH}`.

---

## Template 11 — Independent report auditor (MANDATORY; a DIFFERENT agent from the writer/assembler)

Runs after each report is assembled AND rendered to PDF, before anyone claims the report done.
Hand it the PDF path with the HTML — it counts PDF pages, never `.sheet` divs.
The writer never signs off on its own work. Fill `{REPORT}` (the assembled HTML), `{SPINE}` (the
Finance spine file), and `{RESEARCH}` (the mining/finance research dir). Model `opus`.

> [PASTE SHARED PREAMBLE — you VERIFY; you do not write prose. Assume claims are wrong until
> found in the spine or a research file. Report defects with file:line evidence; do not fix.]
>
> **Role: independent auditor of `{REPORT}`. You did NOT write it. Read the rendered file end to
> end and check it against `{SPINE}` and `{RESEARCH}`. Return a PASS/FAIL list, most severe first,
> each with file:line and the source it should match.**
>
> Check, and FAIL on any miss:
> 1. **Numbers reconcile to the spine.** Every headline (portfolio and per-region wins, losses,
>    win rate, ARR, ASP) matches `{SPINE}` exactly. **Segment counts SUM to their region total and
>    the regions SUM to the portfolio** — compute the sums yourself. A mismatch means a stale
>    spine survived a copy (the Aug 2026 defect: 755/379/197/179 from an old 4,422-row spine).
> 2. **The LEAD paragraph** — it is **≤5 sentences and ≤120 words**, and its sentence 1 matches
>    `KEY-INSIGHTS.md` §1 in substance. It opens with the strongest driver and continues with
>    ranked drivers #2 and #3. One why-sentence followed by three caveat
>    sentences is a FAIL: that is a
>    caveat dump moved down one line. A fourth driver, a refutation, or a nuance in this
>    paragraph is a FAIL. A citation marker, a method word, or an Appendix pointer anywhere in
>    this paragraph is a FAIL. Basis/method belongs in the Appendix.
> 2b. **Two tables per section, in order.** A RANKED-REASONS table (Table 1: `Rank | Root cause |
>    Share of coded {won|lost} deals | {Won|Lost} ARR`, own-side only, descending by ARR, max 6
>    rows) comes BEFORE the Key Insights table at the exec and at each region and each
>    distinct-mix segment. Table 1 and Table 2 rows describe the same root causes in the same rank
>    order. The Key Insights table (Table 2) exists, has 4–5 rows in descending order of ARR (or of
>    the named fallback rung: pipeline ARR → win rate × ASP → win rate), and every row traces to
>    `KEY-INSIGHTS.md` §2. Minimum 4 rows unless fewer than 4 `PASS` clusters exist (then stated in
>    one sentence). **No demoted theme is promoted into it.** A ranking by record count
>    alone is a FAIL.
> 2c. **Every region sheet carries its own RANKED-REASONS table then its insight block of 3–4 rows
>    (up to 5)**, traced to `INSIGHTS-<region>.md`, in descending ARR order; minimum 3 unless fewer
>    than 3 `PASS` clusters exist for that region.
> 2d. **Causal mechanism.** For every Key Insights row, every region top-three row, AND every
>    region SEGMENT-nest row (Ent/MM/SMB), open its attribute-cluster row and its ledger evidence.
>    FAIL the report if any row lacks a decision attribute, a within-cohort win/loss contrast,
>    three named proof deals, one contradictory case, or a complete causal chain (`attribute →
>    buyer change → outcome`). FAIL any row that ends at a channel, segment, list, gate, package,
>    price, team, or other controlled object — "referral", "target list", "expansion", "installed
>    base", "qualification", "coverage", "new logo", "budget", "brand strength", "the customer
>    went quiet". A segment-nest cell with no PASS attribute gets ONE sentence, not a ranked row —
>    flag any segment row that ranks a cohort readout. Confirm each named proof deal actually
>    supports the stated attribute, and that Finance supplies only the size, not the unobserved
>    cause. Run this analytical check BEFORE the page, markup, citation and language checks — a
>    conformance pass cannot override an analytical fail.
> 2d-i. **Sizing floor.** For every published insight, compare its headline ARR to the
>    coded-attribute floor (the ARR of `attribute_state = PRESENT` ledger rows for that
>    attribute). FAIL any insight whose published ARR exceeds its floor — a mechanism proven on
>    $703K of deals may NOT be sized to a $2.67M cohort. A cohort context figure is allowed only
>    when labelled separately ("broader cohort $X, not all attribute-driven"), never as the
>    insight's headline number.
> 2d-ii. **No fusion, no ranked UNKNOWN.** FAIL any insight that fuses distinct attributes into
>    one compound cause unless the SAME deals carry every part (check the ledger). FAIL any
>    ownership/outcome bucket presented as a decision attribute ("Acme loses to itself",
>    "stalled expansion", "never engaged"). FAIL any Key Insights row or region top-three row
>    whose cluster status is UNKNOWN or DESCRIPTIVE — those belong in the demoted list / Open Data
>    Requests, never in a ranked table.
> 2e. **Duplication — the two-level test.** Where a theme is a top row at two levels, the
>    lower-level row MUST carry evidence, numbers and a root cause the higher-level row does not.
>    A region row that repeats the portfolio row's numbers or its root-cause wording is a FAIL.
>    A region row that sizes the same theme with that region's own numbers and adds a
>    region-specific mechanism is CORRECT and is not a duplicate — do not flag it.
> 2e2. **Population integrity.** No insight prints a region numerator over a portfolio
>    denominator. Open the source file behind every Key Insights row and check the population it
>    scopes; a portfolio row sized on one region's deals is a FAIL. Every qualifier the source
>    attaches to the figure ("$X is a floor") must survive into the report.
> 2f. **No method or hedge word outside the appendix.** List every hit with file:line as a FAIL.
>    Search list: "Finance-clean", "all-sizes", "a-s", "basis", "denominator", "verified quotes",
>    "below the floor", "open-data-request", "unsourced", "lower bound", "counter-hypothesis",
>    "sample", "picklist", "methodology", "re-paper", "modelled", "modeled", "tested and
>    rejected", "tested and ruled out", "falsified". Reading real estate includes body prose,
>    tables, table headers, quote headers, stat-tile labels and the exec lead.
> 2g. **Length — count PDF PAGES, never `.sheet` divs.** The PDF is rendered before you run;
>    if you were not given one, render it (`reference/convert_reports.py`) before answering.
>    `.sheet` has `min-height` and `overflow: visible`, so a sheet div is NOT a page and a report
>    can pass a 10-sheet check while printing 16 pages. The report is 10 PDF pages or fewer and
>    the appendix is 2 or fewer. More than 10 is a FAIL: name the sheets to cut. **Do NOT fail a
>    sheet for word count alone — ~650 words is a guide and the rendered page is the gate. The
>    [LOSE] Actions sheet (~750) and [LOSE] appendix page 2 (~710) have stated higher
>    allowances.** Flag an over-guide sheet as non-blocking only if it still renders as one page.
>    FAIL a page-1 sheet that carries a themes table or a competitor
>    table (page 1 holds only the tiles, the lead, the Key Insights table and the matrix).
> 2h. **[LOSE] Controllability.** Every lost deal sits in exactly one outcome class; each class
>    is marked controllable or not controllable; the controllable share of lost ARR is a stat
>    tile; each region sheet carries its own controllable share; the assignment rule is an
>    appendix table. A class that fuses correct exits with unknowns is a FAIL.
>    **One rule across all regions.** Every region's class rows and controllable share must be
>    computed on the SAME reconciled portfolio assignment rule. Two regions publishing on two
>    different rules inside one report is a FAIL, whichever rule each picked — as is any region
>    share that contradicts the class table printed above it on the same sheet. The only
>    exception: a region that proves recomputation impossible by naming the missing roster
>    field, labels its figure inline as a different rule, and has that rule as its own row in
>    the appendix assignment-rule table. Check the rosters yourself before accepting the claim.
> 2i. **Outlier deep-dives are conditional.** A deep-dive whose mechanisms are already printed in
>    that region's top-three insight block is a FAIL for duplication — it should have been
>    absorbed into the insight as two sentences naming the cell and its rate. A deep-dive that is
>    ABSENT because the insight already carries the mechanism is a PASS: record "outlier absorbed
>    into insight N".
> 3. **Competitor tables** — each (every region + every segment that names a rival) has
>    3-5 competitors, follows its themes table, and carries the `Confirmed named cases (count)`
>    column. **A percentage on a small named sample is a FAIL.** The slice's rate appears ONCE,
>    above the table, matches the spine, and is NOT repeated down a column.
>    **[WIN REPORT] A win-side competitor table introduced by a loss-side rate is a FAIL** —
>    "Chose Competitor" exists only on lost records, so it cannot carry a win-side claim. The win
>    report states the competitive share of WINS from won-deal notes, or prints the counts with
>    no rate and files an Open Data Request.
> 4. **No boxes** — zero `.callout`, zero disclaimer/`how to read`/method `.note`, zero
>    `Reconciliation note` / dated `border-left` aside. Every why is prose.
> 4b. **No sausage-making anywhere in the body (scan EVERY sheet, not just the exec).** FAIL if
>    any basis/method/how-to-read annotation SENTENCE appears outside the Appendix: a
>    basis-definition sentence ("Finance-clean excludes sub-$5K amendments…"), amendment-filter
>    mechanics ("removes 642 of 1,431 wins because…"), a modelled-ARR explanation ("ARR is
>    modelled from ASP times count"), a competitor-field/anecdotal preamble ("the field is blank
>    on 99.96%, so names are anecdotal / a lower bound"; "read the two columns together"), a
>    matrix/table how-to-read legend ("each cell reads clean W/L with all-sizes in parens"; "the
>    percentages do not sum to 100%"), a reason-code-reliability lecture, a reconciliation/
>    denominator caveat ("on an all-record basis"; "the two views disagree by $X"), or the LOSE
>    method-and-its-limits paragraph in the exec. Single-basis Finance-clean NUMBERS and one-word
>    labels ("not booked revenue") are fine — but "(modelled)" on a direct sum is itself a FAIL
>    (check 2f). The banned things here are the explanatory SENTENCE and the
>    basis PAIR. **No Appendix pointer is allowed anywhere, including at the end of the exec
>    lead.** FAIL any all-sizes counterpart printed in the body — in a stat tile `.sub`, a matrix
>    cell, a region stat band, a table cell or prose: the body carries the Finance-clean figure
>    alone and the all-sizes comparison lives in ONE appendix table. List every offender with its sheet.
> 5. **Citations** — every `cite">N` resolves to exactly one Sources entry; numbering continuous;
>    no self-citation; the Sources list names the finance spine and the competitor mining file.
>    **Markup check (recurring defect, seen in two consecutive cold runs):** run
>    `grep -c 'span class="cite"' <report>.html` on BOTH reports; the count must be **0**. Only
>    `<sup class="cite">N</sup>` is styled by `report.css` — a `span.cite` marker renders as
>    full-size body text and stops reading as a citation. Any hit is a FAIL with file:line.
> 5b. **Population matching** — for every published ratio, "X wins against Y losses" pair, or
>    win/loss-rate comparison, state the ONE filter chain (period, region, deal type,
>    source/channel, segment, stage, reason code) and confirm BOTH sides were counted under it.
>    Mixing populations is a FAIL even when each side is separately correct.
> 6. **Source policy** — every product NUMBER traces to a Finance/Tableau/SFDC/Gainsight cell;
>    every negative product JUDGMENT quotes a first-hand customer. Flag any ungrounded knock.
> 7. **STE / ASD-STE100** — flag run-ons (>30 words), passive voice, acronyms not expanded on
>    first use, metaphor, idiom, rhetorical inversion, and any banned insider term ("re-paper",
>    "load-bearing", "record-bound", "the assembler", "CRIS", "name-flagged", "no-bid",
>    "contested-loss test", "3-quote floor"). **Grep the rendered report for `→`, `&rarr;`, and a
>    clause-joining `; ` inside table cells and body prose; FAIL on any hit.** The report output
>    carries plain sentences only — the `context → attribute → intervention → change → outcome`
>    notation is an analyst tool and must never appear in the report.
> 8. **Quote blocks** — 15 or fewer report-wide; no quote printed twice; no verification count or
>    sufficiency judgment in any header ("(5 verified)", "below the 3-quote floor"); every
>    Acme-authored quote or Salesforce close note labelled "Deal evidence", not customer
>    voice.
> 9. **Actions** — 5 rows or fewer, descending ARR at stake, each carrying an owner, an ARR
>    figure and a 30-day first step, and each acting on a bedrock root cause. FAIL any row that
>    restates its finding, and FAIL the section if it says "it does not judge strategy".
>    **FAIL any `First step in 30 days` that does not name a counted population and the file,
>    report table or system it comes from** — "Extract every director who sits on a board we
>    already run" names no source and no count; "Extract the 196 accounts behind insight 2" is
>    correct. **FAIL any action that changes a channel or segment mix whose `Because` cell gives
>    only the two win rates and no expected ARR per opportunity for both sides.**
> 10. **The three analytical obligations** (SKILL.md STEP 3b–3d). FAIL if absent with no reason
>    given: (a) every rate-based claim states whether it also holds in money and in new
>    customers, and any tension between two published findings is named; (b) expected ARR per
>    opportunity wherever an action moves volume between channels or segments; (c) [LOSE] the
>    controllable share of the loss book in dollars and as a share. Also check that the Open Data
>    Requests cover the gating unknown behind each Key Insights row.
>
> **Digest to return (≤20 lines):** a PASS/FAIL line per check above; for each FAIL, the
> file:line and the spine/research value it should be; the sum-check arithmetic you ran; a final
> verdict (SHIP / FIX-AND-RE-AUDIT). Never return SHIP with an open FAIL.

## Template 12 — Per-competitor head-to-head win-rate audit (ONE competitor per agent)

Dispatch one per TOP rival when a head-to-head win rate is a deliverable. Do NOT hand five
rivals to one agent — it under-mines each (that is how a real run reported Board Intelligence
2W/3L when the audited truth was 7W/11L). Fill `{RIVAL}`, its `{NAME_VARIANTS}`, and `{PATH}`
(e.g. `{OUT}/research/audit/board-intelligence-audit.md`).

> [PASTE SHARED PREAMBLE]
>
> **Role: independent win/loss auditor for ONE competitor — {RIVAL}. Find EVERY 2026 closed
> BLC opportunity that names {RIVAL}, label each Won or Lost, and report the win/loss RATIO.
> Being exhaustive on records is the whole job — a missed loss (or missed win) is the failure.**
>
> ### Method — count first, quote second (the five banned mistakes; see SKILL.md STEP 2)
> 1. **No quote-gating.** The unit is the RECORD. Count a closed opp whose note names {RIVAL}
>    even with no customer quote. Overlay quotes AFTER, only where they exist.
> 2. **Free text, not the structured field.** The SFDC competitor field is ~0.3% populated.
>    Run `glean search -d salescloud "{RIVAL}" --page-size 100 --output text` for EVERY variant
>    in {NAME_VARIANTS}, PAGE TO THE END, and pull full records
>    (`glean documents get <id> --includeFields DOCUMENT_CONTENT`) to confirm stage + that
>    {RIVAL} is genuinely in the deal (not a stray mention).
> 3. **Mine BOTH sides.** Losses AND wins — takeaway wins are titled "{RIVAL} Steal / Takeaway".
> 4. **Include renewal-churn losses** (a customer leaving TO {RIVAL} is a separate Renewal /
>    Cancelled opp with a companion Closed-Lost record).
> 5. **All product lines.** Search {RIVAL} across BLC AND BoardEffect/adjacent lines; some rivals
>    (OnBoard, BoardPro) fight almost entirely off the BLC line. State the line split.
> Cross-check the CSV spine `{SPINE_CSV}`; keep Glean-only records the CSV misses, note the source.
>
> ### False-positive scrubs — verify each by reading the note
> Our own "Boards Pro" SKU ≠ competitor BoardPro; Dutch "… B.V." ≠ BoardVantage; "onboarding" ≠
> OnBoard; "convention" ≠ Convene; "additional director license" ≠ Director's Desk; "im Board" ≠
> I'mBoard; "friend at {RIVAL}" ≠ a competitive deal.
>
> ### What to produce (write `{PATH}` EARLY, then keep appending — do not hold the list in memory)
> - **Headline:** `Won X / Lost Y = Z% win rate` (all types) + the new-logo split
>   (`OPP_TYPE = New`), raw counts shown beside every rate.
> - **Full auditable deal table:** account | Won/Lost | New/Upsell | region | ARR | where the
>   name was found (name field / competitor field / close note) | one-line evidence snippet.
> - **Reconciliation line:** count via Glean, count in CSV, net after dedupe, and how it compares
>   to any prior count (explain the gap you found).
> - **Confidence + low-confidence deals listed separately.**
> - **Label the rate a FLOOR, biased upward** (a rep had to type the name; incumbent losses are
>   under-named, so the true rate is lower). Never present it as a clean CRM rate.
>
> **Return (≤6 lines):** total W/L, win rate, new-logo split, and the count reconciliation vs any
> prior number.
