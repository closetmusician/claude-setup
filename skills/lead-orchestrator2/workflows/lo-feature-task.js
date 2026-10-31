export const meta = {
  name: 'lo-feature-task',
  description: 'One VIBE task: architect, RED acceptance tests, GREEN code, review, QA C1/C2, verifier',
  whenToUse: 'lead-orchestrator2 feature mode, one task per launch',
  phases: [
    { title: 'Design', detail: 'architect (only if arch_needed)', model: 'sonnet' },
    { title: 'RED', detail: 'QA acceptance-red, then GATE-RED', model: 'sonnet' },
    { title: 'GREEN', detail: 'coder, then GATE-GREEN', model: 'sonnet' },
    { title: 'Review', detail: 'garry-review, P0/P1 fix loop (max 1)', model: 'opus' },
    { title: 'QA', detail: 'cycle-1, cycle-2 (full only)', model: 'sonnet' },
    { title: 'Verify', detail: 'independent verifier, max 2 rounds', model: 'opus' },
  ],
}
// ABOUTME: Workflow script for lead-orchestrator2 feature mode: steps 1-9 of the VIBE per-task loop.
// ABOUTME: The await order is the gate: no coder before GATE-RED passes, no review before GATE-GREEN.
// ABOUTME: Gates are haiku agents that only run validate-artifact.sh, verify-tdd-evidence.sh, test_cmd.
// ABOUTME: Agents write their own artifacts (QA authorship rule); this script never writes one.
// ABOUTME: Spec: ~/.claude/docs/plans/opus55-rollout/LO2-SPEC.md section 2. Tests: ../tests/.
// NOTE: every agent call names its model inline. workflow-model-guard.sh checks this lexically.

const TPL = '/Users/yklin/.claude/skills/lead-orchestrator/templates'
const SCRIPTS = '/Users/yklin/.claude/skills/lead-orchestrator/scripts'
const SHA_RE = /^[0-9a-f]{7,40}$/
// A RED commit may touch only test code, fixtures under a test dir, and the run dir artifacts.
const TEST_PATH_RE = /(^|\/)(tests?|spec|__tests__)\/|(^|\/)test_[^/]*$|_test\.[^/]+$|\.(test|spec)\.[^/]+$|(^|\/)conftest\.py$/
// RED for the right reason: a test ran and failed an assertion. A collection, import or syntax
// error means the tests never ran, so it proves nothing about the missing behaviour.
const NOT_RUN_RE = /ERROR collecting|errors? during collection|SyntaxError|IndentationError|Test suite failed to run/
const ASSERT_FAIL_RE = /\bFAILED\b|\b\d+ failed\b|AssertionError|\bnot ok\b|\u2715|\bFAIL\b/

const INT = { type: 'integer' }
const STR = { type: 'string' }
const ART = { type: 'object', properties: { path: STR, verdict: STR }, required: ['path', 'verdict'] }
const LIST = { type: 'array', items: STR }
const GATE_RED = { type: 'object', properties: { validate_exit: INT, suite_exit: INT, red_sha: STR, runner_tail: STR, red_files: LIST },
  required: ['validate_exit', 'suite_exit', 'red_sha', 'runner_tail', 'red_files'] }
const GATE_GREEN = { type: 'object', properties: { validate_exit: INT, tdd_exit: INT, suite_exit: INT, runner_tail: STR },
  required: ['validate_exit', 'tdd_exit', 'suite_exit', 'runner_tail'] }
const GATE_FIX = { type: 'object', properties: { ...GATE_GREEN.properties, fix_red: STR, fix_red_files: LIST, new_tests: INT },
  required: [...GATE_GREEN.required, 'fix_red', 'fix_red_files', 'new_tests'] }
const CHECK = { type: 'object', properties: { validate_exit: INT, output_tail: STR }, required: ['validate_exit', 'output_tail'] }
const REVIEW = { type: 'object', properties: { p0: INT, p1: INT, p2: INT, path: STR }, required: ['p0', 'p1', 'p2', 'path'] }
const QA = { type: 'object', properties: { verdict: { type: 'string', enum: ['PASS', 'FAIL', 'PASS_WITH_CONCERNS'] }, path: STR },
  required: ['verdict', 'path'] }
const VERIFY = { type: 'object', properties: { verified: INT, unverified: INT, contradicted: INT,
  blocking: { type: 'array', items: STR }, path: STR }, required: ['verified', 'unverified', 'contradicted', 'blocking', 'path'] }

