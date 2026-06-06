# Phase 7.5 ChatGPT MCP Operations Checklist

## Purpose

This checklist is for daily/operator use after the Phase 7 ChatGPT MCP integration is already working end-to-end.

Use it to start, verify, smoke test, recover, and shut down the validated ChatGPT MCP engine without changing runtime behavior or expanding the MCP safety boundary.

Working chain:

```text
ChatGPT
  -> Custom MCP Connector / App
  -> approved HTTPS connector or controlled ngrok tunnel
  -> MCP HTTP Adapter on 127.0.0.1:8790
  -> Dispatcher Bridge on 127.0.0.1:8787
  -> Codex worker
  -> Dispatcher-owned Git commit / optional push
  -> persistent run result
  -> optional browser-visible postback
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
| ngrok auth token missing | Run `ngrok config add-authtoken <TOKEN>` with an operator-held token and do not paste the token into repo files, docs, commits, or chat logs. |
| Qi-AnXin Tianqing quarantined ngrok | Restore or reinstall ngrok only under operator/company policy; if approved, allow the WinGet temp/package locations documented in the Phase 7.4 runbook. |
| Forbidden / 403 / host mismatch | Restart ngrok with `ngrok http 8790 --host-header="localhost:8790"`. |
| ChatGPT connector tool list missing | Confirm the MCP Server URL ends with `/mcp`, ngrok forwards to `localhost:8790`, the MCP HTTP adapter is running, and the tool list is exactly the approved four. |
| Latest result not found while task is active | Call `dispatcher_status`, wait until the run completes, then call `dispatcher_latest_result` again. Do not dispatch another task until the completed result is reviewed. |
| Browser postback timeout | Treat this as optional delivery failure only. Call `dispatcher_status`, then `dispatcher_latest_result`, then `dispatcher_get_run` if a specific task ID is needed. |
| Browser extension reload or ChatGPT page refresh | Reopen the connector context, call `dispatcher_status`, then retrieve the persisted result with `dispatcher_latest_result` or `dispatcher_get_run`. Browser postback is not the recovery source of truth. |
| MCP reconnect after temporary disconnect | Call `dispatcher_status` first. If idle, retrieve the persisted result. If running, wait and check status again. |
| Windows was locked during execution | Execution may have continued if the local worker stayed operational. Browser DOM typing/send is not lock-screen tolerant, so after unlock call `dispatcher_status`, then retrieve and review the persisted result. |
| Bridge restarted | Completed `result.json` files remain retrievable from `dispatcher/runs/<task-id>/`. In-memory task state and postback queue state do not survive restart; recover only completed persisted results through `dispatcher_latest_result` or `dispatcher_get_run`. |

## Result Review Checklist

- [ ] `dispatcher_status` confirms the bridge is reachable before result retrieval.
- [ ] `dispatcher_latest_result` was used for the newest completed persisted result.
- [ ] `dispatcher_get_run` was used when a known task ID needed exact review.
- [ ] `executionStatus` was reviewed separately from `deliveryStatus`.
- [ ] Browser postback was treated as optional delivery, not the only recovery path.
- [ ] No new task was dispatched before reviewing the persisted result.

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
- [ ] Browser postback is optional delivery.
- [ ] Persistent MCP retrieval is the recovery path.
- [ ] Dispatcher Bridge `8787` remains local-only and MCP Adapter `8790` is the only approved adapter endpoint for controlled exposure.

## Known-Good Snapshot

- Validated ngrok command:

  ```powershell
  ngrok http 8790 --host-header="localhost:8790"
  ```

- Phase 7 end-to-end integration has been validated, but current source of truth for commit/version metadata is Git and package/server metadata, not this checklist.
