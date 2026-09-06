# Teams Channel Research

<!-- ABOUTME:
  Mine Teams channels for customer feedback, dedupe, cross-ref with Jira/FA Tracker,
  thread-verify, adversarial review, and produce a prioritized complaint report.
  Reusable pipeline based on the GovernAI complaints session (Jul 2026).
-->

## When to Use

- User says "research customer feedback", "mine the channel", "what are customers complaining about"
- User invokes `/teams-channel-research` explicitly
- User wants to aggregate complaints/feedback from Teams channels into an actionable report

## Parameters

| Param | Default | Description |
|---|---|---|
| `--channel` | AI-AMA (`19:REDACTED-THREAD-ID`, team `2908ba88-e75c-4591-b839-4af4757a7787`) | Teams channel URL(s) or channel-id(s). Accepts 1-N, comma-separated. |
| `--window` | `90d` | Evidence recency window. Only evidence within this window survives to the final report. Older evidence is removed, not flagged. |
| `--output` | `./channel-research/report.md` | Output file path for the final report |
| `--temp` | `./channel-research/temp/` | Temp directory for agent intermediates (all agents persist here) |
| `--fa-tracker` | (GovernAI FA Tracker SharePoint URL) | FA Tracker Excel URL for cross-reference. Omit to skip FA Tracker. |
| `--features` | (ask user) | Comma-separated feature names for segmented mining (e.g. "Smart Summary,Smart Prep,Risk Scanner,Smart Minutes"). If omitted, ask the user. |

## Prerequisites

1. **Glean CLI** authenticated (`/glean-connect`)
2. **Atlassian direct API** connected (`/atlassian-connect`)
3. **FOCI tokens** valid for Teams channel reads (`get-foci-token.js --scope ChannelMessage.Read.All`)

Check all three at skill start. If any fail, tell the user which to fix and stop.

## Procedure

### Phase 0: Setup & Context (2 parallel agents)

| Agent | Task | Model | Output |
|---|---|---|---|
| A0-a: PRD Context | Search Glean for PRDs related to `--features` to identify "by design" behaviors. Produce a noise-filter checklist. | opus | `{temp}/prd-context.md` |
| A0-b: FA Tracker | Download and parse `--fa-tracker` via `node ~/Code/pm_os/bin/graph-workbook.js`. Extract all rows related to `--features`. If no FA Tracker URL, skip. | opus | `{temp}/fa-tracker-extract.md` |

**Gate:** Both complete before Phase 1.

### Phase 1: Channel Mining (N parallel agents, feature-segmented)

For each feature in `--features`, spawn one agent:

- Search Glean scoped to the channel URL for: `"{feature}" complaints OR issues OR bugs OR feedback`
- Extract per finding: complaint description, customer name, CSM who reported, date, Teams post URL
- Mark severity (BLOCKING/MAJOR/MINOR) based on CSM language
- Flag onboarding/training issues vs genuine product gaps
- Write to `{temp}/complaints-{feature-slug}.md`

Also spawn one catch-all agent: search for general complaints not feature-specific.

**Lesson learned (this session):** Glean result-count limits mean you MUST segment by feature. A single broad search misses things.

### Phase 2: Dedupe + Cross-Reference

**Step 2a: Merge & Dedupe** (1 opus agent)
- Read all complaint files from Phase 1 + `{temp}/prd-context.md` (noise filter)
- Merge, dedupe (same complaint from multiple CSMs = 1 entry with multiple sources)
- Remove: onboarding issues, "by design" behaviors, user error
- Rank by frequency x severity
- Cap at top 15 complaints
- Output: `{temp}/merged-complaints.md`

**Step 2b: Independent Glean Cross-Validation** (1 opus agent)
- Run a SEPARATE, broader Glean search across the channel (not feature-segmented)
- Independently rank the complaint clusters
- Output: `{temp}/glean-independent-analysis.md`
- This catches things the feature-segmented search missed and provides an independent ranking to validate against.

**Lesson learned (this session):** The independent Glean analysis was the single most valuable cross-validation step. It caught ranking errors and surfaced complaints the segmented search missed.

