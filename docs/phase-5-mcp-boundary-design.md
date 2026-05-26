# Phase 5.1 MCP Boundary Design

## Purpose

Define what a future MCP layer may and may not expose when connecting ChatGPT to JJ AI Dispatcher. The boundary must let ChatGPT communicate with Dispatcher as a controlled tool layer without bypassing Dispatcher, Git, local-only execution, or human review.

This is a design document only. It does not implement an MCP server.

## Source Basis

This design expands the Phase 5.0 feasibility study:

- `docs/phase-5-tool-integration-feasibility.md`

Phase 5.1 expands the preferred path:

```text
ChatGPT -> MCP/custom tool -> Dispatcher -> Codex -> Git -> Result
```

## Current Baseline

- Branch baseline: `main @ ba74aab`
- Phase 5 tag: `v0.5-phase5-research-start`
- Local HTTP Bridge works.
- Operator helper workflow works.
- Manual review loop works.
- Phase 5.0 feasibility study completed.

## Intended Future Flow

```text
ChatGPT
-> MCP tool layer
-> Dispatcher Local Bridge
-> Codex worker
-> Git control
-> Dispatcher result artifacts
-> ChatGPT review
```

The MCP layer should translate safe, structured tool calls into the existing Dispatcher bridge contract. It must not become a second dispatcher or a general local automation runtime.

## Allowed MCP Tools

Only these future tools are in scope.

### A. `dispatcher_status`

Maps to:

```text
GET /status
```

Input:

```json
{}
```

Output concept:

```json
{
  "status": "ok",
  "dispatcherRoot": "D:\\dev\\projects\\jj-ai-dispatcher",
  "defaultWorker": "codex",
  "autoPush": false,
  "bridgeEnabled": true,
  "taskState": "idle"
}
```

Side effects:

- None.

### B. `dispatcher_dispatch`

Maps to:

```text
POST /dispatch
```

Input concept:

```json
{
  "repo": "self",
  "worker": "codex",
  "task": "Describe the exact task.",
  "commitMessage": "docs: describe change",
  "scope": [
    "Allowed files or directories."
  ],
  "blocked": [
    "Files, behaviors, or integrations that must not change."
  ],
  "validation": [
    "Required validation commands or evidence."
  ],
  "expectedOutput": [
    "Expected files, commits, or result artifacts."
  ]
}
```

Output concept:

```json
{
  "accepted": true,
  "status": "running",
  "taskState": "running",
  "processId": 12345,
  "taskId": null
}
```

If a future Dispatcher bridge returns `taskId`, the MCP tool may surface it. If not, callers must use `dispatcher_latest_result` after the task becomes idle.

Side effects:

- Starts one Dispatcher task.

### C. `dispatcher_latest_result`

Maps to:

```text
GET /runs/latest
```

Input:

```json
{}
```

Output concept:

```json
{
  "taskId": "20260526-031500-a1b2c3d4",
  "status": "success",
  "repo": "D:\\dev\\projects\\jj-ai-dispatcher",
  "worker": "codex",
  "filesChanged": [],
  "commit": null,
  "commitMessage": "docs: describe change",
  "pushed": false,
  "workingTreeClean": true,
  "summary": "Codex worker completed successfully.",
  "needsReview": false,
  "reviewHints": []
}
```

Side effects:

- No execution side effect.

### D. `dispatcher_get_run`

Maps to:

```text
GET /runs/{taskId}
```

Input concept:

```json
{
  "taskId": "20260526-031500-a1b2c3d4"
}
```

Output concept:

- Same as `dispatcher_latest_result`.

Side effects:

- No execution side effect.

## Explicitly Forbidden MCP Tools

These tools must not exist in the MCP layer.

- `arbitrary_shell`: blocked because it would bypass Dispatcher task validation and allow unrestricted local command execution.
- `arbitrary_file_read`: blocked because it would expose local files outside the Dispatcher result contract.
- `arbitrary_file_write`: blocked because it would bypass Codex, Git, review artifacts, and scope controls.
- `delete`: blocked because destructive operations require explicit human review and are outside the bridge contract.
- `push`: blocked because publishing changes must remain a separate explicit Git decision.
- `tunnel_enable`: blocked because it would create remote exposure.
- `remote_exec`: blocked because execution must remain local and controlled.
- `vscode_ui_control`: blocked because direct editor UI automation is broad, brittle, and hard to audit.
- `credential_read`: blocked because tokens, credentials, and secrets must never be exposed to ChatGPT.
- `config_write`: blocked because local configuration changes can alter safety boundaries.

## Approval Model

- `dispatcher_status` can run without approval.
- `dispatcher_latest_result` can run without approval.
- `dispatcher_get_run` can run without approval.
- `dispatcher_dispatch` requires explicit user approval.
- No auto-chain dispatch.
- Every dispatch must be reviewed before the next dispatch.

