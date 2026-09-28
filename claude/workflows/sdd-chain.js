export const meta = {
  name: 'sdd-chain',
  description: 'Run the SDD pipeline as a deterministic DAG: fan-out explore, parallel spec/design, partitioned apply, overlapped verify',
  whenToUse:
    'A substantial change that already passed SDD preflight. Pass args: {change, repo, artifactStore, deliveryStrategy, testCommand, strictTdd}. ' +
    'Prototype: the prose contract in ~/.claude/skills/_shared/sdd-orchestrator-workflow.md stays authoritative for policy; this script is authoritative for execution order.',
  phases: [
    { title: 'Explore', detail: 'three scoped read-only explorers, then one synthesis' },
    { title: 'Propose', detail: 'proposal from the synthesized exploration' },
    { title: 'Contract', detail: 'spec and design in parallel — both read only the proposal' },
    { title: 'Tasks', detail: 'work units with disjoint file sets, one test task per scenario' },
    { title: 'Apply', detail: 'one writer per work unit, disjoint file sets only' },
    { title: 'Verify', detail: 'per work unit, overlapped with remaining apply work' },
    { title: 'Archive', detail: 'merge delta specs and close the change' },
  ],
}

// ---------------------------------------------------------------------------
// Inputs
// ---------------------------------------------------------------------------

const a = args || {}
const change = a.change
const repo = a.repo || '.'
const artifactStore = a.artifactStore || 'engram'
const deliveryStrategy = a.deliveryStrategy || 'ask-on-risk'
const testCommand = a.testCommand || null
const strictTdd = a.strictTdd === true

if (!change) {
  throw new Error('sdd-chain requires args.change — the change name, e.g. {"change":"add-http-api"}')
}

// Shared preamble every phase agent receives. Phase agents read artifacts from
// the backend themselves; we pass references, never artifact bodies.
const CTX = [
  `Change: ${change}`,
  `Repo: ${repo}`,
  `Artifact store: ${artifactStore}`,
  `Delivery strategy: ${deliveryStrategy}`,
  testCommand ? `Test command: ${testCommand}` : null,
  strictTdd
    ? 'STRICT TDD MODE IS ACTIVE. You MUST follow strict-tdd.md. Do NOT fall back to Standard Mode.'
    : null,
  `Topic keys: sdd/${change}/{explore|proposal|spec|design|tasks|apply-progress|verify-report|archive-report}`,
].filter(Boolean).join('\n')

// ---------------------------------------------------------------------------
// Schemas — these replace most of the orchestrator's contract-conformance gate.
// Validation happens at the tool-call layer, so a phase that returns the wrong
// shape is retried by the model instead of silently advancing.
// ---------------------------------------------------------------------------

const ENVELOPE = {
  type: 'object',
  required: ['status', 'executive_summary', 'artifacts', 'risks'],
  properties: {
    status: { type: 'string', enum: ['success', 'partial', 'blocked'] },
    executive_summary: { type: 'string' },
    artifacts: { type: 'array', items: { type: 'string' } },
    risks: { type: 'string' },
  },
}

const TASKS_SCHEMA = {
  type: 'object',
  required: ['status', 'executive_summary', 'artifacts', 'risks', 'work_units', 'forecast'],
  properties: {
    status: { type: 'string', enum: ['success', 'partial', 'blocked'] },
    executive_summary: { type: 'string' },
    artifacts: { type: 'array', items: { type: 'string' } },
    risks: { type: 'string' },
    scenario_coverage: {
      type: 'object',
      required: ['scenarios_total', 'scenarios_with_test_task'],
      properties: {
        scenarios_total: { type: 'integer' },
        scenarios_with_test_task: { type: 'integer' },
        uncovered: { type: 'array', items: { type: 'string' } },
      },
    },
    work_units: {
      type: 'array',
      items: {
        type: 'object',
        required: ['id', 'summary', 'files'],
        properties: {
          id: { type: 'string' },
          summary: { type: 'string' },
          files: {
            type: 'array',
            items: { type: 'string' },
            description: 'Every file this unit writes. Used to prove units are disjoint.',
          },
          depends_on: { type: 'array', items: { type: 'string' } },
        },
      },
    },
    forecast: {
      type: 'object',
      required: ['estimated_changed_lines', 'chained_prs_recommended', 'budget_risk'],
      properties: {
        estimated_changed_lines: { type: 'integer' },
        chained_prs_recommended: { type: 'boolean' },
        budget_risk: { type: 'string', enum: ['Low', 'Medium', 'High'] },
      },
    },
  },
}