**Step 2c: Jira Cross-Reference** (up to 5 parallel agents, 3 complaints each)
- For each complaint cluster:
  - Search Glean for relevant Jira tickets
  - Use `atlassian-connect` curl to read ticket details (status, assignee, priority)
  - Cross-reference with FA Tracker extract
  - Classify: shipped fix, in-progress, backlogged, or untracked gap
  - **Verify Jira statuses are current** (query the ticket directly, don't trust Glean cache)
- Output: `{temp}/jira-xref-{N}.md`

**Lesson learned (this session):** Glean's Jira status cache is stale. Always verify via direct API.

### Phase 2.5: Thread-Level Verification (parallel agents)

For each merged complaint, read the FULL Teams thread (original post + all replies) using:
- `node ~/Code/pm_os/bin/teams-read-channels.js --team-id {id} --channel-id {id} --since {window} --top 100`
- Glean Document Reader for specific message URLs

Determine per complaint:
- **TRUE_ISSUE** — multiple reporters, reproducible, unresolved
- **RESOLVED** — thread shows fix/workaround was found
- **NON_REPRO** — couldn't reproduce, one-off, reporter retracted

**Lesson learned (this session):** BCI Smart Prep was non-reproducible (184-page control test succeeded). Thread verification caught this before it polluted the report.

### Phase 3: Draft Report (1 opus agent)

Read: merged complaints (with verdicts), all jira-xref files, FA Tracker, PRD context, independent Glean analysis.

Produce the report at `{output}` with this structure:

1. **Header** — title, date, sources, method, evidence window
2. **Executive Summary** — 3-5 sentence narrative identifying top themes
3. **Executive Summary Table** — ALL complaints in one table:
   `| # | Complaint / Gap | Issue specifics (with inline evidence URLs) | Category | Severity | Active Jira / PRDs (linked) | Workarounds |`
4. **Untracked Gaps Table** — complaints with no Jira/FA coverage:
   `| # | Complaint | Why it matters | Recommended next step |`
5. **Active Complaints Detail Sections** — per complaint:
   - Field table (severity, frequency, confidence, features, status)
   - Closed Jiras (linked)
   - Open Jiras (linked)
   - Missing Jiras
   - "What's happening" narrative with **inline Teams post links per mention**
   - "Who it affects" with named customers
   - "What's being done" with Jira links
   - Thread check verdict
6. **Workarounds for CSMs Table**:
   `| # | Complaint | Status | Workaround 1 | Workaround 2 | Workaround 3 |`
7. **Appendix: All Themes by Status**:
   `| # | Theme | Status (Resolved/In dev/Planned/Adding to backlog) | Key Jira / PRD |`
8. **Partially Resolved / Recently Resolved** sections
9. **Methodology**

### Phase 4: Adversarial Verification (via `/codex` skill — MANDATORY)

**This phase MUST use the `/codex` skill, not plain opus agents.** Codex provides an independent second opinion from a different model (OpenAI), which catches blind spots that same-model self-review misses.

**Step 4a: Write the draft report to disk** (prerequisite for codex review)
- The Phase 3 draft must be written to `{output}` before invoking codex
- Also write the complaint evidence summary to `{temp}/evidence-for-review.md` (one section per complaint: claim, frequency, severity, cited sources)

**Step 4b: Codex Challenge** (invoke `/codex` in challenge mode)
- Invoke the Skill tool with `skill: "codex"` and pass the report path
- Codex challenge mode tries to BREAK every claim in the report
- It will produce a findings file with verdicts per claim

The orchestrator must frame the codex prompt to cover these verification axes:
1. **Evidence accuracy:** Do cited Teams posts actually say what the report claims?
2. **Frequency inflation:** Does "5+ independent reports" hold up, or is it 2 posts from the same CSM?
3. **Severity inflation:** Is BLOCKING truly blocking, or CSM hyperbole?
4. **Jira cross-ref accuracy:** Does the linked ticket actually address this complaint?
5. **Non-reproducible one-offs:** Should any complaint be dismissed (like BCI was)?
6. **Missing context:** Did the thread resolve the issue and we missed it?

**Step 4c: Codex Review** (invoke `/codex` in review mode)
- Run `/codex` review mode on the draft for a second pass
- This catches structural issues: inconsistent severity ratings, math errors (12 themes but 6 rows), missing links, vague workarounds

**Step 4d: Apply fixes** (1 opus agent)
- Read codex challenge findings + codex review findings
- Downgrade INFLATED claims with corrected evidence
- Remove FABRICATED claims
- Cross-validate ranking against the independent Glean analysis (Phase 2b)
- Update frequency counts to reflect only evidence within `--window`
- Output: final report at `{output}`

**Why codex, not opus self-review:** This session used opus agents for adversarial review, which worked but has a same-model blind spot. Codex (OpenAI) provides genuine independence — a different model with different biases catches things Claude won't.

### Phase 5: Link Verification (1 opus agent)

Before declaring done:
- Every PRD reference must link to a verified Confluence page (search Glean to confirm URL)
- Every Jira reference must be a working `https://example.atlassian.net/browse/` link
- Every Teams post reference must be an inline URL, not a "see Teams" hand-wave
- Workarounds must be concrete actions (not "we should think about...")
- Evidence older than `--window` must be removed, not just flagged

**Lesson learned (this session):** "PRD exists" without a link looks like hand-waving. User caught this and required verification.

## Anti-Patterns (from this session)

1. **Never include evidence outside the recency window.** Old evidence inflates frequency counts and makes stale issues look current.
2. **Never cluster complaints for exec tables.** List each complaint individually so the math adds up (12 themes = 12 rows, not 6 clustered rows).
3. **Never say "PRD exists" without linking it.** Search Glean for the PRD, get the Confluence URL, link it.
4. **Never trust Glean's Jira status cache.** Verify via direct Jira API (`/rest/api/3/issue/{key}`).
5. **Never count reformatting as "filling blanks."** Subagent prompts must include SEARCH, not just WRITE.
6. **Always use `/codex` for adversarial review (Phase 4).** Never self-review with the same model that wrote the report. Codex challenge mode (OpenAI) provides genuine independence.

## Writing Style

Plain English that a smart 18-year-old can understand. No AI jargon, no drama. Say what the problem is, who it affects, what we can do. NOT yk-voice (that's for emails/comms, not analytical reports).

## Execution Budget

Typical run: ~20 agents across 5 phases. Expect 15-30 minutes wall clock.

| Phase | Agents | Model |
|---|---|---|
| 0: Setup | 2 | opus |
| 1: Mining | N+1 (one per feature + catch-all) | opus |
| 2: Dedupe + cross-ref | 1 + 1 + 5 | opus |
| 2.5: Thread verify | up to 15 | opus |
| 3: Draft | 1 | opus |
| 4: Adversarial | codex challenge + codex review + 1 opus fix agent | codex (OpenAI) + opus |
| 5: Link verify | 1 | opus |
