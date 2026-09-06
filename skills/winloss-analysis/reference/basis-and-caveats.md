<!-- ABOUTME: Teaches THE BASIS RULE for win/loss analysis — the dual-basis filter contract,
ABOUTME: the mandatory-caveats checklist, and the number-authority hierarchy with a correction log.
ABOUTME: Reusable method for ANY period; the July 2026 numbers appear only as worked illustrations.
ABOUTME: Read this BEFORE computing any rate/count/ASP or drafting any headline figure.
ABOUTME: Companion to scope-and-segment.md; this file owns figure integrity, that one owns segmentation. -->

# The Basis Rule, Mandatory Caveats, and Number Authority

The single biggest thing this skill was missing: **a rate has no meaning without its basis
label.** Everything below is reusable method. The numbers in *italics* are July 2026
illustrations — do NOT copy them forward; recompute for your period.

---

## 1. The dual-basis rule

Every rate, count, and ASP you publish MUST name the filter chain that produced it, and MUST
show BOTH of these two bases:

- **Finance-clean (PRIMARY — the headline everywhere):** exclude `Duplicate Opportunity`
  reason rows AND rows flagged as a small-deal / sub-threshold amendment
  (July: `< $5K Amendment`).
- **All-sizes (the COMPARISON basis — computed every run, published only in the ONE appendix
  comparison table, never paired with the headline in the body):** exclude only
  `Duplicate Opportunity`.

**Rules, non-negotiable:**
- Never publish a rate without its basis label.
- Never average the two bases. Never blend them into one number.
- Compute both. Publish the Finance-clean figure ALONE in the report body; the all-sizes
  counterpart goes in ONE appendix comparison table. Never average the two, and never mix
  bases inside a single rate.

### Why it matters (July as illustration)

The small-deal amendment filter is not cosmetic. In July it removed *8% of losses but 41% of
wins* — because *62 of the 150 all-sizes "wins" were sub-$5K contract amendments to existing
customers* (all Upsell/Cross-Sell, *ARR $89–$4,845, $101,237 total*). Consequences:
- Raw (all-sizes) win rate was inflated *~8 points* (*28.6% all-sizes vs 20.4% Finance-clean*).
- The real story only appears on the clean basis: the win side is **installed-base farming,
  not conquest.** On the inflated basis that story is invisible.

### Finding YOUR period's filter

The amendment/small-deal filter is period- and workbook-specific. It lives in a **control
cell** in the Finance workbook (July's was `F8 = 'Not <$5K Amendment'`). You MUST:
1. Open the workbook and FIND the equivalent filter cell for your period — the threshold and
   label may differ ($5K, a different amount, a different flag name).
2. CONFIRM the filter and its current status with Finance.
3. If the filter's status is ambiguous (present but not clearly applied, or you can't tell
   which rows it drops), **file an open-data-request** and treat the figure as provisional
   until Finance answers. Do not guess.

---

## 2. Mandatory-caveats checklist

State each prominently, once per report. VERIFY each per run — several are measured values,
not constants. (This is the reusable, period-agnostic version — do not carry July's specific
figures forward.)

- [ ] **Competitor-name field population rate — MEASURE IT EVERY RUN.** Compute the actual
      fill rate of the competitor field for this period's losses. Do NOT assume a prior
      run's number (the old skill wrongly claimed "~3%"; July measured **0%** — 434/434
      losses `No SFDC Data`). State the measured rate, and state that **every** named-
      competitor count is therefore a **lower bound**, sourced to free-text / transcript,
      and labelled as such — not from structured Finance data.
- [ ] **Lost ARR is face-value opportunity ARR — label it "not booked revenue", never
      "modelled".** Never write "ARR lost" or "ARR at risk" either. The portfolio figure is a
      direct `REPORTING_ARR` sum over the lost records, and calling a sum a model invites the
      reader to discount a correct number; state in the appendix that it is summed from N deal
      records. Do not present per-deal ARR as a negotiated price — the per-deal values are often
      list-price defaults (July: only *42 distinct values across 72 rows*, one value repeating
      *11 times*), and that is a per-deal precision caveat for the appendix, not a licence to
      call the total modelled. Use "modelled" ONLY where a figure is genuinely derived rather
      than summed, and name the derivation on the same line.
- [ ] **Retention vs new-business are different populations, periods, and measures.** Say
      "the larger quantified exposure in available evidence" — never "loses more money."
- [ ] **Reason codes are wrong in BOTH directions.** The picklist over-attributes to
      competitors where none existed AND hides real competitive losses under "no interest."
      Verify record-level miscodings; state the picklist is unreliable both ways.
- [ ] **Shipped vs planned for every capability, with GA dates.** Distinguish shipped from
      roadmap; note prior-communicated dates that changed; never conflate two differently-
      named products (July: AI Boards GA vs the separate AI Board Member product).
- [ ] **Verb precision.** ISO/IEC 42001 is "aligned to," never "certified to." Cite the exact
      edition of any standard (e.g. ISO 27001 :2013 vs later). State FedRAMP status precisely.
- [ ] **Cut every exclusivity claim.** No "the only platform that…" survives as fact unless
      independently evidenced. Strip unevidenced assertions.
- [ ] **MOR / deck figures never supersede Finance.** Where a deck and Finance disagree, show
      BOTH and say Finance wins (July worked example: *MOR's $1,729K = Finance spine
      $1,714,798 + $14,218 of out-of-scope MDO* — a scope bug, not a real difference).
- [ ] **Flag numeric coincidences as coincidences.** If a rigorously re-derived figure happens
      to match a prior report's number reached by a different route on a different population,
      say it is a coincidence, not a vindication.

