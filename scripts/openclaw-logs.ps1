param(
    [Parameter(Mandatory = $false)]
    [int]$Tail = 200,

    [Parameter(Mandatory = $false)]
    [switch]$Follow
)

$ErrorActionPreference = "Stop"

$config = & (Join-Path $PSScriptRoot "load-config.ps1")

if ($Follow) {
    & $config.openclawExe logs --follow
}
else {
    & $config.openclawExe logs --tail $Tail
}

exit $LASTEXITCODE
