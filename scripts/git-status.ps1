param(
    [Parameter(Mandatory = $false)]
    [string]$Repo = ""
)

$ErrorActionPreference = "Stop"

if ([string]::IsNullOrWhiteSpace($Repo)) {
    $projectRoot = Split-Path $PSScriptRoot -Parent
    $config = Get-Content (Join-Path $projectRoot "dispatcher\config.json") -Raw | ConvertFrom-Json
    $Repo = $config.defaultRepo
}

if (-not (Test-Path $Repo)) {
    throw "Repo path not found: $Repo"
}

Push-Location $Repo
try {
    git status --short --branch
    git remote -v
}
finally {
    Pop-Location
}
