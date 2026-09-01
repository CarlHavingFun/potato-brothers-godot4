[CmdletBinding()]
param(
	[string]$GodotBinary = $env:GODOT_BIN,
	[string]$TestPath = "res://tests",
	[string]$ReportDirectory = "res://reports/gdunit"
)

$ErrorActionPreference = "Stop"
$projectRoot = Split-Path -Parent $PSScriptRoot

if ([string]::IsNullOrWhiteSpace($GodotBinary)) {
	$godotCommand = Get-Command godot -ErrorAction SilentlyContinue
	if ($null -ne $godotCommand) {
		$GodotBinary = $godotCommand.Source
	}
}

if ([string]::IsNullOrWhiteSpace($GodotBinary) -or -not (Test-Path -LiteralPath $GodotBinary)) {
	throw "Godot 4.7.1 was not found. Pass -GodotBinary or set GODOT_BIN."
}
$consoleBinary = Join-Path (Split-Path -Parent $GodotBinary) (([System.IO.Path]::GetFileNameWithoutExtension($GodotBinary)) + "_console.exe")
if (-not $GodotBinary.EndsWith("_console.exe", [System.StringComparison]::OrdinalIgnoreCase) -and (Test-Path -LiteralPath $consoleBinary)) {
	$GodotBinary = $consoleBinary
}

$runnerArguments = @(
	"--headless",
	"--path", $projectRoot,
	"-s", "res://addons/gdUnit4/bin/GdUnitCmdTool.gd",
	"--ignoreHeadlessMode",
	"-a", $TestPath,
	"-c",
	"-rd", $ReportDirectory
)

$testUserRoot = Join-Path ([System.IO.Path]::GetTempPath()) (
	"lets-gooooo-gdunit-" + [System.Guid]::NewGuid().ToString("N")
)
$testAppData = Join-Path $testUserRoot "Roaming"
$testLocalAppData = Join-Path $testUserRoot "Local"
$testTemp = Join-Path $testUserRoot "Temp"
$testExpectedUserData = Join-Path $testAppData "GOGOBRO"
New-Item -ItemType Directory -Path $testAppData, $testLocalAppData, $testTemp -Force | Out-Null
$previousAppData = $env:APPDATA
$previousLocalAppData = $env:LOCALAPPDATA
$previousTemp = $env:TEMP
$previousTmp = $env:TMP
$previousExpectedUserData = $env:GOGOBRO_TEST_EXPECTED_USER_DATA_DIR
$previousExpectedAppData = $env:GOGOBRO_TEST_EXPECTED_APPDATA
$previousExpectedLocalAppData = $env:GOGOBRO_TEST_EXPECTED_LOCALAPPDATA
$previousErrorActionPreference = $ErrorActionPreference
try {
	# GdUnit exercises real save and settings code. Never let those tests touch a
	# player's live %APPDATA% profile, even when a test forgets to inject a fake
	# SaveProvider.
	$env:APPDATA = $testAppData
	$env:LOCALAPPDATA = $testLocalAppData
	$env:TEMP = $testTemp
	$env:TMP = $testTemp
	$env:GOGOBRO_TEST_EXPECTED_USER_DATA_DIR = $testExpectedUserData
	$env:GOGOBRO_TEST_EXPECTED_APPDATA = $testAppData
	$env:GOGOBRO_TEST_EXPECTED_LOCALAPPDATA = $testLocalAppData
	$ErrorActionPreference = "Continue"
	$output = @(& $GodotBinary @runnerArguments 2>&1)
	$exitCode = $LASTEXITCODE
}
finally {
	$ErrorActionPreference = $previousErrorActionPreference
	$env:APPDATA = $previousAppData
	$env:LOCALAPPDATA = $previousLocalAppData
	$env:TEMP = $previousTemp
	$env:TMP = $previousTmp
	$env:GOGOBRO_TEST_EXPECTED_USER_DATA_DIR = $previousExpectedUserData
	$env:GOGOBRO_TEST_EXPECTED_APPDATA = $previousExpectedAppData
	$env:GOGOBRO_TEST_EXPECTED_LOCALAPPDATA = $previousExpectedLocalAppData
	$resolvedTemp = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath())
	$resolvedTestRoot = [System.IO.Path]::GetFullPath($testUserRoot)
	if ($resolvedTestRoot.StartsWith($resolvedTemp, [System.StringComparison]::OrdinalIgnoreCase)) {
		Remove-Item -LiteralPath $resolvedTestRoot -Recurse -Force -ErrorAction SilentlyContinue
	}
}
$output | ForEach-Object { Write-Output $_ }

$leakPattern = "Leaked instance:|ObjectDB instances were leaked|resources still in use at exit"
$leakLines = @($output | ForEach-Object { $_.ToString() } | Where-Object { $_ -match $leakPattern })
if ($exitCode -eq 0 -and $leakLines.Count -gt 0) {
	Write-Output "GdUnit completed but Godot reported leaked objects/resources:"
	$leakLines | ForEach-Object { Write-Output $_ }
	exit 1
}

$discoveryFailurePattern = "Script errors were detected during test discovery!|No test cases found, abort test run!"
$discoveryFailureLines = @(
	$output | ForEach-Object { $_.ToString() } | Where-Object { $_ -match $discoveryFailurePattern }
)
if ($exitCode -eq 0 -and $discoveryFailureLines.Count -gt 0) {
	Write-Output "GdUnit did not execute the requested test cases:"
	$discoveryFailureLines | ForEach-Object { Write-Output $_ }
	exit 1
}

exit $exitCode
