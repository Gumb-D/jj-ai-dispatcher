# Phase 5.7A MCP Test Harness

## Purpose

Phase 5.7A adds a repeatable smoke harness for the existing MCP stdio server. It replaces part of the manual operator smoke check with a small scripted validation of the current MCP boundary.

The harness validates only the approved Phase 5 MCP surface:

- `dispatcher_status`
- `dispatcher_dispatch`
- `dispatcher_latest_result`
- `dispatcher_get_run`

## Command

Run from the repository root:

```powershell
.\scripts\mcp-smoke.ps1
```

Equivalent npm command:

```powershell
npm run mcp:smoke
```

The Local Dispatcher Bridge must already be reachable on `127.0.0.1` using the existing local configuration.

## Expected PASS Output

Example successful output:

```text
PASS npm build
PASS mcp stdio connect
PASS tool registration - dispatcher_status, dispatcher_dispatch, dispatcher_latest_result, dispatcher_get_run
PASS dispatcher_status - taskState=idle
PASS dispatcher_latest_result - latest run present
PASS mcp smoke complete
```

If no latest run exists, the latest-result check may pass with:

```text
PASS dispatcher_latest_result - no latest run available
```

## Failure Behavior

The harness prints concise `FAIL` output and exits non-zero if:

- `npm run build` fails.
- The MCP stdio server cannot start.
- The registered MCP tools are not exactly the four approved dispatcher tools.
- Any forbidden tool name is registered.
- `dispatcher_status` cannot reach the bridge or does not report `status: ok`.
- `dispatcher_latest_result` returns neither a latest run nor the expected no-run state.
- A read-only tool response exposes a `token` field.

## Safety Boundaries

The harness does not add or register MCP tools. It starts the existing MCP server over stdio and calls only read-only tools:

- `dispatcher_status`
- `dispatcher_latest_result`

It checks that these forbidden tool names are absent:

- `arbitrary_shell`
- `arbitrary_file_read`
- `arbitrary_file_write`
- `delete`
- `push`
- `tunnel_enable`
- `remote_exec`
- `vscode_ui_control`
- `credential_read`
- `config_write`

The harness does not print bridge tokens, local config bodies, or raw MCP server diagnostics.

## What This Harness Does Not Test

- It does not execute `dispatcher_dispatch`.
- It does not perform a full human review-gated dispatch workflow.
- It does not validate worker-side code changes.
- It does not test tunnels, remote bridges, public endpoints, arbitrary shell access, arbitrary file access, direct Git tools, or editor control.
- It does not replace the operator validation guide; it is a repeatable smoke check for the MCP registration and read-only bridge path.
