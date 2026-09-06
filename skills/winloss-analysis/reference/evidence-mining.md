<!-- ABOUTME: Reusable guide to pulling root-cause evidence per deal for win/loss reports.
     ABOUTME: Documents the Glean->Gong bridge, the fuzzy-match verification rule, the one-shot
     ABOUTME: mine-account.py miner, autonomy/auth gotchas, the roster-first prioritization, and
     ABOUTME: the digest-to-file contract mining agents must follow. Proven in the Aug 2026 build. -->

# Evidence mining — pulling root-cause evidence per deal

The Salesforce loss-reason picklist is demonstrably wrong: it over-attributes to competitors
where none existed and hides real competitive losses under "no interest." A win/loss report is
only as good as the transcripts and CRM notes behind its themes. A theme with no quote behind it
is worth less than one deal quoted verbatim with a citation. This is how you get the quotes.

## The Glean -> Gong bridge (the path that actually worked)

Glean is the search front door; Gong holds the full call transcripts. The two-step bridge:

1. **Find the calls with Glean.**
   `glean search -d gong "<account>"` returns, per hit: the call **title**, a few **snippets**
   (the matched passages), and a **URL**. The Gong call-id is embedded in that URL as the query
   parameter `?id=<digits>` — pull it with a regex like `[?&]id=(\d+)`.
2. **Pull the full transcript by id.**
   `~/.claude/skills/gong-connect/bin/gong transcript <id>` returns the full, speaker-attributed
   transcript for that call.

Glean also indexes other datasources you should mine for context, selected with `-d`:
- `salescloud` — Salesforce (opportunity fields, close notes, competitor free-text, loss reasons)
- `gainsight` — customer-success notes and health signals
- omit `-d` entirely to search across all datasources at once.

### Parsing gotcha — read the FIRST JSON object, not the whole stream
`glean` prints its JSON result and THEN appends a human-readable release-upgrade notice as
trailing text. `json.load` / `json.loads` on the raw output will choke on the trailing text. Use
`json.JSONDecoder().raw_decode(out.lstrip())`, which parses the first JSON object and returns the
byte offset where it stopped — ignore everything after it.

```python
obj, _ = json.JSONDecoder().raw_decode(out.lstrip())
results = obj.get("results", [])
```

## CRITICAL verification rule — Glean returns FUZZY matches

A call Glean returns for "<account>" may be:
- a **different product line** at the same company (e.g. a Compliance-Training, Highbond, or ACL
  call surfacing under a board-portal account), or
- a **different company with a similar name**.

Before you quote any call, confirm it maps to the REAL target opportunity — check the **speakers**
(are they from this account?), the **product** discussed (is it the line this report covers?), and
the **date** (near the report period, e.g. ~the closing month). Cite only calls you verified.
Quoting an unverified fuzzy match is how a wrong "why" gets into the report.

## The one-shot miner — start every account here

`fy27/output/tools/mine-account.py` (from the Aug 2026 build) is the recommended per-account entry
point. Given an account name it:
- runs Glean across `gong` + `salescloud` + `gainsight`,
- prints call **titles / snippets / call-ids** and the Salesforce + Gainsight context,
- and pulls **full transcripts** for the top calls (default top 4).

```bash
# run from the repo root so relative paths resolve
~/Code/PM/.venv/bin/python3 fy27/output/tools/mine-account.py "Account Name"
```

It bakes in the raw_decode parse, the `?id=` call-id extraction, and the Gong fallback below.
**Copy it into the new period's `tools/` and adapt** (account list, datasources, transcript cap)
rather than rediscovering the plumbing. It exists so every mining agent mines identically.

## Autonomy and auth gotchas

- **The gong-connect CLI is blocked from autonomous subagent execution** by the auto-mode
  classifier UNLESS an allow-rule exists in a `settings.json`:
  `"Bash(*/skills/gong-connect/bin/gong:*)"`. Without it, subagents you dispatch will stall on a
  permission prompt they cannot answer. Add the rule before fanning out mining agents.
- **The Gong transcript endpoint is intermittently flaky** — it sometimes returns empty or
  HTTP-200 HTML instead of a transcript (session re-auth needed). When it fails, fall back to the
  **Glean-indexed Gong snippets** plus **Salesforce close notes** — both are still citable, as
  long as you verify each to the target opportunity. Note the fallback in the report's caveats.
- **Glean auth**: check with `glean auth status` before a run; re-auth if expired. Gong session
  auth is handled by the gong-connect CLI (own SSO session, no admin API key).

## Roster-first — build the target list before you mine

Do not mine blind. FIRST build per-region x segment won/lost deal **rosters** as JSON, derived
from the Finance CSV spine (the clean deal list). Each record carries the fields a miner needs to
prioritize: acct, opp, arr, seg, subregion, stage-before-lost, picklist reason (a HYPOTHESIS to
test, not truth), type, lead source, days-in-stage, amendment flag, package, org, competitor.
Rosters give every mining agent a bounded target list and a priority order.

