# Feature Enablement Generator Skill

Automates creation of sales and customer success enablement materials from PRDs, designs, and competitive research.

**NEW in v2.0:** 
- Generates a **messaging foundation document** (7-section Command of Message template) first, then derives all downstream assets from it
- Supports Gong calls, Insider sessions, and customer validation
- **PRD-First extraction** - Extracts answers from PRD automatically, only asks PM to fill gaps (reduces PM time from 30-45 min → 5 min)

## Quick Start

```bash
# 1. Bootstrap new enablement project
/feature-enablement init

# You'll be asked:
# - Feature name: "Task Management"
# - PRD URL: https://example.atlassian.net/wiki/spaces/BPROG/pages/1234567/
# - Figma links: (optional)
# - Gong calls: (optional)
# - Competitors: "Asana, Monday.com, Jira"
# - Project path: ~/feature-enablement-task-management

# 2. Generate demo materials (1-pager + demo script with screenshots)
cd ~/feature-enablement-task-management
/feature-enablement demo

# 3. Update when PRD changes
/feature-enablement update

# 4. Add new competitor
/feature-enablement add-competitor ClickUp

# 5. Document future roadmap
/feature-enablement roadmap
```

## What It Generates

**Project structure:**
```
feature-enablement-<name>/
├── messaging-foundation.md       ← NEW: Source of truth (7 sections)
├── docs/
│   ├── sales-kit/
│   │   ├── battle-card.md       ← Derived from messaging foundation
│   │   ├── faq.md                ← 50+ questions across 9 categories
│   │   ├── sales-1-pager.md     ← NEW: One-page sales asset with screenshots
│   │   └── demo-script.md        ← NEW: 15-min demo guide with workflow
│   ├── competitive-analysis/
│   │   ├── competitive-overview.md
│   │   └── feature-comparison-matrix.md
│   ├── enablement/
│   │   └── video-script.md      ← Future enhancement
│   ├── future-roadmap/           ← Optional, via /roadmap command
│   │   ├── <feature>-vision.md
│   │   └── sales-roadmap-messaging.md
│   └── <feature>-overview.md     ← Synthesized PRD
├── assets/
│   ├── validation/               ← Gong transcripts, customer quotes
│   ├── competitive/              ← Competitive research
│   └── demo/
│       └── screenshots/          ← NEW: Demo screenshots (Figma, uploads, etc.)
├── prd-content.html              ← Raw Confluence export
├── prd-metadata.txt              ← Version + validation source tracking
└── README.md
```

**Automatically:**
- ✅ Fetches PRD from Confluence
- ✅ **Extracts answers from PRD** (current state, pain points, features, personas, timeline, etc.)
- ✅ Fetches Gong call transcripts (if provided)
- ✅ Fetches Insider session notes (if provided)
- ✅ Researches competitors via web
- ✅ **Proposes extracted content to PM for validation** (3 options: use as-is, enhance, replace)
- ✅ **Generates messaging foundation doc (7 sections, source of truth)**
  - Command of Message (transformation arc)
  - Solution & Functionality (capabilities table)
  - Key Personas & Priorities
  - Competitive Positioning
  - Proof & Validation
  - Messaging Guardrails
  - Availability & Packaging
- ✅ Generates downstream assets derived from messaging foundation:
  - Battle card with 5 differentiators, 10+ objections, demo flow
  - FAQ with 50+ questions
  - Competitive positioning tables
  - Overview/synthesis
  - **Sales 1-pager with screenshots** (NEW)
  - **Demo script (3-act structure with workflow)** (NEW)
- ✅ Initializes git and pushes to GitHub
- ✅ Updates when PRD changes

## Prerequisites

1. **Atlassian API access:** Run `/atlassian-connect` first (if using Confluence)
2. **GitHub CLI:** For auto-push to GitHub (`gh auth login`)
3. **PRD in Confluence:** With structured content (features, personas, phasing)
4. **Optional:** Gong call links, Insider session transcripts (for customer validation)

## Configuration for Other PMs

This skill is designed to be **universal and customizable**. Other PMs can:

1. **Customize input sources:** Edit `config.yaml` to use Google Docs instead of Confluence, or different customer validation tools instead of Gong
2. **Adjust interview questions:** Modify the questions asked during messaging foundation generation
3. **Enable/disable outputs:** Turn on video scripts, slide deck outlines, or other downstream assets
4. **Set quality thresholds:** Adjust minimum differentiators, FAQ count, etc.

See `skill.md` "Configuration" section for full details on customization.

## Workflow Integration

Use this skill at these stages:

- **DISCOVERY → ARCHITECTURE_APPROVED:** Run `/feature-enablement init` once PRD is solid
- **During BUILD:** Run `/feature-enablement update` as PRD evolves (weekly)
- **Pre-launch:** Run `/feature-enablement roadmap` to document future vision
- **Post-launch:** Run `/feature-enablement add-competitor` as market changes

## Examples

