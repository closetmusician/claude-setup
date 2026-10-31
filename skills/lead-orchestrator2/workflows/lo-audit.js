export const meta = {
  name: 'lo-audit',
  description: 'investigate-audit: fan out lanes, synthesize, then an independent verifier checks the synthesis',
  whenToUse: 'lead-orchestrator2 investigate-audit mode',
  phases: [
    { title: 'Lanes', detail: 'one worker per lane, dead lane re-run once' },
    { title: 'Synthesize', detail: 'opus synthesizer writes the deliverable', model: 'opus' },
    { title: 'Coverage', detail: 'code audits: completeness critic, at most one gap loop', model: 'opus' },
    { title: 'Verify', detail: 'fresh opus verifier after synthesis, plus a repro probe on code audits, max 2 rounds', model: 'opus' },
  ],
}
// ABOUTME: Workflow script for lead-orchestrator2 investigate-audit mode (LO2-SPEC section 1).
// ABOUTME: Lanes run in parallel; a lane that returns nothing is re-run once, then logged as a hole.
// ABOUTME: The synthesizer is a producer, so the verifier runs AFTER it and re-derives its claims.
// ABOUTME: Verifier cap: 2 rounds. Round 2 re-checks only the fixed claims. Never a round 3.
// ABOUTME: Code audits (repo set, round 2): writers lane, coverage critic, repo-test rules, repro probe.
// ABOUTME: No TDD artifacts in this mode. Tests: ../tests/test-lo-audit.mjs.
// NOTE: every agent call names its model inline. workflow-model-guard.sh checks this lexically.

const TPL = '/Users/yklin/.claude/skills/lead-orchestrator/templates'
const MODELS = ['haiku', 'sonnet', 'opus']
const INT = { type: 'integer' }
const STR = { type: 'string' }
const LANE = { type: 'object', properties: { out_file: STR, summary: STR, claims: INT }, required: ['out_file', 'summary'] }
const SYNTH = { type: 'object', properties: { path: STR, claims: INT }, required: ['path', 'claims'] }
const LIST = { type: 'array', items: STR }
const VERIFY = { type: 'object', properties: { verified: INT, unverified: INT, contradicted: INT,
  blocking: LIST, weakens: LIST, path: STR }, required: ['verified', 'unverified', 'contradicted', 'blocking', 'weakens', 'path'] }
const CRITIC = { type: 'object', properties: { uncovered: LIST, path: STR }, required: ['uncovered', 'path'] }
const PROBE = { type: 'object', properties: { checked: INT, bad_tests: LIST, survivors: LIST, path: STR },
  required: ['checked', 'bad_tests', 'survivors', 'path'] }
const MAX_GAPS = 4

// ---- Arguments ---------------------------------------------------------------------------
const A = args || {}
const fail = (reason) => ({ status: 'escalate', stage: 'args', reason, holes: [], counts: null, open_items: [] })
const missing = ['run_dir', 'spec_path', 'scope', 'deliverable_path', 'golden_ref']
  .filter((k) => typeof A[k] !== 'string' || !A[k].trim())
