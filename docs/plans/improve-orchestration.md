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

---

## Codex TDD Enforcement Audit — 2026-05-16

Independent review via `/codex consult` (GPT model, reasoning=high, 29k tokens).
Focus: TDD enforcement continuity in `lead-orchestrator` skill + templates.

### TDD Chain Breaks

| Gap | Location | Issue |
|-----|----------|-------|
| Weak row count check | Pre-QA Gates §3 | Accepts "at least one data row" — not one per behavior. Multi-behavior tasks pass with partial evidence. |
| No canonical behavior list | Pre-QA Gates §3, QA Step 1 | "Every behavior" is undefined. No mechanized inventory from requirement map or changed files. |
| Self-reported evidence | post-agent-audit hook | Checks `REQ-XX:` lines in output. Coder self-reports; no independent verification. |
| Structural-only validation | validate-artifact.sh | Checks table/header/SHA shape, not truth of TDD claims. |

### Enforcement Gaps (Instruction vs Gate)

| What | Reality |
|------|---------|
| Governance activation | Manual `touch .active`. No self-check before spawning. |
| `make test` in Pre-QA | Proves outcomes, not TDD ordering. |
| Commit-order hook | Only blocks code commits until *any* test-only commit exists. Does not prove failing-first, per-behavior, or test-relates-to-implementation. |
| Garry-Review GOVERNANCE_EXEMPT | Bypasses governance chain. Weakens continuous enforcement. |

### Bypass Scenarios

1. **One trivial test unlocks all code commits** — hook is "any test-only commit," not per-behavior.
2. **Write impl first, commit tests first** — commit-time ordering != edit-time ordering.
3. **Broad TDD-EXEMPT** — orchestrator accepts exemptions before QA. QA catches executable-logic exemptions, but only if reached.
4. **P1 skip at QA boundary** — "single-file changes" can contain meaningful executable logic without TDD.
5. **Tests in `tests/` can include helper implementation** — no rule prevents source-adjacent logic hiding in test commits.
6. **No check ReviewCommit SHA matches HEAD** — stale artifact passes pre-QA.

### Missing Checks (Not Verified Anywhere)

- RED test output (command, expected failure text, commit SHA) before implementation diff
- Failure reason matches intended missing behavior
- GREEN commit is minimal (only implements what RED demanded)
- Diff-based mapping: changed implementation lines -> covering tests
- Uncommitted implementation at ready-for-review time
- ReviewCommit includes both test+impl commits in expected order
- Hooks are installed, executable, active, and actually fired
- QA checkout happens on exact ReviewCommit (not stale tree)

### Timing / Ordering Problems

- Commit-time enforcement is too late for TDD (TDD = edit+run order)
- `.gate-pre-qa` set *after* coder returns — does not constrain coder during implementation
- Parallel Task spawning (Plan Execution §9) + shared git state can scramble commit ordering across tasks — no task/branch isolation specified

### QA Coverage Weaknesses

- QA Step 1 verifies artifact/table/log *presence*, not actual chronology
- QA cannot prove tests were written first — only that evidence docs claim so
- Auto-Reject rejects missing evidence, not false/stale/post-hoc evidence
- C2 does not re-audit TDD compliance
- Garry-Review "Tests" category has no mandate to validate RED/GREEN history

### Structural Contradictions

| Claim | Contradiction |
|-------|--------------|
| "Bash is E2E lifecycle only" (Allowed Tools) | Pre-QA §5 requires orchestrator `make test` |
| "Running impl tests -> coder's job" (Red Flags) | Pre-QA §5 requires orchestrator test run |
| "Orchestrator never codes" (Iron Law) | Gate 1 §4: "create lightweight doc in docs/" |
| "Spawn via Agent tool" (Template Protocol) | Allowed Tools says "Task" |

### Highest-Priority Fixes

