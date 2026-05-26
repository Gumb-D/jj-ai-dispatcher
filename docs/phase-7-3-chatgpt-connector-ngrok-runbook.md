# Phase 7.3 ChatGPT Connector ngrok Runbook

## Purpose

This runbook records the confirmed working startup procedure for connecting ChatGPT custom MCP connector feasibility testing to the local JJ Dispatcher MCP HTTP adapter through ngrok.

This is a controlled feasibility procedure. It does not authorize production exposure, new MCP tools, authentication changes, auto-dispatch, auto-review, queueing, scheduling, autonomous loops, or raw Dispatcher bridge exposure.

## Confirmed Working Command

```powershell
ngrok http 8790 --host-header="localhost:8790"
```

Why this is required:

- ChatGPT reaches the ngrok HTTPS URL.
- ngrok forwards traffic to the local MCP HTTP adapter.
- the Host header rewrite avoids forbidden or host mismatch behavior from the localhost-protected MCP adapter.

Without `--host-header="localhost:8790"`, connector creation failed or ngrok showed forbidden behavior.

## Exact Startup Sequence

Terminal 1:

```powershell
cd D:\dev\projects\jj-ai-dispatcher
npm run mcp:http
```

Terminal 2:

```powershell
ngrok http 8790 --host-header="localhost:8790"
```

Local MCP adapter:

```text
http://127.0.0.1:8790/mcp
```

Public MCP endpoint pattern:

```text
https://<ngrok-domain>/mcp
```

## ChatGPT Connector Fields

Name:

```text
JJ Dispatcher MCP
```

Description:

```text
Controlled dispatcher MCP. Four approved tools only.
```

MCP Server URL:

```text
https://<ngrok-domain>/mcp
```

Authentication:

```text
No Auth
```

No Auth is only for controlled feasibility testing.

## Expected Success

ngrok should show successful MCP traffic such as:

```text
GET /mcp 200 OK
POST /mcp 200 OK
POST /mcp 202 Accepted
```

## Expected Tools

ChatGPT should see exactly:

- `dispatcher_status`
- `dispatcher_dispatch`
- `dispatcher_latest_result`
- `dispatcher_get_run`

No extra tools are approved.

## Safety Warnings

- expose port `8790` only
- never expose `8787`
- expose `8790` adapter only
- never tunnel raw Dispatcher bridge
- keep No Auth only for controlled feasibility testing
- stop ngrok after use
- no extra MCP tools
- do not add tools beyond the approved four
- do not remove Dispatcher bridge token protection
- do not store or commit ngrok tokens
- do not use this as unattended production operation

## Troubleshooting

- ngrok auth token may be required before tunnels work.
- ngrok version must be `3.20.0` or newer.
- Qi-AnXin Tianqing may quarantine ngrok; whitelist WinGet temp/package folders only if approved.
- if forbidden occurs, confirm `--host-header="localhost:8790"` is present.
- check ngrok inspector at:

  ```text
  http://127.0.0.1:4040
  ```

## Stop Conditions

Stop immediately if:

- ngrok is forwarding anything other than port `8790`
- `127.0.0.1:8787` is exposed
- extra MCP tools appear
- token or credential material appears in logs
- ChatGPT triggers unexpected dispatch behavior
- review gate is bypassed

After testing, stop ngrok and stop the local MCP HTTP adapter.