See `skill.md` for full examples of:
- Bootstrapping Task Management docs
- Updating after PRD v12 → v15
- Adding ClickUp as competitor
- Generating roadmap vision

## Customization

Generated docs are templates—review and customize:
- Add customer quotes (anonymized by default: industry/region/role only)
- Insert specific pain points from sales calls
- Refine messaging for your market
- Add ROI examples with actual numbers
- Adjust demo flow to match your environment

## Customer Reference Policy

**Default: Anonymized references only.**

All customer quotes and stories are anonymized to:
- Industry (e.g., "Financial services")
- Region (e.g., "North America", "EMEA")
- Role (e.g., "Chief Legal Officer")

**Example:** "A Board Secretary at a healthcare organization in EMEA reduced board prep time by 40%"

Named customer references require explicit approval documented in `prd-metadata.txt`.

## Demo Materials (NEW in v2.0)

### Sales 1-Pager

**Purpose:** One-page sales leave-behind for prospect meetings

**What it contains:**
- **30-second elevator pitch** - Concise value prop opening
- **The Problem** - Current state description + 3 pain points
- **The Solution** - Overview paragraph with hero screenshot
- **3-5 Key Capabilities** - Each capability includes:
  - Feature description
  - Visual (screenshot from Figma/upload/Claude Design)
  - Key benefit
- **Business Impact** - Quantified outcomes + anonymized customer proof point
- **Competitive differentiator** - Why us vs. alternatives
- **Call to action** - Availability and next steps

**Two formats generated:**
1. **Markdown** (`sales-1-pager.md`) - For internal use and editing
2. **HTML** (`sales-1-pager.html`) - For sharing and printing
   - Annotated screenshots with callout arrows pointing to key UI elements
   - Competitive comparison table
   - Objection handling quick hits
   - Optional roadmap tease section
   - Print-optimized for clean PDF exports
   - Shareable via email/Slack/web

**PM inputs needed:**
- 3-5 product screenshots (Figma frames, uploaded images, or Claude Design URLs)
- Brief descriptions of key workflows (auto-extracted from PRD + messaging foundation)
- Optional: Screenshot annotation guidance (which UI elements to highlight)

**Generated via:** `/feature-enablement demo`

---

### Demo Script

**Purpose:** Complete 15-minute demo guide with step-by-step instructions

**3-Act Structure:**

**Act 1: The Problem (2 minutes)**
- Setup context and persona scenario
- Highlight 2-3 pain points
- Include discovery questions for interactive demos

**Act 2: The Solution (10 minutes)**
- Step-by-step workflow (3-5 steps typical)
- Each step includes:
  - Screenshot of the UI state
  - Talking points script
  - Demo actions (click-by-click instructions)
  - Key value props to emphasize
  - ⭐ Competitive differentiators (moments to call out)
  - 💡 Pro tips (power user features)

**Act 3: The Outcome (2 minutes)**
- Results view screenshot
- Business outcomes achieved
- Anonymized customer proof story
- Call to action

**Additional sections:**
- **Objection handling** - 3+ objections with demo responses (how to show, not just tell)
- **Demo variants** - Short (5-min), Standard (15-min), Discovery (20-min with more questions)
- **Competitive positioning** - vs. Competitor 1, vs. Competitor 2, vs. Manual Process
- **Troubleshooting** - Common demo environment issues + fixes

**PM inputs needed:**
- 5+ product screenshots mapped to workflow steps
- Brief workflow outline (e.g., "1. Create item, 2. Assign owner, 3. Set deadline, 4. Track progress")
- Skill maps screenshots to workflow steps automatically

**Generated via:** `/feature-enablement demo`

---

## Output Quality

- **Messaging foundation:** Complete 7-section document (Command of Message, Solution, Personas, Positioning, Proof, Guardrails, Availability) - source of truth
- **Battle cards:** 30-second pitch, 5 differentiators, 10+ objections, 15-min demo flow (derived from messaging foundation)
- **FAQs:** 50+ questions across 9 categories (derived from messaging foundation)
- **Competitive analysis:** Feature matrices, positioning statements, objection handling
- **Sales 1-pager:** One-page asset (Markdown + HTML) with 3-5 annotated screenshots, competitive table, business impact, anonymized proof, print/PDF-ready
- **Demo script:** 15-minute guided demo with step-by-step workflow, objection handling, 3 variants
- **Roadmap messaging:** How to discuss future without over-promising

## Troubleshooting

**"PRD URL not accessible"**
- Run `/atlassian-connect` first
- Verify Confluence page URL is correct
- Check you have read access to the page

**"WebFetch failed for competitor"**
- Some sites block automated requests
- Try homepage URL instead of /features
- Manually provide competitor info when asked

**"GitHub CLI not found"**
- Install: https://cli.github.com/
- Authenticate: `gh auth login`

## Based On

This skill automates the workflow originally used to create the Forward Planner
enablement docs. All outputs follow the same structure and quality standards.

---

**Version:** 1.0
**Last Updated:** 2026-04-16
