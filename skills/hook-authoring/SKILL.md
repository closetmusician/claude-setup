---
name: hook-authoring
description: >-
  How to write, wire, and prove a Claude Code hook (PreToolUse / PostToolUse /
  Stop / UserPromptSubmit / SessionStart, and .githooks/*). Encodes the two
  hardest-won lessons in this harness: parse session/agent identity from the
  STDIN JSON payload (never from env — $SESSION_ID is never set, so env-reading
  guards silently exit 0 in production); and test fixtures must drive the REAL
  stdin contract (the .prompt vs .user_prompt bug shipped 15/15 green while
  being a live no-op). Fire when creating or editing any hook script, any
  guard/gate, any script wired into settings.json hooks or .githooks/, or when
  writing the test suite for one. NOT for deciding WHETHER a behavior should be
  a hook (that is update-config / maintenance-protocol.md) and NOT for editing
  settings.json permissions (update-config skill).
allowed-tools:
  - Bash
  - Read
  - Write
  - Edit
  - Grep
  - Glob
---
<!--
Intended final target: /Users/yklin/.claude/skills/hook-authoring/SKILL.md
Draft source: /Users/yklin/.claude/docs/plans/fable-skills/drafts/skills/hook-authoring/SKILL.md
Draft status: candidate (planning artifact, not installed). Verify volatile
claims (settings.json hook wiring, working-consumer filenames, commit SHAs)
against the live repo before install — see §10.
-->

# hook-authoring: boring, inspectable, stdin-driven, and proven-wired

## 1. Purpose

Encode the operating doctrine for authoring harness hooks so a fresh session
writes one that actually fires in production and cannot silently disable itself.
Hooks are safety- and telemetry-critical; a hook that reads the wrong input or
is never wired is worse than no hook because it creates false assurance. Two
independent adversarial lanes found the entire autonomous-plane safety net
disabled by an env-vs-stdin identity bug (fable-qa-0706); this skill exists so
that class never recurs.

## 2. When to use

- Creating a new hook script (any of the 7 hook events, or a `.githooks/`
  pre-commit drop-in).
- Editing an existing guard/gate that reads identity, tool input, or payload.
- Writing or reviewing the test suite for a hook.
- Auditing whether a wired hook actually enforces anything in production.

## 3. When not to use

- Deciding whether a desired behavior belongs in a hook at all, or changing
  settings.json structure/permissions/env — use the `update-config` skill and
  `docs/plans/harness/maintenance-protocol.md`.
- Debugging a non-hook script bug — `/investigate`.
- Editing protected doctrine files — maintenance-protocol §1 approval flow.

## 4. Inputs required

- The hook event it binds to (PreToolUse/PostToolUse/Stop/UserPromptSubmit/
  SessionStart/SessionEnd/Notification, or `.githooks/pre-commit.d/`).
- The real payload shape for that event — derived from a WORKING consumer or a
  live capture, never from memory (see §5b).
- The fail-open vs fail-closed decision (§5c).
- Where it wires (settings.json entry, or `.githooks/pre-commit.d/NN-name.sh`).

## 5. Procedure

### 5a. Parse identity and input from STDIN JSON — never env

Claude Code delivers the hook payload (including `session_id`, `agent_id`, tool
name, tool input, prompt text) on **stdin as JSON**, not in environment
variables. `$SESSION_ID` is never set by Claude Code. A guard that gates on
`$SESSION_ID` reads empty, its identity/registry check misses, and it `exit 0`s
before enforcing — silently disabled in prod while green in tests.

Correct:
```bash
payload="$(cat)"
session_id="$(printf '%s' "$payload" | jq -r '.session_id // empty')"
tool="$(printf '%s' "$payload" | jq -r '.tool_name // empty')"
```
Copy the read pattern from a guard known to be correct in prod
(`completion-claim-guard.sh` and `qa-artifact-ownership-guard.sh` read stdin
correctly — verify they still do before cloning). `AUTONOMOUS_RUN=1` (env) is an
acceptable *mode* signal; identity must still come from stdin.

### 5b. Fixtures must drive the REAL stdin contract

A test that injects identity/fields via env, or that invents field names,
encodes a contract that never exists in production. Fixtures MUST feed realistic
JSON on stdin using the SAME field names Claude Code actually sends.

Derive field names from one of:
1. a working consumer of the same event (e.g. `skill-nudge.sh` reads `.prompt`,
   which is correct — confirm before copying), or
2. a live capture: a temporary hook that logs `cat` to a file, run once, then
   read the real keys.

Never author the fixture and the script from the same assumption — that
validates internal consistency, not the external contract. Include at least one
live-shape probe OUTSIDE the mocked suite.

### 5c. Fail-open vs fail-closed — decide explicitly

| Hook role | Failure mode | Why |
|---|---|---|
| Telemetry / observers (spine-tap, evidence-ledger) | fail-OPEN (`exit 0` on any error) | must never block real work |
| Safety gates (secret-scan, push-guard, protected-files, completion-claim) | fail-CLOSED (block on error/ambiguity) | a gate that fails open is not a gate |

Write the choice into the script header (ABOUTME) and make it the default
branch, not an afterthought. A safety gate that `exit 0`s when `jq` is missing
or the payload is malformed has silently opened.

### 5d. Keep hooks boring and inspectable

Plain shell + `jq`, small, single-responsibility, no `eval` on payload content
(an eval-based acceptance check was an RCE vector in night-runner —
redesigned, not patched around; capability-capture §4 pattern 15). A reviewer
should read the whole hook in under a minute and see exactly what it blocks.

### 5e. Wire it, then PROVE it fires in the same turn

Wiring is not enforcement. After adding the settings.json entry (or
`.githooks/pre-commit.d/NN-name.sh`):
1. show the settings.json / dispatcher entry (`grep`), and
2. drive a realistic stdin payload through the hook live and show it
   blocking/allowing as intended, in the SAME turn.

`grep`-ing that the line exists is `observed`, not `verified`. The pre-commit
secret-scan was silently UNWIRED (a commit dropped the call) and only caught by
a day-in-the-life replay — wiring drift is real (capability-capture §4 pattern
9). For git hooks, also confirm `git config core.hooksPath` points at
`.githooks` (the hook does nothing otherwise).

### 5f. Every hook ships with a test suite under scripts/tests/

Add `scripts/tests/test-<hook>.sh` that pipes realistic stdin covering: the
enforce path, the allow path, malformed payload (fail-open/closed as decided),
and the identity-missing case. Run it and paste the pass line.

## 6. Evidence required

- stdin-parse line shown (not env);
- fixture field names traced to a named working consumer or a logged live
  capture;
- fail-open/closed choice stated in the header;
- same-turn live-fire probe output (block + allow);
- for git hooks, `core.hooksPath` confirmed;
- test suite pass line pasted.

## 7. Output artifact

The hook script (5-line ABOUTME header, stdin parse, explicit fail mode), its
settings.json/`.githooks` wiring, `scripts/tests/test-<hook>.sh`, and a status
block per `evidence-backed-status` showing the live-fire probe.

## 8. Common traps (bad behavior this prevents)

- **Env-identity silent disable.** Guards reading `$SESSION_ID` from env left
  `autonomous-push-guard.sh`, `autonomous-secret-scan.sh`, and the self-mod
  eval gate disabled in prod — re-opening the 2026-07-03 secret-leak vector —
  while every suite was green because it injected `SESSION_ID` via env
  (`lesson_guard_identity_env_vs_stdin.md`; fixed commit 615996f — verify the
  commit still reads that way before citing). Read identity from stdin; never
  let a test set identity via env.
- **Wrong-field green no-op.** `skill-retrieve.sh` shipped 15/15 green reading
  `.user_prompt` while Claude Code sends `.prompt` — a live no-op, caught only
  by an independent verifier comparing against the proven `skill-nudge.sh`
  (`pattern_test_fixture_contract.md`). Derive field names from a working
  consumer.
- **Wired but not firing.** secret-scan call dropped from pre-commit; green
  until a replay caught it. Prove firing, don't grep the line.
- **Safety gate fails open on error.** A gate that `exit 0`s on missing `jq` or
  bad JSON has silently opened — safety gates fail closed.

## 9. Related skills

- `evidence-backed-status` — the same-turn live-fire proof this skill demands is
  that skill's existence-probe rule applied to hooks.
- `update-config` — owns settings.json structure/permissions/env; use it to
  place the wiring entry.
- `docs/plans/harness/maintenance-protocol.md` — authority for changing harness
  hooks; §1 approval flow for protected files.
- `docs/plans/fable-skills/evidence/harness_inventory.md` — §2 the live map of
  every wired hook and its event (orientation before editing).

## 10. Provenance and maintenance

- Sources: `projects/-Users-yklin--claude/memory/lesson_guard_identity_env_vs_stdin.md`,
  `projects/-Users-yklin--claude/memory/pattern_test_fixture_contract.md`,
  `docs/plans/fable-skills/evidence/recent_capability_capture.md` (§4 patterns
  6, 7, 9, 15), `harness_inventory.md` §2.
- Volatile facts (commit SHAs, which consumer reads which field, the current
  set of wired hooks, `core.hooksPath` state) are snapshots. Before relying on
  any of them, re-probe the live repo — a hook's correctness depends on the
  contract as CC sends it TODAY, not as recorded here.
- Maintenance: when a new hook-failure mode is found, add a trap row + the probe
  that catches it, and point at the guard test that now covers it.
