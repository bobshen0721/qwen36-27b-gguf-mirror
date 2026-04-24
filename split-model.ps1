[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$InputFile,

    [ValidateRange(1, 2000)]
    [int]$PartSizeMiB = 1900,

    [string]$OutputDir,

    [string]$ManifestPath,

    [switch]$UpdateManifest,

    [switch]$Force
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function ConvertTo-HexHash {
    param([byte[]]$Bytes)
    return (($Bytes | ForEach-Object { $_.ToString('x2') }) -join '')
}

$resolvedInput = (Resolve-Path -LiteralPath $InputFile).ProviderPath
$inputItem = Get-Item -LiteralPath $resolvedInput

if (-not $OutputDir) {
    $OutputDir = Split-Path -Parent $resolvedInput
}

$outputDirPath = [System.IO.Path]::GetFullPath($OutputDir)
[System.IO.Directory]::CreateDirectory($outputDirPath) | Out-Null

if ($UpdateManifest -and -not $ManifestPath) {
    $ManifestPath = Join-Path $outputDirPath 'checksums.sha256'
}

if ($ManifestPath) {
    $ManifestPath = [System.IO.Path]::GetFullPath($ManifestPath)
}

$baseName = $inputItem.Name
$partSizeBytes = [int64]$PartSizeMiB * 1MB
$bufferSize = [Math]::Min([int64](16MB), $partSizeBytes)
$buffer = New-Object byte[] $bufferSize
$parts = New-Object 'System.Collections.Generic.List[object]'

$sourceStream = $null
$sourceHash = $null

try {
    $sourceStream = [System.IO.File]::Open($resolvedInput, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::Read)
    $sourceHash = [System.Security.Cryptography.SHA256]::Create()
    $totalBytes = $sourceStream.Length
    $bytesProcessed = 0L
    $partNumber = 1

    while ($bytesProcessed -lt $totalBytes) {
        $partName = '{0}.{1:000}' -f $baseName, $partNumber
        $partPath = Join-Path $outputDirPath $partName
        $partBytesTarget = [Math]::Min($partSizeBytes, $totalBytes - $bytesProcessed)

        if ((Test-Path -LiteralPath $partPath) -and -not $Force) {
            throw "Part already exists: $partPath. Use -Force to overwrite existing parts."
        }

        $partStream = $null
        $partHash = $null
        $partBytesWritten = 0L

        try {
            $partStream = [System.IO.File]::Open($partPath, [System.IO.FileMode]::Create, [System.IO.FileAccess]::Write, [System.IO.FileShare]::None)
            $partHash = [System.Security.Cryptography.SHA256]::Create()

            while ($partBytesWritten -lt $partBytesTarget) {
                $remaining = $partBytesTarget - $partBytesWritten
                $toRead = [int][Math]::Min($buffer.Length, $remaining)
                $bytesRead = $sourceStream.Read($buffer, 0, $toRead)

                if ($bytesRead -le 0) {
                    throw "Unexpected end of file while creating $partName."
                }

                $partStream.Write($buffer, 0, $bytesRead)
                [void]$sourceHash.TransformBlock($buffer, 0, $bytesRead, $buffer, 0)
                [void]$partHash.TransformBlock($buffer, 0, $bytesRead, $buffer, 0)

                $partBytesWritten += $bytesRead
                $bytesProcessed += $bytesRead

                Write-Progress -Id 1 -Activity 'Splitting GGUF file' -Status "Writing $partName" -PercentComplete (($bytesProcessed / $totalBytes) * 100)
            }

            $partStream.Flush()
            [void]$partHash.TransformFinalBlock([byte[]]::new(0), 0, 0)
            $partHex = ConvertTo-HexHash -Bytes $partHash.Hash

            $parts.Add([pscustomobject]@{
                Name   = $partName
                Path   = $partPath
                Size   = $partBytesWritten
                Sha256 = $partHex
            })

            Write-Host ("Created {0} ({1:N0} bytes) SHA256={2}" -f $partName, $partBytesWritten, $partHex)
        }
        finally {
            if ($partHash) {
                $partHash.Dispose()
            }

            if ($partStream) {
                $partStream.Dispose()
            }
        }

        $partNumber++
    }

    [void]$sourceHash.TransformFinalBlock([byte[]]::new(0), 0, 0)
    $sourceHex = ConvertTo-HexHash -Bytes $sourceHash.Hash
}
finally {
    Write-Progress -Id 1 -Activity 'Splitting GGUF file' -Completed

    if ($sourceHash) {
        $sourceHash.Dispose()
    }

    if ($sourceStream) {
        $sourceStream.Dispose()
    }
}

if ($ManifestPath) {
    $manifestLines = New-Object System.Collections.Generic.List[string]
    $manifestLines.Add('# SHA256 manifest for Qwen3.6-27B-UD-IQ2_XXS mirror assets')
    $manifestLines.Add(('# Generated {0}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss K')))
    $manifestLines.Add(('{0} *{1}' -f $sourceHex, $baseName))

    foreach ($part in $parts) {
        $manifestLines.Add(('{0} *{1}' -f $part.Sha256, $part.Name))
    }

    Set-Content -LiteralPath $ManifestPath -Value $manifestLines -Encoding ascii
    Write-Host "Wrote manifest: $ManifestPath"
}

Write-Host ('Source SHA256={0}' -f $sourceHex)

[pscustomobject]@{
    InputFile     = $resolvedInput
    PartSizeMiB   = $PartSizeMiB
    OutputDir     = $outputDirPath
    PartCount     = $parts.Count
    SourceSha256  = $sourceHex
    ManifestPath  = $ManifestPath
    PartFiles     = $parts
}

