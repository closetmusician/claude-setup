---
name: demand-testing
description: "Menu of lightweight demand tests (fake door, Wizard of Oz, concierge, etc.) with selection criteria — read at Step 3.4"
---

# Demand Testing Menu

Before committing to a full build, test demand. This reference provides a menu of lightweight experiments to validate the biggest assumptions with minimal investment. Sourced from Lean Startup (Ries), The Mom Test (Fitzpatrick), Sprint (Knapp), Testing Business Ideas (Bland & Osterwalder).

---

## Core Principle

**The goal is not to test the solution. The goal is to test the assumption behind the solution.** Every test targets one specific assumption from the Assumption Map (Phase 0). If you can't name the assumption, you don't have a test — you have a demo.

---

## Test Selection Matrix

| Test Type | Time to Build | Cost | Signal Quality | Best For |
|-----------|:------------:|:----:|:--------------:|----------|
| **Fake Door** | Hours | Minimal | Medium | Demand validation: "Do users want this?" |
| **Painted Door** | Hours | Minimal | Medium | Feature discovery: "Would users click this?" |
| **Wizard of Oz** | Days | Low-Medium | High | Feasibility of experience: "Can users get value from this flow?" |
| **Concierge** | Days-Weeks | Medium | Very High | Value validation: "Does solving this actually help?" |
| **Landing Page** | Hours-Days | Low | Medium | Market demand: "Is there an audience for this?" |
| **Explainer Video** | Days | Low-Medium | Medium | Concept validation: "Do people understand and want this?" |
| **Pre-order / Waitlist** | Hours | Minimal | High | Commitment validation: "Will users put skin in the game?" |
| **One-Question Survey** | Hours | Minimal | Low-Medium | Quick directional signal on a specific question |
| **Prototype Usability Test** | Days | Low | High | Interaction validation: "Can users complete the flow?" |

---

## Test Details

### Fake Door Test

**What**: Add a button, menu item, or CTA for a feature that doesn't exist yet. When clicked, show an explanation page ("Coming soon — sign up for early access"). Track click-through rate and sign-ups.

**Tests the assumption**: "Users want [feature]" — measured by unprompted discovery and click intent.

**How to run**:
1. Add the trigger (button, link, card) in the natural location where users would encounter it
2. Track impressions (saw it) and clicks (wanted it)
3. On click, show a lightweight explanation + interest capture (email, "notify me")
4. Run for 1-2 weeks minimum for statistical significance

**Success signal**: Click-through rate above baseline for that product area. Interest capture > 10% of clickers.

**Watch out for**: Misleading users. The "coming soon" message must be honest. Don't create expectations you can't meet.

---

### Painted Door Test

**What**: A visual indicator of a feature (grayed-out button, "NEW" badge, menu item) placed in the UI to measure whether users notice and attempt to use it. Unlike a fake door, the user may not even get a click — the test measures noticing, hovering, or attempting.

**Tests the assumption**: "Users will discover this feature in [location]" — information architecture validation.

**How to run**:
1. Add the visual element in the proposed location
2. Track views, hovers, clicks, and time-on-page
3. A/B test placement if possible

**Success signal**: Interaction rate that suggests organic discovery without prompting.

---

### Wizard of Oz Test

**What**: The user experiences what feels like a working feature, but behind the scenes a human (or manual process) is doing what the software would do. The user doesn't know it's manual.

**Tests the assumption**: "If we provide [capability], users will [behaviour]" — validates the experience without building the backend.

**How to run**:
1. Build only the front-end shell (or use the prototype from Step 4.1b)
2. Have a human operator monitor inputs and produce outputs manually
3. Track: completion rate, time-to-value, user satisfaction, repeat usage

**Success signal**: Users complete the flow AND return for a second use. Single use ≠ demand.

**Watch out for**: Scale. This only works for small cohorts (5-20 users). That's fine — the goal is learning, not launch.

---

### Concierge Test

**What**: Manually deliver the value proposition to a small number of users, one at a time. No software required — use email, spreadsheets, video calls, whatever it takes.

**Tests the assumption**: "Solving [problem] actually creates [value]" — the deepest validation possible.

