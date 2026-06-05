# ChatGPT Operator Workflow

This guide records the operator workflow for ChatGPT-directed Dispatcher tasks. It covers both the local helper-script path and the current MCP path, where ChatGPT calls the approved Dispatcher MCP tools through the MCP HTTP Adapter.

## Purpose

The workflow standardizes operation so that:

- ChatGPT can prepare dispatcher-ready tasks.
- ChatGPT can call the approved MCP tool surface, or the operator can run known PowerShell helper scripts.
- The dispatcher remains local-only and token-protected.
- Result artifacts are read back before ChatGPT decides the next action.

The raw Dispatcher Bridge remains local-only on `127.0.0.1:8787`. For controlled ChatGPT feasibility testing, only the MCP HTTP Adapter on `127.0.0.1:8790` may be exposed through the approved HTTPS connector/tunnel boundary.

## Role Model

- ChatGPT = Brain. It prepares the task, reviews results, and decides next action.
- Dispatcher MCP = Tool Channel. It exposes `dispatcher_status`, `dispatcher_dispatch`, `dispatcher_latest_result`, and `dispatcher_get_run`.
- Dispatcher = Execution Controller and Git owner. It accepts constrained requests, starts the worker, records artifacts, and owns Git commit behavior.
- Codex = Coding Worker. It edits files in the target repository.
- Git = Control Point. It records and exposes changes for review through status, diff, commit, and run artifacts.
- Launcher = Environment Startup Helper. It can start configured local services and health checks.
- Browser postback = optional delivery channel.

## Current Operating Flow

1. ChatGPT prepares one explicit dispatch payload.
2. ChatGPT calls `dispatcher_dispatch`, or the operator sends `POST /dispatch` through a helper script.
3. ChatGPT or the operator checks status until the task is complete.
4. ChatGPT calls `dispatcher_latest_result`, or the operator reads `GET /runs/latest`.
5. If needed, ChatGPT calls `dispatcher_get_run` with the task ID.
6. ChatGPT reviews the persisted result and decides the next action.

The dispatch response only means the task was accepted and started. The result may not exist immediately. `/runs/latest` can return `not_found` while Codex is still running.

Browser postback may also deliver a visible summary when the browser is available. It is optional delivery only. A browser postback timeout does not prove execution failure, especially when Windows is locked or the browser cannot perform DOM typing/send interaction.

## Standard ChatGPT Dispatch Envelope

ChatGPT should prepare tasks with this envelope:

```json
{
  "repo": "self",
  "worker": "codex",
  "task": "Describe the exact work for Codex.",
  "commitMessage": "docs: describe the change",
  "scope": [
    "Allowed files or directories."
  ],
  "blocked": [
    "Files, behaviors, integrations, or access patterns that must not change."
  ],
  "validation": [
    "Commands or checks the operator should run."
  ],
  "expectedOutput": [
    "Files, commits, or artifacts expected when complete."
  ]
}
```

Current bridge dispatch requires `repo`, `worker`, and `task`; `commitMessage` is optional but supported. The helper script sends those bridge-supported fields. Put `scope`, `blocked`, `validation`, and `expectedOutput` into the `task` text when they should be visible to Codex.

Example ChatGPT-prepared command:

```powershell
.\scripts\bridge-dispatch.ps1 `
  -Repo self `
  -Worker codex `
  -Task "Update docs only. Scope: docs/chatgpt-operator-workflow.md. Blocked: do not modify bridge.ps1 or dispatcher execution logic. Validation: run git diff --check. Expected output: committed documentation update." `
  -CommitMessage "docs: update operator workflow"
```

## PowerShell Templates

### Status Check

```powershell
.\scripts\bridge-status.ps1
```

Raw endpoint equivalent:

```powershell
$token = "replace-with-your-local-token"
Invoke-RestMethod `
  -Method Get `
  -Uri "http://127.0.0.1:8787/status" `
  -Headers @{ "X-Dispatcher-Token" = $token }
```

### Dispatch

```powershell
.\scripts\bridge-dispatch.ps1 `
  -Repo self `
  -Worker codex `
  -Task "update README usage section" `
  -CommitMessage "docs: update README usage"
```

Raw endpoint equivalent:

```powershell
$token = "replace-with-your-local-token"
$body = @{
  repo = "self"
  worker = "codex"
  task = "update README usage section"
  commitMessage = "docs: update README usage"
} | ConvertTo-Json

Invoke-RestMethod `
  -Method Post `
  -Uri "http://127.0.0.1:8787/dispatch" `
  -ContentType "application/json" `
  -Headers @{ "X-Dispatcher-Token" = $token } `
  -Body $body
```

### Polling

```powershell
.\scripts\bridge-wait-latest.ps1
```

Raw polling equivalent:

```powershell
$token = "replace-with-your-local-token"

do {
  Start-Sleep -Seconds 2
  $status = Invoke-RestMethod `
    -Method Get `
    -Uri "http://127.0.0.1:8787/status" `
    -Headers @{ "X-Dispatcher-Token" = $token }

  $status.taskState
} while ($status.taskState -ne "idle")
```

### Latest Result

```powershell
.\scripts\bridge-latest.ps1
```

Raw endpoint equivalent:

```powershell
$token = "replace-with-your-local-token"
Invoke-RestMethod `
  -Method Get `
  -Uri "http://127.0.0.1:8787/runs/latest" `
  -Headers @{ "X-Dispatcher-Token" = $token }
```

### Specific Run Result

```powershell
$token = "replace-with-your-local-token"
$taskId = "20260525-153012-abc12345"

Invoke-RestMethod `
  -Method Get `
  -Uri "http://127.0.0.1:8787/runs/$taskId" `
  -Headers @{ "X-Dispatcher-Token" = $token }
```

## Helper Scripts

These local helpers are available:

- `scripts/bridge-status.ps1`: calls `GET /status`.
- `scripts/bridge-dispatch.ps1`: sends `POST /dispatch`.
- `scripts/bridge-latest.ps1`: calls `GET /runs/latest`.
- `scripts/bridge-wait-latest.ps1`: polls status every 2 seconds until idle, then prints the latest result.

Each helper reads bridge host, port, and token from local dispatcher configuration. The token is used only as the `X-Dispatcher-Token` request header and is not printed.

## MCP Result Recovery

Use persistent result retrieval as the recovery path whenever browser postback is unavailable:

```text
dispatcher_latest_result
dispatcher_get_run
```

Execution can continue while Windows is locked if the local worker remains operational. Browser DOM typing and send-button interaction are not lock-screen tolerant. After unlocking, confirm MCP connectivity with `dispatcher_status`, then retrieve the persisted result with `dispatcher_latest_result` or `dispatcher_get_run`.

## Safety Boundaries

- Localhost only: use `127.0.0.1`.
- Token required by default.
- Real tokens belong only in `dispatcher/config.local.json`.
- Do not commit `dispatcher/config.local.json`.
- No remote raw bridge.
- MCP is limited to the approved Dispatcher tool surface.
- Only the MCP HTTP Adapter on port `8790` may be exposed for controlled feasibility testing.
- Do not add port forwarding, reverse proxies, public tunnels, or remote access around the raw bridge on port `8787`.

## Operator Checklist

1. Confirm the bridge is running with `.\scripts\bridge-status.ps1`.
2. Send the ChatGPT-prepared task with `.\scripts\bridge-dispatch.ps1`.
3. Wait for completion with `.\scripts\bridge-wait-latest.ps1`.
4. Paste the final JSON result back to ChatGPT.
5. Let ChatGPT review `status`, `filesChanged`, `commit`, `workingTreeClean`, `summary`, and `reviewHints`.
