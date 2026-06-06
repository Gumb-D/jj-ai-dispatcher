# Test Baseline

The P3.3 test baseline uses only built-in Node and PowerShell capabilities plus the repository npm scripts. Existing validation scripts remain the source of coverage; this document defines the standard operator-facing command split.

## Standard Commands

Automated baseline:

```powershell
npm test
```

`npm test` is the standard top-level command. It runs the required automated baseline in this order:

```powershell
npm run test:unit
npm run test:integration
npm run smoke:local
```

Run layers individually when isolating failures:

```powershell
npm run test:unit
npm run test:integration
npm run smoke:local
```

MCP smoke and syntax/build checks are operator-facing commands, but they are distinguished from the `npm test` baseline:

```powershell
npm run mcp:smoke
npm run build
npm run mcp:http:smoke
git diff --check
```

`npm run test:smoke` remains as a compatibility alias for `npm run smoke:local`.

## Command Layers

| Layer | Command | Expected output |
| --- | --- | --- |
| Unit contracts | `npm run test:unit` | `PASS result contract validation` and `PASS mcp contract validation`. |
| Integration | `npm run test:integration` | `PASS delivery state checks`, `PASS result retrieval checks`, `PASS dispatcher lifecycle checks`, then `PASS integration checks`. |
| Local smoke | `npm run smoke:local` | In-process tool registration/status/result checks ending with `PASS mcp smoke complete`. |
| Top-level baseline | `npm test` | Unit, integration, and local smoke output in order. |
| MCP smoke | `npm run mcp:smoke` | Runs `npm run build`, then the same in-process MCP smoke checks. |
| Syntax/build | `npm run build` | `node --check` completes for MCP server and validation scripts. |
| HTTP adapter smoke | `npm run mcp:http:smoke` | Builds, starts the MCP HTTP adapter on an ephemeral `127.0.0.1` port, verifies the approved tool list, rejects an invalid dispatch payload, and stops the adapter. |
| Whitespace check | `git diff --check` | No whitespace errors. |

## Coverage Matrix

| Area | Automated coverage |
| --- | --- |
| Safety validation | `scripts/validate-mcp-contract.mjs` rejects empty tasks, invalid workers, unsafe dispatch text, and missing required MCP safety fields. |
| Lifecycle | `scripts/test-dispatcher-lifecycle.ps1` covers success, worker failure, no-change runs, commit failure, disabled auto-push, explicitly enabled fake-Git push, and `workingTreeClean` accuracy. |
| Execution and delivery separation | `scripts/validate-result-contract.mjs` and `scripts/test-delivery-state.ps1` cover success with delivered, timeout, and unavailable delivery, plus execution failure not being overwritten by delivery failure. |
| Retrieval | `scripts/test-result-retrieval.ps1` covers latest-result selection, exact get-run lookup, missing-task errors, persisted timeout result retrieval, old result compatibility, restart-style reload, and malformed or mismatched result rejection. |
| Git | `scripts/test-dispatcher-lifecycle.ps1` uses temporary repositories and fake Git where needed to verify Dispatcher-owned commit behavior and push boundaries without touching a real remote. |
| Bridge | `scripts/mcp-smoke.mjs`, `scripts/mcp-http-smoke.mjs`, and `scripts/validate-mcp-contract.mjs` cover bridge status shape, token/header behavior, safe bridge error conversion, and no token leakage in tool output. |
| MCP contracts | `scripts/mcp-smoke.mjs`, `scripts/mcp-http-smoke.mjs`, and `scripts/validate-mcp-contract.mjs` assert exactly the four approved tools: `dispatcher_status`, `dispatcher_dispatch`, `dispatcher_latest_result`, and `dispatcher_get_run`. They also assert forbidden arbitrary shell, file, Git, tunnel, remote exec, UI control, credential, and config write tools are absent. |

## Isolation Guarantees

The automated baseline does not push to real remotes, expose Dispatcher Bridge port `8787`, require committed secrets, run browser UI automation, start a scheduler, or create autonomous chains.

Delivery-state and result-retrieval tests create run artifacts under temporary directories. Dispatcher lifecycle tests copy the minimal dispatcher fixture into a temporary directory and run against temporary Git repositories. They do not write production `dispatcher/inbox`, `dispatcher/logs`, or `dispatcher/runs`.

The lifecycle auto-push case uses fake Git and a temporary marker file only. `npm run mcp:http:smoke` binds the MCP HTTP adapter to an ephemeral `127.0.0.1` port; it does not bind or tunnel raw bridge port `8787`.

## Manual Environment Validations

Manual browser validations remain separate from the automated baseline:

```text
Manual environment validation:
- unlocked browser postback
- Windows lock-screen postback timeout
- result recovery after unlock
```

These cases validate the operator environment and browser delivery path. They do not replace automated execution, persistence, retrieval, safety, Git, bridge, or MCP contract tests. A browser postback timeout should be recorded as delivery behavior, then the persisted result should be recovered through `dispatcher_status`, `dispatcher_latest_result`, or `dispatcher_get_run`.

## Troubleshooting

If `npm run test:unit` fails, inspect the named contract assertion first. These checks are fast and usually indicate schema, status-field, safety-field, token, or approved-tool-surface drift.

If `npm run test:integration` fails, rerun the failing script named after `== integration: ... ==`. Integration failures should leave their temporary paths in the error output when cleanup could not complete.

If `npm run smoke:local` or `npm run mcp:smoke` fails with a bridge error, confirm the local Dispatcher Bridge is configured and reachable according to the operator runbook. A `404` no-latest-result response is acceptable when no completed run exists.

If `npm run mcp:http:smoke` fails to start, confirm no local policy is blocking Node from binding an ephemeral localhost port and that `bridge.requireToken` remains enabled in local config. Do not switch the smoke test to public host binding.

If `git diff --check` fails, fix only the reported whitespace lines.

## Known Exclusions

The automated baseline does not cover browser DOM typing, ChatGPT page behavior, Windows lock-screen browser interaction, public HTTPS tunnel behavior, real remote push, distributed execution, scheduling, cancellation, or invalid terminal execution transitions. Cancellation and terminal transition validation remain excluded because the current approved runtime has no public cancel or transition API.
