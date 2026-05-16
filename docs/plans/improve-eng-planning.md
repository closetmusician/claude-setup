# Improve eng-planning Skill

**Round 1 — Completed:** 2026-05-13
26 Codex review findings (P0: 1-4, P1: 5-20, P2: 21-27) applied to `SKILL.md`, `design-doc-template.md`, `review-prompt.md`.

**Round 2 — Completed:** 2026-05-13
6 story decomposition & template modernization changes applied to `design-doc-template.md` and `SKILL.md` (T-XXX→S-XXX, mini-spec rewrite, DD index appendix, Jira Story columns, Story Decomposition Method).

---

## Round 3 — Template & Checkpoint Adherence Enforcement

**Date:** 2026-05-15
**Status:** OPTIONS DRAFTED — awaiting decision

### Problem Statement

During a real eng-planning run (AI expert persona refactor, Tier 1), the produced design doc deviated meaningfully from `design-doc-template.md`. Missing: Requirements tables (P0/P1/P2), Architecture subsections (Component Diagram, DB Schema, Error Handling, Security), S-XXX story format, Execution DAG concurrency table, File Conflict Matrix, Codepath Coverage Diagram, Interfaces section.

The content was solid (10 design decisions, 30-persona roster, detailed task specs, caught real bugs in review). But the structure didn't match the template.

### Root Cause Analysis

Three layered failures:

1. **Context decay over long conversation.** The eng-planning skill was loaded at conversation start. By artifact production (Step 5), ~40 messages and multiple agent spawns had elapsed. The specific instruction "Read `design-doc-template.md`" had faded from working attention.

2. **Agent substituted judgment for process.** The instructions say "Read the template" and "Spawn Opus subagent to fill it." These are commands, not suggestions. The agent felt confident it knew what a design doc should contain and wrote one from scratch. That confidence was misplaced — the template exists precisely because "what seems right" diverges from "what's required."

3. **No self-check at phase boundaries.** The skill defines explicit phases (A through F) with checkpoints. The agent never re-consulted the skill's step instructions at phase transitions. `progress.json` tracked completion but not process compliance.

**Pattern:** Long interactive conversation → procedural instructions fade → agent defaults to improvisation → deviates from explicit spec. This will recur on any multi-phase skill where artifact production is far from skill loading.

### Options

---

#### Option A: Template as Literal Scaffold (File-Based)

**Mechanism:** At Step 5, instead of "read the template and follow it," the skill instructs the agent to physically **copy** `design-doc-template.md` to the output path (`docs/plans/FEAT-XXX-design.md`), then fill sections in-place using the Edit tool. The template becomes a physical scaffold — unfilled sections are visible proof of skipped work.

**Implementation:**
- Modify SKILL.md Step 5a to say: "Copy the template file to the output path. Then edit each section in-place."
- Add placeholder markers to the template (e.g., `<!-- TODO: Fill this section -->`) that are greppable.
- Post-production check: `grep -c 'TODO: Fill' docs/plans/FEAT-XXX-design.md` must return 0.

**Tradeoffs:**

| Pro | Con |
|-----|-----|
| Template sections can't be forgotten — they're in the file | Requires template to be valid markdown even with placeholder text |
| Unfilled sections are visible in review (`grep TODO`) | Agent may write weak/generic content to fill sections |
| Works regardless of context length or conversation age | Template needs careful maintenance (changes propagate to all future docs) |
| Simplest to implement — one `cp` + edit-in-place | Doesn't solve the checkpoint adherence problem |
| Compatible with subagent model (subagent receives copied file, fills it) | N/A sections still need explicit "N/A" annotation |

**Addresses:** Template adherence (strong). Checkpoint adherence (no).

---

#### Option B: Checkpoint File with Per-Step Verification Prompts

**Mechanism:** Replace the flat `progress.json` with a richer checkpoint file that includes a **verification prompt** for each step. Before marking a step complete, the agent must read the checkpoint file's verification question and answer it explicitly in the conversation. The verification prompts are specific and structural, not vague.

**Implementation:**
- Create `~/.claude/skills/eng-planning/checkpoints.json` with entries like:
  ```json
  {
    "step_5": {
      "verification": "Does the design doc at [OUTPUT_PATH] contain ALL of these sections? List each with its line number: Requirements (P0/P1/P2), Non-Goals, Architecture (System Overview, Component Diagram, Data Flow, DB Schema, Error Handling, Security), Interfaces, Stories (S-XXX format with Layers, Slice Done Gate), Execution DAG (concurrency table, File Conflict Matrix), Codepath Coverage, Failure Modes, Definition of Done.",
      "pass_condition": "All sections present with line numbers cited"
    },
    "step_7": {
      "verification": "Does the Execution DAG have: (1) a concurrency batch table, (2) a File Conflict Matrix, (3) agent assignment rules? Print the batch table.",
      "pass_condition": "All three present"
    }
  }
  ```
