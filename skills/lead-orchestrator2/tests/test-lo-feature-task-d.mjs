// ABOUTME: Tests for workflows/lo-feature-task-d.js, the arm D workflow (SPEC.md §4).
// ABOUTME: Each case scripts the agent replies and asserts stage order, model usage, and gates.
// ABOUTME: Key tests: every agent names model, spec gate 2 rounds, no fix when clean, P0 triggers verifier.
// ABOUTME: Run: node ~/.claude/skills/lead-orchestrator2/tests/test-lo-feature-task-d.mjs
import assert from 'node:assert/strict'
import { runWorkflow, responder, test, report, kinds, ALLOWED_MODELS } from './harness.mjs'

const ARGS = {
  repo: '/repo', feat_id: 'FEAT-PT-12', task_id: 'T-001', task_label: 'Add feature X',
  req_ids: ['REQ-01', 'REQ-02'], requirements: 'docs/requirements.md', design: 'docs/design.md',
  run_dir: '/repo/.armd', base_ref: 'abc123', baseline_file: '/repo/baseline.txt',
  test_env: 'PT_TEST_PG_DSN=...', golden_ref: 'GET /api returns 200', codex: '/path/to/codex.mjs',
}
// REQ-09: Updated HAPPY to revision 2 with new required fields (kind, review_ok, final_ok)
const HAPPY = {
  time: null,
  runner: (call) => {
    if (call.label === 'runner:spec') return { passed: true, kind: 'pass', rounds: 1, open_items: [] }
    if (call.label === 'runner:review') return { req_rows_ok: true, review_ok: true, defects: [], pre_fix_sha: 'def456', open_items: [] }
    if (call.label === 'runner:final') return { open_p0p1: [], final_ok: true, src_files_changed: 0, open_items: [] }
    return null
  },
  codex: null,
  'gate-spec': { exit_code: 0, output: 'PASS' },
  commit: null,
  coder: { summary: 'wrote code' },
  'test-run': { exit_code: 0 },
  lint: { exit_code: 0 },
  'gate-req-rows': { exit_code: 0, output: 'ALL ROWS PRESENT (2)' },
  'parse-defects': { defects: [] },
  'count-src-files': { count: 0 },
  verifier: { blocking: [], met_rows_with_new_failures: 0 },
}

const run = (overrides = {}, args = ARGS) =>
  runWorkflow('lo-feature-task-d.js', { args, respond: responder(HAPPY, overrides) })

await test('1. Every agent call names a model', async () => {
  const r = await run()
  for (const c of r.calls) {
    assert.ok(ALLOWED_MODELS.includes(c.model), `${c.label} model=${c.model}`)
  }
})

await test('2. Spec gate fails: Opus resolver runs, then coder', async () => {
  const r = await run({ runner: (call) => {
    if (call.label === 'runner:spec') return { passed: false, kind: 'design', rounds: 1, open_items: ['P1: conflict'] }
    if (call.label === 'runner:spec-resolve-check') return { ok: true }
    if (call.label === 'runner:review') return { req_rows_ok: true, review_ok: true, defects: [], pre_fix_sha: 'def456', open_items: [] }
    return null
  }, resolve: { resolved: true, summary: 'settled P1' } })
  const resolveCall = r.calls.find(c => c.label === 'resolve:spec')
  assert.ok(resolveCall, 'resolver ran')
  assert.equal(resolveCall.model, 'opus')
  assert.ok(r.result.notes.some(i => /settled by opus/.test(i)))
  assert.equal(r.result.status, 'complete')
})

await test('3. No P0/P1, no lint hit: no fix runs, no final check', async () => {
  const r = await run()
  assert.ok(!kinds(r.calls).includes('coder-fix-1'))
  assert.ok(!r.calls.some(c => c.label.includes('final')))
  assert.equal(r.result.status, 'complete')
  assert.equal(r.result.rounds, 0)
})

