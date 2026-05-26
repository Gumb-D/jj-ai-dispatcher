# Phase 6.1 Operator Runbook Checklist Templates

## Purpose

Phase 6.1 creates a reusable checklist pack for daily operator use of the current Dispatcher / MCP / Codex workflow.

This phase is documentation and template only. It does not add runtime logic, MCP tools, bridge behavior, Dispatcher behavior, automation, queues, schedulers, autonomous loops, remote execution, or public endpoints.

## Relationship to Phase 6.0

Phase 6.0 established the production operator runbook foundation after Phase 5 validation and tagging.

Phase 6.1 turns that foundation into practical, repeatable checklists an operator can use before dispatch, during review, before push, and when stopping for an incident.

The Phase 6.0 production boundary remains unchanged:

- localhost only
- token protected bridge
- MCP stdio only
- exactly four approved tools
- explicit dispatch only
- review helper read-only
- review gate preserved
- Codex trusted under the approved workflow
- Cline no auto commit or auto push

## Template Pack

Checklist templates:

- [Pre-start Checklist](templates/pre-start-checklist.md)
- [Dispatch Approval Checklist](templates/dispatch-approval-checklist.md)
- [Review Classification Checklist](templates/review-classification-checklist.md)
- [Push Approval Checklist](templates/push-approval-checklist.md)
- [Incident Stop Checklist](templates/incident-stop-checklist.md)

## Intended Use

Use these templates as manual operator aids.

Recommended usage:

- copy or reference a checklist before each relevant step
- check items manually
- record notes in the run review artifact or operator notes
- classify review outcomes explicitly
- dispatch follow-up work only after a separate explicit decision

The templates are not machine enforcement. They do not write state, block commands, trigger dispatch, approve runs, reject runs, push commits, or modify repository files.

## Manual Workflow Position

The checklist pack fits into the approved manual flow:

```text
pre-start checklist
  |
  v
dispatch approval checklist
  |
  v
explicit dispatch
  |
  v
review classification checklist
  |
  v
push approval checklist
  |
  v
operator final decision
```

If an incident condition appears, stop normal flow and use the incident stop checklist.

## No Runtime Integration

Phase 6.1 does not integrate these templates into Dispatcher, MCP, the bridge, Codex, Cline, Git hooks, CI, or any background process.

No automatic enforcement is added.

The operator remains responsible for:

- deciding whether a task is safe to dispatch
- confirming scope and blocked areas
- reviewing artifacts and changed files
- classifying results
- authorizing push behavior
- stopping the workflow when needed

## Usage Example

Example daily sequence:

```text
pre-start
  |
  v
dispatch approval
  |
  v
dispatch
  |
  v
review
  |
  +--> push approval
  |
  +--> incident stop
```

Concrete example:

1. Operator runs the pre-start checklist and confirms build, smoke, bridge health, and approved tool surface.
2. Operator fills the dispatch approval checklist for one documentation task with narrow scope and blocked areas.
3. Operator performs one explicit dispatch.
4. Operator reviews latest result and changed files using the review classification checklist.
5. If accepted and push is allowed, operator completes the push approval checklist.
6. If a stop condition appears at any point, operator switches to the incident stop checklist and does not dispatch follow-up work automatically.

## Recommendation for Phase 6.2

Recommended next phase:

```text
Phase 6.2 - Troubleshooting Guide
```

Phase 6.2 should document common failure modes and safe diagnostic paths for build failures, MCP smoke failures, bridge health failures, latest-result review issues, dirty repository state, and safety-boundary concerns.
