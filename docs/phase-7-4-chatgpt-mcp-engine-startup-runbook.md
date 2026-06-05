# Phase 7.4 ChatGPT MCP Engine Startup Runbook

## Purpose

This runbook starts the full JJ Engine for ChatGPT MCP operation.

Working chain:

```text
ChatGPT
  -> Custom MCP Connector / App
  -> approved HTTPS connector or controlled ngrok tunnel
  -> local MCP HTTP Adapter on 127.0.0.1:8790
  -> Dispatcher Bridge on 127.0.0.1:8787
  -> Codex worker
  -> Dispatcher-owned Git commit / optional push
  -> persistent run result
  -> optional browser-visible postback
```

This runbook does not add tools, change authentication, expose the raw Dispatcher bridge, or authorize unattended operation.

For daily/operator checklist use after this startup path is already validated, see `docs/phase-7-5-chatgpt-mcp-operations-checklist.md`.

## Prerequisites

- Node/npm installed.
- Repository located at `D:\dev\projects\jj-ai-dispatcher`.
- Dispatcher bridge config/token already available.
- ChatGPT connector created as `JJ Dispatcher MCP`.
- ngrok account available.
- ngrok authtoken configured.

## ngrok Installation

Install and check ngrok:

```powershell
winget install --id Ngrok.Ngrok -e
ngrok version
ngrok update
ngrok config add-authtoken <TOKEN>
```

Do not commit or paste the ngrok token into the repo or docs.

## Antivirus Note

Qi-AnXin Tianqing may quarantine ngrok during WinGet install.

Trust locations used during the successful install:

```text
C:\Users\10265696\AppData\Local\Temp\WinGet\
C:\Users\10265696\AppData\Local\Microsoft\WinGet\
```

Only whitelist these locations if operator/company policy allows it.

## Startup Sequence

### Terminal 1 - Dispatcher Bridge

```powershell
cd D:\dev\projects\jj-ai-dispatcher
.\dispatcher\bridge.ps1
```

Expected:

```text
Listening on http://127.0.0.1:8787/
Task state: idle
```

### Terminal 2 - MCP HTTP Adapter

```powershell
cd D:\dev\projects\jj-ai-dispatcher
npm run mcp:http
```

Expected local endpoints:

```text
http://127.0.0.1:8790/mcp
http://127.0.0.1:8790/sse
http://127.0.0.1:8790/messages
```

### Terminal 3 - ngrok HTTPS Tunnel

```powershell
ngrok http 8790 --host-header="localhost:8790"
```

Expected:

```text
Forwarding https://<ngrok-domain> -> http://localhost:8790
```

## ChatGPT Connector Field Values

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

Expected tools:

- `dispatcher_status`
- `dispatcher_dispatch`
- `dispatcher_latest_result`
- `dispatcher_get_run`

## Smoke Test From ChatGPT

Use:

- `dispatcher_status`
- `dispatcher_latest_result`
- `dispatcher_dispatch` with an explicit approved task

Expected:

- status `ok`
- `taskState` idle before dispatch
- review gate appears before dispatch execution
- latest result returns success after completion

## Result Recovery

Browser-visible postback is optional delivery. It can fail or time out even when execution succeeds.

Execution can continue while Windows is locked if the local worker remains operational. Browser DOM typing and send-button interaction are not lock-screen tolerant, so do not treat a postback timeout as proof of execution failure.

Recovery flow:

1. Confirm the connector still reaches the adapter with `dispatcher_status`.
2. Call `dispatcher_latest_result`.
3. If a task ID is known, call `dispatcher_get_run`.
4. Review the persisted result before dispatching another task.

## Shutdown Sequence

Stop in this order using `Ctrl+C`:

1. ngrok tunnel
2. MCP HTTP adapter
3. Dispatcher bridge

## Safety Warnings

- Never expose `127.0.0.1:8787`.
- Never tunnel raw Dispatcher bridge.
- Expose `8790` adapter only.
- Keep exactly four MCP tools.
- No arbitrary shell/file/Git MCP tools.
- Stop ngrok when not actively testing.
- No Auth is only for controlled feasibility testing.
- Do not commit ngrok tokens or other secrets.
- Do not add scheduler, queue, autonomous loop, or auto-chain behavior.

## Troubleshooting

### ngrok command not found

- Confirm ngrok is installed.
- Reopen the terminal after install.
- Run `ngrok version`.

### ngrok deleted or quarantined by Tianqing

- Qi-AnXin Tianqing may quarantine ngrok during WinGet install.
- Whitelist WinGet temp/package folders only if operator/company policy allows it.

### ngrok auth token missing

- Run:

  ```powershell
  ngrok config add-authtoken <TOKEN>
  ```

- Do not paste the token into repo files, docs, commits, or chat logs.

### ngrok version too old

- Run:

  ```powershell
  ngrok version
  ngrok update
  ```

- ngrok should be `3.20.0` or newer.

### Forbidden / 403 from connector

- Confirm the tunnel command includes:

  ```powershell
  --host-header="localhost:8790"
  ```

- Check ngrok inspector:

  ```text
  http://127.0.0.1:4040
  ```

### Adapter not running

- Start Terminal 2:

  ```powershell
  npm run mcp:http
  ```

### Bridge not running

- Start Terminal 1:

  ```powershell
  .\dispatcher\bridge.ps1
  ```

### ChatGPT connector tool list missing

- Confirm the MCP Server URL ends with `/mcp`.
- Confirm ngrok is forwarding to `http://localhost:8790`.
- Confirm Terminal 2 is still running.
- Confirm expected tools are exactly the approved four.

### Latest result still running

- Run `dispatcher_status`.
- Wait for the task to complete.
- Use `dispatcher_latest_result` again.
- Do not dispatch another task until the latest run is reviewed.

### Browser postback timeout

- Treat the timeout as delivery failure only.
- Use `dispatcher_latest_result` or `dispatcher_get_run` to recover the persisted run result.
- If Windows was locked, unlock first and verify MCP connectivity before retrieval.
