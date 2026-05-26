# Phase 6.6 Production Operator Quickstart

## Purpose

This is the shortest safe workflow reference for daily Dispatcher / MCP / Codex operator use.

Use it when you need to open one file and run safely in about two minutes.

## Quick Pre-Flight

Run:

```powershell
git status --short
npm run build
npm run mcp:smoke
.\scripts\bridge-status.ps1
```

Check:

- [ ] repo clean
- [ ] build pass
- [ ] four approved tools only
- [ ] bridge healthy
- [ ] localhost only

Approved tools:

- `dispatcher_status`
- `dispatcher_dispatch`
- `dispatcher_latest_result`
- `dispatcher_get_run`

## One Explicit Dispatch Workflow

```text
define task
  |
  v
define scope
  |
  v
define blocked areas
  |
  v
define validation
  |
  v
dispatch once only
```

Compact envelope:

```json
{
  "repo": "self",
  "worker": "codex",
  "task": "...",
  "commitMessage": "...",
  "scope": [],
  "blocked": [],
  "validation": []
}
```

Rules:

- one explicit dispatch only
- no chained dispatch
- no automatic follow-up
- no background retry

## Post-Dispatch Review

Run:

```powershell
.\scripts\bridge-latest.ps1
.\scripts\review-latest-run.ps1
npm run review:latest
```

Ask:

- objective satisfied?
- scope respected?
- validations passed?
- unexpected changes?
- safety boundary intact?

Classify:

```text
accepted
rejected
needs_followup
```

## Push Approval

Before push:

- [ ] validations passed
- [ ] repo clean
- [ ] review complete
- [ ] commit reviewed
- [ ] no secret exposure

Codex may push under the approved workflow.

Operator remains final authority.

## Incident Stop Rules

Stop immediately if:

- token exposed
- forbidden tool appeared
- unexpected files changed
- bridge external exposure
- dispatch loop detected
- unresolved validation failure

Do not dispatch again and do not push until the incident is reviewed.

## Never Do This

- autonomous loop
- chained dispatch
- tunnel or public bridge
- remote execution
- arbitrary shell, file, or Git capability
- unattended retries
- "fix everything" prompts

## Safe Daily Command Block

```powershell
git status --short
npm run build
npm run mcp:smoke
.\scripts\bridge-status.ps1
.\scripts\bridge-latest.ps1
npm run review:latest
```

## Relationship to Full Runbook

Use the full Phase 6 package when you need detail:

- Phase 6.0 runbook foundation
- Phase 6.1 checklists
- Phase 6.2 troubleshooting
- Phase 6.3 task patterns
- Phase 6.5 client appendix

## Recommendation for Phase 6.7

Recommended next phase:

```text
Phase 6.7 - Phase 6 Consolidation + Operator Pack Index
```

Goal:

Create a single navigation/index document for the entire Phase 6 operator package.
