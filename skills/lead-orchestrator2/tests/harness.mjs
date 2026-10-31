// ABOUTME: Test harness for lead-orchestrator2 workflow scripts. It loads a workflow file,
// ABOUTME: strips `export`, and runs the body in an async function with stubbed hooks.
// ABOUTME: The stubs record every agent() call (label, model, prompt, opts) in call order.
// ABOUTME: Date.now(), argless new Date() and Math.random() throw, as in the real runtime.
// ABOUTME: Also exports a small test runner (test/report) so the suites need only `node`.
import { readFileSync } from 'node:fs'
import { fileURLToPath } from 'node:url'
import { dirname, join } from 'node:path'

export const WORKFLOWS = join(dirname(fileURLToPath(import.meta.url)), '..', 'workflows')
export const ALLOWED_MODELS = ['haiku', 'sonnet', 'opus']

// Purpose: run one workflow file against a scripted responder and capture what it did.
// Usage:   const r = await runWorkflow('lo-feature-task.js', {args, respond: (call, calls) => ...})
// Gotchas: `respond` gets {label, kind, model, prompt, opts}; kind = label text before ':'.
//          A responder that returns undefined stands for a dead agent (the runtime gives null).
export async function runWorkflow(file, { args, respond }) {
  const src = readFileSync(join(WORKFLOWS, file), 'utf8')
  if (!/^export const meta = \{/m.test(src)) throw new Error(`${file}: no leading export const meta`)
  const body = src.replace(/^export const meta =/m, '__meta.value =').replace(/^export\s+/gm, '')
  const calls = [], logs = [], phases = [], __meta = {}
  const agent = async (prompt, opts = {}) => {
    const label = opts.label || '(no label)'
    const call = { label, kind: label.split(':')[0], model: opts.model, prompt, opts }
    calls.push(call)
    const out = await respond(call, calls)
    return out === undefined ? null : out
  }
  const parallel = async (thunks) =>
    Promise.all(thunks.map((t) => Promise.resolve().then(t).catch(() => null)))
  const pipeline = async (items, ...stages) =>
    Promise.all(items.map(async (item, i) => {
      let v = item
      for (const s of stages) {
        try { v = await s(v, item, i) } catch { return null }
      }
      return v
    }))
  const FakeDate = function (...a) {
    if (!a.length) throw new Error('argless new Date() is not allowed in workflows')
    return new Date(...a)
  }
  FakeDate.now = () => { throw new Error('Date.now() is not allowed in workflows') }
  const FakeMath = Object.create(Math)
  FakeMath.random = () => { throw new Error('Math.random() is not allowed in workflows') }
  const AsyncFunction = Object.getPrototypeOf(async function () {}).constructor
  const fn = new AsyncFunction('agent', 'parallel', 'pipeline', 'phase', 'log', 'args',
    'budget', 'workflow', 'Date', 'Math', '__meta', body)
  const budget = { total: null, spent: () => 0, remaining: () => Infinity }
  const workflow = async () => { throw new Error('nested workflow() not stubbed') }
  const result = await fn(agent, parallel, pipeline, (t) => phases.push(t), (m) => logs.push(m),
    args, budget, workflow, FakeDate, FakeMath, __meta)
  return { result, calls, logs, phases, meta: __meta.value }
}

// Purpose: build a responder from per-kind handlers, falling back to happy-path defaults.
// Usage:   respond: responder(HAPPY, {'gate-red': () => ({...})})
// Gotchas: a handler may be a function (call, nthOfKind, calls) or a plain value.
export function responder(defaults, overrides = {}) {
  const seen = {}
  return (call, calls) => {
    seen[call.kind] = (seen[call.kind] || 0) + 1
    const h = call.kind in overrides ? overrides[call.kind] : defaults[call.kind]
    if (h === undefined) throw new Error(`no response for kind '${call.kind}' (label ${call.label})`)
    return typeof h === 'function' ? h(call, seen[call.kind], calls) : h
  }
}

const results = []
// Purpose: register and run one async test case; failures are recorded, not thrown.
// Usage:   await test('name', async () => { assert... })
// Gotchas: call report() at the end, or the exit code stays 0.
export async function test(name, fn) {
  try { await fn(); results.push([true, name]); console.log(`ok - ${name}`) }
  catch (e) { results.push([false, name]); console.log(`not ok - ${name}\n    ${e.message.split('\n').join('\n    ')}`) }
}

// Purpose: print the summary line and set the process exit code.
// Usage:   report('lo-feature-task') as the last line of a test file.
// Gotchas: the summary line format is "# <suite>: N passed, M failed".
export function report(suite) {
  const failed = results.filter((r) => !r[0]).length
  console.log(`# ${suite}: ${results.length - failed} passed, ${failed} failed`)
  process.exitCode = failed ? 1 : 0
}

export const kinds = (calls) => calls.map((c) => c.kind)