await test('4. P0 with repro: fix round 1, empty still_open, no round 2', async () => {
  const r = await run({
    runner: (call) => {
      if (call.label === 'runner:spec') return { passed: true, kind: 'pass', rounds: 1, open_items: [] }
      if (call.label === 'runner:review') return { req_rows_ok: true, review_ok: true, defects: [{ id: 'D1', sev: 'P0', has_repro: true, file: 'src/x.py' }], pre_fix_sha: 'def456', open_items: [] }
      if (call.label === 'runner:final') return { open_p0p1: [], final_ok: true, src_files_changed: 0, open_items: [] }
      return null
    },
    coder: { summary: 'wrote code' },
    'coder-fix-1': { still_open: [] },
    verifier: { blocking: [] },
  })
  assert.equal(kinds(r.calls).filter(k => k === 'coder' || k === 'coder-fix-1').length, 2)
  assert.equal(r.result.status, 'complete')
  assert.equal(r.result.rounds, 1)
})

await test('5. Non-empty still_open: round 2 runs', async () => {
  const r = await run({
    runner: (call) => {
      if (call.label === 'runner:spec') return { passed: true, kind: 'pass', rounds: 1, open_items: [] }
      if (call.label === 'runner:review') return { req_rows_ok: true, review_ok: true, defects: [{ id: 'D1', sev: 'P1', has_repro: true, file: 'src/x.py' }], pre_fix_sha: 'def456', open_items: [] }
      if (call.label === 'runner:final') return { open_p0p1: [], final_ok: true, src_files_changed: 0, open_items: [] }
      return null
    },
    coder: { summary: 'wrote code' },
    'coder-fix-1': { still_open: ['D1'] },
    'coder-fix-2': { summary: 'fixed D1' },
  })
  assert.equal(kinds(r.calls).filter(k => k === 'coder' || k === 'coder-fix-1' || k === 'coder-fix-2').length, 3)
  assert.equal(r.result.rounds, 2)
})

await test('6. Exactly one final review after fix (arm D has no test run stage)', async () => {
  const r = await run({
    runner: (call) => {
      if (call.label === 'runner:spec') return { passed: true, kind: 'pass', rounds: 1, open_items: [] }
      if (call.label === 'runner:review') return { req_rows_ok: true, review_ok: true, defects: [{ id: 'D1', sev: 'P1', has_repro: true, file: 'src/x.py' }], pre_fix_sha: 'def456', open_items: [] }
      if (call.label === 'runner:final') return { open_p0p1: [], final_ok: true, src_files_changed: 0, open_items: [] }
      return null
    },
    coder: { summary: 'wrote code' },
    'coder-fix-1': { still_open: [] },
  })
  assert.equal(r.calls.filter(c => c.label === 'runner:final').length, 1)
})

await test('7. P0 starts verifier', async () => {
  const r = await run({
    runner: (call) => {
      if (call.label === 'runner:spec') return { passed: true, kind: 'pass', rounds: 1, open_items: [] }
      if (call.label === 'runner:review') return { req_rows_ok: true, review_ok: true, defects: [{ id: 'D1', sev: 'P0', has_repro: true, file: 'src/x.py' }], pre_fix_sha: 'def456', open_items: [] }
      if (call.label === 'runner:final') return { open_p0p1: [], final_ok: true, src_files_changed: 0, open_items: [] }
      return null
    },
    coder: { summary: 'wrote code' },
    'coder-fix-1': { still_open: [] },
    verifier: { blocking: [] },
  })
  assert.ok(kinds(r.calls).includes('verifier'))
  assert.equal(r.result.verifier_ran, true)
})

await test('8. Final review with unfixed defects gives status partial (arm D has no lint stage)', async () => {
  const r = await run({
    runner: (call) => {
      if (call.label === 'runner:spec') return { passed: true, kind: 'pass', rounds: 1, open_items: [] }
      if (call.label === 'runner:review') return { req_rows_ok: true, review_ok: true, defects: [{ id: 'D1', sev: 'P1', has_repro: true, file: 'src/x.py' }], pre_fix_sha: 'def456', open_items: [] }
      if (call.label === 'runner:final') return { open_p0p1: ['D1'], final_ok: true, src_files_changed: 0, open_items: [] }
      return null
    },
    coder: { summary: 'wrote code' },
    'coder-fix-1': { still_open: [] },
  })
  assert.equal(r.result.status, 'partial')
  assert.ok(r.result.open_items.some(i => /P0\/P1 still open/.test(i)))
})

