---
name: e2e-qa-runner
description: Use when executing e2e YAML tests for Boardroom AI — drives Claude-in-Chrome MCP for browser verification (per-tab isolation, parallelizable), E2EClient for backend checks, and produces QA artifacts with visual evidence
---

# E2E QA Runner — YAML Test Execution via Claude-in-Chrome

Execute YAML-defined e2e test cases against the Boardroom AI stack. This skill translates
declarative YAML steps into Claude-in-Chrome MCP tool calls (browser, per-tab isolation)
and E2EClient calls (backend/DB), then produces QA artifact reports with visual evidence.

**Parallelism:** Each subagent gets its own Chrome tab via `tabId`. Multiple subagents
can run browser tests in parallel with zero interference.

---

## 1. Prerequisites Checklist

Run these checks IN ORDER before executing any test. If any fail, stop and fix.

```bash
# 1. Docker stack running (all 3 services: backend, frontend, db)
docker compose -f boardroom-ai/docker-compose.yml ps

# 2. Backend healthy (must return 200)
curl http://localhost:3456/health

# 3. Frontend running (must return 200)
curl -s -o /dev/null -w '%{http_code}' http://localhost:3000

# 4. Read config (source of truth for all URLs, ports, credentials)
# File: boardroom-ai/e2e/config.py

# 5. Run setup (creates test user, logs in, creates project)
python boardroom-ai/e2e/setup.py

# 6. Load session (auth token, user_id, project_id)
# File: boardroom-ai/e2e/.state/session.json
```

**Session JSON structure** (returned by setup.py):
```json
{
  "token": "eyJ...",
  "user_id": "uuid-string",
  "project_id": "uuid-string",
  "email": "e2e-agent@test.com",
  "fe_url": "http://localhost:3000",
  "be_url": "http://localhost:3456"
}
```

These values become the placeholder context for `{token}`, `{user_id}`, `{project_id}`,
`{email}`, `{fe_url}`, `{be_url}` in YAML test files. Additional config-based
placeholders (`{test_email}`, `{test_password}`) come from `config.py`.

---

## 2. Tab Setup (MUST DO FIRST)

Before any browser interaction, each subagent MUST:

1. **Load Claude-in-Chrome tools:**
   ```
   ToolSearch with query: "claude-in-chrome"
   ```

2. **Get tab context:**
   ```
   mcp__claude-in-chrome__tabs_context_mcp(createIfEmpty=true)
   ```

3. **Create a dedicated tab for this subagent:**
   ```
   mcp__claude-in-chrome__tabs_create_mcp()
   ```
   Record the returned `tabId`. Use this tabId for ALL subsequent browser calls.

**Each subagent uses its own tabId.** This is what enables parallel execution.

---

## 3. YAML Action to MCP Tool Mapping

Every YAML step type maps to one or more MCP tool calls. Use this table as the
authoritative reference when translating YAML steps into tool invocations.

**All browser tools require `tabId`.** Use the tabId from Tab Setup (Section 2).

