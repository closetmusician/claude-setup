---
name: diff-audit
description: "Compare an original document against a rewrite to identify semantic losses — missing content, modified behaviors, and degraded specificity. Designed for PRDs, technical specs, and any structured document where content fidelity matters."
---

<!-- ABOUTME:
  diff-audit SKILL.md - Document fidelity auditor for rewrites/compressions.
  Compares original vs rewrite at the semantic-unit level.
  Profiles: prd (requirement IDs), technical (headings+items), generic (headings+blocks).
  Spawns parallel agents per file pair, produces per-file verdicts + rollup summary.
  Reference standard is ALWAYS the original file, never any intermediate artifact.
-->

# /diff-audit — Document Diff Audit

Compare an original document against its rewrite to catch silent content loss.
The **original is the reference standard**. Every comparison checks what the
original says and whether the rewrite preserves it.

---

## Input Contract

| Param | Required | Default | Description |
|-------|----------|---------|-------------|
| `original` | Yes | — | Path to original file or directory of files |
| `rewrite` | Yes | — | Path to rewritten file or directory of files |
| `scope` | No | `all` | `all` or comma-separated file identifiers (e.g., `01,02,05`) |
| `profile` | No | `prd` | Extraction/scoring profile: `prd`, `technical`, `generic`, or path to custom JSON |

Parse from the user's invocation. If `original` or `rewrite` is missing, ask immediately.

---

## Profiles

A profile controls (1) how comparison units are extracted, (2) which structural
sections to verify, and (3) scoring strictness.

### `prd` (default)

- **Unit extraction:** Requirement IDs via regex patterns like `PUB-\d+`, `REQ-\d+`,
  `[A-Z]{2,6}-\d{3,4}`. Each ID maps to its acceptance criteria / sub-items.
- **Structural checklist:** Data model tables, business rules, wireframes/mockup refs,
  state machines/flow diagrams.
- **Scoring:** Strict. Any missing P0 acceptance criterion = FAIL.
- **Priority level:** P0 requirements (inferred from priority markers, or all if unmarked).

### `technical`

- **Unit extraction:** H2/H3 headings -> numbered sub-items within each heading.
- **Structural checklist:** Code blocks, config examples, diagrams/figures, tables,
  CLI examples.
- **Scoring:** Strict. Any missing numbered item = FAIL.
- **Priority level:** All numbered items.

### `generic`

- **Unit extraction:** All headings -> child content blocks (paragraphs, lists, tables).
- **Structural checklist:** Heading parity (all original headings present in rewrite).
- **Scoring:** Moderate. Configurable WARN threshold (default: 3 DEGRADED items).
- **Priority level:** Top-level headings.

### Custom profiles

If `profile` is a file path ending in `.json`, read it. Expected shape:

```json
{
  "unit_extraction": "regex pattern or 'headings' or 'headings+numbered'",
  "structural_checklist": ["list", "of", "section", "types"],
  "scoring": "strict | moderate",
  "priority_description": "what counts as priority",
  "warn_threshold": 3
}
```

---

## Execution

### Step 0: File Pairing

- If `original` and `rewrite` are both files: single pair.
- If both are directories: match by filename. Warn on unmatched files in either direction.
- If `scope` is not `all`: filter to only the listed file identifiers (match as substring
  against filename, e.g., `01` matches `01-overview.md`).

### Step 1: Spawn Parallel Agents

For each file pair, spawn an independent agent (use Agent tool with `run_in_background: true`).
All file-pair agents are embarrassingly parallel — no shared state.

Each agent receives the full context below and executes Steps 2-5.

---

### Step 2: Extraction (per file pair)

For every comparison unit in the **original**, extract the full content from BOTH files.

Build a structured extraction table:

```
| Unit ID | Original sub-item count | Rewrite sub-item count | Original text (verbatim) | Rewrite text (verbatim) |
```

**Unit detection by profile:**
- `prd`: Scan for requirement ID patterns. Each ID's content = everything until the next ID
  or next H2/H3. Sub-items = acceptance criteria bullets, numbered items, or definition entries.
- `technical`: Each H2/H3 heading is a unit. Sub-items = numbered items under that heading.
- `generic`: Each heading at any level is a unit. Sub-items = all child content blocks
  (paragraphs, list items, table rows).

If a unit exists in the original but has **no match at all** in the rewrite, record it
immediately as MISSING — do not search for approximate matches.

### Step 3: Behavioral Diff (per file pair)

For each unit, compare side-by-side:

1. **Count check:** Original sub-item count vs rewrite sub-item count. Flag if rewrite < original.

