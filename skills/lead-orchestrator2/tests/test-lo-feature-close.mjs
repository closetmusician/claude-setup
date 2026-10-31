// ABOUTME: Tests for workflows/lo-feature-close.js, the whole-feature closing workflow (round 1).
// ABOUTME: It runs the integrated suite, review and QA C1 for tasks that stopped early, one fix round,
// ABOUTME: then the feature verifier over ALL requirements with one more fix round and a round-2 cap.
// ABOUTME: Added after tip-001: B's verifier failed 4 claims and no fix round followed.
// ABOUTME: Round 2 (pm-login-002): a mutation probe disables each fix; a surviving mutant blocks.
// ABOUTME: Run: node ~/.claude/skills/lead-orchestrator2/tests/test-lo-feature-close.mjs
import assert from 'node:assert/strict'
import { runWorkflow, responder, test, report, kinds, ALLOWED_MODELS } from './harness.mjs'

const RUN = '/repo/qa/FEAT-001'
const REQS = [
  { req_id: 'REQ-01', what: 'parser reads every section', done_when: 'unit tests pass', source: 'spec 6.1', task_ids: ['T-001'] },
  { req_id: 'REQ-02', what: 'md has team cards', done_when: 'cards in md', source: 'spec 3.2', task_ids: ['T-002'] },
]
const ARGS = {
  repo: '/repo', feat_id: 'FEAT-001', spec_path: 'docs/feat-001.md', run_dir: RUN, base_sha: 'abc1234',
  test_cmd: 'npm test', golden_ref: 'spec section 3 and AC1-AC8', feature_reqs: REQS,
  tasks: [
    { task_id: 'T-001', status: 'complete' },
    { task_id: 'T-002', status: 'complete' },
  ],
}
const ESC = { task_id: 'T-002', status: 'escalate', stage: 'GREEN', reason: "Missing 'ReviewCommit:<SHA>'" }
const HAPPY = {
  'gate-suite': { suite_exit: 0, runner_tail: '40 passed' },
  review: { p0: 0, p1: 0, p2: 0, path: `${RUN}/T-ALL-review-findings.md` },
  c1: { verdict: 'PASS', path: `${RUN}/T-ALL-cycle-1.md` },
  coder: { verdict: 'DONE', path: `${RUN}/T-ALL-ready-for-review.md` },
  'gate-green': { validate_exit: 0, tdd_exit: 0, suite_exit: 0, runner_tail: '41 passed',
    fix_red: 'def5678', fix_red_files: ['tests/test_md.py'], new_tests: 3 },
  verify: { verified: 9, unverified: 0, contradicted: 0, blocking: [], path: `${RUN}/T-ALL-verification.md` },
  check: { validate_exit: 0, output_tail: 'PASS' },
  probe: { checked: 2, survivors: [], path: `${RUN}/T-ALL-mutation-probe.md` },
}
const BLOCK = { verified: 5, unverified: 0, contradicted: 4, blocking: ['REQ-02 md has no cards'], path: 'v' }
const run = (overrides = {}, args = ARGS) =>
  runWorkflow('lo-feature-close.js', { args, respond: responder(HAPPY, overrides) })
const MAIN = (calls) => kinds(calls).filter((k) => k !== 'check' && k !== 'probe')

await test('1. All tasks complete and suite green: gate-suite then verifier only, complete', async () => {
  const r = await run()
  assert.deepEqual(MAIN(r.calls), ['gate-suite', 'verify'])
  assert.equal(r.result.status, 'complete')
  assert.deepEqual(r.result.counts, { verified: 9, unverified: 0, contradicted: 0 })
})

await test('2. Verifier prompt covers ALL feature requirements, the golden ref and the full suite', async () => {
  const r = await run()
  const v = r.calls.find((c) => c.kind === 'verify')
  for (const q of REQS) assert.ok(v.prompt.includes(q.req_id), q.req_id)
  assert.ok(v.prompt.includes(ARGS.golden_ref))
  assert.ok(v.prompt.includes(ARGS.test_cmd))
  assert.match(v.prompt, /\{QA_PHASE\} = verify/)
  assert.match(v.prompt, /every requirement/i)
})

