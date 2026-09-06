---
name: codebase-mapping
description: "Orchestrates comprehensive codebase architecture documentation, producing docs/arch-plan.md with feature-to-code mapping, database schema, API reference, ASCII diagrams, and PM-friendly change guidance. Use when the user wants to understand a codebase, onboard onto an unfamiliar project, create architecture docs, map features to code, or document system design. Triggers: 'map the codebase', 'architecture documentation', 'understand this codebase', 'create arch doc', 'document the system', 'codebase overview'. Spawns explorer and architect subagents, graph-accelerated when the code-review-graph plugin is available. NOT for reviewing diffs (use pr-review-pr), debugging (use investigate), or planning a single feature (use eng-planning)."
---

# Codebase Mapping

Orchestrate a comprehensive codebase exploration to create architecture documentation that shows how features map to code, enabling confident technical decision-making.

## Overview

This skill uses the `lead-orchestrator` pattern to spawn multiple specialized subagents (`code-explorer`, `code-architect`) that thoroughly explore the codebase and produce a complete architecture document at `docs/arch-plan.md`.

**Output**: A PM-friendly architecture document with:
- Feature-to-code mapping
- Component interactions and data flows
- Database schema with relationships
- API endpoint reference
- Visual diagrams (ASCII art)
- Change guidance for common tasks

## When to Use This Skill

Use this skill when:
- Starting work on an unfamiliar codebase
- Onboarding to a project as PM or technical lead
- Needing to understand how features are implemented
- Planning major refactors or feature additions
- Creating technical documentation for stakeholders
- Auditing system architecture

---

## Workflow

### Step 0: Generate Repomap

Before any exploration, generate a git-activity-ranked structural summary to give agents a "lay of the land". This highlights the most actively developed files and their structure, so agents can prioritize exploration.

**Decision rule:** run this whenever the target is a git repository; skip it (without asking) when it isn't, or when the script fails.

```bash
python ~/.claude/scripts/generate-repomap.py --repo {project_path} --max-lines 200 --days 90
```

- The output shows files ranked by recent commit frequency with extracted class/function definitions
- Include this output in code-explorer agent prompts as initial context (prefix with "Here is a repomap of the most active files:")
- If the script fails (not a git repo, no activity, Python not available), proceed without it -- this step is purely additive

### Step 0a: Code Review Graph (Auto-Detected)

Before any manual exploration, check whether a `code-review-graph` knowledge graph
exists for this repo and build one if it doesn't. The graph provides pre-computed
architecture data (communities, execution flows, hub/bridge nodes) that drastically
reduces the manual scanning subagents need to do.

**Probe → Build → Harvest sequence:**

1. **Probe**: Call `list_graph_stats_tool` (no args — auto-detects repo root).
   - If it returns stats with `total_nodes > 0`, a graph exists. Set `GRAPH_AVAILABLE = true`.
   - If it errors or returns 0 nodes, no graph exists yet.

2. **Build** (only when no graph exists): Call `build_or_update_graph_tool` with
   `full_rebuild: true, postprocess: "full"`. This parses the codebase with Tree-sitter
   and detects communities, flows, and FTS index. Takes 10–60 seconds depending on
   codebase size.
   - If the build succeeds, set `GRAPH_AVAILABLE = true`.
   - If it fails (e.g., plugin not installed, unsupported language), set
     `GRAPH_AVAILABLE = false` and proceed with standalone mode — the rest of the
     workflow works without it.

3. **Harvest** (only when `GRAPH_AVAILABLE = true`): Run these graph queries in parallel
   to pre-populate the data that subagents would otherwise discover manually:

   | Query | Tool | What it provides |
   |-------|------|-----------------|
   | Architecture overview | `get_architecture_overview_tool` | Community structure, cross-community coupling |
   | Communities list | `list_communities_tool(detail_level="standard")` | Architectural clusters with members |
   | Top execution flows | `list_flows_tool(limit=30, sort_by="criticality")` | Entry-point call chains |
   | Hub nodes | `get_hub_nodes_tool(top_n=15)` | Most-connected architectural hotspots |
   | Bridge nodes | `get_bridge_nodes_tool(top_n=10)` | Chokepoint nodes between subsystems |
   | Knowledge gaps | `get_knowledge_gaps_tool` | Isolated nodes, untested hotspots, thin communities |

   Capture these results as `GRAPH_CONTEXT` — a structured bundle passed into every
   subagent prompt as pre-computed context.

