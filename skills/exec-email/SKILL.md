---
name: exec-email
description: "Write a short exec email that is NOT the PM weekly: a bottom line, then a few bold section headers with impactful, concrete bullets. Use for a summary or recommendation to a boss or exec (drafted from the user's notes), or a progress email for one named project team (drafted from that repo's GitHub PRs). Triggers: \"exec email\", \"summary email to my boss\", \"tighten this into an exec update\", \"progress email for the <project> team\", \"/exec-email\". NEVER for the PM weekly status email, with or without a project name: that is pm-weekly, with its own format and template. NOT for an internal evidence-cited status report (that is evidence-backed-status)."
---

<!-- ABOUTME:
  exec-email SKILL.md - short exec emails: bottom line, bold headers, concrete bullets.
  Two kinds: a project team update (from GitHub) and a summary to an exec (from notes).
  Templates: templates/team-update.md (cowork w/e 2026-10-30 v2), templates/briefing.md.
  Siblings: pm-weekly (portfolio PM email, Outlook draft); evidence-backed-status.
  Written 2026-10-30; made general the same day for summary and recommendation emails.
-->

# exec-email: short emails for execs

## 1. When to use

- A progress email for one named project team, for example the cowork team. Not the PM weekly.
- A summary, assessment or recommendation to a boss or exec, for example after a meeting.
- The user gives rough notes or a draft and asks for an exec-ready version.

## 2. When NOT to use

- The PM weekly status email: `pm-weekly`. It has its own format, template and pipeline.
  Never use this skill's templates for it, and never edit pm-weekly from here.
  If the user says "weekly update" or "weekly email" and names no project, it is pm-weekly.
- A status report that must cite `file:line` evidence: `evidence-backed-status`.
- A PR summary for reviewers: `pr-briefing`.

## 3. The shape (every kind)

The reader is an exec. They want the conclusion, why it matters, and what happens next.

1. **Subject:** `<Topic>: <kind of email>, <date or context>`.
2. **Bottom line:** one or two sentences after the greeting. State the conclusion first.
3. **Two to four bold section headers.** Each holds two to five bullets.
4. **Bullets lead with a bold phrase**, then one or two sentences. Sub-bullets carry one example or number.
5. **A next-steps or ask section** closes the body. Name an owner or a `[TBD date]` where one is missing.
6. **Sign-off:** a one-line close, then `Yu-Kuan`.

Pick the section set for the kind of email:

| Kind | Section headers | Template |
|---|---|---|
| Project team update | What we shipped · Decisions made · Focus for next week | `templates/team-update.md` |
| Summary or recommendation | Bottom line · What we learned · My view · Suggested next steps · Key facts (optional) | `templates/briefing.md` |
| Other | Choose two to four headers that answer "so what?" and "what next?" | the nearest template |

## 4. The bar

- **Length:** half a page. Put supporting data in a short "Key facts" list, not in the body.
- **Tone:** confident and direct. Positive for a team update. Balanced for an assessment.
- **Concrete:** a number, a name or a short example in each bullet. "$11M ARR, 30% growth" beats "solid growth".
- **Cut what the reader does not act on:** backend work, test counts, PR numbers, ticket keys and raw notes.
- **Keep every fact the user gave.** Never invent a number, date or name. Mark a conflict or a gap as `[TBD: …]`.
- **Hedges stay, once.** If the user is unsure, say so in one plain sentence. Do not repeat it in each bullet.
- **Style:** ASD-STE100 (`~/.claude/rules/writing-style.md`). One idea per sentence, 25 words at most.
- **Confidential topics** (M&A, people, deals): do not commit the draft to a shared repo.

## 5. Procedure

Output first, then refine.

1. **Pick the kind, the reader and the path.** Name all three in your reply.
   - Project team update: `<repo>/docs/comms/weekly/<Friday YYYY-MM-DD>.md`.
   - Summary to an exec: `~/Code/pm_os/drafts/<YYYY-MM-DD>/<slug>.md` (git-ignored), unless the user names a path.
2. **Gather the input.**
   - From the user's notes: read the whole draft. List each claim and number.
   - Project team update from GitHub: run these from the repo.
     ```bash
     gh pr list --state merged --limit 50 --json number,title,mergedAt,author \
       -q '.[] | select(.mergedAt >= "<Monday>") | "\(.number) \(.mergedAt) \(.author.login) \(.title)"'
     git log --all --since=<Monday> --pretty='%ad %an %s' --date=short
     gh pr view <n> --json body -q .body | head -25   # for each merged PR
     ```
     Closed-unmerged PRs are not progress. Leave them out.
3. **Sort each item** into a section, or cut it. Find the bottom line before you write a bullet.
4. **Fill the template.** Keep its order and format.
5. **Write the file.** Commit it locally only if it is a team update in that team's repo.
6. **Report.** List every guess, conflict between notes and every `[TBD]` you left.
7. **Refine with Teams (project team update, only when the user asks).** Ask which chats hold the project. Then read only those:
   ```bash
   node ~/Code/pm_os/bin/teams-read-chats.js --chat-id <id> --since 7d --json
   node ~/Code/pm_os/bin/teams-read-channels.js --team "<team>" --channel "<channel>" --since 7d
   ```

## 6. Traps

- **Confusing this skill with pm-weekly.** On 2026-10-30 a "weekly update" trigger here overlapped pm-weekly.
  An edit also reached pm-weekly's description. Both were reverted. Leave pm-weekly to its own skill.
- **Too much detail.** The first cowork weekly listed test counts, Node versions and PR numbers.
  The user rejected it as "too nitty gritty". Apply the cut list in §4 before you write.
- **Guessed names.** A GitHub login is not a name. Thank "the team" unless the user gives names.
- **Numbers that disagree.** Notes often give two values for one fact. Show the one you used and flag the other.
- **A full Teams scan.** `--scan-recent --since 7d` is slow, and the user rejected it once. Ask for the chats instead.
- **Expired Teams token.** The chat token lasts about 30 minutes.
  Refresh: `node ~/Code/pm_os/bin/extract-teams-chat-token.js`.
- **Short `gh` search.** `--search "updated:>=..."` can miss PRs. Filter merged PRs on `mergedAt` as in step 2.
