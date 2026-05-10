# Plan: Improve Orchestration

**Date:** 2026-03-28 (Layers 0-2), 2026-05-10 (eng-planning analysis)

---

## Completed Work (summary)

- **Layer 0: Fix Spec Wall Path** — Changed `docs/prd/features/` → `docs/` across 8 files. Done 2026-03-28.
- **Layer 1: PreToolUse Hook on Task** — Two-tier warn/block gate for subagent spawning without spec refs. Done 2026-03-28.
- **Layer 2: Spec Registry with Frontmatter** — Auto-generated `docs/spec-registry.yaml` from frontmatter + pre-commit hook + orchestrator injection. Done 2026-03-28.

---

## eng-planning Skill Analysis (2026-05-10)

**Context:** eng-planning at 1,884 total lines ranks #9 of 31 gstack skills (p74). Risk: 3/5. Primary risk is subagent indirection (templates read at runtime), not raw size.

### ASCII Logic Tree — Full Execution Flow

```
/eng-planning [prd-path] [--tier N]
│
├─ SKILL.md ALWAYS LOADED (1,056 lines — loaded by Skill tool on invocation)
│
├─ Step -1: Resume Detection
│   └─ Read progress.json → resume or fresh start
│
├─ Step 0: Locate & Read PRD
│
├─ Step 0.5: Tier Detection
│   ├─ CLI override OR auto-detect from PRD signals
│   ├─ AskUserQuestion → confirm tier
│   └─ Set remaining_steps per tier:
│       ├─ Tier 1: [1,2,3,5,6,7,8,9,11,12,12.5,13]      ← SKIP 7.5, 7.6, 10
│       ├─ Tier 2: [1,2,3,5,6,7,7.5,7.6,8,9,10,11,12,12.5,13]
│       └─ Tier 3: [1,2,3,5,6,7,7.5,7.6,8,9,10,11,12,12.5,13]
│
├─ PHASE B (parallel):
│   ├─ Step 1: Codebase Exploration
│   │   └─ READ explorer-prompt.md (153 lines) ←── ALWAYS
│   │       └─ Spawn Sonnet subagent(s) with filled template
│   │
│   ├─ Step 4: Dependency Verification (inline, no template)
│   │
│   ├─ Step 2.4: WebSearch checks (inline, no template)
│   │   └─ Tier 2: AskUserQuestion "skip?" gate
│   │
│   └─ Step 2.7: Backlog cross-ref (inline, no template)
│
├─ PHASE C (sequential):
│   ├─ Step 2: Scope Challenge synthesis (inline)
│   └─ Step 3: Design Decisions (inline, AskUserQuestion loop)
│
├─ PHASE D (parallel Opus subagents):
│   ├─ Step 5a: Feature Design Doc
│   │   └─ READ design-doc-template.md (263 lines) ←── ALWAYS
│   │       └─ Spawn Opus subagent with filled template
│   │
│   └─ Step 5b: API Contract
│       └─ Uses contract section from design-doc-template.md ←── CONDITIONAL
│           ├─ Tier 1: inline if no API endpoints, else separate
│           ├─ Tier 2: AskUserQuestion "inline or separate?"
│           └─ Tier 3: always separate
│
├─ PHASE E (parallel, append to design doc):
│   ├─ Step 6: Codepath Coverage (uses section from design-doc-template.md)
│   └─ Step 7: DAG Validation (inline)
│
├─ PHASE E.5: PRD Traceability
│   └─ READ traceability-pipeline.md (221 lines) ←── CONDITIONAL
│       ├─ Tier 1: SKIP entirely
│       └─ Tier 2/3: Run 3-agent pipeline
│
├─ PHASE E.6: Quality Synthesis
│   └─ READ quality-synthesis-prompt.md (52 lines) ←── CONDITIONAL
│       ├─ Tier 1: SKIP entirely
│       └─ Tier 2/3: Spawn Opus subagent
│
├─ PHASE F (sequential):
│   ├─ Step 8: Present artifacts for approval (inline)
│   │
│   ├─ Step 9: Engineering Review
│   │   └─ READ review-prompt.md (103 lines) ←── CONDITIONAL
│   │       ├─ Tier 1: SKIP template, use inline simplified prompt
│   │       └─ Tier 2/3: Full template
│   │
│   ├─ Step 10: Auto-Fix Loop
│   │   ├─ Tier 1: SKIP entirely
│   │   ├─ Tier 2: max 1 iteration → re-spawns review (re-reads review-prompt.md)
│   │   └─ Tier 3: max 2 iterations → re-spawns review (re-reads review-prompt.md)
│   │
│   ├─ Step 11: Pre-Final Output (inline)
│   │
│   ├─ Step 12: Final Traceability Gate
│   │   └─ READ traceability-pipeline.md (221 lines) ←── ALWAYS (but tier-conditional depth)
│   │       ├─ Tier 1: Simplified 1-2 Sonnet agents (DON'T use template)
│   │       └─ Tier 2/3: Full 3-agent pipeline (uses template)
│   │
│   ├─ Step 12.5: Post-Review Spot-Check
│   │   └─ READ spot-check-prompt.md (36 lines) ←── ALWAYS
│   │
│   └─ Step 13: Cleanup & Output (inline)
```

