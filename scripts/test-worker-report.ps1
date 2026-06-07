param()

$ErrorActionPreference = "Stop"

$projectRoot = Split-Path $PSScriptRoot -Parent
$runPath = Join-Path $projectRoot "dispatcher\run.ps1"
$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("jj-dispatcher-worker-report-" + [guid]::NewGuid().ToString("N"))

function Get-RunFunctionText {
    param(
        [System.Management.Automation.Language.ScriptBlockAst]$Ast,
        [string]$Name
    )

    $functionAst = $Ast.Find({
        param($Node)
        $Node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $Node.Name -eq $Name
    }, $true)

    if ($null -eq $functionAst) {
        throw "Missing run function $Name."
    }

    return $functionAst.Extent.Text
}

$tokens = $null
$errors = $null
$ast = [System.Management.Automation.Language.Parser]::ParseFile($runPath, [ref]$tokens, [ref]$errors)
if ($errors.Count -gt 0) {
    throw ($errors | ConvertTo-Json -Depth 4)
}

$WorkerReportMaxLength = 12000
@(
    "ConvertTo-DispatcherRelativePath",
    "Set-ObjectProperty",
    "Redact-ResultText",
    "Join-ResultText",
    "New-WorkerReportContract",
    "Set-WorkerReportFields",
    "Get-DeliveryRecoveryMessage",
    "Set-ResultDerivedFields",
    "Normalize-WorkerResult",
    "Write-RunSummary"
) | ForEach-Object { Invoke-Expression (Get-RunFunctionText -Ast $ast -Name $_) }

try {
    New-Item -ItemType Directory -Path $tempRoot -Force | Out-Null

    $result = @{
        ExitCode = 0
        Stdout = "Substantive read-only conclusion.`nNo code changes are needed.`ntoken=local-secret-value"
        Stderr = ""
    }
    $contract = Normalize-WorkerResult `
        -Result $result `
        -TaskId "20000101-020000-report" `
        -RepoPath $projectRoot `
        -Worker "codex" `
        -CommitMessage "test: worker report" `
        -StdoutPath (Join-Path $tempRoot "codex-output.log") `
        -StderrPath (Join-Path $tempRoot "codex-error.log") `
        -DiffPath (Join-Path $tempRoot "git-diff.patch")
    Set-WorkerReportFields -ResultContract $contract -WorkerResult $result
    $contract.workingTreeClean = $true
    $contract.summary = "Codex worker completed successfully. No changes detected. Worker summary: $($contract.workerSummary)"
    Set-ResultDerivedFields -ResultContract $contract

    $runContext = [pscustomobject]@{
        SummaryMd = Join-Path $tempRoot "summary.md"
    }
    Write-RunSummary -RunContext $runContext -ResultContract $contract -TaskText "Read-only fixture"
    $summary = Get-Content -LiteralPath $runContext.SummaryMd -Raw

    if ($contract.workerSummary -ne "Substantive read-only conclusion.") { throw "workerSummary did not preserve worker conclusion." }
    if ($contract.workerReport -notmatch "No code changes are needed") { throw "workerReport did not preserve no-change analysis." }
    if ($contract.workerReport -match "local-secret-value") { throw "workerReport leaked token-like content." }
    if ($contract.workerReport -notmatch "token=\[REDACTED\]") { throw "workerReport did not redact token-like content." }
    if ($summary -notmatch "## Worker Report") { throw "summary.md missing worker report section." }
    if ($summary -notmatch "Substantive read-only conclusion") { throw "summary.md did not include worker report." }
    if ($summary -match "local-secret-value") { throw "summary.md leaked token-like content." }

    $longText = ("A" * ($WorkerReportMaxLength + 500)) + "`nsecret=do-not-persist"
    $longResult = @{
        ExitCode = 0
        Stdout = $longText
        Stderr = ""
    }
    $longContract = Normalize-WorkerResult `
        -Result $longResult `
        -TaskId "20000101-020001-long" `
        -RepoPath $projectRoot `
        -Worker "codex" `
        -CommitMessage "test: long worker report" `
        -StdoutPath (Join-Path $tempRoot "long-output.log") `
        -StderrPath (Join-Path $tempRoot "long-error.log") `
        -DiffPath (Join-Path $tempRoot "long-diff.patch")
    Set-WorkerReportFields -ResultContract $longContract -WorkerResult $longResult

    if (-not $longContract.workerReportMetadata.truncated) { throw "long worker report did not mark truncation." }
    if ($longContract.workerReport.Length -gt $WorkerReportMaxLength) { throw "long worker report exceeded max length." }
    if ($longContract.workerReportMetadata.maxLength -ne $WorkerReportMaxLength) { throw "worker report max length metadata mismatch." }

    [pscustomobject]@{
        noChangeReport = "preserved"
        redaction = "passed"
        truncation = "passed"
        maxLength = $WorkerReportMaxLength
    } | ConvertTo-Json -Depth 4
}
finally {
    if ([System.IO.Directory]::Exists($tempRoot)) {
        [System.IO.Directory]::Delete($tempRoot, $true)
    }
}
