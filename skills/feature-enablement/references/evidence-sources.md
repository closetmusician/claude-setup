<!-- ABOUTME: Diligent-specific facts the evidence sub-agents need: Pendo app IDs, bases, dead tags, Gong rules -->
<!-- ABOUTME: Read by prompts/pendo-sizing.md and prompts/gong-evidence.md; path set in config.yaml evidence.reference_file -->
<!-- ABOUTME: Every entry carries "Last verified: YYYY-MM-DD"; entries older than 6 months lower confidence -->
<!-- ABOUTME: Sub-agents never edit this file; they propose changes under "Proposed Reference Updates" -->
<!-- ABOUTME: Contains no customer names. PMs outside Diligent replace this file for their own product -->

# Evidence Sources Reference (Diligent / Boards)

Pendo subscription for all apps below: `5738959954247680` (Diligent).

To update this file, apply the "Proposed Reference Updates" from an evidence run by hand, and set that entry's `Last verified` date.

---

## Pendo apps

### Boards Web Admin (BWA)
App `5990456097636352`. Admin/staff web app; where most Boards feature tags live.
Accounts: `001*` = real Salesforce account; `TEMP.<env>.NNNN` = internal/test/demo site. Accounts carry no usable metadata in Pendo; to classify one, resolve its ID in Salesforce.
Last verified: 2026-10-01

### Boards Web Director (BWD)
App `6248296564719616`. Director web app.
**No account dimension**: all traffic rolls up to one Pendo account, so it supports visitor-level sizing only. Every visitor is an anonymous `_PENDO_T_*` ID (per browser). Don't screen that prefix out, and don't set `includeAnonymous: false` (it returns 0).
Last verified: 2026-11-16

### Director Network (standalone)
App `6284040822915072`. Separate from the Director Network pages inside BWD (~500 visitors/wk there vs 10k–30k/wk standalone, campaign-spiky). Always say which one you mean.
Last verified: 2026-11-16

### AI Boards / Boards on Diligent One ("BCloud")
App `6288475384512512`. Pages are prefixed `BCloud | ...`; product areas are `BCloud_*` (there is no area called "AI Boards").
Accounts are keyed by **numeric Diligent Org ID**, not Salesforce ID. Product areas cover only ~28% of app events, so never present area totals as a share of the app.
Internal/large orgs to screen out before ranking: `48671`, `48674`, `48455`, `48675`, `48676`, `48672`, `766`, and the `486xx` / `48749` family.
Last verified: 2026-11-18

### Minutes (shared Boards + BoardEffect)
App `5547296519421952`. Holds both products. Split with the account metadata `current.account.agent.platform`: `boardswebadmin` / `boardsios` / `boards` = Boards; `boardeffect` = BoardEffect.
Use accounts, not visitors: internal `TEMP.UAT04.5290` inflates visitor counts.
Last verified: 2026-11-11

### SFS / Diligent Data Room (DDR)
App `6261700701519872`. Accounts are `orgid:<uuid>` with no name or Salesforce ID. All visitors are anonymous. `Nonidentified-SFSAccount` is the guest/share-link bucket (~44% of visitors); exclude it from customer counts. There was a measurement break around 6 May 2026 (MAU −60% while events held), so don't trend across it. Amplitude is the DDR system of record.
Last verified: 2026-10-09

### Boards iOS
Pendo was retired for iOS at v9.4 (~22 Sep 2026). Use Amplitude (Boards iOS project) for iOS usage. Pendo iOS data after that date is not valid.
Last verified: 2026-10-21

---

## Bases

### Forward Planner enabled accounts
~2,700 accounts (BWA). This is a moving base (reps enable/disable sites) and includes internal sites. **Do not use total BWA accounts (7,953) as the Forward Planner base**; it understates adoption ~3×.
Last verified: 2026-10-01

### BWA app-wide (context, not a feature base)
Q3 2026 (Jun 25–Sep 23): ~99,000 visitors, 33.6M events. BWA is shrinking like-for-like (events −7.3% vs Q1 2026), so quote any feature growth against this baseline.
Last verified: 2026-09-24

### Minutes-entitled Boards accounts
5,171 Salesforce Minutes-entitled Boards accounts (list dated 17 Sep 2026). 41% were active in Jul–Oct 2026 and 12% on 6+ days.
Last verified: 2026-10-06

