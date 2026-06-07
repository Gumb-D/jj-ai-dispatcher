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

Live Codex Console observability remains a separate future workstream. Safe bridge restart and stale task-state recovery remain a separate future workstream. Neither workstream is authorized by this P4 design contract.

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
- implementation of Live Codex Console observability
- implementation of safe bridge restart or stale task-state recovery

## Resolved Readiness Decisions

The following decisions resolve the readiness blockers identified in run `20260607-214738-edef168a`:

1. Task/run correlation: a sequence must persist the exact Dispatcher `taskId` returned by `dispatcher_dispatch` before recovery can ever continue. If the current dispatch response cannot synchronously provide that exact ID, the future implementation must change the `dispatcher_dispatch` result contract to include it and must persist `dispatcher/runs/<task-id>/task.json` before returning. This preserves the current four MCP tools and adds no new retrieval surface.
2. Validation ownership: the sequence controller owns validation execution and PASS/FAIL decisions. The worker may suggest validation, but the controller records and evaluates the evidence.
3. Commit/push boundaries: every P4 task is dispatched with per-task no-push. Dispatcher-owned commit may still occur as the task execution boundary. Validation gates continuation and push eligibility; if validation fails after a commit, the sequence stops and the committed hash is quarantined in the audit report for operator rollback, amend, or follow-up decision.
4. Artifact location: runtime sequence artifacts are designed for `dispatcher/sequences/<sequence-id>/`, which is ignored by `.gitignore` and must not dirty the repo.
5. Pause, cancel, resume, and retry semantics: all are operator-boundary actions with explicit state transitions and audit events. No automatic resume or retry is allowed.
6. Legal state transitions: sequence and task transition tables are defined below, including terminal and resumable states.
7. Canonical hashing and idempotency: JSON canonicalization, included and excluded fields, hash timing, idempotency key, duplicate detection, and retry identity rules are defined below.
8. Timeout mapping: Dispatcher execution failure metadata maps deterministically into P4 `timed_out` states as defined below.
9. Checkpoint ownership: the sequence controller owns checkpoints, writes audit events before current-state projections, uses atomic replace, and blocks when result persistence and checkpoint persistence disagree.
10. Failure taxonomy: task failure, validation failure, timeout, checkpoint failure, stale active task, missing result, result mismatch, unsafe boundary, push failure, and delivery-only failure are covered by the recovery matrix below.

There are no open design decisions in this contract. Future implementation may refine field names only through a separately approved implementation task that preserves these decisions.

## Controlled Sequencing Model

P4 sequencing is based on a pre-approved ordered task list. The operator approves the full sequence before execution begins. Each task has explicit safety fields, blocked items, validation requirements, duration limits, and expected outputs. The Dispatcher executes at most one task at a time.

Core rules:

- The task list is immutable after sequence start.
- Tasks execute strictly in the approved order.
- No task starts until the previous task has completed, produced a correlated persisted result, passed controller-owned validation, and persisted a checkpoint.
- Validation runs after each task and before any later dispatch.
- The sequence stops on task failure, validation failure, timeout, duplicate detection, checkpoint write failure, result mismatch, unsafe boundary, push failure, or operator cancellation.
- Recovery never skips a failed or unknown task.
- Recovery never starts a task unless the persisted checkpoint proves the previous task completed and passed validation.
- Operator review remains the authority for rollback, restart, cancellation, continuation, and retry decisions.

## Task and Run Correlation Contract

Each sequence task must correlate to exactly one Dispatcher run result. The correlation is based on the exact `taskId`, not on latest-result ordering, timestamp proximity, commit message, or payload similarity.

Required dispatch behavior:

1. Before dispatch, the controller writes an audit event `task.dispatch_requested` with the approved task index, task identity hash, payload hash, idempotency key, and expected commit message.
2. The controller calls the existing `dispatcher_dispatch` tool with the approved task payload.
3. `dispatcher_dispatch` must synchronously return the exact assigned `taskId`.
4. The Dispatcher must durably persist the submitted task envelope at `dispatcher/runs/<task-id>/task.json` before the dispatch response is considered valid.
5. The controller writes `task.dispatched` and the current checkpoint with the exact `taskId` before it waits for completion or performs any recovery-sensitive action.
6. Result lookup after task completion uses `dispatcher_get_run` with the exact recorded `taskId`. `dispatcher_latest_result` is advisory only and cannot establish task identity.

Future contract change, if needed: if the current `dispatcher_dispatch` response does not provide the exact durable `taskId`, the future P4 implementation must extend that existing tool's response to include `taskId`, `taskPath`, and `acceptedAt`. This is a response-contract change to one of the four existing tools, not a new MCP tool.

Required result correlation fields:

- `taskId`: exact Dispatcher task ID returned by dispatch.
- `sequenceId`: sequence ID supplied in the task metadata.
- `taskIndex`: approved zero-based index.
- `taskIdentityHash`: hash of stable task identity fields.
- `payloadHash`: hash of the exact dispatch payload.
- `idempotencyKey`: stable key for this sequence/task attempt.
- `commitMessage`: expected commit message.
- `repo`: approved repo identifier.
- `worker`: approved worker identifier.

