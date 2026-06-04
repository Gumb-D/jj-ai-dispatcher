[CmdletBinding()]
param(
    [string]$ConfigPath
)

$scriptDirectory = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Path }
if (-not $ConfigPath) {
    $ConfigPath = Join-Path $scriptDirectory "launcher.config.local.json"
}

Write-Host "JJ AI Dispatcher Launcher"
Write-Host "Placeholder only: no services are started by this script yet."
Write-Host ""
Write-Host "Expected future setup:"
Write-Host "  1. Copy launcher.config.example.json to launcher.config.local.json."
Write-Host "  2. Edit the local config for your local, VM, or cloud environment."
Write-Host "  3. Run this launcher after real startup logic is implemented."
Write-Host ""
Write-Host "Config path currently selected: $ConfigPath"
Write-Host ""
Write-Host "Safety boundary: this script does not invoke Codex, modify Dispatcher core, modify MCP, create schedulers, deploy cloud resources, or start services."
