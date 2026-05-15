# everything-claude-code vs ~/.claude/ — Comparative Study

> **Date:** 2026-05-10
> **Source:** https://github.com/affaan-m/everything-claude-code/tree/main
> **Method:** 3-agent parallel exploration (repo crawler, local inventory, episodic memory search)
> **Focus:** TDD enforcement + harness optimization

---

## TDD — Deep Comparison

### ECC's TDD Stack (3 layers)

**Layer 1 — `tdd-workflow` skill** (7-step workflow):
1. Write user journey tests from acceptance criteria
2. Write unit tests for each function (Arrange-Act-Assert)
3. Write integration tests for service boundaries
4. Run RED — all tests must fail
5. Write minimal implementation to pass
6. Run GREEN — all tests must pass
7. Verify 80%+ coverage

Includes concrete mock examples for Supabase, Redis, OpenAI. Git checkpoint commits at RED, GREEN, and refactor stages.

**Layer 2 — `tdd-guide` agent** (delegatable persona):
- 5-step RED-GREEN-REFACTOR enforcement
- 3 test types required: unit, integration, E2E (Playwright)
- Edge case mandate: null/undefined, empty collections, boundary values, concurrency, large datasets
- Anti-pattern catalog: testing implementation details, interdependent tests, insufficient assertions
- **Eval-driven development** (v1.8): define evals before coding, pass@1/pass@3 stability metrics

**Layer 3 — `rules/common/testing.md`** (always-loaded):
- Arrange-Act-Assert pattern enforced
- Descriptive naming: `"returns empty array when no markets match query"`
- Proactive tdd-guide invocation for new features and test failures
- Debugging priority: test isolation > mock accuracy > implementation fixes

### Our TDD Stack (4 layers, enforcement broken)

**Layer 1 — `code-style.md`**: "TDD MANDATORY: Red -> Green -> Refactor"
**Layer 2 — `vibe-protocol.md R2`**: Hard gate with TDD Evidence table artifact
**Layer 3 — `vibe-manual.md SS4.2`**: TDD Evidence table format (Behavior/Test file:line/Red/Green columns)
**Layer 4 — `superpowers:test-driven-development` skill**: Invoked by Developer role

**Enforcement chain failures** (from 2026-05-10 audit):
1. Orchestrator checks `T-XXX-ready-for-review.md` exists but never reads it, never runs tests
2. QA auto-reject checklist has 5 criteria — none mention TDD Evidence
3. Zero machine-enforced gates — every TDD check is instruction-based

**Fix plan** (`docs/plans/improve-tdd.md` v4, 6 changes across 3 files):
- Phase 0: Add TDD Evidence to auto-reject, require QA to run `make test`, scrutinize TDD-EXEMPT
- Phase 1: Orchestrator reads baton, verifies evidence, runs `make test` (hard gate)
- Phase 2: Test-first commit ordering via git log verification

### TDD Feature-by-Feature

| Aspect | ECC | Ours | Assessment |
|---|---|---|---|
| Workflow definition | 7-step skill with examples | VIBE R2 + manual SS4.2 artifact format | ~Parity |
| Machine enforcement | **None** — all instruction-based | **None yet** — but Phase 1 plan has `make test` gate | Both weak; our plan is better |
| Eval-driven development | pass@k metrics, stability scoring | **Missing entirely** | **Adopt** |
| Test type diversity | Unit/integration/E2E templates with mock examples | E2E-focused, "NO mocks in E2E" is stricter | Our E2E policy is stronger |
| Evidence artifacts | None — trust the agent | TDD Evidence table in ready-for-review.md | **We're ahead** |
| Language-specific | django-tdd, laravel-tdd, springboot-tdd | None (language-agnostic) | Not needed for us |
| Anti-pattern catalog | Explicit list (impl details, interdependence, weak assertions) | Implicit in code-style.md | **Adopt** — formalize |
| Git checkpoint commits | RED/GREEN/refactor commits | Phase 2 of improve-tdd.md proposes same | **Adopt** — ECC validates it works |
| Edge case mandate | null/undefined, empty collections, boundary, concurrency, large datasets | "Handle common edge cases thoroughly (80/20)" | **Adopt** — be explicit |

### TDD Adoption Recommendations