Result acceptance rules:

- PASS correlation only when the persisted run result's `taskId`, `repo`, `worker`, `commitMessage`, `taskIndex`, `taskIdentityHash`, `payloadHash`, and `idempotencyKey` match the checkpointed task.
- FAIL correlation when any required field differs, is absent, or is available only through inference.
- Missing optional sequence metadata in older single-task results is not accepted for P4 continuation. P4 requires the future dispatch/result contract to carry these fields before runtime implementation is authorized.

## Validation Ownership Contract

The sequence controller owns validation execution, redaction, evidence persistence, and deterministic PASS/FAIL decisions. The Dispatcher worker is responsible for executing the task and may include suggested validation results in its report, but worker-supplied validation is advisory.

Validation sources:

- Controller-run command validation from the approved allowlist.
- Manual validation evidence entered by the operator.
- Static result-contract checks performed by the controller.

Allowed validation command contract:

- Every validation command must be listed in the approved task's `validation` array before sequence approval.
- Every command must match one allowlist entry exactly after whitespace normalization.
- The allowlist is repository-specific and design-time; it is not an arbitrary shell API.
- Commands may not include shell metacharacters for chaining, redirection, command substitution, environment expansion, background execution, network listeners, or file deletion.
- Commands may not accept operator-supplied runtime arguments after approval.
- Commands must run from the approved repo root.
- Commands must have a validation timeout and bounded stdout/stderr capture.

Initial allowlist for this repository:

| Command | Purpose |
| --- | --- |
| `npm test` | Full existing test suite. |
| `npm run build` | Existing syntax/build validation. |
| `git diff --check` | Whitespace and patch sanity check. |
| `git status --short` | Working-tree cleanliness evidence. |
| `cmd /c fc /b docs\phase-4-controlled-task-sequencing-design.md source\phase-4-controlled-task-sequencing-design.md` | Windows byte-identical mirror check for this design document. |

Manual validation evidence contract:

- Manual checks are allowed only when the approved task declares `manualValidationAllowed: true`.
- Manual evidence must include `checkedBy`, `checkedAt`, `checkName`, `expected`, `observed`, `result`, and `evidenceSummary`.
- Manual evidence must be redacted before persistence.
- Manual validation cannot override a failed required command.
- Manual validation cannot validate runtime behavior that the P4 design task explicitly blocks.

Deterministic validation result rules:

- PASS only when every required controller-run command exits `0`, every required manual check is marked PASS, all required output fields are present, correlation checks pass, and redaction succeeds.
- FAIL when any command exits non-zero, times out, is missing, is not allowlisted, emits unredactable secret material, or when any required manual check is missing or marked FAIL.
- FAIL when validation evidence cannot be persisted atomically.
- FAIL when the repo is dirty after a Dispatcher-owned commit except for ignored runtime artifacts.
- Delivery-only failures do not fail validation when `executionStatus` is success and the result is otherwise correlated.

## Secret Redaction Rules

Audit reports, checkpoints, validation summaries, and sequence metadata must not expose secrets.

Redaction requirements:

- Redact values matching common token shapes, including GitHub tokens, npm tokens, OpenAI-style keys, bearer tokens, JWTs, private keys, password assignments, connection strings, and cloud access keys.
- Redact environment-variable values and preserve only variable names when needed.
- Redact absolute user-profile paths unless the path is part of an approved repo-relative artifact reference.
- Redact command stdout/stderr beyond bounded excerpts.
- Store full raw logs only as local artifact references when they already exist in Dispatcher run artifacts; do not copy raw logs into sequence reports.
- If redaction is uncertain, treat the evidence as unsafe, mark validation failed, and block the sequence for operator review.

Redaction placeholders:

- `[REDACTED:token]`
- `[REDACTED:secret]`
- `[REDACTED:env-value]`
- `[REDACTED:absolute-path]`
- `[REDACTED:output-truncated]`

## Commit and Push Boundary Contract

P4 dispatches must set per-task push behavior to no-push until validation passes. This is mandatory even when the global Dispatcher policy would otherwise allow push.

Commit boundary:

- Dispatcher remains the owner of task execution and any task-level commit it already performs.
- The sequence controller does not perform direct Git commits through MCP.
- A Dispatcher-owned commit is allowed to exist before validation because the current Dispatcher model commits as part of task completion.
- The sequence controller records the commit hash from the correlated run result.
- A commit does not make a task sequence-pass eligible until controller-owned validation passes.

Push boundary:

- P4 must not push before validation passes.
- P4 must not push automatically as part of this design task.
- Future implementation may request an operator-approved push only after the full sequence or a declared checkpoint passes validation.
- Push failure is a sequence stop condition and must not be converted into task success.

Validation failure after commit:

- Mark the task `validation_failed` and the sequence `failed_with_commit`.
- Persist the commit hash as `quarantinedCommitHash`.
- Do not dispatch later tasks.
- Do not push.
- Require operator decision: keep commit and create follow-up task, amend/revert manually, retry with new attempt identity, or cancel the sequence.

Task failure after commit:

- If a commit exists despite a failed task result, mark the sequence `failed_with_commit`.
- Persist the commit hash as quarantined evidence.
- Require operator review before any retry or rollback.

## Runtime Artifact Location

Canonical runtime artifact path:

```text
dispatcher/sequences/<sequence-id>/
```

Canonical layout:

```text
dispatcher/sequences/<sequence-id>/sequence.json
dispatcher/sequences/<sequence-id>/checkpoint.json
dispatcher/sequences/<sequence-id>/checkpoint.json.sha256
dispatcher/sequences/<sequence-id>/audit.jsonl
dispatcher/sequences/<sequence-id>/tasks/<task-index>/dispatch.json
dispatcher/sequences/<sequence-id>/tasks/<task-index>/validation.json
dispatcher/sequences/<sequence-id>/tasks/<task-index>/result-ref.json
dispatcher/sequences/<sequence-id>/reports/audit.md
dispatcher/sequences/<sequence-id>/reports/summary.md
```

The path is under `dispatcher/` for local runtime state, but `dispatcher/sequences/` must be ignored by Git. Runtime sequence artifacts must not dirty the repo. Documentation examples may mention this path; runtime files must not be committed.

## State Model

Sequence state is separate from Dispatcher run result state. A sequence references existing Dispatcher task IDs and persisted run results.

Sequence states:

- `draft`: task list is being prepared and is not executable.
- `approved`: task list has been explicitly approved and can start.
- `dispatching`: controller is submitting exactly one task and waiting for a durable `taskId`.
- `running`: exactly one Dispatcher task has a recorded `taskId` and is active.
- `validating`: the latest completed task is being validated by the controller.
- `checkpointed`: latest task completed, validation passed, and checkpoint persisted.
- `paused`: operator paused the sequence at a safe boundary.
- `blocked`: sequence stopped because operator action is required before any continuation decision.
- `failed`: task execution, validation, push, or safety boundary failed without timeout.
- `failed_with_commit`: task or validation failed after a Dispatcher-owned commit exists.
- `timed_out`: active task, validation, recovery, or total sequence duration exceeded its limit.
- `completed`: all approved tasks completed and passed validation.
- `cancelled`: operator intentionally ended the sequence before completion.

Task item states:

- `pending`
- `dispatching`
- `running`
- `succeeded`
- `validating`
- `validation_passed`
- `validation_failed`
- `failed`
- `failed_with_commit`
- `timed_out`
- `paused`
- `cancelled`
- `retry_superseded`

Terminal sequence states:

- `completed`
- `cancelled`

Stopped sequence states that require operator decision before any new work:

- `failed`
- `failed_with_commit`
- `timed_out`

Resumable sequence states:

- `approved` when no task has started.
- `checkpointed` when the next task is pending and operator approves continuation.
- `paused` when paused at a safe boundary and checkpoint consistency passes.
- `blocked` only after operator resolves the block with an explicit resume, retry, or cancel decision.

Non-resumable without operator decision:

- `dispatching`
- `running`
- `validating`
- any state with missing result, mismatched result, unsafe boundary, checkpoint corruption, or unknown active task.

## Legal Sequence State Transitions

| From | To | Trigger | Recovery action |
| --- | --- | --- | --- |
| `draft` | `approved` | Operator approves immutable sequence. | Start first task only after checkpoint. |
| `approved` | `dispatching` | Operator starts or resumes at first pending task. | If interrupted, block unless no dispatch was attempted. |
| `dispatching` | `running` | Exact durable `taskId` is returned and checkpointed. | Retrieve by exact `taskId`. |
| `dispatching` | `blocked` | Dispatch response missing durable `taskId` or checkpoint write fails. | Operator review; do not redispatch automatically. |
| `running` | `validating` | Correlated run result reports successful execution. | Run controller validation. |
| `running` | `failed` | Correlated run result reports failure without commit. | Stop; operator review. |
| `running` | `failed_with_commit` | Correlated run result reports failure with commit. | Stop; quarantine commit. |
| `running` | `timed_out` | Execution duration exceeds limit or Dispatcher metadata reports timeout. | Stop; reconcile exact result before retry. |
| `validating` | `checkpointed` | Validation passes and checkpoint persists. | Next task may start after operator or policy-approved continuation. |
| `validating` | `failed` | Validation fails without commit. | Stop; operator review. |
| `validating` | `failed_with_commit` | Validation fails after commit exists. | Stop; quarantine commit. |
| `validating` | `timed_out` | Validation duration exceeds limit. | Stop; operator review. |
| `checkpointed` | `dispatching` | Next task is pending and continuation is approved. | Dispatch next approved task. |
| `checkpointed` | `completed` | No pending tasks remain. | Write final audit report. |
| `approved` | `paused` | Operator pauses before first dispatch. | Resume allowed after checkpoint check. |
| `checkpointed` | `paused` | Operator pauses at safe boundary. | Resume allowed after checkpoint check. |
| `paused` | `dispatching` | Operator resumes and next task is pending. | Dispatch next approved task. |
| `paused` | `cancelled` | Operator cancels. | Mark remaining tasks cancelled. |
| `blocked` | `dispatching` | Operator resolves block and approves continuation at safe pending task. | Dispatch only if no ambiguous active task exists. |
| `blocked` | `cancelled` | Operator cancels. | Mark remaining tasks cancelled. |
| `failed` | `cancelled` | Operator cancels failed sequence. | No later tasks dispatch. |
| `failed_with_commit` | `cancelled` | Operator cancels failed sequence. | Preserve quarantined commit evidence. |
| `timed_out` | `cancelled` | Operator cancels timed-out sequence. | Preserve timeout evidence. |
| `timed_out` | `blocked` | Operator requests investigation before retry. | Reconcile result and checkpoint. |

