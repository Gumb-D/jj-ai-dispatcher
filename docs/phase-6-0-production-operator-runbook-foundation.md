# Phase 6.0 Production Operator Runbook Foundation

## Purpose

Phase 6 starts after Phase 5 validation and tagging.

Completed baseline:

- Phase 5 MCP / Tool Integration Validation completed.
- Release tag `v0.5-phase5-mcp-tool-validation` created and pushed.
- Remote `origin/main` validated at Phase 5 completion.

Phase 6 turns the proven ChatGPT / MCP / Dispatcher / Codex workflow into a safe daily operator practice.

Phase 6.0 is documentation-first. It creates the foundation for repeatable production operator use without adding automation, runtime behavior, MCP tools, schedulers, queues, autonomous loops, or remote execution.

## Current Production Boundary

Approved production flow:

```text
ChatGPT Brain
  |
  v
MCP client
  |
  v
Dispatcher MCP stdio server
  |
  v
local bridge
  |
  v
Dispatcher
  |
  v
Codex
  |
  v
Git commit / optional push
  |
  v
latest result
  |
  v
read-only review helper
  |
  v
manual classification
  |
  v
explicit next decision
```

The current approved boundary remains:

- localhost only
- token protected bridge
- MCP stdio only
- exactly four approved MCP tools
- explicit dispatch only
- review helper read-only
- review gate preserved
- Codex may commit and push only after validations pass under the approved Dispatcher workflow
- Cline must not auto commit or auto push

Approved MCP tools:

- `dispatcher_status`
- `dispatcher_dispatch`
- `dispatcher_latest_result`
- `dispatcher_get_run`

## Roles and Authority

### ChatGPT

ChatGPT is the task brain.

Responsibilities:

- define task objective
- define scope and blocked areas
- shape dispatch payloads
- support review decisions
- recommend accepted, rejected, or needs_followup classification

ChatGPT does not bypass the operator, expand the tool boundary, or trigger autonomous follow-up dispatch.

### Dispatcher

Dispatcher is the execution controller.

Responsibilities:

- own the local bridge/API boundary
- receive explicit dispatch requests
- route approved work to the configured worker
- own Git operations performed through the approved workflow
- preserve run artifacts and latest result state

Dispatcher does not expose a public listener, remote bridge, tunnel, queue, scheduler, arbitrary shell, arbitrary file access, or direct Git MCP tool.

### Codex

Codex is the trusted coding worker.

Responsibilities:

- make scoped code or documentation changes
- run requested validations
- commit after validations pass when authorized by the Dispatcher workflow
- push only when policy allows and the operator has authorized it

Codex may commit and push after validations pass under the approved Dispatcher workflow.

### Cline

Cline is not trusted for automatic commit or push.

Requirements:

- Cline changes require review.
- Cline must not auto commit.
- Cline must not auto push.
- Cline output must pass the same review gate before acceptance.

### Operator

The operator is the final acceptance authority.

Responsibilities:

- approve dispatch intent
- inspect results
- classify each run as accepted, rejected, or needs_followup
- decide whether to push
- stop the workflow if a safety boundary is crossed

## Daily Operating Procedure

### A. Pre-start Check

Run from the repository root:

```powershell
git status --short
npm run build
npm run mcp:smoke
.\scripts\bridge-status.ps1
```

Confirm:

- repository state is clean, or existing changes are understood
- build passes
- MCP smoke validates the approved tool surface
- bridge is healthy
- bridge remains localhost-only and token protected
- no task is already running

### B. Before Dispatch

Before every dispatch, confirm:

- task objective is specific
- scope is narrow
- blocked areas are explicit
- commit message is approved
- validation expectations are listed
- expected output is clear
- task does not request broad architecture or security changes
- task does not weaken the current production boundary

### C. Dispatch

Dispatch rules:

- one explicit dispatch only
- no chaining
- no background follow-up
- no automatic retry loop
- no automatic next task
- no auto-review
- no auto-push from the MCP client

Each follow-up requires a separate review decision and a new explicit operator instruction.

### D. Review

After the run completes, inspect the latest result:

```powershell
.\scripts\bridge-latest.ps1
.\scripts\review-latest-run.ps1
npm run review:latest
```

Review:

- task result
- changed files
- summary
- validation output
- commit metadata
- pushed state
- working tree state
- safety boundary

The review helper is read-only and advisory. It does not accept, reject, follow up, dispatch, push, or modify files.

### E. Accept / Reject / Needs Followup

Each run must receive one manual classification:

- `accepted`
- `rejected`
- `needs_followup`

Meaning:

- `accepted`: result satisfies the task, validations passed, safety boundary preserved
- `rejected`: result should not be used without correction or rollback planning
- `needs_followup`: result is useful but requires a new explicit task

A needs_followup decision does not authorize automatic dispatch.

### F. Push Policy

Codex may push only after:

- validations pass
- repository is clean after commit
- scope is satisfied
- review gate is preserved
- operator authorization exists

The operator may still override push behavior by explicit instruction.

## Safe Task Pattern

Recommended task envelope:

```json
{
  "repo": "self",
  "worker": "codex",
  "task": "...",
  "commitMessage": "...",
  "scope": [],
  "blocked": [],
  "validation": [],
  "expectedOutput": []
}
```

Guidance:

- `task` should describe one bounded outcome.
- `commitMessage` should be ready to use if validations pass.
- `scope` should name the files, directories, or behavior areas allowed to change.
- `blocked` should name files, directories, behavior, or security boundaries that must not change.
- `validation` should list commands or checks expected before completion.
- `expectedOutput` should describe the final artifact, summary, or result contract.

## Unsafe Task Examples

Do not dispatch these casually:

- broad refactor without scope
- security boundary change
- tunnel or public listener
- autonomous loop
- scheduler or queue
- arbitrary shell exposure
- arbitrary file read/write exposure
- direct Git tool exposure
- production credential handling
- remote execution
- bridge exposure outside localhost
- task that asks Cline to auto commit or auto push
- task that asks the MCP client to chain follow-up dispatches

These require separate design, review, and explicit authorization before implementation.

## Incident / Stop Rules

Stop immediately if:

- unexpected files changed
- validation failed
- bridge token was printed
- forbidden tool appeared
- bridge was exposed externally
- repository is dirty after supposed completion
- dispatch loop was detected
- task ran outside approved scope
- review helper wrote state or triggered follow-up work
- MCP tool count changed from the approved four tools

After stopping:

- do not dispatch follow-up work automatically
- preserve the current state for inspection
- inspect changed files and latest result
- classify the run manually before deciding next action

## Recovery Commands

Safe read-only and diagnostic commands:

```powershell
git status --short
git log --oneline -10
npm run build
npm run mcp:smoke
npm run review:latest
.\scripts\bridge-status.ps1
.\scripts\bridge-latest.ps1
```

Avoid destructive commands during initial recovery. Do not reset, delete, force-push, rewrite history, or remove run artifacts unless the operator explicitly approves a recovery plan.

## Phase 6 Roadmap

Recommended next sub-phases:

- Phase 6.1: operator runbook checklist templates
- Phase 6.2: troubleshooting guide
- Phase 6.3: approved task patterns catalog
- Phase 6.4: production readiness review
- Phase 6.5: optional client-specific runbook appendix

## Non-Goals

Phase 6.0 does not authorize:

- new automation
- remote execution
- public endpoint
- background agent
- queue or scheduler
- autonomous coding loop
- new MCP tools
- MCP schema changes
- bridge behavior changes
- Dispatcher runtime changes
- auto-dispatch
- auto-review
- arbitrary shell
- arbitrary file read/write
- direct Git MCP tools
- weakened security boundary

