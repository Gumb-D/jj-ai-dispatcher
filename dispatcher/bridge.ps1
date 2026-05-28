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
            Write-BridgeStep "Postback typing timeout exceeded. Reverting task state to idle and clearing queue."
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
        if ($dispatch.PSObject.Properties.Name.Contains("conversationUuid")) {
            $State.ActiveConversationUuid = [string]$dispatch.conversationUuid
        } else {
            $State.ActiveConversationUuid = ""
        }
        $State.PostbackQueue.Clear()
        $State.ActivePostback = $null
        $State.PostbackStartTicks = 0

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

function Test-TaskId {
    param([string]$TaskId)

    return -not [string]::IsNullOrWhiteSpace($TaskId) -and $TaskId -match '^[0-9]{8}-[0-9]{6}-[A-Za-z0-9]+$'
}

function Get-RunsRoot {
    return Join-Path $dispatcherRoot "runs"
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
        $resultPath = Get-RunResultPath -TaskId $TaskId
    }
    catch {
        Write-JsonResponse -Response $Response -StatusCode 400 -Body ([ordered]@{
            status = "invalid_task_id"
            error = "Malformed taskId."
        })
        return
    }

    if (-not (Test-Path -LiteralPath $resultPath -PathType Leaf)) {
        Write-JsonResponse -Response $Response -StatusCode 404 -Body ([ordered]@{
            status = "not_found"
            error = "Run result not found."
        })
        return
    }

    try {
        $result = Get-Content -LiteralPath $resultPath -Raw | ConvertFrom-Json
    }
    catch {
        Write-JsonResponse -Response $Response -StatusCode 500 -Body ([ordered]@{
            status = "invalid_result_json"
            error = "Run result JSON could not be parsed."
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
        Where-Object { Test-TaskId -TaskId $_.Name } |
        Sort-Object Name -Descending |
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
    Write-BridgeStep "Received complete confirmation for task $taskId"

    if ($null -ne $State.ActivePostback -and $State.ActivePostback.taskId -eq $taskId) {
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