### AI Boards active accounts
198 accounts / 508 visitors (1 Jun–7 Sep 2026). This is a small base; state it whenever you quote a percentage.
Last verified: 2026-09-14

### DDR customer-side orgs
1,979 customer-side orgs in 90 days to 8 Oct 2026, after excluding internal Diligent orgs (`fe00ddf6`, `7711a7a1`, `41184e0e`, `9eade7a4`) and the guest bucket.
Last verified: 2026-10-09

### Fallback when no base is listed
Use product-wide active accounts in the same app and window, measured live. Label the claim "of active <app> accounts" and cap confidence at medium.
Last verified: 2026-11-25

---

## Dead or polluted tags

### Director Network conversion tags (BWD), never fire
Profile Search `uCOvQylJyvdRhgoXQCoPMeoly3E`, Profile Claim `iILVR6RPB3ZEsaSajGLJjk47vbc` (0 events for 13 months), Profile Update `_anxENK_m7QMUAavfwtNfXE7Bz8`. Only the hub page `KDzjQJx-dtcbDMgQ7TAe1km3-Cc` and the nav click `bReOQ-E9G_-qeGf_tmICM3tAcmw` work.
Last verified: 2026-09-14

### BWA linking tags, polluted
Add Link `jHpoQFYi9J3eMBRmKhRbfSlJjr0` and Create Link `cQn8AcrirAdUqHRIg3ASTtVI7j0` fire on generic classes outside the link dialog, and Link Button `iZGl4hqEwUHculRDUpP75dHqnX0` probably tracks text-select mode. Use the link-dialog destination tabs instead (a floor): Resource Center `s12aGzlPOhp6B1vddC0T-g4jI0Y`, Current Books `6FcYKu-naP5H-wW_bXyUWKdkLVw`, Archived Books `aU2yB3wfTTO_Rx71RmnGGoZmPQQ`, Web Page `2hC04ropVQGai6NzghREf9RopD0`.
Last verified: 2026-11-18

### AI Boards Create link (save), dead
`u6mQNNM5KxaKNvHoFuXNsGFRxAk` has been 0 since 1 Aug 2026.
Last verified: 2026-11-18

### AI Boards Create book (save), re-tagged
`7wzWwEJA89jK0YO8_Y9uC05af20` stopped matching around 1 Sep 2026. It was re-tagged on 18 Nov 2026 with a history backfill, so pulls made before 18 Nov undercount from August on. ~99% of its volume is internal `486xx` / `48749` accounts.
Last verified: 2026-11-18

### Duplicate tags, never sum
Forward Planner main page `ESe3A1_GNzLDINNKcK077yPzLA4` = `IQcfDJyNHS-oKatSCqZgTz3nZvU`. AI Summary | Open `EY9FqtiWTW8vpg6syyoFRTQQ_gY` = AI Hub | Open Summary `z1LpwWelJF1HDb52Qk6XbgWcwQk`.
Last verified: 2026-10-01

### New tags read as infinite growth
A tag that went live mid-window shows null or huge `pctChange` (e.g. `manage-agenda-templates-btn` +19,371%). Check the monthly series for the tag's first non-zero month before reading growth.
Last verified: 2026-09-24

### Short bursts read as growth
`BWCA | Manage Users | Manage Security` (`neZ7VnRCb7FrhKnBNHOIM8Fw9tA`) spiked Jun–Aug 2026 during an MFA enrolment push. Pull the monthly series before calling any top mover a trend.
Last verified: 2026-09-24

---

## Visitor and join traps

### Partial last bucket
The final bucket of any weekly or monthly series is usually incomplete and reads as a cliff. Drop it before calling a trend. `entityUsageTimeSeries` can also extend the end date past the one you asked for.
Last verified: 2026-10-01

### Silent truncation and wrong parameters
`appUsage` with `groupBy=account` can silently return only the top 10 rows when the response is inline, so assert `len(rows) == summary.totalNumAccounts`. `entityUsageTimeSeries` takes `entityId`; passing `itemId` is ignored and returns subscription-wide totals.
Last verified: 2026-09-14

### Parallel-load timeouts
`queryFunnel`, `entityUsage` and `aggregateEntityUsage` time out when run in parallel, so run them one at a time. `appUsageTimeSeries` is safe in parallel.
Last verified: 2026-11-16

