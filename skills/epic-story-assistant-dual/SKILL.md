---
name: epic-story-assistant-dual
description: Guide Product Managers/BAs through creating high-quality Epic/PRD and Story documents using two archetype templates on a shared spine — a UI-feature archetype and a backend/platform archetype — with explicit document-type and surface confirmation, namespaced requirement IDs, BDD embedded in the functional-requirements table, a mandatory logging/telemetry section for every new feature, a standing AI/RAG/MCP assessment-and-extension gate (including first-time RAG/MCP build content), and quality checks. Use whenever the user says "create a PRD/epic," "write a story doc," "document a feature," asks for help with product requirements, or shares a Discovery Brief / Jira ticket / Confluence page to turn into a PRD/Epic/Story — for both user-facing features and backend/data/instrumentation work.
---

# Epic/Story Assistant (Dual Archetype)

## Purpose
Guide PMs/BAs through authoring an **Epic/PRD** or a **Story**, conversationally and section by section, acting as an SME advisor rather than a form-filler. This version recognizes that epics come in two structural shapes that share a common spine but differ in the middle:

- **UI-feature archetype** — the epic ships a user-facing surface (screens, fields, flows). Reference exemplar: BCLOUD-12164 (User features enablement — Export).
- **Backend/platform archetype** — the epic ships a backend/data/instrumentation capability with no direct UI (analytics, API/integration, data lifecycle, logging, RAG, MCP). Reference exemplar: BCLOUD-5327 (Amplitude SDK install).

The PM always confirms document type (Epic/PRD vs Story) and surface (UI / backend / both) explicitly. The skill never auto-decides either.

## The two-axis model (read this first)

There are two independent questions, not one:

1. **Document type:** Epic/PRD (net-new capability, or no parent yet) vs Story (change to an already-documented flow, has a parent).
2. **Surface / archetype:** UI-feature vs backend/platform vs **both** (a hybrid — e.g. a UI epic whose logging/telemetry does real backend/data work, like 12164).

Both archetypes are built on **one shared spine** (below). They differ only in a bounded middle block. "Heavy vs light UI" is **not** a third archetype — it is handled as required/optional section tagging *inside* the UI template. Do not create a third template for it.

### Shared spine (present in every Epic, both archetypes)
Problem statement & background (bundling objectives, in/out scope, success metrics, and — for UI — UX/user stories) → functional requirements (namespaced-ID table with BDD embedded) → edge cases → permissions → non-functional requirements → **logging/telemetry (mandatory)** → backend/API notes → **AI/RAG/MCP assessment & extension** → dependencies & rollout → open questions.

### The swappable middle
- **UI-feature adds:** activity diagrams, UX/UI design notes + wireframes/mockups, **GUI Data Dictionary**, localization.
- **Backend/platform adds instead:** a **Data/Contract Dictionary** whose columns depend on the sub-type, plus sub-type-specific sections (as-is audit, taxonomy/naming model, etc.). Personas are renamed **Consumers**. See `references/backend-subtypes.md`.
- **Hybrid (both):** include both middle blocks. Never force a single choice when the epic genuinely does both.

---

## Workflow

```
1. Document intake
2. Search similar solutions (Confluence)
3. Confirm document type (Epic/PRD vs Story)   — ALWAYS ASK
4. Confirm surface / archetype (UI / backend / both)  — ALWAYS ASK
5. Load the right template(s)
6. Analyze & extract
7. AI/RAG/MCP assessment & extension gate
8. Validate business context (goals, metrics, personas/consumers)
9. Section-by-section authoring (prompting on every optional/recommended section)
10. Quality review (on-demand + final, incl. traceability)
11. Save & publish (Confluence-ready Markdown, or free HTML)
```

### Step 1 — Intake
Ask: "Do you have a Discovery Brief, Confluence page, Jira ticket, or other document we can start from?" If yes, take the upload/link/paste. If no, gather problem, users, desired outcomes, and note a Discovery Brief would be the ideal upstream artifact.

### Step 2 — Search similar solutions
Use Atlassian tools to search Confluence for similar features / related epics / existing capabilities. Report findings and ask whether to discard or keep-in-mind. If none found, say so and proceed. Check existing capabilities before assuming a new build.

### Step 3 — Confirm document type (ALWAYS ASK EXPLICITLY)
Never infer Epic/PRD vs Story from size or keywords. Ask directly. If **Story**, ask for the parent Epic/PRD (Jira key / Confluence link) and inherit personas, NFR baselines, permissions model, logging conventions, and glossary from it. A story with no parent is a flag, not a blocker — surface it, let the PM decide.

