# Phase 5.0 Tool Integration Feasibility Study

## Purpose

Evaluate how ChatGPT can communicate with JJ AI Dispatcher as a controlled tool layer without directly controlling the VSCode UI. The study compares possible integration paths, security boundaries, auditability, and readiness for a future implementation phase.

This document is research and design only. It does not implement MCP, tunnels, public endpoints, VSCode automation, or any new execution path.

## Current Baseline

- Branch baseline: `main @ 1073864`
- Phase 4 tag: `v0.4-phase4-operator-layer`
- Local HTTP Bridge works.
- Operator helper scripts work.
- Manual review loop works.

Current safe flow:

```text
ChatGPT -> Operator -> Dispatcher Bridge -> Codex -> Git -> Result -> Operator -> ChatGPT Review
```

## Integration Options

### A. Continue Manual Helper-Script Operator Flow

ChatGPT prepares a task envelope, the human operator runs helper scripts, then pastes the result back to ChatGPT.

- Strengths: safest current path, human approval is explicit, no new exposure.
- Weaknesses: manual copy/paste, slower iteration, operator must stay in the loop.
- Fit: stable baseline and fallback path for all future phases.

### B. Local MCP Server Wrapping Dispatcher Bridge

A local MCP server exposes a small allowlisted tool surface that calls the existing local bridge endpoints.

- Strengths: natural fit for tool calling, can preserve Dispatcher as the execution controller, easy to audit if tools are narrow.
- Weaknesses: requires careful tool boundary design, token handling, and local process management.
- Fit: preferred research direction after a documentation-only MCP boundary design.

### C. ChatGPT App / Custom Connector

A ChatGPT-facing app or connector exposes a controlled interface to Dispatcher.

- Strengths: more polished user experience, potential for structured task/result exchange.
- Weaknesses: platform availability, auth model, and local network access constraints need research.
- Fit: useful later, after the local MCP/tool contract is clear.

### D. HTTPS Tunnel To Local Bridge

A tunnel exposes the local bridge through an HTTPS endpoint.

- Strengths: allows remote tool calls to reach the local bridge.
- Weaknesses: high remote exposure risk, token leakage risk, public endpoint hardening burden.
- Fit: not appropriate until the local tool boundary and approval model are proven.

### E. GitHub Issue Bridge

ChatGPT or an operator creates GitHub issues as dispatch requests, and Dispatcher polls or processes them.

- Strengths: strong audit trail, async workflow, GitHub permissions and history are familiar.
- Weaknesses: slower, requires GitHub automation, issue spoofing and command injection boundaries must be designed.
- Fit: possible future async route, not Phase 5.0 implementation.

### F. VSCode Extension Bridge

A VSCode extension provides a controlled bridge UI or local tool endpoint for Dispatcher operations.

- Strengths: good local operator experience, can show repo state and review prompts.
- Weaknesses: extension security, VSCode API complexity, local permissions, packaging overhead.
- Fit: possible UX layer after Dispatcher tool contract stabilizes.

### G. Direct VSCode UI Automation

ChatGPT drives VSCode UI actions directly through automation.

- Strengths: appears flexible.
- Weaknesses: brittle, hard to audit, high risk of unintended edits, weak approval boundaries, unsafe credential/file exposure risk.
- Fit: not recommended.

## Recommendation

Preferred direction:

```text
ChatGPT -> MCP/custom tool -> Dispatcher -> Codex -> Git -> Result
```

This keeps Dispatcher as the execution controller and Git as the control point. ChatGPT should talk to a narrow tool layer, not to the editor UI.

Not recommended:

```text
ChatGPT -> VSCode UI automation
```

Direct VSCode UI automation is too broad, brittle, and difficult to audit. It bypasses the clean Dispatcher contract and makes safe rollback harder.

## Security Analysis

### A. Manual Helper-Script Operator Flow

- Local-only safety: strong; operator runs commands locally.
- Token handling: token remains in `dispatcher/config.local.json`; helpers use it as a header.
- Command injection risk: low to medium; task text still reaches Codex and must be reviewed.
- Arbitrary file access risk: bounded by selected repo and Codex behavior.
- Remote exposure risk: low; no remote endpoint added.
- Auditability: strong; Git commits, run artifacts, and pasted results are visible.
- Rollback capability: strong through Git.
- Human approval point: strong; operator approves every dispatch.

### B. Local MCP Server Wrapping Dispatcher Bridge

- Local-only safety: strong if bound to localhost and not exposed.
- Token handling: should read local config or use process-local secret handling; must not print tokens.
- Command injection risk: medium; tool schemas must constrain fields and preserve Dispatcher validation.
- Arbitrary file access risk: medium unless tools are limited to dispatcher endpoints and known repo aliases.
- Remote exposure risk: low if local-only; high if paired with a tunnel.
- Auditability: strong if every tool call maps to Dispatcher run artifacts.
- Rollback capability: strong through Git if Dispatcher remains the only execution path.
- Human approval point: configurable; should require explicit user approval before dispatch.

