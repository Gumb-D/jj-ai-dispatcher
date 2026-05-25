param(
    [Parameter(Mandatory = $false, Position = 0)]
    [string]$Prompt
)

$ErrorActionPreference = "Stop"

if ([string]::IsNullOrWhiteSpace($Prompt)) {
    Write-Host 'Usage: .\dispatcher\ask.ps1 "describe the Codex task"'
    exit 1
}

$inboxDir = Join-Path $PSScriptRoot "inbox"
if (-not (Test-Path -LiteralPath $inboxDir -PathType Container)) {
    New-Item -ItemType Directory -Path $inboxDir | Out-Null
}

$promptPath = Join-Path $inboxDir "codex-task.txt"
Set-Content -LiteralPath $promptPath -Value $Prompt

& (Join-Path $PSScriptRoot "run.ps1") codex_task
exit $LASTEXITCODE
