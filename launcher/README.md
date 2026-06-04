# JJ AI Dispatcher Launcher

JJ AI Dispatcher Launcher is an internal subproject for a future config-driven startup helper for JJ AI Dispatcher services. Its purpose is to describe and eventually coordinate service startup from configuration, so local, VM, and cloud migration can be handled by changing config instead of rewriting launcher logic.

This subproject is intentionally limited to config loading and dry-run planning right now. It can later be extracted into a standalone `jj-ai-dispatcher-launcher` repository when the launcher has its own release, test, and ownership needs.

## Scope

The launcher is planned to:

- Read a launcher configuration file.
- Validate declared service definitions before startup.
- Present clear operator guidance for local development and future hosted environments.
- Keep environment-specific details in config, not in source code.
- Support future local, VM, and cloud migration by changing config only.

## Safety Boundaries

This initial skeleton does not:

- Start services.
- Invoke Codex directly.
- Modify JJ AI Dispatcher core behavior.
- Modify MCP configuration or MCP runtime behavior.
- Install schedulers, background services, or cloud deployment automation.
- Store token values, secrets, or user-specific runtime paths.

`launcher.ps1` loads local config and prints a resolved startup plan for enabled services. Startup is not implemented yet, so it is safe to run as an orientation script, not as an operational launcher.

## Startup Concept

The launcher currently handles the first planning steps:

1. Load a local launcher config file.
2. Resolve supported variables in selected service fields.
3. Show an operator-readable startup plan for enabled services.

Future versions should extend this sequence:

1. Validate service names, commands, working directories, environment settings, and dependencies.
2. Start only explicitly enabled services.
3. Record status and diagnostics without changing Dispatcher core logic.

The same startup model should work across environments by changing config values such as service command, working directory, host, port, health check, and dependency order.

## Files

- `start.bat` calls `launcher.ps1`.
- `launcher.ps1` loads `launcher.config.local.json` and prints a dry-run startup plan.
- `launcher.config.example.json` shows example config structure without secrets.
- `.gitignore` excludes local launcher config and transient logs.
- `docs/launcher-plan.md` records the phased plan.

## Current Usage

From this directory:

```bat
start.bat
```

Or from PowerShell:

```powershell
.\launcher.ps1
```

On first run, if `launcher.config.local.json` does not exist, the script prints setup instructions:

1. Copy `launcher.config.example.json` to `launcher.config.local.json`.
2. Edit `launcher.config.local.json` for local paths.
3. Keep token values, API keys, and secrets out of launcher config.

The config loader supports basic variable substitution for these values:

- `${dispatcherRoot}` resolves to the repository root.
- `${launcherRoot}` resolves to the `launcher/` directory.

Substitution is applied to service `workingDirectory`, service `command`, and health check `url` fields. The resolved service startup plan prints only enabled services with service name, working directory, and command. Arguments and environment values are not printed to avoid leaking secrets.

Startup is not implemented yet. Both entry points load config or show setup guidance, print the dry-run plan when possible, and do not start services.
