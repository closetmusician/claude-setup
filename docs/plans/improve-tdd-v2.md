# Plan: Simplify Lead Orchestrator — Kill Superpowers Chain, Add Real QA Testing

## Context

The lead-orchestrator currently chain-invokes two superpowers skills per coder subagent (~280 tokens of skill loading overhead each), uses two separate QA templates that only do code review (no testing), and has a soft commit-ordering check in the orchestrator itself instead of the governance hooks. This plan restructures the system to:

- Inline TDD discipline directly into the coder prompt (no skill invocations)
- Inline verification-before-completion into the QA tester prompt
- Replace two review-only QA templates with one test-oriented QA tester
- Move commit-ordering verification into post-agent-audit.sh
- Add a garry-review step between coder and QA for code quality
- Update vibe-protocol.md and vibe-manual.md to reflect the new QA testing model

**New loop:** Coder → garry-review (report-only subagent) → Coder fix → QA Tester C1 (write tests + break it) → bug list → Coder fix → QA Tester C2 (re-test C1 bugs, full mode only)

---

## Files to Modify (execution order)

### Step 1: `templates/coder-prompt.md` — Inline TDD, remove superpowers

**File:** `~/.claude/skills/lead-orchestrator/templates/coder-prompt.md`

**Remove** lines 16-17 (the two `Invoke skill:` lines):
```
2. Invoke skill: `superpowers:test-driven-development` — you MUST follow Red-Green-Refactor
3. Invoke skill: `superpowers:verification-before-completion` — you MUST prove tests pass with evidence before claiming done
```

Renumber step 4 (MCP tools) to step 2.

**Add** new `## TDD Protocol (Inlined — Non-Negotiable)` section after `## Requirements` (before `## Decision Boundaries`). Content condensed from superpowers TDD skill:

1. **Iron Law** (verbatim): `NO PRODUCTION CODE WITHOUT A FAILING TEST FIRST. Write code before the test? Delete it. Start over. No exceptions.`

2. **Red-Green-Refactor** (~10 lines):
   - RED: One minimal failing test, one behavior. Run it. Confirm fails for right reason (feature missing, not typo/error).
   - GREEN: Simplest code to pass. Run it. Confirm all tests pass, output pristine.
   - REFACTOR: Clean up, remove duplication. Keep tests green. Don't add behavior.

3. **Anti-Rationalization Table** (8 rows):

   | Excuse | Reality |
   |--------|---------|
   | "Too simple to test" | Simple code breaks. Test takes 30 seconds. |
   | "I'll test after" | Tests passing immediately prove nothing. |
   | "Already manually tested" | Ad-hoc ≠ systematic. No record, can't re-run. |
   | "Deleting X hours is wasteful" | Sunk cost fallacy. Keeping unverified code is debt. |
   | "Keep as reference" | You'll adapt it. That's testing after. Delete means delete. |
   | "Need to explore first" | Fine. Throw away exploration, start with TDD. |
   | "TDD will slow me down" | TDD faster than debugging. |
   | "Just this once" | No exceptions. |

4. **Verification Checklist** (8 items):
   - [ ] Every new function/method has a test
   - [ ] Watched each test fail before implementing
   - [ ] Each test failed for expected reason
   - [ ] Wrote minimal code to pass each test
   - [ ] All tests pass
   - [ ] Output pristine (no errors, warnings)
   - [ ] Tests use real code (mocks only if unavoidable)
   - [ ] Edge cases and errors covered

5. **Red Flags — Delete and Start Over** (top 5):
   - Code written before test
   - Test passes immediately (never watched it fail)
   - Rationalizing "just this once"
   - Claiming done without running `make test`
   - Using "should pass" / "looks correct" without evidence

**Net change:** Remove 2 lines, add ~50 lines. Eliminates two skill invocations (~280 tokens each at runtime).

---

### Step 2: `templates/qa-tester-prompt.md` — New unified QA template

