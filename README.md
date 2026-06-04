# JJ AI Dispatcher

## Purpose

Local dispatcher for routing small controlled tasks to local AI workers and utility scripts.
It reduces manual copy/paste between ChatGPT, Codex, Co-Claw/OpenClaw, and Git.

## Current Status

v0.1-local-operator:
- stable local operator mode
- backed up to GitHub
- ChatGPT MCP feasibility path validated for controlled operator testing
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
.\dispatcher\run.ps1 codex_task
```

## Dispatcher CLI Usage

Run a Codex task against the configured default repo:
```powershell
.\dispatcher\ask "update README"
```

Run a Codex task against this dispatcher repo:
```powershell
.\dispatcher\ask self "update README"
```

Run a Codex task against another repo:
```powershell
.\dispatcher\ask D:\dev\projects\other-repo "update README"
```

Run a Codex task with a custom commit message:
```powershell
.\dispatcher\ask self "update README" -m "docs: update README"
```

`ask.ps1` is a small CLI wrapper around the existing inbox workflow:
- task prompt is written to `dispatcher/inbox/codex-task.txt`
- optional repo target is written to `dispatcher/inbox/codex-task.repo.txt`
- optional commit message is written to `dispatcher/inbox/codex-task.commit.txt`
- `dispatcher/run.ps1 codex_task` runs Codex, owns the git commit, and handles optional auto-push

Current role split:
- Dispatcher owns orchestration and git operations
- Codex owns file edits

## Dispatcher Operator Workflow

Current Phase 4 role model:

- ChatGPT = Brain
- Dispatcher = Execution Controller
- Codex = Coding Worker
- Git = Control Point

Current safe local workflow:

```powershell
.\dispatcher\bridge.ps1
.\scripts\bridge-status.ps1
.\scripts\bridge-dispatch.ps1 -Repo self -Worker codex -Task "describe task" -CommitMessage "docs: describe change"
.\scripts\bridge-wait-latest.ps1
.\scripts\bridge-latest.ps1
```

Operator sequence:

- Start the local bridge with `.\dispatcher\bridge.ps1`.
- Check status with `.\scripts\bridge-status.ps1`.
- Dispatch with `.\scripts\bridge-dispatch.ps1`.
- Wait for and read the latest result with `.\scripts\bridge-wait-latest.ps1`.
- Review latest result again if needed with `.\scripts\bridge-latest.ps1`.
- Paste the result back to ChatGPT for review before issuing another task.

Operator documentation index:

- [docs/local-bridge-operator-guide.md](docs/local-bridge-operator-guide.md)
- [docs/chatgpt-operator-workflow.md](docs/chatgpt-operator-workflow.md)
- [docs/operator-run-review-template.md](docs/operator-run-review-template.md)
- [docs/session-handover-phase-4.md](docs/session-handover-phase-4.md)
- [docs/phase-7-5-chatgpt-mcp-operations-checklist.md](docs/phase-7-5-chatgpt-mcp-operations-checklist.md)

Safety reminder:

- Localhost only.
- Token required.
- Token only in `dispatcher/config.local.json`.
- MCP remains limited to the approved Dispatcher tool surface.
- Do not expose the raw Dispatcher bridge on `127.0.0.1:8787`.
- Only the MCP HTTP adapter on `127.0.0.1:8790` may be tunneled for controlled ChatGPT feasibility testing.
- Stop ngrok when not actively testing.

Current baseline:

- Phase 4.4 completed.
- Current remote baseline: `main @ 9446e49`.
- Stable tag: `v0.3-phase3-bridge`.

## Custom Codex Task

Use codex-task.repo.txt when the target repo is not config.defaultRepo.
Dispatcher can optionally own git commit for codex_task.

- `dispatcher/inbox/codex-task.txt` = prompt sent to Codex
- `dispatcher/inbox/codex-task.repo.txt` = optional target repo override
- `dispatcher/inbox/codex-task.commit.txt` = optional commit message
- `dispatcher/inbox/codex-task.push.txt` = optional auto-push control; accepts `true`, `yes`, or `1`
- If no repo override is provided, `codex_task` uses `defaultRepo` from config
- If Codex exits successfully and changes are detected, the dispatcher stages and commits them
- If no commit message file is provided, the dispatcher uses `chore: codex task update`
- Auto push is off by default and also requires `safety.allowAutoPush` in config

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

Test note: README append check.

Phase 2A.1 validation note: dispatcher README append path verified.

UX validation note: README append flow stays visible and low-friction.

Repo alias validation note: dispatcher alias resolution path verified.

Compatibility validation note: dispatcher README append path remains compatible.

Commit message validation note: dispatcher commit message checks remain visible.

ZTE laptop setup test note: Dispatcher setup confirmed.
