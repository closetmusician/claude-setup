---
name: pr-review-pr
description: "Comprehensive PR review using specialized agents"
argument-hint: "[review-aspects]"
allowed-tools: ["Bash", "Glob", "Grep", "Read", "Task"]
---

# Comprehensive PR Review

Run a comprehensive pull request review using multiple specialized agents, each focusing on a different aspect of code quality.

**Review Aspects (optional):** "$ARGUMENTS"

## Review Workflow:

1. **Determine Review Scope**
   - Check git status to identify changed files
   - Parse arguments to see if user requested specific review aspects
   - Default: Run all applicable reviews

2. **Available Review Aspects:**

   **Individual skills:**
   - **comments** - Analyze code comment accuracy and maintainability
   - **tests** - Review test coverage quality and completeness
   - **errors** - Check error handling for silent failures
   - **types** - Analyze type design and invariants (if new types added)
   - **code** - General code review for project guidelines
   - **simplify** - Simplify code for clarity and maintainability
   - **all** - Run all applicable reviews (default)

   **Named personas** (each wraps multiple skills with a focused lens):
   - **architecture** - System design, boundaries, coupling, scaling, security (see `personas/architecture-reviewer.md`)
   - **domain** - Business logic correctness, test coverage, comment accuracy (see `personas/domain-specialist.md`)
   - **ambition** - Over-engineering detection, scope creep, YAGNI enforcement (see `personas/ambition-backstop.md`)

3. **Identify Changed Files**
   - Run `git diff --name-only` to see modified files
   - Check if PR already exists: `gh pr view`
   - Identify file types and what reviews apply

4. **Determine Applicable Reviews**

   Based on changes:
   - **Always applicable**: code-reviewer (general quality)
   - **If test files changed**: pr-test-analyzer
   - **If comments/docs added**: comment-analyzer
   - **If error handling changed**: silent-failure-hunter
   - **If types added/modified**: type-design-analyzer
   - **After passing review**: code-simplifier (polish and refine)

5. **Launch Review Agents**

   **Default: Sequential dispatch** (fix findings between reviewers):
   - Run Reviewer/Persona 1 → address all P0/P1 findings
   - Run Reviewer/Persona 2 → address all P0/P1 findings
   - Run final simplifier pass
   - This prevents Reviewer 2 from flagging issues that Reviewer 1's fixes would have resolved

   **Parallel dispatch** (only when explicitly requested or skills are independent):
   - Launch all agents simultaneously
   - Appropriate when review skills examine non-overlapping concerns
   - User must request with: `/pr-review-pr all parallel`

6. **Aggregate Results**

   After agents complete, summarize:
   - **Critical Issues** (must fix before merge)
   - **Important Issues** (should fix)
   - **Suggestions** (nice to have)
   - **Positive Observations** (what's good)

7. **Provide Action Plan**

   Organize findings:
   ```markdown
   # PR Review Summary

   ## Critical Issues (X found)
   - [agent-name]: Issue description [file:line]

   ## Important Issues (X found)
   - [agent-name]: Issue description [file:line]

   ## Suggestions (X found)
   - [agent-name]: Suggestion [file:line]

   ## Strengths
   - What's well-done in this PR

   ## Recommended Action
   1. Fix critical issues first
   2. Address important issues
   3. Consider suggestions
   4. Re-run review after fixes
   ```

## Review Routing

When no specific aspects are requested, auto-select based on change signals:

| Signal | Persona / Skills |
|--------|-----------------|
| New types, interfaces, abstractions | Architecture Reviewer |
| `*.tsx`, `*.css`, `components/` | Domain Specialist + code-reviewer |
| `*test*`, `*spec*` | Domain Specialist + test-analyzer |
| `catch`, `try`, `error`, `fallback` in diff | Architecture Reviewer (silent-failure-hunter) |
| 10+ files changed | pr-briefing first, then parallel personas |
| Schema changes, migrations | Architecture Reviewer |
| Utility/helper additions | Ambition Backstop |
| Default (no strong signals) | Domain Specialist |

### Routing Logic

1. Run `git diff --name-only` and `git diff --stat`
2. Scan diff content for signal keywords
3. Match against routing table (multiple matches = multiple personas)
4. If 10+ files: generate pr-briefing first, then dispatch personas in parallel
5. Otherwise: dispatch matched personas sequentially (fix findings from P1 before P2)
6. Manual override always available: user can specify exact aspects or personas

### Routing Examples

```
# Auto-routed: PR adds a new service class + types
# -> Architecture Reviewer (new abstractions) + Domain Specialist (code quality)

# Auto-routed: PR modifies 3 test files only
# -> Domain Specialist (test-analyzer focus)

# Auto-routed: PR adds 2 utility functions
# -> Ambition Backstop (are these utilities necessary?)

# Auto-routed: PR touches 15 files across backend and frontend
# -> pr-briefing first, then Architecture + Domain + Ambition in parallel
```

## Usage Examples:

**Full review (default, auto-routed):**
```
/pr-review-pr
# Auto-selects personas based on change signals
```

**Specific aspects:**
```
/pr-review-pr tests errors
# Reviews only test coverage and error handling

/pr-review-pr comments
# Reviews only code comments

/pr-review-pr simplify
# Simplifies code after passing review
```

**Named personas:**
```
/pr-review-pr architecture
# Runs Architecture Reviewer persona (garry-review + types + errors)

/pr-review-pr domain
# Runs Domain Specialist persona (code + tests + comments)

/pr-review-pr ambition
# Runs Ambition Backstop persona (simplifier + scope check)

/pr-review-pr architecture domain
# Runs both personas sequentially
```

**Parallel review:**
```
/pr-review-pr all parallel
# Launches all agents in parallel
```

## Agent Descriptions:

**comment-analyzer**:
- Verifies comment accuracy vs code
- Identifies comment rot
- Checks documentation completeness

**pr-test-analyzer**:
- Reviews behavioral test coverage
- Identifies critical gaps
- Evaluates test quality

**silent-failure-hunter**:
- Finds silent failures
- Reviews catch blocks
- Checks error logging

**type-design-analyzer**:
- Analyzes type encapsulation
- Reviews invariant expression
- Rates type design quality

**code-reviewer**:
- Checks CLAUDE.md compliance
- Detects bugs and issues
- Reviews general code quality

**code-simplifier**:
- Simplifies complex code
- Improves clarity and readability
- Applies project standards
- Preserves functionality

## Tips:

- **Run early**: Before creating PR, not after
- **Focus on changes**: Agents analyze git diff by default
- **Address critical first**: Fix high-priority issues before lower priority
- **Re-run after fixes**: Verify issues are resolved
- **Use specific reviews**: Target specific aspects when you know the concern

## Workflow Integration:

**Before committing:**
```
1. Write code
2. Run: /pr-review-pr code errors
3. Fix any critical issues
4. Commit
```

**Before creating PR:**
```
1. Stage all changes
2. Run: /pr-review-pr all
3. Address all critical and important issues
4. Run specific reviews again to verify
5. Create PR
```

**After PR feedback:**
```
1. Make requested changes
2. Run targeted reviews based on feedback
3. Verify issues are resolved
4. Push updates
```

## Notes:

- Agents run autonomously and return detailed reports
- Each agent focuses on its specialty for deep analysis
- Results are actionable with specific file:line references
- Agents use appropriate models for their complexity
- All agents available in `/agents` list
