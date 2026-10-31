# lead-orchestrator2 build notes

ABOUTME: Design choices, deviations from LO2-SPEC.md and known limits for skills/lead-orchestrator2.
ABOUTME: Read this before the side-by-side trial against lead-orchestrator.
ABOUTME: Spec: ~/.claude/docs/plans/opus55-rollout/LO2-SPEC.md. Skill: ./SKILL.md.
ABOUTME: Evidence below is from the build run on 2026-10-25.
ABOUTME: Not a protected file; update it when the scripts change.

## 1. Files

| File | Role |
|---|---|
| `SKILL.md` (156 lines) | Router, tier check, Iron Laws, QA authorship, verifier rules, launch instructions, return-status handling |
| `workflows/lo-feature-plan.js` | Decomposition check before any task (round 1) |
| `workflows/lo-feature-task.js` | One VIBE task, steps 1-9 |
| `workflows/lo-feature-close.js` | Whole-feature close after all tasks (round 1) |
| `workflows/lo-backlog.js` | One backlog wave: coders → QA C1 → wave verifier |
| `workflows/lo-audit.js` | investigate-audit: lanes → synthesis → verifier |
| `tests/harness.mjs` | Loads a workflow, strips `export`, runs the body with stubbed hooks, records every agent call |
| `tests/test-lo-{feature-task,backlog,audit}.mjs` | 26 + 9 + 15 cases (audit +8 in round 2) |
| `tests/test-lo-feature-{plan,close}.mjs`, `tests/test-skill-doc.mjs` | 7 + 16 + 5 cases (round 1; close +4 and skill-doc +2 in round 2) |

Run: `for t in ~/.claude/skills/lead-orchestrator2/tests/test-*.mjs; do node "$t"; done`

## 2. Design choices

- **Templates stay single-source.** Each agent prompt tells the agent to Read `~/.claude/skills/lead-orchestrator/templates/{coder,qa}-prompt.md` and lists every placeholder value. Nothing is copied.
- **Gate scripts by absolute path.** Gate agents run `validate-artifact.sh`, `verify-tdd-evidence.sh` and `test_cmd` from `~/.claude/skills/lead-orchestrator/scripts/`. The script decides pass or fail from the reported exit codes, not from a model opinion.
- **Canonical artifact paths.** The script computes every artifact path from `run_dir` and `task_id`. It never trusts the path a producer reports.
- **Model literal in every agent call.** `workflow-model-guard.sh` checks lexically, so each call writes `model:` inline. No options object is passed through a variable.
- **live-debug stays in session** with plain Agent calls. The loop needs judgment between steps; a fixed script adds little there.

## 3. Deviations from the spec (with reasons)

1. **ABOUTME sits after `export const meta`, not at line 1.** The Workflow runtime requires the script to begin with the meta literal.
2. **Extra haiku `check:*` stages.** After review, C1, C2 and verify, a haiku agent runs `validate-artifact.sh` on the artifact. lead-orchestrator validates these artifacts too. A failed check re-spawns the producer once, then escalates. Test 3 asserts the spec order with `check` removed, and the full order with it.
3. **A C1/C2 fix passes GATE-GREEN before QA runs again.** This is stricter than lead-orchestrator, which only re-runs C1.
4. **C2 FAIL uses the C1 rule** (one fix, re-run, then escalate). The spec does not say.
5. **Optional args added:** `req_map`, `live_target`, `escalate_if`. Without `req_map` the agents build the map from the spec. `arch_needed` defaults to true when absent (the safer side).
6. **Coder verdict BLOCKED escalates at once** (structural problem, per the escalation rules).
7. **Status `partial`** for audit holes and backlog items that are not verified. The spec names only complete and escalate for the feature script.
8. **Backlog verifier runs even after a C1 escalation**, so the session can still check off the verified items. It skips its own fix round when the wave is already escalated.
9. **Dead agent rule:** every stage re-spawns a dead (null) agent once, then escalates or logs a hole.
10. **`node --check`** cannot parse top-level `await`/`return`, so the check wraps the body: `{ echo '(async () => {'; perl -pe 's/^export //' f.js; echo '})'; } > /tmp/x.js && node --check /tmp/x.js`.

