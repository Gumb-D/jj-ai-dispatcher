# Phase 5.12 Stabilization Checklist and Release Tag Candidate

## Purpose

Phase 5.12 stabilizes Phase 5 as a validated milestone before any Phase 6 work.

Phase 5 proves the MCP/tool integration path while preserving the project safety boundary:

```text
ChatGPT / MCP client
  |
  v
MCP stdio server
  |
  v
Local Dispatcher Bridge
  |
  v
Dispatcher
  |
  v
Codex Worker
  |
  v
Git result
  |
  v
Manual review gate
```

This document is a release-candidate checklist. It does not create a tag and does not authorize feature expansion.

## Phase 5 Completed Scope

- Phase 5.0 feasibility: confirmed MCP/tool integration is feasible without expanding the Dispatcher into a remote or autonomous system.
- Phase 5.1 MCP boundary design: defined MCP as a thin adapter over the local bridge with localhost and token boundaries preserved.
- Phase 5.2 protocol research: captured MCP stdio/client behavior needed for a minimal local integration.
- Phase 5.3 skeleton design: designed the minimal MCP server shape and approved tool surface.
- Phase 5.4 minimal MCP server skeleton: added the stdio MCP server with the approved Dispatcher tools.
- Phase 5.5 client validation operator guide: documented how an operator validates an MCP client against the approved boundary.
- Phase 5.6 operator validation run: executed and documented local operator validation.
- Phase 5.7A MCP smoke harness: added repeatable MCP registration and read-only smoke validation.
- Phase 5.7B gated `dispatcher_dispatch` smoke: validated one explicit docs-only dispatch through MCP and the local bridge.
- Phase 5.8 review gate policy: formalized accepted, rejected, and needs-followup review states.
- Phase 5.9 structured review classification: defined machine-readable review classification guidance.
- Phase 5.10A manual review templates: added reusable manual review checklist and example artifacts.
- Phase 5.10B read-only review helper: added a helper that reads latest run output and prints a manual review checklist without side effects.
- Phase 5.11 client dispatch/review usage notes: documented client-specific pre-flight, dispatch, review, and safety guidance.

## Stabilization Checklist

Validation checks:

- [ ] Repository is clean before release tagging.
- [ ] `npm run build` passes.
- [ ] `npm run mcp:smoke` passes.
- [ ] `npm run review:latest` passes.
- [ ] `.\scripts\bridge-status.ps1` reports healthy bridge status.
- [ ] MCP server registers exactly four approved tools.
- [ ] Forbidden tool names are absent.
- [ ] Gated `dispatcher_dispatch` smoke has been tested.
- [ ] Review policy is documented.
- [ ] Review classification model is documented.
- [ ] Manual review templates are available.
- [ ] Read-only latest-run review helper is available.
- [ ] Client usage notes are available.

Safety checks:

- [ ] No secrets committed.
- [ ] No bridge token printed in validation output.
- [ ] No tunnel added.
- [ ] No public listener added.
- [ ] No remote bridge added.
- [ ] No autonomous loop added.
- [ ] No queue added.
- [ ] No scheduler added.
- [ ] No arbitrary shell MCP tool added.
- [ ] No arbitrary file read/write MCP tool added.
- [ ] No direct Git MCP tool added.
- [ ] Review helper remains read-only.
- [ ] Review gate remains preserved.

Approved MCP tools:

- `dispatcher_status`
- `dispatcher_dispatch`
- `dispatcher_latest_result`
- `dispatcher_get_run`

Forbidden tool names and capabilities:

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

## Release Tag Candidate

Recommended tag:

```text
v0.5-phase5-mcp-tool-validation
```

Tagging criteria:

- All validations pass.
- Working tree is clean.
- Remote `origin/main` is up to date.
- Operator accepts the Phase 5 boundary.
- Operator accepts the Dispatcher-created Phase 5 smoke artifacts.
- Operator confirms no tag should be delayed for further review.

Do not create the tag automatically during Phase 5.12. Create it only after explicit operator acceptance.

## Phase 5 Acceptance Statement

Suggested acceptance statement:

```text
Phase 5 is accepted as the MCP/tool integration validation milestone. The system proves ChatGPT-to-Dispatcher tool flow through MCP stdio and the local bridge while preserving localhost/token safety, explicit dispatch, and manual review gates.
```

## Phase 6 Boundary Recommendation

Safest recommended Phase 6 direction:

```text
Phase 6 - Production Operator Runbook
```

Phase 6 should turn the validated Phase 5 workflow into a practical operator runbook for repeated safe use.

Phase 6 should include:

- pre-flight procedure
- MCP client setup notes
- dispatch approval checklist
- review helper usage
- accepted/rejected/needs-followup decision procedure
- push/tag/release guidance
- recovery and rollback review notes

Phase 6 should not be:

- autonomous coding loop
- remote/public bridge
- tunnel-first approach
- scheduler or queue before operator runbook
- broad multi-agent expansion
- unattended production operation

Controlled external client integration can follow after the production operator runbook is stable.

## Final Operator Commands

Suggested manual stabilization commands:

```powershell
git status --short
git log --oneline -10
npm run build
npm run mcp:smoke
npm run review:latest
.\scripts\bridge-status.ps1
```

If Phase 5 is accepted later, create and push the release tag:

```powershell
git tag v0.5-phase5-mcp-tool-validation
git push origin v0.5-phase5-mcp-tool-validation
```

Tag creation is intentionally deferred until explicit operator acceptance.
