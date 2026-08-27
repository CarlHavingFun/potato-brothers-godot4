[CmdletBinding()]
param(
	[Parameter(Mandatory = $true)]
	[string]$GodotBinary,

	[Parameter(Mandatory = $true)]
	[string]$ContractPath,

	[string]$EvidenceDirectory,

	[switch]$ExpectGateFailure
)

$ErrorActionPreference = "Stop"
$projectRoot = [System.IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot))
$resolvedContract = [System.IO.Path]::GetFullPath($ContractPath)
if (-not (Test-Path -LiteralPath $GodotBinary -PathType Leaf)) {
	throw "Godot binary does not exist: $GodotBinary"
}
if (-not (Test-Path -LiteralPath $resolvedContract -PathType Leaf)) {
	throw "Wave023 category contract does not exist: $resolvedContract"
}

$consoleBinary = Join-Path (Split-Path -Parent $GodotBinary) (
	([System.IO.Path]::GetFileNameWithoutExtension($GodotBinary)) + "_console.exe"
)
if (
	-not $GodotBinary.EndsWith("_console.exe", [System.StringComparison]::OrdinalIgnoreCase) `
	-and (Test-Path -LiteralPath $consoleBinary -PathType Leaf)
) {
	$GodotBinary = $consoleBinary
}

$tempRoot = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath())
$isolatedUserRoot = Join-Path $tempRoot (
	"gogobro-static-pixel-user-" + [System.Guid]::NewGuid().ToString("N")
)
$isolatedAppData = Join-Path $isolatedUserRoot "Roaming"
$isolatedLocalAppData = Join-Path $isolatedUserRoot "Local"
New-Item -ItemType Directory -Path $isolatedAppData, $isolatedLocalAppData -Force | Out-Null

if ([string]::IsNullOrWhiteSpace($EvidenceDirectory)) {
	$EvidenceDirectory = Join-Path $tempRoot (
		"gogobro-static-pixel-evidence-" + [System.Guid]::NewGuid().ToString("N")
	)
}
$resolvedEvidence = [System.IO.Path]::GetFullPath($EvidenceDirectory)
$projectPrefix = $projectRoot.TrimEnd([System.IO.Path]::DirectorySeparatorChar) + [System.IO.Path]::DirectorySeparatorChar
if (
	$resolvedEvidence.Equals($projectRoot, [System.StringComparison]::OrdinalIgnoreCase) `
	-or $resolvedEvidence.StartsWith($projectPrefix, [System.StringComparison]::OrdinalIgnoreCase)
) {
	throw "EvidenceDirectory must stay outside the repository: $resolvedEvidence"
}
if (Test-Path -LiteralPath $resolvedEvidence) {
	$existing = @(Get-ChildItem -LiteralPath $resolvedEvidence -Force -ErrorAction Stop)
	if ($existing.Count -gt 0) {
		throw "EvidenceDirectory must be new or empty: $resolvedEvidence"
	}
}
else {
	New-Item -ItemType Directory -Path $resolvedEvidence -Force | Out-Null
}

$arguments = @(
	"--path", $projectRoot,
	"--display-driver", "windows",
	"--rendering-driver", "opengl3",
	"--audio-driver", "Dummy",
	"--windowed",
	"--resolution", "1280x720",
	"--fixed-fps", "60",
	"--disable-vsync",
	"--script", "res://tests/integration/static_asset_pixel_sampling_v1_smoke.gd",
	"--",
	"--contract", $resolvedContract,
	"--output", "user://static-pixel-sampling-v1"
)

$previousAppData = $env:APPDATA
$previousLocalAppData = $env:LOCALAPPDATA
$previousErrorActionPreference = $ErrorActionPreference
$godotOutput = @()
$exitCode = 1
$sourceEvidence = Join-Path $isolatedAppData "GOGOBRO\static-pixel-sampling-v1"
try {
	$env:APPDATA = $isolatedAppData
	$env:LOCALAPPDATA = $isolatedLocalAppData
	$ErrorActionPreference = "Continue"
	$godotOutput = @(& $GodotBinary @arguments 2>&1)
	$exitCode = $LASTEXITCODE
	$ErrorActionPreference = "Stop"

	if (Test-Path -LiteralPath $sourceEvidence -PathType Container) {
		foreach ($entry in Get-ChildItem -LiteralPath $sourceEvidence -Force) {
			Copy-Item -LiteralPath $entry.FullName -Destination $resolvedEvidence -Recurse -Force
		}
	}
}
finally {
	$ErrorActionPreference = $previousErrorActionPreference
	$env:APPDATA = $previousAppData
	$env:LOCALAPPDATA = $previousLocalAppData
	$resolvedIsolatedRoot = [System.IO.Path]::GetFullPath($isolatedUserRoot)
	$tempPrefix = $tempRoot.TrimEnd([System.IO.Path]::DirectorySeparatorChar) + [System.IO.Path]::DirectorySeparatorChar
	if (
		$resolvedIsolatedRoot.StartsWith($tempPrefix, [System.StringComparison]::OrdinalIgnoreCase) `
		-and $resolvedIsolatedRoot -ne $tempRoot
	) {
		Remove-Item -LiteralPath $resolvedIsolatedRoot -Recurse -Force -ErrorAction SilentlyContinue
	}
}

$godotOutput | ForEach-Object { Write-Output $_ }
Write-Output "STATIC_PIXEL_EVIDENCE_DIRECTORY=$resolvedEvidence"
Write-Output "STATIC_PIXEL_GODOT_EXIT=$exitCode"

$reportPath = Join-Path $resolvedEvidence "report.json"
if ($ExpectGateFailure) {
	if (-not (Test-Path -LiteralPath $reportPath -PathType Leaf)) {
		throw "Expected gate failure did not produce report.json"
	}
	$report = Get-Content -Raw -LiteralPath $reportPath | ConvertFrom-Json
	$failureCodes = @($report.failure_codes)
	if ($exitCode -eq 0 -or [bool]$report.ok) {
		throw "Expected the current non-integer project scale to fail, but the gate passed"
	}
	if ($failureCodes -notcontains "non_integer_global_scale") {
		throw "Gate failed, but it did not prove the non-integer global-scale detector"
	}
	if ($failureCodes.Count -ne 1) {
		throw "Expected only non_integer_global_scale, but found: $($failureCodes -join ',')"
	}
	Write-Output "EXPECTED_STATIC_PIXEL_GATE_FAILURE_CONFIRMED=non_integer_global_scale"
	exit 0
}

if ($exitCode -ne 0) {
	exit $exitCode
}
if (-not (Test-Path -LiteralPath $reportPath -PathType Leaf)) {
	throw "Static pixel sampling process exited successfully without report.json"
}
$successReport = Get-Content -Raw -LiteralPath $reportPath | ConvertFrom-Json
if (-not [bool]$successReport.ok) {
	throw "Static pixel sampling process exited successfully but report.ok is false"
}
exit 0
