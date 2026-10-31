// ABOUTME: Lexical tests for SKILL.md: feature mode must run plan, every task, then the close workflow.
// ABOUTME: Added in round 1 after tip-001: B's session stopped after a verifier FAIL, as the
// ABOUTME: old headless note told it to ("Do not relaunch on your own" + report partial).
// ABOUTME: These checks only prove the instructions exist; the scripts enforce the stage order.
// ABOUTME: Round 2 adds the debug-and-fix route (pm-login-002) and code-audit args (fix-ctx-002).
// ABOUTME: Run: node ~/.claude/skills/lead-orchestrator2/tests/test-skill-doc.mjs
import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import { join } from 'node:path'
import { WORKFLOWS, test, report } from './harness.mjs'

const doc = readFileSync(join(WORKFLOWS, '..', 'SKILL.md'), 'utf8')
const feature = doc.split('## MODE: feature')[1].split('## MODE: backlog')[0]

await test('1. Feature mode names the three scripts in order: plan, task, close', async () => {
  const a = feature.indexOf('lo-feature-plan.js'), b = feature.indexOf('lo-feature-task.js'), c = feature.indexOf('lo-feature-close.js')
  assert.ok(a >= 0 && b > a && c > b, `positions ${a} ${b} ${c}`)
})

await test('2. The close workflow is mandatory, whatever the task statuses', async () => {
  assert.match(feature, /ALWAYS launch `lo-feature-close\.js`/)
  assert.match(feature, /full suite/i)
})

await test('3. Headless escalate does not end the run before the close workflow', async () => {
  const headless = doc.split('**Headless note:**')[1].split('\n\n')[0]
  assert.match(headless, /lo-feature-close\.js/)
  assert.ok(!/report it as a `partial` result with the stage and reason, commit only the verified work, and continue/i.test(headless),
    'the old headless text that ended the run is still there')
})

const routing = doc.split('### Mode routing')[1].split('### Parameters')[0]
const audit = doc.split('## MODE: investigate-audit')[1].split('## MODE: live-debug')[0]

await test('4. Routing names the debug-and-fix route: independent diagnoser first, then feature F1-F3', async () => {
  const row = routing.split('\n').find((l) => /debug/i.test(l) && /fix/i.test(l) && /tests?/i.test(l) && l.startsWith('|'))
  assert.ok(row, 'no routing row for a debug + fix with tests ask')
  assert.match(row, /diagnos/i)
  assert.match(row, /lo-feature-plan\.js/)
  assert.match(row, /lo-feature-close\.js/)
  assert.match(doc, /### Debug and fix/)
  const dbg = doc.split('### Debug and fix')[1].split('\n## ')[0]
  assert.match(dbg, /opus/)
  assert.match(dbg, /never diagnose in the session|not in the session/i)
  assert.match(dbg, /every area/i)
  assert.match(routing, /live-debug[^\n]*browser|browser[^\n]*live-debug/i)
})

await test('5. Code audits pass repo, test_dir and test_cmd, and lanes split by failure path', async () => {
  assert.match(audit, /repo/)
  assert.match(audit, /test_dir/)
  assert.match(audit, /test_cmd/)
  assert.match(audit, /failure path|data flow/i)
  assert.match(audit, /writers/)
  assert.match(audit, /critic/i)
  assert.match(audit, /probe/i)
})

report('skill-doc')