const VERIFY_SCHEMA = {
  type: 'object',
  required: ['verdict', 'criticals', 'summary'],
  properties: {
    verdict: { type: 'string', enum: ['pass', 'pass_with_warnings', 'fail'] },
    summary: { type: 'string' },
    criticals: {
      type: 'array',
      items: {
        type: 'object',
        required: ['title', 'origin'],
        properties: {
          title: { type: 'string' },
          // The measured baseline (10 archived reels-lab changes, 2026-08-30) found
          // every FAIL was a coverage gap and every remediation round was one
          // under-specified requirement. Classifying origin here is what keeps the
          // rounds-to-PASS table honest instead of guessing after the fact.
          origin: {
            type: 'string',
            enum: ['coverage', 'spec_ambiguity', 'implementation'],
          },
          evidence: { type: 'string' },
        },
      },
    },
  },
}

// ---------------------------------------------------------------------------
// 1. Explore — breadth-first and read-only, so it fans out. This is the one
//    shape Anthropic's own evaluation shows multi-agent reliably winning at.
// ---------------------------------------------------------------------------

phase('Explore')

const LENSES = [
  {
    key: 'current-state',
    prompt: 'Map the CURRENT STATE of the code this change touches: the modules, entry points, data flow and existing tests. Report file:line anchors, never whole-file dumps.',
  },
  {
    key: 'prior-art',
    prompt: 'Find PRIOR ART in this repo: existing patterns, conventions and near-identical solutions this change should follow rather than reinvent. Include archived SDD changes that touched the same area.',
  },
  {
    key: 'constraints',
    prompt: 'Find CONSTRAINTS AND RISKS: every entry point that can reach the code paths this change touches (CLI, worker/queue, HTTP handler, library API), plus concurrency, migration and rollback hazards. Enumerating entry points is mandatory — a missed surface is the single defect class that has cost this pipeline the most remediation rounds.',
  },
]

const lensReports = (await parallel(
  LENSES.map((lens) => () =>
    agent(
      `${CTX}\n\nYou are the "${lens.key}" explorer for this change. Read-only: do not write files or artifacts.\n\n${lens.prompt}\n\nReturn a dense report. Close with a "## Key Learnings" section of 1-5 numbered standalone factual sentences.`,
      { label: `explore:${lens.key}`, phase: 'Explore', agentType: 'sdd-explore', model: 'sonnet' },
    ),
  ),
)).filter(Boolean)

if (lensReports.length < LENSES.length) {
  log(`WARNING: only ${lensReports.length}/${LENSES.length} explorers returned — synthesis is running on partial coverage.`)
}

const exploration = await agent(
  `${CTX}\n\nSynthesize these ${lensReports.length} independent exploration reports into ONE exploration artifact and persist it to topic key sdd/${change}/explore.\n\nReconcile contradictions explicitly rather than averaging them. Carry the entry-point inventory through verbatim — it drives the spec.\n\n${lensReports.map((r, i) => `--- REPORT ${i + 1} (${LENSES[i].key}) ---\n${r}`).join('\n\n')}`,
  { label: 'explore:synthesis', phase: 'Explore', agentType: 'sdd-explore', model: 'sonnet', schema: ENVELOPE },
)

// ---------------------------------------------------------------------------
// 2. Propose
// ---------------------------------------------------------------------------

phase('Propose')

const proposal = await agent(
  `${CTX}\n\nRead the exploration at sdd/${change}/explore and write the proposal. Persist it to sdd/${change}/proposal.\n\nExploration summary: ${exploration.executive_summary}`,
  { label: 'propose', phase: 'Propose', agentType: 'sdd-propose', model: 'opus', schema: ENVELOPE },
)

if (proposal.status !== 'success') {
  log(`Proposal returned status=${proposal.status}. Stopping before spec/design.`)
  return { stopped_at: 'propose', proposal }
}

