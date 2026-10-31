export const meta = {
  name: 'lo-feature-close',
  description: 'Whole-feature close: integrated suite, review and QA for stopped tasks, one fix round, feature verifier (max 2 rounds)',
  whenToUse: 'lead-orchestrator2 feature mode, once per feature, ALWAYS after every lo-feature-task launch has returned',
  phases: [
    { title: 'Suite', detail: 'integrated full-suite gate, plus the mutation probe in parallel', model: 'haiku' },
    { title: 'Review', detail: 'garry-review over tasks that did not complete', model: 'opus' },
    { title: 'QA', detail: 'cycle-1 over tasks that did not complete', model: 'sonnet' },
    { title: 'Fix', detail: 'one coder fix round with FixRed, then the fix gate', model: 'sonnet' },
    { title: 'Verify', detail: 'feature verifier over ALL requirements, one fix, round 2 cap', model: 'opus' },
  ],
}
// ABOUTME: Workflow script for lead-orchestrator2 feature mode: the whole-feature closing stage (round 1).
// ABOUTME: Why: in tip-001 every task escalated, no QA ran for any task, and the feature verifier's
// ABOUTME: FAIL (4 CONTRADICTED) got no fix round. This script makes those steps code, not session choice.
// ABOUTME: Mirrors lead-orchestrator's T-ALL stages (review, cycle-1, verifier r1 -> fix -> r2) at feature level.
// ABOUTME: Never returns complete with a hole: any failed gate or remaining blocking item gives partial.
// ABOUTME: Round 2 (pm-login-002): a sonnet mutation probe disables each fix in a scratch copy; a survivor blocks.
// NOTE: every agent call names its model inline. workflow-model-guard.sh checks this lexically.

const TPL = '/Users/yklin/.claude/skills/lead-orchestrator/templates'
const SCRIPTS = '/Users/yklin/.claude/skills/lead-orchestrator/scripts'
const SHA_RE = /^[0-9a-f]{7,40}$/
const TEST_PATH_RE = /(^|\/)(tests?|spec|__tests__)\/|(^|\/)test_[^/]*$|_test\.[^/]+$|\.(test|spec)\.[^/]+$|(^|\/)conftest\.py$/

const INT = { type: 'integer' }
const STR = { type: 'string' }
const LIST = { type: 'array', items: STR }
const ART = { type: 'object', properties: { path: STR, verdict: STR }, required: ['path', 'verdict'] }
const SUITE = { type: 'object', properties: { suite_exit: INT, runner_tail: STR }, required: ['suite_exit', 'runner_tail'] }
const GATE_FIX = { type: 'object', properties: { validate_exit: INT, tdd_exit: INT, suite_exit: INT, runner_tail: STR,
  fix_red: STR, fix_red_files: LIST, new_tests: INT },
  required: ['validate_exit', 'tdd_exit', 'suite_exit', 'runner_tail', 'fix_red', 'fix_red_files', 'new_tests'] }
const CHECK = { type: 'object', properties: { validate_exit: INT, output_tail: STR }, required: ['validate_exit', 'output_tail'] }
const REVIEW = { type: 'object', properties: { p0: INT, p1: INT, p2: INT, path: STR }, required: ['p0', 'p1', 'p2', 'path'] }
const QA = { type: 'object', properties: { verdict: { type: 'string', enum: ['PASS', 'FAIL', 'PASS_WITH_CONCERNS'] }, path: STR },
  required: ['verdict', 'path'] }
const PROBE = { type: 'object', properties: { checked: INT, survivors: LIST, path: STR }, required: ['checked', 'survivors', 'path'] }
const VERIFY = { type: 'object', properties: { verified: INT, unverified: INT, contradicted: INT,
  blocking: LIST, path: STR }, required: ['verified', 'unverified', 'contradicted', 'blocking', 'path'] }

