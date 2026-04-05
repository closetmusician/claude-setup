# PM-Weekly Improvement Plan: Materiality Filter + Audit Pass

## Context

The pm-weekly pipeline (extract → dedup → draft) passes ALL deduped evidence to a single Sonnet call for synthesis. Sonnet has no guardrails for BU relevance, customer-facing materiality, or time-window enforcement. Result: the 03/29 weekly email included ~19 of 64 evidence items that should not have been there.

Three failure categories observed:
1. **Non-BU / non-customer-facing items** — Cortex, Atlas, Third-Party Manager, AI Scorecard, Risk Manager
2. **Weak shipping evidence** — "iManage integration in development" with no ETA or concrete signal
3. **Beyond 2-week window** — Items with May/June ETAs appearing in "Shipping Next"

Root cause: no filtering layer exists between extraction and drafting. The `tier` field is computed but never used. The draft prompt says "next 30 days" while the section header says "next 2 weeks."

## Approach: Layered Defense (4 layers)

Three architect perspectives were evaluated:
- **Deterministic filter** — fast, cheap, auditable, but can't handle content nuance
- **LLM-based triage + audit** — handles nuance, but adds cost/latency and is less predictable
- **Prompt engineering** — simplest change, but LLMs don't reliably follow filtering instructions alone

**Decision: combine all three as defense-in-depth layers.** Each layer catches what the prior one misses.

| Layer | What | Where | Catches |
|-------|------|-------|---------|
| L1: Extraction prompts | Teach Haiku what NOT to extract + add `audience`/`bu_relevance` fields | `prompts/extract-*.md` + `bin/extract-evidence.js` | ~60% of bad items never extracted |
| L2: Deterministic filter | Config-driven hard rules (channel blocklist, time window, shipping strength) | NEW `bin/filter-evidence.js` | Known-bad channels, >14d ETAs, weak evidence patterns |
| L3: Draft prompt | Tighten section mapping, add materiality gate + negative examples | `prompts/draft-weekly.md` | Last line of defense for items that pass L1+L2 |
| L4: Post-draft audit | Sonnet verification call producing traceability report | NEW `bin/audit-draft.js` | Hallucinations, wrong-section placement, weak evidence leaks |

---

## Layer 1: Extraction Prompt Improvements

### 1a. Schema change — `bin/extract-evidence.js`

Add two fields to `buildEvidenceTool()` (lines 107-133):

```js
audience: { type: 'string', enum: ['customer', 'internal', 'leadership'],
  description: 'customer=end-user-visible, internal=eng/ops tooling, leadership=ELT-relevant' },
bu_relevance: { type: 'string', enum: ['boards_gov', 'other_bu', 'cross_cutting', 'unknown'],
  description: 'boards_gov=Boards/Governance/GovernAI, other_bu=Risk/TPM/Entity/Compliance, cross_cutting=platform-wide' },
```

NOT in `required` — Haiku can omit when unclear (defaults to null, treated as "unknown" downstream).

### 1b. Extraction prompt additions — `prompts/extract-teams.md` and `prompts/extract-outlook.md`

Add after existing `## Rules` section:

**New `## BU Scope` section** (~15 lines):
- In-scope: Boards (Cloud, NextGen, Mobile), Governance (Community, BoardDocs, BoardEffect, Policy Manager), GovernAI (Minutes, Smart Prep, Smart Summary, Semantic Search), Platform (Migration, MFA, D1P)
- Out-of-scope: Cortex (eng tooling), Atlas (design system), Risk Manager (separate BU), Third-Party Manager (separate BU), Entity & Subsidiary Management, Compliance, ACL Analytics, AI Scorecard (eng internal)

**New `## Audience & Relevance` section** (~20 lines):
- Definitions for `audience` and `bu_relevance` fields
- Explicit instruction: "Do NOT extract items that are purely internal engineering tooling (CI/CD, test coverage, design system packages, npm releases) unless they block a customer-facing deliverable"
- Tighten status=G: require explicit "launched/deployed/live/shipped" signal. "In development" is NOT status G.

