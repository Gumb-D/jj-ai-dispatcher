# Phase 7.2 HTTP/SSE MCP Adapter

## Purpose

Phase 7.2 adds a first local HTTP/SSE MCP transport adapter for the existing JJ Dispatcher MCP tool surface.

This addresses the ChatGPT connector transport mismatch:

- current JJ Dispatcher MCP: local stdio MCP plus protected localhost bridge
- ChatGPT custom connector: MCP Server URL using HTTPS/SSE or streamable HTTP style transport

This adapter is local feasibility infrastructure only. It does not expose the Dispatcher bridge publicly.

Confirmed connector finding:

- ChatGPT can reach this adapter through an HTTPS ngrok URL when ngrok rewrites the Host header to the local adapter host.
- The working public MCP endpoint pattern is `https://<ngrok-domain>/mcp`.
- The local MCP adapter remains `http://127.0.0.1:8790/mcp`.
- This remains controlled feasibility testing, not production exposure.

## Local Start

Start the local HTTP adapter:

```powershell
npm run mcp:http
```

Equivalent script:

```powershell
.\scripts\mcp-http.ps1
```

Default local URLs:

```text
http://127.0.0.1:8790/mcp
http://127.0.0.1:8790/sse
http://127.0.0.1:8790/messages
```

The `/mcp` endpoint is the primary Streamable HTTP MCP endpoint. The `/sse` and `/messages` endpoints are legacy HTTP+SSE compatibility endpoints.

## Local Smoke

Run:

```powershell
npm run mcp:http:smoke
```

The smoke test verifies:

- adapter starts locally
- tool list is exactly:
  - `dispatcher_status`
  - `dispatcher_dispatch`
  - `dispatcher_latest_result`
  - `dispatcher_get_run`
- no extra tools appear
- `dispatcher_status` can be called without modifying the repo
- `dispatcher_latest_result` can be called without modifying the repo
- `dispatcher_dispatch` rejects a non-explicit invalid payload
- protected local bridge config still requires the bridge token

## Safety Boundary

The adapter preserves the existing Dispatcher safety model:

- localhost binding by default
- protected Dispatcher bridge remains token guarded
- exactly four approved MCP tools
- explicit dispatch only
- review gate preserved
- no arbitrary shell execution
- no arbitrary file read/write
- no direct Git tools
- no scheduler
- no queue
- no autonomous loop
- no auto-chain

The adapter supports No Auth only for local feasibility testing. It is not a public production endpoint.

## Public Exposure Warning

ChatGPT requires an HTTPS MCP Server URL. The default local adapter URL is HTTP localhost and is not directly usable by ChatGPT.

Confirmed feasibility command:

```powershell
ngrok http 8790 --host-header="localhost:8790"
```

Why this works:

- ChatGPT reaches the ngrok HTTPS URL.
- ngrok forwards `/mcp` traffic to the local MCP HTTP adapter on port `8790`.
- the Host header rewrite avoids forbidden or host mismatch behavior from the localhost-protected MCP adapter.

Do not tunnel raw Dispatcher bridge.

Do not expose `127.0.0.1:8787` publicly.

Expose port `8790` only for controlled feasibility testing, and stop ngrok after the test.

Do not expose this adapter broadly until an HTTPS exposure strategy, authentication policy, and operator go/no-go review are completed.

## Remaining Work Before ChatGPT Connector Use

Before pasting any URL into ChatGPT Connector:

- verify exact ChatGPT MCP transport expectations
- decide whether ChatGPT requires Streamable HTTP, legacy SSE, or both
- use the reviewed ngrok host-header procedure for feasibility only
- design durable reviewed HTTPS exposure for any longer-lived use
- decide authentication requirements
- preserve bridge token protection
- avoid exposing the raw Dispatcher bridge
- validate the connector manually with operator oversight
- complete security review and operator go/no-go

## Operator Runbook

See:

```text
docs/phase-7-3-chatgpt-connector-ngrok-runbook.md
```
