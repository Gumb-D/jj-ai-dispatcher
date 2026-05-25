
```text
D:\dev\projects\jj-ai-dispatcher\source\TECHNICAL_DESIGN_CHATGPT_DISPATCHER_BRIDGE.md
```

````markdown
# JJ AI Dispatcher — ChatGPT to Dispatcher Technical Design

## 1. Project Purpose

JJ AI Dispatcher 的目标不是让 Codex 自己决定做什么。

目标是建立一个执行体系：

```text
JJ / ChatGPT = Brain
Dispatcher = Execution Controller
Codex = Coding Worker
Git = Control Point
````

ChatGPT 负责理解目标、判断方向、拆任务、定义边界、输出 worker prompt。

Codex 只负责根据明确任务修改文件。

Dispatcher 负责接收任务、调用 Codex、管理日志、执行 git commit、可选 push、输出结果。

---

## 2. Core Problem

当前已经完成：

```text
Dispatcher → Codex → Git
```

但还没有完成：

```text
ChatGPT → Dispatcher
```

目前实际流程仍然是：

```text
User tells ChatGPT goal
↓
ChatGPT writes task / command
↓
User copies command manually
↓
Dispatcher runs Codex
↓
User pastes result back to ChatGPT
↓
ChatGPT reviews result
```

目标是逐步减少人工复制动作，最终实现：

```text
User tells ChatGPT goal
↓
ChatGPT dispatches task to Dispatcher
↓
Dispatcher runs Codex
↓
Dispatcher returns result
↓
ChatGPT reviews and decides next action
```

---

## 3. Role Definition

### 3.1 ChatGPT Brain

Responsibilities:

```text
- Understand user intent
- Decide whether task should be done
- Define scope
- Define blocked areas
- Write Codex worker prompt
- Define validation steps
- Review Dispatcher / Codex result
- Decide next phase
```

ChatGPT must not be treated as a simple prompt generator.

ChatGPT is the project brain and task director.

---

### 3.2 Dispatcher

Responsibilities:

```text
- Receive task package
- Resolve target repo
- Select worker
- Write task files
- Invoke Codex CLI
- Capture logs
- Detect file changes
- Execute git add / commit
- Optional auto push
- Produce result summary
```

Dispatcher owns orchestration and git operations.

---

### 3.3 Codex

Responsibilities:

```text
- Read task prompt
- Modify files
- Run requested validation if possible
- Report what changed
```

Codex must not own final git control.

Codex is a coder, not the project brain.

---

### 3.4 Git

Responsibilities:

```text
- Source control
- Audit trail
- Recovery point
- Backup via remote push
```

Every meaningful execution should end with a clean working tree or clear failure state.

---

## 4. Current Implemented Flow

Current working flow:

```text
.\dispatcher\ask self "task" -m "commit message"
↓
ask.ps1 writes task into dispatcher inbox
↓
run.ps1 codex_task executes Codex
↓
Codex edits files
↓
Dispatcher commits changes
↓
Optional auto push
```

Implemented features:

```text
- dispatcher core
- shared config loader
- config.local override
- env_check
- menu loop
- logging
- Codex task mode
- target repo override
- dispatcher-owned git commit
- optional auto push
- safety guards
- GitHub backup
- ask.ps1 CLI prompt mode
- repo alias support
- better ask UX
- custom commit message support
```

Supported CLI:

```powershell
.\dispatcher\ask "update README"
.\dispatcher\ask self "update README"
.\dispatcher\ask D:\dev\projects\other-repo "update README"
.\dispatcher\ask -repo self "update README"
.\dispatcher\ask self "update README" -m "docs: update README"
```

---

## 5. Required Future Flow

Target technical flow:

```text
ChatGPT Brain
↓
Bridge Channel
↓
Dispatcher
↓
Codex CLI
↓
Target Repo
↓
Dispatcher Git Commit
↓
Result Artifact
↓
ChatGPT Brain Review
```

The missing component is:

```text
Bridge Channel
```

---

## 6. ChatGPT to Dispatcher Communication Options

### Option A — Manual Command Bridge

Current available method.

Flow:

```text
ChatGPT outputs dispatcher command
↓
User copies command
↓
PowerShell executes command
↓
Dispatcher runs Codex
```

Example:

```powershell
.\dispatcher\ask self "update README usage section" -m "docs: update README usage"
```

Pros:

```text
- Already works
- Safe
- No network exposure
- Fast to use today
```

Cons:

```text
- User still copies command manually
- ChatGPT cannot directly execute
```

Status:

```text
Current MVP
```

---

### Option B — Local HTTP Bridge

Flow:

```text
ChatGPT-compatible tool / connector
↓
POST http://127.0.0.1:8787/dispatch
↓
Dispatcher Bridge Server
↓
dispatcher/run.ps1
↓
Codex
```

Request example:

```json
{
  "repo": "self",
  "worker": "codex",
  "task": "update README usage section",
  "commitMessage": "docs: update README usage"
}
```

Pros:

```text
- Clean technical interface
- Can be connected later to MCP, tunnel, bot, or custom action
- Easy to test locally
```

Cons:

```text
- ChatGPT cannot directly access localhost without extra connector
- Needs token safety
- Needs result API
```

Status:

```text
Recommended Phase 3 foundation
```

---

### Option C — MCP Tool

Flow:

```text
ChatGPT
↓
MCP tool
↓
Dispatcher MCP server
↓
Dispatcher
↓
Codex
```

Pros:

```text
- Closest to true “ChatGPT directly talks to Dispatcher”
- Clean tool-based integration
```

Cons:

```text
- Requires ChatGPT MCP/custom connector support
- Requires endpoint accessibility
- More setup complexity
```

Status:

```text
Future integration target
```

---

### Option D — GitHub Issue Bridge

Flow:

```text
ChatGPT creates / prepares issue
↓
Dispatcher polls GitHub issue
↓
Dispatcher runs Codex
↓
Dispatcher comments result
```

Pros:

```text
- Strong audit trail
- No local port exposure
- Good for async workflow
```

Cons:

```text
- Slower
- Requires GitHub token
- More moving parts
```

Status:

```text
Alternative if local bridge is blocked
```

---

### Option E — Bot Bridge

Flow:

```text
ChatGPT / User sends command to Telegram / WhatsApp
↓
Bot listener receives command
↓
Dispatcher runs Codex
↓
Bot sends result
```

Pros:

```text
- Mobile friendly
- Useful for remote control
```

Cons:

```text
- Requires bot setup
- Requires security controls
```

Status:

```text
Optional later
```

---

## 7. Recommended Direction

The project should proceed in this order:

```text
Phase 1 — Dispatcher execution and git control
Status: completed

