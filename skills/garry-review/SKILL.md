---
name: garry-review
description: "Code-quality review of code just written, run after writing code and before opening a PR. Reviews the working-tree delta against engineering preferences (CLAUDE.md / code-style.md): owns preferences/DRY/edge-cases/tests/performance; defers logic-correctness and security to the paired reviewer agent. Two modes: interactive (human present — tradeoffs, auto-fixes, AskUserQuestion) and --agent (no interaction, emits the QA artifact). Commonly invoked by QA subagents inside vibe-protocol pipelines — in that context do NOT ask which mode; use agent mode. Use when the user says 'review what I just wrote', 'check my code', 'review before I commit', or when a QA/orchestrator prompt mandates garry-review. NOT for PR diff review (use pr-review-pr), plan/design docs (use plan-eng-review), or pure style-guide conformance (use pr-code-reviewer)."
argument-hint: "[what-to-review] [--agent]"
---

# Garry Review — Post-Write Code Review

Review the code just written — the working-tree changes — before any PR is
created. Coverage is identical in both modes; only interaction and output
format differ.

## Mode Selection (decide ONCE, first, never re-ask)

**Agent mode** — enter when ANY of these hold:

- the invocation contains `--agent`;
- this skill is running inside a subagent / QA pipeline — the invoking prompt
  forbids editing implementation code, references vibe-protocol, QA artifacts,
  `qa/FEAT-XXX/`, or demands an artifact file;
- no interactive user is available to answer questions (AskUserQuestion would
  hang or is not offered).

**Interactive mode** — a human is present in the main thread and none of the
above apply.

- Positive example (agent mode): a QA Tester subagent prompt says "MANDATORY
  FIRST STEPS: Invoke skill: garry-review … You NEVER edit implementation
  code" → agent mode, zero questions asked, artifact emitted.
- Negative example (interactive mode): Yu-Kuan types `/garry-review` in the
  main thread after a coding session → interactive mode; asking THOROUGH/QUICK
  is correct here and only here.

## Owned Dimensions (do not duplicate the paired reviewer)

In QA pipelines this skill runs alongside a second reviewer
(feature-dev:code-reviewer or a pr-review-pr persona). Duplicating its work
doubles cost for zero coverage gain.

**garry-review OWNS:** engineering-preference conformance (CLAUDE.md /
code-style.md), DRY violations, edge-case handling, test quality/coverage,
performance smells.

**garry-review DEFERS:** logic correctness and security. If a probable
logic/security bug is spotted in passing, record it as ONE line tagged
`[DEFERRED: logic]` or `[DEFERRED: security]` — no deep analysis, no options.

- Positive example: plaintext password in a log line →
  `[DEFERRED: security] src/auth.ts:88 — plaintext password logged; paired reviewer to assess.`
- Negative example: writing a three-option threat-model analysis of the auth
  flow — that is the paired reviewer's dimension, not this skill's.

## Scope Detection (run after mode selection)

1. **A target was named** in "$ARGUMENTS" (files, a directory, a feature) →
   review exactly that.
2. **Default** → the current working delta: `git status`, then `git diff`
   (unstaged) + `git diff --cached` (staged) + unpushed commits
   (`git log @{upstream}..HEAD --oneline 2>/dev/null` and their combined diff;
   if no upstream, commits since the default branch).
3. **Escape hatch — nothing to review:** if all of the above are empty:
   interactive mode → ask "No uncommitted or unpushed changes found — what
   should I review?"; agent mode → emit an artifact stating "SCOPE EMPTY — no
   working-tree delta found" and STOP. Never review the entire repo unprompted.
   - Positive example: clean tree, interactive → ask for a target.
   - Negative example: clean tree → silently reviewing all of `src/`.

## Review Sections (always all four, both modes)

### 1. Architecture review
* Component boundaries, dependency graph, coupling.
* Data flow patterns and potential bottlenecks.
* Scaling characteristics and single points of failure.
* (Auth/data-access architecture only as preference conformance — deep
  security analysis is DEFERRED.)

### 2. Code quality review
* Code organization and module structure.
* DRY violations — be aggressive here.
* Error handling patterns and missing edge cases (call these out explicitly).
* Technical debt hotspots; over-/under-engineering vs stated preferences.

### 3. Test review
* Coverage gaps (unit, integration, e2e); assertion strength.
* Missing edge case coverage — be thorough.
* Untested failure modes and error paths.

### 4. Performance review
* N+1 queries and database access patterns.
* Memory-usage concerns; caching opportunities.
* Slow or high-complexity code paths.

## Confidence Calibration (both modes)

Rate every finding 1-10 before presenting:

| Score | Meaning | Action |
|-------|---------|--------|
| 9-10 | Verified bug or violation | Show — lead with these |
| 7-8 | High confidence | Show normally |
| 5-6 | Moderate confidence | Show with caveat ("likely but verify") |
| 3-4 | Low confidence | Suppress — appendix only |
| 1-2 | Speculation | Suppress unless P0 severity |

**Rules:**
- Never present findings scored <5 inline — collect them in a "Low-Confidence
  Appendix" at the end.
- If 2+ independent signals confirm the same finding, bump +2.
- Findings that contradict CLAUDE.md or code-style.md are auto 8+.

## Fix-First Heuristic (classification is universal; EXECUTION depends on mode)

