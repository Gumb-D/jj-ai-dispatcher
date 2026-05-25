param(
    [Parameter(Mandatory = $false)]
    [int]$PollSeconds = 2,

    [Parameter(Mandatory = $false)]
    [int]$TimeoutSeconds = 600
)

$ErrorActionPreference = "Stop"

function Get-BridgeSettings {
    $projectRoot = Split-Path $PSScriptRoot -Parent
    $configLoaderPath = Join-Path $projectRoot "scripts\load-config.ps1"

    if (-not (Test-Path -LiteralPath $configLoaderPath -PathType Leaf)) {
        throw "Missing config loader: $configLoaderPath"
    }

    $config = & $configLoaderPath
    $bridge = $config.bridge

    if ($null -eq $bridge) {
        throw "Missing bridge configuration."
    }

    if ($bridge.requireToken -and [string]::IsNullOrWhiteSpace([string]$bridge.token)) {
        throw "Bridge token is required but not configured in dispatcher/config.local.json."
    }

    return [pscustomobject]@{
        BaseUri = "http://$($bridge.host):$($bridge.port)"
        RequireToken = [bool]$bridge.requireToken
        Token = [string]$bridge.token
    }
}

function Get-BridgeHeaders {
    param([pscustomobject]$Settings)

    if (-not $Settings.RequireToken) {
        return @{}
    }

    return @{ "X-Dispatcher-Token" = $Settings.Token }
}

if ($PollSeconds -lt 1) {
    throw "PollSeconds must be at least 1."
}

if ($TimeoutSeconds -lt $PollSeconds) {
    throw "TimeoutSeconds must be greater than or equal to PollSeconds."
}

$settings = Get-BridgeSettings
$headers = Get-BridgeHeaders -Settings $settings
$deadline = (Get-Date).AddSeconds($TimeoutSeconds)

do {
    $status = Invoke-RestMethod `
        -Method Get `
        -Uri "$($settings.BaseUri)/status" `
        -Headers $headers

    Write-Host "taskState: $($status.taskState)"

    if ($status.taskState -eq "idle") {
        break
    }

    if ((Get-Date) -ge $deadline) {
        throw "Timed out waiting for bridge taskState to become idle."
    }

    Start-Sleep -Seconds $PollSeconds
} while ($true)

Invoke-RestMethod `
    -Method Get `
    -Uri "$($settings.BaseUri)/runs/latest" `
    -Headers $headers
