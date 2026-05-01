# gbrain Setup Plan — Option 2 (Parallel Coexistence)

> Created: 2026-04-20
> Reference: `docs/learnings/gbrain-study.md` (full research + tradeoff analysis)
> Goal: Install gbrain alongside existing ~/.claude setup with zero disruption, bulk-ingest all ~/OneDrive/Work/ documents

## Scope

Install gbrain as a standalone MCP server for world-knowledge (people, companies, meetings, ideas). Our existing setup (VIBE protocol, 70 skills, hooks, memory system, PM-OS) remains untouched. No features deprecated. Clean domain partition: gbrain owns world-knowledge, our system owns dev workflow.

## What Changes vs What Doesn't

**The ONLY change to our setup:** `claude mcp add gbrain` registers a new MCP server subprocess. This is a Claude Code MCP registry entry — it does NOT modify `~/.claude/settings.json`, hooks, skills, rules, memory, plugins, or any existing file.

**Everything that stays exactly the same:**
- `~/.claude/settings.json` — all hooks, permissions, env vars, plugins untouched
- `~/.claude/skills/` — all 70 skills (31 custom + 30 gstack + 7 PM-OS + 2 misc) unchanged
- `~/.claude/rules/` — VIBE protocol, code-style, protected-files unchanged
- `~/.claude/memory/` — journal.md, lessons.md, MEMORY.md unchanged
- `~/.claude/hooks/` — RTK rewrite, git-safety unchanged
- `~/.claude/scripts/` — all 18 scripts unchanged
- `~/.claude/plugins/` — all 11 plugins unchanged
- All scheduled tasks, PM-OS crons, synthesis pipeline unchanged

**New directories created (isolated from ~/.claude/):**
- `~/Code/gbrain/` — gbrain source code
- `~/.gbrain/` — PGLite database + config
- `~/brain/` — knowledge directory (markdown files)
- `~/gbrain-import/` — temporary staging (deleted after import)

## How to Use gbrain

### In Claude Code (automatic)

gbrain's MCP tools are visible to Claude alongside our existing tools. Claude routes automatically based on what you ask:

```
"What do we know about Acme Corp?"
→ Claude calls gbrain search + get_page MCP tools

"Debug this failing test"
→ Claude uses our existing tools (investigate, VIBE protocol)
```

No special syntax needed. Claude sees both tool sets and picks the right one.

### In Claude Code (explicit)

If you want to force gbrain usage or be specific:

```
"Search gbrain for audit minutes Q3 2024"
"Add this meeting note to the brain"
"What entities does gbrain know about?"
```

### Routing: how Claude decides gbrain vs existing tools

No deterministic router — Claude matches your intent to MCP tool descriptions (e.g., `search` = "Search brain pages using hybrid vector+keyword search"). Tool name collision is low; `ENABLE_TOOL_SEARCH=auto:5` lazy-loads tools by relevance so gbrain tools only surface for knowledge queries. If Claude misroutes, say "search gbrain for X" to be explicit. If misrouting becomes frequent, add a `## Knowledge routing` section to CLAUDE.md mapping domains to tool sets. Start without routing rules — add them only if needed.

### From the terminal (CLI)

gbrain has ~40 CLI commands usable directly:

```bash
gbrain search "board materials"    # Hybrid search
gbrain status                      # Page/link/embedding counts
gbrain doctor                      # Health check
gbrain page people/alice-chen      # View a specific page
gbrain import ~/new-notes/         # Ingest new files
gbrain backlink                    # Refresh entity links
gbrain embed --stale               # Update vector index
```

## Prerequisites

- [x] Bun runtime installed (v1.3.11 at ~/.bun/bin/bun)
- [x] OpenAI API key configured (~/.gstack/openai.json)
- [x] Pandoc installed (/opt/homebrew/bin/pandoc)
- [x] pdftotext installed (/opt/homebrew/bin/pdftotext)
- [x] pymupdf4llm, python-pptx, openpyxl, pdfplumber, html2text (pip)
- [x] deck_trends converter at ~/Code/deck_trends/src/convert.py (PDF + PPTX → MD)
- [ ] ~/OneDrive/Work/Code/ removed (confirmed by user)

---

## Phase 1: Install gbrain (10 min)

### 1.1 Clone and build

```bash
cd ~/Code
git clone https://github.com/garrytan/gbrain.git
cd gbrain
bun install
bun link
```

