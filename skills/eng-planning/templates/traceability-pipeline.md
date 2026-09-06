<!-- ABOUTME: Shared 3-agent PRD traceability pipeline template. Used by eng-planning (Steps 7.5, 12) and plan-eng-review (Section 0.5). Consolidates extraction+tracing into 2 parallel agents + 1 synthesis agent. Fill placeholders before use. -->
<!-- Model tiers: tracers = sonnet (mechanical extraction/matching), synthesis = opus (judgment: dedup, cross-validation, verdict). -->

# PRD Traceability Pipeline (3-Agent)

**Purpose:** Verify 1:1 mapping between PRD requirements/acceptance criteria and engineering tasks/acceptance criteria. Catches dropped, diluted, downgraded, and unauthorized scope.

## Placeholders

| Placeholder | Description |
|-------------|-------------|
| `{TRACE_DIR}` | Working directory for intermediate files (e.g., `docs/.eng-planning/{feature_id}/traceability/`) |
| `{PRD_PATH}` | Path to the approved PRD |
| `{ARTIFACT_PATHS}` | Paths to engineering design doc(s) |
| `{CONTRACT_PATHS}` | Paths to API contract(s) (may be empty) |

## Setup

```bash
mkdir -p {TRACE_DIR}
```

## Pipeline Architecture

```
TRACEABILITY AUDIT PIPELINE (3-agent)
══════════════════════════════════════

Phase 1: Extract + Trace (2 agents in parallel)
  ├─ Agent 1 (sonnet): Forward Trace (PRD→Eng)   → {TRACE_DIR}/forward-trace.md
  ├─ Agent 2 (sonnet): Reverse Trace (Eng→PRD)   → {TRACE_DIR}/reverse-trace.md
  ↓ (both complete)

Phase 2: Synthesis (1 agent)
  └─ Agent 3 (opus): Gap Analysis + Verdict      → {TRACE_DIR}/traceability-matrix.md
```

## Phase 1: Extract + Trace (parallel — launch both in a single message)

### Agent 1 — Forward Tracer

`model: "sonnet"`, `subagent_type: "general-purpose"`

> You are an adversarial forward traceability auditor. You extract every requirement from the PRD, then verify each one has been faithfully translated into engineering work. You are skeptical by default — the engineering doc is GUILTY of dropping requirements until proven otherwise.
>
> Do not give the benefit of the doubt. Do not infer intent. If the PRD says "error message within 2 seconds" and the eng AC says "show error message" — that is DILUTED (threshold dropped). If the PRD has a P0 requirement and no eng task covers it — that is DROPPED, full stop.
>
> ## Inputs
> - PRD: `{PRD_PATH}`
> - Engineering Design Doc(s): `{ARTIFACT_PATHS}`
> - API Contract(s): `{CONTRACT_PATHS}` (if any)
>
> ## Task
>
> ### Step 1: Extract PRD Items
> Read the PRD completely. Extract and number every:
> - **Requirement** (P0/P1/P2), each as `PRD-R-NNN` with priority, full text verbatim, and parent section
> - **Acceptance criterion**, each as `PRD-AC-NNN` linked to parent `PRD-R-NNN`, full text verbatim
> - **User story or use case**, each as `PRD-US-NNN`
> - **Constraint or non-functional requirement**, each as `PRD-C-NNN`
> - **Success metric** with testable threshold, each as `PRD-SM-NNN`
> - **Non-goal** (things explicitly out of scope), each as `PRD-NG-NNN`
>
> For multi-clause acceptance criteria, number each clause separately: `PRD-AC-003a`, `PRD-AC-003b`, etc.
>
> Do NOT interpret, summarize, or paraphrase. Copy the PRD text VERBATIM for each item. Your extraction is a forensic inventory.
>
> ### Step 2: Forward Trace Each Item
> For EACH extracted PRD item (`PRD-R-*`, `PRD-AC-*`, `PRD-US-*`, `PRD-C-*`, `PRD-SM-*`):
> 1. Find the corresponding eng item(s) — match by semantic content, not by ID
> 2. Verify the eng version captures the FULL intent — not a subset, not a paraphrase that loses specifics
> 3. Check priority preservation: P0 PRD requirement must map to P0 eng task (not downgraded)
> 4. Check detail preservation: thresholds, boundary values, error conditions, edge cases all carried through
> 5. Check completeness: if a PRD AC has multiple clauses (a, b, c), ALL must appear in eng ACs
> 6. For `PRD-NG-*` items: verify they do NOT appear as eng tasks (non-goals must stay out of scope)
>
> Classify each mapping:
> - **MATCH**: Eng item faithfully captures full PRD intent
> - **DROPPED**: No eng item corresponds to this PRD item
> - **DILUTED**: Eng item covers the topic but loses specifics (thresholds, edge cases, conditions)
> - **DOWNGRADED**: PRD priority not preserved (P0→P1, P1→P2)
> - **SPLIT_RISK**: PRD item split across multiple eng tasks — detail may fall through cracks
> - **REINTERPRETED**: Eng version changes meaning or narrows intent
>
> ## Output
>
> Write to: `{TRACE_DIR}/forward-trace.md`
>
> Format:
> ```
> PRD EXTRACTION SUMMARY
> Total: N requirements, N acceptance criteria, N user stories, N constraints, N success metrics, N non-goals.
>
> FORWARD TRACE (PRD → Engineering)
> | PRD ID     | PRD Text (≤50 chars)          | Eng Item(s)  | Status         | Detail |
> |------------|-------------------------------|--------------|----------------|--------|
> ```
> For every non-MATCH row, include a "Gap Detail" paragraph: PRD text verbatim, eng text verbatim (or "ABSENT"), and why this is a gap.
>
> End with: "Forward trace complete. Total: N items traced. MATCH: N. Gaps: N (DROPPED: N, DILUTED: N, DOWNGRADED: N, SPLIT_RISK: N, REINTERPRETED: N)."