No transition is legal out of `completed`. No transition from `failed`, `failed_with_commit`, or `timed_out` to `dispatching` is legal without creating an explicit retry attempt record and first moving through `blocked`.

## Legal Task State Transitions

| From | To | Trigger |
| --- | --- | --- |
| `pending` | `dispatching` | Sequence controller submits approved task. |
| `dispatching` | `running` | Exact durable `taskId` is recorded. |
| `dispatching` | `failed` | Dispatch fails before task starts. |
| `dispatching` | `timed_out` | Dispatch acknowledgement exceeds limit. |
| `running` | `succeeded` | Correlated run result reports execution success. |
| `running` | `failed` | Correlated run result reports execution failure without commit. |
| `running` | `failed_with_commit` | Correlated run result reports failure with commit. |
| `running` | `timed_out` | Execution exceeds task limit or Dispatcher reports timeout. |
| `succeeded` | `validating` | Controller validation starts. |
| `validating` | `validation_passed` | All validation evidence passes and persists. |
| `validating` | `validation_failed` | Any required validation fails. |
| `validating` | `timed_out` | Validation exceeds limit. |
| `pending` | `cancelled` | Operator cancels sequence before task starts. |
| `pending` | `paused` | Operator pauses before task starts. |
| `paused` | `pending` | Operator resumes before task starts. |
| `validation_failed` | `retry_superseded` | Operator creates approved retry attempt. |
| `failed` | `retry_superseded` | Operator creates approved retry attempt. |
| `failed_with_commit` | `retry_superseded` | Operator creates approved retry attempt after commit decision. |
| `timed_out` | `retry_superseded` | Operator creates approved retry attempt after reconciliation. |

No task may transition from a terminal failure state directly back to `running`. Retry creates a new attempt identity and preserves the original task state as historical evidence.

## Pause, Cancel, Resume, and Retry Semantics

Pause:

- Operator may pause only before dispatch or after a `checkpointed` safe boundary.
- A pause request while `dispatching`, `running`, or `validating` records `pause_requested` but does not interrupt the active operation.
- The controller enters `paused` only after the active task reaches a safe boundary.

Cancel:

- Operator may cancel at any state.
- Cancellation never kills an already-running Dispatcher task through P4.
- If cancellation is requested during `running`, the sequence moves to `blocked` until the exact result is reconciled, then to `cancelled`.
- Pending tasks become `cancelled`; completed task evidence remains unchanged.

Resume:

- Resume requires operator approval, checkpoint hash verification, audit/checkpoint consistency, and exact result correlation for the last completed task.
- Resume can start only from `approved`, `checkpointed`, or `paused`, or from `blocked` after the block is explicitly resolved.
- Resume from stale `running`, `dispatching`, or `validating` is forbidden without operator reconciliation.

Retry:

- Retry is not automatic.
- Retry requires an operator-approved retry record that references the original sequence ID, original task index, original attempt number, failure reason, and operator decision about any existing commit.
- Retry uses a new `attempt` number, new idempotency key, new payload hash if payload changes, and new Dispatcher `taskId`.
- Retry does not erase or overwrite prior task artifacts.
- Retry is allowed only for failed, validation-failed, timed-out, or blocked tasks after recovery analysis confirms no ambiguous active task remains.

Operator boundaries:

- The operator approves initial sequence start.
- The operator approves continuation after pause, block, timeout, retry, rollback, and cancellation.
- The operator owns decisions about quarantined commits and push attempts.
- P4 controller records decisions; it does not infer them.

## Persisted Checkpoints

P4 design requires checkpoints after every state transition that matters for recovery:

- sequence created
- sequence approved
- task dispatch requested
- exact task ID assigned
- task completed
- task validation started
- task validation passed
- task validation failed
- pause requested
- pause entered
- retry approved
- sequence stopped
- sequence completed
- sequence cancelled

Checkpoint ownership:

- The sequence controller is the only writer of sequence checkpoints and sequence audit events.
- The Dispatcher owns run artifacts under `dispatcher/runs/<task-id>/`.
- The controller may reference Dispatcher run artifacts but must not rewrite them.

