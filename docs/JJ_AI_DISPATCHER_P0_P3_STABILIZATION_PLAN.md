# JJ AI Dispatcher — P0–P3 Stabilization Plan

## 1. Document Purpose

This document records the approved stabilization scope for JJ AI Dispatcher before further autonomous capability expansion.

It is intended to become a project source document under:

```text
source/JJ_AI_DISPATCHER_P0_P3_STABILIZATION_PLAN.md
```

The purpose is to provide ChatGPT, Dispatcher, Codex, and the project operator with one agreed reference for:

- current architecture standing
- known limitations
- P0–P3 implementation scope
- execution order
- acceptance criteria
- safety boundaries
- MCP task packaging
- completion evidence

This document does not authorize implementation by itself. Implementation will be executed later through JJ Dispatcher MCP using explicit task envelopes.

---

## 2. Current Architecture Standing

The current runtime chain is:

```text
ChatGPT
   ↓ MCP HTTPS / approved connector
MCP HTTP Adapter :8790
   ↓ localhost
Dispatcher Bridge :8787
   ↓
Codex Worker
   ↓
Git commit / optional push
   ↓
Persistent run result
   ↓
Optional browser-visible postback
```

Current role model:

```text
ChatGPT = Brain
Dispatcher MCP = Tool Channel
Dispatcher = Execution Controller
Codex = Coding Worker
Git = Control Point
Launcher = Environment Startup Helper
Browser Postback = Optional Delivery Channel
```

The project has already validated:

```text
- local Dispatcher execution
- Codex task execution
- Dispatcher-owned Git commit
- MCP status / dispatch / result tools
- ChatGPT-to-Dispatcher MCP path
- persistent result retrieval
- browser-visible postback while Windows is unlocked
- launcher startup and health-check workflow
```

The project has also confirmed this limitation:

```text
Windows lock screen does not reliably support browser DOM typing and send-button interaction.
```

Therefore:

```text
Execution may continue while Windows is locked.
Browser postback is not lock-screen tolerant.
```

---

## 3. Stabilization Objective

Before adding broader autonomous features, the project must establish this reliable baseline:

```text
Task execution succeeds or fails independently.
Result is persistently stored.
Execution state is accurate.
Delivery state is tracked separately.
Result can be retrieved after unlock or restart.
Documentation matches actual implementation.
Tests validate the critical state transitions.
```

The stabilization scope is divided into:

```text
P0 — Documentation and Current Standing Consolidation
P1 — Execution and Delivery Status Separation
P2 — Persistent Result Retrieval as Primary Recovery Path
P3 — Automated Test Baseline
```

---

# P0 — Documentation and Current Standing Consolidation

## 4. P0 Goal

Create one accurate representation of the current product, architecture, maturity level, known limitations, versioning, and operator flow.

P0 is documentation and metadata alignment only unless a small code metadata change is explicitly required for version consistency.

## 4.1 Required Changes

Update and consolidate the following areas:

```text
README.md
package.json
MCP server version metadata
relevant architecture / operator documents
project source index if present
```

The documentation must accurately describe:

- current runtime chain
- current role model
- MCP tool surface
- Dispatcher Bridge and MCP Adapter boundaries
- Launcher role
- browser postback role
- lock-screen limitation
- current maturity level
- current phase and next milestone
- release/version convention
- current recovery flow

## 4.2 Product Definition

Use this product definition:

> JJ AI Dispatcher is a local-first, safety-controlled AI coding dispatcher with ChatGPT MCP initiation, Codex execution, Dispatcher-owned Git control, persistent run results, and optional browser-visible postback.

It is not yet:

```text
- a fully autonomous AI employee
- a general remote desktop controller
- a production multi-user platform
- a distributed agent system
- a guaranteed lock-screen browser automation system
- a review-free autonomous coding platform
```

## 4.3 Version Alignment

Current version references must be reviewed and made consistent across:

```text
- README current release
- package.json version
- MCP server version
- Git tag / documented baseline
- run metadata where applicable
```

Recommended approach:

```text
Adopt one pre-release baseline version for the stabilized architecture.
Example: 0.4.0
```

