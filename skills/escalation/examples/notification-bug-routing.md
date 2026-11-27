# notification-bug-routing

```yaml
audience: own team
reply_type: plan hand-off
channel: mail
words: 253
```

## Situation

The GM asks Yu-Kuan for the lift to fix a sporadic notification bug that one customer hit.
The customer's report had sat in email with no answer.
Yu-Kuan assigns the work and points the field at the T2 process.

## Sent

### A. <date>

`````text
Hi @<eng lead> would you mind triaging this and assigning it to the right person on the Foundations team, and give an estimate on when we might be able to fix it? I know we recently discovered a root cause and fix related to unreliable email for <customer 2>, do you think/know if it might be related?

@<field seller> - while you’re in <city> would you mind perhaps arranging a time where their technical team and ours can connect for some troubleshooting? The challenge with this is that it’s sporadic and only for a single customer, so it’s hard to chase down. Joint troubleshooting might be able to speed this up.

@<sales VP> would you mind passing the word onto the team - In the future, if a high priority customer has an issue that we haven’t responded to esp one that’s like a bug, could you let the teams to use the existing T2 escalation process? We look at those T2 high prio bugs every week, so you’re guaranteed to get a response and might work better than email which sometimes get lost.

Thanks a lot!
YL
`````

### B. <date> (to the GM)

`````text
Hi <GM>, here’s the Boards T2 Escalation process <link>. I believe it’s pretty similar to Entities?

Once we receive a T2 ticket, we have an internal team that triages and provides a response with an SLA of < <n> wk so at most the customer gets an answer within a week. If it’s more urgent we’ll respond even faster.
`````

### C. <date>

`````text
Thank you @<sales VP> and everyone, really appreciate it!
`````

## Why it works

- He gives each person one task by @-mention: triage, joint troubleshooting, and passing the word.
- He links the bug to a known root cause at another customer. That shows product is already close.
- He explains why it is slow without blame: "sporadic and only for a single customer".
- He uses the case to teach the process: high-priority bugs go through T2, not email.
- The follow-up to the GM gives the SLA in one number (under <n> week) and a link.
- He closes with warm thanks.
