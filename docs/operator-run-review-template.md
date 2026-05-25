# Operator Run Review Template

## Purpose

This template gives ChatGPT a standard way to review JJ AI Dispatcher run results before deciding the next action. It keeps the loop deliberate: dispatch once, inspect the result, review Git evidence, then decide whether to accept, fix, stop, or roll back.

## When To Use This Template

Use this template after every Dispatcher bridge run that reaches `taskState = "idle"` and produces a result from `GET /runs/latest` or `scripts/bridge-latest.ps1`.

Use it especially when:

- Codex changed files.
- A commit was created.
- The result status is `failed`.
- `workingTreeClean` is `false`.
- `needsReview` is `true`.
- `reviewHints` is not empty.
- The next task depends on the previous run being correct.

## Required Input From Operator

Paste these inputs back to ChatGPT:

- Required: output of `scripts/bridge-latest.ps1`.
- Optional: `dispatcher/runs/<task-id>/summary.md`.
- Optional: `git status --short` from the target repository.

If files changed, include enough Git evidence for review. At minimum, paste `filesChanged`, `commit`, `workingTreeClean`, and any validation output requested in the original task.

## Standard Paste-Back Format

Use this format when returning a run result to ChatGPT:

```text
Operator Run Review Input

1. bridge-latest output
<paste full scripts/bridge-latest.ps1 output here>

2. summary.md, optional
<paste dispatcher/runs/<task-id>/summary.md if useful>

3. git status --short, optional
<paste target repo git status --short if files changed or review is needed>

4. validation evidence, optional
<paste test, parse, lint, git diff --check, or manual validation output>

5. operator notes, optional
<anything unusual observed during dispatch or polling>
```

## Review Checklist

ChatGPT should check:

- `taskId` present.
- `status` is understood as `success` or `failed`.
- `repo` is correct.
- `worker` is correct.
- `filesChanged` matches the requested scope.
- `commit` exists if `filesChanged` is not empty.
- `workingTreeClean` is `true`.
- `pushed` is `false` unless explicitly expected.
- `needsReview` has been checked.
- `reviewHints` has been checked.
- Validation evidence has been checked.

If any item is missing or unclear, ChatGPT should ask the operator for the missing evidence before dispatching another task.

## Decision Rules

### ACCEPT

Use `ACCEPT` when:

- `status = "success"`.
- `repo` and `worker` are correct.
- Changed files match the requested scope.
- A commit exists when files changed.
- `workingTreeClean = true`.
- `pushed = false`, unless push was explicitly expected.
- `needsReview = false`.
- `reviewHints` is empty or non-blocking.
- Validation evidence supports the result.

Next action: continue with the planned workflow or ask the operator to push only if pushing was explicitly requested and safe.

### ACCEPT WITH NOTES

Use `ACCEPT WITH NOTES` when:

- The run is successful and safe to keep.
- There are minor caveats, missing non-critical validation details, or documentation-only follow-up notes.
- No immediate fix is required before the next human decision.

Next action: record the notes and decide whether a later cleanup task is useful.

### REQUEST FIX

Use `REQUEST FIX` when:

- The run completed but the output does not fully match the task.
- Expected files are missing.
- Extra files changed within a recoverable scope.
- Validation failed in a way Codex can fix.
- `needsReview = true` with actionable hints.

Next action: prepare a new, narrow dispatch task that fixes only the identified issue.

### STOP AND INVESTIGATE

Use `STOP AND INVESTIGATE` when:

- `status = "failed"`.
- `repo` is wrong.
- `worker` is wrong.
- The result is missing, malformed, or inconsistent.
- `workingTreeClean = false` and the reason is unknown.
- Validation evidence is missing for a risky change.
- The bridge, helper script, or run artifact behavior looks abnormal.

Next action: do not dispatch another task. Ask the operator for logs, `summary.md`, `git status --short`, and relevant run artifacts.

### MANUAL ROLLBACK REVIEW

Use `MANUAL ROLLBACK REVIEW` when:

- Files changed outside the approved scope.
- A commit exists but should likely not be kept.
- Sensitive files, tokens, local config, bridge exposure, MCP, tunnel, or remote-access behavior changed unexpectedly.
- Git history, branch state, or working tree state needs human inspection.

Next action: do not ask Codex to auto-revert unless the operator explicitly approves a rollback plan. Review Git evidence manually first.

## Example PASS Review

Operator paste-back:

```json
{
  "taskId": "20260526-031500-a1b2c3d4",
  "status": "success",
  "repo": "D:\\dev\\projects\\jj-ai-dispatcher",
  "worker": "codex",
  "filesChanged": [
    "docs/chatgpt-operator-workflow.md"
  ],
  "commit": "5e4120d",
  "commitMessage": "feat: add chatgpt operator workflow helpers",
  "pushed": false,
  "workingTreeClean": true,
  "summary": "Codex worker changes committed by dispatcher.",
  "needsReview": false,
  "reviewHints": []
}
```

ChatGPT review:

```text
Decision: ACCEPT

Reason:
- taskId is present.
- status is success.
- repo and worker are correct.
- filesChanged matches the requested scope.
- commit exists because filesChanged is not empty.
- workingTreeClean is true.
- pushed is false as expected.
- needsReview is false and reviewHints is empty.
- Validation evidence is sufficient for the requested docs/helper update.

Next action:
- No fix required before the next operator decision.
```

## Example FAIL Review

Operator paste-back:

```json
{
  "taskId": "20260526-032100-d4c3b2a1",
  "status": "failed",
  "repo": "D:\\dev\\projects\\jj-ai-dispatcher",
  "worker": "codex",
  "filesChanged": [
    "dispatcher/bridge.ps1",
    "docs/local-bridge-operator-guide.md"
  ],
  "commit": null,
  "commitMessage": "docs: update bridge guide",
  "pushed": false,
  "workingTreeClean": false,
  "summary": "Codex worker failed.",
  "needsReview": true,
  "reviewHints": [
    "Git commit failed."
  ]
}
```

ChatGPT review:

```text
Decision: MANUAL ROLLBACK REVIEW

Reason:
- status is failed.
- dispatcher/bridge.ps1 changed even though bridge logic was out of scope.
- commit is missing.
- workingTreeClean is false.
- needsReview is true and reviewHints reports a Git failure.

Next action:
- Do not dispatch another task yet.
- Operator should inspect git status --short, summary.md, codex logs, and git-diff.patch.
- Decide manually whether to keep any docs change, discard the bridge.ps1 change, or create a narrow approved rollback plan.
```

## Safety Boundaries

- ChatGPT reviews the result before the next dispatch.
- Do not auto-chain tasks yet.
- Do not expose the bridge remotely.
- Do not skip Git review if files changed.
- Do not ignore `needsReview` or `reviewHints`.
- Do not treat a commit as safe until changed files and validation evidence have been checked.