// ---- Arguments ---------------------------------------------------------------------------
const A = args || {}
const REQUIRED = ['repo', 'feat_id', 'task_id', 'spec_path', 'mini_spec', 'test_cmd', 'run_dir', 'golden_ref']
const missing = REQUIRED.filter((k) => typeof A[k] !== 'string' || !A[k].trim())
if (missing.length) {
  return { status: 'escalate', stage: 'args', reason: `missing args: ${missing.join(', ')}`,
    artifacts: {}, red_sha: null, counts: null, open_items: [] }
}
const T = A.task_id
const D = `${A.run_dir}/${T}`
const FULL = (A.vibe_level || 'full') !== 'light'
const ARCH = A.arch_needed !== false
const LIVE = A.live_target || A.test_cmd
const artifacts = {
  arch: ARCH ? `${D}-arch.md` : null,
  acceptance: `${D}-acceptance-tests.md`,
  ready: `${D}-ready-for-review.md`,
  review: `${D}-review-findings.md`,
  c1: `${D}-cycle-1.md`,
  c2: FULL ? `${D}-cycle-2.md` : null,
  verification: `${D}-verification.md`,
}
const REL_RUN = A.run_dir.startsWith(`${A.repo}/`) ? `${A.run_dir.slice(A.repo.length + 1)}/` : null
const open_items = []
let red_sha = null
let counts = null

// Purpose: build the common return value for an N=1 escalation.
// Usage:   return escalate('GREEN', 'GATE-GREEN failed twice: tdd_exit=1', lastGate)
// Gotchas: the session turns this into AskUserQuestion, or a partial result when headless.
const escalate = (stage, reason, last) =>
  ({ status: 'escalate', stage, reason, last: last || null, artifacts, red_sha, counts, open_items })

// ---- Prompt builders ---------------------------------------------------------------------
const REQ_MAP = A.req_map
  ? JSON.stringify(A.req_map)
  : `(not supplied) Build it yourself from ${A.spec_path} and the task text: {"task_id":"${T}","requirements":[{"req_id","what","done_when","escalate_if","source"}]}, every value a non-empty string`
const ESCALATE_IF = A.escalate_if ||
  'spec ambiguity, a missing dependency, an interface conflict, or any step you cannot do without guessing'

// Purpose: tell an agent to load a lead-orchestrator template from disk and fill its placeholders.
// Usage:   fromTemplate('qa-prompt.md', {QA_PHASE: 'cycle-1', ...}, 'extra instructions')
// Gotchas: templates stay single-source in skills/lead-orchestrator; this only lists the values.
function fromTemplate(name, values, extra) {
  const base = { TASK_ID: T, MODE: 'feature', RUN_DIR: A.run_dir, SPEC_PATH: A.spec_path,
    ARCH_DESIGN_PATH: artifacts.arch || 'N/A', REQUIREMENT_MAP_JSON: REQ_MAP,
    ESCALATION_CONDITIONS: ESCALATE_IF, TASK_DESCRIPTION: A.mini_spec }
  const all = Object.assign(base, values)
  return [
    `Read ${TPL}/${name} with the Read tool. It is your complete instruction set.`,
    'Substitute these placeholder values everywhere they appear, then follow the template exactly:',
    ...Object.keys(all).map((k) => `- {${k}} = ${all[k]}`),
    `Work in the repository at ${A.repo}. Feature ${A.feat_id}.`,
    extra || '',
    'Your structured output is your digest. The full output goes to the artifact file on disk.',
  ].join('\n')
}

const qaPrompt = (phase, role, inputs, extra) =>
  fromTemplate('qa-prompt.md', { QA_PHASE: phase, QA_GOVERNANCE_ROLE: role, PHASE_INPUTS: inputs, LIVE_TARGET: LIVE }, extra)