### Seasonal baseline
January is seasonally depressed. Compare quarter vs quarter or year on year by month, never anything vs January.
Last verified: 2026-09-24

---

## Gong search rules

### Searching Gong through Glean
Use Glean `search` with `app: gong`, quoted phrases, `num_results: 200`, and follow every cursor. **Hard cap: 1,000 results per query** (the cursor past 1,000 returns HTTP 400). For large phrases, split into date windows (after/before) each under 1,000. Parallel calls return out of order, so map results to windows by their dates.
Large results overflow into tool-results files; smaller ones come back inline. Handle both.
Dedupe by call ID (`call?id=`). Keep only calls whose snippet contains the term.
Full transcripts can be read with Glean `read_document` on the call URL.
Last verified: 2026-11-11

### Spellcheck fallback on zero exact hits
When a quoted phrase has no exact matches, Glean silently swaps in an unquoted keyword query and returns 200+ loosely related calls, shown only by a "Spellcheck replaced the query" notice. Treat that phrase as 0 hits. Long written-style problem phrases ("what changed in the board paper") almost never match speech; use short spoken forms ("what was updated", "what's changed"). Found independently by two evidence runs.
Last verified: 2026-11-25

### Matched windows only
Unfiltered queries rank recent calls first, so any term looks like it is growing. Only compare counts across identical-length date windows (e.g. Feb–Oct 2025 vs Feb–Oct 2026). Treat totals as a floor.
Last verified: 2026-11-10

### Rep-raised mentions
Most mentions of a new feature are raised by reps, not customers (~85% in a hand-coded Forward Planner sample). Reps keep saying "coming soon" after GA. Never report raw mention counts as customer demand; report the rep-raised vs customer-raised share from the transcripts read.
Last verified: 2026-11-10

### Shared feature names
Some names cover two products. "Forward Planner" is both the shipped BWA feature and a future AI-packaged upgrade, and UK/AU company secretaries also use "forward planner" for their own documents. Read the context before counting a mention as the feature.
Last verified: 2026-11-10

### Regex hygiene
Write any parsing script with the Write tool only. Heredocs and `python -c` turn `\b` into a literal backspace (chr 8), which silently breaks filters. After writing, check: `print(open(f).read().count(chr(8)))` must be 0.
Last verified: 2026-11-11

---

## Noise products

### Exclude from Boards Gong evidence
Exclude a call when its title, opportunity or snippet names any of: BoardEffect (including opp names or regions with `MDO BE`), Diligent Community, iCompass, BoardDocs, HighBond, Diligent Vault / whistleblowing, Policy Manager, Market Intelligence. Don't use a bare "community" keyword; it matches nonprofit account names. "Compare versions" is ~95% Policy Manager / Diligent Community policy compare and GRC regulation compare; "Smart Compare" is a separate Boards AI roadmap feature (metric trends across books). Some calls titled "Diligent meeting with <rep>" are BoardEffect demos, so check the transcript. "Document collection" also matches the existing Data Room / Secure Meeting Workflow, Entities, Third Party Manager and audit evidence collection. Generic terms ("agenda template", "approval", "resolution", "calendar", "evaluation", "announcement") need feature phrasing, because 42–76% of raw hits for such terms come from other products or ordinary business language.
Last verified: 2026-11-25

---

## Feature renames

### Ask GovernAI
Search under its old names too: AI Board Member, Smart Assist, AI Assist. ~20% of Oct–Nov 2026 calls still use the old names. "GovernAI" on its own is the umbrella brand; don't count it as Ask GovernAI. **Gong transcribes it as "Ask Govern AI"** (1,162 calls vs 70 for "Ask GovernAI" in the year to Nov 2026), so search both spellings. Reps also describe AI Board Member as a meeting notetaker that takes minutes, which is a recurring misconception.
Last verified: 2026-11-25

### Diligent Data Room
Formerly Secure File Sharing (SFS). Search both names.
Last verified: 2026-10-09

### AI Minutes editing
In Pendo, "Rewrite" (`SyFB`) was replaced by AI Transform in June 2026, so trend the two together.
Last verified: 2026-11-11

---

## Customer-facing naming

### Product and feature names in external copy
Use "Boards on Diligent One" (never "AI Boards", "BD1" or "D1P") and "Ask GovernAI" (not Smart Assist). Strip PM names, early-access customer names, internal test sites, feature flags and release-planning dates.
Last verified: 2026-11-05
