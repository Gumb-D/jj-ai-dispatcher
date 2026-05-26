# Phase 5.3 MCP Server Skeleton Design

## Purpose

Design a future local Node.js MCP server skeleton for JJ AI Dispatcher without implementing it yet. This phase exists to turn the Phase 5.1 boundary and Phase 5.2 protocol research into a concrete implementation shape that can be reviewed before any code is added.

This is a design document only. It does not implement an MCP server.

Scope:

- Define the future Node.js MCP server role.
- Define the file layout that a later implementation phase may create.
- Define config loading, tool schemas, approval behavior, error handling, and test strategy.
- Keep MCP as a thin adapter over the existing Local Dispatcher Bridge.

Non-goals:

- Do not create `package.json`.
- Do not create `node_modules`.
- Do not create an MCP server.
- Do not create TypeScript, JavaScript, Python, or PowerShell implementation files.
- Do not create a VSCode extension.
- Do not create test code.
- Do not add tunnels, public endpoints, remote execution, shell execution, direct Git execution, or autonomous chaining.

## Source Documents

- `docs/phase-5-tool-integration-feasibility.md`
- `docs/phase-5-mcp-boundary-design.md`
- `docs/phase-5-mcp-protocol-research-notes.md`
- `docs/local-bridge-operator-guide.md`
- `docs/operator-run-review-template.md`

## Current Baseline

- Branch baseline: `main @ 9ed35d6`
- Phase 5.0 feasibility completed.
- Phase 5.1 MCP boundary completed.
- Phase 5.2 MCP protocol research completed.
- Local HTTP Bridge already works.
- Dispatcher remains the execution controller.
- Existing Local HTTP Bridge remains authoritative.
- MCP is only a future thin adapter layer.

Current bridge endpoints:

- `GET /status`
- `POST /dispatch`
- `GET /runs/latest`
- `GET /runs/{taskId}`

Allowed future MCP tools:

- `dispatcher_status`
- `dispatcher_dispatch`
- `dispatcher_latest_result`
- `dispatcher_get_run`

## Architecture Overview

Future intended flow:

```text
ChatGPT / MCP Client
-> MCP Server
-> Local Dispatcher Bridge
-> Dispatcher
-> Worker
```

Return flow:

```text
Worker
-> Dispatcher run artifacts
-> Local Dispatcher Bridge
-> MCP Server
-> ChatGPT / MCP Client
```

### ChatGPT / MCP Client Responsibilities

The MCP client is responsible for:

- Presenting available tools to ChatGPT.
- Showing approval UI before sensitive tool calls.
- Launching the local stdio MCP server process.
- Sending MCP protocol messages over stdin.
- Reading MCP protocol messages from stdout.
- Displaying tool results for review.

The MCP client must not be treated as the execution controller. Client-side convenience must not remove the Dispatcher review loop.

### MCP Server Responsibilities

The future MCP server is responsible for:

- Exposing only the approved Dispatcher tool surface.
- Validating tool inputs before bridge calls.
- Loading local bridge configuration safely.
- Calling only the existing Local Dispatcher Bridge endpoints.
- Translating bridge responses into structured MCP tool results.
- Keeping protocol traffic on stdout only.
- Keeping diagnostics on stderr only.
- Never exposing bridge tokens or local config contents to the MCP client.

The MCP server must not:

- Execute shell commands.
- Execute Git commands.
- Read or write arbitrary local files.
- Modify Dispatcher config.
- Start tunnels.
- Bind public ports.
- Control VSCode UI.
- Queue or auto-chain dispatches.
- Become a second Dispatcher.

### Local Dispatcher Bridge Responsibilities

The Local Dispatcher Bridge remains authoritative for:

- Local HTTP endpoint behavior.
- Token authentication.
- Single active task protection.
- Mapping requests to Dispatcher execution.
- Exposing run result lookup.

The MCP server should not duplicate bridge business logic beyond input validation and safe error mapping.