// The template's bold `**ReviewCommit:**` line fails validate-artifact.sh, and coders that typed
// SHAs from memory failed verify-tdd-evidence.sh (tip-001 T-001, T-002, T-004). These rules win.
const ARTIFACT_RULES = [
  `ARTIFACT RULES (the gates check these exactly; they override the template): in ${artifacts.ready} write the review line`,
  'as plain text `ReviewCommit: <40-hex sha>`, with no bold or other markup between the colon and the SHA.',
  'Copy every SHA from `git log --format=%H` output; never type, shorten-then-expand or guess a SHA.',
  'Check each SHA with `git cat-file -e <sha>^{commit}` before you write it.',
].join(' ')
const FIX_RED_RULE = [
  'FIX RED FIRST: before any code change, commit new failing tests (test files only) that reproduce each finding.',
  'Run the suite and confirm they fail on an assertion. Then add the line `FixRed: <sha>` (that commit, full SHA) to',
  `${artifacts.ready}. Only when every fix is docs or config with no testable behaviour, write \`FixRed: TDD-EXEMPT <reason>\`.`,
].join(' ')

// Purpose: build the coder prompt for the first GREEN attempt, a GREEN retry, or a findings fix.
// Usage:   coderPrompt('')  ·  coderPrompt(gateReason)  ·  coderPrompt('Fix every P0...', true)
// Gotchas: a findings fix (fix=true) must start with a FixRed commit; the fix gate checks it.
const coderPrompt = (note, fix) => fromTemplate('coder-prompt.md',
  { ACCEPTANCE_TESTS_RED_SHA: red_sha, ROOT_CAUSE: 'N/A (feature mode)' },
  [ARTIFACT_RULES,
    note ? `FIX ROUND. The orchestrator gate rejected the previous attempt for this reason: ${note}\nFix the cause, keep the TDD commit order, and rewrite ${artifacts.ready}.` : '',
    fix ? FIX_RED_RULE : ''].filter(Boolean).join('\n'))

const archPrompt = (note) => [
  `You are the ARCHITECT for ${T} (feature mode, ${A.feat_id}). Design only. Do not write code or tests.`,
  '## Mandatory Context',
  `- **Spec:** ${A.spec_path}. Read it first.  **Repo:** ${A.repo}  **Output file:** ${artifacts.arch}`,
  `- **Task:** ${A.mini_spec}`,
  '## Requirement Map', '```json', REQ_MAP, '```',
  '## Constraints',
  `- Name every file to create or change, the interfaces, the data-model changes and the test seams. Escalate if: ${ESCALATE_IF}.`,
  '- Write the full design to the output file. Mark anything you could not confirm in the code as UNVERIFIED.',
  note ? `- Previous attempt problem: ${note}` : '',
].join('\n')

const gateRedPrompt = (n) => [
  `MECHANICAL GATE for ${T}. Run the commands below exactly, in order, from ${A.repo}. Do not edit, fix or commit anything.`,
  `1. mkdir -p ${A.run_dir}/runs`,
  `2. bash ${SCRIPTS}/validate-artifact.sh ${artifacts.acceptance} ; echo validate_exit=$?`,
  `3. ( ${A.test_cmd} ) > ${A.run_dir}/runs/${T}-red-${n}-$(date +%Y%m%dT%H%M%S).txt 2>&1 ; echo suite_exit=$?`,
  `4. perl -ne 'print qq($1\\n) if /RED Commit:\\**\\s*([0-9a-f]{7,40})/' ${artifacts.acceptance} | head -1`,
  '5. If step 4 printed a SHA, run: git cat-file -e <sha>^{commit} ; echo exists=$? . If exists is not 0, or step 4 printed nothing, red_sha is the empty string.',
  '6. If red_sha is not empty, run: git diff-tree --no-commit-id --name-only -r <red_sha> . red_files = every printed path; else red_files = [].',
  '7. runner_tail = the last 20 lines of the runs file from step 3.',
  'Report the exit codes exactly as printed. Never guess a value.',
].join('\n')

const gateGreenLines = (n) => [
  `MECHANICAL GATE for ${T}. Run the commands below exactly, in order, from ${A.repo}. Do not edit, fix or commit anything.`,
  `1. mkdir -p ${A.run_dir}/runs`,
  `2. bash ${SCRIPTS}/validate-artifact.sh ${artifacts.ready} ; echo validate_exit=$?`,
  `3. bash ${SCRIPTS}/verify-tdd-evidence.sh ${artifacts.ready} ; echo tdd_exit=$?`,
  `4. ( ${A.test_cmd} ) > ${A.run_dir}/runs/${T}-green-${n}-$(date +%Y%m%dT%H%M%S).txt 2>&1 ; echo suite_exit=$?`,
  '5. runner_tail = the last 20 lines of the runs file from step 4, plus any FAIL lines from steps 2 and 3.',
  'Report the exit codes exactly as printed. Never guess a value.',
]
const gateGreenPrompt = (n) => gateGreenLines(n).join('\n')

