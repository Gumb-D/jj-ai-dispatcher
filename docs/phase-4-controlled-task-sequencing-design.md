# P4 Controlled Task Sequencing Technical Design and Task Plan

## Status Banner

Status: design-only planning artifact.

This document defines the next project phase, P4 Controlled Task Sequencing. It is a technical design and task plan only. P4 runtime implementation is not authorized by this task.

This task does not authorize runtime code changes, test implementation, task executor implementation, new MCP tools, config changes, version changes, tag creation, service restart, public exposure changes, arbitrary shell APIs, WebSocket, SSE, browser console streaming, or any new MCP streaming tool.

The matching canonical copies are:

```text
docs/phase-4-controlled-task-sequencing-design.md
source/phase-4-controlled-task-sequencing-design.md
```

The copies must remain byte-identical.

## Purpose

P4 Controlled Task Sequencing designs a safe way to execute a pre-approved ordered task list through the existing Dispatcher model. The intent is to support a bounded multi-task phase where each task is explicit, serial, validated, checkpointed, auditable, recoverable after restart, and stopped immediately on failure.

P4 is not a general autonomous loop. It is a constrained sequence controller design for operator-approved task lists.

## Current Boundary Preserved

The approved MCP tool surface remains exactly four tools:

- `dispatcher_status`
- `dispatcher_dispatch`
- `dispatcher_latest_result`
- `dispatcher_get_run`

P4 must not add MCP tools. P4 must not add arbitrary shell, direct Git, file read/write, scheduler, queue management, service control, browser control, WebSocket, SSE, or streaming tools.

Existing result retrieval remains through `dispatcher_latest_result` and `dispatcher_get_run`. P4 may design persisted sequence metadata, but result retrieval must continue to depend on the existing persisted run result model.

## Non-Goals

P4 does not authorize:

- runtime implementation
- task executor implementation
- tests implementation
- new MCP tools
- new bridge endpoints
- arbitrary shell APIs
- direct Git MCP tools
- public exposure changes
- service restart
- tag creation
- version changes
- WebSocket, SSE, browser console streaming, or new MCP streaming tools
- queueing arbitrary unapproved tasks
- parallel task execution
- automatic recovery that resumes without an operator-approved checkpoint decision

## Controlled Sequencing Model

P4 sequencing is based on a pre-approved ordered task list. The operator approves the full sequence before execution begins. Each task has explicit safety fields and validation requirements. The Dispatcher executes at most one task at a time.

Core rules:

- The task list is immutable after sequence start.
- Tasks execute strictly in the approved order.
- No task starts until the previous task has completed and passed validation.
- Validation runs after each task.
- The sequence stops on task failure, validation failure, timeout, duplicate detection, checkpoint write failure, or safety boundary violation.
- Recovery never skips a failed or unknown task.
- Recovery never starts a task unless the persisted checkpoint proves the previous task completed and passed validation.
- Operator review remains the authority for rollback, restart, and continuation decisions.

## State Model

Sequence state is separate from run result state. A sequence references existing Dispatcher task IDs and persisted run results.

Sequence states:

- `draft`: task list is being prepared and is not executable.
- `approved`: task list has been explicitly approved and can start.
- `running`: exactly one task is active.
- `validating`: the latest completed task is being validated.
- `checkpointed`: latest task completed, validation passed, and checkpoint persisted.
- `blocked`: sequence stopped because operator action is required.
- `failed`: task execution or validation failed.
- `timed_out`: active task exceeded its duration limit.
- `completed`: all approved tasks completed and passed validation.
- `aborted`: operator intentionally stopped the sequence.

Task item states:

- `pending`
- `running`
- `succeeded`
- `validation_passed`
- `validation_failed`
- `failed`
- `timed_out`
- `skipped_by_abort`

State transitions must be append-only in the audit log. The current-state file is a convenience projection, not the audit source of truth.

## Persisted Checkpoints

P4 design requires checkpoints after every state transition that matters for recovery:

- sequence created
- sequence approved
- task started
- task completed
- task validation started
- task validation passed
- task validation failed
- sequence stopped
- sequence completed

Checkpoint persistence rules:

- Write sequence metadata under a deterministic sequence directory.
- Store append-only audit events.
- Store a current checkpoint projection for quick recovery.
- Include sequence ID, ordered task index, task ID, task state, validation result, timestamps, duration data, commit hash when present, and failure reason when present.
- Flush checkpoint data before starting the next task.
- Treat checkpoint write failure as a stop condition.

Proposed path shape:

```text
dispatcher/sequences/<sequence-id>/sequence.json
dispatcher/sequences/<sequence-id>/checkpoint.json
dispatcher/sequences/<sequence-id>/audit.jsonl
dispatcher/sequences/<sequence-id>/reports/summary.md
```

This is a design path only. This task does not authorize creating runtime state writers.

## Restart Recovery

Restart recovery must reconcile the sequence checkpoint with existing run results.

Recovery procedure:

1. Read the latest sequence checkpoint.
2. Read the append-only audit log.
3. Confirm the checkpoint is consistent with the audit log.
4. If the checkpoint references a completed task ID, retrieve its persisted run result.
5. Confirm the task result matches the checkpointed task index and expected task identity.
6. Resume only from the next pending task when the previous task has `validation_passed`.
7. Stop as `blocked` when state is `running`, `validating`, unknown, corrupted, missing a referenced result, or inconsistent.

Recovery must never assume that an in-memory active task survived restart. It must also never dispatch a replacement for an ambiguous task without operator review, because duplicate task execution can create conflicting commits.

## Duration Limits

Each sequence and each task must define duration limits before approval.

Required limits:

- per-task maximum execution duration
- per-task maximum validation duration
- total sequence maximum duration
- maximum recovery reconciliation duration

Timeout behavior:

- Mark the active task or sequence as `timed_out`.
- Persist a checkpoint and audit event.
- Do not start any later task.
- Report the timeout in the audit summary.
- Require operator review before retry, rollback, or abort.

Duration limits are safety controls, not scheduling controls. P4 does not authorize background scheduling.

## Duplicate Prevention

P4 duplicate prevention protects against repeated dispatches of the same approved task.

Required duplicate keys:

- sequence ID
- task index
- task identity hash
- task payload hash
- expected commit message
- prior Dispatcher task ID when assigned

Rules:

- A task index can have at most one active Dispatcher task ID.
- A completed task index cannot be dispatched again unless the operator creates a new explicit sequence or retry record.
- Recovery must compare payload hash and task ID before continuation.
- A duplicate detected before dispatch stops the sequence.
- A duplicate detected after restart moves the sequence to `blocked` for operator review.

## Validation After Each Task

Each task must include its own validation commands or manual checks. Validation is part of the task plan, not a later best effort.

Validation rules:

- Run validation after the task completes.
- Stop immediately on validation failure.
- Persist validation command, exit code, important output summary, timestamp, and result.
- Do not run the next task until validation passes.
- Include validation evidence in the sequence audit report.

P4 design accepts that some validation may be manual for documentation or policy tasks. Manual validation must still produce explicit completion evidence.

## Stop On Failure

Stop conditions:

- task execution failure
- validation failure
- duration limit exceeded
- duplicate detection
- checkpoint write failure
- missing or inconsistent persisted run result
- task result claims scope outside the approved task item
- unexpected MCP tool surface change
- public exposure or arbitrary shell capability detected
- operator abort

Stop behavior:

- Persist current state.
- Write an audit event.
- Do not dispatch any later task.
- Report the failed task index, task ID if assigned, failure reason, validation status, and recovery recommendation.

## Audit Reporting

Every P4 sequence must produce an audit report that can be reviewed without inspecting implementation logs.

Required report content:

- sequence ID
- approval timestamp
- ordered task list
- task safety fields
- dependencies
- per-task start and finish timestamps
- per-task duration
- Dispatcher task IDs
- validation evidence
- commit hash per task when present
- result retrieval references
- stop reason or completion status
- duplicate-prevention decisions
- restart-recovery decisions
- security boundary checks
- open decisions

Audit reporting must not expose secrets, local tokens, raw environment values, or unnecessary stdout/stderr content.

## Result Retrieval

P4 result retrieval uses the existing model:

- `dispatcher_latest_result` retrieves the newest completed persisted run result.
- `dispatcher_get_run` retrieves one specific persisted run result by task ID.

P4 sequence metadata may reference task IDs and summarize results, but it must not replace the existing run result contract. If the latest result is not the expected task, retrieval must use `dispatcher_get_run` with the exact task ID recorded in the checkpoint.

## Security Boundaries

P4 must preserve the local-first safety boundary:

- raw Dispatcher Bridge remains local-only
- MCP surface remains exactly four tools
- no arbitrary shell MCP API
- no direct Git MCP API
- no direct file read/write MCP API
- no browser control tool
- no public raw bridge exposure
- no new public listener
- no WebSocket or SSE
- no new MCP streaming tool
- no service restart capability in P4 runtime
- no automatic bypass of operator approval
- no parallel execution

The sequence controller must treat any request for blocked behavior as a hard failure.

## Schemas

The following schemas are conceptual design schemas only. They do not authorize runtime implementation.

### Sequence Definition

```json
{
  "sequenceId": "p4-YYYYMMDD-HHMMSS-<slug>",
  "schemaVersion": 1,
  "status": "approved",
  "createdAt": "2026-06-07T00:00:00.000Z",
  "approvedAt": "2026-06-07T00:00:00.000Z",
  "approvedBy": "operator",
  "durationLimits": {
    "taskExecutionMinutes": 30,
    "taskValidationMinutes": 10,
    "sequenceMinutes": 240,
    "recoveryMinutes": 10
  },
  "tasks": []
}
```

### Sequence Task

```json
{
  "index": 0,
  "workPackage": "P4.0",
  "title": "Design finalization and safety review",
  "dependsOn": [],
  "repo": "self",
  "worker": "codex",
  "commitMessage": "docs: example",
  "scope": ["docs", "source", "README.md"],
  "blocked": ["No runtime code changes", "No new MCP tools"],
  "validation": ["npm test", "npm run build", "git diff --check"],
  "expectedOutput": ["Files changed", "Validation results", "Commit hash"],
  "taskIdentityHash": "<sha256>",
  "payloadHash": "<sha256>",
  "state": "pending"
}
```

### Checkpoint

```json
{
  "sequenceId": "p4-YYYYMMDD-HHMMSS-<slug>",
  "schemaVersion": 1,
  "sequenceState": "checkpointed",
  "currentTaskIndex": 0,
  "lastCompletedTaskIndex": 0,
  "lastValidationState": "validation_passed",
  "dispatcherTaskId": "20260607-000000-abcdef12",
  "commitHash": "<git-sha>",
  "updatedAt": "2026-06-07T00:00:00.000Z",
  "nextAction": "start_next_task"
}
```

### Audit Event

```json
{
  "sequenceId": "p4-YYYYMMDD-HHMMSS-<slug>",
  "eventId": "000001",
  "timestamp": "2026-06-07T00:00:00.000Z",
  "type": "task.validation_passed",
  "taskIndex": 0,
  "workPackage": "P4.0",
  "dispatcherTaskId": "20260607-000000-abcdef12",
  "details": {
    "validation": "npm test",
    "exitCode": 0
  }
}
```

## Work Packages

### P4.0 Design Finalization and Safety Review

Dependencies: none.

Allowed scope:

- finalize the P4 controlled sequencing design
- define safety boundaries
- define state model and schemas
- define acceptance criteria
- update documentation mirrors

Blocked items:

- runtime implementation
- new MCP tools
- task executor implementation
- test implementation
- config or version changes
- service restart
- public exposure changes

Validation:

- design exists under `docs`
- design exists under `source`
- copies are byte-identical
- design states implementation is not authorized
- design preserves the four-tool MCP surface

Completion evidence:

- document paths
- byte-identical comparison result
- review note confirming no runtime files changed

### P4.1 Sequence Definition and Approval Contract

Dependencies: P4.0.

Allowed scope:

- design the sequence definition contract
- define immutable approved ordered task list behavior
- define required safety fields for each task
- define operator approval requirements

Blocked items:

- implementing sequence parser
- implementing approval UI
- accepting dynamic task insertion
- adding MCP tools or endpoints
- adding scheduler behavior

Validation:

- schema includes ordered tasks, dependencies, safety fields, duration limits, validation, and expected output
- contract rejects mutation after approval
- contract requires operator approval before execution

Completion evidence:

- approved sequence schema
- approval checklist
- examples of valid and invalid sequence definitions

### P4.2 Serial Execution and Stop Rules

Dependencies: P4.1.

Allowed scope:

- design strictly serial execution behavior
- define one-active-task invariant
- define stop-on-failure rules
- define validation gate between tasks

Blocked items:

- parallel execution
- background scheduler
- queue worker
- retry loop without operator approval
- direct shell or Git MCP execution

Validation:

- design proves no later task can start before previous validation passes
- stop conditions are complete
- failure states are terminal until operator review

Completion evidence:

- execution-state transition table
- stop-condition matrix
- validation-gate checklist

### P4.3 Checkpoint Persistence and Restart Recovery

Dependencies: P4.2.

Allowed scope:

- design checkpoint files
- design append-only audit events
- design restart reconciliation against persisted run results
- define stale and ambiguous state handling

Blocked items:

- service restart implementation
- automatic stale-state deletion
- automatic duplicate re-dispatch
- modifying existing run result contract

Validation:

- checkpoint model includes enough information to resume safely
- ambiguous active state becomes `blocked`
- missing or inconsistent result becomes `blocked`
- recovery cannot skip failed or unknown tasks

Completion evidence:

- checkpoint schema
- recovery algorithm
- stale-state decision table

### P4.4 Duration Limits, Duplicate Prevention, and Audit Reporting

Dependencies: P4.3.

Allowed scope:

- design task and sequence duration limits
- define duplicate-prevention keys
- define audit report contents
- define result retrieval references

Blocked items:

- scheduler implementation
- telemetry service
- streaming logs
- storing secrets in reports
- new retrieval tools

Validation:

- timeouts stop execution
- duplicate task detection stops execution
- audit report includes task IDs, validation evidence, commit hashes, and recovery decisions
- result retrieval remains through existing tools

Completion evidence:

- timeout policy
- duplicate-key policy
- audit report template

### P4.5 Test Plan, Rollout, and Rollback

Dependencies: P4.4.

Allowed scope:

- define test plan
- define rollout phases
- define rollback strategy
- define acceptance gates

Blocked items:

- implementing tests
- changing CI
- changing package scripts
- changing version or tags
- deploying runtime changes

Validation:

- test plan covers schemas, state transitions, stop behavior, validation failure, checkpoint recovery, duplicate prevention, audit reporting, and security boundary checks
- rollout has dry-run, local-only, and operator-reviewed gates
- rollback can disable P4 sequencing without altering existing single-task dispatch

Completion evidence:

- test matrix
- rollout checklist
- rollback checklist

### P4.6 Acceptance Review and Implementation Authorization Gate

Dependencies: P4.5.

Allowed scope:

- perform final design review
- compare implementation proposal against P4 safety boundaries
- decide whether runtime implementation should be separately authorized
- prepare implementation task envelopes for later approval

Blocked items:

- starting implementation during design review
- merging runtime changes under P4 design authorization
- creating tags
- restarting services
- expanding MCP surface

Validation:

- P4.0 through P4.5 completion evidence exists
- no blocked item was implemented
- open decisions are recorded
- explicit separate approval exists before implementation begins

Completion evidence:

- signed-off acceptance checklist
- open decisions list
- future implementation task envelopes
- explicit statement that implementation is or is not authorized

## Test Plan

P4 test implementation is not authorized by this task. The future P4 implementation test plan must cover:

- schema validation for sequence definition, task item, checkpoint, and audit event
- ordered execution invariants
- one-active-task invariant
- validation pass advances to next task
- validation failure stops sequence
- task failure stops sequence
- timeout stops sequence
- duplicate task detection before dispatch
- duplicate task detection after restart
- checkpoint write failure behavior
- checkpoint and audit consistency checks
- restart recovery from completed checkpoint
- restart recovery from active unknown state
- missing persisted result recovery block
- corrupted checkpoint recovery block
- audit report generation
- result retrieval by exact task ID
- no change to the four approved MCP tools
- rejection of arbitrary shell, direct Git, file access, public exposure, WebSocket, SSE, and streaming tool requests