Classify every finding as AUTO-FIX or ASK:

**AUTO-FIX class** (a senior engineer would apply without discussion):
- Dead code / unused variables
- Stale or false comments
- Magic numbers → named constants
- N+1 queries (when fix is obvious)
- Version/path mismatches in config
- Inline styles → CSS classes
- O(n×m) lookups → O(n) with Set/Map

**ASK class** (reasonable engineers could disagree):
- Security (auth, XSS, injection, race conditions) — also DEFERRED dimension
- Design decisions / architectural changes
- Large fixes (>20 lines changed)
- Removing functionality or changing user-visible behavior
- Enum completeness or API contract changes

**Execution by mode:**
- **Interactive mode:** AUTO-FIX items are applied silently and logged as
  `[AUTO-FIXED] [file:line] Problem → what was done`. ASK items get options.
- **Agent mode (no-edit context):** NOTHING is applied. AUTO-FIX-class items
  are emitted as `WOULD-AUTO-FIX` entries carrying the exact fix so the coder
  can apply it verbatim. Never emit "AUTO-FIXED Items — None" — in a no-edit
  context that line means the heuristic silently degenerated.
- Positive AUTO-FIX example: `const TIMEOUT = 30000` replacing a bare `30000`
  used twice — interactive: apply it; agent: `WOULD-AUTO-FIX` with the exact
  replacement.
- Negative example (must be ASK, both modes): swapping a polling loop for a
  webhook — better design, but it changes operational behavior.

---

## Interactive Mode Protocol

**BEFORE STARTING — ask which interaction depth (interactive mode ONLY):**

1. **THOROUGH:** one section at a time (Architecture → Code Quality → Tests →
   Performance), up to 4 top issues per section.
2. **QUICK:** one question per review section — the single most important
   issue each.

(Depth controls interaction granularity, not coverage — all four sections are
always evaluated.)

**For each ASK issue:** describe concretely with file:line; present 2-3
options including "do nothing" where reasonable; per option give effort, risk,
impact, maintenance burden; give the recommended option mapped to the stated
preferences; ask before proceeding.

**Worked ASK example (the contract for Final Review questions):**

```
3. [ASK] (confidence: 8/10) src/sync/queue.ts:78 — Unbounded retry loop on 429
   A) Add exponential backoff with a 5-retry cap (recommended) — ~10 lines,
      low risk, prevents worker-pool DoS under sustained rate limiting.
   B) Cap retries at 3 with fixed delay — 3 lines, but thundering-herd on recovery.
   C) Do nothing — acceptable only if this queue never sees production 429s.
   Recommendation: A — matches "handle common edge cases thoroughly (80/20)".
```

**FINAL REVIEW (interactive mode ONLY):**
1. List all `[AUTO-FIXED]` items applied.
2. Aggregate the most important ASK questions; NUMBER issues, LETTER options
   (recommended option first), then `AskUserQuestion`.
3. Mention the Low-Confidence Appendix if it exists; don't expand unless asked.
4. Per user answer, decide: apply the fix / log for later / discard. Ask
   before finishing.

---

## Agent Mode Protocol

**Contract — all five rules are hard:**

1. **Zero interaction.** No THOROUGH/QUICK question (coverage defaults to
   THOROUGH), no AskUserQuestion, no "pause for feedback". Run all four
   sections, emit the artifact, STOP.
2. **Never edit any file** except the artifact itself.
3. **Severity-only findings.** Every finding is exactly one line:
   `[P0|P1|P2] (confidence: N/10) file:line — problem → fix`.
   No option menus, no tradeoff essays. Severity scale: P0 = must fix before
   merge; P1 = should fix, escalate if stuck; P2 = log to docs/backlog.md.
4. **WOULD-AUTO-FIX section** replaces auto-fixing (see Fix-First above).
5. **Artifact placement:** if a task ID and feature ID are given or derivable
   from the invoking prompt → write
   `qa/FEAT-XXX/T-XXX-review-findings.md`. Otherwise return the same content
   as the final message (the orchestrator persists it).

**Artifact format (the QA-artifact format vibe-protocol expects):**

```markdown
# Review Findings — T-XXX
ReviewCommit: <SHA reviewed, if provided>
Reviewer: garry-review (agent mode)
Dimensions covered: preferences, DRY, edge cases, tests, performance
Deferred to paired reviewer: logic correctness, security

## P0 (must fix)
- (confidence: 9/10) file:line — problem → required fix

## P1 (should fix)
- ...

## P2 (log to docs/backlog.md)
- ...

## WOULD-AUTO-FIX (mechanical; coder may apply verbatim)
- file:line — problem → exact fix

## Deferred Dimension Flags
- [DEFERRED: security] file:line — one-line observation

## Low-Confidence Appendix (<5 confidence)
- ...

Verdict: PASS | FAIL (FAIL iff any P0)
```

- Positive example: QA pipeline invocation with `T-004`, `FEAT-012` in the
  prompt → artifact written to `qa/FEAT-012/T-004-review-findings.md`, verdict
  line present, zero questions asked.
- Negative example (historical failure this mode fixes): agent context, skill
  asks "BIG CHANGE or SMALL CHANGE?" into the void, then reports "AUTO-FIXED
  Items — None" because it couldn't edit — dead interaction + degenerate
  output. Agent mode makes both impossible.
