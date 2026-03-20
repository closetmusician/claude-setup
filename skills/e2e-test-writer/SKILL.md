---
name: e2e-test-writer
description: Use when generating e2e YAML test cases from PRD requirements, acceptance criteria, or feature specs. Translates requirements into executable YAML test files following the test-case schema.
---

# E2E Test Writer

## 1. Overview

This skill teaches agents to translate PRD requirements, acceptance criteria, and feature specs into executable YAML test cases. The DRY principle at work: write this skill once, invoke it for every new feature forever. Never hand-write test YAML one-off.

**Core idea:** Requirements describe WHAT users should experience. Tests describe HOW to verify that experience happened. This skill bridges the gap with a repeatable, mechanical process.

## 2. Input / Output

| Direction | Format | Location |
|-----------|--------|----------|
| **Input** | PRD feature spec, execution plan, task description, or acceptance criteria | `docs/prd/features/` |
| **Output** | YAML test files following `test-case.schema.yaml` | `boardroom-ai/e2e/tests/feat-XXX/` |

One acceptance criterion produces one YAML test file. If a single AC covers multiple concerns (e.g., "user creates item AND sees confirmation AND receives email"), split into focused tests that each verify one observable behavior.

## 3. The Generation Process

### Step 1: Read Requirements

- Read the PRD or spec document in full.
- Identify each acceptance criterion (AC). They are usually numbered (AC-1, AC-2, ...).
- For each AC, ask: **"Is this testable via browser? API? Both?"**
- If an AC is vague or untestable (e.g., "the system should be fast"), flag it and skip. Do not generate tests for unmeasurable requirements unless you can convert them into a `timing_assert`.

### Step 2: Classify Test Type

Use this decision tree to assign each test a `type`:

```
Is the requirement about UI rendering or user interaction?
  YES --> Does it also need backend/DB state verification?
    YES --> type: "full-stack"
    NO  --> type: "frontend"
  NO --> Is it about API behavior, data integrity, or backend logic?
    YES --> type: "backend"
    NO  --> Not testable via e2e. Skip or flag.
```

Most tests will be `full-stack`. Pure `frontend` tests are rare (animation, layout-only). Pure `backend` tests cover health checks, data migration, and API contract validation.

### Step 3: Determine Visual Verification Strategy

For `full-stack` tests, identify:

1. **What user action triggers the flow?** (click, form submit, navigation)
2. **What backend state should change?** (DB row created/updated, API response changes)
3. **What should the UI show AFTER the backend change?** (new element, updated text, status badge)

This becomes the `visual_confirm` step. Use this decision tree:

```
What BE state should this visual_confirm reflect?
  New data created    --> check DB table + API endpoint, assert new element visible
  Data updated        --> check before/after state, assert updated text visible
  Data deleted        --> confirm absence in both BE and UI
  Async operation     --> use poll first, THEN visual_confirm after completion
```

### Step 4: Generate YAML

Follow the schema at `boardroom-ai/e2e/schemas/test-case.schema.yaml` exactly. Every test file MUST include these fields:

| Field | Format | Example |
|-------|--------|---------|
| `id` | `E2E-{FEAT_ABBREV}-{NNN}` | `E2E-FT-001` |
| `name` | Human-readable description | `"Create action item with visual confirm"` |
| `type` | `full-stack` / `frontend` / `backend` | `full-stack` |
| `priority` | `P0` / `P1` / `P2` | `P0` |
| `tags` | Filtering labels list | `[smoke, api, ui]` |
| `feature` | `FEAT-XXX` | `FEAT-003` |
| `preconditions` | Auth, navigation, DB state | See schema |
| `steps` | Ordered list of test actions | See schema |
| `expected_outcomes` | Summary of what PASS means | List of strings |

Optional but recommended: `description`, `acceptance_criteria`, `requires`.

### Step 5: Apply the Visual Verification Pattern

For ANY `full-stack` test, you MUST include this pattern. This is the core value proposition of the e2e system -- proving the frontend reflects backend truth.

