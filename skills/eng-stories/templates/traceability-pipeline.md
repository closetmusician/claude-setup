# ABOUTME: 3-agent traceability pipeline for /eng-stories skill.
# ABOUTME: Forked from eng-planning's traceability-pipeline.md with depth trace
# ABOUTME: and source reconciliation added (dimensions 2 and 3).
# ABOUTME: Placeholders: {TRACE_DIR}, {PRD_PATH}, {ARTIFACT_PATHS},
# ABOUTME: {BEHAVIORAL_INVENTORY_PATH}.

# PRD Traceability Pipeline — eng-stories

## Overview

3-phase pipeline verifying story artifacts against PRD across 3 dimensions:
1. **Coverage** — every PRD requirement maps to a story and vice versa
2. **Depth** — stories have sufficient behavioral ACs relative to source implementations
3. **Source Reconciliation** — every source behavior is accounted for in stories

## Placeholders

- `{TRACE_DIR}` — working directory for intermediate files
- `{PRD_PATH}` — path to approved PRD
- `{ARTIFACT_PATHS}` — paths to story doc(s)
- `{BEHAVIORAL_INVENTORY_PATH}` — path to behavioral inventory (may not exist)

## Pipeline Architecture

```
Phase 1: 2-3 parallel agents (tier-dependent)
  ├─ Agent 1: Forward Tracer (PRD → Stories)
  ├─ Agent 2: Reverse Tracer + Depth (Stories → PRD + thin story detection)
  └─ Agent 3: Source Reconciliation (Standard tier only)

Phase 2: Main agent merges results
  → {TRACE_DIR}/traceability-matrix.md (VERDICT)
  → {TRACE_DIR}/behavioral-coverage-report.md (if behavioral inventory exists)
```

---

## Agent 1 — Forward Tracer

**Model:** sonnet

**Prompt:**
```
You are a FORWARD TRACER verifying PRD-to-engineering coverage.

Read the PRD at {PRD_PATH} and the story artifacts at {ARTIFACT_PATHS}.

STEP 1: Extract every PRD item into a flat list:
- PRD-R-NNN: Requirements (P0/P1/P2)
- PRD-AC-NNN: Acceptance criteria
- PRD-US-NNN: User stories / JTBDs
- PRD-C-NNN: Constraints
- PRD-SM-NNN: Success metrics
- PRD-NG-NNN: Non-goals

STEP 2: For each PRD item, find its engineering equivalent in the story docs.
Classify the mapping:

| Classification | Meaning |
|---------------|---------|
| MATCH | PRD item fully represented in story AC with equivalent specificity |
| DROPPED | PRD item has no corresponding story or AC |
| DILUTED | Story exists but AC is vaguer than PRD (lost specificity) |
| DOWNGRADED | Story exists but at lower priority than PRD specifies |
| SPLIT_RISK | PRD item split across multiple stories with no cross-reference |
| REINTERPRETED | Story changes the meaning of the PRD item |

STEP 3: Write output to {TRACE_DIR}/forward-trace.md

Format:
## Forward Trace: PRD → Stories

| PRD Item | Classification | Story | Notes |
|----------|---------------|-------|-------|
| PRD-R-001 | MATCH | S-CP AC-3 | — |
| PRD-R-002 | DROPPED | — | No story covers timer persistence |

### Gap Details
For each non-MATCH row, write a paragraph explaining:
- What the PRD requires
- What the story says (or doesn't say)
- Why this is a gap
```

**Output:** `{TRACE_DIR}/forward-trace.md`

---

## Agent 2 — Reverse Tracer + Depth

**Model:** sonnet

**Prompt:**
```
You are a REVERSE TRACER and DEPTH ANALYZER.

Read the PRD at {PRD_PATH}, story artifacts at {ARTIFACT_PATHS},
and behavioral inventory at {BEHAVIORAL_INVENTORY_PATH} (if it exists).

## Part A: Reverse Trace (Stories → PRD)

For each engineering item in the story docs, trace back to PRD:
- ENG-AC-NNN: Story acceptance criteria
- ENG-NG-NNN: Story non-goals / out-of-scope items

Classify:

| Classification | Meaning |
|---------------|---------|
| TRACED | Eng item maps to a PRD requirement |
| SCOPE_CREEP | Eng item has no PRD basis and no justification |
| ENG_NECESSITY | Eng item has no PRD basis but is justified (infra, testing, tooling) |
| NON_GOAL_VIOLATION | Eng item implements something PRD explicitly excludes |

## Part B: Depth Trace (if behavioral inventory exists)

For each story, compare:
- Count of behavioral ACs in the story (including [SOURCE-DERIVED] ACs)
- Count of detailed requirements in the story
- Count of [REQ]-tagged behaviors in the behavioral inventory for the same PRD requirements

Note: Only [REQ] (behavioral requirement) items from the inventory count
toward depth. [IMPL] (implementation pattern) items are NOT included
in story artifacts — they stay in explorer reports for /eng-planning.

Flag as THIN_STORY when:
- Source has >3x more distinct [REQ] behaviors than the story has ACs + requirements
- OR story has <3 ACs for a requirement with >10 source [REQ] behaviors

Also verify structural compliance:
- Language quality: story objectives, requirements, workflows, and ACs use plain English (no jargon ANYWHERE — there is no technical section)
- Workflows cover error paths, not just happy path
- No orphan stories (every story traces to PRD)

Write output to {TRACE_DIR}/reverse-depth-trace.md

Format:
## Reverse Trace: Stories → PRD

| Eng Item | Classification | PRD Source | Notes |
|----------|---------------|-----------|-------|
| S-CP AC-1 | TRACED | PRD-R-001 | — |
| S-CP AC-7 | SCOPE_CREEP | — | No PRD basis for audit logging |

### Gap Details
[paragraph per non-TRACED item]

## Depth Analysis

| Story | Story ACs | Source Behaviors | Ratio | Status |
|-------|-----------|-----------------|-------|--------|
| S-CP | 8 | 12 | 1.5x | OK |
| S-AG | 3 | 15 | 5.0x | THIN_STORY |

### Thin Stories Requiring Expansion
[list each THIN_STORY with specific missing behaviors from inventory]

## Structural Compliance
- Stories with jargon in objectives/requirements/ACs: [list or "none"]
- Orphan stories: [list or "none"]
```

