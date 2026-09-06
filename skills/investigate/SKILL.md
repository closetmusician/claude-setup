---
name: investigate
version: 2.0.0
description: >-
  Systematic root-cause debugging for a known bug or error. Five phases:
  root-cause investigation, pattern analysis, hypothesis testing,
  implementation, verification & report. Iron Law: no fixes without root
  cause. Primary method for non-trivial bugs: spawn 2-3 parallel investigation
  agents with different angles and require convergence. Supports a
  mitigation-first branch for live incidents. Trigger phrases: "debug this",
  "fix this bug", "why is this broken", "investigate this error", "root cause
  analysis", "figure out why". Also fire proactively (do NOT debug directly)
  when the user reports errors, 500s, stack traces, unexpected behavior, or
  "it was working yesterday". NOT for discovering unknown bugs by testing an
  app — /qa or /qa-only. NOT for navigation or page automation — /browse.
  NOT for code review — /garry-review or /pr-review-pr.
allowed-tools:
  - Bash
  - Read
  - Write
  - Edit
  - Grep
  - Glob
  - Task
  - AskUserQuestion
  - WebSearch
---

# /investigate: Systematic Debugging

## Which skill? (one-line router)

| Request shape | Skill |
|---|---|
| "Why is this specific thing broken?" — root-cause a known bug | `/investigate` (this skill) |
| "Test what I built / find bugs" → report + health score | `/qa` or `/qa-only` |
| "Open / screenshot / automate a page" | `/browse` |

## Iron Law

**NO FIXES WITHOUT ROOT CAUSE INVESTIGATION FIRST.**

Fixing symptoms creates whack-a-mole debugging. Every fix that doesn't address
root cause makes the next bug harder to find. Find the root cause, then fix it.
The Iron Law binds every subagent you spawn, too.

## Completion Gate (no DONE without these)

You may not declare the investigation DONE unless your final message contains:
1. The **DEBUG REPORT** block (Phase 5), fully filled in — no empty fields.
2. A **regression test**: file:line, shown to FAIL without the fix and PASS
   with it (paste both runs, or the passing run plus the pre-fix failure output).
3. **Full test suite output** pasted — no regressions.

Under time pressure the status becomes DONE_WITH_CONCERNS or BLOCKED and you
name exactly which gate element is missing. "The fix works, I'll skip the
test" is not an available option — the regression test IS the proof that the
root cause was real. Time pressure historically breaks this verification tail,
not the root-causing; the gate exists for exactly that moment.

---

## Mitigation-First Branch (live incidents only)

If the bug is actively hurting right now — prod down, users blocked, data
corrupting — stop the bleeding BEFORE the full root-cause protocol:

1. Apply the **smallest reversible mitigation**: feature-flag off, revert the
   offending deploy/commit, add a guard clause, restart/scale.
2. **Label it explicitly.** The commit message and your message to the user
   MUST say `mitigation: <what> — root cause pending`. A mitigation is not a
   fix and must never be reported as one.
3. Verify the bleeding stopped (reproduce the symptom once).
4. THEN resume the full protocol: Phases 1-3 to find root cause, Phases 4-5 to
   fix properly — and explicitly decide whether the mitigation is removed or kept.

**Decision criteria:** users or data affected right now → mitigate first.
Dev-only bug, failing test, staging issue → skip this branch, go straight to
Phase 1.
- **Positive example:** prod checkout 500s after a deploy → revert the deploy,
  verify checkout works, then investigate the reverted diff for the real cause.
- **Negative example:** a flaky unit test → no mitigation branch; skipping or
  retry-wrapping the test to "stop the bleeding" is an Iron Law violation.

---

## Method Selection (choose before Phase 1)

**Parallel Convergence — PRIMARY method, default for anything non-trivial.**
Spawn 2-3 investigation subagents (Task tool), each with a DIFFERENT angle,
and require convergence before accepting a root cause. Use when any of: the
bug spans more than one file, the stack trace doesn't point at an obvious
line, the bug is intermittent, multiple plausible causes exist, or a first
quick look didn't reveal the cause. This pattern has produced the fastest
correct root causes in practice ("3/3 agents agree").

