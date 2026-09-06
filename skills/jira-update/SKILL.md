---
name: jira-update
description: |
  Flesh out Jira tickets with implementation details, commit links, status
  transitions, and assignments. Works on epics + children or individual
  tickets. Use when asked to "update jira", "flesh out tickets",
  "sync jira with commits", or "update ticket details".
  Also creates Jira epics + stories from eng design docs. Use when asked to
  "create jira from design doc", "break down into tickets", or
  "create tickets from spec".
  NOT for Confluence page updates (→ atlassian-update).
argument-hint: "<ticket-key-or-url | --from-doc <path>> [--epic <parent-key>]"
---

<!-- ABOUTME:
  jira-update — two modes: (1) update existing Jira tickets with rich
  ADF descriptions, commit links, status transitions, and assignments;
  (2) create new epics + stories from eng design docs (docs/plans/).
  Dispatches parallel agents per ticket for speed.
-->

# Jira Update

Two modes:
1. **Update mode** (default) — Flesh out existing Jira tickets with
   implementation details from git history.
2. **Create mode** (`--from-doc`) — Parse an eng design doc and create
   a Jira epic with child stories, each with full ADF descriptions.

## When to Use

- "update jira", "flesh out tickets", "sync jira with commits"
- "create jira from design doc", "break down into tickets"
- After completing implementation that needs Jira traceability
- When a design doc is approved and needs Jira decomposition

## Prerequisites

- Atlassian API connectivity (invoke `/atlassian-connect` first if needed)
- For update mode: git repository with relevant commits
- For create mode: an eng design doc (typically `docs/plans/FEAT-*.md`)

---

## Mode 1: Update Existing Tickets

### Step 1: Verify Atlassian Connectivity

```bash
bash -c 'source ~/.zshrc 2>/dev/null; curl -sf -u dev@example.com:$ATLASSIAN_API_TOKEN "https://example.atlassian.net/rest/api/3/myself" | head -c 200'
```

If this fails, invoke `/atlassian-connect` and return here after.

### Step 2: Parse Input

Extract from the user's request:
- **Target ticket(s):** The ticket key(s) or URL(s) to update. If a URL,
  extract the key (e.g., `AIBM3-284` from the browse URL).

### Step 3: Gather Context (parallel)

Run all of these in parallel:

1. **Fetch target ticket(s):**
   ```bash
   bash -c 'source ~/.zshrc 2>/dev/null; curl -sf -u dev@example.com:$ATLASSIAN_API_TOKEN "https://example.atlassian.net/rest/api/3/issue/{KEY}?fields=summary,status,description,issuetype,assignee" | python3 -m json.tool'
   ```

2. **Fetch children** (if epic or has sub-tasks):
   ```bash
   bash -c 'source ~/.zshrc 2>/dev/null; curl -sf -u dev@example.com:$ATLASSIAN_API_TOKEN -H "Content-Type: application/json" -X POST "https://example.atlassian.net/rest/api/3/search/jql" -d "{\"jql\":\"parent={KEY} ORDER BY key ASC\",\"maxResults\":50,\"fields\":[\"key\",\"summary\",\"status\",\"description\",\"issuetype\",\"assignee\"]}" | python3 -m json.tool'
   ```

3. **Fetch git commits** related to the ticket(s):
   ```bash
   git log --oneline --all --grep="{KEY}\|{related-keywords}" --since="2025-01-01" | head -60
   ```

4. **Fetch available transitions** for each ticket:
   ```bash
   bash -c 'source ~/.zshrc 2>/dev/null; curl -sf -u dev@example.com:$ATLASSIAN_API_TOKEN "https://example.atlassian.net/rest/api/3/issue/{KEY}/transitions" | python3 -c "
   import json, sys
   data = json.load(sys.stdin)
   for t in data.get(\"transitions\", []):
       print(f\"ID: {t[\"id\"]} | Name: {t[\"name\"]} | To: {t[\"to\"][\"name\"]}\")
   "'
   ```

5. **Get GitHub remote URL** for commit links:
   ```bash
   git remote get-url origin
   ```

### Step 4: Analyze & Plan Updates

For each ticket (parent + children), determine:

1. **Status transition needed?** Map current work state to Jira status:
   - Work not started → leave as-is
   - Work in progress → "In Progress"
   - Work complete, pending review → "Code Review"
   - Work reviewed + QA'd → "QA Complete" or "Done"
   - NOTE: Some workflows require intermediate transitions (e.g.,
     Backlog → In Progress → Code Review). Chain transitions if needed.

2. **Assignment needed?** If unassigned and work is done by yklin, assign:
   ```
   accountId: 712020:e1d34a06-b709-4a21-b576-ae5cd4252dc2
   ```

3. **Description update needed?** If the description is empty or lacks
   implementation details, build a rich ADF description.

4. **Commit mapping:** Map commits to sub-tasks/stories by examining
   commit messages for task IDs (e.g., `T-RC-1`, `T-ST-2`) and feature
   keywords.

### Step 5: Build ADF Descriptions

Use these section structures based on ticket type:

**For Epics:**
- Problem Statement — what user pain this solves
- Solution — high-level what was built
- What was built — numbered list (one item per story)
- Design Doc — link to spec/contract files
- Key Technical Decisions — DD-1, DD-2, ... with rationale
- Acceptance Criteria — grouped by story, with IDs (RC-1, SC-1, etc.)
- Stories — list with priority labels and links to child tickets
- Success Metrics — quantitative targets
- Implementation Progress — branch name, commit count, current status

**For Stories/Tasks:**
- Problem Statement — user-facing pain this story addresses
- Solution — what was built and how
- What was built — numbered list with file paths + descriptions
- Sub-Tasks — task IDs with commit SHAs (linked to GitHub via inlineCard)
- Key Technical Decisions — decisions specific to this story
- Acceptance Criteria — with checkmarks for met criteria
- Key Commits — table with SHA + description

Continue to Step 6.

### Step 6: Build ADF JSON