## 4. Build evidence (2026-10-25)

- RED: all three suites failed first with ENOENT (workflow files absent): 0/19, 0/9, 0/7.
- GREEN: `# lo-feature-task: 19 passed, 0 failed` · `# lo-backlog: 9 passed, 0 failed` · `# lo-audit: 7 passed, 0 failed`.
- Neuter-and-fail: `redWhy = redFailure(g)` replaced with `redWhy = ''`. Result `# lo-feature-task: 15 passed, 4 failed`; case 1 failed with "coder was called". Restored: 19/19.
- Guard: `workflow-model-guard.sh` exit 0 (allow) for all three files. A copy with `model` removed from the arch call gets `permissionDecision: deny`.
- `node --check` (wrapped as above): OK for all three files. SKILL.md frontmatter parses as YAML (keys: name, description).

## 5. Known limits

1. **Governance hooks may not see workflow agents.** pre-agent-gate, orchestrator-step-gate and post-agent-audit hook the Agent tool. Whether they fire for workflow agents is untested. The await order replaces the sentinels. Bash hooks such as `commit-order-guard.sh` should still fire inside agents (also untested).
2. **Gates are model-reported.** A haiku agent runs the commands and reports the exit codes. The schema forces integers and the runner output lands in `runs/`, but a model can misreport. lead-orchestrator runs the gates in the session shell, which is deterministic.
3. **No live run yet.** The tests stub the runtime. Real behavior (null on a dead agent, schema enforcement, pipeline semantics) follows the workflow-authoring docs and is not yet proven on a real task.
4. The guard is lexical and its backtick-strip regex does not work. Apostrophes or unbalanced brackets in prompt text inside an agent call can confuse it. Keep prompt text in builder functions.
5. Parallel launches share one working tree. Two agents that commit at the same moment can hit a git `index.lock` race (same as lead-orchestrator).
6. `verification.md` has no structural type in `validate-artifact.sh`, so its check proves only that the file exists.

## 6. Round 1 (2026-10-25): tip-001 side-by-side, B scored 11/20 against A 16/20

Evidence: `docs/temp/opus55-rollout/sxs/judge-tip-001.md`, B's `runs/tip-001-B/run.jsonl`, and the 5 workflow
journals under `~/.claude/projects/-private-tmp-sxs-tip-001-B/dcf3c085-.../subagents/workflows/`.

### 6.1 What happened in B's run

| Task | Run | Args | Last stage | Journal evidence |
|---|---|---|---|---|
| T-001 | wf_9976ada7-204 | light, arch false, scoped test_cmd | GATE-GREEN x2, escalate | `validate_exit:1`, "Missing 'ReviewCommit:<SHA>'" both times; the fix coder changed the SHA, not the bold markup |
| T-002 | wf_8d102bc4-f40 | same | GATE-GREEN x2, escalate | retry `tdd_exit:1`: "RED commit 628483f9bfb5... does not exist" (real SHA 628483f52db1...; the coder expanded short SHAs from memory) |
| T-004 | wf_4bbc9880-bbc | same | GATE-GREEN x2, escalate | `validate_exit:1` ReviewCommit both times |
| T-003 | wf_84cba135-ac4 | same, plus the session's ARTIFACT RULES line | Review, escalate | GREEN passed on retry; review p1 13, then p1 6 after one fix loop |
| T-005 | wf_a8a70a60-463 | same, plus ARTIFACT RULES | Review, escalate | review p1 7, then p1 4; the fix-review coder made 1f77f88 (tests/hygiene.py only, 0 test cases) |

The session called `lo-feature-task.js` for all 5 tasks. It used no direct coder Agent call. `vibe_level light`
came from the repo's `.claude/phase.json` and matches spec D6. Scoped `test_cmd` values were needed for parallel
tasks, but nothing ever ran the full suite through a gate. After all 5 escalations, the session spawned one ad hoc
opus verifier (run.jsonl L1923). It returned 5 VERIFIED, 4 CONTRADICTED. The session then stopped (L2180) and
cited the headless note: "A fix would mean relaunching escalated tasks, and the headless rule forbids that".

### 6.2 Root causes

