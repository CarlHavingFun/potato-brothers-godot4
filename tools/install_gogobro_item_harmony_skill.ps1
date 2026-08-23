[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$SourceRoot,

    [Parameter(Mandatory = $true)]
    [string]$TargetRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Install-GogobroItemHarmonySkill {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$SourceRoot,

        [Parameter(Mandatory = $true)]
        [string]$TargetRoot
    )

    $resolvedSource = (Resolve-Path -LiteralPath $SourceRoot -ErrorAction Stop).Path
    if (-not (Test-Path -LiteralPath $resolvedSource -PathType Container)) {
        throw "SourceRoot must be a directory: $resolvedSource"
    }

    if (-not (Test-Path -LiteralPath $TargetRoot)) {
        New-Item -ItemType Directory -Path $TargetRoot -Force -ErrorAction Stop | Out-Null
    }
    $resolvedTarget = (Resolve-Path -LiteralPath $TargetRoot -ErrorAction Stop).Path
    if (-not (Test-Path -LiteralPath $resolvedTarget -PathType Container)) {
        throw "TargetRoot must be a directory: $resolvedTarget"
    }
    if ([string]::Equals(
        $resolvedSource.TrimEnd('\', '/'),
        $resolvedTarget.TrimEnd('\', '/'),
        [System.StringComparison]::OrdinalIgnoreCase
    )) {
        throw 'SourceRoot and TargetRoot must differ.'
    }

    $manifest = @(
        'SKILL.md',
        'agents\openai.yaml',
        'references\slot-profiles.md',
        'scripts\check_item_harmony.py'
    )

    foreach ($relativePath in $manifest) {
        $sourcePath = Join-Path -Path $resolvedSource -ChildPath $relativePath
        if (-not (Test-Path -LiteralPath $sourcePath -PathType Leaf)) {
            throw "Manifest source file is missing: $sourcePath"
        }
    }

    foreach ($relativePath in $manifest) {
        $sourcePath = Join-Path -Path $resolvedSource -ChildPath $relativePath
        $targetPath = Join-Path -Path $resolvedTarget -ChildPath $relativePath
        $targetParent = Split-Path -Parent $targetPath
        if (-not (Test-Path -LiteralPath $targetParent)) {
            New-Item -ItemType Directory -Path $targetParent -Force -ErrorAction Stop | Out-Null
        }
        Copy-Item -LiteralPath $sourcePath -Destination $targetPath -Force -ErrorAction Stop
    }

    foreach ($relativePath in $manifest) {
        $sourcePath = Join-Path -Path $resolvedSource -ChildPath $relativePath
        $targetPath = Join-Path -Path $resolvedTarget -ChildPath $relativePath
        $sourceHash = (Get-FileHash -LiteralPath $sourcePath -Algorithm SHA256).Hash
        $targetHash = (Get-FileHash -LiteralPath $targetPath -Algorithm SHA256).Hash
        if (-not [string]::Equals(
            $sourceHash,
            $targetHash,
            [System.StringComparison]::OrdinalIgnoreCase
        )) {
            throw "SHA-256 mismatch after copy: $relativePath"
        }
        $displayPath = $relativePath.Replace('\', '/')
        Write-Output "Verified ${displayPath} SHA-256=$($targetHash.ToLowerInvariant())"
    }

    Write-Output "Installed $($manifest.Count) manifest files to $resolvedTarget"
}

Install-GogobroItemHarmonySkill -SourceRoot $SourceRoot -TargetRoot $TargetRoot
