# JJ AI Dispatcher

## Product Definition

JJ AI Dispatcher is a local-first, safety-controlled AI coding dispatcher with ChatGPT MCP initiation, Codex execution, Dispatcher-owned Git control, persistent run results, and optional browser-visible postback.

It reduces manual copy/paste between ChatGPT, Codex, Dispatcher, and Git while keeping the operator or ChatGPT in the review loop.

It is not yet:

- a fully autonomous AI employee
- a general remote desktop controller
- a production multi-user platform
- a distributed agent system
- a guaranteed lock-screen browser automation system
- a review-free autonomous coding platform

## Current Architecture

Runtime chain:

```text
ChatGPT
  -> MCP HTTPS / approved connector
  -> MCP HTTP Adapter on 127.0.0.1:8790
  -> local Dispatcher Bridge on 127.0.0.1:8787
  -> Codex worker
  -> Dispatcher-owned Git commit / optional push
  -> persistent run result
  -> optional browser-visible postback
```

Role model:

- ChatGPT = Brain
- Dispatcher MCP = Tool Channel
- Dispatcher = Execution Controller and Git owner
- Codex = Coding Worker
- Git = Control Point
- Launcher = Environment Startup Helper
- Browser postback = optional delivery channel

The raw Dispatcher Bridge on `127.0.0.1:8787` is local-only and must never be publicly exposed or tunneled. For controlled ChatGPT MCP feasibility testing, only the MCP HTTP Adapter boundary on port `8790` is approved for HTTPS tunnel exposure.

## Current Maturity

Current standing:

- local Dispatcher execution is implemented
- Codex task execution is implemented
- Dispatcher-owned Git commit is implemented
- MCP status, dispatch, latest-result, and get-run tools are implemented
- the MCP HTTP Adapter defaults to `127.0.0.1:8790`
- the Dispatcher Bridge defaults to `127.0.0.1:8787`
- persistent run artifacts are implemented under `dispatcher/runs/<task-id>/`
- browser-visible postback exists as an optional delivery path
- launcher startup and health-check workflow exists as an environment startup helper

Current stabilization focus is the approved P0-P3 plan in [docs/JJ_AI_DISPATCHER_P0_P3_STABILIZATION_PLAN.md](docs/JJ_AI_DISPATCHER_P0_P3_STABILIZATION_PLAN.md). P0.1 is documentation consolidation only; version and runtime metadata alignment are reserved for P0.2.

Current release metadata baseline is `0.8.0`, selected as the stabilization-development baseline after the existing historical Git tag sequence through `v0.7-autonomous-sprint-poc`. Historical tags and phase records remain unchanged. The final `v0.8.0` Git tag is deferred until P0-P3 final stabilization acceptance; do not create it during P0.2 metadata alignment.

## MCP Tool Surface

The approved MCP tool surface is intentionally narrow:

- `dispatcher_status`: read bridge readiness and task state
- `dispatcher_dispatch`: submit one explicit approved Codex task
- `dispatcher_latest_result`: retrieve the most recent persisted run result
- `dispatcher_get_run`: retrieve one persisted run result by task ID

There is no arbitrary shell MCP tool, direct Git MCP tool, scheduler, queue, autonomous loop, distributed worker routing, UI dashboard, bot bridge, or GitHub issue bridge in the current approved surface.

## Operating Flow

Start the local Dispatcher Bridge:

```powershell
.\dispatcher\bridge.ps1
```

Start the MCP HTTP Adapter:

```powershell
npm run mcp:http
```

For controlled ChatGPT connector feasibility testing, expose only the adapter:

```powershell
ngrok http 8790 --host-header="localhost:8790"
```

Then configure the ChatGPT MCP Server URL as:

```text
https://<ngrok-domain>/mcp
```

Manual local helper scripts remain available:

```powershell
.\scripts\bridge-status.ps1
.\scripts\bridge-dispatch.ps1 -Repo self -Worker codex -Task "describe task" -CommitMessage "docs: describe change"
.\scripts\bridge-wait-latest.ps1
.\scripts\bridge-latest.ps1
```

## Result Recovery

Browser postback is an optional delivery channel. It is useful when the browser is available, but it is not the source of execution truth.

