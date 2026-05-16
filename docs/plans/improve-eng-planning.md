# Improve eng-planning Skill — COMPLETED

**Round 1 — Completed:** 2026-05-13
26 Codex review findings (P0: 1-4, P1: 5-20, P2: 21-27) applied to `SKILL.md`, `design-doc-template.md`, `review-prompt.md`.

**Round 2 — Completed:** 2026-05-13
6 story decomposition & template modernization changes applied to `design-doc-template.md` and `SKILL.md` (T-XXX→S-XXX, mini-spec rewrite, DD index appendix, Jira Story columns, Story Decomposition Method).

**Round 3 — Completed:** 2026-05-15
Dual-layer enforcement system: scaffold + sentinel-gated hooks + validation script. Prevents template deviation deterministically.

---

## Round 3 — Template & Checkpoint Adherence Enforcement

### Problem Statement

During a real eng-planning run (AI expert persona refactor, Tier 1), the produced design doc deviated meaningfully from `design-doc-template.md`. Missing: Requirements tables (P0/P1/P2), Architecture subsections (Component Diagram, DB Schema, Error Handling, Security), S-XXX story format, Execution DAG concurrency table, File Conflict Matrix, Codepath Coverage Diagram, Interfaces section.

The content was solid (10 design decisions, 30-persona roster, detailed task specs, caught real bugs in review). But the structure didn't match the template.

### Root Cause Analysis

Three layered failures:

1. **Context decay over long conversation.** The eng-planning skill was loaded at conversation start. By artifact production (Step 5), ~40 messages and multiple agent spawns had elapsed. The specific instruction "Read `design-doc-template.md`" had faded from working attention.

2. **Agent substituted judgment for process.** The instructions say "Read the template" and "Spawn Opus subagent to fill it." These are commands, not suggestions. The agent felt confident it knew what a design doc should contain and wrote one from scratch. That confidence was misplaced — the template exists precisely because "what seems right" diverges from "what's required."

3. **No self-check at phase boundaries.** The skill defines explicit phases (A through F) with checkpoints. The agent never re-consulted the skill's step instructions at phase transitions. `progress.json` tracked completion but not process compliance.

**Pattern:** Long interactive conversation → procedural instructions fade → agent defaults to improvisation → deviates from explicit spec. This will recur on any multi-phase skill where artifact production is far from skill loading.

### Options Evaluated

Five options were evaluated (A: scaffold, B: checkpoint verification prompts, C: validation script, D: subagent gateway, E: all combined). Options B and D were rejected: B has the same vulnerability as the original problem (relies on the agent choosing to read the checkpoint file), and D was already prescribed by the skill and wasn't followed. Option E was overkill.

**Selected: A + C + D-sentinel-variant** — scaffold prevents the category of failure, sentinel-gated hooks prevent wasted tokens on bad subagent runs, validation script catches residual deviations deterministically.

### Implementation

| Step | What | Status |
|------|------|--------|
| 1 | Create `design-doc-scaffold.md` — standalone scaffold file with `<!-- TODO: Fill -->` markers | DONE |
| 2 | Update SKILL.md Step 5a — scaffold copy + sentinel + validation script call + sentinel removal | DONE |
| 3 | Write `validate-design-doc.sh` — checks required sections, naming, table columns, TODO markers | DONE |
| 4 | Write `eng-planning-agent-gate.sh` — PreToolUse hook on Agent, sentinel-gated template enforcement | DONE |
| 5 | Write `eng-planning-write-gate.sh` — PreToolUse hook on Write, structural validation on FEAT design docs | DONE |
| 6 | Add sentinels to SKILL.md Steps 7.5, 7.6, 12 — `.gate-traceability` and `.gate-quality` | DONE |
| 7 | Configure hooks in `~/.claude/settings.json` — added to existing Agent and Write PreToolUse matchers | DONE |

### What Was Built

**Prevention layer (Agent gate hook):**
- Sentinel files (`.gate-design-doc`, `.gate-traceability`, `.gate-quality`) created by SKILL.md before critical agent spawns
- PreToolUse hook on Agent checks that subagent prompts reference required templates when sentinels are active
- Sentinels removed after step validation passes
- Cost: ~microseconds when no sentinels exist (single `stat` call per Agent invocation)