1. **Template and gate disagree.** `lead-orchestrator/templates/coder-prompt.md:77` shows `**ReviewCommit:** <SHA>`.
   `validate-artifact.sh:113` needs `ReviewCommit:` then the SHA. Coders also typed full SHAs from memory.
   Result: 3 of 5 tasks escalated at GATE-GREEN, so they got no review, QA or verifier.
   The template lives in lead-orchestrator (out of scope here); lo2 now overrides it in every coder prompt.
2. **No feature-level stage.** Each task's QA and verifier sat behind its review gate. When a task escalated, the
   whole tail was lost. A ran review, QA C1 and the verifier once for the feature (T-ALL) with fix rounds.
3. **The headless rule ended the run.** "Do not relaunch on your own" plus "report it as partial" left no fix path
   after the verifier FAIL.
4. **Fix rounds had no RED check.** verify-tdd-evidence.sh checks only that a RED commit is test-only and an
   ancestor. 1f77f88 moved helpers into `tests/hygiene.py`, so it passed. GATE-RED did not see it (it is a fix commit).
5. **Decomposition dropped spec lines.** Spec 3.2 gives all 3 outputs the cards and method note. T-002's mini_spec
   said "The .md has the same table" and omitted theme-card bullets and the card Row. `solutions_order` WAS in the
   T-002 req_map (REQ-02). That gap came from root cause 2, because T-002 never reached review or QA.

Rejected candidate: GATE-RED did not accept a fake RED. Every RED commit that GATE-RED saw fails on assertions and
touches only `tests/` paths (checked with `git diff-tree` on e166636, 946eca5, 7cd8d3a, e9a0af0, a7b4bb8).

### 6.3 Changes

- `lo-feature-task.js`: every coder prompt carries ARTIFACT RULES (plain `ReviewCommit: <40-hex sha>`, SHAs
  copied from `git log --format=%H`, each checked with `git cat-file -e`). GATE-RED now also needs an assertion
  failure in the tail with no collection, import or syntax error, and a test-only RED commit (`red_files` from
  `git diff-tree`; run-dir artifacts allowed). Every findings fix (review, C1, C2, verify) must first commit a
  test-only `FixRed: <sha>` that adds a test case or assertion (`new_tests > 0`), or declare `TDD-EXEMPT`, which
  goes to `open_items`. The fix gate (schema GATE_FIX) checks this.
- `lo-feature-plan.js` (new, 1 opus agent): maps every spec requirement to the tasks that fully cover it. Plain
  code returns `fix` with `unmapped` when any requirement has no real task. It returns `feature_reqs` and a
  `req_map` per task.
- `lo-feature-close.js` (new): integrated full suite → review (opus) and QA C1 (sonnet) for tasks that did not
  complete → one combined fix round → feature verifier over ALL requirements → one fix → round 2 cap. Any failed
  gate or remaining blocking item is a hole, and a hole gives `partial`. It replaces the session's ad hoc verifier.
- `SKILL.md`: feature mode is now F1 plan → F2 tasks → F3 close, and F3 is ALWAYS run. The headless note and the
  `escalate` row now route to F3 rather than ending the run.

Speed: with all tasks `complete`, the close adds 1 haiku suite gate plus the verifier that B already ran ad hoc.
Review and QA at feature level run only for tasks that stopped early. The plan stage adds 1 opus agent.

### 6.4 Tests and evidence

- RED first: `lo-feature-task 19 passed, 7 failed` · `lo-feature-close 0 passed, 12 failed` ·
  `lo-feature-plan 0 passed, 7 failed` · `skill-doc 0 passed, 3 failed`.
- GREEN: `lo-audit 7/0` · `lo-backlog 9/0` · `lo-feature-close 12/0` · `lo-feature-plan 7/0` ·
  `lo-feature-task 26/0` · `skill-doc 3/0` (64 cases).
- Fixture change: HAPPY `gate-red` gained `red_files`, and HAPPY `gate-green` gained `fix_red`, `fix_red_files`,
  `new_tests`. No existing assertion changed.
- Neuter-and-fail (`/tmp/lo2-round1-neuter.sh`): right-reason check off → 1 fail; RED test-only check off → 1;
  ARTIFACT RULES off → 1; FixRed check off → 3; close verifier fix off → 2; close stopped-task stage off → 1;
  close fix round off → 5; plan unmapped check off → 2; old headless text → 1.
