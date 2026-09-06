---
name: prd-writer
description: "Write a high-quality, data-driven PRD (Product Requirements Document) from scratch or from rough notes. Use whenever a user wants to CREATE a PRD, product spec, product brief, feature spec, or requirements document — including when they say 'write a PRD', 'help me spec this out', 'I need a product doc', 'turn this into a PRD', 'product requirements', or share rough notes/briefs asking to formalize them. Also the style/format authority when bulk-rewriting existing PRDs to this format (e.g., 'use prd-writer to rewrite every PRD', orchestrated subagent rewrites) — see the Bulk / Orchestrated Rewrite Contract. Compact by default — consolidates redundant sections, enforces 'describe once, reference by ID' (REQ-NNN), and mandates dense formatting. Enforces data-driven rigor, testable hypotheses, prior-art honesty, and structured engineering estimates. NOT for reviewing, critiquing, or improving an existing PRD — use /prd-review. NOT for pure engineering design docs, architecture docs, or technical RFCs that aren't product-facing — use /eng-planning."
---

## Required Files
- `references/quality-patterns.md` — Quality patterns with density rules
- `references/discovery-brief-format.md` — Standalone stakeholder pitch format (Mode C only)
- `templates/acme-prd-template.md` — Full PRD structure template (Mode A)
- `templates/prd-lite-template.md` — PRD-Lite 1-pager template (Mode B)
- `templates/prd-scaffold.md` — TODO-marked scaffold for subagent drafting (prevents structural amnesia)
- `scripts/validate-prd.sh` — Post-production structural validation (catches missing sections, format violations)
- `scripts/prd-writer-agent-gate.sh` — PreToolUse hook: enforces template reference in subagent prompts
- `scripts/prd-writer-write-gate.sh` — PreToolUse hook: validates PRD structure on write

# PRD Writer (Compact)

Optimized for density. Same rigor as verbose PRDs but you must not lose specificity. Execute according to `references/quality-patterns.md`

## Invocation Paths (pick ONE before doing anything else)

| Situation | Path |
|---|---|
| User wants a new PRD, has rough notes or nothing | Interactive Workflow below (Steps 0-7) |
| User supplies a pre-answered input file ("here are my answers", a filled brief, annotated meeting notes) | Interactive Workflow, but Step 2 runs in **Pre-Answered Input Mode** (see Step 2) |
| An orchestrator (or the user) wants MULTIPLE existing PRDs rewritten to this format via parallel subagents | **Bulk / Orchestrated Rewrite Contract** (section after the Workflow) — the interactive Steps 0-7 do NOT run per file |
| User wants an existing PRD reviewed/critiqued/improved | Route to `/prd-review` (see Critique Requests) |

**Decision criteria:** count the target documents and check who answers questions. One document + a human answering → interactive. One document + answers already written down → pre-answered mode. Many documents + subagents doing the writing → bulk contract.
- *Positive example:* "Orchestrate max parallel subagents to use /prd-writer to rewrite every PRD under docs/prds/" → Bulk Contract.
- *Negative example:* "Write a PRD for the briefcase feature, here are my notes" → interactive Workflow, NOT the bulk contract, even though notes exist — one document, human in the loop.

**Density design choices:**
- Sections that repeated info (Problem + JTBD + Business Rules) are consolidated — describe once, reference by ID
- Business rules live inline in §2 requirements (simple as behaviors, complex as dedicated REQ-IDs) — no separate section
- UX Flows section is dedicated (§3) but organized by JTBD with explicit req ID references + illustrative edge flows — no redundancy
- Data Model lives under §7 Engineering (after effort estimates) — keeps all eng-facing content together
- Prose that restates tables is banned
- Wireframes: 3-5 per feature PRD for major interaction patterns
- Acceptance criteria minimums are guidance, not floors
- Compact formatting preferred (inline pipes, dense bullets) over multi-line prose

## Core Principles

1. **Every claim needs a number.** Never "significant improvement" — write "+1.65% OESPD."
2. **Hypotheses, not descriptions.** "If we [X], THEN [Y] because [Z]."
3. **Brutal honesty about prior art.** Document what's been tried, what failed, what's different.
4. **Show the projection math.** Expose derivation: "[base] x [rate] = [outcome]."
5. **User voice, not corporate voice.** "I don't know what to share" not "Users experience friction."
6. **Implementation-ready requirements.** Each P0/P1 gets numbered acceptance criteria mapping to test cases.
7. **Hypotheses tied to measurable KPIs.** Each feature gets a KPI table (qual primary for early-stage, quant for mature).

### End-User POV Rule (Hard Enforcement)

**§1-6 must be written entirely in user-facing language. No exceptions.**

Implementation detail — libraries, protocols, architecture patterns, data schemas, service internals, algorithms, regex patterns, field mappings — belongs ONLY in §7 Engineering or in the TAR. If content cannot be translated to user-facing language or has no direct user/business impact, it does not belong in the PRD.

