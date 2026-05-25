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
    AllowedTaskStates = @("idle", "running")
    ActiveProcess = $null
    ActiveStartedAt = $null
}

function Write-BridgeStep {
    param([string]$Message)
    Write-Host "[bridge] $Message"
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

function Test-BridgeToken {
    param(
        [System.Net.HttpListenerRequest]$Request,
        [bool]$RequireToken
    )

    if (-not $RequireToken) {
        return $true
    }

    $token = $Request.Headers["X-Dispatcher-Token"]
    return -not [string]::IsNullOrWhiteSpace($token)
}

function Update-BridgeTaskState {
    param([pscustomobject]$State)

    if ($State.TaskState -eq "running" -and $null -ne $State.ActiveProcess -and $State.ActiveProcess.HasExited) {
        $State.TaskState = "idle"
        $State.ActiveProcess = $null
        $State.ActiveStartedAt = $null
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

function Write-DispatchInboxFiles {
    param([pscustomobject]$Dispatch)

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
        Write-DispatchInboxFiles -Dispatch $dispatch
        $process = Start-DispatcherCodexTask
        $State.TaskState = "running"
        $State.ActiveProcess = $process
        $State.ActiveStartedAt = (Get-Date).ToString("o")
    }
    catch {
        $State.TaskState = "idle"
        $State.ActiveProcess = $null
        $State.ActiveStartedAt = $null
        Write-JsonResponse -Response $response -StatusCode 500 -Body ([ordered]@{
            accepted = $false
            status = "failed"
            error = $_.Exception.Message
        })
        return
    }

    Write-JsonResponse -Response $response -StatusCode 202 -Body ([ordered]@{
        accepted = $true
        status = "running"
        worker = "codex"
        taskState = $State.TaskState
        processId = $process.Id
    })
}

function Invoke-BridgeRequest {
    param(
        [System.Net.HttpListenerContext]$Context,
        [pscustomobject]$Config,
        [pscustomobject]$State,
        [bool]$RequireToken,
        [bool]$BridgeEnabled
    )

    $request = $Context.Request
    $response = $Context.Response

    Update-BridgeTaskState -State $State

    if (-not (Test-BridgeToken -Request $request -RequireToken $RequireToken)) {
        Write-JsonResponse -Response $response -StatusCode 401 -Body ([ordered]@{
            status = "unauthorized"
            error = "X-Dispatcher-Token header required"
        })
        return
    }

    if ($request.HttpMethod -eq "POST" -and $request.Url.AbsolutePath -eq "/dispatch") {
        Invoke-DispatchRequest -Context $Context -State $State
        return
    }

    if ($request.HttpMethod -ne "GET" -or $request.Url.AbsolutePath -ne "/status") {
        Write-JsonResponse -Response $response -StatusCode 404 -Body ([ordered]@{
            status = "not_found"
            error = "Only GET /status and POST /dispatch are available."
        })
        return
    }

    Write-JsonResponse -Response $response -StatusCode 200 -Body ([ordered]@{
        status = "ok"
        dispatcherRoot = $projectRoot
        defaultWorker = [string](Get-ConfigValue -Object $Config -Name "defaultWorker" -DefaultValue "codex")
        autoPush = [bool]$Config.safety.allowAutoPush
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