### 1.2 Initialize brain with PGLite

```bash
gbrain init
# Creates ~/.gbrain/ (config) and ~/brain/ (knowledge directory)
# PGLite embedded Postgres, zero config, ~2 seconds
```

### 1.3 Wire MCP server to Claude Code

```bash
claude mcp add gbrain -- gbrain serve
```

This adds gbrain's 30+ MCP tools to Claude Code as a stdio subprocess. No hooks, no settings.json modifications, no RESOLVER.md routing.

### 1.4 Verify

```bash
gbrain status
# Should show: 0 pages, 0 links, PGLite engine
```

### 1.5 What NOT to do

- Do NOT symlink gbrain skills into ~/.claude/skills/ (avoids RESOLVER routing conflict with VIBE)
- Do NOT enable signal detector (avoids collision with our auto-journal hook)
- Do NOT install gbrain's autopilot launchd plist yet (avoids conflict with our scheduler)
- Do NOT modify ~/.claude/settings.json hooks

---

## Phase 2: Mass Convert Non-Markdown Files (30-60 min)

### 2.1 Overview

~/OneDrive/Work/ contains ~4,200 ingestible files. gbrain only accepts .md/.mdx.

| Format | Count | Converter | Status |
|---|---|---|---|
| .md | 2,596 | None needed | Ready |
| .txt | 625 | Rename to .md | Ready |
| .pptx | 326 | deck_trends convert.py (python-pptx) | Ready |
| .pdf | 323 | deck_trends convert.py (pymupdf4llm) | Ready |
| .docx | 263 | pandoc | Ready |
| .xlsx | 135 | openpyxl → CSV → MD | Script needed |
| .html | 47 | html2text | Ready |
| **Total** | **4,315** | | |

Skip: .png/.jpg/.jpeg/.svg (images, ~400 files), .mp4 (15), .zip (13), .har (7), .py/.pyc/.js (dev artifacts still present outside Code/)

### 2.2 Create staging directory

```bash
mkdir -p ~/gbrain-import
```

All conversions write to ~/gbrain-import/ to avoid mutating ~/OneDrive/Work/ originals.

### 2.3 Copy existing markdown files

```bash
# Copy all .md files preserving directory structure
cd ~/OneDrive/Work
find . -name '*.md' -not -path '*/Code/*' -not -path '*/.git/*' \
  | rsync -av --files-from=- . ~/gbrain-import/
```

### 2.4 Convert .txt → .md

```bash
# Rename copies (don't touch originals)
find ~/OneDrive/Work -name '*.txt' -not -path '*/Code/*' | while read f; do
  rel="${f#$HOME/OneDrive/Work/}"
  dest="$HOME/gbrain-import/${rel%.txt}.md"
  mkdir -p "$(dirname "$dest")"
  cp "$f" "$dest"
done
```

### 2.5 Convert .docx → .md (pandoc)

```bash
find ~/OneDrive/Work -name '*.docx' -not -path '*/Code/*' | while read f; do
  rel="${f#$HOME/OneDrive/Work/}"
  dest="$HOME/gbrain-import/${rel%.docx}.md"
  mkdir -p "$(dirname "$dest")"
  pandoc "$f" -t markdown --wrap=none -o "$dest" 2>/dev/null
done
echo "DOCX conversion complete"
```

### 2.6 Convert .pdf → .md (deck_trends converter)

```bash
# Option A: Use deck_trends converter (handles frontmatter, logging)
python3 ~/Code/deck_trends/src/convert.py \
  --input ~/OneDrive/Work \
  --output ~/gbrain-import/pdf-converted/ \
  --format pdf

# Option B: If deck_trends CLI doesn't support --input directory scan,
# use pymupdf4llm directly:
find ~/OneDrive/Work -name '*.pdf' -not -path '*/Code/*' | while read f; do
  rel="${f#$HOME/OneDrive/Work/}"
  dest="$HOME/gbrain-import/${rel%.pdf}.md"
  mkdir -p "$(dirname "$dest")"
  python3 -c "
import pymupdf4llm
md = pymupdf4llm.to_markdown('$f')
with open('$dest', 'w') as out:
    out.write(md)
" 2>/dev/null
done
echo "PDF conversion complete"
```

### 2.7 Convert .pptx → .md (deck_trends converter)

