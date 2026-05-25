param(
    [Parameter(Mandatory = $false)]
    [string]$Repo = ""
)

$ErrorActionPreference = "Stop"

if ([string]::IsNullOrWhiteSpace($Repo)) {
    $config = & (Join-Path $PSScriptRoot "load-config.ps1")
    $Repo = $config.defaultRepo
}
else {
    $config = & (Join-Path $PSScriptRoot "load-config.ps1")
}

if (-not (Test-Path $Repo)) {
    throw "Repo path not found: $Repo"
}

Push-Location $Repo
try {
    & $config.gitExe status --short --branch
    & $config.gitExe remote -v
}
finally {
    Pop-Location
}
