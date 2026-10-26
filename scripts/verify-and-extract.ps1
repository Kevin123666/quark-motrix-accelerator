[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$ArchiveDir,

    # Destination folder. If omitted with -Extract, defaults to E:\Games\<archive-folder-name>.
    [string]$Destination,

    [string]$SevenZip = 'E:\7-Zip\7z.exe',

    # Optional explicit first volume, e.g. .\My.Package.part01.rar
    [string]$FirstVolume,

    # Set to the expected number of volumes to fail early on missing parts.
    [ValidateRange(0, 100000)]
    [int]$ExpectedVolumes = 0,

    [switch]$VerifyOnly,
    [switch]$Extract,
    [switch]$SkipTest,
    [switch]$Force
)

$ErrorActionPreference = 'Stop'

function Resolve-FullPath {
    param([string]$Path)
    return [System.IO.Path]::GetFullPath($Path)
}

$archiveRoot = Resolve-FullPath $ArchiveDir
if (-not (Test-Path -LiteralPath $archiveRoot -PathType Container)) {
    throw "Archive directory not found: $archiveRoot"
}

if (-not (Test-Path -LiteralPath $SevenZip -PathType Leaf)) {
    throw "7-Zip not found: $SevenZip. Install 7-Zip or pass -SevenZip <path-to-7z.exe>."
}

$first = $null
if ($FirstVolume) {
    $candidate = if ([System.IO.Path]::IsPathRooted($FirstVolume)) {
        $FirstVolume
    }
    else {
        Join-Path $archiveRoot $FirstVolume
    }
    if (-not (Test-Path -LiteralPath $candidate -PathType Leaf)) {
        throw "First volume not found: $candidate"
    }
    $first = Get-Item -LiteralPath $candidate
}
else {
    $patterns = @('*.part01.rar', '*.part001.rar')
    foreach ($pattern in $patterns) {
        $matches = @(Get-ChildItem -LiteralPath $archiveRoot -Filter $pattern -File -ErrorAction SilentlyContinue | Sort-Object Name)
        if ($matches.Count -gt 1) {
            throw "Multiple first volumes matched '$pattern'. Pass -FirstVolume explicitly."
        }
        if ($matches.Count -eq 1) {
            $first = $matches[0]
            break
        }
    }

    if (-not $first) {
        $fallback = @(Get-ChildItem -LiteralPath $archiveRoot -Filter '*.rar' -File -ErrorAction SilentlyContinue | Sort-Object Name)
        if ($fallback.Count -eq 0) {
            throw "No .rar files found in $archiveRoot"
        }
        $first = $fallback[0]
    }
}

$partVolumes = @(
    Get-ChildItem -LiteralPath $archiveRoot -File -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -match '\.part\d+\.rar$' } |
        Sort-Object Name
)

$volumes = if ($partVolumes.Count -gt 0) {
    $partVolumes
}
else {
    @(Get-ChildItem -LiteralPath $archiveRoot -Filter '*.rar' -File -ErrorAction SilentlyContinue | Sort-Object Name)
}

$totalBytes = ($volumes | Measure-Object -Property Length -Sum).Sum
$lastVolume = $volumes | Select-Object -Last 1

Write-Host "Archive directory : $archiveRoot"
Write-Host "First volume      : $($first.Name)"
Write-Host "Volumes found     : $($volumes.Count)"
Write-Host ("Total size        : {0:N2} GB" -f ($totalBytes / 1GB))
if ($lastVolume) {
    Write-Host ("Last volume       : {0} ({1:N2} MB)" -f $lastVolume.Name, ($lastVolume.Length / 1MB))
}

if ($ExpectedVolumes -gt 0 -and $volumes.Count -ne $ExpectedVolumes) {
    throw "Expected $ExpectedVolumes volumes, found $($volumes.Count). Download may be incomplete."
}

if (-not $SkipTest) {
    Write-Host ''
    Write-Host 'Running 7-Zip integrity test ...'
    $testOutput = & $SevenZip t $first.FullName 2>&1
    $testCode = $LASTEXITCODE
    $testOutput | Select-Object -Last 20 | ForEach-Object { Write-Host $_ }

    if ($testCode -ne 0) {
        throw "7-Zip integrity test failed with exit code $testCode. Do not extract yet."
    }

    Write-Host 'Integrity test passed.'
}
else {
    Write-Warning 'Skipping integrity test because -SkipTest was specified.'
}

if ($VerifyOnly -or -not $Extract) {
    Write-Host ''
    Write-Host 'Verification complete. Pass -Extract to extract the archive.'
    return
}

if (-not $Destination) {
    $gamesRoot = if (Test-Path -LiteralPath 'E:\') { 'E:\Games' } else { Split-Path -Path $archiveRoot -Parent }
    $Destination = Join-Path $gamesRoot (Split-Path -Path $archiveRoot -Leaf)
}

$destinationPath = Resolve-FullPath $Destination
if (Test-Path -LiteralPath $destinationPath -PathType Container) {
    $existing = @(Get-ChildItem -LiteralPath $destinationPath -Force -ErrorAction SilentlyContinue)
    if ($existing.Count -gt 0 -and -not $Force) {
        throw "Destination is not empty: $destinationPath. Pass -Force to extract anyway."
    }
}
else {
    New-Item -ItemType Directory -Path $destinationPath -Force | Out-Null
}

Write-Host ''
Write-Host "Extracting to: $destinationPath"
$extractOutput = & $SevenZip x $first.FullName "-o$destinationPath" -y 2>&1
$extractCode = $LASTEXITCODE
$extractOutput | Select-Object -Last 30 | ForEach-Object { Write-Host $_ }

if ($extractCode -ne 0) {
    throw "7-Zip extraction failed with exit code $extractCode."
}

Write-Host ''
Write-Host 'Extraction complete.'
Write-Host "Destination: $destinationPath"
