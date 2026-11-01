---
name: speed-tune
description: "Weekly self-tune for wall-clock speed: read the speed report, score last week's change, then make ONE change to the biggest bucket. Use when the session-start line says \"Run /speed-tune\", or on \"why is Claude slow\", \"speed report\", \"make yourself faster\", \"/speed-tune\". NOT for the speed of a product app (that is investigate or a perf task)."
---

<!-- ABOUTME:
  speed-tune SKILL.md - the act step of the speed loop in docs/learnings/speed/PLAN.md.
  Measure: scripts/speed-report.py (nightly via nightly-flywheel step 5b). Act: one change a week.
  Log: state/speed/experiments.jsonl. Session nudge: scripts/session-start.d/30-speed.sh.
  Written 2026-11-01. Rule: at most 10 minutes of analysis; no change without a baseline number.
-->

# speed-tune

Weight: light code or docs (whatever the chosen change is). Tier 0. Time box: about 10 minutes of analysis.

## Steps

1. **Measure.** Run `python3 ~/.claude/scripts/speed-report.py --days 7 --save`. If the last tune was under 7 days ago, add `--days` equal to the days since that tune.
2. **Score the last experiment.** Read the last line of `~/.claude/state/speed/experiments.jsonl`. Compare its `bucket` seconds per request (`sec_per_request` in the newest `history.jsonl` line) with its `baseline_s`.
   - Lower by more than 10%: verdict `keep`.
   - Higher by more than 10%: verdict `revert`. Revert the commit with a new commit, not a history rewrite.
   - Otherwise: verdict `neutral`. Keep it if it made the harness simpler; else revert it.
   - Append `{"date", "scores": <commit>, "verdict", "after_s"}` to `experiments.jsonl`.
3. **Pick ONE target.** Take the top row of the bucket table that is at least 15% of wall time. Then pick the cheapest untried lever for it from `docs/learnings/speed/PLAN.md` §3. Read the "Bash calls over 60 s" and "Slowest requests" tables first: an outlier often names the lever.
4. **Change it.** Follow the CLAUDE.md weight table: a code change needs a failing test first. A behaviour rule goes into the shortest file that loads where it acts, and it must not bloat CLAUDE.md. Commit it.
5. **Log it.** Append `{"date", "bucket", "lever", "baseline_s", "commit"}` to `experiments.jsonl`. `baseline_s` is the bucket's current seconds per request.
6. **Report** in at most 5 lines: last verdict, this week's target and its share, the change, and the commit.

## Rules

- One change per run. Two changes at once make the next score useless.
- Skip any bucket under 15% of wall time. Its best case is too small.
- Do not trim hooks for speed while all hooks together take under 0.3 s on a Bash call. Check that with `speed-report.py --hooks`. Hooks run in parallel, so the slowest one sets the cost.
- A new lever that works goes into PLAN.md §3, so the next run can use it.
