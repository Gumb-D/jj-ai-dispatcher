param(
    [int]$TimeoutSeconds = 3
)

$ErrorActionPreference = "Stop"

$projectRoot = Split-Path $PSScriptRoot -Parent
$sourceDispatcherRoot = Join-Path $projectRoot "dispatcher"
$sourceScriptsRoot = Join-Path $projectRoot "scripts"
$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("jj-dispatcher-lifecycle-" + [guid]::NewGuid().ToString("N"))
$dispatcherRoot = Join-Path $tempRoot "dispatcher"
$tempScriptsRoot = Join-Path $tempRoot "scripts"
$inboxRoot = Join-Path $dispatcherRoot "inbox"
$runScript = Join-Path $dispatcherRoot "run.ps1"

$inboxFiles = @(
    "codex-task.txt",
    "codex-task.repo.txt",
    "codex-task.commit.txt",
    "codex-task.push.txt"
)

$backups = @{}

function Backup-Inbox {
    foreach ($name in $inboxFiles) {
        $path = Join-Path $inboxRoot $name
        if (Test-Path -LiteralPath $path -PathType Leaf) {
            $backups[$name] = Get-Content -LiteralPath $path -Raw
        }
    }
}

function Restore-Inbox {
    foreach ($name in $inboxFiles) {
        $path = Join-Path $inboxRoot $name
        if ($backups.ContainsKey($name)) {
            Set-Content -LiteralPath $path -Value $backups[$name] -Encoding UTF8 -NoNewline
        }
        else {
            Remove-Item -LiteralPath $path -ErrorAction SilentlyContinue
        }
    }
}

function New-TestRepo {
    param([string]$Name)

    $repo = Join-Path $tempRoot $Name
    New-Item -ItemType Directory -Path $repo -Force | Out-Null
    & git -C $repo init | Out-Null
    & git -C $repo config user.email "dispatcher-test@example.invalid" | Out-Null
    & git -C $repo config user.name "Dispatcher Test" | Out-Null
    Set-Content -LiteralPath (Join-Path $repo "baseline.txt") -Value "baseline" -Encoding UTF8
    & git -C $repo add baseline.txt | Out-Null
    & git -C $repo commit -m "test baseline" | Out-Null
    return $repo
}

function Write-TestWorker {
    $workerPath = Join-Path $tempRoot "test-worker.ps1"
    @'
param(
    [string]$Repo,
    [string]$Prompt
)

$mode = [Environment]::GetEnvironmentVariable("JJ_DISPATCHER_TEST_WORKER_MODE")
Write-Output "worker stdout mode=$mode"
[Console]::Error.WriteLine("worker stderr mode=$mode")

switch ($mode) {
    "success" {
        Set-Content -LiteralPath (Join-Path $Repo "worker-success.txt") -Value $Prompt -Encoding UTF8
        exit 0
    }
    "failure" {
        Set-Content -LiteralPath (Join-Path $Repo "worker-failure.txt") -Value "failed" -Encoding UTF8
        exit 7
    }
    "hang" {
        Set-Content -LiteralPath (Join-Path $Repo "worker-hang.txt") -Value "partial" -Encoding UTF8
        Start-Sleep -Seconds 60
        exit 0
    }
    "child-hang" {
        Set-Content -LiteralPath (Join-Path $Repo "worker-child-hang.txt") -Value "partial" -Encoding UTF8
        $child = Start-Process -FilePath "pwsh" -ArgumentList @("-NoProfile", "-Command", "Start-Sleep -Seconds 60") -PassThru
        Write-Output "spawned child pid=$($child.Id)"
        Start-Sleep -Seconds 60
        exit 0
    }
    "noop" {
        Write-Output "no repository changes"
        exit 0
    }
    default {
        Write-Error "unknown mode $mode" -ErrorAction Continue
        exit 9
    }
}
'@ | Set-Content -LiteralPath $workerPath -Encoding UTF8
    return $workerPath
}

