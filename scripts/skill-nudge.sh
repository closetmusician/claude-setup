#!/usr/bin/env bash
# ABOUTME: UserPromptSubmit hook — deterministic skill routing nudge.
# ABOUTME: Replaces the prose "SKILL CHECK" mandate from rules/skill-routing.md, which
# ABOUTME: executed ~0 times across 511 mined sessions (audit-2026-07-02 LEAK#1).
# ABOUTME: Emits at most ONE nudge line as additionalContext; silent when no match.
# ABOUTME: Must NEVER block: always exits 0, no network, pure bash+grep+jq.

set -uo pipefail

INPUT=$(cat 2>/dev/null || true)
PROMPT=$(printf '%s' "$INPUT" | jq -r '.prompt // empty' 2>/dev/null || true)
[ -z "$PROMPT" ] && exit 0
# Skip slash-commands and tiny prompts — user already chose, or nothing to route.
case "$PROMPT" in "/"*) exit 0;; esac
[ ${#PROMPT} -lt 12 ] && exit 0

P=$(printf '%s' "$PROMPT" | tr '[:upper:]' '[:lower:]' | head -c 2000)

nudge() {
  # $1 = skill name, $2 = matched intent label
  printf 'SKILL CHECK (hook): this request matches the intent "%s" — invoke the Skill tool with skill: "%s" now, before doing the work manually. If the match is clearly wrong, proceed normally and ignore this.\n' "$2" "$1"
  exit 0
}

m() { printf '%s' "$P" | grep -qE "$1"; }

# Order = first match wins (mirror of rules/skill-routing.md priority).
m 'orchestrat.* (sub)?agents|fan[- ]?out.*agents|spawn.*agents.*parallel|max.*parallel.*(sub)?agents' \
  && nudge "lead-orchestrator" "multi-agent orchestration/fan-out"
m 'review (this|the|that) pr\b|check (this|the) pr\b|review pr *#?[0-9]|adversarial(ly)? review.*(diff|pr\b)' \
  && nudge "pr-review-pr" "PR diff review"
m 'review.*(these|multiple|all).*prs|review [0-9]+ prs' \
  && nudge "multi-pr-review" "multi-PR review"
m 'review (the |my )?(code|what (i|you) (just )?(wrote|did|built))' \
  && nudge "garry-review" "post-write code quality review"
m 'safety review|structural review|sql.*(safety|injection).*review' \
  && nudge "review" "structural safety review"
m '(break|decompose|split).*(prd|spec).*(stor|ticket)|story breakdown|stories from (the |this )?prd' \
  && nudge "eng-stories" "PRD → stories decomposition"
m '(review|critique|is this .*ready).*(prd|product spec)' \
  && nudge "prd-review" "PRD review"
m '(write|draft|create|help me).*(a |the |this )?(prd|product (spec|brief|requirements))' \
  && nudge "prd-writer" "PRD writing"
m '(tech|technical|engineering|eng) review|review the (plan|architecture|design doc)|lock in the plan' \
  && nudge "plan-eng-review" "engineering plan review"
m 'plan (a|the|this) feature|plan the architecture|architecture.*(plan|planning) for' \
  && nudge "eng-planning" "feature planning"
m '\bqa this|run qa\b|test and fix|find (and fix )?bugs|fix what.?s broken' \
  && nudge "qa" "QA test + fix"
m '(debug|investigate) (this|the|why)|why is .*(broken|failing)|root.?cause' \
  && nudge "investigate" "root-cause debugging"
m 'hand.?off|wrap up (the |this )?session|compress.*session' \
  && nudge "handoff" "session handoff"

exit 0