**The test:** Can a product stakeholder read this sentence and understand why it matters to users? If no — translate to user impact or remove entirely. There is no "sparingly OK" exception for §2 acceptance criteria.

**Acceptance criteria rule:** Each acceptance criterion describes observable system behavior in user terms. Concrete values (field lengths, timeouts, colors) are fine when they describe what the user sees. Internal values (array indices, token budgets, buffer sizes, data field names) fail the test.

**Bad (eng detail in §1-6):**
> "The BFF normalizes the source field on each retrieved_docs entry to a single canonical type: 'chunks, keyword' → 'documents'"

**Good (user-facing in §1-6):**
> "Citation pills are color-coded by source type: gray for documents, purple for web results, orange for news articles"

**Where the eng detail goes:** §7 Engineering or the TAR.

### Density Rules

8. **Describe once, reference everywhere.** Every behavior, flow, or rule has ONE canonical location. All other mentions use `-> See REQ-002.2` or `(per REQ-010.2)`. If you're writing the same logic in two sections, one of them is wrong.

9. **Tables speak for themselves.** Never follow a table with prose restating its contents. If the table needs explanation, the table is poorly structured — fix the table.

10. **Compact over verbose.** Prefer `Agendas 1-3: full wizard | 4-10: quick start | >10: button-only` over 4-line bullet lists saying the same thing. Use inline separators, dense bullets, and compressed conditional notation.

11. **Compression never trades away specificity.** Any edit whose goal is "shorter" must pass the Fidelity Gate (Step 6). Density comes from formatting (pipes, tables, ID references), never from deleting behaviors, values, or edge cases.

---

## Workflow

### Working Files (Context Preservation)

Intermediary checkpoint files prevent context loss across the long interview — each step writes its state to disk so a later step (or a resumed session) never depends on conversation memory.

**File naming:** Slugify the feature name (e.g., "Board Briefcase" -> `board-briefcase`). If unclear, use `prd-draft-YYYY-MM-DD`.

**Output directory:** Project's `docs/` if it exists, otherwise cwd.

**Intermediary files:** stored under `docs/temp` if it exists, otherwise cwd
- `<working-name>-context.md` — Step 1 checkpoint
- `<working-name>-interview.md` — Step 2 checkpoint
- `<working-name>-research.md` — Step 3 checkpoint

**Cleanup:** Archive checkpoints to `docs/temp/archive/` after final PRD is generated (preserves audit trail for debugging format deviations). Use `AskUserQuestion` to confirm before archiving.

### Step 0: Resume Detection

Check for existing `*-context.md`, `*-interview.md`, `*-research.md` in `docs/` and project root. If found, use `AskUserQuestion` to offer resume vs. start fresh (list which checkpoint files were found). If not found, proceed to Step 0.5.

### Step 0.5: Determine Document Mode

Based on the user's request, determine which format to use:

**Mode A: Full PRD** (default)
Trigger: User asks for a "PRD", "spec", "product requirements", or provides enough context for a full document.
Template: `templates/acme-prd-template.md` (all 12 sections)

**Mode B: PRD-Lite (1-pager / discovery brief)**
Trigger: User asks for a "1-pager", "discovery brief", "early-stage doc", or explicitly says they don't have enough data for a full PRD.
Template: `templates/prd-lite-template.md` (sections 1, 2, 3, 7)

**Mode B hard minimums (structure is reduced, rigor is not):**
1. **≥1 UX flow per JTBD** in §3 — numbered steps, references its REQ-IDs. A PRD-Lite with a §3 that only says "TBD" fails validation.
2. **Numbered-bullet acceptance criteria** on every P0/P1 requirement, same `[P0]`/`[P1]` tag format as the full PRD, ≥2 per P0 area.
3. **NO Data Model** and no other §7 data-model subsection unless the user explicitly asks for one. Effort estimate ranges only.
- *Positive example:* JTBD-1 has `### Flow: Quick Add → REQ-001` with 3 numbered steps, and REQ-001 lists `1. [P0] ...` `2. [P0] ...` → valid Mode B.
- *Negative example:* delivering a PRD-Lite with a "Data Model" table of columns and endpoints the user never asked for, and requirements written as prose paragraphs without numbered ACs → violates minimums 2 and 3; fix before presenting.

**Mode C: Stakeholder Pitch**
Trigger: User explicitly asks for a "pitch brief", "stakeholder alignment doc", or "conversation starter."
Template: `references/discovery-brief-format.md` (standalone format, not expandable to full PRD)

If ambiguous, use `AskUserQuestion` with these options:
- **Full PRD** — All 12 sections, production-grade
- **PRD-Lite** — Problem, JTBD, Engineering Effort; expandable to full PRD later
- **Stakeholder Pitch** — Standalone conversation starter, not expandable

**Default to Mode B** when the user says "discovery brief" or "1-pager." Mode C requires explicit "pitch" or "conversation starter" language.

### Step 1: Gather Context

