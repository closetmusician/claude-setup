---
name: assumption-mapping
description: "Assumption mapping framework for identifying and prioritising riskiest assumptions before research begins — read at Phase 0"
---

# Assumption Mapping

Before you research anything, map what you're assuming. The riskiest assumption — the one that's both high-impact and low-confidence — is where the research should focus. This technique comes from Strategyzer (Osterwalder), Lean UX (Gothelf & Seiden), and Google Design Sprints.

---

## Why This Matters

Most research plans are topic-driven: "research the personas", "research the competitors." This wastes time on things you're already confident about and under-invests in the beliefs that could sink the entire initiative. Assumption mapping flips the research plan from "cover everything" to "test the things that would kill us if we're wrong."

---

## How to Build the Assumption Map

### Step 1: Extract Assumptions

Read the initiative brief and extract every assumption — things the brief takes as true without evidence. Look for:

| Category | What to look for | Example |
|----------|-----------------|---------|
| **User assumptions** | Who the user is, what they want, how they behave | "Admins will configure this for their team" |
| **Problem assumptions** | That the problem exists, is severe, is widespread | "Users are frustrated by the current sharing flow" |
| **Solution assumptions** | That the proposed approach will work | "A wizard will reduce drop-off" |
| **Business assumptions** | That the opportunity is real and worth pursuing | "This will reduce churn by 5%" |
| **Feasibility assumptions** | That it can be built within constraints | "The API supports real-time updates" |
| **Channel assumptions** | That users can be reached and activated | "Users will discover this via the settings page" |

**Aim for 10-20 assumptions.** If you're finding fewer than 8, you're not looking hard enough. If the brief says "users need X" — that's an assumption. If it says "this will improve Y" — that's an assumption.

### Step 2: Plot on the 2×2

For each assumption, assess two dimensions:

* **Importance**: If this assumption is wrong, how badly does it break the initiative? (Low → High)
* **Evidence**: How much evidence do we have that this assumption is true? (Strong evidence → No evidence)

```
                    HIGH IMPORTANCE
                         │
         Validate        │        Test First
         (have some      │        (MOST DANGEROUS —
          evidence,      │         high stakes,
          confirm it)    │         no evidence)
                         │
  STRONG EVIDENCE ───────┼─────── NO EVIDENCE
                         │
         Monitor         │        Explore
         (low risk,      │        (low stakes but
          well-evidenced)│         unknown — might
                         │         surprise you)
                         │
                    LOW IMPORTANCE
```

### Step 3: Prioritise for Research

| Quadrant | Action | Research investment |
|----------|--------|-------------------|
| **Test First** (top-right) | These are your #1 research priority. Design specific research questions to validate or kill these assumptions. | Heavy — dedicated research questions, external data requests |
| **Validate** (top-left) | You have some evidence but it's not conclusive. Seek confirming or disconfirming data. | Medium — targeted validation during existing research tracks |
| **Explore** (bottom-right) | Low stakes but you genuinely don't know. Worth a lightweight look during Phase 1. | Light — a question or two during broader research |
| **Monitor** (bottom-left) | Safe to proceed. Revisit if something changes. | Minimal — note and move on |

---

## Output Format

Include in `00-research-plan.md` as an Assumption Map section:

```markdown
## Assumption Map

### Test First (High Importance, Low Evidence)
| # | Assumption | Source | What breaks if wrong | Research question |
|---|-----------|--------|---------------------|-------------------|
| A1 | [assumption] | [brief section] | [consequence] | [specific question to answer] |

### Validate (High Importance, Some Evidence)
| # | Assumption | Source | Current evidence | Validation approach |
|---|-----------|--------|-----------------|-------------------|

### Explore (Low Importance, Low Evidence)
| # | Assumption | Source | Why it might matter |
|---|-----------|--------|-------------------|

### Monitor (Low Importance, Strong Evidence)
| # | Assumption | Source | Evidence |
|---|-----------|--------|---------|
```

---

## Integration with Research Plan

The "Test First" assumptions should directly drive:

1. **Key research questions** (Phase 0, item 3) — at least 50% of research questions should target Test First assumptions
2. **Subagent research prompts** — prompts should seek data that confirms or kills the riskiest assumptions
3. **Phase 1 focus** — when writing each Phase 1 step, consciously check: "Am I gathering evidence for or against the Test First assumptions?"
4. **Phase 2 validation** — the Hypothesis Validation section should explicitly revisit every Test First assumption with a verdict: confirmed / partially confirmed / refuted / still unknown

---

## Common Traps

* **Assuming your assumptions are facts.** If the brief says "users want X" and you write that down as a finding instead of an assumption, you've already failed.
* **Only listing safe assumptions.** The uncomfortable ones — "is this problem even real?" — are the ones that matter most.
* **Too many Test First items.** If everything is top-right, you haven't been honest about importance. Force-rank: which 3-5 would truly kill the initiative?
* **Forgetting to revisit.** The map is useless if you don't check it against findings in Phase 2.