**Detection layer (Write gate hook + validation script):**
- PreToolUse hook on Write validates FEAT design doc structure when `progress.json` exists
- Standalone `validate-design-doc.sh` called explicitly in SKILL.md Step 5a post-production
- Checks: 19 required sections, S-XXX naming, required table columns, TODO marker clearance

**Scaffold (template as starting point):**
- `design-doc-scaffold.md` — raw markdown scaffold copied to output path before subagent fills it
- Subagent works against existing skeleton rather than generating structure from memory

**Files created/modified:**
- `skills/eng-planning/templates/design-doc-scaffold.md` (NEW)
- `skills/eng-planning/scripts/validate-design-doc.sh` (NEW)
- `skills/eng-planning/scripts/eng-planning-agent-gate.sh` (NEW)
- `skills/eng-planning/scripts/eng-planning-write-gate.sh` (NEW)
- `skills/eng-planning/SKILL.md` (MODIFIED — Steps 5a, 7.5, 7.6, 12)
- `~/.claude/settings.json` (MODIFIED — hooks added)

---

### Appendix: FEAT-persona-refactor Structural Deviation Inventory

Evidence from session `a1fce8bd-56fd-4334-b757-7be69e6f2338` (2026-05-15). Produced `FEAT-persona-refactor-design.md` without reading `design-doc-template.md`.

#### Sections Missing Entirely

| Required Section | Template Location | Status |
|-----------------|-------------------|--------|
| Requirements tables (P0/P1/P2) with Jira Story + Tasks columns | `## Requirements` | MISSING |
| Non-Goals | `### Non-Goals` | MISSING |
| Interfaces (API Endpoints, DB Changes, FE Changes, New Dependencies) | `## Interfaces` | MISSING |
| API Contract Summary (Endpoints table, Data Models, Error Shape, Enums, SSE) | `## API Contract Summary` | MISSING |
| Codepath Coverage Diagram | `## Codepath Coverage Diagram` | MISSING |
| Appendix: Design Decision Index | `## Appendix: Design Decision Index` | MISSING |
| Architecture: System Overview | `### System Overview` | MISSING |
| Architecture: Component Diagram | `### Component Diagram` | MISSING |
| Architecture: Database Schema | `### Database Schema` | MISSING |
| Architecture: Frontend Architecture | `### Frontend Architecture` | MISSING |
| Architecture: Backend Architecture | `### Backend Architecture` | MISSING |
| Architecture: Error Handling Strategy | `### Error Handling Strategy` | MISSING |
| Architecture: Security Model | `### Security Model` | MISSING |

#### Sections Present but Structurally Wrong

| Section | Expected | Actual | Impact |
|---------|----------|--------|--------|
| Story naming | `S-XXX` at top level, `T-{story}-N` for sub-tasks | `T-001`, `T-002` flat numbering | Breaks S-XXX → T-XXX-N traceability model |
| Section header | `## Jira Stories` | `## Task Mini-Specs` | Wrong semantic framing |
| DAG table columns | `Tasks, Can Run In Parallel, Blocked By` | `Task (singular), Notes` | Missing parallel-safety column |
| File Conflict Matrix | `Task → Creates/Modifies → Conflicts With` | `File → Action → Task` (inverted) | Cannot determine which tasks conflict |
| Failure Modes columns | `Codepath, Realistic Failure, Tests Cover It?, Error Handling Exists?, Silent?` | `Failure, Impact, Mitigation` | Missing test coverage tracking and silent-failure flag |
| Story fields | Explicit `Context:` paragraph, explicit `Acceptance Criteria:` subsection | Content exists but not in labeled subsections | Harder for downstream agents to parse |

#### Failure Point Analysis

The deviation had 3 independent failure points — any single one succeeding would have prevented it:

| Layer | Expected Behavior | Actual | Would Have Prevented? |
|-------|-------------------|--------|----------------------|
| Main agent reads template | Step 5a: "Read `design-doc-template.md`" | Skipped — wrote doc inline from memory | Yes — template has all required sections |
| Main agent spawns Opus subagent | Step 5a: "Spawn subagent with template in prompt" | Never spawned — main agent wrote directly | Yes — fresh subagent context has no decay |
| Post-write validation | None exists | N/A | Yes — would have caught all 13 missing sections + 6 structural mismatches |