// Purpose: GATE-GREEN after a findings fix, plus the FixRed checks (fake RED in tip-001 1f77f88).
// Usage:   agent(gateFixPrompt('fix-review'), {..., schema: GATE_FIX})
// Gotchas: new_tests counts added test cases or assertions; a moved helper file counts 0.
const gateFixPrompt = (n) => [
  ...gateGreenLines(n).slice(0, -1),
  `6. perl -ne 'print qq($1\\n) if /^\\**FixRed:\\**\\s*(\\S+)/' ${artifacts.ready} | tail -1 . fix_red = the printed word, or the empty string.`,
  '7. If fix_red is a hex SHA: fix_red_files = every path printed by git diff-tree --no-commit-id --name-only -r <fix_red> ;',
  `   new_tests = the number printed by: git show --format= <fix_red> | perl -ne '$n++ if /^\\+\\s*((async\\s+)?def test_|it\\(|test\\(|func Test|#\\[test\\]|assert\\b|expect\\(|self\\.assert)/; END{print $n+0}'`,
  '   Otherwise fix_red_files = [] and new_tests = 0.',
  ...gateGreenLines(n).slice(-1),
].join('\n')

const checkPrompt = (path) => [
  `MECHANICAL CHECK for ${T}. Do not edit or fix anything.`,
  `Run from ${A.repo}: bash ${SCRIPTS}/validate-artifact.sh ${path} ; echo validate_exit=$?`,
  'output_tail = the full printed output. Report the exit code exactly as printed.',
].join('\n')

const reviewPrompt = (note) => [
  'GOVERNANCE_EXEMPT (garry-review inline, lead-orchestrator2 feature mode)',
  `You are the GARRY-REVIEW reviewer for ${T} in ${A.repo}. Use the garry-review skill in agent mode (--agent) if it loads.`,
  `Review scope: git diff ${red_sha}^..HEAD (acceptance tests plus implementation). Spec: ${A.spec_path}. Coder artifact: ${artifacts.ready}.`,
  'Lenses: Architecture, Code Quality, Tests, Performance. Classify every finding P0, P1 or P2 with file:line.',
  `Write the full findings to ${artifacts.review} with a ## Findings section and a ## Summary section. If there are none, write: no findings.`,
  'You report. You never edit code. Return the P0, P1 and P2 counts and the artifact path.',
  note ? `Previous attempt problem: ${note}` : '',
].join('\n')

// ---- Gate predicates ---------------------------------------------------------------------
// Purpose: list the paths in a RED commit that are not test code or run-dir artifacts.
// Usage:   const bad = nonTestFiles(g.red_files)  ->  [] when the commit is test-only
// Gotchas: a missing or empty list returns ['(no files)'], so an empty commit never passes.
function nonTestFiles(files) {
  if (!Array.isArray(files) || !files.length) return ['(no files)']
  return files.filter((f) => !TEST_PATH_RE.test(f) && !(REL_RUN && f.startsWith(REL_RUN)))
}

// Purpose: decide whether GATE-RED passed; return '' on pass, else the reason text.
// Usage:   const why = redFailure(gateResult)
// Gotchas: all conditions are required; a null gate (dead agent) is a failure. "Right reason"
//          means the tail shows an assertion failure and no collection/import/syntax error.
function redFailure(g) {
  if (!g) return 'the GATE-RED agent returned nothing'
  if (g.validate_exit !== 0) return `validate_exit=${g.validate_exit}: the acceptance-tests artifact is invalid: ${g.runner_tail}`
  if (g.suite_exit === 0) return 'suite_exit=0: the acceptance tests already pass. Strengthen them so each fails on a real assertion.'
  const tail = String(g.runner_tail || '')
  if (NOT_RUN_RE.test(tail) || !ASSERT_FAIL_RE.test(tail)) {
    return `the tests did not fail on an assertion (collection, import or syntax error, or no failed test in the output): ${tail.slice(-400)} ` +
      'Make every test file import cleanly (import the module inside each test, or run the script with subprocess) so each test fails on a real assertion.'
  }
  if (!SHA_RE.test(String(g.red_sha || ''))) return `red_sha "${g.red_sha}" is missing or not a 7-40 hex commit SHA. Commit the tests and record the RED Commit line.`
  const bad = nonTestFiles(g.red_files)
  if (bad.length) return `the RED commit ${g.red_sha} must touch only test files, but it touches: ${bad.join(', ')}. Move non-test files out of the RED commit.`
  return ''
}

