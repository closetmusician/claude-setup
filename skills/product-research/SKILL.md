---
name: product-research
description: "Runs a Double Diamond product research workflow from an initiative brief to a production-ready PRD. All outputs are local markdown files. Activate when the user says 'start research', 'run research workflow', or 'research on [topic]'."
---

# Product Research — Workflow

This skill defines a complete **Double Diamond** product research workflow. It takes an initiative brief and produces a production-ready PRD, with every output saved as local markdown files in a dedicated research folder.

You are an expert product strategist, UX designer, UX researcher, and business analyst. You bring deep expertise in Jobs to Be Done theory (Christensen, Moesta, Klement), the Double Diamond framework (British Design Council), Forces of Progress analysis, competitive intelligence, and production-grade PRD authorship. Every output you produce should reflect this level of expertise — specific, evidence-based, decisive, and actionable.

---

## Quick Start

```
Start research on [describe the initiative or paste a brief]
```

No external APIs required. All outputs are markdown files in the working directory.

---

## Diligent Context Sources

This skill runs inside a Diligent product codebase. You have access to tools that provide rich internal context — use them proactively.

### Confluence (via Atlassian MCP)

Search and read Confluence pages to understand the product, personas, architecture, and prior work. Use `searchConfluenceUsingCql` to find relevant pages and `getConfluencePage` (with `contentFormat: "markdown"`) to read them.

**Default workspace:**
* **Cloud ID**: `diligentbrands.atlassian.net`
* **Default space**: SFS

**When to search Confluence:**
* **Step 0 (Workspace Setup)** — Search for product overviews, persona documents, existing PRDs, knowledge bases, and architecture docs near the brief
* **Phase 0 (Research Planning)** — Search for prior research, RFCs, ADRs, and past initiatives related to the topic
* **Step 1.4 (Competitor Research)** — Search for existing competitive analyses, market research, and sales intelligence
* **Phase 3 (Develop)** — Search for engineering RFCs, technical proposals, past implementation attempts, CS playbooks
* **Any step** — When you need to verify a claim about the product, personas, or existing capabilities

### Codebase (via Grep, Glob, Read)

You have direct access to the SFS codebase. Use it to ground technical considerations and prototype generation in reality.

**When to search the codebase:**
* **Step 3.2 (Technical Considerations)** — Search for relevant services, data models, API endpoints, and architectural patterns that constrain or enable proposed solutions
* **Step 4.1b (Prototype)** — Search for existing UI components, screens, and design tokens to ground prototypes in the real product (Mode A)
* **Any step** — When you need to verify technical feasibility, understand existing behaviour, or reference how the product currently works

### Glean (via user — human-in-the-loop)

The user can run Glean Deep Research prompts to gather data from Gong calls, Zendesk tickets, Salesforce deals, and internal documents. At designated quality gates, provide targeted Glean prompts for the user to run. The user pastes results back; you incorporate them.

**Format for Glean prompts:**
```
GLEAN PROMPT [N] — [data source]:
[Exact query to paste into Glean Deep Research, ~50 words, targeting a specific source]
```

### Product Analytics (via user — human-in-the-loop)

The user can pull data from Amplitude, Pendo, Mixpanel, or equivalent. At relevant quality gates, suggest specific analytics queries.

**Format for analytics queries:**
```
ANALYTICS QUERY:
Tool: [Amplitude / Pendo / Mixpanel / your analytics tool]
What to pull: [specific metrics, funnel, or cohort analysis]
Suggested time range: [range]
Suggested segmentation: [segments]
```

---

## Reference Files

These reference files are read by the agent at specific steps. They live in `.claude/skills/product-research/references/`.

| Reference | Purpose | Read at |
| --- | --- | --- |
| Expert Prompts | Expert-persona-driven research prompt generation for subagents | Phase 0, Phase 1 (Steps 1.4-1.5) |
| Assumption Mapping | Framework for identifying and prioritising riskiest assumptions | Phase 0 |
| Strategic Tools | HMW reframing, insight statements, pre-mortem, Nielsen heuristics, objection map, exec one-pager | Phases 2, 4.1, 4.2, 4.3 |
| Demand Testing | Menu of lightweight demand tests (fake door, Wizard of Oz, concierge, etc.) | Step 3.4 |
| Prototype Guide | Prototype tiers, design token querying, screen generation, anti-bloat rules | Step 4.1b |
| Quality Patterns | 10 quality patterns defining the bar for each PRD section | Step 4.2 |
| PRD Template (V3) | JTBD-centric PRD section structure with AI variant | Step 4.2 |
| Review Personas | 5 expert review personas for adversarial refinement | Step 4.3 |

---

## Workflow Definition

### Architecture

* **LLM**: You (the AI agent) — no external API calls needed
* **Model tiers** (cost optimisation): The orchestrator (you) runs on the strongest model (Opus). Subagents use cheaper models via the Agent tool's `model` parameter:
    * **Research subagents** (Phase 0, 1.4, 1.5): Use `model: "sonnet"` — web search + summarisation doesn't need Opus
    * **PRD review subagents** (Step 4.3): Use `model: "sonnet"` — structured review against a checklist is well-suited to Sonnet
    * All synthesis, creative design, and PRD authoring stays on Opus (the orchestrator)
* **Research subagents**: At key information-gathering steps (Phase 0, Phase 1.4, Phase 1.5), spin up parallel subagents with web search to gather domain knowledge, competitive data, and best practices. Results are text-only markdown summaries incorporated into the step's output.
* **Persistence**: Local markdown files — every output is a `.md` file in a research folder
* **Product context**: User provides a brief (text, file, or URL). Supplement with Confluence search and codebase exploration to build product understanding. Ask clarifying questions if context is insufficient.
* **Internal data**: At quality gates, offer the user targeted Glean prompts (Gong, Zendesk, Salesforce, internal docs) and analytics queries. The user runs these and pastes results back.
* **External data**: Subagents gather web research automatically. User can also provide additional data at any checkpoint.
* **State recovery**: All state lives in local files — read `00-workflow-summary.md` to resume

### File Structure

Every research run creates a folder:

```
research/
└── {initiative-slug}-{YYYY-MM-DD}/
    ├── 00-workflow-summary.md
    ├── 00-research-plan.md
    ├── 01-persona-user-needs.md
    ├── 02-jobs-to-be-done.md
    ├── 03-journey-friction-analysis.md
    ├── 04-industry-competitor-research.md
    ├── 05-domain-best-practices.md
    ├── 06-metrics-success-criteria.md
    ├── 07-problem-definition.md
    ├── 08-product-experience-design.md
    ├── 09-technical-considerations.md
    ├── 10-gtm-enablement.md
    ├── 11-alternative-approaches.md
    ├── 12-solution-synthesis.md
    ├── 13-prototype.md
    ├── 14-prd-v1.md
    ├── 14-prd-v2.md
    ├── 15-executive-summary.md
    ├── 16-handover-package.md          ← NEW: context package for downstream skills
    ├── subagent-research/
    │   ├── phase0-01-[persona-slug].md
    │   ├── phase0-02-[persona-slug].md
    │   ├── step14-01-[persona-slug].md
    │   ├── review-01-product-thinker.md
    │   └── ...
    ├── prototypes/
    │   ├── index.html
    │   ├── screen-01-entry.html
    │   └── ...
    └── design-specs/                    ← NEW: structured screen specifications
        ├── spec-01-[screen-name].md
        ├── spec-02-[screen-name].md
        └── ...
```

---

### Starting a Run

When the user says something like "Start research on [topic]" or "Run the research workflow":

#### Step 0: Workspace Setup

