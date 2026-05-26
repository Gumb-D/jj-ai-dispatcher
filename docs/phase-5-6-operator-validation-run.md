# Phase 5.6 Operator Validation Run

## Validation Metadata

- Date/time: 2026-05-26T20:24:32+08:00 through 2026-05-26T20:33+08:00
- Repository: `D:\dev\projects\jj-ai-dispatcher`
- Operator phase: Phase 5.6 - Operator Validation Run
- Guide used: `docs/phase-5-mcp-client-validation-operator-guide.md`
- Result: PASS, with one non-blocking bridge startup observation

## Commands Executed

```powershell
git status --short
pwsh -NoProfile -ExecutionPolicy Bypass -File .\dispatcher\run.ps1 env_check
.\dispatcher\bridge.ps1
.\scripts\bridge-status.ps1
.\scripts\bridge-latest.ps1
Get-NetTCPConnection -LocalAddress 127.0.0.1 -LocalPort 8787 -ErrorAction SilentlyContinue | Select-Object LocalAddress,LocalPort,State,OwningProcess
npm install
npm run build
@'
import { Client } from "@modelcontextprotocol/sdk/client/index.js";
import { StdioClientTransport } from "@modelcontextprotocol/sdk/client/stdio.js";

const client = new Client({ name: "phase-5-6-validation", version: "1.0.0" }, { capabilities: {} });
const transport = new StdioClientTransport({
  command: "node",
  args: ["mcp/server/index.js"],
  cwd: process.cwd(),
  stderr: "pipe"
});

await client.connect(transport);
await client.listTools();
await client.callTool({ name: "dispatcher_status", arguments: {} });
await client.callTool({ name: "dispatcher_latest_result", arguments: {} });
await client.callTool({ name: "dispatcher_get_run", arguments: { taskId: "20260526-032536-0c7a30bb" } });
await client.callTool({ name: "dispatcher_get_run", arguments: { taskId: "../bad" } });
await client.close();
'@ | node --input-type=module
Get-Content -Raw .\mcp\server\bridgeClient.js
Get-Content -Raw .\mcp\config\loadConfig.js
Get-Content -Raw .\mcp\tools\schemas.js
Get-Process -ErrorAction SilentlyContinue | Where-Object { @('ngrok','cloudflared','ssh','tailscale','warp','localtunnel','lt') -contains $_.ProcessName.ToLowerInvariant() } | Select-Object ProcessName,Id,Path
Get-NetTCPConnection -State Listen | Where-Object { $_.LocalPort -eq 8787 -or $_.LocalAddress -in @('0.0.0.0','::') } | Select-Object LocalAddress,LocalPort,State,OwningProcess
```

## Check Results

| Check | Result | Observed output summary |
| --- | --- | --- |
| Repository status | PASS | Initial `git status --short` returned no output. Working tree was clean before the validation document was created. |
| Dispatcher environment | PASS | `env_check` exited 0. Config loaded, default repo exists and is a git repo, git is available, configured workers resolve, and required scripts exist. |
| Local bridge start/confirm | PASS with non-blocking observation | `.\dispatcher\bridge.ps1` could not start a second listener because `http://127.0.0.1:8787/` was already registered. Existing bridge was confirmed by helper scripts. |
| Bridge status helper | PASS | `bridge-status.ps1` returned `status: ok`, `bridgeEnabled: True`, `taskState: idle`, `defaultWorker: codex`, and `autoPush: False`. |
| Bridge latest helper | PASS | `bridge-latest.ps1` returned prior run `20260526-032536-0c7a30bb` with `status: success`, `worker: codex`, `filesChanged: {}`, `workingTreeClean: True`, and `pushed: False`. |
| MCP package install | PASS | `npm install` reported packages up to date, audited 93 packages, and 0 vulnerabilities. |
| MCP package build | PASS | `npm run build` completed all `node --check` validations for MCP server, config, bridge client, errors, tools, and schemas. |
| MCP tool registration | PASS | MCP stdio client listed exactly `dispatcher_status`, `dispatcher_dispatch`, `dispatcher_latest_result`, and `dispatcher_get_run`. No extra MCP tools were registered. |
| `dispatcher_status` read-only call | PASS | MCP stdio call returned `status: ok`, `bridgeEnabled: true`, `taskState: idle`, `dispatcherRoot: D:\dev\projects\jj-ai-dispatcher`, and no token. |
| `dispatcher_latest_result` read-only call | PASS | MCP stdio call returned the latest result for `20260526-032536-0c7a30bb`; no token or config body was returned. |
| `dispatcher_get_run` valid call | PASS | MCP stdio call for `20260526-032536-0c7a30bb` returned the expected specific run result. |
| `dispatcher_get_run` invalid call | PASS | MCP stdio call with `../bad` was rejected by input validation with the task ID regex; no arbitrary file read behavior was exposed. |
| Token handling | PASS | Console output, MCP tool output, and captured MCP server stderr did not print a token. Code review confirmed the token is used only as the `X-Dispatcher-Token` request header. |
| No arbitrary shell/file/Git MCP tools | PASS | Tool registration exposed only the four dispatcher tools. No shell, file read, file write, or direct Git MCP tools were present. |
| No public MCP/bridge listener | PASS | MCP server used stdio. Bridge config enforces `127.0.0.1`, and the bridge listener was observed on `127.0.0.1:8787`. System-wide public listeners existed, but none were identified as MCP or Dispatcher listeners. |
| No tunnel | PASS | No common tunnel processes (`ngrok`, `cloudflared`, `tailscale`, `localtunnel`, etc.) were observed during validation. No MCP code path creates a tunnel or remote endpoint. |
| Dispatch review gate | PASS | `dispatcher_dispatch` was registered with `destructiveHint: true` and `openWorldHint: false`, requires explicit structured input, restricts `worker` to `codex`, restricts `repo` to `self`, and blocks terms for public tunnels, reverse proxies, remote endpoints, auto-chain behavior, shell execution, and direct Git. No dispatch was executed during this validation run. |

## Issues Found

| Issue | Severity | Blocking? | Notes |
| --- | --- | --- | --- |
| Starting `.\dispatcher\bridge.ps1` failed because `http://127.0.0.1:8787/` was already registered. | Low | No | Existing bridge responded correctly to `bridge-status.ps1`, `bridge-latest.ps1`, and MCP read-only calls. This is expected when the bridge is already running. |
| System-wide listen check showed unrelated `0.0.0.0`/`::` listeners. | Low | No | The MCP server uses stdio and the Dispatcher bridge was confirmed on `127.0.0.1:8787`. These listeners were not attributed to this project. |

## Safety Notes

- No bridge token appeared in observed logs or MCP outputs.
- No arbitrary shell, arbitrary file read/write, direct Git, tunnel, remote bridge, public endpoint, or expanded MCP tool was added.
- No feature implementation or architecture change was performed.
- `dispatcher_dispatch` was not invoked because this validation scope focused on registration, read-only behavior, and safety boundaries.

## Remaining Manual Work

None required for this validation run. The bridge was already running and reachable locally, so read-only MCP behavior was fully validated through stdio.

## Final Recommendation for Phase 5.7

Proceed to Phase 5.7. Keep the MCP boundary unchanged: stdio-only, local bridge only, exactly four tools, and dispatch only through explicit operator/client approval followed by the existing Dispatcher review loop.
