# Phase 7.5 ChatGPT MCP Operations Checklist

## Purpose

This checklist is for daily/operator use after the Phase 7 ChatGPT MCP integration is already working end-to-end.

Use it to start, verify, smoke test, recover, and shut down the validated ChatGPT MCP engine without changing runtime behavior or expanding the MCP safety boundary.

Working chain:

```text
ChatGPT
  |
  v
Custom MCP Connector / App
  |
  v
ngrok HTTPS tunnel
  |
  v
MCP HTTP adapter on 127.0.0.1:8790
  |
  v
Dispatcher bridge on 127.0.0.1:8787
  |
  v
Codex worker
  |
  v
Git commit
```

## Pre-Flight Checklist

- [ ] Repo path confirmed: `D:\dev\projects\jj-ai-dispatcher`.
- [ ] No active Codex/Dispatcher run is in progress.
- [ ] Required terminals are available.
- [ ] Dispatcher bridge config/token is available.
- [ ] ngrok is installed.
- [ ] ngrok authtoken is configured.
- [ ] ChatGPT connector exists as `JJ Dispatcher MCP`.

## Startup Checklist

### Terminal 1 - Dispatcher Bridge

```powershell
cd D:\dev\projects\jj-ai-dispatcher
.\dispatcher\bridge.ps1
```

### Terminal 2 - MCP HTTP Adapter

```powershell
cd D:\dev\projects\jj-ai-dispatcher
npm run mcp:http
```

### Terminal 3 - ngrok HTTPS Tunnel

```powershell
ngrok http 8790 --host-header="localhost:8790"
```

## Expected Service Outputs

- Dispatcher bridge is listening on `127.0.0.1:8787`.
- Dispatcher bridge reports `taskState` as `idle`.
- MCP adapter exposes `/mcp`, `/sse`, and `/messages`.
- ngrok forwards `https://<ngrok-domain>` to `localhost:8790`.

## ChatGPT Connector Verification

Name:

```text
JJ Dispatcher MCP
```

MCP Server URL:

```text
https://<ngrok-domain>/mcp
```

Authentication:

```text
No Auth
```

Expected tools exactly:

- `dispatcher_status`
- `dispatcher_dispatch`
- `dispatcher_latest_result`
- `dispatcher_get_run`

## Smoke Test Checklist

- [ ] Call `dispatcher_status`.
- [ ] Call `dispatcher_latest_result`.
- [ ] Call `dispatcher_dispatch` with an explicit approved documentation-only task.

Expected:

- status `ok`
- `taskState` idle before dispatch
- review gate appears before execution
- latest result returns success after completion

## Recovery Checklist

| Symptom | Safe recovery |
| --- | --- |
| Bridge down | Start Terminal 1 with `.\dispatcher\bridge.ps1`, then confirm `dispatcher_status` returns status `ok`. |
| MCP adapter down | Start Terminal 2 with `npm run mcp:http`, then rerun the connector/tool-list check. |
| ngrok down | Start Terminal 3 again and update the ChatGPT connector URL to the new `https://<ngrok-domain>/mcp`. |
| ngrok command not found | Confirm ngrok is installed, reopen the terminal, then run `ngrok version`. |
| ngrok auth token missing | Run `ngrok config add-authtoken <TOKEN>` and do not paste the token into repo files, docs, commits, or chat logs. |
| Qi-AnXin Tianqing quarantined ngrok | Restore or reinstall ngrok only under operator/company policy; if approved, allow the WinGet temp/package locations documented in the Phase 7.4 runbook. |
| Forbidden / 403 / host mismatch | Restart ngrok with `ngrok http 8790 --host-header="localhost:8790"`. |
| ChatGPT connector tool list missing | Confirm the MCP Server URL ends with `/mcp`, ngrok forwards to `localhost:8790`, the MCP HTTP adapter is running, and the tool list is exactly the approved four. |
| Latest result still running | Call `dispatcher_status`, wait until the run completes, then call `dispatcher_latest_result` again. Do not dispatch another task until the latest run is reviewed. |

## Shutdown Checklist

Stop in this order with `Ctrl+C`:

1. ngrok tunnel
2. MCP HTTP adapter
3. Dispatcher bridge

## Safety Checklist

- [ ] Never expose `127.0.0.1:8787`.
- [ ] Never tunnel raw Dispatcher bridge.
- [ ] Expose `8790` adapter only.
- [ ] Keep exactly four MCP tools.
- [ ] No arbitrary shell tool.
- [ ] No arbitrary file read/write tool.
- [ ] No direct Git MCP tool.
- [ ] No scheduler.
- [ ] No autonomous loop.
- [ ] Stop ngrok when not actively testing.
- [ ] No Auth is only for controlled feasibility testing.

## Known-Good Snapshot

- Latest known commit: `4794ede`.
- Validated ngrok command:

  ```powershell
  ngrok http 8790 --host-header="localhost:8790"
  ```

- Phase 7 end-to-end integration achieved.