await test('9. P2 defects go to notes and never reach fix prompt', async () => {
  const r = await run({
    runner: (call) => {
      if (call.label === 'runner:spec') return { passed: true, kind: 'pass', rounds: 1, open_items: [] }
      if (call.label === 'runner:review') return { req_rows_ok: true, review_ok: true, defects: [{ id: 'D1', sev: 'P2', has_repro: true, file: 'src/x.py', what: 'minor issue' }], pre_fix_sha: 'def456', open_items: [] }
      return null
    },
    coder: { summary: 'wrote code' },
  })
  assert.ok(!kinds(r.calls).includes('coder-fix-1'))
  assert.equal(r.result.rounds, 0)
  assert.ok(r.result.notes.some(n => /P2 D1/.test(n)))
  assert.equal(r.result.status, 'complete')
})

await test('10. No agent prompt contains banned word', async () => {
  const r = await run()
  const banned = 'adver' + 'sarial'
  for (const c of r.calls) {
    assert.ok(typeof c.prompt === 'string', `${c.label} has prompt`)
    assert.ok(!c.prompt.includes(banned), `${c.label} prompt contains banned word`)
  }
})

// ---- Spec gate (owner, 2026-11-15): Codex runs once; P0/P1 go to one opus resolver, then code ----
// REQ-09: Updated for revision 2 labels + new fields (kind, review_ok, final_ok, notes).
const REV2 = (spec, coder = { summary: 'wrote code' }, resolve = { resolved: true, summary: 'settled' }, specResolveCheck = { ok: true }) => (call) => {
  if (call.label === 'runner:spec') return spec
  if (call.label === 'resolve:spec') return resolve
  if (call.label === 'runner:spec-resolve-check') return specResolveCheck
  if (call.label === 'runner:review') return { req_rows_ok: true, review_ok: true, defects: [], pre_fix_sha: 'def456', open_items: [] }
  if (call.label === 'runner:final') return { open_p0p1: [], final_ok: true, src_files_changed: 0, open_items: [] }
  if (call.label === 'coder') return coder
  if (call.label === 'coder-fix-1') return coder
  if (call.label === 'coder-fix-2') return coder
  throw new Error(`unexpected agent ${call.label}`)
}
const runRev2 = (respond) => runWorkflow('lo-feature-task-d.js', { args: ARGS, respond })
const FAILED = { passed: false, kind: 'design', rounds: 1, open_items: ['P1: conflict in REQ-01'] }

await test('11. Failed spec goes to one opus resolver, then the coder; Codex runs once', async () => {
  const r = await runRev2(REV2(FAILED))
  assert.deepEqual(r.calls.map((c) => c.label), ['runner:spec', 'resolve:spec', 'runner:spec-resolve-check', 'coder', 'runner:review'])
  assert.equal(r.calls[1].model, 'opus')
  assert.ok(r.calls[1].prompt.includes('Read every file it names'))
  assert.equal(r.result.status, 'complete')
  assert.ok(r.result.notes.some((i) => /settled by opus/.test(i)))
})

await test('12. Dead spec runner escalates and the coder never runs', async () => {
  const r = await runRev2(REV2(undefined))
  assert.deepEqual(r.calls.map((c) => c.label), ['runner:spec'])
  assert.equal(r.result.status, 'escalate')
})

await test('13. A non-boolean passed value goes to the resolver, not straight to the coder', async () => {
  const r = await runRev2(REV2({ passed: 'true', kind: 'design', rounds: 1, open_items: [] }))
  assert.equal(r.calls[1].label, 'resolve:spec')
})

await test('13b. Resolver that needs the owner, or dies, escalates before the coder', async () => {
  for (const resolve of [{ resolved: false, summary: 'needs spend' }, null]) {
    const r = await runRev2(REV2(FAILED, undefined, resolve))
    assert.deepEqual(r.calls.map((c) => c.label), ['runner:spec', 'resolve:spec'])
    assert.equal(r.result.status, 'escalate')
  }
})

