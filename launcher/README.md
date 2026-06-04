# JJ AI Dispatcher Launcher

JJ AI Dispatcher Launcher is an internal subproject for a future config-driven startup helper for JJ AI Dispatcher services. Its purpose is to describe and eventually coordinate service startup from configuration, so local, VM, and cloud migration can be handled by changing config instead of rewriting launcher logic.

This subproject provides config loading, resolved startup planning, and local startup for explicitly enabled services. It can later be extracted into a standalone `jj-ai-dispatcher-launcher` repository when the launcher has its own release, test, and ownership needs.

## Scope

The launcher is planned to:

- Read a launcher configuration file.
- Validate declared service definitions before startup.
- Present clear operator guidance for local development and future hosted environments.
- Keep environment-specific details in config, not in source code.
- Support future local, VM, and cloud migration by changing config only.

## Safety Boundaries

The launcher does not:

- Invoke Codex directly.
- Modify JJ AI Dispatcher core behavior.
- Modify MCP configuration or MCP runtime behavior.
- Install schedulers, background services, or cloud deployment automation.
- Store token values, secrets, or user-specific runtime paths.
- Implement health checks.

`launcher.ps1` loads local config, prints a resolved startup plan for enabled services, validates enabled service working directories, and starts enabled services in separate PowerShell windows unless `-PlanOnly` is supplied.

## Startup Concept

The launcher currently handles these local startup steps:

1. Load a local launcher config file.
2. Resolve supported variables in selected service fields.
3. Show an operator-readable startup plan for enabled services.
4. Validate enabled service working directories.
5. Start enabled services in separate PowerShell windows.

Future versions should extend this sequence:

1. Validate service names, commands, working directories, environment settings, and dependencies.
2. Start only explicitly enabled services.
3. Record status and diagnostics without changing Dispatcher core logic.

The same startup model should work across environments by changing config values such as service command, working directory, host, port, health check, and dependency order.

## Files

- `start.bat` calls `launcher.ps1` normally and forwards arguments.
- `launcher.ps1` loads `launcher.config.local.json`, prints a resolved startup plan, and starts enabled services unless `-PlanOnly` is supplied.
- `launcher.config.example.json` shows example config structure without secrets.
- `.gitignore` excludes local launcher config and transient logs.
- `docs/launcher-plan.md` records the phased plan.

## Startup Usage

From this directory:

```bat
start.bat
```

Or from PowerShell:

```powershell
.\launcher.ps1
```

Both commands load `launcher.config.local.json`, print the resolved plan, skip disabled services, validate enabled service working directories, and then start each enabled service in its own PowerShell window.

## Plan-Only Usage

Use `-PlanOnly` to preview startup without starting any services:

```bat
start.bat -PlanOnly
```

Or from PowerShell:

```powershell
.\launcher.ps1 -PlanOnly
```

On first run, if `launcher.config.local.json` does not exist, the script prints setup instructions:

1. Copy `launcher.config.example.json` to `launcher.config.local.json`.
2. Edit `launcher.config.local.json` for local paths.
3. Keep token values, API keys, and secrets out of launcher config.

The config loader supports basic variable substitution for these values:

- `${dispatcherRoot}` resolves to the repository root.
- `${launcherRoot}` resolves to the `launcher/` directory.

Substitution is applied to service `workingDirectory`, service `command`, and health check `url` fields. The resolved service startup plan prints enabled services with service name, working directory, and command. Disabled services are listed as skipped. Arguments and environment values are not printed to avoid leaking secrets.

Health checks are not implemented yet. The launcher may resolve a configured health check URL for planning consistency, but it does not call health check endpoints or wait for readiness.
