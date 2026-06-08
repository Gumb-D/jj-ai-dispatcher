param()

$ErrorActionPreference = "Stop"

$projectRoot = Split-Path -Parent $PSScriptRoot
$watcherPath = Join-Path $PSScriptRoot "watch-current-task.ps1"
$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("jj-dispatcher-watch-current-task-" + [guid]::NewGuid().ToString("N"))
$fixtureRunsRoot = Join-Path $tempRoot "dispatcher\runs"

. $watcherPath

function Assert-Equal {
    param([object]$Actual, [object]$Expected, [string]$Message)
    if ($Actual -ne $Expected) {
        throw "$Message Expected '$Expected' but was '$Actual'."
    }
}

function Assert-Contains {
    param([string]$Text, [string]$Expected, [string]$Message)
    if (-not $Text.Contains($Expected)) {
        throw "$Message Missing '$Expected' in:`n$Text"
    }
}

function Assert-NotContains {
    param([string]$Text, [string]$Unexpected, [string]$Message)
    if ($Text.Contains($Unexpected)) {
        throw "$Message Unexpected '$Unexpected' in:`n$Text"
    }
}

function Join-CommandArgs {
    param([string[]]$CommandArgs)

    return [string](($CommandArgs | ForEach-Object {
        if ($_ -match '^[A-Za-z0-9_:/\\.\-]+$') {
            $_
        }
        else {
            "'" + ($_.Replace("'", "''")) + "'"
        }
    }) -join " ")
}

function Start-WatcherRunspace {
    param([string[]]$CommandArgs)

    $ps = [powershell]::Create()
    $script = "& " + [string](Join-CommandArgs -CommandArgs @($watcherPath)) + " " + [string](Join-CommandArgs -CommandArgs $CommandArgs)
    [void]$ps.AddScript($script)
    $async = $ps.BeginInvoke()
    return [pscustomobject]@{
        PowerShell = $ps
        Async = $async
    }
}

function Receive-WatcherRunspace {
    param(
        [pscustomobject]$Runspace,
        [int]$TimeoutSeconds = 20
    )

    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    while (-not $Runspace.Async.IsCompleted) {
        if ((Get-Date) -gt $deadline) {
            $Runspace.PowerShell.Stop()
            $Runspace.PowerShell.Dispose()
            throw "Watcher did not exit within $TimeoutSeconds seconds."
        }
        Start-Sleep -Milliseconds 100
    }

    try {
        $output = $Runspace.PowerShell.EndInvoke($Runspace.Async) | Out-String
        if ($Runspace.PowerShell.Streams.Error.Count -gt 0) {
            $errors = $Runspace.PowerShell.Streams.Error | Out-String
            throw "Watcher runspace wrote errors:`n$errors`nOutput:`n$output"
        }
        return $output
    }
    finally {
        $Runspace.PowerShell.Dispose()
    }
}

function New-FixtureRun {
    param(
        [string]$TaskId,
        [string]$ExecutionStatus = "running",
        [switch]$Result,
        [switch]$MissingLogs
    )

    $runDir = Join-Path $fixtureRunsRoot $TaskId
    New-Item -ItemType Directory -Path $runDir -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $runDir "task.json") -Value (([ordered]@{
        taskId = $TaskId
        status = $ExecutionStatus
        executionStatus = $ExecutionStatus
        worker = "codex"
    }) | ConvertTo-Json -Depth 4) -Encoding UTF8 -NoNewline

    if (-not $MissingLogs) {
        Set-Content -LiteralPath (Join-Path $runDir "codex-output.log") -Value "" -Encoding UTF8 -NoNewline
        Set-Content -LiteralPath (Join-Path $runDir "codex-error.log") -Value "" -Encoding UTF8 -NoNewline
    }
    Set-Content -LiteralPath (Join-Path $runDir "git-diff.patch") -Value "" -Encoding UTF8 -NoNewline

    if ($Result) {
        Set-Content -LiteralPath (Join-Path $runDir "result.json") -Value (([ordered]@{
            taskId = $TaskId
            status = $ExecutionStatus
            executionStatus = $ExecutionStatus
        }) | ConvertTo-Json -Depth 4) -Encoding UTF8 -NoNewline
    }

    return Get-Item -LiteralPath $runDir
}

