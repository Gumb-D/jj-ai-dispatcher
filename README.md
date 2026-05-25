# JJ AI Dispatcher

## Purpose

Local dispatcher for routing small controlled tasks to local AI workers and utility scripts.
It reduces manual copy/paste between ChatGPT, Codex, Co-Claw/OpenClaw, and Git.

## Current Status

v0.1-local-operator:
- stable local operator mode
- backed up to GitHub
- no API server
- no UI app
- no autonomous routing

## Repository

Local:
D:\dev\projects\jj-ai-dispatcher

Remote:
https://github.com/Gumb-D/jj-ai-dispatcher.git

## Quick Start

Run:
```powershell
.\menu.ps1
```

Or directly:
```powershell
.\dispatcher\run.ps1 env_check
.\dispatcher\run.ps1 safe_commit
.\dispatcher\run.ps1 secure_scan
.\dispatcher\run.ps1 repo_cleanup
```

## Configuration

- `dispatcher/config.json` = shared/default config
- `dispatcher/config.local.json` = machine-specific override
- `dispatcher/config.local.json` is ignored by Git
- `dispatcher/config.local.example.json` is the template

Example `config.local.json`:
```json
{
  "defaultRepo": "D:\\path\\to\\target\\repo",
  "codexExe": "C:\\path\\to\\codex.exe",
  "openclawExe": "C:\\Program Files\\Co-Claw\\Co-Claw.exe",
  "safety": {
    "allowAutoPush": false,
    "allowAutoDelete": false,
    "allowSystemSettingModification": false
  }
}
```

## Available Tasks

- env_check
- safe_commit
- secure_scan
- repo_cleanup
- git_status

## Safety Rules

- config.local.json must not be committed
- logs must not be committed
- no auto push unless explicitly enabled
- no auto delete unless explicitly enabled
- no system setting modification unless explicitly enabled

## Development Log

See [docs/development-log.md](docs/development-log.md).

## Next Milestone

v0.2-worker-usability:
- menu loop improvement
- task descriptions
- config check detail
- documentation polish only