Required validation commands for future implementation acceptance:

```powershell
npm test
npm run build
git diff --check
```

## Rollout Plan

P4 rollout must be separate from this design task.

Future rollout phases:

1. Documentation acceptance only.
2. Schema-only implementation behind no runtime execution path.
3. Dry-run planner that validates a sequence but dispatches nothing.
4. Local-only single-sequence execution with one active task and operator review.
5. Restart-recovery validation using completed persisted results.
6. Audit-report validation.
7. Explicit operator decision before any broader use.

No rollout phase may expand the MCP tool surface or expose the raw Dispatcher Bridge.

## Rollback Plan

P4 rollback must preserve current single-task dispatch behavior.

Rollback requirements:

- Disable sequence execution without removing existing single-task dispatch.
- Preserve persisted run results.
- Preserve sequence audit records for review.
- Leave MCP tools unchanged.
- Remove or ignore incomplete sequence checkpoints only after operator review.
- Do not delete task run directories as a rollback shortcut.
- Document any commits reverted or left in place.

## Acceptance Criteria

P4 design acceptance requires:

- P4 design exists under `docs`.
- P4 design exists under `source`.
- The `docs` and `source` copies are byte-identical.
- P4.0 through P4.6 are fully defined with dependencies, allowed scope, blocked items, validation, and completion evidence.
- The design covers a pre-approved ordered task list.
- The design requires strictly serial execution.
- The design requires validation after each task.
- The design requires stop on failure.
- The design covers persisted checkpoints.
- The design covers restart recovery.
- The design covers duration limits.
- The design covers duplicate prevention.
- The design covers audit reporting.
- The design covers result retrieval.
- The design covers security boundaries.
- The design includes a state model.
- The design includes schemas.
- The design includes a test plan.
- The design includes rollout and rollback.
- The design includes separate future workstreams for live console output and safe restart.
- The design preserves exactly four approved MCP tools.
- The design states that P4 runtime implementation is not authorized by this task.
- README contains only a short link to the design.

## Future Workstream 1: Local Dispatcher Live Codex Console Output

This is a separate future workstream from P4 Controlled Task Sequencing.

Goal: expose local Dispatcher live Codex console output to the operator by using existing stdout/stderr logs that are already produced by the local worker process.

Allowed future direction:

- read existing local stdout/stderr log files
- present bounded local console excerpts to the operator
- preserve existing run result retrieval as the authoritative result source
- redact secrets and tokens from displayed excerpts
- keep logs local

Explicitly blocked:

- WebSocket
- SSE
- browser console transport
- new MCP streaming tool
- public log exposure
- arbitrary shell API
- service restart
- replacing persisted result retrieval with logs

This workstream is observability only. It must not become a task execution channel.

## Future Workstream 2: Safe Bridge and MCP Service Restart plus Stale Task-State Recovery

This is a separate future workstream from P4 Controlled Task Sequencing.

Goal: design and later implement safe local restart procedures for the Dispatcher Bridge and MCP service, plus stale task-state recovery after interruption.

Allowed future direction:

- operator-approved local restart procedure
- detection of stale in-memory task state
- reconciliation with persisted run results
- safe recovery report
- no automatic deletion without operator review
- no automatic duplicate dispatch

Explicitly blocked:

- service restart as part of this P4 design task
- public restart endpoint
- remote restart capability
- arbitrary process control MCP tool
- automatic restart loop
- deletion of task state without audit
- skipping result reconciliation

This workstream must preserve the current four-tool MCP surface unless a later, separate, explicit authorization changes that boundary.

## Open Decisions

- Exact sequence ID format.
- Whether checkpoints use JSON-only files or include a signed checksum.
- Whether validation evidence stores full output or summarized output with local artifact pointers.
- Whether a future implementation uses one sequence directory per approval or per phase.
- How operator approval is represented in a local-only workflow.
- How retries are represented without weakening duplicate prevention.