if (missing.length) return fail(`missing args: ${missing.join(', ')}`)
if (!Array.isArray(A.lanes) || !A.lanes.length) return fail('lanes must be a non-empty array of {id, prompt, model}')
const badLane = A.lanes.find((l) => !l || !l.id || !l.prompt || (l.model && !MODELS.includes(l.model)))
if (badLane) return fail(`bad lane ${JSON.stringify(badLane)}: needs id, prompt, and model in ${MODELS.join('/')} (fable is review-only)`)
// Code audit (round 2): a repo means repro tests, so they must live in the repo's real test dir
// and run under its real test command (fix-ctx-002: B's tests sat in docs/temp with /tmp paths).
const CODE = typeof A.repo === 'string' && A.repo.trim() !== ''
if (CODE) {
  const bad = []
  if (typeof A.test_dir !== 'string' || !A.test_dir.trim()) bad.push('test_dir (the repo test dir, relative, e.g. test)')
  else if (A.test_dir.startsWith('/') || A.test_dir.split('/').includes('..') || /^docs(\/|$)/.test(A.test_dir))
    bad.push(`test_dir ${A.test_dir}: must be the test dir of the repo, relative, not under docs/`)
  if (typeof A.test_cmd !== 'string' || !A.test_cmd.trim()) bad.push('test_cmd (the repo test command, e.g. npm test)')
  else if (A.test_cmd.includes(A.run_dir) || A.test_cmd.includes('docs/temp')) bad.push(`test_cmd ${A.test_cmd}: must be the repo test command, not a run-dir path`)
  if (bad.length) return fail(`code audit (repo set) needs: ${bad.join('; ')}`)
}
const WRITERS_PROMPT = [
  'WRITERS AND SIDE EFFECTS lane. Find every code path that writes, sends, caches, refreshes, retries, resends or filters',
  'the output in scope, not only the main path. Look for a second or other writer of the same output (a refresh job, a chat bot,',
  'a CLI, a cron path) that skips the checks the main path runs; a retry or resend branch that skips a check; a stale cache',
  'or state file that is reused; a dedup that reuses an old id; a filter or lookup that fails open on an error.',
  'For each writer: entry function -> write call (file:line), which checks run, which checks are missing.',
].join(' ')
const lanes = CODE && !A.lanes.some((l) => l.id === 'writers' || l.kind === 'writers')
  ? [...A.lanes, { id: 'writers', prompt: WRITERS_PROMPT, model: 'opus' }]
  : A.lanes
const verification = `${A.run_dir}/verification.md`
const open_items = []
let counts = null

// Purpose: build one lane prompt from the lead-orchestrator dispatch skeleton.
// Usage:   lanePrompt(lane, '') or lanePrompt(lane, 'retry note')
// Gotchas: the lane writes to the canonical file run_dir/<id>.md; the script never writes it.
const laneFile = (l) => `${A.run_dir}/${l.id}.md`
const lanePrompt = (l, note) => [
  `You are a RESEARCH/AUDIT WORKER for lane ${l.id} (investigate-audit). Scope of the run: ${A.scope}`,
  CODE ? `Repository: ${A.repo}.` : '',
  '## Mandatory Context',
  `- **Spec:** ${A.spec_path}. Read it first.  **Output file:** ${laneFile(l)}`,
  `- **Lane task:** ${l.prompt}`,
  '## Constraints',
  '- Self-contained: everything you need is above. Do not search memory.',
  `- Write FULL output to ${laneFile(l)}. Every claim carries its primary source (file:line, URL, or command).`,
  '- Anything you could not verify from a primary source = mark UNVERIFIED. Never fabricate a number, quote, or status.',
  '- No implementation edits. Never git stash, reset or restore files.',
  '- Structured output: out_file (the path you wrote), a short summary, and the claim count.',
  CODE_LANE_RULES,
  note ? `- RETRY: ${note}` : '',
].join('\n')

const TEST_RULES = CODE ? [
  `- TEST RULES (they override any spec line that puts tests elsewhere): write every repro test inside ${A.repo}/${A.test_dir}/,`,
  `  in the style of the existing tests there, so that \`${A.test_cmd}\` (run from ${A.repo}) runs it. Use relative require/import`,
  '  paths only; never an absolute path (/tmp, /Users or the repo path). Each test must FAIL today on an assertion',
  '  (AssertionError), never on a TypeError, ReferenceError, "is not a function", a missing export or module, or a syntax error.',
  '  Test behaviour: never read a source file and regex-match its text, unless the defect is that text (a prompt string).',
].join('\n') : ''
const DIRECTION_RULE = [
  '- FIX DIRECTION: check every proposed fix against the stated goal. A fix that weakens, narrows, removes or bypasses a',
  '  stated safety check (a detector, validator, gate, filter, guard or test) is wrong unless you argue it with evidence:',
  '  the check blocks correct output, and a replacement keeps the goal.',
].join('\n')
const CODE_LANE_RULES = CODE ? [
  '- LANE SPLIT: you own a failure path or data flow end to end, across every file it crosses, not one file.',
  '- End your file with a `## Coverage` section: each code path you traced, entry function -> exit, with file:line.',
  TEST_RULES, DIRECTION_RULE,
].join('\n') : ''

const deadLane = (r) => !r || !String(r.out_file || '').trim()

