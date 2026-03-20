---
name: video-script-creator
description: "Create professional video scripts from narrative documents, product docs, case studies, or existing scripts. Use when the user mentions 'video script', 'video production', 'InVideo', 'scene breakdown', 'voiceover script', 'storyboard', or asks to turn a document into a video, convert a story to a script, create a corporate video, product demo video, or pitch video. Also use when editing, reformatting, or improving existing video scripts. Produces three deliverables by default: formatted markdown script, production-ready .docx, and an AI video generation prompt (e.g., for InVideo AI). Supports custom design systems and multiple narrative arc templates."
---

# Video Script Creator

Turn narrative documents into tight, production-ready video scripts with voiceover/visual breakdowns, production notes, and AI video generation prompts.

## Overview

This skill converts source material (day-in-the-life narratives, PRDs, case studies, testimonials, or existing scripts) into a complete video production package:

1. **Formatted Script** (.md) — Scene-by-scene table with Voiceover and On-Screen Visual columns
2. **Production Document** (.docx) — Professional Word doc matching corporate production standards
3. **AI Video Prompt** — Ready-to-paste prompt for AI video generators (InVideo AI, Runway, etc.)

Users can request any subset of these three deliverables.

## Quick Reference

| Task | Action |
|------|--------|
| Create script from narrative | Follow the full workflow below |
| Edit existing script | Jump to Step 5 (Refinement) |
| Reformat script to new arc | Jump to Step 3 (Arc Selection) with existing content |
| Generate only the AI prompt | Follow workflow, output only Step 6 |
| Use a custom design system | User provides a design system file; override defaults in Step 4 |

---

## Step 1: Source Analysis

Before writing anything, analyze the source material:

### Extract These Elements
- **Core message / thesis**: What is the single takeaway for the audience?
- **Protagonist**: Who or what is the subject? (person, team, product, org)
- **Key moments**: Identify 4–8 high-impact scenes, beats, or turning points
- **Data points**: Any metrics, numbers, or proof points that belong on screen
- **Emotional arc**: Where does tension build? Where does it resolve?
- **Audience**: Who is watching? What do they care about? What are they skeptical of?

### Ask the User (if not obvious from context)
Batch these questions — do NOT spread across multiple turns:

1. **Target duration** (default: 120 seconds)
2. **Audience & context** (e.g., board presentation, product launch, sales enablement)
3. **Which moments from the source should anchor the video?** (present top candidates)
4. **Protagonist framing** (named character, role-based, collective, executive)
5. **Closing / CTA** (brand close, metric-forward, emotional, strategic vision)
6. **Should data/metrics appear explicitly on screen?**
7. **Design system**: Using default (Diligent) or providing a custom one?

CRITICAL: Collect all information needed upfront. Do not ask one question at a time.

---

## Step 2: Duration Budgeting

Video scripts MUST be time-budgeted. Every second counts.

### Duration-to-Word-Count Guide
| Duration | Total Words (VO) | Recommended Scenes |
|----------|------------------|--------------------|
| 30 sec   | 75–85 words      | 2–3 scenes         |
| 60 sec   | 150–165 words    | 3–4 scenes         |
| 90 sec   | 225–250 words    | 4 scenes           |
| 120 sec  | 280–320 words    | 4–5 scenes         |
| 180 sec  | 420–475 words    | 5–6 scenes         |

### Time Allocation by Arc
Each arc template (see Step 3) has a recommended time split. Always define exact second ranges per scene BEFORE writing voiceover.

CRITICAL: After drafting voiceover, COUNT THE WORDS per scene and verify against budget. Professional voiceover reads at ~2.3 words/second. If a scene's word count exceeds its time budget, cut immediately. Tight scripts > verbose scripts.

---

## Step 3: Arc Selection

Present the user with arc options. Default to **The Transformation Arc** unless the content clearly fits another pattern.

### Arc Templates

Read `references/arc-templates.md` for full templates with time splits, scene descriptions, and examples.

**Summary of available arcs:**