**Linear Solo.** Run Phases 1-5 yourself, sequentially. Use ONLY when the bug
is trivially localized: deterministic repro AND single file AND the error
message names the exact line.

- **Positive example (parallel):** "checkout intermittently 500s since
  yesterday" → 3 agents: recent-diff angle, data-flow angle, environment angle.
- **Negative example (parallel is waste):** `TypeError: cannot read 'name' of
  undefined at UserCard.tsx:42` with an obvious missing null-guard → linear solo.

### Parallel Convergence protocol

1. **Spawn 2-3 agents in ONE message** (they run concurrently). Each prompt
   contains: the full symptom description, repro steps, relevant paths, and
   exactly ONE angle:
   - **Angle A — recent changes:** `git log` / `git diff` since last-known-good;
     assume the bug is in the diff. Report which change and why.
   - **Angle B — data flow:** trace the failing value from input to the error
     site; assume the bug is bad data or a missing transform/guard.
   - **Angle C — environment/config:** env vars, dependency versions,
     migrations, caches, feature flags, local-vs-CI differences; assume the
     code is fine and the setup is wrong.
2. Each agent must return: root-cause hypothesis + file:line evidence +
   confidence (1-10). **Agents investigate only — no fixes** (Iron Law).
   If browser repro is needed, only ONE agent may drive the browser (the
   browse daemon is a singleton — parallel `$B` use deadlocks).
3. **Convergence rule:** accept a root cause when ≥2 agents independently name
   the same cause, OR one agent's hypothesis explains ALL evidence the others
   collected. All-disagree → treat as zero confirmed hypotheses: go to Phase 3
   yourself using their combined evidence.
