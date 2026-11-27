export const meta = {
  name: 'lo-feature-task-d',
  description: 'Arm D rev2: Spec Fix + Codex, stage scripts, no tests',
  whenToUse: 'LO2 benchmark arm D revision 2',
  phases: [
    { title: 'Preflight', detail: 'one tiny sonnet agent and one tiny opus agent: model login check', model: 'haiku' },
    { title: 'Spec', detail: 'armd-spec.sh: Codex spec fix, one round; opus resolver on P0/P1', model: 'haiku' },
    { title: 'Code', detail: 'sonnet coder, code only, no tests', model: 'sonnet' },
    { title: 'Suite', detail: 'suite-compare.sh when suite_cmd is given: base vs HEAD', model: 'haiku' },
    { title: 'Review', detail: 'armd-review.sh: Codex review + req-rows', model: 'haiku' },
    { title: 'Fix', detail: 'max 2 rounds, sonnet coder', model: 'sonnet' },
    { title: 'Final', detail: 'armd-final.sh: re-review, src count', model: 'haiku' },
  ],
}
// ABOUTME: Arm D revision 2 workflow. Stage scripts (armd-spec, armd-review, armd-final) move shell work into bash.
// ABOUTME: No tests: the coder writes code only. Runner agents use haiku/low. Coder is sonnet. Verifier is opus.
// ABOUTME: Spec: ~/.claude/docs/plans/lo2-arm-d/SPEC.md §7. Prompt templates: scripts/prompts/*.md.
// ABOUTME: Agent count: 3 with no fix, 5 with one round, 6 with two, plus 1-2 verifier hops. close:true = feature close.
// ABOUTME: Updated 2026-11-16: REQ-01 (unified status), REQ-02/03 (review_ok/final_ok, notes list), REQ-04/05 (kind, spec-resolve-check), REQ-06 (golden_ref), REQ-08 (unmapped).
// ABOUTME: Updated 2026-11-17 (LO2 improve): long-run stage launcher (run-stage/wait-stage), infra kind on dead agents, preflight, smoke run, suite compare.

const INT = { type: 'integer' }
const STR = { type: 'string' }
const BOOL = { type: 'boolean' }
const ARR_STR = { type: 'array', items: STR }

// ---- Arguments ---------------------------------------------------------------------------
const A = args || {}
const REQUIRED = ['repo', 'feat_id', 'task_id', 'task_label', 'req_ids', 'requirements', 'design', 'run_dir', 'base_ref', 'codex']
const missing = REQUIRED.filter((k) => !A[k] || typeof A[k] !== 'string' && !Array.isArray(A[k]))
if (missing.length) {
  return { status: 'escalate', open_items: [`missing args: ${missing.join(', ')}`], notes: [], artifacts: {} }
}

const T = A.task_id
const RUN = A.run_dir
const SCRIPTS = '/Users/yklin/.claude/skills/lead-orchestrator2/scripts'
const open_items = []
const notes = []
const artifacts = {}
// Items that must stop 'complete' but are not yet in open_items; decideStatus moves them there.
const blockers = []
// Set when an agent() call returned null; the workflow return then carries kind 'infra' and this reason (REQ-02a).
let infraSeen = ''
const infraFields = () => (infraSeen ? { kind: 'infra', reason: infraSeen } : {})

// Purpose: single-quote a string so a shell reads it as one word.
// Usage:   shq(A.suite_cmd)
const shq = (x) => `'${String(x).replace(/'/g, "'\\''")}'`

// Purpose: reason text for an agent() call that returned null (REQ-02a).
// Usage:   infraReason('coder')
// Gotchas: the same wording everywhere, so the owner can tell a dead agent from a coder bug.
const infraReason = (label) => `${label} agent returned no result. This is usually an infra failure (model login, AWS 403, rate limit). Check the agent transcript before you relaunch.`

// Purpose: result fields a runner schema used to require; the schemas no longer require them (REQ-01d).
// Usage:   lacks(result, ['passed', 'kind'])  -> list of names that are undefined
const lacks = (r, names) => names.filter((n) => r[n] === undefined)

// Purpose: schema fields that let a runner report a timeout or a failed stage script (REQ-01d).
const STAGE_FAIL = { timed_out: BOOL, stage_error: BOOL, exit_code: INT, out: STR }

// Purpose: stop the workflow when a runner reports timed_out or stage_error. Checked BEFORE any normal field.
// Usage:   const stop = stageStop('review', result, rounds, verifierRan); if (stop) return stop
// Gotchas: timed_out gives partial, stage_error gives escalate with kind infra. Neither ever gives complete.
//          A timed_out return still carries kind infra and its reason when an earlier agent() call returned null.
const stageStop = (stage, r, rounds = 0, verifierRan = false) => {
  if (r.timed_out === true) {
    open_items.unshift(`${stage} stage timed out after 54 min; see ${r.out || `${RUN}/${stage}.*.out`}`)
    open_items.push(...blockers.splice(0))
    return { status: 'partial', stage, ...infraFields(), open_items, notes, artifacts, rounds, verifier_ran: verifierRan }
  }
  if (r.stage_error === true) {
    const reason = `${stage} stage script failed: exit code ${r.exit_code}, output ${r.out}`
    open_items.unshift(reason)
    return { status: 'escalate', stage, reason, kind: 'infra', open_items, notes, artifacts, rounds, verifier_ran: verifierRan }
  }
  return null
}

