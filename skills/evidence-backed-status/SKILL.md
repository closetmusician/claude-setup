---
name: evidence-backed-status
description: >-
  Status-reporting discipline for any claim that something is done, passing,
  deployed, fixed, wired, or exists. Encodes the vocabulary
  (observed/verified/candidate/unverified/stale-risk/duplicate-risk/unused-risk/
  broken-risk/owner-confirmation-needed) and the same-turn evidence rule: every
  done/passing/deployed claim carries its verifying command output in the SAME
  turn; existence claims run the probe FIRST. Fire when you or a subagent are
  about to report completion, mark a checklist item, summarize what shipped, or
  cite a usage/history number. Also fire when reviewing another agent's
  completion claim before trusting it. NOT for the mechanics of spawning
  verifier subagents (see dispatch-protocol.md Rule 5) and NOT for the
  done/escalate/stop decision itself (see judgment-rubrics.md §2/§3). This skill
  governs how a status is WORDED and what proof must accompany it.
allowed-tools:
  - Bash
  - Read
  - Grep
  - Glob
---
<!--
Intended final target: /Users/yklin/.claude/skills/evidence-backed-status/SKILL.md
Draft source: /Users/yklin/.claude/docs/plans/fable-skills/drafts/skills/evidence-backed-status/SKILL.md
Draft status: candidate (planning artifact, not installed). Verify all volatile
claims (incident counts, retention window, guard filenames) against the cited
sources before install — see §10.
-->

# evidence-backed-status: say only what you can prove, in the turn you say it

## 1. Purpose

Capture the reporting doctrine that separates a *claim* from *evidence*, so any
future session — any model tier — reports status the way a careful reviewer
would accept. Fake-done reporting is the single largest trust-incident class in
this harness (stated as 46 incidents over ~6 months in
`/Users/yklin/.claude/docs/plans/harness/judgment-rubrics.md` §7 and `report-trust-incidents.md`;
re-verify that count against those files before citing it — it is a snapshot,
not a live metric). This skill makes the honest form of every status claim
cheap and mechanical.

## 2. When to use

Fire whenever you are about to:
- report a task/feature/fix as done, passing, deployed, wired, or working;
- check off an item in a plan, backlog, ledger, or spec-diff;
- assert a file, hook, schedule, or component *exists* or *is loaded*;
- cite a usage or history number ("fired N times", "no session did X");
- consume and relay a subagent's completion claim to the user.

## 3. When not to use

- The decision of whether something *is* done, or whether to stop/escalate —
  that is `/Users/yklin/.claude/docs/plans/harness/judgment-rubrics.md` §2/§3. This skill governs the
  *wording and proof* once you report.
- The mechanics of spawning an independent verifier subagent — that is
  `/Users/yklin/.claude/docs/plans/harness/dispatch-protocol.md` Rule 5. This skill states the
  contract the verifier must satisfy (re-run, not re-read); it does not own the
  dispatch template.
- Pure exploration/research with nothing being claimed done.

## 4. Inputs required

- The claim you are about to make, in one sentence.
- The artifact that would prove it: command + its output, file:line, git diff,
  screenshot, or probe result. If you cannot name the artifact, you cannot make
  the claim — downgrade the status word (§5) instead.
- For usage/history claims: the data source and its retention window.

## 5. Procedure

### 5a. Pick the status word (vocabulary)

Every status line leads with exactly one of these:

| Word | Means | Requires |
|---|---|---|
| `observed` | I read/saw it directly this session | the read/probe in this turn |
| `verified` | I ran a check that proves it, output shown | command + output, THIS turn |
| `candidate` | proposed/drafted, not yet proven | nothing — but say "not yet verified" |
| `unverified` | claimed by someone/something, not re-checked | name who claimed it |
| `stale-risk` | was true once; may have drifted | the timestamp/window it was last true |
| `duplicate-risk` | may overlap an existing asset | the suspected twin's path |
| `unused-risk` | no usage evidence in the window | the window checked |
| `broken-risk` | plausibly non-functional | the reason to doubt it |
| `owner-confirmation-needed` | needs a human decision | the exact question |

Never write "verified" without the evidence source in the same turn. If you
only read a report that said it passed, the correct word is `unverified`.

### 5b. Claim-and-artifact in the same turn (hard rule)

Any `done | passing | deployed | fixed | wired | green` claim MUST include the
verifying command's output in the SAME message. Not "I ran the suite and it
passed" — paste the summary line. Not "the hook fires now" — paste the probe
firing. A claim whose proof is in a previous turn, another file, or an agent's
head is `unverified`.

### 5c. Existence claims: probe FIRST, then state

Before asserting a file/hook/plist/schedule exists or is loaded, run the probe
and let its output drive the sentence. Order matters: probe → read result →
write the claim. Writing "the plist is loaded" and then checking is how
records drift from reality (this harness recorded plists documented as
"unloaded" while `launchctl list` showed them loaded — capability-capture §6).

