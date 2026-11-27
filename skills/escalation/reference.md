<!-- ABOUTME:
  reference.md - overflow detail for the escalation skill (SKILL.md in the same folder).
  Holds the phrasebook, the audience matrix with quotes, the full source ladder,
  the full command set, rule examples as templates, greetings and sign-offs, and conflict notes.
  Quotes of 5+ words come ONLY from golden/extra-cases.md (sent replies that are not test cases); the rest are <slot> templates.
-->

# Escalation skill: reference

**Example phrases are not facts.** Every quote below shows a pattern of voice or structure. Never copy a name, customer, date or claim from it into a new draft. Use a phrase only if the evidence for the new case supports what it says. Text in `<angle brackets>` is a slot you fill from the evidence.

## 1. Phrasebook

### 1.1 Phrases Yu-Kuan uses

| Phrase | When |
|---|---|
| "TLDR" / "TLDR - <the answer>" | Opening line of a boss or record-setting reply over about 100 words |
| "For context, <the stance in one line>." | Opening when the team is blamed and the stance is set |
| "I think ..." | Any hedged opinion |
| "I'd suggest ..." / "I would suggest this approach" | Proposing a plan or approach |
| "My guess is ..." | A hedged cause, followed by an assigned check |
| "In principle, what we can agree to is ..." | Stating the principle behind a stance |
| "<X> is not a <our product>-specific feature; it's a <wider> platform feature." | Redirecting ownership to the real owner (P5) |
| "I think the <team> would be best equipped to lead on ..." | Redirecting ownership softly (P5, P6) |
| "<We> cannot commit to <X> for any 1 specific customer, that's just not scalable." | A scale-limit principle (P18) |
| "We hear you." | Field anger, in place of a concession |
| "Good news" / "good news they may have found a workaround" | Momentum line |
| "partnership" / "really appreciate everyone's partnership on this" | Close to the field or peers |
| "was this escalated earlier?" | A CSM question back |
| "would you mind ..." / "could you please ..." | Every ask to a named person |
| "I'll leave that in your team's hands to do so?" | Handing the next action back |
| "If you're good w/ that we can ..." | A hedged commitment |
| "happy to <x>, if <condition>?" | Only as a question or conditional |
| "let us know?" / "How does that sound?" / "Hope that helps?" / "does that help <name>?" | Last line |
| "We will keep you all posted" | Last line to a wide thread |
| "Thanks all!" / "Thanks team!" / "Thanks a lot!" | Sign-off line |
| "+ @Name" at the very top | Adding people mid-thread, in Teams or email (owner decides who) |
| "I know we all find this sudden news pretty challenging, as do we." | Shared pain, not fault |
| "I'm sorry <one line of sympathy for the person>" | Sympathy to the boss, not fault |

### 1.2 Phrases Yu-Kuan always cuts

These are patterns from first drafts. Each is a bad draft habit, with the rule it breaks.

| Draft phrase | Why |
|---|---|
| "Short version:" / "Here is the short version" | Weak opener (P2) |
| "Here is the plan. <N> files are attached:" | Weak opener (P2) |
| "<X> is fair" / "we own this" / "That is fair feedback" / "This is real." / "Partly fair." | Concession (P3) |
| "That is on me" / "That is ours to fix" / "<N> gaps are mine to own" | Self-blame (P3) |
| A flat offer of a live session or walkthrough | Volunteered time (P9); flag it instead |
| "Ask:" with no named person | Ask with no owner (P10) |
| "What I suggest next" / "What has not moved" / "Where <critic> is off" | Exposes the team or argues with the source (P7, P18) |
| "In <engineer>'s words" | Yu-Kuan is the engineer's manager; let the words stand |
| "<N> separate internal systems confirm this." / "two independent passes" | Method (P14) |
| "I'm glad to run a short session for <team>" / "I will help with it" | Volunteered work (P9) |
| "I would like us to keep this thread on these next steps from here." | Scolding (P11) |
| "Here is the record" / "The record:" / "so we can move forward on facts" | Combative framing (P18) |
| "Facts to check before sending" table / "Notes for Yu-Kuan" inside the reply | Internal notes leak into the reply (P12) |
| "<engineer>, if engineering says no, please tell us today." | Demand on own team in front of the field (P7) |
| "<N> releases must go live" / PR numbers / "waiting for code review" | Internal mechanics to the field (P13) |
| "most of <the critic's themes> are already fixed" | Counter-headline (P18, P3 note) |
| "this is not a legal or security blocker" | A legal conclusion Product cannot make (checklist row 10) |
| "going forward, decisions like this will go through you first" | A new gate promised to another team (P4) |
| "<the customer's board / CEO> is putting pressure on all of us" | Restated pressure in line 1 (P2) |