See [ADF Construction](#adf-construction) section below.

### Step 7: Execute Updates (parallel agents)

Dispatch one background agent per ticket using the Agent tool. Each agent
receives the complete, pre-built content and handles:
1. Assignment (PUT assignee)
2. Status transitions (POST transitions — chain if needed)
3. Description update (PUT with ADF payload via Python script)

**Agent prompt pattern:**
- Give each agent the **exact curl commands** with real values filled in
- Give each agent the **complete Python script** with the ADF pre-built
  (don't make agents figure out what to write)
- Ask each agent to report back what succeeded and what failed

For epics with children, dispatch all agents simultaneously.

### Step 8: Report Results

Summarize in a table:

| Ticket | Summary | Status | Assignee | Description |
|--------|---------|--------|----------|-------------|
| KEY-1  | ...     | New → In Progress | yklin | Updated |
| KEY-2  | ...     | Backlog → Code Review | yklin | Updated |

Include links to each ticket for verification.

---

## Mode 2: Create from Design Doc

### Step 1: Verify Atlassian Connectivity

Same as Update Mode Step 1.

### Step 2: Parse Input

Extract:
- **Design doc path:** e.g., `docs/plans/FEAT-starred-chats-design.md`
- **Parent epic key** (optional): If `--epic` is provided, create stories
  under that existing epic. Otherwise, create a new epic first.
- **Jira project key:** Default `AIBM3` (from CLAUDE.md). Override with
  `--project`.

### Step 3: Read & Parse the Design Doc

Read the design doc (delegate to Explore agent if >200 lines) and extract:

1. **Epic-level info:**
   - Feature name (from title / Objective section)
   - Problem statement (from Objective or Requirements preamble)
   - Success metrics
   - Scope summary (DB changes, endpoints, components)

2. **Stories** (look for sections named "Stories", "Jira Stories", or
   headings like `S-XX: Story Name`):
   - Story ID (e.g., `S-RC`, `S-ST`, `S-BM`)
   - Name and description
   - Priority (P0/P1/P2)
   - Layers (DB, Backend, Frontend)
   - Dependencies (`depends_on`, `blocks`)
   - Acceptance criteria (with IDs like RC-1, SC-1, BM-1)

3. **Sub-tasks per story** (look for sections named "Sub-Tasks",
   tables with `T-XX-N` IDs):
   - Task ID (e.g., `T-RC-1`, `T-ST-2`)
   - Description
   - Dependencies / batch assignment
   - Files to create/modify

4. **Key technical decisions** (DD-* items from Design Decision Index
   or Architecture section)

5. **Failure modes / edge cases** (if documented)

6. **Execution DAG** (batch ordering, parallelism info)

### Step 4: Plan Ticket Structure

Map design doc → Jira hierarchy:

```
Epic: {Feature Name}
├── Story: {S-XX name} (P0)
│   Description: problem + solution + ACs + sub-tasks + decisions
├── Story: {S-YY name} (P0)
│   Description: problem + solution + ACs + sub-tasks + decisions
└── Story: {S-ZZ name} (P1)
    Description: problem + solution + ACs + sub-tasks + decisions
```

**Present the plan to the user** before creating anything. Show:
- Epic title and summary
- Each story with title, priority, AC count, sub-task count
- Dependency graph between stories
- Ask for confirmation

### Step 5: Build ADF for Each Ticket

**Epic description structure:**
- Problem Statement — from design doc Objective
- Solution — from design doc scope summary
- What was built — one bullet per story with ID and priority
- Design Doc — relative path to the design doc in the repo
- Key Technical Decisions — all DD-* items from the doc
- Acceptance Criteria — grouped by story
- Stories — list with priorities and dependency notes
- Success Metrics — from design doc
- Execution DAG — batch ordering (if documented)

**Story description structure:**
- First paragraph: story description from design doc (purpose, user value)
- Acceptance Criteria — all ACs for this story with IDs
- Sub-Tasks — task IDs with descriptions, dependencies, files affected
- Key Technical Decisions — DD items relevant to this story
- Edge Cases — from failure modes section (if relevant to this story)
- Dependencies — what this story depends on and what it blocks

### Step 6: Create Tickets (parallel agents)

**Step 6a: Create epic first** (if no `--epic` provided):
```bash
bash -c 'source ~/.zshrc 2>/dev/null; python3 << "PYEOF"
import json, os, subprocess

# Build epic ADF (see Step 5)
adf = { ... }

payload = json.dumps({
    "fields": {
        "project": {"key": "AIBM3"},
        "summary": "Feature Name",
        "issuetype": {"name": "Epic"},
        "description": adf,
        "assignee": {"accountId": "712020:e1d34a06-b709-4a21-b576-ae5cd4252dc2"}
    }
})

result = subprocess.run([
    "curl", "-sf", "-w", "\\n%{http_code}",
    "-u", f"dev@example.com:{os.environ[\"ATLASSIAN_API_TOKEN\"]}",
    "-H", "Content-Type: application/json",
    "-X", "POST",
    "https://example.atlassian.net/rest/api/3/issue",
    "-d", payload
], capture_output=True, text=True)
print(result.stdout)
PYEOF'
```

Extract the new epic key from the response (`{"key": "AIBM3-XXX"}`).

**Step 6b: Create child stories** (parallel agents, one per story):

Each agent creates one story via POST and sets the `parent` field:
```python
payload = json.dumps({
    "fields": {
        "project": {"key": "AIBM3"},
        "summary": "Story Name (S-XX)",
        "issuetype": {"name": "Story"},
        "parent": {"key": "AIBM3-XXX"},  # epic key from 6a
        "description": adf,  # story-specific ADF
        "assignee": {"accountId": "712020:e1d34a06-b709-4a21-b576-ae5cd4252dc2"},
        "priority": {"name": "High"}  # P0 → High, P1 → Medium, P2 → Low
    }
})
```

Priority mapping: P0 → "Highest" or "High", P1 → "Medium", P2 → "Low".

**Step 6c: Set blocking relationships** (after all stories created):

Use issue links to express dependencies:
```bash
bash -c 'source ~/.zshrc 2>/dev/null; curl -sf -w "%{http_code}" -u dev@example.com:$ATLASSIAN_API_TOKEN -H "Content-Type: application/json" -X POST "https://example.atlassian.net/rest/api/3/issueLink" -d "{
  \"type\": {\"name\": \"Blocks\"},
  \"inwardIssue\": {\"key\": \"AIBM3-AAA\"},
  \"outwardIssue\": {\"key\": \"AIBM3-BBB\"}
}"'
```

### Step 7: Report Results

Summarize created tickets:

| Ticket | Type | Summary | Priority | Depends On | ACs |
|--------|------|---------|----------|------------|-----|
| AIBM3-XXX | Epic | Feature Name | — | — | — |
| AIBM3-AAA | Story | S-RC: Recent Chats | P0 | — | 14 |
| AIBM3-BBB | Story | S-ST: Star/Unstar | P0 | AIBM3-AAA | 10 |
| AIBM3-CCC | Story | S-BM: Chat Actions | P1 | AAA, BBB | 8 |

Include links to each ticket.

---

## Design Doc Parsing Guide

Eng design docs in this project follow a consistent structure. Here's
how to map each section to Jira content:

| Design Doc Section | Maps To | Jira Field |
|--------------------|---------|------------|
| Objective / title | Epic summary + problem statement | Epic description |
| Success Metrics | Epic success metrics section | Epic description |
| Requirements (P0/P1/P2) | Story priority | Story priority field |
| Jira Stories / `S-XX` headings | Child stories | One Story per `S-XX` |
| Sub-Tasks / `T-XX-N` items | Story description sub-tasks section | Story description |
| Acceptance Criteria | Story ACs section | Story description |
| Architecture / Interfaces | Epic scope section | Epic description |
| Design Decision Index / DD-* | Technical decisions sections | Epic + story descriptions |
| Execution DAG / Batches | Dependency links + DAG section | Issue links + epic description |
| Failure Modes | Edge cases in story descriptions | Story descriptions |
| Definition of Done | Epic DoD section (optional) | Epic description |

**Key patterns to look for when parsing:**
- Story IDs: `S-RC`, `S-ST`, `S-BM` (prefix `S-`)
- Task IDs: `T-RC-1`, `T-ST-2`, `T-BM-3` (prefix `T-`, includes story ref)
- AC IDs: `RC-1`, `SC-1`, `BM-1` (2-letter prefix + number)
- Decision IDs: `DD-1` through `DD-N`
- Priority labels: `P0`, `P1`, `P2` (in Requirements table or story headers)
- Dependency markers: `Depends On:`, `Blocks:`, `depends_on`, `blocks`
- Batch markers: `Batch 1`, `Batch 2`, etc. (in Execution DAG)

---

## ADF Construction

Always use a Python script to construct ADF to avoid shell escaping issues:

```bash
bash -c 'source ~/.zshrc 2>/dev/null; python3 << "PYEOF"
import json, os, subprocess

# --- ADF helper functions ---
def text(t, bold=False, code=False):
    node = {"type": "text", "text": t}
    marks = []
    if bold: marks.append({"type": "strong"})
    if code: marks.append({"type": "code"})
    if marks: node["marks"] = marks
    return node

def heading(level, t):
    return {"type": "heading", "attrs": {"level": level}, "content": [text(t)]}

def para(*nodes):
    return {"type": "paragraph", "content": list(nodes)}

def bullet_item(*nodes):
    return {"type": "listItem", "content": [{"type": "paragraph", "content": list(nodes)}]}

def bullet_list(items):
    """items: list of listItem nodes"""
    return {"type": "bulletList", "content": items}

def ordered_list(items):
    """items: list of listItem nodes"""
    return {"type": "orderedList", "content": items}

def inline_card(url):
    """Renders as a smart link in Jira (commit links, PR links, etc.)"""
    return {"type": "inlineCard", "attrs": {"url": url}}

def commit_link(sha, github_base="https://github.com/ExampleOrg/app-workspace"):
    """Create an inline card linking to a GitHub commit"""
    return inline_card(f"{github_base}/commit/{sha}")

def table(headers, rows):
    """Build an ADF table. headers: list of str, rows: list of list of content.
    Each cell can be: str, a single ADF node (dict), or a list of ADF inline nodes."""
    header_cells = [{"type": "tableHeader", "content": [para(text(h, bold=True))]} for h in headers]
    table_rows = [{"type": "tableRow", "content": header_cells}]
    for row in rows:
        cells = []
        for cell in row:
            if isinstance(cell, str):
                cells.append({"type": "tableCell", "content": [para(text(cell))]})
            elif isinstance(cell, dict):
                cells.append({"type": "tableCell", "content": [para(cell)]})
            elif isinstance(cell, list):
                cells.append({"type": "tableCell", "content": [{"type": "paragraph", "content": cell}]})
            else:
                cells.append({"type": "tableCell", "content": [para(text(str(cell)))]})
        table_rows.append({"type": "tableRow", "content": cells})
    return {"type": "table", "attrs": {"isNumberColumnEnabled": False, "layout": "default"}, "content": table_rows}

# --- Build the ADF document ---
adf = {
    "type": "doc",
    "version": 1,
    "content": [
        # ... build sections here
    ]
}

# --- Send to Jira (PUT for update, POST for create) ---
payload = json.dumps({"fields": {"description": adf}})
result = subprocess.run([
    "curl", "-sf", "-w", "\\n%{http_code}",
    "-u", f"dev@example.com:{os.environ['ATLASSIAN_API_TOKEN']}",
    "-H", "Content-Type: application/json",
    "-X", "PUT",  # or POST for create
    "https://example.atlassian.net/rest/api/3/issue/{KEY}",
    "-d", payload
], capture_output=True, text=True)
lines = result.stdout.strip().split("\\n")
status_code = lines[-1] if lines else "unknown"
body = "\\n".join(lines[:-1])
if status_code in ("200", "201", "204"):
    print(f"OK (HTTP {status_code}): {body}")
else:
    print(f"FAIL (HTTP {status_code}): {body}")
    if result.stderr:
        print(f"  stderr: {result.stderr}")
PYEOF'
```

## ADF Quick Reference

```
doc → heading | paragraph | bulletList | orderedList | table | codeBlock
paragraph → text | inlineCard
text → marks: [strong, code, em, link]
inlineCard → attrs: {url} (renders as smart link)
```

Key patterns:
- **Bold:** `{"type": "text", "text": "...", "marks": [{"type": "strong"}]}`
- **Code:** `{"type": "text", "text": "...", "marks": [{"type": "code"}]}`
- **Link:** `{"type": "text", "text": "...", "marks": [{"type": "link", "attrs": {"href": "..."}}]}`
- **Smart link (commits, PRs):** `{"type": "inlineCard", "attrs": {"url": "..."}}`

## API Reference

Base URL: `https://example.atlassian.net`
Auth: Basic — `dev@example.com:$ATLASSIAN_API_TOKEN`
API version: **v3**

| Operation | Endpoint | Method | Notes |
|-----------|----------|--------|-------|
| Get issue | `/rest/api/3/issue/{key}` | GET | |
| Create issue | `/rest/api/3/issue` | POST | Returns `{"key": "..."}` |
| Update issue | `/rest/api/3/issue/{key}` | PUT | 204 on success |
| Search JQL | `/rest/api/3/search/jql` | POST | JSON body with `jql`, `fields` |
| Get transitions | `/rest/api/3/issue/{key}/transitions` | GET | |
| Do transition | `/rest/api/3/issue/{key}/transitions` | POST | `{"transition": {"id": "..."}}` |
| Add comment | `/rest/api/3/issue/{key}/comment` | POST | ADF body |
| Link issues | `/rest/api/3/issueLink` | POST | `{"type": {"name": "Blocks"}, ...}` |

## Common Pitfalls

1. **Status transitions may require intermediate steps.** Always fetch
   available transitions first. Some workflows require Backlog → In
   Progress → Code Review (can't skip In Progress).
2. **ADF validation is strict.** Missing `"version": 1` or wrong node
   nesting will return 400. Always test with the helper functions.
3. **Shell escaping breaks ADF.** Always use Python `json.dumps()` to
   build the payload. Never hand-craft JSON in bash.
4. **v3 API uses ADF, not wiki markup.** v2 used wiki markup for
   descriptions. v3 requires ADF JSON. Don't mix them.
5. **POST search/jql (not GET).** The v3 search endpoint is POST with
   a JSON body, not GET with query params.
6. **Create returns the key in the response body.** Parse `{"key": "AIBM3-XXX"}`
   from the POST response to use as parent for child stories.
7. **Epic must exist before children.** Create the epic first (Step 6a),
   then create stories with `"parent": {"key": "AIBM3-XXX"}` in parallel.
8. **Issue links are separate from parent/child.** `parent` field creates
   the hierarchy. Issue links (`/issueLink`) create "blocks" relationships.
