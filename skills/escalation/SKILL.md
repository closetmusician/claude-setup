---
name: escalation
description: "Research a new escalation and draft the reply Yu-Kuan would send: solutions, updates, workarounds, framed to protect the team, redirect blame and clear up FUD. Input is a pasted email or Teams message, or a link. Use on \"escalation\", \"draft a response to this\", \"respond to <person>'s email\", \"reply to this Teams message\", \"help me answer this angry email\", \"how do I reply to this\", or /escalation. It ONLY drafts. It never sends or posts. NOT for posting workaround replies into CSM channel threads from a complaint report (csm-response), NOT for a short exec summary email from notes (exec-email), NOT for general voice polish of a non-escalation text (yk-voice)."
---

<!-- ABOUTME:
  escalation - research an inbound escalation, then draft the reply or replies Yu-Kuan would send.
  Rules come from 10 draft-vs-sent comparisons, 8 session logs and test rounds 1-2 (docs/firedrills/escalation-skill/).
  Research first (code is truth), a written stance and point list, then the closest sent examples, then framing rules.
  Output: reply files plus evidence.md in a topic folder; owner-only choices come back as questions.
  Draft only: the skill never calls a send, reply or post tool.
-->

# Escalation

Detail that does not fit here lives in `~/.claude/skills/escalation/reference.md`. Open it for the phrasebook, audience quotes, greetings and sign-offs, the full source ladder, the full commands and the rule examples.

## When to use

- Yu-Kuan pastes an email or Teams message, or gives a link, and wants a reply drafted.
- Someone blames product, asks "when does it ship", forwards a customer complaint, or spreads a wrong claim (FUD) about the team.
- The reply goes to Diligent staff (the field, CS, execs, peers, legal, own team). It may be forwarded to a customer.

## When NOT to use

| Ask | Use instead |
|---|---|
| Post workaround replies into many CSM channel threads from a complaint report | `csm-response` |
| A short summary or recommendation email to a boss from notes, with no blame or FUD to handle | `exec-email` |
| Polish the voice of a text that is not an escalation reply | `yk-voice` |
| Find a thread or count messages only, with no reply | `pm-search` |

**Hard rule: draft only.** Never call a send, reply, forward, post or draft-create tool (Gmail, Outlook, Teams, `csm-response`). Write files. Yu-Kuan sends.

**Fact-pack mode.** If the caller supplies the inbound text plus a fact pack (a test round), make no live lookup at all. Skip the fetch in Step 1 and all of Step 2. The fact pack is the evidence. Still write the Step 4 Stance block, in a file of its own per case (for example `<case>-claims.md`) in the output folder. Skip Step 6 item 20 (the verify pass). Step 4b (examples) still runs. Write files where the caller says.

**Test mode.** In a test, the caller names an example slug (or slugs) to skip. Never open it. Use the next-closest example instead.

**Do not pass the reply through `yk-voice`.** This skill holds its own voice rules (VOICE section).

## Step 1. Intake

1. Get the full thread, every message body, not previews:
   - Teams link: `node ~/.claude/skills/pm-search/scripts/search-all.js thread --ref '<teams link>' --max-messages 60 > <folder>/inbound.json`
   - Email subject: `search-all.js search --q 'subject:"<subject>"' --sources graph --types mail --since 30d --limit 10`, then `thread --ref 'mail:<convId>|<msgId>' --max-messages 50`.
   - Pasted text: save it as-is to `<folder>/inbound.md`.
2. Pick the topic folder now: `<repo>/docs/firedrills/<topic>/`, or the folder the owner names. Every working file goes there. Never `docs/temp`.
3. Write down, in one line each:
   - **Sender** and their role (field, CS, exec, peer, legal, own team).
   - **Audience**: who is on To and Cc, and who may get it forwarded (a customer?).
   - **Channel**: Teams chat or email. The reply matches the channel. If the pack has no channel line, take it from the inbound ref.
   - **The message to answer**: the LATEST message from the MOST SENIOR person on the thread. It sets line 1 and the order of points. An earlier ask comes after it.
   - **Reply moment**: a first reply to a risk flag, an answer to blame or a challenge, a forwarded complaint list, a status, a plan hand-off, or a cover note for an attached analysis. Two moments on one thread get two replies.
   - **Political subtext**: who is being blamed, and what wrong claim is in the thread.
4. **Owner framing.** Pull these out of Yu-Kuan's ask, if present: the stance, the blame target, how hard to push back, what to admit, a word limit, a folder. Each one beats the matching default in this skill (see the precedence order in Step 5). It sets the stance, not the wording. Restate it in the reply's own words and fit it to the reply moment. A premise the evidence contradicts still gets reported to the owner first (Step 3). Never write around it silently.
5. **Audience tier.** Set the audience tier from To/Cc (highest present wins: board > ceo > elt > peers) and read reference.md §Audience tiers. Owner framing still wins.

## Step 2. Research

Code is truth. A Teams message or a Jira status is a lead, not proof. Run steps 2.0-2.4 for every case. Then run one or more branches (A, B, C). Close with 2.6.

Parallel subagents are allowed. Every spawn names a `model`: `sonnet` for search lanes, `opus` for synthesis and the verify pass. Every spawn prompt carries the STE contract line from `~/.claude/docs/plans/harness/dispatch-templates.md` §0.