- Modify SKILL.md checkpoint protocol: "Before updating `progress.json`, read the verification prompt for this step from `checkpoints.json` and answer it in your output. If the answer reveals missing work, fix it before proceeding."

**Tradeoffs:**

| Pro | Con |
|-----|-----|
| Forces re-reading instructions at each phase boundary | Adds token cost per checkpoint (~200 tokens each) |
| Verification prompts are specific and auditable | Agent can rubber-stamp the verification (answer "yes" without actually checking) |
| Catches drift early — per step, not post-hoc | Doesn't physically prevent missing template sections |
| Easy to add new checkpoints without modifying SKILL.md | Checkpoint file becomes another thing to maintain |
| Works across all tiers (prompts can be tier-conditional) | Requires agent discipline to actually read the checkpoint file (same failure mode as the original problem) |

**Addresses:** Checkpoint adherence (moderate — relies on agent compliance). Template adherence (indirect, via Step 5 checkpoint).

**Risk:** This option has the same vulnerability as the original problem — it relies on the agent choosing to follow the process. If context decay causes the agent to skip the skill's instructions, it may also skip the checkpoint verification.

---

#### Option C: Hook-Based Structural Validation

**Mechanism:** A validation script that parses the design doc and checks it against the template's required sections. Runs as a pre-commit hook or as an explicit step in the skill. Similar to `check-migration-registered.sh` — deterministic, can't be skipped.

**Implementation:**
- Create `~/.claude/skills/eng-planning/scripts/validate-design-doc.sh`:
  ```bash
  #!/bin/bash
  # Extract required headings from template
  TEMPLATE="$HOME/.claude/skills/eng-planning/templates/design-doc-template.md"
  DOC="$1"
  
  # Check each required section exists in the produced doc
  REQUIRED_SECTIONS=(
    "## Requirements"
    "## Architecture"
    "### System Overview"
    "### Database Schema"
    "### Error Handling"
    "## Interfaces"
    "## Stories"  # or "## Jira Stories"
    "## Execution DAG"
    "### File Conflict Matrix"
    "## Codepath Coverage"
    "## Failure Modes"
    "## Definition of Done"
  )
  
  MISSING=0
  for section in "${REQUIRED_SECTIONS[@]}"; do
    if ! grep -q "$section" "$DOC"; then
      echo "MISSING: $section"
      MISSING=$((MISSING + 1))
    fi
  done
  
  if [ $MISSING -gt 0 ]; then
    echo "FAIL: $MISSING required sections missing"
    exit 1
  fi
  echo "PASS: All required sections present"
  ```
- Add to SKILL.md Step 5 (post-production): "Run `validate-design-doc.sh docs/plans/FEAT-XXX-design.md` — must exit 0."
- Optionally wire into pre-commit hook for `docs/plans/*.md` files.

**Tradeoffs:**

| Pro | Con |
|-----|-----|
| Deterministic — can't be rubber-stamped or skipped | Only checks structure (heading presence), not content quality |
| Runs at a concrete gate (post-production or pre-commit) | Requires writing + maintaining the script |
| Works even if agent ignores all instructions | Doesn't catch weak/stub content within sections |
| Reusable across all eng-planning runs | Script must stay in sync with template (but template is source of truth) |
| Aligns with existing project patterns (`check-migration-registered.sh`) | Doesn't address checkpoint adherence at all |
| Can be enhanced incrementally (add content checks later) | Can't distinguish "N/A" annotations from missing content |

**Addresses:** Template adherence (strong, deterministic). Checkpoint adherence (no).

---

#### Option D: Subagent-as-Gateway (Process Enforcement)

**Mechanism:** Only a fresh subagent can write the design doc artifact. The main agent is physically prevented from writing to `docs/plans/` (via a session freeze or hook). The subagent receives the template as a literal part of its prompt — no context decay because it's freshly spawned with the template in its immediate context.

**Implementation:**
- Modify SKILL.md Step 5a to be explicit: "You MUST NOT write to `docs/plans/` directly. Spawn an Opus subagent with the template embedded in its prompt."
- The subagent prompt includes the full template text (not a path reference — the actual content) so it cannot fade from context.
- Optionally: add a hook that blocks the main agent from `Write` calls to `docs/plans/FEAT-*.md` during eng-planning sessions.

**Tradeoffs:**