// ---- Arguments ---------------------------------------------------------------------------
const A = args || {}
const REQUIRED = ['repo', 'feat_id', 'spec_path', 'run_dir', 'base_sha', 'test_cmd', 'golden_ref']
const missing = REQUIRED.filter((k) => typeof A[k] !== 'string' || !A[k].trim())
if (!missing.includes('base_sha') && !SHA_RE.test(A.base_sha)) missing.push('base_sha (7-40 hex commit SHA)')
const REQS = Array.isArray(A.feature_reqs) ? A.feature_reqs.filter((q) => q && q.req_id) : []
const TASKS = Array.isArray(A.tasks) ? A.tasks.filter((t) => t && t.task_id) : []
if (!REQS.length) missing.push('feature_reqs (from lo-feature-plan.js)')
if (!TASKS.length) missing.push('tasks (one {task_id, status, stage?, reason?} per lo-feature-task return)')
if (missing.length) {
  return { status: 'escalate', stage: 'args', reason: `missing args: ${missing.join(', ')}`, artifacts: {}, counts: null, open_items: [], holes: [] }
}
const T = 'T-ALL'
const D = `${A.run_dir}/${T}`
const LIVE = A.live_target || A.test_cmd
const REL_RUN = A.run_dir.startsWith(`${A.repo}/`) ? `${A.run_dir.slice(A.repo.length + 1)}/` : null
const artifacts = { review: `${D}-review-findings.md`, c1: `${D}-cycle-1.md`, ready: `${D}-ready-for-review.md`,
  verification: `${D}-verification.md`, probe: `${D}-mutation-probe.md` }
const open_items = []
const holes = []
let counts = null
const REQ_MAP = JSON.stringify({ task_id: T, requirements: REQS })
const uncovered = TASKS.filter((t) => t.status !== 'complete')
const scopeLine = uncovered.map((t) => `${t.task_id} (stopped at ${t.stage || 'unknown stage'}: ${t.reason || 'no reason given'})`).join('; ')

// Purpose: build the return value; partial whenever a hole exists, complete only when clean.
// Usage:   return finish()
// Gotchas: the session reports partial with every hole named; it never upgrades it to done.
const finish = () => ({ status: holes.length ? 'partial' : 'complete', task_id: T, artifacts, counts, open_items, holes })
const escalate = (stage, reason) => ({ status: 'escalate', stage, reason, task_id: T, artifacts, counts, open_items, holes })

// ---- Prompt builders ---------------------------------------------------------------------
// Purpose: tell an agent to load a lead-orchestrator template from disk and fill its placeholders.
// Usage:   fromTemplate('qa-prompt.md', {QA_PHASE: 'cycle-1', ...}, 'extra instructions')
// Gotchas: same contract as lo-feature-task.js (workflow files cannot import each other).
function fromTemplate(name, values, extra) {
  const base = { TASK_ID: T, MODE: 'feature', RUN_DIR: A.run_dir, SPEC_PATH: A.spec_path, ARCH_DESIGN_PATH: 'N/A',
    REQUIREMENT_MAP_JSON: REQ_MAP, ESCALATION_CONDITIONS: 'spec ambiguity, a missing dependency, or any step you cannot do without guessing',
    TASK_DESCRIPTION: `Close feature ${A.feat_id}: every requirement of ${A.spec_path} works in the integrated build.` }
  const all = Object.assign(base, values)
  return [
    `Read ${TPL}/${name} with the Read tool. It is your complete instruction set.`,
    'Substitute these placeholder values everywhere they appear, then follow the template exactly:',
    ...Object.keys(all).map((k) => `- {${k}} = ${all[k]}`),
    `Work in the repository at ${A.repo}. Feature ${A.feat_id}. Feature diff base: ${A.base_sha}.`,
    extra || '',
    'Your structured output is your digest. The full output goes to the artifact file on disk.',
  ].join('\n')
}
const qaPrompt = (phase, role, inputs, extra) =>
  fromTemplate('qa-prompt.md', { QA_PHASE: phase, QA_GOVERNANCE_ROLE: role, PHASE_INPUTS: inputs, LIVE_TARGET: LIVE }, extra)