await test('14. Coder checks the pass file, and a missing file escalates before review', async () => {
  const r = await runRev2(REV2({ passed: true, kind: 'pass', rounds: 1, open_items: [] }, { summary: 'SPEC GATE NOT PASSED' }))
  const coder = r.calls.find((c) => c.label === 'coder')
  assert.ok(coder, 'coder must have run')
  assert.ok(coder.prompt && coder.prompt.includes('test -f "/repo/.armd/spec-gate.pass"'))
  assert.ok(!r.calls.some((c) => c.label === 'runner:review'))
  assert.equal(r.result.status, 'escalate')
})

await test('15. Passed spec gate skips the resolver and reaches coder then review', async () => {
  const r = await runRev2(REV2({ passed: true, kind: 'pass', rounds: 1, open_items: [] }))
  assert.deepEqual(r.calls.map((c) => c.label), ['runner:spec', 'coder', 'runner:review'])
  assert.equal(r.result.status, 'complete')
})

// REQ-01: Status function tests - partial states
await test('REQ-01a: Dead review runner gives partial', async () => {
  const r = await runRev2((call) => {
    if (call.label === 'runner:spec') return { passed: true, kind: 'pass', rounds: 1, open_items: [] }
    if (call.label === 'coder') return { summary: 'wrote code' }
    if (call.label === 'runner:review') return null
    return null
  })
  assert.equal(r.result.status, 'partial')
})

await test('REQ-01b: Review parse fail (review_ok:false) gives partial', async () => {
  const r = await runRev2((call) => {
    if (call.label === 'runner:spec') return { passed: true, kind: 'pass', rounds: 1, open_items: [] }
    if (call.label === 'runner:review') return { req_rows_ok: true, review_ok: false, defects: [], pre_fix_sha: 'def456', open_items: ['parse failed'] }
    if (call.label === 'coder') return { summary: 'wrote code' }
    return null
  })
  assert.equal(r.result.status, 'partial')
})

await test('REQ-01c: req_rows_ok:false gives partial', async () => {
  const r = await runRev2((call) => {
    if (call.label === 'runner:spec') return { passed: true, kind: 'pass', rounds: 1, open_items: [] }
    if (call.label === 'runner:review') return { req_rows_ok: false, review_ok: true, defects: [], pre_fix_sha: 'def456', open_items: ['missing REQ-02'] }
    if (call.label === 'coder') return { summary: 'wrote code' }
    return null
  })
  assert.equal(r.result.status, 'partial')
})

await test('REQ-01d: Dead final runner gives partial', async () => {
  const r = await runRev2((call) => {
    if (call.label === 'runner:spec') return { passed: true, kind: 'pass', rounds: 1, open_items: [] }
    if (call.label === 'runner:review') return { req_rows_ok: true, review_ok: true, defects: [{ id: 'D1', sev: 'P1', has_repro: true, file: 'x.py' }], pre_fix_sha: 'def456', open_items: [] }
    if (call.label === 'runner:final') return null
    if (call.label === 'coder') return { summary: 'wrote code' }
    if (call.label === 'coder-fix-1') return { still_open: [] }
    return null
  })
  assert.equal(r.result.status, 'partial')
})

await test('REQ-01e: Final parse fail (final_ok:false) gives partial', async () => {
  const r = await runRev2((call) => {
    if (call.label === 'runner:spec') return { passed: true, kind: 'pass', rounds: 1, open_items: [] }
    if (call.label === 'runner:review') return { req_rows_ok: true, review_ok: true, defects: [{ id: 'D1', sev: 'P1', has_repro: true, file: 'x.py' }], pre_fix_sha: 'def456', open_items: [] }
    if (call.label === 'runner:final') return { open_p0p1: [], final_ok: false, src_files_changed: 0, open_items: ['parse failed'] }
    if (call.label === 'coder') return { summary: 'wrote code' }
    if (call.label === 'coder-fix-1') return { still_open: [] }
    return null
  })
  assert.equal(r.result.status, 'partial')
})

