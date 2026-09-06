---
name: pr-review-pr
description: "Comprehensive PR-diff review: provenance-checked scope, specialized reviewer agents, a skeptical verifier pass, and a findings-disposition gate. Canonical LOCAL PR-diff review skill — when this and pr-review-toolkit:review-pr, code-review:code-review, or the built-in /review all match, use this one. Use when the user says 'review this PR', 'check this PR', 'look at PR #N', 'pre-landing review', 'review what changed since my last review' (--since-last-review), or 'compare PRs 42 and 43' / 'which of these PRs should we merge' (--compare; supersedes multi-pr-review). NOT for: post-write review of uncommitted work (use garry-review), style-guide conformance only (use pr-review-toolkit:code-reviewer), structural-safety-only checks (use review — 'safety review'), plan/design docs (use plan-eng-review)."
argument-hint: "[pr-number(s)] [aspects|personas] [--since-last-review] [--compare] [--prd path]"
allowed-tools: ["Bash", "Glob", "Grep", "Read", "Task", "Write", "Edit", "AskUserQuestion"]
---

# Comprehensive PR Review

Review a pull request diff using specialized reviewer subagents, verify every
serious finding against the raw diff before presenting it, and end with an
explicit disposition step so findings never evaporate. The orchestrator (the
model running this skill) dispatches subagents, aggregates findings, and runs
the disposition gate. It does not skip steps 0, 4, or 6 under any circumstances.

**Arguments (optional):** "$ARGUMENTS" — PR number(s), aspect names, persona
names, `parallel`, `--since-last-review`, `--compare`, `--prd <path>`.

---

## Step 0: Diff Provenance (MANDATORY — never dispatch without it)

The single worst historical failure of this skill is reviewing the wrong diff
(stale local branches, merge noise, 26 files reviewed when the PR changed 3).
Every review starts with this checklist. No exceptions.

### 0.1 Resolve what to review, in this order

1. **PR number in arguments** → that PR.
2. **No number, but the current branch has a PR** → `gh pr view --json number`
   resolves it; use that PR.
3. **No PR anywhere** → local branch review (see 0.3).
4. **Not a git repo** (`git rev-parse --show-toplevel` fails) → stop: "Not a git
   repository — nothing to review. Point me at a repo or a PR URL."

### 0.2 PR case — the scope IS `gh pr diff`, never a local diff

Run all of the following before dispatching anything:

```bash
gh pr view <N> --json number,title,state,baseRefName,mergeStateStatus,changedFiles
gh pr diff <N> --name-only        # the authoritative file list
gh pr diff <N>                     # the authoritative diff (this is the review scope)
```

**Rules:**

- **RULE: For a PR, the review scope is the output of `gh pr diff <N>`. NEVER
  substitute `git diff main...HEAD`, `git diff main..HEAD`, or any local diff.**
  Local branches drift from the PR (extra commits, missed pushes, merge noise).
  - Positive example: user says "review PR 106" → run `gh pr diff 106`, review
    exactly those hunks.
  - Negative example (historical incident, never repeat): user says "review
    PR 106", the branch is checked out locally, so the reviewer runs
    `git diff main...HEAD` — branch is 7 commits behind, diff shows 26 files,
    the PR actually changes 3, review is mostly wrong.
- **RULE: Check `mergeStateStatus`.** If it is `BEHIND`, print in the review
  header: "PR is BEHIND <base> — reviewing the PR as authored; base drift is
  not part of this review." Do not merge or rebase anything to "fix" it.
  - Positive example: `BEHIND` → state it, proceed on `gh pr diff` output.
  - Negative example: `BEHIND` → silently `git merge origin/main` locally and
    review the merged tree. That reviews code the PR author never wrote.
