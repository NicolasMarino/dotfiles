## Local SDD Overrides (take precedence over the gentle-ai blocks above)

Derived from a measured baseline of 10 archived changes in `reels-lab` (2026-08-30).
Across that corpus the pipeline found **zero implementation defects by code review**:
all 3 FAIL verdicts were missing-test findings, and the single 6-round change was one
requirement that never enumerated its entry points. The raw table lives in the
knowledge vault under `03_Resources/Tech/IA Engineering/Auditoría SDD - Rondas hasta PASS.md`.

### L1. One test task per spec scenario (`sdd-tasks`)

`sdd-verify` marks any scenario without a test that actually ran as CRITICAL, however
correct the code is proven to be by other means. So `sdd-tasks` MUST emit an explicit
test task for every scenario in the delta specs, named with the scenario it covers.
A task list whose test tasks do not cover every scenario is incomplete — say so and fix
it before `sdd-apply`, rather than letting verify discover the gap later.

### L2. Validation requirements MUST enumerate entry points (`sdd-spec`)

A requirement of the form "X is validated" is incomplete. Every requirement that
constrains inbound data MUST carry one scenario per entry surface that can reach the
code path — CLI command, worker/queue boundary, HTTP handler, library API, each named
explicitly. Enumerate the surfaces by searching the codebase for call sites, never from
the proposal's prose alone.

### L3. Tiered preflight (overrides the four-question hard gate)

The `SDD Session Preflight` hard gate is scaled to what the command can actually do:

| Command | Preflight collected |
| --- | --- |
| `/sdd-status`, `/sdd-explore` | none — read-only, no artifacts, no PR |
| `/sdd-new`, `/sdd-ff`, `propose` → `tasks` | pace + artifact store only |
| `/sdd-apply` and beyond | all four, asked once the tasks forecast exists |

Collect the later groups when first needed and cache them, in one `AskUserQuestion`
call per tier. Never block a read-only command on a delivery decision.

### L4. Fan out `sdd-explore`

Exploration is breadth-first and read-only, so run it as three scoped explorers in
parallel — current state, prior art, constraints/entry points — then synthesize one
report. No file conflicts are possible.

### L5. Partitioned apply, and only when the partition is proven

`sdd-tasks` declares work units with the exact list of files each one writes. Units
whose file sets are disjoint may run as parallel writers in the same tree; any unit
that shares a file with another, or declares a dependency, stays serial. Never
parallelize writers on an unproven partition — two agents on one file overwrite each
other, which costs a whole run rather than saving one.

Verification of a unit may overlap with implementation of the next: it runs against
that unit's own frozen candidate, which the receipt machinery already guarantees.

### L6. Agent teams stay per-session

Never add `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS` to `settings.json`. Enabling it makes
every subagent Claude names launch as a full teammate at 3–5× the tokens, including in
delegation never framed as team work. Enable it on the command line for a session that
specifically wants debate — a bug with an unclear root cause, an architecture review.
Default delegation stays on subagents.

### L7. Classify every CRITICAL by origin

When `sdd-verify` raises a CRITICAL, state its origin: `coverage` (the code is correct
but no test that ran covers the scenario), `spec_ambiguity` (the requirement was
under-specified), or `implementation` (the code is actually wrong). Do not default to
`implementation`. That classification is the measurement the rules above were tuned on,
and it is what keeps the next tuning honest instead of guessed.
