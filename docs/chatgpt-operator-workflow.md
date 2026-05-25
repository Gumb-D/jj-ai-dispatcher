# ChatGPT Operator Workflow

Phase 4.2 creates a predictable manual operator workflow between ChatGPT and the JJ AI Dispatcher Local HTTP Bridge. The goal is not remote automation yet. The goal is a stable copy/paste workflow where ChatGPT prepares a task in a standard format, the local operator dispatches it, and the result comes back to ChatGPT for review.

## Purpose

Phase 4.2 standardizes local bridge operation so that:

- ChatGPT can prepare dispatcher-ready tasks.
- The operator can run known PowerShell helper scripts.
- The dispatcher remains local-only and token-protected.
- Result artifacts are read back before ChatGPT decides the next action.

This phase does not add MCP, tunnels, connectors, or remote bridge access.

## Role Model

- ChatGPT = Brain. It prepares the task, reviews results, and decides next action.
- Dispatcher = Execution Controller. It accepts constrained local bridge requests, starts the worker, records artifacts, and owns Git commit behavior.
- Codex = Coding Worker. It edits files in the target repository.
- Git = Control Point. It records and exposes changes for review through status, diff, commit, and run artifacts.

## Current Operating Flow

1. ChatGPT prepares a dispatch payload or helper-script command.
2. Operator sends `POST /dispatch`.
3. Operator polls `GET /status` until `taskState = "idle"`.
4. Operator reads `GET /runs/latest`.
5. Operator pastes the result back to ChatGPT.
6. ChatGPT reviews the result and decides the next action.

The dispatch response only means the task was accepted and started. The result may not exist immediately. `/runs/latest` can return `not_found` while Codex is still running.

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

Phase 4.2 adds these local helpers:

- `scripts/bridge-status.ps1`: calls `GET /status`.
- `scripts/bridge-dispatch.ps1`: sends `POST /dispatch`.
- `scripts/bridge-latest.ps1`: calls `GET /runs/latest`.
- `scripts/bridge-wait-latest.ps1`: polls status every 2 seconds until idle, then prints the latest result.

Each helper reads bridge host, port, and token from local dispatcher configuration. The token is used only as the `X-Dispatcher-Token` request header and is not printed.

## Safety Boundaries

- Localhost only: use `127.0.0.1`.
- Token required by default.
- Real tokens belong only in `dispatcher/config.local.json`.
- Do not commit `dispatcher/config.local.json`.
- No remote bridge.
- No MCP yet.
- No tunnel yet.
- Do not add port forwarding, reverse proxies, public tunnels, or remote access around the bridge.

## Operator Checklist

1. Confirm the bridge is running with `.\scripts\bridge-status.ps1`.
2. Send the ChatGPT-prepared task with `.\scripts\bridge-dispatch.ps1`.
3. Wait for completion with `.\scripts\bridge-wait-latest.ps1`.
4. Paste the final JSON result back to ChatGPT.
5. Let ChatGPT review `status`, `filesChanged`, `commit`, `workingTreeClean`, `summary`, and `reviewHints`.
