# Phase 6.3 Approved Task Patterns Catalog

## Purpose

Phase 6.3 defines approved reusable task patterns for safe Dispatcher / Codex operator usage.

Operators should use bounded task envelopes because they:

- improve consistency across dispatches
- reduce unsafe prompts
- preserve scope discipline
- support reviewability
- make validation expectations explicit
- keep the production boundary visible before work starts

This phase is documentation-only. It does not add runtime logic, MCP tools, bridge behavior, Dispatcher behavior, auto-dispatch, auto-review, queueing, schedulers, autonomous loops, remote bridges, tunnels, public listeners, arbitrary shell access, arbitrary file access, direct Git tools, or any weakened security boundary.

The approved boundary remains:

- localhost only
- token protected bridge
- MCP stdio only
- exactly four approved tools
- explicit dispatch only
- review helper read-only
- review gate preserved
- Codex trusted under the approved workflow
- Cline no auto commit or auto push

## Task Envelope Standard

Use this standard structure for approved task dispatches:

```json
{
  "repo": "self",
  "worker": "codex",
  "task": "...",
  "commitMessage": "...",
  "scope": [],
  "blocked": [],
  "validation": [],
  "expectedOutput": []
}
```

Field meaning:

- `repo`: target repository. Use `self` for this repository.
- `worker`: approved worker. Use `codex` for trusted scoped implementation work.
- `task`: one bounded objective written in reviewable language.
- `commitMessage`: commit message to use only if validations pass and commit is authorized.
- `scope`: explicit files, directories, or behavior areas allowed to change.
- `blocked`: files, directories, capabilities, or safety boundaries that must not change.
- `validation`: commands or manual checks expected before completion.
- `expectedOutput`: final artifact, summary, result contract, or review evidence expected from the run.

Every approved task should be understandable before dispatch and reviewable after completion.

## Approved Task Pattern Categories

### A. Docs-Only Change Pattern

Use this pattern for documentation updates that do not change runtime behavior.

Safe examples:

- README update
- design note update
- operator guide update
- checklist/template update

Required structure:

- narrow scope
- no runtime behavior change
- explicit files
- validation commands listed
- expected documentation output named

Example task envelope:

```json
{
  "repo": "self",
  "worker": "codex",
  "task": "Update the operator guide with a short section describing the manual review states. Keep the change documentation-only.",
  "commitMessage": "docs: clarify operator review states",
  "scope": [
    "docs/local-bridge-operator-guide.md"
  ],
  "blocked": [
    "mcp/",
    "scripts/",
    "dispatcher runtime",
    "bridge behavior",
    "MCP tools",
    "Git automation"
  ],
  "validation": [
    "npm run build",
    "npm run mcp:smoke",
    "git diff --check",
    "git status --short"
  ],
  "expectedOutput": [
    "documentation update committed after validations pass",
    "summary of changed file",
    "final git status"
  ]
}
```

### B. Validation-Only Pattern

Use this pattern when the operator only needs validation evidence.

Safe examples:

- run build
- run MCP smoke
- run review helper
- inspect bridge status

Requirements:

- no file changes unless documenting results
- no dispatch chaining
- no automatic follow-up
- no push unless a separate documentation result is committed and approved

Example task envelope:

```json
{
  "repo": "self",
  "worker": "codex",
  "task": "Run the standard validation commands and report the results without changing files.",
  "commitMessage": "",
  "scope": [],
  "blocked": [
    "file changes",
    "commits",
    "push",
    "runtime changes",
    "MCP tool changes",
    "dispatch chaining"
  ],
  "validation": [
    "npm run build",
    "npm run mcp:smoke",
    "npm run review:latest",
    ".\\scripts\\bridge-status.ps1",
    "git status --short"
  ],
  "expectedOutput": [
    "validation result summary",
    "approved MCP tool list confirmation",
    "bridge status summary",
    "final git status"
  ]
}
```

### C. Narrow Test Update Pattern

Use this pattern for small test or validation script updates.

Safe examples:

- smoke harness adjustment
- test script update
- validation script improvement

Requirements:

- bounded files
- validation defined
- no architecture expansion
- no bridge exposure changes
- no new MCP tools
- no arbitrary shell, file, or Git capability

Example task envelope:

```json
{
  "repo": "self",
  "worker": "codex",
  "task": "Adjust the MCP smoke harness output wording to make the approved tool list easier to review, without changing tool registration or runtime behavior.",
  "commitMessage": "test: clarify mcp smoke output",
  "scope": [
    "scripts/mcp-smoke.mjs"
  ],
  "blocked": [
    "mcp/tools/",
    "mcp/server/",
    "bridge behavior",
    "Dispatcher runtime",
    "new MCP tools",
    "schema changes",
    "auto-dispatch"
  ],
  "validation": [
    "npm run build",
    "npm run mcp:smoke",
    "git diff --check",
    "git status --short"
  ],
  "expectedOutput": [
    "small test harness update",
    "MCP smoke passes",
    "tool list remains exactly four approved tools"
  ]
}
```

### D. Bounded Bug Fix Pattern

Use this pattern for a narrow defect with a clear failure mode and limited blast radius.

Safe examples:

- single helper failure
- parsing issue
- wrapper script issue
- documentation mismatch

Requirements:

- problem statement
- limited blast radius
- validation plan
- explicit blocked areas
- no architecture expansion
- no security boundary change

Example task envelope:

```json
{
  "repo": "self",
  "worker": "codex",
  "task": "Fix the review helper so it handles a missing optional summary file gracefully while remaining read-only.",
  "commitMessage": "fix: handle missing latest run summary",
  "scope": [
    "scripts/review-latest-run.mjs",
    "scripts/review-latest-run.ps1"
  ],
  "blocked": [
    "MCP tools",
    "Dispatcher runtime",
    "bridge behavior",
    "write-side review state",
    "auto-review",
    "auto-dispatch",
    "push automation"
  ],
  "validation": [
    "npm run build",
    "npm run review:latest",
    "npm run mcp:smoke",
    "git diff --check",
    "git status --short"
  ],
  "expectedOutput": [
    "bounded helper fix",
    "review helper remains read-only",
    "validations pass",
    "summary of changed files"
  ]
}
```

### E. Documentation + Validation Combo Pattern

Use this pattern when a documentation update must be paired with validation evidence.

Safe examples:

- add guide + run validation
- update runbook + smoke check

Requirements:

- clear separation between docs and validation
- explicit documentation files
- validation output summarized in the run result
- no runtime changes unless separately approved under another pattern

Example task envelope:

```json
{
  "repo": "self",
  "worker": "codex",
  "task": "Add a short operator note about pre-start validation and run the standard validation suite. Keep the change documentation-only.",
  "commitMessage": "docs: add pre-start validation note",
  "scope": [
    "docs/chatgpt-operator-workflow.md"
  ],
  "blocked": [
    "mcp/",
    "scripts/",
    "dispatcher runtime",
    "bridge behavior",
    "new tools",
    "automation"
  ],
  "validation": [
    "npm run build",
    "npm run mcp:smoke",
    "npm run review:latest",
    ".\\scripts\\bridge-status.ps1",
    "git diff --check",
    "git status --short"
  ],
  "expectedOutput": [
    "documentation change",
    "validation summary",
    "final git status",
    "commit hash if committed"
  ]
}
```

## Conditionally Allowed Patterns

These patterns require extra caution. They are not casual daily dispatches.

### Bridge-Adjacent Changes

Examples:

- bridge status script adjustment
- local bridge client error wording
- operator-facing bridge diagnostics

Require:

- tighter scope
- stronger validation
- explicit review
- confirmation that localhost-only and token protection remain unchanged

### MCP Skeleton Adjustment

Examples:

- server startup message adjustment
- error formatting cleanup
- smoke-test-compatible metadata clarification

Require:

- explicit confirmation that the approved tool list remains exactly four tools
- no schema expansion
- no new tool registration
- MCP smoke validation
- careful review of all MCP-facing diffs

### Helper Script Changes

Examples:

- review helper formatting
- latest-run parsing fix
- PowerShell wrapper message cleanup

Require:

- proof that helper behavior remains read-only
- validation with `npm run review:latest`
- blocked areas that prevent dispatch, push, or acceptance-state writes

### Build Pipeline Changes

Examples:

- `npm run build` command maintenance
- syntax-check target adjustment
- package script wording cleanup

Require:

- explicit file scope
- validation before and after change
- review of package script behavior
- no introduction of background execution or deployment behavior

## Explicitly Blocked Patterns

