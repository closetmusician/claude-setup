# Writing standard — Simplified Technical English (STE) for win/loss reports

<!-- ABOUTME: The mandatory prose standard for every win/loss report and every drafting
  agent. Adapted from ASD-STE100 for executive reporting. Apply BEFORE writing any prose,
  and use the checklist as a gate before shipping. -->

The reports must read in ASD-STE100 Simplified Technical English (STE). STE is a controlled
writing standard: one word means one thing, sentences stay short, and voice stays active.
Adapted here for an executive audience, not an aircraft manual. The goal the user set: no
jargon soup, no verbose run-ons, and every acronym explained.

## The nine rules (apply to every sentence)

1. **One idea per sentence.** If a sentence carries two ideas, split it. A sentence that
   needs a semicolon to hold two clauses together is usually two sentences.
2. **Keep sentences short.** Aim for 25 words or fewer. A sentence over 30 words is a
   defect — cut it.
3. **Active voice, present tense.** "The buyer declined the add-on," not "the add-on was
   declined by the buyer." "Acme wins where it already sits," not "wins have been
   driven by incumbency."
4. **Define every acronym on first use, then use it consistently.** "Board & Leadership
   Collaboration (BLC)". After the first use, use the short form. Never introduce an acronym
   you do not expand. Keep the Appendix glossary as the backstop.
5. **One term for one thing.** Pick a single word for each concept and repeat it. Do not
   alternate "upsell / expansion / cross-sell / land-and-expand / farming" for the same
   motion in one report. Choose the term, define it once, and reuse it.
6. **No jargon without a plain-English gloss in the same clause.** If a term is unavoidable
   (for example "gross dollar retention"), define it in one clause: "gross dollar retention
   — the share of recurring revenue kept across renewals". A smart 18-year-old must follow
   every sentence.
7. **Positive statements over negative.** "Most deals die before a real evaluation," not
   "most deals do not reach a real evaluation."
8. **Lead with the point, then the evidence.** State the finding, then the number and the
   source. Do not bury the conclusion at the end of a long clause.
9. **No filler.** Cut "it is important to note that", "generally speaking", "in terms of",
   "when it comes to". Cut hedges that carry no information ("somewhat", "arguably").

## Product tone — cautiously optimistic, credit the win the evidence supports

The overall tone on the product is **cautiously optimistic**. Report every uncomfortable
finding plainly (honesty is non-negotiable), but where the evidence supports a product
success, STATE IT AS A SUCCESS — do not hedge a well-sourced win into mush or bury it under
caveats.

- When a metric or a customer quote shows the product winning (a platform win-rate lift, a
  governed-AI security pull the customer paid attention to, a data-residency capability that
  closed a regulated deal, a competitor-sunset tailwind), lead the paragraph with the win,
  then attach the caveat in the same breath — not the reverse.
- Do NOT frame a win report as a debunking of its own thesis. "We win by installed-base
  farming" is a true finding, but it is a STRENGTH (durable expansion, low churn, director
  network), not a confession — state it as one.
- Keep the honest counter-evidence in (a declined AI add-on, a shipped-vs-planned gap, a
  thin net-new cell), but weight it: one clause of caveat per sentence of credit, not the
  other way round.
- The bar is calibrated, not cheerleading: no exclusivity claims, no unevidenced superiority,
  shipped-vs-planned always distinguished. Optimism is earned from the evidence, never
  invented.

## Banned constructions (search-and-destroy before shipping)

- **`→` arrows and clause-joining `;` semicolons are banned in ALL report output, including every
  table cell.** Write plain sentences instead. The `attribute → buyer change → outcome; proof: A,
  B, C` form is banned in body prose and in table cells alike. The analyst reasoning-chain notation
  (`context → attribute → intervention → change → outcome`) is an internal analyst tool only — it
  must never appear in report output.
- Run-on sentences joined by "; " or " — " that hold two full ideas.
- Nominalizations that hide the verb: "the driver of the win was expansion" → "expansion
  won the deal."
- Unexpanded acronyms anywhere in the body (ARR, ASP, GDR, SKU, SFDC, D1P, MSA, RFP, ENT,
  MM, SMB, DACH, UKI, ME&A — all must be expanded on first use).
- Stacked qualifiers: "the likely primary proximate root driver" → "the main reason".
- Insider shorthand with no gloss: "brakes-off", "why now", "land-and-expand", "phantom
  competition". Each is allowed ONCE you define it in plain words in the same sentence.

## Footnotes, notes, and commentary (a hard rule the user set)

- **No free-floating "reconciliation notes", "editor's notes", or dated asides in the body.**
  Weave the rationale, correction, or caveat directly into the sentence it belongs to. If a
  number changed after a later review, state the correct number and the
  one-clause reason in place — do not attach a note about the review.
- **No boxed asides of any kind.** No `.callout` "Why…"/"Root cause…"/"Method and its
  limits"/"The through-line" boxes, no disclaimer or "how to read" `.note`. Every explanation
  is prose. The narrative-only rule (`reference/report-structure.md`) is the authority.
- Superscript source citations stay (they resolve to the Sources page). Prose "notes" and
  `<p style=...>` asides do not.

## STE-compliant rewrite examples (from the July reports)

| Before (defect) | After (STE) |
|---|---|
| "Reconciliation note (Aug 2026). A deal-level Gong review of the AMER MM loss book (44 in-scope losses) plus an independent audit confirmed this 'route, don't cold-sell' reading…" | "A deal-by-deal review of all 44 losses confirms the pattern: cold outbound into the wrong accounts stalls before any real evaluation, and a rival is present in only about two deals." |
| "APAC's 42.9% all-sizes collapses to 26.7% clean because 31 of 54 raw wins are sub-$5K amendments." | "APAC looks strong at 42.9%, but 31 of its 54 raw wins are contract tweaks under $5,000. On the clean basis the region wins 26.7% — in line with the others." |
| "GovernAI / Minutes AI is the upgrade trigger and a sanctioned-AI security path vs shadow Copilot." | "Governed AI is the reason a customer starts the upgrade. It gives staff a safe, approved way to use AI, so they stop pasting board papers into unapproved tools like Copilot." |

## The gate (score before shipping — do not ship a report that fails)

- [ ] Every acronym is expanded on first use in the body.
- [ ] No sentence exceeds 30 words; the average is near 20.
- [ ] Every sentence is active voice unless the actor is genuinely unknown.
- [ ] One term per concept, used consistently across BOTH reports.
- [ ] No free-floating notes/reconciliation asides — all woven in.
- [ ] A non-specialist can read any paragraph once and understand it.
- [ ] Product tone is cautiously optimistic — evidence-supported wins stated as wins, not hedged into mush; caveats present but not dominant.
- [ ] No banned filler phrases remain.
- [ ] Grep the rendered report for `→`, `&rarr;`, and clause-joining `; ` inside table cells and body prose — zero hits. Any hit is a FAIL.