**Fallback**: If the graph plugin is not installed or build fails, `GRAPH_AVAILABLE`
stays `false` and all subsequent steps use their original standalone logic. No step
in this workflow requires the graph to function.

### Step 1: Context Gathering

Before spawning agents, gather context:

1. **Ask the user** (if not obvious):
   - What's the primary goal? (onboarding, planning changes, documentation, audit)
   - Any specific features or areas to focus on?
   - Is there existing architecture documentation to build on?
   - What's the target audience? (PMs, engineers, stakeholders)

2. **Quick scan** (skip items already answered by `GRAPH_CONTEXT`):
   - Check for README, package.json, or equivalent to understand tech stack
   - Identify main directories (frontend, backend, database, etc.)
   - Look for existing docs in `docs/` or `README.md`
   - If `GRAPH_AVAILABLE`: the architecture overview and community list already provide
     the directory/subsystem map — use them instead of manual scanning

### Step 2: Orchestration Setup

Invoke the **lead-orchestrator** skill to manage subagents:

```
/lead-orchestrator
```

The orchestrator will coordinate the following subagent sequence:

1. **code-explorer** (Exploration Phase)
   - Scan entire codebase structure
   - Identify main directories, entry points, config files
   - Map major features to their code locations
   - Document external integrations

2. **code-architect** (Architecture Analysis Phase)
   - Analyze component interactions
   - Trace data flows for major features
   - Document database schema and relationships
   - Map API endpoints
   - Create dependency graphs

**Agent availability pre-flight:** the `code-explorer` / `code-architect` agent types
come from the `feature-dev` plugin, which may not be installed. If a dispatch fails
with "No such tool/agent available", use `general-purpose` subagents instead — the
Step 3 task descriptions are self-contained prompts and work with either agent type.
Do not abort the workflow over a missing agent type.

**When `GRAPH_AVAILABLE = true`**: Include the full `GRAPH_CONTEXT` in every subagent
prompt. Instruct agents to use graph data as their primary source and only read source
files to fill gaps (business logic details, env vars, config specifics, database
schema columns). This typically reduces exploration from dozens of file reads to a
handful of targeted reads.

### Step 3: Subagent Task Breakdown

The orchestrator should spawn agents with these specific tasks. Each task has a
**graph-accelerated** variant (used when `GRAPH_AVAILABLE = true`) and a **standalone**
variant (original behavior, used when graph is unavailable).

**Task 1: Structure Mapping** (code-explorer)

*Standalone:*
- Scan directory tree and identify purposes
- Find all entry points (main files, routes, controllers)
- Locate config files and environment setup
- Identify third-party integrations
- **Output**: Directory structure map + initial feature list

