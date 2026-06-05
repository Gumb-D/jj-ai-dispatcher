# JJ AI Dispatcher Launcher Plan

## Purpose

The JJ AI Dispatcher Launcher is planned as a config-driven startup helper for JJ AI Dispatcher services. It should give operators one clear entry point for reading environment configuration, validating startup intent, and eventually coordinating service startup without changing Dispatcher core code.

The subproject starts under `launcher/` for internal development. It can later be extracted into a standalone `jj-ai-dispatcher-launcher` repo when it needs independent versioning, distribution, or release governance.

## Safety Boundaries

The launcher must preserve these boundaries:

- No direct Codex invocation.
- No Dispatcher core changes.
- No MCP changes.
- No scheduler or background service installation.
- No cloud deployment automation.
- No token values or secrets in committed files.
- No hardcoded user-specific runtime paths except generic example placeholders.
- No secret health check header logging.
- No external exposure or tunneling of Dispatcher Bridge port 8787.

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

### Phase 1: Config Loading and Dry-Run Plan

- Load `launcher.config.local.json` or an explicitly supplied config path.
- Print clear setup instructions when local config is missing.
- Resolve `${dispatcherRoot}` and `${launcherRoot}` in service `workingDirectory`, service `command`, and health check `url` fields.
- Print a startup preview without executing commands.
- Omit arguments and environment values from logs to avoid exposing secrets.

Phase 1 established config loading and resolved plan output. Startup now happens in the next phase unless `-PlanOnly` is supplied.

### Phase 2: Validation and Local Startup

- Validate schema shape, required service fields, duplicate names, dependency references, and disabled services.
- Add `-PlanOnly` for safe preview without startup.
- Validate enabled service working directories before startup.
- Start enabled services in separate PowerShell windows.
- Skip disabled services.

Phase 2 established local startup while preserving `-PlanOnly` as a non-starting preview mode.

### Phase 3: Dry-Run Startup Planning Enhancements

- Resolve dependency order.
- Show the exact services that would start.
- Show working directories and health checks.
- Add clear failure messages for missing paths, unsupported runtime types, and invalid dependency graphs.

Phase 3 now includes configured health check planning. The plan output shows health check name, enabled state, URL, method, timeout, and masked header names.

### Phase 4: Controlled Local Startup Enhancements

- Improve local service startup controls.
- Keep command execution visible and auditable.
- Avoid direct Codex invocation and avoid Dispatcher core changes.
- Run enabled health checks after startup using `startupDelaySeconds`.
- Add `-HealthOnly` for checking already-running services without starting new windows.
- Print `PASS`, `FAIL`, and `SKIP` health check results with a final summary.
- Bound each health check with `timeoutSeconds` so launcher execution does not block forever.

### Phase 5: VM-Ready Configuration

- Add VM-oriented config examples.
- Support host, port, and health-check differences through config.
- Keep startup behavior consistent with local mode.

### Phase 6: Cloud Migration Readiness

- Document cloud-hosted service assumptions.
- Support cloud-oriented service descriptors through config only.
- Do not automate cloud deployment unless a separate approved project phase adds that scope.

### Phase 7: Standalone Repository Extraction

- Evaluate whether `launcher/` should become `jj-ai-dispatcher-launcher`.
- Move documentation, tests, config schema, and launcher code into the standalone repo.
- Preserve compatibility with JJ AI Dispatcher service definitions.

## Current State

The current launcher loads `launcher.config.local.json` from the launcher folder and prints a resolved plan for enabled services. If local config is missing, it prints setup guidance telling the operator to copy `launcher.config.example.json` to `launcher.config.local.json` and edit local paths.

Running `start.bat` or `launcher.ps1` normally starts enabled services in separate PowerShell windows after printing the resolved plan and validating enabled service working directories, waits for `startupDelaySeconds`, and then runs enabled health checks.

Running `launcher.ps1 -PlanOnly` or `start.bat -PlanOnly` prints the resolved service and health check plan without starting services or calling health check endpoints.

Running `launcher.ps1 -HealthOnly` or `start.bat -HealthOnly` runs configured health checks without starting services.

Example commands:

```powershell
.\launcher.ps1 -PlanOnly
.\launcher.ps1
.\launcher.ps1 -HealthOnly
```

The launcher still does not invoke Codex, modify Dispatcher core, modify MCP, install schedulers, expose or tunnel Dispatcher Bridge port 8787, or log secret health check header values.
