# gbrain Adoption Study

> Study date: 2026-04-19
> Sources: garrytan/gbrain (v0.12.3, 9.3K stars), [Karpathy LLM Wiki gist](https://gist.github.com/karpathy/442a6bf555914893e9891c11519de94f), ~/.claude local audit
> Method: 6-agent parallel research + synthesis (3 research, 3 analysis)

## Executive Summary

gbrain is a personal knowledge management system built by Garry Tan that turns markdown files into a Postgres-backed knowledge graph with hybrid search, automatic entity linking, and tiered enrichment. It is philosophically aligned with Karpathy's LLM Wiki concept -- pre-compiled knowledge over RAG -- but goes substantially further with a self-wiring graph, durable job queue (Minions), MCP server, and always-on signal detection. It is designed as a "mod" on top of gstack, which we already run.

Our current setup (~/.claude) is heavily optimized for **engineering workflow**: TDD enforcement, QA cycles, phase gates, subagent orchestration. Our memory system (journal -> lessons -> MEMORY.md) is functional but narrow -- it captures dev session artifacts but has no entity resolution, no cross-referencing beyond manual curation, and no search beyond episodic-memory's vector/text matching. gbrain fills a genuine gap in **world knowledge management** (people, companies, ideas, research), but its memory model directly conflicts with our existing 3-tier system.

**Key decision:** Whether the value of gbrain's knowledge graph and enrichment pipeline justifies the operational complexity of running two memory systems side by side, or whether we should selectively port its best ideas into our existing architecture.

---

## 1. What is gbrain?

### 1.1 Architecture

gbrain stores knowledge in PGLite (embedded Postgres 17.5 via WASM, zero config) or optionally a managed Postgres+pgvector instance. Each knowledge page follows a **Compiled Truth + Timeline** format:

- **Above the `---`:** Living synthesis, rewritten as new information arrives
- **Below the `---`:** Append-only chronological evidence trail, never edited

The **self-wiring knowledge graph** auto-extracts entity references and creates typed links (`attended`, `works_at`, `invested_in`, `founded`, `advises`, `source`, `mentions`) with zero LLM calls -- pure heuristic extraction at F1 86.6%. Pages live in MECE directories: `people/`, `companies/`, `deals/`, `meetings/`, `projects/`, `ideas/`, `concepts/`.

**Hybrid search** combines OpenAI HNSW vector embeddings + Postgres tsvector keyword search + Reciprocal Rank Fusion + multi-query expansion (via Haiku) + 4-layer deduplication. Benchmarked Recall@5: 83-95%.

### 1.2 Key capabilities

**26 skills in 6 categories:**

| Category | Skills | Purpose |
|---|---|---|
| Always-on | signal-detector, brain-ops | Passive capture (every message), brain-first lookup |
| Ingestion | ingest, idea-ingest, media-ingest, meeting-ingestion | Voice, email, calendar, Twitter, meeting sync |
| Brain ops | query, enrich, maintain, citation-fixer, publish, data-research | Search, tiered enrichment, health checks, publish |
| Operational | daily-task-manager/prep, cron-scheduler, reports, cross-modal-review, minion-orchestrator | Task mgmt, scheduling, quality gates |
| Identity | soul-audit, setup, migrate, briefing | SOUL.md, USER.md, ACCESS_POLICY.md, HEARTBEAT.md |
| Conventions | quality.md, brain-first.md, model-routing.md, subagent-routing.md | Cross-cutting rules |

**Notable systems:**
- **Iron Law of Back-Linking:** Every entity mention creates a reciprocal back-link. "An unlinked mention is a broken brain."
- **Tiered enrichment:** Tier 3 (stub, 1 mention) -> Tier 2 (web+social, 3+ mentions) -> Tier 1 (full pipeline, 8+ mentions or post-meeting)
- **Minions:** Postgres-native durable job queue (parent-child DAGs, fan-in, timeouts, cascade cancel)
- **Autopilot:** launchd/systemd service for continuous sync, embedding, back-link maintenance
- **MCP server:** 30+ tools via stdio; also remote MCP via ngrok

Garry Tan's production instance: 17,888 pages, 4,383 people, 723 companies, 21 cron jobs.

### 1.3 Relationship to gstack

> "GStack is the engine. GBrain is the mod."

- **gstack** = coding skills (ship, review, QA, investigate, etc.). We already have 30 gstack skills symlinked.
- **gbrain** = knowledge skills (brain ops, signal detection, ingestion, enrichment, scheduling, identity).
- **Bridge:** `hosts/gbrain.ts` tells gstack to check the brain before coding. RESOLVER.md routes thinking skills to gstack when installed.
- **Complementary, not competitive.** gbrain adds a knowledge layer; gstack provides the execution engine.

---

## 2. gbrain vs Karpathy's LLM Wiki

### 2.1 Coverage matrix

| # | Karpathy Concept | gbrain | Evidence |
|---|---|---|---|
| 1 | Pre-compiled knowledge (not RAG) | **YES** | Compiled Truth + Timeline is literally this pattern |
| 2 | Three layers: Raw -> Wiki -> Schema | **YES** | Ingest skills -> brain pages -> SOUL.md/RESOLVER.md/schema.md |
| 3 | Ingest operation (source -> update wiki + index + log) | **YES** | Ingest router + 3 specialized ingest skills |
| 4 | Query operation (search -> synthesize -> optionally file back) | **PARTIAL** | query skill + hybrid search. Filing answers back as new pages is not a named first-class operation -- signal-detector captures "original thinking" which partially covers this |
| 5 | Lint operation (contradictions, orphans, stale claims) | **YES** | `maintain` skill (health checks, orphans, dead links, citation audit) + `cross-modal-review` |
| 6 | index.md (content catalog, updated on every ingest) | **YES** | index.md exists in brain directory |
| 7 | log.md (chronological append-only events) | **YES** | log.md exists in brain directory |
| 8 | Cross-referencing mandatory | **YES+** | Iron Law of Back-Linking + self-wiring knowledge graph (zero LLM calls, F1: 86.6%). Exceeds Karpathy's manual cross-referencing |
| 9 | Human curates sources + meaning; LLM does bookkeeping | **YES** | Notability gate (human judgment), ACCESS_POLICY (human control). LLM handles back-linking, enrichment, maintenance |
| 10 | Schema co-evolution (CLAUDE.md evolves with use) | **PARTIAL** | SOUL.md evolves via soul-audit, but this is identity-focused, not workflow-focused like Karpathy's vision |
| 11 | Hybrid search (qmd-like) | **YES+** | Vector + keyword + RRF + multi-query expansion. Superior to qmd |
| 12 | Notability gate (not everything gets a page) | **YES** | Explicitly implemented with documented thresholds |
| 13 | Git versioning | **NO** | PGLite/Postgres is source of truth. Timeline pattern captures per-page evidence but not whole-brain diffs/rollback |
| 14 | Domain-agnostic | **YES** | Integration recipes span personal, professional, and research |

**Score: 11 YES (2 exceeding), 2 PARTIAL, 1 NO.**

### 2.2 Where gbrain exceeds LLM wiki

| Feature | Why it matters |
|---|---|
| Self-wiring knowledge graph (typed links, F1: 86.6%) | Karpathy's cross-refs are LLM-mediated; gbrain's are deterministic and scalable |
| Signal detector (always-on) | Karpathy requires explicit ingest; gbrain captures from ambient conversation |
| Tiered enrichment auto-escalation | Pages self-improve based on mention frequency -- no Karpathy equivalent |
| Minions (durable job queue with DAGs) | Karpathy's model is synchronous; gbrain has async background processing |
| Autopilot (system service) | Continuous maintenance without user initiation |
| MECE directories with filing rules | Karpathy allows organic growth; gbrain enforces structural discipline |
| Meeting/media/idea specialized ingest | Modality-specific processing vs Karpathy's generic ingest |
| 26 skills with MCP exposure (30+ tools) | Full platform vs pattern description |
| Soul/identity layer (SOUL.md, USER.md) | Identity and access control as first-class concepts |
| Cron scheduling + daily task management | Proactive scheduling vs Karpathy's reactive model |

### 2.3 Gaps

| Gap | Detail |
|---|---|
| Git versioning | Karpathy uses git for whole-brain diffs, blame, rollback. gbrain's Timeline is per-page evidence, not version history. Different tradeoff, not strictly worse. |
| Simplicity as a feature | Karpathy's design fits in your head: markdown + git + search CLI. gbrain is 26 skills, Postgres, MCP, autopilot. The complexity may be justified but it is real. |
| Answer compounding | Karpathy: good query answers get filed back as wiki pages. gbrain approximates this via enrichment and signal-detector but doesn't codify it as a named operation. |

### 2.4 Verdict

**gbrain is a superset of Karpathy's LLM Wiki.** All core ideas are covered (11 fully, 2 partially). The one genuine gap -- git versioning -- is an architectural choice. gbrain then adds substantial machinery Karpathy did not propose. The philosophical tension is minimalism vs. completeness: Karpathy's design is a pattern you could implement in an afternoon; gbrain is a full knowledge operating system.

---

## 3. gbrain vs Our Current Setup

### 3.1 What we have today

| Category | Implementation |
|---|---|
| Memory | 3-tier: journal.md (30K lines) -> synthesize-lessons.py (2x daily) -> lessons.md (86 lines). Also: MEMORY.md index, episodic-memory plugin, per-project MEMORY.md files |
| Skills | 70 total: 31 custom + 30 gstack (symlinked) + 7 PM-OS + 2 misc |
| Protocol | VIBE: 20 hard gates (R0-R19), phase gates, 5 roles, 2 QA cycles |
| Hooks | 8: git-safety, RTK, task-spec-gate, context-guard, notify, auto-journal, PM synthesis, notification |
| Plugins | 11: superpowers, episodic-memory, code-review, LSPs, code-review-graph, scheduler, codex |
| Scheduled | 8 tasks: synthesis 2x daily, weekly cleanup/audit, PM-OS crons |

### 3.2 The five knowledge stores problem

Installing gbrain would create a fifth knowledge store:

| Store | Location | Format | Write trigger | Search tool |
|---|---|---|---|---|
| Journal | `~/.claude/memory/journal.md` | Markdown entries | Stop hook | Manual read |
| Lessons | `~/.claude/memory/lessons.md` | Curated markdown | 2x daily synthesis | Manual read |
| Episodic memory | Plugin database | Vector embeddings | Plugin internals | MCP search |
| gstack learn | `~/.gstack/projects/*/learnings.jsonl` | JSONL | Per-session | gstack CLI |
| **gbrain** | `~/brain/**/*.md` + PGLite | Compiled Truth | Signal detector (every message) | gbrain hybrid search |

An agent asked "what do we know about X?" would need to search 3-4 stores. This is the core adoption tension.

### 3.3 Overlap analysis

| Feature Area | Our Implementation | gbrain's | Conflict Risk |
|---|---|---|---|
| **Session capture** | auto-journal hook -> journal.md (per-session) | Signal detector (every message -> Postgres) | **HIGH** -- double-capturing, double-searching |
| **Knowledge synthesis** | synthesize-lessons.py -> lessons.md (global) | Compiled Truth (per-entity, continuous) | **MEDIUM** -- different granularity, same goal |
| **Memory search** | episodic-memory (vector + text) | Hybrid search (vector + keyword + RRF + expansion) | **HIGH** -- competing indexes, query routing ambiguity |
| **Skill routing** | VIBE protocol (role + phase based) | RESOLVER.md (skill type based) | **HIGH** -- two routing systems with different dispatch logic |
| **Scheduling** | scheduler plugin (8 cron tasks, launchd) | cron-scheduler + Minions + autopilot (also launchd) | **MEDIUM** -- duplicate launchd plists possible |
| **Identity** | personal.md + CLAUDE.md (workflow-focused) | SOUL.md + USER.md + ACCESS_POLICY.md (personality-focused) | **LOW** -- different purposes |
| **Code search** | code-review-graph (Tree-sitter, structural) | Not focused on code | **SAFE** -- complementary |
| **Git safety** | git-safety-hook.sh, protected-files.md | No equivalent | **SAFE** |
| **Token optimization** | RTK (60-90% savings) | No equivalent | **SAFE** |

### 3.4 What gbrain genuinely adds

1. **Entity resolution and knowledge graph** -- We have zero entity tracking. gbrain auto-extracts people, companies, concepts and wires them into a relationship graph. This is the single biggest capability gap.

2. **Tiered enrichment** -- Our lessons.md is flat. gbrain's Tier 3->2->1 progression means stubs mature into full syntheses organically based on mention frequency.

3. **Ingestion pipelines** -- We have no way to ingest voice memos, emails, calendar events, or meeting transcripts into our knowledge base.

4. **Compiled Truth format** -- Our journal.md is append-only with no per-topic synthesis. gbrain ensures you always read the current understanding, with evidence preserved below.

5. **Better search** -- gbrain's RRF + multi-query expansion demonstrably outperforms episodic-memory's simpler vector+text matching.

### 3.5 What we have that gbrain lacks

1. **VIBE Protocol** -- 20 hard gates, phase enforcement, role separation, TDD mandate, 2 QA cycles, N=1 escalation. gbrain has zero engineering process enforcement.

2. **31 custom skills** -- design-implement, eng-planning, lead-orchestrator, systematic-debugging, pr-review suite. Engineering workflow, not knowledge management.

3. **PM-OS** -- 7 skills for product management workflow. gbrain has daily-task-manager but no stakeholder comms pipeline.

4. **Engineering guardrails** -- git-safety hook, protected-files, task-spec-gate, orchestrator-context-guard. gbrain has ACCESS_POLICY but no pre-commit enforcement.

5. **RTK token optimization** -- 60-90% savings. gbrain has no token efficiency layer.

6. **Git-native audit trail** -- Every change to our knowledge base is a git commit with diff, blame, rollback. gbrain stores in Postgres.

7. **Codex adversarial review** -- Independent GPT-5.4 second opinion on code. Not in gbrain.

### 3.6 Risk assessment

| Risk | Probability | Blast Radius | Reversible? |
|---|---|---|---|
| Skill routing confusion (VIBE vs RESOLVER.md) | HIGH | HIGH -- agents take wrong actions | Yes -- remove RESOLVER.md |
| Search fragmentation (5 knowledge stores) | HIGH | MEDIUM -- degraded answers, wasted tokens | Yes -- disable gbrain search |
| Signal detector token burn (fires every message) | MEDIUM | MEDIUM -- higher bill, faster context exhaustion | Yes -- disable signal detector |
| Scheduler/autopilot conflict (two launchd plists) | MEDIUM | MEDIUM -- duplicate jobs, resource contention | Yes -- unload plist |
| Hook chain slowdown (more hooks = slower tool calls) | MEDIUM | LOW -- latency increase per tool call | Yes -- remove hooks |
| gstack bridge modifies tracked repo | LOW | MEDIUM -- unexpected git changes in ~/Code/gstack | Yes -- git checkout |
| settings.json corruption during install | LOW | HIGH -- breaks entire Claude Code | Yes -- restore from git |
| PGLite corruption | LOW | LOW -- only affects gbrain | Yes -- delete data dir |

---

## 4. Adoption Options

### Option A: Full Adoption

**What:** Install gbrain, migrate journal/lessons to brain pages, deprecate auto-journal + synthesize-lessons.py, use gbrain as primary knowledge store. Keep VIBE, custom skills, and engineering guardrails unchanged.

| Dimension | Assessment |
|---|---|
| **Pros** | Single source of truth. Entity graph + enrichment immediately available. gbrain's search is better. No dual-system confusion. |
| **Cons** | Migration risk: 30K journal lines contain dev session context that doesn't map to entity model. Loss of git audit trail. Postgres corruption harder to recover than git revert. Our synthesis pipeline is tuned for dev workflow; gbrain's enrichment is tuned for people/companies/deals. |
| **Risk** | **HIGH** -- Our memory system works. Replacing wholesale risks context loss and workflow disruption for speculative gain. |
| **Effort** | 3-5 days migration, 1-2 weeks stabilization |

### Option B: Selective Integration (cherry-pick patterns)

**What:** Port specific gbrain patterns into our existing architecture without installing gbrain.

**Candidates to port:**
- **Compiled Truth format** -- Restructure lessons.md: synthesis above, evidence below. Modified synthesize-lessons.py.
- **Tiered enrichment** -- Mention counting in synthesize-lessons.py; frequently-referenced topics promote to dedicated files under `memory/topics/`.
- **Entity extraction heuristics** -- Port gbrain's zero-LLM extraction (F1: 86.6%) as post-processing in session-journal.py to auto-tag people, repos, concepts.
- **Iron Law of Back-Linking** -- Cross-reference maintenance in synthesis pipeline.

| Dimension | Assessment |
|---|---|
| **Pros** | No new dependencies. Preserves git audit trail. Incremental, each piece independently testable and reversible. Engineering guardrails untouched. |
| **Cons** | Reimplementing tested code (gbrain's heuristics are production-proven on 17K pages). No knowledge graph -- patterns without structure. No ingestion pipelines. We own the ported code. |
| **Risk** | **LOW** -- Each piece is independently valuable and reversible. |
| **Effort** | 2-3 days per feature, spread across sprints |

### Option C: Parallel Run (domain partition)

**What:** Install gbrain alongside existing setup. Partition by domain.

| Domain | System |
|---|---|
| People, companies, meetings, ideas, research | gbrain (`~/brain/`) |
| Dev sessions, debugging, TDD evidence, architecture | journal/lessons/episodic-memory |

| Dimension | Assessment |
|---|---|
| **Pros** | Each system does what it's best at. No migration. gbrain's ingestion pipelines available for non-dev knowledge. Can evaluate before deeper commitment. |
| **Cons** | Two systems to query. Signal detector + auto-journal both fire -- need configuration or accept duplication. Cognitive overhead: which system do I ask? RESOLVER routing ambiguity remains. The partition is conceptually clean but leaky ("I discussed the API design with Alice at Tuesday's meeting" -- meeting note or dev session?). |
| **Risk** | **MEDIUM** -- Domain boundary is inherently fuzzy. |
| **Effort** | 1-2 days install + configure, ongoing discipline |

**Minimum safe installation path (if choosing C):**
1. Do NOT let gbrain modify `settings.json` hooks -- add MCP server only
2. Disable signal detector (use our journal instead for session capture)
3. Disable gbrain's scheduler (use ours)
4. Disable RESOLVER.md routing (keep VIBE)
5. Use `~/brain/` as enrichment layer for explicit knowledge queries, not as competing search target

### Option D: Wait and Watch

**What:** Don't adopt now. Revisit when conditions change.

| Dimension | Assessment |
|---|---|
| **Pros** | Zero risk, zero effort. Current system works. gbrain is pre-1.0 (breaking changes likely). More time to evaluate real-world reports. |
| **Cons** | Compiled Truth and tiered enrichment are genuinely better patterns than what we have. If we adopt later, migration harder with more accumulated data. Miss ingestion pipelines if needs emerge. |
| **Risk** | **NONE** |

**Revisit when:**
- gbrain reaches 1.0 with stable API
- We need to track 50+ people/companies (flat memory model becomes insufficient)
- We need voice/email/calendar ingestion for a specific project
- episodic-memory plugin hits recall or precision wall

---

## 5. Recommendation

### 5.1 Recommended path

**Option B (Selective Integration) now, with Option C (Parallel Run) as Phase 2 if world-knowledge needs emerge.**

Rationale: Our setup is heavily optimized for engineering workflow and that part works. gbrain's genuine value-add is world-knowledge management (people, companies, meetings), which is not our current bottleneck. The patterns gbrain has proven -- Compiled Truth, tiered enrichment, back-linking -- are independently valuable and portable without the full system. Taking those patterns lets us improve our memory architecture without Postgres dependency risk, RESOLVER routing conflicts, or dual-system cognitive overhead.

Option C becomes right if/when we start tracking relationships, meetings, or research at scale. By then we'll have already improved our memory format (via Option B), making the domain partition cleaner.

Option A is premature. Dev session memory doesn't map to gbrain's entity model. Option D is defensible but leaves known improvements on the table.

### 5.2 Implementation roadmap

**Phase 1: Pattern adoption (Option B) -- ~1 week**

1. **Compiled Truth format** -- Restructure `synthesize-lessons.py` to produce above-the-line synthesis + below-the-line evidence per lesson. Each lesson becomes a mini Compiled Truth page.
2. **Mention counting** -- Add frequency tracking to `session-journal.py`. Topics referenced 3+ times promote to dedicated files under `memory/topics/`.
3. **Back-link maintenance** -- When synthesis creates/updates a topic file, scan for entity references and add `See also:` links.

**Phase 2: Evaluation gate -- 2 weeks after Phase 1**

- Is the improved memory format sufficient?
- Have we started tracking people/companies/research that warrants a graph?
- Has gbrain stabilized toward 1.0?

**Phase 3: Parallel Run (Option C) -- if gate passes, ~1 week**

1. Install gbrain (`git clone && bun install && bun link`)
2. `gbrain init` (PGLite, 2 seconds)
3. Configure: disable signal detector, disable scheduler, disable RESOLVER routing
4. Add MCP server to `settings.json` (tools only, no hooks)
5. Import relevant non-dev knowledge
6. Set up autopilot for embeddings + back-links only
7. Run 2 weeks, evaluate search quality and cognitive overhead

### 5.3 Decision criteria that would change this recommendation

| Condition | New recommendation |
|---|---|
| Start managing 50+ relationships (investors, collaborators, contacts) | Immediate Option C |
| gbrain 1.0 ships with git-backed storage and migration tools | Reconsider Option A |
| episodic-memory plugin degrades (recall drops, corruption) | Accelerate any adoption |
| gbrain adds engineering workflow features (TDD, code review) | Reduces Option A risk |
| Bun runtime causes conflicts with existing toolchain | Blocks any gbrain installation |

---

## 6. Appendix

### 6.1 Prerequisites

| Dependency | Status | Notes |
|---|---|---|
| Bun runtime | Already installed (v1.3.11) | No action needed |
| OpenAI API key | Already configured (`~/.gstack/openai.json`) | Needed for HNSW embeddings |
| Anthropic API key | Already configured | Optional, improves multi-query expansion |
| Disk (~500MB) | Available | PGLite grows with page count |
| macOS LaunchAgent | Scheduler already uses launchd | Potential conflict -- review before installing autopilot |

### 6.2 Key gbrain commands

```bash
gbrain init                    # Initialize brain + PGLite (2 seconds)
gbrain add <file>              # Ingest a document
gbrain search <query>          # Hybrid search across all pages
gbrain page <entity>           # View/create an entity page
gbrain enrich                  # Run tiered enrichment pass
gbrain backlink                # Run back-link maintenance
gbrain embed                   # Rebuild vector embeddings
gbrain status                  # Show brain stats
gbrain mcp serve               # Start MCP server (stdio)
gbrain autopilot --install     # Install system service
```

### 6.3 Files gbrain would create

```
~/.gbrain/                          # Config + PGLite database
  brain.pglite                      # Embedded Postgres data
  preferences.json                  # User settings
  update-state.json                 # Schema adoption tracking

~/brain/                            # Knowledge directory (MECE)
  RESOLVER.md, schema.md, index.md, log.md
  people/  companies/  deals/  meetings/
  projects/  ideas/  concepts/  writing/
  programs/  org/  sources/  prompts/  inbox/

~/Library/LaunchAgents/
  com.gbrain.autopilot.plist        # macOS autopilot service (if enabled)
```

### 6.4 Ingestion Plan (by source)

#### OneDrive (`~/OneDrive/Work/`)

**Corpus:** 11GB total, ~2,600 markdown files ready to ingest.

| Priority | Directory | Files | Value |
|---|---|---|---|
| HIGH | `Org/` | 83 MD | Strategy docs, implementation plans |
| HIGH | `Shared/` | 806 MD | Audit minutes, governance, protocols |
| HIGH | `AI board materials/` (selective) | ~200 of 1,687 MD | Board minutes (skip repetitive financial extracts) |
| HIGH | Top-level MDs | ~5 | Integration guides, notes |
| LOW | `Code/`, `Screenshots/`, `PPTs/`, `Readings/` | — | Skip (code, images, needs conversion, book excerpts) |

```bash
# Day 1 commands:
gbrain import ~/OneDrive/Work/Org/
gbrain import ~/OneDrive/Work/Shared/
gbrain import ~/OneDrive/Work/AI\ board\ materials/ --limit 200
gbrain backlink && gbrain embed
```

**Non-markdown (263 docx, 326 pptx, 323 pdf):** Convert later with `pandoc file.docx -t markdown -o file.md`.

#### Notion

| Option | When to use | Effort | Quality |
|---|---|---|---|
| Native export (MD & CSV) | Mostly prose, <500 pages | 1-2 hours | Good (links break, DB properties lost) |
| notion-to-md script | Database-heavy, >500 pages | 3-4 hours | Better (preserves properties as frontmatter) |
| MCP tools | Ad-hoc, 5-10 pages | 30 min | Fine for on-demand, doesn't scale |

**Gotcha:** Notion appends 32-char hex UUIDs to every filename. Strip before import.

#### Outlook & Teams

**Key finding:** gbrain has NO Outlook/Teams support (Gmail only). But pm_os already has production-grade collectors:
- `outlook-read-mail.js` — Graph API, FOCI token auth
- `teams-read-chats.js` — Skype messaging API, 1:1 + group chats
- `teams-read-channels.js` — Channel messages
- `ensure-tokens.js` — Auto-refreshes 90-day FOCI tokens
- `run-morning.js` — Already orchestrates parallel fetch, dedup, classification

**Recommended:** Write ~200-line adapter script (pm_os JSON → gbrain markdown pages). Or simpler: add brain-write step to existing `run-morning.js` pipeline.

**Privacy:** Delegated permissions (your own mailbox), data stays local, FOCI tokens at `~/.pm-os-foci-token.json` (0o600).

#### Ingestion priority

| Source | Effort | Payoff | When |
|---|---|---|---|
| OneDrive markdown | 10 min (one command) | Immediate — 900+ high-value docs | Day 1 |
| Notion export | 1-4 hours | Immediate — depends on volume | Day 1-2 |
| Outlook/Teams adapter | 1-2 days (write adapter) | Ongoing — relationship graph daily | Week 1 |
| OneDrive non-markdown | 2-4 hours (pandoc) | Medium — older docs | When needed |

### 6.5 Platform Requirements

gbrain does NOT require Hermes or OpenClaw. Those are optional hosting platforms. gbrain works standalone:

| Mode | How | What you get |
|---|---|---|
| **CLI standalone** | `git clone && bun install && bun link && gbrain init` | Full brain, PGLite, all CLI commands |
| **MCP for Claude Code** | `claude mcp add gbrain -- gbrain serve` | 30+ MCP tools in Claude Code |
| **Remote MCP** | ngrok + HTTP (for Claude Desktop, Cowork) | Remote tool access |

**What needs a platform workaround:**
- Cron jobs → use our existing scheduler or system crontab
- Minions worker → `gbrain jobs work` as background daemon
- Signal detector "spawn parallel" → skip or use Stop hook instead
- Credential gateway (ClawVisor) → direct OAuth credentials

### 6.6 Karpathy LLM Wiki -- key ideas not in gbrain

For reference, the only LLM Wiki concepts not fully covered:

1. **Git as version history** -- Karpathy treats the wiki as a git repo. gbrain uses Postgres. Trade-off: git gives diffs/blame/rollback; Postgres gives query performance and graph operations.
2. **Schema co-evolution** -- Karpathy's vision of CLAUDE.md evolving as the wiki grows is more ambitious than gbrain's soul-audit, which is identity-focused rather than workflow-focused.
3. **Answer compounding** -- Explicitly filing good query answers back as new wiki pages. gbrain approximates via enrichment and signal detection but doesn't name this as a first-class operation.
