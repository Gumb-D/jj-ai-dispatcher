param(
    [Parameter(Mandatory = $true, Position = 0)]
    [string]$TaskName,

    [Parameter(Mandatory = $false)]
    [string]$Repo,

    [Parameter(Mandatory = $false)]
    [switch]$VerboseLog
)

$ErrorActionPreference = "Stop"

function Write-Step {
    param([string]$Message)
    Write-Host "[dispatcher] $Message"
}

function New-LogFile {
    param([string]$TaskName)

    $logDir = Join-Path $PSScriptRoot "logs"
    if (-not (Test-Path $logDir)) {
        New-Item -ItemType Directory -Path $logDir | Out-Null
    }

    $timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
    return Join-Path $logDir "$timestamp-$TaskName.log"
}

function New-TaskId {
    $timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $suffix = [guid]::NewGuid().ToString("N").Substring(0, 8)
    return "$timestamp-$suffix"
}

function New-RunContext {
    param([string]$TaskId)

    $runsDir = Join-Path $PSScriptRoot "runs"
    $runDir = Join-Path $runsDir $TaskId
    New-Item -ItemType Directory -Path $runDir -Force | Out-Null

    return [pscustomobject]@{
        TaskId = $TaskId
        RunDir = $runDir
        TaskJson = Join-Path $runDir "task.json"
        ResultJson = Join-Path $runDir "result.json"
        SummaryMd = Join-Path $runDir "summary.md"
        StdoutLog = Join-Path $runDir "codex-output.log"
        StderrLog = Join-Path $runDir "codex-error.log"
        DiffPatch = Join-Path $runDir "git-diff.patch"
    }
}