```bash
# Same approach as PDF — deck_trends handles PPTX natively
find ~/OneDrive/Work -name '*.pptx' -not -path '*/Code/*' | while read f; do
  rel="${f#$HOME/OneDrive/Work/}"
  dest="$HOME/gbrain-import/${rel%.pptx}.md"
  mkdir -p "$(dirname "$dest")"
  python3 -c "
from pptx import Presentation
prs = Presentation('$f')
lines = []
for i, slide in enumerate(prs.slides, 1):
    lines.append(f'## Slide {i}')
    for shape in slide.shapes:
        if shape.has_text_frame:
            for para in shape.text_frame.paragraphs:
                text = para.text.strip()
                if text:
                    lines.append(text)
    lines.append('')
with open('$dest', 'w') as out:
    out.write('\n'.join(lines))
" 2>/dev/null
done
echo "PPTX conversion complete"
```

### 2.8 Convert .html → .md (html2text)

```bash
find ~/OneDrive/Work -name '*.html' -not -path '*/Code/*' | while read f; do
  rel="${f#$HOME/OneDrive/Work/}"
  dest="$HOME/gbrain-import/${rel%.html}.md"
  mkdir -p "$(dirname "$dest")"
  python3 -c "
import html2text
h = html2text.HTML2Text()
h.body_width = 0
with open('$f') as inp:
    md = h.handle(inp.read())
with open('$dest', 'w') as out:
    out.write(md)
" 2>/dev/null
done
echo "HTML conversion complete"
```

### 2.9 Convert .xlsx → .md (openpyxl)

```bash
find ~/OneDrive/Work -name '*.xlsx' -not -path '*/Code/*' | while read f; do
  rel="${f#$HOME/OneDrive/Work/}"
  dest="$HOME/gbrain-import/${rel%.xlsx}.md"
  mkdir -p "$(dirname "$dest")"
  python3 -c "
import openpyxl
wb = openpyxl.load_workbook('$f', data_only=True)
lines = []
for sheet_name in wb.sheetnames:
    ws = wb[sheet_name]
    lines.append(f'## {sheet_name}')
    rows = list(ws.iter_rows(values_only=True))
    if not rows:
        continue
    # Header
    header = [str(c) if c is not None else '' for c in rows[0]]
    lines.append('| ' + ' | '.join(header) + ' |')
    lines.append('| ' + ' | '.join(['---'] * len(header)) + ' |')
    for row in rows[1:]:
        cells = [str(c) if c is not None else '' for c in row]
        lines.append('| ' + ' | '.join(cells) + ' |')
    lines.append('')
with open('$dest', 'w') as out:
    out.write('\n'.join(lines))
" 2>/dev/null
done
echo "XLSX conversion complete"
```

### 2.10 Verify staging directory

```bash
echo "=== File counts in staging ===" 
find ~/gbrain-import -name '*.md' | wc -l
echo ""
echo "=== Total size ==="
du -sh ~/gbrain-import/
echo ""
echo "=== By source directory ==="
find ~/gbrain-import -name '*.md' | cut -d/ -f5 | sort | uniq -c | sort -rn | head -15
echo ""
echo "=== Spot-check: sample files ==="
find ~/gbrain-import -name '*.md' -size +1k | head -5 | while read f; do
  echo "--- $f ($(wc -l < "$f") lines) ---"
  head -5 "$f"
  echo ""
done
```

### 2.11 Clean up conversion artifacts

```bash
# Remove empty files (failed conversions)
find ~/gbrain-import -name '*.md' -empty -delete
# Count what remains
echo "Files ready for import:"
find ~/gbrain-import -name '*.md' | wc -l
```

---

## Phase 3: Bulk Import into gbrain (15-30 min)

### 3.1 Import all converted files

```bash
gbrain import ~/gbrain-import/
```

This reads all .md files recursively, parses frontmatter, and stores pages in PGLite.

### 3.2 Wire the knowledge graph

```bash
# Auto-extract entity references and create typed back-links
gbrain backlink
```

### 3.3 Build vector embeddings

```bash
# Build HNSW vector index for hybrid search (requires OpenAI API key)
gbrain embed
```

### 3.4 Verify import

```bash
# Check stats
gbrain status
# Expected: ~3,500-4,000 pages, N links, N embeddings

# Test search
gbrain search "audit minutes"
gbrain search "board materials"
gbrain search "implementation plan"

# Health check
gbrain doctor
```

---