// ---- Lanes: fan out, one re-run per dead lane --------------------------------------------
phase('Lanes')
const laneResults = await pipeline(lanes, async (l) => {
  const tier = l.model || 'sonnet'
  let r = await agent(lanePrompt(l, ''), { label: `lane:${l.id}`, phase: 'Lanes', model: tier, schema: LANE })
  if (deadLane(r)) {
    r = await agent(lanePrompt(l, 'the previous worker for this lane returned nothing'),
      { label: `lane:${l.id}:retry`, phase: 'Lanes', model: tier, schema: LANE })
  }
  return deadLane(r) ? null : r
})
const live = lanes.filter((l, i) => laneResults[i])
const holes = lanes.filter((l, i) => !laneResults[i]).map((l) => l.id)
if (holes.length) log(`Lanes with no output after one re-run (holes): ${holes.join(', ')}`)
if (!live.length) return { status: 'escalate', stage: 'Lanes', reason: 'every lane returned nothing after one re-run', holes, counts, open_items }

// ---- Synthesis (barrier: needs every lane) -----------------------------------------------
phase('Synthesize')
const synthPrompt = (note) => [
  `You are the SYNTHESIZER for this investigate-audit run. Scope: ${A.scope}`,
  `Spec: ${A.spec_path}. Inputs (read each): ${live.map(laneFile).join(', ')}`,
  holes.length ? `HOLES (no output, report them as gaps, never fill them): ${holes.join(', ')}` : 'Holes: none.',
  `Write the deliverable to ${A.deliverable_path}. Keep each claim tied to its lane source. Keep UNVERIFIED tags from the lanes.`,
  'Never add a fact that no lane file supports. Never fabricate a number, quote, or status.',
  CODE ? [TEST_RULES, DIRECTION_RULE].join('\n') : '',
  note || '',
].join('\n')
let synth = await agent(synthPrompt(''), { label: 'synth', phase: 'Synthesize', model: 'opus', schema: SYNTH })
if (!synth) synth = await agent(synthPrompt('RETRY: the previous synthesizer returned nothing.'), { label: 'synth:retry', phase: 'Synthesize', model: 'opus', schema: SYNTH })
if (!synth) return { status: 'escalate', stage: 'Synthesize', reason: 'the synthesizer returned nothing twice', holes, counts, open_items }

// ---- Coverage critic (code audits): list uncovered code paths; at most one gap loop ---------
// fix-ctx-002: B's 3 lanes all traced the read path, so no lane saw the writer-side causes.
if (CODE) {
  phase('Coverage')
  const criticFile = `${A.run_dir}/coverage-critic.md`
  const criticPrompt = [
    `You are the COMPLETENESS CRITIC for this code audit of ${A.repo}. Scope: ${A.scope}. Spec: ${A.spec_path}.`,
    `Read ${A.deliverable_path} and the \`## Coverage\` section of each lane file: ${live.map(laneFile).join(', ')}.`,
    'Then read the code and list each code path in scope that no lane traced: every entry point, every writer or side',
    'effect (write, send, cache, refresh, retry, resend, filter), and every error or fallback path. Use git grep for callers.',
    'Judge coverage only, not the findings. One line per uncovered path: entry -> exit (file:line): why it can matter.',
    `Write the list to ${criticFile}. Return uncovered (the lines, most important first) and the path.`,
  ].join('\n')
  const critic = await agent(criticPrompt, { label: 'critic', phase: 'Coverage', model: 'opus', schema: CRITIC })
  const uncovered = critic && Array.isArray(critic.uncovered) ? critic.uncovered.filter(Boolean) : []
  if (!critic) open_items.push('the completeness critic returned nothing: coverage is unchecked')
  if (uncovered.length > MAX_GAPS) open_items.push(`uncovered paths past the ${MAX_GAPS}-lane cap: ${uncovered.slice(MAX_GAPS).join('; ')}`)
  const gaps = uncovered.slice(0, MAX_GAPS).map((u, i) => ({ id: `gap-${i + 1}`, model: 'sonnet',
    prompt: `GAP LANE. The completeness critic found this code path uncovered: ${u}. Trace it end to end and report every defect on it.` }))
  if (gaps.length) {
    const gapResults = await pipeline(gaps, (g) =>
      agent(lanePrompt(g, ''), { label: `gap:${g.id}`, phase: 'Coverage', model: 'sonnet', schema: LANE }))
    const liveGaps = gaps.filter((g, i) => !deadLane(gapResults[i]))
    gaps.filter((g, i) => deadLane(gapResults[i])).forEach((g) => holes.push(g.id))
    live.push(...liveGaps)
    if (liveGaps.length) {
      const merged = await agent(synthPrompt(`GAP MERGE. Add the findings of ${liveGaps.map(laneFile).join(', ')} to ${A.deliverable_path}. Change nothing else.`),
        { label: 'synth:gaps', phase: 'Synthesize', model: 'opus', schema: SYNTH })
      if (!merged) open_items.push(`the gap merge returned nothing: ${liveGaps.map(laneFile).join(', ')} are not in the deliverable`)
    }
  }
}

