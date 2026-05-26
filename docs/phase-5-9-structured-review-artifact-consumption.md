# Phase 5.9 Structured Review Artifact Consumption

## Purpose

Phase 5.9 standardizes how ChatGPT and the operator consume a completed Dispatcher run and classify the outcome.

This phase does not automate follow-up dispatch. It does not change Dispatcher execution behavior. It defines a review model so each completed run can be evaluated consistently before any acceptance, rejection, follow-up request, or push decision.

The review classification is advisory unless the operator accepts it.

## Review Input Sources

Use the current Dispatcher and Git artifacts as review inputs:

- Dispatcher latest result from `dispatcher_latest_result` or `.\scripts\bridge-latest.ps1`
- Dispatcher specific run result from `dispatcher_get_run` or `dispatcher/runs/<taskId>/result.json`
- `dispatcher/runs/<taskId>/summary.md`
- `dispatcher/runs/<taskId>/git-diff.patch`, when present
- Changed files listed in the result contract
- `git status --short`
- Git diff or commit diff for reviewed changes
- Validation output captured in run logs or repeated locally
- Commit metadata, including commit hash, commit message, author, and pushed state
- Worker logs, including stdout and stderr, when needed to clarify behavior

The reviewer should prefer the structured result contract first, then inspect summary, changed files, validation evidence, and Git state.

## Review Classification States

Every completed run must be classified into exactly one top-level state:

- `accepted`
- `rejected`
- `needs_followup`

Optional sub-status examples:

Accepted:

- `accepted_clean`
- `accepted_with_notes`

Rejected:

- `rejected_scope_violation`
- `rejected_validation_failed`
- `rejected_security_boundary`
- `rejected_unexpected_changes`

Needs follow-up:

- `needs_clarification`
- `needs_validation`
- `needs_patch`
- `needs_manual_check`

Sub-status values are descriptive review metadata. They do not trigger Dispatcher behavior.

## Minimum Review Object

A review decision should be representable as a machine-readable object:

```json
{
  "taskId": "20260526-205850-fe7136fb",
  "classification": "accepted",
  "subStatus": "accepted_clean",
  "reviewedAt": "2026-05-26T21:20:00+08:00",
  "reviewedBy": "chatgpt/operator",
  "acceptedCommit": "85d5b39",
  "filesReviewed": [
    "docs/dispatch-tool-smoke.tmp.md"
  ],
  "validationSummary": [
    "npm run build passed",
    "npm run mcp:smoke passed",
    "git status --short clean"
  ],
  "riskNotes": [],
  "nextAction": "none"
}
```

Required fields:

- `taskId`
- `classification`
- `subStatus`
- `reviewedAt`
- `reviewedBy`
- `acceptedCommit`
- `filesReviewed`
- `validationSummary`
- `riskNotes`
- `nextAction`

Allowed `classification` values:

- `accepted`
- `rejected`
- `needs_followup`

Suggested `nextAction` values:

- `none`
- `manual_review`
- `manual_cleanup`
- `request_followup`
- `rerun_validation`
- `prepare_push`

`nextAction` is advisory. It must not automatically trigger `dispatcher_dispatch`.

## Review Decision Rules

Classify as `accepted` only if:

- The task objective was satisfied.
- Approved scope was respected.
- Required validations passed or any missing validation is explicitly justified.
- No forbidden areas were touched.
- No security boundary issue occurred.
- Git state is understood.
- The commit was reviewed.
- Result contract, summary, and changed files agree.
- No secret, token, credential, or private config exposure occurred.

Classify as `rejected` if:

- A boundary violation occurred.
- Unexpected file changes occurred.
- Required validation failed without an acceptable reason.
- Output is suspicious or inconsistent.
- A secret, token, credential, or private config was exposed.
- Architecture drift occurred.
- Forbidden MCP, bridge, remote, tunnel, shell, file, Git, or editor-control capability was introduced.
- The commit is misleading, unsafe, or unrelated to the requested task.

Classify as `needs_followup` if:

- The result is mostly valid but incomplete.
- Additional validation is required.
- A small patch is required.
- A human check is required.
- The result is useful but should not yet be accepted.
- The reviewer cannot confidently choose `accepted` or `rejected`.

When uncertain, prefer `needs_followup`.

## ChatGPT Consumption Flow

Expected review flow:

```text
get latest run
  |
  v
read result contract
  |
  v
inspect summary
  |
  v
check changed files and commit metadata
  |
  v
review validation output and git state
  |
  v
classify accepted / rejected / needs_followup
  |
  v
recommend next action
```

ChatGPT may recommend a classification, but that classification is advisory unless the operator accepts it.

The operator remains responsible for accepting, rejecting, requesting follow-up, pushing, reverting, or manually repairing a run result.

## No Auto-Dispatch Rule

A classification result must not automatically trigger `dispatcher_dispatch`.

No review object, sub-status, risk note, or next action may start another Dispatcher run by itself.

Any next dispatch requires a new explicit operator instruction with its own:

- task
- scope
- blocked areas
- validation requirements
- expected output
- review after completion

This preserves the Phase 5 review gate and prevents autonomous loops.

## Safety Boundary

This review model does not authorize:

- new MCP tools
- auto-chain behavior
- scheduler behavior
- queueing
- autonomous loops
- unattended follow-up dispatch
- remote bridge
- tunnel
- public listener
- arbitrary shell
- arbitrary file read/write
- direct Git tools
- weaker token or localhost boundaries

The approved MCP tool surface remains:

- `dispatcher_status`
- `dispatcher_dispatch`
- `dispatcher_latest_result`
- `dispatcher_get_run`

## Documentation-Only Template

A static example template is available at:

```text
docs/templates/run-review-template.json
```

This template is not wired into Dispatcher runtime execution. It is a documentation aid for consistent manual or ChatGPT-assisted review.

## Recommendation for Phase 5.10

The safest next step is Phase 5.10A: add a manual/operator review template file and usage notes.

Reasoning:

- It improves consistency without changing runtime behavior.
- It preserves explicit human review.
- It avoids scheduler, queue, auto-chain, and unattended dispatch risks.
- It creates a stable bridge between free-form review and future structured metadata.

Phase 5.10B, a non-executing review helper script that reads the latest result and prints a checklist, can be considered after the manual template is stable.