**New `## What NOT to Extract (examples)` section** (~15 lines):
- 6 negative examples from the 03/29 failures (Cortex, Atlas, TPM, Scorecard, iManage, build failures)
- 4 positive examples showing what SHOULD be extracted (D1P deployment, GovernAI activations, Smart Book Builder errors, competitive loss)

### Files modified
- `bin/extract-evidence.js` — ~6 lines added to `buildEvidenceTool()`
- `prompts/extract-teams.md` — ~50 lines added
- `prompts/extract-outlook.md` — ~45 lines added

---

## Design Decisions (confirmed by Yu-Kuan)

1. **Upcoming Moments horizon: 30 days** — Items 15-30 days out go to Upcoming Moments. Beyond 30 days excluded entirely.
2. **Major Initiatives table: Boards/Gov only** — Table filtered to portfolio. Other BUs have their own reports.
3. **TBD items: Never in Shipping Next** — "Shipping Next" means you have a date. TBD items appear in Major Initiatives only.
4. **Audit mode: Iterative fix loop** — On P0/P1 findings, automatically re-draft with issues flagged, loop until clean (max 3 iterations, then fail to human).

---

## Layer 2: Deterministic Post-Dedup Filter

### New file: `bin/filter-evidence.js`

Runs between dedup (Step 3) and draft (Step 4) in the pipeline. Three sequential passes:

**Pass 1: Always-Keep Gate**
- `status === "R"` → always keep (risks must never be filtered)
- `owner` matches ELT member from org-chart → always keep

**Pass 2: Channel/Content Relevance (addresses FC1)**
- Channel blocklist (config-driven, case-insensitive substring match):
  - `atlas`, `cortex`, `discussion-ownership`, `localization ama`, `dev - bcore`, `derived data`, `third-party manager`, `risk manager`
- Description blocklist (config-driven keyword patterns):
  - `test coverage reporting`, `design tokens`, `design system`, `monitoring alert`, `build fail`
- Automated sender patterns (Outlook):
  - `no-reply@`, `SFDC_`, `Site24x7` — unless description contains GovernAI activation keywords

**Pass 3: Shipping Quality + Time Window (addresses FC2 + FC3)**
- **Time window (FC3):** If `eta` is parseable and `> today + 14 days` → exclude (reason: `eta-beyond-window`)
- **Weak evidence (FC2):** If `status` is `Y`/`unknown` AND `eta` is `TBD`/`null`, check description for disqualifiers ("in development", "exploring", "investigating", "FAQ", "documentation") WITHOUT any shipping-positive language ("release", "launch", "ship", "deploy", "go live", "production") → exclude (reason: `weak-shipping-evidence`)

### New file: `config/filter-rules.json`

All blocklists and thresholds are config-driven (not hardcoded). Structure:

```json
{
  "version": 1,
  "enabled": true,
  "alwaysKeep": { "statuses": ["R"], "eltBypass": true },
  "channelBlocklist": ["atlas", "cortex", ...],
  "descriptionBlocklist": ["test coverage reporting", ...],
  "automatedSenders": ["no-reply@", "SFDC_", ...],
  "automatedSenderExceptions": ["GovernAI"],
  "shippingDisqualifiers": ["in development", "exploring", ...],
  "shippingPositive": ["release", "launch", "ship", ...],
  "timeWindow": { "shippingNextDays": 14 }
}
```

### New file: `lib/filter.js`

Pure filter logic (no I/O). Exports: `alwaysKeepPass()`, `channelRelevancePass()`, `shippingQualityPass()`, `applyFilters()`. Follows `lib/dedup.js` pattern for testability.

### Audit trail: `state/filter-log-{date}.json`

Every excluded item logged with reason:
```json
{
  "date": "2026-03-29",
  "inputCount": 64, "keptCount": 45, "excludedCount": 19,
  "excluded": [
    { "description": "...", "channel": "...", "reason": "channel-blocklist:cortex" }
  ]
}
```

