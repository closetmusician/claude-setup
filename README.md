# ~/.claude — A Self-Improving Claude Code Setup

A version-controlled [Claude Code](https://docs.anthropic.com/en/docs/claude-code) configuration that adds engineering guardrails, a large library of reusable skills, and multi-agent orchestration on top of the stock tool. Drop it in as your `~/.claude` directory, or cherry-pick the pieces you like.

> **New to Claude Code?** It's Anthropic's command-line coding agent. Your personal settings, hooks, and skills live in a folder called `~/.claude`. This repo *is* that folder — cleaned up and shared so you can start from a batteries-included setup instead of an empty one.

---

## What you get

- **Git safety guardrails** — a hook blocks dangerous commands (`git add -A`, `push --force`, `--no-verify`, `reset --hard`) and protects critical files from deletion, before they run.
- **A skill library (~50 skills)** — reusable, structured prompts Claude invokes automatically: PR review, debugging, testing/QA, planning, PRD writing, and more. You don't memorize them; Claude picks the right one for the task.
- **Multi-agent orchestration** — the `lead-orchestrator` skill coordinates teams of subagents (coder + independent QA) for larger features.
- **Engineering standards baked in** — TDD-first, YAGNI, clear naming, real (non-mocked) tests. Loaded into every session so Claude follows them by default.
- **Session journaling** — a Stop hook records what happened each session to a local journal, with no LLM calls. Over time you build a searchable history.

---

## Quick start

```bash
# Backs up any existing ~/.claude automatically, then installs this one.
git clone https://github.com/closetmusician/claude-setup.git ~/.claude
~/.claude/install.sh
```

Then set your name so Claude addresses you correctly:

```bash
cp ~/.claude/rules/personal.md.example ~/.claude/rules/personal.md
$EDITOR ~/.claude/rules/personal.md
```

`rules/personal.md` is gitignored — your copy stays local and never conflicts with updates. Now start Claude Code in any project:

```bash
claude
```

**What the installer does** (`install.sh`, safe to re-run):
1. Backs up an existing `~/.claude` to `~/.claude-backup-<timestamp>/`.
2. Replaces `__HOME__` placeholders in `settings.json` with your real home directory, then marks the file `assume-unchanged` so your local paths never show up as a git diff.
3. Creates a `rules/personal.md` stub from the example if you don't have one.
4. On macOS, installs `terminal-notifier` (desktop alerts when a task finishes) if Homebrew is present.
5. Makes scripts executable and installs the repo's pre-commit hook (blocks committing secrets).

**To update later:** `cd ~/.claude && git pull`. Personal files are gitignored, so pulls won't clobber them. Re-run `install.sh` if `settings.json` changed upstream.

---

## Layout

```
~/.claude/
├── CLAUDE.md          # Behavior + engineering rules, loaded every session
├── install.sh         # Installer (backup → clone → substitute paths → stubs)
├── settings.json      # Hooks, permissions, sandbox, plugins (__HOME__ placeholders)
├── rules/             # Standards and routing, split by concern
│   ├── code-style.md          # TDD, naming, docs, debugging
│   ├── vibe-protocol.md       # Multi-agent spec-driven TDD workflow
│   ├── protected-files.md     # Files the safety hook won't let you delete
│   ├── skill-routing.md       # Which skill handles which intent
│   ├── tool-registry.md       # Approved tools for file/Office/GitHub I/O
│   ├── memory-routing.md      # Where different kinds of memory live
│   ├── session-handoff.md     # Cross-session continuity
│   └── personal.md.example    # Template for your local personal.md (gitignored)
├── skills/            # ~50 reusable agent skills (see below)
├── scripts/           # Hooks and automation (git safety, journaling, status line)
├── hooks/ .githooks/  # Git hooks (pre-commit secret scan)
├── bin/harness        # Harness CLI entry point
├── evals/ tests/      # Tests for the config itself
└── plugins/           # Plugin registry config
```

---

## The safety hook

The heart of the guardrails is `scripts/git-safety-hook.sh`, wired as a `PreToolUse` hook on `Bash` in `settings.json`. Before any shell command runs, it blocks:

- `git add -A` / `git add .` — forces you to stage files explicitly.
- `git push --force` — suggests `--force-with-lease` instead.
- `git commit --no-verify` — no skipping hooks.
- `git reset --hard` — prevents silent loss of work.
- Deletion of files listed in `rules/protected-files.md`.

It strips heredocs first so the check can't be obfuscated. Like all hooks here, it fails safe — an error never blocks your work.

---

## Skills — the crown jewels

Skills are structured, reusable prompts in `skills/<name>/SKILL.md`. Each one encodes a repeatable workflow — a review checklist, a debugging protocol, a report pipeline — so Claude follows a proven process instead of improvising. You don't invoke them by hand: `rules/skill-routing.md` maps plain-language intents to skills, and Claude picks the right one when your task matches. You can also read any `SKILL.md` directly to see exactly what it does.

Most skills are short "routers" that pull in heavier `reference/` and `templates/` files on demand — so the prompt Claude loads stays small until the detail is actually needed.

### Recently updated (the sharpest tools)

These got the most work in mid-to-late 2026 and are the most battle-tested:

- **`winloss-analysis`** *(updated Aug 2026)* — Produces executive-grade "Why We Win" / "Why We Lose" reports for a product line, split by region and segment. Leads with the **root cause** behind every number, not the CRM dropdown value; every figure carries a basis label and a citation. The `SKILL.md` is a thin router; the method lives in `reference/` files (evidence mining, root-cause protocol, quality rubric, insight patterns) with a golden HTML template. Distilled from a real analysis session, so the rigor is baked in.
- **`teams-channel-research`** *(updated Jul 2026)* — Mines chat channels for customer feedback, deduplicates it, cross-references against a tracker, verifies each thread, runs an adversarial review, and produces a prioritized complaint report. A full pipeline, not a one-shot prompt.
- **`csm-response`** — Takes a complaint report (from `teams-channel-research` or by hand) and drafts per-issue status updates plus 2–3 actionable workarounds, then posts replies back into the original threads.
- **`mor-prep`** — Root-causes month-over-month metric moves ("why did bookings/retention move this month?") and builds the review deck.
- **The connector suite** *(updated Aug 2026)* — one-time bootstraps that wire Claude to your data sources, each auth-aware and re-runnable when a session expires:
  - `salesforce-connect` — logs the official `sf` CLI into a Salesforce org via browser OAuth (SSO/MFA-safe), then registers the Salesforce MCP server read-only. No secret file — auth lives in the CLI's own store.
  - `tableau-connect` — registers the official Tableau MCP server; the access token lives in a `chmod 600` file outside the repo, never in git or chat.
  - `gong-connect` — headless access to your own Gong via a captured web session (full transcripts, call listing, mining) without an admin API key.
  - `glean-connect` — verifies/installs the Glean CLI and handles OAuth login for enterprise search.
  - `connect-all` — umbrella command that verifies every source at once and prints a per-source status summary. Owns no auth logic itself; it just calls each connector's own verb.

### By purpose

**Development & orchestration**
- `lead-orchestrator` — coordinates teams of subagents (e.g. a coder plus an independent QA reviewer that re-runs the work before any "done" claim). Modes for feature builds, backlog burn-down, audits, and live debugging.
- `investigate` — structured root-cause debugging for bugs that span files, are intermittent, or have several plausible causes.
- `codebase-mapping` — spawns explorer agents to produce architecture docs and feature-to-code maps for an unfamiliar project.
- `harness-orientation` — orients you (or Claude) to how this whole setup works.
- `handoff` — compresses a session's state, progress, and open threads into a short handoff note for the next session.
- `hook-authoring` — helps write and debug Claude Code hooks.

**Code & PR review**
- `pr-review-pr` — comprehensive PR-diff review with specialized reviewer personas and a skeptical verifier pass. Can compare competing PRs.
- `garry-review` — reviews code you just wrote against engineering preferences (DRY, edge cases, tests, naming) before you commit.
- `review` — focused structural-safety review (SQL, side-effects, LLM calls).
- `diff-audit` — checks that a rewrite or compression kept everything the original said, comparing semantic unit by unit.

**Planning & product**
- `eng-planning` — turns an approved PRD into a feature design doc (and an API contract when there are API boundaries).
- `eng-stories` — decomposes a PRD into ready-to-work epics and stories with behavioral acceptance criteria.
- `prd-writer` — writes a data-driven PRD from rough notes; enforces testable hypotheses and honest prior-art.
- `prd-review` — adversarial critique of an existing PRD.
- `plan-eng-review` / `plan-design-review` — engineering and design/UX critiques of a plan doc.
- `ceo-review` — founder-mode scope and strategy check ("is this the right thing to build?").
- `feature-enablement` — generates sales/CS collateral (messaging foundation, battle cards, FAQs, demo scripts) from a feature spec.

**Testing & QA**
- `qa` / `qa-only` — tests a running web app like a real user and produces a report with a health score; `qa` can also fix bugs on request, `qa-only` never edits code.
- `e2e-test-writer` — turns PRD requirements into runnable YAML acceptance tests.
- `browse` — fast persistent headless browser for navigation, screenshots, downloads, and one-off automation.

**Design**
- `design-review` — visual QA of a live site or component.
- `design-shotgun` — generates several design variants to explore options.
- `design-html` — turns a design into a finished HTML page.
- `design-implement` — implements an approved mock as real front-end components.

**Shipping & ops**
- `ship` — the deploy workflow: run tests, review the diff, bump the version, update the changelog, commit, push, open a PR.
- `pr-briefing` — generates a structured review guide for large PRs.
- `guard` — flips the session into maximum-safety mode.
- `retro` — builds an engineering retrospective ("what did we ship this week?").
- `skill-lifecycle` — audits, creates, and archives skills to keep the library healthy.

**Second opinion**
- `codex` — routes a review, challenge, or question to an external model for an independent take.

**Connectors & integrations** — see the "Recently updated" section above, plus `atlassian-connect` / `atlassian-update` (Jira + Confluence, comment-safe page edits), `jira-update` (rich ticket updates and epic/story creation from design docs), and `o365-doc-edit` (safe Office/SharePoint document editing).

...and more. Run Claude, describe your task in plain language, and it routes automatically.

---

## Cherry-pick instead

You don't need the whole repo. Good standalone pieces:

- **Just the guardrails** — copy `CLAUDE.md`, `rules/code-style.md`, and `scripts/git-safety-hook.sh`, then wire the hook:
  ```json
  "hooks": {
    "PreToolUse": [{ "matcher": "Bash", "hooks": [
      { "type": "command", "command": "~/.claude/scripts/git-safety-hook.sh" }
    ]}]
  }
  ```
- **Session journaling** — copy `scripts/session-journal.py` + `scripts/auto-journal.sh` and wire the `Stop` hook.
- **Individual skills** — copy any `skills/<name>/` directory into your own `~/.claude/skills/`.

---

## Patterns worth stealing

- **Rules as separate files.** Instead of one giant `CLAUDE.md`, split standards into `rules/*.md`. Claude Code loads them all, so you can version team standards apart from personal taste.
- **Personal overrides via a gitignored file.** `CLAUDE.md` references `rules/personal.md`, which is gitignored. Shared behavior stays in tracked files; your name and preferences stay local — no merge conflicts.
- **`__HOME__` path templating.** `settings.json` can't read environment variables, so paths must be absolute. Ship `__HOME__` as a placeholder, substitute it at install time with `sed`, and `git update-index --assume-unchanged` so the local edit never dirties git.
- **Fail-safe hooks.** Every hook exits 0 on error and degrades gracefully. A missing tool or a parse error never blocks your work.
- **Deterministic journaling.** Session capture uses zero LLM calls — fast, predictable, and auditable.

---

## What's tracked vs. local

| Tracked (shared) | Local (gitignored) |
|---|---|
| `CLAUDE.md`, `rules/` (except `personal.md`) | `rules/personal.md` — your name and preferences |
| `skills/`, `scripts/`, `hooks/` | `memory/` — your session journal and lessons |
| `settings.json` (with `__HOME__` placeholders) | `settings.local.json` — your permission overrides |
| `install.sh`, `evals/`, `tests/` | `projects/`, `debug/`, `cache/`, and other session data |

---

## Notes

- **Platform:** built and tested on macOS. Scripts use `perl` rather than GNU `sed` for portability, but some automation assumes macOS conventions.
- **Personal bits removed.** This is a shared snapshot — some skills and docs referenced in `CLAUDE.md` are personal and not included here. If Claude mentions a file that isn't present, it's one of those; safe to ignore.
- **Requirements:** [Claude Code CLI](https://docs.anthropic.com/en/docs/claude-code), `git`. Optional: Homebrew + `terminal-notifier` (macOS notifications), Python 3 (journaling).
