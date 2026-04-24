[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$File,

    [string]$ManifestPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Resolve-ManifestPath {
    param(
        [string]$TargetFile,
        [string]$ProvidedManifestPath
    )

    if ($ProvidedManifestPath) {
        return (Resolve-Path -LiteralPath $ProvidedManifestPath).ProviderPath
    }

    $fileDir = Split-Path -Parent $TargetFile
    $candidates = @(
        (Join-Path $fileDir 'checksums.sha256'),
        (Join-Path $PSScriptRoot 'checksums.sha256'),
        (Join-Path (Get-Location).Path 'checksums.sha256')
    )

    foreach ($candidate in $candidates) {
        if ($candidate -and (Test-Path -LiteralPath $candidate)) {
            return [System.IO.Path]::GetFullPath($candidate)
        }
    }

    throw 'Unable to locate checksums.sha256. Use -ManifestPath to specify it explicitly.'
}

$resolvedFile = (Resolve-Path -LiteralPath $File).ProviderPath
$resolvedManifest = Resolve-ManifestPath -TargetFile $resolvedFile -ProvidedManifestPath $ManifestPath
$targetName = Split-Path -Leaf $resolvedFile

$entries = foreach ($line in Get-Content -LiteralPath $resolvedManifest) {
    if ([string]::IsNullOrWhiteSpace($line)) {
        continue
    }

    if ($line.TrimStart().StartsWith('#')) {
        continue
    }

    if ($line -notmatch '^(?<hash>[A-Fa-f0-9]{64}) \*(?<name>.+)$') {
        throw "Unsupported manifest line format: $line"
    }

    [pscustomobject]@{
        Name = $matches.name
        Hash = $matches.hash.ToLowerInvariant()
    }
}

$entry = $entries | Where-Object { $_.Name -eq $targetName } | Select-Object -First 1

if (-not $entry) {
    $availableNames = ($entries | Select-Object -ExpandProperty Name) -join ', '
    throw "No SHA256 entry found for $targetName in $resolvedManifest. Available entries: $availableNames"
}

$actualHash = (Get-FileHash -LiteralPath $resolvedFile -Algorithm SHA256).Hash.ToLowerInvariant()

if ($actualHash -ne $entry.Hash) {
    throw ("SHA256 mismatch for {0}. Expected={1} Actual={2}" -f $targetName, $entry.Hash, $actualHash)
}

Write-Host ("SHA256 OK for {0}" -f $targetName)
Write-Host ("Manifest: {0}" -f $resolvedManifest)
Write-Host ("SHA256 : {0}" -f $actualHash)

[pscustomobject]@{
    File      = $resolvedFile
    Manifest  = $resolvedManifest
    Name      = $targetName
    Sha256    = $actualHash
    Verified  = $true
}

