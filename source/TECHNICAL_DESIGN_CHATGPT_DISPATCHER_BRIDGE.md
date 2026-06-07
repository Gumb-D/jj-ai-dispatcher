# JJ AI Dispatcher - ChatGPT Dispatcher Bridge Technical Design

## 1. Canonical Status

This is the live canonical technical design for the JJ AI Dispatcher ChatGPT-to-Dispatcher bridge.

Canonical file:

```text
source/TECHNICAL_DESIGN_CHATGPT_DISPATCHER_BRIDGE.md
```

Current mirror:

```text
docs/TECHNICAL_DESIGN_CHATGPT_DISPATCHER_BRIDGE.md
```

The mirror exists for operator discoverability. When this design changes, update the canonical file first and keep the mirror identical unless a future docs index explicitly changes that policy.

Current baseline:

```text
Version: 0.8.0
Stabilization baseline: P0-P3 completed
Runtime posture: local-first, safety-controlled, review-gated
```

This document describes current implemented behavior. Historical phase notes are retained only in the labeled history section near the end.

## 2. Product Definition

JJ AI Dispatcher is a local-first, safety-controlled AI coding dispatcher with ChatGPT MCP initiation, Codex execution, Dispatcher-owned Git control, persistent run results, and optional browser-visible postback.

It reduces manual copy/paste between ChatGPT, Codex, Dispatcher, and Git while keeping ChatGPT or the operator in the review loop.

It is not:

- a fully autonomous AI employee
- a general remote desktop controller
- a production multi-user platform
- a distributed agent system
- a guaranteed lock-screen browser automation system
- a review-free autonomous coding platform

## 3. Current Runtime Chain

The implemented v0.8.0 runtime chain is:

```text
ChatGPT
  -> MCP HTTPS / approved connector
  -> MCP HTTP Adapter on 127.0.0.1:8790
  -> local Dispatcher Bridge on 127.0.0.1:8787
  -> Codex worker
  -> Dispatcher-owned Git commit / optional push
  -> persisted run result
  -> optional browser-visible postback
```

The source of truth is the persisted run result under:

```text
dispatcher/runs/<task-id>/result.json
```

Browser postback is a delivery convenience. It is never the execution source of truth.

## 4. Role Model

Current roles:

- ChatGPT = Brain and task director
- Dispatcher MCP = approved tool channel
- MCP HTTP Adapter = local adapter boundary for ChatGPT-compatible MCP traffic
- Dispatcher Bridge = local-only execution API on port `8787`
- Dispatcher = execution controller and Git owner
- Codex = coding worker
- Git = control point, audit trail, and recovery point
- Launcher = environment startup and health-check helper
- Browser postback = optional visible delivery channel

ChatGPT owns intent, scope, blocked areas, validation expectations, and review. Dispatcher owns orchestration, run artifacts, and Git operations. Codex edits files within the approved task. The launcher starts or checks services; it does not dispatch tasks, modify runtime behavior, or expand the MCP surface.

## 5. Completed P0-P3 Baseline

P0-P3 stabilization is complete for the v0.8.0 baseline.

Completed stabilization areas:

- P0: documentation and current standing consolidation
- P1: execution and delivery status separation
- P2: persistent result retrieval as the primary recovery path
- P3: automated test baseline

The baseline confirms:

- local Dispatcher execution is implemented
- Codex task execution is implemented
- Dispatcher-owned Git commit is implemented
- MCP status, dispatch, latest-result, and get-run tools are implemented
- MCP HTTP Adapter defaults to `127.0.0.1:8790`
- Dispatcher Bridge defaults to `127.0.0.1:8787`
- persistent run artifacts are implemented under `dispatcher/runs/<task-id>/`
- browser-visible postback exists as optional delivery
- launcher startup and health-check workflow exists
- `npm test` is the standard top-level automated baseline

## 6. Approved MCP Tool Surface

The approved MCP tool surface is intentionally narrow:

- `dispatcher_status`: read local bridge readiness and current task state
- `dispatcher_dispatch`: submit one explicit approved Codex task
- `dispatcher_latest_result`: retrieve the newest completed persisted run result
- `dispatcher_get_run`: retrieve one persisted run result by task ID

The current approved MCP surface does not include:

- arbitrary shell execution
- direct Git commands
- direct file read/write tools
- scheduler or queue management
- autonomous loops
- distributed worker routing
- browser control tools
- UI dashboard control
- bot bridge control
- GitHub issue bridge control
- config or secret write tools

