# JJ AI Dispatcher Launcher — Technical Design & Task Plan (v2)

Status: MVP Complete
Version: 2.0
Last Updated: 2026-06-05

This document refreshes the original launcher technical design after completion of the Launcher MVP on 2026-06-05. It preserves the original rationale, safety model, architecture discussion, and phased planning record while adding the implementation status, accepted ADRs, completed deliverables, and actual commit history.

## 1. Project Name

`jj-ai-dispatcher-launcher`

## 2. Project Purpose

`jj-ai-dispatcher-launcher` 是 JJ AI Dispatcher 工作环境的启动器与操作入口。

它的目标是：

* 一键启动 JJ AI Dispatcher 相关本地服务
* 减少每天手动打开多个 terminal 的步骤
* 统一启动 Dispatcher Bridge、MCP HTTP Adapter、ngrok tunnel
* 执行基础 health check
* 支持本机、VM、cloud 环境迁移
* 保持 config-driven，避免写死本机路径和端口

它不是：

* Dispatcher 本体
* Codex worker
* MCP server 替代品
* 自动 agent
* scheduler
* cloud orchestration platform
* 任意 shell command executor

## 3. Role Model

```text
ChatGPT = Brain
JJ Dispatcher MCP = Tool Channel
Dispatcher = Execution Controller
Codex = Coding Worker
Git = Control Point
Launcher = Environment Startup Helper
```

Launcher 只负责启动和检查环境，不负责决定任务内容，不直接调用 Codex，不直接修改目标项目。

## 4. Target Runtime Chain

```text
User double-clicks launcher
↓
Launcher reads config
↓
Launcher starts Dispatcher Bridge
↓
Launcher starts MCP HTTP Adapter
↓
Launcher starts ngrok Tunnel
↓
Launcher performs health checks
↓
User / ChatGPT uses JJ Dispatcher MCP
↓
Dispatcher calls Codex
↓
Dispatcher commits result
↓
ChatGPT reviews result
```

## 5. v0.1 Scope

Implementation status:

```text
COMPLETE
```

The MVP was completed on 2026-06-05 as an internal `launcher/` subproject inside `jj-ai-dispatcher/`. The original v0.1 scope remains the baseline design intent; the implemented MVP now includes config loading, service startup, startup modes, health checks, operator documentation, and migration documentation.

### Included

v0.1 只实现最小可用启动器：

```text
README.md
.gitignore
start.bat
launcher.ps1
launcher.config.example.json
docs/launcher-plan.md
docs/operator-guide.md
docs/migration-guide.md
```

### v0.1 Capabilities

* Read launcher config
* Validate required paths
* Print resolved service startup plan
* Start enabled services in separate terminal windows
* Optionally open VS Code
* Run basic health checks
* Print pass/fail summary
* Provide clear next action to operator

### v0.1 Excluded

* No auto-push
* No delete operation
* No scheduler
* No background daemon
* No arbitrary command UI
* No direct Codex invocation
* No Git operation beyond normal repo commit by Dispatcher
* No cloud deployment automation
* No hardcoded local user path
* No exposure of raw Dispatcher Bridge to public network

## MVP Completion Status

Status:

```text
COMPLETE
```

Delivered:

```text
✓ Project skeleton
✓ Config loader
✓ launcher.config.local.json support
✓ Variable substitution
✓ Service startup
✓ PlanOnly mode
✓ HealthOnly mode
✓ Health checks
✓ PASS / FAIL / SKIP summary
✓ Operator guide
✓ Migration guide
```

## Current Operational Status

Status:

```text
READY FOR OPERATOR VALIDATION
```

Completed:

```text
✓ Config Loader
✓ Startup Modes
✓ Service Startup
✓ Health Checks
✓ Operator Documentation
```

Pending:

```text
□ End-to-end launcher execution test
□ v0.8-launcher-mvp tag
□ Standalone repo extraction decision
```

## 6. Service Scope

Launcher v0.1 should support these service entries:

Implementation note:

```text
Services are declared in launcher.config.local.json / launcher.config.example.json as entries in the services array.
Enabled services are started in separate PowerShell windows during normal startup.
Disabled services are skipped and shown in the startup plan.
```

### 6.1 Dispatcher Bridge

Purpose:

```text
Local bridge used by Dispatcher MCP / local tools.
```

Default command:

```powershell
.\dispatcher\bridge.ps1
```

Expected local endpoint:

```text
http://127.0.0.1:8787/status
```

Safety:

```text
Do not expose 8787 externally.
```

### 6.2 MCP HTTP Adapter

Purpose:

```text
Expose controlled MCP surface for ChatGPT connector.
```

Default command:

```powershell
npm run mcp:http
```

Expected local endpoint:

```text
http://127.0.0.1:8790/mcp
```

