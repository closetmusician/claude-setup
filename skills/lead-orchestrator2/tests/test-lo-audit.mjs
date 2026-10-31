// ABOUTME: Tests for workflows/lo-audit.js, the investigate-audit workflow (LO2-SPEC §1, §3).
// ABOUTME: Asserts lanes fan out, a dead lane is re-run once then logged as a hole,
// ABOUTME: synthesis waits for all lanes, and the verifier runs AFTER synthesis.
// ABOUTME: Also checks the 2-round verifier cap and an explicit allowed model on every call.
// ABOUTME: Round 2 (fix-ctx-002): code audits add a writers lane, a completeness critic, repo-test
// ABOUTME: rules, a repro/mutation probe in the verify stage, and a fix-direction check.
// ABOUTME: Run: node ~/.claude/skills/lead-orchestrator2/tests/test-lo-audit.mjs
import assert from 'node:assert/strict'
import { runWorkflow, responder, test, report, kinds, ALLOWED_MODELS } from './harness.mjs'

const RUN = '/repo/docs/temp/prd-audit'
const ARGS = {
  run_dir: RUN, spec_path: 'docs/temp/prd-audit/scope.md', scope: '3 lanes, 1 synthesis, 1 verifier',
  deliverable_path: `${RUN}/report.md`, golden_ref: 'Every claim cites a PRD file:line',
  lanes: [
    { id: 'pricing', prompt: 'Audit pricing claims in docs/prd/*.md', model: 'sonnet' },
    { id: 'security', prompt: 'Audit security claims', model: 'opus' },
    { id: 'roadmap', prompt: 'Audit roadmap dates', model: 'sonnet' },
  ],
}
const HAPPY = {
  lane: (c) => ({ out_file: `${RUN}/${c.label.split(':')[1]}.md`, summary: 'ok', claims: 4 }),
  synth: { path: `${RUN}/report.md`, claims: 12 },
  verify: { verified: 12, unverified: 0, contradicted: 0, blocking: [], path: `${RUN}/verification.md` },
}
const run = (overrides = {}, args = ARGS) =>
  runWorkflow('lo-audit.js', { args, respond: responder(HAPPY, overrides) })

await test('1. Verifier runs after synthesis and checks the synthesizer output', async () => {
  const r = await run()
  const k = kinds(r.calls)
  assert.deepEqual(k, ['lane', 'lane', 'lane', 'synth', 'verify'])
  const v = r.calls.find((c) => c.kind === 'verify')
  assert.ok(v.prompt.includes(ARGS.deliverable_path))
  assert.ok(v.prompt.includes(`${RUN}/pricing.md`))
  assert.ok(v.prompt.includes(ARGS.golden_ref))
  assert.match(v.prompt, /\{QA_PHASE\} = verify/)
  assert.equal(r.result.status, 'complete')
  assert.deepEqual(r.result.holes, [])
})

await test('2. Dead lane is re-run once, then logged as a hole; status partial', async () => {
  const r = await run({ lane: (c) => c.label.startsWith('lane:security')
    ? undefined : HAPPY.lane(c) })
  const sec = r.calls.filter((c) => c.label.startsWith('lane:security'))
  assert.equal(sec.length, 2, 'one re-run only')
  assert.ok(r.logs.some((l) => /security/.test(l)), `logs: ${r.logs}`)
  assert.deepEqual(r.result.holes, ['security'])
  assert.equal(r.result.status, 'partial')
  assert.match(r.calls.find((c) => c.kind === 'synth').prompt, /security/)
})

await test('2b. Lane that returns no out_file counts as dead', async () => {
  const r = await run({ lane: (c) => c.label.startsWith('lane:roadmap') ? { out_file: '', summary: '' } : HAPPY.lane(c) })
  assert.deepEqual(r.result.holes, ['roadmap'])
})

await test('3. All lanes dead: escalate, no synthesis', async () => {
  const r = await run({ lane: () => undefined })
  assert.equal(r.result.status, 'escalate')
  assert.ok(!kinds(r.calls).includes('synth'))
})

await test('4. Verifier contradicted twice: one synth fix, no third verifier, escalate', async () => {
  const r = await run({ verify: { verified: 8, unverified: 0, contradicted: 2, blocking: ['claim #4'], path: 'v' } })
  assert.deepEqual(kinds(r.calls).slice(3), ['synth', 'verify', 'synth', 'verify'])
  assert.equal(r.result.status, 'escalate')
  assert.match(r.calls.filter((c) => c.kind === 'verify')[1].prompt, /round 2/i)
})

