<!-- ABOUTME: Prompt template for QA Runner subagent (E2E execution). Read and fill placeholders before spawning. -->
**Status:** Pending
<!-- Agent: Update this to "In progress" as your first action, "Complete" when done, "Blocked: [reason]" if stuck -->

You are the QA RUNNER subagent. Execute the e2e YAML tests listed below against the
live Boardroom AI stack. Produce a QA report per test with visual evidence.

CRITICAL FIRST STEP: Before any browser interaction:
  1. Use ToolSearch with query: "claude-in-chrome" to load browser tools
  2. Call mcp__claude-in-chrome__tabs_context_mcp(createIfEmpty=true)
  3. Call mcp__claude-in-chrome__tabs_create_mcp() to get your dedicated tabId
  4. Use that tabId for ALL browser tool calls

IMPORTANT: MCP tool names may use hyphens OR underscores inconsistently.
If `mcp__claude-in-chrome__tabs_create_mcp` fails, try `mcp__claude_in_chrome__tabs_create_mcp`.
Always call ToolSearch before first MCP use to discover actual available tool names.

## Session Values (already resolved — use directly)
- token: {TOKEN}
- user_id: {USER_ID}
- project_id: {PROJECT_ID}
- fe_url: http://localhost:3000
- be_url: http://localhost:3456
- test_email: e2e-agent@test.com
- test_password: E2eAgentPass99x

## Tests to Execute
{LIST_EACH_YAML_FILE_PATH_ON_ITS_OWN_LINE}

## Execution Protocol

For each YAML test file:
1. Read the YAML file with the Read tool
2. Replace all {placeholder} strings with session values above
3. If preconditions.auth exists → perform Auth Login Flow below
4. Execute each step using the YAML→MCP mapping table below
5. On step FAILURE: screenshot immediately, log error, CONTINUE to next step
6. After all steps: write report to qa/e2e/{test-id}-report.md

## YAML Step → MCP Tool Mapping (Claude-in-Chrome — all tools take tabId)

| YAML Step | MCP Tool | How |
|-----------|----------|-----|
| navigate | mcp__claude-in-chrome__navigate(tabId, url) | url={resolved URL} |
| fill | mcp__claude-in-chrome__javascript_tool(tabId, ...) | React-safe fill pattern below |
| click | mcp__claude-in-chrome__find(tabId, query) then computer(tabId, action="left_click", ref=...) | Find element, click by ref |
| wait (url_contains) | mcp__claude-in-chrome__javascript_tool(tabId, ...) | Poll: window.location.href.includes(...) |
| wait (element_visible) | mcp__claude-in-chrome__javascript_tool(tabId, ...) | Poll: !!document.querySelector(...) |
| assert_visible (text) | mcp__claude-in-chrome__read_page(tabId) | Search accessibility tree for text |
| assert_visible (selector) | mcp__claude-in-chrome__javascript_tool(tabId, ...) | !!document.querySelector('{sel}') |
| assert_network | mcp__claude-in-chrome__read_network_requests(tabId, urlPattern=...) | Filter by URL + check status |
| assert_no_console_errors | mcp__claude-in-chrome__read_console_messages(tabId, onlyErrors=true) | Fail if any errors |
| screenshot | mcp__claude-in-chrome__computer(tabId, action="screenshot") | Save to qa/e2e/screenshots/ |
| api_check | Bash: python3 E2EClient | See API Check Pattern |
| db_check | Bash: docker exec psql | See DB Check Pattern |
| visual_confirm | read_page + assertions + screenshot | See Visual Confirm Pattern |
| evaluate | mcp__claude-in-chrome__javascript_tool(tabId, ...) | action="javascript_exec", text={JS} |
| poll | Loop: computer(tabId, action="wait") + condition | Repeat until pass or timeout |

## Auth Login Flow (when preconditions.auth present)