await test('REQ-01f: Final open_p0p1 non-empty gives partial', async () => {
  const r = await runRev2((call) => {
    if (call.label === 'runner:spec') return { passed: true, kind: 'pass', rounds: 1, open_items: [] }
    if (call.label === 'runner:review') return { req_rows_ok: true, review_ok: true, defects: [{ id: 'D1', sev: 'P1', has_repro: true, file: 'x.py' }], pre_fix_sha: 'def456', open_items: [] }
    if (call.label === 'runner:final') return { open_p0p1: ['D1'], final_ok: true, src_files_changed: 0, open_items: [] }
    if (call.label === 'coder') return { summary: 'wrote code' }
    if (call.label === 'coder-fix-1') return { still_open: [] }
    return null
  })
  assert.equal(r.result.status, 'partial')
})

await test('REQ-01g: Verifier blocking non-empty gives partial', async () => {
  const r = await runRev2((call) => {
    if (call.label === 'runner:spec') return { passed: true, kind: 'pass', rounds: 1, open_items: [] }
    if (call.label === 'runner:review') return { req_rows_ok: true, review_ok: true, defects: [{ id: 'D1', sev: 'P1', has_repro: true, file: 'x.py' }], pre_fix_sha: 'def456', open_items: [] }
    if (call.label === 'runner:final') return { open_p0p1: [], final_ok: true, src_files_changed: 3, open_items: [] }
    if (call.label === 'verifier:final') return { blocking: ['V1: test fails'] }
    if (call.label === 'coder') return { summary: 'wrote code' }
    if (call.label === 'coder-fix-1') return { still_open: [] }
    return null
  })
  assert.equal(r.result.status, 'partial')
})

await test('REQ-01h: Dead verifier (null) gives partial', async () => {
  const r = await runRev2((call) => {
    if (call.label === 'runner:spec') return { passed: true, kind: 'pass', rounds: 1, open_items: [] }
    if (call.label === 'runner:review') return { req_rows_ok: true, review_ok: true, defects: [{ id: 'D1', sev: 'P1', has_repro: true, file: 'x.py' }], pre_fix_sha: 'def456', open_items: [] }
    if (call.label === 'runner:final') return { open_p0p1: [], final_ok: true, src_files_changed: 3, open_items: [] }
    if (call.label === 'verifier:final') return null
    if (call.label === 'coder') return { summary: 'wrote code' }
    if (call.label === 'coder-fix-1') return { still_open: [] }
    return null
  })
  assert.equal(r.result.status, 'partial')
})

// Final verifier result with no valid blocking list must fail closed (FINAL.md section 7 open item).
const verifierCase = (verifier) => runRev2((call) => {
  if (call.label === 'runner:spec') return { passed: true, kind: 'pass', rounds: 1, open_items: [] }
  if (call.label === 'runner:review') return { req_rows_ok: true, review_ok: true, defects: [{ id: 'D1', sev: 'P1', has_repro: true, file: 'x.py' }], pre_fix_sha: 'def456', open_items: [] }
  if (call.label === 'runner:final') return { open_p0p1: [], final_ok: true, src_files_changed: 3, open_items: [] }
  if (call.label === 'verifier:final') return verifier
  if (call.label === 'coder') return { summary: 'wrote code' }
  if (call.label === 'coder-fix-1') return { still_open: [] }
  return null
})

await test('REQ-01j: Final verifier {} / blocking null / blocking string gives partial', async () => {
  for (const v of [{}, { blocking: null }, { blocking: 'V1' }]) {
    const r = await verifierCase(v)
    assert.equal(r.result.status, 'partial', `verifier ${JSON.stringify(v)}`)
  }
})

await test('REQ-01k: Final verifier with an empty blocking list still gives complete', async () => {
  const r = await verifierCase({ blocking: [] })
  assert.equal(r.result.status, 'complete')
})

await test('REQ-01i: Round 2 with empty final open_p0p1 gives complete', async () => {
  const r = await run({
    runner: (call) => {
      if (call.label === 'runner:spec') return { passed: true, kind: 'pass', rounds: 1, open_items: [] }
      if (call.label === 'runner:review') return { req_rows_ok: true, review_ok: true, defects: [{ id: 'D1', sev: 'P1', has_repro: true, file: 'x.py' }], pre_fix_sha: 'def456', open_items: [] }
      if (call.label === 'runner:final') return { open_p0p1: [], final_ok: true, src_files_changed: 0, open_items: [] }
      return null
    },
    coder: { summary: 'wrote code' },
    'coder-fix-1': { still_open: ['D1'] },
    'coder-fix-2': { summary: 'fixed D1' },
  })
  assert.equal(r.result.status, 'complete')
})

