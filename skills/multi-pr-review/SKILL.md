---
name: multi-pr-review
description: "SUPERSEDED — do not select this skill for new work. Multi-PR comparison now lives in pr-review-pr's --compare mode (~/.claude/skills/pr-review-pr/SKILL.md). If the user asks to 'review these PRs', 'compare PRs', or 'which PR should we merge', invoke pr-review-pr with --compare instead."
argument-hint: "[use /pr-review-pr <numbers> --compare instead]"
disable-model-invocation: true
---

# Multi-PR Review — Superseded

This pipeline is retired. Use `/pr-review-pr <PR numbers> --compare`
(`~/.claude/skills/pr-review-pr/SKILL.md`).

**Why:** this skill ran end-to-end exactly once in 4 months, at a cost of
~450 agent spawns per 3-PR run (18 debate agents per PR plus consolidation,
synthesis, audit, and final-output tiers). Its two rules worth keeping —
audit-overrides-synthesis and confidence calibration — were merged into
pr-review-pr (Steps 3-4), and its comparison capability became the size-gated
`--compare` mode there (1/2/3 reviewer agents per PR by diff size, capped
findings, plain-English output).

**If invoked anyway:** state that this skill is superseded, then run
`/pr-review-pr` with the same PR numbers and `--compare` (plus `--prd <path>`
if a PRD was given).

The prompt templates under `~/.claude/skills/multi-pr-review/templates/`
remain on disk for reference only (audit-prompt.md was the donor for
pr-review-pr's skeptical verifier).
