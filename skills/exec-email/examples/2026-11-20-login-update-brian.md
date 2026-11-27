<!-- ABOUTME:
  Teaching example for exec-email: the draft Claude wrote vs the email Yu-Kuan sent.
  Topic: director login status to the CEO (Brian Stafford), 2026-11-20.
  Read §3 (the diff) before drafting any status reply to an exec thread.
  Source: Outlook Sent Items, "RE: Early access to CEO & CFO insights", 2026-11-20 18:53 UTC.
-->

# Example: login status reply to the CEO (2026-11-20)

## 1. The situation

- The CEO forwarded a customer CEO's complaint ("make it easier for clients to log into the app"). He asked twice: "was there a response?" and "can we look at logs?".
- A peer exec (Anmol, CTO) had already replied on the thread. He said the problem needs a systemic fix.
- The deadline in everyone's head: the 12/10 board meeting.

## 2. What Yu-Kuan sent (abridged, his words)

> **To:** Brian, Anmol, Amanda. **Cc:** Maggie, Peter, Lu Chen, Katinka (the people doing the work).
> **Subject:** RE: Early access to CEO & CFO insights (a reply on the CEO's thread)
>
> + Peter and the login team -
>
> Hey everyone,
>
> Quick update on director login since my last 11/11 note. I think Anmol's general take on we need to solve this more systemically is head-on, we're tackling that right now. Re: TerrePower I think it's likely due to an unfortunate gap […] so never got the functionality turned on for them.
>
> **TLDR**
> 1. Systematic testing & fixing - we have shipped a lot of login fixes but our testing hasn't been as systematic in its e2e coverage, which is what we're addressing now. […] 35+ login fixes this year - 8 since August, and 4 of them since October. iOS 9.5 went live on 11/16 with the offline Face ID fix.
> 2. TerrePower - most likely cause is his password expired due to internal company policy. He should've been able to self-reset after our MFA pwd reset launch in Aug, but TerrePower was left off […]. Next step would be to ask CSM/CS to take this over […].
>
> **What shipped since August**
> - iOS: 9.5 […], 9.4 […], SSO directors on iOS […]
> - Web: fewer surprise logouts […], clearer sign-in screens […], new Boards platform […], timeout problem closed […]
> - TLDR - we've shipped 35 login, MFA and password fixes from January to Sept […]
>
> **What's in progress**
> - Better login tracking […] "we can't see why at all due to historical reticence on logging. This will change and help us get more proactive."
> - Login tests […] "Very early estimates show we only have maybe ~30% coverage today? We're closing the gap with a 128-case test plan […]"
> - Q1'27 - Magic link sign-in […]
> - A weekly login status email […] "I think we've been so heads down on the work that we didn't provide enough viz. […] similar to other key projects like AGAI and Warren.ai."
>
> **Duncan Gillis (TerrePower)** […]
> - "The MFA pwd self-reset feature we shipped in August should have solved this - in fact Andy Warner has just told us yesterday his support queue wait on pwd resets have dropped from hours to ~<30 secs […]"
> - […]
>
> And yes we'll aim to fix everything as much as we can before the Dec 10 board meeting.

## 3. The diff: Claude's draft vs what he sent

| # | Claude's draft did | Yu-Kuan sent | Lesson |
|---|---|---|---|
| 1 | New email, new subject, To: Brian only | A **reply on the CEO's own thread**. To: every exec on it. Cc: the people doing the work. Opens "+ Peter and the login team". | Answer where the exec asked. Add the doers so the exec sees who owns it. |
| 2 | Bottom line about our own progress | The opening lines **answer the exact question asked** (TerrePower). He also chose to agree with a peer exec by name. | General rule: answer the reader's question first. How to handle other people on the thread is the user's call, not a rule. |
| 3 | Bold section headers only | A numbered **TLDR with 2 items**: the systemic theme, then the specific case. | Put a 2-3 item TLDR on top. One item per question the exec has. |
| 4 | Led with the recent count ("8 since August") | Leads with the **biggest honest number** ("35+ login fixes this year"), then the recent ones. | Lead with the largest true total, then the trend. |
| 5 | Flat list of 7 fixes | Fixes **grouped by platform** (iOS, Web). | Group by area the exec recognises. |
| 6 | Output counts only | Adds an **outcome from a named person**: support wait on password resets fell "from hours to ~<30 secs" (Andy Warner). | One real-world outcome beats a list of tickets. Ask the user for one if you have none. |
| 7 | Gaps stated as facts in a "what has not moved" section (cut on request) | **Owns the gap once, paired with the fix**: "testing hasn't been as systematic … which is what we're addressing now"; "we didn't provide enough viz … starting next week". | Own a gap in one sentence and attach the fix in the same sentence. Never a standalone "not done" list. |
| 8 | "Next steps" with Monday/Tuesday meetings and `[TBD date]` blanks | No internal logistics and no blanks. Ends with **a commitment to the exec's deadline**: "we'll aim to fix everything as much as we can before the Dec 10 board meeting." | Execs don't need our meeting plan. Close on the date they care about. |
| 9 | Neutral, third-person | **First person and conversational**: "Hey everyone", "I think", "my best guess". Benchmarks against other key projects (AGAI, Warren.ai). | Write the way Yu-Kuan talks to peers. Compare to projects the exec already trusts. |
| 10 | Exact numbers with sources | Rounder numbers with one hedge ("maybe ~30% coverage today?"), a quarter for future work (Q1'27). | One hedge is fine. Give a quarter, not a ticket date, for future work. |
| 11 | Named no cause outside the team | He chose to name a likely cause outside his team (a CSM exception list). | Attribution is the user's call. The draft stays factual. Flag the open question and let the user decide. |

## 4. What stayed the same (keep doing)

- Bold lead phrase on each bullet, then one or two plain sentences.
- Shipped / in progress / customer case structure.
- Every number traced to a source before it went in (Jira, App Store, Salesforce, Confluence).
- No ticket keys, PR numbers or test-tool names in the body.
