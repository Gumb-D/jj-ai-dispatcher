# Phase 5.8 Review Gate and Run Acceptance Policy

## Purpose

Phase 5.7B proved that the controlled path works:

```text
ChatGPT Brain
  |
  v
Dispatcher
  |
  v
Codex Worker
  |
  v
Git
  |
  v
Result
  |
  v
Review Decision
```

Successful dispatch validation does not authorize autonomous execution. The Dispatcher is a controlled execution layer, not a self-running coding loop. ChatGPT remains the planning and review brain, Codex remains the local coding worker, and every Dispatcher result must be reviewed before the next action.

This policy formalizes the review gate, acceptance decision, and post-dispatch behavior for all future Dispatcher and MCP-driven runs.

## Review Gate Policy

Every dispatch result must end in exactly one explicit review state:

- `accepted`
- `rejected`
- `needs_followup`

Definitions:

- `accepted`: The run satisfied the requested task, stayed within scope, passed required validation, preserved safety boundaries, and produced an acceptable result.
- `rejected`: The run result is not acceptable and should not be treated as completed work. Rejection may require manual cleanup, rollback review, or a corrected follow-up task.
- `needs_followup`: The run made partial or useful progress, but more work or clarification is required before the outcome can be accepted.

No dispatch result may be silently treated as accepted just because it completed, produced a commit, or returned `status: success`.

## Acceptance Criteria

Minimum acceptance checklist:

- Task objective is satisfied.
- Approved scope is respected.
- Forbidden files, folders, tools, and behaviors are untouched.
- Required validations passed.
- `git status --short` is clean after the run, unless the task explicitly required uncommitted artifacts.
- No secrets, bridge tokens, credentials, or local private config were exposed.
- Commit message is accurate and acceptable.
- Result contract is present and understandable.
- Logs and summary do not indicate hidden failures or unexpected behavior.
- No MCP or bridge safety boundary was weakened.

If any item is uncertain, the result should be marked `needs_followup` or `rejected`, not `accepted`.

## Rejection Criteria

Reject a dispatcher run if any of these occur:

- Unexpected file changes.
- Failed or skipped required validation without an acceptable explanation.
- Boundary violation.
- Secret, token, credential, or private config exposure.
- Architectural drift beyond the approved task.
- Forbidden MCP tool exposure.
- New tunnel, remote bridge, public listener, scheduler, queue, or auto-chain behavior.
- Arbitrary shell, arbitrary file read/write, direct Git tool, or editor control added to MCP.
- Commit message is misleading or unrelated.
- Result contract is missing, malformed, or inconsistent with observed repository state.

Rejected runs should be documented before cleanup or corrective work begins.

## Post-Dispatch Decision Model

Required decision flow:

```text
dispatch completes
  |
  v
review result contract, changed files, logs, summary, validations, and git state
  |
  v
choose exactly one: accepted / rejected / needs_followup
  |
  v
only after that decision, decide whether another explicit dispatch is appropriate
```

There is no automatic recursive dispatch.

There is no automatic next task.

There is no unattended coding cycle.

Any follow-up dispatch must be a new explicit request with its own scope, blocked areas, validation requirements, expected output, and review after completion.

## Dispatcher Commit Handling

The Dispatcher may create a Git commit as part of a successful run. That commit is evidence of worker output, not proof of acceptance.

Policy:

- A dispatcher-created commit exists does not mean the outcome is automatically accepted.
- The operator must review the result before treating the commit as accepted work.
- If a committed run is rejected, the operator must decide whether to revert, amend, supersede, or manually repair it.
- Future push policy must remain separate from commit creation.
- A commit must not be pushed merely because the Dispatcher created it.

For Phase 5, pushing remains an explicit operator decision after review.

## MCP Boundary Preservation

Approved MCP tools:

- `dispatcher_status`
- `dispatcher_dispatch`
- `dispatcher_latest_result`
- `dispatcher_get_run`

Forbidden MCP tools and capabilities:

- `arbitrary_shell`
- `arbitrary_file_read`
- `arbitrary_file_write`
- `delete`
- `push`
- `tunnel_enable`
- `remote_exec`
- `vscode_ui_control`
- `credential_read`
- `config_write`

The MCP server remains:

- stdio-only
- local bridge only
- localhost-only
- token protected
- explicit dispatch only
- limited to the four approved tools

## Future Phase Boundary

Phase 5.8 does not authorize:

- autonomous agent loops
- self-triggered dispatch
- background scheduling
- unattended coding cycles
- queueing
- remote worker expansion
- public bridges
- tunnels or reverse proxies
- arbitrary shell tools
- arbitrary file read/write tools
- direct Git MCP tools
- automatic push behavior
- removal of human review

Future phases must preserve the review gate unless a separate, explicit design and approval changes the project boundary.

## Acceptance Metadata Example

A lightweight review artifact may record the review decision without changing Dispatcher runtime behavior:

```json
{
  "taskId": "20260526-205850-fe7136fb",
  "decision": "accepted",
  "reviewedBy": "operator",
  "reviewedAt": "2026-05-26T21:15:00+08:00",
  "notes": "Docs-only smoke artifact reviewed. Scope respected. Validations passed.",
  "followupRequired": false
}
```

Allowed `decision` values:

- `accepted`
- `rejected`
- `needs_followup`

This example is documentation only. It does not add runtime behavior, persistence, queueing, or automation.

## Recommendation for Phase 5.9

Phase 5.9 should focus on structured review artifact consumption and result classification.

Recommended direction:

- Define a machine-readable review metadata shape.
- Decide where reviewed run decisions should live.
- Keep acceptance metadata separate from Dispatcher execution.
- Preserve explicit operator review before any push or follow-up dispatch.
- Do not introduce autonomous dispatch, background scheduling, or remote execution.
