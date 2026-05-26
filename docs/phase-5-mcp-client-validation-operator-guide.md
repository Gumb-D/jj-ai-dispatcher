# Phase 5.5 MCP Client Validation Operator Guide

## Purpose

Phase 5.5 validates the existing minimal MCP server skeleton from Phase 5.4. This phase is documentation and operator validation only.

The goal is to confirm that a local MCP client can launch the Node.js stdio server, see the approved Dispatcher tools, call read-only result tools, and preserve the existing Dispatcher approval and review loop.

This phase does not expand MCP functionality.

## Baseline

Phase 5.5 starts from:

- Phase 5.4 commit: `abfbee0`
- Runtime: Node.js
- Transport: stdio only
- MCP server entry point: `mcp/server/index.js`
- MCP remains a thin adapter over the existing Local Dispatcher Bridge

Only four MCP tools are in scope:

- `dispatcher_status`
- `dispatcher_dispatch`
- `dispatcher_latest_result`
- `dispatcher_get_run`

No other tool surface is approved.

## Preconditions

Before validating an MCP client:

- The Local Dispatcher Bridge must be running on `127.0.0.1`.
- `dispatcher/config.local.json` must exist locally.
- `bridge.enabled` must be `true`.
- `bridge.host` must be `127.0.0.1`.
- `bridge.requireToken` should remain `true`.
- A local bridge token must be configured in `dispatcher/config.local.json` or supplied through `JJ_DISPATCHER_BRIDGE_TOKEN`.
- Dependencies must be installed with `npm install` if `node_modules/` is not present.
- No tunnel, reverse proxy, port forwarding, public listener, or remote exposure should be active.

Token rules:

- Do not paste the real token into ChatGPT.
- Do not commit the real token.
- Do not add the token to docs, prompts, scripts, or result artifacts.
- Treat token-related failures as local operator issues.

## Start Commands

Run commands from the repository root:

```powershell
cd D:\dev\projects\jj-ai-dispatcher
```

Install dependencies if needed:

```powershell
npm install
```

Check the MCP server JavaScript files:

```powershell
npm run build
```

Start the Local Dispatcher Bridge in one terminal:

```powershell
.\dispatcher\bridge.ps1
```

Expected bridge output includes:

```text
[bridge] Listening on http://127.0.0.1:8787/
[bridge] Task state: idle
```

Run the MCP server directly for local stdio validation:

```powershell
npm run mcp:start
```

When started directly, the MCP server waits for MCP protocol messages on stdin and writes protocol messages to stdout. It should not print startup banners to stdout.

For a real MCP client, configure the client to launch:

```text
node mcp/server/index.js
```

The working directory should be the repository root.

## Smoke Test Checklist

Use this checklist with an MCP client that can launch local stdio servers.

### Tool Registration Check

Confirm the MCP client lists exactly these Dispatcher tools:

- `dispatcher_status`
- `dispatcher_dispatch`
- `dispatcher_latest_result`
- `dispatcher_get_run`

Fail validation if extra tools appear, especially tools for shell, files, Git, tunnels, remote access, credentials, or editor control.

### `dispatcher_status` Call

Call:

```json
{}
```

Expected result:

- `status` is `ok`.
- `bridgeEnabled` is `true`.
- `taskState` is visible.
- No bridge token is returned.

If `taskState` is `running`, do not dispatch another task.

### `dispatcher_latest_result` Call

Call:

```json
{}
```

Expected result:

- Latest Dispatcher result is returned, or a safe bridge `not_found` style response appears if no run exists.
- No token or local config body is returned.
- Result fields should come from the existing bridge result contract.

If a task is still running, `/runs/latest` may not exist yet. Poll `dispatcher_status` until `taskState = idle`, then retry.

### `dispatcher_get_run` Call

Use a `taskId` from `dispatcher_latest_result` or from a known run directory.

Call:

```json
{
  "taskId": "20260526-031500-a1b2c3d4"
}
```

Expected result:

- The specific Dispatcher run result is returned.
- Malformed task IDs are rejected.
- Path traversal, URL-like values, `.` and `..` must not be accepted.
- No arbitrary file read behavior is exposed.

### `dispatcher_dispatch` Approval Expectation

`dispatcher_dispatch` starts one local Dispatcher task and must require explicit MCP client approval before the bridge call.

Required input fields:

```json
{
  "repo": "self",
  "worker": "codex",
  "task": "Describe the exact task.",
  "commitMessage": "docs: describe change",
  "scope": [
    "docs/"
  ],
  "blocked": [
    "dispatcher/",
    "scripts/",
    "mcp/server/",
    "mcp/tools/"
  ],
  "validation": [
    "git diff --check"
  ],
  "expectedOutput": [
    "One committed documentation update."
  ]
}
```

Before approving, the operator should verify:

- Target repo is expected.
- Worker is `codex`.
- Task is narrow and understandable.
- Commit message matches the task.
- Scope is explicit.
- Blocked list protects safety-sensitive files.
- Validation is realistic.
- Expected output is concrete.
- The bridge is idle.

After approval, the dispatch response only means the task was accepted or rejected by the bridge. It is not the final run result.

## Safety Validation

During client validation, confirm:

- The bridge token is not printed by the MCP server.
- The bridge token is not returned in MCP tool output.
- The MCP server exposes no arbitrary shell tool.
- The MCP server exposes no arbitrary file read tool.
- The MCP server exposes no arbitrary file write tool.
- The MCP server exposes no Git command tool.
- The MCP server starts no public listener.
- The MCP server uses stdio only for MCP transport.
- The MCP server does not create tunnels or remote endpoints.
- The MCP server does not auto-chain dispatches.
- `dispatcher_dispatch` remains approval-gated by the MCP client.

Validation fails if the MCP client, MCP server, or operator workflow bypasses Dispatcher review.

## Failure Troubleshooting

### Bridge Unavailable

Symptoms:

- `dispatcher_status` returns `bridge_unavailable`.
- Client tool call fails with connection refused.
- No bridge listener output is visible.

Fix:

- Start `.\dispatcher\bridge.ps1`.
- Confirm `bridge.enabled = true`.
- Confirm the bridge listens on `http://127.0.0.1:8787/`.
- Confirm no other process is using the configured port.

### Invalid Token

Symptoms:

- Tool result reports `authentication_error`.
- Direct bridge calls return HTTP `401` or `403`.

Fix:

- Confirm `bridge.requireToken`.
- Confirm the local token in `dispatcher/config.local.json`.
- If using `JJ_DISPATCHER_BRIDGE_TOKEN`, confirm it matches the running bridge.
- Do not print or paste the token into ChatGPT or documentation.

### NPM Dependency Missing

Symptoms:

- `npm run mcp:start` fails to import `@modelcontextprotocol/sdk`.
- MCP client cannot start `node mcp/server/index.js`.

Fix:

```powershell
npm install
npm run build
```

If install fails, verify Node.js and npm are available:

```powershell
node --version
npm --version
```

### Malformed Response

Symptoms:

- Tool result reports `malformed_response`.
- Bridge returns non-JSON output or unexpected content.

Fix:

- Confirm the MCP server is calling the existing Local Dispatcher Bridge, not a different local service.
- Restart the bridge.
- Validate bridge endpoints with the existing local operator guide.
- Do not modify bridge behavior as part of Phase 5.5 validation.

### Client Cannot Connect To Stdio Server

Symptoms:

- MCP client cannot launch the server process.
- Client times out before tool listing.
- Client reports invalid stdio protocol output.

Fix:

- Confirm the client command is `node`.
- Confirm the client args are `mcp/server/index.js`.
- Confirm the working directory is the repository root.
- Run `npm run build`.
- Ensure no wrapper script prints banners to stdout.
- Keep diagnostics on stderr only.

## Review Gate

Every dispatch must follow the Dispatcher review loop before the next dispatch.

After `dispatcher_dispatch`:

1. Call `dispatcher_status` until `taskState = idle`.
2. Call `dispatcher_latest_result`.
3. Inspect the returned `taskId`, `status`, `repo`, `worker`, `filesChanged`, `commit`, `pushed`, `workingTreeClean`, `summary`, `needsReview`, and `reviewHints`.
4. Use `docs/operator-run-review-template.md` for the human review.
5. Decide whether to accept the result, request a follow-up fix, stop and investigate, or perform manual rollback review.

ChatGPT and the human operator must review each result before any next dispatch. MCP client convenience must not become auto-chain execution.

## Next Phase Recommendation

Proceed to Phase 5.6 only after this operator guide has been validated with a real local MCP client.

Recommended Phase 5.6 focus:

- Long prompt handling.
- File-task mode design.
- Dispatcher-controlled task inbox boundaries.
- Maximum inline task size.
- Continued local-only operation with no tunnels or remote exposure.

Phase 5.6 should remain a design step unless a later task explicitly approves implementation.