**Output:** `{TRACE_DIR}/reverse-depth-trace.md`

---

## Agent 3 — Source Reconciliation (Standard Tier Only)

**Model:** sonnet

**Prompt:**
```
You are a SOURCE RECONCILIATION agent.

Read the behavioral inventory at {BEHAVIORAL_INVENTORY_PATH}
and the story artifacts at {ARTIFACT_PATHS}.

For each PRD requirement in the behavioral inventory:
1. List all source components implementing it
2. List all user-facing behaviors found in those components
3. For each [REQ]-tagged behavior, check if it appears in any story's
   ACs, requirements, workflow steps, or edge cases (all in PM-facing language)
4. [IMPL]-tagged behaviors are NOT expected in story artifacts — they stay
   in explorer reports for /eng-planning. Do not flag missing [IMPL] items.
5. Categorize uncovered [REQ] behaviors:

| Category | Definition | Action |
|----------|-----------|--------|
| DEPTH_GAP | Behavior in PRD + code, but story AC is too abstract or missing | Auto-expand: suggest specific AC text |
| EXTRACTION_GAP | Behavior in code but P1/P2 or absent in PRD | Flag for PM scope decision |
| NEW_REQUIREMENT | Behavior not in code or PRD | Flag for product discovery |

Write output to {TRACE_DIR}/behavioral-coverage-report.md

Format:
## Behavioral Coverage Report

### [PRD Requirement ID]: [Requirement Title]
**Components:** [file1 (N behaviors), file2 (N behaviors)]
**Total source behaviors:** N
**Covered in stories:** M (X%)
**Uncovered:**
- [behavior] — [file:line] — DEPTH_GAP — Suggested AC: "[text]"
- [behavior] — [file:line] — EXTRACTION_GAP — In code but not in PRD
- [behavior] — NEW_REQUIREMENT — Not in code or PRD

## Summary
| PRD Requirement | Source Behaviors | Covered | Coverage % | Gaps |
|----------------|-----------------|---------|-----------|------|
| [req] | N | M | X% | D depth + E extraction + R new |

## Overall
- Total source behaviors: N
- Total covered: M (X%)
- DEPTH_GAPs (auto-expandable): D
- EXTRACTION_GAPs (PM decision): E
- NEW_REQUIREMENTs (discovery): R
```

**Output:** `{TRACE_DIR}/behavioral-coverage-report.md`

---

## Phase 2: Merge & Verdict (Main Agent)

Main agent reads all trace files from disk and produces `{TRACE_DIR}/traceability-matrix.md`:

```markdown
# Traceability Matrix — [Feature]

## Forward Trace Summary
- Total PRD items: N
- MATCH: M
- Gaps: D (DROPPED: X, DILUTED: Y, DOWNGRADED: Z, SPLIT_RISK: W, REINTERPRETED: V)

## Reverse Trace Summary
- Total eng items: N
- TRACED: M
- Issues: D (SCOPE_CREEP: X, NON_GOAL_VIOLATION: Y)
- ENG_NECESSITY (justified): Z

## Depth Analysis Summary
- Stories analyzed: N
- OK: M
- THIN_STORY: D [list]

## Source Reconciliation Summary (if available)
- Total source behaviors: N
- Covered: M (X%)
- DEPTH_GAP: D
- EXTRACTION_GAP: E
- NEW_REQUIREMENT: R

## VERDICT: PASS | FAIL

[If FAIL, list each gap with classification and required action]
```

---

## Gap Resolution Rules

| Gap Type | Action |
|----------|--------|
| DROPPED | Add missing requirement to appropriate story or create new story |
| DILUTED | Strengthen story AC to match PRD specificity |
| DOWNGRADED | Correct story priority to match PRD priority |
| SPLIT_RISK | Add explicit cross-reference notes to affected stories |
| SCOPE_CREEP | Remove unauthorized work OR add "Engineering Necessity" justification |
| REINTERPRETED | Rewrite story AC to match PRD intent |
| NON_GOAL_VIOLATION | Remove story or AC implementing a PRD non-goal |
| THIN_STORY | Add source-derived ACs from behavioral inventory |
| DEPTH_GAP | Add suggested AC text from reconciliation report to story |
| EXTRACTION_GAP | Flag for PM — do NOT auto-add |
| NEW_REQUIREMENT | Flag for PM — do NOT auto-add |

**Fix iteration:** Main agent fixes DROPPED, DILUTED, DOWNGRADED, SPLIT_RISK, THIN_STORY, and DEPTH_GAP autonomously. Flags EXTRACTION_GAP and NEW_REQUIREMENT for user. Re-runs pipeline (max 1 iteration). If gaps persist, report as DONE_WITH_CONCERNS.

---

## Light Tier Variant

For Light tier, skip Agent 3 (Source Reconciliation). Agent 2 still performs depth analysis if behavioral inventory exists. Main agent produces traceability matrix without the source reconciliation summary section.

---

## Cleanup

Keep all intermediate files in `{TRACE_DIR}/` as audit trail until parent workflow (Step 13) cleans up `docs/.eng-planning/`.
