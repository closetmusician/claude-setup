export const meta = {
  name: 'lo-backlog',
  description: 'backlog wave: one coder per item, QA cycle-1 over the wave, then the wave verifier (always)',
  whenToUse: 'lead-orchestrator2 backlog mode, one wave per launch',
  phases: [
    { title: 'Coders', detail: 'one sonnet coder per item, RED-first unit tests', model: 'sonnet' },
    { title: 'QA', detail: 'cycle-1 over the wave diffs (qa_cycles >= 1)', model: 'sonnet' },
    { title: 'Verify', detail: 'wave verifier, always runs, max 2 rounds', model: 'opus' },
  ],
}
// ABOUTME: Workflow script for lead-orchestrator2 backlog mode: one wave of independent items.
// ABOUTME: Items in one wave must not share files; the script rejects an overlap before any agent.
// ABOUTME: QA cycle-1 runs when qa_cycles >= 1. The wave verifier ALWAYS runs, even after a failure,
// ABOUTME: so the session can check off only the items in verified_items.
// ABOUTME: Tests: ../tests/test-lo-backlog.mjs. Spec: ~/.claude/docs/plans/opus55-rollout/LO2-SPEC.md.
// NOTE: every agent call names its model inline. workflow-model-guard.sh checks this lexically.

const TPL = '/Users/yklin/.claude/skills/lead-orchestrator/templates'
const INT = { type: 'integer' }
const STR = { type: 'string' }
const STRS = { type: 'array', items: STR }
const ART = { type: 'object', properties: { verdict: STR, path: STR }, required: ['verdict', 'path'] }
const C1 = { type: 'object', properties: { verdict: { type: 'string', enum: ['PASS', 'FAIL', 'PASS_WITH_CONCERNS'] },
  path: STR, failing_items: STRS }, required: ['verdict', 'path', 'failing_items'] }
const VERIFY = { type: 'object', properties: { verified: INT, unverified: INT, contradicted: INT, blocking: STRS,
  verified_items: STRS, path: STR }, required: ['verified', 'unverified', 'contradicted', 'blocking', 'verified_items', 'path'] }

// ---- Arguments ---------------------------------------------------------------------------
const A = args || {}
const fail = (reason) => ({ status: 'escalate', stage: 'args', reason, verified_items: [], unverified_items: [], holes: [], counts: null, open_items: [] })
const missing = ['repo', 'run_dir', 'spec_path', 'test_cmd', 'golden_ref'].filter((k) => typeof A[k] !== 'string' || !A[k].trim())
if (missing.length) return fail(`missing args: ${missing.join(', ')}`)
if (!Array.isArray(A.items) || !A.items.length) return fail('items must be a non-empty array of {id, description, files}')
const badItem = A.items.find((it) => !it || !it.id || !it.description || !Array.isArray(it.files) || !it.files.length)
if (badItem) return fail(`bad item ${JSON.stringify(badItem)}: needs id, description and a non-empty files list`)
// Conflict pre-flight: no two agents in one wave may touch the same file.
const owner = {}
const overlaps = []
for (const it of A.items) for (const f of it.files) {
  if (owner[f] && owner[f] !== it.id) overlaps.push(`${f} (${owner[f]}, ${it.id})`)
  owner[f] = owner[f] || it.id
}
if (overlaps.length) return fail(`items in one wave share files: ${overlaps.join('; ')}. Split them into separate waves.`)
const QA_CYCLES = Number.isInteger(A.qa_cycles) ? A.qa_cycles : 1
const ids = A.items.map((it) => it.id)
const verification = `${A.run_dir}/verification.md`
const cycle1 = `${A.run_dir}/cycle-1.md`
const readyFile = (it) => `${A.run_dir}/${it.id}-ready-for-review.md`
const open_items = []
let counts = null