```yaml
# 1. User action (trigger the flow)
- fill:
    selector: "[data-testid='description-input']"
    value: "Review Q4 financials"
  description: "Enter action item description"
- click:
    selector: "[data-testid='create-btn']"
  description: "Submit the form"

# 2. Wait for processing (never use fixed delays)
- wait:
    condition: "element_visible"
    selector: "[data-testid='action-item-card']"
    timeout_ms: 30000
  description: "Wait for new card to appear"
# OR for async agent flows:
- poll:
    condition: "api_status"
    method: "GET"
    path: "/api/agent/missions/{mission_id}"
    field: "status"
    expect: "completed"
    interval_ms: 2000
    timeout_ms: 60000
  description: "Wait for agent mission to complete"

# 3. Backend verify (prove the data exists)
- api_check:
    method: "GET"
    path: "/api/projects/{project_id}/action-items"
    expected_status: 200
    expect:
      body_contains: "Review Q4 financials"
  description: "Verify API returns the created item"
# AND/OR
- db_check:
    query: >
      SELECT description, status FROM action_items
      WHERE project_id = '{project_id}'
      ORDER BY created_at DESC LIMIT 1
    expect:
      description_contains: "Review Q4 financials"
      status: "open"
  description: "Verify DB row was created"

# 4. Visual confirm (MANDATORY for full-stack -- proves FE reflects BE)
- visual_confirm:
    description: "Verify action item card appears with correct data"
    assertions:
      - assert_visible:
          text: "Review Q4 financials"
      - assert_visible:
          selector: "[data-testid='action-item-card']"
      - assert_visible:
          text: "open"
          selector: "[data-testid='status-badge']"
    screenshot: "e2e-ft-001-visual-confirm.png"
    reflects:
      db_table: "action_items"
      api_endpoint: "/api/projects/{project_id}/action-items"
  description: "Visual confirmation that UI matches backend state"
```

### Step 6: Validate Before Committing

Run through this checklist before considering the YAML complete:

- [ ] All placeholders use `{curly_brace}` syntax (never hardcoded values)
- [ ] No hardcoded URLs, ports, or credentials anywhere
- [ ] Placeholder keys match the allowed set: `fe_url`, `be_url`, `project_id`, `test_email`, `test_password`, `token`, `user_id`, `mission_id`, `company_id`, `company_a_id`, `company_b_id`, `chat_id`, `action_item_id`, `timestamp`
- [ ] File name follows convention: `e2e-{feature-abbrev}-{NNN}-{slug}.yaml`
- [ ] `full-stack` tests have a `visual_confirm` step (non-negotiable)
- [ ] All selectors use `data-testid` attributes or semantic selectors (`button:has-text(...)`, `#id`), never brittle CSS classes (`.css-abc123`)
- [ ] Every step has a `description` field
- [ ] `expected_outcomes` lists what PASS means in plain language
- [ ] The 5-line ABOUTME header is present at the top of the file

## 4. Feature Abbreviation Map

| Feature | Abbreviation | Directory |
|---------|-------------|-----------|
| FEAT-001 Infrastructure | INF | `feat-001/` |
| FEAT-002 Briefcase | BC | `feat-002/` |
| FEAT-003 Follow-Through | FT | `feat-003/` |
| FEAT-004 Diligence | DD | `feat-004/` |

When generating test IDs, use the abbreviation: `E2E-FT-001`, `E2E-BC-002`, `E2E-DD-003`.

## 5. Priority Guide

| Priority | Criteria | Example |
|----------|----------|---------|
| P0 | Core user journey. Must pass before merge. Blocks release. | Login, create action item, view project dashboard |
| P1 | Important functionality. Should pass, escalate if blocked. | Filtering action items, sorting, field validation |
| P2 | Nice to have. Deferrable, log to backlog if failing. | Tooltip rendering, animation timing, empty state styling |

**Default to P0** for any test covering a core CRUD operation or authentication flow. Demote only with justification.

## 6. Step Type Quick Reference

All step types defined in `test-case.schema.yaml`:

| Step Type | Purpose | Required Fields | Used In |
|-----------|---------|-----------------|---------|
| `navigate` | Load URL in browser | URL string | All |
| `fill` | Set input field value | `selector`, `value` | All with forms |
| `click` | Click element | `selector` | All with interaction |
| `wait` | Wait for condition | `condition`, `timeout_ms` | All |
| `assert_visible` | Verify text or element visible | `text` and/or `selector` | All |
| `assert_network` | Check browser network log | `url_contains`, `status` | Frontend, full-stack |
| `assert_no_console_errors` | No JS errors in console | `true` | Frontend, full-stack |
| `screenshot` | Capture visual evidence | filename string | All |
| `api_check` | Verify API response | `method`, `path`, `expected_status` | Backend, full-stack |
| `db_check` | Verify database state | `query`, `expect` | Backend, full-stack |
| `visual_confirm` | Prove FE reflects BE state | `assertions`, `screenshot`, `reflects` | Full-stack (mandatory) |
| `evaluate` | Run JavaScript in browser | `script` | Advanced UI checks |
| `poll` | Repeatedly check condition | `condition`, `expect`, `interval_ms`, `timeout_ms` | Async flows |
| `compare` | Cross-source data comparison | `source`, `expected` | Data verification |
| `custom_check` | Run Python script | `script` | Escape hatch |
| `notification_check` | Cross-system verification | `type`, `within_ms` | Email, webhook, log |
| `multi_tab` | Multi-tab browser scenarios | `tabs`, `steps` | Side-by-side |
| `timing_assert` | Event timing verification | `start_event`, `end_event`, `max_duration_ms` | Performance SLAs |

## 7. Anti-Patterns

Things that MUST NOT appear in generated YAML:

| Anti-Pattern | Why It Breaks | Fix |
|-------------|---------------|-----|
| Hardcoded URLs (`http://localhost:3456`) | Breaks in CI, other ports, other environments | Use `{be_url}`, `{fe_url}` placeholders |
| Hardcoded IDs or credentials | Tests become non-portable | Use `{project_id}`, `{test_email}`, etc. |
| Missing `visual_confirm` on full-stack | Defeats the purpose of full-stack testing | Always add the visual verification block |
| Brittle selectors (`.css-abc123`, `.MuiButton-root`) | Break on any style change | Use `[data-testid='...']` or `button:has-text('...')` |
| Testing implementation details (checking Redux state, internal API structure) | Couples test to code, not behavior | Test what the USER sees and experiences |
| Over-testing (multiple assertions per AC) | Slow, fragile, hard to debug failures | One focused test per acceptance criterion |
| Copy-pasting tests with minor tweaks | DRY violation, maintenance nightmare | Parameterize or restructure the requirement |
| Fixed sleep/delay instead of `wait`/`poll` | Flaky -- sometimes too slow, sometimes wasteful | Use condition-based waits with timeouts |
| Missing `description` on steps | Test report is unreadable, debugging is painful | Every step gets a description, no exceptions |

## 8. Examples

### Example 1: Backend-Only Health Check (P0)

```yaml
# ABOUTME: P0 backend health check verifying API availability.
# ABOUTME: No browser interaction -- pure API verification.
# ABOUTME: Should be the first test run in any suite.
# ABOUTME: Covers FEAT-001 infrastructure readiness.
# ABOUTME: File: e2e-inf-001-health-check.yaml

id: "E2E-INF-001"
name: "Backend health check"
type: "backend"
priority: "P0"
tags:
  - "smoke"
  - "api"
feature: "FEAT-001"

description: |
  Verify the backend is running and responding to health checks.
  This is the most basic infrastructure test -- if this fails,
  no other tests will pass.

acceptance_criteria:
  - "AC-1: GET /health returns 200 with status ok"

requires:
  - "backend"

preconditions: {}

steps:
  - api_check:
      method: "GET"
      path: "/health"
      expected_status: 200
      expect:
        body_contains: "ok"
    description: "Verify /health endpoint returns 200 with ok status"

expected_outcomes:
  - "Backend API is reachable and healthy"
  - "/health returns 200 with status ok"
```

### Example 2: Full-Stack Create Action Item (P0)

