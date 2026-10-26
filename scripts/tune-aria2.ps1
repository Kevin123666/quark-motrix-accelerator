[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [string]$RpcUrl = 'http://127.0.0.1:16800/jsonrpc',
    [string]$Secret = $env:MOTRIX_RPC_SECRET,

    [ValidateRange(1, 512)]
    [int]$Split = 64,

    [ValidateRange(1, 512)]
    [int]$MaxConnectionPerServer = 64,

    [ValidateRange(1, 128)]
    [int]$MaxConcurrentDownloads = 16,

    [ValidateRange(1048576, 1073741824)]
    [int]$MinSplitSize = 4194304,

    # Only change global defaults; useful after a Motrix restart.
    [switch]$GlobalOnly,

    # Wait for Motrix/aria2 RPC to become available.
    [switch]$WaitForRpc,

    [ValidateRange(5, 600)]
    [int]$WaitSeconds = 60
)

$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($Secret)) {
    throw "RPC secret is required. Set `$env:MOTRIX_RPC_SECRET or pass -Secret '<secret>'."
}

$token = "token:$Secret"

function Invoke-Aria2Rpc {
    param(
        [Parameter(Mandatory = $true)][string]$Method,
        [Parameter(Mandatory = $true)][object[]]$Params
    )

    $payload = @{
        jsonrpc = '2.0'
        id      = [guid]::NewGuid().ToString()
        method  = $Method
        params  = $Params
    } | ConvertTo-Json -Compress -Depth 10

    try {
        $response = Invoke-RestMethod -Uri $RpcUrl -Method Post `
            -ContentType 'application/json' -Body $payload -TimeoutSec 10
    }
    catch {
        throw "RPC request failed ($Method): $($_.Exception.Message)"
    }

    if ($response.error) {
        throw "aria2 RPC error ($Method): $($response.error.message)"
    }

    return $response.result
}

function Format-Options {
    param($Options)

    if (-not $Options) { return '<none>' }
    return ("split={0}; max-connection-per-server={1}; max-concurrent-downloads={2}; min-split-size={3}" -f `
        $Options.split, $Options.'max-connection-per-server', `
        $Options.'max-concurrent-downloads', $Options.'min-split-size')
}

if ($WaitForRpc) {
    Write-Host "Waiting for aria2 RPC at $RpcUrl ..."
    $deadline = (Get-Date).AddSeconds($WaitSeconds)
    $ready = $false
    while ((Get-Date) -lt $deadline) {
        try {
            Invoke-Aria2Rpc -Method 'aria2.getGlobalStat' -Params @($token) | Out-Null
            $ready = $true
            break
        }
        catch {
            Start-Sleep -Seconds 2
        }
    }
    if (-not $ready) {
        throw "aria2 RPC did not become ready within $WaitSeconds seconds."
    }
}

$before = Invoke-Aria2Rpc -Method 'aria2.getGlobalOption' -Params @($token)
Write-Host "Before: $(Format-Options $before)"

$active = @()
$waiting = @()

if (-not $GlobalOnly) {
    $active = @(Invoke-Aria2Rpc -Method 'aria2.tellActive' -Params @($token))
    $waiting = @(Invoke-Aria2Rpc -Method 'aria2.tellWaiting' -Params @($token, 0, 1000))
}

$pausedGids = @(
    $waiting |
        Where-Object { $_.status -eq 'paused' } |
        ForEach-Object { $_.gid }
)

if (-not $GlobalOnly -and $active.Count -gt 0) {
    if ($PSCmdlet.ShouldProcess('aria2', "Pause all downloads ($($active.Count) active)")) {
        Invoke-Aria2Rpc -Method 'aria2.pauseAll' -Params @($token) | Out-Null
        Start-Sleep -Milliseconds 800
    }
}

$tasks = @()
if (-not $GlobalOnly) {
    $activeAfter = @(Invoke-Aria2Rpc -Method 'aria2.tellActive' -Params @($token))
    $waitingAfter = @(Invoke-Aria2Rpc -Method 'aria2.tellWaiting' -Params @($token, 0, 1000))
    $tasks = @($activeAfter + $waitingAfter)
}

Write-Host "Applying per-task options to $($tasks.Count) task(s) ..."
$failures = 0
foreach ($task in $tasks) {
    $gid = $task.gid
    $fileList = @($task.files)
    $label = if ($fileList.Count -gt 0 -and $fileList[0].path) {
        Split-Path -Path $fileList[0].path -Leaf
    }
    else {
        $gid
    }

    if ($PSCmdlet.ShouldProcess($label, "Set split=$Split, max-connection-per-server=$MaxConnectionPerServer, min-split-size=$MinSplitSize")) {
        try {
            Invoke-Aria2Rpc -Method 'aria2.changeOption' -Params @(
                $token,
                $gid,
                @{
                    split                      = "$Split"
                    'max-connection-per-server' = "$MaxConnectionPerServer"
                    'min-split-size'           = "$MinSplitSize"
                }
            ) | Out-Null
        }
        catch {
            $failures++
            Write-Warning "Failed to update $label ($gid): $($_.Exception.Message)"
        }
    }
}
if ($failures -gt 0) {
    Write-Warning "$failures task(s) could not be updated. They may have completed or been removed."
}

$globalOptions = @{
    split                       = "$Split"
    'max-connection-per-server' = "$MaxConnectionPerServer"
    'max-concurrent-downloads'  = "$MaxConcurrentDownloads"
    'min-split-size'            = "$MinSplitSize"
}

if ($PSCmdlet.ShouldProcess('aria2', "Set global options: $(Format-Options $globalOptions)")) {
    Invoke-Aria2Rpc -Method 'aria2.changeGlobalOption' -Params @($token, $globalOptions) | Out-Null
}

if (-not $GlobalOnly -and $active.Count -gt 0) {
    if ($PSCmdlet.ShouldProcess('aria2', 'Unpause all downloads')) {
        Invoke-Aria2Rpc -Method 'aria2.unpauseAll' -Params @($token) | Out-Null
        Start-Sleep -Milliseconds 800
    }

    foreach ($gid in $pausedGids) {
        if ($PSCmdlet.ShouldProcess($gid, 'Restore original paused state')) {
            try {
                Invoke-Aria2Rpc -Method 'aria2.pause' -Params @($token, $gid) | Out-Null
            }
            catch {
                Write-Warning "Could not restore paused state for $gid : $($_.Exception.Message)"
            }
        }
    }
}

$after = Invoke-Aria2Rpc -Method 'aria2.getGlobalOption' -Params @($token)
$stat = Invoke-Aria2Rpc -Method 'aria2.getGlobalStat' -Params @($token)

Write-Host "After:  $(Format-Options $after)"
Write-Host ("State:  active={0}; waiting={1}; speed={2:N2} MB/s" -f `
    $stat.numActive, $stat.numWaiting, ([double]$stat.downloadSpeed / 1MB))
Write-Host 'Done.'