1. **Machine-verified RED evidence**: require command output, commit SHA, test name, expected failure text, and timestamp *before* implementation diff lands.
2. **Per-behavior commit guard**: hook should track test->impl pairing per behavior, not "any test unlocks all code."
3. **Independent TDD mapping at Pre-QA**: map requirement IDs -> TDD rows -> test files -> commits -> changed impl files mechanically.
4. **Reject broad TDD-EXEMPT at Pre-QA**: don't wait for QA to catch executable-logic exemptions.
5. **Verify hooks are active**: fail-closed check before every spawn; if `.active` missing, refuse to proceed.
6. **Separate TDD audit from outcome QA**: make QA explicitly audit git history with hard evidence, or add a dedicated TDD-audit step.

### Recommendation

Fix #1 (machine-verified RED evidence) first because it closes the largest class of bypasses — without it, every other check trusts self-reported artifacts and commit ordering that can be trivially gamed by writing code first and committing tests first. The commit-order hook (#2) is second-priority because it's the enforcement mechanism that #1 feeds into.

---

## Implementation Status — 2026-05-16

| Fix | Status | Implementation |
|-----|--------|---------------|
| #1 light (verify RED commit is test-only) | DONE | `scripts/verify-tdd-evidence.sh` — checks RED commits only touch test files via `git diff-tree` |
| #3 (independent TDD mapping at Pre-QA) | DONE | Same script — verifies commit SHAs exist, RED/GREEN ordering via `git merge-base --is-ancestor` |
| #4 (reject broad TDD-EXEMPT on impl files) | DONE | Enhanced `scripts/validate-artifact.sh` — rejects TDD-EXEMPT when impl files in src/lib/app/pkg/internal/cmd modified |
| #5 (verify hooks are active, fail-closed) | DONE | `SKILL.md` governance section rewritten — auto-activates `.active`, warns on stale sentinels |
| #2 (per-behavior commit guard) | SKIPPED | Over-engineering per independent review. Current hook + #1/#3 provides sufficient coverage. |
| #6 (separate TDD audit step) | SKIPPED | Redundant with #3. Mechanical verification gives 80% of benefit at 10% cost. |

### Files Changed
- `skills/lead-orchestrator/SKILL.md` — Governance Activation (fail-closed), Pre-QA Gates (step 5 added for verify-tdd-evidence.sh), Hook Scripts table updated
- `skills/lead-orchestrator/scripts/verify-tdd-evidence.sh` — NEW: mechanical TDD evidence verification against git history
- `skills/lead-orchestrator/scripts/validate-artifact.sh` — ENHANCED: rejects TDD-EXEMPT when impl files modified

---

## ChatGPT's additional improvement suggestions — 2026-05-16


Then fix the skill by moving from **prompt obedience** to **mechanical enforcement**.

## What actually failed

The root cause is not “Claude forgot.” The real failure is that the skill relied on the model to voluntarily remember and obey process rules after a long branching conversation. That is inherently weak.

Claude Code has better primitives for this now: **skills can include supporting files like templates, examples, and validation scripts**, and **hooks can run automatically at lifecycle points and block actions**. Anthropic’s docs explicitly describe hooks as deterministic control points that ensure actions happen “rather than relying on the LLM to choose to run them.” ([Claude][1])

So: stop asking Opus to remember. Make it impossible or obviously failing to proceed without proof.

---

# Recommended design

## 1. Make `design-doc-template.md` executable via a renderer, not just readable prose

Best solution: Claude should **not directly write the final design doc**.

Instead:

```text
design-doc-template.md       # canonical template
design-doc.schema.json       # required fields / sections
design-doc-input.json        # Claude fills this only
scripts/render_design_doc.py # deterministic markdown renderer
scripts/validate_design_doc.py
```

Claude fills `design-doc-input.json`. A script renders the markdown using the canonical template. Then another script validates the output.

That converts the key artifact from:

> “Claude, please follow this template”

to:

> “Claude may only provide structured data; code owns the template.”

This is the strongest fix because it removes template adherence from the LLM almost entirely.

**Tradeoff:** More upfront work. But for critical planning artifacts, this is the right architecture.

---

## 2. Add a fail-closed checkpoint state machine

Replace loose `progress.json` with a real phase gate:

```json
{
  "skill": "eng-planning",
  "phase": "E_DESIGN_DOC",
  "allowed_next_phase": "F_FINAL_REVIEW",
  "required_evidence": {
    "template_read_after_phase_start": false,
    "design_doc_rendered_from_template": false,
    "validator_passed": false,
    "opus_subagent_used": false
  },
  "template_sha256": "..."
}
```

