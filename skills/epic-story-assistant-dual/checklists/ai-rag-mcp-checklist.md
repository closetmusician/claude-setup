# AI / RAG / MCP — assessment & extension checklist

Run on every epic. Two modes.

## Mode 1 — Assessment (common case)
- [ ] AI needed at all? If no → one honest line ("Deterministic — no AI/RAG/MCP") is sufficient.
- [ ] If yes: one-shot / orchestration / agent?
- [ ] RAG: none / **extending an existing index** / first-time build?
- [ ] MCP: none / **adding a tool to an existing server** / first-time build?
- [ ] Extension answers describe the *delta* only.

## Mode 2 — Extension (first-time build routes into real content)
If RAG = first-time build:
- [ ] Knowledge Source Dictionary filled (esp. retrieval **permission scope** — no cross-tenant leakage).
- [ ] Grounding/citation requirement authored.
- [ ] Permission-aware retrieval (filter before retrieval).
- [ ] No-result = abstain, never fabricate (negative-path BDD).
- [ ] Quality thresholds + how evaluated (eval set + method).
- [ ] RAG edge cases in FR BDD column (stale index, source deleted mid-session, permission change mid-session, conflicting/malicious sources).

If MCP = first-time build:
- [ ] Tool Catalog filled (+ Resource Catalog if data exposed).
- [ ] Authorization model (caller vs service identity; who can invoke what).
- [ ] Confirmation/consent for writes/destructive tools; blast-radius limits.
- [ ] Every invocation is an audit event (wired to Logging/Telemetry).
- [ ] Versioning / backward-compat for external agents.
- [ ] Failure modes in FR BDD column (timeout, partial success, downstream down, auth expiry, ambiguous input).

Guardrail: no prompts, model names, embeddings/vector internals, or infra config anywhere. Behavioral/contract level only.