**New file:** `~/.claude/skills/lead-orchestrator/templates/qa-tester-prompt.md`

Replaces `qa-cycle1-prompt.md` and `qa-cycle2-prompt.md`. Same governance structure (ABOUTME, GOVERNANCE COMPLIANCE comments, Status line, Mandatory Context, Requirement Map, Constraints).

**Key sections:**

1. **Role:** "You are the QA TESTER subagent for T-XXX."

2. **Mandatory First Steps:**
   - Read `.claude/rules/vibe-protocol.md`
   - Read the coder's `qa/FEAT-XXX/T-XXX-ready-for-review.md`
   - Read PRD/spec at `{SPEC_PATH}`
   - If `{QA_MODE}` = `cycle-2`: also read `qa/FEAT-XXX/T-XXX-cycle-1.md` for bug list

3. **QA Testing Protocol** (5-step sequence):
   - Step 1: Read PRD, internalize all requirements and acceptance criteria
   - Step 1.5: Review existing tests against PRD requirements 1:1. Identify gaps. **Write tests** for uncovered requirements.
   - Step 2: Run `make test` (hard gate). If fail → verdict = FAIL immediately. Re-run once for flaky detection.
   - Step 3: Exercise feature manually (API calls, CLI invocations, read code paths)
   - Step 4: Try to break it — edge cases, boundary values, invalid input, error paths, concurrent access
   - Step 5: Produce bug report (not a review report)

4. **Verification Gate** (inlined from verification-before-completion):
   ```
   Before ANY claim about test results:
   1. IDENTIFY: What command proves this claim?
   2. RUN: Execute the FULL command (fresh, no cache)
   3. READ: Full output, check exit code, count failures
   4. VERIFY: Does output confirm the claim?
   5. ONLY THEN: State claim WITH evidence
   
   "Should pass" = lying. "Looks correct" = lying. Evidence or silence.
   ```

5. **Mode Handling** via `{QA_MODE}` placeholder:
   - `cycle-1`: Full protocol (all 5 steps). Produce `T-XXX-cycle-1.md`.
   - `cycle-2`: Re-test ONLY bugs from cycle-1. Read cycle-1 bug list. Verify each fix. Run regression. Produce `T-XXX-cycle-2.md`.

6. **Auto-Reject Criteria** (carried from existing templates):
   - Mock on internal module (only external HTTP)
   - No SavepointConnection for DB tests
   - Test without exercising real code path
   - Uncaptured warnings in test output
   - Core dependency entirely mocked
   - Missing TDD Evidence table (no exemption)
   - Testing anti-patterns (vibe-manual Section 6.5)

7. **Allowed Actions** (R10 compliance):
   - WRITE: test files (`tests/`, `test_*`, `*_test.*`, `*.spec.*`, `*.test.*`), QA artifacts (`qa/`)
   - READ: any file
   - RUN: test commands, lint commands
   - NEVER: edit implementation code

8. **Artifact output format:**
   ```
   Task: T-XXX
   STATUS: PASS|FAIL
   Mode: {QA_MODE}
   CommandsRun: make test; [manual verification commands]
   ReviewCommit: <SHA>
   
   ## Tests Written
   - [test_file:line] — tests [requirement/behavior]
   
   ## Test Results
   [paste test output summary]
   
   ## Bugs Found
   1) <file:line> — <bug description> — <severity P0/P1/P2> — <repro steps>
   
   ## Verification Evidence
   REQ-XX: [evidence of testing]
   ```

---

### Step 3: `post-agent-audit.sh` — Add commit-ordering check

**File:** `~/.claude/scripts/governance/post-agent-audit.sh`

**Insert** ~20 lines after the "ALL GREEN: persist ledger and allow" block (after line 127, before line 130 "RED items exist"). Runs only when all evidence is GREEN.