// ---------------------------------------------------------------------------
// 3. Spec and design — a genuine barrier, because tasks needs both. But they
//    do NOT depend on each other: both read only the proposal, so serializing
//    them was accidental, not structural.
// ---------------------------------------------------------------------------

phase('Contract')

const [spec, design] = await parallel([
  () =>
    agent(
      `${CTX}\n\nRead the proposal at sdd/${change}/proposal and write the delta specs. Persist to sdd/${change}/spec.\n\nHARD RULE (L2): every requirement that constrains inbound data MUST carry one scenario per entry surface that can reach the code path — CLI command, worker/queue boundary, HTTP handler, library API, each named explicitly. A requirement of the form "X is validated" is incomplete. Derive the surfaces from the exploration's entry-point inventory and confirm them against real call sites, never from the proposal's prose alone.`,
      { label: 'spec', phase: 'Contract', agentType: 'sdd-spec', model: 'sonnet', schema: ENVELOPE },
    ),
  () =>
    agent(
      `${CTX}\n\nRead the proposal at sdd/${change}/proposal and write the technical design. Persist to sdd/${change}/design.`,
      { label: 'design', phase: 'Contract', agentType: 'sdd-design', model: 'opus', schema: ENVELOPE },
    ),
])

if (!spec || !design) {
  log('Spec or design failed to return. Stopping before tasks.')
  return { stopped_at: 'contract', spec, design }
}

// ---------------------------------------------------------------------------
// 4. Tasks — must declare file ownership per work unit (so apply can fan out
//    safely) and a test task per scenario (so verify stops finding coverage
//    gaps this pipeline created itself).
// ---------------------------------------------------------------------------

phase('Tasks')

const tasks = await agent(
  `${CTX}\n\nRead the spec at sdd/${change}/spec and the design at sdd/${change}/design, then write the task breakdown and persist it to sdd/${change}/tasks.\n\nHARD RULE (L1): emit an explicit test task for EVERY scenario in the delta specs, each named with the scenario it covers. sdd-verify marks any scenario without a test that actually ran as CRITICAL regardless of how correct the code is proven to be by other means, so a task list that leaves scenarios uncovered is incomplete by construction. Report the count honestly in scenario_coverage, including any scenario you could not cover and why.\n\nAlso partition the work into work_units, listing EVERY file each unit writes. Units whose file sets are disjoint run as parallel writers; overlapping units must be merged or ordered with depends_on.`,
  { label: 'tasks', phase: 'Tasks', agentType: 'sdd-tasks', model: 'sonnet', schema: TASKS_SCHEMA },
)

const cov = tasks.scenario_coverage
if (cov && cov.scenarios_with_test_task < cov.scenarios_total) {
  log(`WARNING: ${cov.scenarios_total - cov.scenarios_with_test_task}/${cov.scenarios_total} scenarios have no test task. Verify will raise these as CRITICAL. Uncovered: ${(cov.uncovered || []).join(', ') || 'unnamed'}`)
}

// Review workload guard — same thresholds as the prose contract.
if (tasks.forecast.budget_risk === 'High' || tasks.forecast.estimated_changed_lines > 400) {
  if (deliveryStrategy === 'ask-on-risk' || deliveryStrategy === 'single-pr') {
    log(`STOP: forecast is ${tasks.forecast.estimated_changed_lines} changed lines (risk ${tasks.forecast.budget_risk}) and delivery strategy is "${deliveryStrategy}". A human decision is required before apply.`)
    return { stopped_at: 'review-workload-guard', tasks }
  }
  log(`Forecast ${tasks.forecast.estimated_changed_lines} lines exceeds the 400-line budget; continuing under "${deliveryStrategy}".`)
}

// Prove the partition before trusting it. Overlapping writers overwrite each
// other, so anything not provably disjoint collapses back to a single writer.
const units = tasks.work_units || []
const owner = new Map()
const conflicted = new Set()
for (const u of units) {
  for (const f of u.files || []) {
    if (owner.has(f)) { conflicted.add(u.id); conflicted.add(owner.get(f)) }
    else owner.set(f, u.id)
  }
}