## 2. Audience matrix with quotes

Field replies may be forwarded, so write them as if a customer could see them.

| Audience | How the voice changes | Example quotes or templates |
|---|---|---|
| Customer exec (via the field) | Outcomes and dates only. No internals. Upbeat. | "Lots shipping lately: <item 1>, <item 2> and <item 3>." |
| Field seller or sales leader | Momentum first, unless the team is blamed. Hedged dates. Hands the lead back. Partnership close. May push back on the field's approach (owner decides how hard). | "AE/CSM needs to assume that responsibility."; "I'll leave that in your team's hands to do so?"; "really appreciate everyone's partnership on this" |
| CSM or CS leader | Asks questions back. Names a customer-side cause. Routes to T2. Offers a workaround. Warm thanks. | "was this escalated earlier?"; "Have they taken our workaround advice to start archiving their books & mtgs?"; "could you let the teams to use the existing T2 escalation process?" |
| Own team (eng, PMs) | Direct asks with "would you mind". Pointed questions on scope and dates. Tradeoffs and a deadline with slack. | "Please make sure Dan & I know before you end the week?"; "let us know what the competition tradeoffs are"; "As long as we ship it before Dec 30 I think we're good." |
| Boss or execs (CEO, GM, CFO) | Thanks, sympathy, team-level ownership, a TLDR with the stance in one or two numbered lines, then each point, then next steps. Momentum, hedged dates. To their own GM, Yu-Kuan can be blunt about a third party. | "Thanks for sharing <the feedback>, I'm sorry <sympathy>. Our team owns <the experience>." then "<X> is much better than <period> ago, and there's more to do on <Y>." |
| Legal or security | Thanks first. Mitigations in flight, each with a named owner and a status. Point to the security doc in flight. Cite Legal's decision; never state your own legal view. Receipts only when blamed. The risk-points reframe only after a second push. | "Per legal's decision above, no extra opt-in is needed since their current terms already cover our doing this"; second push only: "you're now raising not security blockers, but really good risk management points right?" |
| Peer director (PMM, PM, other BU) | Clarify the record with links and the peer's own words. Plan last, credited to own team. Caution on headlines. An offer to brief the boss is flagged, not written. | "To clarify <the decision>, here are the links."; "I'd back <own team member>'s plan: <steps>."; flagged offer: "if it helps to explain this to <boss>, happy to." |

## 3. Source ladder (full)

