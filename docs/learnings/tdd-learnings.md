# TDD Enforcement Audit — Research Findings

**Date:** 2026-05-10
**Pipeline:** 3 Sonnet auditors (parallel) → Opus synthesis → Codex adversarial review (42 findings) → YAGNI trim → hard-gate rebalancing
**Final plan:** `docs/plans/improve-tdd.md` (v4, 164 lines, 6 changes / 3 files)

---

## Auditor A: TDD Enforcement Gaps

**Focus:** Does lead-orchestrator actually enforce red/green TDD?

### Findings (7 total, 2 CRITICAL)

1. **CRITICAL — Orchestrator cannot verify red phase occurred.** Coder subagent is a black box. Orchestrator's only check is whether `T-XXX-ready-for-review.md` exists (`SKILL.md:88-96`). It never reads the file. Coder could write implementation first, then tests, then fabricate the TDD Evidence table.

2. **CRITICAL — QA template auto-reject list missing TDD Evidence.** `qa-cycle1-prompt.md:40-46` lists 5 auto-reject criteria (mocks, SavepointConnection, etc.). TDD Evidence is absent. `vibe-manual.md:174` says "missing TDD evidence = P0 FAIL" but this rule never made it into the template agents actually read.

3. **CRITICAL — No orchestrator-level TDD verification before QA spawn.** `SKILL.md:123-148` has spec-diff verification for requirements but nothing for TDD. The wait condition is purely "does the artifact file exist?"

4. **MEDIUM — Micro-commits encouraged, not enforced.** `vibe-protocol.md` R6 says "encouraged." Neither SKILL.md nor coder-prompt.md mentions them. Without micro-commits, the only audit trail is the self-reported TDD Evidence table.

5. **HIGH — QA templates don't instruct git log or tool-call ordering checks.** `vibe-manual.md:173` says "verify via git log or tool-call ordering" but no QA template includes this step.

6. **HIGH — Governance hooks have no TDD assertions.** `pre-agent-gate.sh` checks prompt structure. `post-agent-audit.sh` checks REQ-XX evidence. Neither references TDD.

7. **MEDIUM — TDD enforcement delegated to black-box skill.** `superpowers:test-driven-development` is the primary enforcement. If coder skips it, orchestrator has no fallback.

**Verdict:** Lead-orchestrator claims TDD but does not enforce it. Three critical breaks: coder is a black box, QA templates omit TDD checks, governance hooks are TDD-blind.

---

## Auditor B: QA Testing Reality

**Focus:** Does QA do real testing or just code review?

### Findings (10 total, 3 CRITICAL)

1. **CRITICAL — QA cycle is structurally code review.** Mandatory first steps (`qa-cycle1-prompt.md:14-16`): `garry-review` (code review) and `code-reviewer` (code review). No test execution anywhere. `/qa` in the chain is the gstack browser testing skill — UI smoke testing, not unit/integration.

2. **CRITICAL — `CommandsRun: make test` is documentation, not enforcement.** `vibe-manual.md:114` shows it as a template field. Neither QA template instructs the agent to run it. The agent fills it in — possibly fabricating it.

3. **CRITICAL — Auto-reject criteria are read, not verified.** The criterion "uncaptured warnings in pytest output" (`qa-cycle1-prompt.md:45`) is literally unverifiable without running pytest. QA has no instructions to run pytest.

4. **HIGH — QA does not re-run the test suite.** Coder's `CommandsRun: make test (PASS)` is trusted. No independent verification.

5. **HIGH — Missing tests not reliably detectable.** TDD Evidence table presence is checkable, but fabricated content is not. Evidence rows like `Edit#3 -> Bash#4 (FAIL)` are self-reported with no external verification.

6. **HIGH — R18 real-testing verification is static, not runtime.** QA checks for `SavepointConnection` by reading source, not running tests. Won't catch mocks via dependency injection, in-memory DB overrides, or no-op fixtures.

