# Phase 5.10A Manual Review Template and Usage

## Purpose

Phase 5.10A standardizes manual review execution after each Dispatcher run. It provides reusable operator-facing templates without changing Dispatcher runtime behavior.

Manual review is the human review gate between a completed run and any later acceptance, rejection, follow-up dispatch, push, rollback, or cleanup decision.

Manual review does not add automation. It does not approve a run by itself. It does not trigger another dispatch.

## Review Usage Flow

Use this flow after every Dispatcher run:

```text
dispatch completes
  |
  v
retrieve result
  |
  v
inspect summary
  |
  v
inspect changed files
  |
  v
inspect validations
  |
  v
classify
  |
  v
accept / reject / needs_followup
  |
  v
optional explicit next dispatch
```

Recommended operator steps:

1. Confirm the bridge is idle.
2. Retrieve the latest result with `.\scripts\bridge-latest.ps1` or the MCP `dispatcher_latest_result` tool.
3. If needed, retrieve the specific run with `dispatcher_get_run` or inspect `dispatcher/runs/<taskId>/result.json`.
4. Read `dispatcher/runs/<taskId>/summary.md`.
5. Review every changed file listed in the result contract.
6. Review validation output and repeat important validation locally when appropriate.
7. Check `git status --short`.
8. Classify the run as `accepted`, `rejected`, or `needs_followup`.
9. Record the decision using the manual checklist.
10. Only after review, decide whether a new explicit dispatch, manual cleanup, push, or no action is appropriate.

## Templates

Manual review templates:

- `docs/templates/manual-run-review-checklist.md`
- `docs/templates/manual-run-review-example.md`
- `docs/templates/run-review-template.json`

The Markdown checklist is intended for operator-facing review notes. The JSON template is a documentation-only structured shape for consistent classification metadata.

## Usage Notes

Manual review is for:

- Confirming the task objective was met.
- Checking that scope and boundaries were respected.
- Reviewing result artifacts and changed files.
- Confirming validations and Git state.
- Recording a clear acceptance decision.
- Preventing accidental autonomous continuation.

Manual review does not:

- Execute code.
- Dispatch follow-up work.
- Push commits.
- Revert commits.
- Approve a run automatically.
- Replace operator judgment.
- Change MCP, bridge, or Dispatcher behavior.

Important rules:

- Manual review is not automatic approval.
- A commit exists does not mean the result is accepted.
- A successful dispatch does not authorize autonomous continuation.
- A follow-up dispatch requires a new explicit instruction.
- Review classification is advisory until the operator accepts it.

## Compact Review Summary Block

Use this block when a short review summary is enough:

```text
Review decision: accepted | rejected | needs_followup
Task ID:
Commit:
Files reviewed:
Validations reviewed:
Risk notes:
Next action:
Reviewer:
Reviewed at:
```

## Relationship to Prior Phases

Phase 5.8 established the review gate and run acceptance policy: every dispatch result must end in `accepted`, `rejected`, or `needs_followup`.

Phase 5.9 established the structured review classification model and machine-readable review object.

Phase 5.10A adds practical manual templates for applying those policies after each Dispatcher run.

## Phase 5.10B Recommendation

Proceed to Phase 5.10B only as a non-executing review helper.

The safest next step is a read-only helper that prints a checklist from the latest run result without changing Dispatcher behavior, starting dispatches, writing acceptance state, pushing commits, or modifying runtime boundaries.