Safety:

```text
Only approved MCP tools should be exposed.
```

### 6.3 ngrok Tunnel

Purpose:

```text
Expose MCP HTTP Adapter for controlled ChatGPT testing.
```

Default command:

```powershell
ngrok http 8790 --host-header="localhost:8790"
```

Safety:

```text
Only tunnel MCP HTTP Adapter port 8790.
Never tunnel raw Dispatcher Bridge port 8787.
Stop ngrok when not testing.
```

### 6.4 VS Code

Purpose:

```text
Optional operator convenience.
```

Behavior:

```text
Open dispatcher repo and/or launcher repo when configured.
```

## 7. Configuration Design

Launcher must be config-driven.

Files:

```text
launcher.config.example.json
launcher.config.local.json
```

Rules:

* `launcher.config.example.json` is committed
* `launcher.config.local.json` is ignored by Git
* local paths, ports, commands, and environment-specific values live in local config
* future VM/cloud migration should require config changes only
* `${dispatcherRoot}` resolves to the parent JJ Dispatcher repository
* `${launcherRoot}` resolves to the internal launcher directory
* startup delay is configured with `startupDelaySeconds`
* health check timeout is configured per check with `timeoutSeconds`
* optional health check headers are supported and logged only as masked values

Actual implementation shape:

Example:

```json
{
  "version": 1,
  "environment": "local-example",
  "description": "Example-only config for the future JJ AI Dispatcher Launcher. Do not place secrets here.",
  "startupDelaySeconds": 3,
  "services": [
    {
      "name": "dispatcher-bridge",
      "enabled": false,
      "type": "powershell",
      "workingDirectory": "${dispatcherRoot}",
      "command": "${dispatcherRoot}\\dispatcher\\bridge.ps1",
      "arguments": [],
      "dependsOn": []
    },
    {
      "name": "mcp-http-adapter",
      "enabled": false,
      "type": "node",
      "workingDirectory": "${dispatcherRoot}",
      "command": "node",
      "arguments": [
        ".\\mcp\\server\\http.js"
      ],
      "dependsOn": [
        "dispatcher-bridge"
      ]
    }
  ],
  "healthChecks": [
    {
      "name": "Dispatcher Bridge status",
      "enabled": false,
      "url": "http://127.0.0.1:8787/status",
      "method": "GET",
      "timeoutSeconds": 5
    },
    {
      "name": "MCP HTTP Adapter endpoint",
      "enabled": false,
      "url": "http://127.0.0.1:3000/health",
      "method": "GET",
      "timeoutSeconds": 5,
      "headers": {
        "Authorization": "Bearer PLACEHOLDER_TOKEN_DO_NOT_USE"
      }
    }
  ]
}
```

## 8. Startup Flow

Implemented startup modes:

```text
-PlanOnly
-HealthOnly
Normal Startup
```

### 8.1 Normal Startup

```text
User double-clicks start.bat
↓
start.bat calls launcher.ps1
↓
launcher.ps1 loads launcher.config.local.json
↓
if local config missing, show setup instruction
↓
validate dispatcherRoot
↓
resolve variables like ${dispatcherRoot}
↓
print service startup plan
↓
start enabled services in separate terminal windows
↓
wait briefly for services
↓
run health checks
↓
print PASS / FAIL / SKIP status summary
```

### 8.2 PlanOnly Mode

```text
launcher.ps1 -PlanOnly
```

Behavior:

```text
Load config
Resolve ${dispatcherRoot} and ${launcherRoot}
Print enabled and disabled services
Print configured health checks
Do not start services
Do not call health check endpoints
```

### 8.3 HealthOnly Mode

```text
launcher.ps1 -HealthOnly
```

Behavior:

```text
Load config
Resolve variables
Print service plan
Do not start services
Run configured health checks only
Print PASS / FAIL / SKIP summary
```

### 8.4 Health Check Design

Actual implementation:

```text
startupDelaySeconds controls the wait before post-startup health checks.
timeoutSeconds bounds each health check request.
Health checks may define optional HTTP headers.
Header names are shown, but header values are masked as ***.
Disabled health checks return SKIP.
Missing health check URLs return SKIP.
HTTP 2xx and 3xx responses return PASS.
HTTP errors, timeout errors, and request exceptions return FAIL.
Final summary prints PASS / FAIL / SKIP counts.
```

## 9. Safety Rules

Launcher must follow these rules:

```text
1. Never commit local config
2. Never store tokens in repo
3. Never expose Dispatcher Bridge 8787 externally
4. Tunnel only MCP HTTP Adapter 8790
5. Never run destructive commands
6. Never silently run unknown commands
7. Never auto-push
8. Never directly invoke Codex
9. Never operate as scheduler or autonomous loop
10. All commands must come from config
```

## 10. Repository Structure

