# Model Roles

ABOUTME: Which model tier does which work, and the hard rule that keeps Fable off the
ABOUTME: front line. Canonical home — CLAUDE.md, vibe-protocol.md, dispatch-protocol.md
ABOUTME: Rule 3 and policy/route-policy.json all point here and must not restate it.
ABOUTME: Mechanized by scripts/governance/model-role-guard.sh (PreToolUse, hard deny).
ABOUTME: Written 2026-09-11 on Yu-Kuan's instruction; decisions D1-D6 recorded in §6.

## 1. The rule

**Fable reviews and critiques. Fable never chairs a session and never does the work.**

This holds for every agent in every position: the session you are reading this in, a
subagent, a member of an agent team, a fork. A more capable model is a reason to put it
in the chair, not a reason to let it type.

Opus 5.5 chairs sessions (D7). The chair does Tier 0 work itself (CLAUDE.md task size tiers). Tier 1-2 work goes to the workhorses below.

Real work goes to the workhorses:

| Tier | What it is for | Examples |
|---|---|---|
| **haiku** | Mechanical batches with an exact spec | Rename sweeps, format fixes, counts, existence checks, file moves |
| **sonnet** | Standard execution. **The default when unsure.** | Implement from a written spec, targeted search, write tests, draft from a template |
| **opus** | Judgment | Architecture, synthesis across agents, adversarial review, ambiguous debugging, PRD and briefing prose, anything customer-visible |
| **fable** | Review and critique **only** (D7). Not the session chair. | Redline a draft, adversarially review a plan, critique a design |

## 2. What "never does the work" means

A Fable session may NOT edit files, write files, or run a command that changes state.
It has exactly one allowlist — the paperwork an orchestrator owns:

- `docs/plans/**`
- `qa/**`
- `handoffs/**`
- `specs/` directories, and any file named `*spec*.md`
- any file named `*review*.md` (this covers `T-XXX-ready-for-review.md`)
- `ORCHESTRATION.md`

Everything else is delegated.

Git splits in two, because commit sequencing is an orchestrator duty (dispatch-protocol
Rule 10). Fable MAY move work forward: `add`, `commit`, `push`, `tag`, and every read-only
command (`status`, `log`, `diff`, `show`, `fetch`). Fable may NOT rewrite or discard what
exists: `apply`, `checkout`, `switch`, `restore`, `reset`, `revert`, `merge`, `rebase`,
`stash`, `clean`, `rm`, `mv`, `cherry-pick`, `init`, `config`, `filter-branch`. Those are hands-on repair
work, so they go to a worker.

## 3. What every session owes its subagents

**Every `Agent`/`Task` spawn must name a `model`.** An omitted `model` makes the subagent
inherit the parent, which is the exact path by which Fable ends up doing hands-on work one
level down. This applies in every session, not only Fable ones.

- A `fork` always inherits the parent model, so a Fable session may not fork. Spawn a
  fresh agent with an explicit tier instead.
- A `fable` subagent is allowed only when the dispatch is review, critique, audit,
  verification, assessment, synthesis, or orchestration. Production work on Fable is denied.
- Escalation and de-escalation between tiers: dispatch-protocol.md Rule 4.

## 4. Escape hatches

Two, both explicit and both auditable:

- **Per call** — say `FABLE-OK` (any case) in your own message, or put `MODEL-ROLE-EXEMPT`
  in the tool call. The guard stands down for that call only.
- **Per session** — `HARNESS_MODEL_ROLE_GUARD=0`. Use it for a long exceptional run, not
  to get past one block.

If you find yourself reaching for a hatch several times in a session, the tier is wrong
for the work. Change the tier, do not keep overriding.

## 5. How it is enforced

`scripts/governance/model-role-guard.sh` — PreToolUse, wired in settings.json on
`Edit|Write|NotebookEdit|Bash|Agent|Task`. It denies (exit 2 + `permissionDecision: deny`).

It reads the session model from the transcript, because **the PreToolUse payload carries
no model field** — verified by live capture on 2026-09-11, archived at
`docs/plans/harness/model-role-payload-capture.txt`. If the model cannot be resolved, the
guard allows the call and prints a loud warning to stderr; a closed gate there would brick
every session before its first assistant turn reaches disk.

A subagent call is different. Its payload carries `agent_id` and `agent_type`, but its
`transcript_path` is the PARENT session's file (live capture 2026-09-18,
`docs/plans/harness/model-role-payload-capture-subagent.txt`). The guard therefore reads the
subagent's own transcript at `<session id>/subagents/agent-<agent_id>.jsonl`. A sonnet worker
spawned from a Fable session resolves as sonnet and may write. If that file is not on disk
yet, the call resolves as "worker" and is allowed with a stderr note, because the spawn
already had to name a tier.

Tests: `scripts/tests/test-model-role-guard.sh` (59 cases). Neuter-and-fail proven — with
the guard absent, 13 of the original 37 fail; with the 2026-09-18 subagent fix reverted, 4 of
the 6 subagent cases fail.

## 6. Decisions behind this file (binding — do not re-litigate)

Recorded from Yu-Kuan's answers on 2026-09-11:

- **D1** Prose work (PRD narrative, briefings, yk-voice, storytelling) is real work. It
  moved from fable to opus in `policy/route-policy.json`. No rule routes to fable now.
- **D2** Enforcement is a hard block, not a warning.
- **D3** The Fable allowlist is plans, specs, and review artifacts. Not scratch files. Git
  split on 2026-09-11 (Yu-Kuan): forward motion (add, commit, push, tag, and the read-only
  commands) stays with Fable; anything that rewrites or discards state is delegated.
- **D4** Both escape hatches exist (per call and per session).
- **D5** The session default model is Opus; Fable is opt-in through `/model`.
- **D6** Naming a tier on a spawn is required in every session, not only Fable ones.
- **D7** (2026-10-25, Yu-Kuan, after `docs/learnings/opus5.5/REPORT.md`): Fable is for review and critique only. It no longer chairs orchestration. Opus 5.5 chairs sessions and does Tier 0 work itself. D5 and D6 stand. The guard does not change.