The implementation task may select another version only if repository history supports a clearer convention.

## 4.4 README Cleanup

Remove obsolete or misleading content, including:

```text
- outdated phase standing
- outdated baseline commit references
- stale "next milestone" text
- accumulated append-only validation notes that no longer belong in the main README
```

Historical validation records should be moved into an appropriate development log or retained in Git history.

## 4.5 P0 Acceptance Criteria

P0 is complete when:

```text
- README matches current architecture
- lock-screen behavior is documented correctly
- browser postback is described as optional delivery
- version references are internally consistent
- current milestone and maturity are clear
- obsolete README test notes are removed or relocated
- no runtime behavior is changed unintentionally
- validation commands pass
- Dispatcher commits the changes
- working tree is clean
```

---

# P1 — Execution and Delivery Status Separation

## 5. P1 Goal

Ensure task execution status is never overwritten or misrepresented by browser postback failure.

The execution outcome and the result-delivery outcome must be separate concerns.

## 5.1 Required Status Model

Introduce or standardize two independent status domains.

### Execution Status

```text
queued
running
success
failed
cancelled
```

Optional future execution states:

```text
timeout
retrying
```

### Delivery Status

```text
not_requested
pending
delivered
timeout
failed
skipped
unavailable
```

## 5.2 Required Behavioral Rule

The following rule is mandatory:

```text
If Codex execution and Dispatcher Git handling complete successfully,
executionStatus must remain success even when browser postback fails.
```

Browser postback failure may change only delivery-related fields.

Incorrect behavior:

```text
execution succeeded
+ postback timeout
= overall task failed
```

Correct behavior:

```text
executionStatus = success
deliveryStatus = timeout
```

## 5.3 Result Contract

The normalized run result should support fields equivalent to:

```json
{
  "taskId": "20260605-xxxxxx",
  "status": "success",
  "executionStatus": "success",
  "deliveryStatus": "timeout",
  "deliveryChannel": "browser_postback",
  "deliveryRequired": false,
  "needsReview": true,
  "summary": "Task completed and committed. Browser postback timed out.",
  "commit": "abcdef1",
  "workingTreeClean": true
}
```

Compatibility may require retaining the existing `status` field. If retained:

```text
status must represent execution outcome, not browser delivery outcome.
```

Existing run artifacts that only contain `status` remain readable. Result readers should default `executionStatus` from `status`, default `deliveryStatus` to `not_requested`, default `deliveryChannel` to `null`, and default `deliveryRequired` to `false`.

## 5.4 State Transition Requirements

Required execution transitions:

```text
queued → running → success
queued → running → failed
queued → cancelled
```

Required delivery transitions:

```text
not_requested
pending → delivered
pending → timeout
pending → failed
pending → unavailable
pending → skipped
```

Invalid transitions must not silently overwrite terminal execution states.

## 5.5 Postback Behavior

Browser postback must be treated as:

```text
optional convenience notification
```

It must not be treated as:

```text
- proof that task execution succeeded
- a required step for task completion
- the only result retrieval path
- a reason to mark execution failed
```

## 5.6 Logging and Summary Requirements

The run summary must clearly distinguish:

```text
Execution: SUCCESS
Delivery: TIMEOUT
Recovery: result available through MCP dispatcher_get_run / dispatcher_latest_result
```

Operator-facing messages should avoid ambiguous wording such as only `Task failed` when the execution itself succeeded.

## 5.7 P1 Acceptance Criteria

P1 is complete when:

```text
- execution and delivery states are separate in code and artifacts
- successful execution remains success after postback timeout
- failure summaries identify whether failure is execution or delivery
- existing MCP result tools return the separated statuses
- old run compatibility is handled safely
- state transitions are deterministic
- validation commands pass
- Dispatcher commits the changes
- working tree is clean
```

---

# P2 — Persistent Result Retrieval as Primary Recovery Path

## 6. P2 Goal

Formalize MCP result retrieval as the primary recovery method when browser postback is unavailable, especially after Windows lock, browser suspension, extension interruption, or operator absence.

