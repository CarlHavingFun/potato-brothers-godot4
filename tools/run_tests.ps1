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

$runnerArguments = @(
	"--headless",
	"--path", $projectRoot,
	"-s", "res://addons/gdUnit4/bin/GdUnitCmdTool.gd",
	"--ignoreHeadlessMode",
	"-a", $TestPath,
	"-c",
	"-rd", $ReportDirectory
)

& $GodotBinary @runnerArguments
exit $LASTEXITCODE