// Purpose: coder prompt for one backlog item, from templates/coder-prompt.md with MODE=backlog.
// Usage:   coderPrompt(item, '') or coderPrompt(item, 'fix note')
// Gotchas: the first line must be the backlog GOVERNANCE_EXEMPT line (SKILL.md sanctions it here).
const coderPrompt = (it, note) => [
  'GOVERNANCE_EXEMPT (mode=backlog — no acceptance-test pipeline in this mode; verifier stage still mandatory)',
  `Read ${TPL}/coder-prompt.md with the Read tool. It is your complete instruction set.`,
  'Substitute these placeholder values everywhere they appear, then follow the template exactly:',
  `- {TASK_ID} = ${it.id}`, '- {MODE} = backlog', `- {RUN_DIR} = ${A.run_dir}`, `- {SPEC_PATH} = ${A.spec_path}`,
  '- {ACCEPTANCE_TESTS_RED_SHA} = N/A (backlog mode)', '- {ARCH_DESIGN_PATH} = N/A', '- {ROOT_CAUSE} = N/A (backlog mode)',
  `- {REQUIREMENT_MAP_JSON} = ${it.req_map ? JSON.stringify(it.req_map) : `build it from the item text: task_id ${it.id}, one requirement per behavior`}`,
  `- {ESCALATION_CONDITIONS} = the item needs design, or touches files beyond: ${it.files.join(', ')}`,
  `- {TASK_DESCRIPTION} = ${it.description}`,
  `Work in ${A.repo}. Touch only these files and their tests: ${it.files.join(', ')}. Other agents share this tree.`,
  `Unit tests RED-first, commit per item. Write ${readyFile(it)}.`,
  note ? `FIX ROUND: ${note}` : '',
].join('\n')

// Purpose: run one coder for an item, re-spawning once if the agent returns nothing.
// Usage:   const r = await coderRun(item, '', '')   or coderRun(item, note, ':fix')
// Gotchas: returns null for a dead item; the caller records it as a hole.
async function coderRun(it, note, suffix) {
  let r = await agent(coderPrompt(it, note), { label: `coder:${it.id}${suffix}`, phase: 'Coders', model: 'sonnet', schema: ART })
  if (!r && !suffix) r = await agent(coderPrompt(it, 'the previous coder returned nothing'), { label: `coder:${it.id}:retry`, phase: 'Coders', model: 'sonnet', schema: ART })
  return r
}

// ---- Coders ------------------------------------------------------------------------------
phase('Coders')
const coded = await pipeline(A.items, (it) => coderRun(it, '', ''))
const holes = A.items.filter((it, i) => !coded[i]).map((it) => it.id)
if (holes.length) log(`Items with no coder output after one re-run (holes): ${holes.join(', ')}`)
const done = A.items.filter((it, i) => coded[i])
let escalation = null

// ---- QA cycle-1 over the wave (qa_cycles >= 1) -------------------------------------------
const c1Prompt = (round) => [
  `Read ${TPL}/qa-prompt.md with the Read tool. It is your complete instruction set.`,
  'Substitute these placeholder values everywhere they appear, then follow the template exactly:',
  '- {TASK_ID} = wave', '- {MODE} = backlog', '- {QA_PHASE} = cycle-1', '- {QA_GOVERNANCE_ROLE} = qa-tester',
  `- {RUN_DIR} = ${A.run_dir}`, `- {SPEC_PATH} = ${A.spec_path}`, '- {ARCH_DESIGN_PATH} = N/A',
  `- {PHASE_INPUTS} = ${done.map(readyFile).join(', ')}`, `- {LIVE_TARGET} = ${A.test_cmd}`,
  `- {REQUIREMENT_MAP_JSON} = one requirement per item: ${done.map((it) => `${it.id}: ${it.description}`).join(' | ')}`,
  '- {ESCALATION_CONDITIONS} = a change breaks behavior outside its item',
  `Scope: the diffs of items ${done.map((it) => it.id).join(', ')} in ${A.repo}. Try to break the changed behavior.`,
  `Write ${cycle1}${round > 1 ? ' (append a ## Round 2 section)' : ''}. Put the ids of failing items in failing_items.`,
].join('\n')
if (QA_CYCLES >= 1 && done.length) {
  phase('QA')
  let c1 = await agent(c1Prompt(1), { label: 'c1', phase: 'QA', model: 'sonnet', schema: C1 })
  if (!c1) c1 = await agent(c1Prompt(1), { label: 'c1:retry', phase: 'QA', model: 'sonnet', schema: C1 })
  if (!c1) escalation = { stage: 'QA', reason: 'QA cycle-1 returned nothing twice' }
  else if (c1.verdict === 'FAIL') {
    const failing = done.filter((it) => c1.failing_items.includes(it.id))
    const targets = failing.length ? failing : done
    await pipeline(targets, (it) => coderRun(it, `QA cycle-1 found bugs in this item. Read ${cycle1} and fix every one.`, ':fix'))
    c1 = await agent(c1Prompt(2), { label: 'c1:round2', phase: 'QA', model: 'sonnet', schema: C1 })
    if (!c1 || c1.verdict === 'FAIL') {
      escalation = { stage: 'QA', reason: `cycle-1 still FAIL after one fix cycle (N=1): ${c1 ? c1.failing_items.join(', ') : 'no output'}` }
    }
  }
  if (c1 && c1.verdict === 'PASS_WITH_CONCERNS') open_items.push(`cycle-1 PASS_WITH_CONCERNS: see ${cycle1}`)
}

