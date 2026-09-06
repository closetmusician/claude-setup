# Skill Routing Map

A `SKILL CHECK (hook):` line in your context = the router already matched — invoke that
skill via the Skill tool unless clearly wrong. No hook line, but the table below matches
the user's semantic intent = still invoke it (match intent, not keywords; "why is this
broken?" IS /investigate). Plain git ops (commit/push/merge/rebase) are NOT skill intents.

| Intent | Skill | NOT |
|---|---|---|
| Review a PR diff / "look at/check this PR" | `pr-review-pr` | garry-review, review |
| Several PRs / compare competing PRs | `pr-review-pr` with `--compare` (or once per PR) — `multi-pr-review` is a deprecated stub that routes here | multi-pr-review |
| Post-write code quality ("review what I just wrote") | `garry-review` | pr-review-pr |
| Lightweight post-edit code simplification | `simplify` (`code-simplifier` plugin) | |
| Structural SAFETY review (SQL/LLM/side-effects, explicit ask) | `review` | pr-review-pr (which calls it as its safety aspect) |
| Plan review — engineering | `plan-eng-review` (`eng-review` is a deprecated stub → same) | ceo-review |
| Plan review — CEO/product | `ceo-review`; design → `plan-design-review` | plan-eng-review |
| Plan a feature (arch + tasks) | `eng-planning` | eng-stories |
| PRD → stories decomposition | `eng-stories` | eng-planning |
| Write a PRD | `prd-writer`; review/critique a PRD → `prd-review` | |
| Verify or find bugs in something you/we built ("test this", "does it work?") | `qa` (reports by default; fixes only on explicit ask); report-only-by-contract → `qa-only`; e2e YAML from spec → `e2e-test-writer` | browse, verify |
| Browser navigation, research, scraping, screenshots of external sites | `browse` | qa, qa-only |
| Debug / "why is this broken" | `investigate` | |
| Produce evidence-backed status update / "what is the status of X" / "is this done" | `evidence-backed-status` | |
| Write or debug a hook / "hook not firing" / "hook is silently failing" / author a hook test fixture | `hook-authoring` | |
| Orchestrate multi-agent work / fan-out / execute a plan via subagents | `lead-orchestrator` — mode-split: the skill itself routes to feature (full VIBE pipeline), backlog, investigate-audit, or live-debug; do not pre-select a mode | |
| Ship / create PR (then briefing AFTER creation) | `ship`, then `pr-briefing` | |
| Visual QA live site | `design-review`; variants → `design-shotgun`; HTML → `design-html`; Angular impl → `design-implement` | |
| Jira updates/creation from docs | `jira-update` | pm-jira |
| Confluence page update (comment-safe) | `atlassian-update` | atlassian-connect |
| Map codebase architecture | `codebase-mapping`; session end-bridge → `handoff` | |
| Orient to the harness / "how does the harness work" / "what skills exist" / "map the harness" / starting fresh on ~/.claude | `harness-orientation` | codebase-mapping (which is for project repos, not the harness itself) |
| Audit a skill / archive a skill / evaluate skill overlap / create a new skill / "should this skill be kept" | `skill-lifecycle` | |
| Office/SharePoint doc editing | `o365-doc-edit` (+ rules/tool-registry.md table) | |
| Mine Teams channels for customer feedback / "what are customers complaining about" / "aggregate feedback" / "research the channel" | `teams-channel-research` | deep-research (which is web-only, not Teams) |
| Win/loss analysis / "why we win" / "why we lose" / "competitive loss analysis" / refresh a win-loss deck for a new period | `winloss-analysis` | teams-channel-research, deep-research |
| Post workarounds to CSMs / "reply to the channel" / "send updates back" / "post responses" | `csm-response` (requires a report from `teams-channel-research` or equivalent) | pm-jira, atlassian-update |
| Connect to Tableau / "query Tableau" / "set up Tableau MCP" / Tableau BI data, dashboards, metadata, Pulse | `tableau-connect` | gong-connect (that is Gong, not Tableau) |
| Connect to Salesforce / "query Salesforce" / "set up Salesforce MCP" / CRM data — accounts, opportunities, cases (SOQL) | `salesforce-connect` | tableau-connect (that is Tableau BI, not the CRM) |
| Connect/verify EVERYTHING at once / "connect to everything" / "bring all sources online" / master connect | `connect-all` (invokes glean + gong + tableau + salesforce) | the single-source connect skills (use those to fix one source) |

Tool preference: docs→markdown = `~/Code/.venv/bin/markitdown` (never custom extraction).
GitHub ops = `gh` CLI (see tool-registry).

Hook precedence — `gh pr create`: scripts/skill-routing-guard.sh HARD-denies it (exit 2);
the git-safety-hook message about it is advisory only, so the deny wins. Route through
`/ship` (which owns PR creation), then `pr-briefing`. Append `# SKILL-BYPASS` to the
command only in two cases: (a) the command is issued from inside the /ship or /pr-briefing
flow (that is the sanctioned path — see settings-additions §F2), or (b) the user explicitly
asked for a raw `gh pr create`.

Plugin skills (different providers, don't disambiguate): codex:* (second opinions — user
often says "codex review"/"adversarial review" meaning these), episodic-memory:*
(conversation recall), code-review-graph:* (graph-powered review, needs built graph).

## Semantic long-tail fallback

The table above is authoritative. `scripts/skill-nudge.sh` covers hot intents
deterministically via regex. `state/skill-index.db` (gated by `HARNESS_SKILL_SEMANTIC=1`)
surfaces skills the table doesn't name that the listing budget may have dropped — long-tail
only. Table and regex always win ties. If `HARNESS_SKILL_SEMANTIC` is unset, the semantic
path is disabled and the hook returns immediately on any table result.