7. **HIGH — "Verify" conflated with "test" throughout.** The system uses "verify" to mean "read and assess." Three definitions of "testing" are never disambiguated: (a) running pytest, (b) browser smoke testing, (c) code inspection for test quality.

8. **MEDIUM — E2E testing is real but only at FEAT boundary.** `SKILL.md:280-358` E2E Suite Mode runs against a live Docker stack. But it triggers at FEAT completion, not per-task. Individual task QA is review-only.

9. **MEDIUM — Production build verification in manual, not in templates.** `vibe-manual.md:163-167` says build must pass. Neither QA template references it.

10. **MEDIUM — garry-review interactive model conflicts with autonomous QA.** garry-review requires `AskUserQuestion`. QA subagents are autonomous and STOP-bounded. Deadlock risk.

**Verdict:** QA is code review wearing a testing hat. The only real test execution is: (1) coder running `make test` (self-reported), and (2) FEAT-level E2E Suite Mode (separate concern).

---

## Auditor C: Strengthening Proposals

**Focus:** Where and how to strengthen TDD enforcement.

### TDD Touchpoint Audit

| Location | Classification |
|----------|---------------|
| vibe-protocol R2 ("mandatory") | HARD GATE (text only) |
| vibe-protocol R6 (micro-commits) | SOFT (encouraged) |
| vibe-protocol 3.3 Developer steps | HARD GATE (text only) |
| vibe-manual 4.2 TDD Evidence table | HARD GATE (artifact format) |
| vibe-manual 5.1 QA checklist | SOFT (QA should do, not automated) |
| coder-prompt.md ("NEVER skip") | HARD GATE (instruction only) |
| qa-cycle1-prompt.md auto-reject | HARD GATE (5 criteria, none TDD) |
| pre-agent-gate.sh | MACHINE-ENFORCED — **no TDD checks** |
| post-agent-audit.sh | MACHINE-ENFORCED — **no TDD checks** |

**Key insight:** Every hard gate for TDD is text-based. The two machine-enforced gates (governance hooks) govern requirement coverage only.

### Proposals by priority

**P0 (must have, LOW complexity):**
- P0-A: Machine-check TDD Evidence in post-agent-audit
- P0-B: QA C1 must run tests independently
- P0-C: Requirement Map done_when cross-references test names

**P1 (should have, MEDIUM complexity):**
- P1-A: [RED]/[GREEN] commit prefix convention + orchestrator spot-check
- P1-B: TDD Evidence table with red_sha/green_sha columns
- P1-C: TDD-EXEMPT declarations require QA scrutiny
- P1-D: QA test re-run must be independent (two-summary artifact)

**P2 (nice to have, HIGH complexity):**
- P2-A: Pre-commit git hook for test-before-implementation
- P2-B: Timestamp-based commit ordering via SHA pairs
- P2-C: Test count regression gate

---

## Opus Synthesis — Consensus & Disagreements

### All 3 auditors agreed on:
1. Orchestrator cannot verify TDD ordering (black box)
2. QA auto-reject lists omit TDD Evidence
3. Governance hooks have zero TDD assertions
4. QA does not run the test suite
5. Micro-commits encouraged, not enforced
6. TDD Evidence table is self-attested

### Disagreements resolved:
- **garry-review interactive conflict:** Real issue, but QA tooling concern, not TDD. Separate plan.
- **Micro-commits: git hook vs convention:** Convention wins. Hook is too high-friction.
- **QA running tests independently:** Yes. Two-summary artifact format (coder-reported vs QA-verified).
- **SHA pairs vs tool-call refs:** SHA pairs are gold standard but depend on micro-commits.

---

## Codex Adversarial Review — 42 Findings

### Critical hits (accepted)

