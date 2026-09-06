# [Story Name] — Story

*Lean template for additions/modifications to an already-documented flow. If this is net-new with no parent, stop and use the Epic/PRD template. Inherits archetype (UI / backend) from the parent unless overridden.*

---
```yaml
doc_type: story
status: draft
parent_epic_prd: [Jira key / Confluence link — required]
archetype: [inherit-from-parent | ui-feature | backend-platform]
product_area: [Product/App Name]
author: [PM/BA]
created_date: YYYY-MM-DD
last_updated: YYYY-MM-DD
jira_story_link: ""
```
---

## 1. Document Info
**Story name / Component / Screen (or area):** …
**Parent Epic/PRD:** [link — inherits personas/consumers, NFR baselines, permissions model, logging conventions, glossary unless overridden].
**Stakeholders:** PM/BA, Engineering, QA.

## 2. Scope & User Story
As a [persona/consumer — inherited unless different], I want [action], so that [benefit].
**In scope / Out of scope:** explicit; call out anything that belongs to the parent or a future story.

## 3. Context
2–4 sentences — only what's specific to this story; full background lives in the parent.

## 4. Functional Requirements
*(Namespaced IDs; BDD is the last column, after Informal Acceptance Criteria.)*

| Req ID | Capability | Description | Priority | Informal Acceptance Criteria | BDD Scenario(s) |
|--------|-----------|-------------|----------|------------------------------|-----------------|
| A.FR-1 | | | Must/Should/Nice | | `Given/When/Then` (happy + negative) |

### 4.1 Edge Cases
| Edge Case ID | Scenario | Expected Behavior | Related FR |
|--------------|----------|-------------------|------------|
| A.EC-1 | | | A.FR-1 |

### 4.2 GUI Data Dictionary *(UI stories only — elements this story adds/changes; full columns per ui-epic-template §4)*
### 4.2 Data/Contract Dictionary *(backend stories — the sub-type dictionary delta; see backend-subtypes.md)*

## 5. Non-Functional (deltas only)
Only what differs from the parent's NFRs.

## 6. Logging / Telemetry *(mandatory if this story changes access/config or fires events — see references/logging-telemetry.md; else reference parent)*

## 7. Permissions (delta only)
| Role | Field/Action | Visible | Editable | Notes |

## 8. Backend / API notes *(or strict contract if api-integration; see backend-subtypes.md)*

## 9. Analytics (delta) — follow the parent's naming convention.

## 10. Dependencies
| Dependency | Jira link | Status |

## 11. AI/RAG/MCP — inherit parent's assessment; note only deltas. First-time RAG/MCP build → use the Epic template instead.

## 12. Open Questions
- **OQ-1:** [question] — **A:** [answer or "open"]

---
**Status:** Draft | In Review | Approved | In Progress | Completed
