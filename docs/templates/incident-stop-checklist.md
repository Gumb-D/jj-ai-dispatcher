# Incident Stop Checklist

Use this checklist when a stop condition appears.

## Immediate Stop Conditions

Stop immediately if:

- [ ] Token exposed.
- [ ] Forbidden tool appeared.
- [ ] Unexpected files changed.
- [ ] Bridge externally reachable.
- [ ] Dispatch loop detected.
- [ ] Validation failure unresolved.
- [ ] Repository dirty after supposed completion.
- [ ] MCP tool count changed from the approved four tools.
- [ ] Review helper wrote state or triggered follow-up work.
- [ ] Remote execution, tunnel, public listener, queue, scheduler, or autonomous loop appeared.

## Stop Actions

- [ ] Do not dispatch follow-up work automatically.
- [ ] Do not push.
- [ ] Preserve current state for inspection.
- [ ] Inspect latest result.
- [ ] Inspect changed files.
- [ ] Classify the run manually.
- [ ] Decide next action only after operator review.

## Safe Diagnostic Commands

Use safe read-only and diagnostic commands:

```powershell
git status --short
git log --oneline -10
npm run build
npm run mcp:smoke
npm run review:latest
.\scripts\bridge-status.ps1
.\scripts\bridge-latest.ps1
```

Avoid destructive commands during initial incident review. Do not reset, delete, force-push, rewrite history, or remove run artifacts unless the operator explicitly approves a recovery plan.

## Operator Notes

```text
Incident:
Detected by:
Time:
Latest task ID:
Changed files:
Diagnostics run:
Immediate decision:
Follow-up owner:
```
