# CSM Response

<!-- ABOUTME:
  Generate and post CSM-facing workaround replies directly into Teams channel threads.
  Takes a complaint report (from /teams-channel-research or manual), generates per-complaint
  status updates + 2-3 actionable workarounds, and posts replies to the original threads.
-->

## When to Use

- User says "post workarounds", "reply to CSMs", "send updates back to the channel"
- User invokes `/csm-response` explicitly
- After `/teams-channel-research` completes and user wants to push responses back

## Parameters

| Param | Default | Description |
|---|---|---|
| `--report` | (required) | Path to the complaint report (e.g. `./channel-research/report.md` from `/teams-channel-research`). Must contain Teams post URLs to reply to. |
| `--channel` | AI-AMA (same default as `/teams-channel-research`) | Teams channel to post replies into. Must match the channel the complaints were mined from. |
| `--dry-run` | `false` | Generate replies but don't post them. Write to `{temp}/replies/` for review. |
| `--temp` | `./channel-research/temp/` | Temp directory for draft replies |

## Prerequisites

1. **FOCI tokens** valid for Teams channel posting. Check: `node ~/Code/pm_os/bin/get-foci-token.js --scope Group.ReadWrite.All` — this routes to the Office token which carries `ChannelMessage.Send` in its claims. The scope name `ChannelMessage.Send` is NOT recognized by `get-foci-token.js` directly. If `Group.ReadWrite.All` fails, stop and tell the user.
2. **Atlassian direct API** connected (`/atlassian-connect`) — needed to verify current Jira statuses before posting.
3. **A complaint report** at `--report` with Teams post URLs in the complaint detail sections.

## Procedure

### Step 1: Parse the Report

Read `--report` and extract for each active complaint:
- Complaint # and title
- Current status (from Jira cross-ref in the report)
- Teams post URLs (the original CSM posts that raised the complaint)
- Workarounds from the report's CSM Workarounds table
- Jira ticket links and PRD links

If the report doesn't have Teams post URLs or workarounds, tell the user the report needs those sections first (run `/teams-channel-research` to generate them).

### Step 2: Verify Current Jira Status

For each complaint with Jira tickets, hit the Jira API to get CURRENT status:
```bash
bash -c 'source ~/.zshrc 2>/dev/null; curl -sf -u dev@example.com:$ATLASSIAN_API_TOKEN "https://example.atlassian.net/rest/api/3/issue/{KEY}?fields=status,assignee,priority"'
```

Compare against what the report says. If status has changed (e.g. ticket moved from Backlog to In Dev since the report was written), use the CURRENT status in the reply.

**Lesson learned:** Jira status in reports goes stale fast. Always verify before posting.

### Step 2.5: Research Existing Capabilities (before writing replies)

Before generating any reply, use `/glean-connect` then search Glean for existing features, workarounds, or documentation that could solve or partially solve the complaint TODAY. Bias hard toward "here's how to do this with what we already have" over "we're working on it."

**Judgment rules for roadmap language:**

1. **Solve first, roadmap second.** If an existing feature, config flag, API parameter, or documented workaround addresses the complaint — even partially — lead with that. The best reply is "here's how to do this today," not "we'll build it later."
2. **Never use "committed," "guaranteed," "will ship," or equivalent certainty language.** Always qualify with "aiming to," "targeting," "working toward." Graduated tone:
   - **No Jira, no FA Tracker row, no PRD:** "Thanks for flagging this — we're tracking demand and will evaluate based on how many customers need this."
   - **PRD exists or Jira in Backlog (any priority, no quarter):** "We've heard this feedback and captured it — [link ticket]. We're evaluating priority against other requests." Frame as "input received and tracked," never as "we're actively building this."
   - **FA Tracker row with a definite quarter within 2 quarters of today:** "We're aiming to address this by [quarter + 1 buffer] — here's the tracking ticket." Always add 1 quarter of padding to FA Tracker timelines (e.g., FA says Q3 → say Q4). This is the ONLY case where you can give a rough timeline.
3. **Never say "we're filing a ticket"** unless the user (Yu-Kuan) has explicitly confirmed they will file one. Say "we're tracking this" instead.

### Step 3: Generate Replies (parallel, 1 opus agent per complaint)

For each complaint that has a Teams post URL, generate a reply with this structure:

```
**Status Update — {Complaint Title}**

{1-2 sentence status update. What's happening with the fix. Use current Jira status from Step 2.}

**Workarounds available today:**
1. {Concrete action the CSM can take right now}
2. {Second concrete action}
3. {Third if available}

**Tracking:** {Jira link(s)} | {PRD link if relevant}
{If the complaint is untracked: "We're tracking demand for this — thanks for flagging it."}
```

Writing rules for replies:
- Plain, helpful, direct. Like a colleague answering a question.
- No corporate jargon, no "we're excited to share", no "thank you for raising this"
- **Lead with existing solutions** — if something can be done today (feature, config, workaround), that's the headline, not the roadmap status
- Workarounds must be SPECIFIC ACTIONS, not "consider doing X" or "we recommend exploring"
- Include Jira/PRD links so the CSM can track progress. Backlog tickets are fine to link — frame as "we've captured this" not "we're building this." In Dev or higher can be framed as active work.
- **Roadmap tone:** follow Step 2.5 judgment rules. Never use certainty language ("committed," "will ship," "planned for"). Always qualify ("aiming to," "targeting"). Add 1 quarter buffer to any FA Tracker timeline.
- Keep each reply under 200 words

### Step 4: User Review Gate

**Always pause here.** Show the user ALL generated replies in a summary:

```
Ready to post {N} replies to {channel}:

#1 → {complaint title} → replying to {Teams URL} → {word count} words
#2 → {complaint title} → replying to {Teams URL} → {word count} words
...

Post all? Or review individually?
```

Use `AskUserQuestion` with options: "Post all", "Let me review each one", "Dry run only (save to files)".

If "review each one": show each reply and ask approve/edit/skip per reply.

### Step 5: Post to Teams

For each approved reply, post as a reply to the original Teams thread using the Graph API:

```bash
# Extract message ID from the Teams URL
# Teams URLs contain the message ID in the createdTime parameter

# Get token (Group.ReadWrite.All routes to Office token which carries ChannelMessage.Send)
TOKEN=$(node ~/Code/pm_os/bin/get-foci-token.js --scope Group.ReadWrite.All 2>/dev/null)

# Post reply to the thread
curl -sf -X POST \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  "https://graph.microsoft.com/v1.0/teams/{team-id}/channels/{channel-id}/messages/{message-id}/replies" \
  -d '{"body":{"contentType":"html","content":"<reply HTML>"}}'
```

**Message ID extraction:** Teams URLs encode the message ID as the `createdTime` parameter (epoch milliseconds). The Graph API message ID format is the same epoch value. Extract it from the URL.

**HTML conversion:** Convert the markdown reply to simple HTML (bold tags, numbered lists, links). Keep it clean — Teams renders basic HTML well.

**Error handling:** If a post fails (403, 404), log the error and continue to the next reply. Report all failures at the end. Common failures:
- 403: Token doesn't have write scope. Tell user to check FOCI enrollment.
- 404: Message was deleted or channel moved. Skip and note.
- 429: Rate limited. Wait and retry once.

### Step 6: Summary

After posting, report:
```
Posted {N}/{total} replies to {channel}.
{If any failed: "Failed: #X (reason), #Y (reason)"}
{If dry-run: "Dry run — replies saved to {temp}/replies/"}
```

## Anti-Patterns

1. **Never post without user approval.** Always hit the review gate (Step 4).
2. **Never use stale Jira status.** Verify current status before posting (Step 2).
3. **Never post vague workarounds.** "Consider evaluating options" is not a workaround. "Split packs under 150 pages before triggering GovernAI" is.
4. **Never post to the wrong thread.** Verify the Teams URL maps to the correct complaint before posting.
5. **Never skip the dry-run option.** First run against a new channel should always be `--dry-run`.
6. **Never promise roadmap commitments you can't back up.** "We're filing a ticket" = commitment. "We're tracking demand" = honest. Use Step 2.5 judgment rules.
7. **Never skip the Glean capability search.** An existing feature you didn't know about is better than a workaround. Verify before writing.

## Scope Limitations

- **Channel replies only.** This skill posts replies to existing threads, not new messages. It doesn't create new threads or post to 1:1 chats.
- **ChannelMessage.Send scope may not be available.** If the FOCI token doesn't carry this scope, the skill falls back to `Group.ReadWrite.All`. If neither works, it saves replies to files and tells the user to post manually.
- **One channel at a time.** If the report spans multiple channels, run once per channel.