**How to read the commands.**
- `search-all.js` means `node ~/.claude/skills/pm-search/scripts/search-all.js`.
- Inside a table cell, `\|` stands for a plain `|`. Remove the backslash when you run it.
- Every Atlassian `curl` runs as `bash -c 'source ~/.zshrc 2>/dev/null; curl ...'` so the token loads. `-u ...` means `-u yklin@diligent.com:$ATLASSIAN_API_TOKEN`.
- `search-all.js` has four traps (`--to` needs `--from`; `--to` covers the whole day; `thread --ref` starts at the anchor; `--group thread` drops snippets). See `reference.md` §4.
- Auth check: `curl -sf -o /dev/null -w "%{http_code}" -u ... "https://diligentbrands.atlassian.net/rest/api/3/myself"`.

| Step | What | Command |
|---|---|---|
| 2.0 | Auth checks | `node ~/Code/pm_os/bin/ensure-tokens.js --no-browser` (exit 4: `/pm-login`); `glean auth status` (fail: `/glean-connect`); `gh auth status`; Atlassian curl to `/rest/api/3/myself` (not 200: `/atlassian-connect`); `~/.claude/skills/salesforce-connect/bin/salesforce connect` |
| 2.1 | Claim list | Write `<folder>/claims.md` with the Write tool: one row per complaint, ask, date or promise (with who said it), and Yu-Kuan's own premise. Every later step fills a source into a row. |
| 2.1b | Owner's own messages (premise test) | Search Yu-Kuan's own sent mail and chats on the topic before you trust the premise: `search-all.js search --q "<topic>" --sources graph --types mail,teams --from <start> --to <inbound date> --all`, then keep only Yu-Kuan's messages. The owner's earlier reply can confirm or break the premise. |
| 2.1c | Sign-offs and go-lives | Find the message where the sender (or their team) approved, signed off or announced the go-live: `search-all.js search --q '<topic> ("sign off" OR approved OR "go live" OR "live on" OR launched)' --sources graph --types mail,teams --from <start> --to <inbound date> --all`. Also read the sender's own posts in the working chat or channel. A sign-off by the sender beats any later complaint. |
| 2.1d | Momentum | List what the product shipped in the last 90 days that the reader cares about: `search-all.js search --q '<product> (launched OR "now live" OR released OR GA)' --sources graph,glean --types teams,mail,other --from <90 days back> --to <inbound date>`. Keep 2-4 items with dates. Field and customer replies need this line; it costs points when missing. |
| 2.2 | Prior work | `rtk proxy grep -ril -e "<topic>" -e "<customer>" ~/Code/PM/docs/firedrills ~/Code/PM/amanda/firedrills ~/Code/PM/docs`. Reuse an existing code trace or timeline. |
| 2.3 | Surrounding threads | Glean leads: `search-all.js search --q "<topic>" --sources glean --types mail,teams --limit 10`. Graph depth: `search-all.js search --q "<topic>" --sources graph --types mail,teams --since 90d --all --group thread --exclude-own`. Read each key thread with `thread --ref`. Open every Jira or Confluence link posted inside a key thread. |
| 2.4 | Full text of each cited doc | Jira: `curl -sf -u yklin@diligent.com:$ATLASSIAN_API_TOKEN "https://diligentbrands.atlassian.net/rest/api/3/issue/<KEY>?fields=summary,status,fixVersions,resolutiondate,description,comment,issuelinks"` (read raw `fields.description`). As of the escalation day: the description can be newer, so read `/rest/api/3/issue/<KEY>/changelog` and take the text as of that date. Confluence: `.../wiki/rest/api/content/<PAGE_ID>?expand=body.storage,version`. SharePoint or Salesforce doc: `glean documents get --json '{"documentSpecs":[{"url":"<url>"}],"includeFields":["DOCUMENT_CONTENT"]}'`. |

**Branch A. "Is it built, and when does it ship?"** (a feature, a fix or a date)

| Step | What | Command |
|---|---|---|
| A1 | Find the PRs | `gh search prs "<JIRA-KEY>" --owner DiligentCorp --limit 15 --json repository,number,title,state,updatedAt` |
| A2 | PR state and checklist | `gh pr view <N> -R DiligentCorp/<repo> --json title,state,isDraft,mergedAt,baseRefName,reviewDecision,reviews,files,body`. Read the body checklist for other repos, flags and upstream releases. |
| A3 | Read the code, not just the diff | `gh repo clone DiligentCorp/<repo> -- --filter=blob:none`, check out the branch, then `git grep -nE "<symbol>"` on every call path. If the branch fetch fails: `gh api "repos/DiligentCorp/<repo>/commits?sha=<branch>&until=<date>"`. |
| A4 | Fix is in the release | `gh api "repos/DiligentCorp/<repo>/compare/<merge-sha>...<release-tag>" -q '.status'` |
| A5 | Release is live | iOS: `curl -s "https://itunes.apple.com/search?term=diligent+boards&entity=software&country=us&limit=5" \| jq -r '.results[] \| [.trackName,.version,.currentVersionReleaseDate] \| @tsv'`. Web: `curl -s -u ... "https://diligentbrands.atlassian.net/rest/api/3/project/<PROJECT>/versions"`. Treat `released=false` as weak. |
| A6 | QA sign-off | Jira issue curl (2.4) with `fields=comment`. Look for a tester's comment. |

**Branch B. "Who said what, and when?"** (the escalation blames the team)

