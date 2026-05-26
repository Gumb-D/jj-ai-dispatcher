# Phase 7.2 HTTP/SSE MCP Adapter

## Purpose

Phase 7.2 adds a first local HTTP/SSE MCP transport adapter for the existing JJ Dispatcher MCP tool surface.

This addresses the ChatGPT connector transport mismatch:

- current JJ Dispatcher MCP: local stdio MCP plus protected localhost bridge
- ChatGPT custom connector: MCP Server URL using HTTPS/SSE or streamable HTTP style transport

This adapter is local feasibility infrastructure only. It does not expose the Dispatcher bridge publicly and does not make the system ready to paste a URL into ChatGPT.

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

Do not tunnel raw Dispatcher bridge.

Do not expose `127.0.0.1:8787` publicly.

Do not expose this adapter publicly until an HTTPS exposure strategy, authentication policy, and operator go/no-go review are completed.

## Remaining Work Before ChatGPT Connector Use

Before pasting any URL into ChatGPT Connector:

- verify exact ChatGPT MCP transport expectations
- decide whether ChatGPT requires Streamable HTTP, legacy SSE, or both
- design reviewed HTTPS exposure
- decide authentication requirements
- preserve bridge token protection
- avoid exposing the raw Dispatcher bridge
- validate the connector manually with operator oversight
- complete security review and operator go/no-go
