# login-ceo-update

```yaml
audience: boss or exec
reply_type: status to boss
channel: mail
words: 849
```

## Situation

The CEO cold-emailed another company's CEO, who agreed to help only if login gets easier.
<exec> says the fix must be systemic.
Yu-Kuan sends a status update to the CEO, <exec> and the GM, then a short note to his own team.

## Sent

### <date> (reply-all, login team added)

`````text
+ <eng lead> and the login team -

Hey everyone,

Quick update on director login on since my last <date> note. I think <exec>’s general take on we need to solve this more systemically is head-on, we’re tackling that right now. Re: <customer> I think it’s likely due to an unfortunately gap, where they were placed on some exception list for self-pwd reset rollout, so never got the functionality turned on for them.

TLDR

  1.  Systematic testing & fixing - we have shipped a lot of login fixes but our testing haven’t been as systematic in its e2e coverage, which is what we’re addressing now. On the fixes front - <n>+ login fixes this year - <n> since <date>, and <n> of them since <date>. iOS <version> went live on <date> with the offline Face ID fix.

  2.
<customer> - most likely cause is his password expired due to internal company policy. He should’ve been able to self-reset after our MFW pwd reset launch in <date>, but <customer> was left off somehow likely due to an CSM exception list or something, so they don’t have it turned on. Next step would be to ask CSM/CS to take this over, double check and get them to turn it on.

What shipped since <date>

  *
iOS
     *
iOS <version> (<date>). Face ID now keeps working longer when a director is offline, so fewer surprise password prompts. <version> also brings AGAI to iPhone and iPad. In <version> we added Directors no longer have to redo Face ID after switching between boards with MFA
     *
SSO directors on iOS no longer see a wrong MFA warning.
  *
Web
     *
Fewer surprise logouts on the web. Users without admin roles are no longer logged out by mistake (released <date>). An approval export no longer logs users out (<date>).
     *
Clearer sign-in screens. MFA options now show in the user's chosen language, not always English .
     *
New Boards platform. Two sign-in fixes, including one that stops director-only users from seeing admin menus during sign-in (<date> and <date>).
     *
Another reported timeout problem is closed (<date>).
  *
TLDR - we’ve shipped <n> login, MFA and password fixes from <date> to <date> (e.g. admins no longer need a phone number to create a user), and added the above in the last couple of months.

What's in progress

  *
Better login tracking (in testing). Today, when a sign-in fails before the user gets in, we can't see why at all due to historical reticence on logging. This will change and help us get more proactive.
     *   Once it ships, our regular reporting can split customer security settings from our own bugs and can proactively address issues before they’re reported.
  *
Login tests built around real director journeys. Today, none of our <n> core login scenarios (SSO, MFA, switching boards, security policies) has a full end-to-end automated test; only password reset is mostly covered (<n> of <n>). Very early estimates show we only have maybe ~<n>% coverage today? We're closing the gap with a <n>-case test plan ranked by priority asap, starting with the P0 cases.
     *
The team mapped <n> journeys, such as SSO, MFA, switching boards, email links and security policies.
  *
<quarter> - Magic link sign-in on Diligent One Platform. Users can sign in with a one-time email link instead of a password.
  *
A weekly login status email to you, <exec> and <GM>. I think we’ve been so heads down on the work that we didn’t provide enough viz. Starting next week we’ll ask the team to provide weekly update emails on this, similar to other key projects like AGAI and <project>.

<director> (<customer>). We checked his account. He uses classic Boards on one site. Support has helped him sign in <n> times since <date>.

  *
The <n> most recent problems were account lockouts due to expired passwords where his assistant, those are set by their own pwd expiry policy windows. His EA <EA> called in.
  *
The MFA pwd self-reset feature we shipped in <date> should have solved this - in fact <support lead> has just told us yesterday his support queue wait on pwd resets have dropped from hours to ~< <n> secs, thanks to self pwd resets, so self pwd resets is clearly working.
  *
However, <customer>'s site was somehow excluded, so they don’t have self pwd reset turned on, and probably why he had to call in. We're checking why. My best guess is because the CSM may have accidentally put them on an exception list, or didn’t educate them that they had put themselves on an old exception list but  should move to self pwd reset
  *
We’ll ask Support & CSM to take over specifically on working with <customer> so they can get this debugged and turned on.

And yes we’ll aim to fix everything as much as we can before the <date> board meeting.

Yu-Kuan
`````

### <date> (forward to the login team)

`````text
Hi team, I’m going to forward you some examples of weekly project update emails. Could you use those as a reference to write our weekly login update emails for ELT? Thanks!
`````

## Why it works

- He opens by agreeing with <exec>'s "systemic" take, then gives a one-line cause for the customer case.
- The TLDR admits a real gap in plain words: testing "haven't been as systematic in its e2e coverage".
- He backs the effort with counts: <n>+ fixes this year, <n> since <date>, <n> since <date>.
- He gives honest coverage numbers with a hedge ("maybe ~<n>% coverage today?").
- He points the customer's cause at a CSM exception list and hands the fix to Support and CSM.
- He adds a weekly status email to the CEO and ends with a commitment tied to the customer's board date.
