---
name: design-prototype
description: >
  Use when a static HTML mock from /design-html exists and needs clickable
  interactivity added, or when the user says "make this clickable", "prototype",
  "add interactions", "interactive mock", or "make it feel real". Also use when
  the user has an approved design variant and PRD and wants to go straight to a
  clickable prototype. Chains /design-html automatically when no HTML mock exists.
---

# /design-prototype: Clickable Prototype from Static Mock

Takes a static HTML/CSS mock (from /design-html or hand-built) and adds vanilla JS
interactivity to make it feel like a real app. Cards expand with detail panels, search
simulates AI responses, sidebar items reveal summaries, notifications drop down. Single
HTML file, zero dependencies, under 500 lines of JS.

## When to Use

- User has a static HTML mock and wants it clickable
- User has an approved design + PRD and wants an interactive prototype in one step
- User says "prototype", "make this interactive", "add click behavior", "make it real"
- After /design-html completes, as the natural next step

**Do NOT use when:**
- User wants production React/Angular/Vue components (use /design-html with framework output)
- User wants visual design exploration (use /design-shotgun)
- User only wants a static visual spec (use /design-html)

---

## Phase 0: Auto-Detection

Scan the workspace to determine what inputs are available. Run these checks:

### 0a. Find design-shotgun output

```bash
eval "$(~/.claude/skills/gstack/bin/gstack-slug 2>/dev/null)" 2>/dev/null || true
SLUG=${SLUG:-unknown}
# Check for approved design variants
setopt +o nomatch 2>/dev/null || true
_APPROVED=$(find ~/.gstack/projects/$SLUG/designs/ -name "approved.json" -maxdepth 2 2>/dev/null | sort -r | head -1)
[ -n "$_APPROVED" ] && echo "DESIGN_APPROVED: $_APPROVED" || echo "NO_APPROVED_DESIGN"
```

### 0b. Find PRD or 1-pager

```bash
_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
# Look for PRDs, 1-pagers, specs in docs/
setopt +o nomatch 2>/dev/null || true
_PRD=$(find "$_ROOT/docs" -maxdepth 3 -name "*.md" 2>/dev/null | xargs grep -li "problem\|hypothesis\|proposed approach\|user flow\|acceptance criteria\|requirements" 2>/dev/null | head -3)
[ -n "$_PRD" ] && echo "PRD_FOUND:" && echo "$_PRD" || echo "NO_PRD"
```

### 0c. Find HTML mock from /design-html

```bash
_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
setopt +o nomatch 2>/dev/null || true
_HTML=$(find "$_ROOT/samples" "$_ROOT" -maxdepth 2 -name "*.html" ! -name "*prototype*" 2>/dev/null | head -5)
[ -n "$_HTML" ] && echo "HTML_MOCKS:" && echo "$_HTML" || echo "NO_HTML_MOCK"
```

### 0d. Check for existing prototype

```bash
_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
setopt +o nomatch 2>/dev/null || true
_PROTO=$(find "$_ROOT/samples" "$_ROOT" -maxdepth 2 -name "*prototype*.html" 2>/dev/null | head -3)
[ -n "$_PROTO" ] && echo "EXISTING_PROTOTYPE:" && echo "$_PROTO" || echo "NO_EXISTING_PROTOTYPE"
```

### 0e. Present findings and decide path

Use AskUserQuestion to confirm what was found. The message must cover:

1. **What was found** (list each: approved design, PRD, HTML mock, existing prototype)
2. **What is missing** and what the skill will do about it
3. **Recommended path**

**Decision matrix:**

| Design? | PRD? | HTML Mock? | Action |
|---------|------|------------|--------|
| Yes | Yes | Yes | **Scenario 3 (Full pipeline)** — go straight to interactivity |
| Yes | Yes | No | **Scenario 2** — chain /design-html first, then add interactivity |
| Yes | No | Yes | **Scenario 1 + mock** — ask user about flows, add interactivity |
| Yes | No | No | **Scenario 1** — chain /design-html, ask about flows, add interactivity |
| No | Any | Yes | Use existing HTML mock directly, ask about flows |
| No | Any | No | STOP. Tell user: "I need at least an HTML mock or an approved design. Run /design-shotgun first, or point me to your mockup file." |

If an existing prototype is found, ask:
> "Found an existing prototype at [path]. Want to evolve it (add more interactions) or
> start fresh from the static mock?"

