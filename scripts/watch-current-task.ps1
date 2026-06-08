param(
    [string]$RunsRoot = (Join-Path (Join-Path (Split-Path -Parent $PSScriptRoot) "dispatcher") "runs"),
    [int]$PollSeconds = 2,
    [int]$StallSeconds = 120,
    [switch]$Once,
    [switch]$WaitForNext,
    [int]$MaxIterations = 0
)

$ErrorActionPreference = "Stop"

$script:TerminalExecutionStates = @("success", "failed", "cancelled")

function Resolve-NewestRun {
    param([string]$Root)

    if (-not (Test-Path -LiteralPath $Root -PathType Container)) {
        throw "Runs directory not found: $Root"
    }

    $runs = @(Get-ChildItem -LiteralPath $Root -Directory | Where-Object {
        $_.Name -match '^[0-9]{8}-[0-9]{6}-.+'
    })

    if ($runs.Count -eq 0) {
        throw "No Dispatcher runs found under: $Root"
    }

    return @($runs | Sort-Object -Property Name, LastWriteTimeUtc -Descending)[0]
}

function Get-DispatcherRuns {
    param([string]$Root)

    if (-not (Test-Path -LiteralPath $Root -PathType Container)) {
        return @()
    }

    return @(Get-ChildItem -LiteralPath $Root -Directory | Where-Object {
        $_.Name -match '^[0-9]{8}-[0-9]{6}-.+'
    } | Sort-Object -Property Name, LastWriteTimeUtc -Descending)
}

function Get-RunSnapshot {
    param([System.IO.DirectoryInfo]$Run)

    $taskPath = Join-Path $Run.FullName "task.json"
    $resultPath = Join-Path $Run.FullName "result.json"
    $stdoutPath = Join-Path $Run.FullName "codex-output.log"
    $stderrPath = Join-Path $Run.FullName "codex-error.log"
    $diffPath = Join-Path $Run.FullName "git-diff.patch"
    $summaryPath = Join-Path $Run.FullName "summary.md"
    $taskId = $Run.Name
    $executionStatus = $null

    if (Test-Path -LiteralPath $taskPath -PathType Leaf) {
        try {
            $task = Get-Content -LiteralPath $taskPath -Raw | ConvertFrom-Json
            if ($task.PSObject.Properties.Name.Contains("taskId") -and -not [string]::IsNullOrWhiteSpace([string]$task.taskId)) {
                $taskId = [string]$task.taskId
            }
            if ($task.PSObject.Properties.Name.Contains("executionStatus")) {
                $executionStatus = [string]$task.executionStatus
            }
        }
        catch {
            $executionStatus = "task-json-unreadable"
        }
    }

    if (Test-Path -LiteralPath $resultPath -PathType Leaf) {
        try {
            $result = Get-Content -LiteralPath $resultPath -Raw | ConvertFrom-Json
            if ($result.PSObject.Properties.Name.Contains("taskId") -and -not [string]::IsNullOrWhiteSpace([string]$result.taskId)) {
                $taskId = [string]$result.taskId
            }
            if ($result.PSObject.Properties.Name.Contains("executionStatus")) {
                $executionStatus = [string]$result.executionStatus
            }
            elseif ($result.PSObject.Properties.Name.Contains("status")) {
                $executionStatus = [string]$result.status
            }
        }
        catch {
            $executionStatus = "result-json-unreadable"
        }
    }

    return [pscustomobject]@{
        TaskId = $taskId
        RunDir = $Run.FullName
        CreatedAt = $Run.CreationTime
        Elapsed = (Get-Date) - $Run.CreationTime
        ExecutionStatus = $executionStatus
        Artifacts = [ordered]@{
            task = Test-Path -LiteralPath $taskPath -PathType Leaf
            result = Test-Path -LiteralPath $resultPath -PathType Leaf
            stdout = Test-Path -LiteralPath $stdoutPath -PathType Leaf
            stderr = Test-Path -LiteralPath $stderrPath -PathType Leaf
            diff = Test-Path -LiteralPath $diffPath -PathType Leaf
            summary = Test-Path -LiteralPath $summaryPath -PathType Leaf
        }
        Paths = [ordered]@{
            task = $taskPath
            stdout = $stdoutPath
            stderr = $stderrPath
            result = $resultPath
            diff = $diffPath
            summary = $summaryPath
        }
    }
}

