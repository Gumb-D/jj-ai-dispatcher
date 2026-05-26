# Dispatch Approval Checklist

Use this checklist before approving one explicit dispatch.

## Task Quality

- [ ] Objective is clear.
- [ ] Scope is defined.
- [ ] Blocked areas are defined.
- [ ] Validation is defined.
- [ ] Expected output is defined.
- [ ] Commit message is acceptable if the run succeeds.

## Risk Review

- [ ] No architecture drift.
- [ ] No security boundary change.
- [ ] No remote or public behavior.
- [ ] No autonomous behavior.
- [ ] No scheduler or queue.
- [ ] No arbitrary shell exposure.
- [ ] No arbitrary file read/write exposure.
- [ ] No direct Git MCP tool exposure.
- [ ] Cline is not being authorized to auto commit or auto push.

## Dispatch Rules

- [ ] One dispatch only.
- [ ] No chaining.
- [ ] No background follow-up.
- [ ] Explicit operator intent confirmed.
- [ ] Follow-up work requires a separate review and a new explicit instruction.

## Suggested Dispatch Envelope

```json
{
  "repo": "self",
  "worker": "codex",
  "task": "",
  "commitMessage": "",
  "scope": [],
  "blocked": [],
  "validation": [],
  "expectedOutput": []
}
```

## Operator Notes

```text
Task:
Scope:
Blocked:
Validation:
Expected output:
Commit message:
Approval:
```
