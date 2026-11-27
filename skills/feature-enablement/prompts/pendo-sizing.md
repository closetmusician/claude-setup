<!-- ABOUTME: Prompt for the Pendo problem-sizing sub-agent, sent by `/feature-enablement evidence` -->
<!-- ABOUTME: Finds a live stand-in signal for the problem, measures it, writes assets/validation/pendo-sizing.md -->
<!-- ABOUTME: Only sent when the PRD has no quantified sizing (the main session runs that gate) -->
<!-- ABOUTME: Placeholders {{...}} are filled by the main session; output shape is parsed by SKILL.md -->
<!-- ABOUTME: Spec: ~/.claude/docs/specs/2026-11-24-feature-enablement-evidence-design.md §5.3, §5.9 -->

You are sizing the problem that **{{FEATURE_NAME}}** solves, using Pendo usage data, for a sales/CS enablement pack. The PRD doesn't quantify it. A PM will confirm both the stand-in signal you pick and the number, so a candid "low confidence" is far more useful than a confident wrong number.

## Inputs

- The problem, in the PRD's words: {{PROBLEM_SUMMARY}}
- Pendo app(s) in scope: {{PENDO_APPS}}
- Previously confirmed stand-in signal (empty on the first run): {{CONFIRMED_PROXY}}
- Pendo config: {{CONFIG_PENDO}}  (keys: `window_days`, `max_candidates`)
- Reference file: {{REFERENCE_FILE}}. Read these sections first: `## Pendo apps`, `## Bases`, `## Dead or polluted tags`, `## Visitor and join traps`.
- Write your output to: `{{PROJECT_PATH}}/assets/validation/pendo-sizing.md`

## Before you start

Read the reference file first. If the reference file cannot be read, write the output file with `Status: unavailable` and `Reason: reference file cannot be read (<path>)`, then stop. Without it, dead-tag lists and bases are silently lost.

Load the tool schemas with ToolSearch, for example `select:mcp__pendo__listPagesFeaturesAndEvents,mcp__pendo__entityUsage,mcp__pendo__entityUsageTimeSeries,mcp__pendo__appUsage,mcp__pendo__getEntity`. If they don't load, or the first call errors (auth, timeout), write the output file with `Status: unavailable` and the error text, then stop.

Run `entityUsage` and `aggregateEntityUsage` calls **one at a time**, because they time out under parallel load. If a call times out, retry it once before treating it as failed.

## 1. Choose candidates

If `{{CONFIRMED_PROXY}}` is set, skip candidate search but still run step 2 on that proxy, then re-measure **only** that signal in step 3, with the same definition. Don't pick a new one; the PM already confirmed it. If the proxy fails step 2 (it went dead, collapsed or was re-tagged), don't report its number: write `Confidence: low`, say why under `Rejected candidates`, then run step 1 and propose up to `max_candidates` replacements for the PM to re-confirm.

Otherwise, find up to `max_candidates` stand-in signals for the problem in the apps in scope. Use `listPagesFeaturesAndEvents` with `search` and `searchType: "substring"`. Good stand-ins, in order of preference:
1. the manual workaround people use today (e.g. uploading a file the feature would generate);
2. the adjacent feature people use instead;
3. the page where the pain happens.

For each candidate, write one line on *why* it stands in for the problem. If the link is weak, say so.

## 2. Check each candidate is alive

Reject a candidate, and record why under `Rejected candidates`, if any of these is true:
- it is listed in `## Dead or polluted tags`, or is a duplicate of another tag;
- it has zero events in the last 30 days;
- its monthly series (`entityUsageTimeSeries`, sorted by date, last partial bucket dropped) shows an unexplained collapse or a first-ever non-zero month inside the window (a new tag, not usage);
- its volume is implausible next to the page it lives on, which suggests a generic selector.

If every candidate fails, write `Status: measured` with `Confidence: low` and `Proposed claim: none — no usable Pendo signal`, and list the rejections.

## 3. Measure

For the best surviving candidate, measure over the last `window_days` days:
- active **accounts** and visitors (`entityUsage`; `limit: 1` when you only need the summary);
- where it matters for the claim, how often accounts use it (e.g. the share active on 6+ days).

Then follow the app-specific rules in `## Pendo apps` and `## Visitor and join traps`. For example, BWD has no account dimension, so size BWD by visitors only and say so. Screen out internal accounts wherever the reference lists them.

**Base:** use the matching entry in `## Bases`. If none fits, fall back to product-wide active accounts in the same app and window, measured live (`appUsage`). Label the claim "of active <app> accounts" and cap confidence at **medium**.

**Staleness:** if a reference entry you relied on (base, app rule, tag status) has a `Last verified` date more than 6 months before today, lower confidence by one level and name the entry.

## 4. Write the output file

Use exactly this shape:

```
Status: measured | skipped | unavailable
Run: <ISO date>
Proposed claim: "X of N <base definition> (Y%) <did the workaround> in the last <window_days> days"
Proxy: <entity name> (<entity ID>, <page|feature|trackEvent>, app <app ID>) — why it stands in for the problem
Window: <start–end>   Base: <N>, <definition>, <source: reference entry name or "measured live">
Confidence: high | medium | low — <reasons>
Rejected candidates:
- <name> (<ID>) — <reason>

## Proposed Reference Updates
- <new dead tag, new base, changed rule — or "none">
```

(`skipped` is written by the main session when the PRD already has sizing; you will not normally produce it.)

Never edit the reference file yourself; propose changes in the section above.

## Reply

Your chat reply to the main session is **one line only**: `Status: <x>; proxy <ID or none>; confidence <level>`.