await test('5. Every call has an allowed model; lane tier passes through; synth and verify opus', async () => {
  const r = await run()
  for (const c of r.calls) assert.ok(ALLOWED_MODELS.includes(c.model), `${c.label} model=${c.model}`)
  assert.equal(r.calls.find((c) => c.label === 'lane:security').model, 'opus')
  assert.equal(r.calls.find((c) => c.kind === 'synth').model, 'opus')
  assert.equal(r.calls.find((c) => c.kind === 'verify').model, 'opus')
})

await test('6. Lane with a disallowed model (fable) or missing args: escalate before any call', async () => {
  const bad = { ...ARGS, lanes: [{ id: 'x', prompt: 'p', model: 'fable' }] }
  const r1 = await run({}, bad)
  assert.equal(r1.calls.length, 0)
  assert.equal(r1.result.status, 'escalate')
  const r2 = await run({}, { ...ARGS, lanes: [] })
  assert.equal(r2.calls.length, 0)
  assert.equal(r2.result.status, 'escalate')
})

// ---- Round 2: code audits (repo + test_dir + test_cmd) -----------------------------------
const CODE = {
  ...ARGS, repo: '/repo', test_dir: 'test', test_cmd: 'npm test',
  lanes: [
    { id: 'retrieval', prompt: 'Trace context from the API response to the prompt', model: 'opus' },
    { id: 'generation', prompt: 'Trace the prompt to the written draft', model: 'opus' },
  ],
}
const CODE_HAPPY = {
  ...HAPPY,
  critic: { uncovered: [], path: `${RUN}/coverage-critic.md` },
  gap: (c) => ({ out_file: `${RUN}/${c.label.split(':')[1]}.md`, summary: 'ok', claims: 2 }),
  probe: { checked: 4, bad_tests: [], survivors: [], path: `${RUN}/repro-probe.md` },
  verify: { ...HAPPY.verify, weakens: [] },
}
const runCode = (overrides = {}, args = CODE) =>
  runWorkflow('lo-audit.js', { args, respond: responder(CODE_HAPPY, overrides) })

await test('7. Code audit without a writers lane: the script adds one for writers and side effects', async () => {
  const r = await runCode()
  const w = r.calls.find((c) => c.label === 'lane:writers')
  assert.ok(w, `labels: ${r.calls.map((c) => c.label)}`)
  for (const word of [/writ/i, /retr(y|ies)/i, /resend/i, /refresh/i, /fail(s)? open|fail-open/i, /second|other/i])
    assert.match(w.prompt, word)
  assert.ok(ALLOWED_MODELS.includes(w.model))
  const r2 = await runCode({}, { ...CODE, lanes: [...CODE.lanes, { id: 'writers', prompt: 'mine', model: 'sonnet' }] })
  assert.equal(r2.calls.filter((c) => c.label.startsWith('lane:writers')).length, 1, 'no second writers lane')
})

