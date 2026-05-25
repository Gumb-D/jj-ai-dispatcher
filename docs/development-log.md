# JJ AI Dispatcher Development Log

## v0.1-local-operator

Date:
2026-05-25

Status:
STABLE + BACKED UP

Local repo:
D:\dev\projects\jj-ai-dispatcher

Remote:
https://github.com/Gumb-D/jj-ai-dispatcher.git

Tag:
v0.1-local-operator

## Purpose

This project reduces manual copy/paste between ChatGPT, Codex, Co-Claw/OpenClaw, and Git by providing a local dispatcher that routes small controlled tasks to local AI workers and utility scripts.

## Completed Scope

- dispatcher core
- task routing
- Git worker tasks
- Codex worker task
- Co-Claw/OpenClaw executable configuration
- shared config loader
- config.local override pattern
- env_check task
- menu.ps1 launcher
- logs ignored
- repo pushed to GitHub
- tag pushed

## Commit History

- b2db657 init: jj-ai-dispatcher framework
- b4a1313 chore: ignore dispatcher runtime logs
- 211bd52 feat: add local config override for dispatcher workers
- fe8acc3 feat: add dispatcher env_check task
- 07effb5 feat: add dispatcher menu launcher

## Key Architecture Decisions

1. Shared config loader is the single source of truth.
2. config.local.json is machine-specific and ignored.
3. Worker paths are configurable.
4. No premature API/UI/agent mesh.
5. Safety-first Git operations.

## Validation

- env_check PASS
- safe_commit PASS
- secure_scan PASS
- repo_cleanup PASS
- git status clean
- main pushed
- v0.1-local-operator tag pushed

## Boundary Rules

Allowed next:
- README
- menu loop improvement
- task descriptions
- config check detail

Blocked unless explicitly requested with MUST:
- API server
- UI app
- scheduler
- agent mesh
- digital twin
- autonomous routing

## Next Milestone

v0.2-worker-usability

Focus:
Small usability improvements only.