If chaining to /design-html: invoke it, wait for it to complete, then use its output
HTML file as the mock for the interactivity phase.

---

## Phase 1: Analyze the HTML Mock

Read the HTML mock file completely. Identify every interactive zone by scanning for
these structural patterns in the markup:

| HTML Structure | Interactive Zone Type |
|----------------|----------------------|
| Repeating `<div>` siblings with similar class names, grid/flex parent | **Card grid** |
| `<input>` or `<textarea>` with search/chat-related attributes | **Search/chat input** |
| Sidebar `<section>` with list items (news, feeds, links) | **Sidebar widget** |
| Badge/counter elements near bell/notification icons | **Notification area** |
| `<nav>` or navigation-patterned elements | **Navigation** |
| `<button>` elements or click-styled links | **Action buttons** |
| Tab-like elements, filter chips, segmented controls | **Tabs/filters** |
| Collapsible/accordion-looking sections | **Expandable sections** |

**Output a zone inventory** — list each zone found, its CSS selector, and what
interaction pattern applies (from the menu in Phase 2).

---

## Phase 2: Extract Interaction Requirements

### If a PRD exists

Read the PRD. Extract:
- **User flows**: What does the user do on this page? What sequence of actions?
- **Action types**: What kinds of items appear? (signatures, reviews, approvals, etc.)
- **AI behavior**: Does the page have AI/chat? What can the user ask? What responses?
- **Detail levels**: When an item is clicked, what detail should appear?
- **Mock data examples**: Any concrete data mentioned (dollar amounts, dates, names)?

Map each PRD requirement to a zone from Phase 1.

### If no PRD exists

Use AskUserQuestion to gather interaction requirements. Ask these questions ONE AT A
TIME (never bundle). Maximum 4 questions:

**Q1: "What are the main things a user clicks on this page?"**
List the zones you found in Phase 1 and ask the user to confirm which are interactive
and which are decorative/inert.

**Q2: "When someone clicks [primary interactive element], what should they see?"**
Focus on the most prominent interactive zone (usually the card grid or main content).
Offer options: detail panel, navigation to section, modal, state change.

**Q3: "Should search/chat be simulated? If so, what are 2-3 example queries and responses?"**
Only ask if a search/chat input was found in Phase 1.

**Q4: "What domain is this for? I need realistic mock data."**
Only ask if the PRD didn't provide enough context for mock data generation.

### Interaction pattern menu

Based on what zones exist and what the user/PRD says, select from this menu:

| Zone Type | Interaction Pattern | Implementation |
|-----------|-------------------|----------------|
| Card grid / list items | Inline expand panel | Click card, detail panel appears below the grid row spanning full width, pushes siblings down. Shows context, urgency, action buttons. |
| Search / chat input | Simulated streaming response | Enter key or chip click triggers character-by-character text animation, then swaps to rich HTML with links and sources. |
| Sidebar news / feed items | Inline expand summary | Click item, summary slides open below it with AI-generated synopsis. |
| Notification badge | Dropdown panel | Click bell, absolutely-positioned dropdown shows notification items with timestamps. |
| Navigation items | Route switching OR highlight-only | If multiple content sections exist, toggle visibility. Otherwise, just highlight active state. |
| Action buttons | State change animation | Click triggers visual confirmation ("Signed!", checkmark, color change) with 300ms transition. |
| Tabs / filters | Content section toggle | Click tab, show corresponding content, hide others. Active tab gets visual indicator. |
| Meeting / event items | Inline expand detail | Click meeting, detail slides open with location, agenda count, document count. |

**Present the interaction plan to the user via AskUserQuestion before coding:**
> "Here's my plan for making this prototype interactive:
> - [Zone]: [Pattern] — [brief description]
> - [Zone]: [Pattern] — [brief description]
> ...
> Approve this plan, or tell me what to change."

---

## Phase 3: Generate Mock Data

Create a single `const MOCK_DATA` object (or multiple named constants) at the top of
the script containing all mock data. The data must be:

1. **Realistic** — use domain-appropriate names, dates, dollar amounts, titles
2. **Internally consistent** — dates should make sense relative to each other, names
   should recur across related items, amounts should be plausible
3. **Rich enough to demonstrate value** — each card/item should have 3-5 fields of
   detail, not just a title

### If PRD exists