4. **Surface subagent failures immediately.** If any agent errors, stalls, or
   returns nothing, say so to the user in your very next message ("Agent B
   (data-flow) failed: <error>") and either respawn it once or continue with
   the remaining agents — explicitly. NEVER silently continue as if it had
   reported; a silently missing angle looks identical to "no findings there."
5. After convergence, YOU still run Phases 3-5 (confirm, fix, verify). Agent
   agreement is evidence, not proof.

---

## Phase 1: Root Cause Investigation

Gather context before forming any hypothesis.

1. **Collect symptoms:** read the error messages, stack traces, and repro
   steps carefully. If context is missing, ask ONE question at a time via
   AskUserQuestion.
2. **Read the code:** trace the code path from the symptom back to potential
   causes. Grep for all references; Read to understand the logic.
3. **Check recent changes:**
   ```bash
   git log --oneline -20 -- <affected-files>
   ```
   Was this working before? What changed? A regression means the root cause is
   in the diff.
4. **Reproduce:** can you trigger the bug deterministically? If not, gather
   more evidence before proceeding — an unreproducible bug cannot be verified
   fixed.
5. **Check history in this repo:** prior fixes in the same files
   (`git log --oneline -- <file>` + TODOS.md). Recurring bugs in the same area
   are an architectural smell, not a coincidence.

Output: **"Root cause hypothesis: ..."** — a specific, testable claim about
what is wrong and why.

## Phase 2: Pattern Analysis

Check if this bug matches a known pattern:

| Pattern | Signature | Where to look |
|---------|-----------|---------------|
| Race condition | Intermittent, timing-dependent | Concurrent access to shared state |
| Nil/null propagation | NoMethodError, TypeError | Missing guards on optional values |
| State corruption | Inconsistent data, partial updates | Transactions, callbacks, hooks |
| Integration failure | Timeout, unexpected response | External API calls, service boundaries |
| Configuration drift | Works locally, fails in staging/prod | Env vars, feature flags, DB state |
| Stale cache | Shows old data, fixes on cache clear | Redis, CDN, browser cache, Turbo |

**External pattern search:** if the bug matches no known pattern, WebSearch
for "{framework} {generic error type}" and "{library} {component} known
issues". **Sanitize first:** strip hostnames, IPs, file paths, SQL, customer
data — search the error category, not the raw message. If it can't be
sanitized safely or WebSearch is unavailable, skip the search. A documented
solution or known dependency bug becomes a candidate hypothesis in Phase 3.

## Phase 3: Hypothesis Testing

Before writing ANY fix, verify the hypothesis.

1. **Confirm it:** add a temporary log statement, assertion, or debug output at
   the suspected root cause. Run the reproduction. Does the evidence match?
   (Remove the instrumentation afterward.)
2. **If wrong:** optionally run the sanitized web search above, then return to
   Phase 1. Gather more evidence. Do not guess.
3. **3-strike rule:** if 3 hypotheses fail, **STOP**. Use AskUserQuestion:
   ```
   3 hypotheses tested, none match. This may be an architectural issue
   rather than a simple bug.

   A) Continue investigating — I have a new hypothesis: [describe]
   B) Escalate for human review — this needs someone who knows the system
   C) Add logging and wait — instrument the area and catch it next time
   ```

**Red flags — if you catch yourself doing any of these, slow down:**
- "Quick fix for now" — there is no "for now." Fix it right, use the
  mitigation branch (labeled as such), or escalate.
- Proposing a fix before tracing data flow — you're guessing.
- Each fix reveals a new problem elsewhere — wrong layer, not wrong code.

## Phase 4: Implementation

Once root cause is confirmed:

1. **Fix the root cause, not the symptom.** The smallest change that
   eliminates the actual problem.
2. **Minimal diff:** fewest files touched, fewest lines changed. Do not
   refactor adjacent code.
3. **Write the regression test** (required by the Completion Gate):
   - **Fails** without the fix — run it against the pre-fix code (stash the
     fix or write the test first) and paste the failure.
   - **Passes** with the fix — paste the passing run.
4. **Run the full test suite.** Paste the output. No regressions allowed.
5. **Blast-radius gate — fix touches >5 files → AskUserQuestion:**
   ```
   This fix touches N files. That's a large blast radius for a bug fix.
   A) Proceed — the root cause genuinely spans these files
   B) Split — fix the critical path now, defer the rest
   C) Rethink — maybe there's a more targeted approach
   ```

## Phase 5: Verification & Report

**Fresh verification:** reproduce the ORIGINAL bug scenario and confirm it no
longer occurs. Not optional — a green test suite without re-running the
original repro does not count.

Then output the structured report (this block is Completion Gate element #1):

```
DEBUG REPORT
════════════════════════════════════════
Symptom:         [what the user observed]
Root cause:      [what was actually wrong]
Method:          [parallel-convergence (N agents, verdict) | linear-solo]
Mitigation:      [none | what was applied, and whether removed or kept]
Fix:             [what changed, with file:line references]
Evidence:        [test output + original-repro re-run showing it's fixed]
Regression test: [file:line of the new test + fail-then-pass proof]
Related:         [TODOS.md items, prior bugs in same area, architectural notes]
Status:          DONE | DONE_WITH_CONCERNS | BLOCKED
════════════════════════════════════════
```

---

## Important Rules

- **3+ failed fix attempts → STOP and question the architecture.** Wrong
  architecture, not failed hypothesis.
- **Never apply a fix you cannot verify.** If you can't reproduce and confirm,
  don't ship it.
- **Never say "this should fix it."** Verify and prove it. Run the tests.
- **Fix touches >5 files → AskUserQuestion** about blast radius first.
- **Surface every subagent failure immediately** — never report a synthesis
  over silently-missing agent results.
- **Mitigations are always labeled** `mitigation: ... — root cause pending`;
  they never close an investigation.
- **Completion status:**
  - DONE — root cause found, fix applied, regression test written
    (fail→pass shown), full suite passes, original repro re-verified
  - DONE_WITH_CONCERNS — fixed but cannot fully verify (intermittent bug,
    needs staging); missing gate elements named
  - BLOCKED — root cause unclear after investigation, escalated