The approval prompt should show the target repo, worker, task summary, commit message, scope, blocked list, and validation expectations before dispatch.

## Dispatch Constraints

`dispatcher_dispatch` must enforce:

- `worker = codex` only initially.
- `repo = self` or an allowlisted local path only.
- `task` required.
- `commitMessage` required when file changes are expected.
- `scope` should be provided for file-changing tasks.
- `blocked` list should be provided for safety.
- One active task only.
- No queue expansion in the MCP layer.
- No direct push.
- No remote execution.

The MCP layer should reject dispatch requests that are missing required safety context for file-changing tasks.

## Long Task Handling

Future file-task mode concept:

- Long prompts should be stored as task files.
- MCP should not pass huge task payloads blindly.
- A task length threshold should trigger file-task mode or rejection.
- File-task mode must still be bounded to an allowlisted task folder.

The allowlisted task folder should be under Dispatcher control, for example a future `dispatcher/inbox/mcp-tasks/` folder. File-task mode must not accept arbitrary filesystem paths from ChatGPT.

## Token And Secret Handling

Rules:

- MCP must not expose the bridge token to ChatGPT.
- Bridge token stays local.
- MCP reads token from `dispatcher/config.local.json` or environment.
- Logs must not print token.
- Result artifacts must not include token.
- MCP error messages must not reveal token or config contents.

Error messages should be operationally useful but generic, such as `bridge token missing` or `bridge authentication failed`, without echoing secret values or config bodies.

## Audit And Run-Result Mapping

Every MCP dispatch must map to Dispatcher artifacts:

- `dispatcher/runs/<task-id>/task.json`
- `dispatcher/runs/<task-id>/result.json`
- `dispatcher/runs/<task-id>/summary.md`
- `dispatcher/runs/<task-id>/codex-output.log`
- `dispatcher/runs/<task-id>/codex-error.log`
- `dispatcher/runs/<task-id>/git-diff.patch`

The MCP layer must return enough identifiers for ChatGPT to request latest or specific results. At minimum, after a dispatch reaches idle, ChatGPT must be able to call `dispatcher_latest_result` and then use `taskId` with `dispatcher_get_run`.

## Review Checklist After MCP Dispatch

Before the next dispatch, ChatGPT must review:

- `status`
- `repo`
- `worker`
- `filesChanged`
- `commit`
- `pushed`
- `workingTreeClean`
- `needsReview`
- `reviewHints`
- validation evidence

The review loop from `docs/operator-run-review-template.md` remains mandatory. MCP convenience must not replace result review.

## Threat Model

Prompt injection:

- Risk: task text or run output tries to convince ChatGPT to bypass safety rules.
- Control: tool schemas, approval prompts, blocked operations, and mandatory review before next dispatch.

Malicious task text:

- Risk: task asks Codex to change hidden files, weaken security, or modify bridge behavior.
- Control: scope, blocked list, repo allowlist, and human approval.

Repo escape:

- Risk: request targets an unintended path outside approved repositories.
- Control: allow `self` and explicit allowlisted local paths only.

Token leakage:

- Risk: bridge token appears in ChatGPT context, logs, errors, or artifacts.
- Control: token stays local, never returned by MCP, never printed in logs.

Arbitrary shell escalation:

- Risk: ChatGPT gains a general command runner.
- Control: no `arbitrary_shell`; MCP only wraps Dispatcher endpoints.

Local file exposure:

- Risk: ChatGPT reads unrelated local files.
- Control: no arbitrary file read tool; results come only from Dispatcher artifacts.

Remote exposure:

- Risk: local bridge becomes reachable from outside localhost.
- Control: no tunnel, no public endpoint, no remote bridge.

Unsafe auto-push:

- Risk: changes are published before review.
- Control: no `push` MCP tool; `pushed` must be reviewed and expected.

Accidental destructive changes:

- Risk: task deletes or rewrites files outside scope.
- Control: blocked list, Git review, result artifacts, and manual rollback review.

Auto-chain runaway:

- Risk: ChatGPT dispatches repeated tasks without human review.
- Control: no auto-chain; every dispatch requires approval and review before the next dispatch.

## Decision

MCP is acceptable only if it wraps existing Dispatcher bridge functions and does not bypass Dispatcher or Git control.

The MCP layer must remain narrow, local, auditable, approval-gated for dispatch, and unable to perform arbitrary shell, file, remote, credential, push, tunnel, or VSCode UI operations.

## Recommended Next Step

Phase 5.2 - MCP Protocol Research Notes

Scope:

- Documentation only.
- Research practical MCP server options for local Windows, PowerShell, Node, and Python implementation.
- Do not implement MCP yet.
- Do not add tunnels, public endpoints, remote execution, or VSCode UI automation.