function ConvertTo-DispatcherRelativePath {
    param([string]$Path)

    $relative = [System.IO.Path]::GetRelativePath($projectRoot, $Path)
    return $relative.Replace("\", "/")
}

$WorkerReportMaxLength = 12000

function Set-ObjectProperty {
    param(
        [object]$Object,
        [string]$Name,
        [object]$Value
    )

    if ($Object.PSObject.Properties.Name.Contains($Name)) {
        $Object.$Name = $Value
    }
    else {
        $Object | Add-Member -NotePropertyName $Name -NotePropertyValue $Value
    }
}

function Redact-ResultText {
    param([string]$Text)

    if ([string]::IsNullOrWhiteSpace($Text)) {
        return ""
    }

    $redacted = $Text
    $redacted = [regex]::Replace($redacted, "(?i)(x-dispatcher-token\s*[:=]\s*)[^\s""',;]+", '$1[REDACTED]')
    $redacted = [regex]::Replace($redacted, "(?i)\b(bearer\s+)[A-Za-z0-9._~+/\-]+=*", '$1[REDACTED]')
    $redacted = [regex]::Replace($redacted, "(?i)\b(sk-[A-Za-z0-9_\-]{20,})\b", '[REDACTED]')
    $redacted = [regex]::Replace($redacted, "(?i)\b(api[_-]?key|token|secret|password|authorization)\s*[:=]\s*[""']?[^""'\s,;]+", '$1=[REDACTED]')
    return $redacted
}

function New-WorkerReportContract {
    param(
        [hashtable]$Result,
        [int]$MaxLength = $WorkerReportMaxLength
    )

    $report = [string]$Result.Stdout
    if ($Result.ExitCode -ne 0 -and -not [string]::IsNullOrWhiteSpace([string]$Result.Stderr)) {
        $report = Join-ResultText -Existing $report -Addition ([string]$Result.Stderr)
    }
    elseif ([string]::IsNullOrWhiteSpace($report)) {
        $report = [string]$Result.Stderr
    }

    $report = (Redact-ResultText -Text $report).Trim()
    $originalLength = $report.Length
    $truncated = $false
    if ($originalLength -gt $MaxLength) {
        $report = $report.Substring(0, $MaxLength).TrimEnd()
        $truncated = $true
    }

    $summary = ""
    if (-not [string]::IsNullOrWhiteSpace($report)) {
        $summaryLines = @($report -split "`r?`n" | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
        if ($summaryLines.Count -gt 0) {
            $summary = [string]$summaryLines[0]
            if ($summary.Length -gt 1000) {
                $summary = $summary.Substring(0, 1000).TrimEnd()
            }
        }
    }

    return [pscustomobject][ordered]@{
        summary = $summary
        report = $report
        metadata = [pscustomobject][ordered]@{
            maxLength = $MaxLength
            originalLength = $originalLength
            persistedLength = $report.Length
            truncated = $truncated
            redacted = $true
        }
    }
}

function Set-WorkerReportFields {
    param(
        [object]$ResultContract,
        [hashtable]$WorkerResult
    )

    $workerReport = New-WorkerReportContract -Result $WorkerResult
    Set-ObjectProperty -Object $ResultContract -Name "workerSummary" -Value $workerReport.summary
    Set-ObjectProperty -Object $ResultContract -Name "workerReport" -Value $workerReport.report
    Set-ObjectProperty -Object $ResultContract -Name "workerReportMetadata" -Value $workerReport.metadata
    Set-ObjectProperty -Object $ResultContract -Name "workerReportTruncated" -Value $workerReport.metadata.truncated
}

function Get-DeliveryRecoveryMessage {
    param(
        [string]$DeliveryStatus,
        [string]$Detail = ""
    )

    switch ($DeliveryStatus) {
        "delivered" { return "Browser postback delivered. Persistent result remains available through dispatcher_latest_result and dispatcher_get_run." }
        "pending" { return "Browser postback pending. If browser delivery does not complete, retrieve the persisted result through dispatcher_latest_result or dispatcher_get_run." }
        "timeout" { return "Browser postback timed out. Execution result remains authoritative through dispatcher_latest_result and dispatcher_get_run." }
        "failed" {
            if ([string]::IsNullOrWhiteSpace($Detail)) {
                return "Browser postback failed. Execution result remains authoritative through dispatcher_latest_result and dispatcher_get_run."
            }
            return "Browser postback failed: $Detail. Execution result remains authoritative through dispatcher_latest_result and dispatcher_get_run."
        }
        "skipped" { return "Browser postback skipped. Persistent result is available through dispatcher_latest_result and dispatcher_get_run." }
        "unavailable" { return "Browser postback unavailable. Persistent result is available through dispatcher_latest_result and dispatcher_get_run." }
        default { return "No browser postback was requested. Persistent result is available through dispatcher_latest_result and dispatcher_get_run." }
    }
}

function Set-ResultDerivedFields {
    param([object]$ResultContract)

    $validationItems = @()
    if ($ResultContract.PSObject.Properties.Name.Contains("workingTreeClean")) {
        $validationItems += if ([bool]$ResultContract.workingTreeClean) { "git status --short clean" } else { "git status --short not clean or unavailable" }
    }
    $validationItems += "deliveryStatus=$($ResultContract.deliveryStatus)"
    if ($ResultContract.PSObject.Properties.Name.Contains("pushDecision") -and $null -ne $ResultContract.pushDecision) {
        $validationItems += "pushDecision=$($ResultContract.pushDecision.source):$($ResultContract.pushDecision.shouldPush)"
    }
    Set-ObjectProperty -Object $ResultContract -Name "validationSummary" -Value $validationItems

    $detail = if ($ResultContract.PSObject.Properties.Name.Contains("deliveryDetail")) { [string]$ResultContract.deliveryDetail } else { "" }
    Set-ObjectProperty -Object $ResultContract -Name "recovery" -Value (Get-DeliveryRecoveryMessage -DeliveryStatus $ResultContract.deliveryStatus -Detail $detail)
}

function Write-JsonFile {
    param(
        [string]$Path,
        [object]$Value
    )

    $Value | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $Path -Encoding UTF8 -NoNewline
}

function Get-CodexTaskPrompt {
    $promptPath = Join-Path $PSScriptRoot "inbox\codex-task.txt"
    if (-not (Test-Path -LiteralPath $promptPath -PathType Leaf)) {
        return ""
    }

    return (Get-Content -LiteralPath $promptPath -Raw).Trim()
}

function Get-CodexTaskCommitMessage {
    param([string]$DispatcherRoot)

    $commitMessagePath = Join-Path $DispatcherRoot "inbox\codex-task.commit.txt"
    if (Test-Path -LiteralPath $commitMessagePath -PathType Leaf) {
        return (Get-Content -LiteralPath $commitMessagePath -Raw).Trim()
    }

    return "chore: codex task update"
}

function Get-GitStatusFiles {
    param([string]$StatusText)

    if ([string]::IsNullOrWhiteSpace($StatusText)) {
        return @()
    }

    $files = New-Object System.Collections.Generic.List[string]
    foreach ($line in ($StatusText -split "`r?`n")) {
        if ([string]::IsNullOrWhiteSpace($line) -or $line.Length -lt 4) {
            continue
        }

        $path = $line.Substring(3).Trim()
        if ($path -match " -> ") {
            $path = ($path -split " -> ")[-1].Trim()
        }

        if (-not [string]::IsNullOrWhiteSpace($path)) {
            $files.Add($path)
        }
    }

    return @($files | Select-Object -Unique)
}

function Normalize-WorkerResult {
    param(
        [hashtable]$Result,
        [string]$TaskId,
        [string]$RepoPath,
        [string]$Worker,
        [string]$CommitMessage,
        [string]$StdoutPath,
        [string]$StderrPath,
        [string]$DiffPath
    )

    $status = if ($Result.ExitCode -eq 0) { "success" } else { "failed" }
    $summary = if ($status -eq "success") { "Codex worker completed successfully." } else { "Codex worker failed." }

    return [pscustomobject][ordered]@{
        taskId = $TaskId
        status = $status
        executionStatus = $status
        deliveryStatus = "not_requested"
        deliveryChannel = $null
        deliveryRequired = $false
        repo = $RepoPath
        worker = $Worker
        filesChanged = @()
        commit = $null
        commitMessage = $CommitMessage
        pushed = $false
        globalAutoPushAllowed = $false
        pushDecision = [pscustomobject][ordered]@{
            shouldPush = $false
            source = "not_evaluated"
            reason = "Push decision has not been evaluated yet."
        }
        pushDecisionReason = "Push decision has not been evaluated yet."
        workingTreeClean = $false
        summary = $summary
        logs = [pscustomobject][ordered]@{
            stdout = ConvertTo-DispatcherRelativePath -Path $StdoutPath
            stderr = ConvertTo-DispatcherRelativePath -Path $StderrPath
            diff = ConvertTo-DispatcherRelativePath -Path $DiffPath
        }
        needsReview = ($status -ne "success")
        reviewHints = @()
    }
}

function Get-GitHeadCommit {
    param(
        [string]$RepoPath,
        [pscustomobject]$Config,
        [string]$LogFile
    )

    $headResult = Invoke-LoggedCommand -FilePath $Config.gitExe -ArgumentList @("rev-parse", "--short", "HEAD") -WorkingDirectory $RepoPath -LogFile $LogFile
    if ($headResult.ExitCode -ne 0) {
        return $null
    }

    return $headResult.Stdout.Trim()
}

function Write-RunSummary {
    param(
        [pscustomobject]$RunContext,
        [object]$ResultContract,
        [string]$TaskText
    )

    $files = if ($ResultContract.filesChanged.Count -gt 0) {
        ($ResultContract.filesChanged | ForEach-Object { "- $_" }) -join [Environment]::NewLine
    }
    else {
        "- None"
    }

    $commit = if ([string]::IsNullOrWhiteSpace($ResultContract.commit)) {
        "None"
    }
    else {
        "$($ResultContract.commit) $($ResultContract.commitMessage)"
    }

    $validation = if ($ResultContract.PSObject.Properties.Name.Contains("validationSummary") -and $null -ne $ResultContract.validationSummary) {
        (@($ResultContract.validationSummary) | ForEach-Object { "- $_" }) -join [Environment]::NewLine
    }
    elseif ($ResultContract.workingTreeClean) {
        "- git status --short clean"
    }
    else {
        "- git status --short not clean or unavailable"
    }

    $reviewHints = if ($ResultContract.reviewHints.Count -gt 0) {
        ($ResultContract.reviewHints | ForEach-Object { "- $_" }) -join [Environment]::NewLine
    }
    else {
        "- No review hints recorded."
    }

    $deliveryChannel = if ([string]::IsNullOrWhiteSpace($ResultContract.deliveryChannel)) {
        "None"
    }
    else {
        $ResultContract.deliveryChannel
    }

    $detail = if ($ResultContract.PSObject.Properties.Name.Contains("deliveryDetail")) { [string]$ResultContract.deliveryDetail } else { "" }
    $recovery = Get-DeliveryRecoveryMessage -DeliveryStatus $ResultContract.deliveryStatus -Detail $detail
    $workerReport = if ($ResultContract.PSObject.Properties.Name.Contains("workerReport") -and -not [string]::IsNullOrWhiteSpace($ResultContract.workerReport)) {
        [string]$ResultContract.workerReport
    }
    else {
        "No worker report captured."
    }
    $workerMetadata = if ($ResultContract.PSObject.Properties.Name.Contains("workerReportMetadata") -and $null -ne $ResultContract.workerReportMetadata) {
        "Truncated: $($ResultContract.workerReportMetadata.truncated); Persisted Length: $($ResultContract.workerReportMetadata.persistedLength); Original Length: $($ResultContract.workerReportMetadata.originalLength); Max Length: $($ResultContract.workerReportMetadata.maxLength); Redacted: $($ResultContract.workerReportMetadata.redacted)"
    }
    else {
        "Truncated: False; Persisted Length: 0; Original Length: 0; Max Length: $WorkerReportMaxLength; Redacted: True"
    }
    $pushDecision = if ($ResultContract.PSObject.Properties.Name.Contains("pushDecision") -and $null -ne $ResultContract.pushDecision) {
        "Should Push: $($ResultContract.pushDecision.shouldPush); Source: $($ResultContract.pushDecision.source); Reason: $($ResultContract.pushDecision.reason)"
    }
    else {
        "Should Push: False; Source: legacy_result; Reason: Push decision was not recorded."
    }

    $content = @"
# Dispatcher Run Summary

Task ID: $($ResultContract.taskId)
Status: $($ResultContract.status)
Execution Status: $($ResultContract.executionStatus)
Delivery Status: $($ResultContract.deliveryStatus)
Delivery Channel: $deliveryChannel
Delivery Required: $($ResultContract.deliveryRequired)
Repo: $($ResultContract.repo)
Worker: $($ResultContract.worker)

## Execution

Status: $($ResultContract.executionStatus)
Top-level Status: $($ResultContract.status)

## Delivery

Status: $($ResultContract.deliveryStatus)
Channel: $deliveryChannel
Required: $($ResultContract.deliveryRequired)

## Recovery

$recovery

## Task

$TaskText

## Files Changed

$files

## Commit

$commit
Pushed: $($ResultContract.pushed)
Global Auto Push Allowed: $($ResultContract.globalAutoPushAllowed)

## Push Decision

$pushDecision

## Validation

$validation

## Notes

Summary: $($ResultContract.summary)
Needs review: $($ResultContract.needsReview)

## Worker Report

$workerReport

## Worker Report Metadata

$workerMetadata

## Review Hints

$reviewHints
"@

    Set-Content -LiteralPath $RunContext.SummaryMd -Value $content -Encoding UTF8 -NoNewline
}

function Invoke-LoggedCommand {
    param(
        [string]$FilePath,
        [string[]]$ArgumentList,
        [string]$WorkingDirectory,
        [string]$LogFile
    )

    $stdoutFile = "$LogFile.stdout.tmp"
    $stderrFile = "$LogFile.stderr.tmp"

    try {
        $process = Start-Process `
            -FilePath $FilePath `
            -ArgumentList $ArgumentList `
            -WorkingDirectory $WorkingDirectory `
            -NoNewWindow `
            -Wait `
            -PassThru `
            -RedirectStandardOutput $stdoutFile `
            -RedirectStandardError $stderrFile

        $stdout = if (Test-Path $stdoutFile) { Get-Content $stdoutFile -Raw } else { "" }
        $stderr = if (Test-Path $stderrFile) { Get-Content $stderrFile -Raw } else { "" }

        Add-Content -Path $LogFile -Value "COMMAND:"
        Add-Content -Path $LogFile -Value "$FilePath $($ArgumentList -join ' ')"
        Add-Content -Path $LogFile -Value ""
        Add-Content -Path $LogFile -Value "WORKING DIRECTORY:"
        Add-Content -Path $LogFile -Value $WorkingDirectory
        Add-Content -Path $LogFile -Value ""
        Add-Content -Path $LogFile -Value "STDOUT:"
        Add-Content -Path $LogFile -Value $stdout
        Add-Content -Path $LogFile -Value ""
        Add-Content -Path $LogFile -Value "STDERR:"
        Add-Content -Path $LogFile -Value $stderr
        Add-Content -Path $LogFile -Value ""
        Add-Content -Path $LogFile -Value "EXIT CODE: $($process.ExitCode)"

        return @{
            ExitCode = $process.ExitCode
            Stdout = $stdout
            Stderr = $stderr
        }
    }
    finally {
        Remove-Item $stdoutFile, $stderrFile -ErrorAction SilentlyContinue
    }
}

function Set-PushDecisionFields {
    param(
        [object]$ResultContract,
        [object]$Decision
    )

    Set-ObjectProperty -Object $ResultContract -Name "globalAutoPushAllowed" -Value ([bool]$Decision.globalAutoPushAllowed)
    Set-ObjectProperty -Object $ResultContract -Name "pushDecision" -Value ([pscustomobject][ordered]@{
        shouldPush = [bool]$Decision.shouldPush
        source = [string]$Decision.source
        reason = [string]$Decision.reason
    })
    Set-ObjectProperty -Object $ResultContract -Name "pushDecisionReason" -Value ([string]$Decision.reason)
}

function Resolve-CodexTaskPushDecision {
    param(
        [pscustomobject]$Config,
        [string]$DispatcherRoot,
        [switch]$NoChanges
    )

    $globalAllowed = [bool]$Config.safety.allowAutoPush
    if ($NoChanges) {
        return [pscustomobject][ordered]@{
            shouldPush = $false
            source = "no_changes"
            reason = "No Dispatcher-owned commit was created, so push was skipped."
            globalAutoPushAllowed = $globalAllowed
            invalid = $false
            rejected = $false
        }
    }

    $pushControlPath = Join-Path $DispatcherRoot "inbox\codex-task.push.txt"
    if (-not (Test-Path -LiteralPath $pushControlPath -PathType Leaf)) {
        if ($globalAllowed) {
            return [pscustomobject][ordered]@{
                shouldPush = $true
                source = "global_default"
                reason = "Global allowAutoPush=true and no per-task push override was provided."
                globalAutoPushAllowed = $true
                invalid = $false
                rejected = $false
            }
        }

        return [pscustomobject][ordered]@{
            shouldPush = $false
            source = "global_default"
            reason = "Global allowAutoPush=false and no per-task push request was provided."
            globalAutoPushAllowed = $false
            invalid = $false
            rejected = $false
        }
    }

    $pushControl = (Get-Content -LiteralPath $pushControlPath -Raw).Trim().ToLowerInvariant()
    if ($pushControl -in @("false", "no", "0", "off", "never")) {
        return [pscustomobject][ordered]@{
            shouldPush = $false
            source = "task_opt_out"
            reason = "Per-task push override explicitly opted out."
            globalAutoPushAllowed = $globalAllowed
            invalid = $false
            rejected = $false
        }
    }

    if ($pushControl -notin @("true", "yes", "1", "on", "always")) {
        return [pscustomobject][ordered]@{
            shouldPush = $false
            source = "task_override"
            reason = "Invalid push control value in dispatcher/inbox/codex-task.push.txt. Use true/yes/1/on/always or false/no/0/off/never."
            globalAutoPushAllowed = $globalAllowed
            invalid = $true
            rejected = $false
        }
    }

    if (-not $globalAllowed) {
        return [pscustomobject][ordered]@{
            shouldPush = $false
            source = "task_opt_in"
            reason = "Per-task push request was rejected because global allowAutoPush=false."
            globalAutoPushAllowed = $false
            invalid = $false
            rejected = $true
        }
    }

    return [pscustomobject][ordered]@{
        shouldPush = $true
        source = "task_opt_in"
        reason = "Per-task push override explicitly requested push and global allowAutoPush=true."
        globalAutoPushAllowed = $true
        invalid = $false
        rejected = $false
    }
}

function Get-ConfigNumber {
    param(
        [object]$Object,
        [string]$Name,
        [int]$DefaultValue
    )

    if ($null -eq $Object -or -not $Object.PSObject.Properties.Name.Contains($Name)) {
        return $DefaultValue
    }

    $value = 0
    if ([int]::TryParse([string]$Object.$Name, [ref]$value) -and $value -gt 0) {
        return $value
    }

    return $DefaultValue
}

function Get-WorkerTimeoutSeconds {
    param([pscustomobject]$Config)

    $envTimeout = [Environment]::GetEnvironmentVariable("JJ_DISPATCHER_WORKER_TIMEOUT_SECONDS")
    $parsed = 0
    if ([int]::TryParse($envTimeout, [ref]$parsed) -and $parsed -gt 0) {
        return $parsed
    }

    return Get-ConfigNumber -Object $Config -Name "workerTimeoutSeconds" -DefaultValue 1800
}

function Get-OwnedProcessTree {
    param([int]$RootProcessId)

    $all = @(Get-CimInstance Win32_Process -ErrorAction SilentlyContinue)
    $byParent = @{}
    foreach ($processInfo in $all) {
        $parentId = [int]$processInfo.ParentProcessId
        if (-not $byParent.ContainsKey($parentId)) {
            $byParent[$parentId] = New-Object System.Collections.Generic.List[object]
        }
        $byParent[$parentId].Add($processInfo)
    }

    $descendants = New-Object System.Collections.Generic.List[object]
    $queue = New-Object System.Collections.Queue
    $queue.Enqueue($RootProcessId)

    while ($queue.Count -gt 0) {
        $current = [int]$queue.Dequeue()
        if (-not $byParent.ContainsKey($current)) {
            continue
        }

        foreach ($child in $byParent[$current]) {
            $descendants.Add($child)
            $queue.Enqueue([int]$child.ProcessId)
        }
    }

    return @($descendants | ForEach-Object { $_ })
}

function Stop-OwnedProcessTree {
    param(
        [int]$RootProcessId,
        [int]$GraceSeconds = 5
    )

    $descendants = @(Get-OwnedProcessTree -RootProcessId $RootProcessId)
    $targets = @($descendants | Sort-Object ProcessId -Descending | ForEach-Object { [int]$_.ProcessId })
    $targets += $RootProcessId
    $terminated = New-Object System.Collections.Generic.List[int]

    foreach ($targetPid in $targets) {
        $process = Get-Process -Id $targetPid -ErrorAction SilentlyContinue
        if ($null -eq $process) {
            continue
        }

        Stop-Process -Id $targetPid -Force -ErrorAction SilentlyContinue
        $terminated.Add($targetPid)
    }

    $deadline = (Get-Date).AddSeconds($GraceSeconds)
    do {
        $remaining = @($targets | Where-Object { $null -ne (Get-Process -Id $_ -ErrorAction SilentlyContinue) })
        if ($remaining.Count -eq 0) {
            break
        }
        Start-Sleep -Milliseconds 200
    } while ((Get-Date) -lt $deadline)

    $stillRunning = @($targets | Where-Object { $null -ne (Get-Process -Id $_ -ErrorAction SilentlyContinue) })

    return [pscustomobject]@{
        terminatedPids = @($terminated)
        remainingPids = @($stillRunning)
    }
}

function Invoke-WorkerProcess {
    param(
        [string]$FilePath,
        [string[]]$ArgumentList,
        [string]$WorkingDirectory,
        [string]$LogFile,
        [int]$TimeoutSeconds
    )

    $stdoutFile = "$LogFile.stdout.tmp"
    $stderrFile = "$LogFile.stderr.tmp"
    $process = $null
    $timedOut = $false
    $treeCleanup = $null
    $startTime = Get-Date
    $stdoutTask = $null
    $stderrTask = $null

    try {
        $startInfo = [System.Diagnostics.ProcessStartInfo]::new()
        $startInfo.FileName = $FilePath
        $startInfo.WorkingDirectory = $WorkingDirectory
        $startInfo.UseShellExecute = $false
        $startInfo.RedirectStandardOutput = $true
        $startInfo.RedirectStandardError = $true
        $startInfo.CreateNoWindow = $true
        foreach ($argument in $ArgumentList) {
            [void]$startInfo.ArgumentList.Add($argument)
        }

        $process = [System.Diagnostics.Process]::new()
        $process.StartInfo = $startInfo
        [void]$process.Start()
        $stdoutTask = $process.StandardOutput.ReadToEndAsync()
        $stderrTask = $process.StandardError.ReadToEndAsync()

        $deadline = $startTime.AddSeconds($TimeoutSeconds)
        while (-not $process.HasExited) {
            if ((Get-Date) -ge $deadline) {
                $timedOut = $true
                $treeCleanup = Stop-OwnedProcessTree -RootProcessId $process.Id
                break
            }

            Start-Sleep -Milliseconds 500
            $process.Refresh()
        }

        if (-not $timedOut -and -not $process.HasExited) {
            $process.WaitForExit()
        }
    }
    catch {
        $stdout = if ($stdoutTask -and $stdoutTask.IsCompleted) { $stdoutTask.Result } elseif (Test-Path $stdoutFile) { Get-Content $stdoutFile -Raw } else { "" }
        $stderr = if ($stderrTask -and $stderrTask.IsCompleted) { $stderrTask.Result } elseif (Test-Path $stderrFile) { Get-Content $stderrFile -Raw } else { "" }
        $message = "Worker launch failed: $($_.Exception.Message)"
        if (-not [string]::IsNullOrWhiteSpace($_.ScriptStackTrace)) {
            $message = "$message`n$($_.ScriptStackTrace)"
        }
        Add-Content -Path $LogFile -Value "COMMAND:"
        Add-Content -Path $LogFile -Value "$FilePath $($ArgumentList -join ' ')"
        Add-Content -Path $LogFile -Value ""
        Add-Content -Path $LogFile -Value "WORKING DIRECTORY:"
        Add-Content -Path $LogFile -Value $WorkingDirectory
        Add-Content -Path $LogFile -Value ""
        Add-Content -Path $LogFile -Value $message
        return @{
            ExitCode = 1
            Stdout = $stdout
            Stderr = (Join-ResultText -Existing $stderr -Addition $message)
            Phase = "worker launch"
            WorkerPid = $null
            TimedOut = $false
            TimeoutSeconds = $TimeoutSeconds
            TerminatedPids = @()
            RemainingPids = @()
        }
    }

    try {
        if ($stdoutTask) {
            [void]$stdoutTask.Wait([TimeSpan]::FromSeconds(5))
        }
        if ($stderrTask) {
            [void]$stderrTask.Wait([TimeSpan]::FromSeconds(5))
        }
    }
    catch {
        Add-Content -Path $LogFile -Value "WARNING: failed to finish async output read: $($_.Exception.Message)"
    }

    $stdout = if ($stdoutTask -and $stdoutTask.IsCompleted) { $stdoutTask.Result } elseif (Test-Path $stdoutFile) { Get-Content $stdoutFile -Raw } else { "" }
    $stderr = if ($stderrTask -and $stderrTask.IsCompleted) { $stderrTask.Result } elseif (Test-Path $stderrFile) { Get-Content $stderrFile -Raw } else { "" }
    Set-Content -LiteralPath $stdoutFile -Value $stdout -Encoding UTF8 -NoNewline
    Set-Content -LiteralPath $stderrFile -Value $stderr -Encoding UTF8 -NoNewline
    $exitCode = if ($timedOut) { 124 } elseif ($null -ne $process) { $process.ExitCode } else { 1 }
    $phase = if ($timedOut) { "worker timeout" } elseif ($exitCode -eq 0) { "worker execution" } else { "worker execution" }

    Add-Content -Path $LogFile -Value "COMMAND:"
    Add-Content -Path $LogFile -Value "$FilePath $($ArgumentList -join ' ')"
    Add-Content -Path $LogFile -Value ""
    Add-Content -Path $LogFile -Value "WORKING DIRECTORY:"
    Add-Content -Path $LogFile -Value $WorkingDirectory
    Add-Content -Path $LogFile -Value ""
    Add-Content -Path $LogFile -Value "WORKER PID: $(if ($process) { $process.Id } else { '' })"
    Add-Content -Path $LogFile -Value "TIMEOUT SECONDS: $TimeoutSeconds"
    Add-Content -Path $LogFile -Value "TIMED OUT: $timedOut"
    if ($treeCleanup) {
        Add-Content -Path $LogFile -Value "TERMINATED PIDS: $($treeCleanup.terminatedPids -join ', ')"
        Add-Content -Path $LogFile -Value "REMAINING PIDS: $($treeCleanup.remainingPids -join ', ')"
    }
    Add-Content -Path $LogFile -Value ""
    Add-Content -Path $LogFile -Value "STDOUT:"
    Add-Content -Path $LogFile -Value $stdout
    Add-Content -Path $LogFile -Value ""
    Add-Content -Path $LogFile -Value "STDERR:"
    Add-Content -Path $LogFile -Value $stderr
    Add-Content -Path $LogFile -Value ""
    Add-Content -Path $LogFile -Value "EXIT CODE: $exitCode"

    return @{
        ExitCode = $exitCode
        Stdout = $stdout
        Stderr = $stderr
        Phase = $phase
        WorkerPid = if ($process) { $process.Id } else { $null }
        TimedOut = $timedOut
        TimeoutSeconds = $TimeoutSeconds
        TerminatedPids = if ($treeCleanup) { @($treeCleanup.terminatedPids) } else { @() }
        RemainingPids = if ($treeCleanup) { @($treeCleanup.remainingPids) } else { @() }
    }
}

function New-FailedResult {
    param([string]$Message)

    return @{
        ExitCode = 1
        Stdout = ""
        Stderr = $Message
    }
}

function Join-ResultText {
    param(
        [string]$Existing,
        [string]$Addition
    )

    if ([string]::IsNullOrWhiteSpace($Addition)) {
        return $Existing
    }

    if ([string]::IsNullOrWhiteSpace($Existing)) {
        return $Addition
    }

    return ($Existing.TrimEnd() + [Environment]::NewLine + $Addition)
}

function Add-ResultOutput {
    param(
        [hashtable]$Result,
        [string]$Stdout = "",
        [string]$Stderr = ""
    )

    $Result.Stdout = Join-ResultText -Existing $Result.Stdout -Addition $Stdout
    $Result.Stderr = Join-ResultText -Existing $Result.Stderr -Addition $Stderr
}

function Invoke-CodexTaskGitCommit {
    param(
        [hashtable]$Result,
        [object]$ResultContract,
        [string]$RepoPath,
        [pscustomobject]$Config,
        [string]$LogFile,
        [string]$DispatcherRoot,
        [string]$DiffPatch
    )

    Write-Step "Git status check..."
    Add-ResultOutput -Result $Result -Stdout "[dispatcher] Git status check..."
    $identity = try { (& whoami) -join [Environment]::NewLine } catch { "unknown: $($_.Exception.Message)" }
    $indexLockPath = Join-Path (Join-Path $RepoPath ".git") "index.lock"
    $indexLockExists = Test-Path -LiteralPath $indexLockPath -PathType Leaf
    Add-ResultOutput -Result $Result -Stdout "[dispatcher] Git executable: $($Config.gitExe)"
    Add-ResultOutput -Result $Result -Stdout "[dispatcher] Git working directory: $RepoPath"
    Add-ResultOutput -Result $Result -Stdout "[dispatcher] Process identity: $identity"
    Add-ResultOutput -Result $Result -Stdout "[dispatcher] Git index lock exists before Git operations: $indexLockExists"

    $statusResult = Invoke-LoggedCommand -FilePath $Config.gitExe -ArgumentList @("status", "--short") -WorkingDirectory $RepoPath -LogFile $LogFile
    Add-ResultOutput -Result $Result -Stdout $statusResult.Stdout -Stderr $statusResult.Stderr
    if ($statusResult.ExitCode -ne 0) {
        $Result.ExitCode = $statusResult.ExitCode
        $Result.Phase = "Git status"
        $ResultContract.status = "failed"
        $ResultContract.needsReview = $true
        $ResultContract.summary = "Dispatcher Git status failed."
        $ResultContract.reviewHints = @("Git status failed.")
        Add-ResultOutput -Result $Result -Stdout "[dispatcher] Git status failed."
        Add-ResultOutput -Result $Result -Stdout $statusResult.Stderr
        return
    }

    if ([string]::IsNullOrWhiteSpace($statusResult.Stdout)) {
        Write-Step "No changes detected."
        Add-ResultOutput -Result $Result -Stdout "[dispatcher] No changes detected."
        $pushDecision = Resolve-CodexTaskPushDecision -Config $Config -DispatcherRoot $DispatcherRoot -NoChanges
        Set-PushDecisionFields -ResultContract $ResultContract -Decision $pushDecision
        $ResultContract.workingTreeClean = $true
        if ($ResultContract.PSObject.Properties.Name.Contains("workerSummary") -and -not [string]::IsNullOrWhiteSpace($ResultContract.workerSummary)) {
            $ResultContract.summary = "Codex worker completed successfully. No changes detected. Worker summary: $($ResultContract.workerSummary)"
        }
        else {
            $ResultContract.summary = "Codex worker completed successfully. No changes detected."
        }
        return
    }

    $ResultContract.filesChanged = @(Get-GitStatusFiles -StatusText $statusResult.Stdout)

    $commitMessage = $ResultContract.commitMessage
    if ([string]::IsNullOrWhiteSpace($commitMessage)) {
        $Result.ExitCode = 1
        $ResultContract.status = "failed"
        $ResultContract.needsReview = $true
        $commitMessagePath = Join-Path $DispatcherRoot "inbox\codex-task.commit.txt"
        $message = "Custom Codex task commit message file is empty: $commitMessagePath."
        $ResultContract.reviewHints = @($message)
        Add-ResultOutput -Result $Result -Stdout "[dispatcher] $message" -Stderr $message
        return
    }

    Write-Step "Auto commit message: $commitMessage"
    Add-ResultOutput -Result $Result -Stdout "[dispatcher] Auto commit message: $commitMessage"

    $addResult = Invoke-LoggedCommand -FilePath $Config.gitExe -ArgumentList @("add", "-A") -WorkingDirectory $RepoPath -LogFile $LogFile
    Add-ResultOutput -Result $Result -Stdout $addResult.Stdout -Stderr $addResult.Stderr
    if ($addResult.ExitCode -ne 0) {
        $Result.ExitCode = $addResult.ExitCode
        $Result.Phase = "Git add"
        $ResultContract.status = "failed"
        $ResultContract.needsReview = $true
        $ResultContract.summary = "Dispatcher Git add failed."
        $ResultContract.reviewHints = @("Git add failed.")
        Add-ResultOutput -Result $Result -Stdout "[dispatcher] Git add failed."
        Add-ResultOutput -Result $Result -Stdout $addResult.Stderr
        return
    }

    $diffResult = Invoke-LoggedCommand -FilePath $Config.gitExe -ArgumentList @("diff", "--cached", "--binary") -WorkingDirectory $RepoPath -LogFile $LogFile
    if ($diffResult.ExitCode -ne 0) {
        $Result.ExitCode = $diffResult.ExitCode
        $Result.Phase = "Git diff"
        $ResultContract.status = "failed"
        $ResultContract.needsReview = $true
        $ResultContract.summary = "Dispatcher Git diff generation failed."
        $ResultContract.reviewHints = @("Git diff generation failed.")
        Add-ResultOutput -Result $Result -Stdout "[dispatcher] Git diff generation failed."
        Add-ResultOutput -Result $Result -Stdout $diffResult.Stderr
        return
    }

    Set-Content -LiteralPath $DiffPatch -Value $diffResult.Stdout -Encoding UTF8 -NoNewline

    $quotedCommitMessage = '"' + $commitMessage.Replace('"', '\"') + '"'
    $commitResult = Invoke-LoggedCommand -FilePath $Config.gitExe -ArgumentList @("commit", "-m", $quotedCommitMessage) -WorkingDirectory $RepoPath -LogFile $LogFile
    Add-ResultOutput -Result $Result -Stdout $commitResult.Stdout -Stderr $commitResult.Stderr
    if ($commitResult.ExitCode -ne 0) {
        $Result.ExitCode = $commitResult.ExitCode
        $Result.Phase = "Git commit"
        $ResultContract.status = "failed"
        $ResultContract.needsReview = $true
        $ResultContract.summary = "Dispatcher Git commit failed."
        $ResultContract.reviewHints = @("Git commit failed.")
        Add-ResultOutput -Result $Result -Stdout "[dispatcher] Git commit failed."
        Add-ResultOutput -Result $Result -Stdout $commitResult.Stderr
        return
    }

    $ResultContract.commit = Get-GitHeadCommit -RepoPath $RepoPath -Config $Config -LogFile $LogFile
    $ResultContract.summary = "Codex worker changes committed by dispatcher."
    Write-Step "Git commit complete."
    Add-ResultOutput -Result $Result -Stdout "[dispatcher] Git commit complete."

    $pushDecision = Resolve-CodexTaskPushDecision -Config $Config -DispatcherRoot $DispatcherRoot
    Set-PushDecisionFields -ResultContract $ResultContract -Decision $pushDecision
    Add-ResultOutput -Result $Result -Stdout "[dispatcher] Push decision: shouldPush=$($pushDecision.shouldPush); source=$($pushDecision.source); reason=$($pushDecision.reason)"

    if ($pushDecision.invalid) {
        $Result.ExitCode = 1
        $Result.Phase = "Git push decision"
        $ResultContract.status = "failed"
        $ResultContract.needsReview = $true
        $ResultContract.reviewHints = @($pushDecision.reason)
        Add-ResultOutput -Result $Result -Stdout "[dispatcher] $($pushDecision.reason)" -Stderr $pushDecision.reason
        return
    }

    if ($pushDecision.rejected) {
        $Result.ExitCode = 1
        $Result.Phase = "Git push policy"
        $ResultContract.status = "failed"
        $ResultContract.needsReview = $true
        $ResultContract.reviewHints = @($pushDecision.reason)
        Add-ResultOutput -Result $Result -Stdout "[dispatcher] $($pushDecision.reason)" -Stderr $pushDecision.reason
        return
    }

    if (-not $pushDecision.shouldPush) {
        return
    }

    Write-Step "Git push enabled."
    Add-ResultOutput -Result $Result -Stdout "[dispatcher] Git push enabled."

    $pushResult = Invoke-LoggedCommand -FilePath $Config.gitExe -ArgumentList @("push") -WorkingDirectory $RepoPath -LogFile $LogFile
    Add-ResultOutput -Result $Result -Stdout $pushResult.Stdout -Stderr $pushResult.Stderr
    if ($pushResult.ExitCode -ne 0) {
        $Result.ExitCode = $pushResult.ExitCode
        $Result.Phase = "Git push"
        $ResultContract.status = "failed"
        $ResultContract.needsReview = $true
        $ResultContract.reviewHints = @("Git push failed.")
        Add-ResultOutput -Result $Result -Stdout "[dispatcher] Git push failed."
        Add-ResultOutput -Result $Result -Stdout $pushResult.Stderr
        return
    }

    Write-Step "Git push complete."
    Add-ResultOutput -Result $Result -Stdout "[dispatcher] Git push complete."
    $ResultContract.pushed = $true
}

$projectRoot = Split-Path $PSScriptRoot -Parent
$configPath = Join-Path $PSScriptRoot "config.json"
$localConfigPath = Join-Path $PSScriptRoot "config.local.json"
$configLoaderPath = Join-Path $projectRoot "scripts\load-config.ps1"
$tasksPath = Join-Path $PSScriptRoot "tasks.json"

if (-not (Test-Path $configPath)) {
    throw "Missing config file: $configPath"
}

if (-not (Test-Path $tasksPath)) {
    throw "Missing tasks file: $tasksPath"
}

if (-not (Test-Path $configLoaderPath)) {
    throw "Missing config loader: $configLoaderPath"
}

$config = & $configLoaderPath
$localConfigLoaded = Test-Path $localConfigPath
$tasks = Get-Content $tasksPath -Raw | ConvertFrom-Json
$testGitExe = [Environment]::GetEnvironmentVariable("JJ_DISPATCHER_TEST_GIT_EXE")
if (-not [string]::IsNullOrWhiteSpace($testGitExe)) {
    $config.gitExe = $testGitExe
}
$workerTimeoutSeconds = Get-WorkerTimeoutSeconds -Config $config

if (-not $tasks.PSObject.Properties.Name.Contains($TaskName)) {
    $available = ($tasks.PSObject.Properties.Name -join ", ")
    throw "Unknown task '$TaskName'. Available tasks: $available"
}

$task = $tasks.$TaskName
$repoPath = if ($Repo) { $Repo } else { $config.defaultRepo }
$codexInboxRepoError = ""

if ($task.worker -eq "codex_inbox") {
    $repoOverridePath = Join-Path $PSScriptRoot "inbox\codex-task.repo.txt"
    if (Test-Path -LiteralPath $repoOverridePath -PathType Leaf) {
        $repoOverride = (Get-Content -LiteralPath $repoOverridePath -Raw).Trim()
        if (-not [string]::IsNullOrWhiteSpace($repoOverride)) {
            $repoPath = $repoOverride
        }
    }

    if ([string]::IsNullOrWhiteSpace($repoPath)) {
        $codexInboxRepoError = "Target repo is empty. Set defaultRepo in config or provide dispatcher/inbox/codex-task.repo.txt."
    }
    elseif (-not (Test-Path -LiteralPath $repoPath -PathType Container)) {
        $codexInboxRepoError = "Target repo path not found: $repoPath"
    }
    else {
        $gitDir = Join-Path $repoPath ".git"
        if (-not (Test-Path -LiteralPath $gitDir)) {
            $codexInboxRepoError = "Target repo is not a git repo: $repoPath"
        }
    }
}

$runContext = $null
$taskContract = $null
$resultContract = $null
$taskText = ""
$runStartedAt = $null
$workerLogsCaptured = $false

if ($task.worker -eq "codex_inbox") {
    $taskId = New-TaskId
    $runContext = New-RunContext -TaskId $taskId
    $taskText = Get-CodexTaskPrompt
    $commitMessage = Get-CodexTaskCommitMessage -DispatcherRoot $PSScriptRoot
    $resolvedRepoPath = if (Test-Path -LiteralPath $repoPath -PathType Container) { (Resolve-Path -LiteralPath $repoPath).Path } else { $repoPath }

    Set-Content -LiteralPath $runContext.StdoutLog -Value "" -Encoding UTF8 -NoNewline
    Set-Content -LiteralPath $runContext.StderrLog -Value "" -Encoding UTF8 -NoNewline
    Set-Content -LiteralPath $runContext.DiffPatch -Value "" -Encoding UTF8 -NoNewline

    $taskContract = [ordered]@{
        taskId = $taskId
        status = "created"
        executionStatus = "queued"
        createdAt = (Get-Date).ToString("o")
        startedAt = $null
        completedAt = $null
        durationMs = $null
        repo = $repoPath
        resolvedRepo = $resolvedRepoPath
        worker = "codex"
        task = $taskText
        commitMessage = $commitMessage
    }
    Write-JsonFile -Path $runContext.TaskJson -Value $taskContract
}

$logFile = New-LogFile -TaskName $TaskName

Add-Content -Path $logFile -Value "JJ AI Dispatcher Log"
Add-Content -Path $logFile -Value "Timestamp: $(Get-Date -Format o)"
Add-Content -Path $logFile -Value "Task: $TaskName"
Add-Content -Path $logFile -Value "Worker: $($task.worker)"
Add-Content -Path $logFile -Value "Description: $($task.description)"
Add-Content -Path $logFile -Value "Repo: $repoPath"
Add-Content -Path $logFile -Value "Local config override loaded: $localConfigLoaded"
Add-Content -Path $logFile -Value ""

Write-Step "Task: $TaskName"
Write-Step "Worker: $($task.worker)"
Write-Step "Local config override: $(if ($localConfigLoaded) { 'loaded' } else { 'not found' })"
Write-Step "Repo: $repoPath"
Write-Step "Log: $logFile"

$result = $null
$executionError = $null

try {
switch ($task.worker) {
    "codex" {
        $scriptPath = Join-Path $projectRoot "scripts\run-codex-task.ps1"
        $args = @(
            "-PromptFile", $task.command,
            "-Repo", "`"$repoPath`""
        )
        $pwshArgs = @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", "`"$scriptPath`"") + $args
        $result = Invoke-LoggedCommand -FilePath "pwsh" -ArgumentList $pwshArgs -WorkingDirectory $projectRoot -LogFile $logFile
    }

    "codex_inbox" {
        $runStartedAt = Get-Date
        $taskContract.status = "running"
        $taskContract.executionStatus = "running"
        $taskContract.startedAt = $runStartedAt.ToString("o")
        Write-JsonFile -Path $runContext.TaskJson -Value $taskContract

        if (-not [string]::IsNullOrWhiteSpace($codexInboxRepoError)) {
            $result = New-FailedResult -Message $codexInboxRepoError
            Add-Content -Path $logFile -Value "ERROR:"
            Add-Content -Path $logFile -Value $result.Stderr
            Add-Content -Path $logFile -Value ""
            Add-Content -Path $logFile -Value "EXIT CODE: $($result.ExitCode)"
            break
        }

        $promptPath = Join-Path $PSScriptRoot $task.command
        if (-not (Test-Path -LiteralPath $promptPath -PathType Leaf)) {
            $result = New-FailedResult -Message "Missing custom Codex task input file: $promptPath. Create it from dispatcher/inbox/codex-task.example.txt."
            Add-Content -Path $logFile -Value "ERROR:"
            Add-Content -Path $logFile -Value $result.Stderr
            Add-Content -Path $logFile -Value ""
            Add-Content -Path $logFile -Value "EXIT CODE: $($result.ExitCode)"
            break
        }

        $prompt = Get-Content -LiteralPath $promptPath -Raw
        if ([string]::IsNullOrWhiteSpace($prompt)) {
            $result = New-FailedResult -Message "Custom Codex task input file is empty: $promptPath."
            Add-Content -Path $logFile -Value "ERROR:"
            Add-Content -Path $logFile -Value $result.Stderr
            Add-Content -Path $logFile -Value ""
            Add-Content -Path $logFile -Value "EXIT CODE: $($result.ExitCode)"
            break
        }

        $escapedConfigLoaderPath = $configLoaderPath.Replace("'", "''")
        $escapedPromptPath = $promptPath.Replace("'", "''")
        $escapedRepoPath = $repoPath.Replace("'", "''")
        $runner = @"
`$ErrorActionPreference = "Stop"
`$config = & '$escapedConfigLoaderPath'
`$prompt = Get-Content -LiteralPath '$escapedPromptPath' -Raw
Write-Host "[codex-worker] Prompt: dispatcher/inbox/codex-task.txt"
Write-Host "[codex-worker] Target repo: $escapedRepoPath"
Write-Host "[codex-worker] Safety: no auto-push, no destructive actions unless explicitly requested."
Write-Host ""
`$prompt | & `$config.codexExe exec --cd '$escapedRepoPath'
exit `$LASTEXITCODE
"@
        $encodedRunner = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($runner))
        $testWorkerCommand = [Environment]::GetEnvironmentVariable("JJ_DISPATCHER_TEST_WORKER_COMMAND")
        if (-not [string]::IsNullOrWhiteSpace($testWorkerCommand)) {
            $escapedTestWorkerCommand = $testWorkerCommand.Replace("'", "''")
            $runner = @"
`$ErrorActionPreference = "Stop"
`$prompt = Get-Content -LiteralPath '$escapedPromptPath' -Raw
Write-Host "[codex-worker] Prompt: dispatcher/inbox/codex-task.txt"
Write-Host "[codex-worker] Target repo: $escapedRepoPath"
Write-Host "[codex-worker] Test worker: $escapedTestWorkerCommand"
Write-Host ""
& '$escapedTestWorkerCommand' -Repo '$escapedRepoPath' -Prompt `$prompt
exit `$LASTEXITCODE
"@
            $encodedRunner = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($runner))
        }

        $result = Invoke-WorkerProcess -FilePath "pwsh" -ArgumentList @("-NoProfile", "-ExecutionPolicy", "Bypass", "-EncodedCommand", $encodedRunner) -WorkingDirectory $projectRoot -LogFile $logFile -TimeoutSeconds $workerTimeoutSeconds
        Set-Content -LiteralPath $runContext.StdoutLog -Value $result.Stdout -Encoding UTF8 -NoNewline
        Set-Content -LiteralPath $runContext.StderrLog -Value $result.Stderr -Encoding UTF8 -NoNewline
        $workerLogsCaptured = $true
        $resultContract = Normalize-WorkerResult `
            -Result $result `
            -TaskId $runContext.TaskId `
            -RepoPath $resolvedRepoPath `
            -Worker "codex" `
            -CommitMessage $taskContract.commitMessage `
            -StdoutPath $runContext.StdoutLog `
            -StderrPath $runContext.StderrLog `
            -DiffPath $runContext.DiffPatch
        Set-WorkerReportFields -ResultContract $resultContract -WorkerResult $result

        if ($result.ExitCode -eq 0) {
            Invoke-CodexTaskGitCommit `
                -Result $result `
                -ResultContract $resultContract `
                -RepoPath $repoPath `
                -Config $config `
                -LogFile $logFile `
                -DispatcherRoot $PSScriptRoot `
                -DiffPatch $runContext.DiffPatch
        }
    }

    "openclaw" {
        $scriptPath = Join-Path $projectRoot "scripts\run-openclaw-task.ps1"
        $args = @(
            "-Action", $task.command
        )
        $pwshArgs = @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", "`"$scriptPath`"") + $args
        $result = Invoke-LoggedCommand -FilePath "pwsh" -ArgumentList $pwshArgs -WorkingDirectory $projectRoot -LogFile $logFile
    }

    "git" {
        if (-not (Test-Path $repoPath)) {
            throw "Repo path not found: $repoPath"
        }

        $gitArgs = $task.command -split " "
        $result = Invoke-LoggedCommand -FilePath $config.gitExe -ArgumentList $gitArgs -WorkingDirectory $repoPath -LogFile $logFile
    }

    "powershell" {
        $result = Invoke-LoggedCommand -FilePath "pwsh" -ArgumentList @("-NoProfile", "-Command", $task.command) -WorkingDirectory $projectRoot -LogFile $logFile
    }

    default {
        throw "Unsupported worker: $($task.worker)"
    }
}
}
catch {
    $executionError = $_
    $message = "Unexpected dispatcher failure during finalization lifecycle: $($_.Exception.Message)"
    if ($null -eq $result) {
        $result = New-FailedResult -Message $message
    }
    else {
        $result.ExitCode = 1
        Add-ResultOutput -Result $result -Stderr $message
    }
}
finally {

if ($runContext) {
    if (-not $workerLogsCaptured) {
        $stdoutValue = if ($null -ne $result) { $result.Stdout } else { "" }
        $stderrValue = if ($null -ne $result) { $result.Stderr } else { "" }
        Set-Content -LiteralPath $runContext.StdoutLog -Value $stdoutValue -Encoding UTF8 -NoNewline
        Set-Content -LiteralPath $runContext.StderrLog -Value $stderrValue -Encoding UTF8 -NoNewline
    }

    if (-not $resultContract) {
        $resultContract = Normalize-WorkerResult `
            -Result $result `
            -TaskId $runContext.TaskId `
            -RepoPath $resolvedRepoPath `
            -Worker "codex" `
            -CommitMessage $taskContract.commitMessage `
            -StdoutPath $runContext.StdoutLog `
            -StderrPath $runContext.StderrLog `
            -DiffPath $runContext.DiffPatch
        Set-WorkerReportFields -ResultContract $resultContract -WorkerResult $result
    }

    if ($result.ExitCode -ne 0) {
        $resultContract.status = "failed"
        $resultContract.executionStatus = "failed"
        $resultContract.needsReview = $true
        if ($resultContract.reviewHints.Count -eq 0) {
            $hint = if ([string]::IsNullOrWhiteSpace($result.Stderr)) { "Codex task did not complete successfully." } else { $result.Stderr.Trim() }
            $resultContract.reviewHints = @($hint)
        }
        if ($result.ContainsKey("Phase")) {
            $resultContract.summary = "Dispatcher task failed during $($result.Phase)."
        }
    }

    if (Test-Path -LiteralPath $repoPath -PathType Container) {
        try {
            $finalStatus = Invoke-LoggedCommand -FilePath $config.gitExe -ArgumentList @("status", "--short") -WorkingDirectory $repoPath -LogFile $logFile
            if ($finalStatus.ExitCode -eq 0) {
                $resultContract.workingTreeClean = [string]::IsNullOrWhiteSpace($finalStatus.Stdout)
            }
        }
        catch {
            $resultContract.needsReview = $true
            $resultContract.reviewHints = @($resultContract.reviewHints + "Final git status failed: $($_.Exception.Message)")
        }
    }

    $completedAt = Get-Date
    if (-not $runStartedAt) {
        $runStartedAt = $completedAt
    }

    # Phase 4 Visible Closed Loop Postback Trigger
    $bridgeConfig = if ($config.PSObject.Properties.Name.Contains("bridge")) { $config.bridge } else { $null }
    $bridgeEnabled = if ($null -ne $bridgeConfig -and $bridgeConfig.PSObject.Properties.Name.Contains("enabled")) { [bool]$bridgeConfig.enabled } else { $false }
    if ([Environment]::GetEnvironmentVariable("JJ_DISPATCHER_DISABLE_POSTBACK") -eq "true") {
        $bridgeEnabled = $false
    }

    $resultContract.executionStatus = $resultContract.status
    if ($bridgeEnabled) {
        $resultContract.deliveryStatus = "pending"
        $resultContract.deliveryChannel = "browser_postback"
    }
    else {
        $resultContract.deliveryStatus = "not_requested"
        $resultContract.deliveryChannel = $null
    }
    $resultContract.deliveryRequired = $false
    Set-ResultDerivedFields -ResultContract $resultContract

    $taskContract.status = $resultContract.status
    $taskContract.executionStatus = $resultContract.executionStatus
    $taskContract.completedAt = $completedAt.ToString("o")
    $taskContract.durationMs = [int64]($completedAt - $runStartedAt).TotalMilliseconds

    Write-JsonFile -Path $runContext.TaskJson -Value $taskContract
    Write-JsonFile -Path $runContext.ResultJson -Value $resultContract
    Write-RunSummary -RunContext $runContext -ResultContract $resultContract -TaskText $taskText

    if ($bridgeEnabled) {
        $port = if ($bridgeConfig.PSObject.Properties.Name.Contains("port")) { [int]$bridgeConfig.port } else { 8787 }
        $postbackUrl = "http://127.0.0.1:$port/postback"
        
        Write-Step "Triggering visible feedback postback to local bridge..."
        try {
            $summaryContent = Get-Content -LiteralPath $runContext.SummaryMd -Raw
            $mode = if ($resultContract.needsReview) { "review" } else { "auto" }
            $postbackPayload = [ordered]@{
                taskId = $runContext.TaskId
                postbackMode = $mode
                payload = [ordered]@{
                    summaryContent = $summaryContent
                }
            }
            
            $headers = @{
                "Content-Type" = "application/json"
            }
            if ($bridgeConfig.PSObject.Properties.Name.Contains("token") -and -not [string]::IsNullOrWhiteSpace($bridgeConfig.token)) {
                $headers.Add("X-Dispatcher-Token", $bridgeConfig.token)
            }
            
            $jsonBody = $postbackPayload | ConvertTo-Json -Depth 6
            $postbackResult = Invoke-RestMethod -Uri $postbackUrl -Method Post -Headers $headers -Body $jsonBody -TimeoutSec 10
            Write-Step "Postback successfully queued. Execution=$($resultContract.executionStatus); Delivery=$($resultContract.deliveryStatus); Recovery=dispatcher_latest_result or dispatcher_get_run remains available."
        }
        catch {
            $postbackError = $_.Exception.Message
            $postbackDeliveryStatus = "failed"
            if ($postbackError -match "timed out|timeout") {
                $postbackDeliveryStatus = "timeout"
            }
            elseif ($postbackError -match "actively refused|connection refused|Unable to connect|No connection|Name or service not known|nodename nor servname") {
                $postbackDeliveryStatus = "unavailable"
            }

            $resultContract.deliveryStatus = $postbackDeliveryStatus
            Set-ObjectProperty -Object $resultContract -Name "deliveryUpdatedAt" -Value (Get-Date).ToString("o")
            Set-ObjectProperty -Object $resultContract -Name "deliveryDetail" -Value $postbackError
            Set-ResultDerivedFields -ResultContract $resultContract
            Write-Step "Postback trigger warning. Execution=$($resultContract.executionStatus); Delivery=$($resultContract.deliveryStatus); Recovery=dispatcher_latest_result or dispatcher_get_run remains available. Detail: $postbackError"
            Write-JsonFile -Path $runContext.ResultJson -Value $resultContract
            Write-RunSummary -RunContext $runContext -ResultContract $resultContract -TaskText $taskText
        }
    }
}
}

Write-Host ""
Write-Host "===== JJ AI Dispatcher Summary ====="
Write-Host "Task      : $TaskName"
Write-Host "Worker    : $($task.worker)"
Write-Host "Exit Code : $($result.ExitCode)"
Write-Host "Log File  : $logFile"
if ($runContext) {
    Write-Host "Run Dir   : $($runContext.RunDir)"
    Write-Host "Result    : $($runContext.ResultJson)"
}
Write-Host ""

if ($VerboseLog) {
    Write-Host "----- STDOUT -----"
    Write-Host $result.Stdout
    Write-Host "----- STDERR -----"
    Write-Host $result.Stderr
}
else {
    $summaryText = $result.Stdout
    if ($result.ExitCode -ne 0 -and -not [string]::IsNullOrWhiteSpace($result.Stderr)) {
        $summaryText = Join-ResultText -Existing $summaryText -Addition $result.Stderr
    }
    elseif ([string]::IsNullOrWhiteSpace($summaryText)) {
        $summaryText = $result.Stderr
    }

    if (-not [string]::IsNullOrWhiteSpace($summaryText)) {
        $lines = $summaryText -split "`r?`n"
        $preview = $lines | Select-Object -First 40
        Write-Host ($preview -join [Environment]::NewLine)

        if ($lines.Count -gt 40) {
            Write-Host ""
            Write-Host "...output truncated. Use -VerboseLog or open the log file for full details."
        }
    }
}

exit $result.ExitCode