`dispatcher_dispatch` accepts only the `codex` worker and requires explicit safety fields: `repo`, `worker`, `task`, `commitMessage`, `scope`, `blocked`, `validation`, and `expectedOutput`. The minimal MCP boundary currently requires `repo: self`.

## 7. Dispatcher Bridge Boundary

The raw Dispatcher Bridge runs locally on:

```text
http://127.0.0.1:8787
```

It must remain local-only. Do not expose or tunnel port `8787`.

Implemented bridge responsibilities:

- report status
- accept one explicit dispatch request
- read the latest persisted run result
- read a specific persisted run result

The MCP HTTP Adapter runs locally on:

```text
http://127.0.0.1:8790
```

For controlled ChatGPT MCP testing, only the MCP adapter boundary on port `8790` may be exposed through an approved HTTPS connector or tunnel. The raw bridge on `8787` must not be exposed publicly.

## 8. Result Contract and Recovery

Run artifacts live under:

```text
dispatcher/runs/<task-id>/
```

Important artifacts include:

- `task.json`
- `result.json`
- `summary.md`
- `codex-output.log`
- `codex-error.log`
- `git-diff.patch` when a diff is available

Current result retrieval rules:

- `dispatcher_latest_result` returns the newest completed persisted run for this dispatcher repository.
- Latest-result retrieval ignores interrupted `queued` or `running` artifacts, malformed task/result mismatches, and lifecycle-test artifacts for unrelated temporary repositories.
- `dispatcher_get_run` uses the exact task ID and returns that run only.
- Completed `result.json` files remain retrievable after bridge restart because retrieval reads persisted run artifacts.
- In-memory task state, browser postback queue state, and active browser typing state do not survive bridge restart.
- Read-only and no-change worker conclusions are persisted as redacted, bounded `workerSummary`, `workerReport`, `workerReportMetadata`, and `workerReportTruncated` fields, and are included in `summary.md`.
- The worker report is captured from the already-collected worker output. It does not add an MCP tool or arbitrary file-read endpoint.

Primary recovery workflow:

1. Dispatch one approved task.
2. Let Dispatcher and Codex execute locally.
3. If browser postback does not arrive, do not infer execution failure.
4. Call `dispatcher_status` after unlock, reconnect, or client recovery.
5. If `taskState` is still `running`, wait and check again.
6. When idle, call `dispatcher_latest_result`.
7. If the task ID is known or latest is not the intended run, call `dispatcher_get_run`.
8. Review execution status, delivery status, commit, changed files, validation output, and working-tree state before dispatching another task.

## 9. Execution and Delivery Status Separation

The v0.8.0 baseline separates execution outcome from result-delivery outcome.

Execution statuses:

```text
queued
running
success
failed
cancelled
```

Delivery statuses:

```text
not_requested
pending
delivered
timeout
failed
skipped
unavailable
```

Compatibility rule:

```text
status mirrors executionStatus for run results.
```

Required behavior:

```text
execution success + browser postback timeout = executionStatus success, deliveryStatus timeout
```

Browser delivery updates may change only delivery fields:

- `deliveryStatus`
- `deliveryChannel`
- `deliveryRequired`
- delivery-related summary, validation summary, or recovery text

Browser delivery must not overwrite top-level `status` or `executionStatus`.

Older successful results without delivery fields are normalized as:

```text
executionStatus = status
deliveryStatus = not_requested
deliveryChannel = null
deliveryRequired = false
```

## 10. Browser Postback and Lock-Screen Limitation

Browser postback is an optional visible notification channel.

Confirmed limitation:

```text
Windows lock screen does not reliably support browser DOM typing and send-button interaction.
```

Therefore:

- execution may continue while Windows is locked if the local worker, Dispatcher, and target repository remain operational
- browser DOM typing and send-button interaction are not lock-screen tolerant
- browser postback timeout does not prove execution failure
- persisted result retrieval is the authoritative recovery path

Manual environment validation remains separate from automated testing:

- unlocked browser postback
- Windows lock-screen postback timeout
- result recovery after unlock

## 11. Deterministic Worker Finalization

Dispatcher-owned finalization is required for every controlled task.

The worker edits files and reports execution output. Dispatcher performs the final run accounting:

- capture stdout and stderr logs
- detect changed files
- produce run artifacts
- apply Dispatcher-owned Git add and commit when changes exist
- record commit hash or no-change state
- record optional push state
- record working-tree state
- write `result.json` and `summary.md`

Codex does not own final Git control. ChatGPT does not treat browser delivery as finalization. A run is reviewable when the persisted result records a terminal execution state and the relevant artifacts are available.

## 12. Automated Test Baseline

The standard automated baseline is:

```powershell
npm test
```

It runs:

```powershell
npm run test:unit
npm run test:integration
npm run smoke:local
```

Additional operator-facing validation:

```powershell
npm run build
npm run mcp:smoke
npm run mcp:http:smoke
git diff --check
```

Automated coverage includes:

- result contract compatibility
- MCP contract and approved tool surface
- safety field validation
- delivery state separation
- persisted result retrieval
- dispatcher lifecycle behavior
- Git commit and push boundary behavior through temporary fixtures
- bridge/MCP smoke behavior

The automated baseline does not cover browser DOM typing, ChatGPT page behavior, Windows lock-screen browser interaction, public HTTPS tunnel behavior, real remote push, distributed execution, scheduling, cancellation, or invalid terminal transition APIs that do not exist in the approved runtime.

## 13. Launcher Role

The launcher is an environment helper, not an orchestrator.

Current launcher responsibilities:

- load local launcher config
- print a resolved startup plan
- start explicitly enabled local services in separate PowerShell windows
- run configured local health checks
- mask configured header values in output

Launcher boundaries:

- does not invoke Codex
- does not dispatch tasks
- does not modify Dispatcher core
- does not modify MCP runtime behavior
- does not create schedulers
- does not deploy cloud resources
- does not expose Dispatcher Bridge port `8787`
- does not log secret header values

## 14. Safety Boundaries

Current safety boundaries:

- keep Dispatcher Bridge bound to localhost
- never expose or tunnel port `8787`
- expose port `8790` only for approved controlled MCP testing
- keep the MCP tool surface limited to the four approved tools
- require explicit task scope and blocked areas
- require explicit validation expectations
- use `repo: self` for the minimal MCP dispatch boundary
- use only `worker: codex` through MCP
- do not commit secrets or real local tokens
- do not add scheduler behavior
- do not add autonomous chaining
- do not add distributed workers
- do not add browser redesign
- do not add public remote execution
- do not push or tag unless explicitly authorized

## 15. Known Limitations

Known current limitations:

- browser postback is not reliable while Windows is locked
- browser postback queue and active typing state are in-memory
- active bridge task state does not survive bridge restart
- completed persisted results remain recoverable after restart
- cancellation is not exposed as an approved public MCP operation
- no scheduler or queue is implemented in the approved runtime
- no distributed worker routing is implemented
- no P4 controlled orchestration is implemented
- MCP dispatch is intentionally limited to `repo: self` and `worker: codex`
- public exposure of the raw Dispatcher Bridge remains forbidden

## 16. Deferred Candidate: Controlled Orchestration

Future controlled orchestration is only a deferred candidate. It is not part of the v0.8.0 P0-P3 baseline.

Any future orchestration proposal must preserve:

- explicit user or ChatGPT approval boundaries
- narrow tool surface
- persisted result review before follow-on work
- execution and delivery status separation
- no public `8787` exposure
- no secrets in repo
- deterministic Git control
- test coverage for new state transitions

Deferred candidates include controlled queues, controlled multi-step task plans, browser-independent notification, and other P4-style orchestration ideas. None are implemented or authorized by this design.

## 17. Historical Notes

Earlier versions of this design described MCP, local bridge result APIs, token hardening, and result contracts as future Phase 3 work. That is now obsolete for the v0.8.0 baseline: local bridge, MCP adapter, approved MCP tools, persistent result retrieval, token-aware bridge calls, execution/delivery status separation, and automated tests are implemented.

Earlier append-only sections also described broad worker adapter layers, multiple named future workers, GitHub issue bridges, bot bridges, tunnels, dashboards, schedulers, and multi-agent routing as possible future options. These are not current architecture. They are either historical exploration or deferred candidates and must not be read as implemented or approved runtime behavior.

The preserved operating principle is:

```text
ChatGPT decides.
Dispatcher executes.
Codex edits.
Git controls.
Result persists.
Delivery notifies when available.
ChatGPT retrieves and reviews.
```

The key rule is:

```text
Execution truth must never depend on browser delivery success.
```
