# Phase 6.5 Client-Specific Runbook Appendix

## Purpose

Phase 6.5 adapts the Phase 6 production operator runbook for client-side MCP usage.

This appendix explains how an MCP client may safely participate in the approved Dispatcher / Codex workflow while preserving the operator-controlled boundary.

This appendix does not authorize:

- new automation
- runtime behavior changes
- MCP or bridge boundary expansion
- new MCP tools
- auto-dispatch
- auto-review
- queueing
- schedulers
- autonomous loops
- remote bridges
- tunnels
- public listeners
- arbitrary shell, file, or Git capabilities

The operator remains the final acceptance authority.

## Approved Client Usage Context

An MCP client may be used only to access the approved Dispatcher MCP tool surface:

- `dispatcher_status`
- `dispatcher_dispatch`
- `dispatcher_latest_result`
- `dispatcher_get_run`

The client must not expose new capabilities.

The client must not register, request, simulate, or route around the approved tool surface with arbitrary shell, arbitrary file access, direct Git operations, editor control, tunnel management, credential access, or remote execution.

Approved client usage remains:

```text
MCP client
  |
  v
approved Dispatcher MCP tool
  |
  v
local bridge
  |
  v
Dispatcher
  |
  v
Codex under approved workflow
  |
  v
latest result
  |
  v
operator review
  |
  v
manual classification
```

## Client Pre-Flight Checklist

Before using an MCP client for Dispatcher work, confirm:

- [ ] repository is clean
- [ ] bridge is healthy
- [ ] MCP smoke passes
- [ ] review helper works
- [ ] token is configured but not printed
- [ ] no public listener is active
- [ ] no tunnel is active
- [ ] exactly four approved tools are registered
- [ ] prior run has been reviewed or understood
- [ ] operator has explicit intent for the next dispatch

Commands:

```powershell
git status --short
npm run build
npm run mcp:smoke
npm run review:latest
.\scripts\bridge-status.ps1
```

Expected MCP tool list:

- `dispatcher_status`
- `dispatcher_dispatch`
- `dispatcher_latest_result`
- `dispatcher_get_run`

If the tool list differs from the approved four tools, stop and do not dispatch.

## Client Dispatch Procedure

Client dispatch rules:

- one explicit dispatch only
- task must include objective
- scope must be defined
- blocked areas must be defined
- validation must be defined
- commit message must be clear
- no chained dispatch
- no automatic follow-up
- no background retry
- no automatic acceptance

Recommended dispatch envelope:

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

The MCP client may help prepare or send a dispatch only after the operator confirms the objective, scope, blocked areas, validation, expected output, and commit message.

## Client Review Procedure

After dispatch, the operator must run:

```powershell
.\scripts\bridge-latest.ps1
.\scripts\review-latest-run.ps1
npm run review:latest
```

Then classify manually:

- `accepted`
- `rejected`
- `needs_followup`

Review must include:

- latest result
- summary
- changed files
- validation output
- commit metadata
- pushed state
- working tree state
- safety boundary

A `needs_followup` decision does not authorize automatic dispatch. Any follow-up requires a new explicit operator instruction.

## Client Safety Rules

Client safety rules:

- client must not auto-call `dispatcher_dispatch`
- client must not trigger dispatch from prior output
- client must not retry failed dispatch repeatedly
- client must not store or print token
- client must not expose local bridge externally
- client must not push directly
- client must not bypass review helper or checklists
- client must not treat successful completion as automatic acceptance
- client must not add or request new MCP tools
- client must not perform remote execution

If a client violates any safety rule, stop client usage and switch to the Phase 6.2 troubleshooting guide and Phase 6.1 incident stop checklist.

## Example Client Session

Example safe session:

1. Run pre-flight checks:

   ```powershell
   git status --short
   npm run build
   npm run mcp:smoke
   npm run review:latest
   .\scripts\bridge-status.ps1
   ```

2. Confirm approved tools:

   ```text
   dispatcher_status
   dispatcher_dispatch
   dispatcher_latest_result
   dispatcher_get_run
   ```

3. Submit one docs-only dispatch:

   ```json
   {
     "repo": "self",
     "worker": "codex",
     "task": "Update one operator guide section with a short clarification. Keep the change documentation-only.",
     "commitMessage": "docs: clarify operator guide wording",
     "scope": [
       "docs/local-bridge-operator-guide.md"
     ],
     "blocked": [
       "mcp/",
       "scripts/",
       "dispatcher runtime",
       "bridge behavior",
       "new MCP tools",
       "automation"
     ],
     "validation": [
       "npm run build",
       "npm run mcp:smoke",
       "git diff --check",
       "git status --short"
     ],
     "expectedOutput": [
       "one documentation update",
       "validation summary",
       "commit hash if committed",
       "final git status"
     ]
   }
   ```

4. Wait for completion. Do not start another dispatch.

5. Review latest result:

   ```powershell
   .\scripts\bridge-latest.ps1
   .\scripts\review-latest-run.ps1
   npm run review:latest
   ```

6. Classify:

   ```text
   accepted
   ```

7. Stop. Any next task requires a new explicit operator decision.

## Unsafe Client Scenarios

Unsafe client scenarios:

- MCP client auto-dispatches the next task.
- Client tries to expose bridge through a tunnel.
- Client registers extra tools.
- Client bypasses review.
- Client asks for remote execution.
- Client performs direct push.
- Client stores token in logs.
- Client retries failed dispatches repeatedly.
- Client treats latest result output as permission for follow-up work.
- Client requests arbitrary shell, file, or Git capability.

If any unsafe scenario appears, stop immediately. Do not dispatch again and do not push until the operator reviews the incident.

## Relationship to Phase 6 Package

This appendix builds on the Phase 6 operator package:

- Phase 6.0 runbook defines the production operator workflow and safety boundary.
- Phase 6.1 checklists provide pre-start, dispatch, review, push, and incident stop procedures.
- Phase 6.2 troubleshooting provides safe diagnostics and stop rules.
- Phase 6.3 task patterns define safe dispatch envelopes and blocked patterns.
- Phase 6.4 readiness review concludes the workflow is ready for controlled daily use only.

This appendix adapts that package for MCP client usage without changing the system boundary.

## Recommendation for Phase 6.6

Recommended next phase:

```text
Phase 6.6 - Production Operator Quickstart
```

Purpose:

Create a concise one-page quickstart for daily use, focused on the minimum safe sequence:

- pre-flight
- one explicit dispatch
- review
- classify
- push only when approved
- stop on incident
