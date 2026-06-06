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
    "Get-DeliveryRecoveryMessage",
    "Test-TaskId",
    "Get-RunsRoot",
    "Get-RunResultPath",
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

    New-TestRunArtifact -TaskId $mainOld -ExecutionStatus "success" -Repo $projectRoot -OldShape
    New-TestRunArtifact -TaskId $mainTimeout -ExecutionStatus "success" -Repo $projectRoot
    New-TestRunArtifact -TaskId $mainRunning -ExecutionStatus "running" -Repo $projectRoot
    New-TestRunArtifact -TaskId $tempNewer -ExecutionStatus "success" -Repo (Join-Path $tempRoot "lifecycle-temp-repo")
    New-TestRunArtifact -TaskId $mismatch -ExecutionStatus "success" -Repo $projectRoot -ResultTaskId "20260607-010401-other"

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
        oldRunDeliveryStatus = $old.deliveryStatus
        tempRepoIgnored = $tempNewer
        runningRunIgnored = $mainRunning
        missingTaskIdError = "not_found"
        mismatchError = "invalid_result_contract"
    } | ConvertTo-Json -Depth 5
}
finally {
    if ([System.IO.Directory]::Exists($tempRoot)) {
        [System.IO.Directory]::Delete($tempRoot, $true)
    }
}