const parallelUnits = units.filter((u) => !conflicted.has(u.id) && !(u.depends_on || []).length)
const serialUnits = units.filter((u) => conflicted.has(u.id) || (u.depends_on || []).length)

log(`${units.length} work units: ${parallelUnits.length} parallel (disjoint files), ${serialUnits.length} serial (shared files or declared dependencies).`)

// ---------------------------------------------------------------------------
// 5 + 6. Apply and verify — pipelined, NOT barriered. Unit A verifies while
//    unit B is still being written. Verification runs against that unit's own
//    frozen candidate, which is what the receipt machinery already guarantees.
// ---------------------------------------------------------------------------

phase('Apply')

const applyUnit = (u) =>
  agent(
    `${CTX}\n\nImplement work unit "${u.id}" from sdd/${change}/tasks: ${u.summary}\n\nRead sdd/${change}/tasks, sdd/${change}/spec, sdd/${change}/design, and sdd/${change}/apply-progress if it exists — merge into apply-progress, never overwrite it.\n\nYou own EXACTLY these files and must not write any other: ${(u.files || []).join(', ')}. Other agents are writing other files in this same tree concurrently; touching a file outside your list overwrites their work.`,
    { label: `apply:${u.id}`, phase: 'Apply', agentType: 'sdd-apply', model: 'sonnet', schema: ENVELOPE },
  )

const verifyUnit = (u) =>
  agent(
    `${CTX}\n\nVerify work unit "${u.id}" against its spec requirements and tasks. Read sdd/${change}/spec, sdd/${change}/tasks and sdd/${change}/apply-progress.\n\nFor every CRITICAL you raise, classify its origin honestly:\n- "coverage": the code is correct but no test that ran covers the scenario\n- "spec_ambiguity": the requirement was under-specified (e.g. an entry point it never enumerated)\n- "implementation": the code is actually wrong\n\nThat classification is the measurement this pipeline is tuned on. Do not default to "implementation".`,
    { label: `verify:${u.id}`, phase: 'Verify', agentType: 'sdd-verify', model: 'sonnet', schema: VERIFY_SCHEMA },
  )

// Serial units first (they share files or have dependencies), then the
// disjoint ones pipelined through apply -> verify with no barrier between.
const serialResults = []
for (const u of serialUnits) {
  const applied = await applyUnit(u)
  serialResults.push({ unit: u.id, applied, verified: applied ? await verifyUnit(u) : null })
}

const parallelResults = (await pipeline(
  parallelUnits,
  (u) => applyUnit(u),
  (applied, u) => (applied ? verifyUnit(u).then((v) => ({ unit: u.id, applied, verified: v })) : null),
)).filter(Boolean)

const results = [...serialResults, ...parallelResults].filter((r) => r && r.verified)

// ---------------------------------------------------------------------------
// 7. Archive — only when every unit verified clean.
// ---------------------------------------------------------------------------

const criticals = results.flatMap((r) => r.verified.criticals || [])
const byOrigin = criticals.reduce((acc, c) => { acc[c.origin] = (acc[c.origin] || 0) + 1; return acc }, {})

log(`Verify complete: ${criticals.length} CRITICALs across ${results.length} units — ${JSON.stringify(byOrigin)}`)

if (criticals.length > 0) {
  log('Not archiving: CRITICALs remain. Fix them, then resume this run with resumeFromRunId — completed phases return from cache and only the edited stages re-run.')
  return { stopped_at: 'verify', criticals, by_origin: byOrigin, results }
}

phase('Archive')

const archive = await agent(
  `${CTX}\n\nEvery work unit verified clean (0 CRITICAL across ${results.length} units). Archive the change: merge delta specs into the main specs, move the change folder to archive, and persist the archive report to sdd/${change}/archive-report.\n\nFinal-state facts outrank the intermediate apply-progress and verify-report snapshots. Units verified: ${results.map((r) => `${r.unit}=${r.verified.verdict}`).join(', ')}`,
  { label: 'archive', phase: 'Archive', agentType: 'sdd-archive', model: 'haiku', schema: ENVELOPE },
)

return {
  change,
  units: results.length,
  criticals: 0,
  by_origin: byOrigin,
  archive: archive.executive_summary,
}