### C. ChatGPT App / Custom Connector

- Local-only safety: uncertain; depends on platform support for local-only connectors.
- Token handling: sensitive; connector auth and local token storage need careful design.
- Command injection risk: medium; structured schemas help, but task text remains powerful.
- Arbitrary file access risk: medium if connector can reach broad local APIs.
- Remote exposure risk: medium to high depending on connector architecture.
- Auditability: medium to strong if calls are logged and still flow through Dispatcher.
- Rollback capability: strong if Git remains the control point.
- Human approval point: must be explicit in the connector UX.

### D. HTTPS Tunnel To Local Bridge

- Local-only safety: weak; the bridge becomes reachable outside localhost.
- Token handling: high risk; token becomes remote bearer credential.
- Command injection risk: medium to high if endpoint is reachable by unauthorized actors.
- Arbitrary file access risk: medium to high through dispatch misuse.
- Remote exposure risk: high by design.
- Auditability: medium; bridge artifacts exist, but external request provenance must be added.
- Rollback capability: medium to strong through Git, but damage surface is larger.
- Human approval point: weak unless an additional approval gate is built.

### E. GitHub Issue Bridge

- Local-only safety: medium; execution remains local, but requests arrive through GitHub.
- Token handling: GitHub credentials and local bridge token must stay separate.
- Command injection risk: medium; issue text must be parsed conservatively.
- Arbitrary file access risk: medium; repo targeting must be allowlisted.
- Remote exposure risk: medium; no direct local port exposure, but remote users can submit requests if permitted.
- Auditability: strong; issues, comments, commits, and run artifacts form a trace.
- Rollback capability: strong through Git.
- Human approval point: strong if labels or comments are required before dispatch.

### F. VSCode Extension Bridge

- Local-only safety: medium to strong if it remains local and does not expose a public endpoint.
- Token handling: must avoid storing tokens in extension-visible logs or settings sync.
- Command injection risk: medium; extension commands must call only Dispatcher endpoints.
- Arbitrary file access risk: medium; VSCode extensions can access workspace files.
- Remote exposure risk: low if local-only; higher if paired with remote extension features.
- Auditability: medium; requires explicit logging to match Dispatcher artifacts.
- Rollback capability: strong if execution still flows through Dispatcher and Git.
- Human approval point: strong if the extension presents an approval UI before dispatch.

### G. Direct VSCode UI Automation

- Local-only safety: weak; local UI control is broad and hard to constrain.
- Token handling: risky; UI automation may expose secrets in terminals, editors, or logs.
- Command injection risk: high; automation can type or run unintended commands.
- Arbitrary file access risk: high; editor UI can access broad workspace content.
- Remote exposure risk: medium; depends on automation channel, but control surface is broad.
- Auditability: weak; UI actions are not a clean execution contract.
- Rollback capability: weak to medium; Git helps only after changes are detected.
- Human approval point: weak; UI automation can blur action boundaries.

## Safe Phase 5 Boundary

Phase 5 should only research and design:

- No MCP implementation yet.
- No tunnel.
- No public endpoint.
- No remote execution.
- No auto-chain.
- No direct VSCode control.

Any future implementation must preserve Dispatcher as the execution controller and Git as the control point.

## Future MCP Concept

A future local MCP server could expose only narrow Dispatcher tools:

- `dispatcher_status`: call `GET /status`.
- `dispatcher_dispatch`: send a constrained `POST /dispatch` payload.
- `dispatcher_latest_result`: call `GET /runs/latest`.
- `dispatcher_get_run`: call `GET /runs/{taskId}`.

Blocked MCP tools:

- `arbitrary_shell`
- `arbitrary_file_read`
- `arbitrary_file_write`
- `delete`
- `push`
- `tunnel_enable`

The MCP layer should not gain capabilities that Dispatcher itself does not intentionally expose.

## Decision Matrix

Scores: 1 = weak, 5 = strong.

| Option | Safety | Implementation Difficulty | Usefulness | Auditability | Readiness |
| --- | ---: | ---: | ---: | ---: | ---: |
| A. Manual helper-script operator flow | 5 | 1 | 3 | 5 | 5 |
| B. Local MCP server wrapping Dispatcher bridge | 4 | 3 | 5 | 4 | 3 |
| C. ChatGPT App / custom connector | 3 | 4 | 4 | 3 | 2 |
| D. HTTPS tunnel to local bridge | 1 | 3 | 4 | 2 | 1 |
| E. GitHub Issue Bridge | 3 | 4 | 3 | 5 | 2 |
| F. VSCode extension bridge | 3 | 5 | 4 | 3 | 2 |
| G. Direct VSCode UI automation | 1 | 4 | 2 | 1 | 1 |

## Recommended Next Step

Phase 5.1 - MCP Boundary Design

Scope:

- Documentation only.
- Define exact MCP tool schemas.
- Define approval points.
- Define token handling rules.
- Define audit and run-result mapping.
- Keep all execution local-only.
- Do not implement MCP yet.
