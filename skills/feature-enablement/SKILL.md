---
name: feature-enablement
description: "Generates sales and customer success enablement materials from PRDs, designs, and competitive research. Produces a 7-section messaging foundation document (Command of Message, Solution, Personas, Positioning, Proof, Guardrails, Availability) as the source of truth, then derives downstream assets: battle cards, FAQs, competitive analysis, sales 1-pagers, and demo scripts. Use when a PM or product marketer wants to create enablement docs, sales collateral, battle cards, competitive positioning, demo scripts, or a messaging foundation for a feature — including phrases like 'create enablement docs', 'build a battle card', 'sales 1-pager', 'demo script', or 'competitive positioning'. Supports Confluence PRDs (via atlassian-connect), Gong calls, and Acme Insider sessions as inputs. Commands: init, update, demo, add-competitor, roadmap."
---

# Feature Enablement Generator

Automates creation of sales and customer success enablement materials from PRDs, designs, and competitive research. 

**New in v2.0:** Generates a **messaging foundation document** (Command of Message, Solution, Personas, Positioning, Proof, Guardrails, Availability) first, then derives all downstream assets from it (battle cards, FAQs, competitive analysis, roadmap docs).

## Usage

```bash
# Bootstrap new enablement project
/feature-enablement init

# Update existing project with latest PRD/design changes
/feature-enablement update

# Generate demo materials (1-pager + demo script) with screenshots
/feature-enablement demo

# Add competitive analysis for new competitor
/feature-enablement add-competitor <competitor-name>

# Generate future roadmap vision docs
/feature-enablement roadmap
```

---

## Extraction Strategy: PRD-First with PM Validation

The skill follows a **"PRD-First with PM Validation"** approach to minimize PM effort:

1. **Extract First:** Read PRD, Gong calls, Insider sessions, Figma to extract answers for all 7 messaging foundation sections
2. **Propose Answers:** Present extracted content to PM with three options:
   - ✓ Use as-is
   - ✎ Enhance/clarify
   - ✗ Replace completely
3. **Fill Gaps:** Only ask open-ended questions for sections where extraction found no answers
4. **Always Ask:** Guardrails (internal sensitivities) and named customer approval (explicit confirmation required)

**Result:** PM reviews and enhances extracted content instead of answering 20+ questions from scratch.

### PRD Sections Checked by Default

| Messaging Section | PRD Sections Extracted From |
|-------------------|------------------------------|
| Command of Message | problem_statement, current_state, pain_points, goals, vision, success_criteria, business_case, context, market_analysis |
| Solution & Functionality | features, capabilities, functionality, scope, out_of_scope, future_work, limitations, integrations, related_products |
| Personas | target_audience, ideal_customer, personas, user_types, use_cases |
| Competitive Positioning | competitive_analysis, differentiation, positioning, alternatives, market_landscape |
| Proof & Validation | success_metrics, customer_stories, beta_results, validation, proof_points + Gong/Insider transcripts |
| Guardrails | risks, legal_notes, compliance, constraints, cautions (but always ask PM for internal sensitivities) |
| Availability | timeline, phases, rollout, launch_plan, pricing, packaging, entitlement |

---

## Commands

### `/feature-enablement init`

**Purpose:** Bootstrap a new feature enablement documentation project.

**Process:**

0. **Resolve PM identity:**
   - Read `pm.name` and `pm.email` from `config.yaml` (project copy first, then global).
   - If either is blank, prompt the user via `AskUserQuestion` for their name and email.
   - Use these for doc authorship and metadata. Never hardcode a specific person's details in the skill.

1. **Gather inputs** via `AskUserQuestion`:
   - Feature name (e.g., "Forward Planner")
   - PRD URL (Confluence page URL)
   - Figma design links (optional, comma-separated)
   - Target competitors (optional, comma-separated - e.g., "Convene, OnBoard, Board Intelligence")
   - **Gong call links** (optional, comma-separated URLs - for customer validation)
   - **Acme Insider session transcripts/links** (optional - for proof points)
   - **Pricing/packaging details** (optional, can be TBD)
   - Project path (where to create docs, default: `~/feature-enablement-<feature-slug>`)

2. **Validate Atlassian connectivity:**
   - Check if `/atlassian-connect` has been run
   - If not, invoke it to set up API access
   - Test PRD URL is accessible

