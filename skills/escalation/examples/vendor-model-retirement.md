# vendor-model-retirement

```yaml
audience: field seller
reply_type: push-back
channel: mail
words: 387
```

## Situation

A cloud vendor retires AI models in <region> with short notice.
The strategic accounts sales lead asks why Diligent got under <n> days of notice. He says it looks like poor planning.
He also wants customer-facing documents on the fix (CRIS).

## Sent

### A. <date>

`````text
Hi everyone,


  1.
I know we all find this sudden news pretty challenging, as do we. To be honest, the entire product team only found out about this < <n>hrs ago because our <vendor 2> rep only told us this late night <date> so we are scrambling as hard as you are to react to this, and building replacements, CRIS etc. We don’t like it any more than you do either, so really appreciate everyone rallying around this.
  2.
@<sales VP> - totally agree and product team is happy to help with customer-facing documentation on CRIS. However, CRIS is not a Boards-specific feature; it’s a Diligent-wide platform feature. Boards is at best an UI wrapper and I think the platform team would be best equipped to lead on providing the architecture diagrams, technical FAQs, etc on how CRIS works for our customers. We (Boards) don’t know how CRIS works, so we unfortunately can’t help here. @<platform lead> @<platform lead 2> might you be able to help with this?
     *
Once they have provided the main parts, @<PM> and the boards team will be happy to add any Boards specific bits if helpful.
  3.
On the sales comms and other things that <sales exec> asked for, I am not sure who typically prepares these sales comms (GTMR? ), but I think once #2 is done someone can probably easily Claude it and turn it into comms packs for review, etc.

Lastly, I’d suggest we should absolutely make clear to all our customers that this is no fault of Diligent’s; <vendor> and <vendor 2> pulled the rug on us and we’re not the only company scrambling, so we should make this clear in our talk track to customers in some way.

Again, really appreciate everyone’s partnership on this, we’ll get through this together. Thanks all!

YL
`````

### B. <date> (to another asker)

`````text
Hi <field seller>,

Re: all your questions - @<platform lead 2> and his platform team would be the overall project leader for the entire CRIS rollout, since it impacts not only Boards but all Diligent products.

There’s already a few very active threads coordinating this response with documentation, FAQs etc including this one <link> which I believe you are in. I think searching there would be the best way to get your answers, and if you could share back w/ the GTMR team that’d be great.

Thanks!
YL
`````

## Why it works

- He opens with shared pain: "we are scrambling as hard as you are". Then he gives the fact: the vendor told product under <n> hours before.
- He agrees with the ask ("totally agree"), then redirects it: CRIS is a platform feature, so the platform team leads.
- He admits a limit plainly: "We (Boards) don't know how CRIS works".
- He suggests a talk track that puts the fault on the vendor: "this is no fault of Diligent's".
- The follow-up names the project lead and points to an existing thread to search.
- He closes with "we'll get through this together".