Actual MVP structure:

```text
jj-ai-dispatcher/
└─ launcher/
   ├─ README.md
   ├─ .gitignore
   ├─ start.bat
   ├─ launcher.ps1
   ├─ launcher.config.example.json
   └─ docs/
      ├─ launcher-plan.md
      ├─ operator-guide.md
      ├─ migration-guide.md
      └─ JJ AI Dispatcher Launcher — Technical Design & Task Plan.md
```

ADR:

```text
Current JJ Dispatcher MCP implementation only supports repo=self.

Decision:
Launcher was implemented as an internal subproject:

launcher/

Rationale:
This allows JJ Dispatcher MCP to execute and validate launcher work within the existing dispatcher repository while preserving the design boundary that Launcher is an environment startup helper, not Dispatcher core.

Consequence:
The MVP ships under jj-ai-dispatcher/launcher instead of a separate jj-ai-dispatcher-launcher repository.

Future extraction to a standalone repository remains supported.
```

Original target standalone structure remains useful as the extraction model:

```text
jj-ai-dispatcher-launcher/
├─ README.md
├─ .gitignore
├─ start.bat
├─ launcher.ps1
├─ launcher.config.example.json
├─ docs/
│  ├─ launcher-plan.md
│  ├─ operator-guide.md
│  └─ migration-guide.md
└─ scripts/
   └─ health-check.ps1
```

## 10.1 Documentation Deliverables

Delivered:

```text
docs/operator-guide.md
docs/migration-guide.md
```

## 11. Development Phases

### Phase 0 — Planning

Status:

```text
COMPLETE
```

Goal:

```text
Freeze purpose, scope, safety rules, and task list.
```

Deliverable:

```text
Technical design and task plan.
```

### Phase 1 — Project Skeleton

Status:

```text
COMPLETE
Commit: 7ab0b09
```

Goal:

```text
Create initial project files only.
```

No real service startup yet.

### Phase 2 — Config Loader

Status:

```text
COMPLETE
Commit: 5f5f17c
```

Goal:

```text
Read config and print resolved service plan.
```

### Phase 3 — Service Startup

Status:

```text
COMPLETE
Commit: 1357110
```

Goal:

```text
Start configured services in separate terminal windows.
```

### Phase 4 — Health Check

Status:

```text
COMPLETE
Commit: 585fef4
```

Goal:

```text
Check service readiness and print summary.
```

### Phase 5 — Documentation

Status:

```text
COMPLETE
Commit: 1556d0c
```

Goal:

```text
Document local, VM, and cloud usage.
```

### Phase 6 — Standalone Repository Extraction

Status:

```text
FUTURE
```

Goal:

```text
Extract launcher/ into jj-ai-dispatcher-launcher when independent versioning, release governance, or distribution requires it.
```

### Phase 7 — Launcher Dashboard

Status:

```text
FUTURE
```

Goal:

```text
Provide an operator-facing dashboard for service state, health status, and startup visibility.
```

### Phase 8 — Environment Profiles

Status:

```text
FUTURE
```

Goal:

```text
Support named environment profiles for local, VM, and cloud-adjacent runtime configurations.
```

### Phase 9 — Remote VM Launcher

Status:

```text
FUTURE
```

Goal:

```text
Support controlled remote VM startup workflows while preserving explicit operator control and safety boundaries.
```

## 11.1 Actual MVP Commit History

```text
7ab0b09 chore: add launcher project skeleton
5f5f17c feat: add launcher config loader
1357110 feat: start configured launcher services
585fef4 feat: add launcher health checks
1556d0c docs: add launcher operator guides
```

## 11.2 Future Roadmap

```text
Phase 6 — Standalone Repository Extraction
Phase 7 — Launcher Dashboard
Phase 8 — Environment Profiles
Phase 9 — Remote VM Launcher
```

## 12. Development Task List

Historical note:

```text
The original task list targeted D:\dev\projects\jj-ai-dispatcher-launcher as the future standalone repository.
Per the MVP ADR in section 10, actual implementation was completed under jj-ai-dispatcher/launcher because the current JJ Dispatcher MCP implementation only supports repo=self.
The task sequence and safety constraints remain the source planning record.
```

### Task 1 — Add Launcher Project Skeleton

Repo:

```text
D:\dev\projects\jj-ai-dispatcher-launcher
```

Scope:

```text
README.md
.gitignore
start.bat
launcher.ps1
launcher.config.example.json
docs/launcher-plan.md
```

Task:

```text
Create the initial launcher project skeleton.
Document purpose, scope, safety rules, and config-driven design.
Do not implement real service startup yet.
```

Blocked:

```text
No real service startup logic
No auto-push
No destructive commands
No hardcoded user-specific runtime path except example placeholders
No scheduler
No direct Codex invocation
No cloud deployment logic
```