Atomic write strategy:

- Write append-only audit events first to `audit.jsonl.tmp`.
- Flush and atomically append or replace according to the implementation platform's supported safe-write primitive.
- Write `checkpoint.json.tmp` with the complete current projection.
- Write `checkpoint.json.sha256.tmp` containing the SHA-256 of canonical `checkpoint.json`.
- Flush both files.
- Atomically replace `checkpoint.json`, then atomically replace `checkpoint.json.sha256`.
- Re-read both files and verify the checksum before considering the checkpoint persisted.

Write ordering:

1. Audit event for intent, such as `task.dispatch_requested`.
2. External action, such as `dispatcher_dispatch`.
3. Audit event for observed result, such as `task.dispatched`.
4. Current checkpoint projection.
5. Validation or audit report artifact, when applicable.

Checkpoint persistence rules:

- Include sequence ID, task index, attempt, task ID, task state, validation result, timestamps, duration data, commit hash when present, payload hash, idempotency key, and failure reason when present.
- Flush and verify checkpoint data before starting the next task.
- Treat checkpoint write failure as a stop condition.
- If audit append succeeds but checkpoint projection fails, recover from audit and block before any new dispatch.
- If checkpoint projection exists without the corresponding audit event, treat the checkpoint as untrusted and block.

Result/checkpoint disagreement:

- If the checkpoint says `validation_passed` but the correlated result is missing or mismatched, the sequence becomes `blocked`.
- If the result says success but the checkpoint was not persisted, the sequence becomes `blocked`; the operator may approve reconstruction from audit and exact result evidence.
- If the result says failure but the checkpoint says success, the sequence becomes `blocked_result_mismatch` in audit details and cannot resume until operator investigation.
- If a Dispatcher result exists for an uncheckpointed dispatch attempt, treat it as stale active task evidence and block duplicate dispatch.

## Restart Recovery

Restart recovery must reconcile the sequence checkpoint with existing run results.

Recovery procedure:

1. Read `sequence.json`.
2. Read `audit.jsonl`.
3. Read `checkpoint.json` and `checkpoint.json.sha256`.
4. Verify the checkpoint hash using canonical JSON.
5. Confirm the checkpoint is consistent with the audit log.
6. If the checkpoint references a completed or active task ID, retrieve its persisted run result with `dispatcher_get_run`.
7. Confirm the task result matches the checkpointed sequence ID, task index, attempt, task identity hash, payload hash, idempotency key, repo, worker, and expected commit message.
8. Resume only from the next pending task when the previous task has `validation_passed` and the sequence is `checkpointed`, `paused`, or operator-resolved `blocked`.
9. Stop as `blocked` when state is `dispatching`, `running`, `validating`, unknown, corrupted, missing a referenced result, or inconsistent.

Recovery must never assume that an in-memory active task survived restart. It must also never dispatch a replacement for an ambiguous task without operator review, because duplicate task execution can create conflicting commits.

## Stale-State Recovery Decision Table

| Observed state on restart | Evidence | Decision | Next allowed action |
| --- | --- | --- | --- |
| `approved` | No task dispatched; checkpoint hash valid. | Safe pending state. | Operator may start first task. |
| `dispatching` | No durable `taskId`. | `blocked`. | Operator verifies whether dispatch reached Dispatcher before retry. |
| `dispatching` | Durable `taskId` exists. | Reclassify to `running` or completed based on exact result. | Retrieve by `taskId`; no duplicate dispatch. |
| `running` | Exact result success exists. | Move to `validating` after audit repair approval. | Run validation if operator approves. |
| `running` | Exact result failure exists. | `failed` or `failed_with_commit`. | Operator rollback, retry, or cancel. |
| `running` | No result and task age below timeout. | `blocked`. | Operator waits or investigates outside P4. |
| `running` | No result and task age exceeds timeout. | `timed_out`. | Operator reconciliation before retry. |
| `validating` | Validation evidence complete and passing. | `blocked` until checkpoint repair approved. | Reconstruct checkpoint from audit and evidence. |
| `validating` | Validation evidence missing or failed. | `failed`. | Operator retry or cancel. |
| `checkpointed` | Checkpoint and audit valid; result correlated. | Resumable. | Operator may continue. |
| `paused` | Checkpoint and audit valid. | Resumable. | Operator may resume or cancel. |
| `blocked` | Block reason resolved by operator. | Resumable only if safe boundary exists. | Resume, retry, or cancel. |
| Any | Checkpoint hash invalid. | `blocked`. | Operator investigation; no dispatch. |
| Any | Result mismatch. | `blocked`. | Operator investigation; no dispatch. |
| Any | Unsafe boundary detected. | `failed`. | Operator review; no dispatch. |

## Duration Limits and Timeout Mapping

Each sequence and each task must define duration limits before approval.

Required limits:

- per-task maximum dispatch acknowledgement duration
- per-task maximum execution duration
- per-task maximum validation duration
- total sequence maximum duration
- maximum recovery reconciliation duration

