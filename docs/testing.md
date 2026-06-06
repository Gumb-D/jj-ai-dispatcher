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

- Unit: `npm run test:unit` runs `scripts/validate-result-contract.mjs`.
- Integration: `npm run test:integration` runs `scripts/test-integration.ps1`, which orchestrates delivery-state, result-retrieval, and dispatcher lifecycle validations.
- Smoke: `npm run test:smoke` runs the in-process MCP smoke check.
- Manual: browser lock-screen typing remains environment validation, not automated coverage.

## Isolation

The delivery-state and result-retrieval scripts create run artifacts under temporary directories. The dispatcher lifecycle script now copies the minimal dispatcher fixture into a temporary directory and runs against temporary Git repositories, so it does not write production `dispatcher/inbox`, `dispatcher/logs`, or `dispatcher/runs`.

The automated tests do not request a real push, do not expose bridge port `8787`, and do not require real secrets. HTTP adapter smoke remains available separately through `npm run mcp:http:smoke`; it binds an ephemeral `127.0.0.1` port for the MCP adapter, not the dispatcher bridge.