| Claim type | Strongest source | Weaker sources |
|---|---|---|
| Is the feature built? | Code on the PR branch, read in full | The PR diff alone, then Jira scope text |
| Is it merged? | `gh pr view` state and `mergedAt` | Jira status, an engineer's message |
| Is it in the release? | Git tag compare against the merge commit | Jira `fixVersion` |
| Is it live for users? | App Store version and date, or the deploy record | Jira `released` flag (nobody may have ticked it), an email that says "out now" |
| Is it tested? | A tester's Jira comment, plus the PR's own test notes | A Teams claim of "final testing" |
| When will it ship? | Jira release plan, plus every upstream release it needs | One engineer's Teams message |
| What did a person say? | The original message, opened and quoted, with its link | Glean AI summary, an agent's summary |
| A disputed incident detail | The later, first-hand message (quote both) | An earlier "allegedly" |
| How was a change rolled out? | The latest rollout mail with its site list | The first notice, a single Jira ticket |
| How many users? | A usage query you ran, split by version | A lane note, a Glean AI number |
| Is it a bug? | The ticket's type, body and comments | The ticket's title (a test-run ticket is not a bug) |
| Why did a customer leave? | The customer's words in Gong or Gainsight | A CSM loss-reason field |
| Is it legally allowed? | A Legal message or decision, opened, with link | Product's own reading of a contract |

Rules on top of the table:
- When Yu-Kuan's claim and the evidence disagree, the evidence wins. Say so plainly, before the draft.
- When an engineer's claim and the code disagree, the code wins. Check the right epic before you say no work exists.
- Glean search hits are leads only. Glean `--read` often returns titles only. Use the Atlassian REST API for page text.
- Do not be firmer than the accountable engineer or PM. When they differ, use the later, softer date. Yu-Kuan may go softer.

## 4. Commands (full)

Every Atlassian call (`-u ...` below means `-u yklin@diligent.com:$ATLASSIAN_API_TOKEN`) runs inside `bash -c 'source ~/.zshrc 2>/dev/null; ...'` so the token loads.