```yaml
# ABOUTME: P0 full-stack test for creating an action item via the UI.
# ABOUTME: Covers login, form submission, backend verification, and visual confirm.
# ABOUTME: Exercises the core FEAT-003 Follow-Through user journey.
# ABOUTME: Requires backend, frontend, and agent_system migration.
# ABOUTME: File: e2e-ft-001-create-action-item.yaml

id: "E2E-FT-001"
name: "Create action item with visual confirmation"
type: "full-stack"
priority: "P0"
tags:
  - "smoke"
  - "api"
  - "ui"
feature: "FEAT-003"

description: |
  End-to-end test for the core action item creation flow.
  User logs in, navigates to project, creates an action item,
  and we verify the item exists in the DB, API, and is visible
  in the UI.

acceptance_criteria:
  - "AC-1: User can create an action item from the project page"
  - "AC-2: Created item appears in the action items panel"
  - "AC-3: Backend stores the item with correct status"

requires:
  - "backend"
  - "frontend"
  - "migration:add_agent_system"

preconditions:
  auth:
    email: "{test_email}"
    password: "{test_password}"
  navigate: "{fe_url}/project/{project_id}"

steps:
  # --- Authentication ---
  - navigate: "{fe_url}/auth"
    description: "Load the auth page"

  - fill:
      selector: "#signin-email"
      value: "{test_email}"
    description: "Enter test email"

  - fill:
      selector: "#signin-password"
      value: "{test_password}"
    description: "Enter test password"

  - click:
      selector: "button:has-text('Sign In')"
    description: "Submit login form"

  - wait:
      condition: "url_contains"
      value: "/"
      timeout_ms: 5000
    description: "Wait for redirect to dashboard after login"

  # --- Navigate to project ---
  - navigate: "{fe_url}/project/{project_id}"
    description: "Navigate to the test project"

  - wait:
      condition: "element_visible"
      selector: "[data-testid='project-header']"
      timeout_ms: 10000
    description: "Wait for project page to load"

  # --- Create action item ---
  - click:
      selector: "[data-testid='action-items-tab']"
    description: "Switch to action items tab"

  - fill:
      selector: "[data-testid='action-item-description']"
      value: "Review Q4 financial statements"
    description: "Enter action item description"

  - click:
      selector: "[data-testid='create-action-item-btn']"
    description: "Submit the new action item"

  - wait:
      condition: "element_visible"
      selector: "[data-testid='action-item-card']"
      timeout_ms: 30000
    description: "Wait for the new action item card to appear"

  # --- Backend verification ---
  - api_check:
      method: "GET"
      path: "/api/projects/{project_id}/action-items"
      expected_status: 200
      expect:
        body_contains: "Review Q4 financial statements"
    description: "Verify action items API returns the created item"

  - db_check:
      query: >
        SELECT description, status FROM action_items
        WHERE project_id = '{project_id}'
        ORDER BY created_at DESC LIMIT 1
      expect:
        description_contains: "Review Q4 financial statements"
        status: "open"
    description: "Verify action item row exists in DB with open status"

  # --- Visual confirmation ---
  - visual_confirm:
      description: "Verify action item card renders with correct data from backend"
      assertions:
        - assert_visible:
            text: "Review Q4 financial statements"
        - assert_visible:
            selector: "[data-testid='action-item-card']"
        - assert_visible:
            text: "open"
            selector: "[data-testid='status-badge']"
      screenshot: "e2e-ft-001-visual-confirm-action-item.png"
      reflects:
        db_table: "action_items"
        api_endpoint: "/api/projects/{project_id}/action-items"

  - assert_no_console_errors: true
    description: "No JavaScript errors during the entire flow"

expected_outcomes:
  - "User successfully creates an action item from the project page"
  - "Action item appears in the UI with correct description and open status"
  - "Database contains the new row with matching data"
  - "API returns the item in the action items list"
  - "No console errors during the flow"
```

### Example 3: Async Agent Flow with Poll and Timing (P1)