function New-LogTailState {
    param([string]$Path)

    $length = 0L
    if (Test-Path -LiteralPath $Path -PathType Leaf) {
        $length = (Get-Item -LiteralPath $Path).Length
    }

    return [pscustomobject]@{
        Path = $Path
        Offset = $length
        Pending = ""
        MissingReported = $false
    }
}

function Read-NewLogLines {
    param(
        [pscustomobject]$State,
        [string]$Prefix
    )

    if (-not (Test-Path -LiteralPath $State.Path -PathType Leaf)) {
        if (-not $State.MissingReported) {
            $State.MissingReported = $true
            return @("[missing] $Prefix log not present yet: $($State.Path)")
        }
        return @()
    }

    $item = Get-Item -LiteralPath $State.Path
    if ($item.Length -lt $State.Offset) {
        $State.Offset = 0L
        $State.Pending = ""
    }
    if ($item.Length -eq $State.Offset) {
        return @()
    }

    $stream = [System.IO.File]::Open($State.Path, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
    try {
        [void]$stream.Seek($State.Offset, [System.IO.SeekOrigin]::Begin)
        $count = [int]($item.Length - $State.Offset)
        $buffer = New-Object byte[] $count
        [void]$stream.Read($buffer, 0, $count)
        $State.Offset = $item.Length
    }
    finally {
        $stream.Dispose()
    }

    $text = [System.Text.Encoding]::UTF8.GetString($buffer)
    $combined = $State.Pending + $text
    $combined = $combined -replace "`r`n", "`n"
    $combined = $combined -replace "`r", "`n"
    $endsWithNewLine = $combined.EndsWith("`n")
    $parts = @([System.Text.RegularExpressions.Regex]::Split($combined, "`n"))

    if ($endsWithNewLine) {
        $State.Pending = ""
        $complete = @($parts | Select-Object -SkipLast 1)
    }
    else {
        $State.Pending = [string]$parts[-1]
        $complete = @($parts | Select-Object -First ($parts.Count - 1))
    }

    return @($complete | ForEach-Object { "$Prefix $_" })
}

function Test-TerminalRunSnapshot {
    param([pscustomobject]$Snapshot)

    return $Snapshot.Artifacts.result -and ($script:TerminalExecutionStates -contains $Snapshot.ExecutionStatus)
}

function Wait-ForNextRun {
    param(
        [string]$Root,
        [int]$Poll,
        [int]$IterationLimit = 0
    )

    $baseline = $null
    $runs = @(Get-DispatcherRuns -Root $Root)
    if ($runs.Count -gt 0) {
        $baseline = $runs[0]
    }

    $iterations = 0
    while ($true) {
        $iterations++

        $runs = @(Get-DispatcherRuns -Root $Root)
        if ($runs.Count -gt 0) {
            $newest = $runs[0]
            if ($null -eq $baseline -or ($newest.Name -ne $baseline.Name -and $newest.Name -gt $baseline.Name)) {
                return $newest
            }
        }

        if ($IterationLimit -gt 0 -and $iterations -ge $IterationLimit) {
            return $null
        }

        Start-Sleep -Seconds $Poll
    }
}

function Write-RunHeader {
    param([pscustomobject]$Snapshot)

    Write-Output "taskId: $($Snapshot.TaskId)"
    Write-Output "runDir: $($Snapshot.RunDir)"
    Write-Output ("elapsed: {0:hh\:mm\:ss}" -f $Snapshot.Elapsed)
    Write-Output "executionStatus: $($Snapshot.ExecutionStatus)"
    Write-Output "artifacts: task=$($Snapshot.Artifacts.task) result=$($Snapshot.Artifacts.result) stdout=$($Snapshot.Artifacts.stdout) stderr=$($Snapshot.Artifacts.stderr) diff=$($Snapshot.Artifacts.diff) summary=$($Snapshot.Artifacts.summary)"
    Write-Output "task: $($Snapshot.Paths.task)"
    Write-Output "result: $($Snapshot.Paths.result)"
    Write-Output "stdout: $($Snapshot.Paths.stdout)"
    Write-Output "stderr: $($Snapshot.Paths.stderr)"
    Write-Output "diff: $($Snapshot.Paths.diff)"
    Write-Output "summary: $($Snapshot.Paths.summary)"
}

function Watch-Run {
    param(
        [System.IO.DirectoryInfo]$Run,
        [int]$Poll,
        [int]$Stall,
        [switch]$SinglePass,
        [int]$IterationLimit = 0
    )

    $snapshot = Get-RunSnapshot -Run $run
    Write-RunHeader -Snapshot $snapshot

    $stdoutState = New-LogTailState -Path $snapshot.Paths.stdout
    $stderrState = New-LogTailState -Path $snapshot.Paths.stderr
    $lastChangeAt = Get-Date
    $stallReported = $false
    $iterations = 0

    while ($true) {
        $iterations++
        $changed = $false

        foreach ($line in (Read-NewLogLines -State $stdoutState -Prefix "[stdout]")) {
            Write-Output $line
            $changed = $true
        }
        foreach ($line in (Read-NewLogLines -State $stderrState -Prefix "[stderr]")) {
            Write-Output $line
            $changed = $true
        }

        if ($changed) {
            $lastChangeAt = Get-Date
            $stallReported = $false
        }

        $snapshot = Get-RunSnapshot -Run $run
        if (Test-TerminalRunSnapshot -Snapshot $snapshot) {
            Write-Output "terminal: result.json present with executionStatus=$($snapshot.ExecutionStatus)"
            return
        }

        $quietFor = ((Get-Date) - $lastChangeAt).TotalSeconds
        if (-not $stallReported -and $quietFor -ge $Stall) {
            Write-Output ("STALLED: no stdout/stderr changes for {0:N0}s; still watching read-only." -f $quietFor)
            $stallReported = $true
        }

        if ($SinglePass -or ($IterationLimit -gt 0 -and $iterations -ge $IterationLimit)) {
            return
        }

        Start-Sleep -Seconds $Poll
    }
}

function Watch-CurrentTask {
    param(
        [string]$Root,
        [int]$Poll,
        [int]$Stall,
        [switch]$SinglePass,
        [switch]$Wait,
        [int]$IterationLimit = 0
    )

    if ($Poll -lt 1) { throw "PollSeconds must be at least 1." }
    if ($Stall -lt 1) { throw "StallSeconds must be at least 1." }

    if (-not $Wait) {
        $run = Resolve-NewestRun -Root $Root
        $snapshot = Get-RunSnapshot -Run $run
        if (Test-TerminalRunSnapshot -Snapshot $snapshot) {
            Write-RunHeader -Snapshot $snapshot
            Write-Output "terminal: result.json present with executionStatus=$($snapshot.ExecutionStatus)"
            return
        }
        Watch-Run -Run $run -Poll $Poll -Stall $Stall -SinglePass:$SinglePass -IterationLimit $IterationLimit
        return
    }

    Write-Output "waiting: watching for next Dispatcher run under $Root"
    $run = Wait-ForNextRun -Root $Root -Poll $Poll -IterationLimit $IterationLimit
    if ($null -eq $run) {
        return
    }

    Watch-Run -Run $run -Poll $Poll -Stall $Stall -SinglePass:$false
}

if ($MyInvocation.InvocationName -ne ".") {
    try {
        Watch-CurrentTask -Root $RunsRoot -Poll $PollSeconds -Stall $StallSeconds -SinglePass:$Once -Wait:$WaitForNext -IterationLimit $MaxIterations
    }
    catch [System.Management.Automation.PipelineStoppedException] {
        exit 130
    }
    catch {
        Write-Error $_
        exit 1
    }
}