Timeout behavior:

- Mark the active task or sequence as `timed_out`.
- Persist a checkpoint and audit event when persistence is available.
- Do not start any later task.
- Report the timeout in the audit summary.
- Require operator review before retry, rollback, or cancellation.

Dispatcher-to-P4 timeout mapping:

| Dispatcher metadata | P4 task state | P4 sequence state | Notes |
| --- | --- | --- | --- |
| `executionStatus: "timeout"` | `timed_out` | `timed_out` | Direct execution timeout. |
| `status: "timeout"` | `timed_out` | `timed_out` | Legacy or top-level timeout signal. |
| `error.code: "TIMEOUT"` | `timed_out` | `timed_out` | Error metadata timeout. |
| `timedOut: true` | `timed_out` | `timed_out` | Boolean timeout evidence. |
| Missing result after task execution limit | `timed_out` | `timed_out` | Controller-derived timeout; exact task remains stale until reconciled. |
| Validation command timeout | `timed_out` | `timed_out` | Validation timeout, even if task execution succeeded. |
| `deliveryStatus: "timeout"` with successful execution | unchanged | unchanged | Delivery-only timeout does not fail task or sequence. |

Duration limits are safety controls, not scheduling controls. P4 does not authorize background scheduling.

## Canonical Hashing and Idempotency

Canonical JSON rules:

- Encode as UTF-8.
- Sort object keys lexicographically by Unicode code point.
- Preserve array order.
- Use JSON string escaping as defined by RFC 8259.
- Emit no insignificant whitespace.
- Represent numbers in their shortest JSON decimal representation; avoid NaN and Infinity.
- Omit fields with `null` only when the schema marks them optional and absent. Otherwise include explicit `null`.
- Hash bytes with SHA-256 and lowercase hexadecimal output.

Task identity hash included fields:

- `schemaVersion`
- `sequenceId`
- `taskIndex`
- `attempt`
- `workPackage`
- `title`
- `dependsOn`
- `repo`
- `worker`
- `scope`
- `blocked`
- `validation`
- `expectedOutput`
- `manualValidationAllowed`

Payload hash included fields:

- all task identity fields
- `commitMessage`
- exact `dispatcher_dispatch` payload fields
- per-task no-push directive
- duration limits
- idempotency key

Excluded from both hashes:

- `createdAt`
- `approvedAt`
- `startedAt`
- `finishedAt`
- `updatedAt`
- `taskId`
- `commitHash`
- validation command output
- audit event IDs
- operator notes
- redacted evidence excerpts

Hash timing:

- Compute `taskIdentityHash` before sequence approval.
- Compute `payloadHash` immediately before `dispatcher_dispatch` from the exact payload to be sent.
- Persist both hashes in the `task.dispatch_requested` audit event before dispatch.
- Verify both hashes against the correlated result before validation.

Idempotency key:

```text
<sequenceId>:<taskIndex>:<attempt>:<taskIdentityHash>:<payloadHash>
```

Duplicate detection rules:

- A task index and attempt can have at most one active Dispatcher `taskId`.
- A completed task index and attempt cannot be dispatched again.
- A retry must increment `attempt` and create a new idempotency key.
- A retry with unchanged payload keeps the same task identity hash but has a different idempotency key because `attempt` changes.
- A retry with changed payload has a new payload hash and must be operator-approved as a retry record.
- Duplicate detected before dispatch moves the sequence to `blocked`.
- Duplicate detected after restart moves the sequence to `blocked` and requires exact result reconciliation.

## Validation After Each Task

Each task must include its own validation commands or manual checks. Validation is part of the task plan, not a later best effort.

Validation rules:

- Run controller-owned validation after the task completes and before any later dispatch.
- Stop immediately on validation failure.
- Persist validation command, exit code, bounded redacted output summary, timestamp, duration, and result.
- Do not run the next task until validation passes and checkpoint persistence succeeds.
- Include validation evidence in the sequence audit report.

P4 design accepts that some validation may be manual for documentation or policy tasks. Manual validation must still produce explicit completion evidence under the manual evidence contract.

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
- unsafe validation command
- push failure
- operator cancellation

Stop behavior:

- Persist current state when possible.
- Write an audit event when possible.
- Do not dispatch any later task.
- Report the failed task index, task ID if assigned, failure reason, validation status, commit status, and recovery recommendation.

## Failure Taxonomy and Recovery Matrix

