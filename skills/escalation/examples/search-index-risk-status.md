# search-index-risk-status

```yaml
audience: legal-security
reply_type: holding reply
channel: mail
words: 409
```

## Situation

The CISO warns <exec> that board data for about <n> GovernAI clients is now indexed in AWS.
She says this conflicts with what clients were told. Legal, Security and the account lead are on the thread.
Yu-Kuan answers the same evening.

## Sent

### Reply 1, <date>

`````text
Hi <CISO>,

Thanks for raising this early, and we are actively working with @<security lead> and the team to mitigate the customer expectation and communication risks that you raised. We will keep everyone posted.

To provide a bit more details, here are all the things in flight to mitigation the customer expectation & communication risks -

  1.  Updated email comms that explain to customers our change in indexing - have shared w/ <security lead>, <GC>, and <legal counsel> for review. So far they are good w/ it.
  2.  In-product educational UX - same as above.
  3.  Updated AI FAQ in our Help Center - that will include a section on how search indexing & AGAI will work as well as removing stale content that don't apply any longer. This will help with any inbound customer questions. <GC> & <security lead> are final reviewing it now.
  4.  Updated Boards security documentation - @<VP eng> & team are working through this. Regarding your concern that there might be more risk due to Diligent employee's access model on AWS. My prelim guess is that our products should be just as secure on AWS as they were on private cloud (otherwise we'd have far, far larger issues), but I'll ask <VP eng>, <eng lead> to connect w/ <security lead> and truly verify this and report back.
  5.  Working with <sales VP> to determine if any strategic accounts need special handling & communications - we're in touch w/ <sales VP> and waiting for his response to see which accounts might need special communications and collaborating w/ his team on it.
  6.  Fixing the problematic company list - Legal team is investigating the data issues that caused our original indexing list to be incorrect, and also identify any contracts that may have clauses on <contract term>, not just limited to AI or AWS. We will then collaborate on any communications or index deletions as needed.

1-4 will be done before <date> (we're aiming for next Mon), and #5 is in progress. On #5, our very preliminary analysis show that likely fewer than < <n> companies from strategic accounts were indexed, and the big <customer> was not amongst them. So any customer handling or comms should be reasonably scoped & contained. But still we'll do a full check with <sales VP>'s team and report back.

Please let us know if you have any other questions, and we appreciate all your partnership.

Yu-Kuan
`````

## Why it works

- He thanks her for "raising this early" and recasts the issue as a customer expectation and communication risk, not a breach.
- He lists six workstreams already in flight, each with an owner and a status. This shows control.
- He answers her access-model worry with a hedged guess ("My prelim guess") and a promise to verify.
- He sizes the impact with a number: "fewer than < <n> companies" from strategic accounts, and the biggest customer was not one.
- He gives a date ("before <date>") and closes with "we appreciate all your partnership".
