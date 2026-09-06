# Quality review checklist

## Completeness
- [ ] Document type and archetype explicitly confirmed.
- [ ] All mandatory sections present/filled or marked N/A with reason; no placeholders.
- [ ] Success metrics present (with measurable-now vs instrumentation-gated labels where relevant).
- [ ] Logging/Telemetry section present (Activity vs Audit split, field dictionary, canonical events).
- [ ] UI: GUI Data Dictionary covers every element in scope. Backend: the sub-type Data/Contract Dictionary is filled.

## Traceability
- [ ] Every FR and EC has a namespaced ID (surface/area prefix).
- [ ] Every FR row carries BDD (happy + relevant negative) in the BDD column, after Informal Acceptance Criteria.
- [ ] Every EC has a negative-path scenario in the FR BDD column.
- [ ] Every GUI/contract dictionary row maps to an FR.
- [ ] Every canonical logging event maps to the FR(s) that fire it.

## Cohesiveness
- [ ] Requirements tie back to objectives; metrics align with goals.
- [ ] Dependencies are Jira-linked, not just prose.
- [ ] No contradictions between sections.

## Coherence
- [ ] Problem → solution → metrics flows clearly.
- [ ] Terminology consistent.
- [ ] Feasibility considered; WHAT-not-HOW respected (except where an archetype legitimately owns a contract).

## Prompts honored
- [ ] PM was asked about each recommended section (Risks, Rollout/Rollback) and each optional one (Launch checklist, Glossary, Support/CS).
- [ ] Diagram format confirmed with PM; activity diagrams include negative paths.

Length is not a metric.