### Integration: `bin/run-weekly.js`

Insert new Step 3.5 between dedup and draft. Add `--skip-filter` flag (matching `--skip-extract`/`--skip-dedup` pattern). Update summary line to show: `Extracted: N → Deduped: M → Filtered: K`.

### Integration: `config/weekly-pipeline.json`

Add path templates:
```json
"filterRules": "config/filter-rules.json",
"filterLog": "state/filter-log-{date}.json"
```

### Files created
- `bin/filter-evidence.js` — ~200 lines (CLI wrapper)
- `lib/filter.js` — ~150 lines (pure logic)
- `config/filter-rules.json` — ~30 lines
- `test/filter.test.js` — unit tests against 03/29 fixture data

### Files modified
- `bin/run-weekly.js` — ~25 lines added (Step 3.5 + --skip-filter flag + summary update)
- `config/weekly-pipeline.json` — 2 path entries added

---

## Layer 3: Draft Prompt Tightening

### Changes to `prompts/draft-weekly.md`

**3a. Fix Shipping Next window** (lines 31, 68):
- `"next 30 days"` → `"next 14 days"` in both section definition and mapping rule #3

**3b. Add Materiality Gate** (new section after line 71):
~20 lines of rules applied BEFORE section mapping:
- EXCLUDE if `audience=internal` AND `bu_relevance != boards_gov`
- EXCLUDE if `bu_relevance=other_bu` (including from Major Initiatives table)
- INCLUDE despite `internal` if item has ELT ask, budget/headcount, or competitive dynamics
- EXCLUDE from Shipping Next if `eta=TBD` (regardless of status — TBD never goes to Shipping Next)
- Upcoming Moments: only items with ETA within 30 days of today. Beyond 30 days excluded entirely.

**3c. Add negative examples** (new section, ~15 lines):
8 real failure examples from 03/29 with explicit "EXCLUDE" labels — the same items the user flagged.

**3d. Tighten Shipping Next criteria** (replace lines 30-34):
- `eta` must be a concrete date within next 14 days (TBD items NEVER in Shipping Next)
- `audience=customer or leadership`, `bu_relevance=boards_gov or cross_cutting`
- Strong evidence of active work (not "in development" or "exploring")
- TBD items route to Major Initiatives table only

### Files modified
- `prompts/draft-weekly.md` — ~50 lines added, 2 lines edited

---

## Layer 4: Post-Draft Audit with Iterative Fix Loop

### New file: `bin/audit-draft.js`

Sonnet call AFTER drafting. Takes draft markdown + evidence JSON. Produces a verification report via `tool_use` (forced schema). On P0/P1 findings, **automatically re-drafts with issues injected as constraints**, looping until clean or max iterations reached.

**What it checks:**
1. **Traceability** — For each bullet/row in draft, find backing evidence item(s) by index
2. **Factual accuracy** — Dates, owners, statuses match evidence
3. **Hallucination detection** — Any claim with no backing evidence = P0
4. **Section placement** — Status=R only in Risks, ETA>14d not in Shipping Next, TBD never in Shipping Next
5. **BU relevance** — Items with `audience=internal` or `bu_relevance=other_bu` flagged if present
6. **Time window** — Upcoming Moments items beyond 30 days flagged
7. **Omission check** — High-signal evidence items that don't appear anywhere

**Output schema (via `audit_report` tool):**
```
overall_verdict: "pass" | "warn" | "fail"
hallucination_count, mismatch_count, missing_evidence_count
items: [{ draft_section, draft_text, evidence_ids, verdict, severity, detail }]
untraced_evidence: [{ evidence_index, reason }]
```

**Severity:**
- P0: hallucination, status fabrication (evidence=R, draft=G)
- P1: date mismatch >2d, owner mismatch, wrong section, out-of-window, other-BU item included, TBD in Shipping Next
- P2: minor date mismatch, weak evidence, style

