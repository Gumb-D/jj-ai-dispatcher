# JJ AI Dispatcher

## Vision

JJ AI Dispatcher is a local orchestration framework where ChatGPT acts as the brain, while local execution tools act as workers.

The goal is to reduce repetitive copy-paste between ChatGPT, Codex, OpenClaw, PowerShell, and Git.

This project is designed for a Windows-first private development environment.

## Target Environment

- Windows 11
- PowerShell 7
- VSCode
- OpenClaw 2026.3.13
- Codex CLI
- Private repo only

## Architecture

```text
JJ
↓
ChatGPT
Brain / planner / reviewer
↓
Local Dispatcher
Task router
↓
Codex / OpenClaw / PowerShell / Git
Workers
↓
Execution output
↓
ChatGPT reviews and decides next action
```

## Brain vs Worker Model

### ChatGPT

ChatGPT is the brain.

Responsibilities:

- Planning
- Reasoning
- Review
- Task generation
- Safety checking
- Deciding the next action

ChatGPT should not blindly execute destructive actions. It should create clear tasks, review outputs, and decide whether another worker action is needed.

### Codex

Codex is the coding worker.

Responsibilities:

- Code changes
- Repo inspection
- Git operations
- Safe refactoring
- Test execution
- Preparing commits when explicitly requested

Codex should not auto-push unless explicitly instructed.

### OpenClaw

OpenClaw is the agent/runtime worker.

Responsibilities:

- Agent tasks
- Automation
- WhatsApp-related runtime work
- Runtime validation
- Gateway health checks
- OpenClaw service logs

### PowerShell

PowerShell is the system execution worker.

Responsibilities:

- Local command execution
- File inspection
- Process inspection
- Script execution
- Windows-first automation

### Git

Git is the version-control worker.

Responsibilities:

- Status checks
- Diff checks
- Branch checks
- Commit preparation

Git tasks must not push or delete branches unless explicitly requested.

### Dispatcher

The dispatcher is the orchestration layer.

Responsibilities:

- Load task definitions
- Route tasks to the correct worker
- Execute commands
- Capture stdout and stderr
- Save logs
- Print clean summaries

## Project Structure

```text
jj-ai-dispatcher/
│
├─ README.md
│
├─ dispatcher/
│  ├─ run.ps1
│  ├─ tasks.json
│  ├─ config.json
│  └─ logs/
│
├─ prompts/
│  ├─ codex-safe-commit.md
│  ├─ codex-secure-scan.md
│  ├─ openclaw-health-check.md
│  ├─ openclaw-restart.md
│  ├─ repo-cleanup.md
│  └─ deployment-check.md
│
├─ scripts/
│  ├─ run-codex-task.ps1
│  ├─ run-openclaw-task.ps1
│  ├─ git-status.ps1
│  └─ openclaw-logs.ps1
│
└─ examples/
   ├─ example-codex-output.md
   └─ example-openclaw-output.md
```

## Setup

Open PowerShell 7 in the project root.

```powershell
pwsh
```

Optional: allow local script execution for the current process only.

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
```

Check required tools:

```powershell
pwsh --version
git --version
codex --version
openclaw --version
```

Update `dispatcher/config.json` before use.

Important fields:

```json
{
  "defaultRepo": "D:\\dev\\projects\\your-private-repo",
  "codexExe": "codex",
  "openclawExe": "openclaw",
  "gitExe": "git",
  "logRetentionDays": 30
}
```

## Usage Examples

Run a safe commit review using Codex:

```powershell
.\dispatcher\run.ps1 safe_commit
```

Run a security scan using Codex:

```powershell
.\dispatcher\run.ps1 secure_scan
```

Check Git status:

```powershell
.\dispatcher\run.ps1 git_status
```

Restart OpenClaw gateway:

```powershell
.\dispatcher\run.ps1 openclaw_restart
```

Read OpenClaw logs:

```powershell
.\dispatcher\run.ps1 openclaw_logs
```

Run OpenClaw health check:

```powershell
.\dispatcher\run.ps1 health_check
```

Run repo cleanup review:

```powershell
.\dispatcher\run.ps1 repo_cleanup
```

## Workflow

Recommended operating loop:

```text
1. JJ asks ChatGPT for a task.
2. ChatGPT generates or selects a dispatcher task.
3. JJ runs dispatcher locally.
4. Dispatcher routes execution to Codex, OpenClaw, PowerShell, or Git.
5. Dispatcher saves logs.
6. JJ sends output back to ChatGPT.
7. ChatGPT reviews and decides the next action.
```

## Safety Rules

The dispatcher must not perform these actions unless explicitly requested:

- Auto push
- Auto delete files
- Auto modify system settings
- Auto kill unknown processes
- Auto overwrite repo configuration
- Auto expose secrets
- Auto commit runtime credentials

## Recommended Expansion Path

### Phase 1: Local command router

Current version.

- Manual task trigger
- Local logs
- Codex/OpenClaw/Git/PowerShell routing

### Phase 2: ChatGPT task package format

Standardize task handoff format:

```json
{
  "task": "safe_commit",
  "repo": "D:\\dev\\projects\\repo",
  "instruction": "Review changes and prepare a safe commit only."
}
```

### Phase 3: Local inbox

Create:

```text
dispatcher/inbox/
dispatcher/outbox/
```

ChatGPT writes a task file. Dispatcher consumes it.

### Phase 4: Worker result summarizer

Add automatic summary extraction from logs.

### Phase 5: Local UI

Build a small web UI:

- Task selection
- Repo selector
- Run button
- Logs viewer
- Copy summary to ChatGPT

### Phase 6: Controlled automation

Add guarded actions:

- Confirm before commit
- Confirm before OpenClaw restart
- Confirm before repo cleanup
- Confirm before Git push
