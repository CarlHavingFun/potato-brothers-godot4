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

$previousErrorActionPreference = $ErrorActionPreference
$ErrorActionPreference = "Continue"
$output = @(& $GodotBinary @runnerArguments 2>&1)
$exitCode = $LASTEXITCODE
$ErrorActionPreference = $previousErrorActionPreference
$output | ForEach-Object { Write-Output $_ }

$leakPattern = "Leaked instance:|ObjectDB instances were leaked|resources still in use at exit"
$leakLines = @($output | ForEach-Object { $_.ToString() } | Where-Object { $_ -match $leakPattern })
if ($exitCode -eq 0 -and $leakLines.Count -gt 0) {
	Write-Output "GdUnit completed but Godot reported leaked objects/resources:"
	$leakLines | ForEach-Object { Write-Output $_ }
	exit 1
}

exit $exitCode