**Iterative fix loop (the key design):**

```
loop (max 3 iterations):
  1. Run audit against current draft
  2. If verdict === "pass" → done, exit loop
  3. If P0 or P1 issues found:
     a. Build a "fix prompt" that includes:
        - The current draft
        - The audit findings (P0/P1 items only)
        - Explicit instructions: "Remove these items / Fix these mismatches"
     b. Call Sonnet to re-draft with the fix constraints appended
     c. Overwrite the draft file
     d. Continue loop (re-audit the new draft)
  4. If max iterations reached with issues remaining → exit non-zero, log remaining issues
```

**Why iterative instead of single-pass auto-fix:**
- A single "fix" call may introduce NEW issues while fixing old ones (observed in agent orchestration work)
- Re-auditing after each fix catches cascading errors
- Max 3 iterations prevents infinite loops
- Each iteration costs ~$0.30 (audit + re-draft), so worst case is ~$0.90 for 3 loops — still cheap for a weekly pipeline

**Pipeline behavior:**
- Loop converges (usually iteration 1 or 2) → pipeline succeeds, clean draft
- Loop exhausts 3 iterations → pipeline exits non-zero, best draft written, remaining issues logged to stderr
- P2-only findings → pipeline succeeds, P2s embedded as HTML comments (not worth re-drafting)

### New file: `prompts/audit-draft.md`

System prompt for the audit Sonnet call (~60 lines). Includes BU scope context (same as extraction), severity definitions, explicit instructions to flag status upgrades and invented metrics.

### New file: `prompts/fix-draft.md`

System prompt for the re-draft call (~30 lines). Takes audit findings as constraints:
- "Remove the following items from the draft: [list]"
- "Fix the following mismatches: [list with corrections]"
- "Do NOT add any new content. Only remove or correct."
- "Preserve all other content, structure, and formatting exactly"

### Integration: `bin/run-weekly.js`

Insert new Step 4.5 between draft (Step 4) and summary (Step 5). Add `--skip-audit` flag and `--max-audit-loops N` flag (default 3). Audit output written to `state/weekly-audit-{date}.json`.

### Cost/latency impact

| Step | Model | Cost (typical) | Cost (worst: 3 loops) | Latency (typical) | Latency (worst) |
|------|-------|----------------|----------------------|-------------------|-----------------|
| L1 extraction (longer prompts) | Haiku | +~$0.005 | +~$0.005 | +~2s | +~2s |
| L2 filter (deterministic) | None | $0 | $0 | ~0.1s | ~0.1s |
| L4 audit+fix (1 loop) | Sonnet | ~$0.30 | ~$0.90 | ~40s | ~120s |
| **Total new overhead** | | **~$0.31** | **~$0.91** | **~42s** | **~122s** |

Typical pipeline: ~2.2min (up from ~1.5min). Worst case: ~3.5min. Cost per run: ~$0.47 typical, ~$1.07 worst.

### Files created
- `bin/audit-draft.js` — ~350 lines (audit + fix loop + CLI)
- `prompts/audit-draft.md` — ~60 lines (audit system prompt)
- `prompts/fix-draft.md` — ~30 lines (re-draft system prompt)
- `test/audit-draft.test.js` — tests against 03/29 fixture data

### Files modified
- `bin/run-weekly.js` — ~25 lines added (Step 4.5 + --skip-audit + --max-audit-loops flags)
- `config/weekly-pipeline.json` — 1 path entry added (`auditOutput`)

---

## Implementation Order

Build each layer independently and test before moving to the next. Each layer is useful on its own.

### Step 1: Layer 3 — Draft prompt tightening
- Edit `prompts/draft-weekly.md` (30d→14d, materiality gate, negative examples)
- Zero code changes, immediate effect
- Test: re-run pipeline with `--skip-extract --skip-dedup` against 03/29 evidence