Phase 2 — Operator CLI
Status: mostly completed

Phase 3 — Result Contract and Local Bridge Foundation
Status: next

Phase 4 — ChatGPT Tool Integration
Status: future
```

Do not jump directly to UI, scheduler, distributed agents, VM remote execution, or digital twin.

The correct next technical milestone is:

```text
Phase 3.0 — Result Contract
Phase 3.1 — Local Bridge Server
Phase 3.2 — Dispatch API
Phase 3.3 — Result API
Phase 3.4 — Safety Token
```

---

## 8. Dispatcher to Codex Communication

Dispatcher should communicate with Codex through CLI execution, not Codex chat UI.

Current concept:

```text
dispatcher/run.ps1 codex_task
↓
read dispatcher/inbox/codex-task.txt
↓
read optional dispatcher/inbox/codex-task.repo.txt
↓
read optional dispatcher/inbox/codex-task.commit.txt
↓
cd target repo
↓
invoke Codex CLI
↓
Codex edits files
↓
Dispatcher checks git diff
↓
Dispatcher commits
↓
optional push
```

Codex task file:

```text
dispatcher/inbox/codex-task.txt
```

Repo override file:

```text
dispatcher/inbox/codex-task.repo.txt
```

Commit message file:

```text
dispatcher/inbox/codex-task.commit.txt
```

---

## 9. Result Feedback Design

Codex feedback must not rely only on console text.

Dispatcher should generate machine-readable run artifacts.

Recommended run folder:

```text
dispatcher/runs/<task-id>/
```

Example:

```text
dispatcher/runs/20260525-153012/
├─ task.json
├─ codex-output.log
├─ codex-error.log
├─ git-diff.patch
├─ result.json
└─ summary.md
```

---

## 10. task.json Contract

Example:

```json
{
  "taskId": "20260525-153012",
  "createdAt": "2026-05-25T15:30:12+08:00",
  "repo": "self",
  "resolvedRepo": "D:\\dev\\projects\\jj-ai-dispatcher",
  "worker": "codex",
  "task": "update README usage section",
  "commitMessage": "docs: update README usage",
  "requestedBy": "chatgpt",
  "scope": ["README.md"],
  "blocked": ["API", "UI", "scheduler", "distributed architecture"]
}
```

---

## 11. result.json Contract

Example success:

```json
{
  "taskId": "20260525-153012",
  "status": "success",
  "repo": "D:\\dev\\projects\\jj-ai-dispatcher",
  "worker": "codex",
  "filesChanged": ["README.md"],
  "commit": "2ae9e6f",
  "commitMessage": "docs: update README usage",
  "pushed": false,
  "workingTreeClean": true,
  "summary": "README usage section updated.",
  "logs": {
    "stdout": "dispatcher/runs/20260525-153012/codex-output.log",
    "stderr": "dispatcher/runs/20260525-153012/codex-error.log",
    "diff": "dispatcher/runs/20260525-153012/git-diff.patch"
  }
}
```

Example failure:

```json
{
  "taskId": "20260525-153012",
  "status": "failed",
  "repo": "D:\\dev\\projects\\jj-ai-dispatcher",
  "worker": "codex",
  "error": "Codex execution failed.",
  "commit": null,
  "pushed": false,
  "workingTreeClean": false,
  "logs": {
    "stdout": "dispatcher/runs/20260525-153012/codex-output.log",
    "stderr": "dispatcher/runs/20260525-153012/codex-error.log"
  }
}
```

---

## 12. summary.md Contract

Example:

```markdown
# Dispatcher Run Summary