Assess what the user brought (raw notes, brief, verbal description, custom template). Extract: product/feature, target user, problem, data/metrics, prior art, org context. Identify gaps for interview.

**Checkpoint:** Write `<working-name>-context.md` with extracted context and identified gaps.

### Step 2: Interview for Gaps (MANDATORY — NEVER SKIP)

**HARD GATE:** Execute this step even if the user's input appears complete. "Already covered" is not a reason to skip — user confirmation IS the point. If a mandatory question was answered in Step 1, state your understanding and ask the user to confirm or correct. Do NOT silently assume. Skipping = protocol violation equivalent to skipping TDD.

**Procedure:** Use `AskUserQuestion` for ALL interview questions. Batch into 3 rounds (max 4 questions per call). If a mandatory question was already answered in Step 1, pre-fill your understanding as the question description and ask the user to confirm or correct via the "Other" escape hatch. Do NOT proceed to Step 3 without answers to all 3 rounds.

#### Pre-Answered Input Mode (single confirmation pass)

**When it applies:** the user hands over a file or pasted block that already answers the interview — a filled question list, an annotated brief, meeting notes with decisions. Signals: "I've answered your usual questions", "everything you need is in answers.md", an input whose content maps 1:1 onto M1-M9 topics.

**Decision criteria:** the input must contain *answers* (decisions, named users, concrete scopes), not just *material* (background docs, transcripts, competitor links). Material → run the normal 3-round interview using it as Step 1 context. Answers → this mode.
- *Positive example:* user attaches `briefcase-answers.md` with headings "Who uses it", "Scope", "Failure modes" and concrete decisions under each → Pre-Answered Input Mode.
- *Negative example:* user attaches a 40-page competitor teardown and says "write the PRD from this" → that is research material, not answers; run the full 3-round interview.

**Procedure (replaces Rounds 1-3, NOT the gate):**
1. Read the input. Map its content onto M1-M9. For each item record: the answer, the source line/section, and a confidence (Answered / Partially answered / Not covered).
2. Present the full mapping as text: "Here is my reading of M1-M9 from your input" — one line per item, quoting or paraphrasing the source.
3. Run ONE `AskUserQuestion` confirmation pass over the mapping: "Confirm this reading, or name the items to correct." Options: **All correct — proceed** / **Correct specific items (list them)** / **Walk me through the questions anyway**.
4. Items marked "Not covered" are NOT silently assumed — ask them in one normal batched round (they are usually 1-3 questions, e.g., M8/M9 failure modes).
5. Run the Ambiguity Probe as usual — pre-answered input does not exempt ambiguity resolution.

This mode satisfies the HARD GATE: the confirmation pass IS the user confirmation. What it removes is re-asking questions the user already answered in writing.

**If the user explicitly declines the interview** ("just draft it", "skip the questions") and provided no pre-answered input: do NOT skip silently. Present the full list of M1-M9 with your best-guess answer for each in ONE AskUserQuestion call ("Confirm these assumptions or correct any"). Mark every unconfirmed answer as `[Assumed]` in the interview checkpoint so the drafting subagent knows which requirements rest on assumptions.

**Follow-up rule:** After each round, review answers. If any answer is too vague to write a requirement against (e.g., "improve engagement" for M3, or "everyone" for M7), use another `AskUserQuestion` to push for specifics before moving to the next round.

#### Round 1: Context & Users (AskUserQuestion — 3 questions)

| Q# | Header | Question | Options |
|----|--------|----------|---------|
| M1 | Users | "Who exactly uses this — role, context, frequency? What do they already know?" | *(open-ended)* Single persona, Multiple personas (describe primary), Broad audience, Internal team |
| M2 | Current state | "How is this job done today? What's the specific moment of friction or failure?" | *(open-ended)* Manual workaround exists, Competitor tool used, Not done at all, Partially automated |
| M3 | Scope | "What's in scope vs. explicitly out? What's the most likely scope creep risk?" | *(open-ended)* Well-defined boundaries, Still fuzzy — help me define, V1 only — list what to defer, No constraints yet |

#### Round 2: Feature Behavior & Design (AskUserQuestion — 4 questions)

| Q# | Header | Question | Options |
|----|--------|----------|---------|
| M4 | Happy path | "Walk me through the ideal experience: what triggers it, what does the user see at each step, what's the end state?" | *(open-ended)* Simple interaction (1-2 steps), Multi-step workflow, Background process with status, Real-time/streaming |
| M5 | Design | "What should this look like? Any existing patterns to follow, design references, or specific UX expectations?" | *(open-ended)* Follow existing patterns (describe), Have references/mockups, No strong opinion — propose something, Specific requirements (describe) |
| M6 | States | "What does loading, empty, success, and error look like to the user?" | *(open-ended)* Standard patterns fine, Specific requirements (describe), Need streaming/progress states, Haven't considered — help me think through |
| M7 | Priority | "What's the 80/20? What must this absolutely nail vs. nice-to-have polish?" | *(open-ended)* Core behavior is clear (describe), Need help prioritizing, Everything feels P0, Performance/speed is the key |