// Purpose: unified status function (REQ-01). Returns complete/partial/escalate.
// Usage:   decideStatus(reviewResult, finalResult, stillOpenIds, unmapped, fixRan)
// Gotchas: complete only when ALL hold: review parsed, req_rows_ok, no P0/P1 left (including no-fix case), no verifier blockers, no unmapped. Strict checks for null/missing fields (F03).
const decideStatus = (reviewResult, finalResult, stillOpenIds, unmapped, fixRan) => {
  const reasons = []

  // REQ-01: Check all completion gates with strict checks (F03)
  if (!reviewResult) {
    reasons.push('review result missing')
  }
  if (reviewResult && reviewResult.review_ok !== true) {
    reasons.push('review parse failed')
  }
  if (reviewResult && reviewResult.req_rows_ok !== true) {
    reasons.push('req_rows check failed')
  }
  // F03: Strict check for defects array
  if (reviewResult && !Array.isArray(reviewResult.defects)) {
    reasons.push('review defects missing or malformed')
  }

  // F01: When no fix ran, check for P0/P1 defects even without repro (F03: defects already checked above)
  if (!fixRan && reviewResult && Array.isArray(reviewResult.defects)) {
    const unfixedP0P1 = reviewResult.defects.filter((d) => d.sev === 'P0' || d.sev === 'P1')
    if (unfixedP0P1.length > 0) {
      reasons.push(`P0/P1 defects present: ${unfixedP0P1.map((d) => d.id).join(', ')}`)
    }
  }

  // F02: Strict null checks for final result fields
  if (fixRan && !finalResult) {
    reasons.push('final result missing')
  }
  if (finalResult && finalResult.final_ok !== true) {
    reasons.push('final review parse failed')
  }
  if (finalResult && (!Array.isArray(finalResult.open_p0p1) || finalResult.open_p0p1.length > 0)) {
    const list = Array.isArray(finalResult.open_p0p1) ? finalResult.open_p0p1.join(', ') : 'null or missing'
    reasons.push(`P0/P1 still open: ${list}`)
  }
  if (stillOpenIds && stillOpenIds.length > 0) {
    reasons.push(`P0/P1 still open from fix: ${stillOpenIds.join(', ')}`)
  }
  // F03: Strict check for verifier_blocking array when present
  if (finalResult && finalResult.verifier_blocking !== undefined) {
    if (!Array.isArray(finalResult.verifier_blocking)) {
      reasons.push('verifier final: null or malformed')
    } else if (finalResult.verifier_blocking.length > 0) {
      finalResult.verifier_blocking.forEach((b) => reasons.push(`verifier final: ${b}`))
    }
  }
  if (unmapped && unmapped.length > 0) {
    unmapped.forEach((id) => reasons.push(`requirement has no task: ${id}`))
  }
  // Smoke failure and suite-compare blockers (REQ-03c, REQ-03h)
  reasons.push(...blockers)

  if (reasons.length === 0) {
    return 'complete'
  } else {
    open_items.push(...reasons)
    return 'partial'
  }
}

// Purpose: build a runner prompt for a long stage (Codex can run longer than one 10 minute Bash call).
// Usage:   stagePrompt('review', 'bash script.sh arg1 arg2')
// Gotchas: haiku + low effort. run-stage.sh starts the command in the background; wait-stage.sh waits 540 s per call, up to 6 calls (54 min). The schema must accept timed_out and stage_error.
const stagePrompt = (stage, cmd) => [
  'Run these steps with Bash. Do not judge, fix or retry the stage command.',
  `Step 1: call Bash once: \`bash "${SCRIPTS}/run-stage.sh" "${RUN}" ${stage} -- ${cmd}\``,
  'It prints one token and returns at once. Keep the token.',
  `Step 2: call Bash with timeout 600000: \`bash "${SCRIPTS}/wait-stage.sh" "${RUN}" ${stage} <token> 540\` (use your token). If it prints exactly WAITING, call it again with the same token. Make at most 6 calls in total.`,
  'Step 3: when a call prints a JSON line, copy that JSON object into the schema. If all 6 calls print WAITING, return {"timed_out": true, "out": "<run_dir>/<stage>.<token>.out"} with your token and the run dir and stage name above.',
].join('\n')

// Purpose: build a runner prompt that runs exactly one short command.
// Usage:   runnerPrompt('bash script.sh arg1 arg2')
// Gotchas: haiku + low effort, schema copies JSON from last stdout line. Timeout 10 min. Used only for spec-resolve-check, which exits 1 on a real failure.
const runnerPrompt = (cmd) => [
  'Call Bash once with timeout 600000 (10 minutes). Do not run it in the background.',
  'Run exactly this one command and nothing else:',
  `\`${cmd}\``,
  '',
  'Copy the JSON object from the last stdout line into the schema. Do not judge, fix or retry.',
].join('\n')