// F01: No-fix case with P0/P1 defects gives partial
await test('F01: No fix with P1 defect without repro gives partial', async () => {
  const r = await runRev2((call) => {
    if (call.label === 'runner:spec') return { passed: true, kind: 'pass', rounds: 1, open_items: [] }
    if (call.label === 'runner:review') return { req_rows_ok: true, review_ok: true, defects: [{ id: 'D1', sev: 'P1', has_repro: false, file: 'x.py' }], pre_fix_sha: 'def456', open_items: [] }
    if (call.label === 'coder') return { summary: 'wrote code' }
    return null
  })
  assert.equal(r.result.status, 'partial')
  assert.ok(r.result.open_items.some((i) => /P0\/P1 defects present/.test(i)))
})

// F02: Null final lists give partial
await test('F02: Null open_p0p1 gives partial', async () => {
  const r = await runRev2((call) => {
    if (call.label === 'runner:spec') return { passed: true, kind: 'pass', rounds: 1, open_items: [] }
    if (call.label === 'runner:review') return { req_rows_ok: true, review_ok: true, defects: [{ id: 'D1', sev: 'P1', has_repro: true, file: 'x.py' }], pre_fix_sha: 'def456', open_items: [] }
    if (call.label === 'runner:final') return { open_p0p1: null, final_ok: true, src_files_changed: 0, open_items: [] }
    if (call.label === 'coder') return { summary: 'wrote code' }
    if (call.label === 'coder-fix-1') return { still_open: [] }
    return null
  })
  assert.equal(r.result.status, 'partial')
  assert.ok(r.result.open_items.some((i) => /null or missing/.test(i)))
})

// F03: Strict checks for missing fields
await test('F03: Missing review result gives partial', async () => {
  const r = await runRev2((call) => {
    if (call.label === 'runner:spec') return { passed: true, kind: 'pass', rounds: 1, open_items: [] }
    if (call.label === 'runner:review') return null
    if (call.label === 'coder') return { summary: 'wrote code' }
    return null
  })
  assert.equal(r.result.status, 'partial')
  assert.ok(r.result.open_items.some((i) => /review runner failed/.test(i)))
})

// F04: Dead coder escalates
await test('F04: Null coder result escalates', async () => {
  const r = await runRev2((call) => {
    if (call.label === 'runner:spec') return { passed: true, kind: 'pass', rounds: 1, open_items: [] }
    if (call.label === 'coder') return null
    return null
  })
  assert.equal(r.result.status, 'escalate')
  assert.match(r.result.reason, /coder returned nothing/)
})

// REQ-03: notes vs open_items split
await test('REQ-03: Spec verdict in notes, not open_items when complete', async () => {
  const r = await runRev2((call) => {
    if (call.label === 'runner:spec') return { passed: true, kind: 'pass', rounds: 1, open_items: ['NO CONFLICTS'] }
    if (call.label === 'runner:review') return { req_rows_ok: true, review_ok: true, defects: [], pre_fix_sha: 'def456', open_items: [] }
    if (call.label === 'coder') return { summary: 'wrote code' }
    return null
  })
  assert.equal(r.result.status, 'complete')
  assert.equal(r.result.open_items.length, 0)
  assert.ok(r.result.notes.some((n) => /NO CONFLICTS/.test(n)))
})

// REQ-04: infra vs design kind
await test('REQ-04a: Missing input gives kind:infra and escalate', async () => {
  const r = await runRev2((call) => {
    if (call.label === 'runner:spec') return { passed: false, kind: 'infra', rounds: 0, open_items: ['input file missing'] }
    return null
  })
  assert.equal(r.result.status, 'escalate')
  assert.ok(!r.calls.some((c) => c.label === 'resolve:spec'))
})

