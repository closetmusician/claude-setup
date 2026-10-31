// ABOUTME: Tests for workflows/lo-feature-task.js, the one-VIBE-task workflow (LO2-SPEC §2-§3).
// ABOUTME: Each case scripts the agent replies and asserts the stage order and the gates.
// ABOUTME: The gates under test: RED before coder, GREEN before review, verifier round cap 2,
// ABOUTME: cycle-2 only at vibe_level full, and an explicit allowed model on every agent call.
// ABOUTME: Run: node ~/.claude/skills/lead-orchestrator2/tests/test-lo-feature-task.mjs
import assert from 'node:assert/strict'
import { runWorkflow, responder, test, report, kinds, ALLOWED_MODELS } from './harness.mjs'

const RUN = '/repo/qa/FEAT-001'
const ARGS = {
  repo: '/repo', feat_id: 'FEAT-001', task_id: 'T-001', spec_path: 'docs/feat-001.md',
  mini_spec: 'Add a /health route that returns 200 {"ok":true}.', test_cmd: 'npm test',
  vibe_level: 'full', arch_needed: true, run_dir: RUN,
  golden_ref: 'GET http://localhost:3000/health returns 200 {"ok":true}',
}
const HAPPY = {
  arch: { path: `${RUN}/T-001-arch.md`, summary: 'one route' },
  'qa-red': { path: `${RUN}/T-001-acceptance-tests.md`, verdict: 'RED' },
  'gate-red': { validate_exit: 0, suite_exit: 1, red_sha: 'abc1234', runner_tail: 'FAILED tests/test_health.py::test_ok - AssertionError\n2 failed',
    red_files: ['tests/test_health_acceptance.py', 'qa/FEAT-001/T-001-acceptance-tests.md'] },
  coder: { path: `${RUN}/T-001-ready-for-review.md`, verdict: 'DONE' },
  'gate-green': { validate_exit: 0, tdd_exit: 0, suite_exit: 0, runner_tail: '9 passed',
    fix_red: 'def5678', fix_red_files: ['tests/test_health.py'], new_tests: 2 },
  review: { p0: 0, p1: 0, p2: 1, path: `${RUN}/T-001-review-findings.md` },
  c1: { verdict: 'PASS', path: `${RUN}/T-001-cycle-1.md` },
  c2: { verdict: 'PASS', path: `${RUN}/T-001-cycle-2.md` },
  verify: { verified: 6, unverified: 0, contradicted: 0, blocking: [], path: `${RUN}/T-001-verification.md` },
  check: { validate_exit: 0, output_tail: 'PASS' },
}
const run = (overrides = {}, args = ARGS) =>
  runWorkflow('lo-feature-task.js', { args, respond: responder(HAPPY, overrides) })
const MAIN = (calls) => kinds(calls).filter((k) => k !== 'check')

await test('1. GATE-RED suite_exit 0 twice: coder never called, status escalate', async () => {
  const r = await run({ 'gate-red': { validate_exit: 0, suite_exit: 0, red_sha: 'abc1234', runner_tail: '2 passed' } })
  assert.ok(!kinds(r.calls).includes('coder'), `coder was called: ${kinds(r.calls)}`)
  assert.equal(r.result.status, 'escalate')
  assert.equal(kinds(r.calls).filter((k) => k === 'qa-red').length, 2, 'QA re-run exactly once')
  assert.equal(kinds(r.calls).filter((k) => k === 'gate-red').length, 2)
  assert.match(r.result.reason, /RED/)
})

await test('2. GATE-RED reports no red_sha: coder never called', async () => {
  const r = await run({ 'gate-red': { validate_exit: 0, suite_exit: 1, red_sha: '', runner_tail: '2 failed' } })
  assert.ok(!kinds(r.calls).includes('coder'))
  assert.equal(r.result.status, 'escalate')
})

await test('2b. GATE-RED red_sha not hex, or validate_exit 1: coder never called', async () => {
  for (const bad of [{ red_sha: 'HEAD~1' }, { red_sha: 'abc12' }, { validate_exit: 1 }]) {
    const r = await run({ 'gate-red': { ...HAPPY['gate-red'], ...bad } })
    assert.ok(!kinds(r.calls).includes('coder'), JSON.stringify(bad))
    assert.equal(r.result.status, 'escalate')
  }
})

