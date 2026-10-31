---
name: skill-lifecycle
description: >-
  Lifecycle discipline for Claude Code skills: before creating a new skill,
  first decide whether to sharpen / split / merge / rename / demote / archive an
  existing one; and how to archive safely (MOVE to skills-archive/, update
  routing in the SAME change — the skill listing regenerates from SKILL.md
  frontmatter, so it is not hand-edited — grep every caller including
  cross-repo). Fire when asked to create a skill, when you notice two skills
  overlap, when a skill is stale/unused/broken, or when auditing the skill set
  for cruft. Encodes this harness's classification rubric and trigger-quality
  checklist. NOT for authoring the BODY of a specific skill's procedure (write
  it directly), NOT for hooks (hook-authoring), NOT for editing
  settings.json (update-config), NOT for reviewing code you just wrote
  (garry-review), and NOT for mapping a product repo's architecture
  (codebase-mapping). This skill governs whether a skill should exist
  and how it enters/leaves the set.
allowed-tools:
  - Bash
  - Read
  - Write
  - Edit
  - Grep
  - Glob
---
<!--
Intended final target: /Users/yklin/.claude/skills/skill-lifecycle/SKILL.md
Draft source: /Users/yklin/.claude/docs/plans/fable-skills/drafts/skills/skill-lifecycle/SKILL.md
Draft status: candidate (planning artifact, not installed). Verify volatile
claims (skill counts, archive convention path, cross-repo caller filenames)
against the live repo before install — see §10.
-->

# skill-lifecycle: fewer, sharper, routed skills — no cruft

## 1. Purpose

Encode how skills are born, sharpened, and retired so the set stays small,
high-signal, and every skill is either routed or deliberately unrouted. Skill
cruft is a recurring failure: 5 `pr-*` sub-analyzer skills sat as stale
near-duplicates of plugin agents for 3+ months, polluting the listing budget
(`docs/plans/fable-skills/evidence/skill_cleanup_analysis.md` §4). Listing
budget is finite (`SLASH_COMMAND_TOOL_CHAR_BUDGET`, recorded 16000 — confirm
current value), so every dead skill starves a live one.

## 2. When to use

- The user (or a plan) asks to "create/add a skill for X".
- You notice two skills answer the same request, or a false-fire pair.
- A skill looks stale, unused, broken, or oversized.
- You are auditing the skill set for consolidation/cleanup.

## 3. When not to use

- Writing the actual step-by-step procedure inside one skill — just write it.
- Authoring or wiring a hook — `hook-authoring`.
- settings.json / plugin enable-disable mechanics — `update-config`.
- Deciding routing between EXISTING skills for a live request — that is
  `rules/skill-routing.md` at dispatch time, not lifecycle.

## 4. Inputs required

- The capability the candidate skill would cover, in one sentence.
- The current skill set + routing table (`rules/skill-routing.md`) and the
  cleanup analysis (`skill_cleanup_analysis.md`) for the classification rubric.
- Usage evidence for the affected skills, WITH its window.
- For archive/rename: the full caller set (grep, including cross-repo).

## 5. Procedure

### 5a. Create only after checking the six alternatives (decision rule)

Prefer sharpening/merging existing assets over creating new ones. Before
drafting a new skill, classify the need against existing skills using the
rubric from `skill_cleanup_analysis.md`:

| Verdict | When | Action |
|---|---|---|
| **sharpen** | an existing skill nearly covers it but mis-fires or is vague | rewrite its description/trigger + When-to/When-NOT-to |
| **split** | one skill does two jobs users request separately | extract the second job into its own skill + routing rows |
| **merge** | two skills do the same job via different fan-out | fold one into the other as a `--mode`; route both phrasings to the survivor |
| **rename** | dir name ≠ frontmatter name, or name misleads routing | reconcile dir + frontmatter + every referrer atomically |
| **demote** | pure auxiliary of another skill, never independently routed | move into the parent as `reference-*.md`/scripts |
| **archive** | unused in-window AND/OR broken AND/OR duplicate of a plugin | §5c archive procedure |
| **owner-confirm** | any archive / merge / demote / rename of a skill with usage evidence or a routing row, OR any action that touches `protected-files.md`-listed assets | §5e — STOP and get explicit user approval before proceeding |
| **create new** | genuine capability no existing skill/rule/doc covers | §5b trigger-quality checklist |

A capability may be better served by a rule or doc than a skill — if it is
always-on doctrine, it belongs in a rules/ or docs/plans/harness/ file, not a
skill (see maintenance-protocol layering).

### 5b. Trigger-quality checklist (any create/sharpen)

A skill that cannot auto-fire is dead weight (eng-stories had NO frontmatter and
could not fire despite heavy usage — `skill_cleanup_analysis.md` §2). Require:
- [ ] YAML frontmatter present with `name` matching the directory;
- [ ] trigger-rich `description`: names the exact request phrasings that fire it;
- [ ] explicit **When to use** and **When NOT to use** with the sibling it is
      most confused with;
- [ ] a row in `rules/skill-routing.md` (Intent | Skill | NOT);
- [ ] no false-fire pair — if another skill's triggers overlap, disambiguate in
      BOTH descriptions (the "review my code" 5-way collision is the warning);
- [ ] size discipline: `SKILL.md` ≤ ~450 lines (aim <300 for new skills);
      overflow goes to `reference.md` / `templates/` via progressive disclosure.

