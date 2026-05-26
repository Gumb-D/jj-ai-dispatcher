$ErrorActionPreference = "Stop"

$projectRoot = Split-Path -Parent $PSScriptRoot
Push-Location $projectRoot
try {
    node .\scripts\mcp-smoke.mjs
    exit $LASTEXITCODE
}
finally {
    Pop-Location
}