Do not dispatch these patterns:

- autonomous loop
- scheduler or queue introduction
- remote execution
- tunnel or public bridge
- arbitrary shell capability
- arbitrary file capability
- arbitrary Git capability
- broad refactor without scope
- credential or token handling changes
- dispatch chaining
- unattended retry loops
- "fix everything" prompts

Concrete unsafe examples:

- "Add an autonomous loop that keeps dispatching until all issues are fixed."
- "Create a queue so tasks can run in the background overnight."
- "Expose the bridge publicly so a remote client can dispatch work."
- "Add a tunnel for external MCP access."
- "Add an MCP tool that can run any shell command."
- "Add an MCP tool that can read or write arbitrary files."
- "Add a Git MCP tool that commits, pushes, resets, or force-pushes directly."
- "Refactor the whole Dispatcher and clean up anything you see."
- "Fix token handling by printing the token during startup for debugging."
- "Retry failed dispatches automatically until they pass."
- "Let Cline commit and push once it thinks the task is done."

Blocked patterns require separate design, security review, and explicit operator authorization before any implementation discussion.

## Review Expectations Per Pattern

### Docs-Only Change Pattern

Expected validation level:

- `npm run build`
- `npm run mcp:smoke`
- `git diff --check`
- `git status --short`

Expected review depth:

- review changed docs for accuracy
- confirm no runtime files changed
- confirm safety boundary wording is preserved

Push expectations:

- push allowed after validation, clean repo, commit review, and operator approval

### Validation-Only Pattern

Expected validation level:

- run only the requested diagnostics and validations
- no file changes expected

Expected review depth:

- review command output summary
- confirm final Git status
- confirm no side effects

Push expectations:

- no push expected unless a separate documentation artifact is explicitly created and approved

### Narrow Test Update Pattern

Expected validation level:

- `npm run build`
- targeted test or smoke command
- `npm run mcp:smoke` when MCP-adjacent
- `git diff --check`
- `git status --short`

Expected review depth:

- inspect the test script diff carefully
- confirm no production behavior changed
- confirm approved tool list remains unchanged

Push expectations:

- push only after validations pass, review is complete, and scope is satisfied

### Bounded Bug Fix Pattern

Expected validation level:

- reproduce or describe the failure
- run relevant targeted validation
- run standard validation commands
- confirm clean Git status after commit

Expected review depth:

- inspect changed files line by line
- confirm blast radius stayed limited
- confirm blocked areas were untouched
- confirm no security boundary changed

Push expectations:

- push only after explicit acceptance and clean repo state

### Documentation + Validation Combo Pattern

Expected validation level:

- standard validation suite
- documentation review
- diff whitespace check

Expected review depth:

- confirm docs match actual validation results
- confirm validation did not create unexpected artifacts
- confirm no runtime files changed unless explicitly scoped

Push expectations:

- push allowed after validation, review, clean repo, and operator approval

## Pattern Selection Guide

Use this quick selection guide:

- if docs-only, use Pattern A
- if validation work only, use Pattern B
- if a small test or smoke harness update is needed, use Pattern C
- if a narrow fix is needed, use Pattern D
- if docs and validation evidence are both required, use Pattern E
- if bridge-adjacent, MCP-adjacent, helper script, or build pipeline work is needed, use the conditionally allowed pattern rules
- if the task requests autonomy, public exposure, arbitrary capabilities, broad refactor, credential handling, dispatch chaining, or unattended retry, do not dispatch

When uncertain, choose the narrower pattern or stop for operator review.

## Relationship to Earlier Phases

Phase 6.3 builds on:

- Phase 6.0 Production Operator Runbook Foundation, which defines the daily operating boundary and safe task envelope.
- Phase 6.1 Operator Runbook Checklist Templates, which provide manual pre-start, dispatch, review, push, and incident checklists.
- Phase 6.2 Production Troubleshooting Guide, which defines safe diagnostics and stop rules when something fails.

The catalog gives operators concrete pattern choices before dispatch so the review gate remains practical and repeatable.

## Recommendation for Phase 6.4

Recommended next phase:

```text
Phase 6.4 - Production Readiness Review
```

Phase 6.4 should review the full Phase 6 operator package, confirm the production boundary, verify the checklist and troubleshooting coverage, and define readiness criteria for daily use.