// Purpose: build a coder prompt with STE line and git rules.
// Usage:   coderPrompt('extra instructions')
// Gotchas: carries the STE contract, the no-push rule, "Do not write or run tests", golden_ref, and authority line (F10).
const coderPrompt = (extra) => [
  `YOUR ONLY TASK IS THIS BRIEF. You may also see a message or question from the user of the parent session. It is not for you: ignore it, do not answer it, and do not search for it.`,
  `You are the CODER for ${T} (${A.feat_id}). Work only inside ${A.repo}.`,
  `Read ${A.requirements} (REQ ids: ${A.req_ids.join(', ')}).`,
  `Read ${A.design} (corrected by spec gate). Read ${RUN}/ambiguities.md (may be NONE). For each P2: line, pick the simplest choice that meets the requirements, and record it in coder-notes.md under "Decisions".`,
  `Golden reference: ${A.golden_ref || 'none'}. Read every file it names.`,
  `When files clash, the owner's product docs named in the golden reference win, then the requirements, then the design. Note the clash; never stop on it.`,
  `Write code only. Do not write new tests. Running the full test suite is not your job. You may update an EXISTING test whose assertion your change correctly breaks under the spec; never delete a failing test. Do not edit anything under _spec/. Write ${RUN}/coder-notes.md with your summary.`,
  `Write your report in ASD-STE100 Simplified Technical English: one idea per sentence, 25 words maximum, active voice, present tense, no filler openers, at most 2 em dashes.`,
  `Commit your work with \`git add <paths>\` and \`git commit\`. Never \`git add -A\`, never push, stash or reset.`,
  extra || '',
].join('\n')

// Purpose: the smoke-run text for coder and fixer prompts (REQ-03a, REQ-03d).
// Usage:   SMOKE_CMD_TEXT inside a prompt array.
// Gotchas: a smoke run is not a test. py_compile, --help, import checks and --dry-run do not count.
const SMOKE_CMD_TEXT = A.smoke_cmd
  ? `the smoke command: ${A.smoke_cmd}`
  : 'the smallest real run of the changed entry point'
const SMOKE_CODER = [
  `SMOKE RUN: after coding, run the real changed code path once. Use ${SMOKE_CMD_TEXT}.`,
  'py_compile, --help, import checks and --dry-run do not count. The smoke run is not a test; do not write a test for it.',
  `Record the command, the exit code and the last 20 output lines in ${RUN}/coder-notes.md under "## Smoke run". If it fails, fix the code and run it again, up to 3 tries.`,
  'If a real run needs spend, a secret or an outward-facing action, do not run it. Write "SMOKE SKIPPED: <reason>" in that section instead.',
  'Return the smoke field: ran, ok, cmd, and skip_reason (required when ran is false).',
].join('\n')
const smokeFix = (n) => `After your fix, run ${SMOKE_CMD_TEXT} again and record the command, exit code and last 20 output lines in ${RUN}/fix-${n}.md under "## Smoke run".`

// ---- Preflight (REQ-02b, REQ-02c): both modes, before any stage ----------------------------
// One tiny sonnet agent and one tiny opus agent. A null from either means a dead model login, so no stage runs.
phase('Preflight')
const preflightCheck = (model) => agent(
  [`Preflight check for ${model}. Do nothing else.`, 'Return {ok: true}.'].join('\n'),
  { label: `preflight:${model}`, model, effort: 'low', schema: { type: 'object', properties: { ok: BOOL }, required: ['ok'] } },
)
const [pfSonnet, pfOpus] = await parallel([() => preflightCheck('sonnet'), () => preflightCheck('opus')])
const pfDead = [['sonnet', pfSonnet], ['opus', pfOpus]].filter(([, r]) => !r).map(([m]) => m)
if (pfDead.length) {
  const reason = `preflight failed: ${pfDead.join(' and ')} agent returned no result. This is usually an infra failure (model login, AWS 403, rate limit). Check the login before you relaunch.`
  open_items.unshift(reason)
  return { status: 'escalate', stage: 'preflight', reason, kind: 'infra', open_items, notes, artifacts, rounds: 0, verifier_ran: false }
}

// ---- Close mode: args.close = true reviews the whole feature diff (base_ref..HEAD, all REQs) ----
// It skips the spec and code stages and reuses review -> fix -> final (owner, 2026-11-15).
// REQ-08: Close mode takes unmapped from the plan.
const unmappedReqIds = (A.close && A.unmapped) ? A.unmapped : []