await test('2c. GATE-RED fails once then passes: QA retried with the reason, coder runs', async () => {
  const r = await run({ 'gate-red': (c, n) => n === 1
    ? { validate_exit: 0, suite_exit: 0, red_sha: 'abc1234', runner_tail: 'all passed' } : HAPPY['gate-red'] })
  const retry = r.calls.filter((c) => c.kind === 'qa-red')[1]
  assert.match(retry.prompt, /suite_exit/)
  assert.equal(r.result.status, 'complete')
})

await test('3. Happy path: stage order is exact', async () => {
  const r = await run()
  assert.deepEqual(MAIN(r.calls), ['arch', 'qa-red', 'gate-red', 'coder', 'gate-green', 'review', 'c1', 'c2', 'verify'])
  assert.deepEqual(kinds(r.calls), ['arch', 'qa-red', 'gate-red', 'coder', 'gate-green',
    'review', 'check', 'c1', 'check', 'c2', 'check', 'verify', 'check'])
  assert.equal(r.result.status, 'complete')
  assert.equal(r.result.red_sha, 'abc1234')
  assert.equal(r.result.artifacts.verification, `${RUN}/T-001-verification.md`)
})

await test('3b. arch_needed false: no architect call, prompts carry ARCH_DESIGN_PATH=N/A', async () => {
  const r = await run({}, { ...ARGS, arch_needed: false })
  assert.equal(MAIN(r.calls)[0], 'qa-red')
  assert.match(r.calls[0].prompt, /\{ARCH_DESIGN_PATH\} = N\/A/)
})

await test('3c. Prompts carry templates, placeholders, gate scripts and golden_ref', async () => {
  const r = await run()
  const by = (k) => r.calls.find((c) => c.kind === k)
  assert.match(by('qa-red').prompt, /lead-orchestrator\/templates\/qa-prompt\.md/)
  assert.match(by('qa-red').prompt, /\{QA_PHASE\} = acceptance-red/)
  assert.match(by('qa-red').prompt, /\{QA_GOVERNANCE_ROLE\} = qa-test-writer/)
  assert.match(by('coder').prompt, /lead-orchestrator\/templates\/coder-prompt\.md/)
  assert.match(by('coder').prompt, /\{MODE\} = feature/)
  assert.match(by('coder').prompt, /\{ACCEPTANCE_TESTS_RED_SHA\} = abc1234/)
  assert.ok(!/GOVERNANCE_EXEMPT/.test(by('coder').prompt), 'feature coder must not be exempt')
  assert.match(by('gate-red').prompt, /\/Users\/yklin\/\.claude\/skills\/lead-orchestrator\/scripts\/validate-artifact\.sh/)
  assert.match(by('gate-red').prompt, /runs\/T-001-red-/)
  assert.match(by('gate-green').prompt, /verify-tdd-evidence\.sh/)
  assert.match(by('review').prompt, /^GOVERNANCE_EXEMPT/)
  assert.match(by('verify').prompt, /\{QA_PHASE\} = verify/)
  assert.ok(by('verify').prompt.includes(ARGS.golden_ref))
})

await test('4. GATE-GREEN tdd_exit 1: review never called before a passing gate', async () => {
  const r = await run({ 'gate-green': { validate_exit: 0, tdd_exit: 1, suite_exit: 0, runner_tail: 'RED after GREEN' } })
  assert.ok(!kinds(r.calls).includes('review'))
  assert.equal(r.result.status, 'escalate')
  assert.equal(kinds(r.calls).filter((k) => k === 'coder').length, 2, 'one coder fix only')
})

await test('4b. Review P0 then clean: coder fix, gate-green re-runs before the second review', async () => {
  const r = await run({ review: (c, n) => n === 1 ? { p0: 1, p1: 0, p2: 0, path: 'x' } : HAPPY.review })
  const k = MAIN(r.calls)
  assert.deepEqual(k.slice(0, 9), ['arch', 'qa-red', 'gate-red', 'coder', 'gate-green', 'review', 'coder', 'gate-green', 'review'])
  assert.equal(r.result.status, 'complete')
})