const ARTIFACT_RULES = [
  `ARTIFACT RULES (the gates check these exactly; they override the template): in ${artifacts.ready} write the review line`,
  'as plain text `ReviewCommit: <40-hex sha>`, with no bold or other markup between the colon and the SHA.',
  'Copy every SHA from `git log --format=%H` output; never type, shorten-then-expand or guess a SHA.',
  'Check each SHA with `git cat-file -e <sha>^{commit}` before you write it.',
].join(' ')
const FIX_RED_RULE = [
  'FIX RED FIRST: before any code change, commit new failing tests (test files only) that reproduce each item.',
  'Run the suite and confirm they fail on an assertion. Then add the line `FixRed: <sha>` (that commit, full SHA) to',
  `${artifacts.ready}. Only when every fix is docs or config with no testable behaviour, write \`FixRed: TDD-EXEMPT <reason>\`.`,
].join(' ')
const coderPrompt = (items) => fromTemplate('coder-prompt.md',
  { ACCEPTANCE_TESTS_RED_SHA: 'N/A (feature close fix round: see FixRed)', ROOT_CAUSE: 'N/A (feature mode)' },
  [`FEATURE FIX ROUND for ${A.feat_id}. Fix every item below in the integrated build, then run the FULL suite: ${A.test_cmd}`,
    `- ${items}`, ARTIFACT_RULES, FIX_RED_RULE].join('\n'))

const suitePrompt = () => [
  `MECHANICAL GATE for ${A.feat_id} (integrated suite). Run from ${A.repo}. Do not edit, fix or commit anything.`,
  `1. mkdir -p ${A.run_dir}/runs`,
  `2. ( ${A.test_cmd} ) > ${A.run_dir}/runs/${T}-suite-$(date +%Y%m%dT%H%M%S).txt 2>&1 ; echo suite_exit=$?`,
  '3. runner_tail = the last 20 lines of the runs file from step 2.',
  'Report the exit code exactly as printed. Never guess a value.',
].join('\n')

const gateFixPrompt = (n) => [
  `MECHANICAL GATE for ${A.feat_id} (fix round ${n}). Run the commands below exactly, in order, from ${A.repo}. Do not edit, fix or commit anything.`,
  `1. mkdir -p ${A.run_dir}/runs`,
  `2. bash ${SCRIPTS}/validate-artifact.sh ${artifacts.ready} ; echo validate_exit=$?`,
  `3. bash ${SCRIPTS}/verify-tdd-evidence.sh ${artifacts.ready} ; echo tdd_exit=$?`,
  `4. ( ${A.test_cmd} ) > ${A.run_dir}/runs/${T}-fix-${n}-$(date +%Y%m%dT%H%M%S).txt 2>&1 ; echo suite_exit=$?`,
  '5. runner_tail = the last 20 lines of the runs file from step 4, plus any FAIL lines from steps 2 and 3.',
  `6. perl -ne 'print qq($1\\n) if /^\\**FixRed:\\**\\s*(\\S+)/' ${artifacts.ready} | tail -1 . fix_red = the printed word, or the empty string.`,
  '7. If fix_red is a hex SHA: fix_red_files = every path printed by git diff-tree --no-commit-id --name-only -r <fix_red> ;',
  `   new_tests = the number printed by: git show --format= <fix_red> | perl -ne '$n++ if /^\\+\\s*((async\\s+)?def test_|it\\(|test\\(|func Test|#\\[test\\]|assert\\b|expect\\(|self\\.assert)/; END{print $n+0}'`,
  '   Otherwise fix_red_files = [] and new_tests = 0.',
  'Report the exit codes exactly as printed. Never guess a value.',
].join('\n')

const checkPrompt = (path) => [
  `MECHANICAL CHECK for ${A.feat_id}. Do not edit or fix anything.`,
  `Run from ${A.repo}: bash ${SCRIPTS}/validate-artifact.sh ${path} ; echo validate_exit=$?`,
  'output_tail = the full printed output. Report the exit code exactly as printed.',
].join('\n')

