# Review Classification Checklist

Use this checklist after a dispatch completes and before any next decision.

## Artifact Review

- [ ] Latest result reviewed.
- [ ] Summary reviewed.
- [ ] Changed files reviewed.
- [ ] Validations reviewed.
- [ ] Commit metadata reviewed.
- [ ] Working tree state reviewed.
- [ ] Pushed state reviewed.

Suggested review commands:

```powershell
.\scripts\bridge-latest.ps1
.\scripts\review-latest-run.ps1
npm run review:latest
git status --short
```

## Sub-Checks

- [ ] Objective satisfied.
- [ ] Scope respected.
- [ ] Safety preserved.
- [ ] Unexpected changes absent.
- [ ] No token, secret, credential, or private config exposure.
- [ ] No forbidden tool or behavior added.
- [ ] Review helper remained read-only.

## Decision

Choose one:

- [ ] `accepted`
- [ ] `rejected`
- [ ] `needs_followup`

Decision guidance:

- `accepted`: objective satisfied, validations passed, scope respected, safety preserved
- `rejected`: result should not be used without correction or rollback planning
- `needs_followup`: result is useful but requires a new explicit task

A needs_followup decision does not authorize automatic dispatch.

## Operator Notes

```text
Task ID:
Commit:
Changed files:
Validation result:
Classification:
Reason:
Follow-up needed:
```
