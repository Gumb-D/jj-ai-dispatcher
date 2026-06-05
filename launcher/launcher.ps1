[CmdletBinding()]
param(
    [string]$ConfigPath,
    [switch]$PlanOnly,
    [switch]$HealthOnly
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

function ConvertTo-HeaderHashtable {
    param(
        [AllowNull()]
        [object]$Headers
    )

    $resolvedHeaders = @{}
    if ($null -eq $Headers) {
        return $resolvedHeaders
    }

    foreach ($property in $Headers.PSObject.Properties) {
        $resolvedHeaders[[string]$property.Name] = [string](Resolve-LauncherValue $property.Value)
    }

    return $resolvedHeaders
}

function Get-MaskedHeaderText {
    param(
        [hashtable]$Headers
    )

    if ($null -eq $Headers -or $Headers.Count -eq 0) {
        return "none"
    }

    $maskedHeaders = @()
    foreach ($headerName in ($Headers.Keys | Sort-Object)) {
        $maskedHeaders += "$headerName=***"
    }

    return ($maskedHeaders -join ", ")
}

function Get-HealthChecksFromConfig {
    param(
        [Parameter(Mandatory = $true)]
        [object]$Config
    )

    $checks = @()
    if ($Config.healthChecks -is [array]) {
        $checks += @($Config.healthChecks)
    }
    elseif ($null -ne $Config.healthChecks) {
        $checks += $Config.healthChecks
    }

    foreach ($service in @($Config.services)) {
        if ($service.healthCheck -and $service.healthCheck.url) {
            $serviceCheck = $service.healthCheck | Select-Object *
            if (-not $serviceCheck.name) {
                $serviceCheck | Add-Member -NotePropertyName "name" -NotePropertyValue "$($service.name) health" -Force
            }
            if ($null -eq $serviceCheck.enabled) {
                $serviceCheck | Add-Member -NotePropertyName "enabled" -NotePropertyValue ($service.enabled -eq $true) -Force
            }
            $checks += $serviceCheck
        }
    }

    return @($checks)
}

function Invoke-LauncherHealthChecks {
    param(
        [Parameter(Mandatory = $true)]
        [array]$HealthChecks
    )

    $results = @()
    if ($HealthChecks.Count -eq 0) {
        Write-Host "Health checks:"
        Write-Host "  SKIP: no health checks configured."
        $results += [pscustomobject]@{ Status = "SKIP"; Name = "no health checks configured"; Detail = "" }
        return $results
    }

    Write-Host "Health checks:"
    foreach ($healthCheck in $HealthChecks) {
        $name = if ($healthCheck.name) { [string]$healthCheck.name } else { "<unnamed health check>" }
        $enabled = $healthCheck.enabled -eq $true
        $url = Resolve-LauncherValue $healthCheck.url
        $method = if ($healthCheck.method) { [string]$healthCheck.method } else { "GET" }
        $timeoutProperty = $healthCheck.PSObject.Properties["timeoutSeconds"]
        $timeoutSeconds = if ($null -ne $timeoutProperty) { [int]$timeoutProperty.Value } else { 5 }
        $headers = ConvertTo-HeaderHashtable $healthCheck.headers

        if (-not $enabled) {
            Write-Host "  SKIP: $name - disabled"
            $results += [pscustomobject]@{ Status = "SKIP"; Name = $name; Detail = "disabled" }
            continue
        }

        if (-not $url) {
            Write-Host "  SKIP: $name - missing url"
            $results += [pscustomobject]@{ Status = "SKIP"; Name = $name; Detail = "missing url" }
            continue
        }

        if ($timeoutSeconds -lt 1) {
            $timeoutSeconds = 1
        }

        Write-Host "  Checking: $name"
        Write-Host "    URL: $url"
        Write-Host "    Method: $method"
        Write-Host "    Timeout: $timeoutSeconds second(s)"
        Write-Host "    Headers: $(Get-MaskedHeaderText $headers)"

        try {
            $response = Invoke-WebRequest -Uri $url -Method $method -Headers $headers -TimeoutSec $timeoutSeconds -UseBasicParsing
            $statusCode = [int]$response.StatusCode
            if ($statusCode -ge 200 -and $statusCode -lt 400) {
                Write-Host "  PASS: $name - HTTP $statusCode"
                $results += [pscustomobject]@{ Status = "PASS"; Name = $name; Detail = "HTTP $statusCode" }
            }
            else {
                Write-Host "  FAIL: $name - HTTP $statusCode"
                $results += [pscustomobject]@{ Status = "FAIL"; Name = $name; Detail = "HTTP $statusCode" }
            }
        }
        catch {
            $failureMessage = $_.Exception.Message
            Write-Host "  FAIL: $name - $failureMessage"
            $results += [pscustomobject]@{ Status = "FAIL"; Name = $name; Detail = $failureMessage }
        }
    }

    return $results
}

Write-Host "JJ AI Dispatcher Launcher"
if ($PlanOnly) {
    Write-Host "Plan-only mode: no services will be started."
}
if ($HealthOnly) {
    Write-Host "Health-only mode: no services will be started."
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
    Write-Host "Safety boundary: this script does not invoke Codex, modify Dispatcher core, modify MCP, create schedulers, deploy cloud resources, expose Dispatcher Bridge port 8787 externally, or log secret header values."
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
$startupDelayProperty = $config.PSObject.Properties["startupDelaySeconds"]
$startupDelaySeconds = if ($null -ne $startupDelayProperty) { [int]$startupDelayProperty.Value } else { 3 }
if ($startupDelaySeconds -lt 0) {
    $startupDelaySeconds = 0
}
$healthChecks = Get-HealthChecksFromConfig $config

foreach ($service in @($config.services)) {
    $serviceName = if ($service.name) { $service.name } else { "<unnamed service>" }
    $enabled = $service.enabled -eq $true
    $workingDirectory = Resolve-LauncherValue $service.workingDirectory
    $command = Resolve-LauncherValue $service.command
    $commandText = Get-ServiceCommandText $service
    $arguments = Get-ServiceArguments $service

    if ($enabled -and (-not $HealthOnly) -and (-not $workingDirectory -or -not (Test-Path -LiteralPath $workingDirectory -PathType Container))) {
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
Write-Host "  startupDelaySeconds: $startupDelaySeconds"
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

Write-Host ""
Write-Host "Configured health checks:"
if ($healthChecks.Count -eq 0) {
    Write-Host "  No health checks configured."
}
else {
    foreach ($healthCheck in $healthChecks) {
        $healthName = if ($healthCheck.name) { [string]$healthCheck.name } else { "<unnamed health check>" }
        $healthEnabled = $healthCheck.enabled -eq $true
        $healthUrl = Resolve-LauncherValue $healthCheck.url
        $healthMethod = if ($healthCheck.method) { [string]$healthCheck.method } else { "GET" }
        $healthTimeoutProperty = $healthCheck.PSObject.Properties["timeoutSeconds"]
        $healthTimeout = if ($null -ne $healthTimeoutProperty) { [int]$healthTimeoutProperty.Value } else { 5 }
        $healthHeaders = ConvertTo-HeaderHashtable $healthCheck.headers
        Write-Host "  - Health check: $healthName"
        Write-Host "    Enabled: $healthEnabled"
        Write-Host "    URL: $healthUrl"
        Write-Host "    Method: $healthMethod"
        Write-Host "    Timeout: $healthTimeout second(s)"
        Write-Host "    Headers: $(Get-MaskedHeaderText $healthHeaders)"
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
elseif ($HealthOnly) {
    $healthResults = Invoke-LauncherHealthChecks $healthChecks
}
elseif ($enabledServices.Count -eq 0) {
    Write-Host "No enabled services to start."
    $healthResults = Invoke-LauncherHealthChecks $healthChecks
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

    if ($startupDelaySeconds -gt 0) {
        Write-Host ""
        Write-Host "Waiting $startupDelaySeconds second(s) before health checks..."
        Start-Sleep -Seconds $startupDelaySeconds
    }

    $healthResults = Invoke-LauncherHealthChecks $healthChecks
}

Write-Host ""
if ($null -ne $healthResults) {
    $passCount = @($healthResults | Where-Object { $_.Status -eq "PASS" }).Count
    $failCount = @($healthResults | Where-Object { $_.Status -eq "FAIL" }).Count
    $skipCount = @($healthResults | Where-Object { $_.Status -eq "SKIP" }).Count
    Write-Host "Health check summary: PASS=$passCount FAIL=$failCount SKIP=$skipCount"
}
Write-Host "Safety boundary: this script does not invoke Codex, modify Dispatcher core, modify MCP, create schedulers, deploy cloud resources, expose Dispatcher Bridge port 8787 externally, or log secret header values."