2. **Sub-item matching:** For each original sub-item, find its rewrite equivalent by semantic
   similarity (same topic/intent). Then classify:

   - **PRESERVED:** Rewrite equivalent exists and preserves the behavioral meaning.
   - **MISSING:** No rewrite equivalent found. The sub-item was dropped entirely.
   - **MODIFIED:** Rewrite equivalent exists but changes the specified behavior
     (different logic, different constraint, different outcome).
   - **DEGRADED:** Rewrite equivalent exists but removes specificity. Subcategories:
     - `negative-constraint-removed`: "must not X" -> no mention of the constraint
     - `numeric-value-removed`: "< 200ms" -> "fast", "max 50 items" -> "limited"
     - `error-path-removed`: failure/error handling behavior dropped
     - `enum-values-removed`: specific allowed values -> vague "supported types"
     - `cross-reference-removed`: cross-feature, cross-section, or external references dropped
     - `contract-detail-removed`: API shapes, schema fields, config keys dropped

3. **Priority classification.** Assign every non-PRESERVED finding a priority:

   | Priority | Criteria | Examples |
   |----------|----------|---------|
   | **P0** | Loss changes system behavior, breaks a contract, or removes a safety constraint. If the rewrite shipped as-is, something would be built wrong. | MISSING requirement with acceptance criteria; MODIFIED behavior that inverts logic or changes an API contract; DEGRADED negative constraint removed ("must not" → silent); DEGRADED numeric bound removed where the bound is load-bearing (SLA, limit, timeout) |
   | **P1** | Loss reduces precision or completeness but doesn't change behavior. A careful implementer could infer the intent, but shouldn't have to. | DEGRADED enum values removed (implementer must guess valid set); DEGRADED cross-reference removed (context lost but behavior intact); MISSING sub-item within a unit where sibling items make the intent recoverable |
   | **P2** | Loss is cosmetic, editorial, or affects non-behavioral content. Rewrite is less thorough but functionally equivalent. | Reworded examples; removed redundant restatements; simplified prose without losing constraints; structural section present but condensed |

   **Tie-breaking:** When a finding straddles two priorities, choose the higher (more severe).
   The question to ask: "If an implementer reads only the rewrite, will they build the wrong
   thing (P0), have to guess (P1), or just miss color commentary (P2)?"

4. **Recommendation.** Assign every non-PRESERVED finding one of:

   | Recommendation | Meaning | When to use |
   |----------------|---------|-------------|
   | **REJECT** | The rewrite's version is wrong or incomplete. Restore the original content. | MISSING P0/P1 items; MODIFIED behaviors; DEGRADED items where the lost specificity is load-bearing (SLAs, security constraints, contract shapes) |
   | **MODIFY** | The rewrite's version has merit but lost something. Revise to restore the missing detail while keeping the rewrite's improvements. | DEGRADED items where the rewrite is clearer/shorter but dropped a specific value that should be re-added; structural consolidation that went slightly too far |
   | **ACCEPT** | The loss is acceptable. The rewrite is equivalent or the removed content was genuinely redundant. | P2 editorial changes; removed restatements; condensed prose that preserves all constraints |

   **Default mapping** (override with judgment when context warrants):
   - P0 MISSING/MODIFIED → REJECT
   - P0 DEGRADED → REJECT (unless the degradation is clearly cosmetic in context)
   - P1 → MODIFY
   - P2 → ACCEPT

5. **Output per unit:**
   ```
   ### [Unit ID]
   - Original sub-items: N
   - Rewrite sub-items: M
   - Preserved: X | Missing: Y | Modified: Z | Degraded: W
   - Details:
     - [MISSING] [P0:REJECT] "original text snippet..."
     - [DEGRADED:numeric-value-removed] [P1:MODIFY] "< 200ms response time" -> "fast response time"
     - [MODIFIED] [P0:REJECT] "retry 3 times with exponential backoff" -> "retry on failure"
     - [DEGRADED:cross-reference-removed] [P2:ACCEPT] "see Section 4.2" -> (omitted, section still exists)
   ```

### Step 4: Structural Diff (per file pair)

Run the profile's structural checklist. For each expected section type, check whether
it exists in both original and rewrite.

```
| Section type | In original? | In rewrite? | Verdict |
|-------------|-------------|-------------|---------|
| Data model table | Yes (3) | Yes (2) | WARN: 1 missing |
| Business rules | Yes | Yes | OK |
| State machine | Yes | No | MISSING |
```

### Step 5: Scoring (per file pair)

Apply the profile's scoring rules using the priority and recommendation assignments:

- **FAIL:** Any P0 finding with REJECT recommendation.
- **WARN:** No P0 REJECT, but any P1 REJECT or >threshold MODIFY findings across priority units.
- **PASS:** No REJECT findings at P0/P1 level and MODIFY count within threshold.

Profile-specific thresholds remain:
- `prd`: FAIL on any P0 REJECT; WARN threshold = 3 MODIFY findings
- `technical`: FAIL on any P0 REJECT; WARN threshold = 3 MODIFY findings
- `generic`: FAIL on any P0 REJECT; WARN threshold configurable (default: 3)

Write the per-file audit artifact to: `{rewrite_dir}/../audit/diff-{file-id}.md`

Structure of per-file artifact:
```markdown
# Diff Audit: {filename}
Profile: {profile} | Verdict: {PASS|WARN|FAIL}
Units: {total} | Missing: {n} | Modified: {n} | Degraded: {n} | Preserved: {n}
P0: {n} | P1: {n} | P2: {n} | REJECT: {n} | MODIFY: {n} | ACCEPT: {n}

## Extraction Table
(from Step 2)

## Behavioral Diff
(from Step 3, all units with findings — each line tagged [Priority:Recommendation])

## Triage Summary

| # | Unit | Finding | Subcategory | Priority | Recommendation | Original snippet | Rewrite snippet |
|---|------|---------|-------------|----------|----------------|------------------|-----------------|
| 1 | PUB-003 | MISSING | — | P0 | REJECT | "Must validate..." | (absent) |
| 2 | PUB-007 | DEGRADED | numeric-value-removed | P1 | MODIFY | "< 200ms" | "fast" |
| 3 | PUB-012 | DEGRADED | cross-reference-removed | P2 | ACCEPT | "see 4.2" | (omitted) |

## Structural Diff
(from Step 4)

## Verdict
{scoring rationale}
```

---

### Step 6: Rollup Summary

After ALL file-pair agents complete, produce `{rewrite_dir}/../audit/diff-audit-summary.md`:

```markdown
# Diff Audit Summary
Date: {ISO-8601}
Original: {original_path}
Rewrite: {rewrite_path}
Profile: {profile}

## Results

| File | Profile | Units | Missing | Modified | Degraded | Preserved | P0 | P1 | P2 | Verdict |
|------|---------|-------|---------|----------|----------|-----------|----|----|----|---------| 
| 01   | prd     | 22    | 0       | 0        | 2        | 20        | 0  | 1  | 1  | PASS    |
| 02   | prd     | 28    | 3       | 0        | 5        | 20        | 3  | 4  | 1  | FAIL    |

## Aggregate
- Total units: {sum}
- Total missing: {sum} | Total modified: {sum} | Total degraded: {sum}
- By priority: P0: {sum} | P1: {sum} | P2: {sum}
- By recommendation: REJECT: {sum} | MODIFY: {sum} | ACCEPT: {sum}
- Overall verdict: {FAIL if any file FAIL, else WARN if any WARN, else PASS}

## Action Items (REJECT + MODIFY only, by priority)

### P0 — REJECT (must restore)
| # | File | Unit | Finding | Original snippet |
|---|------|------|---------|------------------|
| 1 | 02   | PUB-003 | MISSING | "Must validate..." |

### P1 — MODIFY (revise to restore lost detail)
| # | File | Unit | Finding | Subcategory | Original | Rewrite |
|---|------|------|---------|-------------|----------|---------|
| 1 | 02   | PUB-007 | DEGRADED | numeric-value-removed | "< 200ms" | "fast" |

### P2 — ACCEPT (no action needed)
(listed for completeness, no action required)
```

Report the overall verdict and the summary path to the user.

---

## Critical Design Constraints

1. **The original is the reference standard.** Never compare against intermediate
   artifacts, templates, or schemas. Original text vs new text, directly.
2. **Verbatim extraction.** When populating the extraction table, copy text exactly.
   Do not summarize or paraphrase — the whole point is to detect when the rewrite
   did that inappropriately.
3. **Conservative matching.** When in doubt whether a rewrite sub-item matches an
   original, classify as MISSING rather than DEGRADED. False negatives (missed losses)
   are worse than false positives (flagged non-losses).
4. **No fixes.** This skill audits only. It does not modify either file. If the user
   wants fixes, they act on the audit output separately.

---

## Usage Examples

```
/diff-audit original=docs/v1/ rewrite=docs/v2/ profile=prd
/diff-audit original=spec.md rewrite=spec-compressed.md profile=technical
/diff-audit original=docs/v1/ rewrite=docs/v2/ scope=01,02,05
/diff-audit original=api-docs/ rewrite=api-docs-v2/ profile=generic
```

Standalone or invoked by `/prd-writer` after any rewrite step.
