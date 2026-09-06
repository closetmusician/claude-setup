# Relentless root-cause protocol — keep asking "why"

This is the core value of the whole skill. A win/loss report that stops at the Salesforce
reason picklist is worthless — the picklist is wrong in *both* directions (it blames
competitors who were never in the room, and it hides real competitive losses under "no
interest"). Every material finding must be chased until the "why" bottoms out in something
we control **and** is nailed to a hard source. Paste the relevant parts of this into every
research brief, and RUN the checklists below on every material cell.

---

## 1. The Iron Rule

**Never stop at a category, cohort, or Acme-controlled lever.** A root cause must show this
complete chain:

`context or trigger → decision attribute or friction → Acme intervention → buyer-behavior change → outcome`

The **decision attribute** is the required cause. It is an observable property of the buyer,
account, offer, product, process, competitor, or event. It must separate comparable wins from
losses. A broad capability that shows on BOTH wins and losses is not thereby a non-cause: you
MUST subdivide it until you find the separating sub-attribute, then publish that sub-attribute
(see "Disaggregate before you demote" below). Demotion to `DESCRIPTIVE` is allowed ONLY after a
genuine subdivision attempt finds no separating sub-attribute.

`Referral`, `target list`, `expansion`, `installed base`, `qualification`, `channel`, `new
logo`, `package`, `price`, and `team` are not root causes by themselves. They name exposure,
motion, or ownership. Ask which attribute inside that category changed the buyer's decision.

A publishable root cause must have all four forms of proof:

1. Decision evidence from a Gong transcript or a verbatim Salesforce note.
2. A within-cohort contrast that shows the attribute in wins and its absence, reversal, or
   defeat in comparable losses.
3. At least three named proof deals with source handles. If fewer than three exist, do not
   publish the claim as a headline root cause.
4. Finance evidence for the deal count, share, and annual recurring revenue.

**Size the insight to the coded-attribute FLOOR, never the cohort total.** The ARR you publish
for a causal insight is the ARR of the deals where the attribute is actually evidenced (the
`attribute_state = PRESENT` rows in the ledger), NOT the ARR of the whole channel/segment/motion
cohort it sits inside. Attaching "$2.67M" to a mechanism proven on five deals worth $703K is the
new shallowness: it swaps "referral is the cause" for "this attribute explains $2.67M", and both
are readouts. If the wider cohort matters, name it as a SEPARATE, labelled context figure
("attribute confirmed on $703K of won ARR; the broader referral cohort is $2.67M and is not all
attribute-driven") — never as the insight's headline ARR. The auditor fails any insight whose
published ARR exceeds its coded-attribute floor.

**One attribute per insight — do not fuse.** A compound cause ("value parity AND a platform
gate") may be published only if the SAME deals carry BOTH parts; if Empire State Realty proves
parity and Liberty Bank proves the platform gate, they are two attributes, not one, and each is
sized to its own proof deals. An ownership or outcome bucket ("Acme loses to itself" =
sibling-product routing + a failed trial + slow service; "stalled expansion"; "never engaged")
is NOT a decision attribute — it groups deals that need different interventions. Split it, or
mark it DESCRIPTIVE/UNKNOWN.

Controllability is a separate action test. It selects the intervention after the cause is
known. It does not prove the cause. Do NOT publish a clean portfolio "controllable share" that
counts a partly-controllable block as fully controllable, or that treats named-cause coverage as
a verified controllable share — say which part is controllable and which is an open question.

If the attribute, contrast, or proof deals are missing, classify the result as descriptive.
Put it in the appendix or create an Open Data Request. "We think it's price but couldn't
confirm" is an open data request, not a finding.

Finance remains the authority for counts, basis, and annual recurring revenue. It cannot prove
the decision attribute without record-level decision evidence.

### Disaggregate before you demote (win side and loss side)

A broad capability that appears on both wins and losses is not thereby a non-cause. Subdivide it
until you find the specific, observable sub-attribute that separates the comparable wins from the
comparable losses, and publish THAT. Only when a real subdivision attempt finds no separating
sub-attribute do you mark the candidate `DESCRIPTIVE`. Do NOT hard-drop a broad attribute
("product", "AI", "security", "referral") to `DESCRIPTIVE` merely because it shows on both sides —
that move dropped every product-driven win in a prior run, even though product is one of our top
win reasons.

Worked example: "product" appears on wins and losses. Subdivide it to "Acme One Platform sold
as ONE consolidated licence". Sold this way it wins at 46.4% against 10.4% for non-platform deals
(proof: Airwallex, Agenus). The one platform LOSS (AG2R La Mondiale) happened only when the same
platform was pitched as two separate products. So the separating sub-attribute is "sold as one
licence", not "product".

**AI honesty guardrail — do not overclaim.** AI is a genuine wash on the current evidence: it wins
bundled evaluations (ERGO, Chailey) and loses real deals (BDO $114.8K, PZ Cussons £35.7K).
Disaggregation does NOT license claiming AI as a net product win. The defensible AI sub-attribute
is risk-containment — a governed, approved place for board data — NOT feature superiority. If AI
cannot be subdivided into a separating sub-attribute, it stays `DESCRIPTIVE` and is reported as
table stakes. Honesty still governs.

---

## 2. The 7-step causal loop — run this on EVERY material finding

A material finding is any candidate headline, Key Insights row, region top-three row, theme
row, named deal you cite, or outlier conclusion (see §3). For each one:

- [ ] **(a) Define one comparable cohort.** Hold period, region, segment, motion, and basis
      constant. State which wins and losses are eligible.
- [ ] **(b) Read each eligible deal.** Read the Salesforce note, the opportunity stage history
      (where did it die?), and the available Gong transcript. Keep the opportunity ID attached.
      Do not summarize from the aggregate — open the individual records.
- [ ] **(c) Extract the decision attribute.** Write the smallest observable attribute that
      affected the decision. Do not write a channel, segment, list, or lever. ("A public-company
      transition inside six months", not "the target list".)
- [ ] **(d) Apply one text-to-attribute rule.** State which evidence qualifies a deal for the
      attribute. Apply the same rule to wins and losses. Capture the exact source handle
      (call-id, sheet/cell, note author + date).
- [ ] **(e) Contrast outcomes inside the cohort.** Count wins and losses with and without the
      attribute. Name at least one contradictory case — a deal where the attribute was present
      but the outcome did not follow, or the outcome occurred without the attribute.
- [ ] **(f) Write the causal chain.** Use `context or trigger → attribute or friction →
      intervention → buyer change → outcome`. Cite every link. The Acme-controlled lever is
      the intervention; it does not replace the attribute in the root-cause field.
- [ ] **(g) Quantify and test.** Give deal count, cohort share, annual recurring revenue, three
      named proof deals, and one tested alternative explanation. **Verify every named-deal ARR
      digit-by-digit against the Finance spine AT DRAFT TIME — not later at the audit gate.** Any
      cluster total is the sum of its named deals, re-added from the workbook, never carried from
      a prior deck or a research note. (This is the exact trap behind the July $185,940→$200,940
      fit-cluster correction: six deals were summed wrong and it survived to a published report.
      Re-sum at draft time and log any change in the correction log.) The tested alternative
      lives in the RESEARCH file only; the report publishes the surviving conclusion. "tested and
      rejected", "tested and ruled out", "falsified" and "counter-hypothesis" are banned from
      report body real estate.

Persist each deal-to-attribute row in the required deal ledger (`research/deal-ledger.csv`) as
you go — do not hold it only in context. Compaction destroys in-context state mid-analysis. Do
not aggregate into themes before the ledger exists.

---

## 3. Dig-deepest triggers — when to read EVERY deal in a cell

The normal single-cell win rate sits in a **15–30% band**. Dig every deal in a cell
whenever:

- [ ] The win/loss rate is an **OUTLIER** — well outside 15–30% (either abnormally high or
      abnormally low). AMER MM at **2%**, DACH at **3.8%**, APAC Enterprise at **53%** all
      demanded a deal-by-deal read.
- [ ] **The abnormally-low rule (state it explicitly):** any cell that is abnormally *low*
      — a near-zero win rate, or a "0 of N competitive losses", or "0W/41L" — read every
      single deal in it. Low outliers are where miscodings, no-bids, internal-product moves,
      and phantom competition hide. A zero is almost never real; it is usually a coding
      artifact you must expose.
- [ ] A single deal is a large share of the cell's ARR — read it; one miscoded whale can
      flip the whole cell's story.
- [ ] A "Chose Competitor" count exists at all — read each one; the competitor field is 0%
      populated, so every one of these is a free-text claim that may dissolve at record
      level.

---

## 4. The worked chains — reproduce these as templates

Each renders as: **picklist said X → record shows Y → mechanism Z (controllable) →
quantified → counter-hypothesis falsified.** These five are the gold standard; imitate the
shape.

### Chain A — AMER Mid-Market, the 2% outlier (coverage + packaging, NOT price)

- **Picklist said:** "Unresponsive / Postponed / No-Interest" on 71–72% of the cell.
- **Record shows:** three separate mechanisms once you read all 45 losses.
  1. 14 of 45 non-amendment "losses" (31%, ~$188K ARR) are accounts that **already run
     Acme Boards** — the logged opp was a failed cross-sell/renewal miscoded into BLC
     pipeline (Maine Employers' Mutual SFDC note: "Already a Acme Boards customer";
     Waystar every call is a renewal). So the true net-new denominator is ~31, not 45.
  2. The lone "Chose Competitor" (Dyne Therapeutics, $20K) is a Compliance-Training inquiry
     with zero board-portal intent — no competitor was ever chosen.
  3. Net-new dies at Discovery from thin pipeline: 30/45 (67%) outbound, 27/45 (60%) die at
     Discovery, **39/45 (87%) never had a package or SKU entered**. Lowest list price is
     $12K; these are one-admin shops with no fitted mid-market SKU.
- **Mechanism (controllable):** coverage + packaging gap. Its two dedicated MM territories
  went **0W/41L**; the one real win was closed by SMB Land; MM Outbound is **0W/41L
  worldwide**. The packaging ladder ($12K/$20K/$28K/$35K/$55K) is tiered on
  private-vs-public, **not size** — no tier is aimed at a mid-market company.
- **Quantified:** 1W/44L = 2% clean; 72% Unresponsive/No-Interest/Postponed; 68% die at
  Discovery.
- **Falsified counter-hypotheses (mandatory):** "MM fails differently on the loss side" —
  FALSIFIED (early-loss share 68.2% vs Enterprise 68.4% vs SMB 69.6%). "The short MM cycle
  medians prove weak demand" — FALSIFIED (those are *win* medians; MM losses actually run
  105–124 days, longer than SMB).
- **Verdict:** a go-to-market defect, not a product defeat. Note the Q1 AMS analysis already
  recommended a $6K–$10K SKU and the floor is still $12K.

### Chain B — DACH / Swisscom → Brainloop (internal competition + miscodings)

- **Picklist said:** DACH is Acme's competitive heartland — a wall of "Chose Competitor"
  losses; largest is Swisscom ($45,783).
- **Record shows:** Swisscom went to **Brainloop — a Acme-owned product** (SFDC: Swisscom
  ran an RFP for "both Brainloop and Acme" and chose the Brainloop Meeting Suite; one
  note even reads "Acme won the deal … of Acme Boards"). The $45,783 ARR is likely
  retained on the Brainloop line. Of ~15 headline "competitive" DACH losses, only ~2 name a
  real external rival. Plus verified miscodings feeding the same "picklist is wrong" root
  cause: **IG Markets $115,570** coded "Not Interested in Going Paperless" is actually a
  price loss to Board Intelligence (Gong: opp owner asking "is it BoardIntelligence you're
  currently using? … back to you, with the pricing"); **Vale $72,312** coded "Unresponsive"
  lost to a missing document re-assignment feature; **ABB $11,250** is a Risk/Audit RFI we
  withdrew from, misfiled as BLC.
- **Mechanism (controllable):** internal-product cannibalization (Brainloop) + reason-code
  unreliability. Report it plainly as internal competition, with the Salesforce citation;
  note it means DACH's competitive count **overstates** external pressure. Do NOT editorialise
  about strategy.
- **Quantified:** DACH 1W/25L = 3.8%; ~2 of ~15 "competitive" losses name a real outside
  vendor.
- **Falsified counter-hypotheses (mandatory):** "BoardWise is taking DACH" — FALSIFIED
  (BoardWise is never the confirmed winner of a single mined DACH deal; appears only paired
  with Sherpany in evaluation sets and internal collateral). "A single ME&A vendor is
  displacing us" — FALSIFIED (0 of 5 ME&A "Chose Competitor" losses is a genuine outside
  loss).
- **Genuine residual:** Sherpany in DACH on price (~50% cheaper) + Swiss data hosting +
  incumbency (CYP close note names all three). Real, but narrow.

### Chain C — APAC phantom competition (0 of 72)

- **Picklist said:** two "Chose Competitor" losses in APAC.
- **Record shows:** **both are disproven at record level.** Dah Sing Bank ($15,000, Hong
  Kong) was a Acme **no-bid** — we voluntarily withdrew over Hong Kong data-residency we
  couldn't meet (Gong call 3765064707847844668, AWS-Singapore cloud-only vs on-prem). Racing
  Victoria ($6,679) lost to a failed trial of **GovernAI — Acme's own AI product** (SFDC:
  "We didn't lose to a competitor but we did lose because GovernAI failed their
  evaluation"). Meanwhile the picklist *under*-states competition elsewhere: **SG Fleet**
  ($18,836, coded "No Interest/Need") is a failed displacement of incumbent Azeus Convene
  (Gong: "I've been using conveen daily for the past seven years at SG fleet").
- **Mechanism (controllable):** coverage/qualification failure + data-sovereignty gap for
  regulated buyers + internal-product involvement. The picklist is wrong in both directions.
- **Quantified:** real head-to-head competitive count = **0 of 72**.
- **Falsified counter-hypothesis (mandatory) — the stage-gating counter-test:** "APAC codes
  zero competitive losses because its deals die early, before a competitor shows up" —
  FALSIFIED. APAC's early-loss share (66.7%) is *lower* than AMER's (72.5%), yet it codes 0
  of 23 late-stage losses as competitive vs EMEA's 11 of 38. The zero is a coding artifact,
  not reality.

### Chain D — retention: BT "Legal Issue" is a price loss (a Finance-numbers dig)

Applies the same move to Finance's own retention numbers, not just new-business losses.

- **Picklist said:** BT churn −$304,924 coded "Legal Issue".
- **Record shows:** it's a **price loss** — Gong: "about a third of what we are paying
  today." Correcting BT and CCLA (same treatment) flips addressable churn from **32.3% to
  51.2%**.
- **Mechanism (controllable):** pricing. The reason code hid the single most controllable
  lever in the retention book.
- **Quantified:** addressable-churn share moves 32.3% → 51.2% on two corrected records.
- **Lesson:** run the loop on retention too. Reason codes are just as wrong there, and the
  numbers are usually bigger.

### Chain E — catching a fabricated statistic ("22.5% publishing zero board books")

The loop also catches *invented* stats, not just miscodes.

- **Claim in a prior deck:** "22.5% of Enterprise accounts publish zero board books."
- **Record shows:** there is no such statistic — the "22.5" is a **chart y-axis gridline in
  $M**, misread off a Tableau/dashboard chart as a percentage. Refute it explicitly in the
  report.
- **Lesson:** when a suspiciously clean stat has no traceable source cell, go find the chart
  it came from. A gridline is not a statistic. If you can't trace a number to a source-ladder
  tier (§5), it does not go in as fact.

---

## 4b. The silence rule — "went dark / no momentum" is never a root cause

A loss coded "Unresponsive", "Went dark", "No momentum", "Project Postponed", or
"No Interest/Need" tells you HOW the deal ended, not WHY. Treat every one as a hypothesis
to open, exactly like a picklist code. Dig it to the controllable reason underneath the
silence, quoted from a transcript or a record note. The July 2026 refine proved the silence
almost always hides one of these:

- **Thin value / weak "why now".** The upgrade adds too little to justify acting. AMER
  Mid-Market: the buyer already runs Copilot for minutes (Major Drilling, call
  1222637216212026575) or pipes board papers through Claude (Essent, 7328917630831038832),
  so the shipped board-facing AI is redundant. This is the root cause under most
  "unresponsive" expansion stalls.
- **Our own product failed a trial.** APAC: Acme's GovernAI failed a free evaluation —
  summaries too long and alarming (Racing Victoria), could not reliably extract the
  recommendation section (Powerlink, 4341042589493663660), unfit for finance-heavy packs
  (Vicinity). Coded "No Interest / Chose Competitor" but it was our AI, not a rival.
- **A feature the product does not ship.** Brisbane City Council wanted forward-planning /
  action-tracking, not a meeting portal; Energie AG needed Outlook/Teams sync + ID-Austria
  e-sign + native transcription.
- **A wrong-buyer / no-economic-buyer qualification miss.** Central States (enthusiastic
  junior admin, no budget authority); Adare (contact does not attend board meetings).
- **A legal / procurement / data-residency block we own.** Vale (10-month AI data-processing
  legal block + a board philosophy that rejects director-facing AI); Park'IN (Acme's own
  vendor-onboarding failure, NOT residency); Dah Sing (a no-bid over Hong Kong residency).
- **Genuine no-need at a micro account.** Croydon Shire compiles agendas in Word in five
  minutes and its councillors want printed copies — near-zero pain. This IS a valid
  coverage/qualification root cause, but only after you have ruled out a hidden product/price
  reason AND quantified it. State it explicitly; do not use it as a catch-all.

Rule: a theme row or a named deal that stops at "went dark / coverage failure" with no
reason under it is incomplete. If you genuinely cannot find the reason (no transcript, only
a picklist), say so and file an open-data-request — do not present the silence as the cause.

Grounding guard: the mechanisms above (thin value, our AI failed a trial, feature gap) are
CANDIDATES, not defaults. State one only with a Gong or Salesforce first-hand source behind
that exact deal. A negative product mechanism with no grounded source is a fabrication — file
an open-data-request instead (see `basis-and-caveats.md` §2.5). Depth pressure never licenses
an ungrounded knock.

## 5. Source-strength ladder

Rank every piece of evidence. A conclusion must rest on one of the **top three tiers**.

| Rank | Source | Weight |
|---|---|---|
| 1 (strongest) | **Gong verbatim** (with call-id + date) | Direct customer voice — beats everything |
| 2 | **Finance / FP&A workbook cell** (sheet + cell) | Audited number |
| 3 | **Tableau / dashboard metric** | Reportable, but verify you read the axis right (see Chain E) |
| 4 | **Salesforce record note** (verbatim, author + date) | Record-level truth about one deal |
| 5 (weakest) | **Picklist code** | A hypothesis to disprove — NEVER sufficient alone |

Rules:
- A finding backed only by tier 5 (picklist) is not a finding — it's an open data request.
- When two sources conflict, the higher tier wins; when Finance and a MOR deck disagree,
  Finance wins (say so, show both).
- Every figure in the report traces to a tier-1–4 source, cited inline. Anything you can't
  source gets **[need sources]** and a numbered open-data-request entry. Never invent a
  source; never cite a report as its own source.

The ladder ranks source STRENGTH. Separately, a PRODUCT claim is subject to the source
allowlist in `reference/basis-and-caveats.md` §2.5: it may cite ONLY Gong / Salesforce /
Gainsight / Tableau. Internal Slack/Teams/opinion/OKR is banned as the basis for a product
statement, even though it may sit at tier 4-5 for a non-product fact.

---

## 6. Done-check for the whole report

Before you call any region section done:

- [ ] Every outlier cell (§3) had every deal read.
- [ ] Every themes-table row states a **mechanism** (the "why"), not just the picklist label.
- [ ] Every mechanism is quantified (# deals, % of cell, ARR).
- [ ] Every material finding names at least one falsified counter-hypothesis.
- [ ] Every "Chose Competitor" claim was read at record level and either confirmed with a
      tier-1–4 source or exposed as a mislabel.
- [ ] Every conclusion rests on a tier-1–4 source; nothing rests on the picklist alone.
- [ ] Everything that couldn't bottom out is a numbered open-data-request, not a soft
      assertion in the body.

## 4c. Verify every representative name and quote against the spine (Aug 2026 annual run)

Drafting/assembler agents will invent plausible customer names and quotes to fill a
representative-customers cell or a Voice-of-Customer block. In the 2026 annual run the
assemblers produced fabricated quotes (a "Steve Madden" board quote, an "Atkore" sunset
quote, a "Knoa Pharma" no-learning-curve quote) and mis-segmented real accounts (Airwallex
labelled a referral when it is Marketing; Bookshop Topco and Nationwide placed in SMB when
they are Mid-Market and Strategic). The Codex reviewers caught these one per round, which
turned into many refinement loops.

Do this ONCE, before the audit, not reactively:
- Extract every named account from both reports (representative-customer cells, VoC attribs,
  highlight/lowlight bullets) and grep each against the Finance spine CSV. Any name not in
  the spine is either fabricated or out-of-period — remove it or flag it explicitly as
  out-of-window (never present it as an in-period example).
- For every name that IS in the spine, confirm its region AND segment match the cell it sits
  in. A Mid-Market account in an SMB table is a truth defect the reviewers will fail.
- Every quote must carry a call-id or a named Salesforce/Gainsight record. A quote with only
  a company name and no source handle is a fabrication risk — drop it rather than ship it.
- Build a verified name pool per region×segment from the spine up front (top-ARR won and
  lost per cell) and draw representative names only from that pool.
This single pre-audit sweep would have collapsed ~4 review rounds into one.