### Step 2: Layer 1 — Extraction prompt improvements
- Edit `bin/extract-evidence.js` (add `audience`/`bu_relevance` to schema)
- Edit `prompts/extract-teams.md` and `prompts/extract-outlook.md`
- Test: re-run extraction against 03/29 raw scans, inspect evidence for new fields

### Step 3: Layer 2 — Deterministic filter
- Create `lib/filter.js`, `bin/filter-evidence.js`, `config/filter-rules.json`
- Write tests against 03/29 evidence fixture
- Integrate into `run-weekly.js`
- Test: full pipeline run, compare filtered vs unfiltered draft

### Step 4: Layer 4 — Post-draft audit
- Create `bin/audit-draft.js`, `prompts/audit-draft.md`
- Integrate into `run-weekly.js`
- Test: run audit against 03/29 draft, verify it catches the known failures

### Step 5: End-to-end validation
- Full pipeline run against 03/29 raw data (re-extract, dedup, filter, draft, audit)
- Compare new draft against original 03/29 draft
- Verify all 10 user-identified failure items are excluded
- Verify no legitimate items were lost (manually check filter log)

---

## Verification Plan

**Per-layer tests:**
- L1: Check that re-extracted evidence from 03/29 raw scans has `audience`/`bu_relevance` fields populated; Cortex/Atlas/TPM items either not extracted or marked `internal`/`other_bu`
- L2: Unit tests for `lib/filter.js` using fixture data; verify all 10 failure items are excluded; verify all R-status and ELT items survive
- L3: Re-draft with `--skip-extract --skip-dedup` against filtered 03/29 evidence; verify no out-of-window items in Shipping Next, no other-BU items anywhere
- L4: Audit report for 03/29 draft should produce `overall_verdict: pass` (clean draft)

**Regression test:**
- Save 03/29 raw scans as test fixtures (`test/fixtures/`)
- Create integration test that runs full pipeline against fixtures and asserts:
  - None of the 10 failure items appear in the draft
  - Key legitimate items (D1P deployment, GovernAI activations, Smart Book Builder risk, Search/Encryption) DO appear
  - Audit verdict is "pass" or "warn" (no P0 hallucinations)

---

## Files Summary

### New files (7)
| File | Lines (est.) | Purpose |
|------|-------------|---------|
| `lib/filter.js` | ~150 | Pure filter logic |
| `bin/filter-evidence.js` | ~200 | Filter CLI wrapper |
| `config/filter-rules.json` | ~30 | Filter rules config |
| `bin/audit-draft.js` | ~250 | Post-draft audit script |
| `prompts/audit-draft.md` | ~60 | Audit system prompt |
| `test/filter.test.js` | ~200 | Filter unit tests |
| `test/audit-draft.test.js` | ~150 | Audit tests |

### Modified files (6)
| File | Changes |
|------|---------|
| `bin/extract-evidence.js` | +6 lines (schema fields) |
| `prompts/extract-teams.md` | +50 lines (BU scope, audience, negative examples) |
| `prompts/extract-outlook.md` | +45 lines (same additions) |
| `prompts/draft-weekly.md` | +50 lines added, 2 lines edited (14d window, materiality gate, negative examples) |
| `bin/run-weekly.js` | +45 lines (Step 3.5 filter + Step 4.5 audit + flags + summary) |
| `config/weekly-pipeline.json` | +3 path entries |

---

## Design Decisions (confirmed by Yu-Kuan)

1. **Upcoming Moments horizon: 30 days** — Items 15-30 days out go to Upcoming Moments. Beyond 30 days excluded entirely.
2. **Major Initiatives table: Boards/Gov only** — Table filtered to portfolio. Other BUs have their own reports.
3. **TBD items: Never in Shipping Next** — "Shipping Next" means you have a date. TBD items appear in Major Initiatives only.
4. **Audit mode: Iterative fix loop** — On P0/P1 findings, automatically re-draft with issues flagged, loop until clean (max 3 iterations, then fail to human).