| # | Finding | Disposition |
|---|---------|------------|
| 1 | Plan enforces TDD-looking artifacts, not TDD | ACCEPT — executive summary rewritten |
| 2 | Confuses "evidence exists" with "behavior occurred" | ACCEPT — honest language throughout |
| 3 | git log HEAD~15 is wrong syntax | ACCEPT — fixed to git log -n 20 |
| 6 | QA rerunning tests verifies correctness, not TDD | ACCEPT — separated quality vs TDD concerns |
| 8 | Assumes agents will obey new instructions better than old | PARTIAL — added external checks |
| 10 | post-agent-audit change is theater | ACCEPT — dropped entirely in v4 |
| 42 | Warnings != enforcement. If it matters, block. | ACCEPT |

### Redundancy findings (accepted)

| # | Finding |
|---|---------|
| 11 | F-001/F-002/F-004/F-007 are the same root cause |
| 12 | F-003 and F-009 overlap |
| 13 | F-005 and F-006 are tightly coupled |
| 14 | F-008 is not a finding |
| 15 | F-010 is out of scope |

### Rejected (2 of 42)

| # | Finding | Rejection reason |
|---|---------|-----------------|
| 23 | No history rewrite protection | R15 already covers this. Codex missed it. |
| 25 | No check that GREEN is minimal | Inherently subjective. QA code review handles it. |

### Over-engineering proposals (cut by YAGNI)

| # | Codex proposal | Cut reason |
|---|---------------|-----------|
| 5 | Verify RED commits actually fail | Phase 2 complexity |
| 24 | RED commits must contain only test files | Fuzzy boundary |
| 27 | Check for skipped tests | QA code review catches this |
| 28 | Mutation/resistance testing | Disproportionate |
| 37 | Structured TDD evidence with 6 fields | Over-engineering |
| 38 | QA checkout each red_sha and run test | Enormous complexity |
| 39 | Reject RED commits with impl files | Cut in YAGNI pass |
| 40 | Run tests against parent/base commit | Equivalent to SHA checkout |
| 41 | Machine-readable requirement-to-test map | Already exists partially |

---

## Post-YAGNI Rebalancing — Hard Gate Analysis

v3 YAGNI overcorrected: zero machine-enforced checks. Every gate was instruction-based, meaning enforcement depended on agents following instructions — the problem we're solving.

### Option A: Governance hook (post-agent-audit.sh) — DROPPED
- Grep baton file for TDD Evidence in the hook.
- **Fatal flaw:** Hooks fire after every subagent (coder, QA, architect) with no role context. Can't target coder-completion only. REQ-XX check works because it reads subagent text output (role-implicit). TDD Evidence is a file on disk — the hook needs to know which role ran and which baton is current vs stale. Requires fragile prompt parsing or env var coupling.

### Option B: Orchestrator runs make test — ADOPTED (Phase 1)
- Orchestrator executes make test after reading baton, before spawning QA. Exit != 0 -> re-spawn coder.
- **Why it wins:** Only check where a machine runs code and checks an exit code. Orchestrator has full role context. Creates two independent test execution points: orchestrator (hard gate) + QA (instruction-based).
- **Proves:** Tests pass. **Doesn't prove:** TDD ordering.

### Option C: Separate test/impl commits — ADOPTED (Phase 2, optional)
- Coder commits test files first, then implementation. Orchestrator checks git log for test-only commit preceding impl.
- **Why optional:** Only check that verifies TDD ordering. But requires workflow change, and test/impl file boundary is fuzzy. Warn-not-block to avoid false positives.

---

## Final Resolution (v4)

**6 changes, 3 files:**

Phase 0 (instruction-based, 15 min):
1. qa-cycle1-prompt.md: "TDD Evidence missing = P0" in auto-reject
2. qa-cycle1-prompt.md: "Run make test independently" in mandatory steps
3. qa-cycle1-prompt.md: "TDD-EXEMPT on logic files = P0" in auto-reject

Phase 1 (hard gate, 20 min):
4. SKILL.md: Pre-QA gate — read baton, re-spawn coder if evidence missing
5. SKILL.md: **Orchestrator runs make test** — exit code blocks QA spawn