```bash
# ─── Commit ordering check (warn-only) ───
if command -v git &>/dev/null && git rev-parse --is-inside-work-tree &>/dev/null 2>&1; then
  TASK_PATTERN=$(echo "$TASK_ID" | sed 's/[^a-zA-Z0-9-]//g')
  if [[ -n "$TASK_PATTERN" ]]; then
    FIRST_TEST_COMMIT=""
    while IFS= read -r LINE; do
      COMMIT_HASH=$(echo "$LINE" | awk '{print $1}')
      FILES=$(git diff-tree --no-commit-id --name-only -r "$COMMIT_HASH" 2>/dev/null || true)
      HAS_TEST=false; HAS_IMPL=false
      while IFS= read -r F; do
        if echo "$F" | grep -qE '(^tests/|test_|_test\.|\.spec\.|\.test\.)'; then
          HAS_TEST=true
        elif echo "$F" | grep -qE '\.(py|ts|js|tsx|jsx|go|rs)$'; then
          HAS_IMPL=true
        fi
      done <<< "$FILES"
      [[ "$HAS_TEST" == true && "$HAS_IMPL" == false ]] && FIRST_TEST_COMMIT="$COMMIT_HASH"
    done < <(git log --oneline -n 10 --grep="$TASK_PATTERN" -i 2>/dev/null || true)
    
    if [[ -z "$FIRST_TEST_COMMIT" ]]; then
      echo "post-agent-audit: WARN — no test-only commit found for ${TASK_ID}. TDD commit ordering not verified." >&2
    fi
  fi
fi
```

**Behavior:** Warn-only (never blocks). Searches last 10 commits mentioning the task ID for a test-only commit. Logs to stderr. All git ops guarded with `|| true`.

---

### Step 4: `SKILL.md` — Rewrite orchestration loop

**File:** `~/.claude/skills/lead-orchestrator/SKILL.md`

**4a. VIBE Level table (line 25):** Change `QA Cycles` row:
- `full`: `2 (C1: test + break, C2: re-test bugs)`
- `light`: `1 (C1 only)`

**4b. Orchestration Loop diagram (lines 88-92):** Replace with:
```
Task assigned → [Architect Gate] → Spawn CODER → wait for T-XXX-ready-for-review.md
  → Spawn GARRY-REVIEW subagent (report-only) → wait for T-XXX-review-findings.md
  → Findings? → Spawn CODER fix → wait for updated ready-for-review.md
  → Spawn QA TESTER C1 (test + break) → wait for T-XXX-cycle-1.md
  → Bugs found? → Spawn CODER fix → QA TESTER C2 (re-test bugs, full only)
  → COMPLETE
```

**4c. Pre-QA TDD Verification (lines 98-105):** Remove step 5 (commit ordering — now in post-agent-audit.sh). Keep steps 1-4. Rename to "Pre-QA Gates".

**4d. Add "Garry-Review Step" subsection** after Pre-QA Gates:

After coder submits ready-for-review.md and pre-QA gates pass:
1. Spawn a `general-purpose` subagent with inline prompt (not from template). Mark `GOVERNANCE_EXEMPT`.
2. Prompt reviews changes using garry-review's four categories (Architecture, Code Quality, Tests, Performance), confidence 1-10, suppress <5.
3. Output: `qa/FEAT-XXX/T-XXX-review-findings.md`.
4. If P0/P1 findings: spawn coder fix with findings file.
5. If no findings or P2 only: proceed to QA Tester.

**4e. Light-Level Shortcut (lines 113-115):** Update to new loop.

**4f. Required Artifacts table (lines 134-138):** Add review-findings row.

**4g. Subagent template table (lines 212-217):** Replace:
| Subagent | Template | Type |
|----------|----------|------|
| Coder | `templates/coder-prompt.md` | (default) |
| Architect | `templates/architect-prompt.md` | `general-purpose` |
| Garry-Review | inline prompt, `GOVERNANCE_EXEMPT` | `general-purpose` |
| QA Tester | `templates/qa-tester-prompt.md` | (default) |

