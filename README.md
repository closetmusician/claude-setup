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

## Skills

Skills are structured prompts in `skills/<name>/SKILL.md` that Claude invokes when a task matches. `rules/skill-routing.md` maps intents to skills. Highlights:

**Development & orchestration** — `lead-orchestrator` (coordinate subagent teams), `investigate` (root-cause debugging), `codebase-mapping`, `harness-orientation`, `handoff`.

**Code & PR review** — `pr-review-pr` (multi-persona PR review), `garry-review` (engineering-preferences pass), `review` (structural safety), `diff-audit`.

**Planning & product** — `eng-planning`, `eng-stories`, `prd-writer`, `prd-review`, `plan-eng-review`, `plan-design-review`, `ceo-review`.

**Testing & QA** — `qa` / `qa-only` (test a running app like a user), `e2e-test-writer`, `browse` (headless browser automation).

**Design** — `design-review`, `design-implement`, `design-html`, `design-shotgun`.

**Shipping** — `ship` (test → review → PR), `pr-briefing`.

**Connectors** — `atlassian-connect`, `salesforce-connect`, `tableau-connect`, `gong-connect`, `glean-connect`, `connect-all`.

...and more. Run Claude and describe your task — it routes automatically. Browse `skills/` to read any one directly.

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
