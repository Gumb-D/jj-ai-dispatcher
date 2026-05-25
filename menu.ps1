$ErrorActionPreference = "Stop"

$taskMap = @{
    "1" = "env_check"
    "2" = "safe_commit"
    "3" = "secure_scan"
    "4" = "repo_cleanup"
    "5" = "git_status"
}

$dispatcherPath = Join-Path $PSScriptRoot "dispatcher\run.ps1"

while ($true) {
    Write-Host "================================="
    Write-Host "JJ AI Dispatcher"
    Write-Host "================================="
    Write-Host ""
    Write-Host "1. env_check"
    Write-Host "2. safe_commit"
    Write-Host "3. secure_scan"
    Write-Host "4. repo_cleanup"
    Write-Host "5. git_status"
    Write-Host "0. exit"
    Write-Host ""

    Write-Host "Select task: " -NoNewline
    $selection = [Console]::In.ReadLine()
    if ($null -eq $selection) {
        Write-Host ""
        Write-Host "Input closed. Exiting."
        exit 0
    }

    if ($selection -eq "0") {
        Write-Host "Exiting."
        exit 0
    }

    if ([string]::IsNullOrWhiteSpace($selection) -or -not $taskMap.ContainsKey($selection)) {
        Write-Host "Invalid selection: $selection"
        Write-Host ""
        continue
    }

    $task = $taskMap[$selection]
    & pwsh -NoProfile -ExecutionPolicy Bypass -File $dispatcherPath $task
    Write-Host ""
}