// Purpose: decide whether the FixRed part of a fix gate passed; return '' on pass, else the reason.
// Usage:   const why = greenFailure(g) || fixRedFailure(g, 'review')
// Gotchas: TDD-EXEMPT passes but is logged in open_items so the verifier and the report name it.
function fixRedFailure(g, stage) {
  const fr = String(g.fix_red || '').trim()
  if (/^TDD-EXEMPT$/i.test(fr)) {
    open_items.push(`${stage} fix round declared FixRed: TDD-EXEMPT (no failing test first): see ${artifacts.ready}`)
    return ''
  }
  if (!SHA_RE.test(fr)) return `no valid FixRed line in ${artifacts.ready}: commit failing tests for the fix first, then write FixRed: <sha>`
  const bad = nonTestFiles(g.fix_red_files)
  if (bad.length) return `the FixRed commit ${fr} must touch only test files, but it touches: ${bad.join(', ')}`
  if (!(g.new_tests > 0)) return `the FixRed commit ${fr} adds no new test case or assertion (a refactor labelled RED)`
  return ''
}

// Purpose: decide whether GATE-GREEN passed; return '' on pass, else the reason text.
// Usage:   const why = greenFailure(gateResult)
// Gotchas: validate, TDD evidence and the suite must all exit 0.
function greenFailure(g) {
  if (!g) return 'the GATE-GREEN agent returned nothing'
  const bad = ['validate_exit', 'tdd_exit', 'suite_exit'].filter((k) => g[k] !== 0)
  return bad.length ? `${bad.map((k) => `${k}=${g[k]}`).join(', ')}: ${g.runner_tail}` : ''
}

const blocked = (r) => r && /^BLOCKED/i.test(String(r.verdict || ''))
const isBlocking = (v) => v.contradicted > 0 || v.blocking.length > 0

// Purpose: run a producer, then a haiku artifact check; re-spawn the producer once on failure.
// Usage:   const out = await produceChecked((note, n) => <agent call>, path, 'review', 'Review')
// Gotchas: returns {r} on success or {fail} with the reason. The path is the canonical one,
//          never the path the producer reports, so a wrong self-report cannot pass the check.
async function produceChecked(make, path, name, phaseName) {
  let note = ''
  for (let n = 1; n <= 2; n++) {
    const r = await make(note, n)
    if (!r) { note = 'the previous agent returned nothing, so the artifact may be missing'; continue }
    const c = await agent(checkPrompt(path), { label: `check:${name}${n > 1 ? '-redo' : ''}`, phase: phaseName,
      model: 'haiku', effort: 'low', schema: CHECK })
    if (c && c.validate_exit === 0) return { r }
    note = `artifact check failed for ${path}: ${c ? c.output_tail : 'the check agent returned nothing'}`
  }
  return { fail: note }
}

// Purpose: one coder fix round followed by GATE-GREEN; the N=1 fix budget for a later stage.
// Usage:   const why = await fixAndRegreen('review', 'Fix every P0 and P1 in ...'); if (why) escalate
// Gotchas: returns '' when the fix passed GATE-GREEN and the FixRed checks, else the failure reason.
async function fixAndRegreen(stage, note) {
  const c = await agent(coderPrompt(note, true), { label: `coder:fix-${stage}`, phase: 'GREEN', model: 'sonnet', schema: ART })
  if (!c) return `the coder fix after ${stage} returned nothing`
  if (blocked(c)) return `the coder fix after ${stage} reported BLOCKED`
  const g = await agent(gateFixPrompt(`fix-${stage}`), { label: `gate-green:after-fix-${stage}`, phase: 'GREEN',
    model: 'haiku', effort: 'low', schema: GATE_FIX })
  return greenFailure(g) || fixRedFailure(g, stage)
}

// ---- Step 1: architect (optional) --------------------------------------------------------
if (ARCH) {
  phase('Design')
  let arch = await agent(archPrompt(''), { label: 'arch', phase: 'Design', model: 'sonnet', schema: ART })
  if (!arch) arch = await agent(archPrompt('the previous architect returned nothing'), { label: 'arch:retry', phase: 'Design', model: 'sonnet', schema: ART })
  if (!arch) return escalate('Design', 'the architect returned nothing twice')
}

