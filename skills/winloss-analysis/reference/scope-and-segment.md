# Scoping and segmentation reference

Paste the relevant parts of this into the research brief. It exists because both of these
were got wrong on the first run.

## 1. Period scoping

**Ask first.** The user's mental model of "current" is usually a single month, not a
quarter. The first run defaulted to Q1+Q2 2026 when the user wanted July only.

Default when the user does not answer: **the previous full calendar month.**

Derive it explicitly and state it — do not let an agent infer it:

```bash
# previous full calendar month, e.g. "July 2026" / 2026-07-01..2026-07-31
python3 -c "
from datetime import date
t=date.today().replace(day=1)
import calendar
p=(t.replace(day=1)-__import__('datetime').timedelta(days=1))
print(f'{p:%B %Y}', f'{p.replace(day=1)}..{p}')
"
```

Then, in every agent prompt and every table header, name the period as a hard filter:

> Period filter: **July 2026 only** (2026-07-01 to 2026-07-31). Do NOT widen to the
> quarter. If a figure only exists at quarter or year-to-date granularity, report it with
> its true period label and say plainly that no monthly cut exists — do not present a
> quarterly figure as if it were the month.

Because a single month is a small sample, expect and pre-empt these:
- Low deal counts per region × segment. Report counts alongside every rate; a win rate on
  6 deals must be labelled as such.
- A monthly figure will often be missing where a quarterly one exists. That is a finding,
  not a failure — put it in the gaps list.
- Finance workbooks carry both monthly and QTD/YTD columns in the same sheet. Confirm
  which column you are reading; the column headers are frequently not exposed in search
  snippets, in which case download and open the file.

## 2. Segmentation inside each region

Mandatory. Regional splits alone hide the story.

| Segment | Band | Notes |
|---|---|---|
| Enterprise | $1.5B+ revenue | **Group Strategic into Enterprise.** Strategic is a coverage tier, not a distinct buying behaviour, and splitting it fragments already-small monthly counts. |
| Mid-Market | $251M–$1.49B | The only band confirmed verbatim in a source so far. |
| SMB | <$250M | |

Rules:
- **AMER and EMEA: always split.** These carry the volume and the segments genuinely
  diverge — in the first run SMB was simultaneously the highest-volume winning segment,
  the only improving retention segment, and the biggest price-loss segment.
- **APAC: split if the data supports it, otherwise group and say so.** APAC ran ~72% SMB
  with an ARR per deal under half of EMEA's. Write "APAC segment counts below N are
  grouped; the split is not reportable for this period" rather than publishing a table of
  ones and twos.
- Minimum reportable cell: state your threshold (5 deals is a reasonable floor for a
  single month) and apply it consistently.

Per region × segment, report at minimum:

| Region | Segment | Deals | ARR | ARR/deal | Win rate | ASP | Dominant reason |
|---|---|---|---|---|---|---|---|

The Finance `BLC Wins` sheet has an account-segment column, so this is a pivot over data
you already have — not new research. The win-rate and ASP sheets are also segment-cut.

**Watch for:** the win-reason field is roughly two-thirds blank. Every percentage is a
share *of coded deals*, never of all deals. State the coded denominator in every table
caption, e.g. "n=72 of 215 coded".

## 3. Cross-cutting: what to say when a cell is empty

Use one of these, never an estimate:

- `[need sources]` — the figure should exist and we could not find it.
- "not reportable for this period — n=<count> below threshold" — the data exists but the
  sample is too small.
- "no monthly cut exists; <quarter> figure is <value>" — granularity mismatch.
- "not stated in the source" — the document simply does not contain it.