if (!A.close) {
  // ---- Stage 1: Spec (armd-spec.sh) --------------------------------------------------------
  phase('Spec')

  // REQ-06: Pass golden_ref to armd-spec.sh; escape single quotes for shell safety
  const goldenRefEscaped = (A.golden_ref || '').replace(/'/g, "'\\''")
  const specCmd = `bash "${SCRIPTS}/armd-spec.sh" "${A.repo}" "${RUN}" "${A.task_label}" "${A.req_ids.join(',')}" "${A.requirements}" "${A.design}" "${A.base_ref}" "${A.codex}" '${goldenRefEscaped}'`
  const specResult = await agent(stagePrompt('spec', specCmd), {
    label: 'runner:spec',
    model: 'haiku',
    effort: 'low',
    schema: {
      type: 'object',
      properties: { passed: BOOL, kind: STR, rounds: INT, open_items: ARR_STR, ...STAGE_FAIL },
    },
  })

  // REQ-01d: timeout and stage error come first, before any normal field
  if (specResult) {
    const stop = stageStop('spec', specResult)
    if (stop) return stop
  }

  // REQ-03: Spec open_items go to notes if passed, else to open_items
  if (specResult && specResult.open_items && specResult.open_items.length > 0) {
    if (specResult.passed) {
      notes.push(...specResult.open_items)
    } else {
      open_items.push(...specResult.open_items)
    }
  }

  artifacts.spec_verdict = `${RUN}/spec-verdict.md`
  artifacts.ambiguities = `${RUN}/ambiguities.md`

  // Spec gate (owner, 2026-11-15): a dead spec runner escalates.
  // REQ-02a: a null result is an infra failure; a result missing a field the schema used to require is the same failure branch
  const specMissing = specResult ? lacks(specResult, ['passed', 'kind', 'rounds']) : []
  if (!specResult || specMissing.length) {
    const reason = specResult ? `spec runner result missing fields: ${specMissing.join(', ')}` : infraReason('spec runner')
    open_items.unshift(reason)
    return { status: 'escalate', stage: 'spec', reason, kind: 'infra', last: 'null', open_items, notes, artifacts, rounds: 0, verifier_ran: false }
  }

  // REQ-04: kind="infra" or missing/unknown kind escalates immediately
  // F07: Missing or unknown kind is treated as infra
  if (!specResult.kind || !['pass', 'design', 'infra'].includes(specResult.kind)) {
    const reason = `spec kind missing or unknown: ${specResult.kind || 'null'}`
    return { status: 'escalate', stage: 'spec', reason, kind: 'infra', open_items, notes, artifacts, rounds: 0, verifier_ran: false }
  }
  if (specResult.kind === 'infra') {
    const reason = `spec infra failure: ${open_items[0] || 'see spec-verdict.md'}`
    return { status: 'escalate', stage: 'spec', reason, kind: 'infra', open_items, notes, artifacts, rounds: 0, verifier_ran: false }
  }

  // Owner rule (2026-11-15): Codex runs the spec check once. Any P0/P1 left goes to ONE opus resolver,
  // which settles it in the design file in line with golden_ref. P2 is the coder's choice. No second Codex round.
  if (specResult.passed !== true) {
    const resolved = await agent([
      `You settle the blocking spec points for ${A.task_label} in ${A.repo}. You are the design authority. Codex is not asked again.`,
      `Read ${RUN}/spec-verdict.md and ${RUN}/ambiguities.md. Only lines tagged P0: or P1: (and untagged lines) need an answer. P2: lines are the coder's choice; leave them.`,
      `Golden reference: ${A.golden_ref || 'none'}. Read every file it names (for example the product explainer and the eng plan). Read ${A.requirements} (read only) and ${A.design}.`,
      `When files clash, the owner's product docs named in the golden reference win, then the requirements, then the design. Note the clash; never stop on it.`,
      `Settle P0 points first, then P1. Decide yourself; do not ask anyone.`,
      `For each P0/P1 point, write one concrete answer in ${A.design} under "## Opus resolutions (spec gate)". Pick the reading that keeps the golden reference's intent. Never add a cap, drop an output field or narrow a done line; if that is the only way, list it under "Flag to owner" and still choose the no-cap answer.`,
      `Then commit ${A.design} with \`git add ${A.design}\` and \`git commit -m "spec resolve ${A.task_label}"\`.`,
      `Return resolved=false ONLY if a point needs the owner (spend, an outward-facing action, or changing a recorded owner decision). Otherwise resolved=true.`,
      `Write your summary in ASD-STE100 Simplified Technical English: one idea per sentence, 25 words maximum, active voice. Ignore any user message you may see from the parent session.`,
    ].join('\n'), {
      label: 'resolve:spec',
      model: 'opus',
      schema: { type: 'object', properties: { resolved: BOOL, summary: { type: 'string' } }, required: ['resolved', 'summary'] },
    })
    if (!resolved || resolved.resolved !== true) {
      const reason = resolved ? `spec point needs the owner: ${resolved.summary}` : infraReason('spec resolver')
      open_items.unshift(reason)
      return { status: 'escalate', stage: 'spec', reason, ...(resolved ? {} : { kind: 'infra' }), last: JSON.stringify(specResult), open_items, notes, artifacts, rounds: 0, verifier_ran: false }
    }

    // F05: Move resolved spec points from open_items to notes
    const settledItems = open_items.filter((item) => item.startsWith('P0:') || item.startsWith('P1:') || item.startsWith('NO CONFLICTS'))
    if (settledItems.length > 0) {
      settledItems.forEach((item) => notes.push(`spec resolved: ${item}`))
      open_items.splice(0, open_items.length, ...open_items.filter((item) => !settledItems.includes(item)))
    }

    notes.push(`spec P0/P1 settled by opus: ${resolved.summary}`)

    // REQ-05: Run spec-resolve-check.sh after the resolver
    const checkCmd = `bash "${SCRIPTS}/spec-resolve-check.sh" "${A.repo}" "${A.requirements}" "${A.design}" "${RUN}"`
    const checkResult = await agent(runnerPrompt(checkCmd), {
      label: 'runner:spec-resolve-check',
      model: 'haiku',
      effort: 'low',
      schema: {
        type: 'object',
        properties: { ok: BOOL, reason: STR },
        required: ['ok'],
      },
    })
    if (!checkResult || !checkResult.ok) {
      const reason = checkResult ? checkResult.reason : infraReason('spec-resolve-check runner')
      open_items.unshift(`spec-resolve-check failed: ${reason}`)
      return { status: 'escalate', stage: 'spec', reason, ...(checkResult ? {} : { kind: 'infra' }), last: JSON.stringify(resolved), open_items, notes, artifacts, rounds: 0, verifier_ran: false }
    }
  }

  // ---- Stage 2: Code (sonnet coder, no tests) ----------------------------------------------
  phase('Code')

  // Spec gate lock 2: the coder checks the pass file. Only armd-spec.sh (on a pass) or the resolver
  // writes it, so a runner that copies `passed` wrongly still cannot start the code stage.
  // REQ-06: Coder gets golden_ref in the prompt
  const coderResult = await agent(coderPrompt([
    `FIRST run \`test -f "${RUN}/spec-gate.pass"\`. If it fails, change nothing and return summary exactly SPEC GATE NOT PASSED.`,
    SMOKE_CODER,
  ].join('\n')), {
    label: 'coder',
    model: 'sonnet',
    schema: {
      type: 'object',
      properties: {
        summary: STR,
        smoke: { type: 'object', properties: { ran: BOOL, ok: BOOL, cmd: STR, skip_reason: STR }, required: ['ran'] },
      },
      required: ['summary'],
    },
  })

  // F04: Check for missing or empty coder result
  if (!coderResult || typeof coderResult !== 'object' || Array.isArray(coderResult)) {
    const reason = infraReason('coder')
    open_items.unshift(reason)
    return { status: 'escalate', stage: 'code', reason, kind: 'infra', last: 'null', open_items, notes, artifacts, rounds: 0, verifier_ran: false }
  }
  // F03: Strict check for required summary field
  if (typeof coderResult.summary !== 'string' || coderResult.summary.length === 0) {
    const reason = 'coder result missing summary'
    open_items.unshift(reason)
    return { status: 'escalate', stage: 'code', reason, last: 'empty', open_items, notes, artifacts, rounds: 0, verifier_ran: false }
  }

  if (coderResult.summary === 'SPEC GATE NOT PASSED') {
    const reason = 'spec gate pass file missing although the runner reported passed'
    open_items.unshift(reason)
    return { status: 'escalate', stage: 'spec', reason, last: coderResult.summary, open_items, notes, artifacts, rounds: 0, verifier_ran: false }
  }

  artifacts.coder_notes = `${RUN}/coder-notes.md`

  // REQ-03c: smoke result. A failed real run blocks complete; a skip or a missing field is a note.
  const smoke = coderResult.smoke
  if (!smoke || typeof smoke !== 'object') {
    notes.push('coder returned no smoke field; smoke run not confirmed')
  } else if (smoke.ran === true && smoke.ok !== true) {
    blockers.push(`smoke run failed: ${smoke.cmd || 'no command given'}; see ${RUN}/coder-notes.md`)
  } else if (smoke.ran !== true) {
    notes.push(`smoke run skipped: ${smoke.skip_reason || 'no reason given'}`)
    if (smoke.ran === false && !String(smoke.skip_reason || '').trim()) blockers.push('smoke skipped with no reason')
  }
}

// ---- Suite compare (REQ-03h): after the code stage (task mode) or before the review (close mode) ----
// Both modes reach this point right before the review, so one block serves both.
// Purpose: run suite-compare.sh through the stage launcher. Usage: runSuite('suite') or runSuite('suite-final').
// Gotchas: haiku runner copies the JSON line. The stage name also names the .out file.
const runSuite = (stage) => agent(stagePrompt(stage, `bash "${SCRIPTS}/suite-compare.sh" ${shq(A.repo)} ${shq(A.base_ref)} ${shq(RUN)} ${shq(A.test_env || '')} ${shq(A.suite_cmd)}`), {
  label: `runner:${stage}`,
  model: 'haiku',
  effort: 'low',
  schema: {
    type: 'object',
    properties: { ok: BOOL, inconclusive: BOOL, regressions: ARR_STR, base_exit: INT, head_exit: INT, ...STAGE_FAIL },
  },
})
let suiteRegressions = []
if (A.suite_cmd) {
  phase('Suite')
  const suiteResult = await runSuite('suite')
  if (!suiteResult) {
    const reason = infraReason('suite runner')
    open_items.unshift(reason)
    return { status: 'escalate', stage: 'suite', reason, kind: 'infra', open_items, notes, artifacts, rounds: 0, verifier_ran: false }
  }
  const suiteStop = stageStop('suite', suiteResult)
  if (suiteStop) return suiteStop
  artifacts.suite_compare = `${RUN}/suite-compare.md`
  if (!Array.isArray(suiteResult.regressions) || typeof suiteResult.inconclusive !== 'boolean') {
    blockers.push(`suite compare result missing fields; see ${RUN}/suite-compare.md`)
  } else {
    suiteRegressions = suiteResult.regressions
    if (suiteResult.inconclusive) blockers.push(`suite compare inconclusive (crash before the summary, or no failing id); see ${RUN}/suite-compare.md`)
  }
} else {
  notes.push('no suite_cmd given; suite not compared')
}

// ---- Stage 3: Review (armd-review.sh) ----------------------------------------------------
phase('Review')

// REQ-06: Pass golden_ref to armd-review.sh
const goldenRefEscaped = (A.golden_ref || '').replace(/'/g, "'\\''")
const reviewCmd = `bash "${SCRIPTS}/armd-review.sh" "${A.repo}" "${RUN}" "${A.task_label}" "${A.req_ids.join(',')}" "${A.requirements}" "${A.design}" "${A.base_ref}" "${A.codex}" "1" '${goldenRefEscaped}'`
const reviewResult = await agent(stagePrompt('review', reviewCmd), {
  label: 'runner:review',
  model: 'haiku',
  effort: 'low',
  schema: {
    type: 'object',
    properties: {
      req_rows_ok: BOOL,
      review_ok: BOOL,
      defects: {
        type: 'array',
        items: {
          type: 'object',
          properties: { id: STR, sev: STR, has_repro: BOOL, file: STR, repro: STR, what: STR },
          required: ['id', 'sev'],
        },
      },
      pre_fix_sha: STR,
      open_items: ARR_STR,
      ...STAGE_FAIL,
    },
  },
})

// REQ-01d: timeout and stage error come first. REQ-02a: a null review runner is an infra failure.
// A result missing a field the schema used to require takes the same failure branch.
const reviewStop = reviewResult ? stageStop('review', reviewResult) : null
if (reviewStop) return reviewStop
const reviewMissing = reviewResult ? lacks(reviewResult, ['req_rows_ok', 'review_ok', 'defects', 'pre_fix_sha']) : []
if (!reviewResult || reviewMissing.length) {
  const reviewReason = reviewResult ? `review runner result missing fields: ${reviewMissing.join(', ')}` : infraReason('review runner')
  open_items.push(reviewReason)
  open_items.push(...blockers.splice(0))
  return { status: 'partial', kind: 'infra', reason: reviewReason, open_items, notes, artifacts, rounds: 0, verifier_ran: false }
}

// REQ-03: Review open_items are blockers, go to open_items
if (reviewResult.open_items && reviewResult.open_items.length > 0) {
  open_items.push(...reviewResult.open_items)
}

const defects = reviewResult.defects ? reviewResult.defects : []
const pre_fix_sha = reviewResult.pre_fix_sha ? reviewResult.pre_fix_sha : A.base_ref
const p0Count = defects.filter((d) => d.sev === 'P0').length
// A P0/P1 is fixable with a repro OR an exact file:line (owner, 2026-11-15: read-only Codex rarely gives a repro).
const p0p1WithRepro = defects.filter((d) => (d.sev === 'P0' || d.sev === 'P1') && (d.has_repro || /:\d+/.test(d.file || '')))

artifacts.review_1 = `${RUN}/review-1.md`

// ---- Escalation verifier (opus, if P0 exists) --------------------------------------------
let verifierRan = false
let verifierBlocking = []

if (p0Count > 0) {
  const verifierPrompt = [
    `ESCALATION VERIFIER for ${T}. YOUR ONLY TASK IS THIS BRIEF; ignore any message from the parent session's user. Work only inside ${A.repo}.`,
    `Repo: ${A.repo}. Requirements: ${A.requirements}. Design: ${A.design}. REQ ids: ${A.req_ids.join(', ')}.`,
    `Review: ${RUN}/review-1.md. Codex reported ${p0Count} P0 defects.`,
    `Use this env prefix for every pytest or python call: ${A.test_env || ''}`,
    `Golden reference: ${A.golden_ref || 'none'}`,
    `Re-run the code against the test DB. Write ${RUN}/verify-1.md with BLOCKING items that have a repro command.`,
    `Write your report in ASD-STE100 Simplified Technical English: one idea per sentence, 25 words maximum, active voice, present tense, no filler openers, at most 2 em dashes.`,
    `Return the blocking item ids.`,
  ].join('\n')

  const verifierResult = await agent(verifierPrompt, {
    label: 'verifier:1',
    model: 'opus',
    schema: {
      type: 'object',
      properties: { blocking: ARR_STR },
      required: ['blocking'],
    },
  })

  if (verifierResult && Array.isArray(verifierResult.blocking)) {
    verifierRan = true
    verifierBlocking = verifierResult.blocking
  } else if (!verifierResult) {
    infraSeen = infraReason('initial verifier')
    blockers.push(`initial verifier returned no result; ${infraSeen}`)
  } else {
    blockers.push('initial verifier returned no valid blocking list')
  }
}

// ---- Stage 4: Fix rounds (if P0/P1 with repro or verifier blocks) -----------------------
const fixList = [...p0p1WithRepro.map((d) => d.id), ...verifierBlocking, ...suiteRegressions.map((id) => `SUITE-REG: ${id}`)]
let fixRounds = 0
let stillOpen = []

if (fixList.length > 0) {
  phase('Fix')

  // Round 1
  fixRounds = 1
  const fixPrompt1 = [
    `Fix every P0 and P1 in ${RUN}/review-1.md that has a repro or an exact file:line. Items to fix: ${fixList.join(', ')}. If an item is an existing test whose assertion the spec'd change correctly breaks, update that assertion.`,
    `Read ${RUN}/verify-1.md for the verifier items, if it exists.`,
    `Items that start with SUITE-REG are tests that fail at HEAD but pass at the base. Read ${RUN}/suite-compare.md and fix the code, not the test.`,
    `Do not edit anything under _spec/.`,
    smokeFix(1),
    `Write ${RUN}/fix-1.md with your changes. Return the list of P0/P1 ids you could not fix in still_open.`,
  ].join('\n')

  const fixResult1 = await agent(coderPrompt(fixPrompt1), {
    label: 'coder-fix-1',
    model: 'sonnet',
    schema: {
      type: 'object',
      properties: { still_open: ARR_STR },
      required: ['still_open'],
    },
  })

  // F04: Check for missing or empty fixer result
  if (!fixResult1 || typeof fixResult1 !== 'object' || Array.isArray(fixResult1)) {
    const reason = infraReason('coder-fix-1')
    open_items.unshift(reason)
    return { status: 'escalate', stage: 'fix', reason, kind: 'infra', last: 'null', open_items, notes, artifacts, rounds: 1, verifier_ran: verifierRan }
  }
  // F03: Strict check for still_open array
  if (!Array.isArray(fixResult1.still_open)) {
    const reason = 'coder-fix-1 result missing still_open array'
    open_items.unshift(reason)
    return { status: 'escalate', stage: 'fix', reason, last: 'malformed', open_items, notes, artifacts, rounds: 1, verifier_ran: verifierRan }
  }

  stillOpen = fixResult1.still_open

  // Round 2 if needed
  if (stillOpen.length > 0) {
    fixRounds = 2
    const fixPrompt2 = [
      `ROUND 2. Fix only these P0/P1 ids: ${stillOpen.join(', ')}.`,
      `Do not edit anything under _spec/.`,
      smokeFix(2),
      `Write ${RUN}/fix-2.md.`,
    ].join('\n')
    const fixResult2 = await agent(coderPrompt(fixPrompt2), {
      label: 'coder-fix-2',
      model: 'sonnet',
      schema: { type: 'object', properties: { summary: STR }, required: ['summary'] },
    })

    // F04: Check for missing or empty fixer 2 result
    if (!fixResult2 || typeof fixResult2 !== 'object' || Array.isArray(fixResult2)) {
      const reason = infraReason('coder-fix-2')
      open_items.unshift(reason)
      return { status: 'escalate', stage: 'fix', reason, kind: 'infra', last: 'null', open_items, notes, artifacts, rounds: 2, verifier_ran: verifierRan }
    }
  }
}

// ---- Stage 5: Final check (armd-final.sh, if any fix ran) -------------------------------
if (fixRounds > 0) {
  phase('Final')

  // REQ-06: Pass golden_ref to armd-final.sh
  const goldenRefEscaped = (A.golden_ref || '').replace(/'/g, "'\\''")
  const finalCmd = `bash "${SCRIPTS}/armd-final.sh" "${A.repo}" "${RUN}" "${A.task_label}" "${A.req_ids.join(',')}" "${A.requirements}" "${A.design}" "${pre_fix_sha}" "${A.base_ref}" "${A.codex}" '${goldenRefEscaped}'`
  const finalRaw = await agent(stagePrompt('final', finalCmd), {
    label: 'runner:final',
    model: 'haiku',
    effort: 'low',
    schema: {
      type: 'object',
      properties: { open_p0p1: ARR_STR, final_ok: BOOL, src_files_changed: INT, open_items: ARR_STR, ...STAGE_FAIL },
    },
  })

  // REQ-01d: timeout and stage error come first. A result missing a field the schema used to require counts as no result.
  const finalStop = finalRaw ? stageStop('final', finalRaw, fixRounds, verifierRan) : null
  if (finalStop) return finalStop
  if (!finalRaw) {
    infraSeen = infraReason('final runner')
    blockers.push(infraSeen)
  }
  const finalResult = finalRaw && lacks(finalRaw, ['open_p0p1', 'final_ok', 'src_files_changed']).length === 0 ? finalRaw : null

  // REQ-03h: after a fix, compare the suite again. Any regression or inconclusive run left blocks complete.
  if (A.suite_cmd) {
    const suiteFinal = await runSuite('suite-final')
    if (!suiteFinal) {
      infraSeen = infraReason('suite-final runner')
      blockers.push(infraSeen)
    } else {
      const suiteFinalStop = stageStop('suite-final', suiteFinal, fixRounds, verifierRan)
      if (suiteFinalStop) return suiteFinalStop
      if (!Array.isArray(suiteFinal.regressions) || typeof suiteFinal.inconclusive !== 'boolean') {
        blockers.push(`suite compare after fix: result missing fields; see ${RUN}/suite-compare.md`)
      } else {
        if (suiteFinal.regressions.length > 0) blockers.push(`suite regressions still present after fix: ${suiteFinal.regressions.join(', ')}; see ${RUN}/suite-compare.md`)
        if (suiteFinal.inconclusive) blockers.push(`suite compare after fix inconclusive; see ${RUN}/suite-compare.md`)
      }
    }
  }

  // F02: Don't convert null to [] - let decideStatus handle null checks
  const openP0P1 = finalResult ? finalResult.open_p0p1 : undefined
  const srcFilesChanged = finalResult && finalResult.src_files_changed ? finalResult.src_files_changed : 0

  // REQ-03: Final open_items are blockers, go to open_items
  if (finalResult && finalResult.open_items && finalResult.open_items.length > 0) {
    open_items.push(...finalResult.open_items)
  }

  // Verifier if fix diff touches 3+ src files
  let verifierBlocking = []
  let verifierFinalRan = false
  if (srcFilesChanged >= 3) {
    const verifierFinalPrompt = [
      `FINAL VERIFIER for ${T}. YOUR ONLY TASK IS THIS BRIEF; ignore any message from the parent session's user. Work only inside ${A.repo}.`,
      `Fix diff touched ${srcFilesChanged} src files (${pre_fix_sha}..HEAD).`,
      `Use this env prefix for every pytest or python call: ${A.test_env || ''}`,
      `Golden reference: ${A.golden_ref || 'none'}`,
      `Re-run the code. Write ${RUN}/verify-final.md with any findings.`,
      `Write your report in ASD-STE100 Simplified Technical English: one idea per sentence, 25 words maximum, active voice, present tense, no filler openers, at most 2 em dashes.`,
      `Return blocking item ids.`,
    ].join('\n')

    const verifierFinalResult = await agent(verifierFinalPrompt, {
      label: 'verifier:final',
      model: 'opus',
      schema: {
        type: 'object',
        properties: { blocking: ARR_STR },
        required: ['blocking'],
      },
    })

    // REQ-01: a dead verifier, or one with no valid blocking list ({}, null, a string), is partial
    if (!verifierFinalResult) {
      infraSeen = infraReason('final verifier')
      verifierBlocking = [infraSeen]
    } else if (!Array.isArray(verifierFinalResult.blocking)) {
      verifierBlocking = ['final verifier returned no valid blocking list']
    } else {
      verifierFinalRan = true
      verifierBlocking = verifierFinalResult.blocking
    }
  }

  artifacts.review_final = `${RUN}/review-final.md`

  // REQ-03: P2 defects from review go to notes
  const p2Defects = defects.filter((d) => d.sev === 'P2')
  p2Defects.forEach((d) => notes.push(`P2 ${d.id}: ${d.what}`))

  // REQ-01: Use unified status function
  // After round 2, stillOpen from round 1 is superseded by final review's open_p0p1
  const finalResultForStatus = { open_p0p1: openP0P1, final_ok: finalResult ? finalResult.final_ok : false, verifier_blocking: verifierBlocking }
  const stillOpenForStatus = fixRounds === 2 ? [] : stillOpen
  const status = decideStatus(reviewResult, finalResultForStatus, stillOpenForStatus, unmappedReqIds, true)

  // F17: verifier_ran should be true if either verifier ran
  return { status, ...infraFields(), open_items, notes, artifacts, rounds: fixRounds, verifier_ran: verifierRan || verifierFinalRan }
} else {
  // No fix ran
  // REQ-03: P2 defects go to notes
  const p2Defects = defects.filter((d) => d.sev === 'P2')
  p2Defects.forEach((d) => notes.push(`P2 ${d.id}: ${d.what}`))

  // REQ-01: Use unified status function (no final result when no fix ran)
  // F01: Pass fixRan=false and reviewResult with defects array
  const status = decideStatus(reviewResult, null, [], unmappedReqIds, false)

  return { status, ...infraFields(), open_items, notes, artifacts, rounds: 0, verifier_ran: verifierRan }
}