## Phase 4: Configure Recurring Jobs (10 min)

Do NOT use gbrain's autopilot (conflicts with our scheduler). Instead, add to our existing cron system.

### 4.1 Add to schedules.json or use /schedule

```bash
# Daily: refresh embeddings for new/changed pages
gbrain embed --stale          # Only re-embeds pages changed since last run

# Daily: maintain back-links
gbrain backlink

# Weekly: health check
gbrain doctor
```

### 4.2 Optional: OneDrive sync

If you want ongoing ingestion as new files appear in OneDrive/Work:

```bash
# Run the conversion + import pipeline incrementally
# (only processes files newer than last run)
# This would be a script we write that:
# 1. Finds new/modified files in ~/OneDrive/Work/ since last sync
# 2. Converts non-MD to MD into ~/gbrain-import/
# 3. Runs gbrain import on the new files
# 4. Runs gbrain backlink && gbrain embed --stale
```

This is a Phase 2 enhancement — skip for initial setup.

---

## Phase 5: Verify End-to-End (10 min)

### 5.1 Test MCP tools from Claude Code

Start a new Claude Code session and test:

```
"What do we know about [company name from your board materials]?"
→ Claude should call gbrain search + get_page MCP tools

"Find all audit minutes from Q3 2024"
→ Claude should search and return relevant pages

"Who is mentioned in the implementation plan?"
→ Claude should extract entity references
```

### 5.2 Verify no interference with existing setup

```
# Confirm VIBE protocol still works
"What phase are we in?" → Should reference .claude/phase.json, not gbrain

# Confirm dev skills still work
/investigate, /ship, /review → Should route through VIBE, not gbrain RESOLVER

# Confirm hooks still fire
Run any Bash command → git-safety-hook, RTK rewrite should still trigger

# Confirm memory system untouched
Check that auto-journal still writes to memory/journal.md on Stop
```

### 5.3 Check resource usage

```bash
# PGLite disk usage
du -sh ~/.gbrain/

# Brain directory size
du -sh ~/brain/

# Staging directory (can delete after verified import)
du -sh ~/gbrain-import/
```

---

## Phase 6: Cleanup (5 min)

### 6.1 Remove staging directory

```bash
# Only after Phase 5 verification passes
rm -rf ~/gbrain-import/
```

### 6.2 Document what was done

Update `docs/learnings/gbrain-study.md` appendix with:
- Actual page count imported
- Conversion success/failure rates by format
- Search quality observations
- Any issues encountered

---

## Rollback Plan

If anything goes wrong, gbrain is fully isolated:

```bash
# Remove MCP server from Claude Code
claude mcp remove gbrain

# Remove brain data
rm -rf ~/brain/ ~/.gbrain/

# Remove gbrain tool
cd ~/Code/gbrain && bun unlink
rm -rf ~/Code/gbrain

# Nothing in ~/.claude/ was modified — no rollback needed there
```

---

## What This Plan Does NOT Do

- Does NOT modify ~/.claude/settings.json (no hooks, no env vars)
- Does NOT register gbrain skills in ~/.claude/skills/ (no RESOLVER conflict)
- Does NOT enable signal detector (no session capture collision)
- Does NOT install autopilot launchd plist (no scheduler conflict)
- Does NOT deprecate any existing memory system (journal, lessons, episodic-memory all untouched)
- Does NOT touch Notion or Outlook/Teams ingestion (separate future work, see study doc §6.4)

## Future Work (post-install, if gbrain proves useful)

1. **Notion import** — Native export → strip UUIDs → gbrain import (1-2 hours)
2. **Outlook/Teams adapter** — pm_os scripts → JSON → brain markdown (1-2 days)
3. **OneDrive live sync** — Incremental conversion + import script on cron
4. **Option 1 evaluation** — After 2 weeks, assess whether to deprecate synthesize-lessons.py in favor of gbrain's Compiled Truth (see study doc §4, Option 1: Surgical Replacement)

---

## Time Estimate

| Phase | Duration |
|---|---|
| 1. Install gbrain | 10 min |
| 2. Mass convert | 30-60 min (mostly automated, waiting on PDF/PPTX conversion) |
| 3. Bulk import | 15-30 min (gbrain import + backlink + embed) |
| 4. Configure recurring jobs | 10 min |
| 5. Verify | 10 min |
| 6. Cleanup | 5 min |
| **Total** | **~1.5-2 hours** |