Then require phase transitions to happen only through a script:

```bash
python .claude/skills/eng-planning/scripts/advance_phase.py E_DESIGN_DOC F_FINAL_REVIEW
```

`advance_phase.py` should fail unless all required evidence exists.

Claude should never be allowed to “mark Step 5 complete” by editing JSON manually. The model can request transition; the script decides.

---

## 3. Use Claude Code hooks as hard gates

Use hooks for deterministic enforcement, not reminders.

Anthropic’s hook docs say `PreToolUse` can block tool calls, `Stop` can prevent Claude from stopping, `UserPromptExpansion` can inject context when a slash command expands, and hooks can block with exit code `2` or JSON decisions. ([Claude][2])

For your skill, I’d use these hooks:

### A. `UserPromptExpansion` hook for `/eng-planning`

Inject the latest template hash, current phase, and non-negotiable rules every time the skill starts.

Purpose: prevent stale skill context.

```text
On /eng-planning expansion:
- compute sha256 of design-doc-template.md
- inject current checkpoint state
- inject “you may not write final design doc directly”
```

### B. `PostToolUse` hook on `Write|Edit`

When Claude writes or edits a design doc, immediately run:

```bash
python .claude/skills/eng-planning/scripts/validate_design_doc.py <path>
```

Purpose: catch drift immediately after artifact creation.

### C. `Stop` hook

Before Claude says it is done, block completion unless:

```bash
python .claude/skills/eng-planning/scripts/check_stop_allowed.py
```

passes.

Purpose: prevent the exact failure you saw: Claude confidently finishes while process compliance is false. Claude Code’s docs explicitly say `Stop` hooks can block Claude from stopping and force continuation. ([Claude][2])

### D. `PreCompact` / `PostCompact` hook

If compaction happens mid-skill, re-inject:

```text
Current phase
Required next action
Template hash
Checkpoint obligations
```

This addresses “context decay” directly. The docs call out hooks for re-injecting context after compaction. ([Claude][3])

---

## 4. Add transcript-based evidence checks

Do not let Claude self-attest “I read the template.”

Have the validator inspect the Claude transcript JSONL and require actual evidence:

```text
PASS only if transcript contains:
- Read tool call for design-doc-template.md
- timestamp after entering E_DESIGN_DOC
- Write/Edit to generated design doc after the template read
- validation script run after final Write/Edit
- designated subagent invocation if required
```

This turns “I followed the process” into auditable fact.

This is especially important because the model’s self-reflection is unreliable as a control mechanism. It may be honest after the fact, but that does not prevent recurrence.

---

## 5. Split artifact generation into a narrow subagent

Create a dedicated subagent:

```text
design-doc-writer
```

Give it one job:

```text
Read design-doc-template.md.
Read design-doc-input.json.
Produce design-doc.md through the renderer only.
Run validator.
Return only validator result + path.
```

Claude Code supports custom subagents with their own prompts, tools, permissions, hooks, and skills. It also supports running skills in forked isolated context via `context: fork`, where the subagent receives the skill content as the task and does not inherit the long prior conversation. ([Claude][4])

This directly counters the failure mode:

```text
long conversation → procedural decay → model improvises
```

The artifact writer should have a clean, tiny context and no permission to freestyle.

---

# Options table

| Option                                      | Determinism |      Effort | What it fixes                       | Tradeoff                                  |
| ------------------------------------------- | ----------: | ----------: | ----------------------------------- | ----------------------------------------- |
| Add stronger prompt reminders               |         Low |         Low | Mildly reduces forgetting           | Still depends on model obedience          |
| Re-read template at every phase boundary    |      Medium |         Low | Reduces context decay               | Still not fail-closed                     |
| Add checkpoint checklist in `progress.json` |      Medium |         Low | Makes obligations visible           | Claude can still mark things done falsely |
| Use validator scripts                       |        High |      Medium | Catches template drift              | Requires writing validation logic         |
| Use `Stop` hook to block completion         |   Very high |      Medium | Prevents false “done”               | Needs hook setup                          |
| Render final doc from JSON + template       |     Highest | Medium-high | Removes template adherence from LLM | More engineering                          |
| Transcript evidence audit                   |   Very high | Medium-high | Prevents fake self-attestation      | Needs transcript parsing                  |
| Dedicated design-doc subagent               |        High |      Medium | Avoids long-context decay           | Still needs validator                     |
| Full state machine + hooks + renderer       |     Highest |        High | Makes process compliance mechanical | Best for critical skills                  |