- **RULE: Cross-check the file count.** Compare the line count of
  `gh pr diff <N> --name-only` against the `changedFiles` number from
  `gh pr view`. **On mismatch, ABORT** — print both numbers, do not dispatch
  agents, and ask the user to confirm the repo/PR. A mismatch means a stale
  cache, wrong repo, or truncated diff.
  - Positive example: `changedFiles: 3`, name-only lists 3 files → proceed.
  - Negative example: `changedFiles: 3`, name-only lists 26 files → dispatching
    anyway and reviewing 23 files of merge noise. Abort instead.
- **RULE: Print the scope line before dispatch:**
  `Reviewing N files: <file list>` (if >20 files, list 20 + "… and K more").
  This lets the user catch scope contamination in one glance.

### 0.3 Local case (no PR) — three-dot only

```bash
BASE=$(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's|refs/remotes/origin/||')
# fallback: main, then master
git diff origin/$BASE...HEAD        # three-dot = merge-base diff
git diff; git diff --cached         # plus uncommitted work
```

- **RULE: Three-dot (`...`) only.** Two-dot `git diff origin/main..HEAD`
  includes upstream commits your branch doesn't have and produces phantom
  hunks.
  - Positive example: `git diff origin/main...HEAD` → only this branch's work.
  - Negative example: `git diff origin/main..HEAD` on a branch behind main →
    hundreds of lines of other people's code in the "review".
- Print the header: "No PR found — reviewing branch diff vs origin/<base>."
- Print the same `Reviewing N files: <list>` scope line.

### 0.4 Empty diff

If the resolved scope is empty, stop cleanly: "Empty diff vs <base> — nothing
to review." Do not dispatch agents.

---

## Step 1: Available Review Aspects

**Individual aspects** — each routes to a plugin agent in `pr-review-toolkit`
(upstream-maintained; supercedes former local skill copies):

| Aspect | Agent / skill |
|--------|---------------|
| comments | `pr-review-toolkit` comment-analyzer agent |
| tests | `pr-review-toolkit` test-analyzer agent |
| errors | `pr-review-toolkit` silent-failure-hunter agent |
| types | `pr-review-toolkit` type-design-analyzer agent |
| code | `pr-review-toolkit:code-reviewer` |
| simplify | `simplify` skill (code-simplifier plugin) |
| safety | `~/.claude/skills/review/SKILL.md` (structural safety: SQL, LLM trust boundaries, conditional side effects, shell injection, enum completeness) |

**Named personas** (each wraps multiple aspects with a focused lens):

- **architecture** — `~/.claude/skills/pr-review-pr/personas/architecture-reviewer.md`
- **domain** — `~/.claude/skills/pr-review-pr/personas/domain-specialist.md`
- **ambition** — `~/.claude/skills/pr-review-pr/personas/ambition-backstop.md`

Default (no aspects requested): auto-route per Step 2.

## Step 2: Review Routing

Using the Step 0 file list and diff content, match signals:

| Signal | Persona / Aspects |
|--------|-------------------|
| New types, interfaces, abstractions | Architecture Reviewer |
| `*.tsx`, `*.css`, `components/` | Domain Specialist + code |
| `*test*`, `*spec*` | Domain Specialist (tests focus) |
| `catch`, `try`, `error`, `fallback` in diff | Architecture Reviewer (errors focus) |
| Schema changes, migrations | Architecture Reviewer + **safety** |
| Utility/helper additions | Ambition Backstop |
| Safety signals (below) | **safety** aspect |
| 10+ files changed | Briefing first via `~/.claude/skills/pr-briefing/SKILL.md`, then personas in parallel |
| Default (no strong signals) | Domain Specialist |

Multiple matches = multiple personas. Manual override always wins.

### Safety-dimension detection criteria

Dispatch **safety** only when the diff touches at least one of:

1. **SQL / data access** — raw SQL string literals, `.raw(`, string-interpolated
   queries, migration files, ORM `where`/`execute` with dynamic input.
2. **LLM prompt or output handling** — prompt templates, `messages: [...]`,
   model API calls, code that parses/stores/executes model output.
