param(
    [Parameter(Mandatory = $false, Position = 0)]
    [string]$Prompt,

    [Parameter(Mandatory = $false)]
    [string]$Repo
)

$ErrorActionPreference = "Stop"

if ([string]::IsNullOrWhiteSpace($Prompt)) {
    Write-Host 'Usage: .\dispatcher\ask.ps1 [-repo <alias-or-path>] "describe the Codex task"'
    exit 1
}

$inboxDir = Join-Path $PSScriptRoot "inbox"
if (-not (Test-Path -LiteralPath $inboxDir -PathType Container)) {
    New-Item -ItemType Directory -Path $inboxDir | Out-Null
}

$repoOverridePath = Join-Path $inboxDir "codex-task.repo.txt"
if (-not [string]::IsNullOrWhiteSpace($Repo)) {
    if ($Repo -eq "self") {
        $resolvedRepo = Split-Path $PSScriptRoot -Parent
    }
    elseif (Test-Path -LiteralPath $Repo -PathType Container) {
        $resolvedRepo = (Resolve-Path -LiteralPath $Repo).Path
    }
    else {
        Write-Host "Invalid repo alias or path: $Repo"
        exit 1
    }

    Set-Content -LiteralPath $repoOverridePath -Value $resolvedRepo
}

$promptPath = Join-Path $inboxDir "codex-task.txt"
Set-Content -LiteralPath $promptPath -Value $Prompt

& (Join-Path $PSScriptRoot "run.ps1") codex_task
exit $LASTEXITCODE