const reviewPrompt = (note) => [
  'GOVERNANCE_EXEMPT (garry-review inline, lead-orchestrator2 feature close)',
  `You are the GARRY-REVIEW reviewer for ${A.feat_id} in ${A.repo}. Use the garry-review skill in agent mode (--agent) if it loads.`,
  `Tasks in scope: ${scopeLine}`,
  `These tasks stopped before their own review. Review their commits in git log ${A.base_sha}..HEAD (tests plus implementation). Spec: ${A.spec_path}.`,
  'Lenses: Architecture, Code Quality, Tests, Performance, and spec coverage. Classify every finding P0, P1 or P2 with file:line.',
  `Write the full findings to ${artifacts.review} with a ## Findings section and a ## Summary section. If there are none, write: no findings.`,
  'You report. You never edit code. Return the P0, P1 and P2 counts and the artifact path.',
  note ? `Previous attempt problem: ${note}` : '',
].join('\n')

// Purpose: mutation probe prompt: disable the core of each fix in a scratch copy; a test must fail.
// Usage:   probePrompt('') for every requirement, or probePrompt('REQ-01 ...; REQ-03 ...') to re-probe survivors
// Gotchas: pm-login-002: B's central MFA gate could be disabled with all 53 tests green. Never edit the real repo.
const probePrompt = (only) => [
  `MUTATION PROBE for ${A.feat_id}. Do not edit, fix or commit anything in ${A.repo}.`,
  `1. Copy the repo to a scratch dir: S=$(mktemp -d); rsync -a --exclude .git ${A.repo}/ "$S"/ . Work only in "$S".`,
  `2. Baseline: run the test command in "$S" unchanged: ${A.test_cmd} (if it cds into ${A.repo}, cd into "$S" instead).`,
  '   Record the failing test names. Those do not count below.',
  only ? `3. Re-probe ONLY these mutants, which survived before the fix round: ${only}`
    : `3. Find the core change of each fix in git diff ${A.base_sha}..HEAD (non-test files), one per requirement (${REQS.map((q) => q.req_id).join(', ')}), max 8.`,
  '   For each one: disable that core only (make the new guard take the old branch, return the old value, or skip the new call).',
  '   A change to a comment, a log line or a name does not count. Run the test command. KILLED = a test that passed in the',
  '   baseline now fails. SURVIVED = no new failure. Undo the change before the next mutant.',
  `4. rm -rf "$S". Write the table (req_id, file:line, what you disabled, result) to ${artifacts.probe}.`,
  '5. Return checked (mutants run), survivors (one line each: "<req_id> <file:line>: <what you disabled>: no test failed"), path.',
].join('\n')

// ---- Gate predicates ---------------------------------------------------------------------
// Purpose: list the paths in a RED commit that are not test code or run-dir artifacts.
// Usage:   const bad = nonTestFiles(g.fix_red_files)  ->  [] when the commit is test-only
// Gotchas: a missing or empty list returns ['(no files)'], so an empty commit never passes.
function nonTestFiles(files) {
  if (!Array.isArray(files) || !files.length) return ['(no files)']
  return files.filter((f) => !TEST_PATH_RE.test(f) && !(REL_RUN && f.startsWith(REL_RUN)))
}

// Purpose: decide whether a fix gate passed (GREEN parts plus FixRed); '' on pass, else the reason.
// Usage:   const why = fixFailure(g, 'verify')
// Gotchas: TDD-EXEMPT passes but is logged in open_items so the report names it.
function fixFailure(g, stage) {
  if (!g) return 'the fix gate agent returned nothing'
  const bad = ['validate_exit', 'tdd_exit', 'suite_exit'].filter((k) => g[k] !== 0)
  if (bad.length) return `${bad.map((k) => `${k}=${g[k]}`).join(', ')}: ${g.runner_tail}`
  const fr = String(g.fix_red || '').trim()
  if (/^TDD-EXEMPT$/i.test(fr)) {
    open_items.push(`${stage} fix round declared FixRed: TDD-EXEMPT (no failing test first): see ${artifacts.ready}`)
    return ''
  }
  if (!SHA_RE.test(fr)) return `no valid FixRed line in ${artifacts.ready}`
  const nt = nonTestFiles(g.fix_red_files)
  if (nt.length) return `the FixRed commit ${fr} must touch only test files, but it touches: ${nt.join(', ')}`
  if (!(g.new_tests > 0)) return `the FixRed commit ${fr} adds no new test case or assertion (a refactor labelled RED)`
  return ''
}
const isBlocking = (v) => v.contradicted > 0 || v.blocking.length > 0