### Agent 2 — Reverse Tracer

`model: "sonnet"`, `subagent_type: "general-purpose"`

> You are an adversarial reverse traceability auditor. You extract every engineering deliverable, then verify each one traces back to an approved product requirement. Unauthorized scope creep wastes build time and introduces untested surface area.
>
> ## Inputs
> - PRD: `{PRD_PATH}`
> - Engineering Design Doc(s): `{ARTIFACT_PATHS}`
> - API Contract(s): `{CONTRACT_PATHS}` (if any)
>
> ## Task
>
> ### Step 1: Extract Engineering Items
> Read the engineering design docs and API contracts completely. Extract and number every:
> - **Task** (T-XXX) with priority, objective, full requirements text, and depends-on
> - **Engineering acceptance criterion**, each as `ENG-AC-NNN` linked to parent task, full text verbatim
> - **API endpoint** from contracts, each as `ENG-API-NNN` with method, path, and purpose
> - **Data model/schema**, each as `ENG-DM-NNN` with field names and types
> - **Non-goal or out-of-scope item**, each as `ENG-NG-NNN`
>
> Do NOT interpret, summarize, or paraphrase. Copy the design doc text VERBATIM for each item.
>
> ### Step 2: Reverse Trace Each Item
> For EACH extracted eng item (`ENG-AC-*`, tasks, `ENG-API-*`, `ENG-DM-*`):
> 1. Find the PRD item it traces back to — match by semantic content
> 2. Classify:
>    - **TRACED**: Clear PRD backing exists
>    - **SCOPE_CREEP**: No PRD backing AND no explicit "engineering necessity" justification in the design doc
>    - **ENG_NECESSITY**: No direct PRD backing but the design doc explicitly justifies it as required infrastructure (e.g., migrations, auth middleware, test fixtures)
>
> Also check: do any `PRD-NG-*` non-goals appear as eng tasks? If so, flag as **NON_GOAL_VIOLATION**.
>
> ## Output
>
> Write to: `{TRACE_DIR}/reverse-trace.md`
>
> Format:
> ```
> ENG EXTRACTION SUMMARY
> Total: N tasks, N acceptance criteria, N API endpoints, N data models, N non-goals.
>
> REVERSE TRACE (Engineering → PRD)
> | Eng Item   | Eng Text (≤50 chars)         | PRD Source   | Status          | Detail |
> |------------|------------------------------|--------------|-----------------|--------|
> ```
> For every non-TRACED row, include a "Detail" paragraph explaining what the eng item does and why no PRD backing was found.
>
> End with: "Reverse trace complete. Total: N items traced. TRACED: N. SCOPE_CREEP: N. ENG_NECESSITY: N. NON_GOAL_VIOLATION: N."