You cannot deep-mine every account. Prioritize:
- **Mine EVERY win** — wins are fewer and are the richest material for "why we win."
- **Read the competitor win/loss report and its deep-dives WHEN THEY EXIST — a required win-side
  input, not optional.** Canonical inputs:
  `fy27/competitors/reports/all-boards-competitors-vs-acme.md`, `fy27/competitors/deepdives/`,
  and any prebuilt `research/PRODUCT-WIN-EVIDENCE.md` digest. Code EVERY product, AI and
  competitive takeaway they name into the deal ledger with a decision sub-attribute (keep the
  opportunity ID). **A win ledger that is missing product/competitive wins when a competitor report
  exists is a mining FAIL, not an acceptable outcome** — the report's named product takeaways MUST
  appear as ledger rows. This is exactly the defect a past run hit: 21 wins coded, zero of them
  product- or competitor-sourced, because the mining step never read the competitor report.
- **Mine losses by priority**:
  (a) every loss in an **outlier cell** (a region x segment with an abnormal win rate — normal
      runs ~15-30%; dig every deal in a 2% or 3.8% cell to find the mechanism);
  (b) top losses by **ARR**;
  (c) every loss coded **"Chose Competitor"** or that reached **Proposal or later** (late-stage
      losses carry the real competitive signal);
  (d) a **sample of the Unresponsive / No-Interest tail** — to test whether those are really
      coverage/qualification failures rather than product losses.
- **Skip sub-$5K amendments** (`amendment:true`) for root-cause — they are contract tweaks
  (add-a-user, add-a-committee), not competitive sales. Note them only as a basis caveat.

## The digest-to-file contract for mining agents — deal ledger FIRST, themes AFTER

Mining agents write one deal-to-attribute row BEFORE they write any aggregate theme. A theme is
built from ledger rows; it never stands on its own. Every mining agent MUST:
- **Append rows to `{OUT}/research/deal-ledger.csv` AS EVIDENCE IS FOUND** — never hold
  transcripts or partial analyses only in context (compaction destroys in-context state mid-run).
  Keep the opportunity ID, account, outcome, cohort, attribute, source handle and ARR together on
  each row.
- **Record `UNKNOWN` when no decision attribute is available.** Do NOT infer an attribute from
  Finance fields — a cohort label (expansion, referral, new logo) is not an attribute.
- **Apply the same text-to-attribute rule to comparable wins and losses.**
- **Build an attribute-cluster table only after the ledger rows exist.** Each cluster shows: deals
  read, deals supporting the attribute, wins and losses with the attribute, ARR, at least three
  named proof deals, and one contradictory case.
- **Disaggregate before you demote (win side and loss side).** A broad capability (product, AI,
  security, referral) that appears on BOTH wins and losses is NOT thereby a non-cause. Subdivide it
  until you find the specific observable sub-attribute that separates the comparable wins from the
  comparable losses, and publish THAT. Worked example: "product" appears on wins and losses;
  subdivide to "Acme One Platform sold as ONE consolidated licence" — it wins at 46.4% against
  10.4% for non-platform deals, and the one platform LOSS (AG2R La Mondiale) happened only when the
  same platform was pitched as two separate products. Mark a cluster `DESCRIPTIVE` ONLY after a
  genuine subdivision attempt finds no separating sub-attribute. AI stays table stakes unless a
  separating sub-attribute (a governed, approved place for board data — risk containment, not
  feature superiority) is found; never claim AI as a net product win.
- Mine 5+ attributed Voice-of-Customer quotes per geo×segment cell as raw material; pull all that
  exist where a cell has fewer, and never fabricate to fill.
- **Return to the orchestrator ONLY a <=15-line digest plus the ledger path and the cluster-table
  path.** Never return transcripts or the full findings body.

Every number must trace to the roster JSON or the Finance workbook. Every decision attribute must
trace to verified Gong or Salesforce record evidence — no citation, don't use it.

### The deal-ledger schema (`research/deal-ledger.csv`) — one row per deal-to-attribute observation

```text
opportunity_id,account,outcome,period,region,segment,subregion,motion,arr,basis_status,
context_trigger,decision_attribute,attribute_state,acme_intervention,buyer_behavior_change,
outcome_link,text_to_attribute_rule,source_type,source_handle,source_excerpt,comparator_cohort,
contradictory_case,confidence,miner_file
```

`attribute_state` ∈ {`PRESENT`, `ABSENT`, `REVERSED`, `UNKNOWN`}.

### The attribute-cluster table (`research/ATTRIBUTE-CLUSTERS-<region>.md`)

```text
Cluster ID | Cohort and boundary | Decision attribute | Text-to-attribute rule | Wins read |
Losses read | Wins with attribute | Losses with attribute | ARR | Named proof deals |
Contradictory case | Causal chain | Alternative tested | Decision sources | Status
```

`Status` ∈ {`PASS`, `DESCRIPTIVE`, `UNKNOWN`}. Only `PASS` clusters may enter synthesis as causes.