#### Round 3: Edge Cases & Unhappy Paths (AskUserQuestion — 2 questions)

| Q# | Header | Question | Options |
|----|--------|----------|---------|
| M8 | Failure modes | "What happens on bad input, partial failure, timeout, or concurrent access? What are the 2-3 most likely failure modes?" | *(open-ended)* Known failure modes exist, Haven't considered yet — help me think through, Low-risk — simple CRUD, Complex — multiple failure paths |
| M9 | Recovery | "When something goes wrong, what's the user's recovery path? Can they retry, undo, or is data lost?" | *(open-ended)* Retry is sufficient, Need undo/rollback, Data loss is possible — need safeguards, Depends on failure type (describe) |

#### Ambiguity Probe (AskUserQuestion — after Round 3)

Review all collected context (Step 1 + M1-M9 answers). Use `AskUserQuestion` to surface any terms, behaviors, or scope edges where two engineers could reasonably interpret the spec differently. Propose your interpretation as options and ask the user to confirm or correct. Frame as: "I want to make sure we're aligned on these points before drafting."

**Lean into ambiguity.** Don't limit yourself to 2-3 items — surface every point where the AC could go two ways. Better to over-clarify now than produce vague requirements. Common ambiguity sources: state transitions, permission boundaries, error message content, default values, sort/filter behavior, empty states, concurrent access, "what counts as X."

#### Conditional Questions (AskUserQuestion — when relevant)