Probe menu (verify these still apply to the target machine before relying on
their output):
- file exists: `ls -la <path>` or `wc -c <path>`
- hook wired: `grep <script> settings.json`
- plist loaded: `launchctl list | grep <label>`
- git hook active: `git -C <repo> config core.hooksPath`
- schedule enabled: read `schedules.json` (enabled ≠ executing — see traps)

### 5d. Independent verification RE-RUNS, never re-reads

A verifier who reads the producer's log is not a verifier. Independence means
the checker executes the check itself, in a fresh context, and the verifier is
a different agent than the producer (and ≥ its tier for judgment work). This is
the contract; the dispatch mechanics live in
`/Users/yklin/.claude/docs/plans/harness/dispatch-protocol.md` Rule 5.

### 5e. Self-citation ban

Do not cite an artifact you authored as proof that your own work is correct.
"QA artifacts exist on disk" is worthless if the orchestrator wrote them — 100%
of QA-cycle files in one corpus were authored by the orchestrator, not QA
(`/Users/yklin/.claude/docs/plans/harness/judgment-rubrics.md` §7 NEGATIVE). Evidence must originate outside the claimant.

### 5f. Usage/history claims state the window

Any "fired N times / no session did X" claim is valid ONLY if it states the
retention window taken from the oldest retained file, and reconciles against a
purge-immune source (journal, episodic archive). Transcripts purge on
`cleanupPeriodDays` (recorded as 180 in `settings.json` — confirm current value
before citing). See `/Users/yklin/.claude/docs/plans/harness/judgment-rubrics.md` §6 for
the full rule and the reversal that motivated it.

## 6. Evidence required

To publish any status line, you hold: (1) the status word, (2) for
verified/observed — the command and its output or the file:line in this turn,
(3) for usage claims — the window + purge-immune cross-check. If you cannot
assemble these, downgrade the word; do not upgrade the confidence.

## 7. Output artifact

A status report where every line is `<word>: <claim> — <evidence-or-gap>`.
Example:
```
verified: suite green — `run-harness-evals.sh` → "52/52 PASS" (this turn)
observed: night-runner plist present — launchctl list shows com.yklin.night-runner exit 0
candidate: hermes CLAUDE.md — drafted, not installed, not verified
owner-confirmation-needed: bless OFF plists as live? burn-in review due ~07-08
```
A stated gap ("blocked on missing API key — needs you") is an acceptable line;
a silent gap is the exact failure this skill prevents.

## 8. Common traps (bad behavior this prevents)

- **Checking off on self-report.** A backlog item was marked complete because
  the agent said done — the 5.7 audit delivered 1/4 requirements yet was checked
  off (MEMORY.md 2026-03-22). The fix: spec-diff with file:line per requirement,
  never "agent said done."
- **"Verified" that was re-read, not re-run.** QA once "verified" against the
  wrong URL (trust incident S15, d8450959). Re-running the actual check against
  the actual target is the only verification.
- **Existence asserted before probing** — records claiming plists "unloaded"
  while they were loaded (capability-capture §6). Probe first.
- **Windowless usage claim** — "12 flagship skills fired ~0 times, delete them"
  was reversed when full history showed 383 events for one of them
  (`/Users/yklin/.claude/docs/plans/harness/judgment-rubrics.md` §6 NEGATIVE). State the window.
- **Schedule enabled ≠ running.** `schedules.json` may show `enabled:true` for 8
  tasks with no execution logs (harness_inventory §7). "Enabled" is a config
  observation, not an execution `verified`.

## 9. Related skills

- `/Users/yklin/.claude/docs/plans/harness/judgment-rubrics.md` — §2 done, §3 stop/escalate, §5
  quality floors, §6 usage windows, §7 agent trust. This skill operationalizes
  the *reporting* half of those rubrics.
- `/Users/yklin/.claude/docs/plans/harness/dispatch-protocol.md` — Rule 5 independent-verifier
  mechanics; digest-to-file contract.
- `hook-authoring` — the guard-side enforcement (completion-claim-guard.sh)
  that backstops these claims.
- `/investigate` — its Completion Gate is a worked instance of same-turn
  evidence (regression test shown fail→pass in the report).

## 10. Provenance and maintenance

- Sources: `/Users/yklin/.claude/docs/plans/harness/judgment-rubrics.md` (§2/§5/§6/§7),
  `/Users/yklin/.claude/docs/plans/fable-skills/evidence/recent_capability_capture.md` (§4 patterns
  4, 5), `MEMORY.md` (2026-03-22 incident).
- Volatile facts flagged inline (incident count 46/6mo, retention 180 days,
  suite pass counts, plist load states) are point-in-time snapshots. Before
  citing any of them as current, re-run the named probe or re-read the named
  source — do not trust this skill's snapshot.
- Maintenance: when a new trust-incident class appears, add its status word or
  trap here and cross-link the guard that catches it. Changes follow
  `/Users/yklin/.claude/docs/plans/harness/maintenance-protocol.md`.
