# Phase 5.11 Client MCP Dispatch Review Usage Notes

## Purpose

Phase 5.11 documents the practical operator workflow for the current MCP dispatch and review path after Phase 5.10B.

Required operating flow:

```text
explicit dispatch
  |
  v
wait for result
  |
  v
review helper
  |
  v
manual classification
  |
  v
explicit next decision
```

This is documentation only. It does not add MCP tools, change Dispatcher behavior, or authorize autonomous execution.

## Current Approved Client Flow

Approved client flow:

```text
MCP client
  |
  v
dispatcher_dispatch
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
Git commit
  |
  v
latest result
  |
  v
review helper
  |
  v
manual classification
  |
  v
optional explicit next dispatch
```

The optional next dispatch is allowed only after review and only when the operator gives a new explicit instruction.

## Required Pre-Flight Checks

Run these checks before using an MCP client for dispatch:

```powershell
git status --short
.\scripts\bridge-status.ps1
npm run mcp:smoke
```

Confirm:

- Repository is clean, or any existing changes are understood.
- Bridge is healthy.
- Bridge is localhost-only.
- Approved MCP tool list is unchanged.
- Bridge token is configured but never printed.
- No public Dispatcher listener exists.
- No tunnel, reverse proxy, or remote bridge is active.
- No task is already running.

If `taskState` is `running`, wait for the current run to complete and review it before dispatching anything else.

## Dispatch Usage Rules

Rules for `dispatcher_dispatch`:

- Use one dispatch at a time.
- Use an explicit task only.
- Include narrow `scope`.
- Include concrete `blocked` areas.
- Use a clear commit message.
- Include expected validation.
- Include expected output.
- Do not chain dispatches.
- Do not start unattended follow-up work.
- Do not request broad architecture changes without separate approval.
- Do not use dispatch to bypass manual review.

Every dispatch payload should be understandable enough that an operator can review it before approving the client call.

## Post-Dispatch Review

After dispatch completes, use the latest result and read-only review helper:

```powershell
.\scripts\bridge-latest.ps1
.\scripts\review-latest-run.ps1
npm run review:latest
```

Manual decision states:

- `accepted`
- `rejected`
- `needs_followup`

The review helper prints an advisory checklist and suggested classification only. It does not write acceptance state, dispatch follow-up work, push commits, or modify files.

Review must inspect:

- result contract
- summary
- changed files
- validation output
- commit metadata
- Git status
- safety boundary

## Client Safety Notes

Current approved MCP tools:

- `dispatcher_status`
- `dispatcher_dispatch`
- `dispatcher_latest_result`
- `dispatcher_get_run`

Client safety rules:

- Do not expose the bridge outside localhost.
- Do not print, store, paste, or log the bridge token.
- Do not automatically call `dispatcher_dispatch` from a prior result.
- Do not dispatch unless the operator has explicit intent.
- Do not treat a successful run or commit as automatic acceptance.
- Do not push from the MCP client unless a separate explicit reviewed workflow allows it.

## Safety Boundary

Forbidden capabilities remain forbidden:

- `arbitrary_shell`
- `arbitrary_file_read`
- `arbitrary_file_write`
- `delete`
- `push`
- `tunnel_enable`
- `remote_exec`
- `vscode_ui_control`
- `credential_read`
- `config_write`

The system remains:

- localhost only
- token protected bridge
- MCP stdio only
- four approved MCP tools only
- explicit dispatch only
- read-only review helper
- review gate preserved

## Example Operator Sequence

Example sequence:

```powershell
git status --short
.\scripts\bridge-status.ps1
npm run mcp:smoke
```

Then, in the MCP client, explicitly approve one `dispatcher_dispatch` payload with:

- `repo: self`
- `worker: codex`
- narrow task
- narrow scope
- blocked areas
- validation
- expected output

Wait for completion:

```powershell
.\scripts\bridge-status.ps1
```

When idle, review:

```powershell
.\scripts\bridge-latest.ps1
.\scripts\review-latest-run.ps1
```

Classify manually:

```text
accepted | rejected | needs_followup
```

Then stop, or provide a new explicit next prompt. A prior result must not trigger the next dispatch automatically.

## Non-Authorization

Phase 5.11 does not authorize:

- autonomous loops
- background workers
- recursive dispatch
- remote execution
- auto-push by MCP client
- unattended production operation
- scheduler behavior
- queueing
- auto-review
- automatic acceptance
- automatic follow-up dispatch
- new MCP tools
- bridge exposure outside localhost

## Recommendation for Phase 5.12

Recommended next step:

```text
Phase 5.12 - Phase 5 Stabilization Checklist + Release Tag Candidate
```

Phase 5.12 should verify that the Phase 5 MCP boundary, dispatch smoke path, review gate, structured review model, manual templates, and read-only review helper are stable enough to mark as a release candidate.

It should remain validation and documentation focused unless a separate explicit task approves implementation.
