[CmdletBinding()]
param(
    [string]$RpcUrl = 'http://127.0.0.1:16800/jsonrpc',
    [string]$Secret = $env:MOTRIX_RPC_SECRET,

    [ValidateRange(1, 3600)]
    [int]$IntervalSec = 5,

    # 0 means keep monitoring until active + waiting reaches zero.
    [ValidateRange(0, 1440)]
    [int]$MaxMinutes = 0,

    [switch]$Once,
    [switch]$ShowOptions,
    [switch]$ShowTasks,

    # Total number of tasks in the batch, used for "completed=N/total".
    [ValidateRange(0, 100000)]
    [int]$TotalTasks = 0,

    # Used when a waiting task has not reported totalLength yet.
    [ValidateRange(1, 1048576)]
    [int]$AssumeWaitingMB = 1000
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

if ($ShowOptions) {
    $options = Invoke-Aria2Rpc -Method 'aria2.getGlobalOption' -Params @($token)
    Write-Host 'Global aria2 options:'
    foreach ($key in @('split', 'max-connection-per-server', 'max-concurrent-downloads', 'min-split-size', 'file-allocation', 'disk-cache')) {
        Write-Host ("  {0} = {1}" -f $key, $options.$key)
    }
    return
}

$started = Get-Date
$deadline = if ($MaxMinutes -gt 0) { $started.AddMinutes($MaxMinutes) } else { $null }

while ($true) {
    $stat = Invoke-Aria2Rpc -Method 'aria2.getGlobalStat' -Params @($token)
    $active = @(Invoke-Aria2Rpc -Method 'aria2.tellActive' -Params @($token))
    $waiting = @(Invoke-Aria2Rpc -Method 'aria2.tellWaiting' -Params @($token, 0, 1000))
    $stopped = @(Invoke-Aria2Rpc -Method 'aria2.tellStopped' -Params @($token, 0, 1000))

    $connections = 0
    $remaining = [int64]0

    foreach ($task in $active) {
        $connections += [int64]$task.connections
        $remaining += ([int64]$task.totalLength - [int64]$task.completedLength)
    }

    foreach ($task in $waiting) {
        if ([int64]$task.totalLength -gt 0) {
            $remaining += ([int64]$task.totalLength - [int64]$task.completedLength)
        }
        else {
            $remaining += ([int64]$AssumeWaitingMB * 1MB)
        }
    }

    $speed = [int64]$stat.downloadSpeed
    $etaMin = if ($speed -gt 0) { [math]::Round($remaining / $speed / 60, 1) } else { $null }

    $activeCount = [int]$stat.numActive
    $waitingCount = [int]$stat.numWaiting
    $errors = @($stopped | Where-Object { $_.errorCode })

    $completedText = ''
    if ($TotalTasks -gt 0) {
        $completed = $TotalTasks - $activeCount - $waitingCount - $errors.Count
        if ($completed -lt 0) { $completed = 0 }
        $completedText = " completed=$completed/$TotalTasks"
    }

    $line = "[{0}] speed={1:N2} MB/s active={2} waiting={3}{4} conn={5} remaining={6:N1} GB" -f `
        (Get-Date -Format 'HH:mm:ss'), ($speed / 1MB), $activeCount, $waitingCount, `
        $completedText, $connections, ($remaining / 1GB)

    if ($null -ne $etaMin) {
        $line += " eta=$etaMin min"
    }

    Write-Host $line

    if ($ShowTasks) {
        foreach ($task in $active) {
            $files = @($task.files)
            $name = if ($files.Count -gt 0 -and $files[0].path) { Split-Path -Path $files[0].path -Leaf } else { $task.gid }
            $pct = if ([int64]$task.totalLength -gt 0) {
                [math]::Round(([double]$task.completedLength / [double]$task.totalLength) * 100, 1)
            }
            else { 0 }
            Write-Host ("    {0}  {1:N2} MB/s  conn={2}  {3}%" -f `
                $name, ([double]$task.downloadSpeed / 1MB), $task.connections, $pct)
        }
    }

    if ($errors.Count -gt 0) {
        Write-Host "  Errors: $($errors.Count)"
        $errors | Select-Object -First 5 | ForEach-Object {
            Write-Host ("    {0} code={1} {2}" -f $_.gid, $_.errorCode, $_.errorMessage)
        }
    }

    if ($activeCount -eq 0 -and $waitingCount -eq 0) {
        Write-Host 'All active and waiting tasks are finished.'
        break
    }

    if ($Once) { break }
    if ($null -ne $deadline -and (Get-Date) -ge $deadline) {
        Write-Host "Monitoring window ended after $MaxMinutes minute(s)."
        break
    }

    Start-Sleep -Seconds $IntervalSec
}
