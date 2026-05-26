# Phase 6.7 Operator Pack Index

## Purpose

This is the single entry point for Phase 6 operator materials.

Use this index to find the right Phase 6 document quickly. It consolidates navigation only. It does not create another runbook, expand scope, add automation, or change runtime behavior.

## Recommended Reading Order

1. Phase 6.6 Quickstart
2. Phase 6.0 Runbook Foundation
3. Phase 6.1 Checklist Templates
4. Phase 6.3 Approved Task Patterns
5. Phase 6.2 Troubleshooting Guide
6. Phase 6.5 Client Appendix
7. Phase 6.4 Readiness Review

## Operator Package Map

| Document | Purpose | When to Use |
| --- | --- | --- |
| `docs/phase-6-0-production-operator-runbook-foundation.md` | Defines the production operator workflow, roles, authority, safety boundary, and push policy. | Use when learning or confirming the full daily operating model. |
| `docs/phase-6-1-operator-runbook-checklist-templates.md` | Introduces reusable manual checklists for pre-start, dispatch, review, push, and incident stop. | Use when preparing repeatable operator notes or manual review artifacts. |
| `docs/phase-6-2-production-troubleshooting-guide.md` | Provides safe diagnostics and stop rules for build, MCP, bridge, review, repo, dispatch, push, and boundary issues. | Use when any validation, bridge, repo, or safety problem appears. |
| `docs/phase-6-3-approved-task-patterns-catalog.md` | Catalogs approved task envelopes, conditionally allowed patterns, and blocked prompt shapes. | Use before dispatching work to choose the safest task pattern. |
| `docs/phase-6-4-production-readiness-review.md` | Reviews the Phase 6 package and records readiness for controlled daily use. | Use when confirming readiness posture or preparing Phase 6 closeout. |
| `docs/phase-6-5-client-specific-runbook-appendix.md` | Adapts the approved workflow for MCP client usage without expanding the boundary. | Use when operating through an MCP client. |
| `docs/phase-6-6-production-operator-quickstart.md` | Gives the shortest safe daily workflow reference. | Use first during normal daily operation. |

## Template Map

| Template | Purpose | When to Use |
| --- | --- | --- |
| `docs/templates/pre-start-checklist.md` | Confirms repo, build, MCP smoke, bridge, and security state. | Use before daily operator work or before any dispatch. |
| `docs/templates/dispatch-approval-checklist.md` | Confirms task objective, scope, blocked areas, validation, and dispatch rules. | Use before approving one explicit dispatch. |
| `docs/templates/review-classification-checklist.md` | Guides artifact review and accepted/rejected/needs_followup classification. | Use after a dispatch completes. |
| `docs/templates/push-approval-checklist.md` | Confirms validation, clean repo, reviewed commit, and push approval. | Use before any push. |
| `docs/templates/incident-stop-checklist.md` | Captures immediate stop conditions and safe diagnostics. | Use when a safety, validation, bridge, dispatch, or repo incident appears. |

## Daily Use Shortcut

```text
pre-flight
  |
  v
dispatch approval
  |
  v
one explicit dispatch
  |
  v
review
  |
  v
classification
  |
  v
push approval or stop
```

## Phase 6 Completion Criteria

Phase 6 can close when:

- operator package complete
- validation commands pass
- safety boundary preserved
- repository clean
- operator accepts readiness
- tag candidate created

Recommended tag:

```text
v0.6-phase6-production-operator
```

Do not create the tag yet. Create it only after explicit operator acceptance.

## Phase 7 Recommendation

Recommended next phase:

```text
Phase 7 - Controlled Daily Operation Pilot
```

Goal:

Start using Dispatcher for real daily tasks and collect friction/issues.

## Explicit Non-Goals

Phase 6.7 does not authorize:

- autonomous loop
- remote bridge
- tunnel or public endpoint
- queue or scheduler
- new MCP tools
- arbitrary shell, file, or Git tools
- automatic review
- automatic dispatch
- unattended retries
- weakened security boundary

The operating boundary remains localhost-only, token protected, exactly four approved MCP tools, explicit dispatch only, read-only review helper, review gate preserved, Codex trusted workflow, Cline no auto commit/push, and operator final authority.
