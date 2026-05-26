$ErrorActionPreference = "Stop"

$projectRoot = Split-Path -Parent $PSScriptRoot
Push-Location $projectRoot
try {
    node .\scripts\review-latest-run.mjs
    exit $LASTEXITCODE
}
finally {
    Pop-Location
}