await test('REQ-04b: Codex empty twice gives kind:infra and escalate', async () => {
  const r = await runRev2((call) => {
    if (call.label === 'runner:spec') return { passed: false, kind: 'infra', rounds: 1, open_items: ['codex returned empty verdict twice'] }
    return null
  })
  assert.equal(r.result.status, 'escalate')
  assert.ok(!r.calls.some((c) => c.label === 'resolve:spec'))
})

await test('REQ-04c: Design fail goes to resolver', async () => {
  const r = await runRev2(REV2({ passed: false, kind: 'design', rounds: 1, open_items: ['P1: conflict'] }))
  assert.ok(r.calls.some((c) => c.label === 'resolve:spec'))
})

// REQ-05: resolve check
await test('REQ-05: Resolver true + check ok:false escalates before coder', async () => {
  const r = await runRev2(REV2(FAILED, undefined, { resolved: true, summary: 'settled' }, { ok: false, reason: 'requirements changed' }))
  assert.deepEqual(r.calls.map((c) => c.label), ['runner:spec', 'resolve:spec', 'runner:spec-resolve-check'])
  assert.equal(r.result.status, 'escalate')
})

// REQ-06: golden_ref in prompts
await test('REQ-06: golden_ref appears in coder prompt', async () => {
  const argsWithRef = { ...ARGS, golden_ref: "docs/explainer.md says X" }
  const r = await run({}, argsWithRef)
  const coderCall = r.calls.find((c) => c.label === 'coder')
  assert.ok(coderCall, 'coder ran')
  assert.match(coderCall.prompt, /Golden reference: docs\/explainer\.md says X/)
  assert.match(coderCall.prompt, /When files clash.*owner's product docs/)
})

// REQ-08: unmapped requirements
await test('REQ-08a: Close with unmapped req gives partial', async () => {
  const closeArgs = { ...ARGS, close: true, unmapped: ['REQ-41'] }
  const r = await run({}, closeArgs)
  assert.equal(r.result.status, 'partial')
  assert.ok(r.result.open_items.some((i) => /requirement has no task: REQ-41/.test(i)))
})

await test('REQ-08b: Close with plan unmapped shape maps correctly', async () => {
  const closeArgs = { ...ARGS, close: true, unmapped: [{ req_id: 'REQ-42', what: 'feature X' }].map((q) => q.req_id) }
  const r = await run({}, closeArgs)
  assert.equal(r.result.status, 'partial')
  assert.ok(r.result.open_items.some((i) => /requirement has no task: REQ-42/.test(i)))
  assert.ok(!r.result.open_items.some((i) => /\[object Object\]/.test(i)))
})

// F13: Valid-path tests for spec stage
await test('F13a: Valid NO CONFLICTS verdict gives kind:pass', async () => {
  const r = await run({ runner: (call) => {
    if (call.label === 'runner:spec') return { passed: true, kind: 'pass', rounds: 1, open_items: ['NO CONFLICTS'] }
    if (call.label === 'runner:review') return { req_rows_ok: true, review_ok: true, defects: [], pre_fix_sha: 'def456', open_items: [] }
    return null
  }})
  assert.equal(r.result.status, 'complete')
  assert.ok(r.result.notes.some((n) => /spec resolved.*NO CONFLICTS/.test(n) || n === 'NO CONFLICTS'))
})

await test('F13b: Valid P1 conflict verdict gives kind:design and goes to resolver', async () => {
  const r = await runRev2((call) => {
    if (call.label === 'runner:spec') return { passed: false, kind: 'design', rounds: 1, open_items: ['P1: field X clashes'] }
    if (call.label === 'resolve:spec') return { resolved: true, summary: 'settled' }
    if (call.label === 'runner:spec-resolve-check') return { ok: true }
    if (call.label === 'runner:review') return { req_rows_ok: true, review_ok: true, defects: [], pre_fix_sha: 'def456', open_items: [] }
    if (call.label === 'coder') return { summary: 'wrote code' }
    return null
  })
  assert.ok(r.calls.some((c) => c.label === 'resolve:spec'), 'resolver must run for design conflicts')
  assert.ok(r.calls.some((c) => c.label === 'coder'), 'coder runs after resolver')
  assert.equal(r.result.status, 'complete')
})

report('lo-feature-task-d')
