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

P0-P3 stabilization is complete. The controlling historical implementation plan is preserved in [docs/JJ_AI_DISPATCHER_P0_P3_STABILIZATION_PLAN.md](docs/JJ_AI_DISPATCHER_P0_P3_STABILIZATION_PLAN.md), with a byte-identical project-source mirror at [source/JJ_AI_DISPATCHER_P0_P3_STABILIZATION_PLAN.md](source/JJ_AI_DISPATCHER_P0_P3_STABILIZATION_PLAN.md).

Current release metadata baseline is `0.8.0`. The annotated Git tag `v0.8.0` exists and marks completion of the P0-P3 stabilization baseline. Historical tags and phase records remain unchanged.

Next planning candidate: P4 Controlled Task Sequencing is documented in [docs/phase-4-controlled-task-sequencing-design.md](docs/phase-4-controlled-task-sequencing-design.md), with a byte-identical mirror at [source/phase-4-controlled-task-sequencing-design.md](source/phase-4-controlled-task-sequencing-design.md).

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
.\scripts\watch-current-task.ps1 -StallSeconds 180
```

Inspect the newest Dispatcher run once. If it is already terminal, the watcher prints the run metadata and exits immediately:

```powershell
.\scripts\watch-current-task.ps1
```

Wait for the next active Dispatcher run, attach once, tail newly appended Codex stdout/stderr, and exit when that run reaches a terminal execution state:

```powershell
.\scripts\watch-current-task.ps1 -WaitForNext
```

For an operator console that keeps waiting for another run after each completion:

```powershell
.\scripts\watch-current-task.ps1 -WaitForNext -ContinueWatching
```

## Result Recovery

Browser postback is an optional delivery channel. It is useful when the browser is available, but it is not the source of execution truth.

Execution can continue while Windows is locked when the local worker, Dispatcher, and target repository remain operational. Browser DOM typing and send-button interaction are not lock-screen tolerant, so a browser postback timeout does not prove that task execution failed.

MCP recovery tool roles:

- `dispatcher_status`: confirm the adapter and bridge are reachable and whether a task is still `running` or back to `idle`.
- `dispatcher_latest_result`: retrieve the newest completed persisted result after the task is idle or when browser postback did not arrive.
- `dispatcher_get_run`: retrieve a specific persisted result by task ID when the latest run is not the run being reviewed or the task ID is known from a previous result.

Recovery path:

1. Dispatch one approved task.
2. Let Dispatcher and Codex execute locally.
3. If the screen locks, the browser times out, the extension reloads, the ChatGPT page refreshes, or MCP reconnects, do not infer execution failure from the missing browser postback.
4. After unlock or reconnect, call `dispatcher_status` first. If `taskState` is still `running`, wait and check again.
5. When the bridge is reachable and the task is no longer running, call `dispatcher_latest_result`.
6. If a specific task ID is known or latest result is not the intended run, call `dispatcher_get_run`.
7. Review `executionStatus` separately from `deliveryStatus`, then review commit, changed files, validation output, and working-tree state before dispatching another task.

The persisted result path is:

```text
dispatcher/runs/<task-id>/result.json
```

In run results, `status` is retained for compatibility and represents execution outcome only. Newer results also expose `executionStatus`, `deliveryStatus`, `deliveryChannel`, and `deliveryRequired`; older successful results without delivery fields are read as `deliveryStatus: "not_requested"`.

Read-only and no-change runs persist the worker's final report directly in the result contract as `workerSummary`, `workerReport`, `workerReportMetadata`, and `workerReportTruncated`. The report is redacted for token-like content and bounded before persistence; full raw logs remain artifact references, not MCP file-read endpoints. `summary.md` includes the persisted worker report so substantive no-change conclusions remain recoverable through `dispatcher_latest_result` and `dispatcher_get_run`.

Browser postback delivery is optional and may move through `pending`, `delivered`, `timeout`, `failed`, `skipped`, or `unavailable`. These delivery updates are persisted to `result.json` and reflected by `dispatcher_latest_result` and `dispatcher_get_run`, but they never change top-level `status` or `executionStatus`. A successful execution with a postback timeout remains `status: "success"` and `executionStatus: "success"` with `deliveryStatus: "timeout"`.

`dispatcher_latest_result` returns the newest completed persisted run for this dispatcher repository. It ignores interrupted `queued` or `running` artifacts, malformed task/result mismatches, and completed lifecycle-test artifacts whose `repo` points at unrelated temporary repositories. Direct `dispatcher_get_run` lookup still uses the exact task ID and returns that run only.

Bridge restart limitation: completed `result.json` files remain retrievable after restart because retrieval is based on `dispatcher/runs/<task-id>/`. In-memory task state, browser postback queue state, and active typing state do not survive a bridge restart. After restart, use `dispatcher_status` to confirm the bridge is back, then use `dispatcher_latest_result` or `dispatcher_get_run` as the authoritative recovery path for completed persisted runs.

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

`ask.ps1` writes the task to the dispatcher inbox, then `dispatcher/run.ps1 codex_task` runs Codex, records run artifacts, owns the Git commit, and resolves push behavior from the global safety policy plus the optional per-task push control.

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
- no force push
- Dispatcher push precedence is explicit and backward-compatible:
  - `safety.allowAutoPush=true` makes successful Dispatcher-owned commits push by default
  - `dispatcher/inbox/codex-task.push.txt` values `false`, `no`, `0`, `off`, or `never` opt out for one task
  - `true`, `yes`, `1`, `on`, or `always` remain supported as an explicit per-task push request
  - when `safety.allowAutoPush=false`, no per-task file means no push, and an explicit per-task push request is rejected safely
  - no-change tasks never push
- `dispatcher_status` keeps `autoPush` as a compatibility alias and also reports `globalAutoPushAllowed`, `currentTaskPushDecision`, and `currentTaskPushDecisionReason`
- run results report `pushed`, `globalAutoPushAllowed`, `pushDecision`, and `pushDecisionReason`
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

Standard automated test commands:

```powershell
npm test
npm run test:unit
npm run test:integration
npm run smoke:local
```

Compatibility smoke command:

```powershell
npm run test:smoke
```

Syntax/build checks:

```powershell
npm run build
git diff --check
```

Manual environment validations remain separate from `npm test`:

```text
unlocked browser postback
Windows lock-screen postback timeout
result recovery after unlock
```

`npm test` is the standard top-level automated baseline. It runs unit, integration, and local smoke coverage without real remote pushes, public exposure of port `8787`, committed secrets, browser UI automation, or production checkout mutation outside controlled temporary fixtures. `npm run mcp:smoke` is the operator-facing MCP contract smoke check and includes `npm run build`.

MCP smoke commands:

```powershell
npm run mcp:smoke
npm run mcp:http:smoke
```

See [docs/testing.md](docs/testing.md) for the unit, integration, smoke, and manual validation split.
