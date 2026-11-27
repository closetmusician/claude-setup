# fixed-complaints-reply

```yaml
audience: field seller
reply_type: forwarded complaint
channel: mail
words: 822
```

## Situation

A sales leader forwards a long list of complaints from a new Co-Sec at a <$> account to a wide exec list.
Many of the complaints describe problems that product fixed this year.
Yu-Kuan wants the field to learn the fixes instead of escalating them.

## Sent

### <date>

`````text
Hi <sales VP>,

Thanks for sending this, and thanks to <CSM> for getting such direct feedback from <co-sec>. I agree with the fast follow to show him Boards on D1P is the right next step, I presume the account team will lead in setting that up and presenting?

A lot of what <co-sec> shared will be addressed when we show him D1P. But I also want to highlight that several of his points describe problems we fixed this year. We’d kindly ask the account team and Support familiarize themselves with these fixes, and then they can better help the customers as a first responder. Here’s a list of what we’ve shipped.

1. Sync is unreliable ("press sync three or four times")

  *   Boards iOS <version> (<date>) added background book sync. While the app is closed, it downloads the <n> most relevant books, with today's and tomorrow's meetings first. Books are then mostly ready when a director opens the iPad.
  *   Background sync is off by default. Ask: @<sales VP> can the CSM checks the <customer> site in CSP. If "Background Sync Period (hours)" is 0, request it to be set.
  *
Versions <version> to <version> fixed more sync problems. Sync now resets the inactivity timer, a large sync queue no longer freezes the app, and users no longer sign in again when they switch books. The release notes for each version are in the App Store version history <link>, publicly available to all.
  *
If they are still experiencing specific issues after updating to the latest iOS version and turning on background sync, could you please have the support team raise a T2 ticket and the team will triage appropriate.

2. Offline access failed, including on flights

  *   Boards iOS <version> (<date>) fixed a problem with signing in while offline. Support already solved <co-sec>'s case, so the next step is to make sure every <customer> director is on the latest app.
  *   Ask: Could <support lead> & the support team confirm that each <customer> director has Boards iOS <version> or later and iOS <version> or later. Version <version> is in the App Store <link> now. The app version shows at the bottom left of the Home page, next to the Diligent logo.
  *   To set up and test offline books before a flight, use the help articles Offline access <link> and Boards for iOS: Download and manage current books <link>. Both are in the customer help portal, so <co-sec>'s team can use them directly. For the site-level setting, Support has Enable Offline Access at Site Level <link>.
  *
All account teams & were on the "[Important] Mandatory Application Updates" email thread from <date> to <date>. Every customer got those update notices. A director on an old app version can see exactly the failures <co-sec> described.

3. Harder to navigate, “compartmentalized”

Overall, I agree the right answer here is Boards on D1P, so the demo is the right next step. That said, here are the things we did launch this year.

  *   Boards iOS <version> (<date>) added a redesigned navigation menu on iPhone and iPad. It makes it easier to switch boards and move around the site. Directors who have not updated have not seen it. The details are in the App Store version history <link>.
  *   Notes now sync between web and iPad. Boards iOS <version> (<date>) added note comments of up to <n> characters, and comment editing.

4. Support experience

  *
We believe some of our Support script might be outdated - login script still says "nothing can be done". That has not been true since Boards iOS <version> to <version>.  That is out of date: iOS <version> (<date>) stopped the mid-meeting logouts, and iOS <version> (<date>) stopped Face ID asking again after a board switch.
  *
Ask @<CS lead>: could you let <support lead> know to the call centre script and the help article so that agents give the current fixes.

5. AI features (director questions, summaries)

  *
I’m wondering if the account & CSM team’s AI talk tracks are pretty outdated? If we’re still talking about deck summaries, that’s like <n>+ yrs old. I think with all our recent innovation with AGAI, there’s whole lot more we can offer directors now beyond deck summaries, I hope we can really lean more into our recent innovations when we talk to customers now.

There’s certainly always room to improve the product and we’ll always strive to do so. At the same time, we’d also ask for your partnership in working with your teams to make sure they’re updated on our latest changes & innovations, are using the latest talk tracks from PMM & GTMR, through launch posts, release notes, help centers, etc (Glean can help a lot here). Together I hope we can enable the first responders and account teams to address of many of these points without it needing to be escalated, and ultimately resulting in an experience for our customers.

Thanks,

YL
`````

## Why it works

- He thanks the sender and the CSM, then agrees with the proposed next step. He asks the account team to lead it.
- He states the frame early: "several of his points describe problems we fixed this year".
- Each complaint gets a heading in the customer's words, then the fixes with versions and dates, then a named "Ask".
- He links public sources (App Store history, help articles) so the field can help itself next time.
- He redirects blame with a question, not an accusation: "I'm wondering if the account & CSM team's AI talk tracks are pretty outdated?"
- The close concedes "always room to improve" and asks for "partnership" in keeping teams current.
