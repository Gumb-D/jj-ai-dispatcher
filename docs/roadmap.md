# JJ AI Dispatcher Roadmap

## Current Status Summary

Phase 7.5 is COMPLETE.

The ChatGPT MCP engine is validated end-to-end for controlled feasibility testing, and the daily operations checklist is available.

Still valid from the completed Phase 5 and Phase 6 work:

- Dispatcher remains the local execution controller.
- Local bridge remains valid as the protected Dispatcher access path.
- MCP tool surface remains validated.
- MCP smoke harness remains valid.
- Review gate remains preserved.
- Read-only review helper remains valid.
- Operator remains final acceptance authority.

Approved MCP tools remain exactly:

- `dispatcher_status`
- `dispatcher_dispatch`
- `dispatcher_latest_result`
- `dispatcher_get_run`

## Urgent Issue

ChatGPT can create a custom MCP connector/app.

The real ChatGPT Connector/App settings screen requires an MCP Server URL, such as an HTTPS/SSE or streamable HTTP MCP endpoint.

Current project transport:

- JJ Dispatcher MCP = local stdio MCP server plus localhost bridge
- ChatGPT Connector = remote URL-based MCP endpoint

The current local stdio MCP server cannot be pasted into the ChatGPT connector.

This means the issue is not "MCP unsupported." The issue is a transport mismatch.

Transport compatibility must be fixed before true ChatGPT-to-Dispatcher operation can work.

## Phase 7 - ChatGPT Remote MCP Transport Compatibility

Priority:

```text
IMMEDIATE / URGENT / NEXT
```

Phase 7 is now the highest-priority roadmap item. Do not continue generic documentation work before this transport compatibility issue is addressed.

## Phase 7 Goal

Provide a safe remote MCP transport layer compatible with ChatGPT custom connector while preserving the existing Dispatcher safety model.

## Phase 7 Scope

Phase 7 scope:

- verify exact ChatGPT MCP transport expectations
- design HTTPS/SSE or streamable HTTP MCP adapter
- preserve exactly four approved tools:
  - `dispatcher_status`
  - `dispatcher_dispatch`
  - `dispatcher_latest_result`
  - `dispatcher_get_run`
- preserve explicit dispatch only
- preserve review gate
- preserve token/local Dispatcher bridge protection
- avoid exposing raw localhost bridge directly
- produce operator validation steps for connecting ChatGPT connector

## Phase 7 Non-Goals

Phase 7 does not authorize:

- exposing `127.0.0.1:8787` publicly
- tunneling the raw Dispatcher bridge casually
- removing token protection
- adding arbitrary shell tools
- adding arbitrary file read/write tools
- adding scheduler, queue, autonomous loop, or auto-chain
- expanding beyond four approved MCP tools
- implementing OAuth unless explicitly required after feasibility check

## Phase 7 Proposed Sub-Phases

- 7.0 Connectivity finding record
- 7.1 Remote MCP transport feasibility spike
- 7.2 Transport adapter design and local HTTP/SSE adapter implementation - COMPLETE
- 7.3 ChatGPT connector ngrok runbook with host-header rewrite - COMPLETE
- 7.4 ChatGPT MCP engine startup runbook - COMPLETE
- 7.5 ChatGPT MCP operations checklist - COMPLETE
- 7.6 Security review and operator go/no-go

## Phase 7 Current Operational Status

End-to-end ChatGPT MCP integration has been achieved for controlled feasibility testing.

Validated working chain:

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
local MCP HTTP adapter on 127.0.0.1:8790
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

Validated ngrok command:

```powershell
ngrok http 8790 --host-header="localhost:8790"
```

Operational runbooks:

- `docs/phase-7-3-chatgpt-connector-ngrok-runbook.md`
- `docs/phase-7-4-chatgpt-mcp-engine-startup-runbook.md`
- `docs/phase-7-5-chatgpt-mcp-operations-checklist.md`

Remaining Phase 7 focus:

- keep No Auth limited to controlled feasibility testing
- complete security review and operator go/no-go
- decide any durable HTTPS/auth strategy before broader use

## ADR-0002 ChatGPT MCP Transport Compatibility

Decision:

The project will treat ChatGPT custom MCP support as remote URL-based MCP transport, not local stdio attachment.

Consequence:

Existing stdio MCP work remains useful as tool-surface validation, but a remote-compatible MCP transport adapter is now required.

## Immediate Next Action

Implement Phase 7.0 documentation and feasibility checklist before any tunnel, deployment, or endpoint exposure.

Do not expose a public endpoint, deploy a remote adapter, start a tunnel, or modify MCP transport behavior before Phase 7.0 records the finding and Phase 7.1 verifies exact transport requirements.
