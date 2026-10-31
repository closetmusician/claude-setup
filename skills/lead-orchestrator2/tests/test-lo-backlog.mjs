// ABOUTME: Tests for workflows/lo-backlog.js, the backlog-wave workflow (LO2-SPEC §1, §3).
// ABOUTME: Asserts coders fan out per item, QA cycle-1 runs only when qa_cycles >= 1,
// ABOUTME: and the wave verifier ALWAYS runs (qa_cycles 0, dead coders, C1 escalation).
// ABOUTME: Also checks file-overlap rejection, the 2-round verifier cap and explicit models.
// ABOUTME: Run: node ~/.claude/skills/lead-orchestrator2/tests/test-lo-backlog.mjs
import assert from 'node:assert/strict'
import { runWorkflow, responder, test, report, kinds, ALLOWED_MODELS } from './harness.mjs'

const RUN = '/repo/docs/temp/backlog-w1'
const ARGS = {
  repo: '/repo', run_dir: RUN, spec_path: 'docs/backlog.md', test_cmd: 'make test', qa_cycles: 1,
  golden_ref: 'make test exits 0; each item behaves as its backlog line says',
  items: [
    { id: 'B-01', description: 'Trim whitespace in slug()', files: ['src/slug.js'] },
    { id: 'B-02', description: 'Reject empty title', files: ['src/title.js'] },
  ],
}
const HAPPY = {
  coder: (c) => ({ verdict: 'DONE', path: `${RUN}/${c.label.split(':')[1]}-ready-for-review.md` }),
  c1: { verdict: 'PASS', path: `${RUN}/cycle-1.md`, failing_items: [] },
  verify: { verified: 2, unverified: 0, contradicted: 0, blocking: [], verified_items: ['B-01', 'B-02'], path: `${RUN}/verification.md` },
}
const run = (overrides = {}, args = ARGS) =>
  runWorkflow('lo-backlog.js', { args, respond: responder(HAPPY, overrides) })

await test('1. qa_cycles 0: no cycle-1, wave verifier still runs', async () => {
  const r = await run({}, { ...ARGS, qa_cycles: 0 })
  assert.deepEqual(kinds(r.calls), ['coder', 'coder', 'verify'])
  assert.equal(r.result.status, 'complete')
})

await test('2. qa_cycles 1 (default): coders, then cycle-1, then verifier', async () => {
  const { qa_cycles, ...noQa } = ARGS
  const r = await run({}, noQa)
  assert.deepEqual(kinds(r.calls), ['coder', 'coder', 'c1', 'verify'])
  assert.deepEqual(r.result.verified_items, ['B-01', 'B-02'])
})

await test('3. Dead coder twice: item is a hole, verifier still runs, status partial', async () => {
  const r = await run({ coder: (c) => c.label.startsWith('coder:B-02') ? undefined : HAPPY.coder(c),
    verify: { ...HAPPY.verify, verified: 1, verified_items: ['B-01'] } })
  assert.equal(r.calls.filter((c) => c.label.startsWith('coder:B-02')).length, 2)
  assert.ok(kinds(r.calls).includes('verify'))
  assert.deepEqual(r.result.holes, ['B-02'])
  assert.equal(r.result.status, 'partial')
  assert.ok(r.logs.some((l) => /B-02/.test(l)))
})

await test('4. verified_items come only from the verifier and only for wave items', async () => {
  const r = await run({ verify: { ...HAPPY.verify, verified_items: ['B-01', 'B-99'] } })
  assert.deepEqual(r.result.verified_items, ['B-01'])
  assert.deepEqual(r.result.unverified_items, ['B-02'])
})

await test('5. Two items share a file: escalate before any call', async () => {
  const items = [ARGS.items[0], { ...ARGS.items[1], files: ['src/slug.js'] }]
  const r = await run({}, { ...ARGS, items })
  assert.equal(r.calls.length, 0)
  assert.equal(r.result.status, 'escalate')
  assert.match(r.result.reason, /src\/slug\.js/)
})

await test('6. C1 FAIL twice: only failing items get a fix, verifier still runs, escalate', async () => {
  const r = await run({ c1: { verdict: 'FAIL', path: 'c', failing_items: ['B-02'] } })
  const fixes = r.calls.filter((c) => /:fix$/.test(c.label)).map((c) => c.label)
  assert.deepEqual(fixes, ['coder:B-02:fix'])
  assert.equal(kinds(r.calls).filter((k) => k === 'c1').length, 2)
  assert.equal(kinds(r.calls).at(-1), 'verify')
  assert.equal(r.result.status, 'escalate')
})

await test('7. Coder prompt: backlog GOVERNANCE_EXEMPT line, MODE backlog, template path', async () => {
  const r = await run()
  const p = r.calls.find((c) => c.kind === 'coder').prompt
  assert.match(p, /^GOVERNANCE_EXEMPT \(mode=backlog/)
  assert.match(p, /\{MODE\} = backlog/)
  assert.match(p, /lead-orchestrator\/templates\/coder-prompt\.md/)
  const v = r.calls.find((c) => c.kind === 'verify').prompt
  assert.ok(v.includes(ARGS.golden_ref) && v.includes(ARGS.test_cmd))
})

await test('8. Verifier contradicted twice: no third verifier call, escalate', async () => {
  const r = await run({ verify: { ...HAPPY.verify, contradicted: 1, blocking: ['B-01 claim'], verified_items: ['B-02'] } })
  assert.equal(kinds(r.calls).filter((k) => k === 'verify').length, 2)
  assert.equal(r.result.status, 'escalate')
})

await test('9. Every call has an allowed model; coders/QA sonnet, verifier opus', async () => {
  const r = await run({ c1: (c, n) => n === 1 ? { verdict: 'FAIL', path: 'c', failing_items: ['B-01'] } : HAPPY.c1 })
  const tier = { coder: 'sonnet', c1: 'sonnet', verify: 'opus' }
  for (const c of r.calls) {
    assert.ok(ALLOWED_MODELS.includes(c.model), `${c.label} model=${c.model}`)
    assert.equal(c.model, tier[c.kind], c.label)
  }
})

report('lo-backlog')