Task ID: 20260525-153012  
Status: success  
Repo: D:\dev\projects\jj-ai-dispatcher  
Worker: codex  

## Task

Update README usage section.

## Files Changed

- README.md

## Commit

2ae9e6f docs: update README usage

## Validation

- git status --short clean
- README updated only

## Notes

No API, UI, scheduler, or distributed logic added.
```

This file is the easiest artifact for the user to paste back into ChatGPT during manual feedback phase.

---

## 13. Local Bridge Server Design

Bridge server should be small and local-first.

Recommended endpoints:

```text
POST /dispatch
GET  /status
GET  /runs/latest
GET  /runs/{taskId}
```

---

### 13.1 POST /dispatch

Purpose:

```text
Receive task from ChatGPT-compatible channel and trigger dispatcher.
```

Request:

```json
{
  "repo": "self",
  "worker": "codex",
  "task": "update README usage section",
  "commitMessage": "docs: update README usage",
  "scope": ["README.md"],
  "blocked": ["API", "UI", "scheduler"]
}
```

Response:

```json
{
  "accepted": true,
  "taskId": "20260525-153012",
  "status": "running",
  "resultPath": "dispatcher/runs/20260525-153012/result.json"
}
```

---

### 13.2 GET /status

Purpose:

```text
Return dispatcher health and config summary.
```

Response:

```json
{
  "status": "ok",
  "dispatcherRoot": "D:\\dev\\projects\\jj-ai-dispatcher",
  "defaultWorker": "codex",
  "autoPush": false,
  "availableAliases": ["self", "toonflow", "pr"]
}
```

---

### 13.3 GET /runs/latest

Purpose:

```text
Return latest run result.
```

Response:

```json
{
  "taskId": "20260525-153012",
  "status": "success",
  "commit": "2ae9e6f",
  "filesChanged": ["README.md"],
  "summary": "README usage section updated."
}
```

---

### 13.4 GET /runs/{taskId}

Purpose:

```text
Return specific run result.
```

Response:

```json
{
  "taskId": "20260525-153012",
  "status": "success",
  "repo": "D:\\dev\\projects\\jj-ai-dispatcher",
  "filesChanged": ["README.md"],
  "commit": "2ae9e6f",
  "workingTreeClean": true
}
```

---

## 14. Safety Design

Bridge must never expose arbitrary shell execution.

Allowed:

```text
- dispatch codex task
- read status
- read run result
```

Blocked:

```text
- arbitrary PowerShell command
- arbitrary file read
- arbitrary file write
- delete operation
- remote execution without explicit future design
```

Required protections:

```text
- localhost binding by default
- token required for API calls
- repo must resolve to configured alias or valid allowed path
- worker must be from allowed worker list
- task cannot be empty
- commit message cannot be empty if provided
- logs must not expose secrets
```

Token header example:

```text
X-Dispatcher-Token: <local-token>
```

---

## 15. Configuration Design

Suggested config:

```json
{
  "defaultWorker": "codex",
  "defaultRepo": "D:\\dev\\projects\\jj-ai-dispatcher",
  "autoPush": false,
  "bridge": {
    "enabled": true,
    "host": "127.0.0.1",
    "port": 8787,
    "requireToken": true
  },
  "repoAliases": {
    "self": "D:\\dev\\projects\\jj-ai-dispatcher",
    "toonflow": "D:\\dev\\projects\\toonfloow",
    "pr": "D:\\dev\\projects\\create-pr-cd"
  },
  "allowedWorkers": ["codex"]
}
```

Local secrets should stay in:

```text
dispatcher/config.local.json
```

Do not commit real tokens.

---

## 16. ChatGPT Command Envelope

When ChatGPT prepares a task for Dispatcher, use this structure:

```json
{
  "repo": "self",
  "worker": "codex",
  "task": "Specific work instruction.",
  "commitMessage": "type: short commit message",
  "scope": ["allowed file or folder"],
  "blocked": ["forbidden area"],
  "validation": ["validation command or expected check"],
  "expectedOutput": ["files changed", "commit hash", "final status"]
}
```

This keeps ChatGPT as the brain and Codex as the worker.

---

## 17. Phase Plan

### Phase 1 — Dispatcher Core

Status:

```text
COMPLETED
```

Delivered:

```text
✓ dispatcher core
✓ codex worker
✓ shared config loader
✓ config.local override
✓ env_check
✓ menu loop
✓ logging
✓ target repo override
✓ dispatcher-owned git commit
✓ optional auto push
✓ safety guards
✓ GitHub backup
```

---

### Phase 2A — Operator CLI

Status:

```text
COMPLETED
```

Delivered:

```text
✓ CLI Prompt Mode
✓ Repo Alias Mode
✓ Better Ask UX
✓ Commit Message UX
✓ README Usage Snapshot
```

Supported syntax:

```powershell
.\dispatcher\ask "task"