Phase 2 (optional workflow change):
6. coder-prompt.md: Separate test/impl commits
7. SKILL.md: git log check for test-first commit (warn, not block)

### Enforcement layers

| Check | Type | Proves |
|-------|------|--------|
| TDD Evidence auto-reject | Instruction (QA) | Evidence produced |
| TDD-EXEMPT scrutiny | Instruction (QA) | Exemptions legitimate |
| QA runs make test | Instruction (QA) | Tests pass (independent) |
| Orchestrator reads baton | Instruction (Orch) | Evidence exists before QA |
| **Orchestrator make test** | **Machine (hard gate)** | **Tests pass (deterministic)** |
| Test-first commits | Instruction (Orch) | Tests committed before impl |

### Key principles

1. **Threat model matters.** Sloppy agents need guardrails. Deceptive agents need surveillance. Build for sloppy.
2. **One hard gate beats many soft ones.** Orchestrator running make test is worth more than post-agent-audit, SHA verification, and commit constraints combined.
3. **Put enforcement where role context exists.** Governance hooks are role-blind. Orchestrator knows it just received a coder artifact.

---

## Section 8: Superpowers Dependency Audit (2026-05-10)

**Question:** How much value do `superpowers:test-driven-development` and `superpowers:verification-before-completion` add to `/lead-orchestrator`, given our own enforcement layers?