---

## 2.5. Source rule for PRODUCT claims (hard rule)

A **product claim** = any statement about what the product does, ships, lacks, wins on, loses
on, its adoption, retention, attrition, quality, or roadmap. Two tests apply, by claim type.
**The test is GROUNDING, not internal-vs-external.**

**A. A quantitative product NUMBER** — a win rate, retention/churn/attrition rate, adoption
count, trial-conversion rate, ARR figure — is PUBLISHABLE when it traces to a data cell in a
grounded system, no matter which internal dashboard or report surfaced it:
- Finance / FP&A workbook (sheet + cell),
- Tableau or another Finance/analytics dashboard (verify the axis),
- Salesforce (field or record),
- Gainsight (customer-success record).
These are grounded internal data. A retention or attrition number is fine here even though it
is "internal" — grounding, not internal-vs-external, is the test.

**B. A qualitative product JUDGMENT** — "thin", "not good enough", "the AI failed", "weak
value" — is PUBLISHABLE ONLY when a first-hand customer says it, quoted from a Gong customer
call (call-id + date) or a verbatim Salesforce record note (author + date). The customer's own
words are the only license for a negative product narrative.

**BANNED for BOTH types as the basis of the claim:** an internal Slack or Teams message,
internal opinion, "N internal sources say…", an internal enablement deck, an OKR slide's
editorial claim, a battlecard, or an analyst quote presented as customer voice. These may
point you WHERE to look; they never license a product claim on their own.

The trap (do NOT reproduce): "Three internal sources call governed AI 'table stakes'; the AI
Board Member feature shows 98% two-week attrition." The first half is banned internal opinion.
The second half is banned ONLY because it rests on an OKR/deck with no underlying data cell —
the identical 98% is publishable if you trace it to a Gainsight or Finance cell. Replace the
qualitative half with a customer's own words from a Gong call; ground the number in a data
cell, or drop it and file an open-data-request.

Do not manufacture a negative product mechanism to satisfy the depth gate. The root-cause
protocol (`root-cause-protocol.md` §4b) demands a controllable mechanism under every "silence"
loss, and the quality rubric scores depth. That pressure must NEVER be discharged by asserting
"thin value" or "our AI failed the trial" without a Gong or Salesforce first-hand source. No
grounded source ⇒ a numbered open-data-request. An ungrounded negative product narrative is a
truth defect, not depth.

**A product capability on some losses is disaggregated, not dropped.** When a grounded product
capability appears on both wins and losses, do NOT delete it from the win report. Subdivide it to
the separating sub-attribute and publish that, per `root-cause-protocol.md` §1 ("Disaggregate
before you demote"). This allowlist governs the SOURCE of a product claim; it does not license
dropping a real product win reason. AI is the one exception you must not overclaim: absent a
separating sub-attribute (risk-containment, not feature superiority), AI stays table stakes and is
reported as `DESCRIPTIVE` — the disaggregation rule never turns a wash into a product win.

---

## 3. Number authority + correction log

**Authority hierarchy (strict precedence — higher wins on any conflict):**

1. **The frozen verified-figure table** (the drafting spec's headline table) — this is the
   CONTRACT. It is verified against the Finance workbook and audited. Do not recompute,
   re-round, or "improve" its figures.
2. **Finance-audit MATCH / MISMATCH verdicts** — reconciliation output against the workbook.
3. **Research files** — everything else, lowest authority.

If a research file contradicts the verified-figure table, the TABLE wins — and you note the
discrepancy in the report's method note. Without a frozen table, every redraft silently
re-derives and re-breaks numbers.

**Correction log discipline.** Any figure that changes after the table is frozen gets a
dated CORRECTION LOG entry — old value, new value, reason, date. Worked example of the
discipline: the July *$185,940 → $200,940* fix was logged rather than silently swapped.
Never edit a frozen figure in place without a log entry.

---

## Copy-paste checklist

```
BASIS
[ ] Every rate/count/ASP names its filter chain
[ ] Finance-clean shown as PRIMARY headline (excl. Duplicate Opportunity + small-deal amendment)
[ ] All-sizes computed (excl. Duplicate Opportunity only) and published ONLY in the single
    appendix comparison table — never paired with a body figure
[ ] Never averaged the two bases; both are shown
[ ] Located THIS period's amendment/small-deal control cell in the workbook
[ ] Confirmed filter + status with Finance (open-data-request filed if ambiguous)

CAVEATS (state prominently, once each; VERIFY per run)
[ ] Competitor field population rate MEASURED this run; counts labelled lower-bound + sourced
[ ] Lost ARR called face-value opportunity ARR / "not booked revenue" (not "at risk", not
    "lost", NOT "modelled" — it is a direct sum)
[ ] Retention vs new-business framed as different populations ("larger quantified exposure")
[ ] Reason codes flagged unreliable in BOTH directions
[ ] Shipped-vs-planned + GA dates for every capability; no product conflation
[ ] Verb precision (ISO "aligned to", exact editions, precise FedRAMP status)
[ ] Exclusivity claims cut
[ ] MOR/deck vs Finance: both shown, Finance wins
[ ] Numeric coincidences flagged as coincidences
[ ] Product NUMBERS trace to a Finance/Tableau/Salesforce/Gainsight cell; product JUDGMENTS ("thin/weak/failed") quote a first-hand customer (Gong/SFDC); no ungrounded knock, no internal-opinion basis

AUTHORITY
[ ] Verified-figure table treated as frozen contract (not recomputed)
[ ] Precedence: verified table > finance-audit MATCH/MISMATCH > research files
[ ] Any changed figure has a dated CORRECTION LOG entry
```