| Failure | Detection | Sequence state | Recovery |
| --- | --- | --- | --- |
| Task failure | Correlated run result has failed execution status. | `failed` or `failed_with_commit`. | Stop; operator decides retry, rollback, follow-up task, or cancel. |
| Validation failure | Controller validation command/manual check fails. | `failed` or `failed_with_commit`. | Stop; no push; quarantine commit if present. |
| Timeout | Dispatcher timeout metadata or controller duration limit. | `timed_out`. | Stop; reconcile exact result; operator decides retry or cancel. |
| Checkpoint failure | Atomic write, checksum, or readback failure. | `blocked`. | Stop; recover from audit if possible; no dispatch until repaired. |
| Stale active task | Restart finds `dispatching`, `running`, or `validating`. | `blocked` or `timed_out`. | Retrieve exact result when possible; never duplicate dispatch automatically. |
| Missing result | Checkpoint references task ID but `dispatcher_get_run` cannot retrieve it. | `blocked`. | Operator investigates run artifacts; no continuation. |
| Result mismatch | Result fields differ from checkpoint or hashes. | `blocked`. | Operator investigation; no continuation or retry until resolved. |
| Unsafe boundary | New MCP tool, arbitrary shell, public exposure, scope violation, or blocked item detected. | `failed`. | Stop; security review; no continuation. |
| Push failure | Operator-approved future push fails after validation. | `blocked`. | Preserve local validated state; operator retries push or cancels. |
| Delivery-only failure | Browser postback or delivery status fails while execution succeeds. | unchanged. | Record in audit; does not block validation by itself. |
| Redaction failure | Evidence contains unredactable secret material. | `failed`. | Stop; operator reviews local raw logs outside audit report. |
| Duplicate dispatch | Same idempotency key has active or completed task ID. | `blocked`. | Reconcile existing task; no duplicate dispatch. |
| Dirty repo after validation | Unexpected non-ignored changes remain. | `failed`. | Stop; operator decides cleanup or follow-up task. |

## Audit Reporting

Every P4 sequence must produce an audit report that can be reviewed without inspecting implementation logs.

Required report content:

- sequence ID
- schema version
- approval timestamp and operator identity marker
- ordered task list
- task safety fields
- dependencies
- per-task start and finish timestamps
- per-task duration
- Dispatcher task IDs
- task identity hash, payload hash, and idempotency key
- validation evidence
- commit hash per task when present
- quarantined commit hash when present
- result retrieval references
- stop reason or completion status
- duplicate-prevention decisions
- restart-recovery decisions
- security boundary checks
- redaction summary
- open implementation authorizations, if any

Audit reporting must not expose secrets, local tokens, raw environment values, or unnecessary stdout/stderr content.

### Audit Report Template