### Dispatcher Responsibilities

Dispatcher remains responsible for:

- Accepting constrained task contracts.
- Writing task and run artifacts.
- Starting the selected worker.
- Managing Git commit behavior.
- Recording result summaries, logs, diffs, and review hints.
- Enforcing existing local execution boundaries.

### Worker Responsibilities

The worker remains responsible for:

- Performing the approved task inside the target repository.
- Producing output that Dispatcher captures.
- Leaving Git evidence for review through Dispatcher artifacts.

Initial worker support remains `codex` only.

## Proposed File Layout

This section is design only. These files and directories must not be created in Phase 5.3.

Future layout concept:

```text
mcp/
  server/
    index.ts
    server.ts
    bridgeClient.ts
    errors.ts
  tools/
    dispatcherStatus.ts
    dispatcherDispatch.ts
    dispatcherLatestResult.ts
    dispatcherGetRun.ts
    schemas.ts
  config/
    loadConfig.ts
    types.ts
  transports/
    stdio.ts
  tests/
    unit/
    mocks/
    smoke/
docs/
  phase-5-mcp-server-skeleton-design.md
```

### `mcp/server/`

Future role:

- Own MCP server initialization.
- Register allowed tools.
- Hold the bridge HTTP client wrapper.
- Hold common error normalization.

Design notes:

- `index.ts` would be the future process entry point.
- `server.ts` would construct the MCP server and register tools.
- `bridgeClient.ts` would call the Local Dispatcher Bridge only.
- `errors.ts` would map validation, config, bridge, and malformed response errors into safe tool responses.

### `mcp/tools/`

Future role:

- One file per allowed tool.
- Shared schema definitions in one place.
- Tool handlers should be thin and call `bridgeClient`.

Design notes:

- Tool files should not contain process setup.
- Tool files should not read secrets directly.
- Tool files should not call local shell commands.
- Tool files should not touch Git.

### `mcp/config/`

Future role:

- Load bridge host, port, token, and safety-related local settings.
- Apply environment overrides.
- Validate missing or unsafe configuration.

Design notes:

- Config loading should be centralized.
- Secret values should be held in memory only.
- Config load failures should be reported without echoing config contents.

### `mcp/transports/`

Future role:

- Isolate stdio transport setup.

Design notes:

- Initial implementation should support local stdio only.
- HTTP, streamable HTTP, remote, and tunnel transports are out of scope.

### `mcp/tests/`

Future role:

- Hold future unit, mock bridge, and smoke test assets.

Design notes:

- Tests are not created in Phase 5.3.
- Future tests should verify boundary behavior before broad client validation.

### `docs/`

Future role:

- Keep design decisions, operator guidance, smoke test notes, and phase handovers.

## Runtime Decision

Recommended runtime for the future skeleton:

```text
Node.js MCP server
```

Node.js is selected because:

- The MCP TypeScript SDK path is mature and well aligned with local stdio servers.
- TypeScript provides strong schema and handler structure for a narrow tool surface.
- Modern Node.js can call the Local Dispatcher Bridge with built-in HTTP support.
- Node.js works well on Windows as a child process launched by an MCP client.
- The adapter can stay small and separate from the existing PowerShell operator layer.

### Comparison Against Python

Python remains a practical secondary candidate:

- Strong Windows support.
- Strong JSON handling.
- Good HTTP client options.
- Good fit for local scripts.

Reasons not to choose Python first:

- Phase 5.2 identified Node.js as the strongest first fit for MCP SDK examples and TypeScript schema ergonomics.
- Introducing Python packaging would still require dependency and environment decisions.
- The project already uses PowerShell for operators; adding Python as a second scripting runtime should wait unless Node.js proves awkward.

### Comparison Against PowerShell

PowerShell remains important as the helper/operator layer:

- Excellent Windows fit.
- Existing bridge scripts already use it.
- Operator workflow is already documented.

Reasons not to choose PowerShell as the primary MCP server:

- MCP stdio protocol framing requires strict stdin/stdout behavior.
- Robust tool schema validation is more awkward than in TypeScript.
- Diagnostics and object formatting can accidentally interfere with stdout if not carefully constrained.
- PowerShell should continue to help operators start, inspect, and troubleshoot Dispatcher rather than become the protocol server.

## Transport Design

Initial transport:

```text
local stdio MCP server
```

The MCP client launches the Node.js process locally. The MCP server reads protocol messages from stdin and writes protocol messages to stdout.

No local HTTP MCP listener is introduced in the first skeleton. The only HTTP calls are outbound calls from the MCP server to the existing Local Dispatcher Bridge on `127.0.0.1`.

### stdin Behavior

stdin is reserved for MCP client-to-server protocol messages.

Rules:

- Do not read interactive prompts from stdin.
- Do not ask the operator questions from the server process.
- Do not mix custom line prompts with MCP protocol traffic.
- Treat malformed protocol input as a protocol-level error through the MCP SDK path.

### stdout Behavior

stdout is reserved for MCP server-to-client protocol messages.

Rules:

- Protocol traffic goes to stdout only.
- No diagnostic logs on stdout.
- No startup banners on stdout.
- No config summaries on stdout.
- No bridge token or secret value on stdout.

### stderr Behavior

stderr is reserved for diagnostics.

Rules:

- Diagnostics go to stderr only.
- Logs must be concise.
- Logs must not include bridge tokens.
- Logs must not include full config file contents.
- Logs must not include task bodies unless a future explicit redaction policy allows safe summaries.

## Config Loading Model

The MCP server should use the existing local bridge configuration as the source of truth.

Primary config file:

```text
dispatcher/config.local.json
```

Optional environment override:

```text
JJ_DISPATCHER_BRIDGE_TOKEN
```

Future optional environment overrides may be considered for test isolation, but Phase 5.3 only standardizes token override:

- `JJ_DISPATCHER_BRIDGE_TOKEN`

### Config Values

The future MCP server needs:

- Bridge host.
- Bridge port.
- Whether token is required.
- Bridge token.

Expected source fields:

```text
bridge.host
bridge.port
bridge.requireToken
bridge.token
```

The bridge host must remain local:

```text
127.0.0.1
```

The MCP server must reject non-local bridge hosts unless a later design explicitly changes the safety boundary. No such change is approved in this phase.

### Precedence Rules

Recommended precedence:

1. Load non-secret bridge settings from `dispatcher/config.local.json`.
2. Load `bridge.token` from `dispatcher/config.local.json`.
3. If `JJ_DISPATCHER_BRIDGE_TOKEN` is set, use it instead of `bridge.token`.

This allows local testing with an environment token while preserving the existing config file as the default operator path.

Environment override rules:

- Empty environment variables should be treated as unset.
- Environment token must not be written back to config.
- Environment token must not be printed.
- Environment token must not be returned in tool output.

### Failure Behavior

Config load failure should stop server startup or reject all tool calls with a safe configuration error.

Failure cases:

- `dispatcher/config.local.json` missing.
- Config file is malformed JSON.
- `bridge.enabled` is false.
- `bridge.host` is not `127.0.0.1`.
- `bridge.port` is missing or invalid.
- `bridge.requireToken` is true and no token is available.

Safe error examples:

```json
{
  "status": "config_error",
  "error": "bridge token missing"
}
```

```json
{
  "status": "config_error",
  "error": "bridge host must be 127.0.0.1"
}
```

Unsafe error behavior:

- Do not echo the token.
- Do not echo the full config body.
- Do not print local secret paths beyond normal repo-relative config path.

### Secret Handling Rules

Rules:

- The bridge token stays local.
- The token is only used as the `X-Dispatcher-Token` header when calling the bridge.
- The token must never appear in MCP tool results.
- The token must never appear in stdout.
- The token must never appear in stderr.
- The token must never be written into run artifacts by the MCP layer.
- The token must never be copied into task text.
- The token must never be included in approval text.