**After Phase 1:** Wait for both agents to complete. Verify both files exist on disk. If either agent failed, re-spawn the failed agent.

## Phase 2: Synthesis (sequential — depends on Phase 1 output)

**Before spawning:** Re-read `{TRACE_DIR}/forward-trace.md` and `{TRACE_DIR}/reverse-trace.md` from disk. Pass their contents into the agent prompt.

### Agent 3 — Synthesis & Verdict

`model: "opus"`, `subagent_type: "general-purpose"` — synthesis/verdict is a judgment task; the opus pin holds at every tier that runs this pipeline

> You are the final traceability synthesis agent. You combine forward and reverse trace results into a single traceability matrix with a pass/fail verdict.
>
> ## Inputs (on disk)
> - Forward trace: `{TRACE_DIR}/forward-trace.md`
> - Reverse trace: `{TRACE_DIR}/reverse-trace.md`
>
> ## Task
> 1. **Merge traces** — Combine forward and reverse findings into a unified matrix
> 2. **Deduplicate** — If the same gap appears in both traces, merge into one finding
> 3. **Cross-validate** — Check for contradictions between forward and reverse traces (e.g., forward says MATCH but reverse says SCOPE_CREEP for the same mapping). Flag contradictions.
> 4. **Produce the final matrix and verdict**
>
> ## Output
>
> Write to: `{TRACE_DIR}/traceability-matrix.md`
>
> ```
> PRD TRACEABILITY MATRIX
> ═══════════════════════
>
> FORWARD TRACE (PRD → Engineering):
> | PRD ID     | Requirement (≤40 chars)       | Eng Task(s) | Eng AC(s)   | Status         | Notes |
> |------------|-------------------------------|-------------|-------------|----------------|-------|
> [all rows from forward trace]
>
> REVERSE TRACE (Engineering → PRD):
> | Eng Task   | Objective (≤40 chars)         | PRD Source  | Status       | Notes |
> |------------|-------------------------------|-------------|--------------|-------|
> [all rows from reverse trace]
>
> CROSS-VALIDATION:
> [any contradictions between forward and reverse traces, or "No contradictions found."]
>
> GAP DETAIL:
> For each gap, one paragraph: what the PRD says verbatim, what the eng doc says (or doesn't), and why this is a gap. Group by gap type.
>
> SUMMARY:
> - Total PRD items: N | Fully matched: N (X%) | Gaps: N
>   - DROPPED: N | DILUTED: N | DOWNGRADED: N
>   - SPLIT_RISK: N | REINTERPRETED: N
> - Total eng items: N | Traced to PRD: N | SCOPE_CREEP: N | ENG_NECESSITY: N | NON_GOAL_VIOLATION: N
>
> VERDICT: PASS (100% forward trace, 0 gaps) | FAIL (N gaps requiring resolution)
> ```

**After Phase 2:** Read `{TRACE_DIR}/traceability-matrix.md` from disk. This is the authoritative result.

## Gap Resolution Rules

When VERDICT is FAIL, fix each gap type:
- **DROPPED** → Add missing requirement to appropriate T-XXX task or create a new task with all required fields
- **DILUTED** → Strengthen eng acceptance criteria to match PRD specificity (thresholds, edge cases, conditions)
- **DOWNGRADED** → Correct task priority to match PRD priority
- **SPLIT_RISK** → Add explicit cross-reference notes to affected tasks ensuring no detail is lost
- **SCOPE_CREEP** → Remove unauthorized work OR add explicit "Engineering Necessity" justification in the task
- **REINTERPRETED** → Rewrite eng version to match original PRD intent verbatim
- **NON_GOAL_VIOLATION** → Remove eng task that implements a PRD non-goal

## Cleanup

Keep all files in `{TRACE_DIR}/` until the parent workflow completes. Intermediate files are the audit trail — they prove exactly what each agent saw and concluded. Cleanup is the parent workflow's responsibility.
