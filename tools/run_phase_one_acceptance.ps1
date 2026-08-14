[CmdletBinding()]
param(
	[string]$GodotBinary = $env:GODOT_BIN,
	[switch]$SkipStress
)

$ErrorActionPreference = "Stop"
$projectRoot = Split-Path -Parent $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($GodotBinary) -or -not (Test-Path -LiteralPath $GodotBinary)) {
	throw "Godot 4.7.1 was not found. Pass -GodotBinary or set GODOT_BIN."
}

& $GodotBinary --headless --editor --path $projectRoot --import --quit
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
& "$PSScriptRoot\build_content_pack.ps1" -GodotBinary $GodotBinary
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
& "$PSScriptRoot\run_tests.ps1" -GodotBinary $GodotBinary
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
& "$PSScriptRoot\check_clean_exit.ps1" -GodotBinary $GodotBinary -Mode Editor -Runs 2
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
& "$PSScriptRoot\check_clean_exit.ps1" -GodotBinary $GodotBinary -Mode Game -Runs 2
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
if (-not $SkipStress) {
	& "$PSScriptRoot\run_stress_test.ps1" -GodotBinary $GodotBinary
	if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
}
Write-Output "Phase-one acceptance gates passed."
