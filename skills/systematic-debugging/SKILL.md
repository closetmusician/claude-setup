---
name: systematic-debugging
description: "Use when encountering any bug, test failure, or unexpected behavior. Enforces 4-phase root-cause analysis before proposing fixes. Triggers: 'debug this', 'why is this failing', 'fix this bug', 'test failure', any error message."
---

<!-- ABOUTME: Enforces Yu-Kuan's 4-phase debugging protocol from code-style.md. -->
<!-- ABOUTME: Prevents jumping to fixes before understanding root cause. -->
<!-- ABOUTME: Each phase has a hard gate -- must satisfy before proceeding. -->
<!-- ABOUTME: Builds on superpowers:systematic-debugging with stricter enforcement. -->
<!-- ABOUTME: Invokable standalone; under 100 lines by design. -->

# Systematic Debugging Protocol

Root cause only -- no symptom fixes, no workarounds. Reference: `~/.claude/rules/code-style.md` Debugging Protocol.

## The Iron Rule

**No fixes until you can explain WHY the bug exists.** If you cannot state the root cause in one sentence, you have not investigated enough. STOP and go back to Phase 1.

## Phase 1: Investigate

**Actions:**
1. Read the full error message and stack trace. Note file paths, line numbers, error codes.
2. Reproduce consistently. If you cannot trigger it reliably, gather more data -- do not guess.
3. Run `git diff` and check recent commits. What changed?
4. For multi-component systems: add diagnostic logging at each boundary, run once, read the output.

**GATE -- answer ALL before proceeding:**
- [ ] Can you reproduce the bug on demand?
- [ ] Have you read the complete error output (not skimmed)?
- [ ] Do you know WHAT is failing and WHERE in the code?

STOP if any gate is unsatisfied. Gather more evidence.

## Phase 2: Pattern Match

**Actions:**
1. Find a working example of similar code in the same codebase.
2. If implementing a pattern or following a reference, read the reference implementation COMPLETELY -- every line.
3. Diff the working version against the broken version. List every difference, no matter how small.
4. Check dependencies, config, and environment assumptions.

**GATE -- answer ALL before proceeding:**
- [ ] Have you identified a working comparison point?
- [ ] Can you list the specific differences between working and broken?

STOP if any gate is unsatisfied. You are not ready to hypothesize.

## Phase 3: Hypothesize and Test

**Actions:**
1. State a single hypothesis: "The root cause is X because Y."
2. Design the smallest possible change that tests ONLY this hypothesis.
3. Make ONE change. Run. Observe.

**GATE -- answer before proceeding:**
- [ ] Did the hypothesis hold? If YES -> Phase 4. If NO -> form a NEW hypothesis and repeat Phase 3. Do NOT stack fixes.

STOP if you have tested 3+ hypotheses without success. You likely have an architectural problem. Discuss with Yu-Kuan before continuing (see superpowers:systematic-debugging Phase 4.5).

## Phase 4: Fix

**Actions:**
1. Write the simplest failing test that captures the bug.
2. Implement ONE fix addressing the root cause identified in Phase 3.
3. Run the failing test -- it must pass now.
4. Run the full test suite -- no regressions.

**GATE -- answer ALL before declaring done:**
- [ ] Does a test exist that would have caught this bug?
- [ ] Does the fix address root cause (not symptoms)?
- [ ] Do all tests pass?
- [ ] If fix did NOT work: STOP. Return to Phase 1 with the new information. Do NOT attempt another fix without re-investigating.

## Anti-Patterns -- STOP Immediately If You Catch Yourself:

- Changing code without understanding the error message
- Trying multiple fixes hoping one sticks
- Adding try/catch, null checks, or retries as "fixes"
- Deleting or skipping a failing test
- Blaming the framework before checking your own code
- Saying "it's probably X" without evidence
- Proposing solutions before tracing data flow
- Making more than one change at a time

Each of these means: **STOP. Return to Phase 1.**

## Quick Reference

| Phase | Do | Gate |
|---|---|---|
| 1. Investigate | Read errors, reproduce, git diff | Reproducible? Error understood? Location known? |
| 2. Pattern | Find working example, diff against broken | Differences listed? |
| 3. Hypothesize | Single theory, minimal test, one change | Hypothesis confirmed? |
| 4. Fix | Failing test, one fix, full suite green | Root cause addressed? All tests pass? |

## Supporting Material (superpowers:systematic-debugging)

Deeper techniques: `root-cause-tracing.md`, `defense-in-depth.md`, `condition-based-waiting.md`.