// Purpose: run a producer, then a haiku artifact check; re-spawn the producer once on failure.
// Usage:   const out = await produceChecked((note, n) => <agent call>, path, 'review', 'Review')
// Gotchas: returns {r} on success or {fail}; the path is canonical, never the producer's report.
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

// Purpose: one coder fix round over a list of items, then the fix gate on the full suite.
// Usage:   const why = await fixRound('close', items.join('\n- ')); if (why) holes.push(...)
// Gotchas: one round per call site (N=1); the caller records a failure as a hole and goes on.
async function fixRound(stage, items) {
  phase('Fix')
  const c = await agent(coderPrompt(items), { label: `coder:fix-${stage}`, phase: 'Fix', model: 'sonnet', schema: ART })
  if (!c) return `the coder fix (${stage}) returned nothing`
  if (/^BLOCKED/i.test(String(c.verdict || ''))) return `the coder fix (${stage}) reported ${c.verdict}`
  const g = await agent(gateFixPrompt(stage), { label: `gate-green:after-fix-${stage}`, phase: 'Fix',
    model: 'haiku', effort: 'low', schema: GATE_FIX })
  return fixFailure(g, stage)
}

const probeAgent = (only, label) => agent(probePrompt(only), { label, phase: 'Suite', model: 'sonnet', schema: PROBE })
const survivorsOf = (p) => (p && Array.isArray(p.survivors) ? p.survivors.filter(Boolean) : [])

// ---- Step 1: integrated suite and mutation probe (parallel; the probe uses a scratch copy) --
phase('Suite')
let [suite, probe] = await parallel([
  () => agent(suitePrompt(), { label: 'gate-suite', phase: 'Suite', model: 'haiku', effort: 'low', schema: SUITE }),
  () => probeAgent('', 'probe'),
])
if (!suite) suite = await agent(suitePrompt(), { label: 'gate-suite:retry', phase: 'Suite', model: 'haiku', effort: 'low', schema: SUITE })
if (!suite) return escalate('Suite', 'the integrated suite gate returned nothing twice')
if (!probe) probe = await probeAgent('', 'probe:retry')
if (!probe) holes.push('the mutation probe returned nothing twice: test strength is unchecked')
const fixes = []
if (suite.suite_exit !== 0) fixes.push(`The integrated full suite fails (suite_exit=${suite.suite_exit}): ${suite.runner_tail}`)
const survivors = survivorsOf(probe)
if (survivors.length) fixes.push(`Mutation probe (${artifacts.probe}): these mutants survived, so no test checks the fix. Add a test that fails when each is disabled: ${survivors.join('; ')}`)
for (const t of uncovered) fixes.push(`${t.task_id} stopped at stage ${t.stage || 'unknown'}: ${t.reason || 'no reason given'}`)

// ---- Step 2: review and QA C1 for tasks that stopped before their own --------------------
if (uncovered.length) {
  phase('Review')
  const rv = await produceChecked((note, n) => agent(reviewPrompt(note),
    { label: n === 1 ? 'review' : 'review:redo', phase: 'Review', model: 'opus', schema: REVIEW }), artifacts.review, 'review', 'Review')
  if (rv.fail) holes.push(`feature review: ${rv.fail}`)
  else if (rv.r.p0 + rv.r.p1 > 0) fixes.push(`Fix every P0 and P1 finding in ${artifacts.review} (p0=${rv.r.p0}, p1=${rv.r.p1}).`)
  if (!rv.fail && rv.r.p2 > 0) open_items.push(`${rv.r.p2} P2 review findings in ${artifacts.review}: add them to docs/backlog.md`)

  phase('QA')
  const inputs = uncovered.map((t) => `${A.run_dir}/${t.task_id}-ready-for-review.md + ${A.run_dir}/${t.task_id}-acceptance-tests.md`).join(', ')
  const q = await produceChecked((note, n) => agent(qaPrompt('cycle-1', 'qa-tester', inputs,
    [`Cycle-1 for the tasks that stopped early: ${scopeLine}. Run ${A.test_cmd}, write new tests, and try to break the integrated feature.`,
      note ? `Previous attempt problem: ${note}` : ''].join('\n')),
  { label: n === 1 ? 'c1' : 'c1:redo', phase: 'QA', model: 'sonnet', schema: QA }), artifacts.c1, 'c1', 'QA')
  if (q.fail) holes.push(`feature QA cycle-1: ${q.fail}`)
  else if (q.r.verdict === 'FAIL') fixes.push(`Fix every bug listed in ${artifacts.c1}.`)
  else if (q.r.verdict === 'PASS_WITH_CONCERNS') open_items.push(`cycle-1 PASS_WITH_CONCERNS: see ${artifacts.c1}`)
}