.\dispatcher\ask self "task"

.\dispatcher\ask <repo-path> "task"

.\dispatcher\ask -repo self "task"

.\dispatcher\ask self "task" -m "commit message"
```

---

### Phase 2B

Status:

```text
DEFERRED
```

Candidate scope:

```text
- repo alias config file
```

Reason:

```text
Current bottleneck is no longer CLI ergonomics.

Priority shifted to:
feedback loop + bridge architecture.
```

---

### Phase 3 — Feedback + Bridge Foundation

Status:

```text
NEXT
```

Immediate sequence:

```text
3.0 Run Result Contract
3.1 Local Bridge Foundation
3.2 Dispatch API
3.3 Result API
3.4 Token Safety
```

---

## 18. Non-Goals

Do not implement these until bridge foundation is stable:

```text
- Web UI
- scheduler
- digital twin
- distributed worker
- VM remote execution
- agent mesh
- multi-agent planner
- browser automation
```

---

## 19. Design Principle

The project must follow this principle:

```text
ChatGPT decides.
Dispatcher executes.
Codex edits.
Git controls.
Result returns.
```

Any feature that does not improve this loop should be delayed.

---

## 20. Current Next Action

Recommended next Codex task:

```text
Implement Phase 3.0 Run Result Contract.

Goal:
Every dispatcher codex_task run must produce:
- dispatcher/runs/<task-id>/task.json
- dispatcher/runs/<task-id>/result.json
- dispatcher/runs/<task-id>/summary.md
- stdout/stderr logs if available
- git diff patch if changes exist