3. **Conditional side effects** — writes, deletes, sends, charges, or state
   transitions inside branches; retry loops around mutating calls.
4. **Shell execution** — `exec`, `spawn`, `system`, `subprocess`, backticks,
   command strings built from variables.
5. **New enum/status/tier values** added to an existing set.

Positive example: diff adds `db.raw("... WHERE name = '" + q + "'")` → dispatch
safety (signal 1). Negative example: diff renames a React prop and updates CSS
→ no safety signals; Domain Specialist covers it.

## Step 3: Dispatch Review Agents (NON-OPTIONAL)

**RULE: Agent dispatch is mandatory. Main-thread-only review is permitted ONLY
when the total diff is under 50 changed lines** (sum of insertions+deletions
from `gh pr diff <N> --stat` or `git diff --stat`). In that one case, the final
summary must carry the exact line:
`Main-thread review (diff <50 lines) — no agents spawned.`
A "review" that spawns no agents and doesn't print that line is review theater
and violates this skill.

- Positive example: 12-line typo-fix PR → main-thread review, print the line.
- Negative example (historical incident): 400-line PR "reviewed" entirely in
  the main thread with a generic summary; user had to re-issue the command to
  get the real pipeline. Never do this.

**Model tiers:** reviewer subagents `model: sonnet` (bounded checklist against
a bounded diff); consolidation by the orchestrator on the session model; the
Step 4 verifier `model: opus` (adversarial judgment). Use aliases, never dated
model IDs.

**Dispatch ledger:** record every spawn (persona/aspect, model) — the Step 5
summary must name each one.

**Subagent prompt contract (include ALL of this in every Task prompt — subagents
do not load CLAUDE.md and may not have the Skill tool):**

```
You are the {persona/aspect} reviewer for this PR.
1. Read your instructions: Read {absolute persona/skill path from Step 1}.
   Where that file says "invoke skill X" or "Skill(X)", do NOT attempt the
   Skill tool. Instead Read ~/.claude/skills/X/SKILL.md and apply its
   checklist inline yourself.
2. Get the diff with EXACTLY this command: {exact command from Step 0, e.g.
   `gh pr diff 42`}. Do not substitute any other diff command.
3. Apply the checklist to the diff only. Rate every finding's confidence 1-10;
   suppress findings below 5 to a short appendix.
4. Return findings as: [SEVERITY] (confidence: N/10) file:line — issue
   → recommended fix. Do not edit any files.
```

**Sequential dispatch (default)** — personas one at a time so persona 2 doesn't
re-flag what persona 1's fixes resolved. Between personas, the ORCHESTRATOR
applies only mechanical fixes (dead code, stale comments, magic numbers,
obvious typos) and reports `[AUTO-FIXED] file:line`. Judgment fixes (design,
behavior, security, >20 lines) are NEVER applied mid-review — they go to the
Step 6 disposition gate.

- Positive example: reviewer 1 flags an unused import → delete it now.
- Negative example: reviewer 1 says "split this service in two" → collect for
  Step 6, never auto-applied between reviewers.

**Parallel dispatch** — only when the user asked (`parallel`) or the selected
reviewers examine non-overlapping concerns (e.g. safety + ambition). Launch all
Task calls in one message; apply no fixes until all return.

## Step 4: Skeptical Verifier (MANDATORY before presenting findings)

Reviewer output is not trusted at face value. Before any findings reach the
user, spawn ONE independent verifier agent (`model: opus`) that re-checks every
Critical (P0) and Important (P1) finding against the raw diff.

**Verifier input (nothing else):** (a) the exact diff command from Step 0;
(b) the deduplicated list of P0/P1 findings as bare claims
(`severity, file:line, one-line issue`) — NOT the reviewers' reasoning.

**Verifier instructions (include verbatim in the Task prompt):**

