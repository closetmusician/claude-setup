---
name: mor-prep
description: >
  Prepare the monthly Governance-BU / Boards (BLC) Monthly Operating Review from raw Finance +
  CRM data. Two parts: (A) a detailed, fully-cited HTML root-cause report on Bookings & GDR by
  geo and segment, and (B) the MOR deck's Boards section (exec summary + GDR/bookings slides).
  Use when asked to "prep the MOR", "build the MOR report", "why did bookings/GDR move this
  month", "root-cause the MOR numbers", or "refresh the MOR deck". The Finance model says WHAT
  moved; this skill's whole job is to prove WHY with 5-whys-deep, primary-source-backed root
  causes. NOT for one-off single-metric lookups (answer directly) or non-Governance BUs.
---

# mor-prep — Monthly Operating Review preparation (Boards / BLC)

Turns a month's Finance results workbook + CRM/Gong data into (A) a detailed HTML root-cause
report and (B) the MOR deck's Boards slides. The gold-standard output is
`reference/example-report.html` (July 2026). A regeneration on a new month's data must be
**semantically and structurally equivalent** to that exemplar.

## The one rule that matters most
**Be relentless about true root cause.** A stated reason ("price", "ROI", "no budget", "waiting
for AI", "unresponsive") is a SYMPTOM, never the answer. Keep asking WHY — at least 3 levels,
until the cause is **something we control** (product, packaging, GTM/roadmap messaging,
ICP/qualification, pricing model). **Every rung of every 5-whys chain is backed by a
primary-source quote with a locator** — a Gong call (`[gong <call-id> | speaker | date]`), an
FP&A/Finance workbook cell, a Tableau/Highbond view, a Salesforce field, or a Cancel-Details
email. No quote → it is an assertion, not a finding. Full method + tooling: `reference/root-cause.md`.

## STEP 0 — Ask upfront (one question, then proceed)
Ask via the AskUserQuestion tool which parts to run: **(A) report only · (B) slides only · (both)**.
**If no answer / ambiguous, default to BOTH.** Also confirm the period (close month) and the path
to the Finance results workbook. Ask nothing else you can determine from the data.

## STEP 1 — Establish the "WHAT" (the model), exactly
The Finance results workbook is the **system of record**. Recompute every headline from the
deal-level extracts and reconcile to the workbook **to the dollar** before explaining anything.
- Scope (hard filters): BLC / `Board & Leadership Collaboration` only; `REPORTING_REGION` ∈ {AMS,
  EMEA, APAC} — **exclude MDO**; the close month only (Q2/prior only as labelled context).
- Decompositions to carry through the whole report:
  **Bookings ≈ Pipeline created × Win/Conversion rate × ASP** and
  **GDR shortfall ≈ at-risk renewal pool × realised churn/downsell rate**.
- Win rate has two bases — Finance's **clean** basis (excludes `< $5K Amendment`) and **all-sizes**.
  Always label which; lead with clean. The gap is material, not noise.
- Reuse any prior-run findings/spine files before searching; re-date or discard out-of-period figures.

## STEP 2 — Prove the "WHY" (root cause) — the core of the skill
Fan out **parallel subagents (Opus)**, one per lane — Bookings × {AMER, EMEA, APAC} and GDR ×
{AMER, EMEA, APAC}, plus cross-cuts (the growth engine, the biggest decliner segments, the churn
drivers). Each lane: breadth-first theme count over the FULL population → then **stage-by-stage,
5-whys, primary-source-backed** root cause per `reference/root-cause.md`. Then **adversarially
verify** with the real Codex CLI (see `reference/root-cause.md` §Verify) — it will catch
symptom-level overreach; downgrade verdicts honestly (SUPPORTED → PARTIAL) rather than re-inflating.

## STEP 3 — Part A: the HTML report
Build from `templates/report-template.html` (annotated skeleton), matching
`reference/example-report.html` section-for-section. Link `templates/report.css` (copy it next to
the report). Then render a PDF with headless Chrome and **verify no clipping** — the `.sheet` pages
are fixed-height with `overflow:hidden`, so extract the PDF text layer and confirm each page's
bottom-most element is present. Tone + language: `reference/style-ste100.md`.

## STEP 4 — Part B: the MOR deck slides
Fill/refresh the Boards section (exec summary + GDR + bookings + quantitative + Q2 retrospective).
**Back up the .pptx first**, edit with python-pptx, verify it re-opens. Full slide map, edit method,
and the augment-vs-rewrite rule: `reference/slides.md`.

## Hard rules (non-negotiable)
1. **No hallucination.** Every number, %, name, quote, date comes from a retrieved doc or a CSV/cell
   you read. Cite `[Doc | datasource | YYYY-MM-DD | URL]` or `[CSP/RFL row | OPP_ID | field]`.
   Copy figures exactly — no rounding or "cleaning". Unsourced → mark `[need sources]`.
2. **Cautiously-optimistic, tempered tone.** Lead with what genuinely went well (target beats,
   strong segments); state risks factually without drama. No "sky is falling". `reference/style-ste100.md`.
3. **Plain English, ASD-STE100** for all prose an executive reads (esp. the deck exec summary):
   short active sentences, one idea each, common words. `reference/style-ste100.md`.
4. **Every figure in the report carries a `<sup class="cite">` superscript** resolving to the Sources
   appendix. Every root-cause claim carries a primary-source quote.
5. **Before touching the .pptx**: git-back-up the original (and use python-pptx locally — the
   registry PPT tools only take SharePoint URLs). `reference/slides.md`.
6. **Do not repeat this session's detours.** Run the `reference/traps.md` checklist before declaring done.

## Files
- `templates/report-template.html` — annotated structural skeleton (the unambiguous format)
- `templates/report.css` — the stylesheet (theme-lose)
- `reference/example-report.html` / `.pdf` — the gold-standard finished exemplar
- `reference/root-cause.md` — the 5-whys discipline, evidence tooling (Glean/Gong/FP&A/Tableau), Codex verify
- `reference/style-ste100.md` — cautiously-optimistic tone + ASD-STE100 rules with examples
- `reference/slides.md` — MOR slide map, python-pptx editing, augment-vs-rewrite
- `reference/traps.md` — the mistakes-to-avoid checklist (distilled from the build session)