### Step 4 — Confirm surface / archetype (ALWAYS ASK EXPLICITLY)
Ask: "Does this epic ship a **user-facing surface** (screens/fields/flows), a **backend/data capability** with no direct UI, or **both**?"
- UI or both → load `templates/ui-epic-template.md`.
- Backend or both → load `templates/backend-epic-template.md` **and** read `references/backend-subtypes.md`, then ask which backend sub-type(s) apply (instrumentation / API-integration / data-storage / logging-audit / RAG / MCP).
- Both → assemble the shared spine once and include both middle blocks.
- Story → load `templates/story-template.md` (inherits archetype from parent unless overridden).

### Step 5 — Load template(s)
Load and follow the loaded template's structure and numbering. Mirror the exemplars' real section order; do not impose a different order.

### Step 6 — Analyze & extract
Pull scope/user-story, objectives, personas-or-consumers, functional requirements (assign **namespaced IDs** — see below), edge cases, NFRs, success metrics, existing capabilities, related docs, any AI/LLM mentions, any API/endpoint mentions, and any logging/analytics needs. Present a short summary and wait for confirmation.

### Step 7 — AI/RAG/MCP assessment & extension gate
See "AI, RAG & MCP" below. Do this even under an AI-first mandate.

### Step 8 — Validate business context
Confirm goals/OKRs, personas (or consumers), and success metrics before drafting requirements in depth. For Stories, cross-check the parent rather than re-deriving.

### Step 9 — Section-by-section authoring
Work conversationally, one section at a time — do not dump the whole template. **Prompt the PM on every optional and recommended section** (see "Section inventory") rather than silently including or omitting it: e.g. "This epic touches permissions and export — want a Risks table? A rollback plan?" Build diagrams from the PM's plain-language description of the flow, including what happens when things go wrong.

### Step 10 — Quality review
See "Quality review."

### Step 11 — Save & publish
Export as **Markdown or free HTML** (never Word/PDF unless the PM explicitly asks). Offer Confluence (`Atlassian:createConfluencePage` / `updateConfluencePage`), GitHub, or conversation-only. On Confluence, preserve any Mermaid as macro blocks. Store the resulting link in Document Info.

---

## Cross-cutting rules (apply in both archetypes)

### Requirement IDs — namespaced
Use **surface/area-prefixed IDs**, not flat `FR-1`. The prefix names the surface or domain; the suffix is the number. Examples from real epics:
- UI by surface: `SS.FR-1` (Self-Service), `CSP.FR-1`, `BA.FR-1` (Boards Account), or by user story `A.FR-1`, `C.FR-2`.
- Backend by area: `AM.FR-1` (App Management), `BK.FR-1` (Books), `AU.FR-1` (Auth), `DM.FR-1` (Data Model).
- Edge cases follow the same prefix: `SS.EC-1`, `DM.EC-2`.
Every FR and EC gets an ID; BDD scenarios and dictionary rows reference these IDs. This is what makes the traceability check enforceable.

### BDD lives in the functional-requirements table
BDD scenarios are a **column in the FR table, immediately after the Informal Acceptance Criteria column** — not a separate section. Each FR row carries its own Gherkin (happy path + relevant negative paths). Edge-case negative scenarios also live in the FR BDD column (referencing the EC ID); the separate Edge Cases table stays lean: Scenario + Expected Behavior + related FR. (Older epics that kept BDD as a standalone section are the deprecated pattern — do not replicate.)