// ---- Verifier (fresh agent, AFTER synthesis) ---------------------------------------------
phase('Verify')
// Purpose: one verifier round over the deliverable and the lane files, from qa-prompt.md verify.
// Usage:   const v = await verifyRound(1, '') or verifyRound(2, 'claim #4; claim #7')
// Gotchas: round 2 re-checks only the fixed claims and appends to the same verification.md.
const verifyPrompt = (round, claims) => [
  `Read ${TPL}/qa-prompt.md with the Read tool. It is your complete instruction set.`,
  'Substitute these placeholder values everywhere they appear, then follow the template exactly:',
  '- {TASK_ID} = audit', '- {MODE} = investigate-audit', '- {QA_PHASE} = verify', '- {QA_GOVERNANCE_ROLE} = verifier',
  `- {RUN_DIR} = ${A.run_dir}`, `- {SPEC_PATH} = ${A.spec_path}`, '- {ARCH_DESIGN_PATH} = N/A',
  `- {PHASE_INPUTS} = ${A.deliverable_path} (the synthesis, a producer output) + lane files ${live.map(laneFile).join(', ')}`,
  `- {LIVE_TARGET} = ${A.deliverable_path}`,
  `- {REQUIREMENT_MAP_JSON} = ${A.req_map ? JSON.stringify(A.req_map) : 'build it from the spec: one requirement per scope item'}`,
  '- {ESCALATION_CONDITIONS} = a primary source is unreachable, or the deliverable contradicts a lane',
  `GOLDEN REFERENCE (what correct means): ${A.golden_ref}`,
  `Re-derive claims in ${A.deliverable_path} from the PRIMARY sources, not from the lane files. Write ${verification}.`,
  holes.length ? `Known holes (report as gaps): ${holes.join(', ')}` : '',
  'Scope lock: check the original scope only. Out-of-scope findings go in the report as open items.',
  'FIX DIRECTION: check every proposed fix against the scope and the golden reference. List in `weakens` each fix that',
  'weakens, narrows, removes or bypasses a stated safety check (detector, validator, gate, filter, guard or test), unless the',
  'report argues it with evidence (the check blocks correct output, and a replacement keeps the goal). Empty list if none.',
  round === 2 ? `ROUND 2 of 2 (final). Re-verify ONLY these fixed claims: ${claims}. Append a ## Round 2 section.` : '',
].join('\n')
const verifyRound = (round, claims) => agent(verifyPrompt(round, claims),
  { label: round === 1 ? 'verify' : 'verify:round2', phase: 'Verify', model: 'opus', schema: VERIFY })