| YAML Action | MCP Tool(s) | Notes |
|---|---|---|
| `navigate` | `mcp__claude-in-chrome__navigate(tabId, url)` | Pass full URL with placeholders resolved |
| `fill` | `mcp__claude-in-chrome__javascript_tool(tabId, ...)` | React-safe fill pattern (Section 6). Alt: `find` + `form_input` |
| `click` | `mcp__claude-in-chrome__find(tabId, query)` then `mcp__claude-in-chrome__computer(tabId, action="left_click", ref=...)` | Find element by text/purpose, click by ref. Alt: `javascript_tool` with `.click()` |
| `wait` (url_contains) | `mcp__claude-in-chrome__javascript_tool(tabId, ...)` polling | Check `window.location.href.includes(...)` in a retry loop |
| `wait` (element_visible) | `mcp__claude-in-chrome__javascript_tool(tabId, ...)` polling | Check `!!document.querySelector(...)` in a retry loop |
| `assert_visible` (text) | `mcp__claude-in-chrome__read_page(tabId)` | Search accessibility tree output for the text |
| `assert_visible` (selector) | `mcp__claude-in-chrome__javascript_tool(tabId, ...)` | `!!document.querySelector('{selector}')` |
| `assert_network` | `mcp__claude-in-chrome__read_network_requests(tabId, urlPattern=...)` | Filter by URL pattern and check status |
| `assert_no_console_errors` | `mcp__claude-in-chrome__read_console_messages(tabId, onlyErrors=true)` | Fail if any error messages returned |
| `screenshot` | `mcp__claude-in-chrome__computer(tabId, action="screenshot")` | Save to `qa/e2e/screenshots/` |
| `api_check` | E2EClient via Bash (python) | Backend HTTP verification (Section 7) |
| `db_check` | `docker exec` psql | Database row verification (Section 8) |
| `visual_confirm` | read_page + assertions + screenshot | Full-stack visual proof (Section 5) |
| `evaluate` | `mcp__claude-in-chrome__javascript_tool(tabId, ...)` | Run the JS expression. Use `action="javascript_exec"` |
| `poll` | Loop with `computer(tabId, action="wait")` + condition check | For async flows like agent missions (Section 9.4) |
| `compare` | javascript_tool + api/db check + comparison | Data-driven: FE value vs BE value |
| `custom_check` | Bash (python script) | Escape hatch for anything else |
| `notification_check` | Depends on type | email = DB check, log = `docker logs` |
| `multi_tab` | `mcp__claude-in-chrome__tabs_create_mcp()` per extra tab | Each tab gets its own tabId — no `select_page` needed |
| `timing_assert` | Timestamps captured during execution | Assert elapsed time within window |

---

## 4. Execution Protocol

Follow this sequence for every YAML test file:

```
BEFORE ALL TESTS:
  1. Verify prerequisites (Section 1)
  2. Ensure session.json exists and is fresh
  3. Complete Tab Setup (Section 2) — get your dedicated tabId

FOR EACH YAML TEST FILE:
  1. Read YAML file from disk
  2. Validate required fields: id, name, type, priority, steps
     - type must be: full-stack | frontend | backend
     - priority must be: P0 | P1 | P2
  3. Resolve {placeholders} using session.json values:
     - {fe_url}        -> http://localhost:3000
     - {be_url}        -> http://localhost:3456
     - {token}         -> JWT from session
     - {user_id}       -> UUID from session
     - {project_id}    -> UUID from session
     - {email}         -> e2e-agent@test.com
     - {test_email}    -> e2e-agent@test.com (from config.py)
     - {test_password} -> E2eAgentPass99x (from config.py)
     - {timestamp}     -> current ISO timestamp
  4. Execute preconditions (if present):
     a. preconditions.auth -> perform browser login (fill + click + wait)
     b. preconditions.navigate -> navigate to starting URL
     c. preconditions.db_state -> verify or set up required DB state
  5. FOR EACH STEP in steps[]:
     a. Read the step action type (navigate, fill, click, wait, assert_*, etc.)
     b. Map to MCP tool using the table in Section 3
     c. Execute the tool call with resolved parameters AND tabId
     d. On SUCCESS: log step number, action, "PASS"
     e. On FAILURE: capture screenshot, log error with step number, mark FAIL,
        CONTINUE to next step (do NOT abort the test)
  6. After all steps: compile results into QA artifact (Section 10)

AFTER ALL TESTS:
  - Optionally run teardown: python boardroom-ai/e2e/teardown.py
```

---

## 5. Visual Verification Protocol

This is the CORE value of full-stack e2e tests. The `visual_confirm` step type proves
that what the user sees in the browser matches what the backend actually stored.

**Every full-stack test MUST include at least one visual_confirm step.**

### Execution sequence for `visual_confirm`:

```
1. PRECONDITION: A user action was performed in the browser (fill, click, submit)
   - The preceding steps should have triggered a state change

2. WAIT for backend processing
   - Use wait (element_visible) or poll pattern for async operations
   - For agent missions: poll the mission status endpoint

3. QUERY backend/DB to confirm data was persisted
   - api_check: GET the relevant endpoint, verify expected data in response
   - db_check: SELECT from the relevant table, verify row exists with expected values
   - Record the backend state for comparison

4. RETURN to browser and verify UI reflects backend state
   - mcp__claude-in-chrome__read_page(tabId) -> search accessibility tree for expected text
   - mcp__claude-in-chrome__javascript_tool(tabId, ...) -> check element content/attributes
   - Execute each assertion in the visual_confirm.assertions[] array

5. CAPTURE screenshot as evidence
   - mcp__claude-in-chrome__computer(tabId, action="screenshot")
   - Save to qa/e2e/screenshots/{test_id}-visual-confirm-{description_slug}.png

6. EVALUATE result
   - If step 3 PASSED (backend has data) AND step 4 PASSED (UI shows it):
     -> PASS: "Visual-Backend Match"
   - If step 3 PASSED but step 4 FAILED:
     -> P0 BUG: "Visual-Backend Mismatch" — backend data exists but UI doesn't show it
     -> This means FE/BE are out of sync. Report immediately.
   - If step 3 FAILED:
     -> The backend action failed. Report as backend failure, not visual mismatch.
```

### YAML example with visual_confirm:

```yaml
# After creating an action item...
- visual_confirm:
    description: "Action item card appears in project view"
    assertions:
      - assert_visible:
          text: "Review financials"
      - assert_visible:
          selector: "[data-testid='action-item-card']"
      - assert_visible:
          text: "open"
          selector: ".status-badge"
    screenshot: "e2e-ft-001-visual-confirm-card.png"
    reflects:
      db_table: "action_items"
      api_endpoint: "/api/projects/{project_id}/action-items"
```

### How to execute it:

```
1. Read page: mcp__claude-in-chrome__read_page(tabId) -> search for "Review financials"
2. Evaluate: javascript_tool(tabId, !!document.querySelector("[data-testid='action-item-card']")) -> pass/fail
3. Evaluate: javascript_tool(tabId, document.querySelector(".status-badge")?.textContent) -> check "open"
4. Screenshot: computer(tabId, action="screenshot") -> save to qa/e2e/screenshots/
5. Cross-reference: compare against prior api_check/db_check results
```

---

## 6. Fill Form Pattern (React-safe)

React apps use synthetic events. Setting `.value` directly does NOT trigger React's
state updates. You MUST dispatch native events after setting the value.

### Primary approach: javascript_tool with React-safe pattern

For `<input>` elements:

```javascript
// mcp__claude-in-chrome__javascript_tool(tabId, action="javascript_exec", text=...):
(() => {
  const el = document.querySelector('{selector}');
  if (!el) throw new Error('Element not found: {selector}');
  const nativeInputValueSetter = Object.getOwnPropertyDescriptor(
    window.HTMLInputElement.prototype, 'value'
  ).set;
  nativeInputValueSetter.call(el, '{value}');
  el.dispatchEvent(new Event('input', { bubbles: true }));
  el.dispatchEvent(new Event('change', { bubbles: true }));
  true
})()
```

For `<textarea>` elements, use `HTMLTextAreaElement.prototype` instead.

For `<select>` elements:

```javascript
(() => {
  const el = document.querySelector('{selector}');
  if (!el) throw new Error('Element not found: {selector}');
  el.value = '{value}';
  el.dispatchEvent(new Event('change', { bubbles: true }));
  true
})()
```

### Alternative approach: find + form_input (ref-based)

When CSS selectors are unreliable or the element is complex:

```
1. mcp__claude-in-chrome__read_page(tabId, filter="interactive")
   → Find the target element's ref ID (e.g., "ref_5" for the email input)

2. mcp__claude-in-chrome__form_input(tabId, ref="ref_5", value="e2e-agent@test.com")
   → Set the value directly via the extension's form handler
```

**Use javascript_tool (primary) when:** YAML step has a CSS selector and the app is React.
**Use find + form_input (alternative) when:** No clear CSS selector, or javascript_tool fill doesn't trigger state.

### When translating a `fill` YAML step:

```yaml
- fill:
    selector: "#signin-email"
    value: "{test_email}"
```

Call `mcp__claude-in-chrome__javascript_tool` with tabId, action="javascript_exec",
and the React-safe snippet above, substituting `{selector}` and `{value}`.

---

## 7. API Check Pattern (E2EClient via Bash)

The `api_check` step type uses the Python E2EClient, NOT browser network requests.
This verifies backend state independently of the browser.

### How to execute an `api_check` step:

