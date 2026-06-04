# JJ AI Dispatcher Launcher

JJ AI Dispatcher Launcher is an internal subproject for a future config-driven startup helper for JJ AI Dispatcher services. Its purpose is to describe and eventually coordinate service startup from configuration, so local, VM, and cloud migration can be handled by changing config instead of rewriting launcher logic.

This subproject is intentionally a documentation-only foundation right now. It can later be extracted into a standalone `jj-ai-dispatcher-launcher` repository when the launcher has its own release, test, and ownership needs.

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

`launcher.ps1` only prints a placeholder message and setup guidance. It is safe to run as an orientation script, not as an operational launcher.

## Startup Concept

Future versions should treat startup as a config-driven sequence:

1. Load a local launcher config file.
2. Validate service names, commands, working directories, environment settings, and dependencies.
3. Show an operator-readable startup plan.
4. Start only explicitly enabled services.
5. Record status and diagnostics without changing Dispatcher core logic.

The same startup model should work across environments by changing config values such as service command, working directory, host, port, health check, and dependency order.

## Files

- `start.bat` calls `launcher.ps1`.
- `launcher.ps1` prints placeholder guidance only.
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

Both entry points are placeholders and do not start services.
