# upgrade-failure-ceo-status

```yaml
audience: boss or exec
reply_type: status to boss
channel: mail
words: 346
```

## Situation

The CEO asks for detail on the yellow risks in an upgrade program update.
One risk: the migration screen said "failed" while the upgrade still ran. It also took hours.
The VP of Design asks to be copied.

## Sent

### <date>

`````text
Hi <CEO>,

The TLDR here is the <site> upgrade worked, but with some rough edges as <director> pointed out. The screen told <admin> it had failed while the upgrade was still running in the background, and it took a lot longer than expected. Both of these fixes are done already.

What happened

  *   The upgrade progressed & finished, but the screen said "failed." The tool hit a temporary error and kept retrying on its own, but we hadn’t shipped our fault-tolerant error handling UX at that point, so the admin saw "failed" instead of "in progress." It’s done now.

  *   This was not a miss by the UX team. The team have been focused hard on the technical upgrade problems, and the designers had already prepared these UX fixes, including the corrected message, but just did not ship in time before the test.

  *   The upgrade was also too slow. We hit some AWS infra issues that stretched it to hours, but it’s been since resolved. In our own test, the same site took <n> to <n> minutes and we’d expect similar performance if we run it again.

Changes already in motion

  *   One end-to-end design, signed off by <design VP>, Yu-Kuan, and <eng lead>. A working prototype covers the full journey: multi-site login, mobile, the upgrade and onboarding to make sure we provide a positive, confidence experience for customers even when encountering any issues.

  *   A brand new, <n>-day preview mode with sample data. We listened to customer feedback and added a whole new “Preview with sample data” test phase that was highly requested & welcomed by customers.

  *   Background test runs before the real upgrade. We are also checking if we can run each upgrade quietly ahead of time. Then we find and fix problems before the customer ever sees them.

Next steps

  *   Go/no-go: a first call on <date>, then the first customer invite on <date>.

  *   Prototype review with <design VP> by <date>.

Once we have the e2e experience ready we're also happy to walk you through it live again, let us know?

Yu-Kuan
`````

## Why it works

- "The TLDR here is" leads with success, then the rough edges, in the escalator's own words.
- He says "Both of these fixes are done already" in the first paragraph.
- He protects the design team: "This was not a miss by the UX team."
- Three headings: what happened, changes already in motion, next steps. Each bullet is short.
- He gives proof numbers (<n> to <n> minutes on a re-run) and dates (<date>, <date>, <date>).
- He closes with an offer to walk the CEO through it again, as a question.