## 6.1 Primary Recovery Model

The approved recovery flow is:

```text
Task dispatched
↓
Dispatcher / Codex continues execution
↓
Result persisted in run artifacts
↓
Browser postback may succeed or fail
↓
Operator returns / unlocks Windows
↓
ChatGPT calls dispatcher_latest_result or dispatcher_get_run
↓
ChatGPT reviews result and decides next action
```

## 6.2 MCP Tool Roles

The existing tools must be treated as follows:

```text
dispatcher_status
- confirms bridge readiness and current state

dispatcher_dispatch
- submits one explicit approved task

dispatcher_latest_result
- retrieves the most recent persisted run result

dispatcher_get_run
- retrieves a specific run by task ID
```

## 6.3 Persistence Requirements

A completed run must remain retrievable after:

```text
- browser postback timeout
- browser extension reload
- ChatGPT page refresh
- Windows unlock
- temporary client disconnection
- MCP client reconnection
- Dispatcher restart, where existing architecture permits persisted-run reload
```

P2 must verify actual behavior and document any restart limitation honestly.

## 6.4 Recovery Information

A retrieved result should provide enough information for ChatGPT review:

```text
- taskId
- repo
- worker
- executionStatus
- deliveryStatus
- createdAt / startedAt / completedAt
- filesChanged
- commit hash
- commit message
- pushed state
- workingTreeClean
- validation result
- summary
- error details, if any
- run artifact paths or references
- needsReview
- suggested next action, if supported
```

## 6.5 Operator Documentation

Document a practical locked-screen workflow:

```text
1. Dispatch the approved task.
2. Windows may be locked after execution begins if local worker behavior permits.
3. Do not expect browser typing while locked.
4. After unlocking, confirm MCP connectivity.
5. Call dispatcher_latest_result.
6. If needed, call dispatcher_get_run with the task ID.
7. Review execution and delivery statuses separately.
8. Continue only after result review.
```

## 6.6 P2 Acceptance Criteria

P2 is complete when:

```text
- latest result retrieval works after browser postback timeout
- specific run retrieval works by task ID
- result contains sufficient review information
- lock-screen recovery flow is documented
- browser postback is no longer the only practical feedback path
- unavailable persistence/restart behavior is documented accurately
- validation commands pass
- Dispatcher commits the changes
- working tree is clean
```

---

# P3 — Automated Test Baseline

## 7. P3 Goal

Create a real automated test baseline for critical Dispatcher, MCP, state, safety, and recovery behavior.

`node --check` remains useful for syntax validation but is not considered sufficient automated testing.

## 7.1 Required Test Layers

Recommended commands:

```text
npm test
npm run test:unit
npm run test:integration
npm run smoke:local
```

Exact command names may be adjusted to fit the repository, but there must be one standard top-level command that runs the required test baseline.

## 7.2 Minimum Required Test Cases

### Safety and Schema

```text
- empty task rejected
- invalid worker rejected
- unsafe dispatch rejected
- required safety fields validated
- raw arbitrary shell execution remains unavailable
- token/authentication behavior validated where testable
```

### Execution Lifecycle

```text
- queued to running to success
- queued to running to failed
- cancellation behavior if implemented
- duplicate or invalid terminal transition rejected
```

### Execution and Delivery Separation

```text
- execution success + postback delivered
- execution success + postback timeout
- execution success + postback unavailable
- execution failure + no misleading delivery override
```

### Result Retrieval

```text
- latest result returns correct run
- get run returns requested task ID
- missing task ID returns safe error
- persisted result remains readable after postback failure
- restart persistence behavior tested if supported
```

### Git Handling

```text
- changed files are committed by Dispatcher
- no-change run handled correctly
- commit failure is reported accurately
- auto-push disabled boundary respected
- auto-push enabled only when explicitly permitted
- working-tree-clean result is accurate
```

### Bridge and MCP

```text
- bridge status contract
- MCP tool registration
- MCP dispatch request formatting
- safe error conversion
- result schema compatibility
```

## 7.3 Test Isolation

Tests must not:

```text
- modify the real production checkout unexpectedly
- push to remote repositories
- expose port 8787 externally
- require real secrets committed to the repo
- depend on browser UI unless explicitly marked manual / optional
```

Use temporary directories, fixtures, mocks, or controlled test repositories where appropriate.

## 7.4 Manual Validation Classification

Browser lock-screen typing remains an environment-dependent manual validation case unless a safe automated harness exists.

It should be recorded separately as:

```text
Manual environment validation:
- unlocked browser postback
- Windows lock-screen postback timeout
- result recovery after unlock
```

Manual cases must not replace automated tests for the underlying execution and persistence logic.

## 7.5 P3 Acceptance Criteria

P3 is complete when:

```text
- one top-level test command exists
- critical state separation is covered
- result retrieval is covered
- safety validation is covered
- Git boundary behavior is covered
- tests do not push or expose unsafe endpoints
- syntax checks and smoke tests remain available
- test documentation explains unit, integration, smoke, and manual cases
- all required tests pass
- Dispatcher commits the changes
- working tree is clean
```

---

# 8. Implementation Order

The approved execution order is:

```text
P0
↓
review result
↓
P1
↓
review result
↓
P2
↓
review result
↓
P3
↓
final stabilization review
```

Do not dispatch P0–P3 as one large coding task.

Each priority must be executed as one or more controlled MCP tasks with review gates between them.

Recommended breakdown:

```text
P0.1 Current standing and README consolidation
P0.2 Version metadata alignment

P1.1 Status schema and result contract
P1.2 Postback state integration and operator messages

P2.1 Result retrieval verification and persistence hardening
P2.2 Recovery documentation and MCP operator workflow

P3.1 Test framework and fixtures
P3.2 State, safety, retrieval, and Git test coverage
P3.3 Standard test commands and documentation
```

The exact breakdown may be adjusted after repository inspection, but scope must remain within P0–P3.

---

# 9. Global Safety Boundaries

All P0–P3 tasks must follow these boundaries:

```text
- no arbitrary shell API
- no public exposure of Dispatcher Bridge port 8787
- only approved MCP adapter exposure on port 8790
- no real secrets or tokens committed
- no destructive delete operation unless specifically required and reviewed
- no automatic remote push unless explicitly authorized
- no scheduler
- no distributed worker architecture
- no VM remote execution feature
- no multi-agent planner
- no expansion of MCP tool surface without explicit approval
- no browser automation redesign in P0–P3
```

P0–P3 are stabilization work, not feature expansion.

---

# 10. MCP Execution Envelope Standard

Every implementation task must include:

```json
{
  "repo": "self",
  "worker": "codex",
  "task": "Specific implementation instruction.",
  "commitMessage": "type: concise commit message",
  "scope": [
    "explicit allowed files or folders"
  ],
  "blocked": [
    "explicit forbidden areas and behaviors"
  ],
  "validation": [
    "commands and expected checks"
  ],
  "expectedOutput": [
    "files changed",
    "test result",
    "commit hash",
    "execution status",
    "delivery status",
    "working tree state"
  ]
}
```

ChatGPT must review each result before issuing the next priority task.

---

# 11. Completion Evidence

Each completed task must return or preserve:

```text
- task ID
- execution status
- delivery status
- changed files
- commit hash
- validation commands
- validation results
- working tree status
- push status
- known limitations
- next recommended action
```

P0–P3 are considered fully completed only after a final review confirms:

```text
- documentation is accurate
- execution and delivery are decoupled
- results are recoverable without browser postback
- critical behavior has automated test coverage
- all changes are committed
- working tree is clean
```

---

# 12. Deferred Items

The following are explicitly deferred until P0–P3 stabilization is accepted:

```text
- autonomous multi-step sprint expansion
- unattended overnight task chaining
- VM or remote-host dispatch
- scheduler
- distributed workers
- multi-agent routing
- browser-independent proactive notification channel
- mobile bot integration
- GitHub issue bridge
- UI dashboard
- production multi-user support
```

A future phase may evaluate a browser-independent notification channel, but it is not part of P0–P3.

---

# 13. Final Stabilized Operating Principle

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