Validation:

```text
Files exist
launcher.config.local.json is ignored
README explains project purpose
docs/launcher-plan.md explains phased plan
working tree clean after Dispatcher commit
```

Commit:

```text
chore: add launcher project skeleton
```

### Task 2 — Add Config Loader

Scope:

```text
launcher.ps1
launcher.config.example.json
README.md
```

Task:

```text
Implement config loading in launcher.ps1.
Read launcher.config.local.json.
If missing, show clear setup instruction.
Support basic variable substitution such as ${dispatcherRoot}.
Print resolved services without starting them yet.
```

Blocked:

```text
No service startup
No destructive commands
No token logging
No hardcoded local path
```

Validation:

```text
Running launcher.ps1 without local config shows clear instruction
Running with local config prints resolved service plan
No service is started yet
working tree clean after Dispatcher commit
```

Commit:

```text
feat: add launcher config loader
```

### Task 3 — Add Service Startup

Scope:

```text
launcher.ps1
README.md
docs/launcher-plan.md
```

Task:

```text
Start enabled services from config in separate terminal windows.
Show service name, working directory, and command before launch.
Start only configured enabled services.
```

Blocked:

```text
No arbitrary command UI
No direct Codex invocation
No delete operation
No auto-push
No hidden background daemon
```

Validation:

```text
Dispatcher Bridge can be started from config
MCP HTTP Adapter can be started from config
ngrok can be started from config
Disabled services are skipped
working tree clean after Dispatcher commit
```

Commit:

```text
feat: start configured launcher services
```

### Task 4 — Add Health Checks

Scope:

```text
launcher.ps1
launcher.config.example.json
README.md
```

Task:

```text
Add health check support for configured URLs.
Print pass/fail summary.
Do not block forever.
```

Blocked:

```text
No infinite wait loop
No external exposure of 8787
No secret logging
```

Validation:

```text
Dispatcher Bridge health check reports pass/fail
MCP Adapter health check reports pass/fail
Timeout is handled gracefully
working tree clean after Dispatcher commit
```

Commit:

```text
feat: add launcher health checks
```

### Task 5 — Add Operator Documentation

Scope:

```text
README.md
docs/operator-guide.md
docs/migration-guide.md
```

Task:

```text
Document local usage, VM/cloud migration model, safety boundaries, startup order, shutdown order, and troubleshooting.
```

Blocked:

```text
No secrets
No real token values
No company-sensitive details
```

Validation:

```text
README has quick start
operator guide has startup and shutdown procedure
migration guide explains config-only migration
working tree clean after Dispatcher commit
```

Commit:

```text
docs: add launcher operator guides
```

## 13. Execution Control

All implementation work must be executed through JJ Dispatcher MCP.

Each task must include:

```text
repo
worker
task
commitMessage
scope
blocked
validation
expectedOutput
```

No task should be dispatched without review.

## 14. First Approved Dispatch Candidate

This is the first task candidate, pending operator approval.

```json
{
  "repo": "D:\\dev\\projects\\jj-ai-dispatcher-launcher",
  "worker": "codex",
  "task": "Create the initial launcher project skeleton. Add README.md, .gitignore, start.bat, launcher.ps1, launcher.config.example.json, and docs/launcher-plan.md. Document that this launcher is a config-driven startup helper for JJ AI Dispatcher services. Do not implement real service startup logic yet. Keep the design portable for local, VM, and cloud migration.",
  "commitMessage": "chore: add launcher project skeleton",
  "scope": [
    "README.md",
    ".gitignore",
    "start.bat",
    "launcher.ps1",
    "launcher.config.example.json",
    "docs/launcher-plan.md"
  ],
  "blocked": [
    "No real service startup logic yet",
    "No auto-push",
    "No destructive commands",
    "No hardcoded user-specific runtime path except example placeholders",
    "No scheduler",
    "No direct Codex invocation",
    "No cloud deployment automation"
  ],
  "validation": [
    "Confirm listed files exist",
    "Confirm launcher.config.local.json is ignored by .gitignore",
    "Confirm README explains purpose and safety boundaries",
    "Confirm docs/launcher-plan.md contains phased plan"
  ],
  "expectedOutput": [
    "Initial launcher skeleton created",
    "Documentation-only foundation committed",
    "Dispatcher result returned with files changed and commit hash",
    "Working tree clean after commit"
  ]
}
```

## Appendix A — Autonomous Sprint Validation

Validation record:

```text
Task 1
Commit e038412

Task 2
Commit 58c3735

Task 3
Commit 0459615
```

Result:

```text
ChatGPT
↓
Dispatcher
↓
Codex
↓
Git
↓
Postback
↓
ChatGPT
```

Three consecutive same-session execution cycles were successfully validated.
