# Plan: gstack Integration — Browser QA + Review Improvements

## Context

We studied `~/.claude/docs/plans/gstack-study.md` and compared it against the current `~/.claude` setup. All 32 gstack skills are symlinked and healthy, but several capabilities remain unverified or unintegrated. This plan implements items 1-7 from the gap analysis, scoped by user decisions:

- **$B alias:** Per-skill only (no ~/.zshrc changes)
- **E2E migration:** Skip for now (use /qa for new work, leave YAML tests on Chrome MCP)
- **Review changes:** Add both confidence calibration + Fix-First to garry-review

## Execution Order

### Step 1: Verify browse CLI (Item 1)

Run the 3-command smoke test from the study plan:

```bash
B=~/.claude/skills/gstack/browse/dist/browse
$B goto https://example.com
$B snapshot -i
$B stop
```

**Pass criteria:** `goto` connects, `snapshot` returns accessibility tree with @refs, `stop` exits cleanly.
**If fails:** Run `cd ~/.claude/skills/gstack/browse && ./setup` to rebuild.

### Step 2: Verify design CLI (Item 7)

```bash
D=~/.claude/skills/gstack/design/dist/design
$D generate --brief "Simple blue button on white background" --output /tmp/gstack-design-test.png
```

**Pass criteria:** PNG file generated at `/tmp/gstack-design-test.png`.
**Config already exists:** `~/.gstack/openai.json` has an API key.
**If fails:** Run `$D setup` to reconfigure.

### Step 3: Confirm canary-in-deploy (Item 4)

**No action needed.** Canary logic is already embedded in land-and-deploy Step 7 (lines 743-804). It uses `$B goto`, `$B console --errors`, `$B perf`, `$B text`, `$B snapshot` with depth scaling by diff scope (SCOPE_DOCS/CONFIG/BACKEND/FRONTEND/mixed).

Just document this in MEMORY.md as "already integrated."

### Step 4: Add confidence calibration + Fix-First to garry-review (Items 5+6)

**File:** `~/.claude/skills/garry-review/SKILL.md`

**Changes (additive — inserted between the "For each issue" section and the "Workflow" section):**

#### 4a: Confidence Calibration section

Insert after the "For each issue you find" section (after line 57):

```markdown
### Confidence Calibration

Rate every finding 1-10 before presenting:

| Score | Meaning | Action |
|-------|---------|--------|
| 9-10 | Verified bug or violation | Show — lead with these |
| 7-8 | High confidence | Show normally |
| 5-6 | Moderate confidence | Show with caveat ("likely but verify") |
| 3-4 | Low confidence | Suppress — appendix only |
| 1-2 | Speculation | Suppress unless P0 severity |

**Rules:**
- Never present findings scored <5 inline — collect them in a "Low-Confidence Appendix" at the end
- If 2+ independent signals confirm the same finding, bump +2
- Findings that contradict CLAUDE.md or code-style.md are auto 8+
```

#### 4b: Fix-First Heuristic section

Insert after Confidence Calibration:

```markdown
### Fix-First Heuristic

Classify every finding as AUTO-FIX or ASK before presenting:

**AUTO-FIX** (apply silently, report one-line summary):
- Dead code / unused variables
- Stale or false comments
- Magic numbers → named constants
- N+1 queries (when fix is obvious)
- Version/path mismatches in config
- Inline styles → CSS classes
- O(n×m) lookups → O(n) with Set/Map

**ASK** (present with options as usual):
- Security (auth, XSS, injection, race conditions)
- Design decisions / architectural changes
- Large fixes (>20 lines changed)
- Removing functionality or changing user-visible behavior
- Enum completeness or API contract changes

**Rule of thumb:** If a senior engineer would apply without discussion → AUTO-FIX. If reasonable engineers could disagree → ASK.

**Output format for AUTO-FIX items:**
After completing the review, list auto-fixes as:
`[AUTO-FIXED] [file:line] Problem → what you did`

Then proceed to present ASK items interactively per the existing workflow.
```

#### 4c: Update the "For each issue" section

Modify the existing section to reference the new systems:

```markdown
### For each issue you find

For every specific issue (bug, smell, design concern, or risk):

1. **Rate confidence** (1-10) per Confidence Calibration above. Skip if <5.
2. **Classify** as AUTO-FIX or ASK per Fix-First Heuristic above.
3. If AUTO-FIX: apply the fix and log it as `[AUTO-FIXED] [file:line] Problem → what you did`.
4. If ASK:
   * Describe the problem concretely, with file and line references.
   * Present 2–3 options, including "do nothing" where that's reasonable.
   * For each option, specify: implementation effort, risk, impact on other code, and maintenance burden.
   * Give me your recommended option and why, mapped to my preferences above.
   * Then explicitly ask whether I agree or want to choose a different direction before proceeding.
```

#### 4d: Update the FINAL REVIEW section

Update line 72 to include auto-fix summary:

```markdown
**FINAL REVIEW:**
1. List all `[AUTO-FIXED]` items applied during the review.
2. Aggregate the most important ASK questions/gaps from each stage and output their pros vs cons AND your opinionated recommendation and why. NUMBER issues and then give LETTERS for options then use `AskUserQuestion` to get guidance from the user. Make the recommended option always the 1st option.
3. If there's a Low-Confidence Appendix, mention its existence but don't expand unless asked.
4. Based on what the user says from `AskUserQuestion`, then decide whether you will 1) write the aligned feedback/improvement, 2) log it for later, 3) discard, or something else. Ask the user before finishing.
```

### Step 5: Add confidence calibration to multi-pr-review (Item 5)

**File:** `~/.claude/skills/multi-pr-review/SKILL.md`

**Changes:**

#### 5a: Add Key Rule after line 98

After the "Key rule: Each agent works independently" line, add:

```markdown
   - **Key rule 2: Confidence calibration.** Every finding must include a confidence score (1-10).
     Findings scored <5 go to a "Low-Confidence Appendix" — not inline. Consolidation agents
     should bump +2 when 2+ debate agents independently flag the same issue. Single-reviewer
     findings already get `[single-reviewer finding]` tag — also mark them confidence -1.
```

#### 5b: Update consolidation instructions (around line 144)

Add to the consolidation agent's MUST list:

```markdown
     g. Assign confidence scores (1-10) to each consolidated finding:
        - Flagged by all 3 agents: confidence 9-10
        - Flagged by 2 agents: confidence 7-8
        - Flagged by 1 agent: confidence 5-6 (mark as `[single-reviewer finding]`)
        - Contradicted by another agent: confidence 3-4 (suppress to appendix)
```

### Step 6: Update MEMORY.md

**File:** `~/.claude/memory/MEMORY.md`

Add under "Key Files & Paths":

```markdown
- `~/.claude/skills/gstack/browse/dist/browse` — gstack Playwright CLI (`$B` in skills), 55 commands, 100ms/cmd
- `~/.claude/skills/gstack/design/dist/design` — gstack Design CLI (`$D` in skills), needs ~/.gstack/openai.json
```

Add under "Patterns":

```markdown
- gstack /qa skill uses browse CLI natively — use it for exploratory/regression QA. Keep e2e-qa-runner on Chrome MCP for structured YAML tests.
- Canary is embedded in land-and-deploy Step 7 (not a separate invocation). Depth scales with diff scope.
- garry-review has Fix-First + confidence calibration: AUTO-FIX mechanical issues silently, ASK for judgment calls, suppress <5 confidence.
```

## Verification

1. **Browse CLI:** `$B goto https://example.com && $B snapshot -i && $B stop` succeeds
2. **Design CLI:** PNG generated at `/tmp/gstack-design-test.png`
3. **garry-review:** Invoke `/garry-review` on a small diff and verify:
   - Confidence scores appear on findings
   - Low-confidence items go to appendix
   - Mechanical issues get auto-fixed with `[AUTO-FIXED]` tag
   - ASK items still go through interactive flow
4. **multi-pr-review:** Check that debate agent instructions include confidence scoring

## Files Modified

| File | Change Type |
|------|-------------|
| `~/.claude/skills/garry-review/SKILL.md` | Add confidence calibration + Fix-First sections, update finding/review workflow |
| `~/.claude/skills/multi-pr-review/SKILL.md` | Add confidence scoring to debate + consolidation agents |
| `~/.claude/memory/MEMORY.md` | Document browse CLI, design CLI, patterns |

## Git Plan

Single branch `feat/gstack-integration`, 2 commits:
1. `garry-review: add confidence calibration + Fix-First heuristic`
2. `multi-pr-review: add confidence scoring to debate pipeline`

MEMORY.md update folded into whichever commit touches it last.