function Write-FakeGit {
    param(
        [switch]$FailCommit,
        [switch]$TrackPush
    )

    $fakeGitName = if ($FailCommit) { "fake-git-fail-commit.cmd" } elseif ($TrackPush) { "fake-git-track-push.cmd" } else { "fake-git.cmd" }
    $fakeGit = Join-Path $tempRoot $fakeGitName
    $pushMarker = (Join-Path $tempRoot "fake-git-push.marker").Replace("\", "\\")
    $content = if ($FailCommit) {
@'
@echo off
if /i "%~1"=="status" (
  echo  M worker-success.txt
  exit /b 0
)
if /i "%~1"=="add" (
  exit /b 0
)
if /i "%~1"=="diff" (
  echo fake diff
  exit /b 0
)
if /i "%~1"=="commit" (
  echo forced git commit failure 1>&2
  exit /b 43
)
git %*
'@
    }
    elseif ($TrackPush) {
@"
@echo off
if /i "%~1"=="push" (
  echo pushed > "$pushMarker"
  echo fake push
  exit /b 0
)
git %*
"@
    }
    else {
@'
@echo off
git %*
'@
    }

    $content | Set-Content -LiteralPath $fakeGit -Encoding ASCII
    return $fakeGit
}

function Get-LatestRun {
    Get-ChildItem -LiteralPath (Join-Path $dispatcherRoot "runs") -Directory |
        Sort-Object Name -Descending |
        Select-Object -First 1
}

function Invoke-LifecycleCase {
    param(
        [string]$Name,
        [string]$Mode,
        [string]$WorkerPath,
        [string]$GitExe = "",
        [string]$PushControl = "",
        [switch]$AllowAutoPush
    )

    $repo = New-TestRepo -Name $Name
    Set-Content -LiteralPath (Join-Path $inboxRoot "codex-task.txt") -Value "Lifecycle test $Name" -Encoding UTF8
    Set-Content -LiteralPath (Join-Path $inboxRoot "codex-task.repo.txt") -Value $repo -Encoding UTF8
    Set-Content -LiteralPath (Join-Path $inboxRoot "codex-task.commit.txt") -Value "test: lifecycle $Name" -Encoding UTF8
    if ([string]::IsNullOrWhiteSpace($PushControl)) {
        Remove-Item -LiteralPath (Join-Path $inboxRoot "codex-task.push.txt") -ErrorAction SilentlyContinue
    }
    else {
        Set-Content -LiteralPath (Join-Path $inboxRoot "codex-task.push.txt") -Value $PushControl -Encoding UTF8
    }

    $env:JJ_DISPATCHER_TEST_WORKER_COMMAND = $WorkerPath
    $env:JJ_DISPATCHER_TEST_WORKER_MODE = $Mode
    $env:JJ_DISPATCHER_WORKER_TIMEOUT_SECONDS = [string]$TimeoutSeconds
    $env:JJ_DISPATCHER_DISABLE_POSTBACK = "true"
    if ([string]::IsNullOrWhiteSpace($GitExe)) {
        Remove-Item Env:\JJ_DISPATCHER_TEST_GIT_EXE -ErrorAction SilentlyContinue
    }
    else {
        $env:JJ_DISPATCHER_TEST_GIT_EXE = $GitExe
    }

    $configPath = Join-Path $dispatcherRoot "config.json"
    $config = Get-Content -LiteralPath $configPath -Raw | ConvertFrom-Json
    $config.safety.allowAutoPush = [bool]$AllowAutoPush
    Set-Content -LiteralPath $configPath -Value ($config | ConvertTo-Json -Depth 10) -Encoding UTF8 -NoNewline

    & pwsh -NoProfile -ExecutionPolicy Bypass -File $runScript codex_task | Out-Host
    $exitCode = $LASTEXITCODE
    $run = Get-LatestRun
    $resultPath = Join-Path $run.FullName "result.json"
    $summaryPath = Join-Path $run.FullName "summary.md"
    $stdoutPath = Join-Path $run.FullName "codex-output.log"
    $stderrPath = Join-Path $run.FullName "codex-error.log"
    $result = Get-Content -LiteralPath $resultPath -Raw | ConvertFrom-Json
    $expectedExecutionStatus = if ($exitCode -eq 0) { "success" } else { "failed" }

    if (-not (Test-Path -LiteralPath $summaryPath -PathType Leaf)) { throw "$Name missing summary.md" }
    if (-not (Test-Path -LiteralPath $stdoutPath -PathType Leaf)) { throw "$Name missing codex-output.log" }
    if (-not (Test-Path -LiteralPath $stderrPath -PathType Leaf)) { throw "$Name missing codex-error.log" }
    if ([string]::IsNullOrWhiteSpace((Get-Content -LiteralPath $stdoutPath -Raw))) { throw "$Name stdout log is empty" }
    if ([string]::IsNullOrWhiteSpace((Get-Content -LiteralPath $stderrPath -Raw))) { throw "$Name stderr log is empty" }
    if ($result.status -ne $expectedExecutionStatus) { throw "$Name status expected $expectedExecutionStatus but was $($result.status)" }
    if ($result.executionStatus -ne $expectedExecutionStatus) { throw "$Name executionStatus expected $expectedExecutionStatus but was $($result.executionStatus)" }
    if ($result.deliveryStatus -ne "not_requested") { throw "$Name deliveryStatus expected not_requested but was $($result.deliveryStatus)" }
    if ($null -ne $result.deliveryChannel) { throw "$Name deliveryChannel expected null but was $($result.deliveryChannel)" }
    if ($result.deliveryRequired -ne $false) { throw "$Name deliveryRequired expected false but was $($result.deliveryRequired)" }

    [pscustomobject]@{
        case = $Name
        mode = $Mode
        processExitCode = $exitCode
        taskId = $result.taskId
        status = $result.status
        executionStatus = $result.executionStatus
        deliveryStatus = $result.deliveryStatus
        summary = $result.summary
        needsReview = $result.needsReview
        commit = $result.commit
        pushed = $result.pushed
        filesChanged = @($result.filesChanged)
        workingTreeClean = $result.workingTreeClean
        reviewHints = @($result.reviewHints)
        runDir = $run.FullName
        repo = $repo
    }
}

New-Item -ItemType Directory -Path $dispatcherRoot, $tempScriptsRoot, $inboxRoot -Force | Out-Null
Copy-Item -LiteralPath (Join-Path $sourceDispatcherRoot "run.ps1") -Destination (Join-Path $dispatcherRoot "run.ps1")
Copy-Item -LiteralPath (Join-Path $sourceDispatcherRoot "config.json") -Destination (Join-Path $dispatcherRoot "config.json")
Copy-Item -LiteralPath (Join-Path $sourceDispatcherRoot "tasks.json") -Destination (Join-Path $dispatcherRoot "tasks.json")
Copy-Item -LiteralPath (Join-Path $sourceScriptsRoot "load-config.ps1") -Destination (Join-Path $tempScriptsRoot "load-config.ps1")
Backup-Inbox

try {
    $worker = Write-TestWorker
    $commitFailureGit = Write-FakeGit -FailCommit
    $pushTrackingGit = Write-FakeGit -TrackPush
    $pushMarker = Join-Path $tempRoot "fake-git-push.marker"
    $results = @()
    $success = Invoke-LifecycleCase -Name "success" -Mode "success" -WorkerPath $worker
    $results += $success
    if ([string]::IsNullOrWhiteSpace($success.commit)) { throw "success did not record dispatcher-owned commit." }
    if ($success.pushed -ne $false) { throw "success pushed without explicit push control." }
    if ($success.workingTreeClean -ne $true) { throw "success workingTreeClean expected true." }
    if (-not ($success.filesChanged -contains "worker-success.txt")) { throw "success did not record worker-success.txt in filesChanged." }

    $noChange = Invoke-LifecycleCase -Name "no-change" -Mode "noop" -WorkerPath $worker
    $results += $noChange
    if ($noChange.status -ne "success") { throw "no-change status expected success but was $($noChange.status)." }
    if ($noChange.commit) { throw "no-change unexpectedly recorded a commit." }
    if ($noChange.workingTreeClean -ne $true) { throw "no-change workingTreeClean expected true." }

    $results += Invoke-LifecycleCase -Name "failure" -Mode "failure" -WorkerPath $worker
    $results += Invoke-LifecycleCase -Name "timeout" -Mode "hang" -WorkerPath $worker
    $results += Invoke-LifecycleCase -Name "child-timeout" -Mode "child-hang" -WorkerPath $worker
    $gitFailure = Invoke-LifecycleCase -Name "git-failure" -Mode "success" -WorkerPath $worker -GitExe $commitFailureGit
    $results += $gitFailure
    if ($gitFailure.status -ne "failed") { throw "git-failure status expected failed but was $($gitFailure.status)." }
    if (-not ($gitFailure.reviewHints -contains "Git commit failed.")) { throw "git-failure did not report Git commit failed." }

    $pushDisabled = Invoke-LifecycleCase -Name "push-disabled" -Mode "success" -WorkerPath $worker -PushControl "true"
    $results += $pushDisabled
    if ($pushDisabled.status -ne "failed") { throw "push-disabled status expected failed but was $($pushDisabled.status)." }
    if ($pushDisabled.pushed -ne $false) { throw "push-disabled unexpectedly recorded pushed=true." }
    if (-not ($pushDisabled.reviewHints -contains "Auto push disabled by config.")) { throw "push-disabled did not report disabled auto push." }

    Remove-Item -LiteralPath $pushMarker -ErrorAction SilentlyContinue
    $pushAllowed = Invoke-LifecycleCase -Name "push-allowed" -Mode "success" -WorkerPath $worker -GitExe $pushTrackingGit -PushControl "true" -AllowAutoPush
    $results += $pushAllowed
    if ($pushAllowed.status -ne "success") { throw "push-allowed status expected success but was $($pushAllowed.status)." }
    if ($pushAllowed.pushed -ne $true) { throw "push-allowed did not record pushed=true." }
    if (-not (Test-Path -LiteralPath $pushMarker -PathType Leaf)) { throw "push-allowed did not exercise fake git push." }

    $results | Format-Table -AutoSize
}
finally {
    Remove-Item Env:\JJ_DISPATCHER_TEST_WORKER_COMMAND -ErrorAction SilentlyContinue
    Remove-Item Env:\JJ_DISPATCHER_TEST_WORKER_MODE -ErrorAction SilentlyContinue
    Remove-Item Env:\JJ_DISPATCHER_WORKER_TIMEOUT_SECONDS -ErrorAction SilentlyContinue
    Remove-Item Env:\JJ_DISPATCHER_TEST_GIT_EXE -ErrorAction SilentlyContinue
    Remove-Item Env:\JJ_DISPATCHER_DISABLE_POSTBACK -ErrorAction SilentlyContinue
    Restore-Inbox
    Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
}