*Graph-accelerated:*
- Use `GRAPH_CONTEXT.architecture_overview` for subsystem boundaries
- Use `GRAPH_CONTEXT.communities` for the directory/module cluster map
- Use `GRAPH_CONTEXT.hub_nodes` to identify critical entry points
- Only scan files manually for: config files, env setup, third-party integrations
  (things the graph doesn't capture)
- For targeted deep-dives, call `query_graph_tool(pattern="children_of", target="<file>")`
  or `semantic_search_nodes_tool(query="<concept>")` to find specific code entities
- **Output**: Same — directory structure map + initial feature list

**Task 2: Feature Tracing** (code-explorer)

*Standalone:*
- For each major feature identified:
  - Trace from UI/API → controllers → services → models
  - Document the code path
  - Identify key files with line numbers
  - Note database tables used
- **Output**: Feature-to-code mapping table

*Graph-accelerated:*
- Use `GRAPH_CONTEXT.flows` (top execution flows by criticality) as the starting set
  of features — each flow IS a traced code path from entry point through the call chain
- For each flow, call `get_flow_tool(flow_id=<id>, include_source=true)` to get the
  full call path with file paths and line numbers
- Use `query_graph_tool(pattern="callees_of", target="<function>")` to expand any
  step in a flow
- Only read source files for: business logic understanding, database table identification
  (unless the graph captured ORM model nodes)
- **Output**: Same — feature-to-code mapping table

**Task 3: Architecture Analysis** (code-architect)

*Standalone:*
- Analyze database schema (tables, columns, relationships, indexes)
- Document all API endpoints with handlers
- Map authentication/authorization flows
- Create system component diagrams
- Create request flow diagrams for major features
- **Output**: Architecture diagrams + technical reference

*Graph-accelerated:*
- Use `GRAPH_CONTEXT.communities` + `GRAPH_CONTEXT.bridge_nodes` for the component
  diagram — communities are components, bridges are the connections between them
- Use `GRAPH_CONTEXT.flows` for request flow diagrams — each flow is already a
  traced sequence
- Use `GRAPH_CONTEXT.knowledge_gaps` to identify areas that need extra attention or
  should be flagged as technical debt
- Call `query_graph_tool(pattern="importers_of", target="<module>")` to map
  dependencies between modules
- Still read source files for: database schema details, auth flow specifics, env vars
- **Output**: Same — architecture diagrams + technical reference

**Task 4: Integration** (code-architect)
- Compile all findings into unified `docs/arch-plan.md`
- Create change guidance section
- Flag technical debt or undocumented areas (if `GRAPH_AVAILABLE`: incorporate
  `GRAPH_CONTEXT.knowledge_gaps` — untested hotspots, isolated nodes, thin communities)
- Generate final ASCII diagrams
- **Output**: Complete architecture document

### Step 4: Output Structure

The final `docs/arch-plan.md` document MUST follow this structure. A fully worked
example (filled-in sections, diagram style) lives at
`~/.claude/skills/codebase-mapping/templates/arch-plan-template.md` — include it in
the integration agent's prompt as a formatting reference.

```markdown
# Architecture Plan: [Project Name]

## 1. System Overview
- Purpose and capabilities
- Tech stack summary
- High-level architecture diagram (ASCII)

## 2. Directory Structure Map
```
/directory
  ├── /subdirectory - What it does
  └── Purpose and key files
```

## 3. Feature-to-Code Mapping
For each major feature:
- **Feature Name**
  - User-facing capability: [what users can do]
  - Entry point: [route/endpoint]
  - Code path: [route → controller → service → model]
  - Key files: [list with line numbers if relevant]
  - Database tables used: [tables]
  - Dependencies: [what else this touches]

## 4. Database Schema
```
[ASCII ER diagram here — use box-drawing characters]
```

Table details:
- **table_name**
  - Purpose:
  - Key columns:
  - Relationships:
  - Indexes:

## 5. API Endpoints Reference
| Method | Endpoint | Purpose | Handler | Auth Required |
|--------|----------|---------|---------|---------------|
| GET    | /api/... | ...     | ...     | Yes/No        |

## 6. Core Architecture Diagrams

### System Component Diagram
```
[ASCII component diagram — use box-drawing characters, arrows (──►, ──▼)]
```

### Request Flow Examples
```
[ASCII sequence diagram — use vertical pipes, arrows (──►, ◄──), and labeled lines]
```

## 7. Key Classes & Functions
- **ClassName** (file: path/to/file.ext)
  - Purpose:
  - Key methods:
  - Used by:

## 8. Configuration & Environment
- Required env vars
- Config file locations
- Third-party services

## 9. Change Guidance
For common PM tasks:
- **Adding a new feature**: Start here → modify these → test these
- **Modifying existing feature X**: Touch these files → watch out for these dependencies
- **Database changes**: Migration process → files to update

## 10. Technical Debt & Notes
- Areas of concern
- Undocumented behaviors
- Recommended refactors
```

---

## Output Requirements

### Visual Diagrams

Use **ASCII art** exclusively (no mermaid). Use box-drawing characters (┌─┐│└─┘), arrows (──►, ──▼, ◄──), and plain-text labels inside fenced code blocks:

1. **ER Diagram** for database schema — boxes with columns, relationship lines with 1:N labels
2. **Component Graph** for system architecture — nested boxes with directional arrows
3. **Sequence Diagrams** for key request flows — vertical participant columns with horizontal arrows
4. **Dependency Graphs** for module relationships — boxes with directional arrows

### Documentation Style

- **Specific**: Include file paths with line numbers where relevant
- **Feature-focused**: Explain WHAT each part does for users/features, not just technical details
- **PM-friendly**: Avoid unnecessary jargon; focus on business capabilities
- **Actionable**: "Change Guidance" section must be concrete and specific
- **Honest**: Flag confusing, poorly documented, or concerning areas

### Critical Flows

If the codebase contains these, document them **extra thoroughly**:
- Authentication & authorization
- Payment processing
- Data privacy / PII handling
- External API integrations
- Background jobs / async processing

---

## Subagent Communication Protocol

Agents communicate ONLY through committed artifacts:

1. **code-explorer** creates:
   - `docs/arch-plan-structure.md` (directory map)
   - `docs/arch-plan-features.md` (feature mapping)

2. **code-architect** reads those files and creates:
   - `docs/arch-plan-diagrams.md` (ASCII diagrams)
   - `docs/arch-plan-api.md` (API reference)

3. **Final integration** combines all into:
   - `docs/arch-plan.md` (complete document)

All intermediate files are committed. The orchestrator reviews the final output.

---

## Quality Checklist

Before marking complete, verify:

- [ ] All major features identified and traced to code
- [ ] Database schema fully documented with relationships
- [ ] API endpoints catalogued with auth requirements
- [ ] At least 3 ASCII diagrams present (ER, component, sequence)
- [ ] Change guidance section has 3+ concrete scenarios
- [ ] File paths are accurate and specific
- [ ] Technical debt section flags any concerns
- [ ] Document is PM-readable — test: a PM can answer "which files do I touch to change feature X?" from Section 9 alone, without reading code
- [ ] If graph was available: knowledge gaps incorporated into Technical Debt section

---

## Example Use Case

**Scenario**: PM joining an AI board member app (React frontend, Node.js backend, FastAPI + pgvector for RAG)

**Goal**: Understand how the "meeting transcription" feature works so changes can be planned.

**Process**:
1. Invoke `codebase-mapping` skill
2. Orchestrator spawns `code-explorer` to map structure and find transcription feature
3. `code-explorer` traces: `/api/transcribe` → `transcription.controller.ts` → `transcription.service.ts` → `audio-processing.py` → `transcripts` table
4. `code-architect` creates sequence diagram showing: Upload → FastAPI processing → pgvector embedding → storage → frontend display
5. Final `docs/arch-plan.md` shows complete feature map with change guidance: "To modify transcription: touch these 4 files, watch out for async job processing, test with these endpoints"

**Outcome**: PM can now confidently plan changes without guessing which files to modify.

---

## Tips & Best Practices

- **Start broad, then narrow**: Full codebase scan first, then deep dives on specific features
- **Use parallel exploration**: Multiple code-explorer agents can scan different subsystems simultaneously
- **Commit frequently**: Each subagent commits findings before next agent starts
- **Flag unknowns**: If a pattern is unclear or undocumented, say so explicitly
- **Update over time**: This document should be living; update as architecture changes
- **Graph as primary, files as supplement**: When the graph is available, treat its communities/flows/hubs as ground truth for structure; read source files only for business logic, config details, and schema columns the graph doesn't capture

---

## Troubleshooting

**Issue**: Codebase too large, exploration times out
- **Solution**: Scope to specific subsystem (frontend only, backend only, etc.)

**Issue**: No clear feature boundaries
- **Solution**: Map by technical layers instead (routes → controllers → models)

**Issue**: Existing docs conflict with code
- **Solution**: Flag conflicts explicitly in "Technical Debt" section

**Issue**: Authentication flow unclear
- **Solution**: Spawn dedicated code-explorer focused ONLY on auth; trace from login endpoint

**Issue**: `code-explorer` / `code-architect` dispatch fails ("No such tool/agent available")
- **Solution**: The `feature-dev` plugin is not installed. Use `general-purpose` subagents with the same Step 3 task prompts. Do not abort.

**Issue**: Code review graph build fails or plugin not installed
- **Solution**: This is expected — the skill falls back to standalone mode automatically. No action needed. The graph is purely additive; all exploration tasks have standalone variants that work without it.

**Issue**: Graph exists but feels stale (missing recently added files)
- **Solution**: Call `build_or_update_graph_tool` with `full_rebuild: false` (incremental update). The graph diffing picks up changes since the last build.

---

## Dependencies

- **lead-orchestrator**: Required for coordinating subagents
- **feature-dev:code-explorer / feature-dev:code-architect**: Preferred agent types for scanning and architecture analysis. NOT guaranteed to be installed — fall back to `general-purpose` subagents with the same Step 3 task prompts if dispatch fails.
- **code-review-graph plugin**: Optional — auto-detected and auto-built at Step 0a. When available, provides pre-computed architecture data (communities, flows, hubs, bridges) that accelerates all exploration tasks. The skill works fully without it.

---

## Notes for Orchestrator

When acting as orchestrator:
- **Never implement code yourself** — only spawn and coordinate subagents
- **Review each agent's output** before spawning the next
- **Escalate if >1 fix cycle needed** on any subtask
- **Commit all artifacts** as agents complete work
- **Final review**: Read complete `docs/arch-plan.md` and verify quality checklist
