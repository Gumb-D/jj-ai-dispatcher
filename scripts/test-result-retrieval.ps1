param()

$ErrorActionPreference = "Stop"

$projectRoot = Split-Path $PSScriptRoot -Parent
$sourceDispatcherRoot = Join-Path $projectRoot "dispatcher"
$bridgePath = Join-Path $sourceDispatcherRoot "bridge.ps1"
$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("jj-dispatcher-result-retrieval-" + [guid]::NewGuid().ToString("N"))
$dispatcherRoot = Join-Path $tempRoot "dispatcher"
$runsRoot = Join-Path $dispatcherRoot "runs"

function Get-BridgeFunctionText {
    param(
        [System.Management.Automation.Language.ScriptBlockAst]$Ast,
        [string]$Name
    )

    $functionAst = $Ast.Find({
        param($Node)
        $Node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $Node.Name -eq $Name
    }, $true)

    if ($null -eq $functionAst) {
        throw "Missing bridge function $Name."
    }

    return $functionAst.Extent.Text
}

function New-TestRunArtifact {
    param(
        [string]$TaskId,
        [string]$ExecutionStatus,
        [string]$Repo,
        [switch]$OldShape,
        [string]$ResultTaskId = $TaskId
    )

    $runDir = Join-Path $runsRoot $TaskId
    New-Item -ItemType Directory -Path $runDir -Force | Out-Null

    $result = [ordered]@{
        taskId = $ResultTaskId
        status = $ExecutionStatus
        repo = $Repo
        worker = "codex"
        filesChanged = @("dispatcher/bridge.ps1")
        commit = "abc1234"
        commitMessage = "test: result retrieval"
        pushed = $false
        workingTreeClean = $true
        summary = "Fixture run $TaskId."
        logs = [ordered]@{
            stdout = "dispatcher/runs/$TaskId/codex-output.log"
            stderr = "dispatcher/runs/$TaskId/codex-error.log"
            diff = "dispatcher/runs/$TaskId/git-diff.patch"
        }
        needsReview = ($ExecutionStatus -ne "success")
        reviewHints = @()
    }

    if (-not $OldShape) {
        $result.executionStatus = $ExecutionStatus
        $result.deliveryStatus = if ($ExecutionStatus -eq "success") { "timeout" } else { "not_requested" }
        $result.deliveryChannel = if ($ExecutionStatus -eq "success") { "browser_postback" } else { $null }
        $result.deliveryRequired = $false
        $result.completedAt = "2026-06-07T00:00:00.0000000+08:00"
    }

    Set-Content -LiteralPath (Join-Path $runDir "result.json") -Value ($result | ConvertTo-Json -Depth 10) -Encoding UTF8 -NoNewline
    Set-Content -LiteralPath (Join-Path $runDir "summary.md") -Value "summary $TaskId" -Encoding UTF8 -NoNewline
    Set-Content -LiteralPath (Join-Path $runDir "task.json") -Value "{}" -Encoding UTF8 -NoNewline
}

function Assert-Equal {
    param(
        [object]$Actual,
        [object]$Expected,
        [string]$Message
    )

    if ($Actual -ne $Expected) {
        throw "$Message Expected '$Expected' but was '$Actual'."
    }
}

$tokens = $null
$errors = $null
$ast = [System.Management.Automation.Language.Parser]::ParseFile($bridgePath, [ref]$tokens, [ref]$errors)
if ($errors.Count -gt 0) {
    throw ($errors | ConvertTo-Json -Depth 4)
}

@(
    "Write-BridgeStep",
    "Write-JsonFile",
    "Set-ObjectProperty",
    "Test-SequenceIdentifier",
    "Test-Sha256Hash",
    "Test-IdempotencyKey",
    "Assert-DispatchSequenceMetadata",
    "Redact-ResultText",
    "Normalize-WorkerReportFields",
    "Normalize-PushDecisionFields",
    "Set-RunDerivedFields",
    "ConvertTo-IsoTimestampString",
    "Get-DeliveryRecoveryMessage",
    "Resolve-RepoTarget",
    "New-TaskId",
    "Test-TaskId",
    "Add-OptionalDispatchMetadata",
    "Get-RunsRoot",
    "New-AcceptedRunContext",
    "Write-FailedAcceptedRunResult",
    "Write-DispatchInboxFiles",
    "Get-RunResultPath",
    "Get-RunTaskPath",
    "Convert-TaskContractToRunResult",
    "Normalize-RunResultContract",
    "ConvertTo-ComparablePath",
    "Test-RunResultBelongsToProject",
    "Test-RunResultCompleted",
    "Read-RunResultFile",
    "Get-RunResultContract",
    "Get-LatestRunTaskId"
) | ForEach-Object { Invoke-Expression (Get-BridgeFunctionText -Ast $ast -Name $_) }

