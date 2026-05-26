# Push Approval Checklist

Use this checklist before pushing a completed run.

## Before Push

- [ ] Validations passed.
- [ ] Repository is clean after commit.
- [ ] Review completed.
- [ ] Commit reviewed.
- [ ] Commit message is acceptable.
- [ ] No secret exposure.
- [ ] No token exposure.
- [ ] No private config exposure.
- [ ] Scope is satisfied.
- [ ] Safety boundary is preserved.
- [ ] Operator agrees push is allowed.

Suggested commands:

```powershell
git status --short
git log --oneline -10
npm run build
npm run mcp:smoke
npm run review:latest
```

## Push Policy

Codex may push under the approved Dispatcher workflow when:

- validations pass
- repository is clean after commit
- scope is satisfied
- review gate is preserved
- operator authorization exists

The operator may still override push behavior by explicit instruction.

## Operator Notes

```text
Commit:
Commit message:
Validation:
Review classification:
Push approved:
Pushed by:
Remote:
```