// ---- Step 3: one combined fix round before the verifier ----------------------------------
if (fixes.length) {
  const why = await fixRound('close', fixes.join('\n- '))
  if (why) holes.push(`the fix round before the verifier failed: ${why}`)
}
if (survivors.length) {
  const re = await probeAgent(survivors.join('; '), 'probe:recheck')
  const left = re ? survivorsOf(re) : survivors
  if (left.length) holes.push(`surviving mutant(s) after the fix round (tests do not check the fix): ${left.join('; ')}`)
}

// ---- Step 4: feature verifier over ALL requirements; one fix; round 2 cap -----------------
phase('Verify')
const verifyInputs = TASKS.map((t) => `${A.run_dir}/${t.task_id}-*.md`).concat(uncovered.length ? [artifacts.review, artifacts.c1] : [])
  .concat(probe ? [artifacts.probe] : []).join(', ')
const verifyExtra = (round, claims) => [
  `GOLDEN REFERENCE (what correct means): ${A.golden_ref}`,
  `USER-FACING TARGET: ${LIVE}. Re-run the full suite yourself: ${A.test_cmd}`,
  `Spec-diff every requirement in the requirement map (${REQS.map((q) => q.req_id).join(', ')}) to file:line, one verdict per req_id.`,
  `Re-read ${A.spec_path}. A spec requirement that the map lacks and the build misses is BLOCKING; name its spec section.`,
  `Write ${artifacts.verification}.`,
  'Scope lock: check the spec and its done_when lines only. Put out-of-scope findings in the report as open items.',
  round === 2 ? `ROUND 2 of 2 (final). Re-verify ONLY these fixed claims: ${claims}. Append a ## Round 2 section to the file.` : '',
].join('\n')
const verifyOnce = (round, claims) => produceChecked((note, n) => agent(
  qaPrompt('verify', 'verifier', verifyInputs, verifyExtra(round, claims) + (note ? `\nPrevious attempt problem: ${note}` : '')),
  { label: round === 1 ? (n === 1 ? 'verify' : 'verify:redo') : 'verify:round2', phase: 'Verify', model: 'opus', schema: VERIFY }),
artifacts.verification, 'verify', 'Verify')

let ver = await verifyOnce(1, '')
if (ver.fail) { holes.push(`feature verifier: ${ver.fail}`); return finish() }
if (isBlocking(ver.r)) {
  const list = ver.r.blocking.join('; ') || `${ver.r.contradicted} CONTRADICTED claims`
  const why = await fixRound('verify', `Fix the verifier BLOCKING items in ${artifacts.verification}: ${list}`)
  if (why) holes.push(`the fix after the verifier failed: ${why}`)
  const ver2 = await verifyOnce(2, list)
  if (ver2.fail) holes.push(`verifier round 2: ${ver2.fail}; round 1 blocking items not re-checked: ${list}`)
  else {
    ver = ver2
    if (isBlocking(ver.r)) holes.push(`verifier round 2 still blocking: ${ver.r.blocking.join('; ') || `${ver.r.contradicted} CONTRADICTED`}`)
  }
}
counts = { verified: ver.r.verified, unverified: ver.r.unverified, contradicted: ver.r.contradicted }
if (counts.unverified > 0) open_items.push(`${counts.unverified} UNVERIFIED claims (non-blocking): see ${artifacts.verification}`)
log(`${A.feat_id}: verified ${counts.verified}, unverified ${counts.unverified}, contradicted ${counts.contradicted}, holes ${holes.length}`)
return finish()
