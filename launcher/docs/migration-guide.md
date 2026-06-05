# Launcher Migration Guide

This guide describes config-only migration for the JJ AI Dispatcher Launcher across local PCs, laptops, VMs, and cloud-like hosts. It is documentation only; it does not add deployment automation or change launcher runtime behavior.

## Non-Negotiable Safety Rules

- Do not commit `launcher.config.local.json`.
- Do not put secrets, token values, API keys, credentials, or real bearer tokens in launcher config.
- Do not expose Dispatcher Bridge port `8787` externally.
- Do not tunnel Dispatcher Bridge port `8787`.
- Do not instruct ChatGPT, a browser connector, a tunnel, or a remote client to call `8787`.
- If a tunnel is required, only tunnel the MCP HTTP adapter on port `8790`.
- Keep Dispatcher Bridge bound to `127.0.0.1`.
- Treat migration as a config change only unless a separate approved task changes launcher code.

## Config-Only Migration Model

For each host, migrate by creating or updating only:

```text
launcher/launcher.config.local.json
```

Start from the committed example:

```powershell
Copy-Item .\launcher.config.example.json .\launcher.config.local.json
```

Then change host-specific values:

- `environment`
- `description`
- `startupDelaySeconds`
- service `enabled`
- service `workingDirectory`
- service `command`
- service `arguments`
- health check `enabled`
- health check `url`
- health check `headers`, using local placeholders only

After every migration edit, verify with:

```powershell
.\launcher.ps1 -PlanOnly
.\launcher.ps1
.\launcher.ps1 -HealthOnly
```

## Local PC

Use this profile for a normal developer workstation where all services run on the same machine.

Config approach:

- Keep service working directories under the local Dispatcher checkout.
- Keep Dispatcher Bridge health checks on `http://127.0.0.1:8787/status`.
- Keep MCP HTTP adapter access local unless a tunnel is explicitly required.
- Enable only services that are installed and tested on the PC.
- Use `-PlanOnly` before startup after path or port changes.

Safety notes:

- Do not expose `8787` on the LAN.
- Do not tunnel `8787`.
- If ChatGPT needs remote access through a tunnel, tunnel only the MCP HTTP adapter on `8790`.

## ZTE Laptop

Use this profile for a second laptop with a different checkout path, network profile, or local dependency layout.

Config approach:

- Create a fresh `launcher.config.local.json` from the example on the laptop.
- Update `workingDirectory` values for the laptop checkout location.
- Keep commands and arguments machine-specific in local config.
- Keep disabled services disabled until dependencies are installed.
- Use `startupDelaySeconds` appropriate for the laptop's startup speed.

Verification:

```powershell
.\launcher.ps1 -PlanOnly
.\launcher.ps1
.\launcher.ps1 -HealthOnly
```

Safety notes:

- The laptop must keep Dispatcher Bridge local-only.
- Browser connector settings may need reload after the MCP adapter URL changes.
- ChatGPT must use the MCP HTTP adapter URL, not `8787`.
- If tunneling is used from the laptop, tunnel only adapter port `8790`.

## VM

Use this profile for a virtual machine where services run inside the VM and clients may connect from the host or another approved network path.

Config approach:

- Create `launcher.config.local.json` inside the VM.
- Use VM-local paths for service working directories.
- Bind Dispatcher Bridge to `127.0.0.1` inside the VM.
- Configure health checks from the VM perspective first.
- Configure MCP HTTP adapter health checks for the adapter endpoint.
- Use `-HealthOnly` inside the VM before testing external access.

External access rule:

- Only the MCP HTTP adapter on port `8790` may be tunneled or forwarded.
- Dispatcher Bridge `8787` must remain unavailable outside the VM.

Safety notes:

- Do not create a VM firewall rule for `8787`.
- Do not create a port forward for `8787`.
- Do not use `0.0.0.0:8787`.
- If a host browser connector needs access, point it to the approved MCP adapter URL.

## Cloud-Like Host

Use this profile for a remote host that behaves like cloud infrastructure but is not managed by launcher automation.

Config approach:

- Keep migration config-only.
- Create `launcher.config.local.json` on the host from the example.
- Use host-local service paths and commands.
- Keep Dispatcher Bridge on localhost.
- Put public or tunnel-facing access in front of the MCP HTTP adapter only.
- Use port `8790` for the exposed or tunneled MCP HTTP adapter endpoint.
- Keep real tokens and credentials outside committed files.

Verification sequence:

```powershell
.\launcher.ps1 -PlanOnly
.\launcher.ps1
.\launcher.ps1 -HealthOnly
```

Then verify from the approved client side that the MCP HTTP adapter endpoint is reachable. Do not perform any client-side test against Dispatcher Bridge `8787`.

Safety notes:

- No cloud deployment automation is part of this migration.
- No launcher runtime code changes are required for this migration.
- No Dispatcher core, MCP, browser connector, or service startup code changes are required.
- Only adapter port `8790` may be tunneled.
- Raw Dispatcher Bridge `8787` must not be exposed.

## Migration Checklist

Use this checklist for each host:

- `launcher.config.local.json` was created from the example.
- No real token values or secrets were added.
- `.\launcher.ps1 -PlanOnly` prints the expected services and health checks.
- Normal startup opens only the intended enabled services.
- `.\launcher.ps1 -HealthOnly` passes for expected running services.
- Browser connector was reloaded after MCP URL changes.
- ChatGPT MCP URL points at the MCP HTTP adapter.
- Any tunnel targets MCP HTTP adapter port `8790` only.
- No tunnel, firewall rule, connector, or remote client points at Dispatcher Bridge `8787`.
