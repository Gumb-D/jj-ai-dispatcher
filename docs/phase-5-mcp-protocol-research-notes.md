# Phase 5.2 MCP Protocol Research Notes

## Purpose

Research how MCP could be implemented locally for JJ AI Dispatcher without violating the Phase 5.1 boundary. The goal is to identify practical local Windows implementation routes while preserving the existing Dispatcher bridge, helper workflow, manual review loop, and safety boundary.

This is a documentation-only research note. It does not implement an MCP server.

## Source Documents

- `docs/phase-5-tool-integration-feasibility.md`
- `docs/phase-5-mcp-boundary-design.md`

## Current Baseline

- Branch baseline: `main @ 249d23a`
- Phase 5 tag: `v0.5-phase5-research-start`
- Phase 5.0 feasibility completed.
- Phase 5.1 boundary completed.
- Local HTTP Bridge already works.
- Allowed future MCP tools:
  - `dispatcher_status`
  - `dispatcher_dispatch`
  - `dispatcher_latest_result`
  - `dispatcher_get_run`

## MCP Concept Summary

At a practical level:

- An MCP server exposes tools.
- An MCP client calls tools.
- Tools map to controlled local actions.
- For JJ AI Dispatcher, tools should only call existing Dispatcher bridge endpoints.

MCP uses structured messages between a client and server. The protocol supports local process transports such as stdio and HTTP-style transports for independent server processes. For this project, MCP should be treated as a thin adapter over the existing bridge, not as a new execution controller.

## Candidate Implementation Runtimes

### A. Node.js MCP Server

Windows compatibility:

- Strong. Node.js is common on Windows and official TypeScript MCP SDK examples target Node.js.

Ease of local install:

- Medium. Requires Node.js, npm, package setup, and build scripts if TypeScript is used.

JSON/schema handling:

- Strong. TypeScript plus schema helpers such as Zod fit tool input validation well.

HTTP call support:

- Strong. Built-in `fetch` in modern Node.js can call the Dispatcher bridge.

Token handling:

- Strong if token is read from local config or environment and never returned through tool output.

Process management:

- Strong for stdio MCP. The MCP client can launch a Node process.

Maintainability:

- Strong if the project accepts a Node dependency and keeps the MCP adapter small.

Fit for JJ Dispatcher:

- Strong. Node.js is a good first candidate for a future MCP skeleton because it has official SDK support, strong schema tooling, and simple HTTP calls.

### B. Python MCP Server

Windows compatibility:

- Strong if Python is installed and pinned.

Ease of local install:

- Medium. Requires Python environment management and package installation.

JSON/schema handling:

- Strong. Python has mature JSON and validation options.

HTTP call support:

- Strong. Standard or common libraries can call the Dispatcher bridge.

Token handling:

- Strong if token loading is explicit and logs are sanitized.

Process management:

- Strong for stdio MCP. The MCP client can launch a Python process.

Maintainability:

- Strong if the repo standardizes a virtual environment or lightweight dependency approach.

Fit for JJ Dispatcher:

- Strong. Python is a practical second candidate if the Python MCP SDK and local packaging experience are simpler for the operator.

### C. PowerShell-Based Wrapper Process

Windows compatibility:

- Excellent. The existing Dispatcher and helper scripts are PowerShell-oriented.

Ease of local install:

- Strong. PowerShell is already in the project workflow.

JSON/schema handling:

- Medium. PowerShell handles JSON, but robust MCP protocol framing, schema validation, and stdio discipline are more awkward than Node or Python.

HTTP call support:

- Strong. `Invoke-RestMethod` already works for bridge calls.

Token handling:

- Medium to strong. Existing helpers already read local config safely, but MCP stdout/stderr discipline would need extra care.

Process management:

- Medium. PowerShell can run as a child process, but MCP message framing over stdio must be precise.

Maintainability:

- Medium. Good for operator helpers; less ideal as the primary MCP protocol server.

Fit for JJ Dispatcher:

- Medium. PowerShell should remain the helper/operator layer unless later research shows a clean, well-supported MCP PowerShell server path.

### D. VSCode Extension-Hosted MCP Bridge

Windows compatibility:

- Strong in the VSCode environment.

Ease of local install:

- Weak to medium. Requires extension packaging, installation, and trust decisions.

JSON/schema handling:

- Strong. Extension code can use TypeScript and JSON schemas.

HTTP call support:

- Strong. Extension code can call local bridge endpoints.

Token handling:

- Medium. Extension logs, settings sync, and workspace trust make secret handling more complex.

Process management:

- Medium. Extension lifecycle is tied to VSCode, which is not the desired control plane.

Maintainability:

- Weak to medium. Adds a new UI and extension surface before the MCP boundary is proven.

Fit for JJ Dispatcher:

- Weak for first MCP implementation. Useful later as an operator UX option, but not the first protocol bridge.

## Recommended Runtime

Preferred route for a future Phase 5.3 design:

1. Node.js MCP server, if local install and official SDK ergonomics are acceptable.
2. Python MCP server, if Python packaging is simpler for the operator environment.

PowerShell should remain the helper/operator layer, not the main MCP server, unless later research shows a robust PowerShell MCP server pattern with clean stdio protocol handling and schema validation.

VSCode extension hosting should not be the first MCP implementation route. It adds editor lifecycle and UI concerns before the local tool boundary is proven.

## MCP Transport Options

### stdio Local MCP Server

- Client launches the MCP server as a local child process.
- Server communicates over stdin/stdout.
- Best first fit for local-only integration.
- Keeps the MCP server off the network.
- Requires strict logging discipline: MCP messages on stdout, logs on stderr only.

Recommendation:

- Preferred for first implementation.

### Local HTTP / Streamable HTTP

- MCP server runs as an independent local HTTP process.
- More flexible for multiple clients and longer-lived sessions.
- Adds another local listener and more network binding concerns.
- Must bind to localhost only if used.

Recommendation:

- Research later after stdio design is complete.

### Remote / Tunnel Transport

- Makes a local capability reachable remotely.
- Conflicts with the current safety boundary.
- Adds token, auth, endpoint hardening, and abuse risks.

Recommendation:

- Blocked for now.

## Tool-To-Bridge Mapping

### `dispatcher_status`

Maps to:

```text
GET /status
```

Input:

```json
{}
```

Output summary:

- `status`
- `dispatcherRoot`
- `defaultWorker`
- `autoPush`
- `bridgeEnabled`
- `taskState`

### `dispatcher_dispatch`

Maps to:

```text
POST /dispatch
```

Input summary:

- `repo`
- `worker`
- `task`
- `commitMessage`
- `scope`
- `blocked`
- `validation`
- `expectedOutput`

Output summary:

- `accepted`
- `status`
- `taskState`
- `processId`
- `taskId`, if the bridge supports it later

### `dispatcher_latest_result`

Maps to:

```text
GET /runs/latest
```

Input:

```json
{}
```

Output summary:

- `taskId`
- `status`
- `repo`
- `worker`
- `filesChanged`
- `commit`
- `commitMessage`
- `pushed`
- `workingTreeClean`
- `summary`
- `needsReview`
- `reviewHints`

### `dispatcher_get_run`

Maps to:

```text
GET /runs/{taskId}
```

Input summary:

- `taskId`

Output summary:

- Same as `dispatcher_latest_result`.

## Approval And Review Behavior

The MCP layer must preserve the Phase 5.1 approval model:

- `dispatcher_dispatch` requires explicit approval.
- `dispatcher_status` can be read-only.
- `dispatcher_latest_result` can be read-only.
- `dispatcher_get_run` can be read-only.
- No auto-chain.
- ChatGPT must review the result before the next dispatch.

The approval prompt for dispatch should display:

- Target repo.
- Worker.
- Task summary.
- Commit message.
- Scope.
- Blocked list.
- Validation expectations.
- Expected output.

## Local Configuration Model

The MCP server should read bridge configuration locally:

- Bridge host.
- Bridge port.
- Bridge token.

Possible token sources:

- `dispatcher/config.local.json`
- Environment variable, such as `JJ_DISPATCHER_BRIDGE_TOKEN`

Rules:

- Token must not be exposed to the MCP client.
- Token must not be included in tool output.
- Token must not appear in result artifacts.
- Token must not be printed in stdout or stderr logs.
- Error messages must not echo config contents.

Initial preference:

- Read host and port from local config.
- Read token from local config or an environment variable.
- Prefer environment variable override for future testing, but do not require it for the first design.

## Risks And Unresolved Questions

Which ChatGPT clients can connect to local MCP:

- Needs current client-specific research before implementation.
- Some MCP clients support local stdio servers directly.
- ChatGPT-facing support may depend on connector/app capabilities and may not match local-only stdio assumptions.

Whether the ChatGPT app supports local MCP directly:

- Unresolved.
- Treat direct ChatGPT local MCP as research, not an implementation assumption.

Whether VSCode, Cline, or Claude Desktop support is easier first:

- Likely easier to validate a local stdio MCP server with developer tools that already support local MCP servers.
- This may be useful for smoke testing before any ChatGPT-specific connector path.

How approval prompts are handled by each client:

- Client behavior differs.
- Phase 5.3 must document how the chosen client presents tool approval and whether dispatch can be reliably gated.

How task length/file-task mode should work:

- Long prompts should not be pushed blindly through tool arguments.
- A size threshold should trigger file-task mode or rejection.
- File-task mode must use an allowlisted Dispatcher-controlled folder only.

How to avoid tool misuse through prompt injection:

- Keep tool list narrow.
- Require approval for dispatch.
- Include scope and blocked lists.
- Reject missing safety context for file-changing tasks.
- Require result review before the next dispatch.

## Candidate Runtime Summary

| Runtime | Windows Fit | Install Ease | Schema Handling | HTTP Calls | Token Handling | Process Management | Maintainability | JJ Fit |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Node.js | Strong | Medium | Strong | Strong | Strong | Strong | Strong | Strong |
| Python | Strong | Medium | Strong | Strong | Strong | Strong | Strong | Strong |
| PowerShell | Excellent | Strong | Medium | Strong | Medium | Medium | Medium | Medium |
| VSCode extension-hosted | Strong | Weak/Medium | Strong | Strong | Medium | Medium | Weak/Medium | Weak first |

## Recommended Next Step

Phase 5.3 - MCP Server Skeleton Design

Recommendation:

- Do one more design step before code.
- Choose runtime.
- Define file layout.
- Define config loading.
- Define tool schemas.
- Define test plan.

Scope options for Phase 5.3:

- Documentation only, preferred.
- Minimal skeleton only after explicit approval.

Phase 5.3 must still avoid tunnels, public endpoints, remote execution, VSCode UI automation, and auto-chain behavior.

## References

- MCP transports specification: `https://modelcontextprotocol.io/specification/2025-06-18/basic/transports`
- MCP TypeScript SDK server quickstart: `https://ts.sdk.modelcontextprotocol.io/v2/documents/Documents.Server_Quickstart.html`
- MCP TypeScript SDK server transport overview: `https://ts.sdk.modelcontextprotocol.io/documents/server.html`
- MCP client quickstart: `https://modelcontextprotocol.io/quickstart/client`
