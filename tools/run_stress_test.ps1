[CmdletBinding()]
param(
	[Parameter(Mandatory = $true)]
	[string]$GodotBinary
)

$ErrorActionPreference = "Continue"
$projectRoot = Split-Path -Parent $PSScriptRoot
$output = @(& $GodotBinary --path $projectRoot --resolution 1920x1080 `
	res://tests/performance/combat_stress.tscn 2>&1)
$exitCode = $LASTEXITCODE
$output | ForEach-Object { Write-Output $_ }
$resultLine = @($output | ForEach-Object { $_.ToString() } | Where-Object { $_ -match "PERFORMANCE_RESULT" })
if ($exitCode -ne 0 -or $resultLine.Count -ne 1) {
	Write-Output "Combat stress gate failed (exit=$exitCode, result_lines=$($resultLine.Count))."
	exit 1
}
exit 0
