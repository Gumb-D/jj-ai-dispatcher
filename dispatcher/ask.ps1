param(
    [Parameter(Mandatory = $false, Position = 0, ValueFromRemainingArguments = $true)]
    [string[]]$InputArgs,

    [Parameter(Mandatory = $false)]
    [string]$Repo,

    [Parameter(Mandatory = $false)]
    [Alias("m")]
    [string]$CommitMessage
)

$ErrorActionPreference = "Stop"

function Show-Usage {
    Write-Host 'Usage: .\dispatcher\ask.ps1 [repo-alias-or-path] "describe the Codex task" [-m "commit message"]'
    Write-Host '       .\dispatcher\ask.ps1 [-repo <alias-or-path>] "describe the Codex task" [-m "commit message"]'
}

function Resolve-RepoTarget {
    param([string]$Value)

    if ([string]::IsNullOrWhiteSpace($Value)) {
        return ""
    }

    if ($Value -eq "self") {
        return Split-Path $PSScriptRoot -Parent
    }

    if (Test-Path -LiteralPath $Value -PathType Container) {
        return (Resolve-Path -LiteralPath $Value).Path
    }

    return ""
}

function Test-LooksLikePath {
    param([string]$Value)

    return $Value -match '^[A-Za-z]:' -or $Value.Contains("\") -or $Value.Contains("/")
}

$promptParts = @($InputArgs)
$repoInput = $Repo

if (-not [string]::IsNullOrWhiteSpace($repoInput)) {
    $resolvedRepo = Resolve-RepoTarget -Value $repoInput
    if ([string]::IsNullOrWhiteSpace($resolvedRepo)) {
        Write-Host "Invalid repo alias or path: $repoInput"
        exit 1
    }
}
elseif ($promptParts.Count -ge 2) {
    $possibleRepo = $promptParts[0]
    $resolvedRepo = Resolve-RepoTarget -Value $possibleRepo
    if (-not [string]::IsNullOrWhiteSpace($resolvedRepo)) {
        $repoInput = $possibleRepo
        $promptParts = @($promptParts | Select-Object -Skip 1)
    }
    elseif (Test-LooksLikePath -Value $possibleRepo) {
        Write-Host "Invalid repo alias or path: $possibleRepo"
        exit 1
    }
}

$Prompt = ($promptParts -join " ").Trim()

if ([string]::IsNullOrWhiteSpace($Prompt)) {
    Show-Usage
    exit 1
}

if ($PSBoundParameters.ContainsKey("CommitMessage") -and [string]::IsNullOrWhiteSpace($CommitMessage)) {
    Write-Host "Commit message cannot be empty."
    exit 1
}

$inboxDir = Join-Path $PSScriptRoot "inbox"
if (-not (Test-Path -LiteralPath $inboxDir -PathType Container)) {
    New-Item -ItemType Directory -Path $inboxDir | Out-Null
}

$repoOverridePath = Join-Path $inboxDir "codex-task.repo.txt"
if (-not [string]::IsNullOrWhiteSpace($repoInput)) {
    Set-Content -LiteralPath $repoOverridePath -Value $resolvedRepo
}

$promptPath = Join-Path $inboxDir "codex-task.txt"
Set-Content -LiteralPath $promptPath -Value $Prompt

$commitMessagePath = Join-Path $inboxDir "codex-task.commit.txt"
if ($PSBoundParameters.ContainsKey("CommitMessage")) {
    Set-Content -LiteralPath $commitMessagePath -Value $CommitMessage.Trim()
}

& (Join-Path $PSScriptRoot "run.ps1") codex_task
exit $LASTEXITCODE