- Guard: `workflow-model-guard.sh` exit 0 for all 5 files. A plan copy without `model` gets exit 2, deny.

### 6.5 Known limits (round 1)

1. The close fix round is one sonnet coder for all items. A ran one coder per task in parallel. A long fix list
   may be slower than A.
2. The "right reason" rule rejects a RED whose only failure is a missing-module collection error. The judge counted
   such a RED as genuine. QA must now write tests that import inside the test or call the script by subprocess.
3. `new_tests` is a line count of added test cases and assertions. It catches a moved helper file, not a weak test.
4. Helpers repeat across workflow files (fromTemplate, produceChecked, the fix gate), because a workflow cannot
   import another file.

## 7. Round 2 (2026-10-25): fix-ctx-002 and pm-login-002 side-by-side losses

Both B runs used the PRE-round-1 skill (Workflow calls at 10:24-10:25 UTC; round 1 landed at 10:48).
fix-ctx-002 (investigate-audit): A 16/20, B 13/20, B time 0.77x A. pm-login-002 (debug + fix): A 14/20, B 12/20, B time 0.59x A.
Judgments: `docs/temp/opus55-rollout/sxs/judge-{fix-ctx-002,pm-login-002}.md`. B logs: `sxs/runs/{fix-ctx-002,pm-login-002}-B/run.jsonl`.

### 7.1 Root causes

1. **Audit lanes all traced the read path.** B ran 3 lanes (run.jsonl L131): `codex` (pass-through of one Codex run),
   `trace` (opus, data flow from the API response to the Anthropic call) and `repro` (opus, fixtures through pure read-path
   functions). The scope spec asked only "why does the drafter receive too little context". No lane owned the writers.
   `telegram` occurs 0 times in every lane file and in the report. The synthesizer dropped nothing: the lanes never saw
   the writer side. A split its 3 Codex lanes by failure path: retrieval, generation (it named detector false negatives),
   and end to end plus prior fixes (it named refresh, telegram and other draft writers). A found R5b, R5c, R3d and R5a.
   lo-audit took any lane list and had no coverage check.
2. **No test rules in lo-audit.** The session wrote "Never edit test/" and "repro tests ONLY under docs/temp/fix-ctx-rca/repro/
   ... require by absolute path" into the scope spec and the golden_ref. lo-audit passed that through. The verifier marked
   the TypeError tests VERIFIED because the report "discloses" them (verification.md row 7). Nothing ran them under `npm test`.
3. **No fix-direction check.** The golden_ref said "a symptom-only fix (detect-and-drop like REQ-05) does not count". The
   repro lane then treated the detectors as the fault (repro.md F5a/F5b) and proposed narrower patterns (report RC-5a/5b).
   The verifier checked only that the regex lines exist (verification.md row 20 VERIFIED). No stage asked if a fix weakens a guard.
4. **pm-login: GATE-GREEN stop, then no review or QA.** Journal `wf_4248fbb2-c31`: gate-green `validate_exit:1`
   "Missing 'ReviewCommit:<SHA>'" twice (suite went 187/1 to 188/0). The session then ran an ad hoc verifier, a fix and a
   round-2 verifier (L581-L967). Round 1 already fixes this: ARTIFACT RULES force a plain `ReviewCommit: <sha>`, and
   lo-feature-close runs review and QA C1 for any task that stopped. Still missing in round 1: no stage tests test strength.
5. **Weak tests passed every gate.** The judge disabled B's central gate (`if (false && !shouldOpenMfa)`): 53/53 pass.
   GATE-RED, GATE-GREEN and the verifier all count passes and fails. None of them breaks the fix.
6. **Routing.** The repo has `.claude/phase.json`, so the first-match table sent the ask to feature mode. The session
   diagnosed in-session (run.jsonl L31-L95), then wrote a one-file mini_spec (ensure-tokens.js only). A spawned an opus
   diagnoser first (L45) and found the golden mechanism (daemon close plus no `state load` in SKILL.md Step 2). The TDD
   pipeline was the right tool; the missing part was an independent diagnosis that covers every named area.