// Purpose: repro/mutation probe for code audits: are the repro tests real, and do they track the cause?
// Usage:   const p = await probeRound(1)  ->  {checked, bad_tests, survivors, path} or null
// Gotchas: works in a scratch copy only; a test that stays red after the proposed fix is a survivor.
const probeFile = `${A.run_dir}/repro-probe.md`
const probePrompt = (round) => [
  `REPRO PROBE for the code audit of ${A.repo} (round ${round}). Do not edit the real repo. Do not commit.`,
  `Inputs: ${A.deliverable_path} (each root cause, its proposed fix, its repro test). Test command: ${A.test_cmd}. Test dir: ${A.test_dir}.`,
  '1. For each repro test the deliverable names, check it and add a line to bad_tests ("<file>: <rule broken>") when it:',
  `   is not under ${A.test_dir}/ or is not run by the test command; contains an absolute path (/tmp, /Users or the repo path);`,
  '   fails today with a TypeError, ReferenceError, "is not a function", a missing export or module, or a syntax error rather',
  '   than an assertion (AssertionError); or reads a source file and regex-matches its source text (unless that text is the defect).',
  `2. MUTATION: copy the repo to a scratch dir (mktemp -d; rsync -a --exclude .git ${A.repo}/ <scratch>/). Run the test command`,
  '   there first, unchanged, as the baseline (if it cds into the repo path, use the scratch path). Then, per root cause, apply',
  '   the smallest form of the proposed fix in the scratch copy and run its repro test. The test must now pass. If it still',
  '   fails, or it passed already before the fix, add "<root cause>: <test>: <what happened>" to survivors. Undo before the next.',
  `3. Delete the scratch dir. Write the full table to ${probeFile}. Return checked (tests probed), bad_tests, survivors, path.`,
].join('\n')
const probeRound = (round) => agent(probePrompt(round),
  { label: round === 1 ? 'probe' : 'probe:round2', phase: 'Verify', model: 'sonnet', schema: PROBE })

const listOf = (x) => (Array.isArray(x) ? x.filter(Boolean) : [])
const probeItems = (p) => (p ? [...listOf(p.bad_tests), ...listOf(p.survivors)] : [])
const isBlocking = (v, p) => v.contradicted > 0 || v.blocking.length > 0 || listOf(v.weakens).length > 0 || probeItems(p).length > 0
const blockList = (v, p) => [...v.blocking, ...listOf(v.weakens).map((w) => `fix weakens a safety check: ${w}`),
  ...probeItems(p).map((t) => `repro probe: ${t}`)]
// Purpose: one verify round; on code audits the probe runs in parallel with the verifier.
// Usage:   const [v, p] = await verifyStage(1, '')
// Gotchas: round 2 re-runs the probe only if the round-1 probe blocked; a dead probe is an open item.
const verifyStage = async (round, claims, reprobe) => {
  if (!CODE || (round === 2 && !reprobe)) return [await verifyRound(round, claims), null]
  const [v, p] = await parallel([() => verifyRound(round, claims), () => probeRound(round)])
  if (!p) open_items.push(`the repro probe (round ${round}) returned nothing: repro tests are unchecked`)
  return [v, p]
}

let [ver, probe] = await verifyStage(1, '')
if (!ver) return { status: 'escalate', stage: 'Verify', reason: 'the verifier returned nothing', holes, counts, open_items }
if (isBlocking(ver, probe)) {
  const list = blockList(ver, probe).join('; ') || `${ver.contradicted} CONTRADICTED claims`
  const fixed = await agent(synthPrompt(`FIX ROUND. The verifier${CODE ? ' and the repro probe' : ''} marked these BLOCKING (${verification}${CODE ? `, ${probeFile}` : ''}): ${list}. Correct or tag them in ${A.deliverable_path}${CODE ? ` and fix the named repro tests in ${A.test_dir}/` : ''}; change nothing else.`),
    { label: 'synth:fix', phase: 'Synthesize', model: 'opus', schema: SYNTH })
  if (!fixed) return { status: 'escalate', stage: 'Verify', reason: 'the synthesizer fix returned nothing', holes, counts, open_items, last: ver }
  ;[ver, probe] = await verifyStage(2, list, probeItems(probe).length > 0)
  if (!ver) return { status: 'escalate', stage: 'Verify', reason: 'the round-2 verifier returned nothing', holes, counts, open_items }
  counts = { verified: ver.verified, unverified: ver.unverified, contradicted: ver.contradicted }
  if (isBlocking(ver, probe)) return { status: 'escalate', stage: 'Verify', reason: `verifier round 2 still blocking: ${blockList(ver, probe).join('; ')}`, holes, counts, open_items, last: ver }
}
counts = { verified: ver.verified, unverified: ver.unverified, contradicted: ver.contradicted }
if (counts.unverified > 0) open_items.push(`${counts.unverified} UNVERIFIED claims: tag them in the deliverable`)
holes.forEach((h) => open_items.push(`hole: lane ${h} produced no output`))
return { status: holes.length ? 'partial' : 'complete', deliverable: A.deliverable_path, verification, holes, counts, open_items }