3. **Create project structure:**
   ```
   <project-path>/
   ├── .claude/
   │   ├── phase.json (DISCOVERY, light VIBE)
   │   └── settings.json
   ├── CLAUDE.md (project context)
   ├── messaging-foundation.md (NEW: source of truth)
   ├── docs/
   │   ├── sales-kit/
   │   │   ├── battle-card.md
   │   │   ├── faq.md
   │   │   └── sales-1-pager.md (NEW: with screenshots)
   │   ├── competitive-analysis/
   │   │   ├── competitive-overview.md
   │   │   └── feature-comparison-matrix.md
   │   ├── enablement/
   │   │   ├── demo-script.md (NEW: 3-act demo with workflow)
   │   │   └── video-script.md (future)
   │   ├── future-roadmap/ (if applicable)
   │   │   ├── <feature>-vision.md
   │   │   └── sales-roadmap-messaging.md
   │   └── <feature-slug>-overview.md
   ├── assets/
   │   ├── validation/               ← Gong transcripts, customer quotes
   │   ├── competitive/              ← Competitive research
   │   └── demo/
   │       └── screenshots/          ← NEW: Product/prototype screenshots
   ├── memory/
   │   └── prd-changelog.md
   ├── qa/
   ├── prd-content.html (Confluence export)
   ├── prd-metadata.txt (version tracking)
   └── README.md
   ```

4. **Fetch PRD:**
   - Use Atlassian API to fetch Confluence page content
   - Extract: title, version, page ID, last updated date
   - Save HTML to `prd-content.html`
   - Save metadata to `prd-metadata.txt`

5. **Fetch validation sources** (if provided):
   - **Gong calls:** Fetch transcripts via URL (if accessible)
   - **Insider sessions:** Fetch transcripts/notes via URL
   - Extract customer quotes, pain points, outcomes
   - **Anonymize by default:** Replace company/individual names with "[Industry] company in [Region]", "[Role]"
   - Save to `assets/validation/` with anonymization applied

6. **Extract messaging foundation from source documents, then validate with PM:**
   
   **Phase 1: Extraction** (from PRD, Gong calls, Insider sessions, Figma)
   
   Read and analyze all source documents to extract answers:
   
   - **Command of Message:**
     - Current state: Extract pain points, current workflows, what users tolerate today
     - Risks & consequences: Extract cost/time/risk statements from PRD problem statement
     - Desired future state: Extract from PRD goals, vision, success criteria
     - Business outcomes: Extract metrics from PRD (time savings, error reduction, etc.)
     - Why now: Extract from PRD context, market analysis, competitive pressure sections
   
   - **Solution & Functionality:**
     - Core capabilities: Extract from PRD features section → populate capabilities table
     - Limitations: Extract from PRD scope, future work, out-of-scope sections
     - Better Together: Extract from PRD integrations, related products sections
   
   - **Personas:**
     - ICP: Extract from PRD target audience, ideal customer sections
     - Personas: Extract from PRD personas, user types, use cases sections
   
   - **Competitive Positioning:**
     - Extract from PRD competitive analysis section
     - Draft positioning statement using extracted differentiators
   
   - **Proof & Validation:**
     - Extract customer quotes from Gong calls/Insider sessions (auto-anonymize)
     - Extract metrics from PRD or validation sources
     - Identify if any customers are named (flag for approval check)
   
   - **Guardrails:**
     - Extract from PRD risks, legal notes, compliance sections
     - Check for claims that need substantiation
   
   - **Availability:**
     - Extract from PRD timeline, phases, rollout plan sections
     - Extract from PRD pricing/packaging sections
   
   **Phase 2: Validation** via `AskUserQuestion`
   
   Present extracted answers to PM with option to enhance/clarify:
   
   ```
   Example format:
   
   "From the PRD, I extracted the following for Current State:
   
   'Boards search today operates as character-by-character exact match. 
   Users must guess precise keywords. Minor variations return zero results. 
   Admins have no cross-book search. Mobile users have no search capability.'
   
   [✓ Use as-is]
   [✎ Enhance/clarify]
   [✗ Replace completely]
   
   If enhancing: What would you add or change?"
   ```
   
   **Only ask open-ended questions for sections with gaps:**
   - If PRD has no "why now" → Ask: "What makes this urgent TODAY?"
   - If PRD has no business outcomes → Ask: "What quantified outcomes can customers expect?"
   - If no pricing info → Ask: "Pricing and packaging? (can be TBD)"
   - If no competitive analysis → Ask: "Positioning statement: For [customer] who [problem]..."
   - If no validation sources → Ask: "Any customer impact metrics or anchor stories?"
   
   **Always ask (even if extracted):**
   - Guardrails (words to avoid, legal claims, sensitivities) - PM knows internal sensitivities PRD may not capture
   - Named customer approval - Explicit confirmation required
   
   **Result:** Messaging foundation populated with extracted content, enhanced where PM provided clarification, and gaps filled via targeted questions.

7. **Generate competitive research** (if competitors specified):
   - For each competitor:
     - Use `WebFetch` to research their website/features pages
     - Extract relevant capabilities
     - Identify their core vulnerabilities
     - Document our winning arguments
   - Save research to `assets/competitive/`

8. **Generate messaging foundation document:**
   - Use template: `templates/messaging-foundation-template.md`
   - Populate all 7 sections:
     1. Command of Message (transformation arc)
     2. Solution & Functionality (capabilities table)
     3. Key Personas & Priorities (ICP + personas table)
     4. Competitive Positioning (positioning statement + comparison table)
     5. Proof & Validation (metrics, anchor story, validation)
     6. Messaging Guardrails (words to avoid, legal claims, sensitivities)
     7. Availability & Packaging (GA date, access, pricing)
   - Save to `messaging-foundation.md`
   - **This becomes the source of truth for all downstream assets**

