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
        [string]$RepoPath,
        [pscustomobject]$Config,
        [string]$LogFile,
        [string]$DispatcherRoot
    )

    Write-Step "Git status check..."
    Add-ResultOutput -Result $Result -Stdout "[dispatcher] Git status check..."

    $statusResult = Invoke-LoggedCommand -FilePath $Config.gitExe -ArgumentList @("status", "--short") -WorkingDirectory $RepoPath -LogFile $LogFile
    Add-ResultOutput -Result $Result -Stdout $statusResult.Stdout -Stderr $statusResult.Stderr
    if ($statusResult.ExitCode -ne 0) {
        $Result.ExitCode = $statusResult.ExitCode
        Add-ResultOutput -Result $Result -Stdout "[dispatcher] Git status failed."
        Add-ResultOutput -Result $Result -Stdout $statusResult.Stderr
        return
    }

    if ([string]::IsNullOrWhiteSpace($statusResult.Stdout)) {
        Write-Step "No changes detected."
        Add-ResultOutput -Result $Result -Stdout "[dispatcher] No changes detected."
        return
    }

    $commitMessagePath = Join-Path $DispatcherRoot "inbox\codex-task.commit.txt"
    $commitMessage = "chore: codex task update"
    if (Test-Path -LiteralPath $commitMessagePath -PathType Leaf) {
        $commitMessage = (Get-Content -LiteralPath $commitMessagePath -Raw).Trim()
        if ([string]::IsNullOrWhiteSpace($commitMessage)) {
            $Result.ExitCode = 1
            $message = "Custom Codex task commit message file is empty: $commitMessagePath."
            Add-ResultOutput -Result $Result -Stdout "[dispatcher] $message" -Stderr $message
            return
        }
    }

    Write-Step "Auto commit message: $commitMessage"
    Add-ResultOutput -Result $Result -Stdout "[dispatcher] Auto commit message: $commitMessage"

    $addResult = Invoke-LoggedCommand -FilePath $Config.gitExe -ArgumentList @("add", "-A") -WorkingDirectory $RepoPath -LogFile $LogFile
    Add-ResultOutput -Result $Result -Stdout $addResult.Stdout -Stderr $addResult.Stderr
    if ($addResult.ExitCode -ne 0) {
        $Result.ExitCode = $addResult.ExitCode
        Add-ResultOutput -Result $Result -Stdout "[dispatcher] Git add failed."
        Add-ResultOutput -Result $Result -Stdout $addResult.Stderr
        return
    }

    $quotedCommitMessage = '"' + $commitMessage.Replace('"', '\"') + '"'
    $commitResult = Invoke-LoggedCommand -FilePath $Config.gitExe -ArgumentList @("commit", "-m", $quotedCommitMessage) -WorkingDirectory $RepoPath -LogFile $LogFile
    Add-ResultOutput -Result $Result -Stdout $commitResult.Stdout -Stderr $commitResult.Stderr
    if ($commitResult.ExitCode -ne 0) {
        $Result.ExitCode = $commitResult.ExitCode
        Add-ResultOutput -Result $Result -Stdout "[dispatcher] Git commit failed."
        Add-ResultOutput -Result $Result -Stdout $commitResult.Stderr
        return
    }

    Write-Step "Git commit complete."
    Add-ResultOutput -Result $Result -Stdout "[dispatcher] Git commit complete."
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
& `$config.codexExe exec --cd '$escapedRepoPath' `$prompt
exit `$LASTEXITCODE
"@
        $encodedRunner = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($runner))
        $result = Invoke-LoggedCommand -FilePath "pwsh" -ArgumentList @("-NoProfile", "-ExecutionPolicy", "Bypass", "-EncodedCommand", $encodedRunner) -WorkingDirectory $projectRoot -LogFile $logFile
        if ($result.ExitCode -eq 0) {
            Invoke-CodexTaskGitCommit -Result $result -RepoPath $repoPath -Config $config -LogFile $logFile -DispatcherRoot $PSScriptRoot
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

Write-Host ""
Write-Host "===== JJ AI Dispatcher Summary ====="
Write-Host "Task      : $TaskName"
Write-Host "Worker    : $($task.worker)"
Write-Host "Exit Code : $($result.ExitCode)"
Write-Host "Log File  : $logFile"
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
