# Quality Patterns for High-Impact PRDs (Compact)

Patterns from exemplary PRDs. Includes density rules that cut ~30% without losing rigor.

## Table of Contents
1. [Executive Summary](#executive-summary)
2. [Problem Definition](#problem-definition)
3. [Data-Driven Rigor](#data-driven-rigor)
4. [Differentiation & Prior Art](#differentiation)
5. [User Experience Depth](#user-experience)
6. [Engineering Estimation](#engineering)
7. [Risk & Skepticism](#risk-and-skepticism)
8. [Opportunity Sizing](#opportunity-sizing)
9. [End-User POV (§1-6)](#end-user-pov)
10. [Writing Density](#writing-density)

---

## 1. Executive Summary <a name="executive-summary"></a>

~100 words. Four jobs: name the gap, cite precedent, quantify the prize, state the mechanism.

**Anti-pattern:** "We will improve the experience" with no numbers.

**Pattern:**
> "[Platform] is becoming too [problem]. [Competitor] pulls [segment] away.
> [Past experiment] shows [mechanism] works — [metric]. Past [attempt] suffered [barriers].
> We solve via [approach]. [Tactic A] + [Tactic B] unlocks [projected impact]."

---

## 2. Problem Definition <a name="problem-definition"></a>

### User Problems as Evidence Inside JTBDs
**Rule:** User pain points belong in the JTBD "Evidence" section, not in a standalone Problem Definition block. This eliminates the #1 source of cross-section redundancy.

Each pain point: first-person voice + evidence.
```
**Evidence:**
- "I [pain point]" — [data/research link]
- "I [pain point]" — [quote/study]
```

### Hypotheses Format
Testable hypothesis + KPI table per JTBD:

> *If we [mechanism], THEN [outcome] because [reasoning].*

| | KPI |
|---|---|
| **Primary** | [qual for early-stage: ">=3/5 beta users cite X"] |
| **Secondary** | [quant: ">50% items receive status update before due"] |

### Requirement IDs
`REQ-NNN` only: `REQ-001`, `REQ-010`; sub-areas `REQ-001a`, `REQ-001b`; individual criteria referenced as `REQ-001.3`. Enables reference in code, tests, commits. This is the only scheme `validate-prd.sh` and the write gate accept — do not invent per-feature prefixes (`AC-1`, `BRF-2`, `AUTH-3` are rejected).

### Acceptance Criteria
Each P0/P1 requirement area gets numbered acceptance criteria mapping to test cases:
```
**REQ-001: Name** (P0)                         ← area-level default priority
[1-2 sentence scope.]
1. [P0] [Criterion with concrete values — max 2 logical statements]
2. [P0] [Happy path]
3. [P1] [Polish item — overrides area default]
```

**Rules:** Observable system behavior (not user action). Concrete values. Independently falsifiable. Happy path first, then errors, then edge cases.

**Formatting rules (hard enforcement):**
- **Per-item priority:** Every numbered item starts with `[P0]`, `[P1]`, or `[P2]`. Area header sets the default; items SHOULD override when appropriate — don't blindly inherit.
- **Two-statement limit:** Max 2 logical statements per item (period- or semicolon-separated). If it needs more, split into another numbered item.
- **Five-item cap:** Max 5 numbered items per requirement area. If >5, decompose into sub-areas using hierarchical IDs (`REQ-001a: Layout`, `REQ-001b: Styling`). Each sub-area inherits parent priority and follows the same ≤5 / 2-statement rules.

**Priority judgment (apply per item, not per area):**
The litmus test: if this item shipped broken or missing, would the feature be unusable or misleading? If yes → P0. Feature works but looks rough → P1. No user-visible degradation → P2.
- P0: core happy path, data correctness, error states that prevent confusion, graceful degradation
- P1: visual polish (colors, icons, animations), hover/preview interactions, disambiguation edge cases, accessibility refinements, specific truncation limits
- P2: analytics events, performance optimization, cross-mode parity, advanced tooltip behaviors

**Ratio target:** ~60-70% P0, 25-35% P1, 0-10% P2 within a P0 area. If 100% of items are P0, re-examine.
**Safety check:** After assigning, verify P0 items alone form a coherent shippable feature — no broken states from skipping P1 items.

**Minimum count:** Every P0 requirement area must have ≥2 acceptance criteria. If you can't identify at least 2, the requirement is too vague — split or rewrite it.

---

## 3. Data-Driven Rigor <a name="data-driven-rigor"></a>

Every claim backed by: internal data, analogous product data, user research, or market data.

**Quantification rules:**
- Never "significant improvement" — say "+1.65% OESPD"
- Never "good engagement" — say "9.75% CTR"
- Show projection math: `[base] x [rate] = [outcome]`
- Include confidence intervals when available

---

## 4. Differentiation & Prior Art <a name="differentiation"></a>

**Prior Attempts Table:** Rows = attempts. Columns = "How different?" + "Why worth trying."

**"Reasons to Be Skeptical":** What went wrong before. Why each failure doesn't apply (or does). Honest remaining risks.

---

## 5. User Experience Depth <a name="user-experience"></a>

**Rule:** UX detail is distributed, not centralized.

### Interaction Flows — Inline with JTBDs
Flows live inside the JTBD they serve, immediately after relevant requirements. Compact numbered steps:
```
1. User [trigger with concrete example]
2. System [response] — [visual note]
3. [Streaming/processing]
4. Output: [format], sections: [list]
```

**Rules:** Concrete inputs. Include streaming states. Describe system behavior. End with output format.

### ASCII Wireframes
Include 3-5 per feature PRD for major interaction patterns. Use box-drawing characters (┌ ┐ └ ┘ ─ │ ├ ┤). Wireframes should show layout, key fields, and interaction affordances. Focus on complex multi-panel layouts, forms with many fields, state machines, and multi-step workflows. Not every JTBD needs a wireframe. Place inline with the JTBD they illustrate.

### Component Specs
For each new UI component, define states and behavior — enough for a developer to implement without asking questions.

**Pattern:**
```
**ComponentName:**
- [Default state]: [visual treatment + content layout]
- [Loading/Live state]: [expanded by default, animation, spinner location]
- [Completed state]: [collapsed summary + expand affordance]
- [Error state]: [visual treatment, error message placement]
- [Empty state]: [placeholder text, call-to-action]
- Click/expand: [what happens on interaction]
- Constraints: [max lines, truncation, scroll behavior]
```

Reference design system primitives when known (e.g., "shadcn/ui Collapsible, Badge, Card, Tabs").
Reference design tokens for visual treatment (e.g., "`bg-muted/50`, rounded corners, subtle border").

### Information Architecture
Where the feature lives. Containment hierarchy. Navigation changes. What stays the same.

### Use Case Table
| Use Case | Feature | Trigger | Expected Output |
|---|---|---|---|

---

## 6. Engineering Estimation <a name="engineering"></a>

P0 (MVP) and P1+ tables. Component breakdown. Backend vs. client. Ranges, not points. Staffing + barriers.

---

## 7. Risk & Skepticism <a name="risk-and-skepticism"></a>

**Risks:** Operational, technical, strategic — each with mitigation. Table format.
**Out of Scope:** What you're NOT doing. One line per item with rationale.

---

## 8. Opportunity Sizing <a name="opportunity-sizing"></a>

**Evidence Pyramid:** Direct signals -> Adjacent signals -> Cross-platform -> Research.
**Projection math:** Show derivation. `[base] from [channel] at [rate] (per [precedent]) = [outcome]`.

---

## 9. End-User POV (§1-6) <a name="end-user-pov"></a>

**Rule:** Sections 1-6 must be written entirely in user-facing language. No exceptions. Implementation detail — libraries, protocols, architecture patterns, data schemas, service internals, algorithms, field mappings — belongs ONLY in §7 Engineering or the TAR. If content cannot be translated to user-facing language or has no direct user/business impact, it does not belong in the PRD.

**The litmus test:** Can a product stakeholder read this sentence and understand why it matters to users? If no — translate to user impact or remove entirely.

### Anti-Pattern: Implementation Detail in §1-6

**Bad (eng detail in §1-6):**
> "The BFF normalizes the source field on each retrieved_docs entry to a single canonical type: 'chunks, keyword' → 'documents'"

**Good (user-facing in §1-6):**
> "Citation pills are color-coded by source type: gray for documents, purple for web results, orange for news articles"

**Where the eng detail goes (§7 Engineering or the TAR):**
> "The BFF normalizes the source field on each retrieved_docs entry to a single canonical type before passing to the frontend. Mapping: 'chunks' and 'keyword' → 'documents', 'web_search' → 'web', 'news_search' → 'news'."

### Pattern: Translate Technical Constraints to User Impact

| Technical reality | User-facing translation (for §1-6) |
|---|---|
| "SignalR lacks token refresh" | "Sessions expire after 4 hours; users lose unsaved work" |
| "Client-side computation without server validation" | "Vote results may display incorrectly; no server-side guarantee of accuracy" |
| "DOM state not serialized on tab close" | "Closing the browser tab loses any in-progress changes" |
| "Rate limiter at 100 req/min" | "Rapid actions (bulk approvals) may be throttled; user sees 'please wait' after ~100 items" |
| "Webhook delivery is at-most-once" | "Notifications may occasionally not arrive; user should check dashboard as backup" |
| "System prompt includes numbered source list from retrieved_docs" | "AI responses include numbered markers linking each claim to its source document" |
| "BFF filters company_context from retrieved_docs array" | "Internal company context is not shown as a citable source" |
| "Streaming renderer buffers partial [n] markers until complete" | "Citation markers appear cleanly during streaming — no broken or flickering text" |
| "Custom remark/rehype plugin detects [n] in AST text nodes" | "Citation markers inside code blocks, links, or images are not treated as citations" |

### §2 Acceptance Criteria: User-Observable Only

Acceptance criteria describe what the user sees, not how the system works internally.

**OK:** "Session expires after 4 hours; user sees 'Please refresh to continue voting' banner with one-click refresh"
**OK:** "Citation pills are color-coded: gray for documents, purple for web, orange for news"
**OK:** "Hovering over a citation pill for 200ms shows a preview with source name and excerpt"
**NOT OK:** "SignalR 2.4.1 WebSocket connection drops after token expiry; requires reconnection handler"
**NOT OK:** "The BFF normalizes source field values: 'chunks, keyword' → 'documents'"
**NOT OK:** "The renderer maintains a look-ahead buffer that flushes after 8 characters"

If the only way to state a criterion precisely is to name an internal mechanism, the criterion describes an engineering constraint — it belongs in §7 or the TAR.

---

## 10. Writing Density <a name="writing-density"></a>

These rules target the specific verbosity patterns found in PRD output.

### Rule: Describe Once, Reference by ID
Every behavior, flow, or rule has ONE canonical location. All other mentions reference by ID.

**Bad:** Describing the same copy-review workflow in REQ-002b, then again in "Interaction Flow: Enhanced Copy," then again in Business Rules.
**Good:** Full spec in REQ-002b. Interaction flow says `-> See REQ-002b for full behavior.` Business rule says `(per REQ-002b)`.

### Rule: Tables Speak for Themselves
Never follow a table with prose restating its contents.

**Bad:**
```
| Metric | Value |
| Users | 10K |
| CTR | 9.75% |

As shown above, we have 10K users and a CTR of 9.75%...
```
**Good:** Just the table. If it needs explanation, restructure the table.

### Rule: Options Analysis in Tables with Bullet Summary
Always present options in a table. Summarize the recommendation with bullets below — no advocacy prose.

**Bad:** "LLMs are the future of intelligent software; shipping rules-only means throwaway infrastructure..."
**Good:**
```
| Dimension | Option A | Option B (Recommended) |
|-----------|----------|----------------------|
| User value | ... | ... |
| Eng cost | ... | ... |

- **Recommendation:** Option B — only approach enabling draft generation
- Hallucination risk manageable via structured prompts + human review
```

### Rule: Compact Conditional Notation
Use inline separators for graduated/conditional logic.

**Bad (4 lines):**
```
- First 3 agendas: full wizard with onboarding tooltips
- Agendas 4-10: streamlined quick start, no tooltips
- After 10: wizard offered via button only, not auto-triggered
- Idle nudge disabled after 3 consecutive dismissals
```
**Good (1-2 lines):**
```
Agendas 1-3: full wizard + tooltips | 4-10: quick start | >10: button-only.
Idle nudge disabled after 3 dismissals. User override in settings.
```

### Rule: Scope Paragraphs Are Tight
Requirement scope paragraphs explain what + how in 2-3 sentences max. Implementation detail of any kind — service internals, data pipelines, algorithms, library-specific patterns, field mappings — belongs in §7 Engineering or the TAR. §1-6 scope paragraphs describe WHAT the user gets and WHY it matters.

### Rule: Out of Scope Is One Line Each
**Bad:** "Cross-org intelligence — V1 uses org-specific history only. Anonymized cross-org patterns (leveraging Acme's dataset) is a future exploration pending legal/privacy review."
**Good:** "Cross-org intelligence — V1 uses org-specific history only. Cross-org history deferred pending legal/privacy review."

### Rule: Density Has Boundaries — Protected vs. Safe Targets

Density means fewer words for the same information, not fewer details. The heuristic: if removing text would cause an engineer to ASK A QUESTION the text answered, the cut is destructive. If they'd make the same decision independently, the cut is safe.

**NEVER cut (protected categories):**
1. **Negative constraints** — "must not", "never", "is blocked until", "does not"
2. **Failure/error behaviors** — "on failure...", "if invalid...", "rejects with..."
3. **API contracts (§7 only)** — request/response shapes, event payloads, status codes, error formats. In §1-6, translate to user-observable effects.
4. **Cross-feature conventions** — lock ID formats, FK naming, shared enum values
5. **Data model fields (§7 only)** — referenced by any in-scope requirement. In §1-6, reference the user-visible outcome, not the field name.
6. **Performance targets** for specific operations (query budgets, latency thresholds)
7. **Open architectural questions** flagged for resolution
8. **Enum value lists** — especially when values are non-sequential (legacy artifact)
9. **State machine transitions** — all states and all transitions, not just the happy path
10. **Security/validation constraints** — server-side enforcement, input sanitization, access filtering rules

**MAY cut (safe targets):**
1. Illustrative examples when the rule is unambiguous without them
2. UI implementation details (DOM structure, CSS classes) that don't affect behavior
3. Redundant restatements of the same rule across multiple sections (use "Describe Once" above)
4. Motivation/context prose that explains WHY but doesn't change WHAT
5. Legacy system internals that are replaced entirely (jQuery configs, Lotus Notes formats)
6. Aspirational / "v2 Opportunities" sections when scope-reducing to MVP

**NEVER use a numeric compression target.** Compression is a RESULT of cutting safe targets, not a TARGET to optimize toward. If given a numeric goal (e.g., "compress by 23%"), ignore it and cut only within the safe zone.