```yaml
# ABOUTME: P1 test for async agent mission execution with timing verification.
# ABOUTME: Triggers an agent mission, polls for completion, verifies results.
# ABOUTME: Covers FEAT-004 Diligence agent execution pipeline.
# ABOUTME: Uses poll, timing_assert, and visual_confirm patterns.
# ABOUTME: File: e2e-dd-001-agent-mission-complete.yaml

id: "E2E-DD-001"
name: "Agent mission completes within SLA"
type: "full-stack"
priority: "P1"
tags:
  - "agent"
  - "api"
  - "ui"
feature: "FEAT-004"

description: |
  Verify that triggering an agent mission from the UI results in
  a completed mission within the expected time window. Covers the
  full async flow: trigger -> poll -> verify -> visual confirm.

acceptance_criteria:
  - "AC-1: User can trigger an agent mission from the project page"
  - "AC-2: Mission completes within 5 minutes"
  - "AC-3: Completed mission results are visible in the UI"

requires:
  - "backend"
  - "frontend"
  - "migration:add_agent_system"

preconditions:
  auth:
    email: "{test_email}"
    password: "{test_password}"
  navigate: "{fe_url}/project/{project_id}"

steps:
  # --- Authentication (same pattern as all full-stack tests) ---
  - navigate: "{fe_url}/auth"
    description: "Load the auth page"

  - fill:
      selector: "#signin-email"
      value: "{test_email}"
    description: "Enter test email"

  - fill:
      selector: "#signin-password"
      value: "{test_password}"
    description: "Enter test password"

  - click:
      selector: "button:has-text('Sign In')"
    description: "Submit login form"

  - wait:
      condition: "url_contains"
      value: "/"
      timeout_ms: 5000
    description: "Wait for redirect after login"

  # --- Navigate and trigger mission ---
  - navigate: "{fe_url}/project/{project_id}"
    description: "Navigate to the test project"

  - click:
      selector: "[data-testid='trigger-agent-btn']"
    emit_event: "agent_mission_triggered"
    description: "Trigger agent mission"

  # --- Poll for completion (async -- agent takes unpredictable time) ---
  - poll:
      condition: "api_status"
      method: "GET"
      path: "/api/agent/missions/{mission_id}"
      field: "status"
      expect: "completed"
      interval_ms: 3000
      timeout_ms: 300000
    emit_event: "agent_mission_completed"
    description: "Poll agent mission status until completed or timeout"

  # --- Timing verification ---
  - timing_assert:
      start_event: "agent_mission_triggered"
      end_event: "agent_mission_completed"
      max_duration_ms: 300000
      description: "Verify agent mission completes within 5-minute SLA"

  # --- Backend verification ---
  - api_check:
      method: "GET"
      path: "/api/agent/missions/{mission_id}"
      expected_status: 200
      expect:
        body_contains: "completed"
    description: "Verify mission API shows completed status"

  # --- Refresh UI and visual confirm ---
  - navigate: "{fe_url}/project/{project_id}"
    description: "Reload project page to see mission results"

  - wait:
      condition: "element_visible"
      selector: "[data-testid='mission-results']"
      timeout_ms: 10000
    description: "Wait for mission results to render"

  - visual_confirm:
      description: "Verify mission results are visible in the UI after completion"
      assertions:
        - assert_visible:
            selector: "[data-testid='mission-results']"
        - assert_visible:
            text: "completed"
            selector: "[data-testid='mission-status']"
      screenshot: "e2e-dd-001-visual-confirm-mission.png"
      reflects:
        db_table: "agent_missions"
        api_endpoint: "/api/agent/missions/{mission_id}"

  - assert_no_console_errors: true
    description: "No JavaScript errors during the entire flow"

expected_outcomes:
  - "Agent mission is triggered successfully from the UI"
  - "Mission completes within the 5-minute SLA"
  - "Completed status is visible in both the API and the UI"
  - "No console errors during the async flow"
```

## 9. Cross-References

| Resource | Path | Purpose |
|----------|------|---------|
| YAML Schema | `boardroom-ai/e2e/schemas/test-case.schema.yaml` | Canonical format definition with all step types |
| Config / Routes | `boardroom-ai/e2e/config.py` | All URLs, ports, credentials, route maps |
| Existing Visual Test | `boardroom-ai/e2e/visual/p0_action_items.yaml` | Real-world example of a P0 visual test |
| E2E Testing Skill | `e2e-testing` (personal skill) | How to RUN tests (prerequisites, Chrome DevTools, troubleshooting) |
| E2E QA Runner Skill | `e2e-qa-runner` (personal skill) | Skill for executing generated tests (under construction) |
| FE Route Map | `config.py` -> `FE_ROUTES` | Singular `/project/{id}`, NOT `/projects/{id}` |
| BE Route Map | `config.py` -> `API_ROUTES` | Action items and agent use `/api/` prefix; auth/projects/health do NOT |

## 10. Route Gotchas (Memorize These)

These are the two most common mistakes agents make when generating test YAML:

1. **Frontend routes use SINGULAR nouns:** `/project/{id}` not `/projects/{id}`. Check `FE_ROUTES` in `config.py`.
2. **Backend routes have inconsistent prefixes:** `/api/projects/{project_id}/action-items` (has `/api/`) but `/projects/{project_id}` (no `/api/`). Check `API_ROUTES` in `config.py`.

When in doubt, read `config.py`. Never guess a route.