### Template Loading Summary

| Template | Lines | Loaded When | Times Read Per Run |
|----------|------:|-------------|-------------------|
| `explorer-prompt.md` | 153 | Always (Step 1) | 1 (or 2 for multi-repo split) |
| `design-doc-template.md` | 263 | Always (Step 5a, referenced by 5b, 6) | 1-2 |
| `traceability-pipeline.md` | 221 | Tier 2/3 only (Steps 7.5 + 12) | 2 (pre-approval + post-review) |
| `quality-synthesis-prompt.md` | 52 | Tier 2/3 only (Step 7.6) | 1 |
| `review-prompt.md` | 103 | Tier 2/3 only (Step 9, possibly re-read in Step 10) | 1-3 |
| `spot-check-prompt.md` | 36 | Always (Step 12.5) | 1 |

Templates are NOT all loaded at once. They load conditionally at specific steps. Three are always loaded (explorer, design-doc, spot-check = 452 lines), two are tier-gated (traceability, quality-synthesis = 273 lines), and one is tier-gated with an inline fallback (review = 103 lines). At Tier 1, only 452 lines of templates are read. At Tier 3, all 828 lines could be read.

### Redundancy & Bloat Findings

#### Finding 1: Language Standard repeated 4 times (~90 duplicated lines)

The same "explain to a smart CS senior" rule appears in:
- **SKILL.md:24-82** — Full section with examples (58 lines)
- **SKILL.md:81** — "Include this preamble in EVERY subagent prompt" (1-line block)
- **explorer-prompt.md:74-84** — Near-identical section (11 lines)
- **design-doc-template.md:133-140** — Identical examples section (8 lines)

The copies in templates are necessary (subagents are isolated). But SKILL.md includes 4 BAD/GOOD example pairs that are variations of the same lesson. Two examples would suffice (~30 lines saveable).

#### Finding 2: traceability-pipeline.md is read TWICE per Tier 2/3 run

Steps 7.5 and 12 both read and execute the same 221-line template. This is intentional — Step 7.5 checks pre-approval, Step 12 checks post-review. No fix needed.

#### Finding 3: review-prompt.md chain-loads plan-eng-review skill

The review template (line 8) says "Invoke the `plan-eng-review` skill" then lists 16 sections to SKIP and 6 to FOLLOW. The subagent loads the full external skill then applies ~30% of it. The "sections to FOLLOW" could be inlined into review-prompt.md to eliminate chain-load overhead.

#### Finding 4: Tier 1 inline prompts duplicate parts of templates

At Tier 1, three templates are bypassed with inline prompts in SKILL.md (Step 9: 18 lines, Step 12: 4 lines). These share structural elements with their template counterparts but are simplified. Not redundancy — the tier system working as designed.

#### Finding 5: Vertical Slice rules repeated between SKILL.md and design-doc-template.md

The vertical slice mandate in SKILL.md (lines 88-198, ~110 lines) contains rules the design-doc subagent needs but can't access (subagents don't see SKILL.md). Current mitigation: Step 5a prompt includes the mini-spec rules from SKILL.md explicitly via copy-paste. Could be moved into design-doc-template.md to make it self-contained.

#### Finding 6: Story-Level Consolidation section is dense and example-heavy

SKILL.md lines 155-198 (43 lines) contain Anti-Fragmentation rules with a 19-line ASCII tree example. Loaded into context every time but only relevant during Step 5a. Could be a template read on-demand.

#### Finding 7: Jira Hierarchy Mapping section

SKILL.md lines 135-152 (17 lines). Always loaded but only relevant during Step 5a. Low bloat but could move to design-doc-template.md.

### Quantified Redundancy

| Category | Lines | Assessment |
|----------|------:|------------|
| Language Standard duplicated across files | ~90 | Necessary for subagents; SKILL.md examples trimmable by ~30 lines |
| Vertical Slice rules (main agent only, subagent needs via prompt copy) | ~110 | Move to design-doc-template.md |
| Story Consolidation examples | ~43 | Move to template; only Step 5a needs them |
| Jira Hierarchy Mapping | ~17 | Move to template |
| Tier 1 inline prompts | ~22 | Acceptable |

**Total addressable:** ~200 lines moveable from SKILL.md to templates (SKILL.md drops from ~1,056 to ~850). Templates grow by ~170 lines but only load when needed, reducing net context cost per run.

### Structural Observations

- **No loops found.** Execution is strictly a DAG. Auto-fix loop (Step 10) bounded at max 2 iterations. Traceability re-runs (Step 7.5) bounded at max 2.
- **No template merges recommended.** Each template serves a distinct subagent role. Merging would create a monolith every subagent loads but only partially uses.

### Recommendations (not yet implemented)

- [ ] **R1:** Move Vertical Slice rules (~110 lines), Story Consolidation (~43 lines), Jira Hierarchy Mapping (~17 lines) from SKILL.md into design-doc-template.md
- [ ] **R2:** Trim Language Standard in SKILL.md from 4 BAD/GOOD example pairs to 2 (~30 lines saved)
- [ ] **R3:** Inline the 6 plan-eng-review sections into review-prompt.md to eliminate chain-load of external skill
- [ ] **R4:** No structural changes to template split or tier system — architecture is sound