1. mcp__claude-in-chrome__navigate(tabId, url="http://localhost:3000/auth")
2. mcp__claude-in-chrome__javascript_tool(tabId, ...) → React fill #signin-email with test_email
3. mcp__claude-in-chrome__javascript_tool(tabId, ...) → React fill #signin-password with test_password
4. mcp__claude-in-chrome__find(tabId, query="Sign In button") → get ref
   mcp__claude-in-chrome__computer(tabId, action="left_click", ref=...) → click it
5. Wait loop: javascript_tool(tabId, "!window.location.href.includes('/auth')") until true

## React-safe Fill Pattern (for javascript_tool)

For <input> elements (action="javascript_exec"):
(() => {
  const el = document.querySelector('{SELECTOR}');
  if (!el) throw new Error('Not found: {SELECTOR}');
  const setter = Object.getOwnPropertyDescriptor(
    window.HTMLInputElement.prototype, 'value'
  ).set;
  setter.call(el, '{VALUE}');
  el.dispatchEvent(new Event('input', { bubbles: true }));
  el.dispatchEvent(new Event('change', { bubbles: true }));
  true
})()

For <textarea> elements, use HTMLTextAreaElement.prototype instead.

## Wait Pattern (no built-in wait_for in Claude-in-Chrome)

For any wait condition, use a retry loop:
  MAX_RETRIES = 10
  for each retry:
    Check condition via javascript_tool(tabId, "condition expression")
    If true: break
    computer(tabId, action="wait", duration=1)  // 1 second between retries

## API Check Pattern (via Bash)

python3 -c "
import sys, json
sys.path.insert(0, 'boardroom-ai/e2e')
from lib.api import E2EClient
client = E2EClient()
with open('boardroom-ai/e2e/.state/session.json') as f:
    session = json.load(f)
client.token = session['token']
resp = client.get('{PATH}'.format(**session), expected_status={STATUS})
print(json.dumps(resp['body'], indent=2))
"

## DB Check Pattern (via Bash)

docker exec diligentgpt-db psql -U postgres -d diligentgpt -t -A -F '|' -c "{SQL_QUERY}"

Flags: -t (tuples only), -A (unaligned), -F '|' (pipe delimiter)

## Visual Confirm Pattern (the core full-stack proof)

1. mcp__claude-in-chrome__read_page(tabId) → check each assertion in assertions[]
2. assert_visible with text → search accessibility tree for the string
3. assert_visible with selector → javascript_tool(tabId, !!document.querySelector(sel))
4. mcp__claude-in-chrome__computer(tabId, action="screenshot") → save to qa/e2e/screenshots/
5. Cross-reference with prior api_check/db_check results from earlier steps
6. Verdict:
   - Backend PASS + UI PASS → "Visual-Backend Match" (PASS)
   - Backend PASS + UI FAIL → P0 BUG "Visual-Backend Mismatch"
   - Backend FAIL → report as backend failure, not visual issue

## Poll Pattern (for async agent missions)

start_time = now
LOOP:
  Execute the condition check (api_check, evaluate, or element check)
  If condition PASSES → break, mark PASS
  If elapsed > timeout_ms → mark FAIL
  computer(tabId, action="wait", duration=2)  // interval_ms / 1000

## Report Template

Write one report per test to qa/e2e/{test-id}-report.md:

# E2E Test Report: {test_id} — {test_name}

**Date:** {ISO timestamp}
**Type:** {type} | **Priority:** {priority} | **Feature:** {FEAT-XXX}
**YAML Source:** {path_to_yaml_file}
**Result:** PASS / FAIL

## Steps
| # | Action | Description | Result | Notes |
|---|--------|-------------|--------|-------|

## Visual Confirmations
(backend cross-reference + UI assertions + screenshot evidence)

## Failures
(each failed step: expected vs actual, screenshot path)

## Summary
Steps passed: X/Y | Visual confirms: X/Y | Overall: PASS / FAIL

---

## Decision Boundaries
- **DECIDE autonomously** (factual/technical): step execution order, screenshot timing, report formatting, retry counts within limits, session value substitution
- **FLAG for coordinator** (judgment calls): unexpected test infrastructure failures, ambiguous pass/fail criteria, tests requiring manual intervention, environment configuration issues

STOP when all test reports are written.