await test('3. An escalated task gets review and QA C1, then one fix round, before the verifier', async () => {
  const r = await run({ review: { p0: 0, p1: 2, p2: 0, path: 'x' } }, { ...ARGS, tasks: [ARGS.tasks[0], ESC] })
  assert.deepEqual(MAIN(r.calls), ['gate-suite', 'review', 'c1', 'coder', 'gate-green', 'verify'])
  const rev = r.calls.find((c) => c.kind === 'review')
  assert.match(rev.prompt, /T-002/)
  assert.ok(!/T-001\b/.test(rev.prompt.split('Tasks in scope:')[1].split('\n')[0]), 'review scope is the escalated task only')
  const fix = r.calls.find((c) => c.kind === 'coder')
  assert.ok(fix.prompt.includes(ESC.reason), 'the escalation reason reaches the fix coder')
  assert.match(fix.prompt, /T-ALL-review-findings\.md/)
  assert.equal(r.result.status, 'complete')
})

await test('4. Integrated suite red: fix round runs before the verifier even when every task completed', async () => {
  const r = await run({ 'gate-suite': { suite_exit: 1, runner_tail: '1 error in test_hygiene.py' } })
  assert.deepEqual(MAIN(r.calls), ['gate-suite', 'coder', 'gate-green', 'verify'])
  assert.match(r.calls.find((c) => c.kind === 'coder').prompt, /1 error in test_hygiene\.py/)
})

await test('5. Verifier FAIL: one fix round, round 2 re-checks the fixed claims, complete when clean', async () => {
  const r = await run({ verify: (c, n) => n === 1 ? BLOCK : HAPPY.verify })
  assert.deepEqual(MAIN(r.calls), ['gate-suite', 'verify', 'coder', 'gate-green', 'verify'])
  const r2 = r.calls.filter((c) => c.kind === 'verify')[1]
  assert.match(r2.prompt, /round 2/i)
  assert.match(r2.prompt, /REQ-02 md has no cards/)
  assert.equal(r.result.status, 'complete')
})

await test('6. Verifier still blocking in round 2: no round 3, status partial with the blocking list', async () => {
  const r = await run({ verify: BLOCK })
  assert.equal(kinds(r.calls).filter((k) => k === 'verify').length, 2)
  assert.equal(r.result.status, 'partial')
  assert.ok(r.result.holes.some((h) => /REQ-02/.test(h)))
})

await test('7. Fix gate fails: the verifier still runs, status partial (never complete)', async () => {
  const r = await run({ 'gate-suite': { suite_exit: 1, runner_tail: 'x' },
    'gate-green': { ...HAPPY['gate-green'], suite_exit: 1, runner_tail: '2 failed' } })
  assert.ok(kinds(r.calls).includes('verify'))
  assert.equal(r.result.status, 'partial')
  assert.ok(r.result.holes.some((h) => /suite_exit=1/.test(h)))
})

await test('7b. Fix gate: a fake FixRed (no new test) is a hole, not a pass', async () => {
  const r = await run({ 'gate-suite': { suite_exit: 1, runner_tail: 'x' },
    'gate-green': { ...HAPPY['gate-green'], fix_red: '1f77f88', fix_red_files: ['tests/hygiene.py'], new_tests: 0 } })
  assert.equal(r.result.status, 'partial')
  assert.ok(r.result.holes.some((h) => /no new test/i.test(h)))
})

await test('8. Every agent call has an explicit allowed model; role tiers match', async () => {
  const r = await run({ review: { p0: 1, p1: 0, p2: 0, path: 'x' }, verify: (c, n) => n === 1 ? BLOCK : HAPPY.verify },
    { ...ARGS, tasks: [ESC] })
  const tier = { 'gate-suite': 'haiku', 'gate-green': 'haiku', check: 'haiku', review: 'opus', c1: 'sonnet',
    coder: 'sonnet', verify: 'opus', probe: 'sonnet' }
  for (const c of r.calls) {
    assert.ok(ALLOWED_MODELS.includes(c.model), `${c.label} model=${c.model}`)
    assert.equal(c.model, tier[c.kind], `${c.label} tier`)
  }
})