```yaml
- api_check:
    method: "GET"
    path: "/api/projects/{project_id}/action-items"
    expected_status: 200
    expect:
      body_contains: "Review financials"
```

### Translation to Bash:

```bash
python3 -c "
import sys, json, os
sys.path.insert(0, 'boardroom-ai/e2e')
from lib.api import E2EClient

client = E2EClient()
# Load token from session
with open('boardroom-ai/e2e/.state/session.json') as f:
    session = json.load(f)
client.token = session['token']
client.user_id = session['user_id']

path = '/api/projects/{project_id}/action-items'.format(**session)
resp = client.get(path, expected_status=200)
body_str = json.dumps(resp['body'])

# Check body_contains assertion
assert 'Review financials' in body_str, f'Expected body to contain \"Review financials\", got: {body_str[:300]}'
print('api_check PASS')
print(json.dumps(resp['body'], indent=2))
"
```

### Supported `expect` assertions:

| Assertion | Meaning |
|---|---|
| `body_contains: "text"` | JSON-serialized response body includes substring |
| `body_field: {key: value}` | Response body dict has `body[key] == value` |
| `body_length_gte: N` | Response body (if list) has `len >= N` |
| `status: 200` | HTTP status code matches (also via `expected_status`) |

---

## 8. Database Check Pattern

The `db_check` step type queries the PostgreSQL database directly via `docker exec`.

### How to execute a `db_check` step:

```yaml
- db_check:
    query: >
      SELECT description, assignee_name, status
      FROM action_items
      WHERE project_id = '{project_id}'
      ORDER BY created_at DESC LIMIT 1
    expect:
      description_contains: "Review financials"
      status: "open"
```

### Translation to Bash:

```bash
docker exec diligentgpt-db psql -U postgres -d diligentgpt -t -A -F '|' -c \
  "SELECT description, assignee_name, status FROM action_items WHERE project_id = '<resolved_project_id>' ORDER BY created_at DESC LIMIT 1"
```

**Flags:**
- `-t` = tuples only (no headers)
- `-A` = unaligned output
- `-F '|'` = pipe delimiter between columns

### Evaluating `expect` assertions:

| Assertion | Check |
|---|---|
| `description_contains: "text"` | Output row's description column includes substring |
| `status: "value"` | Output row's status column equals value exactly |
| `row_count_gte: N` | Number of output rows >= N |
| `column_equals: {col: val}` | Named column in output equals value |

If the query returns no rows when rows are expected, that is a FAIL.

---

## 9. Common Patterns

### 9.1 Auth Login Flow (precondition)

Most tests start with authentication. Execute this sequence when `preconditions.auth` is present:

```
1. mcp__claude-in-chrome__navigate(tabId, url="http://localhost:3000/auth")
2. mcp__claude-in-chrome__javascript_tool(tabId, ...) → React-safe fill #signin-email with test_email
3. mcp__claude-in-chrome__javascript_tool(tabId, ...) → React-safe fill #signin-password with test_password
4. mcp__claude-in-chrome__find(tabId, query="Sign In button") → get ref
   mcp__claude-in-chrome__computer(tabId, action="left_click", ref=...) → click it
5. Wait for redirect: retry loop checking javascript_tool(tabId, !window.location.href.includes('/auth'))
```

After login, the browser session is authenticated and subsequent navigations work.

### 9.2 Wait Pattern (no built-in wait_for)

Claude-in-Chrome has no `wait_for` tool. Implement waits as retry loops:

```
// Wait for URL to contain substring:
MAX_RETRIES = 10
for i in range(MAX_RETRIES):
  result = javascript_tool(tabId, "window.location.href.includes('{substring}')")
  if result is true: break
  computer(tabId, action="wait", duration=1)

// Wait for element to appear:
MAX_RETRIES = 10
for i in range(MAX_RETRIES):
  result = javascript_tool(tabId, "!!document.querySelector('{selector}')")
  if result is true: break
  computer(tabId, action="wait", duration=1)

// Wait for text to appear (search accessibility tree):
MAX_RETRIES = 10
for i in range(MAX_RETRIES):
  page = read_page(tabId)
  if "expected text" in page: break
  computer(tabId, action="wait", duration=1)
```

### 9.3 Handling Auth Redirects