9. **Generate downstream assets** (derived from messaging foundation):
   
   **a. Overview document:**
   - Parse messaging foundation
   - Create `docs/<feature-slug>-overview.md` (synthesized version)
   - Include: elevator pitch, target personas, core capabilities, demo flow
   
   **b. Sales battle card:**
   - Extract from messaging foundation
   - Create `docs/sales-kit/battle-card.md` with:
     - 30-second elevator pitch (from Command of Message)
     - Target personas (from Personas section)
     - 5 unique differentiators (from Solution + Competitive Positioning)
     - Competitive positioning tables (from Competitive Positioning)
     - Objection handling (10+ common objections, from Guardrails + Competitive)
     - Discovery questions (10+, derived from Personas pain points)
     - 15-minute demo flow (from Solution capabilities)
     - ROI talking points (from Business Outcomes)
     - Closing questions
   
   **c. FAQ:**
   - Create `docs/sales-kit/faq.md` with categories:
     - General & Overview
     - Features & Capabilities
     - Migration & Setup
     - Workflows & Use Cases
     - Access Control & Security
     - Integrations & Compatibility
     - Pricing & Packaging
     - Competitive Comparisons
     - Roadmap & Future
   - 50+ questions minimum (derived from all sections of messaging foundation)
   
   **d. Competitive analysis:**
   - Create `docs/competitive-analysis/competitive-overview.md`
   - Create `docs/competitive-analysis/feature-comparison-matrix.md`
   - Include positioning vs. manual processes (Excel/Word) as baseline

10. **Initialize git and push to GitHub:**
    - `git init` (if not already a repo)
    - `git add -A && git commit -m "Initial enablement docs for <feature>"`
    - Use GitHub CLI to create repo: `gh repo create <feature-slug>-enablement-docs --private --source=. --push`
    - Return GitHub URL

11. **Summary output:**
    ```
    ✅ Feature enablement project created: <feature-name>
    
    📁 Location: <project-path>
    🔗 GitHub: https://github.com/<user>/<feature-slug>-enablement-docs
    📄 PRD: <confluence-url> (v<version>)
    
    Generated:
    - ✅ Messaging foundation (7 sections, source of truth)
    - ✅ Overview and synthesis
    - ✅ Competitive analysis (<N> competitors)
    - ✅ Sales battle card
    - ✅ FAQ (<N> questions)
    
    Validation sources:
    - 🎙️ Gong calls: <N> transcripts analyzed
    - 📝 Insider sessions: <N> sessions reviewed
    
    Next steps:
    1. Review messaging-foundation.md (source of truth)
    2. Customize downstream assets in docs/
    3. Add customer quotes and metrics to Proof & Validation section
    4. Run `/feature-enablement roadmap` if you have future vision to document
    5. Run `/feature-enablement update` when PRD changes
    ```

---

### `/feature-enablement update`

**Purpose:** Re-sync enablement docs with latest PRD/design changes.

**Process:**

1. **Detect project:**
   - Check current directory for enablement project structure
   - Read `prd-metadata.txt` to get current version

2. **Check for updates:**
   - Fetch latest Confluence page version
   - Compare to stored version in `prd-metadata.txt`
   - If no changes: "PRD v<X> is current. No updates needed."
   - If changed: proceed

3. **Fetch updated PRD:**
   - Download latest HTML
   - Save to `prd-content.html` (overwrite)
   - Update `prd-metadata.txt` with new version + timestamp

4. **Analyze changes:**
   - Read old and new PRD content
   - Identify what changed:
     - New features added
     - Phasing changes
     - Requirements modified
     - New personas/use cases
   - Log changes to `memory/prd-changelog.md`

5. **Re-interview PM for updated sections** via `AskUserQuestion`:
   - Present the detected changes
   - Ask which sections of messaging foundation need updates:
     - Command of Message (if value prop changed)
     - Solution & Functionality (if features added/removed)
     - Personas (if target audience changed)
     - Competitive Positioning (if positioning changed)
     - Proof & Validation (if new metrics/stories available)
     - Guardrails (if new sensitivities)
     - Availability (if launch date/packaging changed)
   - For each section needing update, ask the relevant interview questions

