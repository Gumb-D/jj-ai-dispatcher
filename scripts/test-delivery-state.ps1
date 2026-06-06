param()

$ErrorActionPreference = "Stop"

$projectRoot = Split-Path $PSScriptRoot -Parent
$sourceDispatcherRoot = Join-Path $projectRoot "dispatcher"
$bridgePath = Join-Path $sourceDispatcherRoot "bridge.ps1"
$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("jj-dispatcher-delivery-state-" + [guid]::NewGuid().ToString("N"))
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
        [string]$ExecutionStatus
    )

    $runDir = Join-Path $runsRoot $TaskId
    New-Item -ItemType Directory -Path $runDir -Force | Out-Null

    $result = [ordered]@{
        taskId = $TaskId
        status = $ExecutionStatus
        executionStatus = $ExecutionStatus
        deliveryStatus = "pending"
        deliveryChannel = "browser_postback"
        deliveryRequired = $false
        repo = $projectRoot
        worker = "codex"
        filesChanged = @()
        commit = $null
        commitMessage = "test: delivery state"
        pushed = $false
        workingTreeClean = $true
        summary = "Delivery state test."
        logs = [ordered]@{
            stdout = $null
            stderr = $null
            diff = $null
        }
        needsReview = $false
        reviewHints = @()
    }

    Set-Content -LiteralPath (Join-Path $runDir "result.json") -Value ($result | ConvertTo-Json -Depth 10) -Encoding UTF8

    $summary = @"
# Dispatcher Run Summary

Task ID: $TaskId
Status: $ExecutionStatus
Execution Status: $ExecutionStatus
Delivery Status: pending
Delivery Channel: browser_postback
Delivery Required: False

## Execution

Status: $ExecutionStatus
Top-level Status: $ExecutionStatus

## Delivery

Status: pending
Channel: browser_postback
Required: False

## Recovery

Browser postback pending. If browser delivery does not complete, retrieve the persisted result through dispatcher_latest_result or dispatcher_get_run.
"@

    Set-Content -LiteralPath (Join-Path $runDir "summary.md") -Value $summary -Encoding UTF8 -NoNewline

    return $runDir
}

function Assert-RunDelivery {
    param(
        [string]$TaskId,
        [string]$ExecutionStatus,
        [string]$DeliveryStatus
    )

    $runDir = Join-Path $runsRoot $TaskId
    $result = Get-Content -LiteralPath (Join-Path $runDir "result.json") -Raw | ConvertFrom-Json
    $summary = Get-Content -LiteralPath (Join-Path $runDir "summary.md") -Raw

    if ($result.status -ne $ExecutionStatus) { throw "$TaskId status changed to $($result.status)." }
    if ($result.executionStatus -ne $ExecutionStatus) { throw "$TaskId executionStatus changed to $($result.executionStatus)." }
    if ($result.deliveryStatus -ne $DeliveryStatus) { throw "$TaskId deliveryStatus expected $DeliveryStatus but was $($result.deliveryStatus)." }
    if ($result.deliveryRequired -ne $false) { throw "$TaskId deliveryRequired expected false but was $($result.deliveryRequired)." }
    if ($summary -notmatch "Execution Status: $ExecutionStatus") { throw "$TaskId summary missing execution status." }
    if ($summary -notmatch "Delivery Status: $DeliveryStatus") { throw "$TaskId summary missing delivery status." }
    if ($summary -notmatch "(?ms)## Delivery\s+Status: $DeliveryStatus") { throw "$TaskId delivery section missing terminal delivery status." }
    if ($summary -notmatch "## Recovery") { throw "$TaskId summary missing recovery section." }
}

function Clear-TestRunArtifact {
    param([string]$TaskId)

    $runDir = Join-Path $runsRoot $TaskId
    foreach ($name in @("result.json", "summary.md")) {
        $path = Join-Path $runDir $name
        if ([System.IO.File]::Exists($path)) {
            [System.IO.File]::Delete($path)
        }
    }
    if ([System.IO.Directory]::Exists($runDir)) {
        try {
            [System.IO.Directory]::Delete($runDir, $false)
        }
        catch {
            Write-Warning "Could not remove empty test run directory ${runDir}: $($_.Exception.Message)"
        }
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
    "Update-RunSummaryDelivery",
    "Update-RunDeliveryStatus"
) | ForEach-Object { Invoke-Expression (Get-BridgeFunctionText -Ast $ast -Name $_) }

$taskIds = @(
    "20000101-010000-delivered",
    "20000101-010001-timeout",
    "20000101-010002-unavail",
    "20000101-010003-execfail"
)

try {
    New-Item -ItemType Directory -Path $runsRoot -Force | Out-Null

    foreach ($taskId in $taskIds) {
        Clear-TestRunArtifact -TaskId $taskId
    }

    New-TestRunArtifact -TaskId $taskIds[0] -ExecutionStatus "success" | Out-Null
    Update-RunDeliveryStatus -TaskId $taskIds[0] -DeliveryStatus "delivered" | Out-Null
    Assert-RunDelivery -TaskId $taskIds[0] -ExecutionStatus "success" -DeliveryStatus "delivered"

    New-TestRunArtifact -TaskId $taskIds[1] -ExecutionStatus "success" | Out-Null
    Update-RunDeliveryStatus -TaskId $taskIds[1] -DeliveryStatus "timeout" -Detail "test timeout" | Out-Null
    Assert-RunDelivery -TaskId $taskIds[1] -ExecutionStatus "success" -DeliveryStatus "timeout"

    New-TestRunArtifact -TaskId $taskIds[2] -ExecutionStatus "success" | Out-Null
    Update-RunDeliveryStatus -TaskId $taskIds[2] -DeliveryStatus "unavailable" -Detail "test unavailable" | Out-Null
    Assert-RunDelivery -TaskId $taskIds[2] -ExecutionStatus "success" -DeliveryStatus "unavailable"

    New-TestRunArtifact -TaskId $taskIds[3] -ExecutionStatus "failed" | Out-Null
    Update-RunDeliveryStatus -TaskId $taskIds[3] -DeliveryStatus "failed" -Detail "test delivery failed" | Out-Null
    Assert-RunDelivery -TaskId $taskIds[3] -ExecutionStatus "failed" -DeliveryStatus "failed"

    [pscustomobject]@{
        delivered = $taskIds[0]
        timeout = $taskIds[1]
        unavailable = $taskIds[2]
        executionFailure = $taskIds[3]
        taskStateAfterTerminalDelivery = "idle"
    } | ConvertTo-Json -Depth 4
}
finally {
    foreach ($taskId in $taskIds) {
        Clear-TestRunArtifact -TaskId $taskId
    }
    if ([System.IO.Directory]::Exists($tempRoot)) {
        [System.IO.Directory]::Delete($tempRoot, $true)
    }
}
