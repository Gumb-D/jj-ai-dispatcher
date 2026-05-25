$ErrorActionPreference = "Stop"

$projectRoot = Split-Path $PSScriptRoot -Parent
$requiredScripts = @(
    "scripts/load-config.ps1",
    "scripts/run-codex-task.ps1",
    "scripts/run-openclaw-task.ps1",
    "scripts/git-status.ps1",
    "scripts/openclaw-logs.ps1"
)

$checks = New-Object System.Collections.Generic.List[object]

function Add-Check {
    param(
        [string]$Name,
        [bool]$Passed,
        [bool]$Mandatory = $true,
        [string]$Detail = ""
    )

    $checks.Add([pscustomobject]@{
        Name = $Name
        Passed = $Passed
        Mandatory = $Mandatory
        Detail = $Detail
    })
}

function Test-Executable {
    param([string]$Value)

    if ([string]::IsNullOrWhiteSpace($Value)) {
        return $false
    }

    if (Test-Path -LiteralPath $Value -PathType Leaf) {
        return $true
    }

    return [bool](Get-Command $Value -ErrorAction SilentlyContinue)
}

function Test-LocalConfigProperty {
    param([string]$Name)

    $localConfigPath = Join-Path $projectRoot "dispatcher\config.local.json"
    if (-not (Test-Path -LiteralPath $localConfigPath -PathType Leaf)) {
        return $false
    }

    $localConfig = Get-Content $localConfigPath -Raw | ConvertFrom-Json
    return $localConfig.PSObject.Properties.Name.Contains($Name)
}

$config = $null
$configLoaded = $false
$configLoaderPath = Join-Path $PSScriptRoot "load-config.ps1"

try {
    $config = & $configLoaderPath
    $configLoaded = $true
    Add-Check -Name "config loads through scripts/load-config.ps1" -Passed $true
}
catch {
    Add-Check -Name "config loads through scripts/load-config.ps1" -Passed $false -Detail $_.Exception.Message
}

$defaultRepoExists = $false
if ($configLoaded) {
    $defaultRepoExists = -not [string]::IsNullOrWhiteSpace($config.defaultRepo) -and (Test-Path -LiteralPath $config.defaultRepo -PathType Container)
}
Add-Check -Name "defaultRepo exists" -Passed $defaultRepoExists

$defaultRepoIsGitRepo = $false
if ($defaultRepoExists) {
    $gitDir = Join-Path $config.defaultRepo ".git"
    $defaultRepoIsGitRepo = Test-Path -LiteralPath $gitDir
}
Add-Check -Name "defaultRepo is a git repo" -Passed $defaultRepoIsGitRepo

$gitAvailable = $false
if ($configLoaded) {
    $gitAvailable = Test-Executable -Value $config.gitExe
}
Add-Check -Name "git command is available" -Passed $gitAvailable

$codexAvailable = $false
if ($configLoaded) {
    $codexAvailable = Test-Executable -Value $config.codexExe
}
Add-Check -Name "codexExe exists or codex command is resolvable" -Passed $codexAvailable

$openclawConfigured = $configLoaded -and -not [string]::IsNullOrWhiteSpace($config.openclawExe)
if ($openclawConfigured) {
    $openclawExplicitlyConfigured = Test-LocalConfigProperty -Name "openclawExe"
    Add-Check -Name "openclawExe exists or openclaw command is resolvable, if configured" -Passed (Test-Executable -Value $config.openclawExe) -Mandatory $openclawExplicitlyConfigured
}
else {
    Add-Check -Name "openclawExe exists or openclaw command is resolvable, if configured" -Passed $true -Detail "not configured"
}

foreach ($script in $requiredScripts) {
    $scriptPath = Join-Path $projectRoot $script
    Add-Check -Name "required script exists: $script" -Passed (Test-Path -LiteralPath $scriptPath -PathType Leaf)
}

$failed = $false
foreach ($check in $checks) {
    $status = if ($check.Passed) { "PASS" } else { "FAIL" }
    if ($check.Mandatory -and -not $check.Passed) {
        $failed = $true
    }

    if ([string]::IsNullOrWhiteSpace($check.Detail)) {
        Write-Host "$status $($check.Name)"
    }
    else {
        Write-Host "$status $($check.Name) ($($check.Detail))"
    }
}

Write-Host ""
if ($failed) {
    Write-Host "ENV CHECK FAIL"
    exit 1
}

Write-Host "ENV CHECK PASS"
exit 0
