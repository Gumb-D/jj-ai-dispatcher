param(
    [Parameter(Mandatory = $false)]
    [int]$Tail = 200,

    [Parameter(Mandatory = $false)]
    [switch]$Follow
)

$ErrorActionPreference = "Stop"

$projectRoot = Split-Path $PSScriptRoot -Parent
$config = Get-Content (Join-Path $projectRoot "dispatcher\config.json") -Raw | ConvertFrom-Json

if ($Follow) {
    & $config.openclawExe logs --follow
}
else {
    & $config.openclawExe logs --tail $Tail
}

exit $LASTEXITCODE
