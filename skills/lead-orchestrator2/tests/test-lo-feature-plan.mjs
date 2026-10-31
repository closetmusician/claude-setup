// ABOUTME: Tests for workflows/lo-feature-plan.js, the decomposition check that runs before any task.
// ABOUTME: An independent opus agent maps every spec requirement to the session's tasks.
// ABOUTME: The script fails (status fix) when any requirement has no task that fully covers it.
// ABOUTME: Added in round 1 after tip-001: B's T-002 mini_spec dropped spec 3.2 parts (md/xhtml cards).
// ABOUTME: Run: node ~/.claude/skills/lead-orchestrator2/tests/test-lo-feature-plan.mjs
import assert from 'node:assert/strict'
import { runWorkflow, responder, test, report, kinds, ALLOWED_MODELS } from './harness.mjs'

const RUN = '/repo/qa/FEAT-001'
const ARGS = {
  repo: '/repo', feat_id: 'FEAT-001', spec_path: 'docs/feat-001.md', run_dir: RUN,
  tasks: [
    { task_id: 'T-001', mini_spec: 'Build the parser.' },
    { task_id: 'T-002', mini_spec: 'Render html, md and xhtml with cards and the method note.' },
  ],
}
const REQS = [
  { req_id: 'REQ-01', what: 'parser reads every section', done_when: 'unit tests pass', source: 'spec 6.1', task_ids: ['T-001'] },
  { req_id: 'REQ-02', what: 'md has team cards', done_when: 'cards in md', source: 'spec 3.2', task_ids: ['T-002'] },
]
const HAPPY = { plan: { requirements: REQS, path: `${RUN}/feature-map.md` } }
const run = (overrides = {}, args = ARGS) =>
  runWorkflow('lo-feature-plan.js', { args, respond: responder(HAPPY, overrides) })

await test('1. Every requirement mapped: complete, feature_reqs and per-task req maps returned', async () => {
  const r = await run()
  assert.equal(r.result.status, 'complete')
  assert.deepEqual(kinds(r.calls), ['plan'])
  assert.equal(r.result.feature_reqs.length, 2)
  assert.deepEqual(r.result.task_req_maps['T-002'].requirements.map((q) => q.req_id), ['REQ-02'])
  assert.equal(r.result.task_req_maps['T-001'].task_id, 'T-001')
})

await test('2. A requirement with no task: status fix, unmapped names it', async () => {
  const reqs = [...REQS, { req_id: 'REQ-03', what: 'theme cards have 2-4 bullets', done_when: 'x', source: 'spec 3.2', task_ids: [] }]
  const r = await run({ plan: { requirements: reqs, path: 'p' } })
  assert.equal(r.result.status, 'fix')
  assert.deepEqual(r.result.unmapped.map((q) => q.req_id), ['REQ-03'])
})

await test('2b. A requirement mapped to an unknown task id counts as unmapped', async () => {
  const reqs = [REQS[0], { ...REQS[1], task_ids: ['T-009'] }]
  const r = await run({ plan: { requirements: reqs, path: 'p' } })
  assert.equal(r.result.status, 'fix')
  assert.deepEqual(r.result.unmapped.map((q) => q.req_id), ['REQ-02'])
})

await test('2c. A task with no requirement is reported (scope the session did not ask for)', async () => {
  const args = { ...ARGS, tasks: [...ARGS.tasks, { task_id: 'T-003', mini_spec: 'Extra.' }] }
  const r = await run({}, args)
  assert.deepEqual(r.result.idle_tasks, ['T-003'])
})

await test('3. Plan prompt carries the spec path and every mini_spec; the agent is opus', async () => {
  const r = await run()
  const p = r.calls[0]
  assert.equal(p.model, 'opus')
  assert.ok(p.prompt.includes(ARGS.spec_path))
  for (const t of ARGS.tasks) assert.ok(p.prompt.includes(t.mini_spec), t.task_id)
  assert.match(p.prompt, /every requirement/i)
  for (const c of r.calls) assert.ok(ALLOWED_MODELS.includes(c.model))
})

await test('4. Missing args or an empty task list: escalate before any agent call', async () => {
  for (const a of [{ ...ARGS, spec_path: '' }, { ...ARGS, tasks: [] }]) {
    const r = await run({}, a)
    assert.equal(r.calls.length, 0)
    assert.equal(r.result.status, 'escalate')
  }
})

await test('5. Dead plan agent twice, or zero requirements: escalate', async () => {
  const dead = await run({ plan: () => undefined })
  assert.equal(dead.result.status, 'escalate')
  assert.equal(kinds(dead.calls).length, 2)
  const empty = await run({ plan: { requirements: [], path: 'p' } })
  assert.equal(empty.result.status, 'escalate')
})

report('lo-feature-plan')
