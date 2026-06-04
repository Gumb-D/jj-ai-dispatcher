# JJ AI Dispatcher Launcher Plan

## Purpose

The JJ AI Dispatcher Launcher is planned as a config-driven startup helper for JJ AI Dispatcher services. It should give operators one clear entry point for reading environment configuration, validating startup intent, and eventually coordinating service startup without changing Dispatcher core code.

The subproject starts under `launcher/` for internal development. It can later be extracted into a standalone `jj-ai-dispatcher-launcher` repo when it needs independent versioning, distribution, or release governance.

## Safety Boundaries

The launcher must preserve these boundaries:

- No real service startup logic in this initial skeleton.
- No direct Codex invocation.
- No Dispatcher core changes.
- No MCP changes.
- No scheduler or background service installation.
- No cloud deployment automation.
- No token values or secrets in committed files.
- No hardcoded user-specific runtime paths except generic example placeholders.

Future startup behavior should be explicit, operator-visible, and driven by configuration. Disabled services must stay disabled unless config enables them.

## Startup Concept

The future launcher should model startup as declared service entries rather than hardcoded scripts. Each service should be described by config fields such as:

- Service name.
- Enabled state.
- Runtime type.
- Working directory.
- Command and arguments.
- Dependency order.
- Health check.
- Environment-specific notes.

This lets the same launcher support local workstations, VMs, and cloud-hosted migration paths by changing config values only.

## Phased Plan

### Phase 0: Skeleton

- Create `launcher/` as an internal subproject.
- Add README, plan documentation, example config, batch entry point, and PowerShell placeholder.
- Confirm the script prints guidance only and does not start services.

### Phase 1: Config Loading and Validation

- Load `launcher.config.local.json` or an explicitly supplied config path.
- Validate schema shape, required service fields, duplicate names, dependency references, and disabled services.
- Print a startup preview without executing commands.

### Phase 2: Dry-Run Startup Planning

- Resolve dependency order.
- Show the exact services that would start.
- Show working directories and health checks.
- Add clear failure messages for missing paths, unsupported runtime types, and invalid dependency graphs.

### Phase 3: Controlled Local Startup

- Add opt-in local service startup.
- Start only enabled services.
- Keep command execution visible and auditable.
- Avoid direct Codex invocation and avoid Dispatcher core changes.

### Phase 4: VM-Ready Configuration

- Add VM-oriented config examples.
- Support host, port, and health-check differences through config.
- Keep startup behavior consistent with local mode.

### Phase 5: Cloud Migration Readiness

- Document cloud-hosted service assumptions.
- Support cloud-oriented service descriptors through config only.
- Do not automate cloud deployment unless a separate approved project phase adds that scope.

### Phase 6: Standalone Repository Extraction

- Evaluate whether `launcher/` should become `jj-ai-dispatcher-launcher`.
- Move documentation, tests, config schema, and launcher code into the standalone repo.
- Preserve compatibility with JJ AI Dispatcher service definitions.

## Current State

The current launcher is a placeholder. Running `start.bat` or `launcher.ps1` prints setup guidance and safety boundaries only.