```
You are the independent audit for a PR review. You are the last line of
defense against phantom findings, wrong citations, and inflated severity.
1. Fetch the diff yourself: {exact command from Step 0}.
2. For EACH finding: (a) confirm the cited file:line exists in the diff hunks
   (not merely in the repo — pre-existing code outside the diff is out of
   scope); (b) confirm the described problem is actually present in the diff
   text; (c) judge whether the severity is justified (a P0 must plausibly
   block merge).
3. Verdict per finding: CONFIRMED | REJECTED-PHANTOM | DOWNGRADED-to-X |
   UPGRADED-to-X, each with a one-line reason.
4. Scan the diff once yourself for anything serious no reviewer caught; list
   it under "Additional Findings" with confidence 1-10.
5. Output a table: | finding | verdict | reason |. Do not edit any files.
```

**RULE: The verifier's verdict overrides the reviewers** (audit-overrides-
synthesis). REJECTED findings move to a "Rejected by verifier" appendix;
severity adjustments are applied before the summary is written.

**Skip criterion:** the verifier may be skipped ONLY when both hold: the
<50-line main-thread case applies AND there are zero P0/P1 findings.

- Positive example: 3 P0s reported → verifier confirms 2, rejects 1 as citing a
  line not in the diff → summary shows 2 P0s + the rejection in the appendix.
- Negative example: presenting 12 unverified P0/P1s directly because "the
  reviewers seemed thorough" — this is exactly the trust failure the verifier
  exists to prevent.

## Step 5: Aggregate Results

Deduplicate (same file:line + same issue = one finding, keep highest severity),
apply verifier verdicts, then produce:

```markdown
# PR Review Summary — {PR #N title | branch vs base}
Scope: {exact diff command} | {N} files, +{ins}/-{del} | mergeStateStatus: {status}
Reviewers dispatched:
- {persona/aspect} ({model})   ← one line per spawned agent, from the ledger
- verifier ({model}) — {X confirmed / Y rejected / Z adjusted}
{or: Main-thread review (diff <50 lines) — no agents spawned.}

## Critical Issues (X) — verifier-confirmed
- [persona]: Issue [file:line] → fix
## Important Issues (X) — verifier-confirmed
- [persona]: Issue [file:line] → fix
## Suggestions (X)
- [persona]: Suggestion [file:line]
## Auto-Fixed During Review
- [AUTO-FIXED] file:line — what was done
## Rejected by Verifier
- [persona]: claim → why rejected
## Strengths
- What's well-done
```

Plain English throughout: one sentence problem + one sentence fix per finding.
No jargon walls.

## Step 6: Disposition Gate (findings NEVER evaporate)

