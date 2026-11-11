---
name: run-watch
description: "One status check on a long multi-agent run. It finds stalled or off-track agents and pushes them to finish. It prints a plain-English table: % done, % left, a do/don't decision and an ETA per item. Below it go the total ETA and speed-ups. Safe speed-ups run at once. The rest become checklist items in the plan. Run it on a timer with \"/loop 10m /run-watch [plan path]\". Use on \"check on all agents\", \"are the agents stuck\", \"push them to finish\", \"status table with ETA\", \"/run-watch\". NOT for a done-claim on a deliverable (use evidence-backed-status). NOT for harness speed (use speed-tune). NOT for starting the run (use lead-orchestrator)."
---

<!-- ABOUTME:
  run-watch SKILL.md - one check of a live multi-agent run, built to repeat under /loop.
  Inputs: the running agents in this session and the run's plan file (eng-plan*.md).
  Outputs: nudges to stuck agents, one status table, speed-ups run or logged to the plan.
  Written 2026-11-10 because Yu-Kuan typed the same /loop prompt on every long run.
-->

# run-watch

Weight: none (a check, no deliverable). Tier 0. Time box: about 3 minutes per check.

Start it with `/loop 10m /run-watch <plan path>`. Completion notices still wake the session.
The loop is the fallback for agents that go quiet. Never use an interval under 5 minutes.

**Limit: the loop cannot catch a stuck main session.** Loop ticks run inside this session.
They fire only when the session can take a turn. On 2026-11-05 the ticks queued for
2 h 45 min behind a stuck session (lessons-learned.md, "/loop is not a stall watchdog").
Tell the user this on the first check. Only a script outside the session can catch it.

## Steps

1. **List the work.** Call `ListAgents`. Add running background Bash tasks and workflows.
   Read the plan file (step 6 says how to find it) for the item list and dependencies.
   Each row in the table is one plan item or one agent brief, not one tool call.

2. **Check each agent.** Find its transcript with
   `find ~/.claude/projects -name "agent-<id>.jsonl"`. Read its mtime and its last 20 lines.
   Give it one state:
   - `working`: it wrote to its transcript inside the last loop interval.
   - `stalled`: no write for one full loop interval or more.
   - `off track`: any of these. It hits the same error 3 or more times. It works on files
     or questions outside its brief. It uses over twice the median tool calls of its peers
     with no new file on disk. It redoes a part that is already finished.
   - `blocked`: it waits on a person, a login, or another item.
   - `done`: it returned. Check one output file exists before you trust the claim.

3. **Push.** Send one `SendMessage` to each agent that is not `working` or `done`.
   - Stalled: "Status check. Your brief is <X>. Finish <next step> before the next check.
     If you are blocked, report the blocker now and stop."
   - Off track: "Stop work on <Z>; it is outside your brief. Write it down as an open item.
     Go back to <next step>."
   - Second push with no progress: tell it to save its partial work to `docs/temp/` and return.
   - Third check with no progress: confirm the partial work is on disk. Then call `TaskStop`.
     Spawn a narrower brief on the same model tier. Report this in the table.
   - Blocked on a person: do not push. Put the question in the "Do or don't" cell.

4. **Measure each item.**
   - % done = finished steps ÷ total steps. Count steps from the plan checklist or the brief's
     list of outputs. An agent's own claim is not a count. If no steps are countable, write
     the number with "(est.)".
   - % left = 100 minus % done.
   - ETA = time spent × (% left ÷ % done). Round to 5 minutes. Below 10% done, use the
     plan's estimate or write "unknown". Never invent a precise number.
   - Add the time for checks the item still needs (tests, verifier, QA).

5. **Print the report.** Use this exact table. Every cell is plain English (writing-style.md).

   | Item | Agent | State | Done | Left | Do or don't, and what it means | ETA |
   |---|---|---|---|---|---|---|
   | T-11 Jira batch | sonnet-2 | working | 60% | 40% | Do: keep going. The Jira stage drops from 25 min to under 2 min. | 20 min |
   | T-12 manifest read | sonnet-3 | off track | 30% | 70% | Don't: let it redesign the cache. That doubles the ETA. It got a push back to the brief. | 45 min |

   Under the table, print:
   - **Total time left.** This is the longest chain of remaining items, not the sum.
     Parallel agents overlap. Name the chain, e.g. "T-12 → T-9b → verify = 70 min".
   - **Speed-ups.** One line each, tagged `[done now]` or `[logged to plan §<n>]`.
   - **Changes since the last check**, in at most 3 lines.

6. **Act on speed-ups.** Run a speed-up at once only if ALL of these are true:
   - It is reversible.
   - It stays inside the scope the owner approved.
   - It skips no gate (failing test first, verifier, QA cycle, phase gate).
   - It is not outward-facing (no push to a shared repo, no PR, no message to a person).
   - It does not change a file that another running agent owns.
   Examples that pass: start an independent item on a free worker now. Split one big item
   across two workers on separate files. Narrow a brief that is too wide. Stop a duplicate
   test run.

   Log every other speed-up to the plan:
   - The plan is the path you got. Else take the highest-version `docs/eng-plan*.md`
     in the run's repo.
   - Add a `- [ ]` item to the existing checklist that fits best (same task id or topic).
     Never open a new section. If the plan has no checklist at all, ask once.
   - Search the plan first. If the idea is already there, add the new numbers to that item.
   - Match the plan's item style: a bold title, the measured fact, the idea, the first
     step, and "filed <YYYY-MM-DD> by run-watch".
   - Commit the plan edit by itself, per the repo's commit rules.

7. **Stop the loop when the run ends.** When every item is `done` or waits on the owner,
   print the final table and the open items. Then end the loop (`CronDelete` for a fixed
   interval, `ScheduleWakeup` with `stop: true` for a self-paced one).

## Rules

- Trust disk, not words. A file, a commit, or a test result counts as progress.
- One check makes at most one `AskUserQuestion`. Put every owner question in it.
- Never change an owner decision recorded in the plan. Raise it in the "Do or don't" cell.
- A push or a respawn keeps the agent's model tier. A new spawn names a `model` (model-roles.md).
- Keep it short. A check with no change prints the table and "No change since <time>".