| Step | What | Command |
|---|---|---|
| B1 | Full mail and chat threads | `search-all.js thread --ref 'mail:<convId>\|<msgId>'` and `thread --ref 'chat:<chatId>\|<messageId>' --max-messages 200` |
| B2 | Dated timeline | `jq -r '.results[].messages[] \| [.date, (.from \| if type=="object" then .name else . end), (.text \| .[0:200])] \| @tsv' <thread>.json > <folder>/timeline.tsv`. Then add a short exact quote and a link per key row. |
| B3 | Negative search ("they never asked") | `search-all.js search --q "<topic>" --sources graph,glean --types mail,teams --from <start> --to <end> --all`. Cover Inbox, Archive, Sent and Glean. |
| B4 | Deal or customer fact | `mcp__salesforce__run_soql_query`: `SELECT Name, Account.Name, StageName, CloseDate, Amount FROM Opportunity WHERE Account.Name LIKE '%<customer>%'` |
| B5 | Lead only, then the real message | `node ~/Code/pm_os/bin/glean-search.js --chat "<question>"`. Open and quote the real message before you use it. |

**Branch C. "A customer has a problem with a shipped product"**

| Step | What | Command |
|---|---|---|
| C1 | Map each complaint to its fix release | Jira versions curl (A5), then JQL: `curl -s -G -u ... ".../rest/api/3/search/jql" --data-urlencode 'jql=project=<P> AND fixVersion="<v>"' --data-urlencode 'fields=summary,status,resolutiondate,fixVersions'` |
| C2 | Proof the field was told | `search-all.js search --q "<release or feature>" --sources graph,glean --types mail,teams --since 180d` for launch posts and notices. |
| C3 | A copy the reader can open | `export PATH=/opt/homebrew/opt/node@24/bin:$PATH; npx --yes @salesforce/cli data query -o diligent --query "SELECT Title, UrlName, LastPublishedDate, IsVisibleInPkb, IsVisibleInCsp FROM Knowledge__kav WHERE PublishStatus='Online' AND Title LIKE '%<topic>%'" --json` |
| C4 | Customer set-up (region, SSO, settings) | `mcp__salesforce__run_soql_query`: `SELECT Name, Site_URL__c, Production_Environment__c FROM Site__c WHERE Account__c IN (SELECT Id FROM Account WHERE Name LIKE '%<customer>%')` (pod to region: `reference.md` §4), plus `glean documents get` on the customer's process docs. |
| C5 | Usage numbers or trends | Amplitude `mcp__amplitude__query_amplitude_data` or Pendo `mcp__pendo__entityUsage`, split by app version. First check the tool can see the event at all. |
| C6 | Customer's own words | `node ~/Code/pm_os/bin/glean-search.js -q "<customer>" -d gong`, then the Gong transcript; Gainsight notes via Glean. |

| Step | What | Command |
|---|---|---|
| 2.6 | Independent verify pass | `Agent` with `model: "opus"`: a fresh agent re-runs the Jira, Confluence, `gh` and Glean reads for every number, date and status in the draft. It reports contradictions and overclaims. Run it after Step 5, before hand-off. In a run without subagents, do it yourself: re-read each date and status word in the draft against the saved source file. |

**Source ladder (short).** The winner depends on the claim type. Full table: `reference.md` §3.

| Claim | Strongest source | Not enough alone |
|---|---|---|
| Built | Code on the branch, read in full | PR diff, Jira scope text |
| Merged / in release / live | `mergedAt`; tag compare; App Store or deploy record | Jira status or `released` flag, "out now" email |
| Tested | A tester's Jira comment | "final testing" in chat |
| Ship date | Jira release plan plus every upstream release | One engineer's message |
| What a person said | The original message, opened, with link | Glean AI or agent summary |
| Incident detail | The later, first-hand message | An earlier "allegedly" |
| How many | A query you ran, split by version | A lane note, a Glean AI number |

Evidence beats the owner's claim. Code beats an engineer's claim. Say so plainly.

## Step 3. Pre-draft checks and owner-only flags

**Judgment checks** (no command; run them on `claims.md`):
1. **Test Yu-Kuan's premise.** Look for evidence against their framing. Report it first, in chat, before the draft ("Point 1 is not true, so don't put it in writing"). Quote the source line that breaks the premise, with its date and link. No quote, no challenge: a general or rounded claim ("all users are on SSO") is not proof. Keep every option the premise rules out for only some users. If a narrower version is true, write that version and drop only the false part (P17 template: "nothing in writing before <date>").
2. **Split the cause.** For each complaint: our bug, a customer setting, another team, or a vendor. A cause can have several parts; keep every part.
3. **Workarounds.** Test each option alone and in pairs. Say which pairs close the gap. A workaround that answers a different question is cut and flagged.
4. **Scope.** A bug in a feature that was never supported is not a delivery miss.

**Pre-draft checklist.** Every claim in the draft passes its row, or it is cut.

| # | Claim | Must have |
|---|---|---|
| 1 | Ship date | Release plan plus upstream releases. No firmer than the accountable person's own words; when two sources differ, use the later, softer one. |
| 2 | "Built", "done", "ready", "final steps", "in testing" and every other status word | Code read on the branch, every call path. No firmer than the proof, as for dates: use the weakest true word. |
| 3 | "Shipped", "live" | App Store or deploy record, plus tag compare. |
| 4 | "Tested" | A tester's comment. Use the weakest true word. |
| 5 | A fix's or safeguard's scope | The ticket or source text, word for word in scope. Never widen it (for example "documents" to "documents and web"). |
| 6 | A quote | The real message, opened, with its link. Never Glean AI. |
| 7 | A fast workaround | Where it lives (code, a site setting, a database row), and what it needs (release, database change, UI). |
| 8 | A number or trend | A query you re-ran. A correlation is called a correlation. A range is stated as its floor ("35+"). Two sources differ: use the floor or the one the pack calls verified, and flag the choice. Never drop the number. |
| 9 | "Nobody told us" | A negative search in every folder, chat and Glean. |
| 10 | A legal or security conclusion | A Legal or Security source that says it. Product never states one on its own. |
| 11 | Each key fact | A link the reader can open. If the source has no link, name the source in words. |
| 12 | Every guess | Your own guess: checked or cut. The owner's own stated guess: kept, hedged ("My guess is", "likely"), and flagged. Never written as fact. |