If navigating to a protected route without auth, the app redirects to `/auth`.
After login, it may redirect back. Handle this:

```
1. Navigate to target URL
2. Check current URL via javascript_tool(tabId, "window.location.href"):
   - If at /auth -> perform login flow (Section 9.1)
   - After login, navigate to target URL again
3. Verify arrival at target URL
```

### 9.4 Poll Pattern (Agent Mission Completion)

Agent missions are async. The `poll` step type repeatedly checks a condition until
it passes or times out.

```yaml
- poll:
    description: "Wait for agent mission to complete"
    condition:
      api_check:
        method: "GET"
        path: "/api/agent/missions/{mission_id}"
        expect:
          body_field:
            status: "completed"
    interval_ms: 2000
    timeout_ms: 60000
    on_timeout: "FAIL"
```

### Translation to execution:

```
start_time = now()
LOOP:
  Execute the condition (api_check, evaluate, etc.)
  If condition PASSES: break, mark PASS
  If elapsed > timeout_ms: mark FAIL (or on_timeout action)
  computer(tabId, action="wait", duration=2)  # interval_ms / 1000
```

### 9.5 Compare Pattern (Data-Driven Verification)

The `compare` step reads a value from the browser and compares it to a backend value:

```yaml
- compare:
    description: "Action item count matches between UI and API"
    browser_value:
      evaluate: "document.querySelectorAll('[data-testid=action-item-card]').length"
    backend_value:
      api_check:
        method: "GET"
        path: "/api/projects/{project_id}/action-items"
        extract: "len(body)"
    assertion: "equals"
```

### Execution:

```
1. Get browser value via javascript_tool(tabId, text="document.querySelectorAll(...).length")
2. Get backend value via E2EClient (python)
3. Compare using assertion type (equals, gte, contains, etc.)
4. Report: "Browser: X, Backend: Y, Assertion: equals -> PASS/FAIL"
```

### 9.6 Multi-Tab Pattern

For tests that require multiple browser tabs. With Claude-in-Chrome this is trivial —
each tab gets its own tabId, no `select_page` switching needed.

```yaml
- multi_tab:
    tabs:
      - name: "user_view"
        navigate: "{fe_url}/project/{project_id}"
      - name: "admin_view"
        navigate: "{fe_url}/settings"
    steps:
      - switch: "user_view"
        action:
          click:
            selector: "#create-item"
      - switch: "admin_view"
        action:
          assert_visible:
            text: "New item created"
```

### Execution:

```
1. For each tab in tabs[]:
   tabs_create_mcp() -> record tabId for this tab name
   navigate(tabId, url) -> navigate to tab's URL

2. For each step in steps[]:
   Look up tabId for the named tab
   Execute the action using that tabId (no page switching needed)
```

### 9.7 Notification Check Pattern

Cross-system verification for notifications:

```yaml
- notification_check:
    type: "email"
    query: "SELECT * FROM notifications WHERE user_id = '{user_id}' AND type = 'email' ORDER BY created_at DESC LIMIT 1"
    expect:
      row_count_gte: 1
      subject_contains: "Action item assigned"
```

For email type: use `db_check` translation (Section 8).
For log type: use `docker logs diligentgpt-backend --since 60s | grep "pattern"`.

---

## 10. QA Artifact Template

After executing a test, produce a markdown report at `qa/e2e/{test_id}-report.md`.

```markdown
# E2E Test Report: {test_id} -- {test_name}

**Date:** {ISO timestamp}
**Type:** {full-stack | frontend | backend}
**Priority:** {P0 | P1 | P2}
**Feature:** {FEAT-XXX}
**YAML Source:** boardroom-ai/e2e/{path_to_yaml}
**Result:** PASS / FAIL

## Steps

| # | Action | Description | Result | Notes |
|---|--------|-------------|--------|-------|
| 1 | navigate | Load the auth page | PASS | |
| 2 | fill | Enter test email | PASS | |
| 3 | fill | Enter test password | PASS | |
| 4 | click | Submit login form | PASS | |
| 5 | wait | Wait for redirect | PASS | |
| 6 | assert_visible | Verify dashboard loaded | FAIL | Text "Dashboard" not found in accessibility tree |
| ... | ... | ... | ... | ... |

## Visual Confirmations

### {visual_confirm.description}
- **Backend state:** {api_check result summary or db_check result summary}
- **UI assertion results:**
  - assert_visible text="Review financials": PASS
  - assert_visible selector="[data-testid='action-item-card']": PASS
  - assert_visible text="open" selector=".status-badge": FAIL -- text not found
- **Screenshot:** ![screenshot](screenshots/{filename})
- **Verdict:** MATCH / VISUAL-BACKEND MISMATCH

## Failures

### Step 6: assert_visible
- **Expected:** Text "Dashboard" visible on page
- **Actual:** Accessibility tree did not contain "Dashboard"
- **Screenshot:** ![failure](screenshots/{test_id}-fail-step-6.png)

## Summary
- Steps passed: X/Y
- Visual confirmations: X/Y matched
- Backend checks: X/Y passed
- Console errors: none / {count} detected
- **Overall:** PASS / FAIL
```

