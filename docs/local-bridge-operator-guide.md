# Local Bridge Operator Guide

This guide explains how to operate the JJ AI Dispatcher Local HTTP Bridge safely from the local machine.

## Project Context

JJ AI Dispatcher is a local execution controller for small, controlled coding tasks. It keeps the human or ChatGPT in the decision-making loop while delegating file edits to a local coding worker.

Current role split:

- ChatGPT = Brain. It plans, decides, reviews, and instructs.
- Dispatcher = Execution Controller. It accepts a constrained task, writes dispatcher inbox files, starts the worker, records run artifacts, and owns Git commit behavior.
- Codex = Coding Worker. It performs local code/documentation edits inside the selected repository.
- Git = Control Point. The dispatcher uses Git status, diff, add, commit, and optional push controls to keep changes observable.

Project repository:

- Local: `D:\dev\projects\jj-ai-dispatcher`
- GitHub: `https://github.com/Gumb-D/jj-ai-dispatcher`

## Current Stable Baseline

Stable baseline:

- Branch: `main`
- Baseline tag: `v0.3-phase3-bridge`
- Bridge type: Local HTTP Bridge
- Bind address: `127.0.0.1` only
- Token required by default
- Dispatch support: Codex only
- Concurrency model: single active task
- Queue: none
- MCP: none
- Tunnel: none
- Remote exposure: none

The bridge currently exposes only:

- `GET /status`
- `POST /dispatch`
- `GET /runs/latest`
- `GET /runs/{taskId}`

## Configuration

Shared defaults live in `dispatcher/config.json`. Machine-specific settings belong in `dispatcher/config.local.json`, which is ignored by Git.

Start from the template:

```powershell
Copy-Item .\dispatcher\config.local.example.json .\dispatcher\config.local.json
```

Bridge settings:

- `bridge.enabled`: set to `true` to start the local bridge. If `false`, `dispatcher/bridge.ps1` exits without starting a listener.
- `bridge.host`: must be `127.0.0.1`. The current bridge intentionally rejects any other host.
- `bridge.port`: local port, default `8787`.
- `bridge.requireToken`: should stay `true`. When true, every request must include `X-Dispatcher-Token`.
- `bridge.token`: local secret token. Put the real token only in `dispatcher/config.local.json`.

Repo targeting:

- The bridge accepts `"repo": "self"` as a built-in alias for `D:\dev\projects\jj-ai-dispatcher`.
- The bridge also accepts a direct local repository path.
- There is no configurable repo-alias map in the current stable implementation.
- If `repo` is omitted, the dispatcher falls back to `defaultRepo`.

Safe local example:

```json
{
  "defaultRepo": "D:\\dev\\projects\\jj-ai-dispatcher",
  "codexExe": "codex",
  "openclawExe": "C:\\path\\to\\openclaw.exe",
  "bridge": {
    "enabled": true,
    "host": "127.0.0.1",
    "port": 8787,
    "requireToken": true,
    "token": "replace-with-a-local-random-token"
  },
  "safety": {
    "allowAutoPush": false,
    "allowAutoDelete": false,
    "allowSystemSettingModification": false
  }
}
```

Never put the real token in `dispatcher/config.json`, README files, scripts, prompts, or committed docs.

## Starting the Bridge

From the repository root:

```powershell
.\dispatcher\bridge.ps1
```

Expected startup output when enabled:

```text
[bridge] Listening on http://127.0.0.1:8787/
[bridge] Task state: idle
```

If disabled, expected output is:

```text
[bridge] Bridge disabled by config. Server not started.
```

Health check:

```powershell
$token = "replace-with-your-local-token"
Invoke-RestMethod `
  -Method Get `
  -Uri "http://127.0.0.1:8787/status" `
  -Headers @{ "X-Dispatcher-Token" = $token }
```

Expected health response includes:

```json
{
  "status": "ok",
  "bridgeEnabled": true,
  "taskState": "idle"
}
```

## Operator Usage Examples

### GET /status

```powershell
$token = "replace-with-your-local-token"
Invoke-RestMethod `
  -Method Get `
  -Uri "http://127.0.0.1:8787/status" `
  -Headers @{ "X-Dispatcher-Token" = $token }
```

Use this before dispatching work. `taskState` must be `idle` before a new task can be accepted.

### POST /dispatch

Payload:

```json
{
  "repo": "self",
  "worker": "codex",
  "task": "update README usage section",
  "commitMessage": "docs: update README usage"
}
```

PowerShell:

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

Expected accepted response:

```json
{
  "accepted": true,
  "status": "running",
  "worker": "codex",
  "taskState": "running",
  "processId": 12345
}
```

`POST /dispatch` only confirms that the task was accepted and started. It returns `accepted = true` and `status = "running"` while the Codex worker continues in the background.

The dispatch response does not include a `taskId`. The bridge starts `dispatcher/run.ps1 codex_task` in the background, and that run creates its own ID under `dispatcher/runs/<task-id>/`. The result artifact may not exist immediately after dispatch.

After dispatching, poll `GET /status` until `taskState` returns to `idle`:

```powershell
$token = "replace-with-your-local-token"

do {
  Start-Sleep -Seconds 5
  $status = Invoke-RestMethod `
    -Method Get `
    -Uri "http://127.0.0.1:8787/status" `
    -Headers @{ "X-Dispatcher-Token" = $token }

  $status.taskState
} while ($status.taskState -ne "idle")
```

Then call `GET /runs/latest` to find the completed run result and its `taskId`.

### GET /runs/latest

```powershell
$token = "replace-with-your-local-token"
Invoke-RestMethod `
  -Method Get `
  -Uri "http://127.0.0.1:8787/runs/latest" `
  -Headers @{ "X-Dispatcher-Token" = $token }
```

