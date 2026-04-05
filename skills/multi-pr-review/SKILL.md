---
name: multi-pr-review
description: "Multi-PR review pipeline with 3-agent debate per dimension, Opus consolidation, synthesis, independent audit, and final output"
argument-hint: "[PR numbers...] [--baseline N] [--prd path/]"
allowed-tools: ["Agent", "Bash", "Glob", "Grep", "Read", "Write", "Edit", "Skill", "TaskCreate", "TaskUpdate", "TaskList"]
---

# Multi-PR Review Pipeline

Orchestrate a multi-phase PR review pipeline: parallel debate across 6 dimensions,
consolidation, cross-PR synthesis, independent audit, and final output. Designed
for comparing multiple PRs that solve the same problem or reviewing a set of
related PRs against each other.

**Arguments:** "$ARGUMENTS"

---

## Step 0: Argument Parsing and Validation

Parse the arguments string into structured inputs:

1. **PR numbers:** All bare integers are PR numbers. Must have at least 1.
   Example: `42 43 44` -> PRs [42, 43, 44]

2. **--baseline N:** Optional. A PR number to use as the comparison baseline.
   When set, synthesis agents compare each PR against this baseline's diff.
   The baseline PR goes through the full pipeline like any other PR.

3. **--prd path/:** Optional. Path to a PRD directory or file.
   When set, synthesis agents perform PRD gap analysis (which requirements
   are covered, which are missing, with line-number citations).

**Validate every PR number exists before proceeding:**

```bash
gh pr view {N} --json number,title,state
```

If any PR does not exist or is not open, STOP and report which PRs failed validation.
Collect each PR's title for use in output headers.

**Set up working directory:**

```bash
mkdir -p docs/.pr-review-temp
```

If `docs/.pr-review-temp/` already contains files, ask the user:
```
docs/.pr-review-temp/ exists with files from a prior run.
A) Overwrite (delete and recreate)
B) Abort
```

Create per-PR subdirectories:

```bash
for N in {pr_numbers}; do
  mkdir -p docs/.pr-review-temp/pr-${N}/debate
done
```

---

## Step 1a: Parallel Debate (3 x N x 6 Sonnet agents)

**Goal:** For each PR, 3 independent Sonnet agents review each of 6 dimensions.
Total agents: 18 * N. All launch in a SINGLE message for maximum parallelism.

**Dimensions and their corresponding review skills:**

| Dimension | Skill to Invoke |
|-----------|----------------|
| comments  | `pr-comment-analyzer` |
| tests     | `pr-test-analyzer` |
| errors    | `pr-silent-failure-hunter` |
| types     | `pr-type-design-analyzer` |
| code      | `pr-code-reviewer` |
| simplify  | `pr-code-simplifier` |

**For each PR, for each dimension, for each agent (1, 2, 3):**

Spawn the agent with these instructions:

   - **Model:** sonnet
   - **Instructions:** The agent MUST perform these steps in order:
     1. Fetch the PR diff: `gh pr diff {number}`
     2. Invoke the dimension's review skill via the Skill tool:
        `Skill(skill: "{skill_name}")` where `{skill_name}` is the skill
        from the mapping table above (e.g., `pr-comment-analyzer` for the
        `comments` dimension)
     3. Write the skill's findings to
        `docs/.pr-review-temp/pr-{number}/debate/dim-{dimension}-agent-{agent_number}.md`
        using the Write tool
   - **Key rule:** Each agent works independently. No reading other agents' output.
   - **Key rule 2: Confidence calibration.** Every finding must include a confidence score (1-10).
     Findings scored <5 go to a "Low-Confidence Appendix" — not inline. Consolidation agents
     should bump +2 when 2+ debate agents independently flag the same issue. Single-reviewer
     findings already get `[single-reviewer finding]` tag — also mark them confidence -1.

**Launch ALL 18*N agents in ONE message using the Agent tool.**

**After all agents complete**, verify all output files exist:

```bash
for N in {pr_numbers}; do
  for dim in comments tests errors types code simplify; do
    for a in 1 2 3; do
      test -f docs/.pr-review-temp/pr-${N}/debate/dim-${dim}-agent-${a}.md || echo "MISSING: pr-${N}/debate/dim-${dim}-agent-${a}.md"
    done
  done
done
```

If any file is missing, retry that specific agent ONCE. If still missing after retry,
note the gap and proceed (the consolidation agent handles missing inputs gracefully).

**Do NOT proceed to Phase 1b until ALL agents have completed.**

---

## Step 1b: Consolidation (N x 6 Opus agents)

**Goal:** For each PR + dimension, one Opus agent reads the 3 debate files and
produces a single consolidated finding document.