Ending a review with a report and no disposition is a protocol violation —
findings historically got lost across sessions ("I thought you fixed it all
already?"). After the summary, run `AskUserQuestion`:

1. **Fix now** — orchestrator applies fixes in severity order (mechanical
   first), re-running targeted aspects after.
2. **Persist to backlog (default)** — append ALL findings to `docs/backlog.md`.
3. **Post to GitHub** — `gh pr review <N> --request-changes|--comment
   --body-file <summary>` (ask which verdict before posting).

**RULE: Regardless of the choice, every P0/P1 not fixed in-session is appended
to `docs/backlog.md` before the skill ends** (create the file if missing).
Entry format:
`- [ ] [P0] file:line — issue → fix (from /pr-review-pr PR#N, YYYY-MM-DD)`
If `AskUserQuestion` is unavailable (non-interactive context), take option 2
silently and say so in the final output.

- Positive example: user picks "Fix now", 2 of 5 findings fixed before context
  runs low → the remaining 3 are written to docs/backlog.md.
- Negative example: printing the summary and stopping — the P1s vanish when the
  session ends.

---

## Mode: --since-last-review

Reviews only what changed since the last GitHub review on the PR. Trigger
phrases: "review what changed since last review", "re-review the new commits",
"delta review".

1. Find the last-reviewed commit:
   `gh api repos/{owner}/{repo}/pulls/<N>/reviews --jq '.[-1].commit_id'`
   (resolve owner/repo via `gh repo view --json nameWithOwner`).
   - **If empty (no prior review): say so and ask whether to run a full review
     instead.** Do not silently review the whole PR.
   - Positive example: last review at `a1b2c3d` → delta scope is
     `a1b2c3d..head`.
   - Negative example: no prior review found → running a full review while
     labeling it "delta" — misleads the user about coverage.
2. Fetch the PR head: `git fetch origin pull/<N>/head` (gives `FETCH_HEAD`).
3. Delta diff: `git diff <last_commit>..FETCH_HEAD`, then **intersect its file
   list with `gh pr diff <N> --name-only`** — files only in the delta (e.g.
   from a base-branch merge commit) are upstream noise and are dropped. State
   in the header if any were dropped.
4. Header: `Delta review: PR #N, commits since <sha7> (last review <date>)`.
5. Steps 2-6 run unchanged on the delta scope (dispatch gate scales to the
   delta size).

## Mode: --compare (supersedes multi-pr-review)

Compare 2+ PRs — competing implementations, a related set, or PRs vs a PRD.
Trigger phrases: "compare PRs 42 and 43", "which of these should we merge",
"review these PRs against each other/the PRD".

**Per-PR provenance:** Step 0.2 runs for EACH PR independently (including the
file-count abort rule).

**Size-gated dispatch (per PR — never the old 18-agents-per-PR pipeline):**

| PR size (insertions+deletions from `gh pr diff N --stat`) | Reviewers |
|---|---|
| < 150 lines | 1 agent (domain persona, all dimensions inline) |
| 150–600 lines | 2 agents (architecture + domain) |
| > 600 lines | 3 agents (architecture + domain + safety-or-ambition per Step 2 signals) |

- Positive example: three ~80-line bug-fix PRs → 3 agents total (1 per PR).
- Negative example (the historical failure this replaces): 54 debate agents +
  18 consolidations for three small PRs, 83 findings, output needed a full
  plain-English rewrite. Never scale agents past the table above.

**Pipeline:**

1. Dispatch per-PR reviewers (Step 3 contract; all in one parallel message).
2. Orchestrator synthesizes: per-PR verdict (APPROVE / REQUEST_CHANGES /
   NEEDS_DISCUSSION), a comparison table (approach, tradeoffs, risk, test
   quality), and a recommendation of which PR to merge (or how to combine).
   **Cap: 10 inline findings per PR**; overflow goes to an appendix.
3. If `--prd <path>`: add a per-requirement coverage table per PR
   (`COVERED file:line` / `NOT COVERED`).
4. Step 4 verifier runs ONCE across all PRs' P0/P1 findings (it fetches each
   PR's diff itself). Verifier overrides synthesis everywhere they disagree.
5. Step 6 disposition gate; backlog entries are tagged per PR.

---

## Usage Examples

```
/pr-review-pr                        # auto-route on current PR or branch diff
/pr-review-pr 42                     # review PR #42
/pr-review-pr 42 --since-last-review # only commits since the last GH review
/pr-review-pr 42 43 44 --compare     # comparative review, size-gated agents
/pr-review-pr 42 43 --compare --prd docs/prd/  # + PRD gap analysis
/pr-review-pr tests errors           # only test coverage + error handling
/pr-review-pr safety                 # structural-safety pass only
/pr-review-pr architecture domain    # two personas, sequential
/pr-review-pr all parallel           # everything, parallel
```

## Notes

- Persona and aspect definitions are **markdown files on disk** under
  `~/.claude/skills/` — not `/agents` entries; subagents must Read them by
  absolute path.
- The **safety** aspect is `~/.claude/skills/review/SKILL.md`; users can run it
  standalone as `/review` ("safety review").
- Run early — before creating the PR, not after. Re-run targeted aspects after
  fixes.
- `multi-pr-review` is superseded by `--compare`; its audit-overrides-synthesis
  rule and confidence calibration are built into Steps 3-4 here.