6. **Regenerate affected docs:**
   - **Messaging foundation:** Update affected sections with new content
   - **Overview:** Regenerate if key concepts or value props changed
   - **Battle card:** Regenerate if differentiators or features changed
   - **FAQ:** Add new questions for new features (append, don't replace)
   - **Competitive analysis:** Re-check if new capabilities affect positioning

7. **Git commit:**
   - `git add -A && git commit -m "Update docs for PRD v<new> (was v<old>): <summary-of-changes>"`
   - `git push`

8. **Summary:**
   ```
   ✅ Enablement docs updated
   
   PRD: v<old> → v<new>
   
   Changes detected:
   - Added feature: <X>
   - Modified phasing: <Y>
   - Updated personas: <Z>
   
   Updated files:
   - messaging-foundation.md (sections: Solution, Availability)
   - docs/<feature>-overview.md
   - docs/sales-kit/battle-card.md (added 2 new differentiators)
   - docs/sales-kit/faq.md (added 8 questions)
   
   Commit: <sha>
   ```

---

### `/feature-enablement add-competitor <competitor-name>`

**Purpose:** Add competitive analysis for a new competitor.

**Process:**

1. **Research competitor:**
   - Use `WebFetch` to fetch their website/features pages
   - Extract relevant capabilities
   - Identify gaps vs. your feature

2. **Update messaging foundation:**
   - Add competitor to section 4 (Competitive Positioning)
   - Update competitive comparison table with:
     - Competitor name
     - Their core vulnerability
     - Our winning argument

3. **Update downstream docs:**
   - Add section to `docs/competitive-analysis/competitive-overview.md`
   - Add row to `docs/competitive-analysis/feature-comparison-matrix.md`
   - Add competitive positioning to `docs/sales-kit/battle-card.md`

4. **Git commit:**
   - `git add -A && git commit -m "Add competitive analysis for <competitor>"`
   - `git push`

---

### `/feature-enablement demo`

**Purpose:** Generate demo materials (Sales 1-pager and Demo Script) with screenshots and workflow.

**Process:**

1. **Gather demo inputs** via `AskUserQuestion`:
   - **Screenshots:** Upload or provide links to product/prototype screenshots
     - Figma links (auto-extract screenshots)
     - Uploaded image files (local paths)
     - Claude Design asset URLs
     - Minimum 3-5 screenshots required
   - **Workflow outline:** Brief description of the demo flow
     - Example: "1. Show current manual process, 2. Create new item, 3. Add collaborators, 4. View results dashboard"
   - **Demo duration:** Standard (15 min), Short (5 min), Discovery (20 min)
   - **Key talking points:** 3-5 points to emphasize during demo

2. **Process screenshots:**
   - If Figma links provided: Extract frames/screens via Figma API or MCP
   - If image files: Copy to `assets/demo/screenshots/`
   - If Claude Design assets: Fetch and save locally
   - Generate screenshot inventory with captions

3. **Map workflow to screenshots:**
   - Parse workflow outline into steps (Act 2: Problem → Solution → Outcome)
   - Assign screenshots to workflow steps
   - Identify which capabilities each step demonstrates

4. **Generate Sales 1-pager (Markdown + HTML):**
   - **Markdown version:** Use template `templates/sales-1-pager-template.md`
   - **HTML version:** Use template `templates/sales-1-pager-html-template.html`
   - Populate from messaging foundation:
     - Elevator pitch (from Command of Message)
     - Problem (from Current State)
     - Solution overview (from Solution & Functionality)
     - 3-5 key capabilities with screenshots
     - Business impact (from Business Outcomes)
     - Customer proof (from Proof & Validation, anonymized)
     - Competitive differentiator (from Competitive Positioning)
     - CTA and availability
   - **HTML-specific features:**
     - Annotated screenshots with callout arrows (point to UI elements)
     - Competitive comparison table
     - Objection handling quick hits
     - Optional roadmap tease (future vision)
     - Print-optimized CSS for clean PDF exports
   - Save to:
     - `docs/sales-kit/sales-1-pager.md`
     - `docs/sales-kit/sales-1-pager.html`

5. **Generate Demo Script:**
   - Use template: `templates/demo-script-template.md`
   - Structure as 3-act demo:
     - **Act 1: The Problem (2 min)** - Show pain points, ask discovery questions
     - **Act 2: The Solution (10 min)** - Step-by-step workflow with screenshots, talking points, differentiators
     - **Act 3: The Outcome (2 min)** - Show results, quantify impact, customer proof
   - Include for each workflow step:
     - Screenshot
     - Script/talking points
     - Key value props
     - Demo actions (click-by-click)
     - Differentiators to call out
     - Pro tips
   - Add objection handling with demo responses
   - Add demo variants (short, discovery, executive)
   - Add competitive positioning moments
   - Save to `docs/enablement/demo-script.md`

6. **Git commit:**
   - `git add -A && git commit -m "Add demo materials (1-pager + script) with <N> screenshots"`
   - `git push`

7. **Summary:**
   ```
   ✅ Demo materials created
   
   Generated:
   - Sales 1-pager with 4 screenshots (Markdown + HTML)
   - Demo script (15-minute standard demo)
     - 5 workflow steps
     - 8 screenshots
     - 3 demo variants (short, discovery, executive)
   
   Screenshots saved to: assets/demo/screenshots/
   
   Files:
   - docs/sales-kit/sales-1-pager.md
   - docs/sales-kit/sales-1-pager.html ← Shareable, print/PDF-ready
   - docs/enablement/demo-script.md
   
   Commit: <sha>
   ```

**Screenshot Sources Supported:**
- ✅ Figma frames/screens (auto-extract via API)
- ✅ Uploaded images (PNG, JPG, local paths)
- ✅ Claude Design asset URLs
- ✅ Prototype screenshots (from design-prototype skill)

**HTML Annotation Features:**
The HTML version includes visual callout annotations (arrows pointing to UI elements):
- Position annotations with CSS (top/bottom/left/right percentages)
- Arrow directions: arrow-down, arrow-up, arrow-left, arrow-right
- Red callout boxes with white text (brand color customizable in config.yaml)
- Example: `<div class="annotation arrow-down" style="top: 3%; left: 50%;">Switch views here</div>`

**Workflow Outline Format:**
```
Example input:

"Demo flow: 
1. Show current board prep workflow (manual, disorganized)
2. Create new forward planning session
3. Add agenda items from templates
4. Assign owners and due dates
5. Link to related board materials
6. View consolidated dashboard"

This becomes a 6-step Act 2 with screenshots mapped to each step.
```

---

### `/feature-enablement roadmap`

**Purpose:** Generate future roadmap vision documents (for features beyond current PRD scope).

**Process:**

1. **Interview user** via `AskUserQuestion`:
   - What's the long-term vision beyond current PRD?
   - What future phases are planned? (PU4+, etc.)
   - What agentic/AI capabilities are envisioned?
   - What integrations are planned?
   - What new user personas will be addressed?

2. **Generate vision doc:**
   - Create `docs/future-roadmap/<feature>-vision.md` with:
     - Executive summary
     - Evolution from current to future state
     - Key capabilities by phase
     - Competitive positioning (future moat)
     - Open questions for product/eng
   
3. **Generate sales messaging guide:**
   - Create `docs/future-roadmap/sales-roadmap-messaging.md` with:
     - How to discuss future vision without over-promising
     - Conversation frameworks
     - Objection handling for roadmap questions
     - Discovery questions for future fit
     - When to introduce vision (timing guide)
     - Roadmap FAQ

4. **Git commit:**
   - `git add -A && git commit -m "Add future roadmap vision docs"`
   - `git push`

---

## Configuration

### Global Configuration: `config.yaml`

The skill uses `~/.claude/skills/feature-enablement/config.yaml` for global settings. **Other PMs can customize this file** to match their workflow.

**Key customization points:**

```yaml
# PM Configuration
pm:
  name: "Your Name"
  email: "your.email@company.com"
  organization: "Your Company"

# Input Sources (customize for your org)
input_sources:
  prd:
    type: "confluence"  # Options: confluence | google_docs | notion | markdown | url
    api_skill: "atlassian-connect"
  
  customer_calls:
    - type: "gong"
      prompt: "Gong call links (optional)"
    - type: "insider_sessions"  # Change to your org's customer interview format
      prompt: "Customer session transcripts (optional)"

# Messaging Foundation Template
messaging_foundation:
  template_file: "templates/messaging-foundation-template.md"
  
  # Enable/disable sections (or reorder)
  sections:
    - id: "command_of_message"
      enabled: true
      interview_questions:
        - "What does the buyer's world look like today?"
        - "What does staying in current state cost them?"
        # Add/modify questions as needed

# Downstream Assets (enable/disable)
downstream_assets:
  - id: "battle_card"
    enabled: true
    requirements:
      - "30-second elevator pitch"
      - "5 unique differentiators"
      # Customize requirements per your org
  
  - id: "video_script"
    enabled: false  # Enable when you want video scripts

# Quality Standards (adjust thresholds)
quality_standards:
  battle_card:
    min_differentiators: 5
    min_objections: 10
  faq:
    min_questions: 50
```

**To customize for another PM:**
1. Copy `config.yaml` to a new location or modify in place
2. Update `pm` section with their details
3. Adjust `input_sources` if they use different tools (e.g., Google Docs instead of Confluence)
4. Enable/disable `downstream_assets` based on what they need
5. Modify `interview_questions` to match their terminology/process

### Project Configuration: `prd-metadata.txt`

Each enablement project tracks these settings in `prd-metadata.txt`:

```
Title: <Feature Name>
PRD_URL: <Confluence URL>
PRD_Version: <Version Number>
PRD_Page_ID: <Page ID>
Last_Updated: <ISO Date>
Figma_Links: <Comma-separated URLs>
Gong_Calls: <Comma-separated URLs>
Insider_Sessions: <Comma-separated URLs>
Competitors: <Comma-separated names>
Launch_Date: <ISO Date or TBD>
Launch_Tier: <Tier 1/2/3 or TBD>
Pricing: <Details or TBD>
Approved_References: <Company Name, Contact, Date | NONE (default)>
Approved_Use_Cases: <case_study,battle_card,webinar | NONE (default)>
```

**Note:** `Approved_References` defaults to NONE. All customer references are anonymized unless explicit approval is documented here.

---

## Requirements

- **Atlassian API access:** Must run `/atlassian-connect` first
- **GitHub CLI:** For creating/pushing repos
- **Network access:** For WebFetch competitive research

---

## Examples

### Example 1: Bootstrap new project with PRD-First extraction

```
User: /feature-enablement init

Claude: What's the feature name?
User: Task Management
Claude: PRD URL (Confluence page)?
User: https://example.atlassian.net/wiki/spaces/BPROG/pages/1234567/
Claude: Any Figma design links? (optional, comma-separated)
User: https://www.figma.com/design/XYZ123/Task-Management
Claude: Target competitors? (optional, comma-separated)
User: Asana, Monday.com, Jira
Claude: Project path? (default: ~/feature-enablement-task-management)
User: <press enter for default>

[Claude fetches PRD, extracts messaging foundation content...]

Claude: I've extracted the following from your PRD for "Current State":

"Users today create tasks in Excel spreadsheets or Word documents. 
There's no centralized tracking, no visibility across teams, and 
no way to link tasks to meetings or agendas. Task owners must 
manually email updates, and status tracking is ad-hoc."

[ ] Use as-is
[ ] Enhance/clarify
[✓] Replace completely

User: Use as-is

Claude: For "Business Outcomes", I found:
"Reduce task creation time by 50%, improve task completion rates by 30%"

Would you like to enhance this?

User: Add "Increase visibility into cross-team dependencies"

[Claude continues extraction + validation for all 7 sections, only asking 
 open-ended questions for gaps, always asking about guardrails...]

✅ Feature enablement project created: Task Management

📁 Location: ~/feature-enablement-task-management
🔗 GitHub: https://github.com/<your-org>/task-management-docs
📄 PRD: https://example.atlassian.net/wiki/spaces/BPROG/pages/1234567/ (v12)

Generated:
- Overview and synthesis
- Competitive analysis (3 competitors)
- Sales battle card
- FAQ (65 questions)

Next steps:
1. Review generated content in ~/feature-enablement-task-management/docs/
2. Customize messaging for your market
3. Run `/feature-enablement roadmap` if you have future vision to document
```

### Example 2: Update after PRD changes

```
User: /feature-enablement update

[Claude detects project, checks PRD version...]

✅ Enablement docs updated

PRD: v12 → v15

Changes detected:
- Added feature: Priority levels (P0, P1, P2)
- Modified phasing: Notifications moved from PU2 to PU1
- New persona: Team leads (in addition to individual contributors)

Updated files:
- docs/task-management-overview.md
- docs/sales-kit/battle-card.md (added priority levels to differentiators)
- docs/sales-kit/faq.md (added 8 questions about priority system)

Commit: abc123d
```

### Example 3: Add competitor

```
User: /feature-enablement add-competitor ClickUp

[Claude researches ClickUp, extracts capabilities...]

✅ Added competitive analysis for ClickUp

Updated files:
- docs/competitive-analysis/competitive-overview.md (added ClickUp section)
- docs/competitive-analysis/feature-comparison-matrix.md (added ClickUp row)
- docs/sales-kit/battle-card.md (added "vs ClickUp" positioning)

Commit: def456e
```

### Example 4: Extraction efficiency

**Without PRD-First extraction (old approach):**
- PM answers 20+ open-ended questions from scratch
- Takes 30-45 minutes of PM time
- Risk of inconsistency between PRD and messaging foundation

**With PRD-First extraction (new approach):**
```
[Claude extracts from PRD]

Claude: I've populated 6 of 7 messaging foundation sections from your PRD.

Extracted successfully:
✓ Command of Message (5/5 subsections complete)
✓ Solution & Functionality (capabilities table + limitations)
✓ Personas (2 personas identified)
✓ Competitive Positioning (draft positioning statement)
✓ Availability (timeline, no pricing info found)

Needs your input:
⚠ Proof & Validation - No customer metrics found in PRD
⚠ Guardrails - Always need PM input for internal sensitivities

I have 3 questions for you:

1. Customer impact metrics? (efficiency, cost, risk, revenue)
2. Any words/phrases to avoid in messaging?
3. Do you have explicit approval to use named customer references?

User: [Answers 3 questions]

Done! ✅
```

**Result:** 5 minutes of PM time vs. 30-45 minutes

### Example 5: Generate demo materials

```
User: /feature-enablement demo

Claude: I'll help you create demo materials. Let me gather some inputs.

What screenshots do you have? You can provide:
- Figma frame links
- Uploaded image files (drag and drop or paths)
- Claude Design asset URLs
- Prototype screenshot paths

User: Here are my Figma frames:
- https://www.figma.com/design/ABC/Forward-Planner?node-id=123
- https://www.figma.com/design/ABC/Forward-Planner?node-id=456
- https://www.figma.com/design/ABC/Forward-Planner?node-id=789

Claude: Great! I've extracted 5 screenshots from Figma. What's your demo workflow?

User: 1. Show current manual planning process
2. Create new forward planning session
3. Add agenda items from templates  
4. Assign owners and due dates
5. Link to board materials
6. View consolidated dashboard

Claude: Perfect! What key talking points should I emphasize?

User: - Time savings (50% reduction in prep time)
- Collaboration across teams
- Integration with existing board materials

[Claude generates 1-pager and demo script...]

✅ Demo materials created

Generated:
- Sales 1-pager with 5 screenshots
  - 30-second pitch
  - 3 key capabilities highlighted
  - Customer proof point (anonymized)
- Demo script (15-minute standard demo)
  - 6 workflow steps with screenshots
  - Talking points and pro tips per step
  - 5 objection responses with demo actions
  - 3 demo variants (5-min, 15-min, 20-min)

Screenshots saved to: assets/demo/screenshots/

Files:
- docs/sales-kit/sales-1-pager.md
- docs/enablement/demo-script.md

Commit: jkl012g
```

### Example 6: Generate roadmap vision

```
User: /feature-enablement roadmap

Claude: What's the long-term vision beyond the current PRD?
User: We want Task Management to become an orchestration hub—link tasks to meetings, agendas, and board books. AI suggests task assignments based on workload and expertise.

Claude: What future phases are planned?
User: PU4: AI task suggestions, PU5: Meeting integration, PU6: Analytics dashboard

[Claude generates vision and messaging docs...]

✅ Roadmap vision docs created

Generated:
- docs/future-roadmap/task-management-vision.md
- docs/future-roadmap/sales-roadmap-messaging.md

Commit: ghi789f
```

---

## Making It Universal: For Other PMs

This skill is designed to be customizable for any PM in any organization. Here's how to adapt it:

### Scenario 1: Different Input Sources

**Problem:** Your org uses Google Docs for PRDs, not Confluence.

**Solution:** Edit `config.yaml`:
```yaml
input_sources:
  prd:
    type: "google_docs"  # Changed from "confluence"
    api_skill: "google-docs-connect"  # Or use WebFetch for public docs
```

The skill will adapt its fetch logic based on the `type` field.

### Scenario 2: Different Customer Validation Sources

**Problem:** Your org uses Chorus.ai instead of Gong, or conducts user interviews via Zoom transcripts.

**Solution:** Edit `config.yaml`:
```yaml
input_sources:
  customer_calls:
    - type: "chorus"
      name: "Chorus.ai call links"
      prompt: "Chorus.ai call links (optional, comma-separated URLs)"
    - type: "zoom_transcripts"
      name: "Zoom user interview transcripts"
      prompt: "Zoom transcript URLs or local paths (optional)"
```

The skill will adjust its prompts and validation source tracking accordingly.

### Scenario 3: Different Downstream Assets

**Problem:** Your sales team needs video scripts and slide deck outlines, not just battle cards.

**Solution:** Edit `config.yaml`:
```yaml
downstream_assets:
  - id: "video_script"
    enabled: true  # Changed from false
    output_file: "docs/enablement/video-script.md"
  
  - id: "slide_deck_outline"
    enabled: true  # Changed from false
    output_file: "docs/sales-kit/deck-outline.md"
```

The skill will generate these additional assets from the messaging foundation.

### Scenario 4: Different Terminology/Process

**Problem:** Your org calls it "customer impact stories" not "anchor customer story", or uses different phasing terminology.

**Solution:** Edit `config.yaml` to customize interview questions:
```yaml
messaging_foundation:
  sections:
    - id: "proof_validation"
      interview_questions:
        - "What customer impact stories can you share?"  # Changed terminology
        - "Any lighthouse customers or marquee references?"
```

### Scenario 5: Different Quality Standards

**Problem:** Your sales team expects 15 differentiators in battle cards, not 5.

**Solution:** Edit `config.yaml`:
```yaml
quality_standards:
  battle_card:
    min_differentiators: 15  # Changed from 5
    min_objections: 20       # Changed from 10
```

The skill will adjust its generation logic to meet your standards.

### Sharing Across Teams

**For individual PMs:**
1. Copy `config.yaml` to your home directory: `~/.feature-enablement-config.yaml`
2. Customize as needed
3. The skill will use your personal config first, then fall back to global

**For entire PM teams:**
1. Fork the skill to your org's internal repo
2. Customize `config.yaml` for your org's tools/process
3. Share the skill directory with your team
4. Everyone gets the same standards and workflow

---

## Best Practices

1. **Run `/feature-enablement init` early:** Create enablement docs as soon as PRD reaches ARCHITECTURE_APPROVED phase
2. **Run `/feature-enablement update` regularly:** Re-sync after each PRD iteration (weekly during active development)
3. **Keep competitive research fresh:** Run `/feature-enablement add-competitor` when new competitors emerge
4. **Document vision separately:** Use `/feature-enablement roadmap` for future features, keep sales materials (battle card/FAQ) focused on current state
5. **Customize generated content:** Review and refine AI-generated docs—add customer quotes, real pain points, specific ROI examples from validation sources
6. **Version control everything:** All changes committed to git, pushed to GitHub for team collaboration
7. **Share early, iterate often:** Get sales/CS feedback on messaging foundation before feature ships
8. **Messaging foundation is source of truth:** When updating messaging, edit `messaging-foundation.md` first, then regenerate downstream assets
9. **Default to anonymized customer references:** Only use named customers with explicit approval documented in `prd-metadata.txt`. Use industry/region/role format for all others.

---

## Integration with Workflows

This skill integrates with existing product development workflows:

- **DISCOVERY phase:** Run `/feature-enablement init` after PRD is approved
- **BUILD phase:** Run `/feature-enablement update` as PRD evolves
- **Pre-launch:** Generate roadmap vision with `/feature-enablement roadmap`
- **Post-launch:** Add competitive responses with `/feature-enablement add-competitor` as market changes

---

## Skill Output Quality

Generated documents follow these quality standards (configurable in `config.yaml`):

- **Messaging foundation:** Complete 7-section document (Command of Message, Solution, Personas, Positioning, Proof, Guardrails, Availability) — source of truth for all downstream assets
- **Battle cards:** 30-second pitch, 5+ differentiators, 10+ objections, 10+ discovery questions (derived from messaging foundation)
- **FAQs:** 50+ questions across 9 categories (derived from messaging foundation)
- **Competitive analysis:** Feature-by-feature matrices, positioning statements, objection handling (derived from messaging foundation)
- **Roadmap messaging:** Conversation frameworks, phased value delivery, when to introduce vision

All outputs are GitHub-ready markdown with proper headers, tables, and formatting.

---

## Customer Reference Policy

**Default: Anonymized references only.**

### Allowed Attributes
- **Industry** - "Financial services", "Healthcare", "Manufacturing"
- **Region** - "North America", "EMEA", "APAC" (never specific countries/cities)
- **Role** - "Chief Legal Officer", "Board Secretary", "General Counsel"

### Prohibited Attributes (unless explicitly approved)
- ❌ Company name
- ❌ Individual name
- ❌ Specific location (city, state, country)
- ❌ Company size or identifiers ("Fortune 500", "UK's largest")
- ❌ Any detail that could identify the customer

### Anonymization Templates

**Good examples:**
- ✅ "A Chief Legal Officer at a global financial services firm in EMEA"
- ✅ "A Board Secretary at a healthcare organization in North America"
- ✅ "Financial services leader in APAC"
- ✅ "A General Counsel at a multinational corporation reported 40% time savings"

**Bad examples:**
- ❌ "John Smith, CLO at Goldman Sachs" (individual + company name)
- ❌ "A Fortune 500 bank in New York" (too specific, identifiable)
- ❌ "The UK's largest insurance company" (identifiable)
- ❌ "Microsoft's legal team" (company name without approval)

### When to Use Named References

**Only when:**
1. Customer has explicitly approved use of their name
2. Approval is documented in `prd-metadata.txt`:
   ```
   Approved_References: [Company Name, Contact Email, Approval Date]
   Use_Cases: [case study, battle card, public webinar]
   ```
3. Each use case is confirmed (internal docs vs. external marketing)

**Process:**
1. PM provides customer approval during `/feature-enablement init`
2. Skill adds to `prd-metadata.txt`
3. Named references only appear in approved use cases
4. All other references remain anonymized

### Extracting from Validation Sources

When processing Gong calls or Insider sessions:
1. Extract quotes and outcomes
2. **Automatically anonymize** by replacing:
   - Company names → "[Industry] organization in [Region]"
   - Individual names → "[Role]"
   - Specific locations → "[Region]"
3. Save anonymized versions to `assets/validation/`
4. Flag any quotes that need PM review before use

---

## Troubleshooting

### "PRD URL not accessible"
- Ensure `/atlassian-connect` has been run
- Verify your Atlassian API token is valid
- Check the Confluence page URL is correct and you have access

### "WebFetch failed for competitor research"
- Some competitor sites may block automated requests
- Manually provide competitor info via `AskUserQuestion` fallback
- Use alternative URLs (homepage instead of /features page)

### "GitHub CLI not found"
- Install GitHub CLI: https://cli.github.com/
- Authenticate: `gh auth login`
- Verify: `gh auth status`

### "Generated docs are too generic"
- Customize the output—add real customer quotes, specific pain points
- Re-run commands with more detailed inputs
- Manually edit generated docs before committing

---

## Future Enhancements

Potential future capabilities for this skill:

- **Figma screenshot extraction:** Auto-capture design mockups for demo flows
- **Customer quote integration:** Pull actual quotes from Salesforce/Gong calls
- **ROI calculator generation:** Auto-create spreadsheet for time/cost savings
- **Video script creation:** Generate demo scripts for InVideo-style walkthroughs
- **Slack/Email templates:** Pre-written messages for sales outreach
- **A/B testing:** Track which messaging variations perform better in demos

---

**Last Updated:** 2026-04-16
**Version:** 1.0
