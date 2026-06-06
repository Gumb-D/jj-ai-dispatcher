# Test Baseline

The P3.1 baseline uses only built-in Node and PowerShell capabilities. Existing validation scripts remain the source of the current coverage, and npm scripts provide the standard command framework.

## Commands

```powershell
npm test
npm run test:unit
npm run test:integration
npm run test:smoke
npm run mcp:smoke
```

`npm test` is the standard top-level command and runs unit, integration, and smoke layers in that order.

## Layers

- Unit: `npm run test:unit` runs `scripts/validate-result-contract.mjs` and `scripts/validate-mcp-contract.mjs`.
- Integration: `npm run test:integration` runs `scripts/test-integration.ps1`, which orchestrates delivery-state, result-retrieval, and dispatcher lifecycle validations.
- Smoke: `npm run test:smoke` runs the in-process MCP smoke check.
- Manual: browser lock-screen typing remains environment validation, not automated coverage.

## Isolation

The delivery-state and result-retrieval scripts create run artifacts under temporary directories. The dispatcher lifecycle script now copies the minimal dispatcher fixture into a temporary directory and runs against temporary Git repositories, so it does not write production `dispatcher/inbox`, `dispatcher/logs`, or `dispatcher/runs`.

The automated tests do not request a real push, do not expose bridge port `8787`, and do not require real secrets. HTTP adapter smoke remains available separately through `npm run mcp:http:smoke`; it binds an ephemeral `127.0.0.1` port for the MCP adapter, not the dispatcher bridge.

## P3.2 Coverage Matrix

| Area | Automated coverage |
| --- | --- |
| Safety validation | `scripts/validate-mcp-contract.mjs` rejects empty tasks, invalid workers, unsafe dispatch text, and missing required MCP safety fields. |
| MCP boundary | `scripts/validate-mcp-contract.mjs` and `scripts/mcp-smoke.mjs` assert exactly the four approved tools and no arbitrary shell/file/Git API. |
| Auth/token behavior | `scripts/validate-mcp-contract.mjs` uses temporary config and ephemeral localhost HTTP servers to verify config token loading, environment token override, missing-token rejection, token header use, and safe 403 conversion. |
| Execution and delivery separation | `scripts/validate-result-contract.mjs` and `scripts/test-delivery-state.ps1` cover success with delivered, timeout, and unavailable delivery, and failure not overwritten by delivery failure. |
| Retrieval and persistence | `scripts/test-result-retrieval.ps1` covers latest-result selection, exact get-run lookup, safe missing-task errors, persisted timeout result retrieval, old result compatibility, restart-style reload, and malformed/mismatched result rejection. |
| Dispatcher Git lifecycle | `scripts/test-dispatcher-lifecycle.ps1` covers dispatcher-owned commits, no-change runs, commit failure reporting, auto-push disabled, explicitly enabled auto-push through fake Git only, and `workingTreeClean` accuracy in temporary repositories. |
| Bridge status and schema contracts | `scripts/mcp-smoke.mjs`, `scripts/validate-mcp-contract.mjs`, and `scripts/validate-result-contract.mjs` cover status shape, safe error conversion, tool result formatting, and result schema compatibility. |
| Exclusions | No automated cancellation or invalid execution terminal transition test exists because there is no public cancel or execution transition API in the current runtime. Browser lock-screen typing remains manual environment validation. |
