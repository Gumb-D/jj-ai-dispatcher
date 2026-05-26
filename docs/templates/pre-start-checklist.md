# Pre-Start Checklist

Use this checklist before daily Dispatcher / MCP / Codex operator work.

## Environment

- [ ] Repository is clean, or all existing changes are understood.
- [ ] `npm run build` passes.
- [ ] `npm run mcp:smoke` passes.
- [ ] Bridge is healthy.
- [ ] Approved tool list is unchanged.
- [ ] Dispatcher task state is idle before new dispatch.

Approved MCP tools:

- `dispatcher_status`
- `dispatcher_dispatch`
- `dispatcher_latest_result`
- `dispatcher_get_run`

## Security

- [ ] Bridge token is configured.
- [ ] Bridge token is not printed, pasted, committed, or exposed.
- [ ] No tunnel is active.
- [ ] No public listener is active.
- [ ] Bridge remains localhost-only.
- [ ] MCP remains stdio-only.

## Commands

Run from the repository root:

```powershell
git status --short
npm run build
npm run mcp:smoke
.\scripts\bridge-status.ps1
```

## Operator Notes

```text
Date:
Operator:
Repo state:
Bridge state:
Tool list confirmed:
Notes:
```
