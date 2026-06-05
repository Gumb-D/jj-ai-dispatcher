# Launcher Operator Guide

This guide covers day-to-day operation for the JJ AI Dispatcher Launcher. The launcher is config-driven and local-first. It does not change Dispatcher core, MCP runtime behavior, browser connector behavior, service installation, or cloud deployment.

## First-Time Setup

Run all commands from the `launcher/` directory unless noted otherwise.

1. Confirm PowerShell is available.
2. Confirm the Dispatcher repository exists on the machine.
3. Create a local config from the committed example:

```powershell
Copy-Item .\launcher.config.example.json .\launcher.config.local.json
```

4. Edit `launcher.config.local.json` for the current machine:

- Set only local paths, hostnames, ports, enabled flags, and health check settings.
- Keep `dispatcher-bridge` bound to `127.0.0.1`.
- Keep secrets, token values, API keys, and credentials out of the file.
- Leave services disabled until their commands and working directories are verified.

`launcher.config.local.json` is intentionally ignored by git. Do not commit it.

## PlanOnly Verification

Use `-PlanOnly` before normal startup whenever config changes:

```powershell
.\launcher.ps1 -PlanOnly
```

Or:

```bat
start.bat -PlanOnly
```

Expected result:

- The launcher loads `launcher.config.local.json`.
- Enabled and disabled services are printed.
- Enabled service working directories and commands are shown.
- Health checks are listed.
- No service windows are started.
- No health check endpoints are called.

If the plan shows the wrong path, command, host, port, or enabled state, fix `launcher.config.local.json` before continuing.

## Normal Startup

After `-PlanOnly` looks correct, start the enabled services:

```powershell
.\launcher.ps1
```

Or:

```bat
start.bat
```

Expected result:

- The launcher prints the resolved startup plan.
- Disabled services are skipped.
- Enabled service working directories are validated.
- Enabled services are started in separate PowerShell windows.
- The launcher waits for `startupDelaySeconds`.
- Enabled health checks run after startup.

Leave the service windows open while the Dispatcher workflow is in use.

## HealthOnly Verification

Use `-HealthOnly` to check already-running services without opening new service windows:

```powershell
.\launcher.ps1 -HealthOnly
```

Or:

```bat
start.bat -HealthOnly
```

Expected result:

- The launcher loads the local config.
- No services are started.
- Enabled health checks run.
- Results are printed as `PASS`, `FAIL`, or `SKIP`.
- A final summary prints the count for each result type.

Run this after startup and after any connector or MCP URL change.

## Browser Connector Reload Reminder

After changing launcher config, MCP adapter URL, connector settings, or browser-side integration settings, reload the browser connector before testing ChatGPT integration again.

Use the browser connector UI or extension reload flow available on the machine. Then rerun:

```powershell
.\launcher.ps1 -HealthOnly
```

## ChatGPT MCP URL Reminder

ChatGPT must point at the MCP HTTP adapter URL, not the raw Dispatcher Bridge URL.

Use the local or approved tunnel URL for the MCP HTTP adapter only. For migration scenarios, the only adapter port that may be tunneled is `8790`.

Never configure ChatGPT to use raw Dispatcher Bridge port `8787`, and never expose or tunnel `8787`.

## Shutdown Order

Use this order when stopping a launcher-started session:

1. Stop ChatGPT or browser-side activity that is sending MCP requests.
2. Reload or disconnect the browser connector if it was pointed at the adapter.
3. Stop the MCP HTTP adapter service window.
4. Stop the Dispatcher Bridge service window.
5. Run `.\launcher.ps1 -HealthOnly` if you need to confirm services no longer respond.

Stopping the adapter before the bridge prevents new external MCP traffic from reaching the local bridge during shutdown.

## Troubleshooting

### Missing Local Config

Symptom: the launcher prints setup instructions and exits.

Fix:

```powershell
Copy-Item .\launcher.config.example.json .\launcher.config.local.json
```

Then edit local paths and enabled flags.

### Wrong Working Directory

Symptom: `-PlanOnly` or normal startup reports a missing working directory.

Fix: update the service `workingDirectory` in `launcher.config.local.json`. Prefer `${dispatcherRoot}` and `${launcherRoot}` where possible.

### Service Window Opens Then Closes

Symptom: a service starts in a new PowerShell window and exits quickly.

Fix:

- Run `.\launcher.ps1 -PlanOnly` and inspect the resolved command.
- Confirm the service command works manually from the printed working directory.
- Confirm required local dependencies are installed.
- Confirm the service is enabled only after its command is valid.

### Health Check Fails

Symptom: `-HealthOnly` or post-startup checks show `FAIL`.

Fix:

- Confirm the service window is still open.
- Confirm the configured health check URL matches the service host and port.
- Confirm the service had enough time to start; increase `startupDelaySeconds` only if needed.
- Confirm any required local-only header placeholder was replaced locally without committing a real token.

### Browser Connector Cannot Reach MCP

Symptom: ChatGPT or the browser connector cannot call the tools even though services are running.

Fix:

- Confirm ChatGPT uses the MCP HTTP adapter URL.
- Reload the browser connector after URL or config changes.
- Run `.\launcher.ps1 -HealthOnly`.
- Confirm the adapter is reachable on the configured adapter port.
- Do not point the connector at Dispatcher Bridge `8787`.

### Port Conflict

Symptom: a service fails to bind its configured port.

Fix:

- Stop the older process using the port, or change the local config to an available port.
- Keep Dispatcher Bridge local-only on `127.0.0.1:8787`.
- For any tunneled MCP adapter scenario, use adapter port `8790` only.

### Safety Violation

Symptom: a config, tunnel, or connector points to Dispatcher Bridge `8787` from outside the host.

Fix immediately:

1. Stop external traffic.
2. Remove the tunnel or external binding.
3. Restore Dispatcher Bridge to localhost-only access.
4. Point external MCP clients only at the MCP HTTP adapter on approved port `8790`.