### 7.2 Changes

- `lo-audit.js`, code audit (new args `repo`, `test_dir`, `test_cmd`; a doc audit without `repo` is unchanged):
  - Args: `test_dir` must be relative, without `..`, not under `docs/`; `test_cmd` must not name the run dir or `docs/temp`.
  - Lanes: every lane prompt gets LANE SPLIT (own a failure path end to end), a `## Coverage` section, TEST RULES (repo test
    dir, the repo test command, no absolute path, fail on an assertion, no source-text regex) and FIX DIRECTION.
    The script adds an opus `writers` lane when the session gave none.
  - Coverage: an opus completeness critic after synthesis lists uncovered code paths. At most one gap loop: up to 4 sonnet
    gap lanes, then one `synth:gaps` merge. Paths past the cap go to `open_items`.
  - Verify: a sonnet repro probe runs in parallel with the verifier. It flags bad tests (rules above) and survivors (a repro
    test that stays red after the proposed fix is applied in a scratch copy, or that was green before it). Both block.
    The verifier returns `weakens`, the fixes that weaken a stated safety check with no argument. That blocks too.
    Round 2 re-runs the probe only if it blocked in round 1. The 2-round cap is unchanged.
- `lo-feature-close.js`: a sonnet mutation probe runs in parallel with the suite gate. In a scratch copy (rsync, no `.git`) it
  runs a baseline, then disables the core change of each requirement (max 8) and runs `test_cmd`. A survivor goes into the
  combined fix round (FixRed rule applies), then one `probe:recheck`. Still alive = a hole, so status `partial`. A dead
  probe is re-run once, then a hole. The probe file goes to the verifier inputs.
- `SKILL.md`: a routing row for a debug-and-fix ask (first match, so it wins over `phase.json`): one opus diagnoser Agent,
  never in-session diagnosis, `diagnosis.md`, tasks own every file a root cause names, then F1-F3. live-debug is now only
  for a repro that needs a browser or the live target. Code-audit args and the new audit stages are documented.

Speed: in a code audit the writers lane runs in parallel with the others (no wall time). The critic adds one serial opus
step. The gap loop runs only when the critic finds a gap. Each probe runs in parallel with the verifier or the suite gate.
A probe re-run happens only after a block.

### 7.3 Tests and evidence

- RED first: `lo-audit 8 passed, 7 failed` (test 14 is a scope guard and passes by design) · `lo-feature-close 12 passed,
  4 failed` · `skill-doc 3 passed, 2 failed`.
- GREEN: `lo-audit 15/0` · `lo-backlog 9/0` · `lo-feature-close 16/0` · `lo-feature-plan 7/0` · `lo-feature-task 26/0` ·
  `skill-doc 5/0` (78 cases).
- Fixture change in `test-lo-feature-close.mjs`: HAPPY gained `probe`, `MAIN` also filters `probe`, the tier map gained
  `probe: 'sonnet'`. No existing assertion changed.
- Neuter-and-fail (`/tmp/lo2-round2-neuter/neuter.py`): writers lane off → 3 fail; lane rules off → 1; critic off → 2;
  test-arg check off → 1; audit probe off → 1; `weakens` ignored → 1; close survivors ignored → 1; close re-probe off → 2;
  SKILL routing row removed → 1; Debug and fix section renamed → 1.
- Guard: `workflow-model-guard.sh` exit 0 for all 5 files. A close copy without `model` on the probe call: exit 2, deny.
- `node --check` (wrapped as in §3.10): OK for all 5 files.

### 7.4 Known limits (round 2)

1. The probe is model-run. It decides what "the core of each fix" is, and it may pick a weak mutant. The table in
   `T-ALL-mutation-probe.md` makes that visible to the verifier.
2. In an audit the fix is only proposed, so the audit probe applies it in a scratch copy. A fix too large to apply is a survivor.
3. The writers lane and the critic only reach code audits. A session that omits `repo` on a code ask skips them all.
4. GREEN commits may still edit acceptance tests (pm-login-002-B b45ee4e did, in the ad hoc fix). No gate checks this.
5. lo-feature-task has no probe. A task that completes gets its probe only at close.
