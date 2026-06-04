[CmdletBinding()]
param(
    [string]$ConfigPath
)

$scriptDirectory = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Path }
$dispatcherRoot = Split-Path -Parent $scriptDirectory
if (-not $ConfigPath) {
    $ConfigPath = Join-Path $scriptDirectory "launcher.config.local.json"
}

function Resolve-LauncherValue {
    param(
        [AllowNull()]
        [object]$Value
    )

    if ($null -eq $Value -or $Value -isnot [string]) {
        return $Value
    }

    $resolvedValue = $Value.Replace('${dispatcherRoot}', $dispatcherRoot)
    $resolvedValue = $resolvedValue.Replace('${launcherRoot}', $scriptDirectory)
    return $resolvedValue
}

function Get-ServiceCommandText {
    param(
        [Parameter(Mandatory = $true)]
        [object]$Service
    )

    $command = Resolve-LauncherValue $Service.command
    if ($Service.arguments -is [array] -and $Service.arguments.Count -gt 0) {
        return "$command <arguments omitted>"
    }

    return $command
}

Write-Host "JJ AI Dispatcher Launcher"
Write-Host "Dry-run only: startup is not implemented and no services are started."
Write-Host ""

if (-not (Test-Path -LiteralPath $ConfigPath)) {
    Write-Host "Local launcher config was not found."
    Write-Host ""
    Write-Host "Setup required:"
    Write-Host "  1. Copy launcher.config.example.json to launcher.config.local.json."
    Write-Host "  2. Edit launcher.config.local.json for this machine's local paths."
    Write-Host "  3. Keep tokens, API keys, and secrets out of launcher config."
    Write-Host ""
    Write-Host "Expected path: $ConfigPath"
    Write-Host ""
    Write-Host "Safety boundary: this script does not invoke Codex, modify Dispatcher core, modify MCP, create schedulers, deploy cloud resources, or start services."
    return
}

try {
    $config = Get-Content -LiteralPath $ConfigPath -Raw | ConvertFrom-Json
}
catch {
    Write-Error "Unable to read launcher config '$ConfigPath'. Confirm it is valid JSON. $($_.Exception.Message)"
    exit 1
}

if ($null -eq $config.services) {
    Write-Error "Launcher config '$ConfigPath' must define a services array."
    exit 1
}

$enabledServices = @($config.services | Where-Object { $_.enabled -eq $true })

Write-Host "Config loaded: $ConfigPath"
Write-Host "Variable values:"
Write-Host "  dispatcherRoot: $dispatcherRoot"
Write-Host "  launcherRoot: $scriptDirectory"
Write-Host ""
Write-Host "Resolved service startup plan:"

if ($enabledServices.Count -eq 0) {
    Write-Host "  No enabled services."
}
else {
    foreach ($service in $enabledServices) {
        $serviceName = if ($service.name) { $service.name } else { "<unnamed service>" }
        $workingDirectory = Resolve-LauncherValue $service.workingDirectory
        $command = Get-ServiceCommandText $service

        if ($service.healthCheck -and $service.healthCheck.url) {
            $null = Resolve-LauncherValue $service.healthCheck.url
        }

        Write-Host "  - Service: $serviceName"
        Write-Host "    Working directory: $workingDirectory"
        Write-Host "    Command: $command"
    }
}

Write-Host ""
Write-Host "Safety boundary: this script does not invoke Codex, modify Dispatcher core, modify MCP, create schedulers, deploy cloud resources, or start services."
