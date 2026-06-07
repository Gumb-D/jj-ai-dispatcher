param(
    [Parameter(Mandatory = $false)]
    [switch]$Once
)

$ErrorActionPreference = "Stop"

$dispatcherRoot = $PSScriptRoot
$projectRoot = Split-Path $dispatcherRoot -Parent
$configLoaderPath = Join-Path $projectRoot "scripts\load-config.ps1"
$bridgeState = [pscustomobject]@{
    TaskState = "idle"
    AllowedTaskStates = @("idle", "running", "postback_pending", "postback_typing")
    ActiveProcess = $null
    ActiveStartedAt = $null
    ActiveConversationUuid = ""
    PostbackQueue = [System.Collections.ArrayList]::new()
    ActivePostback = $null
    PostbackTimeoutMs = 120000
    PostbackStartTicks = 0
}

function Write-BridgeStep {
    param([string]$Message)
    Write-Host "[bridge] $Message"
}

function Write-JsonFile {
    param(
        [string]$Path,
        [object]$Value
    )

    $json = $Value | ConvertTo-Json -Depth 10
    Set-Content -LiteralPath $Path -Value $json -Encoding UTF8
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

function Normalize-WorkerReportFields {
    param([object]$Result)

    $report = ""
    if ($Result.PSObject.Properties.Name.Contains("workerReport") -and -not [string]::IsNullOrWhiteSpace($Result.workerReport)) {
        $report = [string]$Result.workerReport
    }
    elseif ($Result.PSObject.Properties.Name.Contains("workerSummary") -and -not [string]::IsNullOrWhiteSpace($Result.workerSummary)) {
        $report = [string]$Result.workerSummary
    }

    $report = (Redact-ResultText -Text $report).Trim()
    $originalLength = $report.Length
    $truncated = $false
    if ($originalLength -gt $WorkerReportMaxLength) {
        $report = $report.Substring(0, $WorkerReportMaxLength).TrimEnd()
        $truncated = $true
    }

    $summary = ""
    if ($Result.PSObject.Properties.Name.Contains("workerSummary") -and -not [string]::IsNullOrWhiteSpace($Result.workerSummary)) {
        $summary = (Redact-ResultText -Text ([string]$Result.workerSummary)).Trim()
    }
    elseif (-not [string]::IsNullOrWhiteSpace($report)) {
        $summaryLines = @($report -split "`r?`n" | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
        if ($summaryLines.Count -gt 0) {
            $summary = [string]$summaryLines[0]
        }
    }
    if ($summary.Length -gt 1000) {
        $summary = $summary.Substring(0, 1000).TrimEnd()
    }

    $metadata = [pscustomobject][ordered]@{
        maxLength = $WorkerReportMaxLength
        originalLength = $originalLength
        persistedLength = $report.Length
        truncated = $truncated
        redacted = $true
    }

    Set-ObjectProperty -Object $Result -Name "workerSummary" -Value $summary
    Set-ObjectProperty -Object $Result -Name "workerReport" -Value $report
    Set-ObjectProperty -Object $Result -Name "workerReportMetadata" -Value $metadata
    Set-ObjectProperty -Object $Result -Name "workerReportTruncated" -Value $truncated
}

function Normalize-PushDecisionFields {
    param([object]$Result)

    $globalAllowed = if ($Result.PSObject.Properties.Name.Contains("globalAutoPushAllowed")) { [bool]$Result.globalAutoPushAllowed } else { $false }
    Set-ObjectProperty -Object $Result -Name "globalAutoPushAllowed" -Value $globalAllowed

    if (-not $Result.PSObject.Properties.Name.Contains("pushDecision") -or $null -eq $Result.pushDecision) {
        $reason = "Push decision was not recorded by this older run artifact."
        Set-ObjectProperty -Object $Result -Name "pushDecision" -Value ([pscustomobject][ordered]@{
            shouldPush = if ($Result.PSObject.Properties.Name.Contains("pushed")) { [bool]$Result.pushed } else { $false }
            source = "legacy_result"
            reason = $reason
        })
        Set-ObjectProperty -Object $Result -Name "pushDecisionReason" -Value $reason
        return
    }

    $source = if ($Result.pushDecision.PSObject.Properties.Name.Contains("source") -and -not [string]::IsNullOrWhiteSpace($Result.pushDecision.source)) { [string]$Result.pushDecision.source } else { "unknown" }
    $reason = if ($Result.pushDecision.PSObject.Properties.Name.Contains("reason") -and -not [string]::IsNullOrWhiteSpace($Result.pushDecision.reason)) { [string]$Result.pushDecision.reason } else { "Push decision reason was not recorded." }
    $shouldPush = if ($Result.pushDecision.PSObject.Properties.Name.Contains("shouldPush")) { [bool]$Result.pushDecision.shouldPush } else { $false }
    Set-ObjectProperty -Object $Result -Name "pushDecision" -Value ([pscustomobject][ordered]@{
        shouldPush = $shouldPush
        source = $source
        reason = $reason
    })
    if (-not $Result.PSObject.Properties.Name.Contains("pushDecisionReason") -or [string]::IsNullOrWhiteSpace($Result.pushDecisionReason)) {
        Set-ObjectProperty -Object $Result -Name "pushDecisionReason" -Value $reason
    }
}

function Set-RunDerivedFields {
    param([object]$Result)

    $validationItems = @()
    if ($Result.PSObject.Properties.Name.Contains("workingTreeClean")) {
        $validationItems += if ([bool]$Result.workingTreeClean) { "git status --short clean" } else { "git status --short not clean or unavailable" }
    }
    if ($Result.PSObject.Properties.Name.Contains("deliveryStatus")) {
        $validationItems += "deliveryStatus=$($Result.deliveryStatus)"
    }
    if ($Result.PSObject.Properties.Name.Contains("pushDecision") -and $null -ne $Result.pushDecision) {
        $validationItems += "pushDecision=$($Result.pushDecision.source):$($Result.pushDecision.shouldPush)"
    }
    Set-ObjectProperty -Object $Result -Name "validationSummary" -Value $validationItems

    $detail = if ($Result.PSObject.Properties.Name.Contains("deliveryDetail")) { [string]$Result.deliveryDetail } else { "" }
    Set-ObjectProperty -Object $Result -Name "recovery" -Value (Get-DeliveryRecoveryMessage -DeliveryStatus $Result.deliveryStatus -Detail $detail)
}

function ConvertTo-IsoTimestampString {
    param([object]$Value)

    if ($null -eq $Value) {
        return $null
    }

    if ($Value -is [datetime]) {
        return $Value.ToString("o")
    }

    return [string]$Value
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
        default { return "Persistent result is available through dispatcher_latest_result and dispatcher_get_run." }
    }
}

function Update-RunSummaryDelivery {
    param(
        [string]$TaskId,
        [object]$Result,
        [string]$DeliveryStatus,
        [string]$Detail = ""
    )

    $runsRoot = Get-RunsRoot
    $summaryPath = Join-Path (Join-Path $runsRoot $TaskId) "summary.md"
    if (-not (Test-Path -LiteralPath $summaryPath -PathType Leaf)) {
        return
    }

    $content = Get-Content -LiteralPath $summaryPath -Raw
    $content = $content -replace "(?m)^Execution Status: .*$", "Execution Status: $($Result.executionStatus)"
    $content = $content -replace "(?m)^Delivery Status: .*$", "Delivery Status: $DeliveryStatus"
    $content = $content -replace "(?m)^Delivery Channel: .*$", "Delivery Channel: $($Result.deliveryChannel)"
    $content = $content -replace "(?m)^Delivery Required: .*$", "Delivery Required: $($Result.deliveryRequired)"

    $content = [regex]::Replace(
        $content,
        "(?ms)(^## Delivery\r?\n\r?\nStatus: ).*?(\r?\nChannel: ).*?(\r?\nRequired: ).*?(\r?\n)",
        {
            param($Match)
            return "$($Match.Groups[1].Value)$DeliveryStatus$($Match.Groups[2].Value)$($Result.deliveryChannel)$($Match.Groups[3].Value)$($Result.deliveryRequired)$($Match.Groups[4].Value)"
        }
    )

    $validation = if ($Result.PSObject.Properties.Name.Contains("validationSummary") -and $null -ne $Result.validationSummary) {
        (@($Result.validationSummary) | ForEach-Object { "- $_" }) -join "`r`n"
    }
    else {
        "- No validation summary recorded."
    }
    $recoveryMessage = if ($Result.PSObject.Properties.Name.Contains("recovery")) { [string]$Result.recovery } else { Get-DeliveryRecoveryMessage -DeliveryStatus $DeliveryStatus -Detail $Detail }
    $recoveryBlock = "## Recovery`r`n`r`n$recoveryMessage"
    if ($content -match "(?ms)^## Recovery\r?\n\r?\n.*?(?=^## |\z)") {
        $content = [regex]::Replace($content, "(?ms)^## Recovery\r?\n\r?\n.*?(?=^## |\z)", $recoveryBlock)
    }
    else {
        $content = $content.TrimEnd() + "`r`n`r`n" + $recoveryBlock + "`r`n"
    }

    $validationBlock = "## Validation`r`n`r`n$validation"
    if ($content -match "(?ms)^## Validation\r?\n\r?\n.*?(?=^## |\z)") {
        $content = [regex]::Replace($content, "(?ms)^## Validation\r?\n\r?\n.*?(?=^## |\z)", $validationBlock)
    }
    else {
        $content = $content.TrimEnd() + "`r`n`r`n" + $validationBlock + "`r`n"
    }

    Set-Content -LiteralPath $summaryPath -Value $content -Encoding UTF8 -NoNewline
}

function Get-ConfigValue {
    param(
        [object]$Object,
        [string]$Name,
        [object]$DefaultValue
    )

    if ($null -eq $Object -or -not $Object.PSObject.Properties.Name.Contains($Name)) {
        return $DefaultValue
    }

    return $Object.$Name
}

function Get-CurrentTaskPushDecision {
    param(
        [pscustomobject]$Config,
        [string]$DispatcherRoot
    )

    $globalAllowed = [bool]$Config.safety.allowAutoPush
    $pushControlPath = Join-Path $DispatcherRoot "inbox\codex-task.push.txt"
    if (-not (Test-Path -LiteralPath $pushControlPath -PathType Leaf)) {
        if ($globalAllowed) {
            return [pscustomobject][ordered]@{
                shouldPush = $true
                source = "global_default"
                reason = "Global allowAutoPush=true and no per-task push override was provided."
            }
        }

        return [pscustomobject][ordered]@{
            shouldPush = $false
            source = "global_default"
            reason = "Global allowAutoPush=false and no per-task push request was provided."
        }
    }

    $pushControl = (Get-Content -LiteralPath $pushControlPath -Raw).Trim().ToLowerInvariant()
    if ($pushControl -in @("false", "no", "0", "off", "never")) {
        return [pscustomobject][ordered]@{
            shouldPush = $false
            source = "task_opt_out"
            reason = "Per-task push override explicitly opted out."
        }
    }

    if ($pushControl -notin @("true", "yes", "1", "on", "always")) {
        return [pscustomobject][ordered]@{
            shouldPush = $false
            source = "task_override"
            reason = "Invalid push control value in dispatcher/inbox/codex-task.push.txt. Use true/yes/1/on/always or false/no/0/off/never."
        }
    }

    if (-not $globalAllowed) {
        return [pscustomobject][ordered]@{
            shouldPush = $false
            source = "task_opt_in"
            reason = "Per-task push request was rejected because global allowAutoPush=false."
        }
    }

    return [pscustomobject][ordered]@{
        shouldPush = $true
        source = "task_opt_in"
        reason = "Per-task push override explicitly requested push and global allowAutoPush=true."
    }
}

function Write-JsonResponse {
    param(
        [System.Net.HttpListenerResponse]$Response,
        [int]$StatusCode,
        [object]$Body
    )

    $json = $Body | ConvertTo-Json -Depth 6
    $bytes = [Text.Encoding]::UTF8.GetBytes($json)
    $Response.StatusCode = $StatusCode
    $Response.ContentType = "application/json; charset=utf-8"
    $Response.ContentLength64 = $bytes.Length
    $Response.OutputStream.Write($bytes, 0, $bytes.Length)
    $Response.OutputStream.Close()
}

function Compare-TokenBytes {
    param(
        [string]$Expected,
        [string]$Actual
    )

    $expectedBytes = [Text.Encoding]::UTF8.GetBytes($Expected)
    $actualBytes = [Text.Encoding]::UTF8.GetBytes($Actual)
    $diff = $expectedBytes.Length -bxor $actualBytes.Length
    $maxLength = [Math]::Max($expectedBytes.Length, $actualBytes.Length)

    for ($i = 0; $i -lt $maxLength; $i++) {
        $expectedByte = if ($i -lt $expectedBytes.Length) { $expectedBytes[$i] } else { 0 }
        $actualByte = if ($i -lt $actualBytes.Length) { $actualBytes[$i] } else { 0 }
        $diff = $diff -bor ($expectedByte -bxor $actualByte)
    }

    return $diff -eq 0
}

function Test-BridgeToken {
    param(
        [System.Net.HttpListenerRequest]$Request,
        [bool]$RequireToken,
        [string]$ConfiguredToken
    )

    if (-not $RequireToken) {
        return [pscustomobject]@{
            Allowed = $true
            StatusCode = 200
            Status = "ok"
            Error = ""
        }
    }

    if ([string]::IsNullOrWhiteSpace($ConfiguredToken)) {
        return [pscustomobject]@{
            Allowed = $false
            StatusCode = 500
            Status = "config_error"
            Error = "Bridge token is required but not configured."
        }
    }

    $token = $Request.Headers["X-Dispatcher-Token"]
    if ([string]::IsNullOrWhiteSpace($token)) {
        return [pscustomobject]@{
            Allowed = $false
            StatusCode = 401
            Status = "unauthorized"
            Error = "X-Dispatcher-Token header required."
        }
    }

    if (-not (Compare-TokenBytes -Expected $ConfiguredToken -Actual $token)) {
        return [pscustomobject]@{
            Allowed = $false
            StatusCode = 403
            Status = "forbidden"
            Error = "X-Dispatcher-Token did not match."
        }
    }

    return [pscustomobject]@{
        Allowed = $true
        StatusCode = 200
        Status = "ok"
        Error = ""
    }
}

function Update-BridgeTaskState {
    param([pscustomobject]$State)

    if ($State.TaskState -eq "running" -and $null -ne $State.ActiveProcess -and $State.ActiveProcess.HasExited) {
        $State.TaskState = "idle"
        $State.ActiveProcess = $null
        $State.ActiveStartedAt = $null
    }

    if ($State.TaskState -eq "postback_typing" -and $State.PostbackStartTicks -gt 0) {
        $nowTicks = [System.DateTime]::Now.Ticks
        $elapsedMs = ($nowTicks - $State.PostbackStartTicks) / [System.TimeSpan]::TicksPerMillisecond
        if ($elapsedMs -gt $State.PostbackTimeoutMs) {
            $taskId = if ($null -ne $State.ActivePostback -and $State.ActivePostback.PSObject.Properties.Name.Contains("taskId")) { [string]$State.ActivePostback.taskId } else { "" }
            if (-not [string]::IsNullOrWhiteSpace($taskId)) {
                Update-RunDeliveryStatus -TaskId $taskId -DeliveryStatus "timeout" -Detail "postback_typing exceeded $($State.PostbackTimeoutMs)ms" | Out-Null
            }
            Write-BridgeStep "Postback typing timeout exceeded. Execution unchanged; delivery=timeout. Reverting task state to idle and clearing queue."
            $State.TaskState = "idle"
            $State.ActivePostback = $null
            $State.PostbackStartTicks = 0
            if ($State.PostbackQueue.Count -gt 0) {
                $State.PostbackQueue.RemoveAt(0)
            }
        }
    }
}

function Read-JsonRequestBody {
    param([System.Net.HttpListenerRequest]$Request)

    $reader = [System.IO.StreamReader]::new($Request.InputStream, $Request.ContentEncoding)
    try {
        $body = $reader.ReadToEnd()
    }
    finally {
        $reader.Close()
    }

    if ([string]::IsNullOrWhiteSpace($body)) {
        throw "Request body must be JSON."
    }

    return $body | ConvertFrom-Json
}

function Resolve-RepoTarget {
    param([string]$Value)

    if ([string]::IsNullOrWhiteSpace($Value)) {
        return ""
    }

    if ($Value -eq "self") {
        return $projectRoot
    }

    return $Value
}

function New-TaskId {
    $testTaskIds = [Environment]::GetEnvironmentVariable("JJ_DISPATCHER_TEST_TASK_ID_SEQUENCE")
    if (-not [string]::IsNullOrWhiteSpace($testTaskIds)) {
        $ids = @($testTaskIds -split "," | ForEach-Object { $_.Trim() } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
        if ($ids.Count -gt 0) {
            $next = $ids[0]
            $remaining = @($ids | Select-Object -Skip 1)
            [Environment]::SetEnvironmentVariable("JJ_DISPATCHER_TEST_TASK_ID_SEQUENCE", ($remaining -join ","))
            return $next
        }
    }

    $timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $suffix = [guid]::NewGuid().ToString("N").Substring(0, 8)
    return "$timestamp-$suffix"
}

function Get-RunsRoot {
    return Join-Path $dispatcherRoot "runs"
}

function Test-TaskId {
    param([string]$TaskId)

    return -not [string]::IsNullOrWhiteSpace($TaskId) -and $TaskId -match '^[0-9]{8}-[0-9]{6}-[A-Za-z0-9_-]+$'
}

function Test-SequenceIdentifier {
    param([string]$Value)

    return -not [string]::IsNullOrWhiteSpace($Value) -and $Value.Length -le 64 -and $Value -cmatch '^[A-Za-z0-9][A-Za-z0-9_.-]{0,63}$' -and $Value -ne "." -and $Value -ne ".." -and -not $Value.Contains("..")
}

function Test-Sha256Hash {
    param([string]$Value)

    return -not [string]::IsNullOrWhiteSpace($Value) -and $Value -cmatch '^[a-f0-9]{64}$'
}

function Test-IdempotencyKey {
    param([string]$Value)

    return -not [string]::IsNullOrWhiteSpace($Value) -and $Value.Length -le 200 -and $Value -cmatch '^[A-Za-z0-9][A-Za-z0-9_.:-]{0,199}$' -and $Value -ne "." -and $Value -ne ".." -and -not $Value.Contains("..")
}

function Assert-DispatchSequenceMetadata {
    param([pscustomobject]$Dispatch)

    if ($Dispatch.PSObject.Properties.Name.Contains("sequenceId") -and -not (Test-SequenceIdentifier -Value ([string]$Dispatch.sequenceId))) {
        throw "invalid_sequence_metadata:Malformed sequenceId."
    }
    if ($Dispatch.PSObject.Properties.Name.Contains("taskIndex")) {
        $rawTaskIndex = $Dispatch.taskIndex
        if (($rawTaskIndex -isnot [byte]) -and ($rawTaskIndex -isnot [int16]) -and ($rawTaskIndex -isnot [int]) -and ($rawTaskIndex -isnot [int64]) -and ($rawTaskIndex -isnot [double]) -and ($rawTaskIndex -isnot [decimal])) {
            throw "invalid_sequence_metadata:Malformed taskIndex."
        }
        try {
            $taskIndex = [int64]$rawTaskIndex
        }
        catch {
            throw "invalid_sequence_metadata:Malformed taskIndex."
        }
        if ($taskIndex -lt 0 -or [decimal]$taskIndex -ne [decimal]$rawTaskIndex) {
            throw "invalid_sequence_metadata:Malformed taskIndex."
        }
    }
    foreach ($name in @("taskIdentityHash", "payloadHash")) {
        if ($Dispatch.PSObject.Properties.Name.Contains($name) -and -not (Test-Sha256Hash -Value ([string]$Dispatch.$name))) {
            throw "invalid_sequence_metadata:Malformed $name."
        }
    }
    if ($Dispatch.PSObject.Properties.Name.Contains("idempotencyKey") -and -not (Test-IdempotencyKey -Value ([string]$Dispatch.idempotencyKey))) {
        throw "invalid_sequence_metadata:Malformed idempotencyKey."
    }
    if ($Dispatch.PSObject.Properties.Name.Contains("pushRequested") -and $Dispatch.pushRequested -isnot [bool]) {
        throw "invalid_sequence_metadata:Malformed pushRequested."
    }
}

function Add-OptionalDispatchMetadata {
    param(
        [System.Collections.Specialized.OrderedDictionary]$Target,
        [pscustomobject]$Dispatch
    )

    foreach ($name in @("sequenceId", "taskIndex", "taskIdentityHash", "payloadHash", "idempotencyKey", "pushRequested")) {
        if ($Dispatch.PSObject.Properties.Name.Contains($name)) {
            $Target[$name] = $Dispatch.$name
        }
    }
}

function New-AcceptedRunContext {
    param([pscustomobject]$Dispatch)

    $runsRoot = Get-RunsRoot
    if (-not (Test-Path -LiteralPath $runsRoot -PathType Container)) {
        New-Item -ItemType Directory -Path $runsRoot | Out-Null
    }

    for ($attempt = 0; $attempt -lt 10; $attempt++) {
        $taskId = New-TaskId
        if (-not (Test-TaskId -TaskId $taskId)) {
            throw "Generated malformed taskId."
        }

        $runDir = Join-Path $runsRoot $taskId
        if (Test-Path -LiteralPath $runDir) {
            Write-BridgeStep "Generated duplicate taskId $taskId; retrying allocation."
            continue
        }

        New-Item -ItemType Directory -Path $runDir -ErrorAction Stop | Out-Null
        $acceptedAt = (Get-Date).ToString("o")
        $resolvedRepo = ""
        if ($Dispatch.PSObject.Properties.Name.Contains("repo") -and -not [string]::IsNullOrWhiteSpace($Dispatch.repo)) {
            $resolvedRepo = Resolve-RepoTarget -Value $Dispatch.repo
        }

        $taskPath = Join-Path $runDir "task.json"
        $resultPath = Join-Path $runDir "result.json"
        $taskContract = [ordered]@{
            taskId = $taskId
            status = "accepted"
            executionStatus = "queued"
            acceptedAt = $acceptedAt
            createdAt = $acceptedAt
            startedAt = $null
            completedAt = $null
            durationMs = $null
            repo = if ($Dispatch.PSObject.Properties.Name.Contains("repo")) { [string]$Dispatch.repo } else { "" }
            resolvedRepo = $resolvedRepo
            worker = "codex"
            task = [string]$Dispatch.task
            commitMessage = if ($Dispatch.PSObject.Properties.Name.Contains("commitMessage")) { [string]$Dispatch.commitMessage } else { "" }
            sequenceId = $null
            sequenceIndex = $null
            sequenceParentTaskId = $null
            sequenceRootTaskId = $null
        }
        Add-OptionalDispatchMetadata -Target $taskContract -Dispatch $Dispatch
        Write-JsonFile -Path $taskPath -Value $taskContract

        return [pscustomobject]@{
            TaskId = $taskId
            AcceptedAt = $acceptedAt
            RunDir = $runDir
            TaskPath = $taskPath
            ResultPath = $resultPath
            TaskRelativePath = "dispatcher/runs/$taskId/task.json"
            ResultRelativePath = "dispatcher/runs/$taskId/result.json"
        }
    }

    throw "Unable to allocate a unique dispatcher taskId."
}

function Write-FailedAcceptedRunResult {
    param(
        [pscustomobject]$RunContext,
        [pscustomobject]$Dispatch,
        [string]$ErrorMessage
)

    $completedAt = (Get-Date).ToString("o")
    $safeErrorMessage = if ([string]::IsNullOrWhiteSpace($ErrorMessage)) { "Worker process did not start." } else { [string]$ErrorMessage }
    $taskPath = $RunContext.TaskPath
    if (Test-Path -LiteralPath $taskPath -PathType Leaf) {
        $taskContract = Get-Content -LiteralPath $taskPath -Raw | ConvertFrom-Json
        Set-ObjectProperty -Object $taskContract -Name "status" -Value "failed"
        Set-ObjectProperty -Object $taskContract -Name "executionStatus" -Value "failed"
        Set-ObjectProperty -Object $taskContract -Name "completedAt" -Value $completedAt
        Write-JsonFile -Path $taskPath -Value $taskContract
    }

    $result = [ordered]@{
        taskId = $RunContext.TaskId
        status = "failed"
        executionStatus = "failed"
        deliveryStatus = "not_requested"
        deliveryChannel = $null
        deliveryRequired = $false
        acceptedAt = $RunContext.AcceptedAt
        completedAt = $completedAt
        repo = if ($Dispatch.PSObject.Properties.Name.Contains("repo")) { Resolve-RepoTarget -Value $Dispatch.repo } else { "" }
        worker = "codex"
        filesChanged = @()
        commit = $null
        commitMessage = if ($Dispatch.PSObject.Properties.Name.Contains("commitMessage")) { [string]$Dispatch.commitMessage } else { "" }
        pushed = $false
        globalAutoPushAllowed = $false
        pushDecision = [ordered]@{
            shouldPush = $false
            source = "not_evaluated"
            reason = "Worker process did not start."
        }
        pushDecisionReason = "Worker process did not start."
        workingTreeClean = $false
        summary = "Dispatcher task failed before worker start."
        workerSummary = "Dispatcher task failed before worker start."
        workerReport = $safeErrorMessage
        workerReportMetadata = [ordered]@{
            maxLength = $WorkerReportMaxLength
            originalLength = $safeErrorMessage.Length
            persistedLength = $safeErrorMessage.Length
            truncated = $false
            redacted = $true
        }
        workerReportTruncated = $false
        logs = [ordered]@{}
        needsReview = $true
        reviewHints = @($safeErrorMessage)
        sequenceId = $null
        sequenceIndex = $null
        sequenceParentTaskId = $null
        sequenceRootTaskId = $null
    }
    Add-OptionalDispatchMetadata -Target $result -Dispatch $Dispatch
    Write-JsonFile -Path $RunContext.ResultPath -Value $result
}

function Write-DispatchInboxFiles {
    param(
        [pscustomobject]$Dispatch,
        [pscustomobject]$RunContext
    )

    $inboxDir = Join-Path $dispatcherRoot "inbox"
    if (-not (Test-Path -LiteralPath $inboxDir -PathType Container)) {
        New-Item -ItemType Directory -Path $inboxDir | Out-Null
    }

    $promptPath = Join-Path $inboxDir "codex-task.txt"
    Set-Content -LiteralPath $promptPath -Value $Dispatch.task -Encoding UTF8

    $repoPath = Join-Path $inboxDir "codex-task.repo.txt"
    if ($Dispatch.PSObject.Properties.Name.Contains("repo") -and -not [string]::IsNullOrWhiteSpace($Dispatch.repo)) {
        Set-Content -LiteralPath $repoPath -Value (Resolve-RepoTarget -Value $Dispatch.repo) -Encoding UTF8
    }
    else {
        Remove-Item -LiteralPath $repoPath -ErrorAction SilentlyContinue
    }

    $commitPath = Join-Path $inboxDir "codex-task.commit.txt"
    if ($Dispatch.PSObject.Properties.Name.Contains("commitMessage") -and -not [string]::IsNullOrWhiteSpace($Dispatch.commitMessage)) {
        Set-Content -LiteralPath $commitPath -Value $Dispatch.commitMessage.Trim() -Encoding UTF8
    }
    else {
        Remove-Item -LiteralPath $commitPath -ErrorAction SilentlyContinue
    }

    $pushPath = Join-Path $inboxDir "codex-task.push.txt"
    if ($Dispatch.PSObject.Properties.Name.Contains("pushRequested")) {
        $pushValue = if ([bool]$Dispatch.pushRequested) { "true" } else { "false" }
        Set-Content -LiteralPath $pushPath -Value $pushValue -Encoding UTF8 -NoNewline
    }

    $metadataPath = Join-Path $inboxDir "codex-task.meta.json"
    if ($null -ne $RunContext) {
        $metadata = [ordered]@{
            taskId = $RunContext.TaskId
            acceptedAt = $RunContext.AcceptedAt
            taskPath = $RunContext.TaskRelativePath
            resultPath = $RunContext.ResultRelativePath
            sequenceId = $null
            sequenceIndex = $null
            sequenceParentTaskId = $null
            sequenceRootTaskId = $null
        }
        Add-OptionalDispatchMetadata -Target $metadata -Dispatch $Dispatch
        Write-JsonFile -Path $metadataPath -Value $metadata
    }
    else {
        Remove-Item -LiteralPath $metadataPath -ErrorAction SilentlyContinue
    }
}

function Start-DispatcherCodexTask {
    $runPath = Join-Path $dispatcherRoot "run.ps1"
    $arguments = @(
        "-NoProfile",
        "-ExecutionPolicy", "Bypass",
        "-File", "`"$runPath`"",
        "codex_task"
    )

    return Start-Process `
        -FilePath "pwsh" `
        -ArgumentList $arguments `
        -WorkingDirectory $projectRoot `
        -WindowStyle Hidden `
        -PassThru
}

function Invoke-DispatchRequest {
    param(
        [System.Net.HttpListenerContext]$Context,
        [pscustomobject]$State
    )

    $request = $Context.Request
    $response = $Context.Response

    if ($State.TaskState -ne "idle") {
        Write-JsonResponse -Response $response -StatusCode 409 -Body ([ordered]@{
            accepted = $false
            status = "busy"
            taskState = $State.TaskState
            error = "A dispatcher task is already running."
        })
        return
    }

    try {
        $dispatch = Read-JsonRequestBody -Request $request
    }
    catch {
        Write-JsonResponse -Response $response -StatusCode 400 -Body ([ordered]@{
            accepted = $false
            status = "invalid_request"
            error = $_.Exception.Message
        })
        return
    }

    $worker = if ($dispatch.PSObject.Properties.Name.Contains("worker")) { [string]$dispatch.worker } else { "" }
    if ($worker -ne "codex") {
        Write-JsonResponse -Response $response -StatusCode 400 -Body ([ordered]@{
            accepted = $false
            status = "invalid_worker"
            error = "Only worker=codex is supported."
        })
        return
    }

    if (-not $dispatch.PSObject.Properties.Name.Contains("task") -or [string]::IsNullOrWhiteSpace($dispatch.task)) {
        Write-JsonResponse -Response $response -StatusCode 400 -Body ([ordered]@{
            accepted = $false
            status = "invalid_task"
            error = "Task cannot be empty."
        })
        return
    }

    if ($dispatch.PSObject.Properties.Name.Contains("commitMessage") -and [string]::IsNullOrWhiteSpace($dispatch.commitMessage)) {
        Write-JsonResponse -Response $response -StatusCode 400 -Body ([ordered]@{
            accepted = $false
            status = "invalid_commit_message"
            error = "Commit message cannot be empty if provided."
        })
        return
    }

    try {
        Assert-DispatchSequenceMetadata -Dispatch $dispatch
    }
    catch {
        Write-JsonResponse -Response $response -StatusCode 400 -Body ([ordered]@{
            accepted = $false
            status = "invalid_sequence_metadata"
            error = $_.Exception.Message
        })
        return
    }

    $acceptedRun = $null
    try {
        if ($dispatch.PSObject.Properties.Name.Contains("conversationUuid")) {
            $State.ActiveConversationUuid = [string]$dispatch.conversationUuid
        } else {
            $State.ActiveConversationUuid = ""
        }
        $State.PostbackQueue.Clear()
        $State.ActivePostback = $null
        $State.PostbackStartTicks = 0

        $acceptedRun = New-AcceptedRunContext -Dispatch $dispatch
        Write-DispatchInboxFiles -Dispatch $dispatch -RunContext $acceptedRun
        $process = Start-DispatcherCodexTask
        $State.TaskState = "running"
        $State.ActiveProcess = $process
        $State.ActiveStartedAt = (Get-Date).ToString("o")
    }
    catch {
        $State.TaskState = "idle"
        $State.ActiveProcess = $null
        $State.ActiveStartedAt = $null
        if ($null -ne $acceptedRun) {
            Write-FailedAcceptedRunResult -RunContext $acceptedRun -Dispatch $dispatch -ErrorMessage $_.Exception.Message
        }
        Write-JsonResponse -Response $response -StatusCode 500 -Body ([ordered]@{
            accepted = $false
            status = "failed"
            taskId = if ($null -ne $acceptedRun) { $acceptedRun.TaskId } else { $null }
            acceptedAt = if ($null -ne $acceptedRun) { $acceptedRun.AcceptedAt } else { $null }
            taskPath = if ($null -ne $acceptedRun) { $acceptedRun.TaskRelativePath } else { $null }
            resultPath = if ($null -ne $acceptedRun) { $acceptedRun.ResultRelativePath } else { $null }
            error = $_.Exception.Message
        })
        return
    }

    $acceptedResponse = [ordered]@{
        accepted = $true
        status = "running"
        worker = "codex"
        taskState = $State.TaskState
        processId = $process.Id
        taskId = $acceptedRun.TaskId
        acceptedAt = $acceptedRun.AcceptedAt
        taskPath = $acceptedRun.TaskRelativePath
        resultPath = $acceptedRun.ResultRelativePath
    }
    Add-OptionalDispatchMetadata -Target $acceptedResponse -Dispatch $dispatch
    Write-JsonResponse -Response $response -StatusCode 202 -Body $acceptedResponse
}

function Get-RunResultPath {
    param([string]$TaskId)

    $runsRoot = Get-RunsRoot
    $runPath = Join-Path $runsRoot $TaskId
    $resolvedRunsRoot = [System.IO.Path]::GetFullPath($runsRoot)
    $resolvedRunPath = [System.IO.Path]::GetFullPath($runPath)

    if (-not $resolvedRunPath.StartsWith($resolvedRunsRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Run path escaped dispatcher/runs."
    }

    return Join-Path $resolvedRunPath "result.json"
}

function Get-RunTaskPath {
    param([string]$TaskId)

    $runsRoot = Get-RunsRoot
    $runPath = Join-Path $runsRoot $TaskId
    $resolvedRunsRoot = [System.IO.Path]::GetFullPath($runsRoot)
    $resolvedRunPath = [System.IO.Path]::GetFullPath($runPath)

    if (-not $resolvedRunPath.StartsWith($resolvedRunsRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Run path escaped dispatcher/runs."
    }

    return Join-Path $resolvedRunPath "task.json"
}

function Convert-TaskContractToRunResult {
    param([object]$Task)

    $taskId = if ($Task.PSObject.Properties.Name.Contains("taskId")) { [string]$Task.taskId } else { "" }
    $executionStatus = if ($Task.PSObject.Properties.Name.Contains("executionStatus") -and -not [string]::IsNullOrWhiteSpace($Task.executionStatus)) { [string]$Task.executionStatus } else { "queued" }
    $acceptedAt = if ($Task.PSObject.Properties.Name.Contains("acceptedAt")) { ConvertTo-IsoTimestampString -Value $Task.acceptedAt } else { $null }

    $result = [ordered]@{
        taskId = $taskId
        status = $executionStatus
        executionStatus = $executionStatus
        deliveryStatus = "not_requested"
        deliveryChannel = $null
        deliveryRequired = $false
        acceptedAt = $acceptedAt
        repo = if ($Task.PSObject.Properties.Name.Contains("resolvedRepo") -and -not [string]::IsNullOrWhiteSpace($Task.resolvedRepo)) { [string]$Task.resolvedRepo } elseif ($Task.PSObject.Properties.Name.Contains("repo")) { [string]$Task.repo } else { "" }
        worker = if ($Task.PSObject.Properties.Name.Contains("worker")) { [string]$Task.worker } else { "codex" }
        filesChanged = @()
        commit = $null
        commitMessage = if ($Task.PSObject.Properties.Name.Contains("commitMessage")) { [string]$Task.commitMessage } else { "" }
        pushed = $false
        globalAutoPushAllowed = $false
        pushDecision = [pscustomobject][ordered]@{
            shouldPush = $false
            source = "not_evaluated"
            reason = "Run has been accepted but has not completed."
        }
        pushDecisionReason = "Run has been accepted but has not completed."
        workingTreeClean = $false
        summary = "Dispatcher task accepted and queued."
        needsReview = $false
        reviewHints = @()
        sequenceId = if ($Task.PSObject.Properties.Name.Contains("sequenceId")) { $Task.sequenceId } else { $null }
        sequenceIndex = if ($Task.PSObject.Properties.Name.Contains("sequenceIndex")) { $Task.sequenceIndex } else { $null }
        sequenceParentTaskId = if ($Task.PSObject.Properties.Name.Contains("sequenceParentTaskId")) { $Task.sequenceParentTaskId } else { $null }
        sequenceRootTaskId = if ($Task.PSObject.Properties.Name.Contains("sequenceRootTaskId")) { $Task.sequenceRootTaskId } else { $null }
    }
    foreach ($name in @("taskIndex", "taskIdentityHash", "payloadHash", "idempotencyKey", "pushRequested")) {
        if ($Task.PSObject.Properties.Name.Contains($name)) {
            $result[$name] = $Task.$name
        }
    }
    return [pscustomobject]$result
}

function Normalize-RunResultContract {
    param([object]$Result)

    if ($null -eq $Result -or -not $Result.PSObject.Properties.Name.Contains("taskId")) {
        return $Result
    }

    $executionStatuses = @("queued", "running", "success", "failed", "cancelled")
    $deliveryStatuses = @("not_requested", "pending", "delivered", "timeout", "failed", "skipped", "unavailable")

    $status = if ($Result.PSObject.Properties.Name.Contains("status")) { [string]$Result.status } else { "" }
    $executionStatus = if ($Result.PSObject.Properties.Name.Contains("executionStatus")) { [string]$Result.executionStatus } else { "" }
    if ($executionStatus -notin $executionStatuses) {
        $executionStatus = if ($status -in $executionStatuses) { $status } else { "failed" }
    }

    Set-ObjectProperty -Object $Result -Name "status" -Value $executionStatus
    Set-ObjectProperty -Object $Result -Name "executionStatus" -Value $executionStatus

    $deliveryStatus = if ($Result.PSObject.Properties.Name.Contains("deliveryStatus")) { [string]$Result.deliveryStatus } else { "" }
    if ($deliveryStatus -notin $deliveryStatuses) {
        $deliveryStatus = "not_requested"
    }
    Set-ObjectProperty -Object $Result -Name "deliveryStatus" -Value $deliveryStatus

    if (-not $Result.PSObject.Properties.Name.Contains("deliveryChannel")) {
        $Result | Add-Member -NotePropertyName "deliveryChannel" -NotePropertyValue $null
    }

    if (-not $Result.PSObject.Properties.Name.Contains("deliveryRequired")) {
        $Result | Add-Member -NotePropertyName "deliveryRequired" -NotePropertyValue $false
    }

    if (-not $Result.PSObject.Properties.Name.Contains("artifacts")) {
        $artifacts = [ordered]@{
            runDir = "dispatcher/runs/$($Result.taskId)"
            task = "dispatcher/runs/$($Result.taskId)/task.json"
            result = "dispatcher/runs/$($Result.taskId)/result.json"
            summary = "dispatcher/runs/$($Result.taskId)/summary.md"
        }

        if ($Result.PSObject.Properties.Name.Contains("logs") -and $null -ne $Result.logs) {
            if ($Result.logs.PSObject.Properties.Name.Contains("stdout") -and -not [string]::IsNullOrWhiteSpace($Result.logs.stdout)) {
                $artifacts.stdout = [string]$Result.logs.stdout
            }
            if ($Result.logs.PSObject.Properties.Name.Contains("stderr") -and -not [string]::IsNullOrWhiteSpace($Result.logs.stderr)) {
                $artifacts.stderr = [string]$Result.logs.stderr
            }
            if ($Result.logs.PSObject.Properties.Name.Contains("diff") -and -not [string]::IsNullOrWhiteSpace($Result.logs.diff)) {
                $artifacts.diff = [string]$Result.logs.diff
            }
        }

        $Result | Add-Member -NotePropertyName "artifacts" -NotePropertyValue ([pscustomobject]$artifacts)
    }

    Normalize-PushDecisionFields -Result $Result
    Normalize-WorkerReportFields -Result $Result
    Set-RunDerivedFields -Result $Result

    if (-not $Result.PSObject.Properties.Name.Contains("errors")) {
        $errors = @()
        if ($Result.PSObject.Properties.Name.Contains("error") -and -not [string]::IsNullOrWhiteSpace($Result.error)) {
            $errors += [string]$Result.error
        }
        if ($Result.PSObject.Properties.Name.Contains("reviewHints") -and $null -ne $Result.reviewHints -and $Result.executionStatus -ne "success") {
            $errors += @($Result.reviewHints | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) } | ForEach-Object { [string]$_ })
        }
        $Result | Add-Member -NotePropertyName "errors" -NotePropertyValue @($errors | Select-Object -Unique)
    }

    return $Result
}

function ConvertTo-ComparablePath {
    param([string]$PathValue)

    if ([string]::IsNullOrWhiteSpace($PathValue)) {
        return ""
    }

    if ($PathValue -eq "self") {
        return [System.IO.Path]::GetFullPath($projectRoot).TrimEnd("\", "/")
    }

    try {
        return [System.IO.Path]::GetFullPath($PathValue).TrimEnd("\", "/")
    }
    catch {
        return $PathValue.TrimEnd("\", "/")
    }
}

function Test-RunResultBelongsToProject {
    param([object]$Result)

    if ($null -eq $Result) {
        return $false
    }

    $repoValue = ""
    if ($Result.PSObject.Properties.Name.Contains("resolvedRepo") -and -not [string]::IsNullOrWhiteSpace($Result.resolvedRepo)) {
        $repoValue = [string]$Result.resolvedRepo
    }
    elseif ($Result.PSObject.Properties.Name.Contains("repo")) {
        $repoValue = [string]$Result.repo
    }

    if ([string]::IsNullOrWhiteSpace($repoValue)) {
        return $true
    }

    $expected = ConvertTo-ComparablePath -PathValue $projectRoot
    $actual = ConvertTo-ComparablePath -PathValue $repoValue
    return [string]::Equals($actual, $expected, [System.StringComparison]::OrdinalIgnoreCase)
}

function Test-RunResultCompleted {
    param([object]$Result)

    if ($null -eq $Result) {
        return $false
    }

    $normalized = Normalize-RunResultContract -Result $Result
    return ([string]$normalized.executionStatus) -in @("success", "failed", "cancelled")
}

function Read-RunResultFile {
    param([string]$ResultPath)

    try {
        return Get-Content -LiteralPath $ResultPath -Raw | ConvertFrom-Json
    }
    catch {
        return $null
    }
}

function Get-RunResultContract {
    param([string]$TaskId)

    if (-not (Test-TaskId -TaskId $TaskId)) {
        throw "invalid_task_id:Malformed taskId."
    }

    try {
        $resultPath = Get-RunResultPath -TaskId $TaskId
    }
    catch {
        throw "invalid_task_id:Malformed taskId."
    }

    if (-not (Test-Path -LiteralPath $resultPath -PathType Leaf)) {
        $taskPath = Get-RunTaskPath -TaskId $TaskId
        if (-not (Test-Path -LiteralPath $taskPath -PathType Leaf)) {
            throw "not_found:Run result not found."
        }

        try {
            $task = Get-Content -LiteralPath $taskPath -Raw | ConvertFrom-Json
        }
        catch {
            throw "invalid_result_json:Run task JSON could not be parsed."
        }

        if ($task.PSObject.Properties.Name.Contains("taskId") -and [string]$task.taskId -ne $TaskId) {
            throw "invalid_result_contract:Run taskId does not match requested taskId."
        }

        return Normalize-RunResultContract -Result (Convert-TaskContractToRunResult -Task $task)
    }

    try {
        $result = Get-Content -LiteralPath $resultPath -Raw | ConvertFrom-Json
    }
    catch {
        throw "invalid_result_json:Run result JSON could not be parsed."
    }

    if ($result.PSObject.Properties.Name.Contains("taskId") -and [string]$result.taskId -ne $TaskId) {
        throw "invalid_result_contract:Run result taskId does not match requested taskId."
    }

    return Normalize-RunResultContract -Result $result
}

function Update-RunDeliveryStatus {
    param(
        [string]$TaskId,
        [string]$DeliveryStatus,
        [string]$Detail = ""
    )

    $deliveryStatuses = @("not_requested", "pending", "delivered", "timeout", "failed", "skipped", "unavailable")
    if ($DeliveryStatus -notin $deliveryStatuses) {
        throw "Invalid deliveryStatus '$DeliveryStatus'."
    }

    $resultPath = Get-RunResultPath -TaskId $TaskId
    if (-not (Test-Path -LiteralPath $resultPath -PathType Leaf)) {
        Write-BridgeStep "Delivery update skipped for task $TaskId because result.json is unavailable."
        return $null
    }

    $result = Get-Content -LiteralPath $resultPath -Raw | ConvertFrom-Json
    $result = Normalize-RunResultContract -Result $result
    $previousExecutionStatus = [string]$result.executionStatus
    $previousStatus = [string]$result.status

    $result.deliveryStatus = $DeliveryStatus
    if ($DeliveryStatus -eq "not_requested" -or $DeliveryStatus -eq "skipped") {
        $result.deliveryChannel = $null
    }
    else {
        $result.deliveryChannel = "browser_postback"
    }
    $result.deliveryRequired = $false

    $now = (Get-Date).ToString("o")
    if (-not $result.PSObject.Properties.Name.Contains("deliveryUpdatedAt")) {
        $result | Add-Member -NotePropertyName "deliveryUpdatedAt" -NotePropertyValue $now
    }
    else {
        $result.deliveryUpdatedAt = $now
    }

    if (-not [string]::IsNullOrWhiteSpace($Detail)) {
        if (-not $result.PSObject.Properties.Name.Contains("deliveryDetail")) {
            $result | Add-Member -NotePropertyName "deliveryDetail" -NotePropertyValue $Detail
        }
        else {
            $result.deliveryDetail = $Detail
        }
    }
    Set-RunDerivedFields -Result $result

    if ($result.status -ne $previousStatus -or $result.executionStatus -ne $previousExecutionStatus) {
        throw "Delivery update attempted to alter execution status for task $TaskId."
    }

    Write-JsonFile -Path $resultPath -Value $result
    Update-RunSummaryDelivery -TaskId $TaskId -Result $result -DeliveryStatus $DeliveryStatus -Detail $Detail
    Write-BridgeStep "Delivery update for task ${TaskId}: Execution=$($result.executionStatus); Delivery=$DeliveryStatus; Recovery=$(Get-DeliveryRecoveryMessage -DeliveryStatus $DeliveryStatus -Detail $Detail)"

    return $result
}

function Read-RunResult {
    param(
        [System.Net.HttpListenerResponse]$Response,
        [string]$TaskId
    )

    if (-not (Test-TaskId -TaskId $TaskId)) {
        Write-JsonResponse -Response $Response -StatusCode 400 -Body ([ordered]@{
            status = "invalid_task_id"
            error = "Malformed taskId."
        })
        return
    }

    try {
        $result = Get-RunResultContract -TaskId $TaskId
    }
    catch {
        $message = $_.Exception.Message
        $parts = $message -split ":", 2
        $status = if ($parts.Count -eq 2) { $parts[0] } else { "invalid_result_json" }
        $error = if ($parts.Count -eq 2) { $parts[1] } else { "Run result JSON could not be parsed." }
        $statusCode = switch ($status) {
            "invalid_task_id" { 400 }
            "not_found" { 404 }
            default { 500 }
        }
        Write-JsonResponse -Response $Response -StatusCode $statusCode -Body ([ordered]@{
            status = $status
            error = $error
        })
        return
    }

    Write-JsonResponse -Response $Response -StatusCode 200 -Body $result
}

function Get-LatestRunTaskId {
    $runsRoot = Get-RunsRoot
    if (-not (Test-Path -LiteralPath $runsRoot -PathType Container)) {
        return $null
    }

    $latest = Get-ChildItem -LiteralPath $runsRoot -Directory |
        Sort-Object Name -Descending |
        Where-Object {
            if (-not (Test-TaskId -TaskId $_.Name)) {
                return $false
            }

            $resultPath = Join-Path $_.FullName "result.json"
            if (-not (Test-Path -LiteralPath $resultPath -PathType Leaf)) {
                return $false
            }

            $result = Read-RunResultFile -ResultPath $resultPath
            if ($null -eq $result) {
                return $false
            }

            if ($result.PSObject.Properties.Name.Contains("taskId") -and [string]$result.taskId -ne $_.Name) {
                return $false
            }

            return (Test-RunResultCompleted -Result $result) -and (Test-RunResultBelongsToProject -Result $result)
        } |
        Select-Object -First 1

    if ($null -eq $latest) {
        return $null
    }

    return $latest.Name
}

function Invoke-RunResultRequest {
    param([System.Net.HttpListenerContext]$Context)

    $request = $Context.Request
    $response = $Context.Response
    $path = $request.Url.AbsolutePath.TrimEnd("/")

    if ($request.HttpMethod -ne "GET") {
        Write-JsonResponse -Response $response -StatusCode 404 -Body ([ordered]@{
            status = "not_found"
            error = "Run result endpoint not found."
        })
        return
    }

    if ($path -eq "/runs/latest") {
        $taskId = Get-LatestRunTaskId
        if ([string]::IsNullOrWhiteSpace($taskId)) {
            Write-JsonResponse -Response $response -StatusCode 404 -Body ([ordered]@{
                status = "not_found"
                error = "No run results found."
            })
            return
        }

        Read-RunResult -Response $response -TaskId $taskId
        return
    }

    if ($path -eq "/runs") {
        Write-JsonResponse -Response $response -StatusCode 404 -Body ([ordered]@{
            status = "not_found"
            error = "Missing taskId."
        })
        return
    }

    $prefix = "/runs/"
    if ($path.StartsWith($prefix, [System.StringComparison]::OrdinalIgnoreCase)) {
        $taskId = $path.Substring($prefix.Length)
        Read-RunResult -Response $response -TaskId $taskId
        return
    }

    Write-JsonResponse -Response $response -StatusCode 404 -Body ([ordered]@{
        status = "not_found"
        error = "Run result endpoint not found."
    })
}

function Invoke-PostbackRequest {
    param(
        [System.Net.HttpListenerContext]$Context,
        [pscustomobject]$State
    )

    $request = $Context.Request
    $response = $Context.Response

    try {
        $postback = Read-JsonRequestBody -Request $request
    }
    catch {
        Write-JsonResponse -Response $response -StatusCode 400 -Body ([ordered]@{
            success = $false
            error = "Invalid JSON payload: $($_.Exception.Message)"
        })
        return
    }

    if (-not $postback.PSObject.Properties.Name.Contains("taskId") -or [string]::IsNullOrWhiteSpace($postback.taskId)) {
        Write-JsonResponse -Response $response -StatusCode 400 -Body ([ordered]@{
            success = $false
            error = "Missing taskId."
        })
        return
    }

    if (-not $postback.PSObject.Properties.Name.Contains("payload") -or $null -eq $postback.payload -or -not $postback.payload.PSObject.Properties.Name.Contains("summaryContent")) {
        Write-JsonResponse -Response $response -StatusCode 400 -Body ([ordered]@{
            success = $false
            error = "Missing payload.summaryContent."
        })
        return
    }

    # Extract conversationUuid fallback
    $uuid = ""
    if ($postback.PSObject.Properties.Name.Contains("conversationUuid") -and -not [string]::IsNullOrWhiteSpace($postback.conversationUuid)) {
        $uuid = [string]$postback.conversationUuid
    } else {
        $uuid = $State.ActiveConversationUuid
    }

    $mode = "review"
    if ($postback.PSObject.Properties.Name.Contains("postbackMode") -and -not [string]::IsNullOrWhiteSpace($postback.postbackMode)) {
        $mode = [string]$postback.postbackMode
    }

    $task = [pscustomobject]@{
        taskId = [string]$postback.taskId
        conversationUuid = $uuid
        postbackMode = $mode
        contentToType = [string]$postback.payload.summaryContent
    }

    # Add to queue and transition state
    [void]$State.PostbackQueue.Add($task)
    $State.TaskState = "postback_pending"
    Update-RunDeliveryStatus -TaskId $task.taskId -DeliveryStatus "pending" | Out-Null

    Write-BridgeStep "Accepted postback for task $($task.taskId) in mode $($task.postbackMode). Queue size: $($State.PostbackQueue.Count)"

    Write-JsonResponse -Response $response -StatusCode 202 -Body ([ordered]@{
        success = $true
        message = "Postback accepted and queued."
        taskId = $task.taskId
        taskState = $State.TaskState
    })
}

function Invoke-PostbackPendingRequest {
    param(
        [System.Net.HttpListenerContext]$Context,
        [pscustomobject]$State
    )

    $request = $Context.Request
    $response = $Context.Response

    if ($State.PostbackQueue.Count -gt 0) {
        if ($State.TaskState -eq "postback_typing") {
            Write-JsonResponse -Response $response -StatusCode 200 -Body ([ordered]@{
                hasPending = $false
                task = $null
            })
            return
        }

        $task = $State.PostbackQueue[0]
        $State.TaskState = "postback_typing"
        $State.ActivePostback = $task
        $State.PostbackStartTicks = [System.DateTime]::Now.Ticks

        Write-BridgeStep "Serving pending postback task $($task.taskId) to extension. State updated to postback_typing."

        Write-JsonResponse -Response $response -StatusCode 200 -Body ([ordered]@{
            hasPending = $true
            task = $task
        })
    } else {
        Write-JsonResponse -Response $response -StatusCode 200 -Body ([ordered]@{
            hasPending = $false
            task = $null
        })
    }
}

function Invoke-PostbackCompleteRequest {
    param(
        [System.Net.HttpListenerContext]$Context,
        [pscustomobject]$State
    )

    $request = $Context.Request
    $response = $Context.Response

    try {
        $body = Read-JsonRequestBody -Request $request
    }
    catch {
        Write-JsonResponse -Response $response -StatusCode 400 -Body ([ordered]@{
            success = $false
            error = "Invalid JSON payload: $($_.Exception.Message)"
        })
        return
    }

    if (-not $body.PSObject.Properties.Name.Contains("taskId") -or [string]::IsNullOrWhiteSpace($body.taskId)) {
        Write-JsonResponse -Response $response -StatusCode 400 -Body ([ordered]@{
            success = $false
            error = "Missing taskId."
        })
        return
    }

    $taskId = [string]$body.taskId
    $deliveryStatus = "delivered"
    $allowedTerminalDeliveryStatuses = @("delivered", "timeout", "failed", "skipped", "unavailable")
    if ($body.PSObject.Properties.Name.Contains("deliveryStatus") -and ([string]$body.deliveryStatus) -in $allowedTerminalDeliveryStatuses) {
        $deliveryStatus = [string]$body.deliveryStatus
    }
    elseif ($body.PSObject.Properties.Name.Contains("success") -and $body.success -eq $false) {
        $deliveryStatus = "failed"
    }
    elseif ($body.PSObject.Properties.Name.Contains("status") -and ([string]$body.status) -in $allowedTerminalDeliveryStatuses) {
        $deliveryStatus = [string]$body.status
    }

    $detail = ""
    if ($body.PSObject.Properties.Name.Contains("error") -and -not [string]::IsNullOrWhiteSpace($body.error)) {
        $detail = [string]$body.error
    }
    elseif ($body.PSObject.Properties.Name.Contains("message") -and -not [string]::IsNullOrWhiteSpace($body.message)) {
        $detail = [string]$body.message
    }

    Write-BridgeStep "Received complete confirmation for task $taskId with delivery=$deliveryStatus"

    if ($null -ne $State.ActivePostback -and $State.ActivePostback.taskId -eq $taskId) {
        Update-RunDeliveryStatus -TaskId $taskId -DeliveryStatus $deliveryStatus -Detail $detail | Out-Null
        $State.TaskState = "idle"
        $State.ActivePostback = $null
        $State.PostbackStartTicks = 0
        if ($State.PostbackQueue.Count -gt 0) {
            $State.PostbackQueue.RemoveAt(0)
        }
        Write-BridgeStep "Acknowledged completion of $taskId. State reset to idle. Queue size: $($State.PostbackQueue.Count)"
        
        Write-JsonResponse -Response $response -StatusCode 200 -Body ([ordered]@{
            success = $true
            message = "Task completion acknowledged."
            deliveryStatus = $deliveryStatus
            taskState = $State.TaskState
        })
    } else {
        # Silent success to keep extension idempotent
        Write-JsonResponse -Response $response -StatusCode 200 -Body ([ordered]@{
            success = $true
            message = "Task already resolved or mismatched."
        })
    }
}

function Invoke-BridgeRequest {
    param(
        [System.Net.HttpListenerContext]$Context,
        [pscustomobject]$Config,
        [pscustomobject]$State,
        [bool]$RequireToken,
        [string]$ConfiguredToken,
        [bool]$BridgeEnabled
    )

    $request = $Context.Request
    $response = $Context.Response

    Update-BridgeTaskState -State $State

    $tokenResult = Test-BridgeToken -Request $request -RequireToken $RequireToken -ConfiguredToken $ConfiguredToken
    if (-not $tokenResult.Allowed) {
        Write-JsonResponse -Response $response -StatusCode $tokenResult.StatusCode -Body ([ordered]@{
            status = $tokenResult.Status
            error = $tokenResult.Error
        })
        return
    }

    if ($request.HttpMethod -eq "POST" -and $request.Url.AbsolutePath -eq "/dispatch") {
        Invoke-DispatchRequest -Context $Context -State $State
        return
    }

    if ($request.HttpMethod -eq "POST" -and $request.Url.AbsolutePath -eq "/postback") {
        Invoke-PostbackRequest -Context $Context -State $State
        return
    }

    if ($request.HttpMethod -eq "GET" -and $request.Url.AbsolutePath -eq "/postback/pending") {
        Invoke-PostbackPendingRequest -Context $Context -State $State
        return
    }

    if ($request.HttpMethod -eq "POST" -and $request.Url.AbsolutePath -eq "/postback/complete") {
        Invoke-PostbackCompleteRequest -Context $Context -State $State
        return
    }

    if ($request.Url.AbsolutePath -eq "/runs" -or $request.Url.AbsolutePath.StartsWith("/runs/", [System.StringComparison]::OrdinalIgnoreCase)) {
        Invoke-RunResultRequest -Context $Context
        return
    }

    if ($request.HttpMethod -ne "GET" -or $request.Url.AbsolutePath -ne "/status") {
        Write-JsonResponse -Response $response -StatusCode 404 -Body ([ordered]@{
            status = "not_found"
            error = "Only GET /status, POST /dispatch, GET /runs/latest, GET /runs/{taskId}, and /postback endpoints are available."
        })
        return
    }

    $globalAutoPushAllowed = [bool]$Config.safety.allowAutoPush
    $currentTaskPushDecision = Get-CurrentTaskPushDecision -Config $Config -DispatcherRoot $dispatcherRoot

    Write-JsonResponse -Response $response -StatusCode 200 -Body ([ordered]@{
        status = "ok"
        dispatcherRoot = $projectRoot
        defaultWorker = [string](Get-ConfigValue -Object $Config -Name "defaultWorker" -DefaultValue "codex")
        autoPush = $globalAutoPushAllowed
        globalAutoPushAllowed = $globalAutoPushAllowed
        currentTaskPushDecision = $currentTaskPushDecision
        currentTaskPushDecisionReason = [string]$currentTaskPushDecision.reason
        bridgeEnabled = $BridgeEnabled
        taskState = $State.TaskState
    })
}

if (-not (Test-Path -LiteralPath $configLoaderPath -PathType Leaf)) {
    throw "Missing config loader: $configLoaderPath"
}

$config = & $configLoaderPath
$bridgeConfig = Get-ConfigValue -Object $config -Name "bridge" -DefaultValue ([pscustomobject]@{})
$bridgeEnabled = [bool](Get-ConfigValue -Object $bridgeConfig -Name "enabled" -DefaultValue $false)
$hostName = [string](Get-ConfigValue -Object $bridgeConfig -Name "host" -DefaultValue "127.0.0.1")
$port = [int](Get-ConfigValue -Object $bridgeConfig -Name "port" -DefaultValue 8787)
$requireToken = [bool](Get-ConfigValue -Object $bridgeConfig -Name "requireToken" -DefaultValue $true)
$configuredToken = [string](Get-ConfigValue -Object $bridgeConfig -Name "token" -DefaultValue "")

if (-not $bridgeEnabled) {
    Write-BridgeStep "Bridge disabled by config. Server not started."
    exit 0
}

if ($hostName -ne "127.0.0.1") {
    throw "Local bridge skeleton only supports host 127.0.0.1."
}

$listener = [System.Net.HttpListener]::new()
$prefix = "http://${hostName}:$port/"
$listener.Prefixes.Add($prefix)

try {
    $listener.Start()
    Write-BridgeStep "Listening on $prefix"
    Write-BridgeStep "Task state: $($bridgeState.TaskState)"

    do {
        $context = $listener.GetContext()
        Invoke-BridgeRequest `
            -Context $context `
            -Config $config `
            -State $bridgeState `
            -RequireToken $requireToken `
            -ConfiguredToken $configuredToken `
            -BridgeEnabled $bridgeEnabled
    } while (-not $Once)
}
finally {
    if ($listener.IsListening) {
        $listener.Stop()
    }

    $listener.Close()
    Write-BridgeStep "Stopped."
}
