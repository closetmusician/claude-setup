# Root-cause method — relentless 5-whys, primary-source at every rung

The model tells you WHAT moved. This file is how you prove WHY. If a reviewer can say "that's a
symptom" or "where's the quote", you are not done.

## The discipline
1. **Start at the stated reason, never stop there.** "Price / ROI / no budget / waiting for AI /
   unresponsive / churned to a competitor" are what the customer *says*. Treat each as WHY #1.
2. **Ask WHY ≥3 times, until the answer is something we control** — product capability, packaging,
   pricing model, GTM/roadmap messaging, ICP/targeting, qualification, or a named execution gap.
   "The customer had no budget" is not actionable; "the shipped feature doesn't do the job the
   buyer values, so the uplift fails the value test" is.
3. **Every rung carries a primary-source quote with a locator.** Acceptable sources, in order of
   weight: **Gong transcript** `[gong <call-id> | speaker | date]`; **FP&A / Finance workbook** cell
   `[<sheet> row/col]`; **Tableau / Highbond** view; **Salesforce** field `[CSP/RFL row | OPP_ID |
   field]`; **Cancel-Details** email; Confluence/Slack thread. A picklist code alone is NOT a root
   cause — it is the label to be explained.
4. **Distinguish sub-populations.** A single segment number often hides two mechanisms (e.g. a
   new-logo funnel failure AND an installed-base upgrade stall). Split them and quantify each.
5. **State the falsification test and a calibrated verdict** — SUPPORTED / PARTIAL / REFUTED, a
   confidence, and the single strongest disconfirming fact you found. Prefer PARTIAL to overclaim.

## Worked examples (the bar to clear — from the July 2026 run)
- **Mid-Market −71% "ROI/no budget":** WHY no ROI → shipped GovernAI is admin-only *book*
  summarisation → WHY low value → boards value the **live Q&A discussion the tool does not
  capture**, admins already do minutes fast/with Copilot, and the interactive AI board member is not
  GA → **bedrock: product-market-fit-at-price gap** (+$15–35K uplift fails at a mid-market board).
  Proof: MEMIC *"the important part … is the questions and answers going back and forth live. But
  this is just based on the materials"* `[gong 3590847483910164781]`; Major Drilling *"I use Copilot
  now … not seeing how [AI minutes] saves much time"* `[gong 1222637216212026575]`.
- **Strategic −78% "waiting for AI":** WHY waiting → shipped GovernAI clears no new bar → WHY expect
  more soon → reps sell the AI *vision* (AI board member, Smart Search) as near-term and price the
  ~$25–35K interim upgrade as *pre-paying the roadmap* → **bedrock: self-inflicted GTM/roadmap-timing
  mismatch — no cost to waiting for the flagship (GA Q1 2027).** Proof: CN Railway rep *"you won't
  have to pay additional money in the future for the roadmap items… get in while the iron's hot"*
  `[gong 5241225742212609819]`; FTI *"not getting anything new yet… pre-buy… without… smart search"*
  `[gong 4811842356495327778]`.
- **EMEA GDR −2.9pt "Legal Issue":** the code is wrong — three transcripts show British Telecom is a
  **price-driven competitive RFP** (competitor ~⅓ our price); one account = 47% of the region's loss;
  our 12-month-only terms were a joint cause. Ex-BT the region clears target.

## Evidence tooling
- **Glean (primary, authenticated):**
  `node ~/Code/pm_os/bin/glean-search.js -q "<text>" -d gong|salesforce|slack|confluence -n 10`.
  Full bodies (the reliable way to read Gong transcripts & SFDC fields):
  `glean documents get --json '{"documentSpecs":[{"url":"<URL>"}],"includeFields":["DOCUMENT_CONTENT"]}'`.
- **Gong full transcripts:** `~/.claude/skills/gong-connect/bin/gong transcript <call-id>` (speaker-
  attributed). **GOTCHA that cost us a whole pass:** `gong mine` greps every transcript client-side
  and TIMES OUT / returns nothing — do NOT conclude "no Gong data" from it. The working path is
  **Glean `-d gong` to get the call id/url, then `gong transcript <id>`** (or `glean documents get`
  on the gong url). ~86% of accounts had retrievable calls once done right. The `gong` CLI may be
  blocked for the main agent (session-replay classifier) but works inside subagents; if a lane needs
  it and it 401s, note it and fall back to Glean.
- **Finance workbook:** parse locally — `uvx --with openpyxl python`, `load_workbook(path,
  read_only=True, data_only=True)`. `graph-workbook.js` 504s on files >60MB, so parse the xlsx
  directly. The `BLC July MOR` sheet (or its month equivalent) carries the authoritative bookings /
  pipeline / GDR / D1P blocks. Read the D1P Upgrade Drivers block carefully — its headline is often
  **YTD, not the month** (see traps).
- **CSV extracts:** stdlib `csv` module (pandas is not installed). Competitor field is ~0% populated
  on losses — every competitive count is a lower bound; say so once, prominently.

## Verify — real Codex adversarial review (mandatory before "done")
Run the ACTUAL Codex CLI, not a Claude stand-in, and WAIT for verbatim output:
`node "$(ls -d ~/.claude/plugins/cache/openai-codex/codex/*/scripts/codex-companion.mjs | tail -1)" task --fresh --effort high "<prompt>"`
(foreground = blocks and returns; run two independent lenses — logic/verdict and quant/arithmetic).
Point it at the findings files; ask it to try to BREAK each verdict and to list numbers to fix.
Adopt its downgrades and corrections. A subagent may only SYNTHESISE Codex output, never perform
the review. In the July run this correctly downgraded 3 of 4 verdicts to PARTIAL.