## Tool Schema Design

The MCP server may expose only the four approved tools. Tool schemas should validate inputs before any bridge call.

All tool outputs should preserve bridge semantics where possible. The MCP layer may normalize transport and validation errors, but it must not invent new Dispatcher capabilities.

### Common Error Model

Tool errors should use a small common shape:

```json
{
  "status": "error",
  "errorType": "validation_error",
  "message": "task is required",
  "retryable": false
}
```

Recommended `errorType` values:

- `config_error`
- `validation_error`
- `bridge_unavailable`
- `authentication_error`
- `bridge_error`
- `timeout`
- `malformed_response`
- `worker_failed`

Rules:

- Error messages should be useful but sanitized.
- Authentication errors must not reveal expected or provided token values.
- Malformed bridge responses should include the endpoint name, not raw secret-bearing headers.
- Worker failure should be surfaced from Dispatcher result status and review hints, not interpreted as an MCP server failure.

### `dispatcher_status`

Purpose:

- Check bridge and Dispatcher task state.

Bridge mapping:

```text
GET /status
```

Input schema:

```json
{}
```

Required fields:

- None.

Optional fields:

- None.

Validation expectations:

- Reject unexpected fields if the MCP SDK supports strict object validation.

Output concept:

```json
{
  "status": "ok",
  "dispatcherRoot": "D:\\dev\\projects\\jj-ai-dispatcher",
  "defaultWorker": "codex",
  "autoPush": false,
  "bridgeEnabled": true,
  "taskState": "idle"
}
```

Side effects:

- None.

Approval:

- No approval required.

### `dispatcher_dispatch`

Purpose:

- Submit one approved task to Dispatcher through the existing bridge.

Bridge mapping:

```text
POST /dispatch
```