**Comparison baseline:** [affaan-m/everything-claude-code](https://github.com/affaan-m/everything-claude-code) `agents/tdd-guide.md` + `skills/tdd-workflow/SKILL.md`

### Where Superpowers Are Invoked

| Template | Superpowers Skill | Purpose |
|----------|------------------|---------|
| `coder-prompt.md` | `superpowers:test-driven-development` | TDD enforcement on coders |
| `coder-prompt.md` | `superpowers:verification-before-completion` | Evidence-before-claims gate |

QA templates invoke `garry-review` and `feature-dev:code-reviewer` — separate skills, not superpowers.

### What Each Superpowers Skill Provides

**`superpowers:test-driven-development` (371 lines):**
- Iron Law: "NO PRODUCTION CODE WITHOUT A FAILING TEST FIRST"
- Gate Function: Code before test → delete and start over
- 11-row rationalization prevention table
- 13 red flags triggering mandatory restart
- 8-point pre-commit verification checklist
- 3 narrow exceptions (throwaway prototypes, generated code, config — all require PM permission)
- References `testing-anti-patterns.md` catalog

**`superpowers:verification-before-completion` (140 lines):**
- Iron Law: "NO COMPLETION CLAIMS WITHOUT FRESH VERIFICATION EVIDENCE"
- 5-step gate function (identify → run → read → verify → claim)
- 7-row common failures table
- 8 red flags (STOP triggers)
- 8-row rationalization prevention table
- Rooted in "24 failure memories" — battle-tested

### What Lead-Orchestrator Already Covers Without Superpowers

| Mechanism | Location | Overlap? |
|-----------|----------|----------|
| TDD Evidence table required in ready-for-review.md | SKILL.md §Pre-QA TDD Verification | Partial — verifies TDD happened, not HOW |
| `make test` must pass before QA spawn | SKILL.md line 104 | Full overlap with verification-before-completion |
| Test-only commit before implementation commit | coder-prompt.md commit protocol | Full overlap with TDD commit ordering |
| Auto-reject: missing TDD Evidence | qa-cycle1-prompt.md | Post-hoc check — doesn't prevent violation |
| Auto-reject: mocking internals, no real DB | qa-cycle1-prompt.md | Covered by both TDD skill and CLAUDE.md |
| Spec-diff verification | SKILL.md §Spec-Diff | Full overlap with verification-before-completion |
| N=1 escalation | SKILL.md §Escalation | No overlap (orchestrator-specific) |

### Comparison: Our System vs. External (affaan-m/everything-claude-code)

| Dimension | Our Implementation | External TDD Guide + Workflow |
|-----------|-------------------|-------------------------------|
| Enforcement depth | Iron Laws + deletion gates + rationalization tables + QA auto-reject | Coverage threshold (80%) + checklist + anti-patterns list |
| Behavioral anchoring | "Delete it. Start over." — visceral consequence | "Tests are a safety net" — motivational framing |
| Exception handling | 3 narrow exceptions, all require PM permission | Not addressed |
| Anti-rationalization | 11 explicit rationalizations with counters | 4 bullet "pitfalls to avoid" |
| Multi-agent enforcement | Coder enforces → QA verifies → Orchestrator gates on evidence | Single-agent workflow only |
| Commit protocol | Test-only commit → impl commit (enforced by QA) | "Create commits after RED/GREEN" (advisory) |
| Verification | Separate 140-line skill with its own Iron Law | Step 5: "Rerun tests" (1 sentence) |
| Coverage metric | Not numerically gated — relies on QA judgment | Hard 80% threshold |
| Complexity | ~511 lines across 2 superpowers skills | ~180 lines total |
| Eval-driven TDD | Not present | v1.8: pass@1/pass@3 metrics |

### Superpowers Value Rating: 3 / 5

**Scoring breakdown:**

| Factor | Impact |
|--------|--------|
| Adds unique behavioral enforcement (rationalization tables, deletion gates) | +2 |
| Prevents pre-QA false-done claims (verification skill) | +1 |
| Orchestrator already catches failures post-hoc via auto-reject + make test | -1 |
| Context bloat (511 lines loaded into every coder subagent) degrades instruction adherence | -1.5 |
| Redundancy with orchestrator's own commit protocol + spec-diff gates | -0.5 |

### Pros of Keeping Superpowers

1. **Defense in depth** — Coder-level (superpowers) + post-hoc QA (orchestrator) catch at different stages
2. **Rationalization prevention is genuinely novel** — 11-row table has no equivalent in orchestrator templates
3. **Verification-before-completion prevents trust cascade** — Without it, coders can claim "done" without fresh evidence
4. **Battle-tested** — "24 failure memories" basis means non-theoretical

### Cons / Costs

1. **Context bloat** — 511 lines into every coder subagent, competing with 68-line task templates
2. **Redundancy** — Commit protocol, auto-reject, `make test` gate already enforce same outcomes externally
3. **Instruction adherence risk** — More instructions = lower compliance probability; 3 clear rules > 30 overlapping ones
4. **Skill invocation overhead** — Two `Skill` tool calls add latency + context switch before actual work begins
5. **No coverage metric** — External's 80% threshold is a concrete gate we lack entirely
6. **Impractical deletion gate** — "Delete code, start over" is cost-prohibitive in bounded subagent contexts

### Recommendation

| Option | Description | Tradeoff |
|--------|-------------|----------|
| **A (Lean)** | Strip both superpowers from coder-prompt.md. Rely on orchestrator external gates. | Accepts higher fix-loop rate |
| **B (Targeted)** | Keep `verification-before-completion` only (140 lines, high signal). Drop TDD skill — inline 3 strongest rules into coder-prompt.md: (1) test FIRST or delete, (2) test-only commit before impl commit, (3) if test passes immediately, investigate | Best complexity/value ratio |
| **C (Status Quo)** | Keep both. Accept context cost. | Strongest guarantee, highest bloat |

**Lean recommendation: Option B.** Verification skill is tight (140 lines, high ROI). TDD skill is mostly redundant with what QA auto-reject + commit protocol already enforce externally — and its 371-line context load actively hurts instruction adherence for the 68-line coder template it's supposed to support.

---

## Section 9: Role-Separated TDD — QA-Writes-RED Proposal (2026-05-10)

### Context

Multi-agent review of lead-orchestrator revealed that all "test first" enforcement is self-reported by the coder subagent. The TDD Evidence table proves structure (rows exist) not temporal sequence (test preceded implementation). This section explores whether separating test authorship from implementation authorship provides cryptographic TDD proof.

### The Proposal: London School / Acceptance-Test-Driven in Multi-Agent Context

```
Current:  Architect → Coder (RED+GREEN) → QA (review)
Proposed: Architect → QA-TestWriter (RED) → Coder (GREEN + unit RED/GREEN) → QA (review)
```

QA-TestWriter reads PRD/spec, writes acceptance/integration tests asserting observable behavior, commits RED (provably pre-implementation by different author + earlier timestamp). Coder receives failing tests + implements to turn them GREEN + writes unit tests for internal logic.

### Where It Works

**Integration/acceptance tests from spec.** These don't need implementation knowledge:
- "POST /api/widget returns 201 with these fields"
- "clicking Save persists to DB"
- "invalid input shows error message X"

Tests are pure spec→assertion. Coder can't game temporal ordering — RED commits exist before they start, authored by different agent.

### Where It Breaks Down

**Unit tests need architectural decisions.** Can't write `test_parse_widget_config()` until architect decides that function exists. If QA writes unit tests blind:
- Tests prescribe HOW, not WHAT (constraining coder's design space)
- Tests don't match actual module boundaries architect chose
- Coder rewrites tests anyway → defeats purpose

### Practical Hybrid Architecture

| Step | Agent | Writes | Commits |
|------|-------|--------|---------|
| 1 | Architect | Interface contracts, file/function design | — |
| 2 | QA-TestWriter | Acceptance tests from PRD + interface-level integration tests from contracts | RED (provably pre-impl) |
| 3 | Coder | Implementation + unit tests for internal logic | GREEN (acceptance) + RED→GREEN micro (unit) |
| 4 | QA-Reviewer | Review artifacts | cycle-1.md, cycle-2.md |

This gives:
- **Cryptographic TDD proof** for acceptance layer (different author, earlier timestamp)
- **Self-reported TDD** for unit tests only (~30% of test surface)
- **Spec fidelity** — QA writes from PRD, tests requirements not implementation details

### Implementation Cost

Requires:
1. New template: `test-author-prompt.md` (QA role, writes from spec, commits RED)
2. Orchestrator loop adds step between architect and coder
3. Coder prompt change: "These acceptance tests exist and MUST pass. Write unit tests for internal logic using TDD."
4. Pre-QA gate: verify commits from QA-TestWriter precede coder's implementation commits (SHA comparison)

### Trade-off Analysis

| Factor | Current System | QA-Writes-RED |
|--------|---------------|---------------|
| Temporal proof | None (self-reported) | Strong for acceptance, self-reported for unit |
| Latency | Architect → Coder → QA | Architect → QA-TestWriter → Coder → QA (+1 sequential spawn) |
| Spec fidelity | Tests may drift from requirements | Acceptance tests ARE the requirements |
| Coder freedom | Full (write any tests) | Constrained by pre-existing acceptance tests |
| Gaming resistance | Low (backfill evidence table) | High for acceptance layer |

### Simpler Alternative: Commit-Ordering Hook

20 lines of bash in `post-agent-audit.sh` — parse `git log --name-only` and verify test files appear in earlier commits than implementation files. Weaker than role separation (same author can still fabricate ordering) but zero latency cost.

**Already documented in Final Resolution Phase 2** as warn-not-block with fuzzy file boundaries. The role-separation proposal is structurally stronger because it removes same-author gaming entirely for the acceptance test layer.

### Decision Status

**OPEN.** Not yet adopted. Key question: does the latency cost of +1 sequential agent spawn per task justify the enforcement gain, given that LLM coders following `superpowers:test-driven-development` already tend to write tests first (the failure mode is rare)?

### Relationship to Existing Findings

- Extends Auditor A Finding 1 (black-box coder) with a structural solution
- Extends Final Resolution Phase 2 (commit ordering) with cross-author proof
- Does NOT conflict with Section 8 recommendation (Option B: drop TDD skill) — acceptance tests from QA-TestWriter replace the need for coder-side TDD skill enforcement
