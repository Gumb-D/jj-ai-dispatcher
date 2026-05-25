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

    if (-not (Test-BridgeToken -Request $request -RequireToken $RequireToken)) {
        Write-JsonResponse -Response $response -StatusCode 401 -Body ([ordered]@{
            status = "unauthorized"
            error = "X-Dispatcher-Token header required"
        })
        return
    }

    if ($request.HttpMethod -ne "GET" -or $request.Url.AbsolutePath -ne "/status") {
        Write-JsonResponse -Response $response -StatusCode 404 -Body ([ordered]@{
            status = "not_found"
            error = "Only GET /status is available in this bridge skeleton"
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
