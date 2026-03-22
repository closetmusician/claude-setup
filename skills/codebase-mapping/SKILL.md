---
name: codebase-mapping
description: "Orchestrates comprehensive codebase architecture documentation. Use when the user wants to understand a codebase, create architecture docs, map features to code, document system design, or needs a technical overview. Triggers: 'map the codebase', 'architecture documentation', 'understand this codebase', 'create arch doc', 'document the system', 'codebase overview'. Spawns code-explorer and code-architect agents to produce complete architecture documentation with feature mappings, diagrams, and PM-friendly change guidance."
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
- Visual diagrams (mermaid)
- Change guidance for common tasks

## When to Use This Skill

Use this skill when:
- Starting work on an unfamiliar codebase
- Onboarding to a project as PM or technical lead
- Needing to understand how features are implemented
- Planning major refactors or feature additions
- Creating technical documentation for stakeholders
- Auditing system architecture

**Trigger phrases**: "map the codebase", "architecture documentation", "understand this codebase", "create arch doc", "document the system", "codebase overview"

---

## Workflow

### Step 0: Generate Repomap (Optional)

Before any exploration, generate a git-activity-ranked structural summary to give agents a "lay of the land". This highlights the most actively developed files and their structure, so agents can prioritize exploration.

```bash
python ~/.claude/scripts/generate-repomap.py --repo {project_path} --max-lines 200 --days 90
```

- The output shows files ranked by recent commit frequency with extracted class/function definitions
- Include this output in code-explorer agent prompts as initial context (prefix with "Here is a repomap of the most active files:")
- If the script fails (not a git repo, no activity, Python not available), proceed without it -- this step is purely additive

### Step 1: Context Gathering

Before spawning agents, gather context:

1. **Ask the user** (if not obvious):
   - What's the primary goal? (onboarding, planning changes, documentation, audit)
   - Any specific features or areas to focus on?
   - Is there existing architecture documentation to build on?
   - What's the target audience? (PMs, engineers, stakeholders)

2. **Quick scan**:
   - Check for README, package.json, or equivalent to understand tech stack
   - Identify main directories (frontend, backend, database, etc.)
   - Look for existing docs in `docs/` or `README.md`

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

### Step 3: Subagent Task Breakdown

The orchestrator should spawn agents with these specific tasks:

**Task 1: Structure Mapping** (code-explorer)
- Scan directory tree and identify purposes
- Find all entry points (main files, routes, controllers)
- Locate config files and environment setup
- Identify third-party integrations
- **Output**: Directory structure map + initial feature list

**Task 2: Feature Tracing** (code-explorer)
- For each major feature identified:
  - Trace from UI/API → controllers → services → models
  - Document the code path
  - Identify key files with line numbers
  - Note database tables used
- **Output**: Feature-to-code mapping table

**Task 3: Architecture Analysis** (code-architect)
- Analyze database schema (tables, columns, relationships, indexes)
- Document all API endpoints with handlers
- Map authentication/authorization flows
- Create system component diagrams
- Create request flow diagrams for major features
- **Output**: Architecture diagrams + technical reference

**Task 4: Integration** (code-architect)
- Compile all findings into unified `docs/arch-plan.md`
- Create change guidance section
- Flag technical debt or undocumented areas
- Generate final mermaid diagrams
- **Output**: Complete architecture document

### Step 4: Output Structure

The final `docs/arch-plan.md` document MUST follow this structure:

```markdown
# Architecture Plan: [Project Name]

## 1. System Overview
- Purpose and capabilities
- Tech stack summary
- High-level architecture diagram (mermaid)

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
```mermaid
erDiagram
    [Your ER diagram here]
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
```mermaid
graph TD
    [Component relationships]
```

### Request Flow Examples
```mermaid
sequenceDiagram
    [Key user flows]
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

Use **mermaid** extensively (renders in markdown):

1. **ER Diagram** for database schema
2. **Component Graph** for system architecture
3. **Sequence Diagrams** for key request flows
4. **Dependency Graphs** for module relationships

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
   - `docs/arch-plan-diagrams.md` (mermaid diagrams)
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
- [ ] At least 3 mermaid diagrams present (ER, component, sequence)
- [ ] Change guidance section has 3+ concrete scenarios
- [ ] File paths are accurate and specific
- [ ] Technical debt section flags any concerns
- [ ] Document is PM-readable (not overly technical)

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

---

## Dependencies

- **lead-orchestrator**: Required for coordinating subagents
- **feature-dev:code-explorer**: Required for codebase scanning
- **feature-dev:code-architect**: Required for architecture analysis

---

## Notes for Orchestrator

When acting as orchestrator:
- **Never implement code yourself** — only spawn and coordinate subagents
- **Review each agent's output** before spawning the next
- **Escalate if >1 fix cycle needed** on any subtask
- **Commit all artifacts** as agents complete work
- **Final review**: Read complete `docs/arch-plan.md` and verify quality checklist
