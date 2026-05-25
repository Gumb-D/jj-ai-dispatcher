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

$settings = Get-BridgeSettings
Invoke-RestMethod `
    -Method Get `
    -Uri "$($settings.BaseUri)/status" `
    -Headers (Get-BridgeHeaders -Settings $settings)