| Need | Command |
|---|---|
| Graph token | `node ~/Code/pm_os/bin/ensure-tokens.js --no-browser` (exit 4 means MFA: `/pm-login`) |
| Glean auth | `glean auth status` (fail: `/glean-connect`) |
| Atlassian auth | `bash -c 'source ~/.zshrc 2>/dev/null; curl -sf -o /dev/null -w "%{http_code}" -u yklin@diligent.com:$ATLASSIAN_API_TOKEN "https://diligentbrands.atlassian.net/rest/api/3/myself"'` (not 200: `/atlassian-connect`) |
| GitHub auth | `gh auth status` |
| Salesforce auth | `~/.claude/skills/salesforce-connect/bin/salesforce connect` |
| Teams thread | `node ~/.claude/skills/pm-search/scripts/search-all.js thread --ref '<teams link>' --max-messages 60` |
| Mail by subject | `node ~/.claude/skills/pm-search/scripts/search-all.js search --q 'subject:"<subject>"' --sources graph --types mail --since 30d --limit 10` |
| Mail thread | `node ~/.claude/skills/pm-search/scripts/search-all.js thread --ref 'mail:<convId>\|<msgId>' --max-messages 50` |
| Teams chat in full | `node ~/.claude/skills/pm-search/scripts/search-all.js thread --ref 'chat:<chatId>\|<messageId>' --max-messages 200` |
| Teams channels | Find threads with `--sources glean`, then `thread --ref <glean teams URL>`. Graph can miss a channel that Glean finds. |
| Topic search, org-wide | `node ~/.claude/skills/pm-search/scripts/search-all.js search --q "<topic>" --sources glean --types mail,teams --limit 10` |
| Topic search, depth | `node ~/.claude/skills/pm-search/scripts/search-all.js search --q "<topic>" --sources graph --types mail,teams --since 90d --all --group thread --exclude-own` |
| Prior work | `rtk proxy grep -ril -e "<topic>" -e "<customer>" ~/Code/PM/docs/firedrills ~/Code/PM/amanda/firedrills ~/Code/PM/docs` |
| Jira issue | `curl -sf -u ... "https://diligentbrands.atlassian.net/rest/api/3/issue/<KEY>?fields=summary,status,fixVersions,resolutiondate,description,comment,issuelinks"`. Read raw `fields.description`; `renderedFields` can be empty. |
| Jira search | `curl -s -G -u ... "https://diligentbrands.atlassian.net/rest/api/3/search/jql" --data-urlencode 'jql=<JQL>' --data-urlencode 'fields=summary,status,created,resolutiondate,fixVersions'` |
| Jira release versions | `curl -s -u ... "https://diligentbrands.atlassian.net/rest/api/3/project/<PROJECT>/versions"` |
| Confluence page | `curl -sf -u ... "https://diligentbrands.atlassian.net/wiki/rest/api/content/<PAGE_ID>?expand=body.storage,version"` |
| Confluence search | `curl -sf -u ... "https://diligentbrands.atlassian.net/wiki/rest/api/content/search?cql=type=page+and+text~\"<term>\"&limit=10"` |
| Glean full document | `glean documents get --json '{"documentSpecs":[{"url":"<url>"}],"includeFields":["DOCUMENT_CONTENT"]}'` |
| Glean lead (AI answer) | `node ~/Code/pm_os/bin/glean-search.js --chat "<question>"`. A lead only; open and quote the real message. |
| Gong via Glean | `node ~/Code/pm_os/bin/glean-search.js -q "<customer>" -d gong` |
| PRs for a ticket | `gh search prs "<JIRA-KEY>" --owner DiligentCorp --limit 15 --json repository,number,title,state,updatedAt` |
| PR state | `gh pr view <N> -R DiligentCorp/<repo> --json title,state,isDraft,mergedAt,baseRefName,reviewDecision,reviews,files,body` |
| PR diff | `gh pr diff <N> -R DiligentCorp/<repo>` |
| Code read | `gh repo clone DiligentCorp/<repo> -- --filter=blob:none`, `git checkout <branch>`, `git grep -nE "<symbol>"` |
| Fix in release | `gh api "repos/DiligentCorp/<repo>/compare/<merge-sha>...<release-tag>" -q '.status'` |
| iOS live version | `curl -s "https://itunes.apple.com/search?term=diligent+boards&entity=software&country=us&limit=5" \| jq -r '.results[] \| [.trackName,.version,.currentVersionReleaseDate] \| @tsv'` |
| Salesforce deal | `mcp__salesforce__run_soql_query`: `SELECT Name, Account.Name, StageName, CloseDate, Amount FROM Opportunity WHERE Account.Name LIKE '%<customer>%'` |
| Salesforce site and pod | `mcp__salesforce__run_soql_query`: `SELECT Name, Site_URL__c, Production_Environment__c FROM Site__c WHERE Account__c IN (SELECT Id FROM Account WHERE Name LIKE '%<customer>%')` |
| Salesforce Knowledge (reader can open) | `export PATH=/opt/homebrew/opt/node@24/bin:$PATH; npx --yes @salesforce/cli data query -o diligent --query "SELECT Title, UrlName, LastPublishedDate, IsVisibleInPkb, IsVisibleInCsp FROM Knowledge__kav WHERE PublishStatus='Online' AND Title LIKE '%<topic>%'" --json` |
| Timeline from a thread | `jq -r '.results[].messages[] \| [.date, (.from \| if type=="object" then .name else . end), (.text \| .[0:200])] \| @tsv' <thread>.json` |

**`search-all.js` traps (live test, 11/27/26).**
- `--to` alone returns nothing. Always pass `--from` with `--to`.
- `--to` covers the whole day. Drop hits that come after the inbound message's time by hand.
- `thread --ref` starts at the anchor message. To get earlier messages, fetch again with an older anchor.
- `--group thread` drops the snippets. Use plain hits when you need the text.

**As-of-date reads.** The research is dated to the escalation day, not today.
- Jira: `curl -sf -u ... "https://diligentbrands.atlassian.net/rest/api/3/issue/<KEY>/changelog"`. Rebuild the description and status as of that day.
- GitHub, when a branch fetch fails: `gh api "repos/DiligentCorp/<repo>/commits?sha=<branch>&until=<date>"`.

