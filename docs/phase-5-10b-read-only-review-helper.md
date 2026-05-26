# Phase 5.10B Read-Only Review Helper

## Purpose

Phase 5.10B adds a non-executing helper that reads the latest Dispatcher run result and prints a manual review checklist.

The helper is for review preparation only. It does not accept, reject, follow up, dispatch, push, queue, schedule, or modify Dispatcher runtime behavior.

## Command Usage

Run from the repository root:

```powershell
.\scripts\review-latest-run.ps1
```

Equivalent npm command:

```powershell
npm run review:latest
```

## Expected Output

The helper prints a concise checklist including:

- task id
- status
- repo
- worker
- commit
- commit message
- pushed state
- working tree clean state from the result contract
- summary
- changed files
- validation hints
- manual review checklist sections
- advisory suggested classification

Example classification line:

```text
Suggested classification: accepted
Advisory only: this helper does not persist classification or trigger follow-up dispatch.
```

## Read-Only Boundary

The helper is read-only during normal execution.

It may read:

- local bridge configuration needed to call the local bridge
- latest result from the existing local bridge
- `dispatcher/runs/<taskId>/result.json`
- `dispatcher/runs/<taskId>/summary.md`

It does not write:

- acceptance files
- rejection files
- follow-up files
- queue files
- Dispatcher state
- Git commits
- Git tags
- runtime config

It does not call `dispatcher_dispatch`.

## Data Source Behavior

Source order:

1. Existing Local Dispatcher Bridge latest result endpoint.
2. Latest local `dispatcher/runs/<taskId>/result.json` artifact if the bridge is unavailable.

The bridge call uses the existing localhost bridge and token header when required. The token is not printed.

Local artifact fallback is limited to Dispatcher run directories whose names match the existing task id shape.

## Failure Behavior

The helper exits with code `0` when it can read a latest result and print a checklist.

The helper exits non-zero when:

- no bridge result can be read and no local run artifact exists
- latest result data is malformed
- the task id shape is invalid
- no readable `result.json` artifact can be found during fallback

Failure output is concise and actionable:

```text
FAIL review latest run - no dispatcher run artifacts found
```

## What It Does Not Do

The helper does not:

- add MCP tools
- change MCP tool registration
- dispatch work
- classify and persist state
- approve a run
- reject a run
- request follow-up
- push commits
- commit files
- schedule work
- queue work
- start autonomous loops
- expose tokens or local private config
- add tunnel, remote bridge, public listener, arbitrary shell, arbitrary file read/write MCP tools, direct Git MCP tools, or editor control

## Relationship to Phase 5.8 and 5.9

Phase 5.8 defines the review gate and states that each run must end in one explicit review decision:

- `accepted`
- `rejected`
- `needs_followup`

Phase 5.9 defines the structured review classification model.

Phase 5.10B helps the operator consume the latest run result and prepare that manual decision. The suggested classification is advisory only and has no side effects.

## Recommendation for Phase 5.11

Phase 5.11 should remain review-focused and non-autonomous.

Recommended direction:

- Add client-specific notes for using the review helper after MCP dispatch.
- Keep review output read-only.
- Do not write acceptance state until a separate storage policy is explicitly designed.
- Do not add auto-dispatch, queues, schedulers, remote execution, or new MCP tools.
