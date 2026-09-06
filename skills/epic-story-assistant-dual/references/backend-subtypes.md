# Backend sub-types and their dictionaries

Every backend/platform epic has a **canonical field-level contract** — it's just not a GUI dictionary. The shared spine stays the same; only this dictionary (and a few sub-type-specific sections) changes. A single epic may combine sub-types (e.g. an instrumentation epic that also defines a data-storage backfill).

Confirm the sub-type(s) with the PM at Step 4, then populate the matching dictionary in Section 9 of the backend template.

Overarching guardrail for all sub-types: stay at PM/behavioral/contract level. **No prompts, no model names, no chunking/embedding/vector-store internals, no infra config.** Illustrative behavioral sample payloads are fine; implementation is engineering's.

---

## 1. Instrumentation / analytics
**Dictionary: Events dictionary.** Exemplar: BCLOUD-5327.

| Event name | Current predecessor | Description | FE/BE | Required properties | Sample payload | Optional properties |
|------------|---------------------|-------------|-------|---------------------|----------------|---------------------|

Sub-type sections: As-Is audit (ungoverned events + issues), Taxonomy (naming pattern, single canonical `user_id`, single `environment`, `app_id` as property), and the **FE/BE decoupling principle** (FE fires on intent/click; BE fires on execution outcome; genuinely independent). Governance: tracking-plan registration + base dashboard.

---

## 2. API / integration (especially endpoints for outside services)
**Dictionary: API contract table** — this is where the strict contract rigor genuinely belongs (external callers depend on it).

| Endpoint | Method | Purpose | Request params (incl. pagination/filter) | Response shape | Auth | Rate limit | Retry/Fallback | Timeout |
|----------|--------|---------|-------------------------------------------|----------------|------|------------|----------------|---------|

Sub-type sections: **versioning & backward-compatibility policy** (deprecation window, version path), **external-consumer list**, and an **error-code catalog** (code → meaning → caller action). Retry/fallback and timeout are required per row here, unlike UI epics' looser API notes.

---

## 3. Data / storage / model (e.g. deletion, retention, backfill)
**Dictionary: Field / entity dictionary.**

| Field / entity | Type | Nullable | Default | Constraint | PII classification | Retention |
|----------------|------|----------|---------|------------|--------------------|-----------|

Sub-type sections: **migration / backfill plan** (is a backfill needed? for which existing records? reversible?) and a **data-lifecycle** view (create → update → soft-delete → hard-delete → purge), with the lifecycle diagram covering negative paths.

---

## 4. Logging / audit (when the logging pipeline itself is the deliverable)
**Dictionary: Log-field dictionary** — see `logging-telemetry.md` for the exact format. Activity-vs-Audit split, canonical event names, retention, and the company Logging & Monitoring Standard. (Note: logging/telemetry is *also* a mandatory section in every epic; this sub-type is for epics whose *primary* deliverable is the pipeline.)

---

## 5. RAG — first-time build
Trigger: the AI/RAG/MCP gate answered "this epic is the first-time implementation of RAG" (not merely extending an existing index — that's assessment-level). The canonical artifact is a **Knowledge Source Dictionary** plus retrieval-behavior requirements. All behavioral; no model/prompt/embedding internals.

### Knowledge Source Dictionary
| Source | Content type | System of record | Retrieval permission scope | Freshness / update cadence | PII / data class | Include-exclude rules | Retention |
|--------|--------------|------------------|----------------------------|----------------------------|------------------|-----------------------|-----------|

The **permission-scope** column is the most important one in a permission-gated, multi-tenant product: retrieval must never surface content the caller isn't allowed to see, and must never cross tenant/org boundaries. This is the RAG parallel to the "org A must not affect org B" rule.

### Retrieval-behavior requirements (author as FRs + NFRs)
- **Grounding / citation:** answers draw only from retrieved sources and cite them.
- **Permission-aware retrieval:** filter by the caller's actual access *before* retrieval, not after.
- **No-result behavior:** abstain / "I don't know" / empty state — never fabricate. (A negative-path scenario → FR BDD column.)
- **Quality thresholds (NFR, behavioral):** a groundedness/faithfulness target and a retrieval-relevance target, plus **how it's evaluated** (eval set + method) — the RAG analog of "events land with required properties present."

### RAG edge cases (→ FR BDD column)
Empty or stale index; source deleted mid-session; caller permission changes mid-session; conflicting sources; malicious/prompt-injection content inside a retrieved document.

---

## 6. MCP — first-time build
Trigger: the gate answered "first-time implementation of an MCP server/interface" (not adding one tool to an existing server). Canonical artifact is a **Tool Catalog** (and a Resource Catalog if it exposes data) plus a safety envelope.

### Tool Catalog
| Tool | Behavior | Read/Write | Inputs (param, type, req/opt) | Output shape (behavioral) | Permission scope required | Idempotent? | Reversible / undo | Rate limit |
|------|----------|------------|-------------------------------|---------------------------|---------------------------|-------------|-------------------|------------|

### Resource Catalog *(if the server exposes data resources)*
| Resource | Content | Read/Write | Permission scope | PII / data class |
|----------|---------|------------|------------------|------------------|

### Safety envelope (author as FRs + NFRs) — where MCP epics live or die
- **Authorization model:** does a tool act with the *caller's* permissions or a service identity? Which agents/callers may invoke which tools?
- **Confirmation / consent** for any write or destructive tool; explicit **blast-radius limits**.
- **Auditability:** every tool invocation is an audit event → ties directly into the mandatory Logging/Telemetry section (not optional here — central).
- **Versioning / backward-compat:** external agents depend on the tool contract; treat like the API-integration sub-type.
- **Failure modes (→ FR BDD column):** tool timeout, partial success on a multi-step call, downstream service down, auth expiry mid-call, ambiguous input.

---

## Choosing quickly
- Firing/renaming analytics events → **instrumentation**.
- Exposing/consuming an endpoint, esp. for outside services → **API-integration**.
- New/changed storage, retention, deletion, backfill → **data/storage**.
- The logging pipeline itself is the deliverable → **logging/audit**.
- First retrieval-over-knowledge capability → **RAG**.
- First tool/resource server for agents → **MCP**.
When in doubt, ask the PM which one is the *primary* deliverable and treat the rest as secondary dictionaries.
