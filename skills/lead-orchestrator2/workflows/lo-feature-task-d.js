export const meta = {
  name: 'lo-feature-task-d',
  description: 'Arm D rev2: Spec Fix + Codex, stage scripts, no tests',
  whenToUse: 'LO2 benchmark arm D revision 2',
  phases: [
    { title: 'Spec', detail: 'armd-spec.sh: Codex spec fix, one round; opus resolver on P0/P1', model: 'haiku' },
    { title: 'Code', detail: 'sonnet coder, code only, no tests', model: 'sonnet' },
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

  if (reasons.length === 0) {
    return 'complete'
  } else {
    open_items.push(...reasons)
    return 'partial'
  }
}

// Purpose: build a runner prompt that runs exactly one command.
// Usage:   runnerPrompt('bash script.sh arg1 arg2')
// Gotchas: haiku + low effort, schema copies JSON from last stdout line. Timeout 10 min.
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
  `Write code only. Do not write new tests and do not run tests. You may update an EXISTING test whose assertion your change correctly breaks under the spec; never delete a failing test. Do not edit anything under _spec/. Write ${RUN}/coder-notes.md with your summary.`,
  `Write your report in ASD-STE100 Simplified Technical English: one idea per sentence, 25 words maximum, active voice, present tense, no filler openers, at most 2 em dashes.`,
  `Commit your work with \`git add <paths>\` and \`git commit\`. Never \`git add -A\`, never push, stash or reset.`,
  extra || '',
].join('\n')

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
  const specResult = await agent(runnerPrompt(specCmd), {
    label: 'runner:spec',
    model: 'haiku',
    effort: 'low',
    schema: {
      type: 'object',
      properties: { passed: BOOL, kind: STR, rounds: INT, open_items: ARR_STR },
      required: ['passed', 'kind', 'rounds'],
    },
  })

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
  if (!specResult) {
    const reason = 'spec runner failed'
    open_items.unshift(reason)
    return { status: 'escalate', stage: 'spec', reason, last: 'null', open_items, notes, artifacts, rounds: 0, verifier_ran: false }
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
      const reason = resolved ? `spec point needs the owner: ${resolved.summary}` : 'spec resolver returned nothing'
      open_items.unshift(reason)
      return { status: 'escalate', stage: 'spec', reason, last: JSON.stringify(specResult), open_items, notes, artifacts, rounds: 0, verifier_ran: false }
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
      const reason = checkResult ? checkResult.reason : 'spec-resolve-check returned nothing'
      open_items.unshift(`spec-resolve-check failed: ${reason}`)
      return { status: 'escalate', stage: 'spec', reason, last: JSON.stringify(resolved), open_items, notes, artifacts, rounds: 0, verifier_ran: false }
    }
  }

  // ---- Stage 2: Code (sonnet coder, no tests) ----------------------------------------------
  phase('Code')

  // Spec gate lock 2: the coder checks the pass file. Only armd-spec.sh (on a pass) or the resolver
  // writes it, so a runner that copies `passed` wrongly still cannot start the code stage.
  // REQ-06: Coder gets golden_ref in the prompt
  const coderResult = await agent(coderPrompt([
    `FIRST run \`test -f "${RUN}/spec-gate.pass"\`. If it fails, change nothing and return summary exactly SPEC GATE NOT PASSED.`,
  ].join('\n')), {
    label: 'coder',
    model: 'sonnet',
    schema: { type: 'object', properties: { summary: STR }, required: ['summary'] },
  })

  // F04: Check for missing or empty coder result
  if (!coderResult || typeof coderResult !== 'object' || Array.isArray(coderResult)) {
    const reason = 'coder returned nothing or malformed result'
    open_items.unshift(reason)
    return { status: 'escalate', stage: 'code', reason, last: 'null', open_items, notes, artifacts, rounds: 0, verifier_ran: false }
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

}

// ---- Stage 3: Review (armd-review.sh) ----------------------------------------------------
phase('Review')

// REQ-06: Pass golden_ref to armd-review.sh
const goldenRefEscaped = (A.golden_ref || '').replace(/'/g, "'\\''")
const reviewCmd = `bash "${SCRIPTS}/armd-review.sh" "${A.repo}" "${RUN}" "${A.task_label}" "${A.req_ids.join(',')}" "${A.requirements}" "${A.design}" "${A.base_ref}" "${A.codex}" "1" '${goldenRefEscaped}'`
const reviewResult = await agent(runnerPrompt(reviewCmd), {
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
    },
    required: ['req_rows_ok', 'review_ok', 'defects', 'pre_fix_sha'],
  },
})