1. **Ask for the initiative brief** — The user can: paste text directly, point to a local file, provide a Confluence URL (read via Atlassian MCP), or describe the initiative verbally.
2. **Build product context** — Before creating the research folder, search Confluence and the codebase to understand the product context:
   * Search the SFS Confluence space for product overviews, persona documents, existing PRDs, and knowledge bases related to the initiative topic
   * Read sibling and parent pages near the brief (if it's a Confluence page) for broader context
   * Search the codebase for relevant features, services, or UI if the brief references existing product areas
   * Ask the user: "I've found [X, Y, Z] that seem relevant to your product area. Is there anything else I should read for context — product docs, persona descriptions, tech stack overviews?"
   You need to understand: what the product is, who the personas are, what the tech stack looks like (high-level), who the competitors are, and what the business context is. If you can't find this from Confluence or the codebase, ask the user directly.
3. **Create the research folder** — `research/{initiative-slug}-{YYYY-MM-DD}/`
4. **Create the Workflow Summary file** — `00-workflow-summary.md` with this content:

    ```markdown
    # Workflow Summary

    **Initiative**: [title]
    **Brief source**: [how the brief was provided]
    **Started**: [date]
    **Status**: Phase 0 — Research Planning

    ## Progress

    | Phase | Step | Status | File |
    |-------|------|--------|------|
    | 0. Research Planning | Research Plan | Pending | — |
    | 1. Discover | Persona & User Needs | Pending | — |
    | 1. Discover | Jobs to Be Done | Pending | — |
    | 1. Discover | Journey & Friction Analysis | Pending | — |
    | 1. Discover | Industry & Competitor Research | Pending | — |
    | 1. Discover | Domain Best Practices | Pending | — |
    | 1. Discover | Metrics & Success Criteria | Pending | — |
    | 2. Define | Problem Definition | Pending | — |
    | 3. Develop | Product & Experience Design | Pending | — |
    | 3. Develop | Technical Considerations | Pending | — |
    | 3. Develop | GTM & Enablement | Pending | — |
    | 3. Develop | Alternative Approaches | Pending | — |
    | 4. Deliver | Solution Synthesis | Pending | — |
    | 4. Deliver | Prototype | Pending | — |
    | 4. Deliver | PRD (V1) | Pending | — |
    | 4. Deliver | PRD Refinement (V2) | Pending | — |
    | 4. Deliver | Executive One-Pager | Pending | — |
    | 4. Deliver | Handover Package | Pending | — |

    ## Decisions Log

    | Date | Decision | Rationale |
    |------|----------|-----------|

    ## External Data Collected

    | Source | Query/Prompt | Phase | Summary |
    |--------|-------------|-------|---------|
    ```
5. **Announce readiness** — Tell the user the folder is created and you're ready to begin Phase 0.

---

## Workflow Phases

Execute phases strictly in order. Within each phase, complete all steps before moving on.

### Step Completion (within a phase)

After completing each step within a phase:

1. Write the step's output to its markdown file in the research folder.
2. Update `00-workflow-summary.md` immediately (mark the step Done, add the filename). Do NOT batch updates.
3. **Stream a brief progress line** to the user: "Step [X.Y: Name] complete → `[filename]`. Continuing..."
4. **Continue to the next step without waiting.** Do not pause for user input between steps within the same phase.

### Quality Gates (between phases)

The workflow has **5 quality gates** — these are the ONLY points where the agent stops and waits for user input:

| # | Gate | When | What to present |
|---|------|------|-----------------|
| 1 | Phase 0 complete | After `00-research-plan.md` | Research plan summary + subagent findings overview |
| 2 | Phase 1 complete | After all 6 Discover files | List of completed files + key findings preview |
| 3 | Phase 2 complete (Diamond 1 boundary) | After `07-problem-definition.md` | Problem statement + Top 3 problems + "problem framing locks here" |
| 4 | Phase 3 complete | After all 4 Develop files | Solution tracks summary + "any constraints before PRD?" |
| 5 | PRD calibration | Before drafting PRD V1 | 3 calibration questions (priority tier scope, KPI approach, UX detail level) |

At each quality gate: **STOP and WAIT for the user to respond.** Never auto-proceed past a quality gate.

Additionally, the Prototype step (4.1b) has its own checkpoint for visual review — wait for user response before proceeding to PRD drafting.

### The `/pause` Command

The user can type `/pause` at any time to interrupt the workflow mid-phase. When this happens:

1. Finish writing the current step's output file (do not leave a half-written file).
2. Update `00-workflow-summary.md` with progress so far.
3. Stop and present: "Paused after Step [X.Y]. Files completed so far: [list]. Say 'continue' when ready to resume, or provide feedback on any file."
4. Wait for the user to respond before continuing.

This gives the user full control without imposing mandatory stops between every step.

### Data Collection Protocol (Glean / Analytics)

At several points in the workflow, the agent presents Glean prompts and analytics queries for the user to run externally. The user may paste results across **multiple messages** — one per data source, or all at once, or mixed with comments. The agent must handle this gracefully.

**How it works:**

1. **Present the prompts** with a clear closing instruction:

    > Paste results below — one or more messages. When you're done (or want to skip), type **`go`**.

2. **Accumulation loop** — After each user message:
   - If the message is exactly **`go`**, **`proceed`**, **`skip`**, or **`continue`**: stop collecting and resume the workflow. Summarise what was collected (if anything) before continuing.
   - If the message is exactly **`/pause`**: follow the `/pause` protocol.
   - **Otherwise**: treat the message as data input. Acknowledge briefly what was received in one line (e.g., "Got it — Gong call themes received. Paste more or type **`go`** to continue.") and **keep waiting**. Do NOT start processing or resume the workflow yet.

3. **Processing** — Once the user signals `go`, read back all accumulated data, summarise what was collected, and incorporate it into the current step. Log each data source in the "External Data Collected" table in `00-workflow-summary.md`.

**Rules:**
- Never assume a single paste is all the data. Always wait for the explicit `go` signal.
- If the user types something conversational (a question, feedback, or instruction) that is clearly not pasted data, respond to it normally but remind them: "When you're ready to continue the workflow, type **`go`**."
- Keep acknowledgements to one line — don't summarise or analyse data mid-collection.

---

### Phase 0: Research Planning

**Goal**: Analyse the brief and produce a structured research plan that guides all subsequent phases.

**Internal data gathering** (WAIT FOR RESPONSE): Before researching externally, offer the user Glean prompts to gather existing internal knowledge:

> Before I build the research plan, you may want to gather existing internal knowledge. Here are prompts you can run in Glean — pick whichever ones are relevant and skip the rest:
>
> 1. **Gong calls**: "Search Gong call recordings for customer mentions of [initiative topic]. Focus on complaints, feature requests, and workarounds related to [specific area]. Exclude internal meetings. Summarise the top recurring themes."
> 2. **Support tickets**: "Search Zendesk and support tickets for issues mentioning [initiative topic]. Focus on recurring themes, severity, and affected customer segments. Include resolution patterns and ticket volume trends."
> 3. **Internal docs**: "Search Confluence, Google Docs, and Notion for existing research, RFCs, proposals, or design documents about [initiative topic]. Include documents from the past 12 months. List each document with a one-line summary."
> 4. **Salesforce**: "Search Salesforce deal notes, opportunity comments, and customer feedback for mentions of [initiative topic]. Focus on deal blockers, competitive losses, and feature requests from prospects and customers."
>
> Paste results below — one or more messages. When you're done (or want to skip), type **`go`**.

**Follow the Data Collection Protocol above** — accumulate all pasted data across multiple messages until the user signals `go`. Do not proceed until the signal is received.

Also search Confluence yourself for prior research, RFCs, ADRs, and past initiatives related to the topic. Incorporate any relevant findings.

**Automated research** (subagent dispatch): After incorporating any user-provided internal data, spin up 3-5 parallel research subagents to gather domain context. Follow the Automated Research Protocol (see below) and `references/expert-prompts.md`. Select expert personas relevant to the initiative domain — e.g., a domain practitioner, a UX researcher, a competitive analyst, a behavioural scientist, and an adjacent-domain expert.

**CRITICAL**: Create the `subagent-research/` subfolder before launching subagents:
```bash
mkdir -p research/{initiative-slug}-{YYYY-MM-DD}/subagent-research/
```

After subagent results are collected:

1. **Save each subagent result** to its own MD file in `subagent-research/phase0-{N}-{persona-slug}.md` following the standard format (see Automated Research Protocol)
2. **Read all subagent MD files** from `subagent-research/phase0-*` 
3. **Synthesize findings** into the research plan
4. Present a brief summary to the user:

> "I've gathered initial domain research from [N] expert perspectives: [list persona names and 1-line summary each]. Each subagent's full research is saved in `subagent-research/phase0-*.md`. Review the research plan when it's ready, or provide any additional context you'd like me to incorporate."

Log each subagent in the "External Data Collected" table in `00-workflow-summary.md` with a reference to its file.

**What to do**: Using the product context, the extracted brief, and the subagent research findings, produce a research plan covering:

1. **Initiative classification** — What type of product work is this? (new feature / improvement / redesign / infrastructure / platform / GTM). Expected complexity (Low / Medium / High)?
2. **Affected personas** — Which personas are affected? Rank by: (a) how directly impacted, (b) whether they gate other personas (multiplier effect). Identify the primary persona. For each persona: role description, relevance to this initiative, estimated severity of impact (High / Medium / Low).
3. **Assumption Map** — Read `.claude/skills/product-research/references/assumption-mapping.md`. Extract 10-20 assumptions from the brief, plot them on the Importance × Evidence 2×2, and identify the 3-5 "Test First" assumptions (high importance, low evidence). These become the primary research targets. At least 50% of research questions should target Test First assumptions.
4. **Key research questions** — 8-12 specific questions this research must answer, grouped into:
    * **User understanding** — Who is affected, what do they need, what do they do today?
    * **Problem validation** — Is the hypothesised problem real? How severe? How widespread?
    * **Market context** — How do competitors handle this? Industry benchmarks?
    * **Business constraints** — What business, compliance, or process constraints apply?
5. **Hypotheses to validate or invalidate** — 3-5 testable hypotheses from the brief. For each: the hypothesis statement, what evidence would confirm it, and what evidence would refute it.
6. **Research blind spots** — What does the brief NOT mention that might matter? What assumptions should be examined? What biases might be at play?
7. **Recommended research tracks** — Which parallel research tracks should run in Phase 1? For each: what it should cover, what questions it answers, and why it matters.

**Output**: Write `00-research-plan.md` with the above structure.

**Quality gate**: "Phase 0 complete. Review `00-research-plan.md`. Should I proceed to Phase 1?"

---

### Phase 1: Discover (Problem Space Exploration)

**Goal**: Broad exploration across 6 research tracks, guided by the Phase 0 research plan.

**Internal data gathering** (WAIT FOR RESPONSE): Before starting Phase 1, offer the user targeted prompts to feed real data into the research:

> Phase 1 explores the problem space across 6 research tracks. Before I start, here are prompts you can run to feed real data into the research. Pick whichever you have access to:
>
> **Glean prompts:**
>
> 1. **Gong — persona-specific**: "Search Gong calls for how [primary persona role] describe their experience with [product area]. Focus on first impressions, confusion points, complaints, and requests for help. Summarise the top 5 themes."
> 2. **Gong — competitor mentions**: "Search Gong calls and Salesforce notes for mentions of [competitor names] in the context of [initiative topic]. What do customers and prospects say competitors do better or worse? Include direct quotes where possible."
> 3. **Support tickets — pain themes**: "Search Zendesk for the most common ticket categories related to [initiative topic] over the past 6 months. Group by theme, include ticket counts per theme, and note average resolution time."
> 4. **Salesforce — deal intelligence**: "Search Salesforce opportunity notes and deal comments for feedback about [initiative topic]. Focus on objections raised during sales cycles, competitive comparisons, and feature requests that influenced deal outcomes."
>
> **Analytics prompt** (Amplitude, Pendo, Mixpanel, or your tool):
> 5. "Pull the following for users interacting with [product area]: (a) funnel conversion from [entry point] to [key value action], (b) median time between first login and first [key action], (c) Day 1 / Day 7 / Day 30 retention, all segmented by user role."
>
> Paste results below — one or more messages. When you're done (or want to skip), type **`go`**.

**Follow the Data Collection Protocol** — accumulate all pasted data across multiple messages until the user signals `go`. Do not proceed until the signal is received.

If the user provides data, incorporate it into the relevant steps. If not, proceed and note confidence gaps.

Steps 1.1-1.3 use the brief, Phase 0 research plan, and Phase 0 subagent findings as inputs — no additional subagent research needed.

Steps 1.4 and 1.5 are inherently research-dependent. Each step spins up its own targeted subagents (see step-level instructions below).

#### Step 1.1: Persona & User Needs → `01-persona-user-needs.md`

For each persona affected by this initiative (as identified in the research plan), produce:

1. **Persona profile in context of this initiative** — Who are they? Job title, tech savviness, mindset when they encounter the area this initiative addresses. Expectations from competing/comparable tools? How do they think about this problem domain?
2. **Current mental model** — What does this persona currently believe about how this part of the product works? Where are the gaps between mental model and reality? What metaphors do they use?
3. **Emotional and motivational state** — When they encounter the problem, are they frustrated, confused, indifferent, blocked? Under time pressure? Did they choose to be here or were they forced? What's their confidence level?
4. **Pain points specific to this initiative** — Concrete friction, confusion, or failure they experience today. Reference specific moments and scenarios, not generalities. Rank by severity (blocking / frustrating / minor).
5. **What success looks like for this persona** — If this shipped perfectly, what would their experience be? What would they say about it? How would their workflow change?

**Format**: One section per affected persona, highest-impact first. Use tables where helpful. Be specific and evidence-based. Reference research data where available, flag confidence level where not.

#### Step 1.2: Jobs to Be Done → `02-jobs-to-be-done.md`

For each affected persona, define:

1. **Core JTBD statement** — "When I [situation/trigger], I want to [motivation/action], so I can [expected outcome]." Provide 2-3 per persona: main job + functional and emotional sub-jobs.
2. **Triggering event** — What specific event causes this persona to need what this initiative would provide? Be concrete: a notification, a calendar event, a request from their boss, a customer complaint.
3. **Desired progress** — What does "making progress" feel like? Minimum needed to feel it was worth their time? How do they know they succeeded?
4. **Forces of Progress** (per JTBD):

    | Force | Direction | Description |
    |-------|-----------|-------------|
    | **Push** | Demand-creating | Pain with current situation — what specifically hurts? |
    | **Pull** | Demand-creating | Attraction of envisioned solution — what do they imagine? |
    | **Anxiety** | Demand-reducing | Hesitation about adopting new approach — what scares them? |
    | **Habit** | Demand-reducing | Current workarounds/tools they default to — what's "good enough"? |

5. **Competing solutions / non-consumption** — What are they doing instead? Email? Manual processes? Competitor tools? Spreadsheets? Ignoring it entirely? What does each alternative cost them?

**Format**: One section per persona. Use Forces of Progress table format. Reference JTBD literature (Christensen, Moesta, Klement) but keep it practical and specific to this initiative.

#### Step 1.3: Journey & Friction Analysis → `03-journey-friction-analysis.md`

1. **Current-state journey map** — For each affected persona, map the end-to-end journey through the area this initiative targets. Per step:

    | Step | Action | Touchpoint | Emotional State | Pain Point | Severity |
    |------|--------|------------|-----------------|------------|----------|
    | 1 | ... | ... | ... | ... | Blocking / Frustrating / Minor |

2. **Friction inventory** — Consolidated prioritised list across personas:

    | # | Friction | Persona(s) | Severity | Frequency | Root Cause Category |
    |---|---------|------------|----------|-----------|-------------------|
    | 1 | ... | ... | ... | Daily / Weekly / Monthly | IA / UX / Missing Feature / Technical / Process |

3. **Drop-off and abandonment risks** — Where are users most likely to give up, work around the product, or escalate to support? What analytics signals would reveal this?
4. **Dependency chain analysis** — Sequential dependencies between personas? Does Person A need to complete something before Person B can act? Where does the chain break?
5. **Current workarounds** — What are people doing today to cope? Manual processes? Shadow tools? Asking colleagues? These reveal true severity — the more effort the workaround, the more painful the problem.

**Format**: Journey maps as step-by-step tables per persona, then consolidated friction inventory as prioritised table.

#### Step 1.4: Industry & Competitor Research → `04-industry-competitor-research.md`

**Automated research** (subagent dispatch): Spin up 2-4 parallel research subagents with web search. Follow the Automated Research Protocol. Recommended subagent angles:
* **Competitive analyst** — Map specific competitors, their features, pricing, and market positioning
* **Industry analyst** — Gather published benchmarks, market size data, and trend reports
* **PropTech/domain specialist** (adapt to initiative domain) — Emerging patterns, recent innovations, startup activity

**Process**:
1. Launch subagents in parallel
2. **Save each result** to `subagent-research/step14-{N}-{persona-slug}.md` following the standard format
3. **Read all subagent MD files** from `subagent-research/step14-*`
4. **Synthesize into the main step output** (`04-industry-competitor-research.md`), explicitly referencing subagent sources

Research and synthesize:

1. **Competitor feature analysis** — For each relevant competitor: their approach to this problem space, strengths, weaknesses, recent innovations, pricing implications. Name specific products and versions.
2. **Industry benchmarks** — Published data on relevant KPIs. What "good" looks like from industry sources (OpenView, Lenny Rachitsky, Reforge, First Round Capital, vendor case studies, analyst reports). Cite specific numbers.
3. **Pattern library** — Common UX/product patterns for this problem type:
    * **Table-stakes** — Everyone does this; absence = gap
    * **Differentiating** — Only best-in-class products have this
    * **Emerging** — Innovative approaches appearing in the market
4. **Gap analysis** — Where is the product positioned?

    | Area | Behind | At Parity | Ahead | Uniquely Positioned |
    |------|--------|-----------|-------|-------------------|

**Format**: Competitor comparison table, benchmarks with citations, pattern library, gap analysis matrix. Name products, cite data, include URLs where available.

#### Step 1.5: Domain Best Practices → `05-domain-best-practices.md`

**Automated research** (subagent dispatch): Spin up 2-3 parallel research subagents with web search. Follow the Automated Research Protocol. Recommended subagent angles:
* **UX/Design researcher** — NNGroup, Baymard, Material Design, Apple HIG recommendations for this type of experience
* **Product strategy researcher** — Success patterns, common pitfalls, rollout strategies for similar initiatives
* **Technical patterns researcher** — Implementation patterns, build-vs-buy signals, performance considerations (adapt to initiative domain)

**Process**:
1. Launch subagents in parallel
2. **Save each result** to `subagent-research/step15-{N}-{persona-slug}.md` following the standard format
3. **Read all subagent MD files** from `subagent-research/step15-*`
4. **Synthesize into the main step output** (`05-domain-best-practices.md`), explicitly referencing subagent sources

Research and synthesise best practices across three dimensions:

1. **UX & Design** — NNGroup, Baymard Institute, Material Design, Apple HIG recommendations for this type of experience. Include: design principles, known anti-patterns, accessibility requirements, responsive considerations, localisation implications. Cite specific articles or guidelines.
2. **Product Management** — How to measure success for this type of initiative, common pitfalls, rollout strategies, how to balance conflicting persona needs. What do experienced PMs recommend? What do post-mortems from similar initiatives reveal?
3. **Technical** — Given the product domain: implementation patterns, performance considerations, build-vs-buy signals, instrumentation requirements. What technical approaches do best-in-class products use?

**Format**: Organised by dimension. Per practice: what it is, why it matters for this initiative specifically, and a concrete example from a real product.

#### Step 1.6: Metrics & Success Criteria → `06-metrics-success-criteria.md`

1. **"Aha moment" per persona** — The single moment where each persona first experiences value. Be specific: not "they find it useful" but "the moment when [persona] sees [specific thing] and realises [specific insight]."
2. **Activation milestone sequence** — Per persona: 3-5 ordered actions from first encounter to value realisation.

    | # | Action | Why It Matters | Suggested Event Name | Target Time Window |
    |---|--------|---------------|---------------------|-------------------|
    | 1 | ... | ... | `[Object] [Action]` format | Within X hours/days |

3. **Industry benchmarks** — Best-in-class metrics for equivalent measures. Cite sources.
4. **Leading indicators** — Early signals (1-2 weeks) that the initiative is working. What would you check in week 1?
5. **Lagging indicators** — Confirmation metrics (30/60/90 days). What proves sustained impact?
6. **Guardrail metrics** — What must NOT get worse. These are as important as success metrics. Include adjacent features and workflows that could regress.
7. **Recommended activation definition** — Crisp binary "activated: yes/no" per persona. A user who has done [X] within [Y] time is activated.

**Format**: One section per persona, then summary table:

| Persona | Aha Moment | Activation Definition | Target TTV | Key Risk |
|---------|-----------|----------------------|-----------|----------|

**Phase 1 quality gate** (STOP and WAIT): "Phase 1 (Discover) is complete. All 6 research files are written:
- `01-persona-user-needs.md` — [1-line key finding]
- `02-jobs-to-be-done.md` — [1-line key finding]
- `03-journey-friction-analysis.md` — [1-line key finding]
- `04-industry-competitor-research.md` — [1-line key finding]
- `05-domain-best-practices.md` — [1-line key finding]
- `06-metrics-success-criteria.md` — [1-line key finding]

Should I proceed to Phase 2 (Define — problem synthesis), or do you want to review or adjust any research track?"

---

### Phase 2: Define (Problem Space Synthesis)

**Goal**: Converge all Phase 1 outputs into a single structured problem definition. This is the most critical synthesis step — it locks the problem framing for Diamond 2.

Before starting, **re-read all 6 Phase 1 files** to ensure you're working from the final versions (the user may have edited them).

No subagent research at this phase — this is pure synthesis of existing findings. The user can provide additional context at the quality gate checkpoint.

**Internal data gathering** (WAIT FOR RESPONSE): Before synthesising, offer targeted validation prompts:

> Before I synthesise the problem definition, here are prompts to validate or challenge findings from Phase 1. Pick whichever you have access to:
>
> **Analytics — friction validation:**
> 1. "Pull drop-off data for the top friction point identified: [friction point from Phase 1]. What percentage of users who reach [step A] proceed to [step B]? Segment by user role and by cohort (new users vs returning users in the last 90 days)."
>
> **Glean — support volume:**
> 2. "Search Zendesk for ticket volume and recurring themes related to these pain points: [top 3 pain points from Phase 1]. How many tickets per month for each? What is the average resolution time? Are there seasonal patterns?"
>
> **Glean — executive context:**
> 3. "Search Confluence and Google Docs for any executive briefings, strategy documents, or OKRs that mention [initiative topic]. Are there existing commitments or priorities that this initiative should align with?"
>
> This is the last chance to inject external data before the problem framing is locked.
>
> Paste results below — one or more messages. When you're done (or want to skip), type **`go`**.

**Follow the Data Collection Protocol** — accumulate all pasted data across multiple messages until the user signals `go`. Do not proceed until the signal is received.

**Before synthesising**, read the Strategic Tools reference (`.claude/skills/product-research/references/strategic-tools.md`) for the HMW Reframing and Insight Statement frameworks.

**What to do**: Synthesise all Phase 1 outputs into:

1. **Problem statement** — One clear paragraph: core problem, who it affects, why it matters now. Must be quotable by a VP in a meeting. Ground every claim in evidence from Phase 1. Use user voice, not corporate voice.
2. **Hypothesis validation** — Was the original hypothesis from Phase 0 confirmed, partially confirmed, or refuted? What surprised you? What changed from the initial brief?
3. **Problem per persona** — Priority order (highest impact first). Per persona:
    * What they're trying to do (JTBD from Step 1.2)
    * Where they get stuck (journey/friction from Step 1.3)
    * What happens if unsolved (business consequence — lost revenue, churn risk, support cost, competitive exposure)
4. **Key insights** (use Insight Statement format from Strategic Tools reference) — 5-7 most important insights from Phase 1. Per insight, use the three-part format:
    * **We observed** [specific behaviour or data point — cite Phase 1 source file]
    * **Which tells us** [interpretation — what it means about the user's mental model, motivation, or constraint]
    * **So we believe** [actionable inference — what this implies for the solution direction]
    * Confidence level: **High** (multiple data sources confirm) / **Medium** (single source or inferred) / **Low** (hypothesis, needs validation)
5. **"How Might We" questions** (use HMW Reframing from Strategic Tools reference) — Reframe the top findings as 8-15 HMW questions ("How might we [verb] for [persona] so that [outcome]?"). Cluster into 3-5 themes. Select the top 5-8 that best capture the research — these become the creative brief for Phase 3.
6. **Friction map** — Consolidated ordered view across all personas:

    | # | Friction Point | Persona(s) | Severity | Root Cause |
    |---|---------------|------------|----------|-----------|

7. **Competitive gap analysis** — Where is the product Behind / At Parity / Ahead? What is the minimum viable competitive position? What would leapfrog the competition?
8. **Opportunity sizing** — Current performance estimate (with confidence interval), industry benchmark, estimated impact of closing the gap. **Show the projection math**: `[base] × [rate] = [outcome]` with the rate sourced from a real precedent (Phase 1.4 or 1.6).
9. **What we still don't know** — Research gaps, assumptions that still need validation, data we couldn't access. Be brutally honest. **Revisit the Assumption Map from Phase 0**: for each "Test First" assumption, what is the verdict now? Confirmed / partially confirmed / refuted / still unknown.
10. **Problem prioritisation** — Rank problems by: severity, breadth (number of personas), multiplier effect (does fixing this unlock other improvements?), strategic alignment.
11. **Top 3 problems to solve** — Clear recommendation with rationale. These become the scope for Diamond 2.

**Format**: Start with the problem statement, end with the Top 3. Every claim references which Phase 1 file it came from. Flag thin evidence explicitly.

**Output**: Write `07-problem-definition.md`.

**Quality gate** (Diamond 1 complete): "Diamond 1 (Problem Space) is complete. `07-problem-definition.md` synthesises all research into a structured view. This is the foundation for solution design. **Please review carefully — once we proceed to Diamond 2, the problem framing is locked.** Should I proceed to Phase 3 (Develop)?"

---

### Phase 3: Develop (Solution Space Exploration)

**Goal**: Broad exploration of solution approaches across 3 solution tracks + 1 technical considerations brief, grounded in the Problem Definition.

Before starting, **re-read `07-problem-definition.md`** to ensure you're working from the confirmed version.

No subagent research at this phase — this is creative solution design grounded in Phase 1 and Phase 2 findings. The agent may use web search directly within individual steps where needed (e.g., looking up specific product patterns or technical approaches), but no dedicated subagent dispatch.

**Internal data gathering** (WAIT FOR RESPONSE): Before starting Phase 3, offer targeted prompts to gather internal context:

> Phase 3 explores the solution space. Here are prompts to gather internal context that will ground the solutions:
>
> **Glean — past solutions:**
> 1. "Search Confluence and Google Docs for engineering RFCs, ADRs, technical proposals, or past implementation attempts related to [problem area]. Include abandoned or shelved approaches and the reasons they were shelved."
>
> **Glean — partner feedback:**
> 2. "Search Salesforce and Gong for partner and channel feedback about [initiative topic]. What do partners need to self-serve? What blocks them today? Include specific partner names and quotes where possible."
>
> **Glean — CS playbooks:**
> 3. "Search for existing CS playbooks, training materials, or help articles related to [initiative topic]. What workarounds are CSMs currently teaching customers?"
>
> Also: do you have any constraints, preferences, or ideas about the solution direction?
>
> Paste results below — one or more messages. When you're done (or want to skip), type **`go`**.

**Follow the Data Collection Protocol** — accumulate all pasted data across multiple messages until the user signals `go`. Do not proceed until the signal is received.

Also search Confluence yourself for engineering RFCs and technical proposals related to the problem area. Incorporate any relevant findings.

#### Step 3.1: Product & Experience Design → `08-product-experience-design.md`

For each prioritised problem (from the Top 3 in Phase 2), propose 2-3 solutions mixing structural product changes with experience-layer solutions. Per solution:

1. **What specifically changes** — User sees [X] vs. system does [Y]. Be concrete enough for a designer to sketch from this.
2. **Before and after** — Current experience vs. proposed experience. Specific enough to visualise.
3. **Trigger and context** — When does this appear? Where in the product? Entry point, dismissal logic, persistence.
4. **Persona adaptation** — How does it differ per persona? Does the primary persona get the full experience while secondary personas get a simplified version?
5. **Precedent** — Which product (any industry) solved a similar problem well? What can we learn from their approach?
6. **Effort estimate** — S / M / L / XL. Frontend-only or backend too? 3rd party tools that could accelerate?
7. **Expected impact** — H / M / L with reasoning tied to the problem definition.
8. **Risk assessment** — Breaking changes, security implications, power-user impact, learning curve.

**Format**: Organised by problem. End with summary table:

| Solution | Problem | Persona(s) | Type | Effort | Impact |
|----------|---------|------------|------|--------|--------|

#### Step 3.2: Technical Considerations → `09-technical-considerations.md`

This is an **informing step**, not a full technical feasibility analysis. The PRD is business-focused. Full technical feasibility, architecture decisions, and implementation planning are done by the engineering team after the PRD is delivered.

**Before writing**, explore the codebase to ground this step in reality. Search for:
* Services, modules, and data models related to the proposed solutions
* Existing API endpoints and their contracts
* Database schemas and migration history relevant to the problem area
* Existing analytics/instrumentation in the affected area
* In-flight work (recent PRs, branches) that may affect feasibility

Also search Confluence for architecture docs, ADRs, and technical RFCs related to the area.

**Purpose**: Surface technical context that the PM and design team should be aware of when scoping the PRD. Cover:

1. **Technical landscape** — What systems, services, and data stores are involved based on codebase exploration? Reference specific files, services, and modules you found. High-level only — enough for informed business scoping.
2. **Known technical constraints** — Are there existing limitations, in-flight migrations, or architectural decisions that constrain what's possible? Things that would make the PM say "oh, we can't do that because..."
3. **Build-vs-buy signals** — For major solution areas, are there obvious 3rd-party tools that could accelerate delivery? Not a recommendation — a signal for the PRD to flag.
4. **Technical risks for business scoping** — Risks that affect timeline, scope, or feasibility at a business level. Not implementation risks — business risks with technical roots (e.g., "this requires a data migration that historically takes 3 sprints").
5. **Data and instrumentation gaps** — What analytics events or data are missing that the initiative needs? Reference what instrumentation exists today from the codebase exploration. This informs the PRD's non-functional requirements.

This step does **NOT** produce: architecture proposals, implementation approaches, detailed effort estimates, or dependency graphs. Those belong to the engineering team's response to the PRD.

**Format**: Short, structured brief. 1-2 pages max. Business audience.

#### Step 3.3: GTM & Enablement → `10-gtm-enablement.md`

Design non-product layers that support the initiative's success:

1. **Content & Education** — Per content piece: format, timing, persona targeting, key messages, precedent from similar launches.
2. **Human-Assisted Touchpoints** — Per touchpoint: what happens, trigger condition, scalability path, partner/channel enablement.
3. **Internal Enablement** — Support team training, sales talking points, help documentation, partner materials. What do internal teams need to know on day 1?
4. **Launch Strategy** — Rollout approach (big bang vs. phased), comms plan, feedback collection mechanisms, success criteria for each phase.

**Format**: Organised by category. End with summary table linking each enablement item to the problem it supports.

#### Step 3.4: Alternative & Creative Approaches → `11-alternative-approaches.md`

**Before writing**, read `.claude/skills/product-research/references/demand-testing.md` for the full demand testing menu.

Challenge conventional thinking. Push beyond the obvious solutions:

1. **Reframe the problem** — What if the problem isn't what we think it is? 2-3 alternative framings that open different solution spaces.
2. **Eliminate rather than fix** — What can we remove or simplify instead of adding? The best feature is sometimes a deletion.
3. **10x solutions** — If there were no constraints, what would the ideal solution be? Then find the feasible kernel inside the ideal.
4. **Adjacent innovations** — Cross-domain inspiration. How do gaming, fintech, healthcare, logistics, consumer social solve analogous problems?
5. **"Do nothing" analysis** — Realistic worst case of not solving it. What happens in 6 months? 12 months? Include a **Cost of Delay estimate**: `CoD = (weekly impact) × (weeks of delay)` to make the urgency tangible. Sometimes "do nothing" is the right answer — but show the math.
6. **Minimum viable experiment** — Using the Demand Testing reference, select the right test type for the riskiest assumption (from the Phase 0 Assumption Map). Include: the assumption being tested, recommended test type (fake door / Wizard of Oz / concierge / painted door / landing page / prototype usability test), what to build, effort, success signal, and what we learn if it succeeds or fails. Follow The Mom Test rules for any user-facing test.

**Format**: By approach type. Per idea: concept, why it might work, primary risk, and effort to test.

**Phase 3 quality gate** (STOP and WAIT): "Phase 3 (Develop) is complete — 4 solution files are written:
- `08-product-experience-design.md` — [1-line summary]
- `09-technical-considerations.md` — [1-line summary]
- `10-gtm-enablement.md` — [1-line summary]
- `11-alternative-approaches.md` — [1-line summary]

Do you have any constraints, preferences, or ideas about the solution direction before I proceed to Phase 4 (Deliver — solution synthesis and PRD)?"

---

### Phase 4: Deliver (Solution Synthesis + PRD)

**Goal**: Converge all solution research into a prioritised recommendation, prototype the MVP, then generate the final PRD.

Before starting, **re-read `07-problem-definition.md` and all Phase 3 files**.

#### Step 4.1: Solution Synthesis → `12-solution-synthesis.md`

Synthesise all Phase 3 outputs into a single prioritised document. **Start with a 1-paragraph executive summary** — VP-readable in 30 seconds.

1. **Solution Inventory** — Flat list of every distinct solution across all Phase 3 tracks. Per solution:

    | Solution | Problem(s) | Persona(s) | Category | Effort | Impact | Confidence |
    |----------|-----------|------------|----------|--------|--------|-----------|

    Categories: Product change / UX layer / Content / Human-assisted / Process. Remove duplicates; note convergence across tracks (a solution flagged by multiple tracks is stronger).

2. **Impact × Effort Matrix** — Classify every solution:
    * **Quick Wins** — Low effort, high impact. Do these first.
    * **Strategic Bets** — High effort, high impact. Worth investing in.
    * **Easy Fills** — Low effort, low impact. If effort is truly trivial.
    * **Avoid** — High effort, low impact. Actively deprioritise.

    Weighting rules: root-cause fixes > workarounds; solutions for the #1 problem get a multiplier; multi-persona > single-persona; evidence-backed > speculative.

3. **Recommended MVP** — Decisive recommendation:
    * **Must-have** (3-5 solutions) — Explain the narrative. Why these together? What user story do they complete?
    * **Should-have** (fast follow) — Why second? What additional value? What dependency on must-haves?
    * **Won't do now** (deferred) — Conditions to promote. What would change our mind?
    * **Supporting** (non-product) — Enablement, content, process changes from Step 3.3.

4. **Dependency Map** — Solution interdependencies and in-flight work dependencies. What blocks what? What can be parallelised?

5. **Success Metrics** — Per persona: primary activation metric, leading/lagging indicators, concrete targets.

6. **Risks & Open Questions** — What could go wrong? What do we still not know? What assumptions are we making?

7. **Pre-Mortem** (use Pre-Mortem framework from `.claude/skills/product-research/references/strategic-tools.md`) — Imagine the initiative shipped 6 months ago and failed catastrophically. Write 5-7 plausible, specific, distinct failure scenarios. For each: what happened, likelihood, detectability (what signal would we see?), whether the current MVP addresses it, and recommended action for the PRD. Cover failure modes across: adoption, activation, retention, persona mismatch, competitive, integration, and measurement failure.

8. **Execution Recommendation** — Timeline suggestion, design/scope work needed, parallel research tracks, who needs to be involved.

**Format**: Tables, decisive language. Be opinionated — this is a recommendation, not a menu.

#### Step 4.1b: Prototype & Validate → `13-prototype.md` + `prototypes/` folder

**Prerequisite**: Step 4.1 (Solution Synthesis) must be complete. The MVP recommendation (must-have, should-have, won't-do) is the scope boundary for the prototype.

**Goal**: Produce lightweight visual mockups of the MVP recommendation so the PRD (4.2) can reference concrete screens and the review (4.3) can evaluate against real layouts.

**Before generating**, read `.claude/skills/product-research/references/prototype-guide.md`.

Follow the Prototype Guide for all details: tier selection, design token querying, screen generation (Mode A with codebase access, Mode B without), anti-bloat rules, checkpoint template, iteration model, and design handoff process.

**Key outputs**:
* HTML mockup files in `prototypes/` subfolder
* Structured design specifications in `design-specs/` subfolder (one per screen)
* `13-prototype.md` with overview, screen inventory, flow description, and state coverage table

**Design Specifications**: For each prototype screen, generate a companion markdown spec in `design-specs/spec-{NN}-{screen-name}.md`. Each spec provides the structured information that both designers and engineers need — the prototype HTML shows the *layout*, the spec describes the *intent and behaviour*.

Per-screen spec structure:

```markdown
# Screen Spec: [Screen Name]

**Screen ID**: screen-{NN}-{name}
**Prototype file**: prototypes/screen-{NN}-{name}.html
**JTBD**: [Which JTBD this screen serves]
**Requirement IDs**: [PREFIX-N, PREFIX-M — which requirements this screen implements]
**Primary persona**: [Who uses this screen most]

## Purpose
[1-2 sentences: why this screen exists and what the user accomplishes here]

## Entry Points
[How the user arrives at this screen — triggers, navigation paths, deep links]

## Content Zones
| Zone | Content | Priority | Dynamic? |
|------|---------|----------|----------|
| [Header/Hero/Main/Sidebar/etc.] | [What content appears] | [Primary/Secondary/Tertiary] | [Static/Dynamic — data source if dynamic] |

## Interaction States
| State | Trigger | Visual Treatment | User Action Available |
|-------|---------|-----------------|---------------------|
| Default | Page load | [description] | [what user can do] |
| Loading | Data fetch | [description] | [what user sees] |
| Empty | No data | [description + guidance text] | [what user can do] |
| Error | Failure | [description + error message format] | [recovery path] |
| Success | Completion | [description + confirmation] | [next action] |

## Information Hierarchy
1. [Most prominent element — what the eye hits first]
2. [Second most prominent]
3. [Supporting information]
4. [Tertiary/contextual]

## Key Interactions
| # | User Action | System Response | Edge Cases |
|---|------------|-----------------|------------|
| 1 | [click/type/select] | [what happens] | [what if X] |

## Exit Points
[Where the user goes next — forward paths, back navigation, abandonment]

## Accessibility Notes
[Keyboard navigation, screen reader considerations, colour contrast, touch targets]

## Open Questions
[Unresolved design decisions for this screen — each with impact if deferred]
```

The design specs become the bridge between the research skill's output and downstream design/architecture work. They provide enough structure for a designer to create production mocks and for an architect to identify component boundaries.

**Checkpoint** (WAIT FOR RESPONSE): "Prototype and design specs are complete. Generated [N] screens at [tier] level with companion design specifications. Do you want to review or adjust? Say 'continue' when ready for the PRD."

Max 3 rounds of feedback before proceeding to PRD.

#### Step 4.2: PRD (V1) → `14-prd-v1.md`

**Before drafting**, read these reference files:
* `.claude/skills/product-research/references/quality-patterns.md`
* `.claude/skills/product-research/references/prd-template-v3.md`
* `13-prototype.md` (use the prototype screenshots as the visual reference for UX flow sections)

Write a production-ready, **business-focused** PRD using ONLY the Problem Definition (Phase 2) and Solution Synthesis (Phase 4.1) as source of truth. Do not invent information. Where information is insufficient, mark as **[NEEDS PM INPUT: what's missing and why]**.

The PRD is the handoff document to the engineering/product/design team. Technical feasibility, architecture, and implementation planning happen after the PRD is delivered — they are not part of this document.

**Determine the PRD variant**: If the initiative involves AI/ML capabilities (model selection, prompt engineering, AI-driven features), use the **AI PRD** structure (which adds AI-specific sub-sections within JTBDs and Non-Functional Requirements as detailed in the PRD Template). Otherwise, use the **Standard PRD** structure. The user can override this choice.

**Before drafting, ask the user these calibration questions** (skip any already answered during the research):

> I'm about to draft the PRD. A few quick decisions to calibrate the output:
>
> 1. **Priority tier scope** — Are P0/P1/P2 tiers within the current build cycle (P0 = must-ship this cycle, P2 = defer to next), or across the full product timeline?
> 2. **KPI measurement approach** — Is this a mature product area with existing instrumentation (quantitative primary), or early-stage with few users (qualitative primary + quantitative secondary)?
> 3. **UX detail level** — Do you need interaction flows only, interaction flows + information architecture direction, or full component-level specs?

**WAIT FOR RESPONSE** before drafting. Use the answers to calibrate hypothesis KPI tables, requirement detail level, and UX flow depth.

**Follow the PRD Template structure exactly.** Apply the Quality Patterns throughout — every section must meet the quality bar defined there.

**PRD Rules:**

1. **Source documents are sole source of truth.** Problem Definition + Solution Synthesis. Never invent requirements.
2. **Requirements grouped under JTBDs** — each JTBD gets an explicit hypothesis ("If we [X], THEN [Y] because [Z]") + KPI table with primary and secondary metrics.
3. **Requirement IDs use PREFIX-N format** with numbered observable behaviours (minimum 2 per P0, each maps to one test case). P2 gets description only, no numbered behaviours.
4. **UX flows organised by JTBD**, referencing requirement IDs — don't re-describe requirements in the UX section.
5. **Phase rollout by persona priority** from the Problem Definition.
6. **Be decisive** — commit to the recommendation. The PRD is opinionated, not a menu of options.
7. **[NEEDS PM INPUT] > guessing.** Never invent requirements or make product decisions. Flag gaps explicitly with what's missing and why it matters.
8. **User voice** — problems stated as "I [verb]..." not "Users experience..."
9. **Show projection math** — opportunity sizing exposes derivation: `[base] × [rate] = [outcome]` with rate sourced from real precedents.
10. **Clean Markdown output** — well-structured, scannable, VP-readable.
11. **No architecture or implementation details** — the PRD is a business document.
12. **Reference prototype screens** — Where the prototype (Step 4.1b) covers a flow or screen, reference it by screen name (e.g., "See Prototype: screen-02-main-flow") rather than describing layout in prose. The prototype is the visual source of truth; the PRD defines the requirements and behaviour. If a requirement has no corresponding prototype screen, describe it in text.
13. **Stakeholder Objection Map** (use framework from `.claude/skills/product-research/references/strategic-tools.md`) — Include a Section 9.5 "Anticipated Objections" in the PRD. Identify 5-7 likely objections from engineering leads, design leads, executives, sales/CS, and legal/compliance. For each: the objection, which stakeholder would raise it, a pre-answer referencing specific research evidence, and the evidence source. The PRD is a persuasion document as much as a spec.

#### Step 4.3: PRD Refinement (V2) → `14-prd-v2.md`

**Before starting**, read `.claude/skills/product-research/references/review-personas.md`.

Immediately after completing the V1 PRD, switch into a rigorous quality review. The goal is to transform the draft PRD into a tighter, more internally consistent V2 before any human review. This review has five phases:

##### Pre-Review: Premise Check

Before diving into detailed review, challenge the PRD's foundational assumptions. Re-read the PRD's Problem Statement, TL;DR, and Opportunity Size sections. Extract 3-5 implicit premises — falsifiable claims the PRD assumes are true. For each, document:

* **PREMISE**: [Concrete claim the PRD takes as given]
* **EVIDENCE IN PRD**: [Direct quote, or "none — assumed"]
* **RISK IF WRONG**: [What breaks in the PRD if this premise is false]

Then consider three challenge questions internally (do not present these to the user yet):

1. **Is this the right problem?** Could we solve something with bigger impact for the same effort?
2. **What's the 10X framing?** Is the PRD constraining the solution space unnecessarily?
3. **What happens if we do nothing?** Is the status quo actually painful enough to justify this work?

Present all extracted premises to the user as a numbered list, followed by the strongest challenge question. Then walk through each premise **one at a time**, offering for each:

* A) Correct as stated — no change needed
* B) [Suggested adjustment — a specific, concrete alternative framing informed by the PRD's own evidence gaps]
* C) [Another suggested adjustment — a different way this premise could be wrong]
* D) Other — let me reframe this premise

**WAIT FOR RESPONSE** on each premise. Do not batch them. After all premises and the challenge question are resolved, present a brief summary of adjusted premises and proceed to Phase A with these as context. If any premise was significantly adjusted, flag which PRD sections may need revision during Phase A.

##### Phase A — Structural Review

Analyse the V1 PRD against this checklist — flag every issue found:

**Consistency & traceability**
* Does every functional requirement trace back to a problem in the Problem Definition and a solution in the Solution Synthesis? Flag orphan requirements (present in PRD but not grounded in research) and missing requirements (grounded in research but absent from PRD).
* Are persona priorities consistent across Problem Statement, JTBDs, Functional Requirements, and Rollout sections?
* Do success metrics match the metrics defined in Phase 1.6 and the Solution Synthesis? Are baselines, targets, and measurement methods aligned?
* Are scope boundaries (in-scope vs out-of-scope) consistent with the Problem Definition's Top 3 problems and the Solution Synthesis's MVP recommendation?
* Does every JTBD's hypothesis + KPI table align with the evidence in Phase 2?
* Do requirement IDs follow PREFIX-N format with sufficient numbered behaviours?

**Completeness & gaps**
* Are there acceptance criteria for every must-have requirement? Are they specific and testable?
* Do user flows cover the primary happy path for every affected persona, plus key edge cases (error, empty state, multi-role)?
* Are non-functional requirements complete — performance, security, accessibility, localisation, observability, reliability, graceful degradation?
* Are dependencies fully enumerated (internal teams, external vendors, in-flight work, technical constraints from Phase 3.2)?
* Does the rollout plan have clear phase gates and rollback criteria?
* Are all [NEEDS PM INPUT] markers genuinely unresolvable from the research, or can some be filled from existing research outputs?

**Logical coherence**
* Do the stated objectives logically lead to the proposed requirements? Could the requirements be met without achieving the objectives (or vice versa)?
* Are effort estimates and priorities internally consistent? (e.g., a "must-have" marked as XL effort with no phasing plan)
* Do risk mitigations actually address the identified risks?

**Specificity & actionability**
* Are requirements specific enough for an engineering team to estimate and design against, without inventing business logic?
* Are user stories written from the persona's perspective with clear "so that" clauses grounded in the JTBD from Phase 1.2?
* Are vague terms ("intuitive", "seamless", "fast") replaced with measurable criteria?

##### Phase B — Five-Persona Review (Parallel Subagents)

Launch **5 independent review subagents in parallel** — one per review persona. Each subagent gets a fresh context with only the PRD, its persona instructions, and relevant reference material. This produces genuinely independent reviews (no anchoring on prior persona findings) and saves tokens in the main context.

**Before launching**, prepare the inputs each subagent needs:
1. Read the current PRD V1 content (`14-prd-v1.md`)
2. Read the Problem Definition (`07-problem-definition.md`) — needed by Product Thinker and Persona Coverage Expert
3. Read the Solution Synthesis (`12-solution-synthesis.md`) — needed by Product Thinker
4. Read the Prototype summary (`13-prototype.md`) — needed by UX Designer
5. Read the Review Personas reference (`.claude/skills/product-research/references/review-personas.md`)
6. Read the Strategic Tools reference (`.claude/skills/product-research/references/strategic-tools.md`) — needed by UX Designer for Nielsen heuristics

**Launch all 5 subagents in a single message** so they run concurrently. Each subagent:
* Gets a self-contained prompt with the full PRD text, its persona instructions (from the Review Personas reference), and any persona-specific reference material
* Uses `model: "sonnet"` for cost optimisation — structured review against a checklist is well-suited to Sonnet
* Is instructed to produce structured findings using the finding format from the Review Personas reference
* Classifies every finding as **SPECIFIABLE** (propose exact fix text) or **REQUIRES_DECISION** (PM must choose)
* Returns findings as markdown — no JSON

**Save each review result** to `subagent-research/review-{N}-{persona-slug}.md`:
- `review-01-product-thinker.md`
- `review-02-ux-designer.md`
- `review-03-engineering-manager.md`
- `review-04-persona-coverage.md`
- `review-05-qa-expert.md`

**Subagent prompts** — Each subagent gets its persona's full review criteria from the Review Personas reference, plus these persona-specific additions:

1. **Product Thinker** — Also receives: Problem Definition, Solution Synthesis. Scores 6 dimensions 1-10: demand reality, status quo honesty, narrowest wedge, competitive positioning, opportunity math, hypothesis clarity.

2. **UX Designer** — Also receives: Prototype summary (`13-prototype.md`), Strategic Tools reference (for Nielsen heuristics). Runs 7 review passes scored 0-10. **Additionally runs Nielsen's 10 Usability Heuristics** — scores each heuristic 0-4 (0=fully addressed, 4=catastrophe). **Reviews PRD UX descriptions against prototype screens — flags any inconsistency.** Verifies state coverage: does the prototype cover all states the PRD requires (empty, error, loading, permission)?

3. **Engineering Manager** — 4 review passes: structural consistency, implementation clarity, edge case & error coverage, hidden assumptions.

4. **Persona Coverage Expert** — Also receives: Problem Definition (for persona priorities). Coverage matrix, underserved persona gaps, confusion risks, adoption barriers, persona dependency chain.

5. **QA Expert** — AC quality grading (BAD/OK/GOOD) for every numbered behaviour. Shadow path tracing. Failure scenario generation per JTBD. Feasibility assessment.

After all 5 subagents complete, **read all review files** and proceed to Phase C (Synthesis & Triage) in the main context.

##### Phase C — Synthesis & Triage

Cross-reference all findings from Phase A and Phase B:

* **Reinforcing** (2+ personas flagged same issue) → HIGHEST priority
* **Unique** (one persona only) → MEDIUM priority
* **Conflicting** (personas disagree) → HIGH priority — surface the disagreement

Compute AC quality score: N% GOOD, M% OK, P% BAD across all numbered behaviours.

Triage every finding with a disposition:

| Disposition | Meaning | Action |
| --- | --- | --- |
| **Applied** | SPECIFIABLE fix with unambiguous text | Apply to PRD |
| **Captured** | REQUIRES_DECISION — PM must choose | Surface as decision item |
| **Dismissed** | False positive or out of scope | Note reason |

**Do NOT cherry-pick.** Every finding from every persona must appear with a disposition.

##### Phase D — Apply & Report

1. Apply all SPECIFIABLE fixes to the PRD content.
2. **Convergence check** — Re-read the updated PRD and verify no new contradictions were introduced by the fixes. If new issues are found, fix them and re-verify. Maximum **3 total iterations**. If the same issue persists after 2 consecutive loops, it cannot be resolved by spec text alone — add it to a **"Reviewer Concerns"** section at the bottom of the PRD (before the Refinement Summary) and stop iterating on it.
3. Add a **Refinement Summary** section at the bottom of the PRD:

    ```markdown
    ## Refinement Summary (V1 → V2)

    ### Applied Fixes
    | # | Finding | Persona | Section | Change Made | Source |
    |---|---------|---------|---------|-------------|--------|

    ### Decisions Needed (for PM)
    | # | Finding | Persona | Question | What Breaks If Deferred |
    |---|---------|---------|----------|------------------------|

    ### Dismissed
    | # | Finding | Persona | Reason |
    |---|---------|---------|--------|

    ### AC Quality
    | Metric | Before | After |
    |--------|--------|-------|
    | % GOOD | | |
    | % OK | | |
    | % BAD | | |
    ```

4. Write the V2 PRD to `14-prd-v2.md`.
5. Update `00-workflow-summary.md` — mark "PRD Refinement (V2)" as Done.

#### Step 4.4: Executive One-Pager → `15-executive-summary.md`

**After the V2 PRD is complete**, produce a single-page executive summary using the template from `.claude/skills/product-research/references/strategic-tools.md` (Tool 6). This is for the executive who will decide whether to fund/approve the initiative — they won't read the PRD, they'll read this.

The one-pager must fit on one page and include: the problem (2-3 sentences, user voice), the opportunity (with projection math), the recommendation (3-5 bullets), why now, key risk, success metric, and the ask.

Update `00-workflow-summary.md` with the new file.

#### Step 4.5: Handover Package → `16-handover-package.md`

**After the Executive One-Pager is complete**, produce a structured context package designed to be the starting input for downstream work — technical architecture, epic breakdown, story writing, or design handoff. This file is the bridge between research and execution.

The handover package is a **self-contained summary** that someone (human or AI) can read without needing to read all 15+ research files. It distills the entire research run into a single document optimised for action.

**Structure**:

```markdown
# Handover Package: [Initiative Title]

**Research folder**: research/{slug}-{date}/
**PRD version**: V2 (refined)
**Date**: [date]
**Status**: Ready for architecture / breakdown / design

---

## 1. Initiative Summary (3-5 sentences)
[What this is, who it's for, why it matters, what the recommended approach is]

## 2. Problem Space Digest
### Core Problem (1 paragraph, user voice)
[From 07-problem-definition.md]

### Personas (priority order)
| Persona | Role | Primary JTBD | Key Pain Point | Activation Definition |
|---------|------|-------------|----------------|----------------------|
[From 01, 02, 06]

### Top 3 Problems
[From 07-problem-definition.md — numbered, with severity and breadth]

## 3. Solution Space Digest
### MVP Recommendation
**Must-have** (3-5 items):
[From 12-solution-synthesis.md — each as: what it does, which problem it solves, which persona benefits]

**Should-have** (fast follow):
[From 12-solution-synthesis.md]

### Solution-to-Problem Traceability
| Solution | Problem | JTBD | Persona(s) | Effort | PRD Requirement IDs |
|----------|---------|------|-----------|--------|-------------------|
[Flat map from solutions to requirements — the single most useful table for architecture and breakdown]

## 4. Design Specs Summary
### Screen Inventory
| Screen | Purpose | Persona | Requirement IDs | Spec File | Prototype File |
|--------|---------|---------|----------------|-----------|----------------|
[From design-specs/ and prototypes/]

### Key Interaction Flows
[From design specs — numbered flows showing screen-to-screen paths per JTBD]

### State Coverage Matrix
| Screen | Default | Loading | Empty | Error | Success |
|--------|---------|---------|-------|-------|---------|
[From 13-prototype.md and design specs]

## 5. Technical Context
[From 09-technical-considerations.md — condensed to: systems involved, known constraints, build-vs-buy signals, data gaps]

## 6. Success Metrics
| Persona | Primary KPI | Target | Leading Indicator (2-week) | Lagging Indicator (90-day) |
|---------|------------|--------|---------------------------|--------------------------|
[From 06-metrics-success-criteria.md and 14-prd-v2.md]

## 7. Risks & Open Questions
### Top Risks (from Pre-Mortem)
[3-5 highest likelihood/impact failure scenarios with mitigation status]

### Open Questions
[All [NEEDS PM INPUT] items from PRD + unresolved items from Solution Synthesis]

### Decisions Needed (from PRD Review)
[All REQUIRES_DECISION items from the Refinement Summary — each with what breaks if deferred]

## 8. Research Confidence Assessment
| Research Area | Confidence | Key Gaps | Impact on Downstream Work |
|--------------|-----------|----------|--------------------------|
| User & persona understanding | HIGH/MEDIUM/LOW | [what's thin] | [what architecture/design should validate] |
| Competitive positioning | HIGH/MEDIUM/LOW | [what's thin] | [what to verify] |
| Technical feasibility | HIGH/MEDIUM/LOW | [what's thin] | [what architecture must resolve] |
| Market sizing & opportunity | HIGH/MEDIUM/LOW | [what's thin] | [what to validate] |

## 9. File Index
[Complete list of all research files with 1-line descriptions — the map for anyone who needs to go deeper]
```

**Rules for the Handover Package:**
* **Self-contained** — readable without any other file. Someone should be able to start architecture or breakdown work from this document alone.
* **Traceable** — every claim references its source file so readers can drill into detail.
* **Honest about gaps** — the Research Confidence Assessment is the most important section for downstream consumers. It tells them where the research is solid and where they need to do their own validation.
* **Action-oriented** — structured for the next step (architecture, breakdown, design), not as a research summary.

**Output**: Write `16-handover-package.md`.

Update `00-workflow-summary.md` with the new file.

**Quality gate** (Diamond 2 complete): Present the complete file list and refinement summary:

> "The full Double Diamond process is complete. All outputs are in your research folder:
>
> * Research Plan: `00-research-plan.md`
> * 6 Discover files: `01-` through `06-`
> * Problem Definition: `07-problem-definition.md`
> * 4 Develop solution files: `08-` through `11-`
> * Solution Synthesis: `12-solution-synthesis.md`
> * Prototype + Design Specs: `13-prototype.md` + `prototypes/` + `design-specs/`
> * PRD (V2 — refined): `14-prd-v2.md`
> * Executive One-Pager: `15-executive-summary.md`
> * **Handover Package: `16-handover-package.md`** — self-contained context for architecture, breakdown, or design handoff
>
> The PRD has been through premise validation, structural review, and five-persona independent adversarial review (parallel subagents) with convergence checking. The Refinement Summary at the bottom documents all applied fixes, decisions needed, and dismissed findings. AC quality scores are included.
>
> **Next steps**: Use `16-handover-package.md` as the starting input for technical architecture, epic breakdown (`/initiative-to-jira-breakdown`), or design handoff. The Research Confidence Assessment tells you where the research is solid and where downstream validation is needed.
>
> Please review and let me know if you want to refine any section further."

---

## Automated Research Protocol

At designated research points (Phase 0, Step 1.4, Step 1.5), the agent automatically spins up parallel subagents to gather domain knowledge via web search. **Subagents operate with fresh, expert eyes** — their prompts describe the domain question without referencing prior workflow findings, ensuring independent research angles.

**Before generating subagent prompts**, read `.claude/skills/product-research/references/expert-prompts.md` for persona selection and prompt structure guidance.

### How It Works

1. **Create subagent-research subfolder** on first subagent dispatch:
   ```
   mkdir -p research/{initiative-slug}-{YYYY-MM-DD}/subagent-research/
   ```

2. **Select expert personas** relevant to the initiative domain and the current step's needs. These are NOT fixed — they change based on the topic and what the step requires. A healthcare initiative gets a clinical workflow expert; a developer tools initiative gets a senior SRE; a real estate initiative gets an experienced broker.

3. **Write independent, expert-driven prompts**. Each prompt should:
   * Frame the research question from the expert's domain perspective
   * **NOT reference prior workflow steps or findings** — the subagent gets fresh eyes
   * Be self-contained (~80-120 words) with clear deliverables
   * Specify output format: prioritised list, confidence notes, citations

4. **Spin up subagents in parallel** using the Agent tool. Each subagent:
   * Gets a self-contained prompt written as an expert-persona-driven research brief
   * Has web search enabled (use `subagent_type: "general-purpose"`)
   * Uses `model: "sonnet"` for cost optimisation — research subagents do web search + summarisation, which doesn't require Opus
   * Returns a **text-only markdown summary** — no JSON, no structured data, just clear prose with cited sources
   * Is capped at ~500 words of output (instruct the subagent to be concise)

5. **Launch all subagents in a single message** so they run concurrently.

6. **Save each subagent result to its own MD file** in `subagent-research/`:
   * Filename format: `{phase}{step}-{sequence}-{persona-slug}.md`
     - Phase 0: `phase0-01-proptech-analyst.md`, `phase0-02-buyer-behavior-expert.md`
     - Step 1.4: `step14-01-competitor-analyst.md`, `step14-02-adjacent-markets.md`
     - Step 1.5: `step15-01-ux-patterns.md`, `step15-02-product-strategy.md`
   * File structure:
     ```markdown
     # Subagent Research: [Expert Persona Name]
     
     **Phase/Step**: [e.g., Phase 0, Step 1.4]
     **Research Question**: [What this subagent was asked to find]
     **Date**: [YYYY-MM-DD]
     
     ## Prompt Given to Subagent
     
     [Exact prompt text sent to the subagent]
     
     ## Findings
     
     [Subagent's full markdown response]
     ```

7. **Quality assessment** — Before synthesis, assess each subagent result. Read each result and tag it:

   | Quality | Criteria | How to weight |
   |---------|----------|---------------|
   | **HIGH** | Names specific companies, products, or people. Cites numbers (%, $, counts). Includes URLs or named reports. Findings are falsifiable. | Full weight — treat as primary evidence. Cite directly. |
   | **MEDIUM** | Describes real patterns or trends but without specific citations. References general industry knowledge. Findings are plausible but unverified. | Partial weight — use as supporting evidence. Flag as "Web-inferred." |
   | **LOW** | Generic statements ("industry experts suggest..."). No specific names, numbers, or sources. Could have been written without web search. Mostly restates the prompt. | Minimal weight — note the gap. Do not cite as evidence. Flag as "No specific data found." |

   Add the quality tag to each subagent's file header and to the "External Data Collected" table in `00-workflow-summary.md`. When a subagent returns LOW quality results, note the research gap explicitly in the synthesis — "Subagent research on [topic] returned limited specific data. The following claims are inferred rather than sourced: [list]."

8. **Master synthesis reads and incorporates subagent findings** into the main workflow step output:
   * Read ALL subagent MD files from the relevant phase/step
   * Synthesize findings into the main step output (e.g., `04-industry-competitor-research.md`)
   * **Weight findings by quality tag** — HIGH-quality findings anchor the synthesis; MEDIUM findings provide supporting context; LOW findings are noted as gaps, not cited as evidence
   * Reference subagent sources explicitly: "From Subagent Research (Competitor Analyst, HIGH): [finding]"
   * Log summary in `00-workflow-summary.md`'s "External Data Collected" table with quality tag
   * Cite with confidence level: **Web-sourced** (HIGH — found specific data with URLs), **Web-inferred** (MEDIUM — synthesised from multiple sources), **No data found** (LOW — subagent couldn't find relevant information)

### Subagent Prompt Template

```
As a [specific expert role with 10+ years experience], I need to understand [specific domain question].

Search the web for: [specific data points, keywords, companies, reports, benchmarks]

Focus on: [specific angle this expert would prioritise — what matters most from their domain lens]

Return a concise markdown summary (under 500 words) with:
- Key findings as a prioritised list
- Specific product/company names, numbers, and URLs where available
- Confidence notes on what's well-documented vs. sparse

Do not include any preamble or meta-commentary — just the research findings.
```

**Key principle**: The prompt describes the domain question, not "what we learned so far." This ensures fresh perspective and avoids confirmation bias.

### Where Subagents Run

| Phase | Subagent dispatch? | Why |
|-------|--------------------|-----|
| Phase 0 (Research Planning) | **Yes** — 3-5 research subagents | Ground the research plan in real domain context before planning |
| Phase 1, Steps 1.1-1.3 | No | Synthesis from brief + Phase 0 findings. No new data needed. |
| Phase 1, Step 1.4 (Competitor) | **Yes** — 2-4 research subagents | Inherently web-research-dependent. Need real competitor data. |
| Phase 1, Step 1.5 (Best Practices) | **Yes** — 2-3 research subagents | Need real UX/product/technical best practices from published sources. |
| Phase 1, Step 1.6 | No | Synthesis step. Metrics derived from prior steps. |
| Phase 2 (Define) | No | Pure synthesis of Phase 1 outputs. |
| Phase 3 (Develop) | No | Creative solution design. Agent may use direct web search within a step if needed, but no subagent dispatch. |
| Phase 4, Steps 4.1-4.2 | No | PRD authoring. No new research. |
| Phase 4, Step 4.3 (PRD Review) | **Yes** — 5 review subagents | Independent five-persona adversarial review. Each persona runs in isolation for genuine independence. |
| Phase 4, Step 4.4 | No | Executive summary from completed PRD. |

### User-Provided Data

The user can still provide additional data at any checkpoint. When they do:

1. Acknowledge what they shared and summarise it back to confirm understanding
2. Integrate it into the current step's output with appropriate weight
3. Log it in `00-workflow-summary.md`'s "External Data Collected" table
4. Cite it explicitly in the output with source and confidence level

---

## Resume Protocol

If a conversation ends mid-workflow and the user says "Resume research for [initiative]":

1. Find the research folder in `research/`
2. Read `00-workflow-summary.md` for current status
3. Read all completed step files to re-establish context
4. **Scan all completed files for any revision notes** — if feedback was partially incorporated, resume the Feedback Incorporation Protocol before continuing forward
5. Identify the next pending step
6. Tell the user where you left off, flag any open issues found, and confirm how to proceed
7. Continue from the next pending step

---

## Feedback Incorporation Protocol

When feedback arrives on completed research files — from stakeholders, reviewers, or the user — this protocol determines how to incorporate it without a wasteful full re-run.

**Trigger**: The user says "incorporate feedback", "process comments", "update research based on [X]", or provides corrections to any research file. Also triggered automatically during Resume if unresolved feedback is detected.

### Step F1: Feedback Collection

Collect all feedback from the user. For each piece of feedback, record:

| Field | Value |
| --- | --- |
| Target file | Which research file this applies to |
| Specific section | Which section or claim is being challenged |
| Feedback | The reviewer's comment or correction |
| Source | Who provided it (user, stakeholder name, etc.) |

Present the full feedback inventory to the user as a numbered list before proceeding.

### Step F2: Feedback Classification

For each piece of feedback, determine three attributes:

**Type** — determines handling approach:

| Type | Description | Example |
| --- | --- | --- |
| **Structural** | Challenges a foundational assumption: persona priority, problem framing, scope boundary, success criteria definition | "The org admin is not the most important user" |
| **Specificity** | Flags vague, generic, or AI-sounding language that needs concrete grounding | "What context? Which user?" |
| **Detail gap** | Notes missing information needed for downstream actionability | "Not enough detail for implementation" |
| **Factual** | Corrects a factual error, outdated data, or misattribution | "We have 4 personas, not 3" |
| **Scope** | Requests addition or removal of something from scope | "We should also consider partner onboarding" |

**Conceptual origin** — The step where the challenged content was *first established*, regardless of which file the comment was left on. A comment on the PRD about persona priority originated in Phase 0 / Phase 1.1, not Phase 4.2.

**Severity**:

* **Local** — Fixable on the target file alone. The change does not alter any conclusion, priority, or input that downstream files depend on. Examples: language polish, adding a clarifying sentence, fixing a typo.
* **Cascading** — Changes an input that downstream files consume: persona priority, problem ranking, metric definitions, JTBD framing, solution recommendations. Requires revision of the origin file and all downstream dependents.

### Step F3: Impact Analysis

Use the dependency graph to trace which files need revision:

```
Phase 0 (Research Plan)
  ├──► Phase 1.1 (Persona & User Needs)      [persona-sensitive]
  ├──► Phase 1.2 (Jobs to Be Done)            [persona-sensitive]
  ├──► Phase 1.3 (Journey & Friction)         [persona-sensitive]
  ├──► Phase 1.4 (Industry & Competitor)      [persona-independent]
  ├──► Phase 1.5 (Domain Best Practices)      [persona-independent]
  └──► Phase 1.6 (Metrics & Success)          [persona-sensitive]
        └──► Phase 2 (Problem Definition)     [synthesises all Phase 1]
              ├──► Phase 3.1 (Product & Experience Design)
              ├──► Phase 3.2 (Technical Considerations)
              ├──► Phase 3.3 (GTM & Enablement)
              └──► Phase 3.4 (Alternative Approaches)
                    └──► Phase 4.1 (Solution Synthesis) [synthesises Phase 2 + Phase 3]
                          └──► Phase 4.1b (Prototype + Design Specs) [visualises Phase 4.1 MVP]
                                └──► Phase 4.2 (PRD V1) [uses Phase 2 + Phase 4.1 + Phase 4.1b]
                                      └──► Phase 4.3 (PRD V2) [refines Phase 4.2 via 5 parallel review subagents]
                                            └──► Phase 4.4 (Executive One-Pager)
                                                  └──► Phase 4.5 (Handover Package) [distils all outputs]
```

**Propagation rules**:

| Feedback Severity | Affected Files |
| --- | --- |
| Local (specificity, minor detail gap) | The target file only. If the file is Phase 1.x or Phase 3.x, also re-check the corresponding synthesis file (Phase 2 or 4.1) for stale references. |
| Cascading — persona-related | Conceptual origin + all persona-sensitive Phase 1 steps + Phase 2 + all Phase 3 steps + Phase 4.1 + Phase 4.2 |
| Cascading — problem/scope-related | Conceptual origin + Phase 2 + all Phase 3 steps + Phase 4.1 + Phase 4.2 |
| Cascading — solution-related | Conceptual origin + Phase 4.1 + Phase 4.2 |
| Cascading — prototype-related | Phase 4.1b + Phase 4.2 (re-check screen references) |

When multiple pieces of feedback affect different steps, union all affected files and process them in dependency order.

### Step F4: Revision Plan

Present the user with:

1. **Feedback analysis table**: each piece of feedback, its type, conceptual origin, severity, and affected files
2. **Revision scope**: ordered list of files that need rewriting, with the reason for each
3. **Estimated effort**: number of files to rewrite (light touch vs. substantial)
4. **Recommendation**: whether to do a targeted revision pass or a broader re-run

**STOP and wait for user confirmation before proceeding.** The user may:

* Agree with the plan
* Reclassify feedback (e.g., "that one is actually just a local fix")
* Add context that changes the scope
* Defer certain items to a later pass

### Step F5: Feedback-Aware Rewrite

For each affected file, in **strict dependency order** (upstream before downstream):

1. **Read** the current file content
2. **Collect** all applicable feedback: direct feedback on this file + cascaded constraints from upstream revisions in this pass
3. **Read** any upstream files that were already revised in this pass (to use as updated inputs)
4. **Rewrite** the file:
    * Incorporate the specific feedback while maintaining section structure and format
    * Preserve evidence citations and confidence flags
    * Ensure consistency with revised upstream files
    * For synthesis files (Phase 2, 4.1, 4.2): **re-synthesise from the revised inputs**, don't just patch sentences
    * Add a revision note at the bottom of the file:

        ```markdown
        ---
        **Revision [YYYY-MM-DD]**: Incorporated stakeholder feedback. Changes: [brief summary]. See Workflow Summary for details.
        ```

5. **Write** the updated file
6. **Stream progress**: "[filename] revised — [brief summary of changes]. Continuing..."
7. **Update** `00-workflow-summary.md` after each file (same non-negotiable rule as the initial run)

After all revisions in the pass are complete, present the full list of revised files and wait for user review.

### Step F6: Workflow Summary Update

After all revisions are complete, update `00-workflow-summary.md` with:

1. A new entry in the **Revision History** section (add this section if it doesn't exist yet):

    ```markdown
    ## Revision History

    | Date | Trigger | Feedback Addressed | Files Revised | Summary |
    |------|---------|--------------------|---------------|---------|
    | [date] | [N] feedback items | [list] | [list] | [brief summary of changes] |
    ```

2. Update the **Decisions Log** with any decisions made during classification
3. Mark affected steps in the Progress table with "Revised" instead of "Done" so it's clear which files reflect post-feedback content

### Step F7: Feedback Resolution

After the user has reviewed all revised files:

1. List each original piece of feedback and how it was addressed
2. Ask the user if they're satisfied with how each was incorporated
3. Document resolution status in the Workflow Summary

### Behavioural Rules for Feedback Incorporation

* **Dependency order is non-negotiable**: Never revise a downstream file before its upstream dependencies are revised. Phase 2 before Phase 3. Phase 4.1 before Phase 4.2.
* **Re-synthesise, don't patch**: For synthesis files (Phase 2, 4.1, 4.2), re-read all inputs and produce a fresh synthesis that reflects the new state. Do not just find-and-replace references to the old content.
* **Preserve what's unchanged**: For files where only downstream effects apply (not direct feedback), keep unaffected sections stable. Only revise sections that reference changed upstream content.
* **One file at a time, review at the end**: Revise one file at a time in dependency order, update the summary after each. Stream progress as you go. Present all revised files for review after the full pass is complete.
* **Multiple feedback rounds are normal**: This protocol is designed to be run multiple times. Each run is additive — the Revision History accumulates entries.

---

## Updating the Workflow Summary

**This is mandatory after EVERY step — no exceptions. Do NOT complete multiple steps before updating.** If you complete a step and move on without updating the Workflow Summary, you are violating the workflow. This is critical for state recovery — if the conversation ends unexpectedly, the Workflow Summary is the only record of progress.

After completing each step:

1. Read the current `00-workflow-summary.md`
2. Update the status of the completed step from "Pending" to "Done"
3. Add the filename for the completed step
4. Update the overall status to reflect the current phase
5. Write the updated file

Note: You do NOT need to wait for user confirmation after updating the summary. The summary update is a bookkeeping step — stream a progress line and continue to the next step within the phase.

---

## Behavioural Rules

* **Flow within phases, gate between phases**: Within a phase, complete steps sequentially without pausing — write file, update summary, stream progress, continue. Between phases, STOP at the quality gate and wait for user input. The user controls pacing at the phase level; `/pause` gives step-level control when needed.
* **Subagent research is automatic**: At Phase 0, Step 1.4, and Step 1.5, spin up parallel subagents without asking the user. Collect results, run quality assessment (see Subagent Quality Assessment), incorporate them, and present findings at the phase quality gate.
* **Wait at quality gates**: When you present quality gate questions (end of each phase), STOP and wait for the user to respond. Quality gates are the user's control points — never auto-proceed past them.
* **Always update the Workflow Summary**: After every single step, update the Workflow Summary. Never batch updates across multiple steps. This is the state recovery mechanism — treat it as non-negotiable.
* **Cite evidence**: Every claim in synthesis steps (Phase 2 and 4) must reference which research step it came from. No ungrounded assertions.
* **Flag uncertainty**: Use confidence levels (High / Medium / Low) and research source type (Web-sourced / Web-inferred / No data found). Never present speculation as fact. Be brutally honest about what you know vs. what you're inferring.
* **Read before synthesising**: Always re-read previous phase files before synthesis steps. The user may have edited them.
* **Product specificity**: Reference actual product concepts, personas, and scenarios. Never be generic when you can be specific. "Admin" is worse than "Organisation Admin who configures sharing permissions for 50+ users."
* **Web search**: Subagents handle web research at Phase 0, 1.4, and 1.5. The agent may also use direct web search within any step where specific data would strengthen the output.
* **Confluence search**: Proactively search Confluence at designated points (Step 0, Phase 0, Phase 3, Step 3.2) to gather internal context. Don't wait for the user to tell you — search for prior research, RFCs, persona docs, and architecture docs relevant to the initiative.
* **Codebase exploration**: At Step 3.2 (Technical Considerations) and Step 4.1b (Prototype), explore the codebase to ground outputs in reality. Reference specific files and patterns you find.
* **Glean prompts at quality gates**: At every quality gate and before every phase, offer the user 2-5 targeted Glean prompts specific to the phase's needs. Always STOP and WAIT for the user to respond — they may need time to run queries.
* **Business-focused PRD**: The PRD is a business document. Technical feasibility and implementation details are handled post-PRD by the engineering team. Do not include architecture proposals, implementation approaches, or detailed effort estimates in the PRD.
* **User voice over corporate voice**: Problems stated as "I don't know what to share" not "Users experience a content creation friction point."
* **Decisive recommendations**: Be opinionated. Commit to the recommendation. The research supports a point of view — express it.
* **Honour `/pause`**: If the user types `/pause` at any point, finish the current step, update the summary, and stop. Present a status and wait.

---

## Tips

**Writing a Good Brief:** Include title, hypothesis, goal, scope hints, constraints, success criteria. The better the brief, the better the research.

**Resuming:** Say "Resume research for [initiative title]" in a new conversation.

**Context Limits:** All state lives in local files. Quality gates are natural pause points. Budget ~30-60 minutes per phase.

**Pausing:** Type `/pause` at any time to stop the workflow mid-phase. The agent finishes the current step, saves state, and waits.

**Feedback:** Say "incorporate feedback" at any time to trigger the Feedback Incorporation Protocol on any completed file.

**Downstream handoff:** After the workflow completes, use `16-handover-package.md` as the starting input for architecture, `/initiative-to-jira-breakdown`, or design handoff. It's self-contained — no need to read all 15+ research files.
