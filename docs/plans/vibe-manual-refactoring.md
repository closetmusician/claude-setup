# Plan: vibe-manual.md Refactoring

## Context

`~/.claude/docs/vibe-manual.md` (744 lines) is the source-of-truth VIBE protocol. It contains several boardroom-ai-specific patterns stated as universal rules, verbose phrasing, and project trivia that wastes context in non-boardroom sessions. The user confirmed that **cross-role rule repetition is intentional** and stays — Claude benefits from seeing rules in context.

**Goal:** Generalize patterns, losslessly compress, extract project trivia. Target: ~650 lines (down from 744).

**Files modified:**
- `~/.claude/docs/vibe-manual.md` — primary (all 3 streams)
- `/Users/yklin/Code/boardroom-ai/CLAUDE.md` — append project-specific pitfalls

---

## Stream 1: Generalize Patterns (generic principle + labeled example)

For each section, add a 1-2 line generic **Principle**, then relabel existing content as **Example**. Existing enforcement detail stays intact.

| Section | Lines | What Changes |
|---------|-------|-------------|
| Schema-Persistence Alignment (QA checklist §6.5.1 item 1) | 371-376 | Add principle: "Validation constraints MUST match persistence constraints." Relabel Pydantic/SQLAlchemy as example. Drop `api/schemas/*.py` paths. |
| Schema Design Rules (§7) | 693-710 | Add principle. Merge items 1+2 (said the same thing). Keep Pydantic example labeled. 18→10 lines. |
| READ-WRITE Consistency (§6.5.1 item 3) | 410-412 | Add principle: "Read endpoint values MUST be accepted by write endpoints." Drop `/api/filters`. |
| Build ≠ Test (§6.5.1 item 5) | 392-396 | Add principle: "Build command MUST pass during QA, not just test runner. Failure = P0." Keep tsc/Vitest as labeled example. 5→3 lines. |
| E2E Infrastructure (§6.5.3) | 494-507 | Add principle: "E2E needs config, setup, teardown, runner. All config in one file." Label directory tree as example. Remove `boardroom-ai/` from paths. |
| E2E Two-Mode Testing (§6.5.3) | 514-523 | Add principle: "Scripted regression + interactive visual verification." Collapse 3-row table to 2 rows. Remove Chrome DevTools MCP specifics. |
| Automated Schema Checks (§6.5.2) | 414-482 | Add principle. **Reduce 3 code blocks to 1** (keep bash script, recommended). 69→22 lines. Biggest single savings (~47 lines). |
| Debugging investigation checklist (§5.6) | 221-227 | Generalize `api/db/models.py` → "persistence models", `api/schemas/*.py` → "validation schemas". |
| Tech Stack (§4) | 124 | Relabel header: "## 4. Tech Stack (Default — override in project CLAUDE.md)" |
| Repo Structure filenames (§3) | 100-101 | Replace `benchmarking-prototype-*` with `<project>-*` |
| PM Interviewer output (§5.1) | 134 | Replace `benchmarking-prototype-master-prd.md` with `<project>-master-prd.md` |
| Architect output (§5.2) | 137 | Same: `benchmarking-prototype-architecture.md` → `<project>-architecture.md` |

---

## Stream 2: Lossless Compression

| Target | Lines | Change | Savings |
|--------|-------|--------|---------|
| `(added YYYY-MM-DD ...)` chronology tags | scattered | Remove all — git history, not protocol | ~6 inline |
| `(existing)` tags | 378,382,387 | Remove — adds nothing | inline |
| File header | 2-5 | 3 blockquote lines → 1 dense line | 2 |
| Phase gate JSON example | 81-83 | Inline into preceding text | 3 |
| Bug severity table | 162-167 | 4-column table → inline paragraph | 5 |
| VIBE Levels §0.1 | 30-68 | Merge enforced/skipped bullet lists into single comparison table | ~10 |
| Worktree setup bash | 295-299 | 3 commands → 1 chained line | 2 |
| Progress log example | 550-578 | 29 lines → 15 lines (merge rows, compress events) | 14 |
| Orchestrator intro | 239-241 | Tighten phrasing | 1 |

---

## Stream 3: Move Project-Specific Content

**From vibe-manual.md lines 525-533 → boardroom-ai/CLAUDE.md:**
- Port mappings (3456/8000, 3000/8080)
- Route patterns (`/project/{id}` singular, `/api/` prefix rules)
- Test user creation via `/test/create-user`
- Stale DB docker compose commands
- JWT expiry timing
- Missing DB migration docker-compose check

**In vibe-manual.md**, replace 9-line pitfalls list with:
```
**Common Pitfalls:**
- Shell escaping — use native HTTP libraries for JSON payloads, never shell-escaped curl
- See project CLAUDE.md for project-specific pitfalls (ports, routes, credentials)
```

**In boardroom-ai/CLAUDE.md**, append new `## E2E Pitfalls` section with the 7 extracted items.

---

## Execution

Single coder agent, edits applied bottom-up within each stream to preserve line numbers. Re-read file between streams.

Order: Stream 1 (generalize) → Stream 2 (compress) → Stream 3 (move) → Verification

**Verification checklist:**
- [ ] Line count ~650 (± 20)
- [ ] All 19 rules R0-R18 still present (grep for each)
- [ ] All role sections (§5.1-5.5) intact with enforcement details
- [ ] All templates (baton file, QA cycles, feature spec) intact
- [ ] Cross-role repetition preserved (R16/R17/R18 in §5.3, §5.4, §5.5, §6.0)
- [ ] boardroom-ai CLAUDE.md has new E2E Pitfalls section
- [ ] No broken markdown
- [ ] git commit both files

**Constraint:** `vibe-manual.md` is a protected file — in-place edits only, never delete/recreate.
