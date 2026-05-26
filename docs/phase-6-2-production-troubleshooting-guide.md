# Phase 6.2 Production Troubleshooting Guide

## Purpose

Phase 6.2 provides practical troubleshooting guidance for daily operator use of the current Dispatcher / MCP / Codex workflow.

This phase is documentation-only. It does not add runtime logic, MCP tools, MCP schema changes, bridge behavior, Dispatcher behavior, queues, schedulers, autonomous loops, remote execution, tunnels, public listeners, arbitrary shell access, arbitrary file access, or direct Git tools.

The approved boundary remains:

- localhost only
- token protected bridge
- MCP stdio only
- exactly four approved tools
- explicit dispatch only
- review helper read-only
- review gate preserved
- Codex trusted under the approved workflow
- Cline no auto commit or auto push

Approved MCP tools:

- `dispatcher_status`
- `dispatcher_dispatch`
- `dispatcher_latest_result`
- `dispatcher_get_run`

## Troubleshooting Decision Tree

Use this flow when any problem is detected:

```text
problem detected
  |
  v
stop dispatch
  |
  v
identify category
  |
  v
run safe diagnostics
  |
  v
classify
  |
  v
manual recovery or explicit follow-up
```

Do not retry blindly. Do not chain follow-up dispatch. Do not push until the problem is understood and the operator has made an explicit decision.

## 1. Build Failure

### Symptoms

- `npm run build` fails.

### Diagnostics

Run:

```powershell
npm run build
```

Then:

- inspect error output
- check recent changes
- identify whether the failure is from syntax checking, dependency state, or a changed script target

### Safe Actions

- stop dispatch
- classify as `needs_followup` or `rejected`
- do not push
- prepare a narrow explicit follow-up only after review

## 2. MCP Smoke Failure

### Symptoms

- `npm run mcp:smoke` fails
- tool list is not exactly four approved tools
- forbidden tool appears

### Diagnostics

Run:

```powershell
npm run mcp:smoke
```

Then:

- inspect tool registration output
- confirm the approved tools are exactly:
  - `dispatcher_status`
  - `dispatcher_dispatch`
  - `dispatcher_latest_result`
  - `dispatcher_get_run`
- inspect whether any forbidden tool or capability appeared

### Safe Actions

- stop immediately if a forbidden tool appears
- do not dispatch
- do not push
- classify as `rejected_security_boundary` if the tool boundary changed unexpectedly
- do not add new MCP tools to fix a smoke failure

## 3. Bridge Health Issue

### Symptoms

- `.\scripts\bridge-status.ps1` fails
- bridge is not reachable
- bridge is not idle
- port is already occupied

### Diagnostics

Run:

```powershell
.\scripts\bridge-status.ps1
```

Then:

- check whether an existing bridge is already running
- confirm the bridge is localhost-only
- confirm the bridge is token protected
- check whether `taskState` is `idle` or `running`

### Safe Actions

- do not start multiple conflicting bridges casually
- if bridge is busy, wait or review latest run
- if bridge is exposed externally, stop immediately
- do not dispatch until bridge state is understood

## 4. Latest Result / Review Helper Problem

### Symptoms

- `npm run review:latest` fails
- `.\scripts\review-latest-run.ps1` fails
- latest result is missing
- result is malformed

### Diagnostics

Run:

```powershell
.\scripts\bridge-latest.ps1
npm run review:latest
```

If appropriate, inspect Dispatcher run artifacts:

```text
dispatcher/runs
```

Keep inspection manual and limited to understanding the latest run state.

### Safe Actions

- do not dispatch again until latest state is understood
- classify as `needs_manual_check`
- do not rely on advisory classification if result data is missing or malformed
- preserve artifacts for operator inspection

## 5. Dirty Repo State

### Symptoms

- `git status --short` is not clean after supposed completion
- unexpected files changed

### Diagnostics

Run:

```powershell
git status --short
git diff --stat
git diff --name-only
```

Then:

- identify every changed file
- compare changed files against approved scope
- check whether generated or temporary artifacts were left behind

### Safe Actions

- do not push
- review changed files
- classify as `rejected` or `needs_followup`
- do not delete files blindly
- prepare explicit recovery or cleanup only after operator review

## 6. Safety Boundary Incident

### Symptoms

- token printed
- forbidden tool exposed
- tunnel or public listener detected
- arbitrary shell, file, or Git tool appears
- dispatch loop detected

### Safe Actions

- stop all dispatch activity
- do not push
- document incident
- classify as `rejected_security_boundary`
- preserve current state for inspection
- do not expose the bridge externally
- do not disable token checks
- do not add new tools, loops, queues, schedulers, tunnels, or listeners as a recovery shortcut

## 7. Dispatch Failure

### Symptoms

- `dispatcher_dispatch` rejected
- bridge returns error
- task stuck running
- run result failed

### Diagnostics

Run:

```powershell
.\scripts\bridge-status.ps1
.\scripts\bridge-latest.ps1
npm run review:latest
```

Then:

- inspect latest result status
- check whether a task is still running
- review any error message from the bridge or Dispatcher
- confirm no automatic retry loop has started

### Safe Actions

- do not retry blindly
- review result
- classify before any next action
- prepare explicit follow-up only after classification
- do not chain dispatches from the failed run

## 8. Push Failure

### Symptoms

- `git push` fails
- remote rejected the push
- branch is not up to date

### Diagnostics

Run:

```powershell
git status --short
git log --oneline -10
git remote -v
```

Then:

- inspect the local commit position
- confirm the intended remote
- review whether local state remains clean

### Safe Actions

- do not force push
- stop and review
- classify as `needs_manual_check`
- do not rewrite history without explicit operator recovery approval
- do not push again until the operator decides the next step

## 9. Cline Boundary Violation

### Symptoms

- Cline attempts commit or push
- Cline modifies files without review
- Cline attempts autonomous execution

### Safe Actions

- stop Cline flow
- inspect Git status
- no push until operator review
- review every changed file
- classify as `rejected` or `needs_followup`
- require explicit operator approval before any continued Cline-assisted work

Suggested diagnostic:

```powershell
git status --short
```

## Safe Diagnostic Command List

Use only safe read-only or validation commands during initial troubleshooting:

```powershell
git status --short
git diff --stat
git diff --name-only
git log --oneline -10
npm run build
npm run mcp:smoke
npm run review:latest
.\scripts\bridge-status.ps1
.\scripts\bridge-latest.ps1
```

## Forbidden Recovery Actions

Do not use these as troubleshooting shortcuts:

- force push
- deleting files blindly
- exposing bridge externally
- disabling token checks
- adding new MCP tools to fix smoke failure
- retrying dispatch repeatedly
- starting autonomous recovery loop
- adding a queue or scheduler
- adding a tunnel or public listener
- adding arbitrary shell, file, or Git tool access

## Relationship to Phase 6.1

This guide complements the Phase 6.1 checklist pack:

- [Pre-start Checklist](templates/pre-start-checklist.md)
- [Dispatch Approval Checklist](templates/dispatch-approval-checklist.md)
- [Review Classification Checklist](templates/review-classification-checklist.md)
- [Push Approval Checklist](templates/push-approval-checklist.md)
- [Incident Stop Checklist](templates/incident-stop-checklist.md)

Use the checklists during normal operation. Use this troubleshooting guide when a checklist item fails, a validation command fails, or a safety concern appears.

## Recommendation for Phase 6.3

Recommended next phase:

```text
Phase 6.3 - Approved Task Patterns Catalog
```

Phase 6.3 should document safe reusable task patterns, including docs-only changes, narrow test updates, bounded bug fixes, validation-only tasks, and explicitly blocked unsafe patterns.