Pod to region (Confluence "Site Location Code"): PROD01 Canada, PROD02 US, PROD03 Germany, PROD04 Australia, PROD05 UK. A short site name is the URL path segment, lower case.

## 5. Rule examples: bad draft pattern vs better pattern

"Bad" is a first-draft habit. "Better" is a template or a quote from `extra-cases.md`. Fill every slot from the new case's evidence, or leave the line out.

| Rule | Bad draft pattern | Better pattern |
|---|---|---|
| P18 | A numbered list of each safeguard, or of each gap | "I think there's a tradeoff between <capability> and <control>. If we <ban X>, we lose <Y>. I'd suggest we agree on <what truly matters> first, and act on that?" |
| P18 | A counter-headline ("the real cause is <Z>") | "I'd be careful about the conclusions we draw from <the data> until <the further check>." |
| P18 | Reasons with no conclusion | One closing paragraph: "So the bottom line is <principle>. <Why the alternative cannot work>." |
| P3 | "<customer>'s frustration is fair; we take full blame." | "We hear you." then the work under way |
| P3 to the boss | "Nearly all of these are fixed already." | "The team owns <the experience>. <X> is much better now, and there's more to do on <Y>." |
| P14 | "I pulled <the source>, reconciled it, then mined <tools>" | "Here's the analysis, let's discuss?" |
| P2 | "Short version: <X> worked." | "TLDR - <X> worked, but with <the problems the boss asked about>." |
| P2 | Line 1 answers the first ask on the thread | Line 1 answers the latest message from the most senior person |
| P8 | "By <date>, I will bring you a choice." | "Once <milestone> is done, we'd aim to come back with a recommendation, maybe around <later month>." |
| P8 | "We are targeting <the requester's deadline>." | "<The step the source names> is under way; we're targeting <the source's own hedge, or no date>." |
| P15 | "A <feature>." | "A brand new <feature> - <what it does for the customer>." (only when true and the stance allows) |
| P1 | A long rebuttal in the body | A cover note under 100 words, with the analysis attached |
| P1 | One line per complaint in a point-by-point reply | One short paragraph per complaint: the fix, its date, what it means for the user, the help article |
| P7 | "The <team> has closed no bugs since <date>." | "Our <testing> hasn't been as complete as it should be, and we're fixing that now." |
| P7 | "The UX wasn't polished." | "The team had already designed <the fix>, but it did not ship before <the event>. It's done now." (only if the pack shows it) |
| P9 | "I'll run a session for the team." | "Could your teams lean on <the existing source>? Really appreciate the partnership." |
| P9 hand-off | "I presume you'll lead from here?" alone | `Actions:` then "<Name> - <action>" per line, own team included |
| P5 | "<Gap> is mine to own." | "<X> is not a <product>-specific feature; it's a <platform> feature, and I think <team> is best equipped to lead on it." |
| P6 | "The <team>'s script is wrong." | "I'm wondering if <team>'s <script> has fallen behind - it still says <exact line>." |
| P17 | "They never told us." | "Nothing in writing before <date> set <requirement> (<link>)." then <what the pack shows was already under way by that date> (only if the pack dates both) |
| P4 | "Going forward, decisions like this go through you first." | "There are lessons here for the team, and we'll retro it." |
| P16 | (no line) | "If they still see <problem> after <fix>, would you mind routing it through the existing T2 escalation process?" |
| P10 | "Ask: the CSM checks <setting>." | "@<name> could the CSM check <setting> on <site>?" |
| P11 | A flat offer of a live session | Flag in chat: "Offer a live walkthrough once <X> is ready, as a question? Default: left out." |
| P12 | A "Links" list at the bottom | The link inline on the claim: "<What it is> is public here<link>." |
| P13 | "It is waiting for code review." | "Final testing is under way." |
| P20 | An email-style memo in a Teams chat | Chat prose, "+ <Name> -" on top if someone is added, no sign-off |