await test('4c. Review P1 twice: escalate, no QA cycle', async () => {
  const r = await run({ review: { p0: 0, p1: 2, p2: 0, path: 'x' } })
  assert.equal(r.result.status, 'escalate')
  assert.ok(!kinds(r.calls).includes('c1'))
})

await test('4d. C1 FAIL twice: escalate, no cycle-2', async () => {
  const r = await run({ c1: { verdict: 'FAIL', path: 'x' } })
  assert.equal(r.result.status, 'escalate')
  assert.equal(kinds(r.calls).filter((k) => k === 'c1').length, 2)
  assert.ok(!kinds(r.calls).includes('c2'))
})

await test('4e. Artifact check fails twice: escalate (no artifact, no progress)', async () => {
  const r = await run({ check: { validate_exit: 1, output_tail: 'FAIL: missing verdict' } })
  assert.equal(r.result.status, 'escalate')
  assert.ok(!kinds(r.calls).includes('c1'))
})

await test('4f. Dead agent (null) at the coder stage twice: escalate', async () => {
  const r = await run({ coder: () => undefined })
  assert.equal(r.result.status, 'escalate')
  assert.ok(!kinds(r.calls).includes('review'))
})

await test('5. Verifier contradicted twice: no third verifier call, status escalate', async () => {
  const r = await run({ verify: { verified: 3, unverified: 0, contradicted: 1, blocking: ['REQ-02'], path: 'v' } })
  assert.equal(kinds(r.calls).filter((k) => k === 'verify').length, 2)
  assert.equal(r.result.status, 'escalate')
  const round2 = r.calls.filter((c) => c.kind === 'verify')[1]
  assert.match(round2.prompt, /round 2/i)
  assert.match(round2.prompt, /REQ-02/)
})

await test('5b. Verifier blocking once, clean on round 2: complete', async () => {
  const r = await run({ verify: (c, n) => n === 1
    ? { verified: 3, unverified: 1, contradicted: 0, blocking: ['REQ-03 status unverified'], path: 'v' } : HAPPY.verify })
  assert.equal(r.result.status, 'complete')
  assert.equal(kinds(r.calls).filter((k) => k === 'verify').length, 2)
})

await test('6. vibe_level light: no cycle-2 call', async () => {
  const r = await run({}, { ...ARGS, vibe_level: 'light' })
  assert.ok(!kinds(r.calls).includes('c2'))
  assert.equal(r.result.status, 'complete')
})

await test('7. Every agent call has an explicit allowed model; role tiers match', async () => {
  const runs = [await run(), await run({ verify: { verified: 1, unverified: 0, contradicted: 1, blocking: ['x'], path: 'v' } })]
  const tier = { 'gate-red': 'haiku', 'gate-green': 'haiku', check: 'haiku', review: 'opus', verify: 'opus',
    coder: 'sonnet', 'qa-red': 'sonnet', c1: 'sonnet', c2: 'sonnet', arch: 'sonnet' }
  for (const r of runs) for (const c of r.calls) {
    assert.ok(ALLOWED_MODELS.includes(c.model), `${c.label} model=${c.model}`)
    assert.equal(c.model, tier[c.kind], `${c.label} tier`)
  }
})

await test('8. Missing required args: escalate before any agent call', async () => {
  const r = await run({}, { ...ARGS, test_cmd: '' })
  assert.equal(r.calls.length, 0)
  assert.equal(r.result.status, 'escalate')
  assert.match(r.result.reason, /test_cmd/)
})

await test('9. meta is a literal with name lo-feature-task and phases', async () => {
  const r = await run()
  assert.equal(r.meta.name, 'lo-feature-task')
  assert.ok(r.meta.phases.length >= 5)
})