| Arc | Structure | Best For |
|-----|-----------|----------|
| **The Transformation Arc** (default) | Problem → Shift → Workflow/Demo → Results | Product demos, corporate vision, AI transformation stories |
| **The Bookend Arc** | Opening moment → Journey → Return to opening (transformed) | Day-in-the-life, customer stories, before/after narratives |
| **The Countdown Arc** | Stakes → Ticking clock → Resolution → Payoff | Urgency-driven, competitive, time-sensitive scenarios |
| **The Reveal Arc** | Mystery/question → Investigation → Reveal → Implications | Product launches, research findings, surprising data |

ALL arcs enforce a narrative pattern: setup tension, build through the middle, resolve with impact. No arc template produces a flat, linear walkthrough.

---

## Step 4: Design System & Production Style

### Default Design System: Diligent

If no custom design system is provided, use:

```
Color Palette:
- White: #ffffff (dominant background)
- Dark Navy: #1a1d2e (primary text, icons, structural elements)
- Dark Red: #e84c3d (sparingly — key highlights, CTAs, active states)
- Light Gray: #f9fafb (card backgrounds, sections)
- Border Gray: #e5e7eb (dividers, borders)
- Medium Gray: #6b7280 (secondary text, labels)

Typography: Arial, sans-serif
- Headings: 18–24px, weight 600
- Body: 13–14px, weight 400
- Labels: 11–12px, weight 400

Spacing: 8px grid, 6–12px border radius for cards, 15–20px card padding

Principles:
1. White space dominates
2. Dark elements provide contrast
3. Red is precious — only for attention-grabbing elements
4. Clean and minimal — no visual clutter
5. Professional, corporate-ready aesthetic
```

### Custom Design System Override
If the user provides a design system file (markdown, JSON, or any format):
- Parse it for: colors, typography, spacing, and principles
- Replace the defaults above with the user's values
- Reference the custom values in all Visual columns and production notes

### Voiceover Talent Defaults
- **Tone**: Observational, straightforward, informative
- **Delivery**: Clear and professional — documentary narrator, NOT salesperson
- **Energy**: Calm confidence, understated competence
- **Style**: Describe, don't direct. Show, don't sell.

### Music Cue Pattern
Map music to the arc's emotional progression:
- **Setup scenes**: Subtle, reflective
- **Transition scenes**: Gentle shift
- **Core/demo scenes**: Modern, clean electronic — building steadily
- **Resolution scenes**: Confident, grounded, uplifting

---

## Step 5: Script Writing

### The Two-Column Format

Every scene MUST be written as a two-column table:

| Voiceover | On-Screen Visual |
|-----------|-----------------|
| Exact words the narrator says, in quotes. | Detailed visual direction: footage type, UI elements, animations, text overlays, design system colors, music cues. |

### Writing Rules

**Voiceover column:**
- Write in complete sentences, natural speech rhythm
- Use quotation marks around all VO text
- No jargon the audience wouldn't use
- Every sentence must earn its seconds — cut anything that doesn't advance the story
- Read it aloud. If it sounds like a press release, rewrite it.
- For investor/board audiences: factual, data-backed, understated. Sophisticated audiences see through hype.

**Visual column:**
- Be specific enough for a video producer OR an AI generator to execute
- Always specify: footage type (stock, product, animated graphic), UI references with hex colors, text overlays with exact copy, music cues with emotional descriptors
- Reference the design system explicitly (e.g., "dark navy card (#1a1d2e), white text, red accent line (#e84c3d) at top")
- Include transition notes between scenes
- Bracket all music cues: `[MUSIC: descriptor]`

**Scene structure rules:**
- Each scene gets a heading with name and exact time range
- Sub-beats within long scenes get labels (e.g., "Beat 1 — Morning")
- The first scene must hook within 5 seconds
- The last scene must land the CTA/close with conviction — hold key visuals for 2–3 beats

### Production Notes Section

After the script tables, always include:
- Visual style guide summary (from design system)
- Voiceover talent spec
- Music cue timeline
- Key messaging principles (what to emphasize, what to avoid)
- Total runtime with expansion notes