## 6. Greetings and sign-offs

| Case | Greeting | Sign-off |
|---|---|---|
| Teams chat | "Hi <sender>," or "Hi team," for a worry raised in a group | None |
| Email to the CEO or the CISO | VOICE greeting rule ("Hey <name>," when they alone are on To) | "Yu-Kuan" |
| Short cover note to a peer (under 100 words) | "Hi <sender>," plus thanks for their work | "YL" |
| Long point-by-point email | "Hi <sender>," | "Thanks," then "YL" |
| Formal plan hand-off to a wide list | "Hi all," | "Yu-Kuan" |
| Any other email | "Hi <sender>," | "Thanks all!" then "YL" on a wide thread; else "YL" |

- One person on To: greet them. Two on To: greet both, or open with the name of the one you answer. Three or more on To, or a group chat: "Hi all," / "Hi team," / "Hey everyone,". Credit their work, not the meeting.
- When you add people mid-thread, open with a "+ <Name>" line in Teams or email. In email, also add them to Cc.
- A reply on a hot thread that opens with a receipt has no greeting.

## 7. Conflict notes (from rounds 1 and 2)

| Conflict | Resolution |
|---|---|
| Owner framing vs the soft defaults (P6, "push back softly") | Owner framing wins. If the ask names who is at fault, state it flat. |
| Owner framing vs a legal or security conclusion | The framing sets the stance. The reply cites Legal's or Security's own words, or holds mitigations only. |
| Owner framing vs the length band | An owner word limit wins. |
| P3 (no self-blame) + P15 (upside first) to the boss | Own the experience at team level, then say what improved and what is still left. No counter-headline. |
| P9 (no volunteering) vs P11 (offer as a question) | The offer leaves the reply and goes to the chat answer as a flag. It never vanishes. |
| P8 (dates) vs P15 (momentum) | P8 wins on every date and date word. |
| P15 vs a "never supported" or "not our scope" stance | Skip momentum, or show past fixes as best-effort favours, never as a delivery track. |
| P17 (receipts) vs a first reply to a risk flag | Receipts wait until someone blames the team. |
| Audience row "numbered mitigations" vs P20 in Teams | P20 wins: chat prose, short. |
| P6 softening vs an owner-only "leave out" | The owner-only default wins: no softened line. |
| A critic's list as the agenda vs P18 "no list of gaps" | Sort the list: complaints get one point each with the fix; wishes go in the upside with the roadmap item. |
| A falling bad number: momentum or weak spot? | Momentum, plus "it will never reach zero, because <reason>" when true. |
| Owner-only "leave out" vs a point the thread raised (round 2) | The raised point stays in, in its safest true form, and is flagged. "Leave out" covers only items nobody raised. A drafter who flags a raised point and also cuts it loses the point. |
| False owner premise vs the point it sits in | Cut only the false part. Write the narrowest version the record proves, with the P17 template. |
| An unconfirmed fact vs the point around it | Cut the fact, keep the point. Asking a named person to check the fact is allowed. |
| The owner's own guess vs "facts not confirmed" | The owner's stated guess is stance: hedged ("My guess is", "likely"), flagged, never written as fact. A drafter's own guess is still cut. |
| Two sources give different counts | Use the floor, or the count the pack calls verified. Flag the choice. Never drop every count. |
| A principle paragraph vs a status or complaint-list reply | Write a principle only when the stance needs an argument. One that fits a single point goes inside that point. An extra principle paragraph adds claims the owner never makes. |
| "Next steps" to the boss vs P14 (no internal meetings) | Keep the block. It holds outcomes, decided plans with the pack's hedged dates, and the boss's own deadline. Team meeting dates stay out. |
| A gap vs P7 (protect own team) | A gap goes in only beside the plan that closes it ("<X> is not yet covered; the plan closes it by priority"). Never a quote that blames a person or team. |
| Length vs a wide To list or a short example | Length is the number of Answer points times the depth per point (SKILL.md Step 4 triage). Route and Push back points take one line. A wide To list never shrinks an Answer point. |

