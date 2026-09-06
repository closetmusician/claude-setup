---
name: harness-orientation
description: >-
  Five-minute orientation for a fresh session working in the ~/.claude harness
  itself: the CLAUDE.md context chain and on-demand rules, where operating
  doctrine lives, the safety stack, memory stores and routing, what runs
  automatically (hooks + schedules + launchd), and how to check live state with
  probe commands. Fire at the start of any session that will modify the harness
  (skills, hooks, settings, rules, doctrine, schedules) or when you are unsure
  where something lives or whether it is on. NOT a substitute for the doctrine
  files it points to (read those on their triggers) and NOT for orienting in a
  product/app repo (use codebase-mapping). This skill is a map with probes, not
  a source of truth — verify volatile facts live.
allowed-tools:
  - Bash
  - Read
  - Grep
  - Glob
---
<!--
Intended final target: $HOME/.claude/skills/harness-orientation/SKILL.md
Draft source: $HOME/.claude/docs/plans/fable-skills/drafts/skills/harness-orientation/SKILL.md
Draft status: candidate (planning artifact, not installed). Every structural
count and live-state fact below is a snapshot — verify with the listed probe
commands before trusting it. See §10.
-->

# harness-orientation: a 5-minute map of ~/.claude, with probes

## 1. Purpose

Give a fresh session — any model tier — a fast, trustworthy map of the
`~/.claude` harness so it can act without re-discovering the structure from
scratch or trusting stale records. This skill is a signpost to the real
doctrine files plus the exact probe commands to confirm live state; it
deliberately does NOT restate doctrine (that would drift). Trust `git status`
and the probes over any snapshot, including this one — the system even
mis-reports `~/.claude` as "not a git repo" (§8).

## 2. When to use

- Session start when the task will touch harness internals (skills, hooks,
  settings.json, rules/, docs/plans/harness/, schedules, launchd plists).
- You need to know where a rule/doctrine/memory fact lives, or whether a
  component is on.
- Before a cleanup/audit/maintenance wave in `~/.claude`.

## 3. When not to use

- Orienting in a product or app codebase — use `codebase-mapping`.
- Executing a specific harness change — read the specific doctrine file this map
  points to (dispatch-protocol, maintenance-protocol, etc.) and follow it.
- When a prompt points you at a specific plan/doc — that doc is sole context;
  don't run a full orientation.

## 4. Inputs required

- Shell access to `~/.claude` (the probes below).
- Nothing else — this skill bootstraps its own context.

## 5. Procedure — the five-minute pass

### 5a. Context chain (what's always loaded)

`CLAUDE.md` + three @-includes: `rules/code-style.md`, `rules/personal.md`,
`RTK.md` (recorded ~115 lines total — confirm with `wc -l`). Plus SIX
read-on-demand rules and their triggers (from the CLAUDE.md table):

| Rule | Trigger |
|---|---|
| `rules/vibe-protocol.md` | repo has `.claude/phase.json` |
| `rules/tool-registry.md` | Office/SharePoint/GitHub ops / file I/O |
| `rules/memory-routing.md` | memory store decisions |
| `rules/session-handoff.md` | session start (auto-pickup) |
| `rules/skill-routing.md` | skill dispatch decisions |
| `rules/protected-files.md` | before editing protected files |

Probe: `ls rules/` and read `CLAUDE.md` top-of-file table.

### 5b. Where doctrine lives (four operating files)

`docs/plans/harness/` holds the read-on-demand operating doctrine (all
protected — see §5c):
- `dispatch-protocol.md` — delegation/subagent rules (read before any multi-agent
  work; `dispatch-templates.md` for the prompt).
- `judgment-rubrics.md` — done / escalate / stop / pivot / trust rubrics.
- `maintenance-protocol.md` — authority to change the harness itself.
- `lessons-learned.md` — append-only lessons log (never truncate).

Do NOT duplicate their content; reference by path and read on the trigger.

### 5c. Safety stack

- `~/.claude/scripts/git-safety-hook.sh` — PreToolUse/Bash: blocks `git add -A`, rm of
  protected files, dangerous git.
- Secret-scan pre-commit via `core.hooksPath=.githooks`
  (`.githooks/pre-commit.d/10-secret-scan.sh`) — installed after the 2026-07-03
  secret-leak incident. **Probe it's active:** `git config core.hooksPath`
  (must print `.githooks`, else the gate does nothing).
- `~/.claude/scripts/autonomous-push-guard.sh` — blocks push outside sanctioned
  solo-owned repos; "push" in `~/.claude` targets closetmusician ONLY
  (`MEMORY.md` feedback_push_target_closetmusician).
- `rules/protected-files.md` — 11 named files that must not be deleted/emptied
  (CLAUDE.md, the four operating files, code-style, tool-registry, etc.).

### 5d. Memory stores + routing (`rules/memory-routing.md`)

| Store | Read via | Rule |
|---|---|---|
| journal (`memory/journal.md`) | `harness recall "<q>"` | NEVER load whole; raw, not citable |
| lessons (`memory/lessons.md`) | read directly (≤200L) | curated patterns |
| project memory (`projects/.../memory/MEMORY.md`) | read directly | persists across sessions |
| handoffs (`handoffs/<slug>.md`) | auto-loaded at start if <48h old | session continuity |
| gbrain | `gbrain query` (binary has been MISSING — verify) | work docs |

