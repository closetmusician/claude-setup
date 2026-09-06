# Traps checklist — run before declaring done

Each line is a real mistake from the build session. Verify you did NOT make it.

## Root cause
- [ ] No root cause stops at a symptom ("price/ROI/no budget/waiting/unresponsive"). Every one is
      driven ≥3 WHYs to something we control.
- [ ] Every rung has a primary-source quote + locator (Gong id / workbook cell / Tableau / SFDC).
- [ ] You did NOT conclude "no Gong data" from a `gong mine` timeout — you used Glean `-d gong` →
      `gong transcript <id>`.
- [ ] Real Codex adversarial review ran; verdicts downgraded to PARTIAL where causation is not proven
      (do not re-inflate). A subagent did not "perform" the Codex review.
- [ ] Single-number segments split into their real sub-populations (e.g., new-logo funnel vs
      installed-base upgrade stall).

## Numbers / scope
- [ ] Deal-level recompute reconciles to the Finance workbook to the dollar, per region.
- [ ] MDO excluded from every AMS/EMEA/APAC total; period is the close month; Q2/prior only as
      labelled context, never blended into a month figure.
- [ ] Win rate labelled clean vs all-sizes everywhere it appears.
- [ ] **D1P (or any driver) headline checked for YTD-vs-month** — the "320 deals / $4.98M / 31.7%"
      figure was YTD, not July (July = 38 / $576K / 33.3%). State the basis in the same breath.
- [ ] A churn "example" is verified to have actually churned in the month, not a forward-risk renewal
      ("First Bank $156K" was a 2027 at-risk renewal, not a July loss).
- [ ] A named competitor is verified present in the period ("Sherpany" appeared in ZERO July Boards
      churn rows; it is a DACH threat). Fix mis-codes (BT "Legal Issue" → price/competitive RFP).
- [ ] ex-<account> GDR removes the account from numerator AND denominator (ex-BT = 94.66%, not 95.9%
      and not the 94.89% "fully-retained" counterfactual).
- [ ] Placeholder cells ("XXX", "[need source]", "XYZ") are filled from a real source or left flagged
      — never invented.

## Report / deck build
- [ ] Cautiously-optimistic tone; leads with the beat; no "sky is falling" vocabulary.
- [ ] Deck exec-summary prose is ASD-STE100 and the why leads each bullet (not a trailing parenthetical).
- [ ] No "How to Read This Report" page — caveats live in ONE footnoted sentence.
- [ ] Every report figure has a `<sup class="cite">` resolving to Sources.
- [ ] `.pptx` backed up before editing; deck re-opens cleanly after; deck agrees with the report.
- [ ] **PDF clip check**: `.sheet` is fixed-height `overflow:hidden`. After rendering, extract the
      PDF text layer and confirm each page's bottom-most element is present (clipped content is not
      painted, so it will be absent). Split or trim any page that clips.
- [ ] Page references use section names, not hard page numbers (they drift when pages are added/cut).

## Process
- [ ] Ask the ONE upfront question (parts A/B/both; period; workbook path), then proceed — do not
      over-interrogate.
- [ ] Fan out parallel Opus subagents per lane; do not serialise independent research.
- [ ] Reuse prior-run findings before searching Glean; re-date or discard out-of-period figures.
- [ ] Commit at checkpoints; on shared `main` with unrelated dirty files, commit locally, do not push.
