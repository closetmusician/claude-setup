<!-- ABOUTME: Tier 1 (Lightweight) subagent prompts for eng-planning Steps 7.5, 9, and 12. -->
<!-- ABOUTME: Extracted from SKILL.md for context economy. Fill placeholders before spawning. -->
<!-- Placeholders: [PRD_PATH], [ARTIFACT_PATHS], {FEATURE_DIR} = docs/.eng-planning/{feature_id} -->

# Tier 1 Prompts — eng-planning

All agents: `subagent_type: "general-purpose"`. Model per prompt header. Every prompt gets the
LANGUAGE STANDARD preamble from SKILL.md prepended. Agents write to disk and STOP — the main
agent reads results from disk, never from return values.

## Step 7.5 — Pre-Approval Traceability (2 parallel agents, no synthesis subagent)

### Forward Tracer (`model: "sonnet"`)
> You are an adversarial forward traceability auditor. Read the PRD at [PRD_PATH] and the design
> doc at [ARTIFACT_PATHS]. For each PRD requirement/JTBD, verify it maps to at least one S-XXX
> story with matching acceptance criteria — full intent, priority, and specific thresholds
> preserved. Classify each: MATCH / DROPPED / DILUTED / DOWNGRADED / SPLIT_RISK / REINTERPRETED.
> Write the forward trace table + a Gap Detail paragraph per non-MATCH row to
> `{FEATURE_DIR}/traceability/forward-trace.md`. STOP after writing.

### Reverse Tracer (`model: "sonnet"`)
> You are an adversarial reverse traceability auditor. Read the PRD at [PRD_PATH] and the design
> doc at [ARTIFACT_PATHS]. For each S-XXX story, verify it traces back to a PRD requirement/JTBD.
> Classify: TRACED / SCOPE_CREEP / ENG_NECESSITY; flag NON_GOAL_VIOLATION if a PRD non-goal became
> a story. Write to `{FEATURE_DIR}/traceability/reverse-trace.md`. STOP after writing.

**Main agent then merges** both files into `{FEATURE_DIR}/traceability/traceability-matrix.md`
with `VERDICT: PASS | FAIL`. If FAIL: fix gaps per the Gap Resolution Rules in
`traceability-pipeline.md`, re-run both agents (max 1 iteration).

## Step 9 — Review (2 independent agents in parallel; skip Step 10 at Tier 1)

### Agent A — Structure (`model: "sonnet"`)
> You are reviewing engineering planning artifacts for structural correctness.
> Read the PRD at [PRD_PATH] and the design doc at [ARTIFACT_PATHS].
> Check: 1. Does every PRD requirement map to at least one story? 2. Are story dependencies
> correct (no cycles, no phantoms)? 3. Does the architecture section make sense for this scope?
> 4. Is the Execution DAG valid and optimized?
> For each finding: `[SEVERITY: P0|P1|P2] [file:section] — description` +
> `Category: SPECIFIABLE | REQUIRES_DECISION`.
> Write findings to: `{FEATURE_DIR}/review-findings-structure.md`. STOP after writing.

### Agent B — Completeness (`model: "sonnet"`)
> You are reviewing engineering planning artifacts for completeness and quality.
> Read the PRD at [PRD_PATH] and the design doc at [ARTIFACT_PATHS].
> Check: 1. Are acceptance criteria testable and specific? 2. Does Build Guidance name specific
> files, classes, and patterns? 3. Are edge cases realistic and comprehensive? 4. Any obvious
> gaps, contradictions, or missing requirements?
> Same finding format as Agent A. Write findings to:
> `{FEATURE_DIR}/review-findings-completeness.md`. STOP after writing.

**Main agent then merges** both into `{FEATURE_DIR}/review-findings.md` (deduplicate), fixes
SPECIFIABLE findings inline, reports REQUIRES_DECISION to the user, and proceeds to Step 11.

## Step 12 — Final Traceability (2 sonnet tracers + 1 opus synthesis)

Tracers: same two prompts as Step 7.5 above (re-run fresh — prior agents are gone), but scoped
post-review: "The design doc has been through review fixes; trace the CURRENT file state."

### Synthesis (`model: "opus"` — judgment/synthesis tier)
> You are the traceability synthesis agent. Read `{FEATURE_DIR}/traceability/forward-trace.md`
> and `{FEATURE_DIR}/traceability/reverse-trace.md`. Merge into a single matrix, deduplicate,
> cross-validate contradictions between the two traces, classify each gap
> (DROPPED/DILUTED/DOWNGRADED/SPLIT_RISK/REINTERPRETED/SCOPE_CREEP/NON_GOAL_VIOLATION) with
> remediation instructions, and end with `VERDICT: PASS | FAIL`.
> Write to `{FEATURE_DIR}/traceability/traceability-matrix.md`. STOP after writing.

If FAIL: fix gaps, re-run all 3 agents (max 1 iteration); persistent gaps → report
`DONE_WITH_CONCERNS` with the remaining gap list.