---

## 11. Error Handling Rules

1. **Continue on step failure** -- do NOT abort the entire test when one step fails.
   Execute all remaining steps to get a complete picture.
2. **Screenshot on every failure** -- call `mcp__claude-in-chrome__computer(tabId, action="screenshot")`
   immediately after any step fails. Save to `qa/e2e/screenshots/{test_id}-fail-step-{N}.png`.
3. **Log full error** -- include step number, action type, expected vs actual, and
   any error messages from MCP tool responses.
4. **Compile all failures** -- at the end of the test, list every failed step in
   the Failures section of the report.
5. **Distinguish failure types:**
   - Step failure: action could not be performed (element not found, navigation error)
   - Assertion failure: action succeeded but result didn't match expectation
   - Visual-Backend Mismatch: backend data correct but UI doesn't reflect it (P0)
   - Timeout: waited longer than timeout_ms for a condition
6. **Never silently swallow errors** -- every failure must appear in the report.

---

## 12. File Locations Reference

| Resource | Path |
|---|---|
| Test case schema | `boardroom-ai/e2e/schemas/test-case.schema.yaml` |
| Config (URLs, ports, creds) | `boardroom-ai/e2e/config.py` |
| API client (E2EClient) | `boardroom-ai/e2e/lib/api.py` |
| YAML loader/validator | `boardroom-ai/e2e/lib/yaml_loader.py` |
| Setup script | `boardroom-ai/e2e/setup.py` |
| Teardown script | `boardroom-ai/e2e/teardown.py` |
| Test runner | `boardroom-ai/e2e/run_all.py` |
| Session state | `boardroom-ai/e2e/.state/session.json` |
| Visual YAML tests | `boardroom-ai/e2e/visual/` |
| Feature test YAMLs | `boardroom-ai/e2e/tests/feat-XXX/` |
| Screenshot output | `qa/e2e/screenshots/` |
| Report output | `qa/e2e/` |

---

## 13. Port and Route Quick Reference

### Ports
| Service | External Port | Internal Port |
|---|---|---|
| Backend | 3456 | 8000 |
| Frontend | 3000 | 8080 |
| Database | 5432 | 5432 |

### Route Prefix Rules
- `/auth/*`, `/projects/*`, `/health`, `/chats/*` -- NO prefix
- `/api/projects/{id}/action-items`, `/api/action-items/*`, `/api/agent/*` -- `/api/` prefix

### Frontend Routes (note SINGULAR `/project/`)
- Auth: `/auth`
- Dashboard: `/`
- Project: `/project/{id}` (NOT `/projects/{id}`)
- Chat: `/chat/{chatId}`
- Company: `/company/{id}`

---

## 14. Checklist Before Submitting QA Artifact

Before finalizing the test report, verify:

- [ ] All steps executed (none skipped silently)
- [ ] Every failure has a screenshot attached
- [ ] Visual confirmations include backend cross-reference
- [ ] Placeholders were resolved (no raw `{placeholder}` strings in report)
- [ ] Screenshot files actually exist at the listed paths
- [ ] Report is saved to `qa/e2e/{test_id}-report.md`
- [ ] Screenshots saved to `qa/e2e/screenshots/`
- [ ] Overall result accurately reflects step results (any FAIL = overall FAIL)
- [ ] Any Visual-Backend Mismatch is flagged as P0
