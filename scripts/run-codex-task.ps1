param(
    [Parameter(Mandatory = $true)]
    [string]$PromptFile,

    [Parameter(Mandatory = $true)]
    [string]$Repo
)

$ErrorActionPreference = "Stop"

$projectRoot = Split-Path $PSScriptRoot -Parent
$configPath = Join-Path $projectRoot "dispatcher\config.json"
$promptPath = Join-Path $projectRoot "prompts\$PromptFile"

if (-not (Test-Path $configPath)) {
    throw "Missing config file: $configPath"
}

if (-not (Test-Path $promptPath)) {
    throw "Prompt file not found: $promptPath"
}

if (-not (Test-Path $Repo)) {
    throw "Repo path not found: $Repo"
}

$config = Get-Content $configPath -Raw | ConvertFrom-Json
$prompt = Get-Content $promptPath -Raw

Write-Host "[codex-worker] Prompt: $PromptFile"
Write-Host "[codex-worker] Repo: $Repo"
Write-Host "[codex-worker] Safety: no auto-push, no destructive actions unless explicitly requested."
Write-Host ""

& $config.codexExe exec --cd $Repo $prompt

exit $LASTEXITCODE
