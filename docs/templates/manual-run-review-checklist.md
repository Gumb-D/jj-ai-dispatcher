# Manual Dispatcher Run Review Checklist

## Identity

- Task ID:
- Commit:
- Commit message:
- Reviewer:
- Review timestamp:
- Review source:

## Artifact Review

- [ ] Latest result checked.
- [ ] `result.json` reviewed.
- [ ] `summary.md` reviewed.
- [ ] Changed files list reviewed.
- [ ] Run logs reviewed if needed.
- [ ] Commit metadata reviewed.

## Changed Files

List reviewed files:

- 

## Validation Review

- [ ] Build validation reviewed.
- [ ] MCP smoke validation reviewed.
- [ ] `git status --short` reviewed.
- [ ] Additional validation reviewed if applicable.

Validation notes:

- 

## Boundary Review

- [ ] Approved scope respected.
- [ ] Forbidden areas untouched.
- [ ] No forbidden tool exposure.
- [ ] No security issue.
- [ ] No secret, token, credential, or private config exposure.
- [ ] No unexpected architecture drift.
- [ ] No auto-chain, scheduler, queue, tunnel, remote bridge, or public listener introduced.

Boundary notes:

- 

## Decision

Choose one:

- [ ] `accepted`
- [ ] `rejected`
- [ ] `needs_followup`

Sub-status:

- 

Decision rationale:

- 

## Next Action

Choose one:

- [ ] `none`
- [ ] `manual_review`
- [ ] `manual_cleanup`
- [ ] `request_followup`
- [ ] `rerun_validation`
- [ ] `prepare_push`

Next action notes:

- 

## Review Summary

```text
Review decision:
Task ID:
Commit:
Files reviewed:
Validations reviewed:
Risk notes:
Next action:
Reviewer:
Reviewed at:
```
