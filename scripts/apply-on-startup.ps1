[CmdletBinding()]
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

    [ValidateRange(5, 600)]
    [int]$WaitSeconds = 90
)

$ErrorActionPreference = 'Stop'

$tuneScript = Join-Path $PSScriptRoot 'tune-aria2.ps1'
if (-not (Test-Path -LiteralPath $tuneScript -PathType Leaf)) {
    throw "tune-aria2.ps1 not found next to this script: $tuneScript"
}

& $tuneScript `
    -RpcUrl $RpcUrl `
    -Secret $Secret `
    -Split $Split `
    -MaxConnectionPerServer $MaxConnectionPerServer `
    -MaxConcurrentDownloads $MaxConcurrentDownloads `
    -MinSplitSize $MinSplitSize `
    -GlobalOnly `
    -WaitForRpc `
    -WaitSeconds $WaitSeconds

exit $LASTEXITCODE