// ---- Steps 2-3: QA acceptance-red, then GATE-RED -----------------------------------------
phase('RED')
let red = null
let redWhy = ''
for (let n = 1; n <= 2 && !red; n++) {
  const extra = redWhy ? `RETRY. The RED gate rejected the previous attempt: ${redWhy}` : ''
  const qa = await agent(qaPrompt('acceptance-red', 'qa-test-writer', 'none', extra),
    { label: n === 1 ? 'qa-red' : 'qa-red:retry', phase: 'RED', model: 'sonnet', schema: ART })
  if (!qa) { redWhy = 'the QA agent returned nothing, so the artifact may be missing'; continue }
  const g = await agent(gateRedPrompt(n), { label: n === 1 ? 'gate-red' : 'gate-red:retry', phase: 'RED',
    model: 'haiku', effort: 'low', schema: GATE_RED })
  redWhy = redFailure(g)
  if (!redWhy) red = g
}
if (!red) return escalate('RED', `RED gate failed twice: ${redWhy}`)
red_sha = red.red_sha
log(`${T}: RED confirmed at ${red_sha}`)

// ---- Steps 4-5: coder, then GATE-GREEN (one fix round) -----------------------------------
phase('GREEN')
let greenWhy = ''
let green = false
for (let n = 1; n <= 2 && !green; n++) {
  const c = await agent(coderPrompt(greenWhy), { label: n === 1 ? 'coder' : 'coder:fix-green', phase: 'GREEN', model: 'sonnet', schema: ART })
  if (!c) { greenWhy = 'the previous coder returned nothing. Finish the task and write the artifact.'; continue }
  if (blocked(c)) return escalate('GREEN', `coder reported ${c.verdict}`, c)
  const g = await agent(gateGreenPrompt(n), { label: n === 1 ? 'gate-green' : 'gate-green:retry', phase: 'GREEN',
    model: 'haiku', effort: 'low', schema: GATE_GREEN })
  greenWhy = greenFailure(g)
  green = !greenWhy
}
if (!green) return escalate('GREEN', `GATE-GREEN failed twice: ${greenWhy}`)
log(`${T}: GREEN gate passed`)

// ---- Step 6: garry-review; P0/P1 -> coder fix -> GATE-GREEN -> review (max 1 loop) -------
phase('Review')
const reviewOnce = async (round) => {
  const out = await produceChecked((note, n) => agent(reviewPrompt(note),
    { label: round === 1 ? (n === 1 ? 'review' : 'review:redo') : 'review:round2', phase: 'Review', model: 'opus', schema: REVIEW }),
    artifacts.review, 'review', 'Review')
  return out
}
let rev = await reviewOnce(1)
if (rev.fail) return escalate('Review', rev.fail)
if (rev.r.p0 + rev.r.p1 > 0) {
  const why = await fixAndRegreen('review', `Fix every P0 and P1 finding in ${artifacts.review}.`)
  if (why) return escalate('Review', `fix after review failed GATE-GREEN: ${why}`, rev.r)
  rev = await reviewOnce(2)
  if (rev.fail) return escalate('Review', rev.fail)
  if (rev.r.p0 + rev.r.p1 > 0) return escalate('Review', `P0/P1 remain after one fix loop: p0=${rev.r.p0} p1=${rev.r.p1}`, rev.r)
}
if (rev.r.p2 > 0) open_items.push(`${rev.r.p2} P2 review findings in ${artifacts.review}: add them to docs/backlog.md`)