if (!reviewResult) {
  open_items.push('review runner failed')
  return { status: 'partial', open_items, notes, artifacts, rounds: 0, verifier_ran: false }
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
  verifierRan = true
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

  if (verifierResult && verifierResult.blocking) {
    verifierBlocking = verifierResult.blocking
  }
}

// ---- Stage 4: Fix rounds (if P0/P1 with repro or verifier blocks) -----------------------
const fixList = [...p0p1WithRepro.map((d) => d.id), ...verifierBlocking]
let fixRounds = 0
let stillOpen = []

if (fixList.length > 0) {
  phase('Fix')

  // Round 1
  fixRounds = 1
  const fixPrompt1 = [
    `Fix every P0 and P1 in ${RUN}/review-1.md that has a repro or an exact file:line. Items to fix: ${fixList.join(', ')}. If an item is an existing test whose assertion the spec'd change correctly breaks, update that assertion.`,
    `Read ${RUN}/verify-1.md for the verifier items, if it exists.`,
    `Do not edit anything under _spec/.`,
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
    const reason = 'coder-fix-1 returned nothing or malformed result'
    open_items.unshift(reason)
    return { status: 'escalate', stage: 'fix', reason, last: 'null', open_items, notes, artifacts, rounds: 1, verifier_ran: verifierRan }
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
      `Write ${RUN}/fix-2.md.`,
    ].join('\n')
    const fixResult2 = await agent(coderPrompt(fixPrompt2), {
      label: 'coder-fix-2',
      model: 'sonnet',
      schema: { type: 'object', properties: { summary: STR }, required: ['summary'] },
    })

    // F04: Check for missing or empty fixer 2 result
    if (!fixResult2 || typeof fixResult2 !== 'object' || Array.isArray(fixResult2)) {
      const reason = 'coder-fix-2 returned nothing or malformed result'
      open_items.unshift(reason)
      return { status: 'escalate', stage: 'fix', reason, last: 'null', open_items, notes, artifacts, rounds: 2, verifier_ran: verifierRan }
    }
  }
}

// ---- Stage 5: Final check (armd-final.sh, if any fix ran) -------------------------------
if (fixRounds > 0) {
  phase('Final')

  // REQ-06: Pass golden_ref to armd-final.sh
  const goldenRefEscaped = (A.golden_ref || '').replace(/'/g, "'\\''")
  const finalCmd = `bash "${SCRIPTS}/armd-final.sh" "${A.repo}" "${RUN}" "${A.task_label}" "${A.req_ids.join(',')}" "${A.requirements}" "${A.design}" "${pre_fix_sha}" "${A.base_ref}" "${A.codex}" '${goldenRefEscaped}'`
  const finalResult = await agent(runnerPrompt(finalCmd), {
    label: 'runner:final',
    model: 'haiku',
    effort: 'low',
    schema: {
      type: 'object',
      properties: { open_p0p1: ARR_STR, final_ok: BOOL, src_files_changed: INT, open_items: ARR_STR },
      required: ['open_p0p1', 'final_ok', 'src_files_changed'],
    },
  })

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
    verifierFinalRan = true
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
    if (!verifierFinalResult || !Array.isArray(verifierFinalResult.blocking)) {
      verifierBlocking = ['final verifier returned no valid blocking list']
    } else {
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
  return { status, open_items, notes, artifacts, rounds: fixRounds, verifier_ran: verifierRan || verifierFinalRan }
} else {
  // No fix ran
  // REQ-03: P2 defects go to notes
  const p2Defects = defects.filter((d) => d.sev === 'P2')
  p2Defects.forEach((d) => notes.push(`P2 ${d.id}: ${d.what}`))

  // REQ-01: Use unified status function (no final result when no fix ran)
  // F01: Pass fixRan=false and reviewResult with defects array
  const status = decideStatus(reviewResult, null, [], unmappedReqIds, false)

  return { status, open_items, notes, artifacts, rounds: 0, verifier_ran: verifierRan }
}