function Complete-FixtureRun {
    param(
        [System.IO.DirectoryInfo]$Run,
        [string]$ExecutionStatus = "success"
    )

    $taskId = $Run.Name
    Set-Content -LiteralPath (Join-Path $Run.FullName "result.json") -Value (([ordered]@{
        taskId = $taskId
        status = $ExecutionStatus
        executionStatus = $ExecutionStatus
    }) | ConvertTo-Json -Depth 4) -Encoding UTF8 -NoNewline
}

function Get-ArtifactHashes {
    param([string]$Root)

    $hashes = [ordered]@{}
    Get-ChildItem -LiteralPath $Root -Recurse -File | Sort-Object FullName | ForEach-Object {
        $relative = $_.FullName.Substring($Root.Length).TrimStart("\")
        $hashes[$relative] = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash
    }
    return $hashes
}

function Assert-HashesUnchanged {
    param([hashtable]$Before, [hashtable]$After)

    Assert-Equal -Actual $After.Count -Expected $Before.Count -Message "Artifact file count changed."
    foreach ($key in $Before.Keys) {
        if (-not $After.Contains($key)) {
            throw "Artifact disappeared: $key"
        }
        Assert-Equal -Actual $After[$key] -Expected $Before[$key] -Message "Artifact content changed for $key."
    }
}

try {
    New-Item -ItemType Directory -Path $fixtureRunsRoot -Force | Out-Null

    $oldRun = New-FixtureRun -TaskId "20260608-010000-old"
    $newRun = New-FixtureRun -TaskId "20260608-010100-new"
    $oldRun.LastWriteTime = (Get-Date).AddMinutes(10)
    $selected = Resolve-NewestRun -Root $fixtureRunsRoot
    Assert-Equal -Actual $selected.Name -Expected $newRun.Name -Message "Newest run selection should prefer taskId timestamp order."

    $stdoutPath = Join-Path $newRun.FullName "codex-output.log"
    $stderrPath = Join-Path $newRun.FullName "codex-error.log"
    Set-Content -LiteralPath $stdoutPath -Value "already seen`n" -Encoding UTF8 -NoNewline
    Set-Content -LiteralPath $stderrPath -Value "" -Encoding UTF8 -NoNewline
    $stdoutState = New-LogTailState -Path $stdoutPath
    Add-Content -LiteralPath $stdoutPath -Value "line one" -NoNewline
    $lines = Read-NewLogLines -State $stdoutState -Prefix "[stdout]"
    Assert-Equal -Actual $lines.Count -Expected 0 -Message "Partial stdout line should not be emitted yet."
    Add-Content -LiteralPath $stdoutPath -Value "`nline two`n" -NoNewline
    $lines = Read-NewLogLines -State $stdoutState -Prefix "[stdout]"
    Assert-Equal -Actual $lines.Count -Expected 2 -Message "Completed stdout lines should be emitted incrementally."
    Assert-Equal -Actual $lines[0] -Expected "[stdout] line one" -Message "First incremental stdout line mismatch."
    Assert-Equal -Actual $lines[1] -Expected "[stdout] line two" -Message "Second incremental stdout line mismatch."

    $stalledOutput = & $watcherPath -RunsRoot $fixtureRunsRoot -PollSeconds 1 -StallSeconds 1 -MaxIterations 2 *>&1 | Out-String
    Assert-Contains -Text $stalledOutput -Expected "STALLED:" -Message "Stalled warning was not displayed."

    $terminalRun = New-FixtureRun -TaskId "20260608-010200-terminal" -ExecutionStatus "success" -Result
    $terminalOutput = & $watcherPath -RunsRoot $fixtureRunsRoot -PollSeconds 1 -StallSeconds 10 -Once *>&1 | Out-String
    Assert-Contains -Text $terminalOutput -Expected "terminal: result.json present with executionStatus=success" -Message "Terminal result detection failed."

    Remove-Item -LiteralPath $terminalRun.FullName -Recurse -Force
    $missingRun = New-FixtureRun -TaskId "20260608-010300-missing" -MissingLogs
    $missingOutput = & $watcherPath -RunsRoot $fixtureRunsRoot -PollSeconds 1 -StallSeconds 10 -Once *>&1 | Out-String
    Assert-Contains -Text $missingOutput -Expected "[missing] [stdout] log not present yet:" -Message "Missing stdout log was not reported."
    Assert-Contains -Text $missingOutput -Expected "[missing] [stderr] log not present yet:" -Message "Missing stderr log was not reported."

    $before = Get-ArtifactHashes -Root $missingRun.FullName
    $readOnlyOutput = & $watcherPath -RunsRoot $fixtureRunsRoot -PollSeconds 1 -StallSeconds 10 -Once *>&1 | Out-String
    $after = Get-ArtifactHashes -Root $missingRun.FullName
    Assert-HashesUnchanged -Before $before -After $after
    Assert-Contains -Text $readOnlyOutput -Expected "taskId: 20260608-010300-missing" -Message "Read-only run did not inspect expected fixture."

    Remove-Item -LiteralPath $missingRun.FullName -Recurse -Force
    Complete-FixtureRun -Run $oldRun
    Complete-FixtureRun -Run $newRun
    $baselineRun = New-FixtureRun -TaskId "20260608-010400-baseline" -ExecutionStatus "success" -Result
    $baselineHashes = Get-ArtifactHashes -Root $baselineRun.FullName
    $waiter = Start-WatcherRunspace -CommandArgs @(
        "-RunsRoot", $fixtureRunsRoot,
        "-PollSeconds", "1",
        "-StallSeconds", "10",
        "-WaitForNext"
    )
    Start-Sleep -Milliseconds 1500
    $waitRun = New-FixtureRun -TaskId "20260608-010500-waited"
    $waitRunInitialHashes = Get-ArtifactHashes -Root $waitRun.FullName
    Start-Sleep -Milliseconds 2000
    Add-Content -LiteralPath (Join-Path $waitRun.FullName "codex-output.log") -Value "fresh stdout" -Encoding UTF8
    Add-Content -LiteralPath (Join-Path $waitRun.FullName "codex-error.log") -Value "fresh stderr" -Encoding UTF8
    Start-Sleep -Milliseconds 1200
    Complete-FixtureRun -Run $waitRun
    $waitOutput = Receive-WatcherRunspace -Runspace $waiter
    $baselineAfterHashes = Get-ArtifactHashes -Root $baselineRun.FullName
    $waitRunAfterHashes = Get-ArtifactHashes -Root $waitRun.FullName
    Assert-HashesUnchanged -Before $baselineHashes -After $baselineAfterHashes
    Assert-Equal -Actual $waitRunAfterHashes["task.json"] -Expected $waitRunInitialHashes["task.json"] -Message "Wait mode changed the new run task artifact."
    Assert-Equal -Actual $waitRunAfterHashes["git-diff.patch"] -Expected $waitRunInitialHashes["git-diff.patch"] -Message "Wait mode changed the new run diff artifact."
    Assert-Contains -Text $waitOutput -Expected "waiting: watching for next Dispatcher run under" -Message "Wait mode did not report waiting state."
    Assert-NotContains -Text $waitOutput -Unexpected "taskId: $($baselineRun.Name)" -Message "Wait mode attached to already-completed baseline run."
    Assert-Contains -Text $waitOutput -Expected "taskId: $($waitRun.Name)" -Message "Wait mode did not attach to newly created run."
    Assert-Contains -Text $waitOutput -Expected "[stdout] fresh stdout" -Message "Wait mode did not tail appended stdout."
    Assert-Contains -Text $waitOutput -Expected "[stderr] fresh stderr" -Message "Wait mode did not tail appended stderr."
    Assert-Contains -Text $waitOutput -Expected "terminal: result.json present with executionStatus=success" -Message "Wait mode did not exit on terminal result."
    Assert-Equal -Actual ([regex]::Matches($waitOutput, "taskId: $([regex]::Escape($waitRun.Name))").Count) -Expected 1 -Message "Wait mode should attach exactly once to the new run."

    $readOnlyWaitOutput = & $watcherPath -RunsRoot $fixtureRunsRoot -PollSeconds 1 -StallSeconds 10 -WaitForNext -MaxIterations 1 *>&1 | Out-String
    $afterReadOnlyWaitHashes = Get-ArtifactHashes -Root $baselineRun.FullName
    Assert-HashesUnchanged -Before $baselineAfterHashes -After $afterReadOnlyWaitHashes
    Assert-Contains -Text $readOnlyWaitOutput -Expected "waiting: watching for next Dispatcher run under" -Message "Wait mode read-only check did not wait for a newer run."

    Write-Host "watch-current-task fixture tests passed."
}
finally {
    Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
}