The response is the latest `result.json`. It includes fields such as `taskId`, `status`, `repo`, `worker`, `filesChanged`, `commit`, `workingTreeClean`, `summary`, `logs`, `needsReview`, and `reviewHints`.

`/runs/latest` may return `not_found` while a task is still running. This is expected when the worker has not written `result.json` yet. Poll `GET /status` until `taskState = "idle"`, then retry `GET /runs/latest`.

### GET /runs/{taskId}

```powershell
$token = "replace-with-your-local-token"
$taskId = "20260525-153012-abc12345"

Invoke-RestMethod `
  -Method Get `
  -Uri "http://127.0.0.1:8787/runs/$taskId" `
  -Headers @{ "X-Dispatcher-Token" = $token }
```

Task IDs are generated by the dispatcher in this shape:

```text
yyyyMMdd-HHmmss-xxxxxxxx
```

Example:

```text
20260525-153012-abc12345
```

## Result Artifact Structure

Codex bridge runs are written under:

```text
dispatcher/runs/<task-id>/
```

The run directory contains:

- `task.json`: task contract with task ID, repo, worker, task text, commit message, timestamps, and final task status.
- `result.json`: machine-readable run result returned by `GET /runs/latest` and `GET /runs/{taskId}`.
- `summary.md`: human-readable run summary.
- `codex-output.log`: captured Codex stdout.
- `codex-error.log`: captured Codex stderr.
- `git-diff.patch`: Git diff patch captured before dispatcher commit.

Run artifacts are ignored by Git through `dispatcher/runs/`.

## Phase 4.1 Smoke Test Results

Phase 4.1 local operator smoke testing confirmed:

- `GET /status`: PASS
- `GET /runs/latest`: PASS
- `GET /runs/{taskId}`: PASS
- `POST /dispatch`: PASS
- Busy protection: PASS
- Result artifacts: PASS

The smoke test also confirmed that a freshly accepted dispatch can be running before a result artifact exists. Operators should treat temporary `/runs/latest` `not_found` responses during active execution as normal and continue polling `GET /status`.

## Troubleshooting

Token missing:

- Symptom: HTTP `401`, `status = "unauthorized"`, `error = "X-Dispatcher-Token header required."`
- Fix: include `-Headers @{ "X-Dispatcher-Token" = $token }`.

Invalid token:

- Symptom: HTTP `403`, `status = "forbidden"`, `error = "X-Dispatcher-Token did not match."`
- Fix: use the exact token from local `dispatcher/config.local.json`.

Token required but not configured:

- Symptom: HTTP `500`, `status = "config_error"`, `error = "Bridge token is required but not configured."`
- Fix: set `bridge.token` in `dispatcher/config.local.json`, or disable token enforcement only for controlled local testing.

Bridge not running:

- Symptom: request cannot connect.
- Fix: start `.\dispatcher\bridge.ps1` and confirm the listener output.

Localhost connection failure:

- Symptom: connection refused or wrong-port failure.
- Fix: confirm `bridge.port`, use `http://127.0.0.1:<port>/`, and keep `bridge.host` as `127.0.0.1`.

Task already running:

- Symptom: HTTP `409`, `status = "busy"`, `error = "A dispatcher task is already running."`
- Fix: wait for the active Codex task to finish. This baseline supports one active task and no queue.

No latest run:

- Symptom: HTTP `404`, `status = "not_found"`, `error = "No run results found."`
- Fix: run a dispatch first. If `GET /status` shows `taskState = "running"`, wait and poll status until `taskState = "idle"`, then query `GET /runs/latest` again.

Codex execution failure:

- Symptom: `result.json` has `status = "failed"` and `needsReview = true`.
- Fix: inspect `summary.md`, `codex-output.log`, `codex-error.log`, and `reviewHints`.

Working tree not clean:

- Symptom: `workingTreeClean = false`.
- Fix: inspect the target repo with `git status --short`, review `git-diff.patch`, and decide whether to commit, fix, or revert manually.

Result lookup failure:

- Symptom: HTTP `400` for malformed task IDs or HTTP `404` for missing results.
- Fix: use the exact `taskId` from `GET /runs/latest` or from the run directory name under `dispatcher/runs/`.

## Safety Guidance

The Local HTTP Bridge is intentionally local and narrow.

- Use `127.0.0.1` only.
- Do not bind the bridge to `0.0.0.0`, a LAN IP, or a public interface.
- Never expose the bridge remotely.
- Never commit a real bridge token.
- Put real local bridge secrets only in `dispatcher/config.local.json`.
- Keep `dispatcher/config.local.json` ignored by Git.
- There is no tunnel yet.
- There is no MCP bridge yet.
- There is no GitHub bridge yet.
- Do not add port forwarding, reverse proxies, public tunnels, or remote access around this bridge.

## Future Direction

The intended next milestone is Phase 4: ChatGPT Tool Integration / Operator Layer.

Possible future routes include:

- Continued local `curl` or PowerShell manual usage.
- MCP integration.
- Connector integration.
- HTTPS tool integration.
- Tunnel-based access later.

The local operator workflow must stabilize first. Until then, the stable operating model remains local-only, token-protected, Codex-only, single-task dispatch over `127.0.0.1`.