**How to run**:
1. Identify 5-10 users who have the problem (from Phase 1 personas)
2. Manually deliver the solution: do it for them, walk them through it, white-glove it
3. Track: did they get value? Would they pay/continue? What surprised you?
4. Interview after: "If I took this away tomorrow, what would you do?"

**Success signal**: Users express genuine disappointment at the idea of losing it. "Would you pay for this?" is weaker than "what would you do without it?"

**Watch out for**: Founder bias. You're so close to the user that you'll over-interpret positive signals. Use The Mom Test rules: ask about their life, not your idea.

---

### Landing Page Test

**What**: A standalone page describing the proposed solution, targeting the right audience through ads, email, or social. Measure interest via sign-ups, waitlist joins, or "learn more" clicks.

**Tests the assumption**: "There is market demand for [solution category]" — top-of-funnel demand.

**How to run**:
1. Write a clear value proposition page (use the TL;DR from the PRD or Solution Synthesis)
2. Drive traffic via targeted channels (ads, community posts, email to existing users)
3. Track: conversion rate, sign-up rate, bounce rate, time on page

**Success signal**: Conversion rate above 5% from qualified traffic. Below 2% = reconsider the positioning or the audience.

---

### Prototype Usability Test

**What**: Put the prototype from Step 4.1b in front of 5-8 users and observe them completing tasks. No guidance — just "try to [accomplish X]."

**Tests the assumption**: "Users can understand and complete the proposed flow" — interaction validation.

**How to run**:
1. Define 3-5 tasks tied to the P0 requirements
2. Recruit users matching the primary persona (5 users finds ~85% of usability issues — Nielsen)
3. Think-aloud protocol: "Tell me what you're thinking as you go"
4. Track: task completion rate, time-on-task, error rate, satisfaction

**Success signal**: >80% task completion on the primary happy path. <60% = fundamental flow problem.

---

## How to Choose

Ask three questions:

1. **What's the riskiest assumption?** (From the Assumption Map)
   * Demand assumption → Fake Door, Landing Page, Pre-order
   * Value assumption → Concierge, Wizard of Oz
   * Usability assumption → Prototype Test, Wizard of Oz
   * Feasibility assumption → Technical spike (not in this menu — that's engineering)

2. **How much time do you have?**
   * Hours → Fake Door, Painted Door, One-Question Survey
   * Days → Wizard of Oz, Landing Page, Prototype Test
   * Weeks → Concierge

3. **What signal quality do you need?**
   * Directional ("is this worth exploring?") → Fake Door, Survey
   * Confident ("should we build this?") → Concierge, Wizard of Oz, Prototype Test

---

## Output Format for Step 3.4

In the Alternative Approaches file, the "Minimum viable experiment" section should include:

```markdown
### Minimum Viable Experiment

**Riskiest assumption to test**: [from Assumption Map]

**Recommended test**: [test type]
**Why this test**: [1-2 sentences linking the test to the specific assumption]
**What to build**: [specific deliverable — e.g., "Add a 'Smart Suggestions' button to the toolbar"]
**Effort**: [hours/days]
**Run for**: [duration]
**Success signal**: [specific, measurable threshold]
**If it succeeds**: [what we learn, how it changes the PRD]
**If it fails**: [what we learn, how it changes the PRD]

**Alternative test** (if primary isn't feasible): [backup test type + brief rationale]
```

---

## The Mom Test Rules (for any user-facing test)

From Rob Fitzpatrick — apply these whenever you're gathering user feedback during tests:

1. **Talk about their life, not your idea.** "Tell me about the last time you tried to [do X]" not "Would you use a feature that [does Y]?"
2. **Ask about specifics in the past, not generics or the future.** "What did you do last Tuesday?" not "What would you do if...?"
3. **Talk less, listen more.** If you're talking more than 20% of the time, you're pitching, not researching.
4. **Bad data: compliments, fluff, ideas.** "That's cool!" means nothing. "I tried to do X last week and ended up spending 2 hours on a spreadsheet" means everything.
5. **Good data: facts about their past behaviour, specific complaints, the workarounds they're already using.**