try {
    New-Item -ItemType Directory -Path $runsRoot -Force | Out-Null

    $mainOld = "20260607-010000-mainold"
    $mainTimeout = "20260607-010100-maintimeout"
    $mainRunning = "20260607-010200-mainrun"
    $tempNewer = "20260607-010300-tempnew"
    $mismatch = "20260607-010400-mismatch"
    $acceptedOnly = "20260607-010500-accepted"
    $collision = "20260607-010600-collision"
    $afterCollision = "20260607-010601-unique"

    New-TestRunArtifact -TaskId $mainOld -ExecutionStatus "success" -Repo $projectRoot -OldShape
    New-TestRunArtifact -TaskId $mainTimeout -ExecutionStatus "success" -Repo $projectRoot
    New-TestRunArtifact -TaskId $mainRunning -ExecutionStatus "running" -Repo $projectRoot
    New-TestRunArtifact -TaskId $tempNewer -ExecutionStatus "success" -Repo (Join-Path $tempRoot "lifecycle-temp-repo")
    New-TestRunArtifact -TaskId $mismatch -ExecutionStatus "success" -Repo $projectRoot -ResultTaskId "20260607-010401-other"
    New-Item -ItemType Directory -Path (Join-Path $runsRoot $acceptedOnly) -Force | Out-Null
    Set-Content -LiteralPath (Join-Path (Join-Path $runsRoot $acceptedOnly) "task.json") -Value (([ordered]@{
        taskId = $acceptedOnly
        status = "accepted"
        executionStatus = "queued"
        acceptedAt = "2026-06-07T01:05:00.0000000+08:00"
        repo = "self"
        resolvedRepo = $projectRoot
        worker = "codex"
        task = "accepted only"
        commitMessage = "test: accepted only"
        sequenceId = $null
        sequenceIndex = $null
        sequenceParentTaskId = $null
        sequenceRootTaskId = $null
    }) | ConvertTo-Json -Depth 10) -Encoding UTF8 -NoNewline

    $latest = Get-LatestRunTaskId
    Assert-Equal -Actual $latest -Expected $mainTimeout -Message "Latest completed main repo run selection failed."

    $run = Get-RunResultContract -TaskId $mainTimeout
    Assert-Equal -Actual $run.taskId -Expected $mainTimeout -Message "get-run returned wrong taskId."
    Assert-Equal -Actual $run.executionStatus -Expected "success" -Message "get-run executionStatus failed."
    Assert-Equal -Actual $run.deliveryStatus -Expected "timeout" -Message "get-run deliveryStatus failed."
    Assert-Equal -Actual $run.artifacts.result -Expected "dispatcher/runs/$mainTimeout/result.json" -Message "get-run artifact path failed."
    if ($run.validationSummary.Count -lt 1) { throw "get-run validationSummary was empty." }
    if ([string]::IsNullOrWhiteSpace($run.recovery)) { throw "get-run recovery guidance was empty." }

    $old = Get-RunResultContract -TaskId $mainOld
    Assert-Equal -Actual $old.executionStatus -Expected "success" -Message "old result executionStatus default failed."
    Assert-Equal -Actual $old.deliveryStatus -Expected "not_requested" -Message "old result deliveryStatus default failed."
    Assert-Equal -Actual $old.deliveryRequired -Expected $false -Message "old result deliveryRequired default failed."

    $restartReload = Get-RunResultContract -TaskId $mainTimeout
    Assert-Equal -Actual $restartReload.taskId -Expected $mainTimeout -Message "restart-style persisted reload returned wrong taskId."

    $acceptedReload = Get-RunResultContract -TaskId $acceptedOnly
    Assert-Equal -Actual $acceptedReload.taskId -Expected $acceptedOnly -Message "accepted get-run returned wrong taskId."
    Assert-Equal -Actual $acceptedReload.executionStatus -Expected "queued" -Message "accepted get-run executionStatus failed."
    Assert-Equal -Actual $acceptedReload.acceptedAt -Expected "2026-06-07T01:05:00.0000000+08:00" -Message "accepted get-run acceptedAt failed."
    Assert-Equal -Actual $acceptedReload.artifacts.task -Expected "dispatcher/runs/$acceptedOnly/task.json" -Message "accepted get-run task artifact path failed."
    Assert-Equal -Actual $acceptedReload.artifacts.result -Expected "dispatcher/runs/$acceptedOnly/result.json" -Message "accepted get-run result artifact path failed."

    New-Item -ItemType Directory -Path (Join-Path $runsRoot $collision) -Force | Out-Null
    $env:JJ_DISPATCHER_TEST_TASK_ID_SEQUENCE = "$collision,$afterCollision"
    $acceptedContext = New-AcceptedRunContext -Dispatch ([pscustomobject]@{
        repo = "self"
        worker = "codex"
        task = "collision allocation"
        commitMessage = "test: collision allocation"
    })
    Remove-Item Env:\JJ_DISPATCHER_TEST_TASK_ID_SEQUENCE -ErrorAction SilentlyContinue
    Assert-Equal -Actual $acceptedContext.TaskId -Expected $afterCollision -Message "duplicate taskId allocation did not regenerate safely."
    if (-not (Test-Path -LiteralPath $acceptedContext.TaskPath -PathType Leaf)) { throw "accepted allocation did not persist task.json." }
    Assert-Equal -Actual $acceptedContext.TaskRelativePath -Expected "dispatcher/runs/$afterCollision/task.json" -Message "accepted task relative path failed."
    Assert-Equal -Actual $acceptedContext.ResultRelativePath -Expected "dispatcher/runs/$afterCollision/result.json" -Message "accepted result relative path failed."

    $metadataTaskId = "20260607-010700-metadata"
    $metadataDispatch = [pscustomobject]@{
        repo = "self"
        worker = "codex"
        task = "metadata allocation"
        commitMessage = "test: metadata allocation"
        sequenceId = "seq-local-001"
        taskIndex = 3
        taskIdentityHash = "a" * 64
        payloadHash = "b" * 64
        idempotencyKey = "p4:seq-local-001:task-003:$('b' * 64)"
        pushRequested = $false
    }
    Assert-DispatchSequenceMetadata -Dispatch $metadataDispatch
    $env:JJ_DISPATCHER_TEST_TASK_ID_SEQUENCE = $metadataTaskId
    $metadataContext = New-AcceptedRunContext -Dispatch $metadataDispatch
    Remove-Item Env:\JJ_DISPATCHER_TEST_TASK_ID_SEQUENCE -ErrorAction SilentlyContinue
    Write-DispatchInboxFiles -Dispatch $metadataDispatch -RunContext $metadataContext
    $metadataTask = Get-Content -LiteralPath $metadataContext.TaskPath -Raw | ConvertFrom-Json
    Assert-Equal -Actual $metadataTask.sequenceId -Expected "seq-local-001" -Message "task.json sequenceId did not round-trip."
    Assert-Equal -Actual $metadataTask.taskIndex -Expected 3 -Message "task.json taskIndex did not round-trip."
    Assert-Equal -Actual $metadataTask.taskIdentityHash -Expected ("a" * 64) -Message "task.json taskIdentityHash did not round-trip."
    Assert-Equal -Actual $metadataTask.payloadHash -Expected ("b" * 64) -Message "task.json payloadHash did not round-trip."
    Assert-Equal -Actual $metadataTask.idempotencyKey -Expected "p4:seq-local-001:task-003:$('b' * 64)" -Message "task.json idempotencyKey did not round-trip."
    Assert-Equal -Actual $metadataTask.pushRequested -Expected $false -Message "task.json pushRequested did not round-trip."
    $pushControl = Get-Content -LiteralPath (Join-Path $dispatcherRoot "inbox\codex-task.push.txt") -Raw
    Assert-Equal -Actual $pushControl.Trim() -Expected "false" -Message "pushRequested=false did not write push opt-out transport."
    $metadataAccepted = Get-RunResultContract -TaskId $metadataTaskId
    Assert-Equal -Actual $metadataAccepted.sequenceId -Expected "seq-local-001" -Message "accepted result sequenceId did not round-trip."
    Assert-Equal -Actual $metadataAccepted.taskIndex -Expected 3 -Message "accepted result taskIndex did not round-trip."
    Assert-Equal -Actual $metadataAccepted.idempotencyKey -Expected "p4:seq-local-001:task-003:$('b' * 64)" -Message "accepted result idempotencyKey did not round-trip."
    Assert-Equal -Actual $metadataAccepted.pushRequested -Expected $false -Message "accepted result pushRequested did not round-trip."

    $invalidRejected = $false
    try {
        Assert-DispatchSequenceMetadata -Dispatch ([pscustomobject]@{
            repo = "self"
            worker = "codex"
            task = "invalid metadata"
            commitMessage = "test: invalid metadata"
            sequenceId = "../escape"
        })
    }
    catch {
        $invalidRejected = $_.Exception.Message -eq "invalid_sequence_metadata:Malformed sequenceId."
    }
    if (-not $invalidRejected) { throw "invalid sequence metadata was not rejected." }

    $invalidHashRejected = $false
    try {
        Assert-DispatchSequenceMetadata -Dispatch ([pscustomobject]@{
            repo = "self"
            worker = "codex"
            task = "invalid hash"
            commitMessage = "test: invalid hash"
            payloadHash = "A" * 64
        })
    }
    catch {
        $invalidHashRejected = $_.Exception.Message -eq "invalid_sequence_metadata:Malformed payloadHash."
    }
    if (-not $invalidHashRejected) { throw "invalid payloadHash metadata was not rejected." }

    $pushRequestedTrueId = "20260607-010701-pushtrue"
    $pushRequestedTrueDispatch = [pscustomobject]@{
        repo = "self"
        worker = "codex"
        task = "push requested transport"
        commitMessage = "test: push requested transport"
        pushRequested = $true
    }
    $env:JJ_DISPATCHER_TEST_TASK_ID_SEQUENCE = $pushRequestedTrueId
    $pushRequestedTrueContext = New-AcceptedRunContext -Dispatch $pushRequestedTrueDispatch
    Remove-Item Env:\JJ_DISPATCHER_TEST_TASK_ID_SEQUENCE -ErrorAction SilentlyContinue
    Write-DispatchInboxFiles -Dispatch $pushRequestedTrueDispatch -RunContext $pushRequestedTrueContext
    $pushControlTrue = Get-Content -LiteralPath (Join-Path $dispatcherRoot "inbox\codex-task.push.txt") -Raw
    Assert-Equal -Actual $pushControlTrue.Trim() -Expected "true" -Message "pushRequested=true did not write push request transport."

    $missingSafe = $false
    try {
        Get-RunResultContract -TaskId "20260607-999999-missing" | Out-Null
    }
    catch {
        $missingSafe = $_.Exception.Message -eq "not_found:Run result not found."
    }
    if (-not $missingSafe) { throw "missing taskId did not return the safe not_found error." }

    $mismatchRejected = $false
    try {
        Get-RunResultContract -TaskId $mismatch | Out-Null
    }
    catch {
        $mismatchRejected = $_.Exception.Message -eq "invalid_result_contract:Run result taskId does not match requested taskId."
    }
    if (-not $mismatchRejected) { throw "mismatched result taskId was not rejected." }

    [pscustomobject]@{
        latestTaskId = $latest
        getRunTaskId = $run.taskId
        getRunExecutionStatus = $run.executionStatus
        getRunDeliveryStatus = $run.deliveryStatus
        restartReloadTaskId = $restartReload.taskId
        acceptedReloadTaskId = $acceptedReload.taskId
        duplicateRegeneratedTaskId = $acceptedContext.TaskId
        metadataTaskId = $metadataAccepted.taskId
        metadataSequenceId = $metadataAccepted.sequenceId
        metadataPushRequested = $metadataAccepted.pushRequested
        oldRunDeliveryStatus = $old.deliveryStatus
        tempRepoIgnored = $tempNewer
        runningRunIgnored = $mainRunning
        missingTaskIdError = "not_found"
        mismatchError = "invalid_result_contract"
    } | ConvertTo-Json -Depth 5
}
finally {
    Remove-Item Env:\JJ_DISPATCHER_TEST_TASK_ID_SEQUENCE -ErrorAction SilentlyContinue
    if ([System.IO.Directory]::Exists($tempRoot)) {
        [System.IO.Directory]::Delete($tempRoot, $true)
    }
}