await test('9. Missing args, empty feature_reqs or empty tasks: escalate before any agent call', async () => {
  for (const a of [{ ...ARGS, test_cmd: '' }, { ...ARGS, feature_reqs: [] }, { ...ARGS, tasks: [] }, { ...ARGS, base_sha: 'HEAD' }]) {
    const r = await run({}, a)
    assert.equal(r.calls.length, 0, JSON.stringify(Object.keys(a)))
    assert.equal(r.result.status, 'escalate')
  }
})

await test('10. Coder fix prompt carries the artifact rules and FixRed line', async () => {
  const r = await run({ 'gate-suite': { suite_exit: 1, runner_tail: 'x' } })
  const c = r.calls.find((k) => k.kind === 'coder')
  assert.match(c.prompt, /ReviewCommit: <40-hex sha>/)
  assert.match(c.prompt, /FixRed: <sha>/)
  assert.match(c.prompt, /\{TASK_ID\} = T-ALL/)
})

await test('11. meta is a literal with name lo-feature-close', async () => {
  const r = await run()
  assert.equal(r.meta.name, 'lo-feature-close')
})

await test('12. Mutation probe always runs before the verifier, in a scratch copy, over the feature diff', async () => {
  const r = await run()
  const k = kinds(r.calls)
  assert.ok(k.includes('probe'), `kinds ${k}`)
  assert.ok(k.indexOf('probe') < k.indexOf('verify'))
  const p = r.calls.find((c) => c.kind === 'probe')
  assert.equal(p.model, 'sonnet')
  assert.match(p.prompt, /scratch/i)
  assert.match(p.prompt, /abc1234/)
  assert.match(p.prompt, /npm test/)
  assert.match(p.prompt, /disable/i)
  assert.match(p.prompt, /baseline/i)
  assert.match(p.prompt, /never edit|do not edit/i)
  assert.ok(r.calls.find((c) => c.kind === 'verify').prompt.includes(`${RUN}/T-ALL-mutation-probe.md`))
})

await test('13. A surviving mutant goes to the fix round, then a re-probe; killed means complete', async () => {
  const surv = { checked: 2, survivors: ['REQ-01 bin/ensure-tokens.js:1099: gate disabled, 53/53 pass'], path: 'p' }
  const r = await run({ probe: (c, n) => n === 1 ? surv : HAPPY.probe })
  assert.deepEqual(kinds(r.calls).filter((x) => x !== 'check'), ['gate-suite', 'probe', 'coder', 'gate-green', 'probe', 'verify'])
  assert.ok(r.calls.find((c) => c.kind === 'coder').prompt.includes(surv.survivors[0]))
  assert.match(r.calls.filter((c) => c.kind === 'probe')[1].prompt, /REQ-01 bin\/ensure-tokens\.js:1099/)
  assert.equal(r.result.status, 'complete')
})

await test('14. A mutant that survives the fix round is a hole: status partial', async () => {
  const surv = { checked: 2, survivors: ['REQ-01 gate disabled, all pass'], path: 'p' }
  const r = await run({ probe: surv })
  assert.equal(r.calls.filter((c) => c.kind === 'probe').length, 2, 'one re-probe only')
  assert.equal(r.result.status, 'partial')
  assert.ok(r.result.holes.some((h) => /mutant/i.test(h) && /REQ-01/.test(h)))
})

await test('15. A dead probe is re-run once, then logged as a hole', async () => {
  const r = await run({ probe: () => undefined })
  assert.equal(r.calls.filter((c) => c.kind === 'probe').length, 2)
  assert.equal(r.result.status, 'partial')
  assert.ok(r.result.holes.some((h) => /probe/i.test(h)))
})

report('lo-feature-close')