Do not add HTTP bridge yet.
Do not add API yet.
First standardize result output.
```

Reason:

```text
Before ChatGPT can receive feedback automatically, Dispatcher must produce a clean result artifact.
```

````markdown
## 21. How ChatGPT Actually Talks to Dispatcher

There are two stages.

### Stage 1 — Current Manual Relay

ChatGPT cannot directly access the user's local machine.

Current practical loop:

```text
ChatGPT prepares dispatcher command
↓
User copies command into PowerShell
↓
Dispatcher runs Codex
↓
Dispatcher outputs result summary
↓
User pastes result summary back to ChatGPT
````

This is acceptable only as temporary MVP.

### Stage 2 — Tool-Based Relay

The final goal requires ChatGPT to access Dispatcher through an approved tool channel.

Supported future tool channels:

```text
- MCP tool
- Custom action
- HTTPS bridge endpoint
- GitHub issue bridge
- Bot bridge
```

The preferred technical target is:

```text
ChatGPT Tool Call
↓
HTTPS / MCP endpoint
↓
Local Dispatcher Bridge
↓
Dispatcher run
↓
Result JSON returned
```

The bridge must never expose arbitrary shell execution.

It should expose only:

```text
- dispatch task
- get status
- get latest run result
- get specific run result
```

---

## 22. Integration Decision Matrix

| Option              |    Can ChatGPT trigger directly? |     Security Risk | Setup Difficulty | Recommended Use       |
| ------------------- | -------------------------------: | ----------------: | ---------------: | --------------------- |
| Manual Command      |                               No |               Low |              Low | Current temporary MVP |
| Local HTTP only     |                No, not by itself |            Medium |           Medium | Foundation layer      |
| Local HTTP + Tunnel | Yes, if connected as tool/action | High if unsecured |           Medium | Fast MVP with token   |
| MCP Tool            |                              Yes |            Medium |      Medium/High | Final preferred path  |
| GitHub Issue Bridge |                         Indirect |        Low/Medium |           Medium | Safe async fallback   |
| Bot Bridge          |                         Indirect |            Medium |           Medium | Mobile/remote control |

Recommended order:

```text
1. Result Contract
2. Local HTTP Bridge
3. Token Safety
4. Status / Result API
5. MCP or HTTPS Tool Integration
```

Final target:

```text
ChatGPT should call Dispatcher as a tool.
Dispatcher should call Codex as a worker.
Codex should never control the project direction.
```

## 23. Dispatcher Internal Architecture

Dispatcher internal modules:

```text
Dispatcher
├─ ConfigLoader
│    load config + local override
│
├─ TaskManager
│    task lifecycle + run tracking
│
├─ WorkerRouter
│    worker selection
│
├─ WorkerAdapters
│    CodexAdapter
│    OpenClawAdapter
│    MTGravityAdapter
│    ColdClawAdapter
│
├─ GitController
│    add / commit / push
│
├─ ResultWriter
│    task.json
│    result.json
│    summary.md
│
├─ BridgeServer
│    dispatch API
│
└─ Logger
     runtime logs
```

## ADR-0001 Bridge Strategy

Official Phase 3 bridge:

```text
Local HTTP Bridge
```

Constraints:

```text
- localhost only
- token required
- single active task
- codex worker only initially
```

Deferred:

```text
- MCP
- tunnel
- GitHub bridge
- bot bridge
```

Reason:

```text
Need stable local bridge foundation before integration layer.
```

## 24. Worker Adapter Layer

Dispatcher must not directly hardcode Codex execution logic.

Dispatcher should communicate through worker adapters.

Architecture:

```text
Dispatcher
↓
WorkerRouter
├─ CodexAdapter
├─ OpenClawAdapter
├─ MTGravityAdapter
├─ ColdClawAdapter
└─ FutureAdapter
```

Worker contract:

Input:

```json
{
  "worker":"codex",
  "repo":"self",
  "task":"update README"
}
```

Output:

```json
{
  "status":"success",
  "stdout":"...",
  "stderr":"...",
  "filesChanged":[]
}
```

Reason:

```text
Dispatcher is a controller.

Codex is only one worker implementation.

Future workers must be pluggable without dispatcher refactor.
```

## 25. Task Lifecycle Model

Every Dispatcher run must follow an explicit lifecycle.

State model:

```text
queued
↓
running
↓
success
OR
failed
OR
cancelled
```

Optional future states:

```text
retrying
timeout
```

Recommended result fields:

```json
{
  "taskId":"20260525-153012",
  "status":"running",
  "createdAt":"",
  "startedAt":"",
  "completedAt":"",
  "durationMs":0
}
```

Reason:

```text
Bridge APIs require formal task state tracking.
```

## 26. Dispatcher Execution Policy

Phase 3 policy:

single active task

If dispatcher already running:

reject new dispatch request.

HTTP response:

409 Conflict

Future queue:

```text
Phase 4 candidate
```

Not implemented in Phase 3.

## 27. Brain ⇄ Dispatcher Feedback Contract

Dispatcher artifacts are not only logs.

They exist to support ChatGPT review.

Recommended result fields:

```json
{
  "needsReview":true,
  "reviewHints":[
      "validation failed",
      "README only changed"
  ],
  "nextSuggestedAction":"review"
}
```

Purpose:

```text
ChatGPT Brain consumes dispatcher output
and decides next action.
```

Flow:

```text
Dispatcher
↓
result.json
↓
ChatGPT review
↓
next task decision
```

## 28. Worker Result Contract

Worker adapters must return a normalized result object.

Schema:

```json
{
  "worker":"codex",
  "status":"success",
  "stdout":"...",
  "stderr":"...",
  "filesChanged":[
      "README.md"
  ],
  "validationAttempted":true,
  "validationPassed":true
}
```

Dispatcher consumes worker result and produces:

```text
result.json
summary.md
git operations
```

Reason:

```text
Worker adapters should not own dispatcher result format.
```

## 29. Phase 3 Deliverable Boundary

Phase 3 implementation MUST deliver:

✓ dispatcher/runs/<task-id>/

✓ task.json

✓ result.json

✓ summary.md

✓ worker result normalization

✓ Local HTTP bridge

✓ POST /dispatch

✓ GET /status

✓ GET /runs/latest

✓ localhost only

✓ token required

✓ single active task

Phase 3 MUST NOT deliver:

✗ MCP

✗ tunnel

✗ GitHub bridge

✗ bot bridge

✗ multi-worker scheduling

✗ distributed execution

✗ VM dispatch