Extract real examples from the PRD. The GC Homepage PRD, for instance, mentioned:
- Signatures pending with deadline context
- Documents awaiting review with meeting date context
- Minutes to approve with decision summaries
- Regulatory alerts, risk signals, filtered news

Turn these into concrete mock records with specific names, dates, and numbers.

### If no PRD exists

Use the domain context from Q4 to generate mock data. For a board management app,
that might mean committee names, resolution titles, filing deadlines. For a project
management tool, that might mean sprint names, ticket IDs, story points.

### Mock data structure example

```javascript
const CARDS = {
  'sign-resolution': {
    title: 'Sign Q2 Board Resolution',
    badge: 'Signature', badgeClass: 'signature',
    urgency: 'Deadline was April 10 — 3 days overdue. Blocking Q2 dividend.',
    context: 'Resolution approves Q2 dividend of $0.45/share. 6 of 8 signed.',
    buttons: [{label: 'Sign Now', primary: true}, {label: 'View Document'}]
  },
  // ... more items
};

const AI_RESPONSES = {
  'overdue': `You have <strong>3 overdue items</strong>...`,
  // ... more canned responses
};

const SIDEBAR_DETAILS = {
  'regulatory': {
    summary: 'New SEC rules effective June 1 require...',
    link: 'Read full article'
  },
  // ... more items
};
```

Each mock data constant maps to one interaction zone. Keys match `data-*` attributes
in the HTML.

---

## Phase 4: Implement Interactivity

### Setup

1. Copy the HTML mock to `samples/{feature}-prototype.html`. **Never modify the
   original /design-html output.**
2. All JS goes in a single `<script>` tag at the end of `<body>`, before `</body>`.
3. All new CSS for interactive states (detail panels, transitions, dropdowns) goes
   in a new `<style>` block appended after the existing styles, clearly commented:
   ```css
   /* ================================================================
      PROTOTYPE INTERACTIVITY STYLES
      ================================================================ */
   ```

### Implementation rules (non-negotiable)

These rules keep the prototype maintainable and consistent:

1. **Event delegation on `document`** — one `document.addEventListener('click', ...)` 
   handler routes all clicks via `e.target.closest()`. No individual element listeners
   except for specific keyboard events (Enter on search input).

2. **CSS transitions for expand/collapse** — use `max-height` + `opacity` with
   200-300ms ease. Pattern:
   ```css
   .detail-panel {
     max-height: 0;
     opacity: 0;
     overflow: hidden;
     transition: max-height 0.3s ease, opacity 0.25s ease, padding 0.3s ease;
     padding: 0 24px;
   }
   .detail-panel.open {
     max-height: 500px;
     opacity: 1;
     padding: 24px;
   }
   ```

3. **`insertAdjacentHTML` or `after()` for injecting detail panels** — create panel
   elements dynamically. For card grids, insert the panel as a sibling after the
   clicked card with `grid-column: 1 / -1` to span full width.

4. **`data-*` attributes link elements to mock data** — every clickable element gets
   a `data-{type}="{key}"` attribute matching a key in the mock data constants.
   Example: `<div class="action-card" data-card="sign-resolution">`.

5. **Detail panels match the existing theme** — extract `border-radius`, `box-shadow`,
   `font-family`, `color` values from the existing CSS custom properties. Do not
   introduce new visual styles. The detail panel should look like it belongs.

6. **Single state variable per zone type** — track expanded state with simple variables:
   ```javascript
   let expandedCard = null;
   let expandedNews = null;
   let expandedMeeting = null;
   ```

7. **Collapse-before-expand pattern** — when opening a new item, always close the
   previously open one in the same zone first. Remove the old panel element after
   the transition completes (use `setTimeout` matching the CSS transition duration).

8. **`requestAnimationFrame` for open animation** — after inserting a panel, add the
   `.open` class on the next frame so the CSS transition actually fires:
   ```javascript
   cardEl.after(panel);
   requestAnimationFrame(() => panel.classList.add('open'));
   ```

9. **Preserve all existing CSS and `contenteditable` attributes** — the static mock
   may have editable text areas for design iteration. Do not remove or interfere with
   them. Click handlers must check `!e.target.closest('[contenteditable]')`.

10. **No external dependencies** — no libraries, no CDN scripts beyond what the HTML
    mock already includes (typically just Google Fonts).

11. **JS size budget** — under 300 lines for simple prototypes (3-4 interaction zones),
    under 500 lines for complex ones (6+ zones with AI simulation).

