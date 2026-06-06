param()

$ErrorActionPreference = "Stop"

$scriptRoot = $PSScriptRoot
$checks = @(
    @{
        Name = "delivery-state"
        Path = Join-Path $scriptRoot "test-delivery-state.ps1"
    },
    @{
        Name = "result-retrieval"
        Path = Join-Path $scriptRoot "test-result-retrieval.ps1"
    },
    @{
        Name = "dispatcher-lifecycle"
        Path = Join-Path $scriptRoot "test-dispatcher-lifecycle.ps1"
    }
)

foreach ($check in $checks) {
    Write-Host "== integration: $($check.Name) =="
    & pwsh -NoProfile -ExecutionPolicy Bypass -File $check.Path
    if ($LASTEXITCODE -ne 0) {
        throw "Integration check failed: $($check.Name) exited with $LASTEXITCODE."
    }
}

Write-Host "PASS integration checks"