### 5e. What runs automatically

- **Hooks:** ~41 wired scripts across 7 events (PreToolUse/PostToolUse/Stop/
  UserPromptSubmit/SessionStart/SessionEnd/Notification). Full live map:
  `docs/plans/fable-skills/evidence/harness_inventory.md` §2. Probe:
  `jq '.hooks' settings.json`.
- **schedules.json:** recorded 8 tasks `enabled:true` (pm-morning, pm-jira,
  pm-weekly, synthesis ×2, weekly cleanup/audit, pulse). **Caveat: execution is
  UNVERIFIED — enabled ≠ running**; no execution logs found beyond
  `.last-update-result.json`. Do not assume they fire.
- **launchd:** `com.yklin.*` plists (harness-doctor, journal-index, burnin, and —
  as of last probe — night-runner/nightly-flywheel/morning-brief were LOADED,
  contradicting records that call them "unloaded"). **Probe:**
  `launchctl list | grep yklin` and `ls ~/Library/LaunchAgents/com.yklin.*`.

### 5f. Skills — three ownership classes (edit the right place)

- `~/.claude/skills/<name>/` — user-owned; edit directly.
- pm_os symlinks (the 9 `pm-*`/`yk-*` skills) — edit UPSTREAM in `~/Code/pm_os`,
  not the symlink.
- Plugins (codex, pr-review-toolkit, code-review-graph, episodic-memory, etc.) —
  managed upstream; do not fork locally (see `skill-lifecycle`). Probe:
  `ls -la skills/ | grep '\->'` to spot symlinks; `settings.json enabledPlugins`
  for plugins.

### 5g. How to check live state (truth over snapshots)

```bash
git -C ~/.claude status                 # trust this over system metadata
git -C ~/.claude config core.hooksPath  # .githooks = secret-scan live
launchctl list | grep yklin             # what's actually loaded
```
Report snapshots (`state/burnin/report.md`, briefings) go STALE — re-run the
suites (`bash ~/.claude/scripts/run-harness-evals.sh`) for current truth, don't cite the
snapshot.

## 6. Evidence required

Any live-state claim you make after orienting carries its probe output in the
same turn (per `evidence-backed-status`): "loaded" ← `launchctl list`;
"secret-scan active" ← `git config core.hooksPath`; "suite green" ← a fresh
`run-harness-evals.sh` run, not the stale burn-in report.

## 7. Output artifact

Usually none written — orientation is context-building. If asked for a
state snapshot, emit a status block (`evidence-backed-status` format) with each
line backed by its probe. Optionally refresh
`docs/plans/fable-skills/evidence/harness_inventory.md` rather than creating a
new file.

## 8. Common traps (bad behavior this prevents)

- **Trusting system metadata over git.** Claude Code reports `~/.claude` as "not
  a git repository" — this is WRONG; `git status` works (`MEMORY.md`
  Environment). Always trust `git status`.
- **Citing a stale report as live.** The burn-in report showed 3 RED suites that
  a fresh re-run cleared (52/52) — the report was a stale 07-06 snapshot
  (recent_capability_capture §7 / F2). Re-run, don't cite.
- **Assuming schedules run because enabled.** 8 tasks `enabled:true` with no
  execution evidence (harness_inventory §7). Enabled ≠ running.
- **Editing a symlinked skill in place.** pm_os skills are symlinks; edit
  upstream or the change is lost/misattributed.
- **Records say OFF, reality says loaded.** night-runner/flywheel/morning-brief
  plists were loaded while FINAL-REPORT called them "unloaded" (F1). Probe
  launchctl; never trust the record.

## 9. Related skills

- `skill-lifecycle` — for changing the skill set once oriented.
- `hook-authoring` — for changing hooks.
- `evidence-backed-status` — the reporting discipline every live-state claim
  here must follow.
- `codebase-mapping` — the analogue for product/app repos.
- `docs/plans/harness/maintenance-protocol.md` — authority for any harness
  change; read before modifying.

## 10. Provenance and maintenance

- Sources: `docs/plans/fable-skills/evidence/harness_inventory.md` (context
  chain, hooks, schedules, safety), `recent_capability_capture.md` (§6 open
  questions, F1/F2), `MEMORY.md` (git-repo metadata, push target), the CLAUDE.md
  read-on-demand table, `rules/memory-routing.md`, `rules/protected-files.md`.
- EVERY count and live-state fact here (line counts, ~41 hooks, 8 schedules,
  which plists are loaded, suite pass counts, gbrain binary presence) is a
  point-in-time snapshot from 2026-07-07. Verify with the §5g/§6 probes before
  asserting any of them as current. This skill is a map, not a live sensor.
- Maintenance: refresh the pointers (not the volatile numbers) when the harness
  structure changes; regenerate `harness_inventory.md` for current counts.
  Changes follow `docs/plans/harness/maintenance-protocol.md`.
