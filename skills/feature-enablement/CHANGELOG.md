# Feature Enablement Skill - Changelog

## v2.0 (2026-05-15)

### Major Enhancements

#### 1. Messaging Foundation Document (NEW)
- **7-section template** based on 2026 CWT Messaging Template
  1. Command of Message (transformation arc)
  2. Solution & Functionality (capabilities table)
  3. Key Personas & Priorities
  4. Competitive Positioning
  5. Proof & Validation
  6. Messaging Guardrails
  7. Availability & Packaging
- Generated FIRST as source of truth for all downstream assets
- Template file: `templates/messaging-foundation-template.md`

#### 2. Customer Validation Sources
- **Gong call links** - Fetch transcripts for customer quotes and pain points
- **Acme Insider sessions** - Extract proof points from customer interviews
- Validation assets saved to `assets/validation/`

#### 3. Universal PM Configuration
- **config.yaml** - Comprehensive configuration file for customization
- Customizable per PM or per organization:
  - Input sources (Confluence, Google Docs, Notion, markdown, URL)
  - Interview questions for messaging foundation
  - Downstream asset requirements
  - Quality standards (min differentiators, FAQ count, etc.)
  - Enable/disable specific outputs (video scripts, slide decks, etc.)

#### 4. Enhanced Workflow
- **Step 1:** Gather inputs (PRD, Gong calls, Insider sessions, pricing)
- **Step 2:** Fetch PRD and validation sources
- **Step 3:** Interview PM for messaging foundation (7 sections)
- **Step 4:** Generate messaging foundation doc
- **Step 5:** Derive downstream assets from messaging foundation
  - Overview
  - Battle card
  - FAQ
  - Competitive analysis

#### 5. Flexible Pricing/Packaging
- Allow "TBD" for pricing/packaging details
- Helpful for early-stage features without finalized go-to-market details

#### 6. Customer Reference Policy
- **Default to anonymized references** - industry/region/role only
- **Allowed attributes:** Industry, Region, Role
- **Prohibited attributes:** Company name, individual name, specific location
- **Anonymization templates** built into messaging foundation
- **Named references only with explicit approval** documented in `prd-metadata.txt`
- **Automatic anonymization** when extracting from Gong calls and Insider sessions

**Examples:**
- ✅ "A Chief Legal Officer at a global financial services firm in EMEA"
- ✅ "A Board Secretary at a healthcare organization in North America"
- ❌ "John Smith, CLO at Goldman Sachs" (requires explicit approval)

#### 7. PRD-First Extraction Strategy
- **Extract answers from PRD first** - Automatically populate messaging foundation sections from PRD content
- **Propose and validate** - Show extracted content to PM with 3 options: use as-is, enhance, replace
- **Only ask for gaps** - Open-ended questions only for sections where extraction found nothing
- **Always ask critical questions** - Guardrails (internal sensitivities) and customer approval (explicit confirmation)
- **Massive time savings** - Reduces PM time from 30-45 minutes → 5 minutes

**PRD sections checked:**
- Command of Message: problem_statement, current_state, pain_points, goals, vision, success_criteria, business_case
- Solution & Functionality: features, capabilities, functionality, scope, out_of_scope, future_work, limitations
- Personas: target_audience, ideal_customer, personas, user_types, use_cases
- Competitive Positioning: competitive_analysis, differentiation, positioning, alternatives
- Proof & Validation: success_metrics, customer_stories, beta_results, validation
- Guardrails: risks, legal_notes, compliance (but always ask PM)
- Availability: timeline, phases, rollout, launch_plan, pricing, packaging

#### 8. Demo Materials Generation (NEW)
- **Sales 1-pager** - One-page sales asset with screenshots (Markdown + HTML)
  - 30-second elevator pitch
  - 3-5 key capabilities with visuals
  - Customer proof point (anonymized)
  - Competitive differentiator
  - CTA and availability
  - **HTML version features:**
    - Annotated screenshots with callout arrows
    - Competitive comparison table
    - Objection handling quick hits
    - Optional roadmap tease
    - Print-optimized CSS for PDF exports
    - Shareable via email/Slack/web
- **Demo script** - Complete 15-minute demo with 3-act structure
  - Act 1: The Problem (2 min) - Pain points, discovery questions
  - Act 2: The Solution (10 min) - Step-by-step workflow with screenshots, talking points, differentiators
  - Act 3: The Outcome (2 min) - Results, business impact, customer proof
  - Objection handling with demo responses
  - Demo variants (5-min short, 15-min standard, 20-min discovery)
  - Competitive positioning moments
- **Screenshot support** - Multiple sources
  - Figma frames (auto-extract via API/MCP)
  - Uploaded images (PNG, JPG, local paths)
  - Claude Design asset URLs
  - Prototype screenshots
- **Workflow mapping** - PM provides brief workflow outline, skill maps screenshots to steps

**New command:** `/feature-enablement demo`

### Updated Files

- **skill.md** - Complete workflow documentation with messaging foundation first
- **README.md** - Updated quick start and feature list
- **templates/messaging-foundation-template.md** - NEW template file
- **config.yaml** - NEW configuration file

### Migration from v1.0

If you used the v1.0 skill:
1. Existing projects will continue to work
2. Run `/feature-enablement update` to add messaging foundation to existing projects
3. Downstream assets will be regenerated from the new messaging foundation

### Benefits of v2.0

**For PMs:**
- Single source of truth (messaging foundation) reduces inconsistencies
- Customer validation built into the process (Gong, Insider sessions)
- Clearer transformation arc with Command of Message framework
- Explicit guardrails section prevents messaging mistakes

**For Sales/CS:**
- All downstream assets derive from approved messaging foundation
- Better competitive positioning with vulnerability/winning argument tables
- Stronger proof points from customer calls
- Clear guidance on what NOT to say (guardrails)

**For Universal Use:**
- Any PM can customize config.yaml for their org's tools
- Supports multiple PRD sources (not just Confluence)
- Configurable interview questions match your terminology
- Enable/disable outputs based on your team's needs

---

## v1.0 (2026-04-16)

### Initial Release

- Bootstrap enablement projects from PRDs
- Generate battle cards, FAQs, competitive analysis
- Update docs when PRD changes
- Add competitor analysis on demand
- Generate roadmap vision docs
- Git/GitHub integration

### Based On

Originally derived from the Forward Planner enablement docs workflow.

---

## Roadmap

### Future Enhancements (v2.1+)

- **Video scripts** - Generate InVideo-style demo scripts from messaging foundation
- **Slide deck outlines** - PowerPoint/Google Slides structure for sales presentations
- **Case studies** - Formatted customer success stories from anchor stories
- **Email/Slack templates** - Pre-written outreach messages
- **ROI calculator** - Spreadsheet template for time/cost savings
- **Figma integration** - Auto-capture design mockups for demo flows
- **Salesforce integration** - Pull customer quotes directly from opportunities
- **A/B testing tracking** - Track which messaging variations perform better

### Potential MCP Integrations

- **Gong MCP** - Direct API access to call transcripts
- **Salesforce MCP** - Pull approved references and customer data
- **Google Docs MCP** - Support Google Docs as PRD source
- **Notion MCP** - Support Notion as PRD source
- **Figma MCP** - Extract design screenshots automatically

---

**Version:** 2.0  
**Last Updated:** 2026-05-15