Execution can continue while Windows is locked when the local worker, Dispatcher, and target repository remain operational. Browser DOM typing and send-button interaction are not lock-screen tolerant, so a browser postback timeout does not prove that task execution failed.

Recovery path:

1. Dispatch one approved task.
2. Let Dispatcher and Codex execute locally.
3. If browser postback succeeds, review the posted summary.
4. If browser postback times out or the browser is unavailable, call `dispatcher_latest_result`.
5. If a specific task ID is known, call `dispatcher_get_run`.
6. Review the persisted result, commit, changed files, validation output, and working-tree state before dispatching another task.

The persisted result path is:

```text
dispatcher/runs/<task-id>/result.json
```

In run results, `status` is retained for compatibility and represents execution outcome only. Newer results also expose `executionStatus`, `deliveryStatus`, `deliveryChannel`, and `deliveryRequired`; older successful results without delivery fields are read as `deliveryStatus: "not_requested"`.

Browser postback delivery is optional and may move through `pending`, `delivered`, `timeout`, `failed`, `skipped`, or `unavailable`. These delivery updates are persisted to `result.json` and reflected by `dispatcher_latest_result` and `dispatcher_get_run`, but they never change top-level `status` or `executionStatus`. A successful execution with a postback timeout remains `status: "success"` and `executionStatus: "success"` with `deliveryStatus: "timeout"`.

## Dispatcher CLI Usage

Run a Codex task against the configured default repo:

```powershell
.\dispatcher\ask "update README"
```

Run a Codex task against this dispatcher repo:

```powershell
.\dispatcher\ask self "update README"
```

Run a Codex task against another repo:

```powershell
.\dispatcher\ask D:\dev\projects\other-repo "update README"
```

Run a Codex task with a custom commit message:

```powershell
.\dispatcher\ask self "update README" -m "docs: update README"
```

`ask.ps1` writes the task to the dispatcher inbox, then `dispatcher/run.ps1 codex_task` runs Codex, records run artifacts, owns the Git commit, and handles optional auto-push when explicitly enabled.

## Configuration

- `dispatcher/config.json` = shared/default config
- `dispatcher/config.local.json` = machine-specific override
- `dispatcher/config.local.json` is ignored by Git
- `dispatcher/config.local.example.json` is the template

Example `config.local.json`:

```json
{
  "defaultRepo": "D:\\path\\to\\target\\repo",
  "codexExe": "C:\\path\\to\\codex.exe",
  "openclawExe": "C:\\Program Files\\Co-Claw\\Co-Claw.exe",
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

Never commit real tokens or secrets.

## Safety Rules

- keep the Dispatcher Bridge on localhost only
- never expose or tunnel port `8787`
- expose adapter port `8790` only for approved controlled MCP testing
- stop tunnels when not actively testing
- keep exactly the approved MCP tool surface
- no auto push unless explicitly enabled in config and requested by task
- no auto delete unless explicitly enabled
- no system setting modification unless explicitly enabled
- review persisted run results before issuing the next task

## Documentation Index

- [docs/JJ_AI_DISPATCHER_P0_P3_STABILIZATION_PLAN.md](docs/JJ_AI_DISPATCHER_P0_P3_STABILIZATION_PLAN.md)
- [docs/local-bridge-operator-guide.md](docs/local-bridge-operator-guide.md)
- [docs/chatgpt-operator-workflow.md](docs/chatgpt-operator-workflow.md)
- [docs/phase-7-2-http-sse-mcp-adapter.md](docs/phase-7-2-http-sse-mcp-adapter.md)
- [docs/phase-7-4-chatgpt-mcp-engine-startup-runbook.md](docs/phase-7-4-chatgpt-mcp-engine-startup-runbook.md)
- [docs/phase-7-5-chatgpt-mcp-operations-checklist.md](docs/phase-7-5-chatgpt-mcp-operations-checklist.md)
- [launcher/README.md](launcher/README.md)
- [docs/development-log.md](docs/development-log.md)

## Validation

Syntax and smoke commands:

```powershell
npm run build
npm run mcp:smoke
npm run mcp:http:smoke
git diff --check
```
