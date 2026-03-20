# Discovery Brief (1-Pager) Format

Use this condensed format when the user is in early-stage exploration, doesn't have enough data for a full PRD, or explicitly requests a 1-pager.

## Structure

```markdown
# [Project Name]: Discovery Brief

**Area:** [Product / Focus Area]
**Author:** [Name]
**Date:** [Date]
**Status:** Discovery / Exploration

---

## The Bet (2-3 sentences)
What are we proposing and why? State the core hypothesis in plain language.
Include the expected impact if known.

## The Problem (3-5 bullets)
- Each bullet is a user problem, framed as a need
- Back each with at least one piece of evidence (even if informal)
- Order by severity

## Proposed Approach
Brief description of the solution (3-5 sentences). Focus on the key insight
or mechanism that makes this worth trying. If there are past attempts,
one sentence on what's different this time.

## Key Hypotheses
1. If we [do X], then [Y outcome] because [reason]
2. If we [do X], then [Y outcome] because [reason]
3. ...

## Success Metrics
- **Primary:** [ONE metric]
- **Monitor:** [2-3 additional metrics]

## Rough Sizing
- **Opportunity:** [Back-of-envelope impact estimate with reasoning]
- **Effort:** [T-shirt size: S/M/L/XL with brief justification]

## Key Risks (2-3 max)
- Risk 1 → Mitigation
- Risk 2 → Mitigation

## Open Questions
- [ ] Question that needs answering before committing to a full PRD
- [ ] ...

## Next Steps
- [ ] What needs to happen to move from discovery to full PRD?
```

## Guidance

- The entire brief should fit on 1-2 printed pages
- Favor clarity and brevity over completeness — this is a conversation starter, not a spec
- It's OK to have more "open questions" than answers at this stage
- Don't force data you don't have — it's better to flag "we need to validate this" than to make something up
- This format is designed to help a PM get alignment before investing in a full PRD
