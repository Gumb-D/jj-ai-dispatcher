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
- Expose or tunnel Dispatcher Bridge port 8787.
- Log secret health check header values.

`launcher.ps1` loads local config, prints a resolved startup plan for enabled services, validates enabled service working directories, starts enabled services in separate PowerShell windows unless `-PlanOnly` is supplied, and runs configured health checks after startup. Use `-HealthOnly` to run health checks without starting services.

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
- `launcher.ps1` loads `launcher.config.local.json`, prints a resolved startup plan, starts enabled services unless `-PlanOnly` or `-HealthOnly` is supplied, and runs configured health checks.
- `launcher.config.example.json` shows example config structure without secrets.
- `.gitignore` excludes local launcher config and transient logs.
- `docs/launcher-plan.md` records the phased plan.
- `docs/operator-guide.md` covers setup, verification, startup, shutdown, connector reminders, and troubleshooting.
- `docs/migration-guide.md` covers config-only migration across local PC, ZTE laptop, VM, and cloud-like host.

## Documentation

- [Operator Guide](docs/operator-guide.md)
- [Migration Guide](docs/migration-guide.md)
- [Launcher Plan](docs/launcher-plan.md)

## Startup Usage

From this directory:

```bat
start.bat
```

Or from PowerShell:

```powershell
.\launcher.ps1
```

Both commands load `launcher.config.local.json`, print the resolved plan, skip disabled services, validate enabled service working directories, start each enabled service in its own PowerShell window, wait for `startupDelaySeconds`, and then run enabled health checks.

Example:

```powershell
.\launcher.ps1
```

## Plan-Only Usage

Use `-PlanOnly` to preview startup without starting any services:

```bat
start.bat -PlanOnly
```

Or from PowerShell:

```powershell
.\launcher.ps1 -PlanOnly
```

`-PlanOnly` only prints the resolved service and health check plan. It does not start services, wait for startup delay, or call health check endpoints.

## Health-Only Usage

Use `-HealthOnly` to run configured health checks without starting services:

```bat
start.bat -HealthOnly
```

Or from PowerShell:

```powershell
.\launcher.ps1 -HealthOnly
```

Each enabled health check supports:

- `name`
- `url`
- `method`, defaulting to `GET`
- `timeoutSeconds`, defaulting to `5`
- `headers`, with values masked in launcher output

Health checks print per-check `PASS`, `FAIL`, or `SKIP` lines and a final `PASS=... FAIL=... SKIP=...` summary. Timeouts and connection failures are reported as `FAIL` without blocking forever.

On first run, if `launcher.config.local.json` does not exist, the script prints setup instructions:

1. Copy `launcher.config.example.json` to `launcher.config.local.json`.
2. Edit `launcher.config.local.json` for local paths.
3. Keep token values, API keys, and secrets out of launcher config.

The config loader supports basic variable substitution for these values:

- `${dispatcherRoot}` resolves to the repository root.
- `${launcherRoot}` resolves to the `launcher/` directory.

Substitution is applied to service `workingDirectory`, service `command`, service `arguments`, health check `url`, and health check header values. The resolved service startup plan prints enabled services with service name, working directory, and command. Disabled services are listed as skipped. Arguments and environment values are not printed to avoid leaking secrets.

The example config includes disabled health checks for Dispatcher Bridge status on `http://127.0.0.1:8787/status` and the MCP HTTP Adapter on `http://127.0.0.1:3000/health`. Keep Dispatcher Bridge bound to localhost; do not expose or tunnel port 8787. If a header token is needed, use a local-only value and never commit the real token.

## MVP Checklist

- [x] Launcher subproject exists under `launcher/`.
- [x] Example config exists without real secrets.
- [x] Local config is ignored by git.
- [x] `-PlanOnly` prints the resolved service and health check plan without startup.
- [x] Normal startup starts explicitly enabled services and runs health checks.
- [x] `-HealthOnly` checks already-running services without starting new windows.
- [x] Operator guide documents setup, verification, startup, shutdown, connector reload, ChatGPT MCP URL, and troubleshooting.
- [x] Migration guide documents config-only migration for local PC, ZTE laptop, VM, and cloud-like host.
- [x] Safety docs warn that Dispatcher Bridge port `8787` must never be exposed or tunneled.
- [x] Migration docs state that only MCP HTTP adapter port `8790` may be tunneled.
- [x] No token values or secrets are committed in launcher documentation.
