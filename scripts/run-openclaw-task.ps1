param(
    [Parameter(Mandatory = $true)]
    [ValidateSet("restart", "logs", "health")]
    [string]$Action
)

$ErrorActionPreference = "Stop"

$projectRoot = Split-Path $PSScriptRoot -Parent
$configPath = Join-Path $projectRoot "dispatcher\config.json"

if (-not (Test-Path $configPath)) {
    throw "Missing config file: $configPath"
}

$config = Get-Content $configPath -Raw | ConvertFrom-Json
$openclaw = $config.openclawExe

Write-Host "[openclaw-worker] Action: $Action"

switch ($Action) {
    "restart" {
        Write-Host "[openclaw-worker] Restarting OpenClaw gateway/runtime..."
        & $openclaw gateway restart
        exit $LASTEXITCODE
    }

    "logs" {
        Write-Host "[openclaw-worker] Reading OpenClaw logs..."
        & $openclaw logs --tail 200
        exit $LASTEXITCODE
    }

    "health" {
        Write-Host "[openclaw-worker] Running OpenClaw health check..."
        & $openclaw gateway status

        if ($LASTEXITCODE -ne 0) {
            exit $LASTEXITCODE
        }

        & $openclaw status
        exit $LASTEXITCODE
    }
}