**4h. Orchestration Log (lines 292-298):** Update checklist to include garry-review step.

**4i. Plan Execution Mode (line 256):** Update summary from `coder → QA C1 → QA C2` to `coder → review → QA C1 → QA C2`.

---

### Step 5: `vibe-protocol.md` — Revised rules, roles, and loop

**File:** `~/.claude/rules/vibe-protocol.md`

#### 5a. R4 (line 13)

**Current:**
```
5. **R4 2 QA Cycles** -- No merge without 2 documented review passes.
```
**New:**
```
5. **R4 2 QA Test Cycles** -- No merge without 2 QA test cycles (`full`) or 1 (`light`). QA writes and runs tests, not just reviews.
```

#### 5b. R10 (line 19)

**Current:**
```
11. **R10 QA No-Edit** -- QA NEVER edits implementation code; only writes QA artifacts.
```
**New:**
```
11. **R10 QA No-Edit** -- QA NEVER edits implementation code; only writes QA artifacts. Test files (`tests/`, `*_test.*`, `*.spec.*`, `*.test.*`) written by QA are QA artifacts, not implementation code.
```

#### 5c. VIBE Levels table R4 row (line 42)

**Current:**
```
| R4 2 QA Cycles | **Yes** | 1 pass |
```
**New:**
```
| R4 2 QA Test Cycles | **2 test cycles** | 1 test cycle |
```

#### 5d. Section 3.3 Developer (lines 93-98)