**For each PR, for each dimension:**

1. Read the prompt template:
   `~/.claude/skills/multi-pr-review/templates/consolidate-prompt.md`

2. Fill template placeholders:
   - `{number}` — PR number
   - `{pr_title}` — PR title
   - `{dimension}` — dimension name
   - `{debate_file_1}` — path to agent-1 debate file
   - `{debate_file_2}` — path to agent-2 debate file
   - `{debate_file_3}` — path to agent-3 debate file
   - `{output_path}` — `docs/.pr-review-temp/pr-{number}/dim-{dimension}.md`

3. Spawn the agent:
   - **Model:** opus
   - **Instructions:** The filled template. The agent MUST:
     a. Read all 3 debate files from disk
     b. De-duplicate shared claims across agents
     c. Preserve ALL unique findings (even single-reviewer ones)
     d. Apply most-conservative severity when agents disagree on severity
     e. Mark single-reviewer findings with `[single-reviewer finding]`
     f. Assign confidence scores (1-10) to each consolidated finding:
        - Flagged by all 3 agents: confidence 9-10
        - Flagged by 2 agents: confidence 7-8
        - Flagged by 1 agent: confidence 5-6 (mark as `[single-reviewer finding]`)
        - Contradicted by another agent: confidence 3-4 (suppress to appendix)
     g. Write consolidated output to `{output_path}` using the Write tool

**Launch ALL 6*N agents in ONE message.**

**After all agents complete**, verify output files and clean up:

```bash
# Verify consolidated files exist
for N in {pr_numbers}; do
  for dim in comments tests errors types code simplify; do
    test -f docs/.pr-review-temp/pr-${N}/dim-${dim}.md || echo "MISSING: pr-${N}/dim-${dim}.md"
  done
done

# Delete debate subdirectories (no longer needed)
for N in {pr_numbers}; do
  rm -rf docs/.pr-review-temp/pr-${N}/debate
done
```

**Result:** Exactly 6 consolidated dimension files per PR.

**Do NOT proceed to Phase 2 until ALL consolidation agents have completed.**

---

## Step 2: Synthesis (N Opus agents)

**Goal:** For each PR, one Opus agent reads ONLY its own 6 consolidated dimension
files, verifies findings against the actual diff, and optionally analyzes PRD
coverage. Cross-PR comparison is deferred to the Audit phase.

**For each PR:**

1. Read the prompt template:
   `~/.claude/skills/multi-pr-review/templates/synthesis-prompt.md`

2. Fill template placeholders:
   - `{number}` — this PR's number
   - `{pr_title}` — this PR's title
   - `{own_dimension_files}` — paths to this PR's 6 dim-*.md files
   - `{has_baseline}` — true/false
   - `{baseline_number}` — baseline PR number (if applicable)
   - `{has_prd}` — true/false
   - `{prd_path}` — PRD path (if applicable)
   - `{output_path}` — `docs/.pr-review-temp/pr-{number}/synthesis.md`

