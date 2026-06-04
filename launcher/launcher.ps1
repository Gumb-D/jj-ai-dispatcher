[CmdletBinding()]
param(
    [string]$ConfigPath,
    [switch]$PlanOnly
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

function ConvertTo-PowerShellLiteral {
    param(
        [AllowNull()]
        [object]$Value
    )

    if ($null -eq $Value) {
        return "''"
    }

    $text = [string]$Value
    return "'" + $text.Replace("'", "''") + "'"
}

function Get-ServiceArguments {
    param(
        [Parameter(Mandatory = $true)]
        [object]$Service
    )

    if ($Service.arguments -isnot [array]) {
        return @()
    }

    return @($Service.arguments | ForEach-Object { Resolve-LauncherValue $_ })
}

Write-Host "JJ AI Dispatcher Launcher"
if ($PlanOnly) {
    Write-Host "Plan-only mode: no services will be started."
}
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
    Write-Host "Safety boundary: this script does not invoke Codex, modify Dispatcher core, modify MCP, create schedulers, deploy cloud resources, or implement health checks."
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

$servicePlans = @()
$validationErrors = @()

foreach ($service in @($config.services)) {
    $serviceName = if ($service.name) { $service.name } else { "<unnamed service>" }
    $enabled = $service.enabled -eq $true
    $workingDirectory = Resolve-LauncherValue $service.workingDirectory
    $command = Resolve-LauncherValue $service.command
    $commandText = Get-ServiceCommandText $service
    $arguments = Get-ServiceArguments $service

    if ($service.healthCheck -and $service.healthCheck.url) {
        $null = Resolve-LauncherValue $service.healthCheck.url
    }

    if ($enabled -and (-not $workingDirectory -or -not (Test-Path -LiteralPath $workingDirectory -PathType Container))) {
        $validationErrors += "Service '$serviceName' has a missing workingDirectory: $workingDirectory"
    }

    $servicePlans += [pscustomobject]@{
        Name = $serviceName
        Enabled = $enabled
        WorkingDirectory = $workingDirectory
        Command = $command
        CommandText = $commandText
        Arguments = $arguments
    }
}

$enabledServices = @($servicePlans | Where-Object { $_.Enabled })
$disabledServices = @($servicePlans | Where-Object { -not $_.Enabled })

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
        Write-Host "  - Service: $($service.Name)"
        Write-Host "    Working directory: $($service.WorkingDirectory)"
        Write-Host "    Command: $($service.CommandText)"
    }
}

if ($disabledServices.Count -gt 0) {
    Write-Host ""
    Write-Host "Skipped disabled services:"
    foreach ($service in $disabledServices) {
        Write-Host "  - $($service.Name)"
    }
}

if ($validationErrors.Count -gt 0) {
    Write-Host ""
    Write-Error "Launcher config validation failed. Fix the enabled service workingDirectory values before startup."
    foreach ($validationError in $validationErrors) {
        Write-Error "  $validationError"
    }
    exit 1
}

Write-Host ""
if ($PlanOnly) {
    Write-Host "Plan-only mode complete. No services were started."
}
elseif ($enabledServices.Count -eq 0) {
    Write-Host "No enabled services to start."
}
else {
    Write-Host "Starting enabled services in separate PowerShell windows..."
    foreach ($service in $enabledServices) {
        Write-Host "  Starting: $($service.Name)"

        $commandParts = @(
            "Set-Location -LiteralPath $(ConvertTo-PowerShellLiteral $service.WorkingDirectory);"
            "& $(ConvertTo-PowerShellLiteral $service.Command)"
        )

        foreach ($argument in $service.Arguments) {
            $commandParts += (ConvertTo-PowerShellLiteral $argument)
        }

        $commandLine = $commandParts -join " "
        Start-Process -FilePath "powershell.exe" -WorkingDirectory $service.WorkingDirectory -ArgumentList @(
            "-NoExit",
            "-NoProfile",
            "-ExecutionPolicy",
            "Bypass",
            "-Command",
            $commandLine
        )
    }
}

Write-Host ""
Write-Host "Safety boundary: this script does not invoke Codex, modify Dispatcher core, modify MCP, create schedulers, deploy cloud resources, or implement health checks."