## Audience tiers

Set the tier from To and Cc. The highest tier present wins: `board` (an @insightpartners.com address) > `ceo` (Brian Stafford) > `elt` (an exec such as a GM, the CFO, the CISO, the GC, Anmol, Amanda, Jeff or Peter) > `peers` (no exec). The tier sets the register. §2 (audience matrix) still sets the voice for the addressee's role, and §6 still sets greetings. Owner framing beats both. Full study with quotes: `docs/firedrills/escalation-skill/audience-tiers.md` in the PM repo.

At `ceo`, check who the reply speaks to. Brian as the addressee and Brian as a bystander read differently.

| Dimension | board (1 case: lead only) | ceo, Brian addressed | ceo, Brian bystander | elt | peers (2 cases: lead only) |
|---|---|---|---|---|---|
| Sign-off (the greeting always follows the SKILL.md VOICE greeting rule) | "Hope that helps," then "Yu-Kuan" | "Yu-Kuan" | "YL" | mostly "YL" | Teams: none / mail: "Thanks, YL" |
| Length (a ceiling; the reply-type size in SKILL.md wins) | 50-250 words | 350-850 words | 115-820 words | 50-400 words | 50-150 words |
| Structure | Numbered findings, then workaround steps | TLDR, headings, tables or bullets, "Next steps" | Numbered points, no TLDR | Numbered points or prose | One or two short paragraphs |
| Evidence | Facts about the person's own case | Shipped fixes with dates, trend numbers | Versions, links, the peer's own words | Receipts only when blamed; else terse | None; routing only |
| Blame | None; a user-side cause as a soft question | Third party, hedged; own team defended by name | Field habits, cushioned | Flat, by name (a seller, a vendor) | Flat, at the sender's process |
| Admission | None | Team level, with the plan beside it | Light | Can be personal: a lesson for Yu-Kuan and the team | None |
| Dates | None | Exact mm/dd; hedges as "?" or "likely" | Shipped dates exact; future hedged | "targeted", "aiming for", quarters | None |
| Close | A check-in question | Offer to walk through it, or commit to his deadline | Partnership; named asks to the field | @mention routing; "Thanks all!" | Point to the process or ticket |
| Never | Internal names, team blame, roadmap, dates | A "what has not moved" section; blame on own eng; brief-style prose | Volunteered work for the team | A legal view of Product's own | Momentum lists, apologies |

Example moves (paraphrased, not quotes):
- **board.** Open by checking whether the problem is still there. Give what the logs show about their own attempts. Ask gently if a saved password might be stale. Give a step-by-step workaround with a screenshot.
- **board.** Name no internal team or person, and give no roadmap or date.
- **ceo, addressed.** Line 1 is a TLDR: it worked, with rough edges, and both fixes are done. Then "What happened", "Changes in motion", "Next steps" with mm/dd dates.
- **ceo, addressed.** Say sorry he was caught off guard, and that the team owns the experience. Show a gap as a coverage number plus the plan, never as a person's fault.
- **ceo, bystander.** Thank the sender and the team by name. Put the root cause on the vendor limit in one line. Ask the field politely to learn the shipped fixes, and close on partnership.
- **ceo, bystander.** Offer, as a question, to explain the decision to Brian if needed.
- **elt.** To a GM about a seller: say plainly that product is not at fault and the deal should not have been sold. Back it with dated links.
- **elt.** To legal or security: thank them, list each mitigation with an owner and a status. If blamed, show the written approvals, then admit the comms could have been stronger.
- **peers.** Say in two sentences that this is not your team's product, and send them to the support process.
- **peers.** Or thank them, say you did not know, and ask a named engineer to explore options.

Bluntness is not a straight line: gentlest at board, cushioned at ceo, flat at elt and peers.
