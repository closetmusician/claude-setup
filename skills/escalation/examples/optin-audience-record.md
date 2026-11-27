# optin-audience-record

```yaml
audience: peer exec
reply_type: record-setting
channel: mail
words: 586
```

## Situation

A Senior Director of product asks why product did not show an opt-in only to private companies.
The CEO is on the thread.
Yu-Kuan replies to all with a dated record and links.

## Sent

### <date> (reply-all)

`````text
Hi all,

I'd like to clarify the the situation on peer checkbox from public companies, with some references so we can all clear on the situation.

1. There was no clear written, private-only audience requirements to the Boards team in the beginning. None of the opt-in chat messages from <date> onward limited the audience (chat <link>), and the eng work had already started in back in <date>.

2. The request to limit showing the opt-in only to private companies came to us very late, on <date>, <n> daysbefore launch, and <eng lead> had immediately already responded that this was not possible. Instead he proposed a fallback which is we filter for private companies on the backend that was confirmed.

  1.  On <date>, <peer exec> wrote: "we don't want to surface the opt-in to public companies, at all" (chat <link>), and <eng lead> answered the same day - "we don't have the ability to target public companies easily in the UI". Boards doesn't have any record of which companies are public vs private today, and it's not.
  2.  <eng lead> proposed we "look them up and then not process the data in the back end" (chat <link>, chat <link>). On <date> <peer exec> confirmed "Live on <date>. All Boards Classic customers" (chat <link>, chat <link>). The label reads "for private companies", as <CEO> asked on <date> (chat <link>).

5. Bigger picture - Attempting to filter for private vs public companies is not really feasible and would be error prone no matter how we try.

  *   No reliable source. Boards stores sites, not company types, so we would depend on Salesforce to create a manual list. And SFDC is notoriously wrong - even <peer exec> had pointed out on <date> that Salesforce is mis-identifying a large number of NPOs as private companies.
  *   The list goes out of date every week. Companies go public, get taken private, merge, delist or list on a foreign exchange. Someone would have to own that list and keep it current forever, it cannot be the product team.
  *   Most important - a site is not a company. One site can hold a public parent and its private subsidiaries. A PE firm's site can hold many portfolio companies that could be a mix of public and private. We will get it wrong both ways, whether mis marking public as private, or vice versa. It's not possible to do in Boards.

So I think the net conclusion is need the back-end check anyway. No list will be perfect nor maintainable, so we must check each opt-in before we use any data anyways. I think that check is the real control, not in the UI. UI-wise, we have already provided the labels that clearly shows this is for private companies, and if a public company accidentally checks it, we should just not use it. We need to do this anyways, even if we think we have the perfect list, because we could always be wrong.

I would suggest we go with the plan that <eng lead> provided, and <peer exec> seconded fallback, and I support it:

  1.  We record every tick, process only private companies, and count only private companies against the target.
  2.  <eng lead>'s team sends the opt-in extract with the site name and Salesforce account ID on every row.
  3.  <peer exec>'s team marks the public companies in that extract and does not process their data.

That's really the only realistic, scalable way to do this, and if we need to explain it to <CEO> happy to explain further if I can be helpful.

YL
`````

## Why it works

- He opens with "clarify the situation... with some references". It signals facts, not feelings.
- Numbered points give dates and links: no written requirement at first, then a late ask <n> days before launch.
- He quotes the other side's own words back ("we don't want to surface the opt-in to public companies, at all").
- "Bigger picture" gives three bullets on why the filter cannot work. Each starts with a short claim.
- He backs the fallback plan the other side already agreed to, so it becomes a shared plan.
- He offers to explain it to the CEO. That keeps him the expert, not the defendant.