After the ambiguity probe, if any of these topics are relevant but unaddressed, batch the most relevant 2-4 into one `AskUserQuestion` call:
Timeline/urgency | Prior art (what's been tried) | North star metric | KPI approach (qual vs quant) | Delivery context (launch vs demo vs internal) | Dependencies on other teams/systems | Data sensitivity / compliance | Accessibility requirements | Cross-team coordination | Pricing/release constraints

**Delivery context calibration** (apply when delivery context is known):

| Context | P0 emphasis | P1 emphasis | Deprioritize |
|---------|------------|------------|-------------|
| Product launch | Data governance, error handling, edge cases | Performance, polish | — |
| Demo/sprint (<3 weeks) | Core happy path, perceived quality, progress feedback | Broad format support, visual polish | Governance, persistence, data retention |
| Internal tool | Core functionality, correctness | Error handling | Polish, onboarding |

#### Completion Criteria

Complete when: all M1-M9 answered or confirmed via `AskUserQuestion`, ambiguity probe resolved, and each answer is concrete enough that two engineers would make the same implementation decision.

**No deferred questions.** Every open question must be resolved via `AskUserQuestion` during this step and incorporated directly into the PRD. Never output an "Open Questions" section — that's a failure to do your job. If a question truly can't be answered yet, flag it as a `[Data gap: recommend X research]` inline where the answer would go, not in a separate section.
*(Mode C exception: the discovery-brief format deliberately includes an "## Open Questions" section — a pitch brief is a conversation starter, not a spec. The ban applies to Mode A/B PRDs only.)*

**Checkpoint:** Write `<working-name>-interview.md` with all M1-M9 answers, ambiguity resolutions, and conditional Q&A.

### Step 3: Research & Validate

Use web search to strengthen data-driven foundation:
- Competitor features, industry benchmarks, market data
- Evidence supporting or challenging user claims
- Prior art (blog posts, press releases, product announcements)

**Guardrails:** Only verified data. Mark web-sourced vs. user-provided. Flag gaps honestly. Search for counterarguments too.

**Checkpoint:** Write `<working-name>-research.md` with findings.

### Step 4: Draft the PRD

**⚠️ RE-ANCHORING CHECKPOINT — Context decay is real.**
By this point, 15-20+ messages have elapsed since skill load. You MUST re-read these instructions before proceeding. Do NOT draft from memory.

**Step 4a: Setup (MANDATORY)**
1. Create sentinel directory: `mkdir -p docs/.prd-writer`
2. Create sentinel: `touch docs/.prd-writer/.gate-prd-draft`
3. Read `templates/acme-prd-template.md` (Mode A) or `templates/prd-lite-template.md` (Mode B) — DO NOT SKIP THIS READ
4. Read `references/quality-patterns.md`

**Step 4b: Spawn drafting subagent (MANDATORY — prevents context decay)**

Do NOT write the PRD inline from the main conversation. Spawn a fresh subagent via the Task tool (`subagent_type: "general-purpose"`, `model: opus` — the PRD is the primary artifact; drafting is judgment-tier work) with:
- The scaffold from `templates/prd-scaffold.md` (copy it into the prompt verbatim)
- The interview checkpoint (`<working-name>-interview.md`)
- The context checkpoint (`<working-name>-context.md`)
- The research checkpoint (`<working-name>-research.md`) if it exists
- The quality-patterns reference
- Explicit instruction: "Fill every TODO marker. Do not invent new sections or skip existing ones. Requirement IDs use the **REQ-NNN:** format only (REQ-001, REQ-002; sub-areas REQ-001a)."

The subagent writes the PRD by filling the scaffold — this ensures structural compliance regardless of how long the preceding conversation was. The subagent does not load CLAUDE.md or this skill: every rule it must obey travels in the prompt above.

**Step 4c: Validate (MANDATORY, NON-SKIPPABLE, EVIDENCED)**

After the subagent writes the PRD, run:
```bash
~/.claude/skills/prd-writer/scripts/validate-prd.sh <output-file> --mode full
```
(Use `--mode lite` for Mode B.)

Three hard rules:
1. **This step runs on every draft, always.** "The PRD looks structurally correct" is not a reason to skip — the validator exists precisely because drafts that look correct have failed it. Skipping this step is a protocol violation equivalent to skipping TDD.
2. **The validator's output is evidence, and evidence travels.** Capture the command's full stdout/stderr and exit code. You will paste it verbatim into the Step 5 summary. A summary that claims "validation passed" without the pasted output is an unverified completion claim — do not make it.
3. If validation fails, fix the specific issues it reports and re-run until exit 0. Do NOT regenerate from scratch.

- *Positive example:* Step 5 summary contains a fenced block with `$ validate-prd.sh docs/briefcase-prd.md --mode full` followed by the validator's actual output lines and `exit 0`.
- *Negative example:* Step 5 summary says "✓ Passed structural validation" with no command output shown — that is a claim, not evidence; the step is incomplete.

If the script itself is missing or crashes (script failure, not validation failure), do not skip validation — manually check the PRD against the section list in `templates/acme-prd-template.md` and the REQ-format rules below, and paste your manual checklist results into the summary, stating that the validator was unavailable.

**Step 4d: Remove sentinel**
```bash
rm -f docs/.prd-writer/.gate-prd-draft
rmdir docs/.prd-writer 2>/dev/null || true
```

**Section-specific guidance:**

#### TL;DR
One sentence: gap + mechanism + projected impact. Not a description — a pitch.

#### Table of Contents
Always include. Auto-generated links to all H2/H3.

#### Problem Definition
Objective, context, strategic drivers, success measures. Include "why now." Back with evidence. **Do NOT include user pain points here** — those belong in JTBDs as evidence. **All language must be user/business-facing.** No architecture, protocols, libraries, or eng investigation notes. If the "why now" is technical debt or system fragility, frame it as user impact ("users lose data during long sessions") not eng cause ("SignalR lacks token refresh").

#### Opportunity Size
Show projection math. Reference precedents. Be honest about assumptions.

#### Jobs to Be Done & Requirements

**This is the core. Each JTBD is self-contained — problem, evidence, hypothesis, KPIs, requirements, AND business rules all in one place.**

**Anti-bloat principle:** Requirements *fall from* the JTBD — each exists because the job can't be done without it. The JTBD provides the "why"; requirements provide the "what." Don't restate the problem inside each requirement. One sentence of scope, then straight to behaviors.

**Per-JTBD structure:**
1. JTBD heading with job statement
2. Job statement in persona format
3. Evidence (user pain points with data — this is where "user voice" lives, not in Problem Definition)
4. Hypothesis: *If we [X], THEN [Y] because [Z].*
5. KPI table (qual primary for early-stage, quant for mature)
6. Requirements ordered P0 -> P1 -> P2
7. Cross-Cutting Rules subsection (only when complexity warrants dedicated REQ-IDs)

**Requirement ID format (the ONLY accepted scheme):** `**REQ-NNN:**` — e.g., REQ-001, REQ-010. Sub-areas use hierarchical suffixes: REQ-001a, REQ-001b. Individual acceptance criteria are referenced as `REQ-001.3` (req ID + item number). Do NOT invent per-feature prefixes (AC-1, BRF-2, AUTH-3 are all rejected) — `validate-prd.sh` and the write-gate hook fail any PRD without `**REQ-NNN:**` headers.

**Per-requirement-area structure:**
```
**REQ-001: Name** (P0)                          ← area-level default priority
[1-2 sentence scope. What it does, key constraint.]
1. [P0] [Acceptance criterion — maps to one test case]
2. [P0] [Another criterion]
3. [P1] [Polish/enhancement criterion — overrides area default]
```

**Requirement formatting rules (hard enforcement):**

1. **Per-requirement priority.** Every numbered requirement gets a `[P0]`, `[P1]`, or `[P2]` tag at the start. The area header sets the default priority; individual requirements SHOULD override it when appropriate. Don't blindly inherit — apply the priority judgment heuristic below.

2. **Two-statement limit.** Each numbered requirement is at most 2 logical statements (period- or semicolon-separated). If a requirement needs more, split it into a separate numbered requirement. This forces atomic, testable behaviors.

3. **Five-requirement cap per area.** If a requirement area would exceed 5 numbered requirements, decompose it into sub-areas using hierarchical IDs: `REQ-002a: Pill Layout`, `REQ-002b: Pill Styling`. Each sub-area inherits the parent's default priority and follows the same rules (≤5 reqs, 2-statement limit). This prevents monolithic requirement blocks that obscure priority and scope.

**Priority judgment heuristic (apply to every numbered item):**

The area header is a starting point, not a stamp. A P0 area can — and often should — contain P1 and P2 items. The litmus test: **if this item shipped broken or missing, would the feature be unusable or misleading?** If yes → P0. If the feature works correctly but looks rough or misses a polish detail → P1. If it's an optimization or enhancement with no user-visible degradation on skip → P2.

| P0 — must ship | P1 — should ship | P2 — defer |
|----------------|------------------|------------|
| Core happy-path behavior | Visual polish (specific colors, icons, animations) | Analytics events |
| Data integrity / correctness | Disambiguation for edge cases (e.g., duplicate names) | Performance optimization |
| Error states that prevent user confusion | Hover/preview interactions | Cross-mode parity (agent modes) |
| Security / access control | Keyboard accessibility refinements | Advanced tooltip behaviors |
| Graceful degradation (no broken UI) | Specific truncation limits | Mobile-specific interactions |

**Healthy ratio target:** Within a P0 area, expect roughly 60-70% of items to remain P0, 25-35% to be P1, and 0-10% to be P2. If every item in an area is P0, you're likely not applying enough judgment — re-examine visual polish, analytics, edge-case handling, and accessibility refinements as P1 candidates.

**Safety check:** After assigning priorities, verify that all P0 items together form a coherent, shippable feature. An engineer building only P0 items should produce something that works end-to-end without broken states or confusing UX. If skipping a P1 item would leave the P0 set in a broken state (e.g., a click handler with no visual affordance), promote it back to P0.

**P2 requirements:** `[P2]` tag + one-line description, no acceptance criteria.

**Business rules placement (mix approach):**
- **Simple constraints** (field validation, role checks, format rules): inline as acceptance criteria under the REQ they govern (e.g., "4. Only users with Editor role can invoke")
- **Complex cross-cutting rules** (permission models spanning multiple REQs, state machines, lifecycle transitions): dedicated REQ-IDs in a "Cross-Cutting Rules" subsection within the JTBD or at end of §2

**Acceptance criteria rules:**
- Observable system behavior, not user action
- Concrete values: field names, max lengths, valid states
- Each independently falsifiable (one test case per item)
- Each numbered item starts with `[P0]`, `[P1]`, or `[P2]` — inherits area default unless overridden
- Max 2 logical statements per numbered item (split if more)
- Max 5 numbered items per requirement area (decompose into sub-areas with hierarchical IDs if more)
- Order: happy path -> error/validation -> edge cases -> constraints/permissions
- **Minimum count:** Every P0 requirement area must have ≥2 acceptance criteria. If you can't identify at least 2, the requirement is too vague — split or rewrite it.

**Priority tiers within each JTBD's build scope:** P0 = must ship, P1 = should ship, P2 = defer.

#### UX Flows

Dedicated section immediately after JTBD & Requirements. Organized by JTBD — each flow references requirement IDs it satisfies. **JTBDs define the "what"; UX flows show the "how."** Don't re-describe requirements, reference by ID (`-> See REQ-002`).

**Per-JTBD UX subsection:**

**1. Interaction Flows** — Compact numbered flow per user journey. Each flow:
- References requirement IDs it satisfies (e.g., `→ REQ-001, REQ-002`)
- Numbered steps: user trigger → system response → final output
- Concrete example inputs
- Streaming/real-time states where applicable

```
### JTBD-1: [abbreviated]
#### Flow: [Feature] → REQ-001, REQ-002
1. User [trigger]
2. System [response]
3. Output: [format]
```

**2. Edge Flows (illustrative)** — Show business rules in action via representative scenarios. Purpose: make constraints concrete for stakeholders and designers. These are NOT exhaustive — eng planning will expand into the full edge-case matrix. Include 1-2 per JTBD when meaningful rules exist.

```
### Edge Flow: [Rule Name] → REQ-010, REQ-001.4
1. User [attempts action that triggers rule]
2. System [checks constraint]
3. System [enforces — error/block/redirect]
4. User [recovery path]
```

**Guidance note in template:** "Eng planning will enumerate the full edge-case matrix from these illustrative flows."

**3. ASCII Wireframes (for major interaction patterns)** — Include 3-5 per feature PRD. Use box-drawing characters (┌ ┐ └ ┘ ─ │ ├ ┤). Focus on complex multi-panel layouts, forms with many fields, state machines, and multi-step workflows. Place with the JTBD flow they illustrate.

**Cross-cutting UX (once, after all JTBD flows):**

**4. Information Architecture** — Where feature lives. Containment hierarchy. What doesn't change.

**5. Component Specs (new components only):**
For each new UI component, define:
- **States**: all visual states (default, loading, completed, error, empty)
- **Visual treatment**: background, borders, colors, layout (reference design system tokens)
- **Interaction behavior**: click, expand, filter, hover
- **Constraints**: max lines, truncation, scroll behavior

```
**ComponentName:**
- [State]: [visual treatment + content layout]
- [State]: [visual treatment + content layout]
- Click/expand: [behavior]
- Constraints: [limits]
```

**6. Use Cases Table** — Map scenarios to JTBDs, features, triggers, outputs.

#### Risks & Out of Scope
Risks with mitigations + out of scope. Be explicit.

#### Legacy Reference (optional)
Only when replacing existing system. Context only — does NOT drive requirements.

#### Engineering (§7)
Two subsections: (1) Effort Estimates — ranges, not points; backend vs. client split; staffing needs; blockers/dependencies. (2) Data Model (if applicable) — tables/columns, API endpoints, state machines, tracking requirements. Effort first, data model second.

### Step 5: Output and Present

**Step 5a: Save & Present**
1. Save PRD as `.md` to output directory
2. Archive checkpoint files: move to `docs/temp/archive/` (do NOT delete — they serve as audit trail for debugging format deviation)
3. Brief summary: what it proposes, key data anchors, sections needing review, next steps — **including the verbatim validator output from Step 4c** (fenced block: command + output + exit code)

**Step 5b: Confluence Publish/Sync (OPTIONAL — offer, never assume)**

Applies when: the user asks to publish, the source material came from a Confluence page, or the project's PRDs live in Confluence.

1. Offer via ONE `AskUserQuestion`: **Publish to Confluence** / **Keep local only**. Never publish without this confirmation.
2. To publish a NEW page: invoke the `atlassian-connect` skill (Skill tool) for auth + page creation.
3. To update an EXISTING page: invoke the `atlassian-update` skill — it preserves inline comments; never overwrite an existing page body via raw REST.
4. **Pull-PM-edits-back flow (before ANY later iteration on a published PRD):** fetch the current Confluence page body first, diff it against the local `.md`. If a PM edited on Confluence, merge those edits into the local file BEFORE applying new changes, and say so in the iteration summary. The published page is the shared truth once stakeholders touch it.
- *Positive example:* user says "iterate on §3" of a published PRD → fetch page, find a PM added a KPI row on Confluence, merge that row locally, then edit §3, then re-publish via atlassian-update.
- *Negative example:* editing the local file and re-publishing without fetching first — silently clobbering the PM's Confluence edits. This is data loss; never do it.

**Step 5c: Suite-Consistency Pass (CONDITIONAL — master + children PRD sets)**

Applies when: this PRD is part of a set (a master PRD with feature-PRD children, or siblings in one directory), the user says "suite"/"all the PRDs", or the edit touched shared behavior referenced by sibling PRDs. Skip for a standalone single PRD.

Run three checks and output a short results table:
1. **REQ-ID gap scan:** list every REQ-NNN per file (`grep -o 'REQ-[0-9a-z]*' <file> | sort -u`). Flag numbering gaps within a file and duplicate IDs across files that are supposed to share an ID space.
2. **Cross-ref / TOC check:** every `→ See REQ-...` and every link to a sibling PRD must resolve to an existing ID/file; every TOC entry must match an actual heading. Flag dangling references.
3. **Propagation checklist:** for each behavior changed in THIS PRD, list sibling files that reference it (grep the suite for the REQ-ID and key nouns) and confirm each was either updated or consciously left unchanged — one row per sibling, no blanket "all consistent" claims.
- *Positive example:* master PRD renames REQ-012 → REQ-012a/b; Step 5c greps children, finds `feature-3.md` still cites REQ-012, fixes it, shows both files in the table.
- *Negative example:* declaring "suite is consistent" after editing only the master file, without grepping the children — that's an unverified claim, the exact failure this step exists to prevent.

### Step 6: Iterate

Update in place. Each iteration reduces flagged items. **Max 3 iterations:** if the user is still unsatisfied after 3, stop regenerating and use `AskUserQuestion` to isolate what specifically is failing (structure, data, scope, tone) — the problem is upstream of the draft.

**Fidelity Gate (MANDATORY after any compression iteration):**

Applies when: any iteration's goal is to shorten, condense, tighten, or "make more compact" — whether user-requested or self-initiated. Does NOT apply to pure additions or corrections.

Procedure: before presenting the compressed version, keep the pre-compression file (copy to `docs/temp/<working-name>-precompress.md`), then invoke the `diff-audit` skill (Skill tool) with the pre- and post-compression files. Every semantic loss it reports (missing behavior, modified behavior, degraded specificity) must be either restored into the compressed version or explicitly approved by the user via `AskUserQuestion` — one loss list, user confirms. Then re-run Step 4c validation on the compressed file.
- *Positive example:* compression drops "retry up to 3 times with backoff" to "retries on failure"; diff-audit flags degraded specificity; you restore the concrete value before presenting.
- *Negative example:* presenting a 40%-shorter PRD with "no content lost, only formatting tightened" and no diff-audit run — 6 sessions of verbosity↔specificity oscillation came from exactly this claim.

### Step 7: Adversarial Review (Recommended)

Use `AskUserQuestion` to offer `/prd-review` after user is satisfied (ONE question, one decision):
- **Run adversarial review** — 5 specialized personas probe for ambiguities and hidden complexity
- **Skip for now** — PRD is ready as-is

---

## Bulk / Orchestrated Rewrite Contract

**This is the dominant real-world usage of this skill.** When an orchestrator (or the user directly) rewrites MULTIPLE existing PRDs to this format via parallel subagents, the interactive Workflow (Steps 0-7) does NOT run per file. This contract governs instead. The skill is the style authority; the contract is how its authority actually reaches subagents.

**Why a contract is needed:** subagents do not load this skill, CLAUDE.md, or any rule file. A prompt that says "follow /prd-writer conventions" transmits NOTHING — the subagent cannot read the skill. Every rule must travel verbatim inside each subagent prompt.

### Contract terms (all five are mandatory)

1. **Embed the rules verbatim in EVERY subagent prompt.** Each rewrite subagent's prompt MUST contain, copied verbatim (not summarized, not referenced by path):
   - the full scaffold from `templates/prd-scaffold.md`
   - the **End-User POV Rule** block (from Core Principles above, including the Bad/Good example)
   - the **Requirement ID format**, **Requirement formatting rules (hard enforcement)**, and **Acceptance criteria rules** blocks (from Step 4 guidance above)
   - *Positive example:* prompt contains "### End-User POV Rule ... §1-6 must be written entirely in user-facing language ..." pasted in full.
   - *Negative example:* prompt says "apply the prd-writer End-User POV rule and AC formatting (see ~/.claude/skills/prd-writer/SKILL.md)" — the subagent never reads that path; jargon leaks straight through. This exact failure produced "_documentAttachmentsLock in acceptance criteria".

2. **Scope = EVERY requirement in the file, never a named hit-list.** The prompt must instruct: "Apply these rules to EVERY requirement area and every acceptance criterion in the document, top to bottom. Do not stop at the examples named in this prompt." If specific problem areas are known, name them as *examples of the pattern*, never as the work list.
   - *Positive example:* "Rewrite every REQ area to numbered `[P0]`-tagged ACs; REQ-007 and REQ-012 illustrate the current violations."
   - *Negative example:* "Fix REQ-007 and REQ-012" — agents did exactly that and nothing else ("agents only decomposed the requirements I explicitly named").

3. **Per-file validation gate before acceptance.** The orchestrator runs `~/.claude/skills/prd-writer/scripts/validate-prd.sh <file> --mode full` (or `--mode lite` for PRD-Lites) on EVERY rewritten file. A file is accepted only on exit 0. On failure: send the file back with the verbatim validator output (max 2 fix cycles, then escalate to the user). The orchestrator's final report pastes per-file validator output — subagent self-reports ("rewrote and verified") are not acceptance evidence.

4. **Fidelity gate per file.** A rewrite is a compression risk. For each file, run the `diff-audit` skill (original vs rewritten) or have a dedicated verifier subagent do so; semantic losses must be restored or surfaced to the user. Do not let 13 parallel rewrites each silently drop edge cases.

5. **Suite-consistency pass once at the end.** After all files are accepted, the orchestrator runs Step 5c (REQ-ID gap scan, cross-ref/TOC check, propagation checklist) across the whole set — parallel rewrites are the primary source of cross-PRD ID collisions and stale cross-references.

### Orchestrator checklist (copy into the orchestration plan)

```
[ ] Every subagent prompt embeds: scaffold + End-User POV rule + REQ-ID format
    + formatting rules + AC rules — VERBATIM
[ ] Every prompt says "EVERY requirement, top to bottom" (no hit-lists)
[ ] validate-prd.sh run per file; exit 0 required; output pasted in report
[ ] diff-audit per file (original vs rewrite)
[ ] Step 5c suite pass after all files accepted
```

---

## Critique Requests

Reviewing, critiquing, or improving an existing PRD is `/prd-review`'s job (5-persona adversarial pipeline) — route there. Only if the user explicitly wants a light inline critique WITHOUT the full pipeline: score the PRD against `references/quality-patterns.md`, organize feedback as structural / rigor / clarity / honesty gaps, and offer rewrites for the weakest sections.

---

## Template Override

Use user's template structure. Apply quality patterns regardless. Suggest missing sections but don't force.

---

## Edge Cases

- **No data:** Flag honestly as "[Data gap: recommend X research]"
- **Very early stage:** Use Mode B (PRD-Lite) per Step 0.5. Same section structure as full PRD, same behavior requirements for P0/P1, reduced depth for §3 UX Flows, TBD markers for §4-6. Mode B hard minimums apply: ≥1 UX flow per JTBD, numbered ACs, no unsolicited Data Model.
- **User pushes back on rigor:** Help identify obtainable metrics. Frame gaps as action items.
- **Multiple audiences:** Note where detail levels need adjustment.
