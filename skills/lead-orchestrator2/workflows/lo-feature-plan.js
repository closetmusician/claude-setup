export const meta = {
  name: 'lo-feature-plan',
  description: 'Decomposition check: map every spec requirement to a task before any task runs',
  whenToUse: 'lead-orchestrator2 feature mode, once per feature, before the lo-feature-task launches',
  phases: [
    { title: 'Map', detail: 'opus agent maps every spec requirement to the tasks that fully cover it', model: 'opus' },
  ],
}
// ABOUTME: Workflow script for lead-orchestrator2 feature mode: the decomposition check (round 1).
// ABOUTME: An opus agent reads the spec and the session's task list, and maps every requirement.
// ABOUTME: Plain code then fails the plan (status fix) if any requirement has no covering task.
// ABOUTME: Why: in tip-001 the session's T-002 mini_spec dropped spec 3.2 parts and nobody noticed.
// ABOUTME: Returns feature_reqs for lo-feature-close.js and a req_map per task for lo-feature-task.js.
// NOTE: every agent call names its model inline. workflow-model-guard.sh checks this lexically.

const STR = { type: 'string' }
const REQ = { type: 'object', properties: { req_id: STR, what: STR, done_when: STR, source: STR,
  task_ids: { type: 'array', items: STR } }, required: ['req_id', 'what', 'done_when', 'source', 'task_ids'] }
const PLAN = { type: 'object', properties: { requirements: { type: 'array', items: REQ }, path: STR },
  required: ['requirements', 'path'] }

// ---- Arguments ---------------------------------------------------------------------------
const A = args || {}
const REQUIRED = ['repo', 'feat_id', 'spec_path', 'run_dir']
const missing = REQUIRED.filter((k) => typeof A[k] !== 'string' || !A[k].trim())
const tasks = Array.isArray(A.tasks) ? A.tasks.filter((t) => t && t.task_id && t.mini_spec) : []
if (!tasks.length) missing.push('tasks (non-empty list of {task_id, mini_spec})')
if (missing.length) return { status: 'escalate', stage: 'args', reason: `missing args: ${missing.join(', ')}` }
const PATH = `${A.run_dir}/feature-map.md`
const ids = new Set(tasks.map((t) => t.task_id))

// Purpose: build the prompt for the independent mapping agent.
// Usage:   agent(planPrompt(''), {...}) · planPrompt('the previous agent returned nothing')
// Gotchas: the agent must split the spec itself; it never trusts the session's task wording.
const planPrompt = (note) => [
  `You are the DECOMPOSITION CHECKER for feature ${A.feat_id} in ${A.repo}. You did not write the task list.`,
  '## Mandatory Context',
  `- **Spec:** ${A.spec_path}. Read all of it first.  **Output file:** ${PATH}`,
  '- **Tasks the orchestrator plans to run (task_id: mini_spec):**',
  ...tasks.map((t) => `  - ${t.task_id}: ${t.mini_spec}`),
  '## Job',
  '1. Split the spec into atomic requirements: every output part, every acceptance criterion, every format and every rule.',
  '   One requirement per testable behaviour. Example: "the .md output has the method note" is separate from the .html one.',
  '2. For every requirement, list the task_ids whose mini_spec FULLY covers it. A task that names only part of it does not count.',
  '   If no task fully covers it, task_ids is []. Do not stretch a mini_spec to make it fit.',
  '3. Write the full table to the output file: req_id, what, done_when, source (spec section), task_ids, and a gap note for each [] row.',
  '## Constraints',
  '- Report only. Never edit the spec, the tasks or any code. Mark a requirement UNVERIFIED in the file if the spec is ambiguous.',
  '- Every value is a non-empty string, except task_ids. req_id format: REQ-01, REQ-02, ...',
  note ? `- Previous attempt problem: ${note}` : '',
].join('\n')

// ---- Map ---------------------------------------------------------------------------------
phase('Map')
let plan = await agent(planPrompt(''), { label: 'plan', phase: 'Map', model: 'opus', schema: PLAN })
if (!plan) plan = await agent(planPrompt('the previous agent returned nothing'), { label: 'plan:retry', phase: 'Map', model: 'opus', schema: PLAN })
if (!plan) return { status: 'escalate', stage: 'Map', reason: 'the decomposition checker returned nothing twice' }
const reqs = plan.requirements || []
if (!reqs.length) return { status: 'escalate', stage: 'Map', reason: `the checker found no requirements in ${A.spec_path}`, path: plan.path }

// Plain-code decision: a requirement is mapped only when it names at least one real task.
const covered = (q) => (q.task_ids || []).filter((id) => ids.has(id))
const unmapped = reqs.filter((q) => !covered(q).length)
const used = new Set(reqs.flatMap(covered))
const idle_tasks = tasks.map((t) => t.task_id).filter((id) => !used.has(id))
const feature_reqs = reqs.map((q) => ({ ...q, task_ids: covered(q) }))
const task_req_maps = {}
for (const t of tasks) {
  task_req_maps[t.task_id] = { task_id: t.task_id,
    requirements: feature_reqs.filter((q) => q.task_ids.includes(t.task_id))
      .map(({ req_id, what, done_when, source }) => ({ req_id, what, done_when, source, escalate_if: 'spec ambiguity or a missing dependency' })) }
}
log(`${A.feat_id}: ${reqs.length} requirements, ${unmapped.length} unmapped, ${idle_tasks.length} idle tasks`)
if (unmapped.length) {
  return { status: 'fix', path: PATH, unmapped, idle_tasks, feature_reqs,
    reason: `${unmapped.length} requirements have no task: ${unmapped.map((q) => `${q.req_id} ${q.what}`).join('; ')}` }
}
return { status: 'complete', path: PATH, feature_reqs, task_req_maps, idle_tasks, unmapped: [] }