// ---- Wave verifier (ALWAYS runs) ---------------------------------------------------------
phase('Verify')
const verifyPrompt = (round, claims) => [
  `Read ${TPL}/qa-prompt.md with the Read tool. It is your complete instruction set.`,
  'Substitute these placeholder values everywhere they appear, then follow the template exactly:',
  '- {TASK_ID} = wave', '- {MODE} = backlog', '- {QA_PHASE} = verify', '- {QA_GOVERNANCE_ROLE} = verifier',
  `- {RUN_DIR} = ${A.run_dir}`, `- {SPEC_PATH} = ${A.spec_path}`, '- {ARCH_DESIGN_PATH} = N/A',
  `- {PHASE_INPUTS} = ${[...done.map(readyFile), QA_CYCLES >= 1 ? cycle1 : ''].filter(Boolean).join(', ') || 'none'}`,
  `- {LIVE_TARGET} = ${A.test_cmd}`,
  `- {REQUIREMENT_MAP_JSON} = one requirement per item: ${A.items.map((it) => `${it.id}: ${it.description}`).join(' | ')}`,
  '- {ESCALATION_CONDITIONS} = the suite fails, or an item claim cannot be re-derived',
  `GOLDEN REFERENCE (what correct means): ${A.golden_ref}`,
  `Re-run ${A.test_cmd} yourself in ${A.repo}. Spec-diff each item claim to file:line. Write ${verification}.`,
  holes.length ? `Items with no coder output (never mark them verified): ${holes.join(', ')}` : '',
  'verified_items = the ids of items whose every claim you VERIFIED. Scope lock: these items only.',
  round === 2 ? `ROUND 2 of 2 (final). Re-verify ONLY these fixed claims: ${claims}. Append a ## Round 2 section.` : '',
].join('\n')
const isBlocking = (v) => v.contradicted > 0 || v.blocking.length > 0
let ver = await agent(verifyPrompt(1, ''), { label: 'verify', phase: 'Verify', model: 'opus', schema: VERIFY })
if (!ver) ver = await agent(verifyPrompt(1, ''), { label: 'verify:retry', phase: 'Verify', model: 'opus', schema: VERIFY })
if (ver && isBlocking(ver) && !escalation) {
  const list = ver.blocking.join('; ') || `${ver.contradicted} CONTRADICTED claims`
  const hit = done.filter((it) => list.includes(it.id))
  await pipeline(hit.length ? hit : done, (it) => coderRun(it, `The verifier marked these BLOCKING in ${verification}: ${list}. Fix the ones in this item.`, ':fix-verify'))
  ver = await agent(verifyPrompt(2, list), { label: 'verify:round2', phase: 'Verify', model: 'opus', schema: VERIFY })
  if (!ver || isBlocking(ver)) escalation = { stage: 'Verify', reason: `verifier round 2 still blocking: ${ver ? ver.blocking.join('; ') : 'no output'}` }
} else if (ver && isBlocking(ver)) {
  open_items.push(`verifier BLOCKING (not fixed, wave already escalated): ${ver.blocking.join('; ')}`)
}
if (!ver && !escalation) escalation = { stage: 'Verify', reason: 'the wave verifier returned nothing twice' }

const verified_items = ver ? ids.filter((id) => ver.verified_items.includes(id) && !holes.includes(id)) : []
const unverified_items = ids.filter((id) => !verified_items.includes(id))
counts = ver ? { verified: ver.verified, unverified: ver.unverified, contradicted: ver.contradicted } : null
const out = { verification, verified_items, unverified_items, holes, counts, open_items }
if (escalation) return { status: 'escalate', ...escalation, ...out }
return { status: holes.length || unverified_items.length ? 'partial' : 'complete', ...out }