### 5c. Archive procedure (never delete)

Archive = MOVE, never `rm`. In ONE change:
1. `mv skills/<name> skills-archive/<name>-<YYYYMMDD>/` (the existing
   convention — confirm `skills-archive/` still exists and matches this naming).
2. Grep every caller BEFORE the move: `rules/skill-routing.md`, the CLAUDE.md
   skill listing, other skills that chain it, and **cross-repo callers** —
   notably the hermes factory (`gauntlet.py` invokes global skills BY NAME with
   no interface contract; a rename/archive can break it —
   `docs/plans/fable-skills/evidence/gap_analysis.md` HG-3 / F7). Also grep
   `pm_os` and any `factory`/`fleet` code.
3. Update `rules/skill-routing.md` in the SAME change so the table never
   references a skill that no longer routes. (The skill listing itself is
   system-generated from each `skills/*/SKILL.md` frontmatter — moving the dir
   out of `skills/` de-lists it automatically; it is NOT a block in CLAUDE.md.)
4. Re-point anything that called the archived skill (e.g. rewire to the plugin
   agent that supersedes it).
5. Verify: `ls skills-archive/`, routing-table grep clean, and a fresh-session
   skill-listing check that the skill disappeared as intended.

Rollback is `mv skills-archive/<name>-<date> skills/<name>` + revert the routing
edits — which is why MOVE (not delete) is mandatory.

### 5d. Usage-evidence rules (state the window)

"Unused" is only valid with its retention window stated, reconciled against a
purge-immune source (journal, episodic archive) — transcripts purge on
`cleanupPeriodDays`. "Unused" may mean "seasonal"; archives are reversible by
design for exactly this reason. See `evidence-backed-status` §5f and
judgment-rubrics §6.

### 5e. Owner-gate triggers (when to classify owner-confirm)

Classify a lifecycle action as `owner-confirm` and STOP for approval when ANY of:

- **Archive with usage evidence** — skill has in-window invocations OR a routing
  row; reversibility does not substitute for approval.
- **Merge where loser is actively routed** — folding a skill into another loses
  the original trigger phrasing for active users.
- **Demote with in-window usage** — independently routed skill loses auto-fire;
  treat as archive for owner-gate purposes.
- **Rename of a routed skill** — breaks cross-repo callers (e.g. hermes factory
  calls skills by name — gap_analysis HG-3 / F7); atomic update required.
- **Action touching protected-files.md assets** — any ripple into `rules/`,
  `CLAUDE.md`, or `skills-archive/` naming that affects routing or listings.

When owner-confirm fires: state the action, evidence window, and risk; then STOP.
Do not proceed until the user explicitly approves.

## 6. Evidence required

- the six-way classification verdict with its rationale;
- for create/sharpen: the trigger-quality checklist all ticked;
- for archive: the pre-move caller grep (incl. cross-repo) shown clean or
  rewired, the `mv` result, the routing+listing edit in the same change, and the
  post-change listing check;
- any usage claim carrying its window.

## 7. Output artifact

Either (a) a new/sharpened `SKILL.md` + its routing row, or (b) an
archive/merge change: the move, the atomic routing+listing update, the caller
rewires, and a status block (`evidence-backed-status`) proving the skill left
the set cleanly with rollback noted.

## 8. Common traps (bad behavior this prevents)

- **Stale near-duplicates accumulate.** 5 `pr-*` sub-analyzer skills duplicated
  plugin agents for 3+ months, unrouted and unused, eating listing budget
  (`skill_cleanup_analysis.md` §4). Classify against plugins before creating a
  local fork.
- **A skill that can't fire.** eng-stories had no frontmatter → could not
  auto-fire despite 190 events/72 sessions (window-stated). Trigger-quality
  checklist catches this.
- **Archive breaks a cross-repo caller.** hermes factory calls global skills by
  name with no contract — a blind archive/rename breaks the gauntlet
  (gap_analysis HG-3). Grep cross-repo callers before moving.
- **Routing/listing drift.** Archiving a skill without updating
  skill-routing.md leaves the table pointing at a ghost. Same-change update is
  mandatory.
- **Windowless "unused → delete".** Reversed once when full history showed 383
  events for a "dead" skill (judgment-rubrics §6). State the window; MOVE, don't
  delete.

## 9. Related skills

- `rules/skill-routing.md` — the routing table this skill keeps in sync.
- `evidence-backed-status` — usage-window and existence-probe discipline.
- `hook-authoring` — sibling for the hook side of harness assets.
- `docs/plans/harness/maintenance-protocol.md` — authority for harness changes
  and the global-vs-rules-vs-skill layering decision.
- `docs/plans/fable-skills/evidence/skill_cleanup_analysis.md` — the full
  worked classification of the current set (keep/fix/merge/archive).

## 10. Provenance and maintenance

- Sources: `docs/plans/fable-skills/evidence/skill_cleanup_analysis.md`,
  `skill_inventory.md`, `gap_analysis.md` (area 3, HG-3/F7),
  `rules/skill-routing.md`, `rules/protected-files.md` (archive-as-move
  convention).
- Volatile facts (skill counts 46→39, listing budget 16000, which callers exist
  cross-repo, `skills-archive/` naming) are snapshots. Re-grep and re-count
  before acting — the set changes with every cleanup wave.
- Maintenance: after any archive/merge wave, update the counts here and in
  skill_cleanup_analysis.md; changes to this skill follow maintenance-protocol.