```markdown
# P4 Sequence Audit Report

Sequence ID: <sequence-id>
Schema Version: 1
Status: <completed|blocked|failed|failed_with_commit|timed_out|cancelled>
Approved By: <operator>
Approved At: <timestamp>
Started At: <timestamp>
Finished At: <timestamp>

## Scope

- Repo: <repo>
- MCP tools: dispatcher_status, dispatcher_dispatch, dispatcher_latest_result, dispatcher_get_run
- Runtime implementation authorized: no
- Push policy: per-task no-push until validation passes

## Tasks

| Index | Attempt | Work Package | Dispatcher Task ID | Result | Validation | Commit | Notes |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 0 | 0 | <work-package> | <task-id> | <success|failure|timeout> | <pass|fail|manual> | <sha-or-none> | <redacted-summary> |

## Validation Evidence

| Task | Command or Manual Check | Result | Evidence |
| --- | --- | --- | --- |
| 0 | npm test | PASS | exit 0, redacted bounded output |

## Recovery Decisions

| Event | Decision | Operator | Timestamp |
| --- | --- | --- | --- |
| <event> | <decision> | <operator> | <timestamp> |

## Security and Redaction

- Boundary checks: <pass|fail>
- Redaction status: <pass|fail>
- Omitted raw logs: <artifact references>

## Final Decision

<completed, blocked with next action, failed with recovery recommendation, or cancelled>
```

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
    "dispatchAckSeconds": 30,
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
  "attempt": 0,
  "workPackage": "P4.0",
  "title": "Design finalization and safety review",
  "dependsOn": [],
  "repo": "self",
  "worker": "codex",
  "commitMessage": "docs: example",
  "pushPolicy": "no-push-until-validation-passes",
  "scope": ["docs", "source", "README.md"],
  "blocked": ["No runtime code changes", "No new MCP tools"],
  "validation": ["npm test", "npm run build", "git diff --check"],
  "manualValidationAllowed": false,
  "expectedOutput": ["Files changed", "Validation results", "Commit hash"],
  "taskIdentityHash": "<sha256>",
  "payloadHash": "<sha256>",
  "idempotencyKey": "<sequenceId>:0:0:<taskIdentityHash>:<payloadHash>",
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
  "attempt": 0,
  "lastValidationState": "validation_passed",
  "dispatcherTaskId": "20260607-000000-abcdef12",
  "taskIdentityHash": "<sha256>",
  "payloadHash": "<sha256>",
  "idempotencyKey": "<sequenceId>:0:0:<taskIdentityHash>:<payloadHash>",
  "commitHash": "<git-sha>",
  "quarantinedCommitHash": null,
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
  "attempt": 0,
  "workPackage": "P4.0",
  "dispatcherTaskId": "20260607-000000-abcdef12",
  "details": {
    "validation": "npm test",
    "exitCode": 0,
    "redaction": "pass"
  }
}
```

## Concrete Sequence Examples

### Valid Documentation-Only Sequence

```json
{
  "sequenceId": "p4-20260607-220000-docs-hardening",
  "schemaVersion": 1,
  "status": "approved",
  "approvedBy": "operator",
  "durationLimits": {
    "dispatchAckSeconds": 30,
    "taskExecutionMinutes": 30,
    "taskValidationMinutes": 10,
    "sequenceMinutes": 60,
    "recoveryMinutes": 10
  },
  "tasks": [
    {
      "index": 0,
      "attempt": 0,
      "workPackage": "P4.0",
      "title": "Harden design contract",
      "dependsOn": [],
      "repo": "self",
      "worker": "codex",
      "commitMessage": "docs: harden P4 sequencing contract",
      "pushPolicy": "no-push-until-validation-passes",
      "scope": [
        "docs/phase-4-controlled-task-sequencing-design.md",
        "source/phase-4-controlled-task-sequencing-design.md",
        ".gitignore",
        "README.md"
      ],
      "blocked": [
        "Documentation only",
        "No runtime code changes",
        "No new MCP tools",
        "No bridge endpoints"
      ],
      "validation": [
        "npm test",
        "npm run build",
        "git diff --check"
      ],
      "manualValidationAllowed": false,
      "expectedOutput": [
        "Files changed",
        "Resolved blocker checklist",
        "Test and build results"
      ]
    }
  ]
}
```

Why valid:

- One approved task with explicit scope.
- No runtime code scope.
- Push policy is no-push until validation passes.
- Validation commands are allowlisted.
- No new MCP tools are requested.

### Valid Retry Record

```json
{
  "sequenceId": "p4-20260607-220000-docs-hardening",
  "taskIndex": 0,
  "originalAttempt": 0,
  "retryAttempt": 1,
  "reason": "validation_failed",
  "operatorDecision": "keep quarantined commit and create corrective follow-up",
  "commitDecision": {
    "quarantinedCommitHash": "abc123",
    "action": "keep"
  },
  "approvedAt": "2026-06-07T00:00:00.000Z",
  "approvedBy": "operator"
}
```

Why valid:

- Retry is explicit and operator-approved.
- Attempt identity changes.
- Original failed attempt remains preserved.

### Invalid Sequence: Runtime Expansion

```json
{
  "sequenceId": "p4-20260607-220500-runtime",
  "status": "approved",
  "tasks": [
    {
      "index": 0,
      "repo": "self",
      "worker": "codex",
      "scope": ["mcp/server/index.js"],
      "blocked": [],
      "validation": ["npm test && npm run build"]
    }
  ]
}
```

Why invalid:

- Runtime code is in scope.
- Validation command uses shell chaining and is not allowlisted.
- Required blocked safety fields are missing.

### Invalid Sequence: Ambiguous Recovery

```json
{
  "sequenceId": "p4-20260607-221000-ambiguous",
  "checkpoint": {
    "sequenceState": "running",
    "dispatcherTaskId": null,
    "taskIndex": 1
  },
  "recoveryAction": "redispatch"
}
```

Why invalid:

- Running state has no exact `taskId`.
- Redispatch would risk duplicate work.
- Recovery must block for operator review.

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

- schema includes ordered tasks, dependencies, safety fields, duration limits, validation, expected output, correlation fields, hashing fields, and push policy
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
- modifying existing run result retrieval tools

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
- audit report includes task IDs, validation evidence, commit hashes, hashes, idempotency keys, and recovery decisions
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
- no open readiness decisions remain
- explicit separate approval exists before implementation begins

Completion evidence:

- signed-off acceptance checklist
- no-open-readiness-decision checklist
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
- The design covers exact task/run correlation by task ID.
- The design covers commit and push boundaries.
- The design covers persisted checkpoints.
- The design covers restart recovery.
- The design covers pause, cancel, resume, and retry.
- The design covers duration limits and timeout mapping.
- The design covers duplicate prevention.
- The design covers canonical hashing and idempotency.
- The design covers audit reporting.
- The design covers secret redaction.
- The design covers result retrieval.
- The design covers security boundaries.
- The design includes sequence and task state transition tables.
- The design includes stale-state recovery decisions.
- The design includes schemas.
- The design includes concrete valid and invalid examples.
- The design includes a failure taxonomy and recovery matrix.
- The design includes a test plan.
- The design includes rollout and rollback.
- The design includes separate future workstreams for live console output and safe restart.
- The design preserves exactly four approved MCP tools.
- The design states that P4 runtime implementation is not authorized by this task.
- Runtime sequence artifacts are designed for an ignored path that does not dirty the repo.
- README contains only a short link to the design if README is changed.

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

## Implementation Authorization

P4 runtime implementation remains explicitly unauthorized. This contract may be used to judge a future implementation proposal, but it does not itself permit runtime code, tests, scheduler behavior, executor behavior, new bridge endpoints, new MCP tools, service restart, WebSocket, SSE, public exposure changes, or arbitrary shell APIs.
