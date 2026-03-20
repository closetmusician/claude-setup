# Diligent PRD Template

This is the default PRD template based on Diligent Boards conventions. When generating a full PRD, follow this structure. Apply quality patterns from `quality-patterns.md` throughout.

## Template Structure

```markdown
# [Project Name]

**Area:** [Product / Focus Area]
**Timeframe:** [Quarter - Year]
**TL;DR:** [1-liner for what this project is about]

---

## RACI

| Responsible (Doing the Work) | Accountable (Owners + Approvers) | Consulted (Providing Feedback) | Informed (Knows this is happening) |
|------------------------------|----------------------------------|-------------------------------|-----------------------------------|
| PM: [name] | [name] | [names] | [names] |
| ENG: [name] | | | |
| DES: [name] | | | |

---

# 1. Problem Definition

## Objective
[One sentence: what are you trying to do?]

## Context, Problems, Opportunities
[Describe the problem or opportunity. Include:
- Why this matters to customers
- Why now? What business needs drive prioritization?
- How this ties to strategic goals / vision
- Key user insights and competitive insights
- Reference past attempts and their outcomes]

## User Problems
[Frame using Jobs to be Done. Each problem backed by evidence.]

As a [persona]:
- Help me do [X job] so that I can [achieve Y outcome] — [evidence link]
- When I [context], but [barrier], help me [goal] so [outcome] — [evidence link]

## Opportunity Size
[Show your math. Use baseline metrics, conversion rates from comparable products,
and clear reasoning. Include optimistic and conservative estimates.]

## Success Measure
[Define metric hierarchy:]
- **Target Metric:** [The ONE metric to optimize]
- **Secondary Metrics:** [Should improve or stay neutral]
- **Guardrail Metrics:** [Must NOT regress]

---

# 2. Product Requirements

[What are you building? Categorize into:]
- **P0 (MVP):** Must-have for launch
- **P1 (Fast-follow):** Important but not blocking launch
- **P2 (Future):** Aspirational, out of scope for now

## Core Features + Hypotheses
[For each feature:]
- *Feature name:* If we [do X], THEN [expected outcome] because [reasoning]

## Options Analysis
[For larger projects, assess 2-3 different approaches:]

| Dimension | Option A | Option B | Option C (Recommended) |
|-----------|----------|----------|----------------------|
| User value | ... | ... | ... |
| Business value | ... | ... | ... |
| Eng cost | ... | ... | ... |
| Risk | ... | ... | ... |

[If past attempts exist, include a Differentiation table — see quality-patterns.md Pattern 4]

## User Experience
[This should be the largest section. Break into distinct flows:]

### Producer Flow
[Step-by-step numbered flow for the person creating/initiating]

### Consumer Flow
[Step-by-step numbered flow for the person viewing/responding]

### Use Cases Table
| Use Case | Hypothesis | Example |
|----------|-----------|---------|
| ... | ... | ... |

## Designs
[Link to Figma or embed design references. Note if designs are WIP.]

## Data or Tracking Requirements
| Tracking Change | Details |
|----------------|---------|
| ... | ... |

## Other Dependencies & Requirements

### Cross Product Dependencies
| Product | Details |
|---------|---------|
| Mobile/Web | [Does this need to exist across platforms?] |
| ... | ... |

### Settings Toggles
| Toggle | Functionality | Default State |
|--------|-------------|---------------|
| ASA / Director Settings | [description] | On/Off |
| BWCA / Admin Site Settings | [description] | On/Off |
| CSP / CSM admin page | [description] | On/Off |

### Cross Team Support
| Type of Support | Needs Review | Point of Contact |
|----------------|-------------|-----------------|
| Legal | Y/N | [name] |
| Security | Y/N | [name] |
| Translation | Y/N | [name] |
| Product Marketing | Y/N | [name] |
| Help Center Content | Y/N | [name] |
| Training Team | Y/N | [name] |

### Pricing Tiers
| Pricing Plan | Description | Feature Included |
|-------------|------------|-----------------|
| All Legacy Plans | Existing contracts | Y/N |
| Foundation | SMBs / Private under $100M | Y/N |
| Essential | Small Public Companies | Y/N |
| Pro | Medium Public Companies | Y/N |
| Plus | Large Public Global Companies | Y/N |

---

# 3. Engineering Effort

[Break down by component. Include parallelization notes.]

## P0: MVP

| Component | Scope Description | Est. Hours (Human) | Est. Hours (Agentic/Claude Code) | Backend vs. Client | Dependencies |
|-----------|------------------|-------------------|--------------------------------|-------------------|-------------|
| ... | ... | ... | ... | ... | ... |
| **Total** | | **X hrs** | **Y hrs** | | |

*Eng Needed: [specific roles]*
*Parallelization notes: [what can run in parallel]*

## P1: Fast-Follow (if applicable)

| Component | Scope Description | Est. Hours (Human) | Est. Hours (Agentic/Claude Code) | Backend vs. Client | Dependencies |
|-----------|------------------|-------------------|--------------------------------|-------------------|-------------|
| ... | ... | ... | ... | ... | ... |

*Barriers to consider:* [list specific risks to timeline]

---

# 4. Release Plan

## Service Releases
| Service | Required? |
|---------|----------|
| Bcore (2-3 week release time) | Y/N |

## Standard Release Process
| Step | Details |
|------|---------|
| Dogfooding & QA | [date/status] |
| Pre-Release Communications (2 weeks before) | [channels/audience] |
| Release Communications | [channels/audience] |

## Additional Steps
| Step | Details |
|------|---------|
| Beta/Pilot program? | [details] |
| Customer-specific build? | [details] |

---

# 5. Risks & Considerations

## Cons/Risks with Mitigations
[For each risk: state it, rate severity, list mitigations]

## Out of Scope
[Explicitly state what you're NOT doing and why]

---

# 6. Appendix (if applicable)

[Include only when sufficient data exists. Candidates:]
- Opportunity sizing details with source data
- Reasons to be skeptical (with mitigations)
- Learnings from past attempts (detailed tables)
- Alternative designs explored
- Competitive analysis

## Post Launch Analysis
[Questions to answer after release. How long needed for analysis?]
```

## Template Notes

- Not every section is required for every project. Small projects can skip Options Analysis, Pricing Tiers, etc.
- The User Experience section should be the most detailed part of the PRD
- Settings Toggles, Cross Team Support, and Pricing Tiers are Diligent-specific sections — omit if using a custom template
- Always ask the user which Diligent product area they're working in (Boards, Entities, ESG, etc.) to contextualize appropriately