**Owner-only. Flag, never decide.** Find these. Put each one in the chat answer as a short question. Leave the safe default in the draft.

**Raised or not raised.** "Leave out" covers only items nobody on the thread raised. If the inbound, the sender or a critic the sender forwards raised it, it is a point. Answer it in its safest true form in the reply, AND flag it. No new date, no fix promise, no quote that blames a person. For an item nobody raised, its default wins: do not write a softer version.

**Headline level only.** A raised point goes in as its outcome, in one or two lines. Leave out the detail under it:
- internal pipeline state ("merged but not deployed", "in the release branch"): say "live", "coming" or "being fixed";
- raw counts and tallies from a report or a review ("12 of 59 mentions");
- a new promise to chase another team ("I'll ask X for a date"): write what that team owns, not what we will ask them;
- an ask that the reader turns on a setting with a known problem that the pack does not show as fixed;
- a legal or contract conclusion ("most contracts permit it") without a Legal source in the pack: hedge it as the owner's understanding and flag it.

| Item | Safe default in the draft |
|---|---|
| A break-glass or manual option (database change, site move) | Leave out |
| A new date only Yu-Kuan can promise, or a firmer date than the source | Use the source's date and hedge |
| Bad news nobody raised ("what has not moved") | Leave out |
| A gap the thread raised, or the gap a plan in the reply closes | In, beside its plan (P7 template), never alone; flag it |
| Pin a guessed cause on a named team or seller | Facts only |
| A second blame target, when the ask or the facts give two | Use the stronger one; flag the other |
| Agree with a peer exec by name | Leave out |
| Admit own slowness or a bug as ours | Leave out, unless the owner's ask admits it |
| Staffing or quality numbers that expose eng | Leave out, unless they size a gap from the row above; then beside the plan, and flagged |
| How hard to push back on the field or the customer | The owner's ask, if it sets it; else soft (P6) |
| Push back on a field sender's request for help, or suggest a use-it-now workaround they did not ask for | Leave out. This row does NOT cover a request that breaks a process already agreed, or the owner's own team asking to change a plan the owner set. Those hold the line (Step 4 reply moments "Process redirect" and "Decision gate") |
| Two sources give different numbers for one thing, the pack names a data problem in an analysis, or the pack holds a newer bad event (another failure after the fix) | Leave out of the reply; ALWAYS flag it in one line |
| The reply touches consent, contract, privacy or terms wording | Flag: "bring Legal in before sending?" |
| The reply names an open ticket | Flag: "who owns <ticket>? name them?" |
| A repeat problem for the same user or customer | One short "sorry again for the hassle" line in the reply; flag whether to answer "why is this still happening?" head-on |
| A firm or blunt reply, or any reply to a CISO, GC or exec who raised a risk, with an exec or the sender's boss on To/Cc | Keep the firm line. Flag: "tone OK with <exec> on the thread?" |
| Accept the sender's proposed shape for a plan, or a peer's offered work | The smallest plan the owner decided. A sender's next step that costs our team nothing: back it in one line, hand its lead to their team, flag it |
| An option not yet decided; internal gates and policy | Leave out. If the thread raised the topic: "a choice is open", plus the pack's hedged date for a recommendation |
| A number the source calls preliminary, rough or "~" | In only with its hedge ("early count, ~25"); flag that it may move |
| Privileged or legal material (counsel's notes, screenshots of a legal thread) | Never quote or attach it; flag who may see it |
| An attachment or memo, and who receives it | Flag: "send to the whole To/Cc list, or only <name>?" |
| A legal or contract view with no Legal source | Hedge as "my understanding"; flag it for Legal to confirm |
| A meeting or review the thread mentions with no date | No date in the reply; flag "do you want a date for <meeting>?" |
| Offer Yu-Kuan's time, a walkthrough, a meeting or new work | Leave out of the reply; ALWAYS flag it |
| In a reply to the boss: a "Next steps" block with new team work | Keep it in the draft: outcomes and the boss's own deadline only, no internal meetings (P14). Flag it, with its lines |
| A document not yet final (in review) | Name its owner and status; do not ask anyone to share it |
| Who goes on To and Cc, who to "+" add | Keep the inbound list |
| A person's role no source confirms | Ask |
| Which internal facts may reach the field | Internal reply only |
| A premise the evidence contradicts | Report it; do not write it in |

## Step 4. Stance and point list (write before drafting)

Add a `## Stance` block to `claims.md`. Draft nothing until it exists.

1. **Stance**: one sentence. From the owner's ask if given; else your best inference, named in the chat answer.
   With no owner ask, infer the stance from who asks and what the ask does, not from the literal question:
   - The ask breaks a process already agreed (a single tracker, a channel, an approval step), or repeats an ask that was already redirected: hold the process. Do not answer the items one by one.
   - The owner's own team asks to change a plan the owner or their boss set: gate it. The change waits for data and a named approver.
   - A question list with answers in the pack: answer it. Defer only what the pack does not hold.
   - Help with a customer problem: help (the default).
2. **Principle** (only when the stance needs an argument: an answer to blame, a challenge, a push-back or a record-setting reply; else write "none"): one or two sentences that make the stance right to a fair reader outside the team. Good kinds: a tradeoff (capability vs control), a scale limit ("cannot be done for one customer, that is not scalable"), a design choice made long ago that made this unavoidable, a written limit the other side ignored, "the control belongs in <place>, not in <place>". The principle becomes its own short paragraph in the reply. A principle that fits one point only goes inside that point. Never add a principle paragraph that a fact in the reply already says. A list of facts or safeguards is not a principle.
3. **Blame target**: one team or vendor, or none.
4. **Reply moment** (from Step 1), and what it allows:

| Moment | The reply holds |
|---|---|
| First reply to a risk flag (a warning that needs action) | Thanks, the mitigations in flight with owners and status, the scope and what it means, "we will keep you posted". No receipts, no defence; the principle as one line at most. |
| Answer to blame | Line 1 the receipt or the disagreement, then the principle, then numbered reasons with receipts. |
| Answer to a challenge (someone questions a decision or a design) | The principle first, then a short proof, in chat prose if on Teams. Not a list of safeguards. |
| Forwarded complaint list | Thanks to the sender and whoever got the feedback, any ask on the field from the owner's framing, then one point per complaint: the fix, its date, what it means for the user, the help article, any "field was told" receipt. Leftover issues go to T2. |
| Status to the boss | A TLDR with the stance in one or two numbered lines (what we must still fix, what is going well), then each point, then a "Next steps" block (kept, flagged; Step 3). |
| Plan hand-off | The plan, one line per material with what it is for, then an `Actions:` list. |
| Cover note for an attached analysis | Thanks for their work, who reviewed it with you, one general hedge ("may change if ..."), "let's discuss?". No finding from the analysis. Do not accept, date or direct their plan. |
| Process redirect (piecemeal asks against an agreed process) | Line 1 restates the agreed process as a polite ask ("let's please ..."). One line of why (things get lost, the customer suffers). The plain rule ("we are not going to answer <channel> one by one"). Who to go to first, and where answers already live. No item answered in the reply; list them in chat. |
| Decision gate (own team asks to change a plan) | What you learned and who you spoke to. Openness, if any. Then "HOWEVER" and the decision rule (the deadline the change must not hurt). Per option, one ask per role (PM, Eng, UX), each to a named person: estimates, days, timeline. Who approves. "We are not approving <x> yet." "Is that clear?" |
| Holding reply (the full answer needs an owner decision, a meeting or more work, and the sender wants an answer now) | Line 1 the status in one phrase (where things stand), plus any pushback on the sender's framing. When the full answer comes, only if a source names the time (else "shortly"), and who sends it. No plan detail yet. Then the full answer goes in a second reply. |
| Question list (a factual checklist: security, RFP, a customer questionnaire. NOT an exec's or peer's planning questions, which take "Plan hand-off") | One short opener. One numbered line per question, in the sender's order: "yes", "will be in <product>", or "not sure, defer to <team>". Defer only what the pack does not answer. No routing paragraph. |
| Field feedback forwarded, with the boss on the thread (this row wins over "Status to the boss" when the boss forwarded or is on Cc and the feedback came from the field; Brian addressed alone with a status ask takes "Status to the boss") | Thanks to the sender and team. "A few quick things -". Then 2-4 numbered points: the likely root cause (hedged), our approach (near and long term), and a debug or follow-up ask to named people. |
| Correcting your own earlier answer (your last message on the thread was wrong) | Line 1 owns the slip in a few words ("I need to correct my note above"), then the right answer. No apology paragraph. Same length as the message it corrects, or shorter. |
| Wrong-team escalation (a peer sends us another team's item) | Short. Which items are ours and which are not, with the right team or ticket path. A blunt "please check <source>" line when the error came from the sender's tool or list. No meeting. |

5. **Point list**: number each point the message to answer raises, each option or next step the sender lists, each complaint in a list the sender forwards, and each point in the owner's ask. Every point is answered in the reply or flagged in chat. Never cut one in silence.
   **Triage each point first, and write the move next to it.** Yu-Kuan answers in full only what his own team owns and the evidence answers. Most other points get one line.
   - **Answer**: the owner's team owns it and the pack answers it. Full depth (size table).
   - **Route**: another team or person owns it (AI/ML, CS, Security, Sales, Support, the field team itself). One clause: the owner by name, and a polite ask to loop them in or go to them. Never answer it yourself, even when the pack holds a partial answer; put that partial answer in chat.
   - **Push back**: the point rests on a vague ask, a wrong premise, old data or a skipped process. One or two lines: say so plainly and ask the sender to be specific or fix the input ("could you be more specific on which <x>?"). Do not answer the vague ask.
   - **Back**: a colleague on the thread already made the right point. One line that backs them ("Neither was I", "+1 to <name>"), then build on it.
   When the senior person's latest message is a short note, line 1 answers the person whose message carried the complaint. A reply with more Route and Push back points than Answer points is a short reply: use the quick reply, process redirect or push-back size. A point with a false, unconfirmed or owner-only part keeps its true part. Per point: the answer, the verified facts that support it (with source), and any receipt (for example "the field was told on <date>"). For a critic's list, sort each item: a reason to leave (a complaint) or a wish (goes in the upside, paired with the roadmap item).
6. **Not asked**: facts that answer no point (competitors, market, a later date, a forwarded side ask). They stay out of the reply. A point from the owner's ask is never "not asked". Offer them in the chat answer if useful.
7. **Facts not confirmed**: one line each. None of them may appear in the reply as a claim. Cut only that fact, not the point around it. An ask that someone check it is allowed. The owner's own stated guess is not on this list (checklist row 12).

## Step 4b. Read the closest examples (before drafting)

`~/.claude/skills/escalation/examples-private/` holds the real replies Yu-Kuan sent. It is local only and never committed. If it is missing (a fresh clone), use `examples/`, which holds the same replies with names, customers and numbers replaced by slots. This step runs in fact-pack mode too.

1. Read `INDEX.md` in that folder. Pick the 2-3 rows closest to this case: same audience first, then same reply type, then same channel. In test mode, skip the slugs the caller names.
2. Read those files. Note the opening move, the structure (numbered points, tables, `Actions:`), the close, the hedges and how deep one point goes.
3. **Copy moves, never facts.** Never copy a name, customer, number, date, product or claim from an example. Every fact comes from this case's evidence.
4. Length comes from the size table (P1) times the number of **Answer** points. Route, Push back and Back points take one line each. An example of the same reply moment shows the depth per point and the total length: when your draft is more than 1.5 times the closest example's word count, cut to the example's depth.

## Step 5. Draft

**Precedence order.** When two rules pull apart, the higher one wins.

1. **Facts.** The source ladder, the pre-draft checklist, P8 dates and status words, and "unconfirmed facts never appear as claims". Nothing overrides these, not even the owner's framing. Report the conflict in chat.
2. **The owner's ask** (Step 1.4): stance, blame target, push-back level, what to admit, word limit. If the ask names who is at fault, state it flat; do not soften it with P6 and do not flag it.
3. **Owner-only defaults** (Step 3), read with "raised or not raised". They beat P6 softening and P15 momentum.
4. **Reply moment and point list** (Step 4). Answer each point; add nothing else.
5. **Channel (P20)** beats the audience row on format. Teams gets chat prose and no sign-off block.
6. **Stance beats momentum.** When the team is blamed, receipts (P17) come before momentum (P15). When the stance is "never supported" or "not our scope", skip momentum, or show past fixes as best-effort only, and say the words "best effort" (or "not a commitment") in the reply. P8 beats P15 on every date.
7. **The audience row beats the generic P2 opener** (for example Legal gets thanks first; a cover note under 100 words gets no "TLDR").
8. The rest, in the order below.

**Rules read wrongly in rounds 1 and 2.**
- **P3 bans fault words, not ownership.** To the boss, own the product experience at team level and say there is still work to do. After a process miss, a "lessons for the team, we will retro" line is allowed. Never answer a critic with a "mostly fixed" counter-headline.
- **P9 bans volunteering in the reply, not offers.** An offer never vanishes silently. It goes to the chat answer as an owner-only question.

**Rules, ordered by points lost.**

1. **P18. Argue the principle, not weak spots.** If Step 4 has a principle, it is a paragraph in the reply (or a line inside its one point). Never hand a critic a list of your gaps. Never swap their headline for a counter-headline. Hedge opinions; state design limits flat.
2. **P2. Open with the answer and the frame.** Line 1 answers the message to answer (Step 1.3) or states the stance. When the team is blamed and the stance is set, line 1 is the disagreement, not a literal yes or no. A "TLDR" to the boss states the stance in one or two numbered lines and touches every problem they asked about; it is not a list of the critic's items. When someone flags a risk or relays a complaint, thank them first; thank the person who did the work (the one who gathered the feedback), not the boss who forwarded it. In every other moment, line 1 is the point itself: no "thanks for the detail", "thanks for your patience" or "thanks for laying this out" opener. Never restate the customer's pressure or the accusation. Never "Short version" or "Here is the plan".
3. **P1. Size by points, not by audience.** See the size table below. Never shrink a point because the To list is wide.
4. **P8. Nothing firmer than the source.** Status words ("built", "final steps", "live") follow the proof, like dates. Use only dates and date words ("early", "mid", "end of") someone already said. No date at all when a release it needs is not live. Never turn the requester's deadline into our target. Hedge: "targeting", "aim", "maybe". No "I will bring you X by <date>". If the chat answer flags a date as the owner's call, the reply holds no date for it ("we'll confirm timing shortly"). A flag and a commitment never coexist. Never promise work, a date or a pickup on behalf of another person or team unless the evidence shows they agreed to it. A sign-off, approval or review that the evidence shows as pending is written as pending ("to be signed off by <name>"). P8 is not a reason to defer: answer every question the evidence answers, in its own hedge, and defer only the rest, naming the team. State a date as the team's ("we're targeting 12/12"), never as a named colleague's ("the timing <name> shared"). The owner often manages that colleague.
5. **P3. No concession words, no self-blame** (read with the note above). Cut "fair", "real", "we own it", "that is on me", "ours to fix". Sympathy is one short line at most.
6. **P14. Cut method, caveats, process.** No "four systems confirm", "two passes", "I pulled the workbook", no critic's tallies. No internal meeting plans. Keep the claim.
7. **P7. Protect own team.** Never list "what has not moved". Frame a gap as a feature not shipped yet, never as a defect in our code. When the pack shows it, credit the work already built or designed, and say only the ship step was late. Blame history or tooling, not people. No demand on a team member in front of the field.
8. **P15. Momentum and upside**, where the stance allows (precedence 6). Say what just shipped, with every shipped item the pack lists. Pair each customer wish with its roadmap item. A falling bad number is progress, plus "it will never reach zero, because <reason>" when that is true.
9. **P9. Hand off, do not volunteer.** No sessions, write-ups or personal follow-ups in the reply. Point to existing sources. A reply that hands a plan or work to others ends with an `Actions:` list: one line per named person, own team's step included. Name the one person who sends the next update. In a boss reply, say "we'll ask <team> to take over <x>" instead of a direct ask to a team not on the thread.

Then the others:

10. **P5.** Redirect blame to one real owner (Sales, Rev Ops, Platform, a vendor, CSM) in one clause, framed as work under way there. Move on.
11. **P6.** Name another team's gap softly ("I'm wondering if", "We believe ... might"), once per point, unless the owner's ask sets a harder line.
12. **P17.** Set the record with dated, linked receipts. Never in a first reply to a risk flag. Claim only what the record proves ("nothing in writing before <date>", not "they never told us"). Every "the field was told" receipt in the pack goes in.
13. **P4.** If some ownership is needed, own visibility or communication only, as a lesson and a retro. Never promise a new approval gate or process to another team.
14. **P16.** Give something to do now (a setting, a scoped use, archiving). If a problem may continue after the fix, route it to the existing T2 escalation process.
15. **P10.** Each ask names one person and is a polite question ("could you", "would you mind").
16. **P11.** Close: field and peers get a specific ask to a named person, with thanks or partnership before it (VOICE section). For a peer with the boss on the thread, flag a conditional offer to brief the boss. The boss gets the hedged commitment to their own deadline, or an offer as a question (flagged).
17. **P12.** Numbered points with bullets under them. Links inline on the claim, never a link section. Dates as mm/dd/yy; a month with no day as a word ("July 2025"). Names spelled as on the To and Cc list. A table only for a boss reply with many items.
18. **P13.** The field reply holds outcomes and dates only. No PR numbers, release names, code gaps, gates or internal docs. Label any internal file as internal.
19. **P20.** Match the channel. Teams gets chat prose, not a memo. When you add people mid-thread, open with a "+ <Name>" line, in Teams or email, and add them to Cc in email. When threads split, say which thread does what.
20. **P19.** Voice and sign-off: see the VOICE section and `reference.md` §6.

**Size table (P1).** Count the points in the Step 4 list. An owner word limit wins.

| Job | Size |
|---|---|
| Cover note, analysis attached | 50-100 words in all |
| Teams chat answer | 40-200 words; chat prose. Up to 350 only for an answer to a challenge that needs the principle |
| Push-back or routing reply (mostly Route and Push back points, with an exec or the field on the thread) | 80-180 words |
| Field update, one or two points | 150-300 words |
| Plan hand-off with materials | 250-450 words |
| Point-by-point record-setting or forwarded complaint list (field or peer) | about 100-150 words per point, plus about 80 for the open and close |
| Status to the boss | about 80-150 words per point; usually 350-900 |
| Quick reply: one point to answer, a reply during a live meeting, or a short chat answer to one question | 40-100 words; no greeting line, no numbered list, no sign-off in chat. This row wins over any longer row when the message to answer raises one point |
| Process redirect | 100-200 words |
| Decision gate to own team | 350-650 words |
| Question list | about 10-20 words per question, plus about 30 |
| Field feedback with the boss on Cc ("a few quick things") | 150-250 words |
| Wrong-team redirect to a peer | 50-90 words |

Under the size means an Answer point, a verified fact or a point's depth is missing. Never drop a point in silence; a Route or Push back point takes one line. Over the size means an unasked point, a routed point answered at full depth, or a preview of an attachment. Fix the content, not the word count. When the reply-type size and the tier length (`reference.md` §Audience tiers) differ, the reply-type size wins and the tier length is a ceiling. Yu-Kuan's real replies run short: about half are under 200 words, and a reply during a meeting or to one point is often 50-70 words.

**Audience and phrasebook.** Voice per audience, quotes, and the use and never-use phrases: `reference.md` §1-§2. Phrases are voice, never facts. Never use: "Short version", "<X> is fair", "we own this", "What has not moved", "Here is the record", a fact table or "Notes for Yu-Kuan" inside the reply.

**Output split.** Write one reply per audience when the audience needs both:
- `reply-external.md` (or `reply-<field-team>.md`): forwardable, outcomes only (P13).
- `reply-internal.md`: own team or execs. It may hold release names, gaps and asks to engineers.
If one reply covers everyone, write only one file, and write it as if a customer could read it. Two reply moments get `reply-1.md` and `reply-2.md`; keep the principle argument for the reply that answers blame.

## Step 6. Self-check

Run this on your own reply text. Fix each fail, then run it again.

1. Line 1 answers the message to answer, or states the stance; no restated pressure (P2).
2. No concession or self-blame word: grep `fair|we own|on me|ours to fix|mine to own|is real|is right` (P3).
3. No method, caveat or process line; no critic's tallies (P14).
4. Every date, date word and status word matches a source line, with an equal or softer hedge; no date when its release is not live (P8).
5. **Unconfirmed facts:** for each line in "Facts not confirmed", grep its key noun in the reply. Zero hits as a claim (an ask to check it is fine). The owner's hedged guess reads as a guess and is flagged. Each scope claim keeps the source's exact scope.
6. If Step 4 has a principle, it is in the reply, in plain words: a paragraph, one line inside its point, or one line in a first reply to a risk flag (P18). If Step 4 says "none", the reply has no principle paragraph.
7. Every point on the point list is answered in the reply or flagged in chat; no section answers a point that is not on it. Every claims row marked cut or owner-only has a chat question.
8. No list of own weak spots and no counter-headline (P18).
9. Momentum only where the stance allows; every shipped item the pack lists is there (P15).
10. Size fits the size table: `wc -w`. Under the floor: find the dropped point or the thin one, then fix it. Over: find the extra point.
11. No "what has not moved", no named team member blamed, no defect framing of own team (P7).
12. A hand-off ends with an `Actions:` list; one person owns the next update (P9).
13. A problem that may continue is routed to T2 (P16). Every "field was told" receipt in the pack is in, except in a first reply to a risk flag (P17).
14. Each ask names one person and ends with "?" (P10).
15. Links inline; mm/dd/yy; month-only dates as words; names as on To and Cc (P12).
16. The field reply has no PR numbers, release names or internal gates (P13).
17. Every owner-only item nobody raised is out of the reply; every raised one is in, in its safest form; both kinds are chat questions. Every offer became a chat question.
18. No fact table, method or "how we checked" text inside any reply file.
19. Greeting and sign-off match `reference.md` §6.
20. Step 2.6 verify pass ran, and each contradiction it found is fixed or cut.

## Output format

Folder: `<repo>/docs/firedrills/<topic>/`, or the folder the owner names. Never `docs/temp`.

| File | Holds |
|---|---|
| `reply-<audience>.md` | A header, then the reply text only. |
| `evidence.md` | Each fact the draft rests on, with its source link; each fact not confirmed; the verify-pass result. |
| `inbound.md` or `inbound.json`, `claims.md` (with the Stance block), `timeline.tsv` | Working files. |

Reply file header (above a `---` line):
```
Channel: <Teams chat link or email thread, reply-all or new>
To / Cc: <names>; + add: <names, or none>
Mention: <@names>
---
<reply text>
```

**Chat answer to Yu-Kuan:**
1. Any premise the evidence contradicts (first). Then one line: "Stance: <stance>. Principle: <principle, or none>." Say if you assumed the stance. Name the examples you read.
2. The reply file paths, with word counts and the point count.
3. The owner-only flags, as short questions, one per line ("Mention the manual database switch? Default: left out."). Always include each offer and, for a boss reply, the proposed "Next steps" lines.
4. Facts not confirmed, one line each (none of them is in the reply).

## VOICE

<!-- VOICE-MODE: owner-voice (set by Yu-Kuan, 2026-11-27) -->

Drafts use Yu-Kuan's own voice, as seen in their Sent mail. The owner chose this on 2026-11-27. It is a named exception to the STE writing rule, for escalation reply text only. The chat answer, `evidence.md` and every other file still use STE.

- First person, with hedged opinion: "I think", "I'd suggest", "My guess is".
- Long sentences joined by commas are fine. Shorthand is fine: "w/", "&", "e.g.", "e2e", "asap", "~", "<".
- Sign-off "YL" by default. Use "Yu-Kuan" to the CEO, the CISO, an external customer, or on a formal hand-off to a wide list. No sign-off in Teams chat. Full table: `reference.md` §6.
- Greeting: one person on To, greet them ("Hi <name>,", "Hey <name>,"). Exactly two on To: greet both ("Hi <name> and <name>,"), or open with the name of the one you answer ("<name>, ..."). Three or more on To, or a group chat, greet the group ("Hi all,", "Hi team,", "Hey everyone,"). A reply that answers one person on a wide thread may open with that person's name instead of a greeting ("Lily, ..."). A quick reply during a live meeting has no greeting. When you add people, the "+ <Name> -" line opens the reply and replaces the greeting. Never greet the most senior person on Cc.
- **Less polish than you think.** Less polish cuts headings and labels, never a point or a fact. Length still comes from the size table and the Step 4 triage. Under ~400 words, or in Teams, or to peers: no headings, no bold section labels, no "TLDR" unless the reply goes to the boss. Write it the way the closest example in `examples/` reads, including its loose sentences and "?" softeners ("See if that buys us some time?").
- **Push back in plain first-person words.** When the stance is a disagreement, say it: "I disagree with <name>'s characterization", "<team> shouldn't have sold it". Never water it down to "I don't think this is ...". Keep the owner's strongest argument (the one that makes the stance hold), even if it is blunt. Push-back stays push-back: no "thanks for jumping on this", "happy to help", "let me know how I can help" or offer of your time in a push-back or routing reply. The one thanks allowed is to a colleague who backed you or gathered the feedback.
- **End on a specific ask or next step**, addressed to a named person ("Could <team> take the lead on <next step>?"). Then only "Thanks!" or "Thanks all!". No stock partnership or "looking forward" sentence. A plan or hand-off ends by handing the lead to the sender's team ("Could <team> take the lead on <next step>?"), not by keeping the next update ourselves. An offer to brief the boss, or any offer of your time, never goes in the reply. Ask it in the chat answer as a question. Never end on "we'll keep you all posted".
- Keep facts exact. The voice never loosens a date, a number or a hedge.
- If a reply will be forwarded outside Diligent, cut shorthand that a customer would not know ("e2e", "D1P" without a gloss).