My recommendation: do **renderer + validator + Stop hook + transcript evidence**. That is the smallest architecture that is actually deterministic.

---

# Concrete implementation shape

Your skill folder should look like this:

```text
.claude/skills/eng-planning/
├── SKILL.md
├── templates/
│   └── design-doc-template.md
├── schemas/
│   └── design-doc-input.schema.json
├── examples/
│   └── design-doc.example.md
├── state/
│   └── progress.json
└── scripts/
    ├── render_design_doc.py
    ├── validate_design_doc.py
    ├── advance_phase.py
    ├── check_stop_allowed.py
    └── audit_transcript.py
```

## `SKILL.md` should contain blunt operational rules

```md
## Non-negotiable execution rules

Do not write `design-doc.md` directly.

For the design-doc phase:

1. Read `templates/design-doc-template.md`.
2. Compute and record its SHA256.
3. Fill `artifacts/design-doc-input.json`.
4. Run `scripts/render_design_doc.py`.
5. Run `scripts/validate_design_doc.py`.
6. Run `scripts/advance_phase.py`.
7. Do not mark the phase complete manually.

If any script fails, stop and fix the underlying artifact. Do not bypass the script. Do not self-certify compliance.
```

## `check_stop_allowed.py` should block done-state

Pseudo-logic:

```python
required = [
    "template_read_after_phase_start",
    "design_doc_rendered_from_template",
    "validator_passed_after_last_edit",
    "checkpoint_advanced_by_script",
]

if current_phase_requires_design_doc and not all(required):
    print("Blocked: design-doc phase is not compliant. Re-read template, render via script, validate, then advance phase.", file=sys.stderr)
    sys.exit(2)

sys.exit(0)
```

Exit code `2` is important because Claude Code treats it as the blocking signal for hook enforcement. ([Claude][2])

---

# Prompt to give Claude Code now

Paste this after committing:

```md
We need to harden the eng-planning skill so it cannot skip `design-doc-template.md` or critical checkpoints again.

First, inspect the current skill structure. Then implement deterministic enforcement with the smallest robust change set.

Requirements:

1. Do not rely on prompt reminders alone.
2. Add a fail-closed checkpoint mechanism.
3. Design-doc generation must be mechanically tied to `design-doc-template.md`.
4. Claude must not be able to mark the design-doc phase complete by manually editing progress state.
5. Add validation scripts that can be run from CLI.
6. Add or propose Claude Code hooks that block completion if required evidence is missing.
7. Add transcript/evidence checks where practical.
8. Update SKILL.md so phase boundaries explicitly call the enforcement scripts.
9. Add a README section explaining the compliance mechanism and how to test it.

Preferred architecture:
- `templates/design-doc-template.md` is canonical.
- Claude fills structured input.
- script renders the design doc.
- script validates the rendered doc.
- phase transition happens only via `advance_phase.py`.
- `check_stop_allowed.py` fails closed if compliance is incomplete.

Before changing files:
- read the current SKILL.md
- read the current design-doc-template.md
- read existing progress/checkpoint logic
- produce a brief implementation plan

After changing files:
- run the validators
- run a negative test proving direct/manual completion fails
- show git diff summary
```

---

# The sharp rule

For critical artifacts, never let the LLM be both:

```text
the worker
the judge
the process auditor
```

Make Claude the worker. Make scripts the judge. Make hooks the cop.

[1]: https://code.claude.com/docs/en/skills "Extend Claude with skills - Claude Code Docs"
[2]: https://code.claude.com/docs/en/hooks "Hooks reference - Claude Code Docs"
[3]: https://code.claude.com/docs/en/hooks-guide "Automate workflows with hooks - Claude Code Docs"
[4]: https://code.claude.com/docs/en/sub-agents "Create custom subagents - Claude Code Docs"