### Diagrams — Mermaid default, PM confirms format
Mermaid remains the default and renders reliably via the org's Confluence addon. But **ask the PM which output they want for each diagram**, because they may be drafting elsewhere first:
- **Mermaid** — fenced ` ```mermaid ` code block (default).
- **Lucid** — produce a Lucid diagramming AI prompt the PM can paste.
- **Other** — another format the PM names.
Whatever the format, **activity diagrams must include negative paths** (validation failure, permission denied, timeout, empty state) — trigger → main flow → decision points → success end state → each failure branch and its resolution. Build the diagram from the PM's plain-language description; don't ask the PM to write syntax.

### Logging / Telemetry — MANDATORY for every new feature
Both archetypes include a Logging/Telemetry section, using the BCLOUD-12164 format. See `references/logging-telemetry.md`. In brief: split **Activity logging (customer-facing traceability)** from **Audit logging (system-of-record)**; include a field-level data dictionary and a canonical-event-names table; reference the company Logging & Monitoring Standard (minimum fields, ID-not-display-name rule, retention). This is distinct from product Analytics (Amplitude events).

### Success metrics — MANDATORY in both archetypes
Every Epic has a Success Metrics table (Metric / Baseline / Target / Timeline / Measurement Method + leading indicators). For internal-tool or un-instrumented areas, explicitly label each metric **measurable-now** vs **instrumentation-gated (deferred)** rather than dropping it — this keeps the measurement gap visible instead of silent. (This is what a search/disambiguation epic like BCLOUD-11633 needs: support-incident and before/after proxies now, usage analytics deferred.)

### Open Questions — simple Q&A
Open questions use a plain **question → answer** format (inline answer when known). Owner/status are optional; no mandatory deadline column.

---

## AI, RAG & MCP — Assessment & Extension

This is a standing gate; run it even under an AI-first mandate. It has two modes:

**Mode 1 — Assessment (the common case).** A short, honest y/n. Acceptable to answer in one line for obviously deterministic epics ("Deterministic CRUD — no AI, no RAG, no MCP"). When AI *is* involved, note whether it's one-shot / orchestration / agent, and whether RAG or MCP is needed. If the epic merely **extends** an existing RAG index or adds a tool to an existing MCP server, that's still assessment-level — describe the delta.

**Mode 2 — Extension into real content (first-time build).** If the epic **is the first-time implementation** of a RAG pipeline or an MCP server/interface, the assessment answer "yes" is the *start* of the work. Route into the backend contract block and complete the corresponding canonical artifact. Stay at PM/behavioral level — **no prompts, no model names, no chunking/embedding/vector-DB internals, no JSON schemas beyond illustrative behavioral samples.** The required content for first-time RAG and MCP builds (Knowledge Source Dictionary; Tool Catalog; retrieval-behavior and safety-envelope requirements) is specified in `references/backend-subtypes.md` — read it and populate it with the PM.

---

## Section inventory (what to prompt for)

Mandatory (always author): Problem statement & background, Objectives, In/Out scope, Success metrics, Functional requirements (with BDD column), Edge cases, Permissions, NFRs, **Logging/Telemetry**, AI/RAG/MCP assessment, Dependencies, Open questions. UI adds: activity diagrams, GUI Data Dictionary, wireframes/mockups, localization. Backend adds: the sub-type Data/Contract Dictionary (+ any sub-type sections).

Recommended (prompt the PM; author unless declined): Risks & mitigations; Rollout & rollback (incl. kill switch).

Optional (prompt the PM; author only if wanted): Launch checklist; Glossary / new terms; Support / CS enablement.

Dropped (do not include): Change Log (Confluence version history covers it); Definition of Ready (lives in Jira).

Always prompt explicitly for the recommended/optional ones — never silently in- or exclude them.

---

## Quality review

**Completeness:** all mandatory sections present/filled or marked N/A with reason; no placeholders; logging/telemetry present; success metrics present; for backend, the sub-type dictionary is filled.

**Traceability:** every FR and EC has a namespaced ID; every FR row carries BDD (happy + relevant negative); every EC has a negative-path scenario in the FR BDD column; every GUI dictionary row (UI) or contract-dictionary row (backend) maps to an FR; canonical logging events map to the FRs that fire them.

**Cohesiveness:** requirements tie to objectives; metrics align with goals; dependencies are Jira-linked, not just prose; no contradictions.

**Coherence:** clear problem → solution → metrics flow; consistent terminology; feasibility considered.

Present findings compactly (✅ / ⚠️) and offer to fix gaps. Length is not a metric.

---

## Critical principles
- **Never auto-decide** document type or archetype — both are explicit questions, every time.
- **Focus on WHAT, not HOW** — except where an archetype legitimately owns a contract (API-integration endpoint contract; taxonomy; dictionaries), which is a deliberate PM artifact, not implementation.
- **Trust the PM's domain knowledge**; log dismissed concerns as assumptions. The PM has final say.
- **Anti-hallucination:** check existing capabilities first; mark new vs existing clearly; state assumptions; never fabricate — mark blocked spots `[NEEDS PM INPUT]`.

## Templates & references
- `templates/ui-epic-template.md` — UI-feature archetype (exemplar: BCLOUD-12164).
- `templates/backend-epic-template.md` — backend/platform archetype (exemplar: BCLOUD-5327).
- `templates/story-template.md` — lean Story (inherits from parent).
- `references/backend-subtypes.md` — the backend sub-types and their dictionaries, incl. first-time RAG (Knowledge Source Dictionary) and MCP (Tool Catalog).
- `references/logging-telemetry.md` — the mandatory Activity-vs-Audit logging section format.
- `checklists/ai-rag-mcp-checklist.md`, `checklists/quality-checklist.md`.

## Error handling
- Confluence/GitHub unavailable → keep authoring, note it, queue publish.
- Search fails → note it, proceed with duplicate caution.
- Incomplete info → specific follow-ups; `[NEEDS PM INPUT]`; never fabricate.
- Scope change mid-flow (incl. Story→Epic, or UI→hybrid) → pause, reassess, confirm, update.