Input concept:

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
    "dispatcher/bridge.ps1"
  ],
  "validation": [
    "git diff --check"
  ],
  "expectedOutput": [
    "docs/example.md updated"
  ]
}
```

Required fields:

- `task`

Conditionally required fields:

- `commitMessage` should be required when file changes are expected.
- `scope` should be required when file changes are expected.
- `blocked` should be required when the request touches safety-sensitive areas or when the task asks for implementation work.

Optional fields:

- `repo`
- `worker`
- `commitMessage`
- `scope`
- `blocked`
- `validation`
- `expectedOutput`

Default values:

- `repo`: `self`, if omitted and the bridge supports the same default behavior.
- `worker`: `codex`, if omitted.

Validation expectations:

- `worker` must be `codex` initially.
- `repo` must be `self` or an allowlisted local repo path supported by the bridge.
- `task` must be a non-empty string.
- `task` must not be only whitespace.
- `commitMessage`, if present, must be a non-empty string.
- `scope`, `blocked`, `validation`, and `expectedOutput`, if present, must be arrays of strings.
- Reject unknown worker values.
- Reject attempts to request direct shell execution.
- Reject attempts to request direct Git execution outside Dispatcher behavior.
- Reject attempts to enable tunnels, public endpoints, remote access, or auto-chain behavior.
- Reject unsafe file-task paths that are outside the future allowlisted task folder.

Bridge payload:

- The MCP server should pass only fields accepted by the existing bridge contract.
- If `scope`, `blocked`, `validation`, or `expectedOutput` are not yet bridge-native fields, the future implementation must either include them inside the approved task text envelope or wait for bridge support in a later phase.
- The MCP layer must not create new bridge capabilities silently.

Output concept:

```json
{
  "accepted": true,
  "status": "running",
  "worker": "codex",
  "taskState": "running",
  "processId": 12345,
  "taskId": null
}
```

Side effects:

- Starts one Dispatcher task if accepted by the bridge.

Approval:

- Explicit approval required before bridge call.

### `dispatcher_latest_result`

Purpose:

- Read the latest Dispatcher run result after task completion.

Bridge mapping:

```text
GET /runs/latest
```

Input schema:

```json
{}
```

Required fields:

- None.

Optional fields:

- None.

Validation expectations:

- Reject unexpected fields if strict validation is available.

Output concept:

```json
{
  "taskId": "20260526-031500-a1b2c3d4",
  "status": "success",
  "repo": "D:\\dev\\projects\\jj-ai-dispatcher",
  "worker": "codex",
  "filesChanged": [],
  "commit": null,
  "commitMessage": "docs: describe change",
  "pushed": false,
  "workingTreeClean": true,
  "summary": "Codex worker completed successfully.",
  "needsReview": false,
  "reviewHints": []
}
```

Side effects:

- None.

Approval:

- No approval required.

### `dispatcher_get_run`

Purpose:

- Read a specific Dispatcher run result by task ID.

Bridge mapping:

```text
GET /runs/{taskId}
```

Input concept:

```json
{
  "taskId": "20260526-031500-a1b2c3d4"
}
```

Required fields:

- `taskId`

Optional fields:

- None.

Validation expectations:

- `taskId` must be a non-empty string.
- `taskId` must match the Dispatcher task ID shape.
- Reject path separators.
- Reject `.` and `..`.
- Reject URL-like values.
- Reject unexpected fields if strict validation is available.

Output concept:

- Same result shape as `dispatcher_latest_result`.

Side effects:

- None.

Approval:

- No approval required.

## Approval Model

The Phase 5.1 safety boundary remains mandatory.

Approval rules:

- `dispatcher_status` can run without approval.
- `dispatcher_latest_result` can run without approval.
- `dispatcher_get_run` can run without approval.
- `dispatcher_dispatch` requires explicit approval.
- No auto-chain dispatch.
- Every dispatch must be reviewed before the next dispatch.

### Dispatch Approval Content

Before `dispatcher_dispatch`, the approval view should show:

- Target repo.
- Worker.
- Task summary.
- Commit message.
- Scope.
- Blocked list.
- Validation expectations.
- Expected output.
- Reminder that the request will start one local Dispatcher task.

Approval content must not include:

- Bridge token.
- Full local config contents.
- Hidden environment variable values.
- Any request to expose a public endpoint.

### Review Flow

After dispatch:

1. Poll or request `dispatcher_status` until `taskState = "idle"`.
2. Request `dispatcher_latest_result`.
3. Review the result using `docs/operator-run-review-template.md`.
4. Inspect status, repo, worker, files changed, commit, pushed, working tree cleanliness, summary, `needsReview`, and `reviewHints`.
5. Decide whether to accept, request a fix, stop and investigate, or perform manual rollback review.

The MCP server must not automatically perform step 1 through step 5 as an autonomous chain. ChatGPT and the operator remain responsible for deliberate review.

### Post-Dispatch Expectations

Before the next dispatch, ChatGPT must understand:

- Whether the previous task succeeded or failed.
- Whether changed files match the approved scope.
- Whether a commit exists when changes were expected.
- Whether the working tree is clean.
- Whether validation evidence is sufficient.
- Whether `needsReview` or `reviewHints` require operator attention.

## Long Prompt Strategy

The future MCP server should handle task size deliberately.

### Small Inline Tasks

Small tasks may be passed inline as `task` text.

Suitable examples:

- Documentation edits with narrow scope.
- Simple refactors with explicit files.
- Small bug fixes with clear validation.

Rules:

- Include scope and blocked lists for file-changing tasks.
- Require approval before dispatch.
- Preserve result review before another dispatch.

### Large Tasks

Large tasks should not be pushed blindly through tool arguments.

Risks:

- Approval UI becomes unreadable.
- Prompt injection text becomes harder to inspect.
- Client or bridge size limits may be hit.
- Long task text may hide unsafe instructions.

Recommended behavior:

- Define a future maximum inline task size.
- If the task exceeds the threshold, reject it with guidance to use file-task mode.
- Do not silently truncate task text.
- Do not split a large task into multiple dispatches automatically.

### File-Task Mode

Future file-task mode may allow long task instructions to be stored in a Dispatcher-controlled inbox file.

Allowlisted folder concept:

```text
dispatcher/inbox/mcp-tasks/
```

Rules:

- Only allow task files under the approved Dispatcher-controlled folder.
- Do not accept arbitrary filesystem paths from ChatGPT.
- Do not read unrelated local files.
- Do not allow `..` path traversal.
- Do not allow absolute paths supplied by the MCP client.
- Keep approval visible by showing the file name, task summary, scope, blocked list, and validation expectations.

File-task mode is not implemented or approved in Phase 5.3. It is only a design direction for later phases.

## Error Handling Model

The MCP server should convert operational failures into safe structured errors.

### Bridge Unavailable

Cause examples:

- Bridge process is not running.
- Wrong port.
- Connection refused.
- Localhost network failure.

Tool error:

```json
{
  "status": "error",
  "errorType": "bridge_unavailable",
  "message": "dispatcher bridge is unavailable",
  "retryable": true
}
```

Operator action:

- Start `.\dispatcher\bridge.ps1`.
- Confirm host and port.
- Confirm `GET /status` works through existing helper flow.

### Invalid Token

Cause examples:

- Missing token.
- Wrong token.
- Environment token does not match bridge config.

Tool error:

```json
{
  "status": "error",
  "errorType": "authentication_error",
  "message": "bridge authentication failed",
  "retryable": false
}
```

Rules:

- Do not reveal expected token.
- Do not reveal provided token.
- Do not echo token source value.

### Invalid Payload

Cause examples:

- Missing `task`.
- Unsupported `worker`.
- Invalid `taskId`.
- Non-array `scope`.
- Unsafe repo value.

Tool error:

```json
{
  "status": "error",
  "errorType": "validation_error",
  "message": "invalid dispatcher_dispatch payload",
  "retryable": false
}
```

Rules:

- Reject before calling the bridge when possible.
- Keep messages specific enough to fix the request.
- Do not mutate unsafe requests into safe-looking requests.

### Worker Failure

Cause examples:

- Codex task fails.
- Git commit fails.
- Validation fails.
- Working tree remains dirty.

Tool result:

- `dispatcher_dispatch` may still return accepted if the bridge started the worker.
- Worker failure should later appear in `dispatcher_latest_result` or `dispatcher_get_run`.

Result review should inspect:

- `status`
- `summary`
- `needsReview`
- `reviewHints`
- `workingTreeClean`
- `filesChanged`
- `commit`

Worker failure is not the same as MCP server failure. It is a Dispatcher run outcome requiring review.

### Timeout

Cause examples:

- Bridge call does not return.
- Local bridge is overloaded.
- Network stack stalls.

Tool error:

```json
{
  "status": "error",
  "errorType": "timeout",
  "message": "dispatcher bridge request timed out",
  "retryable": true
}
```

Rules:

- Timeouts should apply to bridge HTTP calls.
- A timeout after `POST /dispatch` may be ambiguous.
- If dispatch timeout occurs, the next safe action is `dispatcher_status`, then `dispatcher_latest_result` after idle.
- Do not automatically retry `POST /dispatch` because it may start duplicate work if the first request was accepted.

### Malformed Response

Cause examples:

- Bridge returns non-JSON.
- Bridge returns missing required fields.
- Bridge returns an unexpected shape.

Tool error:

```json
{
  "status": "error",
  "errorType": "malformed_response",
  "message": "dispatcher bridge returned an unexpected response",
  "retryable": false
}
```

Rules:

- Include endpoint name in diagnostics if useful.
- Do not include request headers.
- Do not include token values.
- Do not guess missing result fields.

## Testing Plan

This is a design-only test plan. No tests are added in Phase 5.3.

### Unit Test Ideas

Future unit tests should cover:

- Config load precedence.
- Missing config behavior.
- Malformed config behavior.
- Environment token override.
- Token redaction in errors.
- Host validation requiring `127.0.0.1`.
- `dispatcher_status` empty input validation.
- `dispatcher_dispatch` required and optional field validation.
- Rejection of unsupported workers.
- Rejection of unsafe repo values.
- Rejection of unsafe long-prompt file paths.
- `dispatcher_get_run` task ID validation.
- Bridge error normalization.
- Timeout error normalization.
- Malformed response handling.

### Bridge Mock Ideas

Future mock bridge should simulate:

- Successful `GET /status`.
- Busy status.
- Successful `POST /dispatch`.
- `401` missing token.
- `403` invalid token.
- `404` no latest run.
- `409` busy dispatch.
- `500` config error.
- Non-JSON response.
- Slow response for timeout testing.
- Successful latest run with `status = "success"`.
- Failed latest run with `needsReview = true`.

Mock bridge tests should assert:

- MCP server sends `X-Dispatcher-Token`.
- Token is never returned in tool output.
- Token is never printed in diagnostics.
- `POST /dispatch` is not retried automatically after timeout.

### Manual Smoke Test Ideas

Future manual smoke tests should verify:

- MCP server starts through a local MCP client using stdio.
- `dispatcher_status` works with the real bridge.
- `dispatcher_latest_result` handles no-run and latest-run states.
- `dispatcher_get_run` retrieves a known run.
- `dispatcher_dispatch` requires client approval before execution.
- Dispatch starts exactly one Dispatcher task.
- Busy protection is preserved.
- Result review follows `docs/operator-run-review-template.md`.
- No stdout diagnostic noise corrupts MCP protocol traffic.
- No token appears in client-visible output or logs.

Manual smoke tests must not include:

- Remote endpoint exposure.
- Public tunnels.
- Direct shell tools.
- Direct Git tools.
- Auto-chain behavior.

## Future Roadmap

Possible later phases:

### Phase 5.4 - Minimal MCP Skeleton Implementation

Potential scope:

- Add a minimal Node.js stdio MCP server skeleton.
- Register only the four approved Dispatcher tools.
- Implement config loading and bridge client.
- Add minimal tests or a mock bridge if approved.

Implementation must still avoid:

- Tunnels.
- Public endpoints.
- Remote execution.
- Shell tools.
- Direct Git tools.
- VSCode UI automation.
- Auto-chain behavior.

### Phase 5.5 - Client Validation Research

Potential scope:

- Validate which MCP clients can launch a local stdio server.
- Check how approval UI is presented for `dispatcher_dispatch`.
- Confirm whether ChatGPT-facing local MCP support is available and safe.
- Document client-specific setup without weakening the Dispatcher boundary.

### Phase 5.6 - Long Prompt And File-Task Design

Potential scope:

- Define maximum inline task size.
- Design Dispatcher-controlled file-task inbox behavior.
- Preserve allowlisted task folder constraints.
- Decide whether bridge support is needed before MCP exposes file-task mode.

### Phase 5.7 - Operator UX Improvements

Potential scope:

- Improve local helper scripts.
- Improve review templates.
- Explore a local-only operator UI after MCP boundaries are proven.

This roadmap does not approve implementation. Each implementation phase requires explicit approval.

## Decision

Phase 5.3 selects a future Node.js stdio MCP server skeleton as the preferred implementation shape.

The server must remain a thin adapter:

```text
MCP tool call -> validated bridge request -> existing Dispatcher bridge endpoint
```

The design preserves:

- Dispatcher as execution controller.
- Local HTTP Bridge as authoritative.
- Local-only operation.
- Token-protected bridge calls.
- Explicit dispatch approval.
- Manual result review.
- Single-task discipline.
- No auto-chain behavior.

The design blocks:

- Direct shell execution.
- Direct Git execution.
- Arbitrary file read/write tools.
- Remote execution.
- Tunnels.
- Public endpoints.
- VSCode UI automation.
- Hidden automation.