---

## Step 6: AI Video Prompt Generation

Generate a single block of text optimized for AI video generators (InVideo AI, Runway, Sora, etc.).

### Prompt Structure
```
1. Format & duration declaration
2. Visual style direction (colors, typography, motion — from design system)
3. Voiceover tone direction
4. Music direction
5. Scene-by-scene breakdown:
   - Scene label + time range
   - Voiceover text (full)
   - Visual direction (full)
6. Closing visual direction
```

### Prompt Writing Rules
- Flatten all formatting into plain prose paragraphs — no tables, no markdown
- Bold scene labels for scanability
- Include ALL voiceover text verbatim — the AI generator needs the complete script
- Include ALL visual direction — don't summarize
- Reference colors by hex value AND description (e.g., "dark red (#e84c3d)")
- Specify motion style explicitly ("smooth and purposeful, never frantic")

---

## Step 7: Output Generation

### Default: All Three Deliverables

1. **Markdown script** → Save to `/mnt/user-data/outputs/{title}-Script.md`
2. **Production .docx** → Use the `docx` skill (read `/mnt/skills/public/docx/SKILL.md` first) to generate a formatted Word document with:
   - Branded header (design system colors)
   - Title block with subtitle, duration, audience
   - Scene tables with proper cell shading and borders
   - Production notes section
   - AI prompt section in a styled callout box
   - Save to `/mnt/user-data/outputs/{title}-Script.docx`
3. **AI video prompt** → Include in both the .md and .docx, AND as a standalone `.txt` file at `/mnt/user-data/outputs/{title}-InVideo-Prompt.txt`

### Subset Requests
If the user asks for only one or two outputs, produce only those. Always confirm which outputs they want if unclear.

---

## Refinement & Editing

When editing existing scripts:

1. **Read the existing script** — extract arc, duration, design system, scene structure
2. **Identify the edit type**:
   - Tone adjustment → Rewrite VO only, preserve visuals
   - Scene restructure → Re-budget time, reflow content
   - Duration change → Re-budget all scenes proportionally, then rewrite
   - Design system swap → Update all Visual column references
   - AI prompt regeneration → Rebuild from current script state
3. **Preserve what works** — don't rewrite scenes that are already tight
4. **Re-validate word count** against time budget after every edit

---

## Common Mistakes to Avoid

- **Overstuffing scenes**: 120 seconds is ~300 words. That's it. Kill your darlings.
- **Vague visuals**: "Show the product" is useless. "Diligent platform dashboard with usage data cards (#1a1d2e on #ffffff, red accent on key metric)" is useful.
- **Forgetting music cues**: Every scene transition needs a music note.
- **Flat arcs**: If there's no tension in the first 20%, the audience is gone. Every arc must have a problem/question/stakes before the solution.
- **Selling instead of showing**: "Our amazing revolutionary product" vs. "The prototype was live with 12 customers in 9 days. 73% activation."
- **Ignoring the audience**: A board of PE/VC investors needs different framing than a product launch crowd. Adjust tone, data density, and CTA accordingly.
- **Not counting words**: Always verify VO word count against duration budget. This is non-negotiable.

---

## Examples

### Example 1: Day-in-the-Life → Board Pitch Video
- **Input**: Narrative doc describing a PM's AI-augmented workday
- **Arc**: Transformation Arc (default) with Bookend sub-pattern (Tokyo morning/evening)
- **Output**: 120-sec script, production .docx, InVideo AI prompt
- **See**: `references/example-product-org-script.md`

### Example 2: Customer Case Study → Sales Enablement Video
- **Input**: Customer success story with metrics
- **Arc**: Reveal Arc (mystery: what changed? → reveal: the platform)
- **Output**: 60-sec script, markdown only
- **See**: `references/example-case-study-script.md`

---

## Dependencies

- **docx skill** (`/mnt/skills/public/docx/SKILL.md`): Required for .docx output generation
- **No external packages required** for markdown or AI prompt outputs