await test('8. Code audit lanes follow a failure path, list their coverage, and carry the test and direction rules', async () => {
  const r = await runCode()
  for (const c of r.calls.filter((k) => k.kind === 'lane')) {
    assert.match(c.prompt, /failure path|data flow/i, c.label)
    assert.match(c.prompt, /## Coverage/, c.label)
    assert.match(c.prompt, /test\//, c.label)
    assert.match(c.prompt, /npm test/, c.label)
    assert.match(c.prompt, /absolute path/i, c.label)
    assert.match(c.prompt, /assertion/i, c.label)
    assert.match(c.prompt, /weaken/i, c.label)
  }
  assert.match(r.calls.find((c) => c.kind === 'synth').prompt, /weaken/i)
})

await test('9. Completeness critic runs after synthesis; uncovered paths get one gap loop, never two', async () => {
  const gaps = ['telegram propose_draft -> writeFileSync (telegram-chat.js:333)', 'refresh keeps old body (refresh.js:843)']
  const r = await runCode({ critic: { uncovered: gaps, path: 'c' } })
  const k = kinds(r.calls).filter((x) => x !== 'probe')
  assert.deepEqual(k, ['lane', 'lane', 'lane', 'synth', 'critic', 'gap', 'gap', 'synth', 'verify'])
  assert.equal(r.calls.find((c) => c.kind === 'critic').model, 'opus')
  assert.match(r.calls.find((c) => c.kind === 'critic').prompt, /## Coverage/)
  assert.ok(r.calls.filter((c) => c.kind === 'gap').some((c) => c.prompt.includes(gaps[0])))
  const merge = r.calls.filter((c) => c.kind === 'synth')[1]
  assert.match(merge.prompt, /gap-1\.md/)
  assert.ok(r.calls.find((c) => c.kind === 'verify').prompt.includes(`${RUN}/gap-2.md`))
  const many = await runCode({ critic: { uncovered: ['a', 'b', 'c', 'd', 'e', 'f'], path: 'c' } })
  assert.equal(many.calls.filter((c) => c.kind === 'gap').length, 4, 'gap lanes capped at 4')
  assert.equal(many.calls.filter((c) => c.kind === 'critic').length, 1)
  assert.ok(many.result.open_items.some((o) => /uncovered/i.test(o)))
})

await test('10. Critic finds nothing: no gap lane, straight to verify', async () => {
  const r = await runCode()
  assert.deepEqual(kinds(r.calls).filter((x) => x !== 'probe'), ['lane', 'lane', 'lane', 'synth', 'critic', 'verify'])
  assert.equal(r.result.status, 'complete')
})

await test('11. Code audit test args: missing, absolute or docs/ test_dir, or a run-dir test_cmd escalate before any call', async () => {
  const bads = [
    { ...CODE, test_dir: '' }, { ...CODE, test_cmd: '' }, { ...CODE, test_dir: '/tmp/sxs/x/test' },
    { ...CODE, test_dir: 'docs/temp/prd-audit/repro' }, { ...CODE, test_dir: '../test' },
    { ...CODE, test_cmd: `node --test ${RUN}/repro/` },
  ]
  for (const a of bads) {
    const r = await runCode({}, a)
    assert.equal(r.calls.length, 0, JSON.stringify({ d: a.test_dir, c: a.test_cmd }))
    assert.equal(r.result.status, 'escalate')
  }
})

await test('12. Verify stage runs a repro/mutation probe; a survivor or bad test blocks, then one fix and round 2', async () => {
  const r = await runCode()
  const p = r.calls.find((c) => c.kind === 'probe')
  assert.ok(p, 'probe ran')
  assert.ok(['haiku', 'sonnet'].includes(p.model), `probe model ${p.model}`)
  assert.match(p.prompt, /scratch/i)
  assert.match(p.prompt, /npm test/)
  assert.match(p.prompt, /AssertionError|assertion/i)
  assert.match(p.prompt, /TypeError/)
  assert.match(p.prompt, /source text/i)
  const bad = { checked: 4, bad_tests: ['test/repro-1.test.js: TypeError, not an assertion'], survivors: [], path: 'p' }
  const r2 = await runCode({ probe: (c, n) => n === 1 ? bad : CODE_HAPPY.probe })
  assert.deepEqual(kinds(r2.calls).slice(-5), ['verify', 'probe', 'synth', 'verify', 'probe'])
  const fix = r2.calls.filter((c) => c.kind === 'synth').pop()
  assert.match(fix.prompt, /repro-1\.test\.js: TypeError/)
  assert.equal(r2.calls.filter((c) => c.kind === 'probe').length, 2, 'probe re-runs in round 2')
  assert.equal(r2.result.status, 'complete')
  const r3 = await runCode({ probe: { checked: 4, bad_tests: [], survivors: ['RC-2 fix applied, test still fails'], path: 'p' } })
  assert.equal(r3.result.status, 'escalate')
  assert.match(r3.result.reason, /RC-2/)
})

await test('13. Fix direction: a fix that weakens a stated safety check is blocking', async () => {
  const r = await runCode()
  const v = r.calls.find((c) => c.kind === 'verify')
  assert.match(v.prompt, /FIX DIRECTION/)
  assert.match(v.prompt, /weaken/i)
  const w = { ...CODE_HAPPY.verify, weakens: ['RC-5a narrows detectContextRequest with no argument'] }
  const r2 = await runCode({ verify: (c, n) => n === 1 ? w : CODE_HAPPY.verify })
  const fix = r2.calls.filter((c) => c.kind === 'synth').pop()
  assert.match(fix.prompt, /RC-5a narrows/)
  assert.equal(r2.calls.filter((c) => c.kind === 'verify').length, 2)
})

await test('14. Doc audit (no repo): no writers lane, critic or probe', async () => {
  const r = await run()
  assert.ok(!kinds(r.calls).some((k) => ['critic', 'probe', 'gap'].includes(k)))
  assert.ok(!r.calls.some((c) => c.label === 'lane:writers'))
})

report('lo-audit')