// ---- Steps 7-8: QA cycle-1, then cycle-2 (full only); FAIL -> fix -> re-run -> escalate --
phase('QA')
const cycleInputs = `${artifacts.ready} + ${artifacts.acceptance}`
const c1Extra = 'Cycle-1: run the suite, write new tests, and try to break the feature.'
const c2Extra = 'Cycle-2: REAL end-to-end tests against the real DB plus regression. Do not re-test cycle-1 bugs.'
// Purpose: run one QA cycle with its artifact check, and one fix round on FAIL.
// Usage:   const out = await qaCycle('c1'); if (out.escalate) return out.escalate
// Gotchas: the fix round passes GATE-GREEN before QA runs again (stricter than re-running QA alone).
async function qaCycle(key) {
  const phaseName = key === 'c1' ? 'cycle-1' : 'cycle-2'
  const extra = key === 'c1' ? c1Extra : c2Extra
  const once = (round) => produceChecked((note, n) => agent(qaPrompt(phaseName, 'qa-tester', cycleInputs,
    [extra, round > 1 ? `Round 2 after a coder fix of the bugs in ${artifacts[key]}.` : '', note ? `Previous attempt problem: ${note}` : ''].join('\n')),
  { label: round === 1 ? (n === 1 ? key : `${key}:redo`) : `${key}:round2`, phase: 'QA', model: 'sonnet', schema: QA }),
  artifacts[key], key, 'QA')
  let out = await once(1)
  if (out.fail) return { escalate: escalate('QA', out.fail) }
  if (out.r.verdict === 'FAIL') {
    const why = await fixAndRegreen(key, `Fix every bug listed in ${artifacts[key]}.`)
    if (why) return { escalate: escalate('QA', `fix after ${phaseName} failed GATE-GREEN: ${why}`, out.r) }
    out = await once(2)
    if (out.fail) return { escalate: escalate('QA', out.fail) }
    if (out.r.verdict === 'FAIL') return { escalate: escalate('QA', `${phaseName} still FAIL after one fix cycle (N=1)`, out.r) }
  }
  if (out.r.verdict === 'PASS_WITH_CONCERNS') open_items.push(`${phaseName} PASS_WITH_CONCERNS: see ${artifacts[key]}`)
  return {}
}
const q1 = await qaCycle('c1')
if (q1.escalate) return q1.escalate
if (FULL) {
  const q2 = await qaCycle('c2')
  if (q2.escalate) return q2.escalate
}

// ---- Step 9: verifier; contradicted/blocking -> one fix -> round 2 -> escalate -----------
phase('Verify')
const verifyInputs = [artifacts.arch, artifacts.acceptance, artifacts.ready, artifacts.review, artifacts.c1, artifacts.c2]
  .filter(Boolean).join(', ')
const verifyExtra = (round, claims) => [
  `GOLDEN REFERENCE (what correct means): ${A.golden_ref}`,
  `USER-FACING TARGET: ${LIVE}. Re-run ${A.test_cmd} yourself. Spec-diff every requirement to file:line.`,
  `Write ${artifacts.verification}.`,
  'Scope lock: check the original ask and its done_when lines only. Put out-of-scope findings in the report as open items.',
  round === 2 ? `ROUND 2 of 2 (final). Re-verify ONLY these fixed claims: ${claims}. Append a ## Round 2 section to the file.` : '',
].join('\n')
const verifyOnce = (round, claims) => produceChecked((note, n) => agent(
  qaPrompt('verify', 'verifier', verifyInputs, verifyExtra(round, claims) + (note ? `\nPrevious attempt problem: ${note}` : '')),
  { label: round === 1 ? (n === 1 ? 'verify' : 'verify:redo') : 'verify:round2', phase: 'Verify', model: 'opus', schema: VERIFY }),
artifacts.verification, 'verify', 'Verify')

let ver = await verifyOnce(1, '')
if (ver.fail) return escalate('Verify', ver.fail)
if (isBlocking(ver.r)) {
  const list = ver.r.blocking.join('; ') || `${ver.r.contradicted} CONTRADICTED claims`
  const why = await fixAndRegreen('verify', `Fix the verifier BLOCKING items in ${artifacts.verification}: ${list}`)
  if (why) return escalate('Verify', `fix after verifier failed GATE-GREEN: ${why}`, ver.r)
  ver = await verifyOnce(2, list)
  if (ver.fail) return escalate('Verify', ver.fail)
  counts = { verified: ver.r.verified, unverified: ver.r.unverified, contradicted: ver.r.contradicted }
  if (isBlocking(ver.r)) return escalate('Verify', `verifier round 2 still blocking: ${ver.r.blocking.join('; ')}`, ver.r)
}
counts = { verified: ver.r.verified, unverified: ver.r.unverified, contradicted: ver.r.contradicted }
if (counts.unverified > 0) open_items.push(`${counts.unverified} UNVERIFIED claims (non-blocking): see ${artifacts.verification}`)
log(`${T}: verified ${counts.verified}, unverified ${counts.unverified}, contradicted ${counts.contradicted}`)
return { status: 'complete', task_id: T, artifacts, red_sha, counts, open_items }
