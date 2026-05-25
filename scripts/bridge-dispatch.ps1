param(
    [Parameter(Mandatory = $false)]
    [string]$Repo = "self",

    [Parameter(Mandatory = $false)]
    [string]$Worker = "codex",

    [Parameter(Mandatory = $true)]
    [string]$Task,

    [Parameter(Mandatory = $false)]
    [string]$CommitMessage = ""
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

$payload = [ordered]@{
    repo = $Repo
    worker = $Worker
    task = $Task
}

if (-not [string]::IsNullOrWhiteSpace($CommitMessage)) {
    $payload["commitMessage"] = $CommitMessage
}

$settings = Get-BridgeSettings
$body = $payload | ConvertTo-Json -Depth 4

Invoke-RestMethod `
    -Method Post `
    -Uri "$($settings.BaseUri)/dispatch" `
    -ContentType "application/json" `
    -Headers (Get-BridgeHeaders -Settings $settings) `
    -Body $body