| Pro | Con |
|-----|-----|
| Subagent always has fresh context with template at write time | Adds agent spawn overhead (~30-60s for Opus) |
| Main agent physically can't shortcut the process | Main agent still needs to provide good intermediates on disk |
| Template is in the prompt at the moment of writing — no decay | Subagent might still deviate (though much less likely with fresh context) |
| Already what the skill prescribes (just needs enforcement) | Hook enforcement adds complexity (session freeze mechanism) |
| Naturally provides context isolation (subagent doesn't carry main agent's conversation drift) | If intermediates on disk are incomplete, subagent produces garbage |

**Addresses:** Template adherence (strong — template in fresh context). Checkpoint adherence (partial — only enforces the Step 5 boundary, not all checkpoints).

**Note:** This is already what the skill says to do. The failure was that the agent didn't follow it. Making this enforceable (via hook/freeze) is the key difference.

---

#### Option E: Defense in Depth — A + B + C Combined

**Mechanism:** All three layers working together:
1. **Layer 1 (Scaffold — Option A):** Template physically copied as the starting file. Unfilled sections are visible.
2. **Layer 2 (Checkpoints — Option B):** Verification prompts at each phase boundary force re-reading instructions.
3. **Layer 3 (Validation — Option C):** Script gates the commit with structural checks. Deterministic backstop.

**Implementation:** All three as described above, plus:
- SKILL.md updated with all three mechanisms integrated into the step flow.
- Validation script runs both post-production (Step 5 gate) AND at pre-commit.

**Tradeoffs:**

| Pro | Con |
|-----|-----|
| Defense in depth — each layer catches what others miss | Most implementation effort (~2-3 hours) |
| Layer A prevents omission, Layer B prevents drift, Layer C prevents merge | Three mechanisms to maintain |
| A catches structural gaps, B catches process gaps, C is the hard gate | Token overhead from checkpoint verification prompts |
| Can degrade gracefully (if agent skips B, C still catches it) | Might feel heavy for Tier 1 plans |
| Aligns with project patterns (hooks, validation scripts, scaffolds) | N/A |

**Addresses:** Template adherence (very strong — triple redundancy). Checkpoint adherence (moderate — Layer B).

---

### Recommendation

**Primary: Option A + C (Scaffold + Validation Script)**

Rationale:
- **A (scaffold)** prevents the most common failure mode — forgetting sections. If the template is physically in the file, sections can't be forgotten, only poorly filled. This is the highest-leverage single change.
- **C (validation script)** is the deterministic backstop. It aligns with existing project patterns (`check-migration-registered.sh`), is cheap to maintain (extract headings from template, grep the doc), and can't be rubber-stamped.
- Together they cover template adherence completely: A prevents omission during writing, C catches any remaining gaps at commit time.

**Why not B (checkpoints)?** B has the same vulnerability as the original problem — it relies on the agent choosing to read and follow the checkpoint file. If context decay caused the agent to skip "read the template," it may also skip "read the checkpoint." B adds value but doesn't add a new enforcement mechanism — it's more instructions for the agent to follow, not a structural constraint.

**Why not D (subagent gateway)?** D is already prescribed by the skill and wasn't followed. Making it enforceable requires a hook/freeze mechanism that's more complex than A+C and addresses only Step 5, not the full pipeline. However, D is a good optional addition if A+C proves insufficient.

**Why not E (all three)?** Diminishing returns. A+C covers 90% of the problem. Add B or D later if A+C isn't enough in practice.

### Implementation Plan (if A + C selected)

| Step | What | Effort |
|------|------|--------|
| 1 | Add `<!-- TODO: Fill -->` markers to `design-doc-template.md` for each required section | 15 min |
| 2 | Update SKILL.md Step 5a: "Copy template to output path, then fill in-place" | 5 min |
| 3 | Write `validate-design-doc.sh` script | 30 min |
| 4 | Add validation call to SKILL.md Step 5 (post-production gate) | 5 min |
| 5 | Wire validation into pre-commit hook for `docs/plans/FEAT-*.md` | 15 min |
| 6 | Test: run eng-planning on a test feature, verify scaffold + validation work | 30 min |

**Total: ~1.5 hours.**

### Alternative Recommendation: A + C + D

If you want stronger enforcement, add D (subagent gateway) on top of A+C. The subagent receives the copied scaffold file path + all intermediates. The validation script still runs as the commit gate. This gives:
- A prevents omission (scaffold)
- D prevents context decay (fresh subagent)
- C prevents merge of broken docs (validation script)

This adds ~30 min of implementation (hook to block main agent from `docs/plans/` writes).

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

This inventory validates the Round 3 recommendation: **scaffold (Option A) prevents the category of failure; validation script (Option C) catches residual deviations deterministically.**