3. Spawn the agent:
   - **Model:** opus
   - **Instructions:** The filled template. The agent MUST:
     a. Read ONLY its own 6 consolidated dimension files (do NOT read other PRs' files)
     b. Fetch the actual PR diff: `gh pr diff {number}`
     c. Verify every finding against the real diff (drop phantom findings)
     d. If `{has_baseline}` is true: also `gh pr diff {baseline_number}` and
        compare approaches, tradeoffs, missed edge cases
     e. If `{has_prd}` is true: read PRD files and perform gap analysis —
        for each requirement, cite PR diff line numbers showing coverage
        or note "NOT COVERED"
     f. Write synthesis to `{output_path}` using the Write tool

**Launch ALL N agents in ONE message.**

**After all agents complete**, verify:

```bash
for N in {pr_numbers}; do
  test -f docs/.pr-review-temp/pr-${N}/synthesis.md || echo "MISSING: pr-${N}/synthesis.md"
done
```

**Do NOT proceed to Phase 3 until ALL synthesis agents have completed.**

---

## Step 3: Audit (1 Opus agent)

**Goal:** A single independent Opus agent audits all synthesis outputs for
quality, catching softened findings, dropped findings, inflated scores,
and cross-PR contradictions.

1. Read the prompt template:
   `~/.claude/skills/multi-pr-review/templates/audit-prompt.md`

2. Fill template placeholders:
   - `{all_pr_numbers}` — space-separated list of all PR numbers
   - `{synthesis_files}` — paths to all pr-{N}/synthesis.md files
   - `{dimension_files}` — paths to ALL pr-{N}/dim-*.md files (raw evidence)
   - `{output_path}` — `docs/.pr-review-temp/audit-report.md`

3. Spawn the agent:
   - **Model:** opus
   - **Instructions:** The filled template. The agent MUST:
     a. Read ALL synthesis files
     b. Read ALL consolidated dimension files (the raw evidence)
     c. Spot-check findings against actual PR diffs using `gh pr diff {N}`
        for at least 3 PRs (or all PRs if N <= 3)
     d. Check for: findings present in dimension files but missing from synthesis
        (dropped findings), severity downgraded without justification (softened
        findings), scores that seem inconsistent with finding severity (inflated
        scores), contradictions between different PR synthesis files
     e. Write audit report to `{output_path}` using the Write tool

**Wait for the audit agent to complete before proceeding.**

---

## Step 4: Final Output (1 Opus agent)

**Goal:** Produce the final review documents, incorporating audit corrections.

1. Read the prompt template:
   `~/.claude/skills/multi-pr-review/templates/final-prompt.md`

2. Fill template placeholders:
   - `{all_pr_numbers}` — space-separated list of all PR numbers
   - `{synthesis_files}` — paths to all synthesis files
   - `{audit_report}` — path to audit-report.md
   - `{has_baseline}` — true/false
   - `{baseline_number}` — baseline PR number (if applicable)
   - `{has_prd}` — true/false
   - `{output_dir}` — `docs/pr-reviews`

3. Spawn the agent:
   - **Model:** opus
   - **Instructions:** The filled template. The agent MUST:
     a. Read all synthesis files and the audit report
     b. For each finding where the audit disagrees with synthesis: use the
        audit's correction (audit overrides synthesis)
     c. Write one final review file per PR:
        `docs/pr-reviews/pr-review-{number}-final.md`
     d. Each file includes: executive summary, per-dimension findings with
        severity and file:line references, cross-PR comparison notes (if
        multiple PRs), PRD coverage table (if --prd), verdict
        (APPROVE / REQUEST_CHANGES / NEEDS_DISCUSSION)

```bash
mkdir -p docs/pr-reviews
```

**Wait for the final output agent to complete.**

---

## Step 5: Git Commit

Commit the final review files (NOT the temp files):

```bash
git add docs/pr-reviews/pr-review-*-final.md
git commit -m "docs: multi-PR review for PRs {comma_separated_list}"
```

**Do NOT delete temp files until the commit succeeds.**

---

## Step 6: Cleanup

Remove all temporary working files:

```bash
rm -rf docs/.pr-review-temp
```

---

## Step 7: Notify

Print a summary table to the user:

```
## Multi-PR Review Complete

| PR | Title | Verdict | Critical | Important | Suggestions |
|----|-------|---------|----------|-----------|-------------|
| #{N} | {title} | {verdict} | {count} | {count} | {count} |
| ... | ... | ... | ... | ... | ... |

Final reviews written to:
- docs/pr-reviews/pr-review-{N}-final.md
- ...

Audit report incorporated: {X} corrections applied.
```

If --baseline was used, add a comparison summary row.
If --prd was used, add a PRD coverage percentage.

---

## Key Rules

1. **Phase boundaries are hard stops.** Never start Phase N+1 until every agent
   in Phase N has completed and all output files are verified on disk.

2. **Maximum parallelism within phases.** Launch ALL agents in each phase in a
   SINGLE message. Use `run_in_background: true` where applicable.

3. **Temp file lifecycle.** Create `docs/.pr-review-temp/` at start. Never
   delete any temp file before the git commit in Step 5 succeeds. Delete
   everything in Step 6 after commit.

4. **Retry policy.** If any agent fails, retry it ONCE. If it still fails,
   skip it and note the gap in the final output under a "## Pipeline Gaps"
   section listing which PR + dimension is missing coverage.

5. **No context pollution.** The orchestrating agent (you) should NOT read
   the full content of dimension or debate files. You read only file paths
   and existence checks. Subagents read from disk and write to disk.

6. **Audit overrides synthesis.** When the audit report contradicts a synthesis
   finding (severity, presence, score), the audit's judgment wins in the
   final output.

## Model Assignments

| Phase | Agents | Model | Count |
|-------|--------|-------|-------|
| 1a Debate | Per-dimension reviewers | sonnet | 3 x N x 6 = 18N |
| 1b Consolidation | Dimension consolidators | opus | N x 6 = 6N |
| 2 Synthesis | Per-PR synthesizers | opus | N |
| 3 Audit | Independent auditor | opus | 1 |
| 4 Final Output | Final writer | opus | 1 |
| **Total** | | | **25N + 2** |