### AI/Chat simulation pattern

If the mock has a search or chat input, implement streaming simulation:

```javascript
function showResponse(key) {
  if (streamTimer) clearInterval(streamTimer);
  const panel = document.querySelector('[data-response-panel]');
  const html = AI_RESPONSES[key];
  if (!html) { showGenericResponse(key); return; }

  panel.innerHTML = `
    <div class="response-header">...</div>
    <div class="response-body"></div>
  `;
  panel.classList.add('open');

  const body = panel.querySelector('.response-body');
  // Stream plain text first, then swap to rich HTML
  const plain = html.replace(/<[^>]+>/g, '').replace(/&[a-z]+;/g, m => {
    const map = {'&rarr;':'\u2192','&amp;':'&'};
    return map[m] || m;
  });

  let i = 0;
  streamTimer = setInterval(() => {
    if (i < plain.length) {
      body.textContent = plain.slice(0, i + 1);
      i++;
    } else {
      clearInterval(streamTimer);
      streamTimer = null;
      body.innerHTML = html; // Swap to rich version
    }
  }, 15);
}
```

The streaming gives a "typing" effect, then the final swap reveals formatted HTML with
links, bold text, and source citations. Provide a generic fallback for free-text queries
that acknowledges the query and explains it is a prototype.

### Notification dropdown pattern

```javascript
// In the click delegation handler:
const notifBtn = document.querySelector('[data-notif-btn]');
const notifDrop = document.querySelector('[data-notif-dropdown]');
// Close when clicking outside
if (!notifBtn?.contains(e.target) && notifDrop?.classList.contains('open')) {
  notifDrop.classList.remove('open');
}
// Toggle on bell click
if (e.target.closest('[data-notif-btn]')) {
  e.stopPropagation();
  notifDrop?.classList.toggle('open');
  return;
}
```

### Action button confirmation pattern

For "Sign Now", "Approve", or similar action buttons inside detail panels:

```javascript
if (e.target.closest('.action-btn.primary')) {
  const btn = e.target.closest('.action-btn.primary');
  const originalText = btn.textContent;
  btn.textContent = 'Done!';
  btn.style.background = '#2d8a4e';
  btn.disabled = true;
  setTimeout(() => {
    btn.textContent = originalText;
    btn.style.background = '';
    btn.disabled = false;
  }, 2000);
  return;
}
```

---

## Phase 5: Verify and Open

1. **Open in browser** — use `open file://...` (or `$B goto` if browse binary
   available) to show the prototype.
2. **Test each interaction** — click every interactive zone, verify panels open/close,
   search returns responses, notifications toggle.
3. **Report to user** — list what was implemented:
   - N card types with expand/collapse detail panels
   - AI search simulation with N canned responses + generic fallback
   - Sidebar item expand with N detail summaries
   - Notification dropdown with N items
   - Total JS lines added

---

## Phase 6: Iterate

After showing the prototype, ask:
> "The prototype is live at [path]. What should I adjust?
> Common changes: add more mock data, change what detail panels show, adjust
> animation speed, add another interaction zone, make buttons do something different."

Apply changes to the prototype file directly. Keep iterating until the user is
satisfied.

---

## Output Summary

| Artifact | Location |
|----------|----------|
| Static mock (input, untouched) | `samples/{feature}-{variant}.html` |
| Interactive prototype (output) | `samples/{feature}-prototype.html` |

The prototype is a single self-contained HTML file that can be shared with anyone
via file:// or any static file server. No build step, no dependencies.

---

## Example: GC Homepage

To ground the abstract patterns above, here is how they mapped to a real prototype:

**Zones detected:** card grid (6 action items), AI search bar with chips, news sidebar
(3 items), meetings sidebar (3 items), notification bell.

**Patterns applied:**
- Card grid -> inline expand with urgency, context, and action buttons
- AI search -> streaming simulation with 3 canned responses (overdue, talking points,
  summary) plus generic fallback
- News items -> inline expand with AI summary
- Meeting items -> inline expand with location, agenda count, doc count
- Notification bell -> dropdown with 3 notification items

**Mock data:** 6 card records with board governance domain data (resolutions, minutes,
compliance reports), 3 AI response strings with HTML formatting and source citations,
3 news detail records, 3 meeting detail records.

**Result:** ~380 lines of JS, ~300 lines of prototype-specific CSS. Single file, opens
in any browser, feels like a real app.