**P0 — Eval-driven development.** ECC's pass@k/pass^k metrics add a quantitative layer on top of TDD. Add eval criteria to our TDD Evidence table: "does this test pass consistently across 3 runs?" Catches flaky tests at creation time. No equivalent exists in our stack.

**P1 — Anti-pattern catalog.** Formalize what NOT to do in tests. Add to `code-style.md` testing section:
- Testing implementation details (mock internals, private methods)
- Interdependent tests (test B depends on test A's side effects)
- Insufficient assertions (test passes with trivially weak assertions)
- Snapshot overuse (testing rendered output instead of behavior)

**P1 — Git checkpoint commits.** Already in our Phase 2 plan. ECC validates this works in practice. Coder commits test files separately: `git commit "RED: tests for X"` then `git commit "GREEN: implementation for X"`. Provides verifiable evidence of test-first ordering.

**P2 — Explicit edge case checklist.** Replace "handle common edge cases" with enumerated list: null/undefined, empty collections, boundary values, error paths, concurrent access.

**Skip — Language-specific TDD skills.** We don't need django-tdd or laravel-tdd. Our stack is language-agnostic by design.

---

## Harness Optimization — Deep Comparison

### ECC's Optimization Stack

**`context-budget` skill** (4-phase audit):
1. Inventory — scan all components, estimate tokens per file (prose: words x 1.3; code: chars / 4)
2. Classify — always needed / sometimes needed / rarely needed
3. Detect issues — inflated agent descriptions (>30 words), redundant skills, MCP over-subscription, verbose CLAUDE.md (>300 lines combined)
4. Report — total overhead, component breakdown, top 3 optimization recommendations

Key insight: "Agent descriptions are loaded always regardless of invocation" — every agent costs ~500 tokens permanently. MCP tools cost ~500 tokens per schema.

**`token-budget-advisor` skill**: Intercepts before responding, offers 4 depth levels (Essential 25%, Moderate 50%, Detailed 75%, Exhaustive 100%). Session memory for chosen depth.

**MCP discipline** (from longform guide):
- "Have 20-30 MCPs in config, but keep under 10 enabled / under 80 tools active"
- "200k context window before compacting might only be 70k with too many tools enabled"
- Replace MCPs wrapping existing CLIs (GitHub, Supabase) with skills that call CLI directly

**Model routing** (`rules/common/performance.md`):
- Haiku 4.5: "90% of Sonnet capability, 3x cost savings" — lightweight agents, workers
- Sonnet 4.6: "Best coding model" — main development, orchestration
- Opus 4.5: "Deepest reasoning" — architecture, research
- Avoid using final 20% of context for large refactors

**`harness-optimizer` agent**: 5-step audit targeting hooks, evaluations, routing, context, safety. Cross-platform.

### Our Optimization Stack

- **RTK proxy**: 60-90% token savings on dev operations via hook rewrite (`git status` -> `rtk git status`)
- **`CLAUDE_AUTOCOMPACT_PCT_OVERRIDE: 60`**: Aggressive auto-compaction
- **`ENABLE_TOOL_SEARCH: auto:5`**: Lazy tool loading
- **`CLAUDE_CODE_DISABLE_ADAPTIVE_THINKING: 1`**: Thinking disabled (token savings)
- **Orchestrator context guard hook**: Blocks large file reads at orchestrator level, forces delegation
- **Recent work**: Tavily/GBrain MCP removal, eng-planning 25% compression (1276 -> 951 lines)

### Harness Feature-by-Feature

| Aspect | ECC | Ours | Assessment |
|---|---|---|---|
| Token savings on CLI output | Not addressed | **RTK proxy** — 60-90% savings, machine-enforced | They should adopt ours |
| Context budget auditing | Formal skill with heuristics | Ad-hoc (manual removal of bloat) | **Adopt** the audit methodology |
| MCP discipline | "Under 10/80" rule with cost awareness | Plugin list is 10+ with no formal budget | **Adopt** the discipline |
| Model routing | Explicit Haiku/Sonnet/Opus by task type | lessons.md mentions it informally | **Formalize** into rules |
| Compaction strategy | Manual at logical intervals | Auto at 60% | Tradeoff — auto safer for long sessions |
| Large-file protection | None | Orchestrator context guard hook | **We're ahead** |
| Token estimation heuristics | Words x 1.3 / chars / 4 | None | **Adopt** for planning |
| Session persistence | `.tmp` checkpoint files | Journal + lessons.md auto-curation | Different approaches, both valid |

### Harness Optimization Adoption Recommendations

**P0 — Context budget audit skill.** Create `/context-audit` that inventories all always-loaded components (CLAUDE.md chain, rules, agent descriptions, MCP tool schemas), estimates token cost, flags bloat. Our CLAUDE.md chain alone is 2000+ lines loaded every session.

**P0 — MCP tool budget rule.** Formalize: "max 10 MCP servers enabled, max 80 tools active." code-review-graph alone contributes 30+ tools. Audit and prune.

**P1 — Model routing rules.** Add to rules: when spawning subagents, specify `model: "haiku"` for exploration/workers, `model: "sonnet"` for implementation, `model: "opus"` for architecture/judgment.

**P2 — Token estimation heuristics.** Add to lessons.md as reference: prose = words x 1.3 tokens, code = chars / 4 tokens.

**Skip — Token budget advisor.** Over-engineered for single user. RTK + context audit covers this.

**Skip — Manual compaction.** Our 60% auto-compaction is safer for long governance sessions where manual checkpoints would be forgotten.

---

## Hooks — Feature-by-Feature Comparison

| Hook Category | ECC | Ours | Assessment |
|---|---|---|---|
| Safety/destructive guards | Config-protection hook | git-safety, remote-destructive, incident-freeze, external-comms | **We're far ahead** |
| Role enforcement | None | role-enforcement.sh (orchestrator vs subagent) | **We're ahead** |
| Agent governance | None | pre-agent-gate.sh + post-agent-audit.sh | **We're ahead** |
| **GateGuard (investigate-before-edit)** | **Yes — "+2.25 quality improvement"** | **Missing** | **Adopt** |
| Compaction suggestion | Suggests manual compaction at logical intervals | Auto-compaction at 60% | Consider hybrid |
| Cost/token tracking | stop:cost-tracker | RTK gain (CLI savings only) | **Adopt** broader tracking |
| Desktop notifications | stop:desktop-notify (macOS + WSL) | notify.sh with Basso sound | ~Parity |
| MCP health check | PostToolUseFailure: auto-reconnect MCP | **Missing** | **Adopt** |
| Session activity tracking | post:session-activity-tracker | session-journal.py (Stop hook) | ~Parity |
| Continuous learning | PreToolUse + Stop hooks for instinct capture | lessons.md manual curation | Their v2 is more sophisticated |
| Format/typecheck on stop | stop:format-typecheck (batch JS/TS) | **Missing** | Adopt if JS/TS heavy |
| Console.log detection | post:edit + stop:check-console-log | **Missing** | Nice-to-have |
| Protected files | pre:config-protection (linter/formatter configs) | git-safety-hook.sh (protected-files.md list) | ~Parity, different targets |

### Hook Adoption Recommendations

**P0 — GateGuard.** Force investigation before first edit per file. Their data: +2.25 quality improvement. Implementation: PreToolUse hook on Edit/Write that checks if the file was Read in the current session. If not, block and require Read first. Directly enforces our "no code without understanding" principle.

**P1 — MCP health check.** PostToolUseFailure hook that detects MCP disconnections and auto-reconnects. Prevents silent tool failures mid-session.

**P2 — Cost tracking.** Stop hook logging token usage per session. Complements RTK's CLI-level tracking with conversation-level metrics.

---

## Memory & Learning — Comparison

| Aspect | ECC | Ours | Assessment |
|---|---|---|---|
| Architecture | Continuous Learning v2: atomic instincts with confidence (0.3-0.9) | Journal -> lessons.md pipeline | Their instinct model is more sophisticated |
| Project isolation | Git remote URL hash | Project path directories | ~Parity |
| Confidence scoring | 0.3-0.9 per instinct | Binary (in lessons or not) | Interesting but not critical |
| Evolution path | observation -> instinct -> skill/command/agent | No formal promotion path | **Adopt** the concept |
| Background analysis | Haiku model analyzes observations | session-journal.py + synthesize-lessons.py | Similar pipeline |
| Cross-session | MCP memory server + instinct files | episodic-memory plugin + MEMORY.md | ~Parity |

**P2 — Formalize promotion path.** When a pattern in lessons.md proves stable across 5+ sessions, promote to rule or skill. Currently ad-hoc.

**Skip — Continuous Learning v2.** Our journal -> lessons pipeline with Opus curation is higher quality than automated instinct capture. Manual curation is a strength.

---

## Unique Strengths We Have That ECC Lacks

| Our Strength | ECC Equivalent | Why It Matters |
|---|---|---|
| **VIBE Protocol** (19 hard gates, phase gates, role separation) | No governance framework | Multi-agent orchestration quality |
| **RTK token proxy** (60-90% savings) | Nothing | Machine-enforced token savings |
| **Governance hooks** (agent gate, audit, role enforcement) | Nothing | Subagent quality control |
| **Incident freeze** (NORMAL -> ARMED -> FROZEN state machine) | Nothing | Production safety |
| **External comms control** (Graph API messaging guards) | Nothing | Unauthorized outbound prevention |
| **Orchestrator context guard** (blocks large reads at orchestrator) | Nothing | Forces delegation, protects context |
| **Spec-wall + contract-first** (R1 + R7) | Nothing formal | Architecture-before-code discipline |
| **N=1 escalation** (1 failed fix -> STOP) | Nothing | Prevents infinite loops |
| **Tool registry** (Office/SharePoint routing) | Nothing | Domain-specific critical infrastructure |
| **TDD Evidence artifacts** (table in ready-for-review.md) | Nothing | Auditable TDD proof |

---

## Priority Adoption Matrix

| Item | Source | Effort | Impact | Priority |
|---|---|---|---|---|
| GateGuard hook (investigate-before-edit) | ECC hooks | Low (1 hook script) | High (+2.25 quality) | **P0** |
| Context budget audit skill | ECC skills | Medium (new skill) | High (token savings) | **P0** |
| MCP tool budget rule | ECC guide | Low (add to rules) | High (context savings) | **P0** |
| Eval-driven development | ECC tdd-guide | Medium (extend TDD Evidence) | High (catches flaky tests) | **P1** |
| MCP health check hook | ECC hooks | Low (1 hook script) | Medium (reliability) | **P1** |
| Model routing rules | ECC rules | Low (add to rules) | Medium (cost optimization) | **P1** |
| TDD anti-pattern catalog | ECC tdd-guide | Low (add to code-style) | Medium (quality) | **P1** |
| Cost tracking hook | ECC hooks | Medium (hook + storage) | Medium (visibility) | **P2** |
| Git checkpoint commits | ECC tdd-workflow | Low (already in Phase 2) | Medium (TDD evidence) | **P2** |
| Instinct -> skill promotion | ECC continuous-learning | Medium (formalize path) | Low (we curate manually) | **P3** |

---

## What NOT to Adopt

| ECC Feature | Why Skip |
|---|---|
| 182 skills | Most are generic/language-specific. We need depth, not breadth. Our ~40 are battle-tested. |
| 48 standalone agents | Agent files as separate personas add context overhead. Skill-based approach is leaner. |
| Cross-harness configs (Cursor/Codex/Gemini) | We're Claude Code only. No benefit. |
| Token budget advisor (4 depth levels) | Over-engineered for single user. RTK + context audit covers this. |
| Continuous Learning v2 | Journal -> lessons with Opus curation is higher quality than automated instinct capture. |
| Manual compaction over auto | 60% auto-compaction is safer for long governance sessions. |
| Security bounty hunter skill | We have `/cso` which is more comprehensive. |
| Language-specific TDD skills | Not needed — our stack is language-agnostic. |

---

## Summary

**ECC is wider, we're deeper.** They optimized for community adoption across stacks (178K stars, 170 contributors). We optimized for governance-enforced quality in a specific ecosystem.

**Three things to steal immediately:**
1. **GateGuard** — investigate-before-edit enforcement. Low effort, proven +2.25 quality lift.
2. **Context budget audit** — we're flying blind on token costs of our always-loaded rules chain.
3. **MCP tool budget discipline** — "under 80 tools active" is a rule we're likely violating.

**One thing they should steal from us:** RTK + governance hooks. Their setup has zero machine enforcement of any quality standard. All 182 skills and 48 agents are instruction-based with no verification that any agent followed any rule.