// ---- Round 1 (tip-001 side-by-side): gates that B's run showed were too weak ----------------
const RED_OK = HAPPY['gate-red']
await test('10. GATE-RED: a collection or import error is not a real RED; coder never called', async () => {
  const tails = [
    'ERROR collecting tests/test_health.py\nModuleNotFoundError: No module named health\nInterrupted: 1 error during collection',
    'E   SyntaxError: invalid syntax\n1 error in 0.10s',
    '1 error in 0.10s',
  ]
  for (const runner_tail of tails) {
    const r = await run({ 'gate-red': { ...RED_OK, runner_tail } })
    assert.ok(!kinds(r.calls).includes('coder'), `coder was called for tail: ${runner_tail}`)
    assert.equal(r.result.status, 'escalate')
    const retry = r.calls.filter((c) => c.kind === 'qa-red')[1]
    assert.match(retry.prompt, /real assertion|assertion/i)
  }
})

await test('10b. GATE-RED: a RED commit that touches a non-test file is rejected', async () => {
  const r = await run({ 'gate-red': { ...RED_OK, red_files: ['tests/test_health.py', 'src/health.js'] } })
  assert.ok(!kinds(r.calls).includes('coder'))
  assert.equal(r.result.status, 'escalate')
  assert.match(r.result.reason, /src\/health\.js/)
  const r2 = await run({ 'gate-red': { ...RED_OK, red_files: [] } })
  assert.ok(!kinds(r2.calls).includes('coder'), 'an empty file list is not a RED commit')
})

await test('10c. GATE-RED prompt runs git diff-tree on the RED SHA to list its files', async () => {
  const r = await run()
  assert.match(r.calls.find((c) => c.kind === 'gate-red').prompt, /git diff-tree --no-commit-id --name-only -r/)
})

await test('11. Coder prompts carry the artifact rules the gates check (plain ReviewCommit, real SHAs)', async () => {
  const r = await run({ review: (c, n) => n === 1 ? { p0: 1, p1: 0, p2: 0, path: 'x' } : HAPPY.review })
  const coders = r.calls.filter((c) => c.kind === 'coder')
  assert.equal(coders.length, 2)
  for (const c of coders) {
    assert.match(c.prompt, /ReviewCommit: <40-hex sha>/)
    assert.match(c.prompt, /git log --format=%H/)
    assert.match(c.prompt, /git cat-file -e/)
  }
  assert.match(coders[1].prompt, /FixRed: <sha>/)
})

await test('12. Fix round: a FixRed commit with no new test case is a fake RED; escalate before QA', async () => {
  const r = await run({
    review: (c, n) => n === 1 ? { p0: 1, p1: 0, p2: 0, path: 'x' } : HAPPY.review,
    'gate-green': (c, n) => n === 1 ? HAPPY['gate-green']
      : { ...HAPPY['gate-green'], fix_red: '1f77f88', fix_red_files: ['tests/hygiene.py'], new_tests: 0 },
  })
  assert.equal(r.result.status, 'escalate')
  assert.match(r.result.reason, /no new test/i)
  assert.ok(!kinds(r.calls).includes('c1'))
})

await test('12b. Fix round: missing FixRed line, or FixRed touching code, fails the fix gate', async () => {
  for (const bad of [{ fix_red: '' }, { fix_red_files: ['tests/test_x.py', 'scripts/x.py'] }]) {
    const r = await run({
      review: (c, n) => n === 1 ? { p0: 1, p1: 0, p2: 0, path: 'x' } : HAPPY.review,
      'gate-green': (c, n) => n === 1 ? HAPPY['gate-green'] : { ...HAPPY['gate-green'], ...bad },
    })
    assert.equal(r.result.status, 'escalate', JSON.stringify(bad))
  }
})

await test('12c. Fix round: FixRed TDD-EXEMPT passes but is named in open_items', async () => {
  const r = await run({
    review: (c, n) => n === 1 ? { p0: 0, p1: 1, p2: 0, path: 'x' } : HAPPY.review,
    'gate-green': (c, n) => n === 1 ? HAPPY['gate-green'] : { ...HAPPY['gate-green'], fix_red: 'TDD-EXEMPT', fix_red_files: [], new_tests: 0 },
  })
  assert.equal(r.result.status, 'complete')
  assert.ok(r.result.open_items.some((s) => /TDD-EXEMPT/.test(s)), JSON.stringify(r.result.open_items))
  const fixGate = r.calls.filter((c) => c.kind === 'gate-green')[1]
  assert.match(fixGate.prompt, /FixRed/)
  assert.match(fixGate.prompt, /git show --format=/)
})

report('lo-feature-task')
