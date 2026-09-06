# [Feature/Epic Name] — Epic / PRD (Backend/platform archetype)

*Use when the epic ships a backend/data/instrumentation capability with no direct UI. Structure mirrors BCLOUD-5327. Keep the shared spine; the middle swaps in a **Data/Contract Dictionary** whose columns depend on the sub-type. Personas are renamed **Consumers**. Read `references/backend-subtypes.md` and confirm the sub-type(s) with the PM before authoring Sections 3–9.*

Backend sub-types (a single epic may combine them): **instrumentation/analytics · API-integration · data/storage · logging/audit · RAG (first-time build) · MCP (first-time build).**

---
```yaml
doc_type: epic-prd
archetype: backend-platform     # ui-feature | backend-platform | hybrid
backend_subtypes: []            # instrumentation | api-integration | data-storage | logging-audit | rag | mcp
status: draft
product_area: [Product/App Name]
jira_epic_link: ""
confluence_link: ""
author: [PM/BA]
created_date: YYYY-MM-DD
last_updated: YYYY-MM-DD
```
---

## 1. Problem Statement & Background

### 1.1 Parent / epic context
[Jira + parent PRD smartlinks.] What this epic realizes and where it sits relative to any parent PRD.

### 1.2 Objectives
Numbered objectives.

### 1.3 Problem Description
Use the **WHO / CONTEXT / IMPACT** framing:
- **WHO:** which roles/teams are trying to do what.
- **CONTEXT:** the constraints the capability must satisfy.
- **IMPACT:** what breaks or stays blocked without this baseline.

### 1.4 Scoping objective *(if the epic is a POC or has a sharp filter)*
State the small set of questions the epic must answer, and use it as the scoping filter for what's in vs deferred.

### 1.5 Success Metrics *(mandatory)*
| Metric | Baseline | Target | Timeline | Method | Confidence / Note |
|--------|----------|--------|----------|--------|-------------------|
| | | | | | measurable-now / instrumentation-gated |

---

## 2. In Scope / Out of Scope
Explicit in/out lists. For deferred items, say *why* and flag the release/phase they belong to.

---

## 3. Current State — As-Is Audit *(recommended for instrumentation / data / logging sub-types)*
What exists today and what's wrong with it, as a table. For instrumentation: the ungoverned events and their issues (casing, identity, duplication). For data/storage: current schema/fields. Root causes.

| Item (event / field / endpoint) | In place today? | Issue |
|----------------------------------|-----------------|-------|

---

## 4. Consumers *(replaces Personas)*
| Consumer | Need |
|----------|------|
| Product Management | |
| Data Science / downstream service / team | |
| Engineering (implementing) | an unambiguous, minimal contract |
| Decision the output feeds (e.g. a go/no-go) | |

---

## 5. Taxonomy & Data Model *(instrumentation / data / API / RAG / MCP as applicable)*
Naming rules, canonical identity/environment model, core properties, and any load-bearing principle (e.g. FE = intent on click, BE = execution outcome; the two must be genuinely decoupled). Keep it behavioral/contractual — no implementation internals.

---

## 6. Functional Requirements
*(Namespaced area IDs — e.g. AM.FR-1, BK.FR-1, DM.FR-1. BDD is the last column, after Informal Acceptance Criteria.)*

| Req ID | Event / Capability | Priority | Description | Informal Acceptance Criteria | BDD Scenario(s) |
|--------|--------------------|----------|-------------|------------------------------|-----------------|
| DM.FR-1 | | Must/Should/Nice | | | `Scenario: … Given/When/Then` (happy + negative) |

---

## 7. Permissions
| Role group | Scope | Roles | Field / Action | Visible | Editable |
|------------|-------|-------|----------------|---------|----------|

---

## 8. Edge Cases
| Area | Edge Case ID | Scenario | Expected Behavior |
|------|--------------|----------|-------------------|
| Data Model | DM.EC-1 | [unexpected shape / duplicate identity / stale index / cross-tenant] | [what the system does] |

---

## 9. Data / Contract Dictionary *(the backend analog of the GUI Data Dictionary — pick columns by sub-type; see references/backend-subtypes.md)*

- **Instrumentation:** Events dictionary — event name, current predecessor, description, FE/BE, required props, sample payload, optional props.
- **API-integration:** Endpoint contract — endpoint, method, purpose, request params (incl. pagination/filter), response shape, auth, rate limit, **retry/fallback, timeout**, versioning/deprecation. External-consumer list + error-code catalog.
- **Data/storage:** Field/entity dictionary — field, type, nullable, default, constraint, **PII classification, retention**; plus migration/backfill plan.
- **Logging/audit:** Log-field dictionary (see `references/logging-telemetry.md`), Activity vs Audit split, retention, standard reference.
- **RAG (first-time):** **Knowledge Source Dictionary** + retrieval-behavior requirements — see `references/backend-subtypes.md`.
- **MCP (first-time):** **Tool Catalog** (+ Resource Catalog) + safety envelope — see `references/backend-subtypes.md`.

---

## 10. Non-Functional Requirements
| Category | Requirement |
|----------|-------------|
| Data consistency | canonical identity; no duplicate/committee-scoped fields reintroduced |
| Extensibility | add a new entry via registry, not schema redesign |
| Environment integrity | dev/prod separation; no cross-environment bleed |
| Performance / latency | read/write latency budget; idempotency where relevant |
| Backward compatibility | for API/MCP consumers |
| Accessibility | N/A — no UI surface (state explicitly) |

---

## 11. Logging / Telemetry *(mandatory — see references/logging-telemetry.md)*
Activity vs Audit split, field dictionary, canonical event names, company Logging & Monitoring Standard. For a **logging/audit sub-type**, this *is* the primary deliverable and its dictionary lives here (or in Section 9).

---

## 12. AI, RAG & MCP — Assessment & Extension *(mandatory gate)*
| Question | Answer | Rationale |
|----------|--------|-----------|
| AI needed at all? | Y/N | |
| If yes: one-shot / orchestration / agent? | | |
| RAG — none / extending existing / **first-time build**? | | if first-time → complete Knowledge Source Dictionary (ref) |
| MCP — none / extending existing / **first-time build**? | | if first-time → complete Tool Catalog (ref) |

---

## 13. Dependencies & Rollout
**Dependencies** (Jira issue links) and **release sequence** (the ordered path: sign-off → implement in dev-connected env → PM validation → governance/dashboard → prod promotion, or the analog for this sub-type).

**Risks & mitigations** *(recommended — prompt the PM).*
**Rollout & rollback / kill switch** *(recommended — prompt the PM).*
**Launch checklist / Glossary / Support-CS enablement** *(optional — prompt the PM).*

---

## 14. Open Questions
*(Simple Q → A. Inline answer when known. Owner/status optional.)*
- **OQ-1:** [question] — **A:** [answer or "open"]

---
**Status:** Draft | In Review | Approved | In Progress | Completed