**Current:**
```
### 3.3 Developer
**Trigger:** `feat/*` worktree, phase = BUILD, assigned T-XXX.

**Invoke IN ORDER:** `superpowers:test-driven-development` -> `superpowers:verification-before-completion`

Steps: Context load -> Dependency check (R17) -> Follow Build Guidance -> For each behavior: write failing test (RED) -> run test (confirm FAIL) -> write minimal implementation (GREEN) -> run test (confirm PASS) -> refactor -> Real testing (R18) -> Output `T-XXX-ready-for-review.md` with TDD Evidence table and `ReviewCommit:<SHA>` (R11).
```

**New:**
```
### 3.3 Developer
**Trigger:** `feat/*` worktree, phase = BUILD, assigned T-XXX.

TDD protocol is inlined in the coder prompt template — no skill chain invocation needed.

Steps: Context load -> Dependency check (R17) -> Follow Build Guidance -> For each behavior: write failing test (RED) -> run test (confirm FAIL) -> write minimal implementation (GREEN) -> run test (confirm PASS) -> refactor -> Real testing (R18) -> Output `T-XXX-ready-for-review.md` with TDD Evidence table and `ReviewCommit:<SHA>` (R11).
```

#### 5e. Section 3.4 QA Auditor → QA Tester (lines 100-113)

**Current:**
```
### 3.4 QA Auditor
**Trigger:** Developer claims T-XXX complete. QA NEVER edits implementation code (R10).

**Invoke IN ORDER:** `garry-review` -> `feature-dev:code-reviewer` -> `/qa`
**Also read:** `~/.claude/docs/vibe-manual.md` SS5 (QA verification checklist + automated review gates).

**Auto-Reject (P0):** mock on internal module | no SavepointConnection | test without real path | uncaptured warnings (P1) | entire core dependency mocked | missing TDD Evidence (no exemption)
**Severity:** P0 = must fix. P1 = should fix, escalate if stuck. P2 = log to `docs/backlog.md`.

**2 cycles, sequential** (C1 must PASS before C2):
- **C1 (Security & Logic, P0 gate):** garry-review -> code-reviewer -> /qa. Verify contracts (R7), auto-reject criteria (R18). Output `T-XXX-cycle-1.md`.
- **C2 (Quality & Resilience):** naming, duplication, edge cases, failure modes. Output `T-XXX-cycle-2.md`.

Re-run failing cycle after fix. N=1 escalation (R13).
```

**New:**
```
### 3.4 QA Tester
**Trigger:** Developer claims T-XXX complete. QA writes tests and tries to break the feature (R10 — test files are QA artifacts).

QA Tester uses the unified `qa-tester-prompt.md` template. No skill chain invocation.

**Protocol:** Read PRD → review tests against requirements 1:1 (add missing tests) → run `make test` (hard gate — fail = immediate FAIL) → exercise feature manually → try to break with edge cases → produce bug report.

**Auto-Reject (P0):** mock on internal module | no SavepointConnection | test without real path | uncaptured warnings (P1) | entire core dependency mocked | missing TDD Evidence (no exemption)
**Severity:** P0 = must fix. P1 = should fix, escalate if stuck. P2 = log to `docs/backlog.md`.

**2 test cycles, sequential** (C1 must PASS before C2):
- **C1 (Test + Break):** Full testing protocol. Write missing tests, run suite, exercise feature, try to break it. Output `T-XXX-cycle-1.md`.
- **C2 (Re-test bugs, `full` only):** Re-test ONLY bugs found in C1. Verify each fix. Run regression. Output `T-XXX-cycle-2.md`.

Re-run failing cycle after fix. N=1 escalation (R13).
```

#### 5f. Section 4.1 Deterministic Loop (lines 126-142)

**Current:**
```
### 4.1 Deterministic Loop

Subagents share NO context -- communication via committed artifacts under `qa/FEAT-XXX/`.

\```
For each T-XXX (respecting depends_on):
  1. ARCHITECT (skip if trivial): spawn code-architect -> file-level design -> STOP
  2. CODER: spawn subagent using superpowers:test-driven-development to write failing test -> then do R/G TDD -> T-XXX-ready-for-review.md -> then superpowers:verification-before-completion -> STOP.
  3. QA C1 (P0 gate): spawn code-reviewer -> garry-review + code-reviewer + /qa
     -> T-XXX-cycle-1.md -> STOP
  4. IF C1 FAIL: fix -> re-run C1 -> if still fail ESCALATE (N=1)
  5. QA C2: spawn code-reviewer -> quality checks -> T-XXX-cycle-2.md -> STOP
  6. IF C2 FAIL: fix P1 (P2 -> backlog) -> re-run C2 -> if still fail ESCALATE
  7. ON PASS: git add -A && git commit && git push; update progress log
\```

**Skip Architect:** setup/config, bash commands, rote tasks, or Build Guidance already file-level specific.
```

**New:**
```
### 4.1 Deterministic Loop

Subagents share NO context -- communication via committed artifacts under `qa/FEAT-XXX/`.

\```
For each T-XXX (respecting depends_on):
  1. ARCHITECT (skip if trivial): spawn code-architect → file-level design → STOP
  2. CODER: TDD inlined in prompt → R/G/R → T-XXX-ready-for-review.md → STOP
  3. REVIEW: spawn garry-review subagent (report-only) → T-XXX-review-findings.md → STOP
  4. IF FINDINGS: spawn coder fix (with findings file) → STOP
  5. QA TESTER C1 (test + break): write tests → run suite → exercise feature → try to break → T-XXX-cycle-1.md → STOP
  6. IF C1 FAIL: coder fix → re-run C1 → if still fail ESCALATE (N=1)
  7. QA TESTER C2 (full only): re-test C1 bugs only → T-XXX-cycle-2.md → STOP
  8. IF C2 FAIL: coder fix → re-run C2 → if still fail ESCALATE
  9. ON PASS: git add -A && git commit && git push; update progress log
\```

**Skip Architect:** setup/config, bash commands, rote tasks, or Build Guidance already file-level specific.
```

#### 5g. Section 4.2 Spawning Model (lines 144-148)

**Current:**
```
### 4.2 Spawning Model

**Within-task (architect -> coder -> C1 -> C2): FOREGROUND (blocking).** Each step waits for prior artifact.
**Cross-task independent pipelines: BACKGROUND (`run_in_background: true`).** Orchestrator monitors artifacts.
**Rule:** C1 and C2 are always sequential -- C2 depends on C1's findings.
```

**New:**
```
### 4.2 Spawning Model

**Within-task (architect → coder → review → fix → C1 → C2): FOREGROUND (blocking).** Each step waits for prior artifact.
**Cross-task independent pipelines: BACKGROUND (`run_in_background: true`).** Orchestrator monitors artifacts.
**Rule:** C1 and C2 are always sequential -- C2 re-tests only C1's bugs.
```

#### 5h. Section 8 Subagent Mapping (lines 188-201)

**Current:**
```
| Phase | Subagent Type | Mandatory Skills | Output |
|-------|---------------|-----------------|--------|
| **Orchestrate** | `lead-orchestrator` | N/A -- **never feature-dev** | Task coordination |
| Explore | `feature-dev:code-explorer` | N/A | Patterns, dependencies report |
| Architect (Feature) | `eng-planning` | + `/plan-eng-review`; if UI: + `/plan-design-review` | Arch docs, contracts, FEAT design docs |
| Architect (Task) | `feature-dev:code-architect` | N/A | Files to create/modify, test mapping |
| Implement | `feature-dev:feature-dev` | `superpowers:test-driven-development` then `superpowers:verification-before-completion` | Code + tests + `T-XXX-ready-for-review.md` |
| QA | `feature-dev:code-reviewer` | `garry-review` -> `feature-dev:code-reviewer` -> `/qa` | `T-XXX-cycle-1.md`, `T-XXX-cycle-2.md` |
| Debug | `/investigate` | Fallback: `superpowers:systematic-debugging` | Diagnosis + fix |
| Fix Bugs | `feature-dev:feature-dev` | Same as Implement | Targeted fixes |
```

**New:**
```
| Phase | Subagent Type | Mandatory Skills | Output |
|-------|---------------|-----------------|--------|
| **Orchestrate** | `lead-orchestrator` | N/A -- **never feature-dev** | Task coordination |
| Explore | `feature-dev:code-explorer` | N/A | Patterns, dependencies report |
| Architect (Feature) | `eng-planning` | + `/plan-eng-review`; if UI: + `/plan-design-review` | Arch docs, contracts, FEAT design docs |
| Architect (Task) | `feature-dev:code-architect` | N/A | Files to create/modify, test mapping |
| Implement | `feature-dev:feature-dev` | TDD inlined in coder prompt | Code + tests + `T-XXX-ready-for-review.md` |
| Review | `general-purpose` | `GOVERNANCE_EXEMPT`, inline garry-review prompt | `T-XXX-review-findings.md` |
| QA Test | `qa-tester-prompt.md` | Verification gate inlined | `T-XXX-cycle-1.md`, `T-XXX-cycle-2.md` |
| Debug | `/investigate` | Fallback: `superpowers:systematic-debugging` | Diagnosis + fix |
| Fix Bugs | `feature-dev:feature-dev` | TDD inlined in coder prompt | Targeted fixes |
```

---

### Step 6: `vibe-manual.md` — Update artifact templates and QA checklists

**File:** `~/.claude/docs/vibe-manual.md`

#### 6a. Section 4.3 QA Cycle File Templates (lines 106-138)

**Current:** Two separate templates — cycle-1 (Security & Logic) and cycle-2 (Quality & Resilience) with code-review-oriented format.

**Replace with one unified QA test report format:**

```markdown
### 4.3 QA Test Report Format

QA Tester produces `qa/FEAT-XXX/T-XXX-cycle-{1|2}.md`:

\```markdown
Task: T-XXX
STATUS: PASS|FAIL
Mode: cycle-1|cycle-2
CommandsRun: make test; [manual verification commands]
ReviewCommit: <SHA>

## Tests Written
- [test_file:line] — tests [requirement/behavior]

## Test Results
[test output summary — pass count, fail count, duration]

## Bugs Found
1) <file:line> — <description> — <P0|P1|P2> — <repro steps>

## Verification Evidence
REQ-XX: [evidence of testing this requirement]
\```

**Cycle 1** (all modes): Full testing protocol — write missing tests, run suite, exercise feature, try to break it with edge cases.

**Cycle 2** (`full` only): Re-test ONLY bugs from cycle-1. Verify each fix. Run regression suite. Report remaining failures.
```

#### 6b. Section 5.1 Mandatory Verification Items (lines 144-175)

**Keep all 6 items unchanged.** Update item 6 (TDD Compliance, lines 170-174) to add:

```
- Commit ordering (test-only commit before implementation) is now checked automatically by post-agent-audit.sh
```

#### 6c. Section 5.2 Automated Code Review Gates (lines 176-200)

**Keep** the schema alignment script (lines 180-194) and bypass rule (line 195).

**Update** the "Additional auto-reject criteria" (lines 197-200) to note these are now enforced by the QA Tester template directly:

```markdown
**Additional auto-reject criteria (enforced by QA Tester template):**
- TDD Evidence section missing or empty (no exemption declared)
- Implementation committed without corresponding test (checked by post-agent-audit.sh commit ordering)
- Test exhibits any anti-pattern from Section 6.5 (testing impl details, interdependent tests, insufficient assertions, mock-heavy, catch-all errors)
```

#### 6d. Section 5.3 Recommended Verification Items (lines 202-216)

**Rename** from "Recommended Verification Items (Cycle 2 - P1/P2)" to "Recommended Verification Items (All Cycles)".

**Keep all 3 items** (Code Quality, Error Handling, READ-WRITE Consistency). Add note:

```
These items are addressed by the QA Tester's "try to break it" step (Step 4 in the testing protocol) and by the garry-review subagent's code quality review.
```

---

### Step 7: Delete old templates

```bash
rm ~/.claude/skills/lead-orchestrator/templates/qa-cycle1-prompt.md
rm ~/.claude/skills/lead-orchestrator/templates/qa-cycle2-prompt.md
```

---

### Step 8: Stale reference sweep

Grep all modified files + any other files in `~/.claude/` for:
- `qa-cycle1-prompt`, `qa-cycle2-prompt`
- `superpowers:test-driven-development`, `superpowers:verification-before-completion` (in coder/orchestrator context — leave debugging references alone)
- `feature-dev:code-reviewer` in QA context
- `Invoke skill:` in coder template
- `QA Auditor` → should now be `QA Tester`
- `QA C1`, `QA C2` in old "Security & Logic" / "Quality & Resilience" sense

---

## Governance Hooks — No Changes Needed

**post-agent-audit.sh:** Works unchanged. Only checks `REQ-XX: <evidence>` patterns in `tool_result` — agnostic to template names. New commit-ordering check is additive (warn-only).

**pre-agent-gate.sh:** Works unchanged. Checks `## Mandatory Context`, `## Requirement Map`, `## Constraints` — all present in new qa-tester-prompt.md.

**role-enforcement.sh:** Works unchanged. QA Tester runs as subagent (has `agent_id`), so role enforcement skips it entirely. Garry-review also runs as subagent. Only the orchestrator is constrained.

**roles.json:** No changes. Only governs orchestrator (top-level agent without `agent_id`).

---

## Verification Plan

1. **Template governance:** Fill coder-prompt.md and qa-tester-prompt.md with sample placeholders, verify pre-agent-gate.sh passes all 3 checks
2. **Commit-ordering:** Run post-agent-audit.sh with sample evidence, verify warn/no-warn behavior
3. **Stale reference sweep:** Grep all modified files for old terms
4. **Cross-doc consistency:** Verify loop description matches across SKILL.md (Step 4), vibe-protocol.md §4.1 (Step 5f), and vibe-manual.md (Step 6a)
5. **Role enforcement:** Confirm QA Tester subagent bypasses role-enforcement.sh (has agent_id)
