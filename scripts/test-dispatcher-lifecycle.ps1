param(
    [int]$TimeoutSeconds = 3
)

$ErrorActionPreference = "Stop"

$projectRoot = Split-Path $PSScriptRoot -Parent
$dispatcherRoot = Join-Path $projectRoot "dispatcher"
$inboxRoot = Join-Path $dispatcherRoot "inbox"
$runScript = Join-Path $dispatcherRoot "run.ps1"
$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("jj-dispatcher-lifecycle-" + [guid]::NewGuid().ToString("N"))

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
    default {
        Write-Error "unknown mode $mode" -ErrorAction Continue
        exit 9
    }
}
'@ | Set-Content -LiteralPath $workerPath -Encoding UTF8
    return $workerPath
}

function Write-FakeGit {
    $fakeGit = Join-Path $tempRoot "fake-git.cmd"
    @'
@echo off
if "%1"=="status" (
  echo  M worker-success.txt
  exit /b 0
)
if "%1"=="add" (
  echo forced git add failure 1>&2
  exit /b 42
)
if "%1"=="diff" (
  exit /b 0
)
if "%1"=="commit" (
  echo forced git commit failure 1>&2
  exit /b 43
)
git %*
'@ | Set-Content -LiteralPath $fakeGit -Encoding ASCII
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
        [string]$GitExe = ""
    )

    $repo = New-TestRepo -Name $Name
    Set-Content -LiteralPath (Join-Path $inboxRoot "codex-task.txt") -Value "Lifecycle test $Name" -Encoding UTF8
    Set-Content -LiteralPath (Join-Path $inboxRoot "codex-task.repo.txt") -Value $repo -Encoding UTF8
    Set-Content -LiteralPath (Join-Path $inboxRoot "codex-task.commit.txt") -Value "test: lifecycle $Name" -Encoding UTF8
    Remove-Item -LiteralPath (Join-Path $inboxRoot "codex-task.push.txt") -ErrorAction SilentlyContinue

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
        runDir = $run.FullName
    }
}

New-Item -ItemType Directory -Path $tempRoot -Force | Out-Null
New-Item -ItemType Directory -Path $inboxRoot -Force | Out-Null
Backup-Inbox

try {
    $worker = Write-TestWorker
    $fakeGit = Write-FakeGit
    $results = @()
    $results += Invoke-LifecycleCase -Name "success" -Mode "success" -WorkerPath $worker
    $results += Invoke-LifecycleCase -Name "failure" -Mode "failure" -WorkerPath $worker
    $results += Invoke-LifecycleCase -Name "timeout" -Mode "hang" -WorkerPath $worker
    $results += Invoke-LifecycleCase -Name "child-timeout" -Mode "child-hang" -WorkerPath $worker
    $results += Invoke-LifecycleCase -Name "git-failure" -Mode "success" -WorkerPath $worker -GitExe $fakeGit

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
