---
name: expert-prompts
description: "Expert-persona-driven research prompt generation for subagents — governs how the agent creates prompts at Phase 0, Step 1.4, and Step 1.5"
---

# Expert Research Prompts

At designated research points (Phase 0, Step 1.4, Step 1.5), the agent spins up parallel subagents with web search. Each subagent gets an **expert-persona-driven research brief** — written as if a world-class specialist in that domain were commissioning the research.

---

## Core Principle

Instead of "search for [topic]", write subagent prompts as: **"As an expert [role] investigating [topic], I need to understand [specific question]. Search the web for [specific data] focusing on [specific angle]."**

The expert persona frames the prompt with domain-specific judgment about what matters, what to look for, and what signals to prioritise. This produces dramatically better results from web search and AI research.

---

## How to Select Expert Personas

At each research point, **select expert personas relevant to the initiative domain and the step's needs**. The personas should vary — don't pick 5 business roles. Mix across these categories:

| Category | Examples | When to use |
|----------|---------|-------------|
| **Domain expert** | Real estate agent, healthcare administrator, compliance officer, logistics coordinator, teacher | Always — the person who lives in the problem space daily |
| **UX researcher** | NNGroup-level usability researcher, ethnographic researcher, service designer | Always — the person who knows how to study human behaviour |
| **Business strategist** | Growth PM, pricing analyst, competitive intelligence analyst, market researcher | When business case, sizing, or competitive positioning matters |
| **Technical investigator** | Staff engineer, data analyst, infrastructure architect, security researcher | When technical feasibility, data availability, or instrumentation matters |
| **Adjacent-domain expert** | Behavioural economist, cognitive psychologist, game designer, operations researcher | When the problem has analogues in other fields |

**The agent must choose personas based on the initiative topic, not from a fixed list.** A healthcare initiative gets a clinical workflow expert; a developer tools initiative gets a senior SRE; a consumer social initiative gets a community manager and a behavioural psychologist.

---

## Subagent Prompt Structure

Each subagent gets a self-contained research brief:

```
As a [specific expert role] investigating [initiative topic], I need to understand [specific question].
Search the web for [specific data — what to search, what to look for, what signals matter].
Focus on [specific angle that this expert would prioritise].
Return a concise markdown summary (under 500 words) with:
- Key findings as a prioritised list
- Specific product/company names, numbers, and URLs where available
- Confidence notes on what's well-documented vs. sparse
Do not include any preamble or meta-commentary — just the research findings.
```

**~80-120 words per prompt.** Each subagent runs independently with web search and returns text-only markdown.

---

## Per-Phase Prompt Guidance

### Phase 0 (Research Planning) — 3-5 subagents

Goal: Gather broad domain context before planning research. Cast a wide net.

Suggested expert angles:
* **Domain practitioner**: "What does the day-to-day look like for someone dealing with [problem]? What are the common pain points, workarounds, and tools?"
* **UX researcher**: "How do [personas] actually behave when encountering [product area]? What are the known failure modes and behavioural patterns?"
* **Competitive/market analyst**: "What is the competitive landscape for [initiative topic]? Who are the key players and what approaches are they taking?"
* **Behavioural scientist**: "What cognitive biases and mental models are at play when [persona] encounters [situation]?"
* **Adjacent-domain expert**: "How do other industries solve analogous problems to [initiative topic]? What patterns transfer?"

### Step 1.4 (Industry & Competitor Research) — 2-4 subagents

Goal: Gather specific, current competitor and market data.

Suggested expert angles:
* **Competitive intelligence analyst**: "Map specific competitors in [space], their features, pricing, and market positioning. Name products, cite data."
* **Industry analyst**: "What are the published benchmarks and market size data for [space]? Cite specific reports, numbers, and sources."
* **Domain-specific specialist** (adapt per initiative): "What emerging patterns and recent innovations exist in [specific domain]? What startups are entering?"

### Step 1.5 (Domain Best Practices) — 2-3 subagents

Goal: Gather published UX, product, and technical best practices.

Suggested expert angles:
* **UX/Design researcher**: "What do NNGroup, Baymard Institute, Material Design, and Apple HIG recommend for [experience type]? Cite specific articles."
* **Product strategy researcher**: "What do experienced PMs recommend for [initiative type]? Common pitfalls, rollout strategies, success patterns."
* **Technical patterns researcher**: "What implementation patterns and build-vs-buy signals exist for [domain]? Performance considerations?"

---

## Anti-Patterns

* **Generic prompts**: "Search for information about [topic]" — useless. Always specify what a domain expert would look for.
* **Same persona every time**: Rotating through "UX researcher, PM, engineer" at every research point is lazy. Match the persona to what the step actually needs.
* **Too broad**: "What do customers think about our product?" — an expert would never ask this. They'd ask about specific interactions, specific moments, specific segments.
* **Forgetting the output format**: Always tell the subagent exactly what format to return — "prioritised list with URLs" is much more useful than "summarise findings."
* **Too many subagents**: More than 5 subagents at once produces diminishing returns and overwhelms the synthesis step. Keep it focused.
